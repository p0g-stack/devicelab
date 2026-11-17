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
20 GiB swap maximum, three build jobs), leaving
memory for the Actions listener. `AERA build resources` check output retains
minute-by-minute latest disk/RAM/cgroup evidence remotely even if a runner
disappears; the complete resource log is uploaded when the runner survives.
Earlier failures' annotations report lost runner communication, not a proven
OOM or disk failure. The prior successful image used a 76 GiB synced tree
and ended with only 3.6 GiB disk free; the rebased local sync also used 76 GiB.
The existing disk cleanup, swap and post-sync metadata removal are retained.
Soong's `ui/build/soong.go` clears the bootstrap process environment and passes
only its own invocation variables. A shell `GOMEMLIMIT` is therefore not a
limit on `soong_build`; reducing make jobs does not bound that single large
process either. The cgroup applies below both mechanisms. A compilation
sample showed `soong_build` at 7.8 GiB resident with 10.7 GiB build-cgroup swap,
while 5.6 GiB system memory and 33 GiB disk remained available; no cgroup
OOM or kill events had occurred.

### Host API 2 qualification (2026-11-17)

Recovery `d80a712b739a9e6cde0fe3ff7bd00e8e101625d9` contains upstream
`1cabc509`, the rebased non-protocol fixes, and both extension patches. The
local image build passed (76 GiB synced tree, 18 GiB metadata, 13 GiB build
output; 1,246 seconds sync and 499 seconds compilation). Its release is
[`aera-cf-x86_64-d80a712-a9691570617da5da`](https://github.com/p0g-stack/devicelab/releases/tag/aera-cf-x86_64-d80a712-a9691570617da5da).
The ramdisk SHA256 is
`a9691570617da5daac6ee5a8da7e5e8bbafebb1e6aa0345cef0de61eaad240ed`.

flutter-aera `upstream-host-api-2` was rebased onto main's Flutter 3.47.9
engine and deterministic packaging. Commit
`235f2d1abf071d21ad6bd995b69a1cffa0763024` passed
[Kit 44093060655](https://github.com/p0g-stack/flutter-aera/actions/runs/44093060655)
on both x64 and arm64 with `publish=false`. The x64 debug kit uses engine
`89c39edfdfae2949f6806e4a315c0c08522238b7`; archive SHA256
`796388780d92cbafaa025579ee93e48b45fb1999ed15a0760a4aaef37c09902f`.
The Kit failure before this run was stale API 3 tap coordinates outside the
API 2 desktop, not a render failure. Correct desktop taps retain the original
before/after inequality assertion and show the counter changing from 0 to 3.

The unchanged `ci/apps/api2_probe` passed `aera-api2-check.sh` on local
Cuttlefish build 16373615 (host package 1.57.0, KVM,
`gfxstream_guest_angle_host_swiftshader`, 720x1348 panel, software landscape):

- Two real Remote touch events produced count 1 then 2; 3,735 guest pixels
  differed between the captured counter frames.
- Bit 12 showed the real AERA keyboard. Touching its keys submitted
  `route42`; Flutter's measured inset changed 0 → 298 → 0.
- The native Files overlay returned `/data/media/0-api2-selected.txt`.
  `/data/media` was absent, so the check created this fixture directory on
  the emulator's ramdisk; this is not evidence of persistent Android storage.
- The desktop ESC toolbar returned the Details route to Flutter's probe.

Evidence is under
`/home/vivy/.cache/p0g-agents/AeraApi2Cuttlefish/local-cf/out/api2/`:
`03-counter-before.png`, `04-counter-after.png`, `05-keyboard.png`,
`07-submitted.png`, `08-picker.png`, `09-picked.png`, `11-returned.png`,
their upright annotated `-view.png` counterparts, and `probe-markers.log`.
The probe asserts actual Flutter log messages and captured pixels; it does
not synthesize picker replies, text submissions, or Back callbacks.

The same image and kit also passed the branch's hosted
[`aera-cf` run 44097599856](https://github.com/p0g-stack/devicelab/actions/runs/44097599856)
in 11m55s. Its `api2-cf-44097599856-1` Actions artifact contains screenshots,
probe markers, source/SDK/kit identity, and recovery logs. The run accepted
the successful Kit conclusion gate and verified the downloaded artifact
digest, kit file checksums, engine/SDK identity and candidate ramdisk hash.

Hosted screenshots and logs are retained in
[the Actions artifact](https://github.com/p0g-stack/devicelab/actions/runs/44097599856/artifacts/14336305326)
and [lab-results](https://github.com/p0g-stack/devicelab/tree/lab-results/runs/20261117T140621Z-aera-cf-recovery-44097599856/api2).
The counter pair is `03-counter-before.png` / `04-counter-after.png`;
the hosted run measured 3,735 changed guest pixels and the probe logged 1 then 2.
Use the `-view.png` copies for upright viewing; pixel assertions use raw captures,
not their annotated copies.

Reproduce the hosted check with the same independently identified inputs:

```sh
gh workflow run aera-cf.yml -R p0g-stack/devicelab \
  --ref aera-upstream-1cabc509-api2 -f api2_kit_run=44093060655 \
  -f aera_release=aera-cf-x86_64-d80a712-a9691570617da5da \
  -f aera_sha256=a9691570617da5daac6ee5a8da7e5e8bbafebb1e6aa0345cef0de61eaad240ed
```

This proves the Flutter bit-12 desktop path, not the separate bit-13 native
modal editor (which Flutter intentionally does not request). The integrated
recovery session negotiation test passed, but bit-13 UI behavior remains
unqualified. Also unqualified: Unicode/IME composition on recovery, picker
cancel/error/folder modes, real system Back, real-vsync timing, live resize
or rotation, multitouch, persistent Recents/data, shared clipboard, physical
GPU/panel behavior, and release/AOT. Multi-file and save remain explicitly
unsupported. No main branches or consumer pins changed; no physical device
was selected or written.


For a local build, use an x86_64 Ubuntu 22.04/24.04 box with sudo,
~150 GB free and 32 GB RAM (+swap). The hosted qualification uses the
resource-bounded workflow above; its image must not replace main's API 3
image or consumer pins implicitly:

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

The Android build and real Cuttlefish qualification have run successfully
for the explicit API 2 candidate recorded above. This supports a later
debug-only Host API 2 main-line migration with the two negotiated extensions;
it does not qualify unmodified upstream recovery or remove the listed limits.
