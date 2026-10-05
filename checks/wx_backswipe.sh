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

# The touchscreen's evdev node and range: `input motionevent` steps (one
# process each, own downTime) did not start the system back gesture on the
# AVD (2026-10-05 run 37267772813), so drive the kernel device directly, as
# the AERA lab does: one adb shell of sendevent writes.
TOUCH=$(adb shell getevent -pl 2>/dev/null | tr -d '\r' | awk '/^add device/ {d=$4} /ABS_MT_POSITION_X/ {print d; exit}')
read -r MX MY < <(adb shell getevent -pl "$TOUCH" 2>/dev/null | tr -d '\r' | awk '/ABS_MT_POSITION_X/ {for (i=1;i<=NF;i++) if ($i=="max") x=$(i+1)} /ABS_MT_POSITION_Y/ {for (i=1;i<=NF;i++) if ($i=="max") y=$(i+1)} END {gsub(",","",x); gsub(",","",y); print x, y}')
rec touch "\"$TOUCH max ${MX}x$MY\""
rec gesture-settings "$(adb shell "settings list secure | grep -i -E 'gesture|navigation_mode|back'; dumpsys input | grep -i -E -A2 'monitor' | head -20; dumpsys window | grep -i -E 'exclusion|gesturalNav|NavigationMode' | head -10" 2>&1 | tr -d '\r' | q)"
# swipe <tag> <commit|cancel>: finger down at the left edge, 12 moves out to
# 45% of the width (cancel: 6 moves back to the edge), screencaps mid-gesture
# (after move 6 and at the far point), lift.
swipe() {
  local tag=$1 mode=$2 i px py sy s
  sx() { echo $(( $1 * MX / W )); }
  py=$((H / 2)); sy=$(( py * MY / H ))
  E="sendevent $TOUCH"
  s="$E 3 57 7; $E 3 53 $(sx 1); $E 3 54 $sy; $E 3 58 50; $E 1 330 1; $E 0 0 0; sleep 0.03;"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do px=$((1 + (W * 45 / 100 - 1) * i / 12)); s+=" $E 3 53 $(sx $px); $E 0 0 0; sleep 0.03;"; [ $i = 6 ] && s+=" screencap -p /sdcard/bs-$tag-1.png;"; done
  s+=" screencap -p /sdcard/bs-$tag-2.png;"
  if [ "$mode" = cancel ]; then for i in 10 8 6 4 2 0; do px=$((1 + (W * 45 / 100 - 1) * i / 12)); s+=" $E 3 53 $(sx $px); $E 0 0 0; sleep 0.03;"; done; fi
  s+=" $E 3 57 4294967295; $E 1 330 0; $E 0 0 0; sleep 0.4; screencap -p /sdcard/bs-$tag-3.png"
  adb shell "$s" 2>&1 | tr -d '\r' | tail -3
  for i in 1 2 3; do adb pull "/sdcard/bs-$tag-$i.png" "$O-$tag-$i.png" >/dev/null 2>&1; done
  adb shell "rm -f /sdcard/bs-$tag-*.png"
}
ev 'window.__bs && (__bs.length = 0)' >/dev/null
swipe cancel cancel; sleep 2
rec cancel-events "$(ev 'window.__bs || "logger gone"')"
rec cancel-route "$(text)"; rec cancel-top "\"$(top)\""
ev 'window.__bs && (__bs.length = 0)' >/dev/null
adb shell "getevent -lt $TOUCH > /sdcard/ge.txt 2>&1 & echo \$! > /sdcard/ge.pid"
adb logcat -c
swipe commit commit; sleep 3
adb shell 'kill $(cat /sdcard/ge.pid)'; adb pull /sdcard/ge.txt "$O-commit-getevent.txt" >/dev/null 2>&1
adb logcat -d 2>/dev/null | grep -v -E 'nativeloader|chromium' | tail -200 >"$O-commit-logcat.txt"
rec commit-events "$(ev 'window.__bs || "logger gone"')"
rec commit-route "$(text)"; rec commit-top "\"$(top)\""
# At the root route a committed swipe should close the page.
ev 'window.__bs && (__bs.length = 0)' >/dev/null
swipe root commit; sleep 3
rec root-events "$(ev 'window.__bs || "logger gone"')"; rec root-top "\"$(top)\""
# Comparison: one `input swipe` from the edge on a pushed route.
step "$ROUTE" >/dev/null; sleep 3; ev 'window.__bs && (__bs.length = 0)' >/dev/null
adb shell input swipe 1 $((H / 2)) $((W * 45 / 100)) $((H / 2)) 600
sleep 3; rec inputswipe-events "$(ev 'window.__bs || "logger gone"')"; rec inputswipe-route "$(text)"; rec inputswipe-top "\"$(top)\""
adb logcat -d 2>/dev/null | grep -i -E 'BackGesture|OnBackInvoked|BackNavigation|predictive' | tail -40 >"$O-logcat.txt"
adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton >/dev/null 2>&1
