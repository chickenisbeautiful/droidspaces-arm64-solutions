#!/bin/sh
set -e
f=/home/steamos/gamescope_steam.sh
sed -i 's/exec steam -gamepadui -steamdeck -steamos3 -steampal -cef-enable-debugging/exec steam -gamepadui -cef-enable-debugging/' "$f"
grep -n 'exec steam' "$f"
