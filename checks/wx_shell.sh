#!/usr/bin/env bash
# WebUI X shell permission gate (v608 and later gate ksu.exec behind
# "kernelsu.permission.SHELL" in the module's webroot/config.json permissions;
# without it the host shows an Allow/Reject overlay and exec returns null with
# no callback). From a fresh host state (WebUI X's per-module config under
# /data/adb/.config/<id> removed), open the module and for 40 s record: any
# overlay text on screen, the page's text, root.log, and whether the host wrote
# its own config.webroot.json. Then probe ksu.exec directly from the page.
# Usage: wx_shell.sh <label> <host pkg> <module id> [module name]
#   -> $LAB_OUT/<label>-wxshell.jsonl
set -uo pipefail
LABEL=$1; HPKG=$2; ID=$3; NAME=${4:-$3}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"; UI="python3 $HERE/managers/ui.py"
O=$OUT/$LABEL-wxshell; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
sh_() { adb shell "$1" 2>&1 | tr -d '\r' | js; }
FW=/data/adb/modules/$ID/flutter_webui
now() { adb shell "cut -d' ' -f1 /proc/uptime" | tr -d '\r'; }

rec host-version "$(sh_ "dumpsys package $HPKG | grep -m2 -E 'versionName|versionCode'")"
rec module-config "$(sh_ "cat /data/adb/modules/$ID/webroot/config.json 2>&1")"
rec host-config-before "$(sh_ "ls -la /data/adb/.config/$ID 2>&1; cat /data/adb/.config/$ID/config.webroot.json 2>&1")"
adb shell "rm -rf /data/adb/.config/$ID"
# A channel left from an earlier check would answer without a new exec.
adb shell "pkill -f '[f]lutter_webui_root.aot serve'; rm -f $FW/run/root.log" 2>/dev/null
T0=$(now)
rec open "\"$("$HERE/managers/open_webui.sh" "$LABEL-wxshell" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1)\""
rec open-uptime "\"$T0\""
for i in $(seq 1 20); do
  t=$(now)
  ov=$($UI dump "$O-$i.xml" 2>/dev/null | grep -i -E 'allow|reject|missing permission|deny' | head -5 | tr '\n' '|')
  [ -n "$ov" ] && timeout 20 adb exec-out screencap -p >"$O-overlay-$i.png"
  pt=$(text | python3 -c 'import json,sys
try: v = json.loads(sys.stdin.read())
except Exception: v = []
v = v.get("value", v) if isinstance(v, dict) else v
print(json.dumps([x for x in (v or []) if any(k in x.lower() for k in ("root", "shell", "refus", "channel", "error", "timeout", "uid", "permission"))][:8]))' 2>/dev/null)
  rl=$(adb shell "grep -m1 -E 'listening' $FW/run/root.log 2>/dev/null; [ -f /data/adb/.config/$ID/config.webroot.json ] && echo host-config-written" | tr -d '\r' | tr '\n' '|')
  rec "t$i" "$(printf '{"uptime":"%s","overlay":%s,"page":%s,"root":%s}' "$t" "$(printf %s "$ov" | js)" "${pt:-null}" "$(printf %s "$rl" | js)")"
  sleep 1
done
timeout 20 adb exec-out screencap -p >"$O-end.png"
rec root-log "$(sh_ "cat $FW/run/root.log 2>&1 | head -8")"
rec host-config-after "$(sh_ "ls -la /data/adb/.config/$ID 2>&1; cat /data/adb/.config/$ID/config.webroot.json 2>&1 | head -40")"
# A root call from the page's own UI: Say hello starts the root channel through
# ksu.exec. Time until the page shows the hello, or an error (a refused shell
# should fail in about 2 s, not after the 30 s exec timeout).
# The home card runs in a Web Worker until "Process" (the root process) is picked.
rec process-tap "$(step 'Process')"; sleep 1
TH=$(now); rec hello-tap "$(step 'Say hello')"
for i in $(seq 1 20); do
  t=$(now)
  pt=$(text | python3 -c 'import json,sys
try: v = json.loads(sys.stdin.read())
except Exception: v = []
v = v.get("value", v) if isinstance(v, dict) else v
print(json.dumps([x[:200] for x in (v or []) if any(k in x.lower() for k in ("runs in", "hello,", "uid", "refus", "error", "timeout", "denied", "permission", "opening", "fail"))][:6]))' 2>/dev/null)
  ov=$($UI dump "$O-hello-$i.xml" 2>/dev/null | grep -i -E 'allow|reject|missing permission' | head -3 | tr '\n' '|')
  rec "hello-t$i" "$(printf '{"uptime":"%s","since_tap":"%s","page":%s,"overlay":%s}' "$t" "$(echo "$t - $TH" | bc 2>/dev/null)" "${pt:-null}" "$(printf %s "$ov" | js)")"
  case "$pt" in *[a-zA-Z]*) case "$pt" in '[]') ;; *) [ $i -ge 3 ] && break;; esac;; esac
  sleep 1
done
timeout 20 adb exec-out screencap -p >"$O-hello.png"
# Straight from the page: does ksu.exec run and call back, and how fast?
rec exec-probe "$(ev 'new Promise(r => { if (!window.ksu || typeof ksu.exec !== "function") return r({ksu: typeof window.ksu}); const t = performance.now(), cb = "__labcb" + Date.now(); window[cb] = (c, o, e) => r({callback: true, code: c, out: String(o).slice(0, 80), ms: Math.round(performance.now() - t)}); let ret; try { ret = ksu.exec("id", "{}", cb) } catch (e) { return r({threw: String(e)}) } setTimeout(() => r({callback: false, returned: String(ret), ms: 5000}), 5000) })')"
adb logcat -d 2>/dev/null | grep -i -E 'permission|shell|webui' | grep -v -E 'nativeloader|PackageManager' | tail -60 >"$O-logcat.txt"
# Host extras as the page sees them (WebUI X v608: webui.createShortcut /
# hasShortcut, ksu.listPackages / getPackagesInfo, ksu://icon/<pkg>), probed
# straight from JS, not through flutter-webui's WebUi.* wrappers.
rec host-extras "$(ev 'new Promise(async r => { const o = {}; const t = (k, f) => { try { o[k] = f() } catch (e) { o[k] = "throw " + String(e).slice(0, 120) } };
  for (const [ns, m] of [["webui", "createShortcut"], ["webui", "hasShortcut"], ["ksu", "listPackages"], ["ksu", "getPackagesInfo"], ["ksu", "listUserPackages"], ["ksu", "exit"], ["webui", "exit"]]) o["typeof " + ns + "." + m] = typeof (window[ns] && window[ns][m]);
  if (window.ksu && typeof ksu.listPackages === "function") t("listPackages(user) length", () => { const v = ksu.listPackages("user"); try { return JSON.parse(v).length } catch (e) { return String(v).slice(0, 120) } });
  if (window.ksu && typeof ksu.getPackagesInfo === "function") t("getPackagesInfo([android])", () => String(ksu.getPackagesInfo(JSON.stringify(["android"]))).slice(0, 400));
  if (window.webui && typeof webui.hasShortcut === "function") t("hasShortcut()", () => String(webui.hasShortcut()));
  o.icon = await new Promise(q => { const i = new Image(); i.onload = () => q("loaded " + i.naturalWidth + "x" + i.naturalHeight); i.onerror = () => q("error"); i.src = "ksu://icon/android"; setTimeout(() => q("timeout"), 4000) });
  r(o) })')"
