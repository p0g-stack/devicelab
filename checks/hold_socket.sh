#!/usr/bin/env bash
# webui-termux-api RootHelperService hold socket (webui.8+): the service binds
# abstract @<pkg>/hold and stops when the last holder disconnects, or 10 s after
# start with no holder. Can the root channel's domain (u:r:ksu:s0 on these
# setups) connect to an untrusted_app's abstract socket?
# Usage: hold_socket.sh <label> <apk>   -> $LAB_OUT/<label>-hold.jsonl
set -uo pipefail
LABEL=$1; APK=$2
OUT=${LAB_OUT:-$PWD/out}; J=$OUT/$LABEL-hold.jsonl; : >"$J"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
sh_() { adb shell "$1" 2>&1 | tr -d '\r' | js; }
AAPT=$(ls "$ANDROID_HOME"/build-tools/*/aapt2 2>/dev/null | tail -1)
PKG=$("$AAPT" dump packagename "$APK" 2>/dev/null | tr -d '\r')
rec apk "$(echo "pkg $PKG sha256 $(sha256sum "$APK" | cut -c1-64) aapt2 $AAPT" | js)"
[ -n "${SOCKPROBE:-}" ] && adb push "$SOCKPROBE" /data/local/tmp/sockprobe >/dev/null && adb shell chmod 755 /data/local/tmp/sockprobe
adb push "$APK" /data/local/tmp/hold.apk >/dev/null
rec install "$(sh_ "pm install -r /data/local/tmp/hold.apk </dev/null; pm path $PKG; dumpsys package $PKG | grep -m2 -E 'versionCode|versionName'")"
SVC=$PKG/com.termux.api.RootHelperService
up() { adb shell "dumpsys activity services $SVC 2>/dev/null | grep -c 'ServiceRecord{'" | tr -d '\r'; }
start_svc() { adb shell "am start-foreground-service --user 0 -n $SVC" 2>&1 | tr -d '\r'; }
# Seconds until the service is gone (poll every second, give up at $1).
gone_after() { local t0=$SECONDS; while (( SECONDS - t0 < $1 )); do [ "$(up)" = 0 ] && { echo $((SECONDS - t0)); return; }; sleep 1; done; echo "still up after $1 s"; }
avc() { adb shell "dmesg | grep avc | grep -E 'unix_stream_socket|connectto|$PKG' | tail -6" | tr -d '\r'; }
rec su-domain "$(sh_ "su -c 'id; cat /proc/self/attr/current' 2>&1 </dev/null; echo; ls -la /system/bin/su /data/adb/ksud 2>&1")"

# 1. Nobody connects: expect a stop about 10 s after start.
adb shell am force-stop "$PKG"; adb shell dmesg -c >/dev/null 2>&1
rec idle-start "$(start_svc | js)"; sleep 1; rec idle-up "\"$(up)\""
rec idle-gone "\"$(gone_after 30)\""
# 2. Hold from each domain for 20 s: up while held, gone soon after release.
hold() { # <tag> <command; ARGS is replaced by the sockprobe hold op>
  adb shell am force-stop "$PKG"; sleep 1; adb shell dmesg -c >/dev/null 2>&1
  rec $1-start "$(start_svc | js)"; sleep 2
  adb shell "${2//ARGS/hold:$PKG/hold:20}" >"$OUT/$LABEL-hold-$1.txt" 2>&1 &
  local hp=$!; sleep 15
  rec $1-held "$(echo "up=$(up) $(head -c 600 "$OUT/$LABEL-hold-$1.txt")" | tr -d '\r' | js)"
  wait $hp
  rec $1-holder "$(tr -d '\r' <"$OUT/$LABEL-hold-$1.txt" | js)"
  rec $1-gone "\"$(gone_after 20)\""
  rec $1-avc "$(avc | js)"
}
hold ksu-setcon "/data/local/tmp/sockprobe -as-uid 0 -as-ctx u:r:ksu:s0 ARGS"
hold ksu-su "su -c 'cat /proc/self/attr/current; echo; /data/local/tmp/sockprobe -as-uid 0 ARGS' </dev/null"
hold su-adbroot "/data/local/tmp/sockprobe -as-uid 0 ARGS"
adb shell am force-stop "$PKG"
