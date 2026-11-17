#!/usr/bin/env bash
# Put the current official WebUI X on an AVD that runs KernelSU.
# Usage: webuix.sh     needs gh (GH_TOKEN) and adb.
# Release identity is committed in managers/webuix-apks.sha256.
set -uo pipefail
TAG=v660; REPO=MMRLApp/WebUI-X-Portable; PKG=com.dergoogler.mmrl.wx
# v660 ships two launcher activities: MainActivity and WX Explorer. `monkey -c
# LAUNCHER` picks one at random, and when Explorer is under MainActivity the
# setup screen finishes onto a file browser with no bottom navigation.
MAIN=$PKG/com.dergoogler.mmrl.wx.ui.activity.MainActivity
case ${FLAVOR:-kernelsu} in next) KSU=com.rifsxd.ksunext;; *) KSU=me.weishu.kernelsu;; esac
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT"; D=$(mktemp -d)
HERE=$(cd "$(dirname "$0")/.." && pwd); UI="python3 $HERE/managers/ui.py"
log() { echo "== $*"; }
APK=WebUI-X-v660-release-official.apk
gh release download -R "$REPO" "$TAG" -D "$D" -p "$APK" || exit 1
(cd "$D" && sha256sum -c "$HERE/managers/webuix-apks.sha256") || exit 1
log "downloaded $REPO $TAG $APK (sha256 verified)"
adb install -r -g "$D/$APK" 2>&1 | tail -1
UID_=$(adb shell stat -c %u /data/data/$PKG | tr -d '\r')
log "installed $PKG uid=$UID_ $(adb shell dumpsys package $PKG | grep -m1 versionName | tr -d '\r')"
log "activities: $(adb shell dumpsys package $PKG | grep -o "$PKG/[A-Za-z0-9_.]*" | sort -u | tr '\n' ' ')"

# Root grant: KernelSU's allowlist, through ksud if it can, else the manager's
# Superuser tab (tap the app, flip its Superuser switch).
adb shell /data/adb/ksud profile --help >"$OUT/ksud-profile-help.txt" 2>&1
granted=no
# The grant walks the manager UI; a busy AVD can throw ANR dialogs over it
# (seen 2026-10-05), so retry from a fresh manager start.
for attempt in 1 2 3; do
  adb shell am force-stop $KSU; adb shell monkey -p $KSU -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 4
  UI_EXACT=1 UI_WAIT=30 $UI tap Superuser; sleep 8
  adb exec-out screencap -p >"$OUT/webuix-ksu-superuser.png"
  # The list may expose its rows directly; if not, search (retyping when the
  # field took focus too late) and tap the row.
  found=no
  if UI_WAIT=8 $UI tap "$PKG"; then found=yes; else
    $UI tapxy 160 152; sleep 3
    for _ in 1 2 3; do
      $UI type "WebUI"; sleep 4
      UI_WAIT=4 $UI tap "$PKG" && { found=yes; break; }
      UI_EXACT=1 UI_WAIT=2 $UI tap Clean; sleep 2
    done
  fi
  if [ $found = yes ]; then
    sleep 3; $UI dump "$OUT/webuix-ksu-profile.xml"; adb exec-out screencap -p >"$OUT/webuix-ksu-profile.png"
    # The App Profile screen: its first switch is Superuser.
    $UI switch 1 && sleep 2 && granted=ui
    adb exec-out screencap -p >"$OUT/webuix-ksu-granted.png"; $UI dump "$OUT/webuix-ksu-granted.xml" >/dev/null
  fi
  [ $granted = ui ] && break
  log "root grant attempt $attempt failed; retrying"; sleep 15
done
log "ksud feature list: $(adb shell /data/adb/ksud feature list 2>&1 | tr -d '\r' | tr '\n' ' ')"
log "su_compat: $(adb shell /data/adb/ksud feature get su_compat 2>&1 | tr -d '\r' | tr '\n' ' ')"
log "root grant: $granted; su as app uid $UID_: $(adb shell "su $UID_ /system/bin/su -c id 2>&1 || true" | tr -d '\r' | head -2)"
adb shell input keyevent KEYCODE_HOME

# First launch: walk through any onboarding, keep what it shows.
adb shell am start -n "$MAIN" >/dev/null 2>&1; sleep 6
# v660 SetupScreen still selects a platform then Continue with KernelSU.
# Give its platform list and fixed-height button room on the small AVD.
adb shell wm size 320x900; sleep 2
adb shell am force-stop $PKG; adb shell am start -n "$MAIN" >/dev/null 2>&1; sleep 6
export UI_EXACT=1
UI_WAIT=20 $UI tap KernelSU || exit 1
UI_WAIT=10 $UI tap "Continue with KernelSU" || exit 1
sleep 3
if UI_WAIT=2 $UI has "Select your Platform"; then
  log "onboarding did not finish"; exit 1
fi
unset UI_EXACT
adb exec-out screencap -p >"$OUT/webuix-after-onboarding.png"; $UI dump "$OUT/webuix-after-onboarding.xml" | head -20
# WebView debugging is not gated behind Developer Mode here: a fresh install
# with the setting off reached every devtools check (run 44049815536). Do not
# drive Settings: after setup the host can land on WX Explorer, which has no
# bottom navigation, and a fatal tap there fails the leg for nothing.
adb shell wm size reset; sleep 2
log "WebUI X platform after onboarding: $(adb shell "ls /data/data/$PKG/files/datastore/ 2>/dev/null; strings /data/data/$PKG/files/datastore/*.pb 2>/dev/null | head -20" | tr -d '\r' | tr '\n' ' ')"
log "devtools sockets: $(adb shell cat /proc/net/unix | grep -o '@[a-z_]*devtools_remote[0-9_]*' | tr '\n' ' ')"
