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
UID_=$(adb shell stat -c %u /data/data/$PKG | tr -d '\r')
log "installed $PKG uid=$UID_ $(adb shell dumpsys package $PKG | grep -m1 versionName | tr -d '\r')"
log "activities: $(adb shell dumpsys package $PKG | grep -o "$PKG/[A-Za-z0-9_.]*" | sort -u | tr '\n' ' ')"

# Root grant: KernelSU's allowlist, through ksud if it can, else the manager's
# Superuser tab (tap the app, flip its Superuser switch).
adb shell /data/adb/ksud profile --help >"$OUT/ksud-profile-help.txt" 2>&1
granted=no
adb shell am force-stop $KSU; adb shell monkey -p $KSU -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 4
UI_EXACT=1 UI_WAIT=30 $UI tap Superuser; sleep 8
adb exec-out screencap -p >"$OUT/webuix-ksu-superuser.png"
# The Superuser list exposes no nodes either: search, tap the first row.
$UI tapxy 160 152; sleep 3; $UI type "WebUI X"; sleep 4
if $UI tap "$PKG"; then
  sleep 3; $UI dump "$OUT/webuix-ksu-profile.xml"; adb exec-out screencap -p >"$OUT/webuix-ksu-profile.png"
  # The App Profile screen: its first switch is Superuser.
  $UI switch 1 && sleep 2 && granted=ui
  adb exec-out screencap -p >"$OUT/webuix-ksu-granted.png"; $UI dump "$OUT/webuix-ksu-granted.xml" >/dev/null
fi
log "root grant: $granted; su as app uid $UID_: $(adb shell "su $UID_ /system/bin/su -c id 2>&1 || true" | tr -d '\r' | head -2)"
adb shell input keyevent KEYCODE_HOME

# First launch: walk through any onboarding, keep what it shows.
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 6
# Onboarding (v438): "Select your Platform" list, then Next / Continue.
export UI_EXACT=1
UI_WAIT=20 $UI tap KernelSU && sleep 1
for i in 1 2 3 4 5; do
  adb exec-out screencap -p >"$OUT/webuix-start-$i.png"; $UI dump "$OUT/webuix-start-$i.xml" | head -20
  hit=no
  for b in Next Continue Grant Allow "Get started" Done OK Finish; do UI_WAIT=1 $UI tap "$b" && { hit=yes; break; }; done
  [ $hit = yes ] || { $UI scroll; sleep 2; }
  sleep 2
  UI_WAIT=2 $UI has "Select your Platform" || [ $i -lt 3 ] || break
done
unset UI_EXACT
log "WebUI X platform after onboarding: $(adb shell "ls /data/data/$PKG/files/datastore/ 2>/dev/null; strings /data/data/$PKG/files/datastore/*.pb 2>/dev/null | head -20" | tr -d '\r' | tr '\n' ' ')"
log "devtools sockets: $(adb shell cat /proc/net/unix | grep -o '@[a-z_]*devtools_remote[0-9_]*' | tr '\n' ' ')"
