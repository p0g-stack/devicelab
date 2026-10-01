# AERA deficiencies found on Cuttlefish

AERA-side problems hit while running AERA Recovery (built by `build/`, pin
in `build/pins.xml`, patches in `build/patches/`) on Cuttlefish x86_64. Each
has the exact log lines, how to reproduce it, the workaround used here and
what an upstream fix would be. flutter-aera's `docs/aera-deficiencies.md`
lists the plugin-host gaps; this list adds what the VM shows and says when
it confirms or contradicts an entry there.

Image: devicelab release `aera-cf-x86_64-ba4d988-06f0a135fd4de661`
(bootable/recovery ba4d988 = abf3316 + patches 0001-0010, built 2026-10-01).

## D1. Recovery binary cannot link: libincfs.so not packed

```
linker: CANNOT LINK EXECUTABLE "/system/bin/recovery": library "libincfs.so" not found: needed by /system/lib64/libandroidfw.so in namespace (default)
init: Service 'recovery' (pid 89) exited with status 1
```

- Repro: build without `TW_INCLUDE_CRYPTO_FBE` (devicelab's `aera_cf`), boot
  it; init restarts `recovery` every 5 s and the screen stays black.
  `adb shell 'stop recovery; /system/bin/recovery'` prints the line above.
  Run `runs/20261001T135111Z-aera-cf-recovery-36868223572` (`aera-diag.txt`).
- Cause: `prebuilt/Android.mk` adds `libincfs.so` to
  `RECOVERY_LIBRARY_SOURCE_FILES` only inside `ifeq ($(TW_INCLUDE_CRYPTO_FBE), true)`,
  but `libandroidfw.so`, which the recovery binary always links, needs it.
- Workaround: device tree adds `libincfs` (BoardConfig.mk, from devicelab
  6b0202e; needs a rebuild). Android 17's own copy does not stand in: it
  needs a newer libc++ (`cannot locate symbol "_ZNSt3__113__hash_memoryEPKvm"
  referenced by "/system/lib64/libincfs.so"`, run
  `runs/20261001T140843Z-aera-cf-recovery-36872033282`), so the image itself
  must carry it.
- Upstream fix: move `libincfs.so` out of the FBE block in
  `prebuilt/Android.mk` (or add it next to `libandroidfw`).

## D2. Battery status thread asks servicemanager every second (was: "waits forever")

```
servicemanager: Caller(pid=89,uid=0,sid=u:r:recovery:s0) Could not find android.hardware.health.IHealth/default in the VINTF manifest. No alternative instances declared in VINTF.
```
(637 times in 640 s of run `runs/20261001T160857Z-aera-cf-recovery-36886400049`,
each with eight lines of `NULL VINTF MANIFEST` around it)

- First read as a hang (run `runs/20261001T154019Z-aera-cf-recovery-36874193791`);
  it is not: the recovery keeps running. The hang-looking part was adb (D-cf1).
- Cause: twrp.cpp's status thread calls `GetBatteryInfo()` every second and
  each call looks the AIDL health HAL up again (`AServiceManager_isDeclared`),
  so a device without one floods the kernel log.
- Upstream fix: look the health HAL up once and cache the result (patch
  0012's bounded wait also helps a declared-but-dead HAL).

## D3. Nothing reaches the screen on a DRM driver without Qualcomm SDE

```
display mode: 720x1348 @ 60 Hz (720x1348)
setting DRM_FORMAT_XRGB8888 and GGL_PIXEL_FORMAT_BGRA_8888
Could not find obj_id = 32
Could not find obj_id = 39
Atomic Commit failed, rc = -22
Using drm graphics.
Atomic commit failed ret=-22
```
(`aera-recovery.log` in run `runs/20261001T171434Z-aera-cf-recovery-36894820751`; the last line 349 times, once per flip)

- AERA itself draws: its own capture (`/tmp/aeraui-capture`) shows the home
  screen and the counter (`aera-counter/01-home.png`, `03-app.png`), but the
  scanout never gets a frame, so the real screen stays black.
- Cause: minuitwrp's DRM backend assumes Qualcomm SDE. Without a connector
  `mode_properties` topology it still uses `DEFAULT_NUM_LMS` (2) layer
  mixers, and it takes the first two entries of `drmModeGetPlaneResources()`
  whatever their type or CRTC. virtio-gpu lists a primary and a cursor plane
  per CRTC (16 outputs on Cuttlefish), so half the screen goes to a cursor
  plane and every atomic commit is EINVAL. Any non-QCOM device has the same
  shape.
- Upstream fix (draft): without a topology, one layer mixer on the CRTC's own
  primary plane (by `possible_crtcs` and plane `type`); SDE devices unchanged.
  Patch 0013 (flutter-aera ab5de47).
- FIXED on image `aera-cf-x86_64-e54e216-4aabff1095d6546e` (run `runs/20261001T175801Z-aera-cf-recovery-36899838494`):
  `no SDE topology: 1 layer mixer, plane 32`, `Atomic Commit succeed`, zero
  `Atomic commit failed`; debugfs `dri/0/state` shows plane 32 on crtc-0
  holding a 720x1348 XR24 FB allocated by `recovery`.

## D4. logd aborts every few seconds: no task_profiles.json in the ramdisk

```
logd: libprocessgroup: Failed to read task profiles from /etc/task_profiles.json
logd: libprocessgroup: Failed to find SCHED_SP_BACKGROUND task profile
logd: failed to set background scheduling policy: No such file or directory
init: Service 'logd' (pid 856) received signal 6
```
(job log of run `runs/20261001T171434Z-aera-cf-recovery-36894820751`, Logs step; 59 aborts in `kernel.log`)

- Cause: `task_profiles.json` is a required module only under
  `TW_INCLUDE_CRYPTO`, and even then nothing copies it into the recovery
  root (the `cp` in `prebuilt/Android.mk` is commented out). The ramdisk has
  an empty `/system/etc/task_profiles/` directory instead.
- Effect: no logcat in recovery, init restarts logd forever.
- Upstream fix: require it on every build and copy it to
  `/system/etc/task_profiles.json`. Patch 0014 (flutter-aera ab5de47).
- FIXED on image e54e216 (run `runs/20261001T175801Z-aera-cf-recovery-36899838494`): `init.svc.logd=running`, logcat
  works in recovery.

## Lab gaps (devicelab, not AERA yet)

- Taps written to `/dev/input/event2` (Cuttlefish multitouch, 720x1348) do
  not reach the counter: three taps on its + leave 0 (`aera-counter/06-after.png`).
  getevent on the node shows the written events going out to readers
  (protocol B, BTN_TOUCH, ABS_X/Y), so AERA receives them and does not act
  on them. Next: AERA Remote's uinput touch (`op mirror`, header `x-aera-code`).
- `flutter_p0g run --aera`: the attach error was this workflow's
  `flutter create -q` (no such flag). With that fixed (a8b887d), the second
  `plugin open` (after `install --open` already opened the counter) printed
  nothing until the 300 s timeout; state capture added.

## D-cf1 (devicelab, not AERA). adbd stops at `sys.usb.config=none`

AERA (TWRP) sets `sys.usb.config` to `none` at start; init.rc stops adbd,
and devicelab's device tree sets `AERA_EXCLUDE_DEFAULT_USB_INIT`, so no USB
rc starts it again. Cuttlefish's adb is vsock-only, so adb stays `offline`.
Cuttlefish-only: real supported devices use a USB gadget and want this.
Handled by the fake `patches-cf/bootable/recovery/0001-FAKE-keep-adbd-running-on-Cuttlefish-*`
(init.rc: `on property:sys.usb.config=* && property:ro.hardware=cutf_cvm
start adbd`), carried from the next image build. Until an image carries it,
boot-aera.sh appends the same trigger to `init.recovery.cutf_cvm.rc`.
