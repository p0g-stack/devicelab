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
rec app-user "$(sh_ "pm list packages -3 $APP; pm list packages -s $APP | sed 's/^/system: /'; dumpsys package $APP | grep -E 'versionCode|installerPackageName|installInitiatingPackageName' | head -4; echo '-- install log:'; cat /data/adb/modules/$ID/webui_app_plane/app-install.log 2>&1 | tail -5")"
rec mounts "$(sh_ "ls -la /data/adb/metamodule 2>&1; grep -E ' /product| /system ' /proc/mounts | grep -v -E '^/dev/block/dm' | head -12; ls /product/app | head -40 | tr '\\n' ' '")"
rec app-label "$(sh_ "cmd package query-activities --brief -a android.intent.action.MAIN -p $APP 2>&1 | head -5; dumpsys package $APP | grep -m3 -i -E 'label|nonLocalizedLabel'")"
rec metamodule-log "$(sh_ "M=\$(readlink /data/adb/metamodule); echo \"metamodule \$M\"; ls -la \$M 2>&1 | head -20; for f in \$(find \$M /data/adb/\${M##*/}* /data/adb/ksu/log /cache -maxdepth 3 \\( -name '*.log' -o -name '*.txt' \\) 2>/dev/null | head -8); do echo \"== \$f\"; tail -25 \$f; done; ls -la /data/adb/modules/$ID 2>&1 | head; echo '-- dmesg:'; dmesg | grep -i -E 'hybrid|magic|overlay|mountify|meta' | tail -15")"
rec module-config "$(sh_ "/data/adb/ksud module config --help 2>&1 | head -12; echo '-- files:'; ls -la /data/adb/ksu/module_configs/$ID/ 2>&1; for f in /data/adb/ksu/module_configs/$ID/*; do echo \"== \$f\"; head -c 400 \$f; echo; done; echo '-- ksud get:'; KSU_MODULE=$ID /data/adb/ksud module config get webui.installed 2>&1; KSU_MODULE=$ID /data/adb/ksud module config list 2>&1 | head")"
rec module-dirs "$(sh_ "ls -la /data/adb/$ID /data/adb/$ID/tmp 2>&1 | head -20")"

# Page 6 (Plugins): open the module fresh, Places from home, then the nav bar.
rec open "\"$("$HERE/managers/open_webui.sh" "$LABEL-appmod" "$HPKG" "$ID" "${NAME:-$ID}" 2>&1 | tail -1)\""; sleep 8
ev "$HELP" >/dev/null; ev '__w.on(); "semantics on"' >/dev/null; sleep 2
rec tap-places "$(step Places)"; sleep 6
rec tap-plugins "$(step Plugins)"; sleep 6
fgs() { sh_ "dumpsys activity services $APP 2>&1 | grep -E 'ServiceRecord|isForeground|foregroundId' | head -6; echo '-- notification:'; dumpsys notification --noredact 2>&1 | grep -A4 \"pkg=$APP\" | head -12; echo '-- procs:'; ps -A -o USER,PID,NAME | grep -E 'webui.api|dartaotruntime'"; }
rec fgs-open "$(fgs)"
rec plugins "$(page_text Camera Share share_plus permission)"; shot plugins

# Share: Android's chooser, started by the module's app.
adb logcat -c
rec tap-share "$(step 'Share text')"; sleep 8
rec share-top "\"$(top)\""; shot share
rec app-process "$(sh_ "ps -A -o USER,UID,LABEL,PID,NAME | grep -E 'webui.api' ")"
rec app-mounts "$(sh_ "p=\$(pidof $APP); [ -n \"\$p\" ] && { echo \"pid \$p\"; grep -c . /proc/\$p/mounts; grep -E '/product/app|/data/adb|mountify|KSU' /proc/\$p/mounts | head -6; } || echo 'app not running'")"
rec share-log "$(adb logcat -d | grep -i -E "$APP|chooser|share|BackgroundActivityStart|avc" | grep -v -E 'Enqueued|Broadcasting' | tail -12 | js)"
for _ in 1 2 3; do adb shell input keyevent KEYCODE_BACK; sleep 3; top | grep -q -i webui && break; done  # WX on KernelSU: one Back left the chooser up
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
top | grep -q -i webui || { adb shell input keyevent KEYCODE_BACK >/dev/null 2>&1; sleep 1; }  # Back on the page itself closes a manager WebUI
reset_cam
cam grant "While using the app"
UI_WAIT=1 $UI has "Only this time" && { $UI tap "Only this time"; sleep 3; rec cam-grant-status-2 "$(page_text 'Camera:')"; }
# Clipboard (clipboard_webui through the app's invisible read activity) and
# file pick, when page 6 has the buttons ("Copy text", "Paste", "Pick a file").
has_btn() { ev "$HELP" >/dev/null; ev "new Promise(r => { __w.on(); setTimeout(() => r(!!__w.find($(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"))), 600) })" | grep -q '"value": *true'; }
ext_copy() { # put $1 on Android's clipboard from another app (Settings search)
  adb shell am start -a android.settings.APP_SEARCH_SETTINGS >/dev/null 2>&1 || adb shell am start -a android.settings.SETTINGS >/dev/null 2>&1; sleep 4
  adb shell input text "$1"; sleep 1; adb shell input keycombination 113 29; adb shell input keycombination 113 31; sleep 1
}
ext_paste() { # paste Android's clipboard into Settings search and read it back
  adb shell am start -a android.settings.APP_SEARCH_SETTINGS >/dev/null 2>&1 || adb shell am start -a android.settings.SETTINGS >/dev/null 2>&1; sleep 4
  adb shell input keycombination 113 29; adb shell input keyevent KEYCODE_DEL; adb shell input keycombination 113 50; sleep 2
  $UI dump "$O-ext-paste.xml" >/dev/null 2>&1; grep -o 'text="[^"]*"' "$O-ext-paste.xml" | head -5 | tr '\n' ' '
}
back_to_page() { # leave Settings by Back (its task returns to the WebUI's); Recents if not
  for _ in 1 2 3; do top | grep -q -i webui && break; adb shell input keyevent KEYCODE_BACK; sleep 2; done
  top | grep -q -i webui || "$HERE/managers/back_to_app.sh" >/dev/null 2>&1; sleep 4; }
LISTEN='window.__msgs = []; addEventListener("message", e => __msgs.push([Math.round(performance.now()), typeof e.data === "string" ? e.data : JSON.stringify(e.data)])); document.addEventListener("visibilitychange", () => __msgs.push([Math.round(performance.now()), "visibility " + document.visibilityState])); "listening"'
# The buttons sit below the fold: scroll page 6 down first (Flutter scrolls on
# touch, not on DOM scrollIntoView).
scroll_to Paste; shot plugins-scrolled
if on Paste; then
  ext_copy "lab-clip-$$"; back_to_page
  scroll_to Paste
  rec clip-listen "$(ev "$LISTEN")"
  rec clip-paste-tap "$(step Paste)"; sleep 8
  rec clip-paste-top "\"$(top)\""; shot clip-paste
  rec clip-pasted "$(page_text Pasted Paste clipboard)"
  rec clip-blips "$(ev 'JSON.stringify(window.__msgs || [])')"
  rec clip-process "$(sh_ "ps -A -o USER,LABEL,NAME | grep webui.api; dumpsys activity activities | grep -E 'webui.api' | head -4")"
  rec clip-copy-tap "$(step 'Copy text')"; sleep 5
  rec clip-copied "$(page_text Copied Copy clipboard)"
  rec clip-ext-paste "$(ext_paste | js)"; back_to_page
else rec clipboard '"no Paste button on page 6"'; fi
if scroll_to 'Pick a file'; then
  adb shell "echo lab-pick >/sdcard/Download/lab-pick.txt; am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Download/lab-pick.txt" >/dev/null 2>&1
  rec pick-tap "$(step 'Pick a file')"; sleep 6
  rec pick-top "\"$(top)\""; shot pick
  UI_WAIT=8 $UI tap lab-pick.txt >/dev/null 2>&1 || { UI_WAIT=3 $UI tap Downloads; sleep 3; UI_WAIT=8 $UI tap lab-pick.txt; } >/dev/null 2>&1; sleep 6
  rec picked "$(page_text Picked pick file)"
  rec pick-files "$(sh_ "ls -laZ /data/adb/$ID/tmp/ /data/adb/$ID/tmp/open-*/ 2>&1 | head -20")"
