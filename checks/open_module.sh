#!/usr/bin/env bash
# Open one module's WebUI in the manager and record what a person would see:
# screenshots over time, DevTools targets, console-visible state, and for
# Flutter pages the first-frame time. Usage: open_module.sh <label> <pkg> <module id> [name]
set -uo pipefail
LABEL=$1; PKG=$2; ID=$3; NAME=${4:-$3}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"
J=$OUT/$LABEL.jsonl; : >"$J"
rec() { echo "{\"check\":\"$1\",\"result\":$2}" | tee -a "$J"; }
ev() { $WV eval "$1" 2>&1 | tail -1; }
"$HERE/managers/open_webui.sh" "$LABEL" "$PKG" "$ID" "$NAME"
for t in 2 6 15; do sleep $(( t == 2 ? 2 : t == 6 ? 4 : 9 )); adb exec-out screencap -p >"$OUT/$LABEL-${t}s.png"; done
rec targets "$($WV list | python3 -c 'import json,sys; print(json.dumps([{k:t.get(k) for k in ("type","url","title")} for t in json.load(sys.stdin)]))')"
rec page "$(ev '({href: location.href, title: document.title, ready: document.readyState, flutter: !!window._flutter, glass: !!document.querySelector("flt-glass-pane, flutter-view"), nav: performance.getEntriesByType("navigation").map(e => ({dcl: Math.round(e.domContentLoadedEventEnd), load: Math.round(e.loadEventEnd)}))[0], paint: Object.fromEntries(performance.getEntriesByType("paint").map(e => [e.name, Math.round(e.startTime)])), glassAt: (() => { const g = document.querySelector("flt-glass-pane, flutter-view"); return g ? "present" : null })(), firstFrame: window.__devicelabFirstFrame ?? null, insets: getComputedStyle(document.documentElement).getPropertyValue("--safe-area-inset-top") || null, vv: [innerWidth, innerHeight, devicePixelRatio]})')"
rec console-errors "$(adb logcat -d -s chromium:* | tail -30 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))')"
# Flutter: reload with a first-frame listener installed before page scripts.
# Cold: the first open above (paint entries = first canvas draw; WebView and
# canvaskit.wasm compile cold). Warm: this reload in the same WebView.
rec first-frame-warm "$($WV eval '({firstFrameMs: window.__ff ?? null, now: Math.round(performance.now()), flutter: !!window._flutter, resizes: window.__rs, paint: Object.fromEntries(performance.getEntriesByType("paint").map(e => [e.name, Math.round(e.startTime)]))})' --preload 'window.__rs = []; addEventListener("resize", () => window.__rs.push([Math.round(performance.now()), innerWidth, innerHeight])); addEventListener("flutter-first-frame", () => { window.__ff = Math.round(performance.now()) })' --wait-ms 15000 2>&1 | tail -1)"
adb exec-out screencap -p >"$OUT/$LABEL-reloaded.png"
