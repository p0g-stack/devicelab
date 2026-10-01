#!/usr/bin/env bash
# Re-pin every AERA-remote project of android_manifest@MANIFEST_REV to its
# current aera-16.0 head. Writes pins.xml next to this script.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); rev=${1:-aera-16.0}
m=$(mktemp -d); git clone -q https://github.com/AERA-Recovery/android_manifest "$m"; git -C "$m" checkout -q "$rev"
mrev=$(git -C "$m" rev-parse HEAD)
{ echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo "<!-- AERA pin taken $(date -u +%F) from aera-16.0 heads; android_manifest $mrev -->"
  echo '<manifest>'
  python3 - "$m" <<'PY' | while read -r path name; do
import re, sys
for f in ('aera.xml', 'twrp-default.xml'):
    for t in re.findall(r'<project\b[^>]*>', open(f"{sys.argv[1]}/{f}").read()):
        if 'remote="AERA"' in t:
            print(re.search(r'path="([^"]+)"', t)[1], re.search(r'name="([^"]+)"', t)[1])
PY
    sha=$(git ls-remote "https://github.com/AERA-Recovery/$name" refs/heads/aera-16.0 | cut -f1)
    echo "  <extend-project name=\"$name\" path=\"$path\" revision=\"$sha\" />"
  done
  echo '</manifest>'; } > "$here/pins.xml"
echo "pinned to android_manifest $mrev"
