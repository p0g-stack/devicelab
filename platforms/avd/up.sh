#!/usr/bin/env bash
# Boot a headless AVD with adb root. Needs /dev/kvm and the Android SDK
# (ANDROID_HOME), which GitHub's ubuntu runners have.
# Usage: up.sh [api] [tag] [abi]   defaults: 35 google_apis x86_64
set -euo pipefail
API=${1:-35}; TAG=${2:-google_apis}; ABI=${3:-x86_64}
IMG="system-images;android-$API;$TAG;$ABI"
SDK=${ANDROID_HOME:?}
BIN=$SDK/cmdline-tools/latest/bin
"$BIN/sdkmanager" --install emulator platform-tools "$IMG" < <(yes) >/dev/null
export ANDROID_AVD_HOME=${ANDROID_AVD_HOME:-$HOME/.android/avd}; mkdir -p "$ANDROID_AVD_HOME"
command -v apt-get >/dev/null && sudo apt-get install -y -qq libpulse0 >/dev/null 2>&1
echo no | "$BIN/avdmanager" create avd -f -n lab -k "$IMG" | tail -2
ls "$ANDROID_AVD_HOME"
"$SDK/emulator/emulator" -avd lab -no-window -no-audio -no-boot-anim -no-snapshot \
  -gpu swiftshader_indirect -memory 4096 -cores 4 -writable-system \
  >"${LAB_OUT:-.}/emulator.log" 2>&1 &
echo "emulator $("$SDK/emulator/emulator" -version | head -1)"
ADB=$SDK/platform-tools/adb
LOG=${LAB_OUT:-.}/emulator.log
fail() { echo "$1"; tail -40 "$LOG"; exit 1; }
timeout 300 "$ADB" wait-for-device || fail "no adb device after 300s"
t0=$SECONDS
until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
  (( SECONDS - t0 > 600 )) && fail "boot timeout"
  sleep 3
done
"$ADB" root >/dev/null; sleep 2; "$ADB" wait-for-device
echo "booted in $((SECONDS - t0))s: $("$ADB" shell getprop ro.build.fingerprint | tr -d '\r')"
