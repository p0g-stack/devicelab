#!/usr/bin/env bash
# Install a KernelSU metamodule (3.x mounts module system/ only through one).
# KernelSU's official one, meta-overlayfs, moved out of tiann/KernelSU
# (3e8b4a7, "Moved to module repo"): look it up in the module repo index and
# take its latest release zip. Records which one, its version and sha256.
# Usage: metamodule.sh [module id | owner/repo | search:<words>]   needs gh, adb
# (owner/repo and search: take the latest release zip whose module.prop has
# metamodule=1; Yuv 23:52Z: forks and other metamodules, e.g. hybrid mount, are fine)
set -uo pipefail
ARG=${1:-meta-overlayfs}; ID=${ARG##*/}; ID=${ID#search:}
case $ARG in */*) REPO_GIVEN=$ARG;; esac; OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
D=$(mktemp -d)
pick() { # <repo>: latest release zip with metamodule=1 in module.prop -> $Z
  rm -rf "$D/rel"; gh release download -R "$1" -D "$D/rel" -p '*.zip' >/dev/null 2>&1 || return 1
  for z in "$D"/rel/*.zip; do echo "== metamodule candidate $1 $(basename "$z"): $(unzip -p "$z" module.prop 2>/dev/null | tr -d '\r' | grep -E '^(id|version|versionCode|metamodule)=' | tr '\n' ' ')"; done
  for z in "$D"/rel/*.zip; do unzip -p "$z" module.prop 2>/dev/null | grep -q -E '^metamodule=(1|true)' && { Z=$z; REPO=$1; return 0; }; done; return 1; }
Z=
if [ -n "${REPO_GIVEN:-}" ]; then pick "$REPO_GIVEN" && echo "== metamodule repo (given): $REPO_GIVEN"; fi
case $ARG in search:*)
  gh api "search/repositories?q=$ID+in:name,description,topics&sort=stars&per_page=15" --jq '.items[]|"\(.full_name) \(.stargazers_count)"' >"$D/cands.txt" 2>&1
  echo "== metamodule candidates ($ID): $(tr '\n' ';' <"$D/cands.txt")"
  while read -r r _; do pick "$r" && { echo "== metamodule repo (search): $r"; break; }; done <"$D/cands.txt";;
esac
if [ -z "$Z" ]; then
curl -sSL -A "Mozilla/5.0 devicelab" -w "%{http_code}" https://modules.kernelsu.org/modules.json -o "$D/index.json" | sed "s/^/== metamodule index http: /"
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
# Not in the index: search GitHub for the repo (KernelSU-Modules-Repo or tiann first).
if [ -z "$REPO" ]; then
  gh api "search/repositories?q=$ID+in:name&per_page=20" --jq '.items[]|"\(.full_name) \(.stargazers_count) \(.pushed_at)"' >"$D/search.txt" 2>&1
  echo "== metamodule search: $(tr '\n' ';' <"$D/search.txt")"
  REPO=$(grep -m1 -i -E '^(KernelSU-Modules-Repo|tiann)/' "$D/search.txt" | cut -d' ' -f1)
fi
REPO=${REPO:-KernelSU-Modules-Repo/$ID}
gh release view -R "$REPO" --json tagName,publishedAt,assets --jq '"== metamodule release: '"$REPO"' \(.tagName) \(.publishedAt) \([.assets[].name]|join(" "))"' 2>&1
gh release download -R "$REPO" -D "$D/rel" -p '*.zip' 2>&1 | tail -2
Z=$(ls "$D"/rel/*.zip 2>/dev/null | head -1)
# The manager's own route: modules.kernelsu.org/module/<id>.json (ModuleRepoApi.kt) -> releases.
if [ -z "$Z" ]; then
  code=$(curl -sSL -A "Mozilla/5.0 devicelab" -w "%{http_code}" "https://modules.kernelsu.org/module/$ID.json" -o "$D/detail.json")
  cp "$D/detail.json" "$OUT/ksu-module-$ID.json" 2>/dev/null
  echo "== metamodule detail http: $code keys: $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(list(d)[:20]); r=(d.get("releases") or [{}])[0]; print("release0", {k: (v if len(str(v))<120 else "...") for k,v in r.items() if k!="descriptionHTML"})' "$D/detail.json" 2>&1 | tr '\n' ' ')"
  U=$(grep -o 'https://[^"]*\.zip' "$D/detail.json" | head -1)
  echo "== metamodule zip url: $U"
  [ -n "$U" ] && mkdir -p "$D/rel" && curl -fsSL -A "Mozilla/5.0 devicelab" "$U" -o "$D/rel/$ID.zip" && Z=$D/rel/$ID.zip
fi
# Last resort: KernelSU's own releases from the weeks it built meta-overlayfs
# in-tree (3630d67 2025-11-17 .. 3e8b4a7 2025-11-21), and the module repo org.
if [ -z "$Z" ]; then
  echo "== metamodule org repos: $(gh api 'orgs/KernelSU-Modules-Repo/repos?per_page=100&sort=pushed' --jq '.[].name' 2>&1 | grep -i meta | tr '\n' ' ')"
  for t in v3.0.0 v3.1.0 v3.2.0; do
    gh release download -R tiann/KernelSU "$t" -D "$D/rel" -p 'meta-overlayfs*.zip' >/dev/null 2>&1 && { echo "== metamodule from tiann/KernelSU release $t"; break; }
  done
  Z=$(ls "$D"/rel/*.zip 2>/dev/null | head -1)
fi
fi
[ -n "$Z" ] || { echo "== metamodule: no zip found for $REPO"; exit 1; }
echo "== metamodule zip: $(basename "$Z") sha256 $(sha256sum "$Z" | cut -c1-64)"
echo "== metamodule module.prop: $(unzip -p "$Z" module.prop | tr -d '\r' | tr '\n' ' ')"
"$HERE/managers/install_modules.sh" "$Z"
echo "== metamodule active: $(adb shell 'ls -la /data/adb/metamodule; cat /data/adb/metamodule/module.prop' 2>&1 | tr -d '\r' | tr '\n' ' ')"
