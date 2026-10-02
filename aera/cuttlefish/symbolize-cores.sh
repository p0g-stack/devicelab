#!/usr/bin/env bash
# Backtraces for recovery cores the checks pulled ($LAB_OUT/*/*core.*), using
# the image release's recovery-unstripped.elf; the cores themselves move out
# of $LAB_OUT (too big for lab-results).
# Usage: symbolize-cores.sh RELEASE_TAG
set -uo pipefail
OUT=${LAB_OUT:?}; T=${RUNNER_TEMP:-/tmp}
ls "$OUT"/*/*core.* >/dev/null 2>&1 || exit 0
command -v gdb >/dev/null || sudo apt-get install -y -qq gdb >/dev/null 2>&1 || true
[ -f "$T/recovery-unstripped.elf" ] || gh release download "$1" -R "${GITHUB_REPOSITORY:-p0g-stack/devicelab}" -p recovery-unstripped.elf -D "$T" --clobber || exit 0
for c in "$OUT"/*/*core.*; do
  { echo "== $c"; gdb -batch -nx -ex 'info registers rip' -ex 'bt 30' -ex 'info sharedlibrary' "$T/recovery-unstripped.elf" "$c" 2>&1 | tail -70; } \
    | tee -a "${c%/*}/backtrace.txt"
  mv "$c" "$T"/
done
exit 0
