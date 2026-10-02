#!/usr/bin/env bash
# Rotation with a pixel plugin running (flutter-aera 0020): open the
# counter, rotate AERA from Quick Settings (swipe the shade down, tap the
# Rotation tile), and check the same aera-flutter process keeps running and
# redraws in the new orientation. Input through AERA Remote (needs 0017).
# Usage: aera-rotate-check.sh PKG.aerap  ->  $LAB_OUT/aera-rotate/
# Env: ROTATE_TILE  x,y of the Rotation tile in the open shade (portrait)
#      SHADE_CLOSE  x,y of the shade's collapse chevron (portrait)
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
# D9: minuitwrp zeroes a contact's position on release and the kernel drops
# a coordinate equal to the slot's last one, so a press at the same x (or y)
# as the previous contact reaches AERA at 0. Fixed by flutter-aera 0025; with
# PRESS_SHIFT=1 every press shifts by 1 px from the last one (fallback for
# images without 0025).
J=0
touch_() { [ "$1" = down ] && [ "${PRESS_SHIFT:-0}" = 1 ] && J=$((1 - J)); curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" \
  -d "{\"action\":\"$1\",\"x\":$(( $2 + J )),\"y\":$(( $3 + J ))}" "$REMOTE/api/input/touch" >/dev/null; }
tap() { touch_ down "$1" "$2"; sleep 0.1; touch_ up "$1" "$2"; log "tap $1,$2"; }
swipe() {  # swipe X1 Y1 X2 Y2
  local i; touch_ down "$1" "$2"
  for i in 1 2 3 4 5 6 7 8; do touch_ move $(( $1 + ($3 - $1) * i / 8 )) $(( $2 + ($4 - $2) * i / 8 )); sleep 0.03; done
  touch_ up "$3" "$4"; log "swipe $1,$2 -> $3,$4"
}
arm_core() { a shell "echo /tmp/core.%e.%p > /proc/sys/kernel/core_pattern; toybox ulimit -P \$(pidof recovery) -c unlimited 2>&1; toybox ulimit -P \$(pidof recovery) -c" | tr -d '\r' | sed 's/^/[rotate] core limit: /' | tee -a "$OUT/log.txt"; }
cores() { local c; for c in $(a shell 'ls /tmp/core.* 2>/dev/null' | tr -d '\r'); do a pull "$c" "$OUT/$1-${c##*/}" >/dev/null 2>&1 && a shell "rm -f $c" && log "core $1-${c##*/}"; done; }
pids() { a shell 'pidof ld-linux-x86-64.so.2 aera-flutter 2>/dev/null; ps -A -o PID,ETIME,ARGS | grep aera-flutter | grep -v grep' | tr -d '\r'; }

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null

r=$(rpc '{"v":1,"id":"rotate-mirror","op":"mirror","args":{"action":"start","port":8088}}')
RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
[ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; exit 0; }
a forward tcp:18088 tcp:8088 >/dev/null; REMOTE=http://127.0.0.1:18088
sleep 2
a shell 'pkill -f aera-fl[u]tter; sleep 2'
log "open: $(rpc '{"v":1,"id":"rotate","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"
sleep "${APP_WAIT:-25}"; shot 1-portrait
before=$(pids); log "before: $before"

curl -s -m 10 -H "x-aera-code: $RCODE" "$REMOTE/screen.jpg" -o "$OUT/1-remote-screen.jpg"; log "remote screen.jpg (portrait) $(stat -c %s "$OUT/1-remote-screen.jpg" 2>/dev/null) bytes"
arm_core; rp=$(a shell pidof recovery | tr -d '\r')
swipe 360 10 360 900; sleep 2; shot 2-shade
xy=${ROTATE_TILE:-240,400}; tap "${xy%,*}" "${xy#*,}"; sleep 3; shot 3-after-toggle
a shell 'logcat -d 2>/dev/null | grep -iE "rotat|landscape" | tail -10' | tr -d '\r' >> "$OUT/log.txt"
# In landscape (0026) AERA maps the panel's touches like its frames: the
# 1348x720 landscape picture is the 720x1348 panel turned a quarter left
# (title reads bottom to top, run 36962574911), so landscape lx,ly is panel
# ly,1347-lx. Portrait taps after the toggle missed (shade stayed open; the
# swipe from the right edge was a Back that quit the counter).
ltap() { tap "$2" "$(( 1347 - $1 ))"; }                       # landscape x y
lswipe() { swipe "$2" "$(( 1347 - $1 ))" "$4" "$(( 1347 - $3 ))"; }
ltap 590 110; log "(landscape: shade chevron)"; sleep 3; shot 3b-after-chevron
sleep 5; shot 4-rotated
ltap 1290 660; sleep 1; ltap 1291 661; log "(landscape: counter + twice)"; sleep 3; shot 4b-landscape-taps
curl -s -m 10 -H "x-aera-code: $RCODE" "$REMOTE/screen.jpg" -o "$OUT/4-remote-screen.jpg"; log "remote screen.jpg $(stat -c %s "$OUT/4-remote-screen.jpg" 2>/dev/null) bytes"
# Back to portrait: shade down from the landscape top, Rotation tile (the
# landscape shade lays tiles out differently: Rotation at landscape 432,345
# in run 36965839509's 4c-landscape-shade.png).
lswipe 674 10 674 600; sleep 2; shot 4c-landscape-shade; ltap 432 345; sleep 4; shot 5-toggled-back
sleep 6; log "recovery pid $rp -> $(a shell pidof recovery | tr -d '\r')"; after=$(pids); log "counter pids: $before -> $after"
[ -n "$before" ] && [ "$(echo "$before" | head -1)" = "$(echo "$after" | head -1)" ] && log "SAME PROCESS" || log "PROCESS CHANGED or gone"; cores counter
# Control (run 36953588555: toggling back crashed AERA with the counter open):
# the same rotation and back with no plugin running, on Home.
# After rotating back the portrait shade keeps a different tile layout (run
# 36968103917, 5-toggled-back.png: Rotation moved), so restart AERA for a
# fresh portrait layout before the Home control. A fresh AERA's landscape
# shade is laid out full width with its chevron at landscape 1226,108 (run
# 36978191707), the shade after a plugin at 590,110: tap both.
a shell 'pkill -f aera-fl[u]tter'; r0=$(a shell pidof recovery | tr -d '\r'); a shell 'setprop ctl.restart recovery'; sleep 15
for _ in $(seq 20); do a shell true >/dev/null 2>&1 && break; sleep 2; done
log "AERA restart for the control: recovery pid $r0 -> $(a shell pidof recovery | tr -d '\r')"
if [ "$(a shell pidof recovery | tr -d '\r')" != "$rp" ]; then
  sleep 5; r=$(rpc '{"v":1,"id":"rotate-mirror2","op":"mirror","args":{"action":"start","port":8088}}')
  RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1); sleep 2; a forward tcp:18088 tcp:8088 >/dev/null
