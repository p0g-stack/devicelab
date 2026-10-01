#!/usr/bin/env bash
# Open a module's WebUI in a manager and wait for its page in DevTools.
# Usage: open_webui.sh <label> <pkg> <module id> [module name]
# Tries the manager's WebUI activity by intent first, then the manager's own
# UI (Module tab, the module's card, its WebUI button). Prints the path that
# worked on the last line ("opened: intent|ui|none"); leaves screenshots,
# UI dumps and logcat under $LAB_OUT/<label>-open*.
set -uo pipefail
LABEL=$1; PKG=$2; ID=$3; NAME=${4:-$3}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
UI="python3 $HERE/managers/ui.py"; O=$OUT/$LABEL-open
page() { node "$HERE/driver/webview.mjs" list 2>/dev/null | python3 -c 'import json,sys; t=[x for x in json.load(sys.stdin) if x.get("type")=="page"]; print(t[0]["url"] if t else ""); sys.exit(0 if t else 1)'; }
wait_page() { for _ in $(seq 1 "${1:-8}"); do sleep 1; page && return 0; done; return 1; }
case $PKG in
  me.weishu.kernelsu|com.rifsxd.ksunext|com.sukisu.ultra) ACT=$PKG/.ui.webui.WebUIActivity;;
  com.dergoogler.mmrl.wx) ACT=$PKG/.ui.activity.webui.WebUIActivity;;
  *) ACT=${WEBUI_ACTIVITY:-};;
esac
adb logcat -c
adb shell am force-stop "$PKG"
# A first-launch notification prompt sits on top of the manager UI otherwise.
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null
if [ -n "$ACT" ]; then
  adb shell am start -W -n "$ACT" -e id "'$ID'" -e name "'$NAME'" 2>&1 | tr -d '\r' | grep -E 'Status|Activity|Error|Warning'
  if wait_page 8; then adb exec-out screencap -p >"$O-intent.png"; echo "opened: intent"; exit 0; fi
fi
adb exec-out screencap -p >"$O-intent.png"
adb logcat -d 2>/dev/null | grep -v -E 'nativeloader|WindowManager' | tail -1500 >"$O-intent-logcat.txt"
echo "intent path: no page; manager log:"; grep -E " $(adb shell pidof "$PKG" | tr -d '\r' | awk '{print $1}') " "$O-intent-logcat.txt" | tail -25
# Manager UI path. KernelSU 3.3.0's module list exposes no uiautomator nodes
# until it is searched, so: Module tab, tap the search box (reference
# 320x640 position), type the name, tap the first result's Open.
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1; sleep 5
UI_EXACT=1 UI_WAIT=30 $UI tap Module || $UI tap Modules; sleep 6
adb exec-out screencap -p >"$O-modules.png"
$UI tapxy 160 152; sleep 3; $UI type "$NAME"; sleep 4
adb exec-out screencap -p >"$O-search.png"; $UI dump "$O-search.xml"
UI_EXACT=1 $UI tap Open
if wait_page 12; then
  adb exec-out screencap -p >"$O-ui.png"
  # How the manager itself starts its WebUI (compare with the intent path).
  adb shell dumpsys activity activities | grep -E -A4 'Hist.*WebUI|intent=.*WebUI' | head -20 | tr -d '\r' | tee "$O-ui-intent.txt"
  echo "opened: ui"; exit 0
fi
$UI dump "$O-after.xml"; adb exec-out screencap -p >"$O-after.png"
adb logcat -d 2>/dev/null | grep -v -E 'nativeloader|WindowManager' | tail -1500 >"$O-ui-logcat.txt"
echo "opened: none"; exit 1
