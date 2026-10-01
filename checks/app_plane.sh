#!/usr/bin/env bash
# App-plane checks for the webui-termux-api APK (package com.webui.termux.api)
# on a KernelSU AVD:
#   1. it installs as a system app from a module overlay
#      (system/product/app/WebuiTermuxApi/) and is visible after the (soft) reboot;
#   2. a root `am broadcast` to its TermuxApiReceiver reaches it;
#   3. SELinux lets the app connect back to a root-owned abstract socket:
#      one listener started by the module's service.sh (KernelSU's module
#      context), one by adb root (u:r:su), both via tools/sockprobe.
# Usage: app_plane.sh build <apk> <sockprobe> <out.zip>   (before install_modules.sh)
#        app_plane.sh run                                   (after the soft-reboot)
set -uo pipefail
OUT=${LAB_OUT:-$PWD/out}; PKG=com.webui.termux.api; ID=devicelab_app_plane
J=$OUT/app-plane.jsonl
rec() { echo "{\"check\":\"$1\",\"result\":$2}" | tee -a "$J"; }
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
if [ "${1:-}" = build ]; then
  D=$(mktemp -d); mkdir -p "$D/system/product/app/WebuiTermuxApi"
  cp "$2" "$D/system/product/app/WebuiTermuxApi/WebuiTermuxApi.apk"; cp "$3" "$D/sockprobe"
  printf 'id=%s\nname=devicelab app plane\nversion=1\nversionCode=1\nauthor=p0g-stack\ndescription=webui-termux-api as a system app, plus a root socket listener\n' $ID >"$D/module.prop"
  cat >"$D/service.sh" <<'S'
#!/system/bin/sh
MODDIR=${0%/*}
chmod 755 "$MODDIR/sockprobe"
"$MODDIR/sockprobe" -t 900 -reply '' wx_ksu_out wx_ksu_in >/data/local/tmp/sockprobe-module.log 2>&1 &
S
  mkdir -p "$D/META-INF/com/google/android"; echo '#MAGISK' >"$D/META-INF/com/google/android/updater-script"
  printf '#!/sbin/sh\n' >"$D/META-INF/com/google/android/update-binary"
  (cd "$D" && zip -qr "$4" .) && echo "built $4"; exit 0
fi

: >"$J"
rec mount "$(adb shell "ls -la /product/app/WebuiTermuxApi/ 2>&1; grep -E 'product|modules' /proc/mounts | head -5" | tr -d '\r' | js)"
rec package "$(adb shell "pm path $PKG; dumpsys package $PKG | grep -E 'codePath|flags=|privateFlags|versionName|userId' | head -8" | tr -d '\r' | js)"
UID_=$(adb shell "stat -c %u /data/data/$PKG 2>/dev/null" | tr -d '\r')
# adb-root listener (u:r:su) next to the module's one.
adb push "$SOCKPROBE" /data/local/tmp/sockprobe >/dev/null
adb shell "chmod 755 /data/local/tmp/sockprobe; (nohup /data/local/tmp/sockprobe -t 300 wx_su_out wx_su_in >/data/local/tmp/sockprobe-su.log 2>&1 &)"
sleep 1
adb logcat -c
for side in ksu su; do
  adb shell am broadcast -f 0x01000020 -n $PKG/com.termux.api.TermuxApiReceiver \
    --es socket_output wx_${side}_out --es socket_input wx_${side}_in --es api_method BatteryStatus 2>&1 | tr -d '\r' | tee "$OUT/app-plane-broadcast-$side.txt"
  sleep 8
done
rec broadcast "$(cat "$OUT"/app-plane-broadcast-*.txt | js)"
rec app-process "$(adb shell "ps -A -o USER,UID,LABEL,NAME | grep -i termux" | tr -d '\r' | js)"
rec listener-module "$(adb shell cat /data/local/tmp/sockprobe-module.log 2>&1 | tr -d '\r' | js)"
rec listener-su "$(adb shell cat /data/local/tmp/sockprobe-su.log 2>&1 | tr -d '\r' | js)"
rec avc "$(adb shell "dmesg | grep -i 'avc' | grep -i -E 'termux|$PKG|connectto|unix_stream' | tail -15; logcat -d | grep -i -E 'avc:.*(connectto|unix_stream)|TermuxApi|termux' | tail -25" | tr -d '\r' | js)"
echo "app uid: $UID_"
