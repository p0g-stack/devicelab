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
# Without one (Cuttlefish's aosp_cf_x86_64_only_phone, Android 17), the
# recovery root lives in the single platform fragment next to
# first_stage_ramdisk/ and the modules: AERA is overlaid onto that fragment.
overlay=""
if [ -z "$rec" ]; then
  for ((j=0; j<${#A[@]}; j++)); do [ "${A[$j]}" = --vendor_ramdisk_fragment ] && { rec=${A[$((j+1))]}; break; }; done
  [ -n "$rec" ] || { log "no vendor ramdisk fragment; layout in $OUT/vendor_boot-layout.txt"; exit 1; }
  overlay=1
  log "no RECOVERY fragment: overlaying AERA onto the platform fragment $rec"
else
  log "stock recovery fragment: $rec"
fi

# 3. AERA ramdisk + Cuttlefish's init.recovery.cutf_cvm.rc -> new fragment.
dec() { case "$(file -b "$1")" in *LZ4*) lz4 -dc "$1";; *gzip*) gzip -dc "$1";; *) cat "$1";; esac; }
mkdir -p "$w/stock" "$w/aera"
(cd "$w/stock" && dec "$rec" | cpio -idm --quiet 2>/dev/null) || true
(cd "$w/aera" && dec "$AERA_RD" | cpio -idm --quiet 2>/dev/null)
(cd "$w/stock" && find . | sort) > "$OUT/stock-fragment-files.txt"
(cd "$w/aera" && find . | sort) > "$OUT/aera-ramdisk-files.txt"
log "stock fragment $(wc -l < "$OUT/stock-fragment-files.txt") entries, AERA ramdisk $(wc -l < "$OUT/aera-ramdisk-files.txt")"
if [ -n "$overlay" ]; then
  # AERA's tree, plus only what Cuttlefish's kernel and init need from the
  # stock fragment: the first-stage ramdisk, the kernel modules and the
  # root-level cutf files AERA lacks (init.recovery.cutf_cvm.rc, ueventd,
  # fstab). Stock /system and /vendor stay out: Android 17 binaries next to
  # AERA's Android 16 libraries crash, and a stock VINTF entry for a health
  # service that cannot start makes AERA wait for it forever.
  mkdir -p "$w/new"; cp -a "$w/aera/." "$w/new/"
  for d in first_stage_ramdisk lib/modules; do
    [ -e "$w/stock/$d" ] && { rm -rf "$w/new/$d"; mkdir -p "$(dirname "$w/new/$d")"; cp -a "$w/stock/$d" "$w/new/$d"; log "kept stock $d"; }
  done
  for f in "$w"/stock/*; do
    [ -f "$f" ] && [ ! -L "$f" ] && [ ! -e "$w/new/$(basename "$f")" ] && cp -a "$f" "$w/new/" && log "carried $(basename "$f")"
  done
  src=$w/new
else
  for f in "$w"/stock/*.rc; do [ -f "$f" ] && [ ! -e "$w/aera/$(basename "$f")" ] && cp -a "$f" "$w/aera/" && log "carried $(basename "$f")"; done
  src=$w/aera
fi
(cd "$src" && find . | sort | cpio -o -H newc --quiet --owner=0:0 | lz4 -l -12 --favor-decSpeed > "$w/aera-recovery.lz4")
cp "$w/aera-recovery.lz4" "$rec"

# 4. Repack with the same arguments.
"$OTA/mkbootimg" "${A[@]}" --vendor_boot "$w/vendor_boot-aera.img"
cp "$w/vendor_boot-aera.img" "$CF_HOME/vendor_boot-aera.img"
log "vendor_boot-aera.img: $(stat -c %s "$CF_HOME/vendor_boot-aera.img") bytes"

# 5. Relaunch with it and go to recovery.
asme cvd reset -y >/dev/null 2>&1 || asme "$CF_HOME/bin/stop_cvd" >/dev/null 2>&1 || true
GPU=$(cat "$OUT/cf-gpu-mode.txt" 2>/dev/null || echo guest_swiftshader)
# launch_cvd reads vendor_boot.img from the fetch directory (and repacks it
# with its own bootconfig), so the AERA image takes that name; the stock
# one is kept as vendor_boot.stock.img.
[ -f "$CF_HOME/vendor_boot.stock.img" ] || cp "$CF_HOME/vendor_boot.img" "$CF_HOME/vendor_boot.stock.img"
cp "$CF_HOME/vendor_boot-aera.img" "$CF_HOME/vendor_boot.img"
asme "$CF_HOME/bin/launch_cvd" --daemon --report_anonymous_usage_stats=n --cpus "${CF_CPUS:-2}" \
  --memory_mb "${CF_MEM:-4096}" --gpu_mode="$GPU" ${CF_EXTRA---enable_sandbox=false} \
  >"$OUT/launch_cvd-aera.log" 2>&1 \
  || { tail -30 "$OUT/launch_cvd-aera.log"; exit 1; }
$ADB connect $S >/dev/null 2>&1 || true
timeout 600 $ADB -s $S wait-for-device
t0=$SECONDS
until [ "$($ADB -s $S shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
  (( SECONDS - t0 > 900 )) && { log "Android did not boot with the AERA vendor_boot"; tail -60 "$CF_HOME"/cuttlefish_runtime/kernel.log; exit 1; }
  sleep 3
done
$ADB -s $S root >/dev/null 2>&1; sleep 3; $ADB connect $S >/dev/null 2>&1
# Android's own libraries, for aera-fixlibs.sh to stand in for ones the
# AERA ramdisk lacks (recorded as AERA deficiencies).
[ -d "$CF_HOME/android-lib64" ] || { mkdir -p "$CF_HOME/android-lib64"; $ADB -s $S pull /system/lib64/. "$CF_HOME/android-lib64/" >/dev/null 2>&1 || true; }
log "Android up ($(ls "$CF_HOME/android-lib64" | wc -l) system libs saved); rebooting into AERA"
