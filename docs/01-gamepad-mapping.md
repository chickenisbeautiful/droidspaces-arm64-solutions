# Gamepad Identification & Mapping on an ARM64 SteamOS Container

> Bilingual pair: [docs/01-gamepad-mapping.zh-CN.md](01-gamepad-mapping.zh-CN.md) (Chinese)

This is the **most detailed** document in the repository. It explains how a gamepad gets from a
Bluetooth/USB connection on Android all the way to a running Windows game under Proton, what
breaks at each step on this ARM64 setup, and the exact fixes that were applied.

---

## 1. The three layers of "recognition"

A controller is "recognized" by three **independent** mechanisms, each with a different rule:

| Layer | Where | Matching rule | Purpose |
|-------|-------|---------------|---------|
| 1. Android exclusion | `/vendor/etc/excluded-input-devices.xml` | **exact full name** | Stop Android's InputManager from grabbing the pad so Anland does not forward duplicate key events to the container |
| 2. Container node manager | `input-nodes.sh` (inside the container) | **keyword / glob match** on the kernel input device name | Create `/dev/input/eventN` + `chmod 666` so Steam/Proton can open the device |
| 3. Steam / SDL / Steam Input | inside the container | VID:PID + SDL mappings + `uinput` | Detect the pad, create a virtual Xbox pad for games |

If a controller "isn't recognized", the first question is **which layer** is failing.

---

## 2. Layer 1 — Android side (exact name matching)

### 2.1 How Android sees the device

Bluetooth pairing is done by Android's Bluetooth stack (by MAC address). Once connected, the
kernel creates an input device whose name is the **HID product string** reported by the pad:

```
/sys/class/input/eventN/device/name = "Xbox Wireless Controller"
```

### 2.2 The exclusion list

`/data/adb/modules/gamepad-isolate/excluded-input-devices.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<devices>
    <device name="qti-haptics"/>
    <device name="Xbox Wireless Controller"/>
    <device name="GameSir-X5 Lite"/>
    <device name="Sony Computer Entertainment Wireless Controller"/>
    ...
</devices>
```

**Rules:**

- Matching is **exact and case-sensitive**. `*Xbox*` is **invalid** here; the whole name must match.
- This only affects Android's InputManagerService. It does **not** affect the kernel, the container
  or Steam.
- InputManagerService reads the file **once at boot**. After editing, a soft reboot
  (`stop; start` or `su -c 'stop; start'`) or a phone reboot is required.

### 2.3 Why this layer exists

Without it, Android forwards every gamepad button to the Anland app as a key event, and the
container sees the **same** input twice (once from the kernel evdev, once from Anland's keyboard
forwarding). That is the "duplicate input" symptom.

### 2.4 Examples of exact names

| Controller | Exact name to add |
|-----------|-------------------|
| Xbox BT (XInput) | `Xbox Wireless Controller` |
| GameSir-X5 Lite | `GameSir-X5 Lite` |
| DS4 / PS mode | `Sony Computer Entertainment Wireless Controller` (+ the two sensor devices) |
| Steam virtual pad | `Steam Virtual Gamepad` |
| Generic 360 clone | `Microsoft X-Box 360 pad` (and `Microsoft X-Box 360 pad 0`..`3`) |

**Important:** The exclusion list uses exact names. Brand keywords (see section 4) belong in the
container script, not here. To add a new pad to the list, run on the phone:

```bash
su -c 'cat /proc/bus/input/devices' | grep 'N: Name='
```

and copy the string **verbatim** into the XML.

---

## 3. Layer 2 — Container side (`input-nodes.sh`)

### 3.1 Why a script is needed

The container has its **own** `/dev` (a separate `devtmpfs`, different `stat -c %d` from the
host) and its `systemd-udevd` runs in a **separate network namespace**. Kernel hot-plug uevents
are broadcast in the init netns only, so the container's udev never sees them. Consequently:

- Nodes for newly connected devices are **not** created automatically.
- `/run/udev/data/*` is not updated for hot-plugged devices (only cold-plugged ones at boot).

The script closes that gap by polling `/sys/class/input` (which *is* shared with the host) and
`mknod`-ing the corresponding node in the container's `/dev/input`.

### 3.2 What the script does every 0.5 s

1. Scan `/sys/class/input/event*`.
2. Read the device name from `/sys/class/input/eventN/device/name`.
3. If the name matches the **keyword list** (or the udev data says `ID_INPUT_JOYSTICK=1`),
   `mknod /dev/input/eventN c <major> <minor>` if missing, then `chmod 666`.
4. Delete stale nodes whose sysfs entry is gone (stale nodes make Steam enumerate dead fds).
5. Handle `hidraw` nodes for the same devices (see 3.5).
6. `chmod 666 /dev/uinput` (see 3.4).
7. Maintain `/run/input-nodes.state` (the set of *physical* gamepad event numbers). When the set
   changes (a pad connects/disconnects), run `udevadm trigger --action=add` for every gamepad
   node so Steam has a chance to re-scan.

