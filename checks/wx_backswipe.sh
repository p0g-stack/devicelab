#!/usr/bin/env bash
# Predictive back on WebUI X v608+: drive a left-edge back swipe with progress
# and record what the page saw. Switches the AVD to gesture navigation (the
# 3-button bar sends a plain KEYCODE_BACK with no progress), opens the module,
# installs a page-side logger on WebUI X's document.addMXEventListener for
# backStarted/backProgressed/backCancelled/backPressed (plus popstate and
# Flutter route text), then runs one cancelled swipe (out and back, released at
# the edge) and one committed swipe. Each swipe is a single adb shell of
# `input motionevent` steps with screencaps taken mid-gesture.
# Usage: wx_backswipe.sh <label> <host pkg> <module id> [module name] [route label to push first]
#   -> $LAB_OUT/<label>-bswipe.jsonl, <label>-bswipe-<swipe>-<n>.png
set -uo pipefail
LABEL=$1; HPKG=$2; ID=$3; NAME=${4:-$3}; ROUTE=${5:-Places}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"
O=$OUT/$LABEL-bswipe; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
top() { adb shell dumpsys activity activities | grep -m1 topResumedActivity | tr -d '\r' | sed 's/^ *//'; }
q() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }

# Gesture navigation, so the system's back gesture (and its progress) exists.
rec nav-before "$(adb shell cmd overlay list android 2>&1 | grep -i navbar | tr -d '\r' | q)"
adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.gestural 2>&1 | tr -d '\r'
sleep 4
rec nav-after "$(adb shell "cmd overlay list android | grep -i navbar; settings get secure navigation_mode" 2>&1 | tr -d '\r' | q)"
read -r W H < <(adb shell wm size | tr -d '\r' | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)
rec screen "\"${W}x$H\""

rec open "\"$("$HERE/managers/open_webui.sh" "$LABEL-bswipe" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1)\""; sleep 6
LOGGER='(() => { window.__bs = []; const T = () => Math.round(performance.now()); const p = (n, d) => __bs.push([n, d === undefined ? null : JSON.stringify(d).slice(0, 200), T()]);
  const api = typeof document.addMXEventListener === "function";
  if (api) for (const n of ["backStarted", "backProgressed", "backCancelled", "backPressed"]) { try { document.addMXEventListener(n, e => p(n, e)) } catch (e) { p("listen-error " + n, String(e)) } }
  addEventListener("popstate", e => p("popstate", {len: history.length, state: e.state}));
  addEventListener("message", e => p("message", String(e.data).slice(0, 120)));
  return {addMXEventListener: api, historyLength: history.length, href: location.href} })()'
rec logger "$(ev "$LOGGER")"
rec push-route "$(step "$ROUTE")"; sleep 3
rec route-before "$(text)"

# swipe <tag> <commit|cancel>: DOWN at the left edge, MOVE in steps to 45% of
# the width (cancel: back to the edge), a screencap at 3 points, UP.
swipe() {
  local tag=$1 mode=$2 y=$((H / 2)) x1=$((W * 45 / 100)) s="" i x
  s="input motionevent DOWN 1 $y; sleep 0.05;"
  for i in 1 2 3 4 5 6 7 8 9 10; do x=$((1 + (x1 - 1) * i / 10)); s+=" input motionevent MOVE $x $y; sleep 0.04;"; [ $i = 5 ] && s+=" screencap -p /sdcard/bs-$tag-1.png;"; done
  s+=" screencap -p /sdcard/bs-$tag-2.png;"
  if [ "$mode" = cancel ]; then for i in 9 7 5 3 1; do x=$((1 + (x1 - 1) * i / 10)); s+=" input motionevent MOVE $x $y; sleep 0.04;"; done; x=1; else x=$x1; fi
  s+=" input motionevent UP $x $y; sleep 0.3; screencap -p /sdcard/bs-$tag-3.png"
  adb shell "$s" 2>&1 | tr -d '\r' | tail -3
  for i in 1 2 3; do adb pull "/sdcard/bs-$tag-$i.png" "$O-$tag-$i.png" >/dev/null 2>&1; done
  adb shell "rm -f /sdcard/bs-$tag-*.png"
}
ev 'window.__bs && (__bs.length = 0)' >/dev/null
swipe cancel cancel; sleep 2
rec cancel-events "$(ev 'window.__bs || "logger gone"')"
rec cancel-route "$(text)"; rec cancel-top "\"$(top)\""
ev 'window.__bs && (__bs.length = 0)' >/dev/null
swipe commit commit; sleep 3
rec commit-events "$(ev 'window.__bs || "logger gone"')"
rec commit-route "$(text)"; rec commit-top "\"$(top)\""
# At the root route a committed swipe should close the page.
ev 'window.__bs && (__bs.length = 0)' >/dev/null
swipe root commit; sleep 3
rec root-events "$(ev 'window.__bs || "logger gone"')"; rec root-top "\"$(top)\""
adb logcat -d 2>/dev/null | grep -i -E 'BackGesture|OnBackInvoked|BackNavigation|predictive' | tail -40 >"$O-logcat.txt"
adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton >/dev/null 2>&1
