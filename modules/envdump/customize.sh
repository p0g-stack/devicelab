# devicelab: record the environment the manager's installer gives customize.sh,
# then refuse to stay installed (nothing to mount or run).
{ echo "== env"; env | sort; echo "== ids"; id; cat /proc/self/attr/current; echo; echo "== paths"; ls -la /data/adb/metamodule /data/adb/ksud /data/adb/ksu/bin 2>&1; } >/data/local/tmp/customize-env.txt 2>&1
ui_print "- devicelab envdump: written /data/local/tmp/customize-env.txt"
