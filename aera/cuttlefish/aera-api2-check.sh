#!/usr/bin/env bash
# Host API 2 qualification of flutter-aera's API 2 probe (ci/apps/api2_probe)
# on a booted upstream AERA recovery (1cabc509 + rebased non-protocol series
# + API 2 extension bits 12/13), emulator 0.0.0.0:6520 only.
#
# The plugin goes into AERA's RAM plugin store exactly as InstallLocal()
# leaves it (payload size and SHA-256 checked against the manifest first),
# AERA is restarted so Home lists it, and it is opened by tapping its Home
# tile: upstream has no RPC "plugin open". All input is AERA Remote touch
# (RPC `mirror start`, its uinput device), so it passes AERA's own routing:
#   counter   two taps on the FAB; `api2: count: 1`, `api2: count: 2` and no
#             more; the guest rectangle of the captures before/after differs
#   text      tap the TextField; Flutter asks for AERA's desktop keyboard
#             (bit 12 SetDesktopKeyboard), `api2: inset: N>0`; API2_TEXT is
#             typed on that LVGL keyboard key by key and Done submits it:
#             `api2: submitted: TEXT`, then `api2: inset: 0`. Flutter does not
#             use the bit 13 native modal editor; it is not exercised here.
#   files     a fixture file in the picker's start folder (RPC status
#             "storage", else /); Pick opens upstream Files over the desktop
#             (bit 12); its row is tapped: `api2: picked: PATH`
#   back      Details, then the desktop toolbar's ESC: `api2: back returned`
# Captures are AERA's own /tmp/aeraui-capture frames (panel pixels), each
# with an upright *-view.png marking the taps made since the previous one.
# Plugin stdout/stderr is recovery's /tmp/recovery.log (upstream launcher).
#
# Every coordinate is computed by aera-api2-geom.py from the recovery source
# layout and the real panel/logical sizes and rotation of this boot; see its
# header for the spaces. Overrides when a capture shows a miss:
#   API2_HOME_TAP, API2_PICK_TAP   x,y in the -view.png pixels of the capture
#   API2_FAB API2_FIELD API2_PICK API2_DETAILS   x,y in the guest frame
#     (defaults from the host proof ci/api2-check.sh: 916,496 400,170 80,280 70,333)
#   API2_TEXT (default route42: keys every keyboard layout has in place)
#   API2_LOGICAL WxH, API2_ROTATION 0|90|270, API2_FRAME WxH,
#   API2_UI_SIZE small|normal|large|spacious, API2_KB_LAYOUT qwerty|qwertz|azerty,
#   API2_HOME_COLUMNS 2-5, API2_APP_WAIT seconds (default 120)
# Usage: CF_HOME=... LAB_OUT=... aera-api2-check.sh API2-PROBE.aerap
#   -> $LAB_OUT/api2/; exit 0 only when every check passed.
set -uo pipefail
PKG=${1:?usage: aera-api2-check.sh API2-PROBE.aerap}
OUT=${LAB_OUT:-$PWD/out}/api2; mkdir -p "$OUT"
CF_HOME=${CF_HOME:-$HOME/cf}
ADB=$CF_HOME/bin/adb; [ -x "$ADB" ] || ADB=adb
here=$(cd "$(dirname "$0")" && pwd)
GEOM=$OUT/geometry.json
NONCE=$(date +%s)-$$
TEXT=${API2_TEXT:-route42}
FIXTURE_NAME=0-api2-selected.txt
a() { $ADB -s 0.0.0.0:6520 "$@"; }
G() { python3 "$here/aera-api2-geom.py" "$@"; }
log() { echo "[api2] $*" | tee -a "$OUT/log.txt"; }
FAILED=()
fail() { log "FAIL: $*"; FAILED+=("$*"); }

