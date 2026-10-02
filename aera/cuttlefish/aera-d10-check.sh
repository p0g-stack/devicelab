#!/usr/bin/env bash
# D10: AERA crashed (SIGSEGV) when a paused pixel plugin was reopened from
# its Recents card. With the kernel's exception trace on, run three cases and
# record the segfault line (fault address, ip, mapping) for addr2line:
#   A  probe left by the bottom-edge swipe (preview captured), Menu, card
#   B  probe never left: Menu from inside it, card (no preview yet)
# Usage: aera-d10-check.sh PKG.aerap  ->  $LAB_OUT/aera-d10/
# Env: RECENTS_CARD x,y of the first card (default 360,790)
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-d10; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[d10] $*" | tee -a "$OUT/log.txt"; }
shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 1; a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && log "frame $1.png" || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
remote() {
  local r; r=$(rpc '{"v":1,"id":"d10-mirror","op":"mirror","args":{"action":"start","port":8088}}')
  RCODE=$(echo "$r" | sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' | head -1)
  [ -n "$RCODE" ] || { log "AERA Remote did not start: $r"; return 1; }
  a forward tcp:18088 tcp:8088 >/dev/null; REMOTE=http://127.0.0.1:18088; sleep 2
}
post() { curl -s -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" -d "$2" "$REMOTE$1"; }
touch_() { post /api/input/touch "{\"action\":\"$1\",\"x\":$2,\"y\":$3}" >/dev/null; }
tap() { touch_ down "$1" "$2"; sleep 0.1; touch_ up "$1" "$2"; log "tap $1,$2"; }
key() { post /api/input/key "{\"key\":\"$1\"}" >/dev/null; log "key $1"; }
swipe_home() {
  local i; touch_ down 360 1340
  for i in 1 2 3 4 5 6; do touch_ move 360 $(( 1340 - 50 * i )); sleep 0.03; done
  touch_ up 360 1040; log "edge swipe Home"
}
rec_pid() { a shell 'pidof recovery' 2>/dev/null | tr -d '\r'; }
# Exception trace printed nothing in run 36949565316 (recovery's own SIGSEGV
# handler re-raises), so let the running recovery dump core instead.
arm_core() { a shell "echo /tmp/core.%e.%p > /proc/sys/kernel/core_pattern; ulimit -P \$(pidof recovery) -c unlimited 2>&1; ulimit -P \$(pidof recovery) -c" | tr -d '\r' | sed 's/^/[d10] core limit: /' | tee -a "$OUT/log.txt"; }
open_() { log "open $1: $(rpc '{"v":1,"id":"d10","op":"plugin","args":{"action":"open","id":"'"$1"'"}}' | tr '\n' ' ')"; }
# After a case: did recovery survive? Keep the kernel's segfault lines.
verdict() {
  local before=$1 name=$2 after
  for _ in $(seq 20); do a shell true >/dev/null 2>&1 && break; sleep 2; done
  after=$(rec_pid)
  if [ "$before" = "$after" ]; then log "$name: AERA survived (recovery pid $after)"
  else
    log "$name: AERA RESTARTED (recovery pid $before -> $after)"
    a shell 'dmesg | grep -E "segfault|traps:|recovery\[|signal 11|Service .recovery" | tail -8' | tr -d '\r' | tee -a "$OUT/segfault.txt" | sed 's/^/[d10]   /' | tee -a "$OUT/log.txt"
    a shell 'ls -l /tmp/core.* 2>&1' | tr -d '\r' | sed 's/^/[d10]   /' | tee -a "$OUT/log.txt"
    for c in $(a shell 'ls /tmp/core.* 2>/dev/null' | tr -d '\r'); do a pull "$c" "$OUT/$name-${c##*/}" >/dev/null 2>&1 && a shell "rm -f $c"; done
    sleep 8; remote || true
  fi
}
install() {  # install DIR-with-plugin.json-and-runtime.xz ID
  a shell "mkdir -p /tmp/aera/plugins/$2 && chmod 700 /tmp/aera /tmp/aera/plugins"
  a push "$1/plugin.json" "$1/runtime.xz" "/tmp/aera/plugins/$2/" >/dev/null && log "installed $2"
}

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"; install "$OUT/.pkg" "$id"
a shell 'echo 1 > /proc/sys/debug/exception-trace; cat /proc/sys/debug/exception-trace' | tr -d '\r' | sed 's/^/[d10] exception-trace=/' | tee -a "$OUT/log.txt"
remote || exit 0
card=${RECENTS_CARD:-360,790}

log "== A: left by the edge swipe, reopened from its card"
a shell 'pkill -f aera-flutter; sleep 2'; p=$(rec_pid); arm_core
open_ "$id"; sleep "${APP_WAIT:-25}"; shot A1-app
swipe_home; sleep 3; key menu; sleep 3; shot A2-recents
tap "${card%,*}" "${card#*,}"; sleep 5; shot A3-after-card
verdict "$p" A

log "== B: never left, Menu from inside the app, its card"
a shell 'pkill -f aera-flutter; sleep 2'; p=$(rec_pid); arm_core
open_ "$id"; sleep "${APP_WAIT:-25}"; shot B1-app
key menu; sleep 3; shot B2-recents
tap "$(( ${card%,*} + 1 ))" "$(( ${card#*,} + 1 ))"; sleep 5; shot B3-after-card
verdict "$p" B

# C (AERA Browser) dropped: RPC plugin open refuses browser-runtime plugins
# ("not an installed Host API 2 or 3 plugin", run 36949565316).

a shell 'pkill -f aera-flutter; dmesg | grep -E "segfault|traps:" | tail -10' | tr -d '\r' > "$OUT/dmesg-segfault.txt"
rm -rf "$OUT/.pkg" "$OUT/.req.json"
exit 0
