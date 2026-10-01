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
# KernelSU 3.3.0's list exposes nodes only after a search.
if ! UI_WAIT=3 $UI has Update; then
  $UI tapxy 160 152; sleep 3; $UI type "$NAME"; sleep 4; shot search
fi
rec offered "$( (UI_WAIT=15 $UI has Update && echo yes || echo no; $UI dump) 2>&1 | js)"
if UI_EXACT=1 UI_WAIT=5 $UI tap Update || UI_WAIT=5 $UI tap Update; then
  sleep 5; shot tapped
  # Confirmation dialogs vary by manager.
  for b in Update Install Confirm OK Yes; do UI_EXACT=1 UI_WAIT=3 $UI tap "$b" && { sleep 3; break; }; done
  for i in $(seq 1 18); do sleep 5; UI_WAIT=1 $UI has Reboot && break; UI_WAIT=1 $UI has Failed && break; done
  shot flashed
  rec flash-screen "$($UI dump 2>&1 | js)"
fi
rec after "$(props | js)"
rec manager-log "$(adb logcat -d | grep -i -E 'update|download|flash|install|module' | grep -v -E 'PackageManager|ProfileInstaller|nativeloader' | tail -30 | js)"
adb shell input keyevent KEYCODE_BACK; adb shell am force-stop "$PKG"
