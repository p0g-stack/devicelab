#!/usr/bin/env bash
# Walk the p0g demo module's pages (1 Places, 2 Strategy, 4 Lifecycle) in an
# already opened host WebView, through Flutter's semantics tree (enabled over
# DevTools), so taps go by label rather than by screen position. Each step
# records the page's semantic text and a screenshot.
# Usage: demo_walk.sh <label>        writes $LAB_OUT/<label>-walk.jsonl
set -uo pipefail
LABEL=$1; OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"; J=$OUT/$LABEL-walk.jsonl; : >"$J"
rec() { echo "{\"check\":\"$1\",\"result\":$2}" | tee -a "$J"; }
ev() { $WV eval "$1" 2>&1 | tail -1; }
shot() { timeout 20 adb exec-out screencap -p >"$OUT/$LABEL-walk-$1.png"; }
# Helpers on window: enable semantics, list labels, tap by label prefix.
HELP='window.__w = window.__w || {
  on() { const p = document.querySelector("flt-semantics-placeholder"); if (p) p.click(); },
  nodes() { return [...document.querySelectorAll("flt-semantics")].filter(e => !e.querySelector("flt-semantics")) },
  text() { return [...document.querySelectorAll("flt-semantics")].map(e => (e.getAttribute("aria-label") || [...e.childNodes].filter(n => n.nodeType === 3 || n.tagName === "SPAN").map(n => n.textContent).join("")).trim()).filter(Boolean) },
  find(l) { const all = [...document.querySelectorAll("flt-semantics")]; const lab = e => (e.getAttribute("aria-label") || e.textContent || "").trim(); return all.find(e => lab(e) === l) || all.filter(e => lab(e).startsWith(l)).sort((a, b) => lab(a).length - lab(b).length)[0] },
  tap(l) { const e = this.find(l); if (!e) return "no " + l; const r = e.getBoundingClientRect(); e.click(); return "tapped " + l + " at " + Math.round(r.x) + "," + Math.round(r.y) }
}; "ok"'
step() { ev "$HELP" >/dev/null; ev "new Promise(r => { __w.on(); setTimeout(() => r(__w.tap($(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"))), 600) })"; }
text() { ev "$HELP" >/dev/null; ev 'new Promise(r => { __w.on(); setTimeout(() => r(__w.text()), 600) })'; }

ev "$HELP" >/dev/null; ev '__w.on(); "semantics on"'; sleep 2
rec home "$(text)"; shot home
rec tap-places "$(step Places)"; sleep 12
rec places "$(text)"; shot places
rec tap-strategy "$(step Strategy)"; sleep 10
rec strategy "$(text)"; shot strategy
rec tap-lifecycle "$(step Lifecycle)"; sleep 4
rec tap-root-process "$(step 'root process')"; sleep 3
rec tap-start "$(step Start)"; sleep 6
rec lifecycle-running "$(text)"; shot lifecycle
adb shell input keyevent KEYCODE_HOME; sleep 5
"$HERE/managers/back_to_app.sh"; sleep 4
rec lifecycle-after-home "$(text)"; shot lifecycle-after-home
rec root-process "$(adb shell "ps -A -o USER,UID,LABEL,PID,NAME | grep -E 'demo|dartaot'" | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
