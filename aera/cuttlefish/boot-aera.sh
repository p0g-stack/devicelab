#!/usr/bin/env bash
# Put AERA's recovery ramdisk where Cuttlefish's bootloader takes the
# recovery ramdisk from (the "recovery" fragment of vendor_boot), keeping
# Cuttlefish's own kernel and vendor ramdisk (virtio modules, first-stage
# fstab), then relaunch and boot into recovery.
#   boot-aera.sh RAMDISK_RECOVERY_IMG      (after up.sh; Cuttlefish running)
# AERA's ramdisk has no Cuttlefish init bits, so the stock fragment's
# init.recovery.cutf_cvm.rc (adbd on vsock etc.) is carried over.
set -euo pipefail
AERA_RD=$(realpath "${1:?usage: boot-aera.sh ramdisk-recovery.img}")
OUT=${LAB_OUT:-$PWD/out}; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
S=0.0.0.0:6520
log() { echo "[aera-boot] $*"; }
OTA=$CF_HOME/otatools/bin; [ -x "$OTA/unpack_bootimg" ] || OTA=$CF_HOME/bin
w=$(mktemp -d)
asme() { sudo -u "$USER" -H env HOME="$CF_HOME" PATH="$PATH" EGL_PLATFORM=surfaceless "$@"; }

# 1. Stock vendor_boot apart.
"$OTA/unpack_bootimg" --boot_img "$CF_HOME/vendor_boot.img" --out "$w/vb" --format=mkbootimg -0 > "$w/args0"
"$OTA/unpack_bootimg" --boot_img "$CF_HOME/vendor_boot.img" --out "$w/vb" > "$OUT/vendor_boot-layout.txt"
tr '\0' '\n' < "$w/args0" > "$w/args"; cat "$w/args" | tr '\n' ' ' >> "$OUT/vendor_boot-layout.txt"
grep -n -i "ramdisk\|name\|type" "$OUT/vendor_boot-layout.txt" | head -30

# 2. Which fragment is recovery: the --ramdisk_type RECOVERY entry.
mapfile -t A < "$w/args"
rec=""; for i in "${!A[@]}"; do
  if [ "${A[$i]}" = --ramdisk_type ] && [ "${A[$((i+1))]}" = RECOVERY ]; then
    for ((j=i; j<${#A[@]}; j++)); do [ "${A[$j]}" = --vendor_ramdisk_fragment ] && { rec=${A[$((j+1))]}; break; }; done
  fi
done
[ -n "$rec" ] || { log "no RECOVERY fragment in vendor_boot; layout in $OUT/vendor_boot-layout.txt"; exit 1; }
log "stock recovery fragment: $rec"

# 3. AERA ramdisk + Cuttlefish's init.recovery.cutf_cvm.rc -> new fragment.
dec() { case "$(file -b "$1")" in *LZ4*) lz4 -dc "$1";; *gzip*) gzip -dc "$1";; *) cat "$1";; esac; }
mkdir -p "$w/stock" "$w/aera"
(cd "$w/stock" && dec "$rec" | cpio -idm --quiet 2>/dev/null) || true
(cd "$w/aera" && dec "$AERA_RD" | cpio -idm --quiet 2>/dev/null)
ls "$w/stock" > "$OUT/stock-recovery-fragment.txt"
for f in "$w"/stock/*.rc; do [ -f "$f" ] && [ ! -e "$w/aera/$(basename "$f")" ] && cp -a "$f" "$w/aera/" && log "carried $(basename "$f")"; done
(cd "$w/aera" && find . | sort | cpio -o -H newc --quiet --owner=0:0 | lz4 -l -12 --favor-decSpeed > "$w/aera-recovery.lz4")
cp "$w/aera-recovery.lz4" "$rec"

# 4. Repack with the same arguments.
"$OTA/mkbootimg" "${A[@]}" --vendor_boot "$w/vendor_boot-aera.img"
cp "$w/vendor_boot-aera.img" "$CF_HOME/vendor_boot-aera.img"
log "vendor_boot-aera.img: $(stat -c %s "$CF_HOME/vendor_boot-aera.img") bytes"

# 5. Relaunch with it and go to recovery.
asme cvd reset -y >/dev/null 2>&1 || asme "$CF_HOME/bin/stop_cvd" >/dev/null 2>&1 || true
GPU=$(cat "$OUT/cf-gpu-mode.txt" 2>/dev/null || echo guest_swiftshader)
asme "$CF_HOME/bin/launch_cvd" --daemon --report_anonymous_usage_stats=n --cpus "${CF_CPUS:-2}" \
  --memory_mb "${CF_MEM:-4096}" --gpu_mode="$GPU" ${CF_EXTRA---enable_sandbox=false} \
  --vendor_boot_image="$CF_HOME/vendor_boot-aera.img" >"$OUT/launch_cvd-aera.log" 2>&1 \
  || { tail -30 "$OUT/launch_cvd-aera.log"; exit 1; }
$ADB connect $S >/dev/null 2>&1 || true
timeout 600 $ADB -s $S wait-for-device
until [ "$($ADB -s $S shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 3; done
$ADB -s $S root >/dev/null 2>&1; sleep 3; $ADB connect $S >/dev/null 2>&1
log "Android up; rebooting into AERA"
