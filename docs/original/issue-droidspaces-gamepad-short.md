# [Feature] Gamepad support for containers: expose `/dev/input` joysticks to the container, and stop Anland from turning gamepad buttons into keyboard keys

## Summary

Physical gamepads (Bluetooth or USB) do not work inside a Droidspaces container running Steam Big Picture through
Anland. There are two separate problems:

1. `/dev/input` inside the container has no `event*` nodes (only udev `by-path` symlinks), so Steam/SDL cannot see
   the controller at all.
2. After creating the node by hand, D-pad presses are duplicated: the real gamepad event **plus** a simulated
   keyboard arrow key, because Android's InputReader still owns the gamepad and Anland forwards its key events into
   the container.

## Environment

- OnePlus Ace 3, Android 17, kernel 5.15.180 aarch64 (GKI), SukiSU Ultra
- Droidspaces v6.6.0; container: SteamOS (systemd), directory rootfs
- Container options: Hardware Access **ON** (`enable_hw_access=1`), Anland Display **ON**, Termux:X11 **OFF**
- Anland app `com.anland.consumer` 5.23; gamescope `--backend anland` running `steam -gamepadui`
- Controller: Xbox Wireless Controller, USB `045e:02e0`, evdev `event10` (`c 13:74`), udev `ID_INPUT_JOYSTICK=1`

## Steps to reproduce

1. Connect the gamepad, then start the container with Hardware Access + Anland enabled.
2. Inside the container: `ls -l /dev/input` → only `by-path`, no `event*`.
3. Steam/SDL sees no controller.
4. Create the node manually and restart the session:
   ```bash
   mknod /dev/input/event10 c 13 74 && chmod 666 /dev/input/event10
   ```
   Steam now detects it, but every D-pad press fires twice (gamepad input + keyboard arrow key).

## Observations

- The host has the device and marks it `ID_INPUT_JOYSTICK=1`; only the container is missing the node.
- Devices hot-plugged *after* the container starts do get a node (devtmpfs), devices already present at start do not
  → it looks like `/dev/input` is emptied at container start.
- Host `dumpsys input` lists both `Xbox Wireless Controller` and Steam's uinput pad `Microsoft X-Box 360 pad 0`, and
  Anland forwards the key events of both as keyboard input.

## Current workaround

- Container: a small systemd service that recreates **joystick-only** nodes (filtered on `ID_INPUT_JOYSTICK=1`).
- Host: exclude the gamepad names in `/vendor/etc/excluded-input-devices.xml` (bind-mounted by a KernelSU module) so
  Android/Anland never sees them. This is root-only and fragile, and every wired controller model needs its own name.

More details and the full script can be added in a follow-up comment if needed.

## Proposed changes

1. **Container side:** a per-container option (e.g. `passthrough_input`) that exposes the host `event*` nodes inside
   the container and keeps them in sync on hot-plug, filtered to `ID_INPUT_JOYSTICK=1` by default. Exposing *all*
   input devices is not desirable: it leaks `uinput_nav` (fingerprint navigation), the touchpanel and power keys
   into the container, where they appear as stray arrow keys / input.
2. **Anland side:** do not translate `SOURCE_GAMEPAD` / `SOURCE_JOYSTICK` events into keyboard keys. Either drop
   them (when the container already has the raw evdev node) or deliver them as a proper gamepad input.

With both workarounds applied the controller works perfectly in Steam Big Picture, so the container plumbing is fine;
only these two issues block a clean, out-of-the-box experience.

Happy to provide logs (`droidspaces check`, container log, `dumpsys input`), test builds, or help with a PR.
