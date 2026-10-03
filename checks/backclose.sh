#!/usr/bin/env bash
# Evidence for "page closed, channel stays" (KernelSU 3.3.0's own manager in
# the v0.1.49 walk): close the page on Places by Back, then by the manager's
# own close (the page calling the host's exit API), and at 0, 60, 120 and 240 s
# capture root.log, the newest run/proc/*.log, every TCP socket on the channel's
# port (state and owning pid), processes with ages, the WebUI activity's state
# and whether the page still exists in DevTools.
# Usage: backclose.sh <label> <host pkg> <module id> [module name]  -> $LAB_OUT/<label>-bc.jsonl
set -uo pipefail
LABEL=$1; HPKG=$2; ID=$3; NAME=${4:-$3}; APP=com.webui.api.$ID
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"; UI="python3 $HERE/managers/ui.py"
O=$OUT/$LABEL-bc; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
sh_() { adb shell "$1" 2>&1 | tr -d '\r' | js; }
top() { adb shell dumpsys activity activities | grep -m1 topResumedActivity | tr -d '\r'; }
RUN=/data/adb/modules/$ID/flutter_webui/run
snap() { # <tag>
  rec "$1-uptime" "\"$(adb shell "cut -d' ' -f1 /proc/uptime" | tr -d '\r')\""
  rec "$1-rootlog" "$(sh_ "tail -12 $RUN/root.log")"
  rec "$1-proclog" "$(sh_ "ls -lt $RUN/proc 2>&1 | head -8; f=\$(ls -t $RUN/proc/*.log 2>/dev/null | head -1); echo \"== \$f\"; tail -20 \"\$f\" 2>&1")"
  rec "$1-sockets" "$(sh_ "p=\$(KSU_MODULE=$ID /data/adb/ksud module config get webui.session 2>/dev/null | sed -n 's/.*\"port\": *\\([0-9]*\\).*/\\1/p'); [ -z \"\$p\" ] && p=\$(cat /data/local/tmp/bc.port 2>/dev/null); echo \"port \$p\"; [ -n \"\$p\" ] && echo \$p >/data/local/tmp/bc.port; hp=\$(printf '%04X' \"\$p\"); cat /proc/net/tcp /proc/net/tcp6 | awk -v p=\":\$hp\" 'substr(\$2, length(\$2)-4) == p || substr(\$3, length(\$3)-4) == p { print \$2, \$3, \$4, \$10 }' | while read l r st ino; do o=\$(for f in /proc/[0-9]*/fd/*; do [ \"\$(readlink \$f 2>/dev/null)\" = \"socket:[\$ino]\" ] && { d=\${f#/proc/}; echo \${d%%/*}; break; }; done); n=\$([ -n \"\$o\" ] && tr '\\0' ' ' </proc/\$o/cmdline | cut -c1-60); echo \"\$l \$r st=\$st ino=\$ino pid=\$o \$n\"; done")"
  rec "$1-procs" "$(sh_ "ps -A -o PID,PPID,ETIME,LABEL,ARGS | grep -E 'flutter_webui|demo|$APP|$HPKG|sandboxed_process|webview' | grep -v grep | cut -c1-200")"
  rec "$1-activity" "$(sh_ "dumpsys activity activities | grep -E 'WebUI|$HPKG' | grep -E 'ActivityRecord|state=|finishing' | head -10; dumpsys activity processes $HPKG | grep -E 'curProcState|lastActivityTime|hasActivities' | head -4")"
  rec "$1-devtools" "$($WV list 2>&1 | head -c 800 | js)"
  rec "$1-cgroup" "$(sh_ "for p in \$(pgrep -f '[f]lutter_webui_root.aot serve') \$(pgrep -f 'demo[.]aot') \$(pidof $HPKG); do echo \"== pid \$p: \$(tr '\\0' ' ' </proc/\$p/cmdline | cut -c1-70)\"; cat /proc/\$p/cgroup; grep '^State:' /proc/\$p/status; for c in \$(sed -n 's/^0:://p' /proc/\$p/cgroup); do echo \"cgroup.freeze \$(cat /sys/fs/cgroup\$c/cgroup.freeze 2>&1) cgroup.events: \$(tr '\\n' ' ' </sys/fs/cgroup\$c/cgroup.events 2>&1)\"; done; done")"
  rec "$1-rootport" "$(sh_ "p=\$(sed -n 's/.*\"port\": *\\([0-9]*\\).*/\\1/p' /data/adb/modules/$ID/run/demo.place.json 2>/dev/null | head -1); echo \"root process port \$p\"; [ -n \"\$p\" ] && { hp=\$(printf '%04X' \"\$p\"); cat /proc/net/tcp /proc/net/tcp6 | awk -v p=\":\$hp\" 'substr(\$2, length(\$2)-4) == p || substr(\$3, length(\$3)-4) == p { print \$2, \$3, \$4, \$10 }' | while read l r st ino; do o=\$(for f in /proc/[0-9]*/fd/*; do [ \"\$(readlink \$f 2>/dev/null)\" = \"socket:[\$ino]\" ] && { d=\${f#/proc/}; echo \${d%%/*}; break; }; done); echo \"\$l \$r st=\$st pid=\$o \$([ -n \"\$o\" ] && tr '\\0' ' ' </proc/\$o/cmdline | cut -c1-50)\"; done; }")"
  rec "$1-service" "$(sh_ "dumpsys activity services $APP/com.termux.api.RootHelperService | grep -E 'ServiceRecord|isForeground' ; grep -c '@$APP/hold' /proc/net/unix")"
}
phase() { # <tag> <how: back|exit>
  rec "$1-open" "\"$("$HERE/managers/open_webui.sh" "$LABEL-bc-$1" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1)\""; sleep 6
  ev "$HELP" >/dev/null; ev '__w.on(); "semantics on"' >/dev/null; sleep 2
  rec "$1-places" "$(step Places)"; sleep 12
  snap "$1-before"
  if [ "$2" = back ]; then
    for n in 1 2 3 4; do adb shell input keyevent KEYCODE_BACK; sleep 2.5; top | grep -q -i webui || break; done
    rec "$1-closed" "\"after $n Back: $(top)\""
  else
    rec "$1-exit-api" "$(ev 'JSON.stringify({ksu: typeof window.ksu, exit: window.ksu && typeof ksu.exit, webui: typeof window.webui, webuiExit: window.webui && typeof webui.exit})')"
    rec "$1-exit-call" "$(ev 'setTimeout(() => { try { (window.webui && webui.exit) ? webui.exit() : ksu.exit() } catch (e) { console.log(e) } }, 200); "called"')"
    sleep 3; rec "$1-closed" "\"$(top)\""
  fi
  timeout 20 adb exec-out screencap -p >"$O-$1-closed.png"
  snap "$1-t0"; sleep 55; snap "$1-t60"; sleep 55; snap "$1-t120"; sleep 115; snap "$1-t240"
}
phase back back
phase exit exit
