#!/usr/bin/env bash
# AERA's own UI, no plugin (maintainer report on the upstream PRs,
# 2026-10-06: pressed buttons drawn about half size and misaligned, mode
# transitions not happening, reboot not working):
#   1. press and hold the Home screen's Files card: frames before, held,
#      after release (stock AERA draws transform_scale at 100%, so the held
#      card must keep its size and place)
#   2. mode transition to fastboot and back (RPC `transition`, the same
#      animation as the UI's): frames during and after, recovery alive
#   3. power menu (Power held 3.5 s on Remote's uinput node), then its
#      Recovery button: the power transition must end in a reboot
#      (uptime drops)
# Usage: aera-stock-ui-check.sh  ->  $LAB_OUT/aera-stock-ui/
# FILES_XY and RECOVERY_XY override the touch points (screen pixels).
set -uo pipefail
OUT=${LAB_OUT:-$PWD/out}/aera-stock-ui; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[stock-ui] $*" | tee -a "$OUT/log.txt"; }
shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  # The PNG is still being written when it first appears: wait for its size to settle.
  local s0= s1; for _ in $(seq 20); do s1=$(a shell 'stat -c %s /tmp/aeraui.png 2>/dev/null' | tr -d '\r')
    [ -n "$s1" ] && [ "$s1" = "$s0" ] && break; s0=$s1; sleep 0.3; done
  a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && log "frame $1.png" || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