collect() {
  a shell 'cat /tmp/recovery.log' 2>/dev/null | tr -d '\r' > "$OUT/recovery.log"
  awk -v m="lab-api2: start $NONCE" 'index($0, m) {on = 1} on' "$OUT/recovery.log" > "$OUT/run.log"
  grep -E 'api2: |aera-flutter|aera-plugin|flutter: |lab-api2: ' "$OUT/run.log" > "$OUT/plugin-stdout.log"
  a shell 'logcat -d 2>/dev/null' | tr -d '\r' > "$OUT/logcat.txt"
  a shell 'ps -A -o PID,PPID,ETIME,ARGS 2>/dev/null' | tr -d '\r' > "$OUT/ps.txt"
  a shell 'dmesg 2>/dev/null | tail -200' | tr -d '\r' > "$OUT/dmesg.txt"
  a shell 'ls -laR /tmp/aera/plugins; cat /tmp/aera-audio-rotation' > "$OUT/device-state.txt" 2>&1
  rm -rf "$OUT/.pkg" "$OUT/.req.json"
}
finish() {
  collect
  if [ ${#FAILED[@]} -eq 0 ]; then log "API 2 qualification passed"; exit 0; fi
  log "API 2 qualification FAILED (${#FAILED[@]}):"; printf '  - %s\n' "${FAILED[@]}" | tee -a "$OUT/log.txt"
  exit 1
}
die() { fail "$*"; finish; }

rpc() {
  printf '%s\n' "$1" > "$OUT/.req.json"; a push "$OUT/.req.json" /tmp/lab-req.json >/dev/null
  a shell '[ -p /system/bin/aerain ] && { timeout 60 cat /system/bin/aeraout & sleep 0.3; cat /tmp/lab-req.json > /system/bin/aerain; wait; }' 2>&1 | tr -d '\r'
}
mark() { a shell "echo 'lab-api2: $*' >> /tmp/recovery.log" >/dev/null 2>&1; }
# The probe's output since this run's start marker, read on the device.
since() { a shell "sed -n '/lab-api2: start $NONCE/,\$p' /tmp/recovery.log" 2>/dev/null | tr -d '\r'; }
wait_for() {  # wait_for SECONDS ERE
  local i
  for ((i = 0; i < $1; i += 2)); do since | grep -qE "$2" && return 0; sleep 2; done
  return 1
}

post() { curl -s -o /dev/null -w '%{http_code}' -m 5 -X POST -H 'Content-Type: application/json' -H "x-aera-code: $RCODE" -d "$2" "$REMOTE$1"; }
TAPS=()
tap() {  # tap NAME PANEL_X PANEL_Y VIEW_X VIEW_Y
  local down up
  mark "tap $1 panel $2,$3 view $4,$5"
  down=$(post /api/input/touch "{\"action\":\"down\",\"x\":$2,\"y\":$3}"); sleep 0.08
  up=$(post /api/input/touch "{\"action\":\"up\",\"x\":$2,\"y\":$3}")
  printf '%s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$5" >> "$OUT/taps.txt"
  TAPS+=("$4,$5"); log "tap $1 at panel $2,$3 (view $4,$5)"
  [ "$down" = 204 ] && [ "$up" = 204 ] || fail "tap $1: AERA Remote answered $down/$up"
}
at() {  # at NAME GEOM-TAP-ARGS...: computed tap
  local name=$1 r; shift
  r=$(G tap "$GEOM" "$@" 2>>"$OUT/log.txt") || { fail "$name: no coordinates for '$*' (log.txt)"; return 1; }
  # shellcheck disable=SC2086
  tap "$name" $r
}
xy() { echo "${1%,*} ${1#*,}"; }  # "x,y" -> "x y"

SHOTN=0 LAST=
shot() {  # shot NAME -> $OUT/NN-NAME.png and NN-NAME-view.png
  local f; SHOTN=$((SHOTN + 1)); f=$(printf '%02d-%s' "$SHOTN" "$1")
  mark "shot $f"
  a shell 'rm -f /tmp/aeraui.png; touch /tmp/aeraui-capture'
  for _ in $(seq 20); do a shell '[ -s /tmp/aeraui.png ] && [ ! -e /tmp/aeraui-capture ]' && break; sleep 0.5; done
  sleep 0.5
  if a pull /tmp/aeraui.png "$OUT/$f.png" >/dev/null 2>&1; then
    LAST=$OUT/$f.png; log "frame $f.png"
    [ -f "$GEOM" ] && { G view "$GEOM" "$LAST" "$OUT/$f-view.png" "${TAPS[@]}" 2>>"$OUT/log.txt" || log "no view for $f"; }
  else
    LAST=; fail "no frame for $1"
  fi
  TAPS=()
}
# seg NAME: the run log between `phase NAME` and the next phase marker.
seg() { awk -v p="lab-api2: phase $1" 'index($0, "lab-api2: phase ") {on = (substr($0, length($0) - length(p) + 1) == p); next} on' "$OUT/run.log"; }
# has TEXT MARKER: a line that is "api2: MARKER" exactly, after an optional log prefix.
has() { awk -v m="api2: $2" '$0 == m || substr($0, length($0) - length(m)) == " " m {f = 1} END {exit !f}' <<< "$1"; }

# ---- preconditions -------------------------------------------------------
: > "$OUT/log.txt"; : > "$OUT/taps.txt"
for t in curl unzip python3; do command -v $t >/dev/null || { log "$t is required"; exit 2; }; done
python3 -c 'import PIL' 2>/dev/null || pip3 install -q pillow >/dev/null 2>&1 || python3 -m pip install -q --break-system-packages pillow >/dev/null 2>&1
python3 -c 'import PIL' 2>/dev/null || { log "python3 pillow is required for captures and the counter comparison"; exit 2; }
[ "$(a get-state 2>/dev/null)" = recovery ] || { log "0.0.0.0:6520 is not in recovery"; exit 2; }
[ "$(a shell id -u | tr -d '\r')" = 0 ] || { log "recovery adb is not root"; exit 2; }

# ---- package and install -------------------------------------------------
rm -rf "$OUT/.pkg"; mkdir -p "$OUT/.pkg"
unzip -q -o "$PKG" -d "$OUT/.pkg" || die "cannot unzip $PKG"
# The checks AERA's ParsePlugin()/InstallLocal() make for a generic plugin.
id=$(python3 - "$OUT/.pkg" <<'PY' 2> "$OUT/package.txt"
import hashlib, json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "plugin.json")))
need = {"schema": 1, "type": "ui-runtime", "entry": "main", "protocol_version": 2,
        "min_host_api": 2, "executable": "usr/bin/aera-plugin", "payload": "runtime.xz"}
