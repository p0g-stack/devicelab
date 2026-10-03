#!/usr/bin/env bash
# Root channel lifetime around a WebUI page: a non-root page starts nothing,
# Places starts the channel; after the page is closed, when do the last
# loopback connection to the channel's port, the channel, the app's root
# process and the helper FGS go away? Once normally, once with the screen off
# right after closing. Plus what `am stopservice` returns.
# Usage: idle_timing.sh <label> <host pkg> <module id> [module name]  -> $LAB_OUT/<label>-idle.jsonl
set -uo pipefail
LABEL=$1; HPKG=$2; ID=$3; NAME=${4:-$3}; APP=com.webui.api.$ID
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"
O=$OUT/$LABEL-idle; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
sh_() { adb shell "$1" 2>&1 | tr -d '\r' | js; }
top() { adb shell dumpsys activity activities | grep -m1 topResumedActivity | tr -d '\r'; }
chan() { adb shell "pgrep -f flutter_webui_root.aot" 2>/dev/null | tr -d '\r' | head -1; }
place() { adb shell "pgrep -f 'serve --session-file'" 2>/dev/null | tr -d '\r' | head -1; }
fgs() { adb shell "dumpsys activity services $APP/com.termux.api.RootHelperService | grep -c ServiceRecord" 2>/dev/null | tr -d '\r'; }
port() { adb shell "KSU_MODULE=$ID /data/adb/ksud module config get webui.session" 2>/dev/null | python3 -c 'import json,sys
try: print(json.loads(sys.stdin.read())["port"])
except Exception: print("")'; }
conns() { [ -n "$1" ] && adb shell "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null" | python3 -c '
import sys
p = "%04X" % int(sys.argv[1]); n = 0
for l in sys.stdin:
    f = l.split()
    if len(f) > 3 and f[3] == "01" and (f[1].endswith(":" + p) or f[2].endswith(":" + p)): n += 1
print(n)' "$1" || echo "?"; }
open_page() { "$HERE/managers/open_webui.sh" "$LABEL-idle-$1" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1; }
close_page() { for _ in 1 2 3 4; do top | grep -q -i webui || break; adb shell input keyevent KEYCODE_BACK; sleep 1.5; done; top | grep -q -i webui && adb shell input keyevent KEYCODE_HOME; }

# Stop whatever an earlier check left running, then a fresh page on Home (no root use).
adb shell "pkill -f flutter_webui_root.aot; pkill -f 'serve --session-file'" >/dev/null 2>&1; adb shell am force-stop "$HPKG"; sleep 3
rec open-home "\"$(open_page home)\""; sleep 10
rec home-only "\"channel=$(chan) place=$(place) fgs=$(fgs)\""
ev "$HELP" >/dev/null
round() { # <tag> <screen off after close: 0|1>
  rec $1-tap-places "$(step Places)"; local t0=$SECONDS
  until [ -n "$(chan)" ] || (( SECONDS - t0 > 20 )); do sleep 1; done
  rec $1-channel-up-after "\"$((SECONDS - t0)) s (pid $(chan))\""; sleep 8
  local P; P=$(port); rec $1-state-open "\"port=$P conns=$(conns "$P") channel=$(chan) place=$(place) fgs=$(fgs)\""
  close_page; local tc=$SECONDS; [ "$2" = 1 ] && adb shell input keyevent KEYCODE_SLEEP
  rec $1-closed "\"$(date -u +%T) top: $(top | sed 's/.*ActivityRecord{[^ ]* [^ ]* //; s/ t[0-9]*}//')\""
  local tconn= tchan= tplace= tfgs=
  while (( SECONDS - tc < 240 )); do
    local d=$((SECONDS - tc))
    [ -z "$tconn" ] && [ "$(conns "$P")" = 0 ] && tconn=$d
    [ -z "$tchan" ] && [ -z "$(chan)" ] && tchan=$d
    [ -z "$tplace" ] && [ -z "$(place)" ] && tplace=$d
    [ -z "$tfgs" ] && [ "$(fgs)" = 0 ] && tfgs=$d
    [ -n "$tconn" ] && [ -n "$tchan" ] && [ -n "$tplace" ] && [ -n "$tfgs" ] && break
    sleep 2
  done
  rec $1-after-close "{\"conn_dropped_s\":\"${tconn:->240}\",\"channel_exit_s\":\"${tchan:->240}\",\"place_exit_s\":\"${tplace:->240}\",\"fgs_gone_s\":\"${tfgs:->240}\"}"
  rec $1-root-log "$(sh_ "tail -15 /data/adb/modules/$ID/flutter_webui/run/root.log")"
  [ "$2" = 1 ] && { adb shell input keyevent KEYCODE_WAKEUP; sleep 1; adb shell wm dismiss-keyguard; sleep 2; }
}
round normal 0
rec reopen "\"$(open_page screenoff)\""; sleep 8; ev "$HELP" >/dev/null
round screenoff 1
# am stopservice's own exit status (service started by hand, as adb root).
rec stopservice "$(sh_ "am start-foreground-service --user 0 -n $APP/com.termux.api.RootHelperService; sleep 2; am stopservice --user 0 -n $APP/com.termux.api.RootHelperService; echo exit=\$?; sleep 1; dumpsys activity services $APP/com.termux.api.RootHelperService | grep -c ServiceRecord")"
