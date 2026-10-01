#!/usr/bin/env bash
# Where is the second tap lost? Three Remote taps on the lifecycle probe's +
# (centre of the surface, far from the side-edge zones), then three taps on
# AERA's own Files card (Back between them). Records, for every tap, the
# kernel events (getevent), AERA's touch log lines and the probe's POINTER
# and LIFECYCLE lines.
# Usage: aera-taps-check.sh PKG.aerap  ->  $LAB_OUT/aera-taps/
# Env: FILES_CARD  x,y of Home's Files card (default 378,660)
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-taps; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[taps] $*" | tee -a "$OUT/log.txt"; }
shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 1; a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && log "frame $1.png" || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
post() { curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" -d "$2" "$REMOTE$1"; }
mark() { a shell "log -t lab-taps '$*'" >/dev/null 2>&1; echo "== $(date +%T.%N | cut -c1-12) $*" >> "$OUT/getevent.txt"; }
tap() {  # tap LABEL X Y
  mark "$1 at $2,$3"
  post /api/input/touch "{\"action\":\"down\",\"x\":$2,\"y\":$3}" >/dev/null; sleep 0.1
  post /api/input/touch "{\"action\":\"up\",\"x\":$2,\"y\":$3}" >/dev/null; log "$1 tap $2,$3"
}
key() { mark "key $1"; post /api/input/key "{\"key\":\"$1\"}" >/dev/null; log "key $1"; }
applog() { a shell "cat /sdcard/AERA/plugin-data/$id/aera-flutter.log /tmp/aera/plugin-data/$id/aera-flutter.log 2>/dev/null" | tr -d '\r'; }

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
r=$(rpc '{"v":1,"id":"taps-mirror","op":"mirror","args":{"action":"start","port":8088}}')
RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
[ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; exit 0; }
a forward tcp:18088 tcp:8088 >/dev/null; REMOTE=http://127.0.0.1:18088; sleep 2
a shell 'pkill -f aera-flutter; sleep 2; rm -f /sdcard/AERA/plugin-data/'"$id"'/aera-flutter.log; logcat -c'
a shell 'getevent -lt' >> "$OUT/getevent.txt" 2>&1 & GE=$!
sleep 1
log "open: $(rpc '{"v":1,"id":"taps","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"
sleep "${APP_WAIT:-25}"; shot 0-app
for n in 1 2 3; do tap "app-$n" $(( 360 - n * 6 )) $(( 1000 + n * 7 )); sleep 2; shot "app-$n"; done
key home; sleep 3; shot home
xy=${FILES_CARD:-378,660}
for n in 1 2 3; do tap "files-$n" $(( ${xy%,*} - n * 5 )) $(( ${xy#*,} + n * 5 )); sleep 3; shot "files-$n"; key back; sleep 3; done
kill $GE 2>/dev/null; wait $GE 2>/dev/null
a shell 'logcat -d 2>/dev/null | grep -E "lab-taps|touch|Touch|pointer|edge|Back gesture"' | tr -d '\r' > "$OUT/logcat-touch.txt"
applog | grep -E "POINTER|LIFECYCLE" > "$OUT/app.txt"
log "app got: $(grep -c 'POINTER down' "$OUT/app.txt") downs, $(grep -c 'LIFECYCLE tap' "$OUT/app.txt") counted taps"
log "kernel BTN_TOUCH DOWN on AERA Remote Input: $(grep -c 'BTN_TOUCH *DOWN' "$OUT/getevent.txt")"
a shell 'pkill -f aera-flutter'
rm -rf "$OUT/.pkg" "$OUT/.req.json"
exit 0
