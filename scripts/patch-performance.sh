#!/bin/sh
set -e
f=/home/steamos/gamescope_steam.sh
sed -i 's/exec steam -gamepadui -cef-enable-debugging/exec steam -gamepadui -steamdeck -steamos3 -steampal -cef-enable-debugging/' "$f"
sed -i 's|exec "$GAMESCOPE_BIN" --backend anland -f -e  --|exec "$GAMESCOPE_BIN" --backend anland -f -e --mangoapp --|' "$f"
sed -i 's|exec "$GAMESCOPE_BIN" --backend anland -f --|exec "$GAMESCOPE_BIN" --backend anland -f --mangoapp --|' "$f"
grep -n -e 'exec steam' -e 'GAMESCOPE_BIN" --backend' "$f"
