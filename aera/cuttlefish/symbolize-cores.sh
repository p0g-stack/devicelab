#!/usr/bin/env bash
# Backtraces for recovery cores the checks pulled ($LAB_OUT/*/*core.*), using
# the image release's recovery-unstripped.elf; the cores themselves move out
# of $LAB_OUT (too big for lab-results).
# recovery is a PIE and the core's libraries are not on the runner, so gdb
# cannot relocate it by itself: the load base comes from the core's NT_FILE
# note (the mapping of /system/bin/recovery at file offset 0) and gdb loads
# the symbols at that base (symbol-file -o).
# Usage: symbolize-cores.sh RELEASE_TAG
set -uo pipefail
OUT=${LAB_OUT:?}; T=${RUNNER_TEMP:-/tmp}
ls "$OUT"/*/*core.* >/dev/null 2>&1 || exit 0
command -v gdb >/dev/null || sudo apt-get install -y -qq gdb >/dev/null 2>&1 || true
ELF=$T/recovery-unstripped.elf
[ -f "$ELF" ] || gh release download "$1" -R "${GITHUB_REPOSITORY:-p0g-stack/devicelab}" -p recovery-unstripped.elf -D "$T" --clobber || exit 0
for c in "$OUT"/*/*core.*; do
  {
    echo "== ${c##*/}"
    base=$(python3 "$(dirname "$0")/../tools/core_maps.py" "$c" /system/bin/recovery)
    python3 "$(dirname "$0")/../tools/core_maps.py" "$c" | grep -E "recovery|aera" | head -8
    echo "recovery load base: ${base:-unknown}"
    rip=$(gdb -batch -nx -ex 'p/x $rip' -c "$c" 2>/dev/null | sed -n 's/^\$1 = //p')
    echo "rip: $rip"
    if [ -n "$base" ] && [ -n "$rip" ]; then
      off=$(printf '0x%x' $(( rip - base )))
      echo "rip - base: $off"
      addr2line -f -C -i -e "$ELF" "$off"
      gdb -batch -nx -ex "symbol-file -o $base $ELF" -ex 'bt 30' -ex 'thread apply all bt 8' -c "$c" 2>&1 \
        | grep -vE "^warning: Can't open file|^$" | head -120
    fi
  } | tee -a "${c%/*}/backtrace.txt"
  mv "$c" "$T"/
done
exit 0
