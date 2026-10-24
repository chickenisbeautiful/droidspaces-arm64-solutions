#!/bin/bash
eval "$(sed -n '/^is_gamepad()/,/^}/p' /usr/local/bin/input-nodes.sh)"
for n in \
  "Xbox Wireless Controller" \
  "Flydigi VADER4" \
  "FLYDIGI APEX 5" \
  "GameSir-X5 Lite" \
  "BETOP BTP-2585" \
  "BETOP KunPeng 40" \
  "ShanWan Wireless Gamepad" \
  "8BitDo Pro 2" \
  "BIGBIG WON Rainbow 2" \
  "Machenike G5 Pro" \
  "Razer Wolverine V2" \
  "Logitech Gamepad F710" \
  "Sony Computer Entertainment Wireless Controller" \
  "Nintendo Switch Pro Controller" \
  "touchpanel" \
  "uinput_nav" \
  "qcom-hv-haptics"; do
  if is_gamepad "$n"; then echo "YES  $n"; else echo "NO   $n"; fi
done
