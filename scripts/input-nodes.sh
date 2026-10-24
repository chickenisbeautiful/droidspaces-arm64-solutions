#!/bin/bash
# Maintain /dev/input and /dev/hidraw nodes for gamepad devices only.
mkdir -p /dev/input
STATE_FILE=/run/input-nodes.state

is_gamepad() {
  case "$1" in
    # Xbox / PlayStation / Nintendo modes and generic names
    *Xbox*|*X-Box*|*X-BOX*|*Microsoft*|*Controller*|*Gamepad*|*Joystick*|*"2.4G"*|*"Wireless Controller"*|*DualSense*|*DualShock*|*Sony*|*Nintendo*|*"Switch Pro"*|*"Pro Controller"*)
      return 0 ;;
    # Chinese brands: GameSir, Flydigi, BETOP, ShanWan, 8BitDo, BIGBIG WON, Machenike, IINE ...
    *GameSir*|*Flydigi*|*VADER*|*APEX*|*Direwolf*|*BETOP*|*BTP-*|*Beitong*|*KunPeng*|*Pangu*|*Asura*|*Sparta*)
      return 0 ;;
    *ShanWan*|*8BitDo*|*BIGBIG*|*Machenike*|*IINE*|*Ajazz*|*Dareu*|*Rapoo*|*Thunderobot*|*RedMagic*|*"Black Shark"*)
      return 0 ;;
    # International brands
    *Razer*|*Wolverine*|*Kishi*|*Logitech*|*SteelSeries*|*Stratus*|*Nimbus*|*PowerA*|*PDP*|*HORI*|*Nacon*|*SCUF*|*"Turtle Beach"*|*Thrustmaster*)
      return 0 ;;
  esac
  return 1
}

# Steam's own virtual pads must not drive the rescan trigger, or we can loop.
is_physical_gamepad() {
  case "$1" in
    *"Microsoft X-Box 360 pad"*|*"Steam Virtual Gamepad"*) return 1 ;;
  esac
  is_gamepad "$1"
}

trigger_rescan() {
  local e k name
  for e in /sys/class/input/event*; do
    [ -e "$e" ] || continue
    k=${e##*/}
    name=$(cat "$e/device/name" 2>/dev/null)
    is_gamepad "$name" || continue
    udevadm trigger --action=add "$e" 2>/dev/null
  done
}

sync_nodes() {
  local e k name m current="" previous=""
  for e in /sys/class/input/event*; do
    [ -e "$e" ] || continue
    k=${e##*/}
    name=$(cat "$e/device/name" 2>/dev/null)
    is_gamepad "$name" || continue
    is_physical_gamepad "$name" && current="$current $k"
    m=$(cat "$e/dev" 2>/dev/null) || continue
    [ -e "/dev/input/$k" ] || mknod "/dev/input/$k" c "${m%%:*}" "${m##*:}" 2>/dev/null
    chmod 666 "/dev/input/$k" 2>/dev/null
  done

  current=$(printf '%s\n' $current | sort | tr '\n' ' ')
  [ -f "$STATE_FILE" ] && previous=$(cat "$STATE_FILE")
  if [ "$current" != "$previous" ]; then
    printf '%s\n' "$current" > "$STATE_FILE"
    logger -t input-nodes "gamepad set changed:$current" 2>/dev/null
    trigger_rescan
  fi

  for d in /dev/input/event*; do
    [ -e "$d" ] || continue
    k=${d##*/}
    [ -e "/sys/class/input/$k" ] || rm -f "$d"
  done

  local h hn hname hm
  for h in /sys/class/hidraw/hidraw*; do
    [ -e "$h" ] || continue
    hn=${h##*/}
    hname=$(sed -n 's/^HID_NAME=//p' "$h/device/uevent" 2>/dev/null)
    is_gamepad "$hname" || continue

    # Keep GameSir hidraw away from Steam's HIDAPI; evdev is enough and
    # HIDAPI reads make this controller re-enumerate / switch modes.
    case "$hname" in
      *GameSir*)
        chown root:input "/dev/$hn" 2>/dev/null
        chmod 660 "/dev/$hn" 2>/dev/null
        continue
        ;;
    esac

    hm=$(cat "$h/dev" 2>/dev/null) || continue
    [ -e "/dev/$hn" ] || mknod "/dev/$hn" c "${hm%%:*}" "${hm##*:}" 2>/dev/null
    chmod 666 "/dev/$hn" 2>/dev/null
  done

  for d in /dev/hidraw*; do
    [ -e "$d" ] || continue
    k=${d##*/}
    [ -e "/sys/class/hidraw/$k" ] || rm -f "$d"
  done

  [ -e /dev/uinput ] && chmod 666 /dev/uinput 2>/dev/null
}

sync_nodes
while :; do
  sleep 0.5
  sync_nodes
done