### 3.3 Keyword matching

`is_gamepad()` uses shell `case` globbing, **case-sensitive**, substring match (`*keyword*`):

```bash
is_gamepad() {
  case "$1" in
    # Xbox / PlayStation / Nintendo modes and generic names
    *Xbox*|*X-Box*|*X-BOX*|*Microsoft*|*Controller*|*Gamepad*|*Joystick*|*"2.4G"*|*"Wireless Controller"*|*DualSense*|*DualShock*|*Sony*|*Nintendo*|*"Switch Pro"*|*"Pro Controller"*)
      return 0 ;;
    # Chinese brands
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
```

Notes:

- Matching is on the **kernel name**, which is always the English product string. Chinese brand
  names (飞智/北通/盖世小鸡/山弯) do **not** appear in the name; the keywords use the English
  brand and product lines.
- `is_physical_gamepad()` additionally excludes Steam's own virtual pads
  (`Microsoft X-Box 360 pad*`, `Steam Virtual Gamepad`) from the state-change trigger, to avoid a
  rescan loop. Those nodes are still `chmod 666`-ed so games can open them.

### 3.4 `/dev/uinput` must be 0666

Steam Input creates a **virtual Xbox pad** (`Microsoft X-Box 360 pad 0`) with `uinput`. That is
what Proton/Wine games normally see. If `/dev/uinput` is `0600 root:root`, Steam (running as the
normal user `steamos`) cannot create it, the game sees nothing — while the Steam UI still works
because it reads the physical evdev directly. Symptom: *"Steam UI can be controlled, but the
game does not recognize the pad."* Fix: `chmod 666 /dev/uinput` (the script enforces this).

### 3.5 hidraw vs evdev — the GameSir trap

- `evdev` (`/dev/input/eventN`) is the classic Linux input path.
- `hidraw` is used by Steam's **HIDAPI** backend, which can talk HID feature reports and is
  preferred by Steam for many pads.

For the **GameSir-X5 Lite** this went wrong: Steam's HIDAPI reads made the device re-enumerate
and flip between modes (`3537:1116` GameSir ↔ `057e:2009` Switch Pro), producing
`Controller device closed after hid_read failure` in Steam's log. The fix was to **deny** Steam
access to the GameSir hidraw:

```bash
chown root:input /dev/hidrawN
chmod 660 /dev/hidrawN      # steamos cannot open it → SDL falls back to evdev
```

Other brands' hidraw nodes stay `0666`; only `*GameSir*` is forced to evdev.

### 3.6 State-change trigger (hot-plug)

Simply creating the node is **not enough**: Steam's SDL does not re-scan on its own after a
disconnect. Verified experimentally:

- Renaming `/dev/input/event10` → `event20` left Steam holding the stale fd
  (`/dev/input/event10 (deleted)`) and it never opened `event20`.
- Creating a **new uinput** device *did* make Steam scan (it opened the new node immediately).
- Plugging a USB pad forces a full rescan, which is why a "plug/unplug the wired pad" trick
  revived the Bluetooth pad.

The script therefore tracks the physical gamepad set in `/run/input-nodes.state` and, when it
changes, runs `udevadm trigger --action=add` for all gamepad nodes. Combined with the 0.5 s poll,
total hot-plug latency is roughly:

| Step | Time |
|------|------|
| Bluetooth reconnect | 1–2 s |
| node creation (poll) | ≤ 0.5 s |
| Steam controller rescan | 1–2 s |
| **Total** | **~2–4 s** |

### 3.7 Wired GameSir-X5 Lite USB enumeration quirk

On this phone the pad enumerates as `3537:1116` (GameSir) and repeatedly disconnects/reconnects.
Linux kernel patches for similar GameSir pads explain the behaviour: the pad picks XInput vs
DInput **based on how the host fetches the configuration descriptor**, and without a
`USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE`-style quirk it keeps resetting. The stock phone kernel has
no such quirk and `xpad` has no ID for `3537:1116`, so:

- Xbox mode is effectively unusable on the phone (the XInput interface has no driver).
- PS/DualShock mode (`054c:09cc`) works.
- Blocking Steam's HIDAPI on the GameSir hidraw stopped the reset loop.

---

## 4. Full keyword & real-name table

