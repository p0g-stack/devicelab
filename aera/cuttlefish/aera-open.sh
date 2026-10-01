#!/usr/bin/env bash
# In a booted AERA recovery: install a .aerap into AERA's RAM plugin store,
# open it (AERA's RPC `plugin open` when the image has patch 0008, else
# scripted taps through AERA's launcher), tap the app and capture frames
# with AERA's own /tmp/aeraui-capture.
# Usage: aera-open.sh LABEL PKG.aerap
# Env: AERA_TAPS   "x,y x,y ..." launcher taps in screen pixels (fallback path)
#      APP_TAPS    "x,y ..." taps inside the app (default: the counter's +)
#      SWITCHES    engine switches, one per line, for $AERA_PLUGIN_DATA/engine-switches
set -uo pipefail
LABEL=$1 PKG=$2
OUT=${LAB_OUT:-$PWD/out}/$LABEL; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
here=$(cd "$(dirname "$0")/.." && pwd)
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[aera] $*"; }
n=0
shot() {  # shot NAME: AERA writes its framebuffer to /tmp/aeraui.png
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  n=$((n + 1)); a pull /tmp/aeraui.png "$OUT/$(printf %02d $n)-$1.png" >/dev/null 2>&1 \
    && log "frame $(printf %02d $n)-$1.png" || log "no frame for $1"
}
# Touch panel: the multitouch evdev node and its range vs the frame size.
TS=$(a shell 'for d in /sys/class/input/event*; do grep -qi touch $d/device/name && echo /dev/input/${d##*/}; done' | tr -d '\r' | head -1)
read -r TX TY < <(a shell "getevent -pl $TS" | tr -d '\r' | awk '/ABS_MT_POSITION_X/ {for(i=1;i<=NF;i++) if($i=="max") x=$(i+1)} /ABS_MT_POSITION_Y/ {for(i=1;i<=NF;i++) if($i=="max") y=$(i+1)} END {gsub(",","",x); gsub(",","",y); print x, y}')
tap() {  # tap X Y NAME (screen pixels of the captured frame)
  local W H; read -r W H < <(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print(*struct.unpack('>II',d[16:24]))" "$(ls "$OUT"/*.png | tail -1)")
  local x=$(( $1 * ${TX:-$W} / W )) y=$(( $2 * ${TY:-$H} / H ))
  python3 "$here/tools/touch.py" "$x" "$y" "$OUT/.ev" && a push "$OUT/.ev/down.ev" "$OUT/.ev/up.ev" /tmp/ >/dev/null
  a shell "cat /tmp/down.ev > $TS; sleep 0.12; cat /tmp/up.ev > $TS"
  log "tap $1,$2 (panel $x,$y on $TS)"; sleep "${TAP_WAIT:-2}"; shot "${3:-tap}"
}

log "uid $(a shell id -u | tr -d '\r'); touch $TS max ${TX}x${TY}"
a shell 'ps -A -o PID,NAME,ARGS 2>/dev/null | grep -iE "recovery|aera" | grep -v grep' | tee "$OUT/ps.txt"
shot home

# Install the way AERA's manager leaves it: <store>/<id>/{plugin.json,runtime.xz}
id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
data=/tmp/aera/plugin-data/$id
a shell "[ -d /sdcard/AERA ] && echo /sdcard/AERA/plugin-data/$id" | tr -d '\r' | grep -q . && data=/sdcard/AERA/plugin-data/$id
a shell "mkdir -p $data && rm -f $data/engine-switches"
[ -n "${SWITCHES:-}" ] && printf '%s\n' "$SWITCHES" | a shell "cat > $data/engine-switches"
log "installed $id ($(stat -c %s "$OUT/.pkg/runtime.xz") bytes payload), data $data, switches: ${SWITCHES:-none}"

# Open: RPC first (patch 0008), else launcher taps.
req='{"v":1,"id":"lab","op":"plugin","args":{"action":"open","id":"'"$id"'"}}'
echo "$req" > "$OUT/.pkg/req.json"; a push "$OUT/.pkg/req.json" /tmp/lab-req.json >/dev/null
rpc=$(a shell '[ -p /system/bin/aerain ] && { timeout 10 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r')
echo "$rpc" > "$OUT/rpc.txt"; log "rpc: $(echo "$rpc" | tail -3 | tr '\n' ' ')"
if ! echo "$rpc" | grep -q "Opening $id"; then
  for t in ${AERA_TAPS:-}; do tap "${t%,*}" "${t#*,}" launcher; done
fi
sleep "${APP_WAIT:-20}"; shot opened
# Counter's + (bottom right, 16dp margin) unless APP_TAPS says otherwise.
read -r W H < <(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print(*struct.unpack('>II',d[16:24]))" "$(ls "$OUT"/*.png | tail -1)" 2>/dev/null || echo "720 1280")
for t in ${APP_TAPS:-$((W - 70)),$((H - 70)) $((W - 70)),$((H - 70)) $((W - 70)),$((H - 70))}; do TAP_WAIT=1 tap "${t%,*}" "${t#*,}" app; done
sleep 2; shot after
a shell "ls -la $data; tail -40 $data/aera-flutter.log" > "$OUT/aera-flutter.log" 2>&1
a shell 'logcat -d 2>/dev/null | grep -iE "aera|plugin" | tail -150' > "$OUT/logcat-aera.txt" 2>&1
a shell 'dmesg | tail -60' > "$OUT/dmesg.txt" 2>&1
grep -iE "capset|renderer|impeller|vulkan|zink|error" "$OUT/aera-flutter.log" | head -20
rm -rf "$OUT/.pkg" "$OUT/.ev"
exit 0
