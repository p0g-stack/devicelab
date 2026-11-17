#!/usr/bin/env bash
# Publish an aera/build/build.sh result as a devicelab release, where the
# Cuttlefish workflow picks it up. Usage: publish.sh OUT_DIR
set -euo pipefail
out=$(realpath "${1:?usage: publish.sh OUT_DIR}")
[ -f "$out/BUILD-INFO" ] && [ -f "$out/SHA256SUMS" ] || { echo "$out has no BUILD-INFO/SHA256SUMS"; exit 1; }
rec=$(awk '/^bootable\/recovery/ {print substr($2,1,7)}' "$out/BUILD-INFO")
sum=$(awk '$2 == "ramdisk-recovery.img" {print $1}' "$out/SHA256SUMS")
[[ "$sum" =~ ^[0-9a-f]{64}$ ]] || { echo "missing ramdisk SHA256" >&2; exit 1; }
rev=$(awk '/^devicelab/ {print $2}' "$out/BUILD-INFO")
[[ "$rev" =~ ^[0-9a-f]{40}$ ]] || { echo "missing devicelab commit" >&2; exit 1; }
tag="aera-cf-x86_64-$rec-${sum:0:16}"
files=("$out/BUILD-INFO" "$out/SHA256SUMS")
for f in "$out"/*.img "$out"/*.tgz "$out"/*.elf; do [ -f "$f" ] && files+=("$f"); done
gh release create "$tag" -R p0g-stack/devicelab --target "$rev" --prerelease \
  --title "AERA API 2 recovery for Cuttlefish x86_64 ($rec)" \
  --notes-file "$out/BUILD-INFO" "${files[@]}"
echo "published $tag"
