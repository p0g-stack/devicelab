# devicelab

Recreates the platforms the embedders run on, as close to the real thing as
this machine allows, and drives them so an agent can watch what a host
actually does. Bring-up and behaviour discovery only. It ships nothing and no
repo's CI depends on it.

Named after Flutter's `dev/devicelab`, which runs tasks against real devices.

## Scope

In: provisioning scripts per platform, a driver an agent can call (install,
launch, tap, read the WebView over DevTools, capture logs and frames), and the
observations it records: which bridge methods exist, what they return, what
blocks, timings, with the host build named.

Out: tests that gate a PR (those are unit tests in each embedder, against
fakes built from what this lab observed), app code, grading.

## Platforms

| Target | How it is recreated | Notes |
|---|---|---|
| KernelSU, KSU Next, SukiSU, APatch | Cuttlefish or AVD on a GKI kernel with the manager's LKM/patch | Kernel-level root needs a kernel it can patch; container Android can't host these. CBM already qualified on Cuttlefish Android 17 + KSU Next 3.3.0 |
| WebUI X (MMRL, Portable) | Same images, WebUI X installed | Portable v438 is the known-broken `spawn` case |
| KsuWebUIStandalone | Same images | |
| Android container (Waydroid, redroid, Anbox) | Container on the host kernel | Fast, for app-side and WebView behaviour only; no KSU |
| Plain browser | Headless Chromium, plus Android System WebView builds | The degraded web floor |
| AERA Recovery | flutter-aera's host simulator; real device over adb when attached | GPU paths only on device |

## Driving

- adb + uiautomator for the manager UI.
- The module's WebView over Chrome DevTools (`webview_devtools_remote`), with
  the manager's WebView debugging switch on.
- Every observation is a file: platform, host build, method, input, output,
  timing, date. Embedders turn them into fakes.

## Proposed nest

```
platforms/
  cuttlefish/        image fetch, KSU/APatch kernel, boot, snapshot
  avd/
  container/         waydroid/redroid
  chromium/
  aera/
managers/            install + configure each manager (debugging on)
driver/              one CLI: up, install-module, open-webui, eval, logs, screenshot, down
observations/        recorded host behaviour, one dir per host build
```

## License

LGPL-3.0-or-later with the LGPL-3.0 linking exception
(`LICENSE`, `LICENSE.exception`; SPDX `LGPL-3.0-or-later WITH LGPL-3.0-linking-exception`).
