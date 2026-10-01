#!/usr/bin/env bash
# flutter_p0g dart-android kit on a booted AVD as root: build the probe's
# Android snapshot with the kit, push runtime + snapshot to /data/adb, run
# with an empty environment (and with TMPDIR). Usage: run_kit_avd.sh <kit.tar.gz>
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT"; W=$(mktemp -d)
"$HERE/kit_snapshot.sh" "$1" "$W" | tee "$OUT/kit-build.txt" || exit 1
L=/data/adb/devicelab-kit
adb shell "rm -rf $L; mkdir -p $L"
adb push "$W/dartaotruntime" "$W/probe.aot" $L/ >/dev/null; adb shell chmod 755 $L/dartaotruntime
R=$OUT/.kit.jsonl; : >"$R"
dev() {
  local t0; t0=$(date +%s%N)
  adb shell "($2) >/data/local/tmp/o 2>/data/local/tmp/e; echo \$?" | tr -d '\r' >"$W/rc"
  local ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  adb shell cat /data/local/tmp/o >"$W/o"; adb shell cat /data/local/tmp/e >"$W/e"
  python3 - "$1" "$2" "$(cat "$W/rc")" "$ms" "$W/o" "$W/e" >>"$R" <<'PY'
import json, sys
n, c, rc, ms, o, e = sys.argv[1:]
out = open(o, errors="replace").read().strip(); err = open(e, errors="replace").read().strip()
try: out = json.loads(out)
except Exception: out = out[-3000:]
print(json.dumps({"name": n, "cmd": c, "exit": int(rc or -1), "ms": int(ms), "stdout": out, "stderr": err[-3000:]}))
PY
  echo "== $1: exit $(cat "$W/rc") in ${ms}ms"; head -c 400 "$W/o"; echo; head -c 400 "$W/e"; echo
}
dev kit-runtime-empty-env "env -i $L/dartaotruntime $L/probe.aot"
dev kit-runtime-tmpdir "env -i PATH=/system/bin TMPDIR=$L $L/dartaotruntime $L/probe.aot"
dev kit-cold-start-x5 "for i in 1 2 3 4 5; do env -i TMPDIR=$L $L/dartaotruntime $L/probe.aot >/dev/null; done"
python3 - "$R" "$OUT/dart-kit.json" "$1" <<'PY'
import json, sys, subprocess, datetime
p = lambda *a: subprocess.run(["adb", "shell", *a], capture_output=True, text=True).stdout.strip()
json.dump({"probe": "dart_bionic kit", "kit": sys.argv[3].rsplit("/", 1)[-1], "date": datetime.date.today().isoformat(),
           "fingerprint": p("getprop", "ro.build.fingerprint"), "kernel": p("uname", "-r"),
           "results": [json.loads(l) for l in open(sys.argv[1])]}, open(sys.argv[2], "w"), indent=1)
PY
