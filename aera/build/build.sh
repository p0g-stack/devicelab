#!/usr/bin/env bash
# Build AERA Recovery's ramdisk for Cuttlefish x86_64, reproducibly:
#   AERA android_manifest @ MANIFEST_REV  +  pins.xml (every AERA project by
#   commit)  +  patches/<project path>/*.patch (git am, name order)  +
#   device/ (the aera_cf device tree)  ->  `m adbd recoveryimage`.
#
#   aera/build/build.sh [SRC_DIR] [OUT_DIR]
#     SRC_DIR  Android tree, default ~/aera-src (reused on reruns)
#     OUT_DIR  results, default ./aera-out
#
# Unattended on a stock Ubuntu 22.04/24.04 x86_64 box with sudo. Needs about
# 150 GB free and 32 GB RAM (+swap); 16+ cores keeps it to a few hours.
# Env: MANIFEST_REV, AERA_PATCHES (patch dir), NO_APT=1 (skip apt),
#      JOBS (default nproc), SKIP_SYNC=1 (reuse SRC_DIR as is).
# Ends by printing the image paths and their sha256; see README.md for
# publishing them as a devicelab release.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(realpath -m "${1:-$HOME/aera-src}"); out=$(realpath -m "${2:-$PWD/aera-out}")
MANIFEST_REV=${MANIFEST_REV:-250b38eed4b7bb663a945deb3c4f12e4ff2339dd}
PATCHES=$(realpath -m "${AERA_PATCHES:-$here/patches}")
# Devicelab-only fakes (Cuttlefish stand-ins, not upstream fixes), applied
# after the series; AERA_PATCHES_CF= (empty) leaves them out.
PATCHES_CF=$(realpath -m "${AERA_PATCHES_CF-$here/patches-cf}")
JOBS=${JOBS:-$(nproc)}
mkdir -p "$src" "$out"
exec > >(tee -a "$out/build.log") 2>&1
log() { echo "[aera $(date -u +%H:%M:%S)] $*"; }

# Preflight
[ "$(uname -m)" = x86_64 ] || { log "needs an x86_64 Linux host"; exit 1; }
free_gb=$(df -BG --output=avail "$src" | tail -1 | tr -dc 0-9)
mem_gb=$(awk '/MemTotal/ {print int($2/1048576)}' /proc/meminfo)
swap_gb=$(awk '/SwapTotal/ {print int($2/1048576)}' /proc/meminfo)
log "host: $JOBS jobs, ${mem_gb} GB RAM + ${swap_gb} GB swap, ${free_gb} GB free at $src"
(( free_gb < 120 )) && log "WARNING: under 120 GB free; the sync + out/ needs ~150 GB"
(( mem_gb + swap_gb < 32 )) && log "WARNING: under 32 GB RAM+swap; Soong may be OOM-killed (add swap)"

if [ "${NO_APT:-0}" != 1 ] && command -v apt-get >/dev/null; then
  log "installing build packages (apt)"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git gnupg flex bison build-essential zip curl \
    zlib1g-dev libc6-dev-i386 x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc \
    unzip fontconfig python3 python-is-python3 rsync bc cpio lz4 openssl libssl-dev >/dev/null
fi
if ! command -v repo >/dev/null; then
  mkdir -p "$HOME/.bin"; curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/.bin/repo"
  chmod +x "$HOME/.bin/repo"; export PATH=$HOME/.bin:$PATH
fi
# The manifest names AERA's public repos over ssh; read them over https
# without touching the user's git config.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf GIT_CONFIG_VALUE_0=ssh://git@github.com/
git config --global user.name >/dev/null || git config --global user.name "aera-lab"
git config --global user.email >/dev/null || git config --global user.email "aera-lab@localhost"

cd "$src"
if [ "${SKIP_SYNC:-0}" != 1 ]; then
  t0=$SECONDS
  log "repo init android_manifest@$MANIFEST_REV"
  repo init -q --depth=1 --no-clone-bundle --no-use-superproject \
    -u https://github.com/AERA-Recovery/android_manifest -b "$MANIFEST_REV" --groups=default,-darwin,-mips,-notdefault
  mkdir -p .repo/local_manifests
  cp "$here/pins.xml" .repo/local_manifests/zz-pins.xml   # remove-minimal.xml is already included by the manifest
  for try in 1 2 3; do
    log "repo sync (attempt $try)"
    repo sync -c -q --force-sync --no-clone-bundle --no-tags --optimized-fetch -j"$JOBS" && break
    [ $try = 3 ] && { log "sync failed"; exit 1; }; sleep 30
  done
  log "sync done in $((SECONDS - t0))s; $(du -sh --exclude=out . | cut -f1)"
