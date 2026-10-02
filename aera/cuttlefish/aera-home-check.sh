#!/usr/bin/env bash
# D8 follow-up from the infiniti (2026-10-02): the session's first Remote
# `home` key did nothing before Recents had ever been opened; later ones
# worked. On a freshly started AERA: open the plugin, `home` as the very
# first key, `home` again, reopen, Menu (Recents) and Menu, then `home`.
# getevent on Remote's uinput node shows whether each key reached the kernel.
# Usage: aera-home-check.sh PKG.aerap  ->  $LAB_OUT/aera-home/
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-home; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[home] $*" | tee -a "$OUT/log.txt"; }
shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 1; a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && log "frame $1.png" || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
key() { log "key $1: $(curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" -d "{\"key\":\"$1\"}" "$REMOTE/api/input/key")"; a shell "echo 'lab-home: key $1' >> /tmp/recovery.log"; }
apppids() { a shell 'for p in /proc/[0-9]*; do grep -qa "aera-host-ap[i]" $p/cmdline 2>/dev/null && echo ${p#/proc/}; done' | tr -d '\r' | sort -n | tr '\n' ' '; }
open_() { log "open: $(rpc '{"v":1,"id":"home","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"; }

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
log "installed $id"

# A fresh AERA: Recents and its card list live in the recovery process.
a shell 'pkill -f aera-fl[u]tter'; r0=$(a shell pidof recovery | tr -d '\r'); a shell 'setprop ctl.restart recovery'; sleep 5
for _ in $(seq 30); do rpc '{"v":1,"id":"home-up","op":"status"}' | grep -q '"result"' && break; sleep 2; done
log "AERA restarted (recovery pid $r0 -> $(a shell pidof recovery | tr -d '\r'))"
r=$(rpc '{"v":1,"id":"home-mirror","op":"mirror","args":{"action":"start","port":8088}}')
RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
[ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; exit 0; }
a forward tcp:18088 tcp:8088 >/dev/null; REMOTE=http://127.0.0.1:18088; sleep 2
node=$(a shell 'grep -A5 "AERA Remote Input" /proc/bus/input/devices | sed -n "s/.*Handlers=.*\(event[0-9]*\).*/\1/p"' | tr -d '\r' | head -1)
log "Remote input node: ${node:-none}"
[ -n "$node" ] && a shell "(getevent -lt /dev/input/$node > /tmp/lab-home-getevent.txt 2>&1 &)"

open_; sleep "${APP_WAIT:-25}"; shot 1-open; log "pids: $(apppids)"
key home; sleep 3; shot 2-first-home      # the very first key of this AERA
key home; sleep 3; shot 3-second-home     # still before any Recents
open_; sleep 5; shot 4-reopened
key menu; sleep 3; shot 5-menu-recents
key menu; sleep 3; shot 6-menu-closed
key home; sleep 3; shot 7-home-after-recents
log "pids after keys: $(apppids)"

a shell 'pkill getevent' >/dev/null 2>&1
a pull /tmp/lab-home-getevent.txt "$OUT/getevent.txt" >/dev/null 2>&1
log "KEY_HOMEPAGE events: $(grep -c 'KEY_HOMEPAGE' "$OUT/getevent.txt" 2>/dev/null)"
a shell 'grep -nE "lab-home|Reloading input|input device|Recents|Home" /tmp/recovery.log | tail -80' | tr -d '\r' > "$OUT/recovery-keys.log"
a shell 'pkill -f aera-fl[u]tter'
rm -rf "$OUT/.pkg" "$OUT/.req.json"
exit 0
