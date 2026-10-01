#!/usr/bin/env bash
# State of AERA's recovery without disturbing it: its full log, display and
# capture facts, whether logd stays up, the kernel's DRM plane state. Only when the service is not running
# does it start the binary by hand (to see a link error).
# Usage: aera-diag.sh  ->  $LAB_OUT/aera-diag.txt, $LAB_OUT/aera-recovery.log
OUT=${LAB_OUT:-$PWD/out}; CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
sleep 20
state=$(a shell getprop init.svc.recovery | tr -d '\r')
{
echo "init.svc.recovery=$state"
for c in 'getprop | grep -E "aera|ro.boot.mode|bootmode|sys.usb"' 'ps -A -o PID,PPID,S,NAME,ARGS | grep -vE " \[|ps -A"' \
         'ls -la /tmp' 'ls -la /dev/dri /dev/graphics /sys/class/drm 2>&1' \
         'cat /sys/class/drm/card0-*/modes /sys/class/drm/card0-*/status 2>&1' \
         'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture; sleep 3; ls -la /tmp/aeraui-capture /tmp/aeraui.png 2>&1' \
         'getprop init.svc.logd; pidof logd; logcat -d -t 5 2>&1 | tail -5' \
         'grep -c "Atomic commit failed" /tmp/recovery.log; grep -E "SDE topology|Atomic Commit" /tmp/recovery.log | head -5' \
         'mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug; cat /sys/kernel/debug/dri/0/state 2>&1 | head -60' \
         'ls -la /system/etc/task_profiles* /system/etc/cgroups.json 2>&1' \
         'dmesg | grep -iE "drm|virtio_gpu|recovery|aera|CANNOT|avc" | tail -40'; do
  echo "\$ $c"; a shell "$c" 2>&1; echo
done
if [ "$state" != running ]; then
  echo '$ /system/bin/recovery (by hand, service not running)'
  a shell 'cd /; timeout 15 /system/bin/recovery 2>&1 | tail -40; echo "exit $?"'
fi
} > "$OUT/aera-diag.txt"
a pull /tmp/recovery.log "$OUT/aera-recovery.log" >/dev/null 2>&1
grep -nE "DRM|drm|setting DRM_FORMAT|Atomic|crtc|connector|plane|fbdev|graphics|minui|LVGL|lvgl|aeraui|E:|error" "$OUT/aera-recovery.log" 2>/dev/null | awk '!seen[$0]++' | head -40
grep -A3 "aeraui-capture\|init.svc.logd\|Atomic commit failed" "$OUT/aera-diag.txt" | head -16
grep -A14 "dri/0/state" "$OUT/aera-diag.txt" | head -30
exit 0