| Brand | Kernel/Bluetooth names seen | Keywords in script |
|-------|----------------------------|--------------------|
| 飞智 Flydigi | `Flydigi VADER3/4/5`, `FLYDIGI APEX 5`, `Flydigi Direwolf` | `Flydigi` `VADER` `APEX` `Direwolf` |
| 盖世小鸡 GameSir | `GameSir-X5 Lite`, `GameSir-Nova 2 Lite`, `GameSir G7 SE`, `GameSir Cyclone 2` | `GameSir` |
| 北通 BETOP | `BETOP BTP-2585`, `BETOP KunPeng 40` | `BETOP` `BTP-` `Beitong` `KunPeng` `Pangu` `Asura` `Sparta` |
| 山弯 ShanWan | `ShanWan Wireless Gamepad` | `ShanWan` |
| 八位堂 8BitDo | `8BitDo Pro 2`, `8BitDo Ultimate`, `8BitDo SN30 Pro` | `8BitDo` |
| 墨将 BIGBIG WON | `BIGBIG WON Rainbow 2`, `BIGBIG WON Ovari` | `BIGBIG` |
| 机械师 Machenike | `Machenike G5 Pro` | `Machenike` |
| 良值 IINE | `IINE ...` | `IINE` |
| 黑爵 Ajazz / 达尔优 Dareu / 雷柏 Rapoo | `Ajazz ...`, `Dareu ...`, `Rapoo ...` | `Ajazz` `Dareu` `Rapoo` |
| 雷神 Thunderobot / 红魔 / 黑鲨 | `Thunderobot ...`, `RedMagic ...`, `Black Shark ...` | `Thunderobot` `RedMagic` `Black Shark` |
| Microsoft | `Xbox Wireless Controller`, `Microsoft X-Box 360 pad 0`, `Xbox One/Series X Controller` | `Xbox` `X-Box` `X-BOX` `Microsoft` |
| Sony | `Sony Computer Entertainment Wireless Controller`, `Wireless Controller`, `DualSense Wireless Controller` | `Sony` `DualSense` `DualShock` |
| Nintendo | `Pro Controller`, `Nintendo Switch Pro Controller` | `Nintendo` `Switch Pro` `Pro Controller` |
| Razer | `Razer Wolverine V2`, `Razer Kishi` | `Razer` `Wolverine` `Kishi` |
| Logitech / SteelSeries | `Logitech Gamepad F710`, `SteelSeries Stratus Duo` | `Logitech` `SteelSeries` `Stratus` `Nimbus` |
| PowerA / PDP / Hori / Nacon / SCUF / Turtle Beach / Thrustmaster | `PowerA ...`, `PDP ...`, `HORIPAD ...`, `Nacon ...`, `SCUF ...`, `Turtle Beach ...`, `Thrustmaster ...` | `PowerA` `PDP` `HORI` `Nacon` `SCUF` `Turtle Beach` `Thrustmaster` |
| Generic | anything containing `Controller` / `Gamepad` / `Joystick` / `2.4G` / `Wireless Controller` | those tokens |

Verified with `scripts/test-keywords.sh`:

```
YES  Xbox Wireless Controller
YES  Flydigi VADER4
YES  FLYDIGI APEX 5
YES  GameSir-X5 Lite
YES  BETOP BTP-2585
YES  BETOP KunPeng 40
YES  ShanWan Wireless Gamepad
YES  8BitDo Pro 2
YES  BIGBIG WON Rainbow 2
YES  Machenike G5 Pro
YES  Razer Wolverine V2
YES  Logitech Gamepad F710
YES  Sony Computer Entertainment Wireless Controller
YES  Nintendo Switch Pro Controller
NO   touchpanel
NO   uinput_nav
NO   qcom-hv-haptics
```

---

## 5. Failure modes and fixes

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| Steam UI works, game sees no pad | `/dev/uinput` is `0600 root:root`; Steam cannot create the virtual Xbox pad | `chmod 666 /dev/uinput`; script enforces it |
| Pad works at boot but not after hot-plug | Steam holds a stale deleted fd; container udev gets no uevents | 0.5 s poll + state-change `udevadm trigger`; better: connect pad before Steam, or restart the session |
| GameSir keeps disconnecting / switching to Switch Pro mode | Steam HIDAPI reads reset the pad (`hid_read failure`) | force evdev: `chmod 660` its hidraw |
| Duplicate key events in the container | Android forwards the pad to Anland | add exact name to `excluded-input-devices.xml` + soft reboot |
| Pad visible in `/proc/bus/input/devices` but not in container | container `/dev` is a separate devtmpfs | `input-nodes.sh` mknod |
| Wired 2.4 GHz Xbox dongle shows only arrow keys | XInput interface has no driver (`3537:1116`); only the keyboard interface binds | use PS mode (`054c:09cc`) or Bluetooth |
| Random `controller.txt` `hid_read failure` | pad re-enumerating underneath Steam | same GameSir fix; also check cable/power (500 mA OTG limit) |

---

## 6. How to add a new controller

1. On the phone:
   ```bash
   su -c 'cat /proc/bus/input/devices' | grep 'N: Name='
   ```
2. Container node script: if the name has no keyword, add one to `is_gamepad()` in
   `scripts/input-nodes.sh` and restart `input-nodes.service`.
3. Android exclusion: add the **exact** name to `excluded-input-devices.xml` in the Magisk module,
   then soft-reboot (`su -c 'stop; start'`).
4. Verify:
   ```bash
   # inside container
   ls -l /dev/input
   cat /run/input-nodes.state
   tail -f /home/steamos/.local/share/Steam/logs/controller.txt
   ```

---

## 7. The script

Full source: [scripts/input-nodes.sh](../scripts/input-nodes.sh)

Unit file: [services/input-nodes.service](../services/input-nodes.service)
