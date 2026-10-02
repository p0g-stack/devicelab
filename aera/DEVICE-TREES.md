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
  Both nodes carry the generic `device` label. A build with an enforcing
  recovery domain loses the GPU plugin path. Fix direction: label the nodes
  (e.g. `gpu_device`) in the tree's file_contexts and allow `recovery` to
  open them; flutter-aera is deciding the fix. Cuttlefish never shows this
  (virtio-gpu, different nodes).
- **Audio:** `AERA audio: init service aera-oplus-charger did not start`,
  `stock AGM backend failed to start`; a plugin asking for `audio-output`
  would be silent here.

