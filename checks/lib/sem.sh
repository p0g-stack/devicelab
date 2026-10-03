# Flutter web semantics helpers over DevTools (from demo_walk.sh): ev <js>, step <label> taps by label, text lists labels. Needs $WV.
ev() { $WV eval "$1" 2>&1 | tail -1; }
HELP='window.__w = window.__w || {
  on() { const p = document.querySelector("flt-semantics-placeholder"); if (!p) return; const r = p.getBoundingClientRect(), o = {bubbles: true, cancelable: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, pointerType: "touch", isPrimary: true}; for (const t of ["pointerdown", "pointerup"]) p.dispatchEvent(new PointerEvent(t, o)); p.dispatchEvent(new MouseEvent("click", o)); },
  nodes() { return [...document.querySelectorAll("flt-semantics")].filter(e => !e.querySelector("flt-semantics")) },
  text() { return [...document.querySelectorAll("flt-semantics")].map(e => (e.getAttribute("aria-label") || [...e.childNodes].filter(n => n.nodeType === 3 || n.tagName === "SPAN").map(n => n.textContent).join("")).trim()).filter(Boolean) },
  find(l) { const lab = e => (e.getAttribute("aria-label") || e.textContent || "").trim(); const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight }; const all = [...document.querySelectorAll("flt-semantics")].filter(vis); const btn = e => e.hasAttribute("flt-tappable") || e.getAttribute("role") === "button"; const exact = all.filter(e => lab(e) === l); return exact.find(btn) || exact[0] || all.filter(e => lab(e).startsWith(l)).sort((a, b) => btn(b) - btn(a) || lab(a).length - lab(b).length)[0] },
  tap(l) { const e = this.find(l); if (!e) return "no " + l; const r = e.getBoundingClientRect(); e.click(); return "tapped " + l + " at " + Math.round(r.x) + "," + Math.round(r.y) + " size " + Math.round(r.width) + "x" + Math.round(r.height) + " role " + e.getAttribute("role") + (e.hasAttribute("flt-tappable") ? " tappable" : "") }
}; "ok"'
step() { ev "$HELP" >/dev/null; ev "new Promise(r => { __w.on(); setTimeout(() => r(__w.tap($(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"))), 600) })"; }
text() { ev "$HELP" >/dev/null; ev 'new Promise(r => { __w.on(); setTimeout(() => r(__w.text()), 600) })'; }
# on <label>: true when a node with that label is on screen. scroll_to <label>:
# back to the top, then small upward swipes until it is (page layouts change
# between releases, so no fixed swipe count).
on() { ev "$HELP" >/dev/null; ev "new Promise(r => { __w.on(); setTimeout(() => r(!!__w.find($(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"))), 600) })" | grep -q '"value": *true'; }
scroll_to() {
  for _ in 1 2 3; do adb shell input swipe 160 160 160 500 200; sleep 1; done
  for _ in 1 2 3 4 5 6 7 8 9 10; do on "$1" && return 0; adb shell input swipe 160 420 160 300 400; sleep 1.5; done
  on "$1"
}