bad = [f"{k}={m.get(k)!r} (want {v!r})" for k, v in need.items() if m.get(k) != v]
perms = m.get("permissions", [])
bad += [f"permission {p} missing" for p in ("display", "touch-input", "desktop-surface") if p not in perms]
payload = os.path.join(d, "runtime.xz")
data = open(payload, "rb").read() if os.path.isfile(payload) else b""
if len(data) != m.get("payload_size"):
    bad.append(f"runtime.xz is {len(data)} bytes, manifest says {m.get('payload_size')}")
if hashlib.sha256(data).hexdigest() != m.get("payload_sha256"):
    bad.append("runtime.xz SHA-256 differs from payload_sha256")
for k in ("expanded_size", "expanded_sha256", "member_count"):
    if not m.get(k):
        bad.append(f"{k} missing")
sys.stderr.write(json.dumps(m, indent=1, sort_keys=True) + "\n")
if bad:
    sys.stderr.write("\n".join(bad) + "\n")
    sys.exit(1)
print(m["id"])
PY
) || die "$PKG is not an installable Host API 2 plugin: $(tail -3 "$OUT/package.txt" | tr '\n' ' ')"
log "package $id: $(stat -c %s "$OUT/.pkg/runtime.xz") byte payload, manifest checked"
sig=; [ -f "$OUT/.pkg/plugin.json.sig" ] && sig=$OUT/.pkg/plugin.json.sig
store=/tmp/aera/plugins stage=/tmp/aera/plugins/.install-$id-lab
a shell "mkdir -p $store && chmod 700 /tmp/aera $store && rm -rf $store/$id $stage && mkdir -m 700 $stage" || die "cannot prepare $store"
a push "$OUT/.pkg/plugin.json" "$OUT/.pkg/runtime.xz" $sig "$stage/" >/dev/null || die "push to $stage failed"
a shell "chmod 444 $stage/* && mv $stage $store/$id" || die "cannot publish $store/$id"
log "installed $id into the RAM store ($store/$id$([ -n "$sig" ] && echo ', signed' || echo ', unsigned: Unofficial'))"
others=$(a shell "ls -1 $store /sdcard/AERA/plugins 2>/dev/null" | tr -d '\r' | grep -E '^[a-z0-9][a-z0-9.-]*$' | grep -vxF "$id" | sort -u | tr '\n' ' ')
if [ -n "$others" ] && [ -z "${API2_HOME_TAP:-}" ]; then
  die "other installed plugins ($others) may hold Home's first tile; give API2_HOME_TAP from a Home capture"
fi

