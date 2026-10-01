#!/usr/bin/env bash
# Put a KernelSU-family manager on a booted AVD (adb root) by loading the
# release's x86_64 LKM late with insmod, then running ksud's boot stages by
# hand. Installs the probe module and turns on WebView debugging.
# Usage: ksu.sh <kernelsu|next> [tag]     needs gh (GH_TOKEN) and adb.
set -uo pipefail
FLAVOR=${1:-kernelsu}; TAG=${2:-}
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT"; D=$(mktemp -d)
HERE=$(cd "$(dirname "$0")/.." && pwd)
case $FLAVOR in
  kernelsu) REPO=tiann/KernelSU; KO='lkm-x86_64-%s_kernelsu.ko'; APK='KernelSU_v*-release.apk'; PKG=me.weishu.kernelsu;;
  next) REPO=KernelSU-Next/KernelSU-Next; KO='x86_64-%s_kernelsu.ko'; APK='KernelSU_Next_v*_[0-9]*-release.apk'; PKG=com.rifsxd.ksunext;;
  *) echo "flavor?"; exit 2;;
esac
[ -n "$TAG" ] || TAG=$(gh release view -R "$REPO" --json tagName -q .tagName)
UNAME=$(adb shell uname -r | tr -d '\r')
KMI=$(echo "$UNAME" | sed -E 's/^([0-9]+\.[0-9]+)\.[0-9]+-(android[0-9]+).*/\2-\1/')
echo "kernel $UNAME -> kmi $KMI; $REPO $TAG"
gh release download -R "$REPO" "$TAG" -D "$D" -p "$(printf "$KO" "$KMI")" -p "$APK" -p 'ksud-x86_64-linux-android'
ls -la "$D"
log() { echo "== $*"; }

adb install -r "$D"/*.apk >/dev/null && log "manager installed ($PKG)"
adb push "$D"/*kernelsu.ko /data/local/tmp/kernelsu.ko >/dev/null
adb push "$D"/ksud-x86_64-linux-android /data/adb/ksud >/dev/null
adb shell chmod 755 /data/adb/ksud
log "ksud: $(adb shell /data/adb/ksud -V 2>&1 | tr -d '\r')"
adb shell /data/adb/ksud --help >"$OUT/ksud-help.txt" 2>&1
for c in late-load insmod boot-info profile debug feature module; do adb shell /data/adb/ksud $c --help >>"$OUT/ksud-help.txt" 2>&1; done
# Plain insmod can't resolve the SELinux internals the LKM uses (they are not
# exported). `ksud late-load` (no path argument; it picks the LKM for the
# running KMI) loads it with kallsyms access and runs the late-load stages:
# on 3.3.0 that gives "Working [Jailbreak mode]" / LKM in the manager.
# `ksud insmod <ko>` is the fallback with our downloaded LKM.
adb shell cp /data/local/tmp/kernelsu.ko /data/adb/kernelsu.ko
for try in "late-load" "insmod /data/adb/kernelsu.ko"; do
  log "ksud $try: $(adb shell /data/adb/ksud $try 2>&1 | tail -5 | tr -d '\r'; echo rc=$?)"
  adb shell "lsmod 2>/dev/null | grep -i kernelsu" && break
done
adb shell "dmesg | grep -i -E 'kernelsu|ksu' | tail -40" >"$OUT/ksu-dmesg.txt"
if ! adb shell "lsmod | grep -q kernelsu"; then
  for stage in post-fs-data services boot-completed; do
    log "ksud $stage: $(adb shell /data/adb/ksud $stage 2>&1 | tail -3 | tr -d '\r'; echo rc=$?)"
  done
fi
log "lsmod: $(adb shell lsmod | grep -i kernelsu | tr -d '\r')"

# Probe module, as if installed and rebooted (WebUI needs only the dir).
adb shell "mkdir -p /data/adb/modules/devicelab_probe" 
adb push "$HERE/modules/probe/." /data/adb/modules/devicelab_probe/ >/dev/null
adb shell "chmod -R 755 /data/adb/modules/devicelab_probe"
log "modules: $(adb shell /data/adb/ksud module list 2>&1 | tr -d '\r' | head -c 400)"

# WebView debugging switch, written where the manager keeps it, then launch.
adb shell am force-stop $PKG
PREFS=/data/data/$PKG/shared_prefs; UIDG=$(adb shell stat -c %u:%g /data/data/$PKG | tr -d '\r')
adb shell "mkdir -p $PREFS; cat > $PREFS/settings.xml <<'X'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map><boolean name=\"enable_web_debugging\" value=\"true\" /></map>
X
chown -R $UIDG $PREFS; restorecon -R $PREFS"
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 6
adb exec-out screencap -p >"$OUT/$FLAVOR-home.png"
adb shell uiautomator dump /data/local/tmp/ui.xml >/dev/null; adb shell cat /data/local/tmp/ui.xml >"$OUT/$FLAVOR-home.xml"
log "home text: $(grep -o 'text="[^"]\+"' "$OUT/$FLAVOR-home.xml" | head -20 | tr '\n' ' ')"
log "manager activities: $(adb shell dumpsys package $PKG | grep -o "$PKG/[A-Za-z0-9_.]*" | sort -u | tr '\n' ' ')"
