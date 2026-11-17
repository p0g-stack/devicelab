#!/usr/bin/env bash
# Keep the Actions listener outside the Android build's memory cgroup.
# Persist resource samples in a separate check: runner loss can discard all logs.
set -euo pipefail
src=${1:?source directory}; out=${2:?output directory}
mkdir -p "$out"
check=$(gh api "repos/$GITHUB_REPOSITORY/check-runs" -X POST \
  -f name='AERA build resources' -f head_sha="$GITHUB_SHA" -f status=in_progress \
  -f details_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" --jq .id)
summary=$out/resources-latest.txt
sample() {
  {
    date -u
    df -h "$src" /mnt
    free -m
    for f in memory.current memory.peak memory.swap.current memory.events memory.pressure; do
      path=/sys/fs/cgroup/system.slice/aera-build.service/$f
      if [ -r "$path" ]; then echo "== $f"; cat "$path"; fi
    done
    echo '== largest resident processes (KiB)'
    ps -eo pid,rss,comm --sort=-rss | head -12
    echo '== recent build output'
    tail -12 "$out/build.log" 2>/dev/null || true
  } > "$summary"
  cat "$summary" >> "$out/resources.log"
  gh api "repos/$GITHUB_REPOSITORY/check-runs/$check" -X PATCH \
    -f 'output[title]=Hosted build resource sample' \
    -f "output[summary]=$(printf '```text\n'; cat "$summary"; printf '\n```')" >/dev/null
}
monitor() { while :; do sample || true; sleep 60; done; }
monitor & monitor_pid=$!
finish() {
  rc=$?
  trap - EXIT
  kill "$monitor_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true
  sample || true
  result=failure; [ "$rc" = 0 ] && result=success
  gh api "repos/$GITHUB_REPOSITORY/check-runs/$check" -X PATCH \
    -f status=completed -f conclusion="$result" >/dev/null || true
  exit "$rc"
}
trap finish EXIT
# Four GiB stay available to the runner, monitoring, and the kernel. Soong
# clears its bootstrap process environment, so shell GOMEMLIMIT is ineffective
# there; the cgroup bounds that single large process independently of make -j.
sudo systemd-run --unit=aera-build --wait --pipe --collect \
  --uid="$(id -u)" --gid="$(id -g)" --working-directory="$GITHUB_WORKSPACE" \
  -p MemoryAccounting=yes -p MemoryHigh=10G -p MemoryMax=12G \
  -p MemorySwapMax=20G -p CPUWeight=50 \
  --setenv="HOME=$HOME" --setenv="PATH=$PATH" \
  --setenv=NO_APT=1 --setenv=JOBS=3 \
  --setenv="AERA_PATCHES=${AERA_PATCHES:-$GITHUB_WORKSPACE/aera/build/patches}" \
  /bin/bash "$GITHUB_WORKSPACE/aera/build/build.sh" "$src" "$out"
