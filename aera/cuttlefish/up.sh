#!/usr/bin/env bash
# Boot a headless x86_64 Cuttlefish with adb root. Needs /dev/kvm and sudo
# (GitHub's ubuntu-24.04 runners have both).
# Usage: up.sh [branch/target] [build_id]
#   defaults: aosp-android-latest-release/aosp_cf_x86_64_only_phone-userdebug, latest
# Leaves: $CF_HOME (images + runtime), adb on 0.0.0.0:6520; frames via shot.sh.
set -euo pipefail
BUILD=${1:-aosp-android-latest-release/aosp_cf_x86_64_only_phone-userdebug}
BID=${2:-}
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}; mkdir -p "$CF_HOME"
log() { echo "[cf] $*"; }

if ! command -v cvd >/dev/null; then
  log "installing cuttlefish host packages"
  sudo curl -fsSL https://us-apt.pkg.dev/doc/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/artifact-registry.asc
  echo "deb https://us-apt.pkg.dev/projects/android-cuttlefish-artifacts android-cuttlefish main" \
    | sudo tee /etc/apt/sources.list.d/artifact-registry.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq cuttlefish-base cuttlefish-user >/dev/null
  sudo usermod -aG kvm,cvdnetwork,render "$USER"
fi
dpkg -l cuttlefish-base | tail -1 | tee "$OUT/cf-host.txt"
# sudo -u re-reads the group database, so the new groups apply without a re-login.
# EGL_PLATFORM=surfaceless: the runner has no display, so Mesa's default EGL
# display (used by Cuttlefish's graphics check and virglrenderer) must not
# look for X11/Wayland.
asme() { sudo -u "$USER" -H env HOME="$CF_HOME" PATH="$PATH" EGL_PLATFORM=surfaceless "$@"; }

if [ ! -x "$CF_HOME/bin/launch_cvd" ]; then
  spec=$BUILD; [ -n "$BID" ] && spec="$BID/${BUILD#*/}"
  log "fetching $spec"
  asme cvd fetch --default_build="$spec" --target_directory="$CF_HOME" 2>&1 | tail -20 || {
    asme cvd help fetch 2>&1 | head -60; exit 1; }
fi
ls "$CF_HOME" | tee "$OUT/cf-images.txt"
grep -h -m1 ro.build.fingerprint "$CF_HOME"/*.prop 2>/dev/null || true

# crosvm's sandboxed device processes die on the runner ("failed to create
# a PCI root hub ... Connection reset by peer"), hence --enable_sandbox=false.
# drm_virgl: virglrenderer in crosvm renders guest GL through the host's EGL
# (llvmpipe on a GPU-less runner), giving the guest /dev/dri/renderD128.
GPU=${CF_GPU:-drm_virgl}
[ "$GPU" = drm_virgl ] && sudo apt-get install -y -qq libegl1 libgles2 libgl1-mesa-dri mesa-libgallium >/dev/null 2>&1
launch() {
  log "launching (gpu_mode=$1)"
  asme "$CF_HOME/bin/launch_cvd" --daemon --report_anonymous_usage_stats=n \
    --cpus "${CF_CPUS:-2}" --memory_mb "${CF_MEM:-4096}" --gpu_mode="$1" ${CF_EXTRA---enable_sandbox=false} \
    >"$OUT/launch_cvd-$1.log" 2>&1
}
t0=$SECONDS
if ! launch "$GPU"; then
  grep -h -E "errors:|prerequisites|BOOT_FAILED" "$OUT/launch_cvd-$GPU.log" "$CF_HOME"/cuttlefish_runtime/launcher.log 2>/dev/null | tail -8
  cp "$CF_HOME"/cuttlefish_runtime/launcher.log "$OUT/launcher-$GPU.log" 2>/dev/null
  asme cvd reset -y >/dev/null 2>&1 || asme "$CF_HOME/bin/stop_cvd" >/dev/null 2>&1 || true
  [ "$GPU" = guest_swiftshader ] && exit 1
  log "gpu_mode=$GPU failed; falling back to guest_swiftshader (no render node in the guest)"
  GPU=guest_swiftshader; t0=$SECONDS
  launch "$GPU" || { tail -40 "$OUT/launch_cvd-$GPU.log"; exit 1; }
fi
echo "$GPU" > "$OUT/cf-gpu-mode.txt"
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
$ADB connect 0.0.0.0:6520 >/dev/null 2>&1 || true
timeout 600 $ADB -s 0.0.0.0:6520 wait-for-device
until [ "$($ADB -s 0.0.0.0:6520 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
  (( SECONDS - t0 > 900 )) && { log "boot timeout"; tail -60 "$CF_HOME"/cuttlefish_runtime/kernel.log; exit 1; }
  sleep 3
done
$ADB -s 0.0.0.0:6520 root >/dev/null 2>&1 || true; sleep 3; $ADB connect 0.0.0.0:6520 >/dev/null 2>&1 || true
log "booted in $((SECONDS - t0))s: $($ADB -s 0.0.0.0:6520 shell getprop ro.build.fingerprint | tr -d '\r')"
