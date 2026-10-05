#!/usr/bin/env bash
# flutter-webui extras lab module (extras_lab, flutter-webui a1835ca): the 8
# cases of /mnt/project-files/flutter-webui/lab-cases-v608-extras.md. Reads
# the module's own console lines ("extras-lab: ...", logcat tag chromium).
# Usage: extras_lab.sh <label> <host pkg> <module id> [module name]
#   -> $LAB_OUT/<label>-xl.jsonl, <label>-xl-*.png
set -uo pipefail
LABEL=$1; HPKG=$2; ID=$3; NAME=${4:-$3}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"; UI="python3 $HERE/managers/ui.py"
O=$OUT/$LABEL-xl; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"; . "$HERE/checks/lib/swipe.sh"
q() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
top() { adb shell dumpsys activity activities | grep -m1 topResumedActivity | tr -d '\r' | sed 's/^ *//'; }
FW=/data/adb/modules/$ID/flutter_webui
# The module's log lines since the last mark.
# Lines come from logcat (WebView console -> tag chromium, when the host lets
# it through) and from a console hook put in the page after each open.
HOOK='(() => { if (!window.__xl) { window.__xl = []; for (const k of ["log", "info", "debug"]) { const o = console[k]; console[k] = (...a) => { const s = a.map(String).join(" "); if (s.includes("extras-lab:")) __xl.push(s.slice(s.indexOf("extras-lab:"))); return o.apply(console, a) } } } return "hooked" })()'
mark() { adb logcat -c; ev 'window.__xl && (__xl.length = 0)' >/dev/null 2>&1; }
lines() { sleep "${1:-2}"; local lc pg
  lc=$(adb logcat -d -s chromium:* 2>/dev/null | tr -d '\r' | grep -o 'extras-lab: .*' | sed 's/", source:.*//' | q)
  pg=$(ev 'window.__xl ? __xl.slice() : "no hook"' 2>/dev/null)
  echo "{\"logcat\":$lc,\"page\":${pg:-null}}"; }
open_() { "$HERE/managers/open_webui.sh" "$LABEL-xl-$1" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1; ev "$HOOK" >/dev/null 2>&1; }
depth() { text | python3 -c 'import json,sys
try: v = json.loads(sys.stdin.read())
except Exception: v = []
v = v.get("value", v) if isinstance(v, dict) else v
d = [x for x in (v or []) if x.startswith("depth ")]
print(json.dumps(d[0] if d else None))' 2>/dev/null; }
shot() { timeout 20 adb exec-out screencap -p >"$O-$1.png"; }

# SystemUI on the AVD has shown an ANR window and a disabled EdgeBackGestureHandler; restart it once.
adb shell "pkill -f com.android.systemui$"; sleep 20; adb shell input keyevent KEYCODE_WAKEUP; sleep 2
# The handler stayed disabled after that (run 37274405346): flip the navigation
# mode to three-button and back so SystemUI re-attaches the gesture handler.
adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton; sleep 6
adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.gestural; sleep 8
swipe_setup
rec env "$(adb shell "echo touch=$TOUCH max=${MX}x$MY screen=${W}x$H; settings get secure navigation_mode; dumpsys activity service com.android.systemui/.SystemUIService 2>/dev/null | grep -A3 'EdgeBackGestureHandler:' | tr -s ' '" 2>&1 | tr -d '\r' | q)"

# 1: open, start line, push to depth 2.
adb shell am force-stop "$HPKG"; mark
rec 1-open "\"$(open_ 1)\""; sleep 5
rec 1-start "$(lines 1)"; rec 1-ui "$(text)"
mark; step 'push depth 1' >/dev/null; sleep 2; step 'push depth 2' >/dev/null; sleep 2
rec 1-push "$(lines 1)"; rec 1-depth "$(depth)"; shot 1-depth2
# 2: swipe, hold 1 s at halfway, release.
mark; edge_swipe "$O" 2 commit 1; rec 2-log "$(lines 2)"; rec 2-depth "$(depth)"; rec 2-top "\"$(top)\""
# 3: swipe out and back to the edge (cancel). Push back to depth 2 first if 2 popped.
case $(depth) in *'depth 1'*) step 'push depth 2' >/dev/null; sleep 2;; esac
mark; edge_swipe "$O" 3 cancel 0.5; rec 3-log "$(lines 2)"; rec 3-depth "$(depth)"
# 4: keyevent Back at depth 1.
case $(depth) in *'depth 2'*) mark; adb shell input keyevent 4; sleep 2; rec 4-pre-pop "$(lines 1)";; esac
rec 4-depth-before "$(depth)"
mark; adb shell input keyevent 4; rec 4-log "$(lines 2)"; rec 4-depth "$(depth)"
# 5: swipe at the root: the page closes; the root channel shuts down as before.
mark; edge_swipe "$O" 5 commit 0; rec 5-log "$(lines 2)"; rec 5-top "\"$(top)\""
# Swipe did nothing (gesture handler off on the AVD): close with keyevent Back.
case "$(top)" in *WebUIActivity*) mark; adb shell input keyevent 4; rec 5-key-log "$(lines 2)"; rec 5-key-top "\"$(top)\"";; esac
sleep 60; rec 5-rootlog "$(adb shell "tail -6 $FW/run/root.log 2>&1" | tr -d '\r' | q)"
# 6: cold start, one push, swipe right away.
adb shell am force-stop "$HPKG"; mark
rec 6-open "\"$(open_ 6)\""; sleep 4
step 'push depth 1' >/dev/null; edge_swipe "$O" 6 commit 1; rec 6-log "$(lines 2)"; rec 6-depth "$(depth)"
# 7: create shortcut, accept the launcher's pin dialog, reopen: exists=true.
mark; rec 7-tap "$(step 'create shortcut')"; sleep 3
rec 7-log "$(lines 1)"; shot 7-dialog; rec 7-dialog "$($UI dump "$O-7.xml" 2>/dev/null | head -12 | q)"
UI_WAIT=3 $UI tap 'Add automatically' || UI_WAIT=3 $UI tap 'Add to home screen' || UI_EXACT=1 UI_WAIT=3 $UI tap 'Add'; sleep 2
rec 7-pinned "$(adb shell "dumpsys shortcut | grep -i -B2 -A6 'pinned\|$HPKG' | grep -i -E 'package|id=|flags|pinned' | head -12" | tr -d '\r' | q)"
adb shell am force-stop "$HPKG"; mark
rec 7-reopen "\"$(open_ 7)\""; sleep 5; rec 7-start "$(lines 1)"; rec 7-ui "$(text)"
# 8: package info for android; the icon row.
mark; rec 8-tap "$(step 'package info for android')"; sleep 3
rec 8-log "$(lines 2)"; rec 8-ui "$(text)"; shot 8-icon
rec 8-icon-dom "$(ev 'new Promise(r => { const i = [...document.querySelectorAll("img")].filter(x => (x.src || "").startsWith("ksu://icon")); r(i.map(x => ({src: x.src, complete: x.complete, w: x.naturalWidth, h: x.naturalHeight}))) })')"
rec end-top "\"$(top)\""
