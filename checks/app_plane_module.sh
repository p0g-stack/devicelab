#!/usr/bin/env bash
# Per-module app plane (webui-packages: the module carries its own app,
# com.webui.api.<id> at system/product/app/WebuiApi_<id>/): the installed app,
# its module config, and the demo's page 6 calls through it: share sheet, the
# camera permission dialog (deny, deny again = permanent, grant). With
# UNINSTALL=1 last: uninstall + soft-reboot, then what is left.
# Usage: [NAME=<module name>] app_plane_module.sh <label> <host pkg> [module id]
#   -> $LAB_OUT/<label>-appmod.jsonl, <label>-appmod-*.png/xml
set -uo pipefail
LABEL=$1; HPKG=$2; ID=${3:-demo}; APP=com.webui.api.$ID
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"; UI="python3 $HERE/managers/ui.py"
O=$OUT/$LABEL-appmod; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
sh_() { adb shell "$1" 2>&1 | tr -d '\r' | js; }
shot() { timeout 20 adb exec-out screencap -p >"$O-$1.png"; $UI dump "$O-$1.xml" >/dev/null 2>&1; }
top() { adb shell dumpsys activity activities | grep -m1 topResumedActivity | tr -d '\r' | sed 's/.*ActivityRecord{[^ ]* [^ ]* //; s/ t[0-9]*}//'; }
dialog() { $UI dump 2>/dev/null | cut -d' ' -f2- | head -12; }   # visible clickable labels
page_text() { text | python3 -c 'import json,sys; v=json.loads(sys.stdin.read()); v=v.get("value",v) if isinstance(v,dict) else v; print("\n".join(x for x in v if any(k in x for k in sys.argv[1:])))' "$@" 2>&1; }

rec app "$(sh_ "pm path $APP; ls -laZ /product/app/WebuiApi_$ID/ 2>&1; dumpsys package $APP | grep -E 'codePath|versionName|userId|pkgFlags|privateFlags|signatures|requested permissions' -A0 | head -10; dumpsys package $APP | grep -A12 'requested permissions:' | head -13")"
rec mounts "$(sh_ "ls -la /data/adb/metamodule 2>&1; grep -E ' /product| /system ' /proc/mounts | grep -v -E '^/dev/block/dm' | head -12; ls /product/app | head -40 | tr '\\n' ' '")"
rec app-label "$(sh_ "cmd package query-activities --brief -a android.intent.action.MAIN -p $APP 2>&1 | head -5; dumpsys package $APP | grep -m3 -i -E 'label|nonLocalizedLabel'")"
rec module-config "$(sh_ "/data/adb/ksud module config --help 2>&1 | head -12; echo '-- files:'; ls -la /data/adb/ksu/module_configs/$ID/ 2>&1; for f in /data/adb/ksu/module_configs/$ID/*; do echo \"== \$f\"; head -c 400 \$f; echo; done; echo '-- ksud get:'; KSU_MODULE=$ID /data/adb/ksud module config get webui.installed 2>&1; KSU_MODULE=$ID /data/adb/ksud module config list 2>&1 | head")"
rec module-dirs "$(sh_ "ls -la /data/adb/$ID /data/adb/$ID/tmp 2>&1 | head -20")"

# Page 6 (Plugins): open the module fresh, Places from home, then the nav bar.
rec open "\"$("$HERE/managers/open_webui.sh" "$LABEL-appmod" "$HPKG" "$ID" "${NAME:-$ID}" 2>&1 | tail -1)\""; sleep 8
ev "$HELP" >/dev/null; ev '__w.on(); "semantics on"' >/dev/null; sleep 2
rec tap-places "$(step Places)"; sleep 6
rec tap-plugins "$(step Plugins)"; sleep 6
rec plugins "$(page_text Camera Share share_plus permission)"; shot plugins

# Share: Android's chooser, started by the module's app.
adb logcat -c
rec tap-share "$(step 'Share text')"; sleep 8
rec share-top "\"$(top)\""; shot share
rec app-process "$(sh_ "ps -A -o USER,UID,LABEL,PID,NAME | grep -E 'webui.api' ")"
rec share-log "$(adb logcat -d | grep -i -E "$APP|chooser|share|BackgroundActivityStart|avc" | grep -v -E 'Enqueued|Broadcasting' | tail -12 | js)"
adb shell input keyevent KEYCODE_BACK; sleep 4
rec share-result "$(page_text 'Share result')"

# Camera: reset to never asked, then deny, deny (permanent), grant.
reset_cam() { adb shell "pm revoke $APP android.permission.CAMERA; pm clear-permission-flags $APP android.permission.CAMERA user-set user-fixed" 2>&1 | tr -d '\r'; }
reset_cam
cam() { # <tag> <button to press in the dialog or ''>
  rec cam-$1-tap "$(step 'Request camera')"; sleep 6
  rec cam-$1-top "\"$(top)\""; rec cam-$1-dialog "$(dialog | js)"; shot cam-$1
  [ -n "$2" ] && { rec cam-$1-press "$( (UI_WAIT=5 $UI tap "$2") 2>&1 | js)"; sleep 4; }
  rec cam-$1-status "$(page_text 'Camera:')"
  rec cam-$1-perm "$(sh_ "dumpsys package $APP | grep -A1 'android.permission.CAMERA' | head -4")"
}
cam deny-1 "Don"   # "Don’t allow" (curly apostrophe)
cam deny-2 "Don"
cam after-deny ''   # permanently denied: expect no dialog
adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1; sleep 1
reset_cam
cam grant "While using the app"
UI_WAIT=1 $UI has "Only this time" && { $UI tap "Only this time"; sleep 3; rec cam-grant-status-2 "$(page_text 'Camera:')"; }
# App info page for the app (what openAppSettings opens; the demo page has no button for it).
adb shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d "package:$APP" >/dev/null 2>&1; sleep 5
rec app-settings "$(dialog | js)"; shot app-settings
adb shell input keyevent KEYCODE_BACK; sleep 2

if [ "${UNINSTALL:-0}" = 1 ]; then
  rec uninstall "$(sh_ "/data/adb/ksud module uninstall $ID 2>&1 | tail -3")"
  adb shell /data/adb/ksud soft-reboot >/dev/null 2>&1; sleep 5; timeout 120 adb wait-for-device
  t0=$SECONDS; until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do (( SECONDS - t0 > 300 )) && break; sleep 3; done; sleep 20
  rec after-uninstall "$(sh_ "ls -d /data/adb/modules/$ID /data/adb/$ID /data/adb/ksu/module_configs/$ID /product/app/WebuiApi_$ID 2>&1; pm path $APP 2>&1; pm list packages $APP")"
fi
