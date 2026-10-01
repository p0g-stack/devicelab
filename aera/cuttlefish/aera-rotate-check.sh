#!/usr/bin/env bash
# Rotation with a pixel plugin running (flutter-aera 0020): open the
# counter, rotate AERA from Quick Settings (swipe the shade down, tap the
# Rotation tile), and check the same aera-flutter process keeps running and
# redraws in the new orientation. Input through AERA Remote (needs 0017).
# Usage: aera-rotate-check.sh PKG.aerap  ->  $LAB_OUT/aera-rotate/
# Env: ROTATE_TILE  x,y of the Rotation tile in the open shade (portrait)
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-rotate; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[rotate] $*" | tee -a "$OUT/log.txt"; }

shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 1; a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 \
    && log "frame $1.png $(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print('%dx%d' % struct.unpack('>II',d[16:24]))" "$OUT/$1.png")" \
    || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
touch_() { curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" \
  -d "{\"action\":\"$1\",\"x\":$2,\"y\":$3}" "$REMOTE/api/input/touch" >/dev/null; }
tap() { touch_ down "$1" "$2"; sleep 0.1; touch_ up "$1" "$2"; log "tap $1,$2"; }
swipe() {  # swipe X1 Y1 X2 Y2
  local i; touch_ down "$1" "$2"
  for i in 1 2 3 4 5 6 7 8; do touch_ move $(( $1 + ($3 - $1) * i / 8 )) $(( $2 + ($4 - $2) * i / 8 )); sleep 0.03; done
  touch_ up "$3" "$4"; log "swipe $1,$2 -> $3,$4"
}
pids() { a shell 'pidof ld-linux-x86-64.so.2 aera-flutter 2>/dev/null; ps -A -o PID,ETIME,ARGS | grep aera-flutter | grep -v grep' | tr -d '\r'; }

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null

r=$(rpc '{"v":1,"id":"rotate-mirror","op":"mirror","args":{"action":"start","port":8090}}')
RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
[ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; exit 0; }
a forward tcp:18090 tcp:8090 >/dev/null; REMOTE=http://127.0.0.1:18090
sleep 2
a shell 'pkill -f aera-flutter; sleep 2'
log "open: $(rpc '{"v":1,"id":"rotate","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"
sleep "${APP_WAIT:-25}"; shot 1-portrait
before=$(pids); log "before: $before"

swipe 360 10 360 900; sleep 2; shot 2-shade
xy=${ROTATE_TILE:-240,400}; tap "${xy%,*}" "${xy#*,}"; sleep 3; shot 3-after-toggle
sleep 8; shot 4-rotated
after=$(pids); log "after: $after"
[ -n "$before" ] && [ "$(echo "$before" | head -1)" = "$(echo "$after" | head -1)" ] \
  && log "SAME PROCESS" || log "PROCESS CHANGED or gone"
a shell 'cat /sys/class/drm/card0-*/modes 2>/dev/null | head -2; grep -iE "rotat|SURFACE|generation" /tmp/recovery.log | tail -20' > "$OUT/recovery-rotate.log" 2>&1
a shell "tail -30 /sdcard/AERA/plugin-data/$id/aera-flutter.log 2>/dev/null" > "$OUT/aera-flutter.log" 2>&1
rm -rf "$OUT/.pkg" "$OUT/.req.json"
exit 0
