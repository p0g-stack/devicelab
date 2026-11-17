# Pins

Pins: what this repo holds fixed, where, and who moves it. Values read from the repo at the commit that added this file; the bump order across repos is https://github.com/p0g-stack/.github/blob/main/docs/flutter-bump.md.

| What | Where | Current | Bumped by |
| --- | --- | --- | --- |
| AERA carried patches | p0g-stack branches pinned in `aera/build/pins.xml`: `android_bootable_recovery` `rebase-1cabc509`, `android_external_lvgl` `rebase-626794146` | recovery `1bd318e1` on upstream `1cabc509`, lvgl `7840a34a` on upstream `626794146` | devicelab, push to the branch and move the pin |
| AERA manifest | `aera/build/build.sh` `MANIFEST_REV` | `aabd43b` | devicelab, with `pin.sh` |
| AERA project heads | `aera/build/pins.xml` (from `aera/build/pin.sh`) | taken 2026-11-17 from aera-16.0, including `libsmb2`, `libssh2`, `aera_qrtr`, `aera_rmtfs`, `aera_tqftpserv` | devicelab |
| AOSP base | `pins.xml` comment: manifest's tag | android-16.0.0_r1 | follows MANIFEST_REV |
| flutter-aera for the x64 kit build | `aera/kit/build-x64.sh` `FA_REV` | `67e6c29edd0c3c6728b30900b82b2cc6629dfbff`, recovery series tested by [aera-cf 37582507317](https://github.com/p0g-stack/devicelab/actions/runs/37582507317) | devicelab after qualification; later source syncs do not imply image qualification |
| AERA kit + sim in the CF lab | `.github/workflows/aera-cf.yml`, matching flutter_p0g's `artifact_pins.dart` | Flutter 3.47.5 x64 asset `610973281`, SHA256 `89502b18226472ee3d981eda915f1afee9b5643af67c8da9a1beeb8338ad52aa`; sim asset `610973279`, SHA256 `e5ac7c08304ba5f7a74c3d88059ded26d59ad38f1a82d785cea9eeebf1283cda` | devicelab, from downloaded bytes; never sibling-checksum authority |
| AERA image under test | `aera-cf.yml` input `aera_release` + required candidate `aera_sha256` | default `aera-cf-x86_64-84736fe-c07ed742cefdb67c`, image SHA256 `339127018320454ceaefa63e6c1c2b7b2a2f67880ef0fd5d2a9d82761df8d105`, Cuttlefish build `16373615` | lab run dispatcher; successful [run 37582507317](https://github.com/p0g-stack/devicelab/actions/runs/37582507317) |
| Managers (KernelSU, WebUI X, …) | `managers/*.sh` `TAG` arg | latest release when not given | per run |
| WebUI X Play build (host `webuix608`) | `managers/webuix-apks.sha256`; APK on lab-inputs `managers/` | v608 `ae88a8ca…afb2` (Play, 2026-10-03) | devicelab, from an APK Yuv supplies |
| Flutter in the CF lab | `aera-cf.yml` `flutter-version` | 3.47.5 | devicelab |