# ---- fresh AERA, so Home lists the plugin --------------------------------
a shell 'for p in /proc/[0-9]*; do grep -qa "/tmp/aera-p2-" $p/cmdline 2>/dev/null && kill -9 ${p#/proc/}; done' >/dev/null 2>&1
r0=$(a shell pidof recovery | tr -d '\r'); a shell 'setprop ctl.restart recovery'; sleep 5
for _ in $(seq 40); do rpc '{"v":1,"id":"api2-up","op":"status"}' > "$OUT/status.txt"; grep -q '"storage"' "$OUT/status.txt" && break; sleep 2; done
grep -q '"storage"' "$OUT/status.txt" || die "AERA RPC did not answer after the restart (status.txt)"
log "AERA restarted: recovery pid $r0 -> $(a shell pidof recovery | tr -d '\r')"
a shell "echo 'lab-api2: start $NONCE' >> /tmp/recovery.log"
r=$(rpc '{"v":1,"id":"api2-mirror","op":"mirror","args":{"action":"start","port":8088}}'); echo "$r" > "$OUT/mirror.txt"
RCODE=$(sed -n 's/.*"access_code":"\([0-9]*\)".*/\1/p' <<< "$r" | head -1)
[ -n "$RCODE" ] || die "AERA Remote did not start (mirror.txt)"
a forward tcp:18088 tcp:8088 >/dev/null || die "adb forward failed"
REMOTE=http://127.0.0.1:18088
sleep "${API2_HOME_WAIT:-12}"   # boot scene to Home; minuitwrp adopts Remote's device within 2 s
remote_size=$(curl -s -m 5 -H "x-aera-code: $RCODE" "$REMOTE/api/status")
shot home
[ -n "$LAST" ] || die "no capture of Home"

# ---- geometry from this boot ---------------------------------------------
logical=${API2_LOGICAL:-$(a shell 'logcat -d 2>/dev/null' | tr -d '\r' | grep -o 'engine initialized at logical [0-9]*x[0-9]*' | tail -1 | grep -o '[0-9]*x[0-9]*$')}
G init "$GEOM" "$LAST" "$logical" || die "geometry init failed"
G set "$GEOM" "frame_w=$(echo "${API2_FRAME:-960x540}" | cut -dx -f1)" "frame_h=$(echo "${API2_FRAME:-960x540}" | cut -dx -f2)" \
  "ui_size=${API2_UI_SIZE:-normal}" "kb_layout=${API2_KB_LAYOUT:-qwerty}" "home_columns=${API2_HOME_COLUMNS:-3}" "rotation=0"
src=${API2_LOGICAL:+API2_LOGICAL}; [ -n "$src" ] || src=${logical:+AERA logcat}
log "geometry: $(tr -d '\n ' < "$GEOM") (logical size from ${src:-the adaptive default})"
log "Remote /api/status: $remote_size"
python3 - "$GEOM" "$remote_size" <<'PY' || fail "Remote's framebuffer size is not the capture's: touch and capture spaces differ"
import json, sys
g, s = json.load(open(sys.argv[1])), json.loads(sys.argv[2] or "{}")
sys.exit(0 if (s.get("width"), s.get("height")) == (g["pw"], g["ph"]) else 1)
PY
# A fresh AERA starts Home in portrait; the file may be stale from before the restart.
log "Home: /tmp/aera-audio-rotation '$(a shell 'cat /tmp/aera-audio-rotation 2>/dev/null' | tr -d '\r\n')', tapping Home as portrait"

# ---- open from Home --------------------------------------------------------
if [ -n "${API2_HOME_TAP:-}" ]; then at home-tile view $(xy "$API2_HOME_TAP"); else at home-tile home; fi
wait_for "${API2_APP_WAIT:-120}" 'api2: inset: ' || { shot not-open; die "the probe printed nothing in ${API2_APP_WAIT:-120} s (no api2: inset line)"; }
sleep 3
rot=${API2_ROTATION:-$(a shell 'cat /tmp/aera-audio-rotation 2>/dev/null' | tr -d '\r\n')}
case "$rot" in 0|90|270) ;; *) die "desktop rotation unknown (/tmp/aera-audio-rotation '$rot'); give API2_ROTATION" ;; esac
G set "$GEOM" "rotation=$rot"
log "desktop open, rotation $rot ($( [ "$rot" = 90 ] && echo software || { [ "$rot" = 270 ] && echo GPU; } ) landscape); $(G desktop "$GEOM")"
shot opened
G detect "$GEOM" "$LAST" 2>&1 | sed 's/^/[api2] /' | tee -a "$OUT/log.txt"
a shell 'ps -A -o PID,ARGS 2>/dev/null | grep "aera-p2-" | grep -v grep' | tr -d '\r' | sed 's/^/[api2] process: /' | tee -a "$OUT/log.txt"

# ---- counter -------------------------------------------------------------
mark "phase counter"
fab=${API2_FAB:-916,496}; read -r fx fy <<< "$(xy "$fab")"
shot counter-before; before=$LAST
at fab-1 guest "$fx" "$fy"; sleep 1.2
at fab-2 guest $((fx + 2)) $((fy + 2)); sleep 2   # 2 px apart: a fresh ABS value
shot counter-after; after=$LAST
if [ -n "$before" ] && [ -n "$after" ]; then
  d=$(G differ "$GEOM" "$before" "$after" 2>&1); rc=$?
  log "counter captures: $d"
  [ $rc = 0 ] || fail "counter captures before/after are equal in the guest rectangle"
