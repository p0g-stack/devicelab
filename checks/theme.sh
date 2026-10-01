#!/usr/bin/env bash
# Manager theme -> page: for each (manager colour mode, system night mode),
# open the module's WebUI and record what the page sees: prefers-color-scheme
# (Flutter web's platformBrightness), /internal/colors.css, and a screenshot.
# KernelSU: color_mode in shared_prefs/settings.xml (0 system, 1 light,
# 2 dark, 3 Monet system, 4 Monet light, 5 Monet dark); others: night mode only.
# Usage: theme.sh <label> <pkg> <module id> [module name]  -> $LAB_OUT/<label>-theme.jsonl
set -uo pipefail
LABEL=$1; PKG=$2; ID=$3; NAME=${4:-$3}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
J=$OUT/$LABEL-theme.jsonl; : >"$J"
WV="node $HERE/driver/webview.mjs"
PREFS=/data/data/$PKG/shared_prefs/settings.xml
color_mode() { # KernelSU only; rewrite in place so the file keeps its owner and label
  adb shell "am force-stop $PKG; f=$PREFS; [ -f \$f ] || { mkdir -p \${f%/*}; echo '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?>' >\$f; echo '<map>' >>\$f; echo '</map>' >>\$f; chown \$(stat -c %u:%g /data/data/$PKG) \$f \${f%/*}; restorecon -R \${f%/*}; }
    { grep -v -e 'name=\"color_mode\"' -e '</map>' \$f; echo '    <int name=\"color_mode\" value=\"$1\" />'; echo '</map>'; } >/data/local/tmp/settings.xml && cat /data/local/tmp/settings.xml >\$f"
}
probe='Promise.all([fetch("/internal/colors.css").then(r => r.text()).catch(e => "error " + e), new Promise(r => setTimeout(r, 0))]).then(([css]) => ({dark: matchMedia("(prefers-color-scheme: dark)").matches, primary: (css.match(/--primary:\s*(#\w+)/) || [])[1] || null, background: (css.match(/--background:\s*(#\w+)/) || [])[1] || null, cssBytes: css.length}))'
run() { # <tag> <night yes|no> [color_mode]
  local tag=$1 night=$2 cm=${3:-}
  adb shell cmd uimode night "$night" >/dev/null
  [ -n "$cm" ] && color_mode "$cm"
  sleep 2
  local opened=$("$HERE/managers/open_webui.sh" "$LABEL-theme-$tag" "$PKG" "$ID" "$NAME" 2>&1 | tail -1)
  sleep 10
  local v=$($WV eval "$probe" 2>&1 | tail -1)
  echo "{\"check\":\"$tag\",\"night\":\"$night\",\"color_mode\":\"${cm:-}\",\"opened\":\"$opened\",\"result\":${v:-null}}" | tee -a "$J"
  timeout 20 adb exec-out screencap -p >"$OUT/$LABEL-theme-$tag.png"
}
case $PKG in
  me.weishu.kernelsu)
    run monet-dark-sys-light no 5
    run monet-light-sys-dark yes 4
    run monet-system-sys-dark yes 3
    run dark-sys-light no 2
    run system-sys-dark yes 0
    color_mode 0;;
  *)
    run sys-dark yes
    run sys-light no;;
esac
adb shell cmd uimode night no >/dev/null
