#!/usr/bin/env bash
# arm64 bionic without an arm64 emulator: the AVD arm64 system image's
# userland (linker64, bionic from the runtime APEX, mksh) in a chroot, run
# under qemu-user via binfmt. Shows whether arm64 binaries load and work
# against real bionic; cannot show kernel or SELinux behaviour.
# Needs sudo, qemu-user-static, ANDROID_HOME. Writes $LAB_OUT/dart-bionic-arm64.json.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT"
API=${1:-35}
W=$(mktemp -d); R=$W/root
IMG="system-images;android-$API;google_apis;arm64-v8a"
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --install "$IMG" < <(yes) >/dev/null 2>&1
D=$ANDROID_HOME/system-images/android-$API/google_apis/arm64-v8a
file "$D/system.img" | tee "$OUT/arm64-system-img.txt"

mnt() { # mount an fs image read-only, whatever its type
  local img=$1 dir=$2; mkdir -p "$dir"
  sudo mount -o loop,ro "$img" "$dir" 2>/dev/null && return
  local dev; dev=$(sudo losetup -fP --show "$img")
  for p in "$dev"p*; do sudo mount -o ro "$p" "$dir" 2>/dev/null && { echo "mounted $p"; return; }; done
  echo "cannot mount $img"; return 1
}
DEV=$(sudo losetup -fP --show "$D/system.img")
sudo sgdisk -p "$DEV" 2>/dev/null | tail -8
for p in "$DEV"p*; do echo "$p: $(sudo file -sL "$p" | cut -d: -f2 | cut -c1-120) $(sudo blkid -o export "$p" | tr '\n' ' ')"; done
mkdir -p "$W/sys"; for p in "$DEV"p*; do sudo mount -o ro "$p" "$W/sys" 2>/dev/null && { echo "mounted $p"; break; }; done
if ! mountpoint -q "$W/sys"; then
  SUPER=$(for p in "$DEV"p*; do sudo blkid -o value -s PARTLABEL "$p" | grep -qx super && echo "$p"; done)
  sudo python3 "$HERE/../../tools/lpunpack.py" "$SUPER" system "$W/system.img" || exit 1
  file "$W/system.img"; mnt "$W/system.img" "$W/sys" || exit 1
fi
ls "$W/sys" | head; S=$W/sys; [ -d "$S/system/bin" ] && S=$S/system
mkdir -p "$R"/{system,apex/com.android.runtime,data,proc,dev,tmp,linkerconfig}
sudo mount --bind "$S" "$R/system"
APEX=$(ls "$S"/apex/com.android.runtime*.apex 2>/dev/null | head -1)
if [ -f "$APEX" ]; then unzip -o -q "$APEX" apex_payload.img -d "$W/apex"; mnt "$W/apex/apex_payload.img" "$R/apex/com.android.runtime"
else sudo mount --bind "$S/apex/com.android.runtime" "$R/apex/com.android.runtime"; fi
sudo mount -t proc proc "$R/proc"; sudo mount --bind /dev "$R/dev"
ls "$R/apex/com.android.runtime/lib64/bionic" | tr '\n' ' '; echo

# Termux aarch64 Dart, and a host-built arm64 AOT snapshot of the same version.
python3 "$HERE/termux_fetch.py" aarch64 dart "$W/termux" | tee "$OUT/termux-packages-aarch64.txt"
TVER=$(awk '$1=="dart"{print $2}' "$OUT/termux-packages-aarch64.txt" | sed 's/-.*//')
curl -sSfLo "$W/sdk.zip" "https://storage.googleapis.com/dart-archive/channels/stable/release/$TVER/sdk/dartsdk-linux-x64-release.zip" && unzip -q "$W/sdk.zip" -d "$W/host"
HD=$W/host/dart-sdk/bin/dart
$HD compile aot-snapshot --target-os linux --target-arch arm64 "$HERE/bin/probe.dart" -o "$W/probe-arm64.aot" 2>&1 | tail -3
sudo mkdir -p "$R/data/data/com.termux/files"
sudo cp -a "$W/termux/data/data/com.termux/files/usr" "$R/data/data/com.termux/files/"
RT=$(cd "$R" && sudo find data/data/com.termux -name dartaotruntime -type f | head -1)
sudo mkdir -p "$R/data/adb/devicelab"; sudo cp "$R/$RT" "$W/probe-arm64.aot" "$HERE/bin/probe.dart" "$R/data/adb/devicelab/"
readelf -lhd "$R/$RT" >"$OUT/readelf-termux-dartaotruntime-arm64.txt" 2>&1
grep -E 'NEEDED|RUNPATH|interpreter' "$OUT/readelf-termux-dartaotruntime-arm64.txt"

