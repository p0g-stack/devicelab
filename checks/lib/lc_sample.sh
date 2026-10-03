#!/system/bin/sh
# Device-side sampler for checks/lifecycle.sh: every ~1 s, the root channel,
# the demo's root process, established connections to the channel's loopback
# port, the app plane service/notification/hold socket and the app process.
# Prints a line (uptime first) only when something changed.
# Usage: lc_sample.sh <seconds> <module id> <app package>
SECS=$1; ID=$2; PKG=$3; SVC=$PKG/com.termux.api.RootHelperService
up() { cut -d' ' -f1 /proc/uptime; }
end=$(awk -v u="$(up)" -v s="$SECS" 'BEGIN { print u + s }')
last=""; port=""
while awk -v u="$(up)" -v e="$end" 'BEGIN { exit !(u < e) }'; do
  p=$(KSU_MODULE=$ID /data/adb/ksud module config get webui.session 2>/dev/null | sed -n 's/.*"port": *\([0-9]*\).*/\1/p')
  [ -n "$p" ] && port=$p
  ch=$(pgrep -f 'flutter_webui_root.aot serve' | tr '\n' ',')
  aot=$(pgrep -f 'demo.aot' | tr '\n' ',')
  conn=0
  if [ -n "$port" ]; then
    hp=$(printf '%04X' "$port")
    conn=$(cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk -v p=":$hp" '$4 == "01" && substr($2, length($2) - 4) == p' | wc -l)
  fi
  fgs=$(dumpsys activity services "$SVC" 2>/dev/null | grep -c 'ServiceRecord{')
  isfg=$(dumpsys activity services "$SVC" 2>/dev/null | grep -c 'isForeground=true')
  notif=$(dumpsys notification --noredact 2>/dev/null | grep -c "NotificationRecord.*pkg=$PKG")
  hold=$(grep -c "@$PKG/hold" /proc/net/unix)
  app=$(pidof "$PKG")
  s="ch=$ch aot=$aot port=$port conn=$conn fgs=$fgs fg=$isfg notif=$notif hold=$hold app=$app"
  [ "$s" != "$last" ] && { echo "$(up) $s"; last=$s; }
  sleep 1
done
echo "$(up) end $last"
