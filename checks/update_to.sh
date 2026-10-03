#!/usr/bin/env bash
# Module update by zip (what the manager's Update button does after its
# download): install a newer demo release over the installed one with
# `ksud module install`, soft-reboot, then Android's view of the app plane app.
# Usage: update_to.sh <label> <module id> <zip>   -> $LAB_OUT/<label>-updto.jsonl
set -uo pipefail
LABEL=$1; ID=$2; ZIP=$3; APP=com.webui.api.$ID
OUT=${LAB_OUT:-$PWD/out}; J=$OUT/$LABEL-updto.jsonl; : >"$J"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
sh_() { adb shell "$1" 2>&1 | tr -d '\r' | js; }
appinfo() { sh_ "grep -E '^(version|versionCode)=' /data/adb/modules/$ID/module.prop; pm path $APP; dumpsys package $APP | grep -E 'versionCode|versionName|codePath|installerPackageName|lastUpdateTime|pkgFlags|signatures' | head -10; pm list packages -3 $APP; echo '-- install log:'; tail -8 /data/adb/modules/$ID/webui_app_plane/app-install.log 2>&1"; }
rec zip "\"$(basename "$ZIP") $(sha256sum "$ZIP" | cut -c1-64)\""
rec before "$(appinfo)"
adb push "$ZIP" /data/local/tmp/update.zip >/dev/null
rec install "$(sh_ "/data/adb/ksud module install /data/local/tmp/update.zip 2>&1 | tail -15; echo exit=\$?")"
rec staged "$(appinfo)"
adb shell /data/adb/ksud soft-reboot >/dev/null 2>&1; sleep 5; timeout 120 adb wait-for-device; t0=$SECONDS
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && adb shell pidof system_server >/dev/null; do (( SECONDS - t0 > 300 )) && break; sleep 3; done; sleep 30
rec after-reboot "$(appinfo)"
rec runtime "$(sh_ "cd /data/adb/modules/$ID; du -sh . ; find . -name dartaotruntime -o -name '*.aot' -o -name '*.so' | xargs stat -c '%h links inode %i %s %n'")"
