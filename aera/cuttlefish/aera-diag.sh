#!/usr/bin/env bash
# Why AERA's recovery service is (not) running: its own log, a manual
# foreground start with stderr, linker and init facts.
# Usage: aera-diag.sh  ->  $LAB_OUT/aera-diag.txt
OUT=${LAB_OUT:-$PWD/out}; CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
{
for c in 'getprop init.svc.recovery' 'getprop | grep -E "ro.build.version.(sdk|release)|ro.twrp|aera|ro.boot.mode|bootmode"' \
         'ls -la /tmp /tmp/recovery.log 2>&1' 'tail -80 /tmp/recovery.log 2>&1' \
         'grep -rn -A8 "service recovery" /init.rc /system/etc/init/hw/init.rc /*.rc 2>/dev/null | head -40' \
         'file /system/bin/recovery 2>&1; ls -la /system/bin/recovery' \
         'readelf -d /system/bin/recovery 2>/dev/null | grep NEEDED' \
         'ls /system/lib64 | head -100; ls /system/lib64 | wc -l' \
         'ls -la /twres /twres/fonts 2>&1 | head -20' \
         'ls -la /etc /system/etc/task_profiles.json /etc/task_profiles.json 2>&1 | head -20' \
         'stop recovery; sleep 1; cd /; (timeout 15 /system/bin/recovery; echo "exit $?") 2>&1 | tail -60' \
         'tail -60 /tmp/recovery.log 2>&1' \
         'logcat -d 2>/dev/null | tail -80' \
         'dmesg | grep -iE "recovery|aera|twrp|linker|CANNOT|avc" | tail -60'; do
  echo "\$ $c"; a shell "$c" 2>&1; echo
done
} > "$OUT/aera-diag.txt"
grep -n -A30 "timeout 15" "$OUT/aera-diag.txt" | head -50
exit 0
