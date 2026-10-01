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

Pin: AERA `android_manifest` 250b38e (`aera-16.0`, 2026-10-01) with every
AERA project pinned by commit in `build/pins.xml` (`bootable/recovery`
abf3316); Android projects stay on the manifest's `android-16.0.0_r1` tag.
`build/pin.sh` regenerates the pins. `build/patches/bootable/recovery/` holds
flutter-aera's Host API 3 series (`third_party/aera` there; `SOURCE` names
the commit). `build/device/` is the `aera_cf` device tree (x86_64, no
kernel; AERA's arm-only prebuilts dropped in `vendorsetup.sh`).

AERA publishes no images (no GitHub releases, no download page; checked
2026-10-01), and the build does not fit GitHub's free runners (2 cores,
7 GB RAM, 14 GB disk). Run it on any x86_64 Ubuntu 22.04/24.04 box with sudo,
~150 GB free and 32 GB RAM (+swap):

```sh
git clone https://github.com/p0g-stack/devicelab && cd devicelab
aera/build/build.sh ~/aera-src ~/aera-out      # unattended; rerunnable
```

It installs the apt packages and `repo`, syncs shallowly (406 projects),
applies the patches, builds `adbd recoveryimage` for `twrp_aera_cf-bp2a-eng`
and ends by printing `BUILD-INFO` (manifest, recovery commit, patch-set hash)
and `SHA256SUMS` for the files in `~/aera-out`. `SKIP_SYNC=1` reruns only the
patch + build steps (for a new patch series). Full log: `~/aera-out/build.log`.

Publish the result for the lab (needs `gh auth login` with push to
devicelab):

```sh
aera/build/publish.sh ~/aera-out
```

Checked here without a full build (2026-10-01): repo init at the pin and
manifest resolution (406 projects), sync of every GitHub-hosted project
(AERA, LineageOS, TeamWin), and the patch series applying in-tree. Not yet
run: the Android build itself, so expect a first round of x86_64 fixes in
`build/device/`.
