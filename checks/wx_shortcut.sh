#!/usr/bin/env bash
# WebUI X home-screen shortcut for a shipped module (v608 builds it from the
# module icon named by module.prop webuiIcon=; without one create returns false
# with an "invalid icon" toast). Calls webui.createShortcut() from the page as
# flutter-webui's WebUi.extras does, accepts the launcher's pin dialog, checks
# dumpsys shortcut, opens the page from the home-screen icon and reads
# webui.hasShortcut there.
# Usage: wx_shortcut.sh <label> <host pkg> <module id> [module name]
#   -> $LAB_OUT/<label>-wxsc.jsonl, <label>-wxsc-*.png
set -uo pipefail
LABEL=$1; HPKG=$2; ID=$3; NAME=${4:-$3}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"; UI="python3 $HERE/managers/ui.py"
O=$OUT/$LABEL-wxsc; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"
q() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
top() { adb shell dumpsys activity activities | grep -m1 topResumedActivity | tr -d '\r' | sed 's/^ *//'; }
shot() { timeout 20 adb exec-out screencap -p >"$O-$1.png"; }
ui_text() { $UI dump "$O-$1.xml" 2>/dev/null | head -14 | q; }
STATE='({createShortcut: typeof (window.webui && webui.createShortcut), hasShortcut: window.webui ? String(webui.hasShortcut) : "no webui"})'

M=/data/adb/modules/$ID
rec module-icon "$(adb shell "grep -E '^webuiIcon=' $M/module.prop; i=\$(sed -n 's/^webuiIcon=//p' $M/module.prop | tr -d '\r'); ls -la $M/webroot/\$i 2>&1" | tr -d '\r' | q)"
adb shell am force-stop "$HPKG"
rec open "\"$("$HERE/managers/open_webui.sh" "$LABEL-wxsc" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1)\""; sleep 8
rec state-before "$(ev "$STATE")"
adb logcat -c
rec create "$(ev 'new Promise(r => { if (!window.webui || typeof webui.createShortcut !== "function") return r("unsupported"); let v; try { v = webui.createShortcut() } catch (e) { return r("throw " + String(e).slice(0, 120)) } r({returned: v, type: typeof v}) })')"
sleep 2; shot dialog; rec dialog "$(ui_text dialog)"
rec accept "\"$( (UI_WAIT=3 $UI tap 'Add automatically' || UI_WAIT=3 $UI tap 'Add to home screen' || UI_EXACT=1 UI_WAIT=3 $UI tap 'Add') 2>&1 | tail -1)\""; sleep 3
rec logcat "$(adb logcat -d 2>/dev/null | grep -i -E 'shortcut|icon|toast' | grep -v nativeloader | tail -20 | tr -d '\r' | q)"
rec pinned "$(adb shell "dumpsys shortcut | grep -A12 'Package: $HPKG' | head -30" | tr -d '\r' | q)"
adb shell am force-stop "$HPKG"; adb shell input keyevent KEYCODE_HOME; sleep 3; shot home
rec home-tap "\"$(UI_EXACT=1 UI_WAIT=5 $UI tap "$NAME" 2>&1 | tail -1)\""; sleep 10
rec from-shortcut-top "\"$(top)\""; shot from-shortcut
rec state-from-shortcut "$(ev "$STATE")"
rec page "$(text)"
