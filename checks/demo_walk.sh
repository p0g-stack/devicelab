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
  on() { const p = document.querySelector("flt-semantics-placeholder"); if (!p) return; const r = p.getBoundingClientRect(), o = {bubbles: true, cancelable: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, pointerType: "touch", isPrimary: true}; for (const t of ["pointerdown", "pointerup"]) p.dispatchEvent(new PointerEvent(t, o)); p.dispatchEvent(new MouseEvent("click", o)); },
  nodes() { return [...document.querySelectorAll("flt-semantics")].filter(e => !e.querySelector("flt-semantics")) },
  text() { return [...document.querySelectorAll("flt-semantics")].map(e => (e.getAttribute("aria-label") || [...e.childNodes].filter(n => n.nodeType === 3 || n.tagName === "SPAN").map(n => n.textContent).join("")).trim()).filter(Boolean) },
  find(l) { const lab = e => (e.getAttribute("aria-label") || e.textContent || "").trim(); const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight }; const all = [...document.querySelectorAll("flt-semantics")].filter(vis); const btn = e => e.hasAttribute("flt-tappable") || e.getAttribute("role") === "button"; const exact = all.filter(e => lab(e) === l); return exact.find(btn) || exact[0] || all.filter(e => lab(e).startsWith(l)).sort((a, b) => btn(b) - btn(a) || lab(a).length - lab(b).length)[0] },
  tap(l) { const e = this.find(l); if (!e) return "no " + l; const r = e.getBoundingClientRect(); e.click(); return "tapped " + l + " at " + Math.round(r.x) + "," + Math.round(r.y) + " size " + Math.round(r.width) + "x" + Math.round(r.height) + " role " + e.getAttribute("role") + (e.hasAttribute("flt-tappable") ? " tappable" : "") }
}; "ok"'
step() { ev "$HELP" >/dev/null; ev "new Promise(r => { __w.on(); setTimeout(() => r(__w.tap($(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"))), 600) })"; }
text() { ev "$HELP" >/dev/null; ev 'new Promise(r => { __w.on(); setTimeout(() => r(__w.text()), 600) })'; }

ev "$HELP" >/dev/null; ev '__w.on(); "semantics on"'; sleep 2
rec home "$(text)"; shot home
rec tap-places "$(step Places)"; sleep 12
rec places "$(text)"; shot places
# The root process place is further down: scroll and read again.
for n in 1 2 3; do adb shell input swipe 160 480 160 180 400; sleep 2; rec places-scroll-$n "$(text)"; shot places-scroll-$n; done
rec tap-strategy "$(step Strategy)"; sleep 10
rec strategy "$(text)"; shot strategy
rec tap-rust "$(step Rust)"; sleep 10
rec rust "$(text)"; shot rust
rec tap-rust-run "$(step 'Run in every place')"; sleep 20
rec rust-ran "$(text)"; shot rust-ran
rec tap-lifecycle "$(step Lifecycle)"; sleep 4
rec tap-root-process "$(step 'root process')"; sleep 3
rec tap-start "$(step Start)"; sleep 8
rec lifecycle-running "$(text)"; shot lifecycle
adb shell input keyevent KEYCODE_HOME; sleep 5
"$HERE/managers/back_to_app.sh"; sleep 4
rec lifecycle-after-home "$(text)"; shot lifecycle-after-home
rec root-process "$(adb shell "ps -A -o USER,UID,LABEL,PID,NAME | grep -E 'demo|dartaot'" | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
# block_devices=false in the root process place: an SELinux deny or a Dart
# open failure? The same probes as adb root (u:r:su) and as uid 0 in
# u:r:ksu:s0, the root launcher's domain (via sockprobe -as-ctx).
[ -n "${SOCKPROBE:-}" ] && adb push "$SOCKPROBE" /data/local/tmp/sockprobe >/dev/null && adb shell chmod 755 /data/local/tmp/sockprobe
B=$(adb shell "ls /sys/class/block | head -1" | tr -d '\r')
rec block-devices "$(adb shell "ls /sys/class/block | head -8; ls -lZ /dev/block | head -12; echo '-- su:'; head -c1 /dev/block/$B | od -c | head -1; echo '-- ksu:'; /data/local/tmp/sockprobe -as-uid 0 -as-ctx u:r:ksu:s0 /system/bin/sh -c 'cat /proc/self/attr/current; echo; for n in \$(ls /sys/class/block | head -4); do f=/dev/block/\$n; [ -e \$f ] || f=/dev/\$n; printf \"%s: \" \$f; head -c1 \$f >/dev/null && echo ok; done' 2>&1; echo '-- avc:'; dmesg | grep avc | grep -E 'blk_file|block_device' | tail -8" | tr -d '\r' | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')"
