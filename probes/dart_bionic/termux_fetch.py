#!/usr/bin/env python3
"""Download a Termux package and its dependency closure, unpacked into DEST.
Usage: termux_fetch.py <arch> <package> <dest>
Termux debs install to data/data/com.termux/files/usr; DEST mirrors that tree."""
import gzip, io, os, subprocess, sys, tarfile, urllib.request

REPO = "https://packages.termux.dev/apt/termux-main"
arch, root_pkg, dest = sys.argv[1:4]
idx = urllib.request.urlopen(f"{REPO}/dists/stable/main/binary-{arch}/Packages.gz").read()
pkgs, cur = {}, {}
for line in gzip.decompress(idx).decode().splitlines() + [""]:
    if not line.strip():
        if cur: pkgs[cur["Package"]] = cur
        cur = {}
    elif ":" in line and not line.startswith(" "):
        k, v = line.split(":", 1); cur[k] = v.strip()

seen, todo = [], [root_pkg]
while todo:
    p = todo.pop()
    if p in seen or p not in pkgs: continue
    seen.append(p)
    for d in pkgs[p].get("Depends", "").split(","):
        d = d.split("|")[0].split("(")[0].strip()
        if d: todo.append(d)
os.makedirs(dest, exist_ok=True)
for p in seen:
    info = pkgs[p]
    print(f"{p} {info['Version']}", flush=True)
    deb = urllib.request.urlopen(f"{REPO}/{info['Filename']}").read()
    tmp = os.path.join(dest, ".deb"); open(tmp, "wb").write(deb)
    subprocess.run(["dpkg-deb", "-x", tmp, dest], check=True); os.remove(tmp)
