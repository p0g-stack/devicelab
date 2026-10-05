# Left-edge back swipe through the touchscreen's evdev node (sendevent in one
# adb shell; `input motionevent` steps did not start the system back gesture,
# run 37267772813). swipe_setup sets TOUCH, MX, MY (device range), W, H (screen).
# edge_swipe <outprefix> <tag> <commit|cancel> [hold seconds at the far point]:
# finger down at the edge, 12 moves to 45% of the width, screencap, hold,
# screencap, (cancel: 6 moves back to the edge), lift, screencap.
swipe_setup() {
  TOUCH=$(adb shell getevent -pl 2>/dev/null | tr -d '\r' | awk '/^add device/ {d=$4} /ABS_MT_POSITION_X/ {print d; exit}')
  read -r MX MY < <(adb shell getevent -pl "$TOUCH" 2>/dev/null | tr -d '\r' | awk '/ABS_MT_POSITION_X/ {for (i=1;i<=NF;i++) if ($i=="max") x=$(i+1)} /ABS_MT_POSITION_Y/ {for (i=1;i<=NF;i++) if ($i=="max") y=$(i+1)} END {gsub(",","",x); gsub(",","",y); print x, y}')
  read -r W H < <(adb shell wm size | tr -d '\r' | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)
}
edge_swipe() {
  local out=$1 tag=$2 mode=$3 hold=${4:-0} i px s E="sendevent $TOUCH" sy=$(( H / 2 * MY / H ))
  _sx() { echo $(( $1 * MX / W )); }
  s="$E 3 57 7; $E 3 53 $(_sx 1); $E 3 54 $sy; $E 3 58 50; $E 1 330 1; $E 0 0 0; sleep 0.03;"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do px=$((1 + (W * 45 / 100 - 1) * i / 12)); s+=" $E 3 53 $(_sx $px); $E 0 0 0; sleep 0.03;"; [ $i = 6 ] && s+=" screencap -p /sdcard/sw-$tag-1.png;"; done
  s+=" screencap -p /sdcard/sw-$tag-2.png;"
  [ "$hold" != 0 ] && s+=" sleep $hold;"
  if [ "$mode" = cancel ]; then for i in 10 8 6 4 2 0; do px=$((1 + (W * 45 / 100 - 1) * i / 12)); s+=" $E 3 53 $(_sx $px); $E 0 0 0; sleep 0.03;"; done; fi
  s+=" $E 3 57 4294967295; $E 1 330 0; $E 0 0 0; sleep 0.5; screencap -p /sdcard/sw-$tag-3.png"
  adb shell "$s" 2>&1 | tr -d '\r' | tail -3
  for i in 1 2 3; do adb pull "/sdcard/sw-$tag-$i.png" "$out-$tag-$i.png" >/dev/null 2>&1; done
  adb shell "rm -f /sdcard/sw-$tag-*.png"
}
