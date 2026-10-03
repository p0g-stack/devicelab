#!/usr/bin/env bash
# Copy flutter-aera's AERA patch series into patches/, replacing what is
# there (files dropped upstream do not linger), and write SOURCE.
#   aera/build/sync-patches.sh FLUTTER_AERA_CHECKOUT COMMIT
# bootable/recovery/ gets patches/, cuttlefish-patches/ (C*),
# refinement-patches/ (F*) and remote-patches/ (R*): name order is apply order.
# external/lvgl/ gets lvgl-patches/.
set -euo pipefail
src=$1 rev=$2
here=$(cd "$(dirname "$0")" && pwd)
rec=$here/patches/bootable/recovery lvgl=$here/patches/external/lvgl
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git -C "$src" archive "$rev" third_party/aera | tar -x -C "$tmp"
ta=$tmp/third_party/aera
mkdir -p "$rec" "$lvgl"
find "$rec" "$lvgl" -maxdepth 1 -name '*.patch' -delete
for d in patches cuttlefish-patches refinement-patches remote-patches; do
  [ -d "$ta/$d" ] && cp "$ta/$d"/*.patch "$rec/"
done
cp "$ta/lvgl-patches"/*.patch "$lvgl/"
short=$(git -C "$src" rev-parse --short "$rev")
echo "from p0g-stack/flutter-aera $short third_party/aera/patches, then cuttlefish-patches (C*), refinement-patches (F*), remote-patches (R*); name order = apply order" > "$rec/SOURCE"
echo "from p0g-stack/flutter-aera $short third_party/aera/lvgl-patches (series order = name order)" > "$lvgl/SOURCE"
echo "recovery: $(cd "$rec" && ls *.patch | sed 's/-.*//' | tr '\n' ' ')"
echo "lvgl:     $(cd "$lvgl" && ls *.patch | sed 's/-.*//' | tr '\n' ' ')"
