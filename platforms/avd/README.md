# avd

`up.sh [api] [tag] [abi]` boots a headless emulator and leaves adb as uid 0.
Runs where `/dev/kvm` exists: GitHub's ubuntu runners (see the workflows),
not agent cloud sessions. Default: API 35 google_apis x86_64, kernel
6.6.50-android15 (KMI android15-6.6), SELinux enforcing.

Cannot show: arm64 CPU behaviour (x86 runners can't emulate arm64 Android;
`probes/dart_bionic/run_arm64_qemu.sh` covers arm64 bionic userland only),
vendor kernels, real GPU.
