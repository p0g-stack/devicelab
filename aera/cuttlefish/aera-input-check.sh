#!/usr/bin/env bash
# Raw panel input on the counter, for flutter-aera 0025 (amended), F0001 and
# 0029. Every step is a raw evdev write to the touch panel, so the kernel
# drops an ABS value equal to that slot's last one, as a real multitouch
# controller's driver does:
#   D9   six taps on the + over slots 0 and 1, each sharing an axis (or both)
#        with that slot's previous contact, the last without an ABS_MT_SLOT
#        event at all; with 0025 the count reaches 6
#   F0001 a still press in the bottom strip, on the +, held 0.8 s: Remote's
#        /screen.jpg during the press equals the one before it (no Recents
#        morph) and the release counts; then a swipe up goes Home and a
#        swipe up and hold opens Recents
#   0029 the plugin's surface size (aera-flutter.log) and tap positions
# Usage: aera-input-check.sh COUNTER.aerap  ->  $LAB_OUT/aera-input/
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-input; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[input] $*" | tee -a "$OUT/log.txt"; }
shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 0.5; a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && log "frame $1.png" || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
mark() { a shell "log -t lab-input '$*'"; }
jpg() { curl -s -m 10 -H "x-aera-code: $RCODE" "$REMOTE/screen.jpg" -o "$OUT/$1.jpg"; }
# ev FILE "type code value" ...: x86_64 input_event records
ev() { local f=$1; shift; python3 - "$OUT/$f" "$@" <<'PY'
import struct, sys
codes = {"SYN": (0, 0), "KEY": (1, 0x14a), "SLOT": (3, 0x2f), "TRACK": (3, 0x39), "MX": (3, 0x35), "MY": (3, 0x36), "X": (3, 0), "Y": (3, 1)}
out = b""
for item in sys.argv[2:]:
    name, value = item.split("=")
    t, c = codes[name]
    out += struct.pack("<qqHHi", 0, 0, t, c, int(value))
open(sys.argv[1], "wb").write(out)
PY
a push "$OUT/$f" "/tmp/$f" >/dev/null; }
put() { a shell "cat /tmp/$1 > $TS"; }
# rtap NAME SLOT|- X Y: press on SLOT (- = no ABS_MT_SLOT event), release
TRK=100
rtap() {
  local s=() ; [ "$2" != - ] && s=("SLOT=$2"); TRK=$((TRK + 1))
  ev "$1-d.ev" "${s[@]}" "TRACK=$TRK" "MX=$3" "MY=$4" KEY=1 "X=$3" "Y=$4" SYN=0
  ev "$1-u.ev" "${s[@]}" TRACK=-1 KEY=0 SYN=0
  mark "$1 slot $2 at $3,$4"; put "$1-d.ev"; sleep 0.12; put "$1-u.ev"; log "$1: slot $2 at $3,$4"; sleep 1.2
}
count() { a shell 'logcat -d -t 400 2>/dev/null | grep "touch released"' | tr -d '\r' | tail -1 | sed 's/.*touch released/released/'; }

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
TS=$(a shell 'for d in /sys/class/input/event*; do grep -qi touch $d/device/name && echo /dev/input/${d##*/}; done' | tr -d '\r' | head -1)
log "panel $TS: $(a shell "getevent -pl $TS" | tr -d '\r' | grep -E 'MT_POSITION|MT_SLOT' | tr -s ' ' | tr '\n' ';')"
r=$(rpc '{"v":1,"id":"input-mirror","op":"mirror","args":{"action":"start","port":8088}}')
RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
a forward tcp:18088 tcp:8088 >/dev/null; REMOTE=http://127.0.0.1:18088; sleep 2
a shell 'pkill -f aera-fl[u]tter; sleep 2; logcat -c'
log "open: $(rpc '{"v":1,"id":"input","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"
sleep "${APP_WAIT:-25}"; shot 0-open
a shell "(timeout 150 getevent -lt $TS > /tmp/lab-input-getevent.txt 2>&1 &)"; sleep 1

