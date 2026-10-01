#!/usr/bin/env bash
# Commit a job's $LAB_OUT to the lab-results branch, so agents without
# artifact access (blob storage is not reachable from their sessions) can
# read results with git. Usage: publish.sh <label>. Needs GH_TOKEN with
# contents: write.
set -u
LABEL=$1; SRC=${LAB_OUT:?}
DEST=runs/$(date -u +%Y%m%dT%H%M%SZ)-$LABEL-$GITHUB_RUN_ID
R=$(mktemp -d); cd "$R" || exit 1
git init -q; git config user.name devicelab; git config user.email devicelab@users.noreply.github.com
git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/$GITHUB_REPOSITORY"
for i in 1 2 3 4 5; do
  if git fetch -q --depth 1 origin lab-results 2>/dev/null; then git checkout -q -B lab-results FETCH_HEAD
  else git checkout -q --orphan lab-results; git rm -rq --cached . 2>/dev/null || true; fi
  mkdir -p "$DEST"
  (cd "$SRC" && find . -type f -size -20M ! -name labserver ! -name '*.apk' -print0 | cpio -0pdm --quiet "$R/$DEST")
  git add "$DEST"; git commit -qm "$LABEL run $GITHUB_RUN_ID ($GITHUB_SHA)" || exit 0
  git push -q origin lab-results && { echo "published $DEST"; exit 0; }
  sleep $((i * 3))
done
echo "publish failed"
