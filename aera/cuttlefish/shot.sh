#!/usr/bin/env bash
# Capture Cuttlefish display 0 to a PNG through the host tools (works in
# recovery too, where there is no screencap). Usage: shot.sh FILE.png
set -u
CF_HOME=${CF_HOME:-$HOME/cf}
f=$(realpath -m "$1")
sudo -u "$USER" -H env HOME="$CF_HOME" PATH="$PATH" cvd display screenshot --screenshot_path="$f" >/dev/null 2>"$f.err" \
  || sudo -u "$USER" -H env HOME="$CF_HOME" PATH="$PATH" cvd screenshot --screenshot_path="$f" >/dev/null 2>>"$f.err"
if [ -s "$f" ]; then echo "[cf] frame -> $f"; rm -f "$f.err"
else echo "[cf] screenshot failed:"; tail -5 "$f.err"; sudo -u "$USER" -H env HOME="$CF_HOME" cvd display --help 2>&1 | head -30; fi