fi
a shell 'pkill -f aera-fl[u]tter'; sleep 2; arm_core; rp=$(a shell pidof recovery | tr -d '\r')
xy=${ROTATE_TILE:-240,400}
swipe 360 10 360 900; sleep 2; tap "${xy%,*}" "${xy#*,}"; sleep 4; ltap 590 110; sleep 2; ltap 1226 108; sleep 3; shot 6-home-landscape
lswipe 674 10 674 600; sleep 2; ltap 432 345; sleep 4; shot 7-home-back
sleep 4; log "no plugin: recovery pid $rp -> $(a shell pidof recovery | tr -d '\r')"; cores home
a shell 'logcat -d 2>/dev/null | grep -E "touch released|orientation|frame capture" | tail -25' | tr -d '\r' > "$OUT/logcat-rotate.txt"
a shell 'cat /sys/class/drm/card0-*/modes 2>/dev/null | head -2; grep -iE "rotat|SURFACE|generation" /tmp/recovery.log | tail -20' > "$OUT/recovery-rotate.log" 2>&1
a shell "tail -40 /sdcard/AERA/plugin-data/$id/aera-flutter.log /tmp/aera/plugin-data/$id/aera-flutter.log 2>/dev/null" > "$OUT/aera-flutter.log" 2>&1
a shell 'logcat -d 2>/dev/null | grep -iE "surface|pixel|scene|orientation|present|plugin" | tail -60' | tr -d '\r' > "$OUT/logcat-surface.txt"
rm -rf "$OUT/.pkg" "$OUT/.req.json"
exit 0
