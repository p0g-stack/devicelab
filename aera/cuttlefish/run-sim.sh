#!/usr/bin/env bash
# Run a Flutter payload through flutter-aera's host simulator *inside* the
# Cuttlefish recovery: memfd frames + SEQPACKET control on fds 3/4, scripted
# taps, frames written as PNG on the device and pulled back. No AERA and no
# scanout yet: proves the kit (static launcher, glibc loader, Mesa) runs as
# root in a bionic recovery ramdisk on this kernel.
# Usage: run-sim.sh <label> <payload-dir> <aera-host-sim> [sim args...]
set -uo pipefail
LABEL=$1 PAYLOAD=$2 SIM=$3; shift 3
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT/$LABEL"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
D=${DEVICE_DIR:-/tmp/aera-lab}
a shell "rm -rf $D; mkdir -p $D/root $D/out"
tar -C "$PAYLOAD" -czf "$OUT/$LABEL/payload.tgz" .
t0=$SECONDS
a push "$OUT/$LABEL/payload.tgz" "$D/" >/dev/null && a push "$SIM" "$D/aera-host-sim" >/dev/null
a shell "cd $D/root && tar -xzf ../payload.tgz && chmod 755 ../aera-host-sim usr/bin/*" || exit 1
rm "$OUT/$LABEL/payload.tgz"
echo "[sim] pushed in $((SECONDS - t0))s; $(a shell "du -sh $D/root" | tr -d '\r')"
t0=$SECONDS
a shell "cd $D && ./aera-host-sim --root $D/root --embedder $D/root/usr/bin/aera-plugin --out $D/out $*" \
  >"$OUT/$LABEL/sim.log" 2>&1; rc=$?
echo "[sim] exit $rc after $((SECONDS - t0))s"; tail -25 "$OUT/$LABEL/sim.log"
a pull "$D/out" "$OUT/$LABEL/" >/dev/null 2>&1
ls -la "$OUT/$LABEL/out" 2>/dev/null
exit $rc
