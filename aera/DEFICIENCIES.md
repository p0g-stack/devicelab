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

## D5. The Back-gesture edge swallows taps on a Host API 3 plugin's edge controls

`PixelPluginHandlePointer` (patch 0006, `aeraui/scenes/pixel_plugin_scene.cpp`)
ignores every touch that STARTS within `max(72, width / 20)` px of a side
edge, so it can serve as AERA's Back swipe. On a 720 px screen that is
x < 72 or x >= 648. A stock Flutter FloatingActionButton (56 dp, 16 dp
margin, 1.75 px/dp) spans x 594-692, so taps on its right half never reach
the app; any edge-aligned control (icon buttons in an AppBar, sliders,
drawers' edge swipe) loses its outer part too.

- Repro: counter .aerap open in AERA, tap at 650,1278 (inside the +): the
  count stays 0 (run `runs/20261001T171434Z-aera-cf-recovery-36894820751`,
  `aera-counter/06-after.png`).
- Suggested upstream fix: decide on movement, not on the down point. Send
  TOUCH_DOWN at once; only if the contact then moves inward past a slop
  (e.g. 16 dp) mostly horizontally, cancel it in the plugin (TOUCH_UP or a
  cancel kind) and treat it as Back. Or narrow the zone to a few dp as
  Android's gesture nav does, with the plugin able to opt out (Android's
  systemGestureExclusionRects).

## D6. An RPC request can wait until the next client writes (POLLHUP not handled)

```
rpc.txt of `op mirror` (sent after `plugin open` got no answer in 60 s):
{"event":"log","id":"lab","text":"Opening counter\n"}
{"code":0,"event":"result","id":"lab"}
logcat: 22:28:36 recovery(94) opens /system/bin/aerain; next open of the
plugin and of aerain only at 22:30:38, when the mirror request arrived.
```
(runs `runs/20261001T205150Z-aera-cf-recovery-36920805677` and
`runs/20261001T181707Z-aera-cf-recovery-36903585783`; earlier the
`flutter_p0g run --aera` open that printed nothing for 300 s)

- Cause: `RunFrame` (aeraui/core/engine.cpp) polls the input FIFO for
  POLLIN only. If a frame reads the request after the writer wrote but
  before it closed, `HandleInput` buffers it and waits for EOF; after the
  close the empty FIFO reports only POLLHUP, so nothing reads the EOF until
  another client writes. That client's bytes are appended, the first
  request runs, the second is lost and its client gets the first answer.
- Effect: plugin opens and other RPC ops randomly stall for minutes; it
  also broke the lab's AERA Remote start and taps landing on AERA's menu.
- Upstream fix (draft): treat POLLHUP like POLLIN.
  `/mnt/project-files/devicelab-aera/patches-draft/0016-*`, applies after
  0015; not yet built.
- FIXED by 0016 on image 29c34fe (run `runs/20261001T212049Z-aera-cf-recovery-36926456381`): the open answered at once,
  the following `op mirror` got its own answer, and the counter was up
  before the taps.

## D7. AERA Remote loses the first touch after it starts

```
getevent -lt during the first POST /api/input/touch down+up:
add device 7: /dev/input/event6  name: "AERA Remote Input"
/dev/input/event6: EV_ABS ABS_MT_TRACKING_ID ffffffff
/dev/input/event6: EV_KEY BTN_TOUCH UP
/dev/input/event6: EV_SYN SYN_REPORT 00000000
```
(run `runs/20261001T212049Z-aera-cf-recovery-36926456381`, `aera-counter/getevent-remote.txt`; the down never shows)

- Cause: `aera_remote/input.cpp` creates its uinput device lazily on the
  first `Touch()`/`Key()` and writes the DOWN right after `UI_DEV_CREATE`,
  before any reader (minuitwrp, getevent) has opened the new node; only
  the UP arrives. The remote viewer's first tap does nothing, and a lost
  DOWN with later moves can be read as a swipe (earlier run: two remote
  taps opened the Quick Settings shade).
- Suggested upstream fix: create the device when AERA Remote starts (and
  destroy it on stop), or wait for the node to appear and settle (~100 ms)
  after `UI_DEV_CREATE` before the first event.
- FIXED by 0017 on image e986e97 (run `runs/20261001T214146Z-aera-cf-recovery-36928925615`): getevent shows the remote
  tap's DOWN with its position, and the tap counts (`aera-counter/07-remote.png`).
