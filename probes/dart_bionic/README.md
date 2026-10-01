# dart_bionic

Can a Dart program run as root on Android, outside any app, the way a
module's root process would? `bin/probe.dart` prints one JSON object
(uid, SELinux context, process spawn, isolates, DNS, loopback WebSocket,
path and abstract AF_UNIX sockets); the scripts start it each way a module
could ship it.

| Script | Where | Routes tried |
|---|---|---|
| `run_avd.sh` | booted AVD with adb root (`platforms/avd/up.sh`) | Linux exe as is / via glibc loader / patched interpreter; Termux SDK compiling on device, output run from `/data/adb` with Termux removed; Termux runtime + Linux snapshot; glibc loader + Linux `dartaotruntime` + `.aot` |
| `run_arm64_qemu.sh` | GitHub runner, sudo | same routes against the arm64 AVD image's bionic in a qemu-user chroot |
| `kit_snapshot.sh` | anywhere | builds an Android `.aot` with a flutter_p0g dart-android kit |

Workflow: `.github/workflows/avd-probe.yml`. Results: `lab-results` branch,
summarised in `observations/*/dart-bionic-*.json`.

## Results, 2026-10-01

Android 15 AVD x86_64 (AE3A.240806.043, kernel 6.6.50-android15, SELinux
enforcing, `u:r:su:s0`), Dart 3.13.5:

| Route | Result |
|---|---|
| glibc loader + Linux `dartaotruntime` + `.aot` | works; remote DNS fails (no resolv.conf); ~0.35 s start; 5.7 MB runtime + 3.3 MB glibc |
| `dart compile exe` output via loader or patchelf | fails: prints VM usage (snapshot is found via /proc/self/exe) |
| Termux runtime + Linux snapshot | fails: snapshot feature string says `linux`, VM is `android` |
| Termux SDK `dart compile exe` on device, run with Termux removed | works incl. DNS, needs only libc/libdl/libm/liblog; set `TMPDIR` (default is Termux's prefix); output is not +x |

arm64 (qemu-user chroot of the API 35 arm64 image): glibc loader route and
Termux-built exe both start, spawn processes and pass socket checks. The
chroot has no property service (`Platform.operatingSystemVersion` throws)
and no netd or /etc, so DNS results there say nothing about devices.
