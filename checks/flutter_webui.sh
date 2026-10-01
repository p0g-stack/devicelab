#!/usr/bin/env bash
# flutter-webui's own checks on a module page already open in a host
# (managers/open_webui.sh): root channel start through the bridge,
# session.json, WebSocket hello, the channel's uid/context/runtime,
# visibility+focus across Home/resume, then Back at the root route.
# Usage: flutter_webui.sh <label> <module id>     writes $LAB_OUT/<label>-fw.jsonl
set -uo pipefail
LABEL=$1; ID=${2:-flutter_webui_counter}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"; J=$OUT/$LABEL-fw.jsonl; : >"$J"
rec() { echo "{\"check\":\"$1\",\"result\":$2}" | tee -a "$J"; }
ev() { $WV eval "$1" 2>&1 | tail -1; }
M=/data/adb/modules/$ID
rec root-start "$(ev "new Promise(r => { const t0 = performance.now(); window.__fwcb = (code, out, err) => r({code, out, err, ms: Math.round(performance.now() - t0)}); ksu.exec(\"sh '$M/flutter_webui/root' start\", '{}', '__fwcb'); setTimeout(() => r('timeout'), 10000) })")"
rec session "$(ev 'new Promise(async r => { const t0 = performance.now(); while (performance.now() - t0 < 6000) { try { const x = await fetch("/.run/session.json?n=" + Math.random(), {cache: "no-store"}); if (x.ok) { const s = await x.json(); window.__fws = s; return r({status: x.status, ms: Math.round(performance.now() - t0), protocol: s.protocol, version: s.version, port: s.port, pid: s.pid, tokenLen: (s.token || "").length}) } } catch (e) {} await new Promise(q => setTimeout(q, 100)) } r("no session.json after 6s") })')"
rec ws-hello "$(ev 'new Promise(r => { const s = window.__fws; if (!s) return r("no session"); const ws = new WebSocket(`ws://127.0.0.1:${s.port}/v1?token=${s.token}`); ws.onmessage = e => { r({first: String(e.data).slice(0, 400)}); ws.close() }; ws.onerror = () => r({error: "ws error"}); setTimeout(() => r("timeout"), 6000) })')"
PID=$(adb shell "cat $M/webroot/.run/session.json 2>/dev/null" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["pid"])
except Exception: print("")')
rec channel-process "$(adb shell "[ -n '$PID' ] && { ps -o USER,UID,LABEL,PID,NAME -p $PID; echo exe=\$(readlink /proc/$PID/exe); tr '\\0' ' ' </proc/$PID/cmdline; echo; ls $M/flutter_webui/; ls $M/flutter_webui/*/ | head -20; }" | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
rec root-log "$(adb shell "tail -20 $M/webroot/.run/root.log 2>&1" | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
rec session-mode "$(adb shell "ls -la $M/webroot/.run/ 2>&1" | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
# Home / resume: what the page sees.
ev 'window.__fwev = []; for (const t of ["visibilitychange", "pagehide", "pageshow", "freeze", "resume"]) document.addEventListener(t, () => __fwev.push([t, document.visibilityState, Math.round(performance.now())]), true); for (const t of ["focus", "blur", "pagehide", "pageshow"]) addEventListener(t, () => __fwev.push(["window:" + t, document.visibilityState, Math.round(performance.now())]), true); window.__fwtick = 0; setInterval(() => __fwtick++, 250); "ok"' >/dev/null
adb shell input keyevent KEYCODE_HOME; sleep 5
"$HERE/managers/back_to_app.sh"; sleep 3
rec home-resume "$(ev '({events: window.__fwev, ticks: window.__fwtick, vis: document.visibilityState, hasFocus: document.hasFocus()})')"
timeout 20 adb exec-out screencap -p >"$OUT/$LABEL-fw-resumed.png"
# Back at the root route: does the host close the WebUI? On WebUI X, does
# WX_ON_BACK reach the page and does the page call webui.exit()?
top() { adb shell dumpsys activity activities | grep -m1 -E 'topResumedActivity|mResumedActivity' | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec before-back "$(ev 'window.__bk = []; const T = () => Math.round(performance.now()); addEventListener("message", e => __bk.push(["message", String(e.data).slice(0, 120), T()])); addEventListener("popstate", e => __bk.push(["popstate", JSON.stringify(e.state), history.length, T()])); addEventListener("error", e => __bk.push(["error", String(e.message), T()])); addEventListener("unhandledrejection", e => __bk.push(["unhandledrejection", String(e.reason).slice(0, 160), T()])); for (const k of ["log", "info", "warn", "error", "debug"]) { const o = console[k]; console[k] = (...a) => { __bk.push(["console." + k, a.map(String).join(" ").slice(0, 200), T()]); return o.apply(console, a) } } let wrapped = "no webui.exit"; if (window.webui && typeof webui.exit === "function") { const x = webui.exit; const w = (...a) => { __bk.push(["webui.exit", T()]); return x.apply(webui, a) }; try { webui.exit = w } catch (e) {} wrapped = webui.exit === w ? "wrapped" : "not writable" } ({historyLength: history.length, historyState: JSON.stringify(history.state), href: location.href, typeofWebui: typeof window.webui, typeofWebuiExit: typeof (window.webui && webui.exit), typeofKsuExit: typeof (window.ksu && ksu.exit), webuiKeys: window.webui ? Object.keys(window.webui).slice(0, 40) : null, wrapped})')"
adb logcat -c
adb shell input keyevent KEYCODE_BACK; sleep 3
rec back-events "$(ev '({bk: window.__bk, vis: document.visibilityState, historyLength: history.length, historyState: JSON.stringify(history.state)})')"
rec back-console "$(adb logcat -d | grep -E 'CONSOLE|chromium' | tail -30 | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip().splitlines()))')"
rec back-at-root "$(top)"
timeout 20 adb exec-out screencap -p >"$OUT/$LABEL-fw-after-back.png"
# Does the host's exit itself close the WebUI? Call it by hand.
if grep -q WebUIActivity <<<"$(top)"; then
  rec manual-exit "$(ev 'new Promise(r => { const f = window.webui && webui.exit ? "webui.exit" : window.ksu && ksu.exit ? "ksu.exit" : null; if (!f) return r("no exit"); setTimeout(() => { try { f === "webui.exit" ? webui.exit() : ksu.exit() } catch (e) { __bk.push(["exit threw", String(e)]) } }, 50); r(f) })' --timeout-s 10)"
  sleep 3; rec after-manual-exit "$(top)"
fi
