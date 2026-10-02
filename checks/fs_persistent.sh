#!/usr/bin/env bash
# fs.persistent per place (p0g_app 0.8.5: the WebUI root process works in
# /data/adb/<id>). The Places page shows facts as icons only, so read them where
# they are decided: the root process's working folder (/proc/<pid>/cwd) and the
# CLI's own `facts` there; the page and a Web Worker: navigator.storage.persisted().
# Usage: fs_persistent.sh <label> <host pkg> <module id> [module name]
#   -> $LAB_OUT/<label>-fsp.jsonl
set -uo pipefail
LABEL=$1; HPKG=$2; ID=$3; NAME=${4:-$3}
OUT=${LAB_OUT:-$PWD/out}; HERE=$(cd "$(dirname "$0")/.." && pwd)
WV="node $HERE/driver/webview.mjs"
O=$OUT/$LABEL-fsp; J=$O.jsonl; : >"$J"
. "$HERE/checks/lib/sem.sh"
js() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'; }
rec() { echo "{\"check\":\"$1\",\"result\":${2:-null}}" | tee -a "$J"; }
sh_() { adb shell "$1" 2>&1 | tr -d '\r' | js; }
MOD=/data/adb/modules/$ID

rec open "\"$("$HERE/managers/open_webui.sh" "$LABEL-fsp" "$HPKG" "$ID" "$NAME" 2>&1 | tail -1)\""; sleep 8
rec tap-places "$(step Places)"; sleep 15
timeout 20 adb exec-out screencap -p >"$O-places.png"
rec places "$(text)"
# The root process place: `<module>/bin/<app> serve --session-file ...`.
rec root-process "$(sh_ "for p in \$(pgrep -f 'serve --session-file'); do echo \"pid \$p uid \$(stat -c %u /proc/\$p) ctx \$(cat /proc/\$p/attr/current | tr -d '\\0') cwd \$(readlink /proc/\$p/cwd)\"; tr '\\0' ' ' </proc/\$p/cmdline; echo; done")"
rec root-cwd "$(sh_ "p=\$(pgrep -f 'serve --session-file' | head -1); [ -n \"\$p\" ] && readlink /proc/\$p/cwd || echo 'no root process'")"
# The same facts check the root place runs, from the CLI in that folder (and from / for contrast).
rec cli-facts-datadir "$(sh_ "cd /data/adb/$ID && $MOD/bin/$ID facts 2>&1 | head -30")"
rec cli-facts-slash "$(sh_ "cd / && $MOD/bin/$ID facts 2>&1 | grep -E 'fs.persistent|root'")"
rec page-persisted "$(ev '(navigator.storage && navigator.storage.persisted ? navigator.storage.persisted().then(v => ({persisted: v})) : Promise.resolve({persisted: "no navigator.storage"}))')"
rec worker-persisted "$(ev 'new Promise(r => { const src = "navigator.storage && navigator.storage.persisted ? navigator.storage.persisted().then(v => postMessage({persisted: v})) : postMessage({persisted: \"no navigator.storage\"})"; let w; try { w = new Worker(URL.createObjectURL(new Blob([src], {type: "text/javascript"}))) } catch (e) { return r({error: String(e)}) } w.onmessage = e => { r(e.data); w.terminate() }; w.onerror = e => r({error: e.message || "error"}); setTimeout(() => r({error: "timeout"}), 6000) })')"
