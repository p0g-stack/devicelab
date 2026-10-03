#!/usr/bin/env bash
# Root channel + app plane lifecycle with the demo (v0.1.47+: the channel holds
# RootHelperService through @<pkg>/hold). Numbers only. Phases:
#   open    page opened on its home page: does anything start? then Places
#   hold    is the hold socket connected, what root.log says, the channel's domain
#   swipe   page on Places, manager task swiped away from Recents
#   kill    page on Places, `am force-stop <manager>`
#   close   page closed by Back, then idle exit
#   sleep   page closed by Back, screen off right after
#   notif   POST_NOTIFICATIONS / appop / importance / is the FGS notice shown
#   stopsvc what `am stopservice` returns (service up, service down)
# Times are device uptime seconds; the sampler (lib/lc_sample.sh) logs changes.
# Usage: lifecycle.sh <label> <host pkg> <module id> [module name]
#   -> $LAB_OUT/<label>-lc.jsonl, <label>-lc-<phase>.txt, screenshots
set -uo pipefail
LABEL=$1; HPKG=$2; ID=$3; NAME=${4:-$3}; APP=com.webui.api.$ID; SVC=$APP/com.termux.api.RootHelperService
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"; UI="python3 $HERE/managers/ui.py"
O=$OUT/$LABEL-lc; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
sh_() { adb shell "$1" 2>&1 | tr -d '\r' | js; }
now() { adb shell "cut -d' ' -f1 /proc/uptime" | tr -d '\r'; }
mark() { rec "mark-$1" "\"$(now)\""; }
shot() { timeout 20 adb exec-out screencap -p >"$O-$1.png"; $UI dump "$O-$1.xml" >/dev/null 2>&1; }
top() { adb shell dumpsys activity activities | grep -m1 topResumedActivity | tr -d '\r'; }
RLOG=/data/adb/modules/$ID/flutter_webui/run/root.log
adb push "$HERE/checks/lib/lc_sample.sh" /data/local/tmp/lc_sample.sh >/dev/null; adb shell chmod 755 /data/local/tmp/lc_sample.sh
SP=""
sample() { adb shell sh /data/local/tmp/lc_sample.sh "$2" "$ID" "$APP" >"$O-$1.txt" 2>&1 & SP=$!; sleep 1; }
sample_wait() { wait "$SP" 2>/dev/null; rec "sample-$1" "$(tr -d '\r' <"$O-$1.txt" | js)"; }
rootlog() { rec "rootlog-$1" "$(sh_ "wc -l <$RLOG; tail -15 $RLOG")"; }
avc() { rec "avc-$1" "$(sh_ "dmesg | grep avc | grep -E 'unix_stream_socket|connectto|$APP|hold' | tail -8; logcat -d -b events,main | grep avc | grep -E 'connectto|$APP' | tail -6")"; }
open_places() { # <tag>: open the module's page fresh, then Places; sample from before the tap
  rec "open-$1" "\"$("$HERE/managers/open_webui.sh" "$LABEL-lc-$1" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1)\""; sleep 6
  ev "$HELP" >/dev/null; ev '__w.on(); "semantics on"' >/dev/null; sleep 2
  sample "$1-places" 25; mark "$1-tap-places"; rec "$1-tap" "$(step Places)"; sleep 22; sample_wait "$1-places"
}
close_back() { # Back until the WebUI activity is no longer resumed; records when it left
  local n
  for n in 1 2 3 4 5 6; do adb shell input keyevent KEYCODE_BACK; sleep 2.5; top | grep -q -i webui || { mark "$1-closed-after-back-$n"; return; }; done
  rec "$1-close" "\"still on top: $(top)\""; shot "$1-not-closed"
}
wake() { adb shell input keyevent KEYCODE_WAKEUP; sleep 1; adb shell wm dismiss-keyguard; sleep 2; }

rec setup "$(sh_ "getenforce; pm path $APP; dumpsys package $APP | grep -m2 -E 'versionCode|versionName'; /data/adb/ksud -V; dumpsys package $HPKG | grep -m1 versionName")"
adb shell "dmesg -c >/dev/null; logcat -c" 2>/dev/null
rootlog start

# open: home page first (nothing should start), then Places.
rec open-home "\"$("$HERE/managers/open_webui.sh" "$LABEL-lc-home" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1)\""
mark home-opened; sample home 20; sample_wait home
ev "$HELP" >/dev/null; ev '__w.on(); "semantics on"' >/dev/null; sleep 2
sample places 25; mark tap-places; rec tap-places "$(step Places)"; sleep 22; sample_wait places

