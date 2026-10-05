# managers/

Root managers on the Android 15 x86_64 AVD (GitHub Actions KVM runner,
`platforms/avd/up.sh`), each driven far enough to open a module's WebUI with
DevTools attached. Entry point: `.github/workflows/avd-ksu.yml` (matrix
`host: [kernelsu, webuix]`); every job publishes `$LAB_OUT` to the
`lab-results` branch. Rerun with a push touching these paths or
`workflow_dispatch` (inputs: `flavor`, `tag`, `api`, `modules`).

| Script | Does |
|---|---|
| `ksu.sh <kernelsu\|next> [tag]` | KernelSU release LKM + ksud + manager. `ksud late-load` (jailbreak mode: adb root loads the LKM, no boot patch) |
| `webuix.sh [tag]` | WebUI X Portable: install, root grant in KernelSU's App Profile, onboarding (picks KernelSU) |
| `install_modules.sh <zip>...` | `ksud module install`, then `ksud soft-reboot` so module stages run |
| `open_webui.sh <label> <pkg> <id> [name]` | Opens a module's WebUI: intent first, then the manager's own UI. Last line says which path worked |
| `back_to_app.sh` | Recents + tap, so the activity resumes rather than relaunches |
| `ui.py` | uiautomator helpers: tap by text (waits, dismisses ANR dialogs), switch, tapxy, type, scroll |

Checks that run in an opened page live in `checks/` (`webui_host.sh`,
`open_module.sh`, `flutter_webui.sh`, `app_plane.sh`).

## Host quirks this depends on

- KernelSU 3.3.0 on the 6.6 emulator kernel: plain `insmod` fails on ~30
  unexported SELinux symbols; `ksud late-load` (no path argument) works and
  the manager shows "Working [Jailbreak mode]" / LKM.
- KernelSU 3.3.0 starts its WebUI as `VIEW ksu://webui?id=<id>&token=<64 hex>`;
  `WebUIActivity` with only `-e id` closes itself after ~2 s. `open_webui.sh`
  falls back to Module tab, search, Open.
- KernelSU's Module and Superuser lists expose no uiautomator nodes until
  searched; the search box is driven by position (`ui.py tapxy 160 152`).
- First launch of the KernelSU manager shows a notification prompt over
  everything: `pm grant ... POST_NOTIFICATIONS` first.
- WebUI X Portable v438: `.ui.activity.webui.WebUIActivity -e id <id>` opens a
  module directly; DevTools is on without a setting. Its onboarding button
  ("Continue with KernelSU") has zero height on the AVD's 320x640 screen, so
  `webuix.sh` sets `wm size 320x900` for onboarding only.
- KernelSU 2+ mounts module `system/` only through a metamodule; `ksu.sh`
  installs the release's one if it ships one.
- After `ksud soft-reboot` system_server is slow for a while (ANR dialogs);
  `install_modules.sh` waits 25 s.

Results so far: `observations/avd-35-x86_64/managers-2026-10-01.md`.

## TODO

- WebUI X root grant: the Superuser-tab grant was flaky (search typing raced focus; 18:28 KernelSU run got none) and always drove KernelSU even in `flavor=next`. 2026-10-01 fix: tap the row directly, retry the search, use the flavor's manager. Unverified until Actions runs again.

- WebUI X after v438 (Play v608, master): the activity is `.ui.webui.WebUIActivity` and reads only `-e MODULE_ID <id>`;
  the old `.ui.activity.webui.WebUIActivity` stays in the manifest but its class is gone. `open_webui.sh` tries the new
  form first. Host `webuix608` in avd-ksu installs the supplied Play APK, sha256-checked against `webuix-apks.sha256`.
