# [Feature] Native gamepad support for containers (expose `/dev/input` joysticks and stop Anland from duplicating gamepad input as keyboard)

## Summary

I would like to use a physical gamepad (a Bluetooth Xbox Wireless Controller, and wired controllers too) inside a
Droidspaces container that runs Steam Big Picture through the Anland display path.

Right now this needs two host-side hacks to work at all, and I think it is worth supporting in mainline, because
"phone that runs Steam / a full desktop" is one of the main use cases for Droidspaces + Anland.

There are two separate problems:

1. **No input device nodes inside the container.** `/dev/input` in the container contains only udev `by-path`
   symlinks; there are no `event*` nodes, so Steam/SDL cannot see the controller at all.
2. **Duplicate input.** Once a node is created by hand, every D-pad press is delivered twice: once as real gamepad
   input through the raw evdev node, and once as a simulated keyboard arrow key, because Android's InputReader still
   sees the gamepad and Anland forwards its key events into the container.

Both workarounds are described below. I am happy to test builds and to help with a PR if the direction sounds
acceptable.

## Environment

| Item | Value |
| --- | --- |
| Device | OnePlus Ace 3, Android 17 |
| Kernel | `5.15.180-Gold_bug aarch64` (GKI) |
| Root | SukiSU Ultra (`su` via `/system/bin/su`) |
| Droidspaces | v6.6.0 (app + daemon module) |
| Container | SteamOS (`ID_LIKE=arch`, holo), directory rootfs, systemd as PID 1 |
| Container options | Hardware Access = ON (`enable_hw_access=1`), Anland Display = ON, Termux:X11 = OFF, Net = host |
| Anland app | `com.anland.consumer` 5.23 (Anland 5.x, the version Droidspaces requires), display via gamescope `--backend anland` |
| Session | gamescope running `steam -gamepadui` (Big Picture) |
| Controller | Xbox Wireless Controller over Bluetooth, USB ID `045e:02e0`, evdev `event10` (`c 13:74`), udev `ID_INPUT_JOYSTICK=1` |

## Steps to reproduce

1. Pair/connect the gamepad to the phone.
2. Start a container with **Hardware Access** and **Anland Display** enabled.
3. Inside the container: `ls -l /dev/input` → only `by-path`, no `event*` nodes.
4. Steam/SDL does not see a controller (nothing in `~/.steam/steam/logs/controller.txt`).
5. Manually create the node and restart the game session:
   ```bash
   mknod /dev/input/event10 c 13 74 && chmod 666 /dev/input/event10
   ```
   Steam now detects it (`Local Device Found type: 045e 02e0`, `Xbox One Wireless Controller`, SDL mapping
   generated), but **the D-pad fires twice**: one gamepad input plus one keyboard arrow key.

## Root cause / observations

**Problem 1 — missing nodes.** On the host the device is present and correctly classified
(`/proc/bus/input/devices`: `ID_INPUT_JOYSTICK=1`). Inside the container the node is simply absent. Interestingly,
devices that are hot-plugged *after* the container has started do get a node automatically (devtmpfs), while devices
that are already present when the container starts do not. That suggests Droidspaces clears the existing nodes in
`/dev/input` at container start, and the container is expected to get its input through Anland only.

**Problem 2 — duplication.** Android's InputReader also owns the gamepad, so the Anland app receives its key events
and forwards them as keyboard events into the compositor:

```
$ dumpsys -t 30 input | grep -E "Device [0-9]+: (Xbox|Microsoft)"
Device 21: Xbox Wireless Controller
Device 22: Microsoft X-Box 360 pad 0     # the uinput virtual pad Steam itself creates
```

Steam Input additionally creates a virtual pad (`Microsoft X-Box 360 pad 0`) via uinput, which Android also sees and
Anland also forwards, so the duplication happens for both devices.

## Current workaround

**Part A — recreate joystick nodes inside the container with a small systemd service** (filtered to joysticks only,
so that the fingerprint-nav device, touchscreen or power keys are not leaked into the container):