else rec file-pick '"no Pick a file button on page 6"'; fi
# App info page for the app (what openAppSettings opens; the demo page has no button for it).
adb shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d "package:$APP" >/dev/null 2>&1; sleep 5
rec app-settings "$(dialog | js)"; shot app-settings
adb shell input keyevent KEYCODE_BACK; sleep 2

# Foreground helper service: up while the WebUI's root channel is wound up, gone after its idle exit.
adb shell input keyevent KEYCODE_HOME; sleep 50; rec fgs-home "$(fgs)"
adb shell am force-stop "$HPKG"; sleep 45; rec fgs-closed "$(fgs)"
# Reboot keeps the user app (soft-reboot here: the AVD has no KernelSU at real boot).
adb shell /data/adb/ksud soft-reboot >/dev/null 2>&1; sleep 5; timeout 120 adb wait-for-device
t0=$SECONDS; until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do (( SECONDS - t0 > 300 )) && break; sleep 3; done; sleep 30
rec after-reboot "$(sh_ "pm path $APP; dumpsys package $APP | grep -E 'versionCode|codePath' | head -2; echo '-- service.sh log:'; cat /data/adb/modules/$ID/webui_app_plane/app-install.log 2>&1 | tail -5")"
if [ "${UNINSTALL:-0}" = 1 ]; then
  rec uninstall "$(sh_ "/data/adb/ksud module uninstall $ID 2>&1 | tail -3")"
  adb shell /data/adb/ksud soft-reboot >/dev/null 2>&1; sleep 5; timeout 120 adb wait-for-device
  t0=$SECONDS; until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do (( SECONDS - t0 > 300 )) && break; sleep 3; done; sleep 45  # uninstall.sh runs pm uninstall after boot_completed
  rec after-uninstall "$(sh_ "ls -d /data/adb/modules/$ID /data/adb/$ID /data/adb/ksu/module_configs/$ID /product/app/WebuiApi_$ID 2>&1; pm path $APP 2>&1; pm list packages $APP")"
fi
