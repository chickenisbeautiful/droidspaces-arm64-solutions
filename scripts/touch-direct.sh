#!/bin/bash
# Keep gamescope in touch passthrough (direct touch) mode.
# Steam writes STEAM_TOUCH_CLICK_MODE on the X root window:
#   1 = left click (simulated mouse), 4 = passthrough (direct touch).
# Without a gamepad Steam sets 1; this watcher keeps it at 4.
export DISPLAY=:0
XP=/usr/sbin/xprop
while :; do
    cur=$("$XP" -root STEAM_TOUCH_CLICK_MODE 2>/dev/null | awk '{print $NF}')
    if [ "$cur" != "4" ]; then
        "$XP" -root -f STEAM_TOUCH_CLICK_MODE 32c -set STEAM_TOUCH_CLICK_MODE 4 2>/dev/null
    fi
    sleep 1
done
