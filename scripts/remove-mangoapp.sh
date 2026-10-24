#!/bin/sh
set -e
f=/home/steamos/gamescope_steam.sh
sed -i 's/ --mangoapp / /g' "$f"
grep -n 'GAMESCOPE_BIN" --backend' "$f"
