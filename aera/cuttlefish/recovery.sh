#!/usr/bin/env bash
# Reboot the running Cuttlefish into its recovery and record what a plugin
# host there would see: kernel, DRM/input nodes, mounts, processes, a frame.
# Usage: recovery.sh <label>     (after up.sh; writes $LAB_OUT/<label>-*)
set -uo pipefail
LABEL=${1:-recovery}
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
S=0.0.0.0:6520
a() { $ADB -s $S "$@"; }

if [ "$(a get-state 2>/dev/null)" != recovery ]; then
  a reboot recovery || true
  t0=$SECONDS
  until [ "$(a get-state 2>/dev/null)" = recovery ]; do
    (( SECONDS - t0 > 300 )) && { echo "[cf] no recovery adb after 300s"; break; }
    $ADB connect $S >/dev/null 2>&1; sleep 3
  done
  echo "[cf] state $(a get-state 2>&1) after $((SECONDS - t0))s"
fi
sleep 5
f=$OUT/$LABEL-facts.txt
for c in 'id' 'uname -a' 'getprop ro.build.fingerprint' 'getprop ro.bootmode' 'cat /proc/cmdline' \
         'ls -la /' 'ls -la /dev/dri /dev/input /dev/graphics' 'cat /proc/mounts' 'ps -A' \
         'ls /system/bin' 'ls /system/lib64 | head -80' 'cat /proc/meminfo | head -3' 'nproc' \
         'cat /sys/kernel/debug/dri/0/clients /sys/kernel/debug/dri/0/name 2>&1' \
         'cat /sys/class/drm/card0-*/modes 2>&1' 'getevent -pl 2>&1 | head -60' \
         'cat /system/etc/init/hw/init.rc 2>/dev/null | grep -n -A3 "service recovery"' \
         'ls /*.rc /system/etc/init 2>&1' 'getenforce' 'getprop' 'cat /proc/sys/kernel/osrelease' \
         'ls /lib/modules 2>&1 | head; lsmod 2>&1 | head -40'; do
  printf '\n$ %s\n' "$c" >>"$f"; timeout 20 $ADB -s $S shell "$c" >>"$f" 2>&1
done
echo "[cf] facts: $(wc -l <"$f") lines -> $f"
aera_dir=$(cd "$(dirname "$0")" && pwd); "$aera_dir/shot.sh" "$OUT/$LABEL.png"
