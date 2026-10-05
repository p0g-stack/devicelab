#!/usr/bin/env bash
# Back and the way out of a pixel plugin, with the lifecycle probe
# (aera/apps/lifecycle_probe, whose PopScope keeps Back and logs it):
#   short Back (Remote key)            -> the app gets it, stays in front
#   gesture navigation on:  swipe up from the bottom edge -> AERA Home,
#                           app paused in Recents
#   gesture navigation off: AERA Remote's Home key (R0003) -> the same
# reopening keeps the count and the process. Runs with Gesture navigation on,
# then off (AERA restarted with aera_recents_enabled=0), then restores it.
# (A held Back that also left the app, flutter-aera 0024, was dropped
# 2026-10-05: swipe-up is the way out.)
# Usage: aera-back-check.sh PKG.aerap  ->  $LAB_OUT/aera-back/
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-back; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
here=$(cd "$(dirname "$0")/.." && pwd)
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[back] $*" | tee -a "$OUT/log.txt"; }

shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 1; a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && log "frame $1.png" || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
remote() {
  local r; r=$(rpc '{"v":1,"id":"back-mirror","op":"mirror","args":{"action":"start","port":8088}}')
  RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
  [ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; return 1; }
  a forward tcp:18088 tcp:8088 >/dev/null; REMOTE=http://127.0.0.1:18088; sleep 2
}
# D9: minuitwrp zeroes a contact's position on release and the kernel drops
# a coordinate equal to the slot's last one, so a press at the same x (or y)
# as the previous contact reaches AERA at 0. Fixed by flutter-aera 0025; with
# PRESS_SHIFT=1 every press shifts by 1 px from the last one (fallback for
# images without 0025).
J=0
touch_() { [ "$1" = down ] && [ "${PRESS_SHIFT:-0}" = 1 ] && J=$((1 - J)); curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" \
  -d "{\"action\":\"$1\",\"x\":$(( $2 + J )),\"y\":$(( $3 + J ))}" "$REMOTE/api/input/touch" >/dev/null; }
tap() { touch_ down "$1" "$2"; sleep 0.1; touch_ up "$1" "$2"; log "tap $1,$2"; }
# What reached AERA (its "touch released" debug lines) and the app (POINTER lines).
touches() { a shell 'logcat -d 2>/dev/null | grep -E "touch released|Back gesture|edge" | tail -40' | tr -d '\r' > "$OUT/touches-aera.log"; }
key() { log "key $1: $(curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" -d "{\"key\":\"$1\"}" "$REMOTE/api/input/key")"; }
# Swipe up from the bottom edge and let go: AERA Home (no hold, so not Recents).
swipe_up() {
  local i; touch_ down 360 1340
  for i in 1 2 3 4 5 6; do touch_ move 360 $(( 1340 - 300 * i / 6 )); sleep 0.03; done
  touch_ up 360 1040; log "swipe up"
}
apppids() { a shell 'for p in /proc/[0-9]*; do grep -qa "aera-host-ap[i]" $p/cmdline 2>/dev/null && echo ${p#/proc/}; done' | tr -d '\r' | sort -n | tr '\n' ' '; }
open_() { log "open: $(rpc '{"v":1,"id":"back","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"; }
applog() { a shell "cat /sdcard/AERA/plugin-data/$id/aera-flutter.log /tmp/aera/plugin-data/$id/aera-flutter.log 2>/dev/null" | tr -d '\r'; }
gesture_nav() {  # gesture_nav 0|1: save it and restart AERA so it is read
  local f=/data/recovery/AERA/.aera
  a shell '[ -f /sdcard/AERA/.aera ]' && f=/sdcard/AERA/.aera
  rm -f "$OUT/.aera"; a pull "$f" "$OUT/.aera" >/dev/null 2>&1
  python3 "$here/tools/aera_settings.py" set "$OUT/.aera" "aera_recents_enabled=$1" >/dev/null
  a push "$OUT/.aera" "$f" >/dev/null
  a shell 'pkill -f aera-fl[u]tter'; local r0; r0=$(a shell pidof recovery | tr -d '\r'); a shell 'setprop ctl.restart recovery'; sleep 5
  for _ in $(seq 30); do rpc '{"v":1,"id":"back-up","op":"status"}' | grep -q '"result"' && break; sleep 2; done
  log "gesture navigation $1 in $f, AERA restarted (recovery pid $r0 -> $(a shell pidof recovery | tr -d '\r'))"
  remote
}
reloads() { a shell 'grep -nE "lab-back|Reloading input devices" /tmp/recovery.log; stat -c "%y %n" /dev/input /dev/input/*' | tr -d '\r' > "$OUT/input-reload-$1.txt"; }
round() {  # round NAME on|off: open, tap, short Back, leave (swipe up or Home key), reopen
  local n=$1 before
  a shell "echo 'lab-back: round $n' >> /tmp/recovery.log"
  a shell 'pkill -f aera-fl[u]tter; sleep 2'
  open_; sleep "${APP_WAIT:-25}"
  tap 360 1000; sleep 1; tap 352 1010; sleep 2; shot "$n-1-tapped"
  before=$(apppids); log "$n pids: $before"
  key back; sleep 3; shot "$n-2-short-back"
  if [ "$n" = on ]; then swipe_up; else key home; fi
  sleep 3; shot "$n-3-left"
  log "$n pids after leaving: $(apppids)"
  open_; sleep 4; shot "$n-4-reopened"
  [ -n "$before" ] && [ "$before" = "$(apppids)" ] && log "$n SAME PROCESS" || log "$n PROCESS CHANGED or gone"
  reloads "$n"
}

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
log "installed $id"
remote || exit 0

round on
gesture_nav 0 && round off
gesture_nav 1
touches
applog | grep -E "LIFECYCLE|POINTER" > "$OUT/lifecycle.log"
log "app saw: $(grep -oE 'LIFECYCLE [a-z]+ [^ ]*' "$OUT/lifecycle.log" | sed 's/LIFECYCLE //' | tr '\n' ';')"
a shell 'grep -iE "Back|held|lifecycle|pause|resume" /tmp/recovery.log | tail -60' > "$OUT/recovery-back.log" 2>&1
a shell 'pkill -f aera-fl[u]tter'
rm -rf "$OUT/.pkg" "$OUT/.req.json" "$OUT/.aera"
exit 0
