#!/usr/bin/env python3
"""uiautomator helpers for driving a manager's UI over adb.

  ui.py dump [file]            print clickable nodes (text/desc of their subtree, bounds)
  ui.py tap <text> [--desc]    tap the nearest clickable ancestor of the first node
                               whose text (or content-desc) contains <text>
  ui.py has <text>             exit 0 if some node's text or desc contains <text>
  ui.py switch [n]             tap the n-th (default 1st) checkable node (a switch)
tap and has keep re-dumping for up to UI_WAIT seconds (default 12) until the
node shows up, and dismiss "isn't responding" dialogs with Wait on the way
(the emulator renders slowly; a dump taken too early has an empty list).
"""
import os, re, subprocess, sys, time, xml.etree.ElementTree as ET

def adb(*a):
    return subprocess.run(["adb", *a], capture_output=True, text=True).stdout

def dump(save=None):
    for _ in range(3):
        adb("shell", "uiautomator", "dump", "/data/local/tmp/ui.xml")
        x = adb("shell", "cat", "/data/local/tmp/ui.xml")
        if x.startswith("<?xml"):
            break
    if save:
        open(save, "w").write(x)
    return ET.fromstring(x.encode())

def center(n):
    a, b, c, d = map(int, re.findall(r"\d+", n.get("bounds")))
    return (a + c) // 2, (b + d) // 2

def label(n):
    return " | ".join(t for e in n.iter() for t in (e.get("text"), e.get("content-desc")) if t)

def walk(root):
    parent = {c: p for p in root.iter() for c in p}
    return parent

def main():
    cmd = sys.argv[1]
    root = dump(sys.argv[2] if cmd == "dump" and len(sys.argv) > 2 else None)
    if cmd == "dump":
        for n in root.iter("node"):
            if n.get("clickable") == "true":
                print(n.get("bounds"), label(n)[:120])
        return 0
    if cmd == "switch":
        sw = [n for n in root.iter("node") if n.get("checkable") == "true"]
        k = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        if len(sw) < k:
            print("ui: no switch"); return 1
        n = sw[k - 1]; adb("shell", "input", "tap", *map(str, center(n)))
        print(f"ui: tapped switch {k} ({label(n)[:60]!r}, was checked={n.get('checked')})"); return 0
    want = sys.argv[2]
    find = lambda r, w: next((n for n in r.iter("node") if w == (n.get("text") or "") or w == (n.get("content-desc") or "")), None) \
        or next((n for n in r.iter("node") if w in (n.get("text") or "") or w in (n.get("content-desc") or "")), None)
    end = time.time() + float(os.environ.get("UI_WAIT", "12"))
    while True:
        hit = find(root, want)
        if hit is not None or time.time() > end:
            break
        anr = find(root, "Wait")
        if anr is not None and find(root, "Close app") is not None:
            adb("shell", "input", "tap", *map(str, center(anr))); print("ui: dismissed ANR dialog")
        time.sleep(1.5); root = dump()
    if cmd == "has":
        return 0 if hit is not None else 1
    if hit is None:
        print(f"ui: no node with {want!r}"); return 1
    parent = walk(root); n = hit
    while n is not None and n.get("clickable") != "true":
        n = parent.get(n)
    x, y = center(n if n is not None else hit)
    adb("shell", "input", "tap", str(x), str(y))
    print(f"ui: tapped {want!r} at {x},{y}"); return 0

sys.exit(main())
