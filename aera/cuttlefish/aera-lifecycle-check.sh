#!/usr/bin/env bash
# Pixel plugin lifecycle (flutter-aera 0021) and AERA_PLUGIN_DATA_VOLATILE
# (0022) with the lifecycle probe (aera/apps/lifecycle_probe): open it, tap +
# twice, go Home (short swipe up from the bottom edge), reopen it from Recents
# (swipe up and hold, tap its card); the count must still be 2 in the same
# process. Then open it again with /sdcard/AERA moved away, so its data
# directory is the RAM fallback, and check the variable. Input through AERA
# Remote (needs 0017).
# Usage: aera-lifecycle-check.sh PKG.aerap  ->  $LAB_OUT/aera-lifecycle/
# Env: RECENTS_CARD  x,y of the app's card in Recents (default 360,790)
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-lifecycle; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[lifecycle] $*" | tee -a "$OUT/log.txt"; }

shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 1; a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && log "frame $1.png" || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
touch_() { curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" \
  -d "{\"action\":\"$1\",\"x\":$2,\"y\":$3}" "$REMOTE/api/input/touch" >/dev/null; }
tap() { touch_ down "$1" "$2"; sleep 0.1; touch_ up "$1" "$2"; log "tap $1,$2"; }
key() { log "key $1: $(curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" -d "{\"key\":\"$1\"}" "$REMOTE/api/input/key")"; }
# What reached AERA (its "touch released" debug lines) and the app (POINTER lines).
touches() { a shell 'logcat -d 2>/dev/null | grep -E "touch released|Back gesture|edge" | tail -40' | tr -d '\r' > "$OUT/touches-aera.log"; }
# Bottom-edge gesture: up from the last 64 px. HOLD=1 keeps still at the top
# for 0.6 s first, which AERA reads as Recents; without it the swipe goes Home.
edge_swipe() {
  local i y; touch_ down 360 1340
  for i in 1 2 3 4 5 6; do y=$(( 1340 - 300 * i / 6 )); touch_ move 360 $y; sleep 0.03; done
  if [ "${HOLD:-}" = 1 ]; then for i in 1 2 3 4 5 6; do touch_ move 360 $(( 1040 + i % 2 )); sleep 0.1; done; fi
  touch_ up 360 1040; log "edge swipe up${HOLD:+ and hold}"
}
apppids() { a shell 'for p in /proc/[0-9]*; do grep -qa "aera-host-ap[i]" $p/cmdline 2>/dev/null && echo ${p#/proc/}; done' | tr -d '\r' | sort -n | tr '\n' ' '; }
appenv() { local p; for p in $(apppids); do a shell "tr '\\0' '\\n' < /proc/$p/environ | grep ^AERA_" | tr -d '\r' | sed "s/^/pid $p: /"; done; }
applog() { a shell "cat /sdcard/AERA/plugin-data/$id/aera-flutter.log /sdcard/AERA.lab/plugin-data/$id/aera-flutter.log /tmp/aera/plugin-data/$id/aera-flutter.log 2>/dev/null" | tr -d '\r'; }
open_() { log "open: $(rpc '{"v":1,"id":"lifecycle","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"; }

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
log "installed $id"

r=$(rpc '{"v":1,"id":"lifecycle-mirror","op":"mirror","args":{"action":"start","port":8088}}')
RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
[ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; exit 0; }
a forward tcp:18088 tcp:8088 >/dev/null; REMOTE=http://127.0.0.1:18088
sleep 2
a shell 'pkill -f aera-flutter; sleep 2'
open_; sleep "${APP_WAIT:-25}"; shot 1-open
before=$(apppids); log "pids: $before"
tap 360 1000; sleep 1; tap 350 1012; sleep 2; shot 2-tapped
edge_swipe; sleep 3; shot 3-home
log "pids at Home: $(apppids)"
key menu; sleep 3; shot 4-recents  # Recents by Menu (0023); swipe-and-hold missed in run 36934450186
xy=${RECENTS_CARD:-360,790}; tap "${xy%,*}" "${xy#*,}"; sleep 4; shot 5-reopened
after=$(apppids); log "pids: $after"
[ -n "$before" ] && [ "$before" = "$after" ] && log "SAME PROCESS" || log "PROCESS CHANGED or gone"
applog | grep -E "LIFECYCLE|POINTER" > "$OUT/lifecycle.log"
log "app saw: $(grep -oE 'LIFECYCLE (start|tap|[a-z]+) [^ ]*' "$OUT/lifecycle.log" | sed 's/LIFECYCLE //' | tr '\n' ';')"
log "env (storage): $(appenv | tr '\n' ' ')"

# Data directory in RAM: no /sdcard/AERA at launch.
# A file named /sdcard/AERA keeps AERA from recreating the folder before the launch.
a shell 'pkill -f aera-flutter; sleep 2; mv /sdcard/AERA /sdcard/AERA.lab && touch /sdcard/AERA'
log "storage before RAM launch: $(a shell 'ls -ld /sdcard/AERA /sdcard/AERA.lab /data/media/0/AERA 2>&1' | tr -d '\r' | tr '\n' ' ')"
open_; sleep "${APP_WAIT:-25}"; shot 6-ram-data
log "env (RAM): $(appenv | tr '\n' ' ')"
applog | grep 'LIFECYCLE start' | tail -1 | sed 's/^/[lifecycle] app (RAM): /' | tee -a "$OUT/log.txt"
a shell 'pkill -f aera-flutter; sleep 2; [ -d /sdcard/AERA.lab ] && { rm -rf /sdcard/AERA; mv /sdcard/AERA.lab /sdcard/AERA; }'
touches

# D8 (flutter-aera 0023): Remote's Home and Menu buttons reach Home and
# Recents; Menu again closes Recents.
open_; sleep "${APP_WAIT:-25}"; shot 7-app-for-keys
key home; sleep 3; shot 8-key-home
key menu; sleep 3; shot 9-key-menu-recents
key menu; sleep 3; shot 10-key-menu-again
log "pids after keys: $(apppids)"
a shell 'pkill -f aera-flutter'
a shell 'grep -iE "lifecycle|pause|resume|recents|plugin" /tmp/recovery.log | tail -60' > "$OUT/recovery-lifecycle.log" 2>&1
applog | tail -60 > "$OUT/aera-flutter.log"
rm -rf "$OUT/.pkg" "$OUT/.req.json"
exit 0
