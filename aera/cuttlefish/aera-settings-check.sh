#!/usr/bin/env bash
# flutter-aera reads AERA's saved settings at launch (fadd7b1): 24-hour
# clock from tw_military_time, dynamic_color's accent from
# aera_theme_accent. Save each combination in AERA's settings file, relaunch
# the probe app (aera/apps/settings_probe) and capture it.
# Usage: aera-settings-check.sh PKG.aerap  ->  $LAB_OUT/aera-settings/
set -uo pipefail
PKG=$1
OUT=${LAB_OUT:-$PWD/out}/aera-settings; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
here=$(cd "$(dirname "$0")/.." && pwd)
a() { $ADB -s 0.0.0.0:6520 "$@"; }
log() { echo "[settings] $*" | tee -a "$OUT/log.txt"; }

shot() {
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 1; a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && log "frame $1.png" || log "no frame for $1"
}
rpc() {
  echo "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
# Save KEY=VALUE pairs in every settings file AERA may use (the newest wins).
save() {
  local files; files=$(a shell 'for f in /sdcard/AERA/.aera /data/recovery/AERA/.aera; do [ -f $f ] && echo $f; done' | tr -d '\r')
  [ -n "$files" ] || files=/sdcard/AERA/.aera
  for f in $files; do
    rm -f "$OUT/.aera"; a pull "$f" "$OUT/.aera" >/dev/null 2>&1
    python3 "$here/tools/aera_settings.py" set "$OUT/.aera" "$@" >/dev/null
    a shell "mkdir -p ${f%/*}"; a push "$OUT/.aera" "$f" >/dev/null && log "saved $* in $f"
  done
}
launch() {  # launch NAME: stop the running app, open it, capture
  a shell 'pkill -f aera-flutter; sleep 2'
  log "open: $(rpc '{"v":1,"id":"settings","op":"plugin","args":{"action":"open","id":"'"$id"'"}}' | tr '\n' ' ')"
  sleep "${APP_WAIT:-25}"; shot "$1"
}

id=$(unzip -p "$PKG" plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"; unzip -q "$PKG" -d "$OUT/.pkg"
a shell "mkdir -p /tmp/aera/plugins/$id && chmod 700 /tmp/aera /tmp/aera/plugins"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" "/tmp/aera/plugins/$id/" >/dev/null
a shell 'for f in /sdcard/AERA/.aera /data/recovery/AERA/.aera; do ls -la $f; done' > "$OUT/files-before.txt" 2>&1
for f in /sdcard/AERA/.aera /data/recovery/AERA/.aera; do
  a pull "$f" "$OUT/.orig" >/dev/null 2>&1 && { echo "== $f"; python3 "$here/tools/aera_settings.py" dump "$OUT/.orig" | grep -E "military|accent"; } >> "$OUT/files-before.txt"
done
log "installed $id"

save tw_military_time=1 aera_theme_accent=ff8800
launch 24h-orange
save tw_military_time=0 aera_theme_accent=16c8ff
launch 12h-default
a shell "tail -30 /sdcard/AERA/plugin-data/$id/aera-flutter.log /tmp/aera/plugin-data/$id/aera-flutter.log 2>/dev/null" > "$OUT/aera-flutter.log" 2>&1
rm -rf "$OUT/.pkg" "$OUT/.aera" "$OUT/.orig" "$OUT/.req.json"
exit 0
