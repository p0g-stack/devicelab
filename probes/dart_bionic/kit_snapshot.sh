#!/usr/bin/env bash
# Build an Android AOT snapshot of the probe with a dart-android kit
# (flutter_p0g: VERSION, ABI, gen_snapshot [linux-x64 host], dartaotruntime).
# Kernel comes from the stock SDK of the kit's version, targeting android.
# Usage: kit_snapshot.sh <kit.tar.gz> <out-dir>   -> <out>/probe.aot, <out>/dartaotruntime
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$1; O=$2; mkdir -p "$O/kit"
tar -xzf "$KIT" -C "$O/kit"
K=$(dirname "$(find "$O/kit" -name VERSION | head -1)")
VER=$(cat "$K/VERSION" | tr -d '[:space:]'); ABI=$(cat "$K/ABI" | tr -d '[:space:]')
case $ABI in arm64*) ARCH=arm64;; x86_64) ARCH=x64;; *) ARCH=$ABI;; esac
SDK=$O/sdk-$VER
[ -d "$SDK" ] || { curl -sSfLo "$O/sdk.zip" "https://storage.googleapis.com/dart-archive/channels/stable/release/$VER/sdk/dartsdk-linux-x64-release.zip"; unzip -q "$O/sdk.zip" -d "$SDK"; }
D=$SDK/dart-sdk
"$D/bin/dartaotruntime" "$D/bin/snapshots/gen_kernel_aot.dart.snapshot" \
  --platform "$(ls "$D"/lib/_internal/vm_platform_product.dill "$D"/lib/_internal/vm_platform_strong.dill 2>/dev/null | head -1)" --aot --target-os android \
  -o "$O/probe.dill" "$HERE/bin/probe.dart"
GS=$(find "$K" -name 'gen_snapshot*' -type f | head -1); chmod +x "$GS"
"$GS" --snapshot-kind=app-aot-elf --elf="$O/probe.aot" "$O/probe.dill"
cp "$(find "$K" -name dartaotruntime -type f | head -1)" "$O/dartaotruntime"; chmod 755 "$O/dartaotruntime"
echo "kit $VER $ABI ($ARCH): $(du -b "$O/dartaotruntime" "$O/probe.aot" | tr '\n' ' ')"
readelf -lhd "$O/dartaotruntime" | grep -E 'NEEDED|interpreter|RUNPATH' || true
