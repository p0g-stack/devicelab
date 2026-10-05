# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is /mnt/project-files/proposals/flutter-bump-checklist.md (project files).

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| flutter-aera AERA patch series | copied into `aera/build/patches/` (+ `patches-cf/`), source commit in `.../bootable/recovery/SOURCE` and `.../external/lvgl/SOURCE`; `aera/build/sync-patches.sh` | flutter-aera `33d7515` | devicelab, sync then delete stale files |
| AERA manifest | `aera/build/build.sh` `MANIFEST_REV` | `250b38e` | devicelab, with `pin.sh` |
| AERA project heads | `aera/build/pins.xml` (from `aera/build/pin.sh`) | taken 2026-10-01 from aera-16.0 | devicelab |
| AOSP base | `pins.xml` comment: manifest's tag | android-16.0.0_r1 | follows MANIFEST_REV |
| flutter-aera for the x64 kit build | `aera/kit/build-x64.sh` `FA_REV` | `c9414a5` (stale against flutter-aera HEAD) | devicelab |
| AERA kit + sim in the CF lab | `.github/workflows/aera-cf.yml` | release kit-3.47.5, **latest upload every run**, sha256 from the release itself | follows flutter-aera |
| AERA image under test | `aera-cf.yml` input `aera_release` | default `latest`; gate image aera-cf-x86_64-90aeba8-242db857a00545f4 | lab run dispatcher |
| Managers (KernelSU, WebUI X, …) | `managers/*.sh` `TAG` arg | latest release when not given | per run |
| WebUI X Play build (host `webuix608`) | `managers/webuix-apks.sha256`; APK on lab-inputs `managers/` | v608 `ae88a8ca…afb2` (Play, 2026-10-03) | devicelab, from an APK Yuv supplies |
| Flutter in the CF lab | `aera-cf.yml` `flutter-version` | 3.47.5 | devicelab |
