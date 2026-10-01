#!/usr/bin/env bash
# Sync AERA's Android 16 tree shallowly at the pin (android_manifest
# MANIFEST_REV + pins.xml), apply patches/<project path>/*.patch, drop in
# the Cuttlefish x86_64 device tree from ./device and build the recovery
# ramdisk.
#   build.sh SRC_DIR OUT_DIR      (needs ~100 GB free and repo's deps)
# Phases can be re-entered: sync is skipped if SRC_DIR/.repo exists.
set -euo pipefail
src=$(realpath -m "${1:?usage: build.sh SRC OUT}"); out=$(realpath -m "${2:?}")
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$src" "$out"
MANIFEST_REV=${MANIFEST_REV:-250b38eed4b7bb663a945deb3c4f12e4ff2339dd}
PATCHES=${AERA_PATCHES:-$here/patches}
command -v repo >/dev/null || { mkdir -p ~/.bin; curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/.bin/repo; chmod +x ~/.bin/repo; export PATH=~/.bin:$PATH; }
# The manifest names AERA's public repos over ssh; read them over https.
git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
git config --global user.name devicelab; git config --global user.email devicelab@users.noreply.github.com
git config --global color.ui false
cd "$src"
t0=$SECONDS
if [ ! -d .repo ]; then
  repo init -q --depth=1 --no-clone-bundle -u https://github.com/AERA-Recovery/android_manifest -b "$MANIFEST_REV" \
    --groups=default,-darwin,-mips,-notdefault
fi
mkdir -p .repo/local_manifests
cp .repo/manifests/remove-minimal.xml .repo/local_manifests/ 2>/dev/null || true
cp "$here/pins.xml" .repo/local_manifests/zz-pins.xml
repo sync -c -q --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune -j"$(nproc)" -j8 2>&1 | tail -30 \
  || repo sync -c -q --force-sync --no-clone-bundle --no-tags -j4 --fail-fast 2>&1 | tail -30
echo "[aera] sync $((SECONDS - t0))s; $(du -sh --exclude=out . 2>/dev/null | cut -f1)"; df -h "$src" | tail -1
# Patches: reset each patched project to its pin first, so reruns are clean.
(cd "$PATCHES" && find . -name '*.patch' -printf '%h\n' | sort -u) | while read -r d; do
  d=${d#./}; git -C "$d" reset -q --hard; git -C "$d" clean -qfd
  git -C "$d" am -q --3way "$PATCHES/$d"/*.patch && echo "[aera] patched $d: $(ls "$PATCHES/$d"/*.patch | wc -l) patch(es)"
done
repo manifest -r -o "$out/manifest-pinned.xml"
rm -rf device/p0g/aera_cf && mkdir -p device/p0g && cp -r "$here/device" device/p0g/aera_cf
t0=$SECONDS
set +u
source build/envsetup.sh >/dev/null
lunch twrp_aera_cf-bp2a-eng
set -u
export ALLOW_MISSING_DEPENDENCIES=true
m adbd recoveryimage 2>&1 | tee "$out/build.log" | grep -E "^(FAILED|error|ninja: build stopped)|\[ *[0-9]+% " | awk 'NR%200==1 || /FAILED|error|stopped/' || true
rc=${PIPESTATUS[0]}
echo "[aera] build rc=$rc in $((SECONDS - t0))s"
p=out/target/product/aera_cf
ls -la $p/*.img $p/*.lz4 2>/dev/null || true
cp $p/ramdisk-recovery.img $p/recovery.img "$out/" 2>/dev/null || true
[ -d $p/recovery/root ] && tar -C $p/recovery/root -czf "$out/recovery-root.tgz" .
exit $rc
