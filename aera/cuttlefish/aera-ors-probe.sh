#!/usr/bin/env bash
# Read-only probe: are AERA's status-bar metrics readable as TWRP data
# variables over the OpenRecoveryScript channel (/system/bin/orsin|orsout,
# the `twrp` command), as root and from a running pixel plugin's process?
# Usage: aera-ors-probe.sh COUNTER.aerap  ->  $LAB_OUT/aera-ors/log.txt
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-ors; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[ors] $*" | tee -a "$OUT/log.txt"; }
sh_() { log "\$ $1"; a shell "$1" 2>&1 | tr -d '\r' | sed 's/^/    /' | tee -a "$OUT/log.txt"; }
VARS="status_h status_indent_left status_indent_right status_placement screen_h tw_version"
sh_ 'id; which twrp; ls -lZ /system/bin/orsin /system/bin/orsout /system/bin/twrp 2>&1'
for v in $VARS; do sh_ "timeout 10 twrp get $v"; done
for v in status_h status_indent_left status_indent_right; do sh_ "timeout 10 twrp getval $v"; done
sh_ 'timeout 10 twrp get'   # no variable: what it lists or says
# Without the twrp binary: write the command to orsin, read orsout.
sh_ '{ timeout 10 cat /system/bin/orsout & sleep 0.3; echo "get status_indent_left" > /system/bin/orsin; wait; } 2>&1'

# From the plugin's side: its uid, mount namespace and whether the FIFOs and
# the twrp binary are visible and writable there.
id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
echo '{"v":1,"id":"ors","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
a shell 'pkill -f aera-fl[u]tter; sleep 2; { timeout 30 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' >/dev/null 2>&1
sleep "${APP_WAIT:-25}"
pid=$(a shell 'for p in /proc/[0-9]*; do grep -qa "aera-host-ap[i]" $p/cmdline 2>/dev/null && echo ${p#/proc/}; done' | tr -d '\r' | sort -n | head -1)
log "plugin pid: ${pid:-none}"
if [ -n "$pid" ]; then
  sh_ "grep -E '^(Uid|Gid|Groups|CapEff|NoNewPrivs|Seccomp):' /proc/$pid/status; cat /proc/$pid/attr/current; echo; readlink /proc/$pid/ns/mnt /proc/1/ns/mnt"
  sh_ "ls -lZ /proc/$pid/root/system/bin/orsin /proc/$pid/root/system/bin/orsout /proc/$pid/root/system/bin/twrp 2>&1"
  sh_ "nsenter -t $pid -m -- sh -c 'ls -l /system/bin/orsin; timeout 10 twrp getval status_h' 2>&1"
fi
a shell 'pkill -f aera-fl[u]tter'
rm -rf "$OUT/.pkg" "$OUT/.req.json"
exit 0
