#!/usr/bin/env bash
# Publish an aera/build/build.sh result as a devicelab release, where the
# Cuttlefish workflow picks it up. Usage: publish.sh OUT_DIR
set -euo pipefail
out=$(realpath "${1:?usage: publish.sh OUT_DIR}")
[ -f "$out/BUILD-INFO" ] && [ -f "$out/SHA256SUMS" ] || { echo "$out has no BUILD-INFO/SHA256SUMS"; exit 1; }
rec=$(awk '/^bootable\/recovery/ {print substr($2,1,7)}' "$out/BUILD-INFO")
pat=$(awk '/^patches/ {print $2}' "$out/BUILD-INFO")
tag="aera-cf-x86_64-$rec-${pat:-nopatch}"
files=("$out/BUILD-INFO" "$out/SHA256SUMS")
for f in "$out"/*.img "$out"/*.tgz; do [ -f "$f" ] && files+=("$f"); done
gh release create "$tag" -R p0g-stack/devicelab --prerelease --title "AERA recovery for Cuttlefish x86_64 ($rec, patches $pat)" \
  --notes-file "$out/BUILD-INFO" "${files[@]}" \
  || gh release upload "$tag" -R p0g-stack/devicelab --clobber "${files[@]}"
echo "published $tag"