```bash
#!/bin/bash
# /usr/local/bin/input-nodes.sh
mkdir -p /dev/input
sync_nodes() {
  local e k m major minor db
  for e in /sys/class/input/event*; do
    [ -e "$e" ] || continue
    k=${e##*/}
    m=$(cat "$e/dev" 2>/dev/null) || continue
    major=${m%%:*}; minor=${m##*:}
    db="/run/udev/data/c${major}:${minor}"
    grep -q '^E: ID_INPUT_JOYSTICK=1' "$db" 2>/dev/null || continue
    [ -e "/dev/input/$k" ] || mknod "/dev/input/$k" c "$major" "$minor" 2>/dev/null
    chmod 666 "/dev/input/$k" 2>/dev/null
  done
  [ -e /dev/uinput ] && chmod 666 /dev/uinput 2>/dev/null
}
sync_nodes
while :; do sleep 2; sync_nodes; done
```

with a matching `input-nodes.service` (`Restart=always`).

**Part B — remove the duplicate keyboard path by making Android ignore the gamepad**, so Anland never receives its
key events. This requires editing (via a KernelSU module that bind-mounts a replacement over the read-only erofs
file) `/vendor/etc/excluded-input-devices.xml` and restarting the framework:

```xml
<devices>
    <device name="Xbox Wireless Controller"/>
    <device name="Microsoft X-Box 360 pad 0"/>
    <device name="Microsoft X-Box 360 pad 1"/>
    <device name="Microsoft X-Box 360 pad 2"/>
    <device name="Microsoft X-Box 360 pad 3"/>
    <device name="Steam Virtual Gamepad"/>
</devices>
```

This works, but it is a system-level hack (root, SELinux relabel, framework restart, and the gamepad disappears from
Android itself). It is not something users should have to do, and wired controllers need their own name added
(`Microsoft X-Box 360 pad`, `Microsoft X-Box One pad`, `Microsoft X-Box One S pad`, …), which makes it even more
unfriendly.

## Proposed changes

1. **Container side — expose host input devices in the container's `/dev/input`.**
   A per-container option (for example *Input devices* / `passthrough_input`) that creates the host `event*` nodes
   inside the container and keeps them in sync on hot-plug add/remove, with sane permissions (0666, or group
   `input`). Passing only `ID_INPUT_JOYSTICK=1` devices by default would be enough for gamepads.
   *Note:* passing every host input device is not desirable — it leaks the fingerprint-nav `uinput_nav`, touchpanel
   and power keys into the container, where they are interpreted as arrow keys/other input. So the filter matters.

2. **Anland side — stop translating gamepad events into keyboard events.**
   Only real keyboard events should be forwarded as keys. Events whose `InputDevice` source is `SOURCE_GAMEPAD` /
   `SOURCE_JOYSTICK` should either be dropped (when the container already has the raw evdev node) or delivered as a
   proper evdev/uinput gamepad through the Anland protocol, instead of being mapped to arrow keys. This fixes the
   duplication at the source, without touching `/vendor`.

If passing the joystick nodes through is the intended design, then (2) alone would be enough to make gamepads usable;
if instead everything is meant to go through Anland, then a real gamepad input channel in the protocol is needed.
Either way, exposing the raw evdev joystick seems like the smallest and most compatible change, because SDL/Steam
then use the standard Linux input path.

## Additional context

- With both workarounds in place the controller works perfectly in Steam Big Picture (`SDL Mapping ... leftx:a0,
  lefty:a1 ...`), so the plumbing inside the container is fine; only the two issues above stand in the way.
- Related: #328 (input/touchscreen behaviour under Hardware Access) suggests input device handling with hw-access has
  a few rough edges in general.
- I searched the existing issues for gamepad/controller/input and did not find a duplicate report.
- Happy to provide logs (`droidspaces check`, container log, `dumpsys input`), test builds, or work on a PR.
