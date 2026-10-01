#!/usr/bin/env bash
# Start AERA's recovery by hand until it links: each "library X not found"
# is filled from Android's /system/lib64 (saved by boot-aera.sh) and logged
# to $LAB_OUT/aera-missing-libs.txt, then init's recovery service restarts.
OUT=${LAB_OUT:-$PWD/out}; CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[aera-libs] $*"; }
: > "$OUT/aera-missing-libs.txt"
a shell 'stop recovery' >/dev/null 2>&1
for _ in $(seq 20); do
  msg=$(a shell 'cd /; timeout 5 /system/bin/recovery 2>&1 | grep -m1 "CANNOT LINK"' | tr -d '\r')
  lib=$(echo "$msg" | sed -n 's/.*library "\([^"]*\)" not found.*/\1/p')
  [ -n "$lib" ] || { [ -n "$msg" ] && log "unresolved: $msg"; break; }
  echo "$msg" >> "$OUT/aera-missing-libs.txt"
  if [ -f "$CF_HOME/android-lib64/$lib" ]; then
    a push "$CF_HOME/android-lib64/$lib" /system/lib64/ >/dev/null && log "missing $lib: pushed Android's copy"
  else
    log "missing $lib: not in Android's /system/lib64 either"; break
  fi
done
a shell 'killall recovery 2>/dev/null; start recovery'
sleep 10
log "init.svc.recovery=$(a shell getprop init.svc.recovery | tr -d '\r'); $(wc -l < "$OUT/aera-missing-libs.txt") libraries filled in"
a shell 'tail -30 /tmp/recovery.log 2>/dev/null' > "$OUT/aera-recovery-log-tail.txt"
tail -15 "$OUT/aera-recovery-log-tail.txt"
exit 0
