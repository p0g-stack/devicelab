#!/usr/bin/env bash
# Can a `dart compile exe` binary run as root on Android? Tries each way of
# getting one onto bionic and records what happened. Expects a booted device
# with adb root (platforms/avd/up.sh) and the Linux Dart SDK on PATH.
# Writes $LAB_OUT/dart-bionic.json.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT"
ADB=${ADB:-adb}
ABI=$($ADB shell getprop ro.product.cpu.abi | tr -d '\r')
case $ABI in x86_64) TARCH=x86_64; LD=ld-linux-x86-64.so.2;; arm64-v8a) TARCH=aarch64; LD=ld-linux-aarch64.so.1;; *) echo "abi $ABI"; exit 1;; esac
LAB=/data/adb/devicelab           # where a module's binary would live
TP=/data/data/com.termux/files/usr
W=$(mktemp -d)

# Run a shell line on the device as root; append {name, cmd, exit, ms, stdout, stderr}.
RESULTS=$OUT/.results.jsonl; : >"$RESULTS"
dev() {
  local name=$1 cmd=$2
  local t0; t0=$(date +%s%N)
  $ADB shell "($cmd) >/data/local/tmp/o 2>/data/local/tmp/e; echo \$?" | tr -d '\r' >"$W/rc"
  local ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  $ADB shell cat /data/local/tmp/o >"$W/o"; $ADB shell cat /data/local/tmp/e >"$W/e"
  python3 - "$name" "$cmd" "$(cat "$W/rc")" "$ms" "$W/o" "$W/e" >>"$RESULTS" <<'PY'
import json, sys
n, c, rc, ms, o, e = sys.argv[1:]
out = open(o, errors="replace").read().strip(); err = open(e, errors="replace").read().strip()
try: parsed = json.loads(out)
except Exception: parsed = None
print(json.dumps({"name": n, "cmd": c, "exit": int(rc or -1), "ms": int(ms),
                  "stdout": parsed if parsed is not None else out[-4000:], "stderr": err[-4000:]}))
PY
  echo "== $name: exit $(cat "$W/rc") in ${ms}ms"; head -c 600 "$W/o"; echo; head -c 600 "$W/e"; echo
}

$ADB shell "rm -rf $LAB; mkdir -p $LAB/glibc /data/local/tmp/lab"
$ADB push "$HERE/bin/probe.dart" /data/local/tmp/lab/probe.dart >/dev/null

# 1. Official Linux SDK output (glibc), as is.
dart compile exe "$HERE/bin/probe.dart" -o "$W/probe-glibc" >/dev/null
cp "$W/probe-glibc" "$W/probe-glibc-patched"
for lib in $LD libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0; do
  f=$(ldconfig -p | awk -v l="$lib" '$1==l && /x86-64|AArch64/ {print $NF; exit}')
  [ -n "$f" ] && cp -L "$f" "$W/$lib" && $ADB push "$W/$lib" $LAB/glibc/ >/dev/null
done
patchelf --set-interpreter $LAB/glibc/$LD --set-rpath $LAB/glibc "$W/probe-glibc-patched"
$ADB push "$W/probe-glibc" "$W/probe-glibc-patched" $LAB/ >/dev/null
$ADB shell "chmod 755 $LAB/probe-glibc* $LAB/glibc/*"
readelf -lhd "$W/probe-glibc" >"$OUT/readelf-glibc.txt" 2>&1
dev glibc-direct "env -i PATH=/system/bin $LAB/probe-glibc"
dev glibc-via-loader "env -i PATH=/system/bin $LAB/glibc/$LD --library-path $LAB/glibc $LAB/probe-glibc"
dev glibc-patched-interp "env -i PATH=/system/bin $LAB/probe-glibc-patched"

# 2. Termux's Dart SDK (bionic) compiling on the device, then the output run
#    with Termux gone, from the module path, with an empty environment.
python3 "$HERE/termux_fetch.py" "$TARCH" dart "$W/termux" | tee "$OUT/termux-packages.txt"
$ADB shell "rm -rf /data/data/com.termux; mkdir -p /data/data/com.termux/files"
$ADB push "$W/termux/data/data/com.termux/files/usr" /data/data/com.termux/files/ >/dev/null
$ADB shell "chmod -R 755 $TP/bin $TP/lib; find $TP -path '*dart-sdk/bin/*' -type f -exec chmod 755 {} +"
TENV="env -i PATH=$TP/bin:/system/bin HOME=/data/local/tmp/lab TMPDIR=/data/local/tmp/lab PREFIX=$TP"
dev termux-dart-version "$TENV $TP/lib/dart-sdk/bin/dart --version"
dev termux-compile-exe "cd /data/local/tmp/lab && $TENV $TP/lib/dart-sdk/bin/dart compile exe probe.dart -o probe-bionic"
$ADB pull /data/local/tmp/lab/probe-bionic "$W/probe-bionic" >/dev/null 2>&1 &&
  readelf -lhd "$W/probe-bionic" >"$OUT/readelf-bionic.txt" 2>&1
