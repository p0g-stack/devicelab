#!/usr/bin/env bash
# Install module zips through the manager's own installer (ksud module
# install), then emulate a reboot with ksud soft-reboot so post-fs-data and
# service stages run the way they do after a real reboot (a real reboot
# would drop the late-loaded LKM).
# Usage: install_modules.sh <zip>...
set -uo pipefail
OUT=${LAB_OUT:-$PWD/out}
for z in "$@"; do
  adb push "$z" /data/local/tmp/m.zip >/dev/null
  echo "== install $(basename "$z")"
  adb shell /data/adb/ksud module install /data/local/tmp/m.zip 2>&1 | tr -d '\r' | tail -15
done
[ $# -gt 0 ] || exit 0
echo "== soft-reboot: $(adb shell /data/adb/ksud soft-reboot 2>&1 | tail -3 | tr -d '\r')"
sleep 5; timeout 120 adb wait-for-device
t0=$SECONDS
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && adb shell pidof system_server >/dev/null; do
  (( SECONDS - t0 > 300 )) && { echo "no boot_completed after soft-reboot"; break; }; sleep 3
done
echo "== after soft-reboot ($((SECONDS - t0))s): $(adb shell /data/adb/ksud module list 2>&1 | tr -d '\r' | head -c 1500)"
adb shell "ls -la /data/adb/modules/" | tr -d '\r'
