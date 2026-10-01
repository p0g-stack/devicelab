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

## D2. Recovery waits forever for a declared AIDL health service

```
servicemanager: Caller(pid=88,uid=0,sid=u:r:recovery:s0) Could not find android.hardware.health.IHealth/default in the VINTF manifest. No alternative instances declared in VINTF.
```
(once a second for the whole run; nothing draws, adb stays `offline`)

- Repro: run `runs/20261001T154019Z-aera-cf-recovery-36874193791`
  (image b540be3). devicelab had overlaid AERA onto Cuttlefish's stock
  ramdisk, which declares a health HAL whose Android 17 binary then exits 1
  next to AERA's Android 16 libraries (`init: Service 'vendor.health-cuttlefish' (pid 89) exited with status 1`).
- Cause (from the source, not yet confirmed on the device):
  `recovery_utils/battery_utils.cpp` `GetBatteryInfo()` calls
  `AServiceManager_waitForService()` with no timeout once
  `AServiceManager_isDeclared()` says yes, and the recovery (pid 88) keeps
  asking servicemanager for `IHealth/default` once a second, never reaching
  the HIDL fallback or "assuming defaults". With no UI up, adbd stays
  offline too. Which manifest declared it is still to be checked.
- Workaround: devicelab no longer carries stock /system or /vendor files
  into AERA's ramdisk (boot-aera.sh), so nothing declares the AIDL service.
- Upstream fix: use `AServiceManager_getService`/a bounded wait and fall
  through to HIDL and then defaults, so a broken health HAL costs a battery
  reading, not the whole recovery.
