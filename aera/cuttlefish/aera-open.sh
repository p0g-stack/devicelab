#!/usr/bin/env bash
# In a booted AERA recovery: install a .aerap into AERA's RAM plugin store,
# open it (AERA's RPC `plugin open` when the image has patch 0008, else
# scripted taps through AERA's launcher), tap the app and capture frames
# with AERA's own /tmp/aeraui-capture. Taps go through AERA Remote (RPC
# `mirror start`, its uinput touch API) when it starts, else raw evdev writes.
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
rpc() {  # rpc JSON: one request through AERA's FIFOs, prints the event lines
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout ${RPC_WAIT:-60} cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
RPORT=8088 REMOTE=
remote_start() {
  local r; r=$(rpc '{"v":1,"id":"lab-mirror","op":"mirror","args":{"action":"start","port":'$RPORT'}}')
  echo "$r" >> "$OUT/rpc.txt"
  if echo "$r" | grep -q '"running":true'; then
    RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
    a forward tcp:1$RPORT tcp:$RPORT >/dev/null && REMOTE=http://127.0.0.1:1$RPORT
    curl -s -m 5 -H "x-aera-code: $RCODE" "$REMOTE/api/status" > "$OUT/remote-status.json" || true
    log "AERA Remote up: $(cat "$OUT/remote-status.json" 2>/dev/null | head -c 300)"
  else log "AERA Remote did not start: $(echo "$r" | tail -2 | tr '\n' ' ')"; fi
}
touch_remote() {  # touch_remote ACTION X Y
  curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" \
    -d "{\"action\":\"$1\",\"x\":$2,\"y\":$3}" "$REMOTE/api/input/touch"
}
tap() {  # tap X Y NAME (screen pixels of the captured frame)
  if [ -n "$REMOTE" ]; then
    local r1 r2; r1=$(touch_remote down "$1" "$2"); sleep 0.1; r2=$(touch_remote up "$1" "$2")
    log "tap $1,$2 via AERA Remote: $(echo "$r1 $r2" | tr -d '\n' | head -c 200)"
    sleep "${TAP_WAIT:-2}"; shot "${3:-tap}"; return
  fi
  local W H; read -r W H < <(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print(*struct.unpack('>II',d[16:24]))" "$(ls "$OUT"/*.png | tail -1)" 2>/dev/null || echo "${TX:-720} ${TY:-1348}")
  local x=$(( $1 * ${TX:-$W} / W )) y=$(( $2 * ${TY:-$H} / H ))
  python3 "$here/tools/touch.py" "$x" "$y" "$OUT/.ev" && a push "$OUT/.ev/down.ev" "$OUT/.ev/up.ev" /tmp/ >/dev/null
  # getevent shows whether the kernel passes the written events on to readers
  a shell "(timeout 2 getevent -lt $TS > /tmp/lab-getevent.txt 2>&1 &); sleep 0.3; cat /tmp/down.ev > $TS; sleep 0.12; cat /tmp/up.ev > $TS; sleep 1.8; cat /tmp/lab-getevent.txt" >> "$OUT/getevent.txt" 2>&1
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
rpc=$(rpc '{"v":1,"id":"lab","op":"plugin","args":{"action":"open","id":"'"$id"'"}}')
echo "$rpc" >> "$OUT/rpc.txt"; log "rpc: $(echo "$rpc" | tail -3 | tr '\n' ' ')"
if ! echo "$rpc" | grep -q "Opening $id"; then
  for t in ${AERA_TAPS:-}; do tap "${t%,*}" "${t#*,}" launcher; done
fi
sleep "${APP_WAIT:-20}"; shot opened
# Counter's + (bottom right, 16dp margin) unless APP_TAPS says otherwise.
read -r W H < <(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print(*struct.unpack('>II',d[16:24]))" "$(ls "$OUT"/*.png | tail -1)" 2>/dev/null || echo "720 1280")
set -- ${APP_TAPS:-$((W - 100)),$((H - 70)) $((W - 100)),$((H - 70)) $((W - 100)),$((H - 70))}
# One raw evdev tap first (recorded with getevent), then AERA Remote.
TAP_WAIT=1 tap "${1%,*}" "${1#*,}" raw; shift
remote_start
[ -n "$REMOTE" ] && curl -s -m 10 -H "x-aera-code: $RCODE" -o "$OUT/remote-screen.jpg" "$REMOTE/screen.jpg"
for t in "$@"; do TAP_WAIT=1 tap "${t%,*}" "${t#*,}" app; done
sleep 2; shot after
a shell "ls -la $data; tail -40 $data/aera-flutter.log" > "$OUT/aera-flutter.log" 2>&1
a shell 'logcat -d 2>/dev/null | grep -iE "aera|plugin" | tail -150' > "$OUT/logcat-aera.txt" 2>&1
a shell 'dmesg | tail -60' > "$OUT/dmesg.txt" 2>&1
grep -iE "capset|renderer|impeller|vulkan|zink|error" "$OUT/aera-flutter.log" | head -20
rm -rf "$OUT/.pkg" "$OUT/.ev" "$OUT/.req.json"
exit 0
