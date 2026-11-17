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

GPU (`aera-gpu.yml`, 2026-10-01): the default is
`--gpu_mode=gfxstream_guest_angle_host_swiftshader`. The guest gets
`/dev/dri/renderD128` with 3D on (`+virgl +context_init +resource_blob`)
but only gfxstream capsets: 3 (gfxstream Vulkan) and 9 (composer); plain
`gfxstream` adds 8 (gfxstream GLES). No virgl capset, so a guest renders
through Mesa's gfxstream Vulkan driver, not virgl. `host_lavapipe` and plain
`gfxstream` boot too. `drm_virgl` crashes crosvm (core dump right after
launch) on the GPU-less runner even with host EGL/GLES installed.

No arm64 KVM: `ubuntu-24.04-arm` has no `/dev/kvm` (checked 2026-10-01), so
arm64 Cuttlefish would be TCG emulation.

## Scripts

- `cuttlefish/up.sh [branch/target] [build_id]`: install the host packages
  (cuttlefish-base 1.57.0 from Google's apt registry), `cvd fetch`, launch
  headless, wait for boot, adb root on `0.0.0.0:6520`.
- `cuttlefish/recovery.sh LABEL`: `adb reboot recovery`, record kernel, DRM
  and input nodes, mounts, processes, props and a frame.
- `cuttlefish/boot-aera.sh ramdisk-recovery.img`: swap AERA's ramdisk into
  the RECOVERY fragment of Cuttlefish's `vendor_boot` (keeping its kernel,
  vendor ramdisk and `init.recovery.cutf_cvm.rc`), relaunch, boot Android.
  The workflow then runs `recovery.sh aera-recovery`. It takes the newest
  `aera-cf-x86_64-*` devicelab release (input `aera_release`).
- `tools/aerap.py`: unpack/pack/retarget `.aerap` with AERA's exact stream
  layout.
- `cuttlefish/shot.sh FILE.png`: display 0 through `cvd display screenshot`.
- `cuttlefish/run-sim.sh LABEL PAYLOAD SIM [args]`: push a payload tree and
  the static simulator to `/tmp/aera-lab` in recovery, run it, pull frames.
- `kit/build-x64.sh OUT`: the x86_64 kit and static simulator from a pinned
  flutter-aera commit.
- `build/`: AERA's Android 16 tree at the pin (`build/pins.xml`: manifest
  aabd43b, `bootable/recovery` and `external/lvgl` on the p0g-stack rebase
  branches) + `build/patches/<path>/*.patch` (device and `system/core`
  patches only; the recovery series is in the branch) + a
  Cuttlefish x86_64 device tree (`build/device`). Needs a big machine.

Workflow: `.github/workflows/aera-cf.yml` (push to `aera/**` or dispatch).
Results land on the `lab-results` branch under `runs/*-aera-cf-*`.

## Building AERA for Cuttlefish

Pin: AERA `android_manifest` aabd43b (`aera-16.0`, 2026-11-15) with every
AERA project pinned by commit in `build/pins.xml`; Android projects stay on
the manifest's `android-16.0.0_r1` tag. `build/pin.sh` regenerates the pins
except `bootable/recovery` and `external/lvgl`, which are pinned to p0g-stack
branches that inherit AERA upstream `1cabc509` and `626794146` and carry the
rebased non-protocol patches (the pins' comment names them). `build/device/`
is the `aera_cf` device tree (x86_64, no kernel; AERA's arm-only prebuilts
dropped in `vendorsetup.sh`).

This qualification branch adds the two negotiated Host API 2 extension patches
to `rebase-1cabc509-api2` (desktop integration bit 12 and native editor bit 13).
It does not change the main-line image or consumer pins. Dispatch `aera-cf`
on this branch with the image's independently recorded SHA256 and a successful
`upstream-host-api-2` Kit run; do not run the old API 3 checks against it.

Hosted builds run inside a memory cgroup (10 GiB high, 12 GiB maximum,
20 GiB swap maximum, three build jobs, 8 GiB Go heap soft limit), leaving
memory for the Actions listener. `AERA build resources` check output retains
minute-by-minute latest disk/RAM/cgroup evidence remotely even if a runner
disappears; the complete resource log is uploaded when the runner survives.
Earlier failures' annotations report lost runner communication, not a proven
OOM or disk failure. The prior successful image used a 76 GiB synced tree
and ended with only 3.6 GiB disk free; the rebased local sync also used 76 GiB.
The existing disk cleanup, swap and post-sync metadata removal are retained.

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