dev termux-run-in-place "$TENV /data/local/tmp/lab/probe-bionic"
$ADB shell "chmod 755 /data/local/tmp/lab/probe-bionic; cp /data/local/tmp/lab/probe-bionic $LAB/ && chmod 755 $LAB/probe-bionic && mv /data/data/com.termux /data/data/com.termux.off"
dev bionic-module-path-no-termux "env -i PATH=/system/bin $LAB/probe-bionic"
dev bionic-module-path-tmpdir "env -i PATH=/system/bin TMPDIR=$LAB $LAB/probe-bionic"
# 3. AOT route: snapshot compiled on the host by the Linux SDK of the same
#    version, run by Termux's bionic dartaotruntime copied out of the package.
TVER=$(awk '$1=="dart"{print $2}' "$OUT/termux-packages.txt" | sed 's/-.*//')
HSDK=$W/host-sdk
curl -sSfLo "$W/sdk.zip" "https://storage.googleapis.com/dart-archive/channels/stable/release/$TVER/sdk/dartsdk-linux-x64-release.zip" &&
  unzip -q "$W/sdk.zip" -d "$HSDK"
"$HSDK/dart-sdk/bin/dart" compile aot-snapshot "$HERE/bin/probe.dart" -o "$W/probe.aot" >/dev/null
RT=$(find "$W/termux" -name dartaotruntime -type f | head -1)
echo "termux dart $TVER, runtime $RT"
readelf -lhd "$RT" >"$OUT/readelf-termux-dartaotruntime.txt" 2>&1
$ADB push "$RT" "$W/probe.aot" $LAB/ >/dev/null; $ADB shell chmod 755 $LAB/dartaotruntime
dev aot-host-snapshot-termux-runtime "env -i PATH=/system/bin $LAB/dartaotruntime $LAB/probe.aot"
ls -l "$W"/probe-* "$W/probe.aot" "$RT" | awk '{print $5, $NF}' >"$OUT/sizes.txt"; cat "$OUT/sizes.txt"
# 4. glibc loader + stock Linux dartaotruntime + snapshot (no appended exe,
#    so /proc/self/exe pointing at the loader does not matter).
$ADB push "$HSDK/dart-sdk/bin/dartaotruntime" $LAB/glibc/dartaotruntime-linux >/dev/null
$ADB shell chmod 755 $LAB/glibc/dartaotruntime-linux
dev glibc-loader-linux-runtime-aot "env -i PATH=/system/bin $LAB/glibc/$LD --library-path $LAB/glibc $LAB/glibc/dartaotruntime-linux $LAB/probe.aot"
du -b "$HSDK/dart-sdk/bin/dartaotruntime" "$W"/$LD "$W"/lib*.so* 2>/dev/null >>"$OUT/sizes.txt"
dev bionic-cold-start-x5 "for i in 1 2 3 4 5; do env -i $LAB/probe-bionic >/dev/null; done"
dev selinux-context "id; cat /proc/self/attr/current; getenforce"

python3 - "$RESULTS" "$OUT/dart-bionic.json" "$ABI" <<'PY'
import json, sys, subprocess, datetime
rows = [json.loads(l) for l in open(sys.argv[1])]
prop = lambda p: subprocess.run(["adb", "shell", "getprop", p], capture_output=True, text=True).stdout.strip()
json.dump({"probe": "dart_bionic", "date": datetime.date.today().isoformat(),
           "platform": "avd", "abi": sys.argv[3], "fingerprint": prop("ro.build.fingerprint"),
           "kernel": subprocess.run(["adb", "shell", "uname", "-r"], capture_output=True, text=True).stdout.strip(),
           "dartLinuxSdk": subprocess.run(["dart", "--version"], capture_output=True, text=True).stdout.strip(),
           "results": rows}, open(sys.argv[2], "w"), indent=1)
PY
echo "wrote $OUT/dart-bionic.json"
