#!/usr/bin/env bash
# What the guest's virtio-gpu offers (3D or not, which capsets), from the
# guest kernel and DRM. Usage: gpu-facts.sh LABEL  ->  $LAB_OUT/gpu-LABEL.txt
OUT=${LAB_OUT:-$PWD/out}; ADB=${ADB:-adb -s 0.0.0.0:6520}
{
  echo "# gpu_mode $(cat "$OUT/cf-gpu-mode.txt" 2>/dev/null)"
  for c in 'ls -l /dev/dri' 'dmesg | grep -iE "virtio.?gpu|virgl|drm|capset" | head -40' \
           'cat /sys/kernel/debug/dri/*/virtio-gpu-features 2>&1' \
           'cat /sys/kernel/debug/dri/*/name 2>&1' \
           'getprop | grep -E "egl|vulkan|gfxstream|graphics|gralloc|hwui" | head -30'; do
    echo "## $c"; $ADB shell "$c" 2>&1
  done
} > "$OUT/gpu-$1.txt"
cat "$OUT/gpu-$1.txt"
exit 0
