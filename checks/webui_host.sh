#!/usr/bin/env bash
# Host checks inside a manager's WebUI WebView, driven over DevTools.
# Expects: booted AVD with a manager set up (managers/*.sh), the probe module
# installed, labserver on PATH as a static binary for the device ABI.
# Usage: webui_host.sh <label> <manager pkg> [module id] [name]   (default: the probe)
# Writes $LAB_OUT/<label>-webui.json.
set -uo pipefail
LABEL=$1; PKG=$2; ID=${3:-devicelab_probe}; NAME=${4:-devicelab probe}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"
J=$OUT/$LABEL-webui.jsonl; : >"$J"
rec() { echo "{\"check\":\"$1\",\"result\":$2}" | tee -a "$J"; }
ev() { $WV eval "$1" --match "${MATCH:-}" 2>&1 | tail -1; }

adb push "$LABSERVER" /data/local/tmp/labserver >/dev/null
adb shell "chmod 755 /data/local/tmp/labserver; pkill -f labserver; (nohup /data/local/tmp/labserver >/data/local/tmp/labserver.log 2>&1 &)"
"$HERE/managers/open_webui.sh" "$LABEL" "$PKG" "$ID" "$NAME"
sleep 2
adb exec-out screencap -p >"$OUT/$LABEL-webui.png"
rec targets "$($WV list | python3 -c 'import json,sys; print(json.dumps([{k:t.get(k) for k in ("socket","type","url","title")} for t in json.load(sys.stdin)]))')"
rec globals "$(ev '({ua: navigator.userAgent, origin: location.origin, href: location.href, globals: Object.keys(window).filter(k => /ksu|webui|mmrl|\$/i.test(k)), ksu: typeof ksu === "object" ? Object.keys(Object.getPrototypeOf(ksu)).concat(Object.keys(ksu)).concat((()=>{const a=[]; for (const k in ksu) a.push(k); return a})()) : null})')"
rec ksu-exec "$(ev 'new Promise(r => { window.__cb = (code, out, err) => r({code, out, err}); ksu.exec("id; cat /proc/self/attr/current", "{}", "__cb"); setTimeout(() => r("timeout"), 8000) })')"
rec ws-loopback "$(ev 'new Promise(r => { const t0 = performance.now(); const ws = new WebSocket("ws://127.0.0.1:8765/ws"); const got = []; ws.onopen = () => ws.send("hi"); ws.onmessage = e => { got.push(e.data); if (got.length == 2) { ws.close(); r({got, ms: Math.round(performance.now() - t0)}) } }; ws.onerror = () => r({error: "ws error"}); setTimeout(() => r({timeout: got}), 8000) })')"
rec fetch-loopback "$(ev 'fetch("http://127.0.0.1:8765/ping").then(r => r.json()).catch(e => ({error: String(e)}))')"
rec webview-uid "$(adb shell "ps -A -o USER,UID,NAME | grep -E 'webview|sandboxed|$PKG'" | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().splitlines()))')"

# Lifecycle: start a slow fetch, go HOME for 6s, come back, read what the page saw.
ev 'window.__slow = fetch("http://127.0.0.1:8765/slow?ms=3000").then(r => r.json()).then(j => ({...j, resolvedAt: Date.now(), vis: document.visibilityState})); window.__slow.then(v => window.__slowDone = v); "started"' >/dev/null
adb shell input keyevent KEYCODE_HOME; sleep 6
rec while-home-heartbeat "$(ev '({last: window.__lab.last, now: Math.round(performance.now()), vis: document.visibilityState})')"
"$HERE/managers/back_to_app.sh"; sleep 3
rec lifecycle "$(ev '({events: window.__lab.events, gaps: window.__lab.gaps, slow: window.__slowDone ?? "pending"})')"
adb shell cat /data/local/tmp/labserver.log >"$OUT/$LABEL-labserver.log"
python3 - "$J" "$OUT/$LABEL-webui.json" "$LABEL" <<'PY'
import json, sys, subprocess, datetime
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
p = lambda *a: subprocess.run(["adb", "shell", *a], capture_output=True, text=True).stdout.strip()
json.dump({"check": "webui_host", "label": sys.argv[3], "date": datetime.date.today().isoformat(),
           "fingerprint": p("getprop", "ro.build.fingerprint"), "kernel": p("uname", "-r"),
           "webview": p("dumpsys package com.google.android.webview | grep -m1 versionName"),
           "results": rows}, open(sys.argv[2], "w"), indent=1)
PY
