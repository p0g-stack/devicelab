#!/usr/bin/env bash
# Install a KernelSU metamodule (3.x mounts module system/ only through one).
# KernelSU's official one, meta-overlayfs, moved out of tiann/KernelSU
# (3e8b4a7, "Moved to module repo"): look it up in the module repo index and
# take its latest release zip. Records which one, its version and sha256.
# Usage: metamodule.sh [module id, default meta-overlayfs]   needs gh, adb
set -uo pipefail
ID=${1:-meta-overlayfs}; OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
D=$(mktemp -d)
curl -fsSL https://modules.kernelsu.org/modules.json -o "$D/index.json" || echo "== metamodule: module repo index unreachable"
python3 - "$D/index.json" "$ID" >"$D/entry.txt" <<'P'
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception as e: print("index unreadable", e); sys.exit()
d = d if isinstance(d, list) else d.get("modules", [])
for m in d:
    if sys.argv[2] in (m.get("moduleId"), m.get("id"), m.get("name")):
        print(json.dumps(m)[:2000]); break
else: print("not in index")
P
echo "== metamodule index entry: $(cat "$D/entry.txt")"
cp "$D/index.json" "$OUT/ksu-modules-index.json" 2>/dev/null
# Repo: the index entry's url/source, else KernelSU-Modules-Repo/<id>.
REPO=$(python3 -c 'import json,sys,re; s=open(sys.argv[1]).read(); m=re.search(r"github\.com/([\w.-]+/[\w.-]+)", s); print(m.group(1).removesuffix(".git") if m else "")' "$D/entry.txt")
REPO=${REPO:-KernelSU-Modules-Repo/$ID}
gh release view -R "$REPO" --json tagName,publishedAt,assets --jq '"== metamodule release: '"$REPO"' \(.tagName) \(.publishedAt) \([.assets[].name]|join(" "))"' 2>&1
gh release download -R "$REPO" -D "$D/rel" -p '*.zip' 2>&1 | tail -2
Z=$(ls "$D"/rel/*.zip 2>/dev/null | head -1)
[ -n "$Z" ] || { echo "== metamodule: no zip found for $REPO"; exit 1; }
echo "== metamodule zip: $(basename "$Z") sha256 $(sha256sum "$Z" | cut -c1-64)"
echo "== metamodule module.prop: $(unzip -p "$Z" module.prop | tr -d '\r' | tr '\n' ' ')"
"$HERE/managers/install_modules.sh" "$Z"
echo "== metamodule active: $(adb shell 'ls -la /data/adb/metamodule; cat /data/adb/metamodule/module.prop' 2>&1 | tr -d '\r' | tr '\n' ' ')"