fi

# ---- text through AERA's desktop keyboard (bit 12) -----------------------
mark "phase text"
at field guest $(xy "${API2_FIELD:-400,170}")
if wait_for 10 '(^|[[:space:]])api2: inset: [1-9][0-9]*$'; then
  shot keyboard
  ok=1
  for ((i = 0; i < ${#TEXT}; i++)); do
    at "key-${TEXT:i:1}" key "${TEXT:i:1}" || { ok=; break; }; sleep 0.4
  done
  shot typed
  [ -n "$ok" ] && at key-done key OK
  sleep 2
else
  fail "no keyboard: no positive api2: inset after tapping the field"
fi
shot submitted

# ---- Files selection over the desktop (bit 12) ---------------------------
mark "phase files"
storage=$(sed -n 's/.*"storage":"\([^"]*\)".*/\1/p' "$OUT/status.txt" | head -1)
dir=/
if [ -n "$storage" ]; then
  if ! a shell "[ -d '$storage' ]"; then
    a shell "mkdir -p '$storage'" && log "created the missing storage folder $storage (emulator ramdisk)"
  fi
  a shell "[ -d '$storage' ]" && dir=$storage
fi
fixture=${dir%/}/$FIXTURE_NAME
a shell "printf 'API 2 selected file fixture\n' > '$fixture'" || fail "cannot write $fixture"
# Populate(): folders first, then names, case-insensitive; no hidden names;
# "Parent folder" first below /. Symlinks list as files.
a shell "ls -1AF '$dir'" | tr -d '\r' > "$OUT/picker-folder.txt"
row=$(python3 - "$OUT/picker-folder.txt" "$dir" "$FIXTURE_NAME" <<'PY'
import sys
lines, d, want = open(sys.argv[1]).read().splitlines(), sys.argv[2], sys.argv[3]
entries = []
for line in lines:
    kind = line[-1] if line and line[-1] in "/@*|=" else ""
    name = line[:-1] if kind else line
    if not name or name.startswith(".") or kind in "|=" and kind:
        continue
    entries.append((kind != "/", name.lower().encode(), name))
entries.sort()
names = [e[2] for e in entries]
print((d != "/") + names.index(want))
PY
) || fail "fixture $FIXTURE_NAME not listed in $dir"
log "picker start folder $dir ($(wc -l < "$OUT/picker-folder.txt") entries); fixture row ${row:-?}"
at pick guest $(xy "${API2_PICK:-80,280}")
sleep 4; shot picker
if [ -n "${API2_PICK_TAP:-}" ]; then at fixture-row view $(xy "$API2_PICK_TAP")
elif [ -n "${row:-}" ]; then at fixture-row pick-row "$row"
fi
wait_for 10 "api2: picked: " || fail "Files returned nothing to the probe"
sleep 1; shot picked

# ---- route and Back (desktop ESC) ----------------------------------------
mark "phase back"
at details guest $(xy "${API2_DETAILS:-70,333}"); sleep 2
shot details
at esc toolbar esc
wait_for 10 'api2: back returned' || fail "no api2: back returned after ESC"
sleep 1; shot returned
mark "phase end"

# ---- assertions on the probe's own output --------------------------------
collect
counter=$(seg counter | grep -oE 'api2: count: [0-9]+$')
[ "$counter" = $'api2: count: 1\napi2: count: 2' ] || fail "counter printed '$(tr '\n' ';' <<< "$counter")', want count: 1 then count: 2"
text=$(seg text)
insets=$(grep -oE 'api2: inset: [0-9]+$' <<< "$text" | awk '{print $3}' | tr '\n' ' ')
log "insets during text: $insets"
has "$text" "submitted: $TEXT" || fail "no 'api2: submitted: $TEXT' (got: $(grep -oE 'api2: submitted: .*' <<< "$text" | tr '\n' ';'))"
awk '/api2: inset: [1-9][0-9]*$/ {pos = 1} pos && /api2: inset: 0$/ {z = 1} END {exit !z}' <<< "$text" ||
  fail "inset did not go positive and back to 0 during text"
has "$(seg files)" "picked: $fixture" || fail "no 'api2: picked: $fixture' (got: $(seg files | grep -oE 'api2: pick.*' | tr '\n' ';'))"
has "$(seg back)" "back returned" || fail "no 'api2: back returned'"
grep -E 'api2: |lab-api2: phase' "$OUT/run.log" > "$OUT/probe-markers.log"
finish
