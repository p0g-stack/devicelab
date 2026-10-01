# AERA on Cuttlefish

Device-like runs of flutter-aera without a phone. Owned by the AERA devicelab
thread; scripts here do not touch `managers/` or `probes/`.

## What runs where

| Piece | Substitute used | What it cannot show |
|---|---|---|
| Phone | Cuttlefish x86_64 (`aosp_cf_x86_64_only_phone-userdebug`, `aosp-android-latest-release`) under KVM on GitHub's `ubuntu-24.04` runner (2 vCPU, 7 GB) | arm64 code paths, Adreno/KGSL, real panel timing |
| AERA Recovery | Cuttlefish's stock AOSP recovery (same kernel, minui on virtio-gpu, root adb) until an AERA build for this target exists | AERA's own plugin host, LVGL UI, `/tmp/aera-p2-*` runtime handling |
| Host API 3 | flutter-aera's `aera-host-sim`, built static, run on the device | scanout and real touch: frames go to PNG, taps are scripted |
| flutter-aera kit | flutter-aera's own x64 kit and static `aera-host-sim-linux-x64` from release kit-3.47.5, downloaded fresh each run (`kit/build-x64.sh` is a local fallback) | Zink/Turnip, the arm64 kit binary itself |

No arm64 KVM: `ubuntu-24.04-arm` has no `/dev/kvm` (checked 2026-10-01), so
arm64 Cuttlefish would be TCG emulation.

## Scripts

- `cuttlefish/up.sh [branch/target] [build_id]`: install the host packages
  (cuttlefish-base 1.57.0 from Google's apt registry), `cvd fetch`, launch
  headless, wait for boot, adb root on `0.0.0.0:6520`.
- `cuttlefish/recovery.sh LABEL`: `adb reboot recovery`, record kernel, DRM
  and input nodes, mounts, processes, props and a frame.
- `cuttlefish/shot.sh FILE.png`: display 0 through `cvd display screenshot`.
- `cuttlefish/run-sim.sh LABEL PAYLOAD SIM [args]`: push a payload tree and
  the static simulator to `/tmp/aera-lab` in recovery, run it, pull frames.
- `kit/build-x64.sh OUT`: the x86_64 kit and static simulator from a pinned
  flutter-aera commit.
- `build/`: AERA's Android 16 tree at the pin (`build/pins.xml`: manifest
  250b38e, `bootable/recovery` abf3316) + `build/patches/<path>/*.patch`
  (flutter-aera's Host API 3 series under `bootable/recovery/`) + a
  Cuttlefish x86_64 device tree (`build/device`). Needs a big machine.

Workflow: `.github/workflows/aera-cf.yml` (push to `aera/**` or dispatch).
Results land on the `lab-results` branch under `runs/*-aera-cf-*`.

## Building AERA for Cuttlefish

AERA's manifest (`AERA-Recovery/android_manifest`, `aera-16.0`) is public
apart from a few LineageOS projects, and is a full Android 16 tree minus
`remove-minimal.xml`. Building `recoveryimage` needs roughly 100 GB of disk
and 32 GB of RAM; the free runner has 14 GB free disk and 7 GB RAM. AERA's
vendor prebuilts (busybox, bash, ...) exist only for arm/arm64. AERA
publishes no images (no GitHub releases, no download page; checked
2026-10-01), so the image has to come from this build.
