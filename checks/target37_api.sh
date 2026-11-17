#!/usr/bin/env bash
# Qualify the shipped target-37 app-plane client on an AVD only.
# Usage: target37_api.sh <label> [module id]
set -euo pipefail
LABEL=$1; ID=${2:-demo}; APP=com.webui.api.$ID
OUT=${LAB_OUT:-$PWD/out}; API=/data/adb/modules/$ID/webui_app_plane/termux-api
J=$OUT/$LABEL-target37.jsonl
: >"$J"
[ "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" = 1 ] || { echo 'AVD required'; exit 1; }
package_info=$(adb shell dumpsys package "$APP")
grep -q 'targetSdk=37' <<<"$package_info" || { echo 'targetSdk 37 APK required'; exit 1; }
api() { adb shell sh "$API" --package "$APP" --wait 60 "$@" </dev/null | tr -d '\r'; }
record() { jq -nc --arg check "$1" --arg result "$2" '{check:$check,result:$result}' | tee -a "$J"; }
original=$(adb shell settings get global wifi_on | tr -d '\r')
restore=true; [ "$original" != 0 ] || restore=false
trap 'api WifiEnable --ez enabled "$restore" >/dev/null || true' EXIT
for state in false true; do
  answer=$(api WifiEnable --ez enabled "$state")
  record "wifi-$state-answer" "$answer"
  [ -z "$answer" ] || { echo 'WifiEnable returned an API error'; exit 1; }
  expected=disabled; [ "$state" != true ] || expected=enabled
  status=
  for _ in $(seq 1 20); do
    status=$(adb shell cmd wifi status | tr -d '\r')
    grep -q "Wifi is $expected" <<<"$status" && break
    sleep 1
  done
  record "wifi-$state-state" "$status"
  grep -q "Wifi is $expected" <<<"$status" || exit 1
done
api WifiEnable --ez enabled "$restore" >/dev/null
trap - EXIT

# app_plane_module.sh has requested/granted CAMERA through Android's dialog.
# The AVD camera is synthetic; no physical camera or private image is used.
# A soft reboot (app_plane_module.sh) and root_channel.sh's stopservice leave no
# helper running, and CameraPhoto is dispatched through it: "API needs the
# authorized root helper to be running". Start it as shell — the client the
# page's own app plane uses — and re-arm it each try, because a start that no
# holder follows is stopped 10 s later.
photo=/data/user/0/$APP/cache/webui-target37.jpg
answer=
for _ in $(seq 1 5); do
  adb shell am start-foreground-service --user 0 -n "$APP/com.termux.api.RootHelperService" >/dev/null 2>&1 || true
  answer=$(api CameraPhoto --es file "$photo" --es camera 0)
  case $answer in *authorized*) sleep 2;; *) break;; esac
done
record camera-answer "$answer"
[ -z "$answer" ] || { echo 'CameraPhoto returned an API error'; exit 1; }
adb shell test -s "$photo" || { echo 'CameraPhoto produced no image'; exit 1; }
record camera-file "$(adb shell stat -c '%s bytes' "$photo" | tr -d '\r')"
adb shell rm "$photo"
record result passed
