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
  # KernelSU 3.3.0 mounts module system/ only through a metamodule and its
  # release ships none, so this module overlays its own product/app at
  # post-fs-data, the way a metamodule (or Magisk) would.
  cat >"$D/post-fs-data.sh" <<'S'
#!/system/bin/sh
# Overlay first; when that fails (it did on the AVD, exit 255), Magisk's
# "magic mount": a tmpfs holding bind mounts of every original entry plus
# ours, bound over /product/app.
MODDIR=${0%/*}; L=/data/local/tmp/app-plane-mount.log
chcon -R u:object_r:system_file:s0 "$MODDIR/system"
if mount -t overlay overlay -o "lowerdir=$MODDIR/system/product/app:/product/app" /product/app 2>>$L; then
  echo "overlay ok" >>$L
else
  echo "overlay failed: $?" >>$L
  T=/dev/app_plane_app; mkdir -p $T
  mount -t tmpfs -o mode=755 tmpfs $T 2>>$L && chcon u:object_r:system_file:s0 $T
  for e in /product/app/*; do n=${e##*/}; mkdir $T/$n; mount --bind $e $T/$n 2>>$L; done
  mkdir $T/WebuiTermuxApi; mount --bind "$MODDIR/system/product/app/WebuiTermuxApi" $T/WebuiTermuxApi 2>>$L
  chcon u:object_r:system_file:s0 $T/*
  # rbind: a plain bind carries only the tmpfs, not the binds inside it
  # (that emptied every product app and crash-looped system_server).
  mount -o rbind $T /product/app 2>>$L && echo "magic mount ok" >>$L || echo "magic mount failed: $?" >>$L
fi
S
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
for i in $(seq 60); do [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break; sleep 2; done
rec mount "$(adb shell "cat /data/local/tmp/app-plane-mount.log 2>&1; ls -laZ /product/app/WebuiTermuxApi/ 2>&1; ls /product/app | head -5; grep -E 'product|modules|app_plane' /proc/mounts | grep -v '/dev/app_plane_app/' | head -8; grep -c ' /product/app/' /proc/mounts" | tr -d '\r' | js)"
rec package "$(adb shell "pm path $PKG; dumpsys package $PKG | grep -E 'codePath|flags=|privateFlags|versionName|userId' | head -8" | tr -d '\r' | js)"
UID_=$(adb shell "dumpsys package $PKG | grep -m1 -o 'userId=[0-9]*' | cut -d= -f2" | tr -d '\r')
UID_=${UID_:-$(adb shell "stat -c %u /data/data/$PKG 2>/dev/null" | tr -d '\r')}
# adb-root listener (u:r:su) next to the module's one.
adb push "$SOCKPROBE" /data/local/tmp/sockprobe >/dev/null
adb shell "chmod 755 /data/local/tmp/sockprobe; (nohup /data/local/tmp/sockprobe -t 300 wx_su_out wx_su_in >/data/local/tmp/sockprobe-su.log 2>&1 &)"
sleep 1
adb logcat -c
# Extras as termux-api-package's exec_am_broadcast_v2 sends them (what
# webui-packages' Dart port sends): the listening process's pid/uid/starttime.
for side in ksu su; do
  case $side in ksu) log=sockprobe-module;; su) log=sockprobe-su;; esac
  P=$(adb shell "pgrep -f 'sockprobe.*wx_${side}_out' | head -1" | tr -d '\r')
  ST=$(adb shell "cut -d' ' -f22 /proc/$P/stat 2>/dev/null" | tr -d '\r')
  adb shell am broadcast --user 0 -f 0x01000020 -n $PKG/com.termux.api.TermuxApiReceiver \
    --es socket_output wx_${side}_out --es socket_input wx_${side}_in \
    --ei api_server_pid "${P:-0}" --ei api_server_uid 0 --ei api_server_starttime "${ST:-0}" \
    --es api_method BatteryStatus 2>&1 | tr -d '\r' | tee "$OUT/app-plane-broadcast-$side.txt"
  sleep 8
done
rec broadcast "$(cat "$OUT"/app-plane-broadcast-*.txt | js)"
rec app-process "$(adb shell "ps -A -o USER,UID,LABEL,NAME | grep -i termux" | tr -d '\r' | js)"
rec listener-module "$(adb shell cat /data/local/tmp/sockprobe-module.log 2>&1 | tr -d '\r' | js)"
rec listener-su "$(adb shell cat /data/local/tmp/sockprobe-su.log 2>&1 | tr -d '\r' | js)"
rec avc "$(adb shell "dmesg | grep -i 'avc' | grep -i -E 'termux|$PKG|connectto|unix_stream' | tail -15; logcat -d | grep -i -E 'avc:.*(connectto|unix_stream)|TermuxApi|termux' | tail -25" | tr -d '\r' | js)"
# restorecon in the app's data dir: a file written by root gets the app's MLS categories?
adb shell "mkdir -p /data/data/$PKG/files/devicelab; echo x >/data/data/$PKG/files/devicelab/probe.txt; chown -R $UID_:$UID_ /data/data/$PKG/files/devicelab; restorecon -R /data/data/$PKG/files/devicelab"
rec restorecon "$(adb shell "ls -Zd /data/data/$PKG /data/data/$PKG/files/devicelab/probe.txt" | tr -d '\r' | js)"
# What the app itself can read and write: a file labelled as webui-packages'
# writeAppFile does (the data dir's full context via chcon) next to the
# restorecon'd one (s0, no categories), opened as the app's uid and context.
D=/data/data/$PKG/files/devicelab
CTX=$(adb shell "stat -c %C /data/data/$PKG" | tr -d '\r')
adb shell "echo chcon >$D/chcon.txt; chown $UID_:$UID_ $D/chcon.txt; chcon $CTX $D/chcon.txt; chcon $CTX $D"
APPCTX=$(adb shell "ps -A -o LABEL,NAME | grep -m1 ' $PKG\$' | cut -d' ' -f1" | tr -d '\r')
APPCTX=${APPCTX:-$(echo "$CTX" | sed 's/object_r:app_data_file/r:untrusted_app_27/')}
rec app-read "$(adb shell "ls -Z $D; for f in probe.txt chcon.txt; do echo \"read \$f:\"; /data/local/tmp/sockprobe -as-uid $UID_ -as-ctx $APPCTX /system/bin/cat $D/\$f 2>&1; done; echo 'write:'; /data/local/tmp/sockprobe -as-uid $UID_ -as-ctx $APPCTX /system/bin/sh -c 'echo w >>$D/chcon.txt && echo ok; echo w >>$D/probe.txt && echo ok' 2>&1; dmesg | grep avc | grep -E 'chcon.txt|probe.txt|sockprobe' | tail -5" | tr -d '\r' | js)"
# Share end to end, as webui_app_plane runs it: text on stdin, then a file.
share() { # <tag> <stdin text> <extras...>
  local tag=$1 in=$2; shift 2
  adb shell "(nohup /data/local/tmp/sockprobe -t 60 -reply '$in' sh_${tag}_out sh_${tag}_in >/data/local/tmp/sockprobe-share-$tag.log 2>&1 &)"; sleep 1
  local P=$(adb shell "pgrep -f 'sockprobe.*sh_${tag}_out' | head -1" | tr -d '\r')
  adb logcat -c
  adb shell am broadcast --user 0 -f 0x01000020 -n $PKG/com.termux.api.TermuxApiReceiver \
    --es socket_output sh_${tag}_out --es socket_input sh_${tag}_in --ei api_server_pid "${P:-0}" --ei api_server_uid 0 \
    --ei api_server_starttime "$(adb shell "cut -d' ' -f22 /proc/$P/stat" | tr -d '\r')" --es api_method Share "$@" >/dev/null 2>&1
  sleep 12
  rec share-$tag "$(adb shell "dumpsys activity activities | grep -m1 -E 'topResumedActivity'; cat /data/local/tmp/sockprobe-share-$tag.log; logcat -d | grep -i -E 'termux|share|chooser|FileNotFound|denied|avc' | grep -v -E 'Broadcasting|Enqueued' | tail -12" | tr -d '\r' | js)"
  timeout 20 adb exec-out screencap -p >"$OUT/app-plane-share-$tag.png"
  adb shell input keyevent KEYCODE_BACK; sleep 2
}
share text "hello from devicelab" --es action send --es title devicelab
share file "" --es action send --es file $D/chcon.txt --es content-type text/plain
echo "app uid: $UID_"