fi

# Patches: reset each patched project to its pin first, so reruns are
# clean; then the series, then the devicelab-only fakes.
projects=$(for p in "$PATCHES" "$PATCHES_CF"; do [ -d "$p" ] && (cd "$p" && find . -name '*.patch' -printf '%h\n'); done | sed 's#^\./##' | sort -u)
for d in $projects; do
  git -C "$d" am --abort >/dev/null 2>&1 || true
  pin=$(repo forall "$d" -c 'echo $REPO_RREV')   # the commit pins.xml names
  git -C "$d" reset -q --hard "$pin"
  git -C "$d" clean -qfd
  for p in "$PATCHES" "$PATCHES_CF"; do
    ls "$p/$d"/*.patch >/dev/null 2>&1 || continue
    git -C "$d" am -q --3way "$p/$d"/*.patch
    log "patched $d from ${p#$here/}: $(ls "$p/$d"/*.patch | wc -l) patch(es), now $(git -C "$d" log --oneline -1)"
  done
done
repo manifest -r -o "$out/manifest-pinned.xml" >/dev/null 2>&1 || log "WARNING: repo manifest -r failed (unsynced projects?)"

rm -rf device/p0g/aera_cf && mkdir -p device/p0g && cp -r "$here/device" device/p0g/aera_cf

t0=$SECONDS
log "building twrp_aera_cf-bp2a-eng: adbd recoveryimage"
set +eu
source build/envsetup.sh >/dev/null
lunch twrp_aera_cf-bp2a-eng || { log "lunch failed"; exit 1; }
m -j"$JOBS" adbd recoveryimage
rc=$?
set -eu
log "build rc=$rc in $((SECONDS - t0))s"
p=$src/out/target/product/aera_cf
[ $rc = 0 ] || { log "see $out/build.log (search for FAILED:)"; exit $rc; }

# Results
for f in ramdisk-recovery.img recovery.img; do [ -f "$p/$f" ] && cp "$p/$f" "$out/"; done
# Unstripped recovery binary (same BuildID as the one in the ramdisk), for
# addr2line on crashes: there is no crash_dump in recovery.
[ -f "$p/symbols/recovery/root/system/bin/recovery" ] && cp "$p/symbols/recovery/root/system/bin/recovery" "$out/recovery-unstripped.elf"
[ -d "$p/recovery/root" ] && tar -C "$p/recovery/root" -czf "$out/recovery-root.tgz" .
ls "$p"/AERA*.zip "$p"/AERA*.img 2>/dev/null | while read -r f; do cp "$f" "$out/"; done
(cd "$out" && sha256sum ./*.img ./*.tgz ./*.zip ./*.elf 2>/dev/null | sed 's# \./# #' > SHA256SUMS)
{
  echo "android_manifest $MANIFEST_REV"
  echo "bootable/recovery $(git -C bootable/recovery rev-parse HEAD)"
  echo "patches $( (cd "$PATCHES" 2>/dev/null && find . -name '*.patch' | sort | xargs -r sha256sum; cd "$PATCHES_CF" 2>/dev/null && find . -name '*.patch' | sort | xargs -r sha256sum) | sha256sum | cut -c1-16)"
  (cd "$PATCHES" && find . -name SOURCE | sort | while read -r f; do echo "patch-source ${f#./} $(head -1 "$f")"; done)
  (cd "$PATCHES" 2>/dev/null && find . -name '*.patch' | sort | sed 's#^\./#patch #')
  (cd "$PATCHES_CF" 2>/dev/null && find . -name '*.patch' | sort | sed 's#^\./#fake #')
  echo "devicelab $(git -C "$here" rev-parse HEAD 2>/dev/null)"
  echo "built $(date -u +%FT%TZ) on $(hostname)"
} > "$out/BUILD-INFO"
log "done. Results in $out:"
cat "$out/BUILD-INFO"
echo; cat "$out/SHA256SUMS"
