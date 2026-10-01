#!/usr/bin/env bash
# AERA's file picker for pixel plugins (flutter-aera 0018/0019): open the
# picker probe (aera/apps/picker_probe), press each stock file_selector
# call's button, capture the picker, press Back and capture what the app got.
# Taps and Back go through AERA Remote (needs 0017).
# Usage: aera-picker-check.sh PKG.aerap  ->  $LAB_OUT/aera-picker/
# Env: PICK_TAPS  "name:x,y ..." extra taps inside a picker (to choose an entry)
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-picker; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[picker] $*" | tee -a "$OUT/log.txt"; }

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
tap() { post /api/input/touch "{\"action\":\"down\",\"x\":$1,\"y\":$2}" >/dev/null; sleep 0.1
        post /api/input/touch "{\"action\":\"up\",\"x\":$1,\"y\":$2}" >/dev/null; log "tap $1,$2"; }
back() { post /api/input/key '{"key":"back"}' >/dev/null; log "back"; }

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
# Something to pick: a folder with two small files in internal storage.
a shell 'mkdir -p /sdcard/lab-pick && echo a > /sdcard/lab-pick/a.txt && echo b > /sdcard/lab-pick/b.txt'
log "installed $id"

r=$(rpc '{"v":1,"id":"picker-mirror","op":"mirror","args":{"action":"start","port":8089}}')
RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
[ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; exit 0; }
a forward tcp:18089 tcp:8089 >/dev/null; REMOTE=http://127.0.0.1:18089
sleep 2  # minuitwrp picks the new input device up within 2 s
a shell 'pkill -f aera-flutter; sleep 2'
log "open: $(rpc '{"v":1,"id":"picker","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"
sleep "${APP_WAIT:-25}"; shot 00-app

# Button centres: the surface starts below AERA's 165 px status bar and the
# probe splits it into 4 buttons + a results area of 2 units.
top=165 unit=$(( (1348 - 165) / 6 ))
n=0
for name in openFile openFiles getDirectoryPath getSaveLocation; do
  y=$(( top + unit * n + unit / 2 )); n=$((n + 1))
  tap 360 $y; sleep 4; shot "$n-$name-picker"
  picked=
  for t in ${PICK_TAPS:-}; do
    [ "${t%%:*}" = "$name" ] || continue
    xy=${t#*:}; tap "${xy%,*}" "${xy#*,}"; sleep 3; shot "$n-$name-picked"; picked=1
  done
  [ -n "$picked" ] || { back; sleep 3; shot "$n-$name-after"; }
done
a shell "grep -h PICKER /sdcard/AERA/plugin-data/$id/aera-flutter.log /tmp/aera/plugin-data/$id/aera-flutter.log 2>/dev/null; tail -30 /sdcard/AERA/plugin-data/$id/aera-flutter.log 2>/dev/null" > "$OUT/aera-flutter.log" 2>&1
a shell 'grep -iE "picker|pick_files|kPickFiles|file_selector" /tmp/recovery.log | tail -40' > "$OUT/recovery-picker.log" 2>&1
rm -rf "$OUT/.pkg" "$OUT/.req.json"
exit 0
