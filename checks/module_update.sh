#!/usr/bin/env bash
# The manager's module update button: with an older release installed whose
# module.prop names an updateJson, does the manager offer the newer release,
# and does pressing it stage the new zip? Explores the manager UI: Module tab,
# search the module, tap Update, accept dialogs, wait for the flash.
# Usage: module_update.sh <label> <pkg> <module id> [module name]
#   -> $LAB_OUT/<label>-update.jsonl and <label>-update-*.png/xml
set -uo pipefail
LABEL=$1; PKG=$2; ID=$3; NAME=${4:-$3}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
UI="python3 $HERE/managers/ui.py"; O=$OUT/$LABEL-update; J=$O.jsonl; : >"$J"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":$2}" | tee -a "$J"; }
props() { adb shell "for d in /data/adb/modules/$ID /data/adb/modules_update/$ID; do echo \"-- \$d\"; grep -E '^(version|versionCode|updateJson)=' \$d/module.prop 2>&1; ls -la --time-style=+%T \$d/module.prop 2>/dev/null; done" | tr -d '\r'; }
rec installed "$(props | js)"
U=$(adb shell "sed -n 's/^updateJson=//p' /data/adb/modules/$ID/module.prop" | tr -d '\r')
rec update-json "$( (echo "$U"; [ -n "$U" ] && curl -fsSL "$U") 2>&1 | js)"
shot() { timeout 20 adb exec-out screencap -p >"$O-$1.png"; $UI dump "$O-$1.xml" >/dev/null 2>&1; }
adb logcat -c
adb shell am force-stop "$PKG"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 6
UI_EXACT=1 UI_WAIT=30 $UI tap Module || UI_EXACT=1 $UI tap Modules; sleep 8
shot modules
# KernelSU 3.3.0's list exposes nodes only after a search (typing races the
# field focus: check and retype, as open_webui.sh does). Next shows an
# UPDATE badge on the card; KernelSU an Update button.
offer() { for w in Update UPDATE; do UI_EXACT=1 UI_WAIT=${1:-3} $UI has "$w" && { echo "$w"; return 0; }; done; return 1; }
if ! offer 5 >/dev/null; then
  $UI tapxy 160 152; sleep 3
  for _ in 1 2 3; do
    $UI type "$NAME"; sleep 3
    UI_EXACT=1 UI_WAIT=3 $UI has "$NAME" && break
    UI_EXACT=1 UI_WAIT=2 $UI tap Clean; sleep 2
  done
  # Close the keyboard (search key) so cards below the first show; a metamodule's
  # card lists "modules: demo" and matches the search too, above ours.
  adb shell input keyevent KEYCODE_ENTER; sleep 2
  shot search
fi
W=$(offer 10)
[ -z "$W" ] && { $UI scroll; sleep 3; W=$(offer 5); }
rec offered "$( (echo "${W:-no}"; $UI dump) 2>&1 | js)"
if [ -n "$W" ] && UI_EXACT=1 $UI tap "$W"; then
  sleep 5; shot tapped
  # Next opens the card's sheet or a confirm dialog; KernelSU a confirm dialog.
  # Next: the badge expands the card (Update button), that opens a Changelog
  # dialog (Cancel / Update). So keep confirming until a flash screen shows.
  flashing() { for w in Reboot REBOOT "Soft restart" "Save logs" Failed; do UI_WAIT=1 $UI has "$w" && return 0; done; return 1; }
  for n in 1 2 3; do
    flashing && break
    for b in Update UPDATE Install INSTALL Confirm CONFIRM OK Yes; do UI_EXACT=1 UI_WAIT=3 $UI tap "$b" && { sleep 4; shot confirmed-$n; break; }; done
  done
  for i in $(seq 1 24); do flashing && break; sleep 5; done
  shot flashed
  rec flash-screen "$($UI dump 2>&1 | js)"
fi
rec after "$(props | js)"
# Apply the staged update the way install_modules.sh does (soft restart), then
# check Android took the new zip's app (same package, same signer, new version).
APKDIR=$(adb shell "ls -d /data/adb/modules_update/$ID/system/product/app/WebuiApi_* 2>/dev/null | head -1" | tr -d '\r')
if [ -n "$APKDIR" ]; then
  APP=$(adb shell "dumpsys package packages | grep -o 'com.webui.api.[a-z0-9_.]*' | sort -u | head -1" | tr -d '\r')
  rec app-before "$(adb shell "dumpsys package $APP | grep -E 'versionName|signatures|codePath|lastUpdateTime'" 2>&1 | tr -d '\r' | js)"
  adb shell /data/adb/ksud soft-reboot >/dev/null 2>&1; sleep 5; timeout 120 adb wait-for-device; t0=$SECONDS
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && adb shell pidof system_server >/dev/null; do (( SECONDS - t0 > 300 )) && break; sleep 3; done; sleep 25
  rec applied "$(props | js)"
  rec app-after "$( (adb shell "dumpsys package $APP | grep -E 'versionName|signatures|codePath|lastUpdateTime'; ls -la /product/app/WebuiApi_*/; grep /product/app /proc/mounts"; adb logcat -d | grep -i -E 'signature|INSTALL_FAILED|PackageManager.*webui' | tail -10) 2>&1 | tr -d '\r' | js)"
fi
rec manager-log "$(adb logcat -d | grep -i -E 'update|download|flash|install|module' | grep -v -E 'PackageManager|ProfileInstaller|nativeloader|AiAiEcho|SsMediaDataProvider|Smartspace' | tail -30 | js)"
adb shell input keyevent KEYCODE_BACK; adb shell am force-stop "$PKG"