# hold: the channel's side of @<pkg>/hold, its domain, the log.
CH=$(adb shell pgrep -f "'flutter_webui_root.aot serve'" | tr -d '\r' | head -1)
rec hold "$(sh_ "echo channel pid $CH; cat /proc/$CH/attr/current; echo; ps -o USER,PID,PPID,LABEL,ARGS -p $CH; echo '-- /proc/net/unix:'; grep -E 'hold' /proc/net/unix; echo '-- channel fds -> sockets:'; ls -l /proc/$CH/fd 2>/dev/null | grep -c socket; echo '-- service:'; dumpsys activity services $SVC | grep -E 'ServiceRecord|isForeground|foregroundId|startRequested'")"
rootlog hold; avc hold
rec procs "$(sh_ "ps -A -o USER,PID,PPID,LABEL,NAME,ARGS | grep -E 'webui|demo|$APP' | grep -v grep")"

# notif: notification state of the silently installed app, with the FGS up.
rec notif-perm "$(sh_ "dumpsys package $APP | grep -E 'POST_NOTIFICATIONS' ; echo '-- appops:'; appops get $APP POST_NOTIFICATION; appops get $APP 2>&1 | head -20; echo '-- targetSdk:'; dumpsys package $APP | grep -m1 targetSdk")"
rec notif-importance "$(sh_ "dumpsys notification --noredact | grep -E \"$APP\" | grep -v -E '^ *$' | head -20; echo '-- channels:'; cmd notification list 2>&1 | grep $APP | head")"
rec notif-record "$(sh_ "dumpsys notification --noredact | grep -A14 \"NotificationRecord.*pkg=$APP\" | head -30")"
adb shell cmd statusbar expand-notifications; sleep 3; shot notif-shade
rec notif-shade "$(grep -o -E '(text|content-desc)="[^"]+"' "$O-notif-shade.xml" 2>/dev/null | sort -u | head -40 | js)"
adb shell cmd statusbar collapse; sleep 2
rec notif-fgs-manager "$(sh_ "dumpsys activity services $SVC | grep -E 'isForeground|foregroundNoti|fgRequired|fgWaiting' | head; dumpsys activity processes $APP 2>/dev/null | grep -E 'curProcState|setProcState|mCurSchedGroup|hasForegroundServices' | head -6")"

# notify (v0.1.48+): page 6 "Show notification" asks through Android's one-time
# prompt for a legacy-target app, then posts. Deny first, reset, then allow.
page_text() { text | python3 -c 'import json,sys
try: v = json.loads(sys.stdin.read())
except Exception: v = []
v = v.get("value", v) if isinstance(v, dict) else v
print(json.dumps([x for x in (v or []) if any(k in x for k in sys.argv[1:])][:12]))' "$@" 2>&1; }
reset_notif() { adb shell "pm revoke $APP android.permission.POST_NOTIFICATIONS; pm clear-permission-flags $APP android.permission.POST_NOTIFICATIONS user-set user-fixed" 2>&1 | tr -d '\r'; }
perm() { sh_ "dumpsys package $APP | grep -A1 'POST_NOTIFICATIONS' | head -4; appops get $APP POST_NOTIFICATION"; }
notify() { # <tag> <button in Android's prompt>
  adb shell logcat -c
  rec "notify-$1-tap" "$(step 'Show notification')"; sleep 6
  rec "notify-$1-top" "\"$(top)\""; rec "notify-$1-dialog" "$($UI dump 2>/dev/null | cut -d' ' -f2- | head -12 | js)"; shot "notify-$1"
  [ -n "$2" ] && { rec "notify-$1-press" "$( (UI_EXACT=$([ "$2" = Allow ] && echo 1 || echo "") UI_WAIT=5 $UI tap "$2") 2>&1 | js)"; sleep 5; }
  rec "notify-$1-page" "$(page_text otification ermission ranted enied)"
  rec "notify-$1-perm" "$(perm)"
  rec "notify-$1-log" "$(adb logcat -d | grep -i -E 'NotificationPrompt|GrantPermissions|PermissionPolicy|BackgroundActivityStart|POST_NOTIFICATIONS|$APP' | grep -v -E 'Enqueued|Broadcasting' | tail -14 | js)"
  rec "notify-$1-records" "$(sh_ "dumpsys notification --noredact | grep -E 'NotificationRecord.*pkg=$APP' | head -6")"
  adb shell cmd statusbar expand-notifications; sleep 3; shot "notify-$1-shade"
  rec "notify-$1-shade" "$(grep -o -E '(text|content-desc)="[^"]+"' "$O-notify-$1-shade.xml" 2>/dev/null | sort -u | head -40 | js)"
  adb shell cmd statusbar collapse; sleep 2
  top | grep -q -i webui || "$HERE/managers/back_to_app.sh" >/dev/null 2>&1; sleep 3
}
rec tap-plugins "$(step Plugins)"; sleep 6
if scroll_to 'Show notification'; then
  rec notify-before "$(perm)"
  notify deny "Don"
  notify after-deny ""
  reset_notif; rec notify-reset "$(perm)"
  notify allow "Allow"
  notify after-allow ""
else rec notify '"no Show notification button on page 6"'; fi
rec tap-places-2 "$(step Places)"; sleep 4

# swipe: Recents, swipe the top card away (page on Places, FGS up).
read -r W H < <(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)
TASK=$(top | sed -n 's/.* t\([0-9]*\)}.*/\1/p')
recents_swipe() { adb shell input keyevent KEYCODE_APP_SWITCH; for _ in 1 2 3 4 5; do sleep 1; adb shell dumpsys activity activities | grep -m1 topResumedActivity | grep -q -i -E 'recents|launcher' && break; done; sleep 1
  adb shell input swipe $((W / 2)) $((H / 2)) $((W / 2)) $((H / 12)) 200; }
task_alive() { adb shell dumpsys activity recents | grep -q "#$TASK "; }
sample swipe 60; mark swipe-recents; recents_swipe; mark swipe-done; sleep 2; shot swipe-after
task_alive && { rec swipe-retry "\"task $TASK still in recents\""; recents_swipe; mark swipe-done-2; sleep 2; shot swipe-after-2; }
rec swipe-tasks "$(sh_ "dumpsys activity recents | grep -E 'Recent #|realActivity' | head -10; pidof $HPKG")"
adb shell input keyevent KEYCODE_HOME; sample_wait swipe; rootlog swipe; avc swipe

# kill: force-stop the manager (KernelSU's own manager: closing it).
open_places kill
sample kill 60; mark kill-force-stop; adb shell am force-stop "$HPKG"; sample_wait kill; rootlog kill

# close: Back out of the page, normal screen.
open_places close
sample close 240; mark close-back; close_back close; sample_wait close; rootlog close; avc close

# sleep: Back out, screen off right after.
open_places sleep
sample sleep 240; mark sleep-back; close_back sleep; adb shell input keyevent KEYCODE_SLEEP; mark sleep-screen-off; sample_wait sleep
wake; rootlog sleep

# stopsvc: what `am stopservice` returns, service up and service down (adb root, u:r:su:s0).
rec stopsvc "$(sh_ "am start-foreground-service --user 0 -n $SVC; echo start-exit=\$?; sleep 2; am stopservice --user 0 -n $SVC; echo stop-up-exit=\$?; sleep 2; am stopservice --user 0 -n $SVC; echo stop-down-exit=\$?")"
rec stopsvc-rootlog "$(sh_ "grep -n -E 'stopservice|start-foreground-service|hold' $RLOG | tail -12")"

# Summary per phase: seconds after the mark until each thing first went to its end state.
python3 - "$O" "$J" <<'PY' | tee -a "$J"
import json, re, sys
O, J = sys.argv[1], sys.argv[2]
marks = {}
for l in open(J):
    j = json.loads(l)
    if j["check"].startswith("mark-"): marks[j["check"][5:]] = float(j["result"])
def rows(name):
    out = []
    try:
        for l in open(f"{O}-{name}.txt"):
            m = re.match(r"([\d.]+) (?:end )?(.*)", l.strip())
            if m: out.append((float(m.group(1)), dict(kv.split("=", 1) for kv in m.group(2).split() if "=" in kv)))
    except FileNotFoundError: pass
    return out
def first(rs, t0, pred):
    for t, s in rs:
        if t >= t0 and pred(s): return round(t - t0, 1)
    return None
def gone(k): return lambda s: s.get(k, "") in ("", "0")
for ph, mk in [("places", "tap-places"), ("kill-places", "kill-tap-places"), ("close-places", "close-tap-places"), ("sleep-places", "sleep-tap-places")]:
    rs = rows(ph); t0 = marks.get(mk)
    if t0 is None: continue
    print(json.dumps({"check": f"summary-{ph}", "result": {"channel_up_s": first(rs, t0, lambda s: s.get("ch")), "conn_up_s": first(rs, t0, lambda s: s.get("conn", "0") != "0"), "fgs_up_s": first(rs, t0, lambda s: s.get("fgs", "0") != "0"), "hold_connected_s": first(rs, t0, lambda s: int(s.get("hold", "0") or 0) >= 2), "root_process_up_s": first(rs, t0, lambda s: s.get("aot"))}}))
for ph, mk in [("swipe", "swipe-done"), ("kill", "kill-force-stop"), ("close", "close-back"), ("sleep", "sleep-back")]:
    rs = rows(ph); t0 = marks.get(mk)
    if t0 is None: continue
    closed = [v for k, v in marks.items() if k.startswith(f"{ph}-closed-after-back")]
    print(json.dumps({"check": f"summary-{ph}", "result": {"mark": t0, "page_left_s": round(closed[0] - t0, 1) if closed else None, "conn_zero_s": first(rs, t0, gone("conn")), "channel_gone_s": first(rs, t0, gone("ch")), "root_process_gone_s": first(rs, t0, gone("aot")), "hold_released_s": first(rs, t0, lambda s: int(s.get("hold", "0") or 0) < 2), "fgs_gone_s": first(rs, t0, gone("fgs")), "notif_gone_s": first(rs, t0, gone("notif")), "app_gone_s": first(rs, t0, gone("app")), "end_state": rs[-1][1] if rs else None}}))
PY