touch_() { curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" \
  -d "{\"action\":\"$1\",\"x\":$2,\"y\":$3}" "$REMOTE/api/input/touch" >/dev/null; }
mark() { a shell "echo 'lab-stock-ui: $*' >> /tmp/recovery.log"; }
remote() {
  local r; r=$(rpc '{"v":1,"id":"stock-mirror","op":"mirror","args":{"action":"start","port":8088}}')
  RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
  [ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; return 1; }
  a forward tcp:18088 tcp:8088 >/dev/null; REMOTE=http://127.0.0.1:18088; sleep 2
}
up() { for _ in $(seq 60); do rpc '{"v":1,"id":"stock-up","op":"status"}' | grep -q '"result"' && return 0; sleep 3; done; return 1; }
# Where two frames differ: changed pixel count and their bounding box.
diffbox() {
  python3 - "$OUT/$1.png" "$OUT/$2.png" "$here/../tools" <<'PY' 2>&1
import sys, os
sys.path.insert(0, sys.argv[3])
from png_read import read_png
w1, h1, a = read_png(sys.argv[1]); w2, h2, b = read_png(sys.argv[2])
if (w1, h1) != (w2, h2): print(f"sizes differ {w1}x{h1} {w2}x{h2}"); sys.exit()
xs, ys, n = [], [], 0
for y in range(h1):
    ra, rb = a[y], b[y]
    if ra == rb: continue
    for x in range(w1):
        if ra[x*3:x*3+3] != rb[x*3:x*3+3]:
            n += 1; xs.append(x); ys.append(y)
print(f"{n} px differ" + (f", box x {min(xs)}-{max(xs)} y {min(ys)}-{max(ys)}" if n else ""))
PY
}
here=$(cd "$(dirname "$0")" && pwd)

up || { log "AERA not answering"; exit 0; }
remote || exit 0
a shell 'pkill -f aera-fl[u]tter'
key_home() { curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" -d '{"key":"home"}' "$REMOTE/api/input/key" >/dev/null; }
key_home; sleep 3

# 1. Press and hold a card.
read -r fx fy <<< "${FILES_XY:-190 330}"
mark "press Files card $fx,$fy"
shot 1-home
touch_ down "$fx" "$fy"; sleep 1.2; shot 1-held
touch_ up "$fx" "$fy"; sleep 2; shot 1-after
log "held vs home: $(diffbox 1-home 1-held)"
key_home; sleep 3; shot 1-home-again

# 2. Mode transition to fastboot and back.
r0=$(a shell pidof recovery | tr -d '\r')
mark "transition fastboot"
log "transition fastboot: $(rpc '{"v":1,"id":"stock-tr","op":"transition","args":{"target":"fastboot"}}' | tr '\n' ' ')"
sleep 0.4; shot 2-during-1; shot 2-during-2; sleep 3; shot 2-fastboot
log "recovery pid $r0 -> $(a shell pidof recovery | tr -d '\r')"
mark "transition recovery"
log "transition recovery: $(rpc '{"v":1,"id":"stock-tr2","op":"transition","args":{"target":"recovery"}}' | tr '\n' ' ')"
sleep 0.4; shot 2-back-during; sleep 3; shot 2-recovery
log "after transitions: recovery pid $(a shell pidof recovery | tr -d '\r'), status $(rpc '{"v":1,"id":"stock-st","op":"status"}' | grep -c '"result"')"
# A UI that stopped drawing: busy (spinning) or asleep, and where its threads wait.
cpu=$(a shell 'p=$(pidof recovery); t0=$(cut -d" " -f14,15 /proc/$p/stat | tr " " +); sleep 2; t1=$(cut -d" " -f14,15 /proc/$p/stat | tr " " +); echo $(( (t1) - (t0) ))' | tr -d '\r')
log "recovery CPU over 2 s: $cpu ticks (200 = one core busy)"
a shell 'p=$(pidof recovery); for t in /proc/$p/task/*; do echo "$(cat $t/comm) $(cat $t/stat | cut -d" " -f3) $(cat $t/wchan)"; done' | tr -d '\r' > "$OUT/recovery-threads.txt" 2>&1
key_home; sleep 3

# 3. Power menu, Recovery: the power transition must reboot.
node=$(a shell 'grep -A5 "AERA Remote Input" /proc/bus/input/devices | sed -n "s/.*Handlers=.*\(event[0-9]*\).*/\1/p"' | tr -d '\r' | head -1)
python3 - "$OUT" <<'PY'
import struct, sys
ev = lambda t, c, v: struct.pack("<qqHHi", 0, 0, t, c, v)
open(sys.argv[1] + "/power-down.ev", "wb").write(ev(1, 116, 1) + ev(0, 0, 0))
open(sys.argv[1] + "/power-up.ev", "wb").write(ev(1, 116, 0) + ev(0, 0, 0))
PY
a push "$OUT/power-down.ev" "$OUT/power-up.ev" /tmp/ >/dev/null
[ -n "$node" ] || { log "no AERA Remote Input node"; exit 0; }
mark "power held on $node"
a shell "cat /tmp/power-down.ev > /dev/input/$node; sleep 3.5; cat /tmp/power-up.ev > /dev/input/$node"
sleep 1.5; shot 3-power-menu
read -r rx ry <<< "${RECOVERY_XY:-491 630}"
up0=$(a shell cut -d. -f1 /proc/uptime | tr -d '\r')
mark "tap Recovery $rx,$ry (uptime $up0)"
touch_ down "$rx" "$ry"; sleep 0.6; shot 3-recovery-held
touch_ up "$rx" "$ry"; sleep 0.8; shot 3-transition
a shell 'grep -nE "lab-stock-ui|eboot|ransition" /tmp/recovery.log | tail -30' | tr -d '\r' > "$OUT/recovery-tail.log" 2>&1
sleep 20
gone=0; a get-state >/dev/null 2>&1 || gone=1
a wait-for-device 2>/dev/null & w=$!; sleep 180; kill $w 2>/dev/null
up1=$(a shell cut -d. -f1 /proc/uptime 2>/dev/null | tr -d '\r')
if [ -n "$up1" ] && [ "$up1" -lt "$up0" ]; then log "REBOOTED (uptime $up0 -> $up1, adb gone at +20 s: $gone)"
else log "NOT REBOOTED (uptime $up0 -> ${up1:-none}, adb gone at +20 s: $gone)"; a shell 'tail -40 /tmp/recovery.log' > "$OUT/recovery-noreboot.log" 2>&1; shot 3-stuck; fi
rm -f "$OUT/.req.json" "$OUT"/*.ev
exit 0