- Same run, D5 confirmed: both edge-zone taps (680,1278 and 674,1286) counted;
  the counter reached 4 from 4 raw + 1 remote taps. The miss was again the
  second raw tap (610,1286), not an exact repeat this time: every raw tap is
  now recorded with getevent to see why.

## D8. AERA Remote's Home and Menu buttons do nothing

Found in the source, not yet on screen: `aera_remote/client/index.html`
offers Home (`key('home')`), and `aera_remote/input.cpp` emits
`KEY_HOMEPAGE` / `KEY_MENU` for `home` / `menu`, but nothing in aeraui
handles either code (`core/runner.cpp` acts on POWER, VOLUMEUP/DOWN and
BACK only; no other `KEY_HOMEPAGE`/`KEY_MENU` in the tree at abf3316 +
0001-0022). A remote viewer can only reach Home or Recents with the
bottom-edge swipe.

- Suggested upstream fix: in `HandleKey`, `KEY_HOMEPAGE` release -> the
  same path as an accepted bottom-edge swipe (`ShowHome()`), and
  `KEY_MENU` (or `KEY_APPSELECT`, which Remote could send) -> `ShowRecents()`.
- The lab's lifecycle check (`aera-lifecycle-check.sh`) uses the swipe
  for that reason.

## Lab gaps (devicelab, not AERA yet)

- Taps written to `/dev/input/event2` (Cuttlefish multitouch, 720x1348) do
  not reach the counter: three taps on its + leave 0 (`aera-counter/06-after.png`).
  getevent on the node shows the written events going out to readers
  (protocol B, BTN_TOUCH, ABS_X/Y). AERA's own UI does act on them: in run
  `runs/20261001T181707Z-aera-cf-recovery-36903585783` the open answered
  late, the counter was not up yet, and the same tap at 650,1278 selected
  the Wipe tab (`aera-counter/03-raw.png`). The counter missed them
  because of D5 (the lab tapped at x=650); taps now go to x=W-100.
- D5 retest on image 29c34fe (0015): 4 raw taps gave 2 counts. The counting
  ones were the first inside tap (620) and the first edge-zone tap (680), so
  0015 works; the misses were exact repeats of the previous tap's pixel, whose
  ABS values the kernel drops as duplicates, so the contact had no position.
  Taps now vary by a few px. (A real panel always jitters; minuitwrp could
  still keep the slot's last position for a contact without one.)
- Raw taps work: on image 722b33f (run `runs/20261001T201700Z-aera-cf-recovery-36918690305`) one raw tap at 620,1278 took
  the count to 1 (`aera-counter/03-raw.png`).
- AERA Remote's touch API (`op mirror`, POST /api/input/touch through its
  uinput device) did not: a tap on the + changed nothing and two taps at
  680,1278 opened AERA's Quick Settings shade instead (`05-app.png`,
  `07-after.png`). Its POSTs return an empty body. Possible AERA deficiency
  (D6 candidate); next run records getevent on all devices for one remote tap.
- Hot reload shows on screen: title `Reloaded on AERA` after `r`
  (`flutter_p0g-reloaded.png`, `Reloaded 1 of 754 libraries in 620ms`).
- `flutter_p0g run --aera`: the attach error was this workflow's
  `flutter create -q` (no such flag). With that fixed (a8b887d), the second
  `plugin open` once printed nothing until the 300 s timeout; on the next
  run (36903585783) attach and hot reload worked: `Reloaded 1 of 754
  libraries in 700ms`. A `plugin open` result can take over 10 s.

## D-cf1 (devicelab, not AERA). adbd stops at `sys.usb.config=none`

AERA (TWRP) sets `sys.usb.config` to `none` at start; init.rc stops adbd,
and devicelab's device tree sets `AERA_EXCLUDE_DEFAULT_USB_INIT`, so no USB
rc starts it again. Cuttlefish's adb is vsock-only, so adb stays `offline`.
Cuttlefish-only: real supported devices use a USB gadget and want this.
Handled by the fake `patches-cf/bootable/recovery/0001-FAKE-keep-adbd-running-on-Cuttlefish-*`
(init.rc: `on property:sys.usb.config=* && property:ro.hardware=cutf_cvm
start adbd`), carried from the next image build. Until an image carries it,
boot-aera.sh appends the same trigger to `init.recovery.cutf_cvm.rc`.
