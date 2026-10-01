#!/usr/bin/env bash
# Put WebUI X Portable on an AVD that already runs KernelSU (managers/ksu.sh),
# grant it root through KernelSU, and record its first screens and
# activities. Usage: webuix.sh [tag]     needs gh (GH_TOKEN) and adb.
set -uo pipefail
TAG=${1:-}; REPO=MMRLApp/WebUI-X-Portable; PKG=com.dergoogler.mmrl.wx; KSU=me.weishu.kernelsu
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT"; D=$(mktemp -d)
HERE=$(cd "$(dirname "$0")/.." && pwd); UI="python3 $HERE/managers/ui.py"
log() { echo "== $*"; }
[ -n "$TAG" ] || TAG=$(gh release view -R "$REPO" --json tagName -q .tagName)
gh release view -R "$REPO" "$TAG" --json assets -q '.assets[].name' | tee "$OUT/webuix-assets.txt"
APK=$(grep -i -E '\.apk$' "$OUT/webuix-assets.txt" | grep -i -v -E 'debug|arm|x86' | head -1)
[ -n "$APK" ] || APK=$(grep -i -E '\.apk$' "$OUT/webuix-assets.txt" | head -1)
gh release download -R "$REPO" "$TAG" -D "$D" -p "$APK" && log "downloaded $REPO $TAG $APK"
adb install -r -g "$D/$APK" 2>&1 | tail -1
UID_=$(adb shell dumpsys package $PKG | sed -n 's/.*userId=\([0-9]*\).*/\1/p' | head -1 | tr -d '\r')
log "installed $PKG uid=$UID_ $(adb shell dumpsys package $PKG | grep -m1 versionName | tr -d '\r')"
log "activities: $(adb shell dumpsys package $PKG | grep -o "$PKG/[A-Za-z0-9_.]*" | sort -u | tr '\n' ' ')"

# Root grant: KernelSU's allowlist, through ksud if it can, else the manager's
# Superuser tab (tap the app, flip its Superuser switch).
adb shell /data/adb/ksud profile --help >"$OUT/ksud-profile-help.txt" 2>&1
granted=no
adb shell am force-stop $KSU; adb shell monkey -p $KSU -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 4
$UI tap Superuser; sleep 3; $UI dump "$OUT/webuix-ksu-superuser.xml" >/dev/null
adb exec-out screencap -p >"$OUT/webuix-ksu-superuser.png"
if $UI tap "WebUI X" || $UI tap "WebUI-X" || $UI tap "$PKG"; then
  sleep 3; $UI dump "$OUT/webuix-ksu-profile.xml"; adb exec-out screencap -p >"$OUT/webuix-ksu-profile.png"
  $UI tap Superuser && sleep 2 && granted=ui
  adb exec-out screencap -p >"$OUT/webuix-ksu-granted.png"
fi
log "root grant: $granted; su as app: $(adb shell "su $UID_ -c '/data/adb/ksu/bin/su -c id' 2>&1 || true" | tr -d '\r' | head -2)"
adb shell input keyevent KEYCODE_HOME

# First launch: walk through any onboarding, keep what it shows.
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 6
for i in 1 2 3 4; do
  adb exec-out screencap -p >"$OUT/webuix-start-$i.png"; $UI dump "$OUT/webuix-start-$i.xml" | head -20
  $UI tap Grant || $UI tap Allow || $UI tap Continue || $UI tap Next || $UI tap "Get started" || $UI tap OK || break
  sleep 3
done
log "devtools sockets: $(adb shell cat /proc/net/unix | grep -o '@[a-z_]*devtools_remote[0-9_]*' | tr '\n' ' ')"
