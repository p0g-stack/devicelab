#!/usr/bin/env bash
# flutter-webui root channel (bebb1ec, needs ksud module config = KernelSU/Next 3.x):
# `sh <moddir>/flutter_webui/root start` prints one JSON line (version 0.2.0) and
# exits 0; webui.session/webui.boot live in the tmp module config (no webroot/.run);
# run/ is 0700 with lock, start.lock, root.log, proc/; /data/adb/<id>/tmp is emptied
# on the first start after a boot; a second start reuses the pid; deleting
# webui.session makes the next start replace the channel; the page's hello is uid 0.
# Usage: root_channel.sh <label> <host pkg> <module id> [module name]
#   -> $LAB_OUT/<label>-rootch.jsonl
set -uo pipefail
LABEL=$1; HPKG=$2; ID=$3; NAME=${4:-$3}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"
O=$OUT/$LABEL-rootch; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
sh_() { adb shell "$1" 2>&1 | tr -d '\r' | js; }
MOD=/data/adb/modules/$ID; FW=$MOD/flutter_webui; KSUD=/data/adb/ksud
cfg() { adb shell "for k in webui.session webui.boot; do printf '%s=' \$k; KSU_MODULE=$ID $KSUD module config get \$k 2>&1; done; echo '-- list:'; KSU_MODULE=$ID $KSUD module config list 2>&1 | head -12" | tr -d '\r'; }
# As the manager runs module shell: uid 0 in u:r:ksu:s0 (sockprobe), else adb root.
asroot() { adb shell "if [ -x /data/local/tmp/sockprobe ]; then /data/local/tmp/sockprobe -as-uid 0 -as-ctx u:r:ksu:s0 /system/bin/sh -c '$1'; else /system/bin/sh -c '$1'; fi" 2>&1 | tr -d '\r'; }
start() { asroot "cd /; sh $FW/root start; echo exit=\$?"; }
pid_of() { python3 -c 'import json,re,sys
for l in sys.stdin:
    l = l.strip()
    if l.startswith("{"):
        try: j = json.loads(l)
        except Exception: continue
        print(j.get("pid", "")); break'; }
layout() { sh_ "ls -la $FW 2>&1; echo '-- run:'; stat -c '%a %U:%G %n' $FW/run 2>&1; ls -la $FW/run $FW/run/proc 2>&1 | head -20; echo '-- webroot/.run:'; ls -la $MOD/webroot/.run 2>&1"; }
soft_reboot() {
  adb shell $KSUD soft-reboot >/dev/null 2>&1; sleep 5; timeout 120 adb wait-for-device; t0=$SECONDS
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && adb shell pidof system_server >/dev/null; do (( SECONDS - t0 > 300 )) && break; sleep 3; done; sleep 25
}

[ -n "${SOCKPROBE:-}" ] && adb push "$SOCKPROBE" /data/local/tmp/sockprobe >/dev/null && adb shell chmod 755 /data/local/tmp/sockprobe
rec ksud-version "$(sh_ "$KSUD -V 2>&1; $KSUD module config --help 2>&1 | head -3")"
rec root-script "$(sh_ "ls -la $FW/root 2>&1; head -30 $FW/root 2>&1")"
rec layout-before "$(layout)"
rec config-before "$(cfg | js)"
# Boot: leave a marker in tmp, soft-reboot, the first start must empty tmp.
adb shell "mkdir -p /data/adb/$ID/tmp && echo lab >/data/adb/$ID/tmp/lab-marker && ls -la /data/adb/$ID/tmp" >/dev/null 2>&1
soft_reboot
rec config-after-boot "$(cfg | js)"
rec tmp-after-boot "$(sh_ "ls -la /data/adb/$ID/tmp 2>&1")"
S1=$(start); rec start-1 "$(echo "$S1" | js)"; P1=$(echo "$S1" | pid_of)
rec tmp-after-start-1 "$(sh_ "ls -la /data/adb/$ID/tmp 2>&1")"
rec config-after-start-1 "$(cfg | js)"
rec layout-after-start-1 "$(layout)"
S2=$(start); rec start-2 "$(echo "$S2" | js)"; P2=$(echo "$S2" | pid_of)
rec same-pid "$(echo "{\"first\":\"$P1\",\"second\":\"$P2\",\"same\":$([ -n "$P1" ] && [ "$P1" = "$P2" ] && echo true || echo false)}")"
rec delete-session "$(sh_ "KSU_MODULE=$ID $KSUD module config delete --temp webui.session 2>&1; echo exit=\$?")"
S3=$(start); rec start-3 "$(echo "$S3" | js)"; P3=$(echo "$S3" | pid_of); sleep 2
rec replaced "$(echo "{\"old\":\"$P2\",\"new\":\"$P3\",\"new_pid\":$([ -n "$P3" ] && [ "$P3" != "$P2" ] && echo true || echo false),\"old_alive\":\"$(adb shell "[ -n '$P2' ] && kill -0 $P2 2>/dev/null && echo yes || echo no" | tr -d '\r')\"}")"
rec procs "$(sh_ "ps -A -o USER,PID,PPID,LABEL,NAME,ARGS | grep -i -E 'webui|$ID' | grep -v grep | head -12")"
rec root-log "$(sh_ "tail -20 $FW/run/root.log 2>&1")"
rec config-end "$(cfg | js)"
# The page's hello: open the module and look for uid in the page text.
rec open "\"$("$HERE/managers/open_webui.sh" "$LABEL-rootch" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1)\""; sleep 10
rec page-uid "$(text | python3 -c 'import json,sys
try: v = json.loads(sys.stdin.read())
except Exception: v = []
v = v.get("value", v) if isinstance(v, dict) else v
print(json.dumps([x for x in (v or []) if any(k in x.lower() for k in ("uid", "root", "hello", "channel"))][:12]))' 2>&1)"
rec start-after-page "$(echo "$(start)" | js)"
rec layout-end "$(layout)"
