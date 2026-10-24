#!/bin/sh
set -e
f=/usr/local/bin/input-nodes.sh
sed -i 's/E: ID_INPUT_JOYSTICK/E:ID_INPUT_JOYSTICK/' "$f"
grep -n 'ID_INPUT_JOYSTICK' "$f"
