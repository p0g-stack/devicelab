#!/usr/bin/env bash
# D5 A/B (infiniti: Remote taps in the side-edge zone dropped; Cuttlefish's
# 0015 retest used raw kernel taps). On the counter's +, a tap outside the
# zone and one inside it (x >= W-72 in AERA pixels, either reading), first
# through AERA Remote's touch API, then as raw evdev taps on the panel.
# After each edge tap: Remote /screen.jpg ~2 s later, then a tap on empty
# content and /screen.jpg again (tells "dropped" from "arrived, frame not
# presented"). getevent -lt on all devices and AERA's "touch released"
# lines are kept as traces.
# Usage: aera-d5-check.sh COUNTER.aerap  ->  $LAB_OUT/aera-d5/
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-d5; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
here=$(cd "$(dirname "$0")/.." && pwd)
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[d5] $*" | tee -a "$OUT/log.txt"; }
shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 0.5; a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && log "frame $1.png" || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
mark() { a shell "log -t lab-d5 '$*'; echo 'lab-d5: $*' >> /tmp/recovery.log"; }
jpg() { curl -s -m 10 -H "x-aera-code: $RCODE" "$REMOTE/screen.jpg" -o "$OUT/$1.jpg"; log "screen.jpg $1 ($(stat -c %s "$OUT/$1.jpg" 2>/dev/null) bytes)"; }
rtap() {  # Remote tap X Y (frame pixels)
  mark "remote tap $1,$2"
  curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" -d "{\"action\":\"down\",\"x\":$1,\"y\":$2}" "$REMOTE/api/input/touch" >/dev/null
  sleep 0.1
  curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" -d "{\"action\":\"up\",\"x\":$1,\"y\":$2}" "$REMOTE/api/input/touch" >/dev/null
  log "remote tap $1,$2"
}
ktap() {  # raw kernel tap X Y (frame pixels, scaled to the panel's range)
  local x=$(( $1 * TX / FW )) y=$(( $2 * TY / FH ))
  mark "raw tap $1,$2 (panel $x,$y)"
  python3 "$here/tools/touch.py" "$x" "$y" "$OUT/.ev" && a push "$OUT/.ev/down.ev" "$OUT/.ev/up.ev" /tmp/ >/dev/null
  a shell "cat /tmp/down.ev > $TS; sleep 0.12; cat /tmp/up.ev > $TS"
  log "raw tap $1,$2 (panel $x,$y on $TS)"
}

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
TS=$(a shell 'for d in /sys/class/input/event*; do grep -qi touch $d/device/name && echo /dev/input/${d##*/}; done' | tr -d '\r' | head -1)
read -r TX TY < <(a shell "getevent -pl $TS" | tr -d '\r' | awk '/ABS_MT_POSITION_X/ {for(i=1;i<=NF;i++) if($i=="max") x=$(i+1)} /ABS_MT_POSITION_Y/ {for(i=1;i<=NF;i++) if($i=="max") y=$(i+1)} END {gsub(",","",x); gsub(",","",y); print x, y}')
r=$(rpc '{"v":1,"id":"d5-mirror","op":"mirror","args":{"action":"start","port":8088}}')
RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
[ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; exit 0; }
a forward tcp:18088 tcp:8088 >/dev/null; REMOTE=http://127.0.0.1:18088; sleep 2
a shell 'pkill -f aera-fl[u]tter; sleep 2; logcat -c'
log "open: $(rpc '{"v":1,"id":"d5","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"
sleep "${APP_WAIT:-25}"; shot 0-open; jpg 0-open
read -r FW FH < <(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print(*struct.unpack('>II',d[16:24]))" "$OUT/0-open.png" 2>/dev/null || echo "720 1348")
log "panel $TS max ${TX}x${TY}; frame ${FW}x${FH}; remote status $(curl -s -m 5 -H "x-aera-code: $RCODE" "$REMOTE/api/status" | head -c 200)"
a shell "(timeout 120 getevent -lt > /tmp/lab-d5-getevent.txt 2>&1 &)"; sleep 1
# The +: frame x about 594-692, y about 1222-1320 (16 dp margin).
IN_X=$((FW - 100)) EDGE_X=$((FW - 32)) PY=$((FH - 76))
rtap $IN_X $PY;               sleep 2; jpg 1-remote-inside; shot 1-remote-inside
rtap $EDGE_X $PY;             sleep 2; jpg 2-remote-edge-2s
rtap $((FW / 2)) $((FH / 3)); sleep 2; jpg 3-remote-after-empty; shot 3-remote-after-empty
ktap $((IN_X - 2)) $((PY + 3)); sleep 2; jpg 4-raw-inside; shot 4-raw-inside
ktap $((EDGE_X + 2)) $((PY - 3)); sleep 2; jpg 5-raw-edge-2s
ktap $((FW / 2 + 3)) $((FH / 3 + 3)); sleep 2; jpg 6-raw-after-empty; shot 6-raw-after-empty
sleep 2
a shell 'pkill getevent' >/dev/null 2>&1
a pull /tmp/lab-d5-getevent.txt "$OUT/getevent.txt" >/dev/null 2>&1
a shell 'logcat -d 2>/dev/null | grep -E "lab-d5|touch released|edge|Back gesture|Recents|Quick" ' | tr -d '\r' > "$OUT/logcat-touches.txt"
a shell 'grep -E "lab-d5|touch|edge" /tmp/recovery.log | tail -60' | tr -d '\r' > "$OUT/recovery-touches.log"
log "AERA touch lines: $(grep -c 'touch released' "$OUT/logcat-touches.txt")"
a shell 'pkill -f aera-fl[u]tter'
rm -rf "$OUT/.pkg" "$OUT/.ev" "$OUT/.req.json"
exit 0
