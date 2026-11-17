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
| `webuix.sh` | WebUI X v660 official: verify committed SHA256, install, root grant in KernelSU's App Profile, onboarding (picks KernelSU) |
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
- WebUI X v660 uses `.ui.webui.activity.NewProcessWebUIActivity` with
  `MODULE_ID`, matching its launcher shortcuts. Its default in-app launch
  mode is a navigation-stack screen; the lab explicitly exercises the
  separate-process activity. Onboarding selects KernelSU and Continue.
- KernelSU 2+ mounts module `system/` only through a metamodule; `ksu.sh`
  installs the release's one if it ships one.
- After `ksud soft-reboot` system_server is slow for a while (ANR dialogs);
  `install_modules.sh` waits 25 s.

Results so far: `observations/avd-35-x86_64/managers-2026-10-01.md`.

## Current qualification inputs

- KernelSU v3.3.1 manager, x86_64 ksud and Android 15/6.6 LKM are pinned in
  `kernelsu.sha256`. Other KernelSU tags require an explicit pin update.
- WebUI X v660 official is pinned in `webuix-apks.sha256` and downloaded
  from its GitHub release. The v438 Portable and v608 Play legs are retired.
- KernelSU plus webui-termux-api remains the non-WebUI-X path. `hold_tag`
  runs its socket-hold check on the KernelSU leg only.
