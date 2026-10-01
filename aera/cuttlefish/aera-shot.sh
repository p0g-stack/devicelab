#!/usr/bin/env bash
# One frame of AERA's screen via its /tmp/aeraui-capture request.
# Usage: aera-shot.sh NAME  ->  $LAB_OUT/NAME.png
OUT=${LAB_OUT:-$PWD/out}; CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
a() { $ADB -s 0.0.0.0:6520 "$@"; }
a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
a pull /tmp/aeraui.png "$OUT/$1.png" >/dev/null 2>&1 && echo "[aera] frame $1.png" || echo "[aera] no frame for $1"
exit 0