# D9 (0025): the + spans about x 594-692, y 1222-1320 in panel pixels.
rtap d9-1 0 620 1270     # slot 0 first contact
rtap d9-2 1 612 1270     # slot 1 first contact
rtap d9-3 0 606 1270     # slot 0: y equals its last, dropped by the kernel
rtap d9-4 1 612 1262     # slot 1: x equals its last
rtap d9-5 0 606 1270     # slot 0: both equal its last
ev d9-6-d.ev SLOT=0 TRACK=120 MX=614 MY=1266 KEY=1 X=614 Y=1266 SYN=0; ev d9-6-u.ev TRACK=-1 KEY=0 SYN=0
put d9-6-d.ev; sleep 0.2
ev d9-6b-d.ev TRACK=-1 KEY=0 SYN=0; put d9-6b-d.ev; sleep 1   # (slot 0 is current now)
ev d9-7-d.ev TRACK=121 MX=618 MY=1266 KEY=1 X=618 Y=1266 SYN=0; ev d9-7-u.ev TRACK=-1 KEY=0 SYN=0
mark "d9-7 no slot event at 618,1266"; put d9-7-d.ev; sleep 0.12; put d9-7-u.ev; log "d9-6: slot 0 at 614,1266; d9-7: no slot event at 618,1266 (y equals the last)"; sleep 1.5
shot 1-after-d9   # expected 7
a shell 'logcat -d 2>/dev/null | grep -E "lab-input|touch released"' | tr -d '\r' | sed 's/^.*\(lab-input\|touch released\)/\1/' > "$OUT/d9-trace.txt"
log "D9 releases: $(grep -c 'touch released' "$OUT/d9-trace.txt") lines; zeroed: $(grep -cE 'released at (-1|0),|,(0|65535)$' "$OUT/d9-trace.txt")"

# F0001: still press in the bottom strip on the + (panel y 1300 >= 1348-64).
jpg 2-before-press
ev st-d.ev SLOT=0 TRACK=130 MX=640 MY=1300 KEY=1 X=640 Y=1300 SYN=0; ev st-u.ev SLOT=0 TRACK=-1 KEY=0 SYN=0
mark "still press 640,1300"; put st-d.ev; sleep 0.5; jpg 3-during-press; sleep 0.3; put st-u.ev; log "still press 640,1300 for 0.8 s"
sleep 1.5; jpg 4-after-press; shot 4-after-press   # expected 8, no Home/Recents
python3 - "$OUT" <<'PY' | tee -a "$OUT/log.txt"
import sys
from PIL import Image, ImageChops
d = sys.argv[1]
try:
    a, b = (Image.open(f"{d}/{n}.jpg").convert("L") for n in ("2-before-press", "3-during-press"))
    diff = ImageChops.difference(a, b).point(lambda v: 255 if v > 24 else 0)
    changed = sum(1 for v in diff.getdata() if v) / (a.width * a.height)
    print(f"[input] still press: {changed:.2%} of pixels changed during the press ({'NO MORPH' if changed < 0.01 else 'MORPH'})")
except Exception as e:
    print(f"[input] still press: compare failed: {e}")
PY
# Swipe up from the strip goes Home; up and hold opens Recents.
swipe() {  # swipe NAME HOLD
  local f=() i y; f+=(SLOT=0 TRACK=140 MX=360 MY=1340 KEY=1 X=360 Y=1340 SYN=0)
  ev "$1-d.ev" "${f[@]}"; put "$1-d.ev"
  for i in 1 2 3 4 5 6; do y=$(( 1340 - 300 * i / 6 )); ev "$1-m.ev" "MY=$y" "Y=$y" SYN=0; put "$1-m.ev"; sleep 0.03; done
  if [ "$2" = 1 ]; then for i in 1 2 3 4 5 6; do y=$(( 1040 + i % 2 )); ev "$1-m.ev" "MY=$y" "Y=$y" SYN=0; put "$1-m.ev"; sleep 0.1; done; fi
  ev "$1-u.ev" TRACK=-1 KEY=0 SYN=0; put "$1-u.ev"; log "raw swipe up${2/1/ and hold}"
}
swipe home 0; sleep 3; shot 5-swipe-home
log "reopen: $(rpc '{"v":1,"id":"input2","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"; sleep 4
swipe recents 1; sleep 3; shot 6-swipe-hold-recents
a shell 'pkill getevent' >/dev/null 2>&1; a pull /tmp/lab-input-getevent.txt "$OUT/getevent.txt" >/dev/null 2>&1
a shell 'logcat -d 2>/dev/null | grep -E "lab-input|touch released|Recents|edge"' | tr -d '\r' > "$OUT/logcat-input.txt"
a shell "cat /tmp/aera/plugin-data/$id/aera-flutter.log /sdcard/AERA/plugin-data/$id/aera-flutter.log 2>/dev/null | grep -i surface" | tr -d '\r' > "$OUT/surface.txt"
log "0029 surface: $(tr '\n' ';' < "$OUT/surface.txt")"
a shell 'pkill -f aera-fl[u]tter'
rm -rf "$OUT/.pkg" "$OUT"/*.ev "$OUT/.req.json"
exit 0