RES=$OUT/.arm64.jsonl; : >"$RES"
run() { # name, then a command line for /system/bin/sh inside the chroot
  local t0; t0=$(date +%s%N)
  sudo chroot "$R" /system/bin/sh -c "$2" >"$W/o" 2>"$W/e"; local rc=$?
  python3 - "$1" "$2" "$rc" "$(( ($(date +%s%N) - t0) / 1000000 ))" "$W/o" "$W/e" >>"$RES" <<'PY'
import json, sys
n, c, rc, ms, o, e = sys.argv[1:]
out = open(o, errors="replace").read().strip(); err = open(e, errors="replace").read().strip()
try: out = json.loads(out)
except Exception: out = out[-3000:]
print(json.dumps({"name": n, "cmd": c, "exit": int(rc), "ms": int(ms), "stdout": out, "stderr": err[-3000:]}))
PY
  echo "== $1 exit $rc"; head -c 500 "$W/o"; echo; head -c 500 "$W/e"; echo
}
L=/data/adb/devicelab; TP=/data/data/com.termux/files/usr
run sh-works "echo bionic sh ok; /system/bin/toybox uname -m; ls -l /system/bin/env"
run aot-host-snapshot-termux-runtime "PATH=/system/bin $L/dartaotruntime $L/probe-arm64.aot"
run termux-compile-exe "cd $L && PATH=$TP/bin:/system/bin HOME=$L TMPDIR=$L $TP/lib/dart-sdk/bin/dart compile exe probe.dart -o probe-bionic"
sudo chmod 755 "$R$L/probe-bionic" 2>/dev/null
sudo mv "$R/data/data/com.termux" "$R/data/data/com.termux.off"
run bionic-exe-no-termux "PATH=/system/bin $L/probe-bionic"
# glibc-loader route on arm64: stock Linux arm64 dartaotruntime + Ubuntu
# arm64 glibc, snapshot from the same stock SDK.
curl -sSfLo "$W/rt-linux-arm64" "https://storage.googleapis.com/dart-archive/channels/stable/release/$TVER/sdk/dartaotruntime_linux_arm64"
GL=$(curl -sSfL http://ports.ubuntu.com/ubuntu-ports/dists/noble-updates/main/binary-arm64/Packages.gz | gunzip | awk '/^Package: libc6$/{p=1} p&&/^Filename:/{print $2; exit}')
curl -sSfLo "$W/libc6.deb" "http://ports.ubuntu.com/ubuntu-ports/$GL" && dpkg-deb -x "$W/libc6.deb" "$W/libc6"
sudo mkdir -p "$R$L/glibc"
sudo cp "$W/rt-linux-arm64" "$R$L/glibc/dartaotruntime-linux"; sudo chmod 755 "$R$L/glibc/dartaotruntime-linux"
for l in ld-linux-aarch64.so.1 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0; do sudo cp -L "$(find "$W/libc6" -name "$l" | head -1)" "$R$L/glibc/"; done
run glibc-loader-linux-runtime-aot "PATH=/system/bin TMPDIR=$L $L/glibc/ld-linux-aarch64.so.1 --library-path $L/glibc $L/glibc/dartaotruntime-linux $L/probe-arm64.aot"
# Termux bionic exe again, with TMPDIR set (its default is Termux's prefix).
run bionic-exe-tmpdir "PATH=/system/bin TMPDIR=$L $L/probe-bionic"
# flutter_p0g arm64 kit, when one is given: KIT=<kit.tar.gz>.
if [ -n "${KIT:-}" ]; then
  "$HERE/kit_snapshot.sh" "$KIT" "$W/kit" | tee "$OUT/kit-build-arm64.txt"
  sudo mkdir -p "$R$L/kit"; sudo cp "$W/kit/dartaotruntime" "$W/kit/probe.aot" "$R$L/kit/"; sudo chmod 755 "$R$L/kit/dartaotruntime"
  run kit-runtime "PATH=/system/bin TMPDIR=$L $L/kit/dartaotruntime $L/kit/probe.aot"
fi
ls -lR "$R$L" | tee "$OUT/sizes-arm64.txt"
python3 - "$RES" "$OUT/dart-bionic-arm64.json" "$API" "$TVER" <<'PY'
import json, sys, datetime
rows = [json.loads(l) for l in open(sys.argv[1])]
json.dump({"probe": "dart_bionic", "date": datetime.date.today().isoformat(),
           "platform": f"qemu-user chroot of AVD android-{sys.argv[3]} google_apis arm64-v8a system.img",
           "cannotShow": "kernel, SELinux, real CPU timing", "termuxDart": sys.argv[4], "results": rows},
          open(sys.argv[2], "w"), indent=1)
PY
