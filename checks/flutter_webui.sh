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
ev 'window.__bk = []; addEventListener("message", e => __bk.push(["message", String(e.data).slice(0, 120), Math.round(performance.now())])); if (window.webui && webui.exit) { const x = webui.exit.bind(webui); try { webui.exit = (...a) => { __bk.push(["webui.exit", Math.round(performance.now())]); return x(...a) } } catch (e) { __bk.push(["wrap-failed", String(e)]) } } "ok"' >/dev/null
adb shell input keyevent KEYCODE_BACK; sleep 3
rec back-events "$(ev '({bk: window.__bk, vis: document.visibilityState})')"
rec back-at-root "$(adb shell dumpsys activity activities | grep -m1 -E 'topResumedActivity|mResumedActivity' | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
timeout 20 adb exec-out screencap -p >"$OUT/$LABEL-fw-after-back.png"
