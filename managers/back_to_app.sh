#!/usr/bin/env bash
# Return to the most recent task the way a person does (Recents, tap the top
# card), so the activity resumes instead of being relaunched by an intent.
adb shell input keyevent KEYCODE_APP_SWITCH; sleep 2
read -r W H < <(adb shell wm size | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)
adb shell input tap $((W / 2)) $((H / 2))
