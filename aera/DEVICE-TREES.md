# AERA device trees

Notes on real-device trees we build AERA (with our patch series) against, and
what they mean for patches written against Cuttlefish. Read from the tree's
own files on GitHub; nothing here has been flashed by us unless it says so.

## infiniti (OnePlus 15, SM8850 "canoe")

Tree: [AERA-Recovery/android_device_oneplus_infiniti-AERA](https://github.com/AERA-Recovery/android_device_oneplus_infiniti-AERA),
branch `aera-16.0`, head `0d5f0b6` (2026-09-25, "fix adaptive UI scaling
flag"). It is AERA's own tree, migrated from the OrangeFox one; maintained
actively (eight commits 2026-09-13 to 09-25). Our AERA pin `abf3316` is from
2026-09-30, so the tree is current against it.

| | |
|---|---|
| Build | `lunch twrp_infiniti-bp2a-eng`, `mka adbd recoveryimage`; output `out/target/product/infiniti/` |
| Recovery limit | 100 MiB |
| Kernel | `TARGET_PREBUILT_KERNEL := kernel/prebuilts/6.6/arm64/kernel-6.6` (AOSP GKI 6.6, in the synced tree), but `BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true`, so the image is ramdisk-only and boots the device's own kernel |
| Vendor modules | `AERA_LOAD_VENDOR_MODULES` loads touch (Synaptics, FocalTech, Goodix, Ilitek, Novatek), audio (q6, wcd93xx, lpass, wsa88xx, TFA98xx), charger, NFC and `msm_kgsl.ko` |
| Blobs | about 88 MB across 439 files, extracted from the matching OnePlus 15 stock OTA: Adreno 840 EGL/GLES and `libllvm-qgl`, `msm_kgsl.ko` built for this kernel ABI, gen80200 GPU firmware, AGM/PAL audio, Wi-Fi board files. Not reusable on other platforms |
| Rendering | **Hardware (Adreno 840 GLES)**. `TARGET_BOARD_PLATFORM_GPU := qcom-adreno840`, `ro.hardware.egl=adreno`, ships `aera-gpu-probe`; AERA's `core/gpu_renderer.cpp` resolves EGL at runtime and keeps the software renderer as fallback |
| UI | `AERA_UI_ADAPTIVE_RESOLUTION := true`, `TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888` |
| Also | FBE, A/B, KeyMint, Wi-Fi, haptics, flashlight, KernelSU/Next/SukiSU support |

What this means for our Cuttlefish-motivated patches:

- **0026 (landscape on the software renderer):** only reached on infiniti if
  the GPU path fails to start and AERA falls back. Harmless otherwise.
- **LVGL L0003 (layer larger than the budget):** probably still relevant.
  The GPU renderer uploads a display texture, but LVGL still draws layers in
  software into it, and the tree runs the same adaptive canvas that hit D13.
- **0010 (libincfs), 0011 (x86 libwebp), 0012 (health HAL lookup), 0013 (no
  SDE), 0014 (task_profiles):** expected harmless here (FBE, arm64, a health
  HAL and Qualcomm SDE are all present); 0010 and 0014 just pack a file the
  build may already carry. Not yet confirmed by an infiniti build.

Yuv's note (2026-10-02): typical device trees can be late to add hardware
rendering, so the software-renderer fixes stay worth keeping for trees that
have not got there yet. infiniti already has it.

### First run on hardware (2026-10-02)

Image `aera-infiniti-arm64-040070f-b413b91c42e5fd41`, `Flutter-Demo-0.1.42.aerap`
ran on the Adreno GPU (shader cache filled, `Atomic Commit succeed. Using
drm graphics.`). Findings file: project files `real-device-infiniti-2026-10-02.md`.

- **SELinux: the GPU works only because the `recovery` domain is
  permissive.** `getenforce` says Enforcing, but the plugin's opens of the GPU
  nodes are logged with `permissive=1`:
  ```
  avc: denied { open } for comm="aera-plugin" path="/dev/dri/renderD128"
    scontext=u:r:recovery:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
  avc: denied { getattr } for comm="aera-plugin" path="/dev/kgsl-3d0"
    scontext=u:r:recovery:s0 tcontext=u:object_r:device:s0 tclass=chr_file permissive=1
  ```
  Both nodes carry the generic `device` label. This is the same on every
  AERA build, Cuttlefish included, because the permissive `recovery` domain
  comes from AERA's shared sepolicy; see "SELinux across trees" below. It is
  a note, not an infiniti bug.
- **Audio: dead because the tree pins the charger HAL's version, not
  because of the audio bridge.** The tree's `init.recovery.qcom.rc` starts
  `aera-oplus-charger` from
  `/mnt/aera-stock/odm/bin/hw/vendor.oplus.hardware.charger-V10-service`, but
  Yuv's firmware ships `...charger-V11-service`. init logs
  `Could not ctl.start for 'aera-oplus-charger' ... No such file or directory`,
  `aera-audio-bootstrap` stops at that required service (`AERA audio: init
  service aera-oplus-charger did not start`), the AGM backend never starts
  and `init.svc.aera-audio-bootstrap` is stopped. The bridge theory is ruled
  out: the bridge never got as far as running. Draft fix
  `aera/build/patches/device/oneplus/infiniti/0001-*.patch`: the bootstrap
  links the highest `vendor.oplus.hardware.charger-V*-service` the stock ODM
  ships to `/vendor/bin/aera-oplus-charger`, which the init service now
  starts, so V10 devices keep working. Resolver checked in a sandbox (V9+V10+V11
  picks V11, V10 alone picks V10). Left as is: the recovery VINTF fragment
  still declares charger version 10; servicemanager matches AIDL services by
  name and instance, so a V11 service should register, but a hardware run
  settles it. Upstream candidate for the AERA-Recovery tree.


## SELinux across trees (2026-10-02)

Question: is the permissive `recovery` domain an infiniti choice or an AERA
convention, and are the GPU nodes labelled anywhere?

| Tree | `recovery` domain permissive? | GPU node labels | Where set |
|---|---|---|---|
| AERA `system/sepolicy` ([AERA-Recovery/android_system_sepolicy](https://github.com/AERA-Recovery/android_system_sepolicy) `aera-16.0`, pinned `9641d92`) | **Yes, on every AERA recovery build** | No `/dev/dri/*` or `/dev/kgsl*` entry (only `/dev/pvrsrvkm` is `gpu_device`) | `private/twrp.te`: `recovery_only()` block with `permissive recovery;` (also `init`, `ueventd`, `adbd`, `logd`, `fastbootd`, `postinstall`) |
| AERA `bootable/recovery` at `abf3316` | No policy of its own | none | (no `sepolicy/` dir, no `.te` files) |
| infiniti `0d5f0b6` | Inherits yes | `device` (confirmed on hardware for `renderD128`, `kgsl-3d0`) | Tree ships no sepolicy, no `BOARD_*SEPOLICY*`; ueventd sets only mode/owner (`/dev/dri/* 0666 root graphics`, `/dev/kgsl-3d0 0666 system system`) |
| dodge (OnePlus 13) `e27e8db` | Inherits yes | `device` (inferred: same tree shape) | Same as infiniti: no sepolicy; ueventd `/dev/dri/*`, `/dev/kgsl` modes only |
| Our Cuttlefish `aera/build/device` | Inherits yes | `device`, confirmed: AERA's own `recovery` binary gets `ioctl`/`map` on `/dev/dri/card0` and the plugin `open`/`map` on `/dev/dri/renderD128`, all `tcontext=u:object_r:device:s0 ... permissive=1` (lab run 36929322912 `kernel.log`) | No sepolicy in our tree |
| TWRP upstream ([TeamWin/android_system_sepolicy](https://github.com/TeamWin/android_system_sepolicy) `android-14.1`, `0a6792e`) | Yes | none | Same `private/twrp.te` `recovery_only(permissive recovery ...)`; AERA's file is TWRP's (commit by bigbiff) |
| Stock AOSP `system/sepolicy` | No | n/a | `recovery.te` declares no permissive |

How it is gated: `recovery_only()` expands when the policy is built with
`target_recovery=true` (the `recovery_sepolicy.conf` module), whatever the
build variant. A `user` lunch would not produce an enforcing recovery
either: soong's `sepolicy-analyze permissive` check fails the build with
"permissive domains not allowed in user builds" (`build/soong/policy.go`),
so every AERA recovery that builds is permissive. infiniti and our
Cuttlefish build `-eng`; on infiniti the kernel cmdline has no
`androidboot.selinux=permissive` (PC worker), so `getenforce` says Enforcing
while the `recovery`, `init`, `ueventd`, `adbd` domains stay permissive.

The manifest lists only two AERA-Recovery device trees (infiniti, dodge); the
org listing is not reachable from the lab, so any other tree is unchecked.
Neither checked tree runs recovery enforcing, and none could without
changing the shared sepolicy.

**Conclusion: permissive by design, AERA-wide (TWRP heritage). The GPU
finding is a note, not a bug.** The pixel plugin depends on the permissive
domain exactly as much as AERA's own UI does (its DRM ioctls on
`/dev/dri/card0` and the GPU renderer's opens are denied the same way), and
the RPC FIFOs, netlink and VM-service file are denied too. Making the plugin
path survive an enforcing recovery would mean, in AERA's sepolicy fork (not
the device trees, not `bootable/recovery`): `/dev/dri/*` and
`/dev/kgsl-3d0` labelled `gpu_device` in `file_contexts`, an
`allow recovery gpu_device:chr_file rw_file_perms` in `twrp.te`, and the
other denials above; only worth doing if AERA ever drops the permissive line.
