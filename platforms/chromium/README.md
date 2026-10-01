# chromium

The plain-browser floor: headless Chromium (Playwright's build) opening a
built web dir served the way WebUI hosts serve it, with no COOP/COEP.

```sh
node platforms/chromium/open.mjs build/web --mobile --wait-ms 5000 \
  --eval 'document.title' --screenshot out.png
```

Prints one JSON observation (browser version, load time,
`crossOriginIsolated`, console, page errors, eval result). `--headers coop`
adds COOP/COEP for comparison runs. `--mobile` uses a Pixel-sized viewport
with touch.

What it cannot show: Android System WebView differences (pauseTimers,
onPause visibility, addJavascriptInterface objects). Those come from the AVD
platform.
