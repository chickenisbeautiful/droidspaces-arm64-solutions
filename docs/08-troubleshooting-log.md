# Troubleshooting Log (chronological)

> Bilingual pair: [08-troubleshooting-log.zh-CN.md](08-troubleshooting-log.zh-CN.md) (Chinese)

Every row below is a problem that actually occurred during this session and how it was resolved.

| # | Symptom | Root cause | Fix | Doc |
|---|---------|-----------|-----|-----|
| 1 | Gamepad not visible inside the container | container `/dev` is a separate devtmpfs; nodes not created | `input-nodes.sh` polls `/sys/class/input` and `mknod`s gamepad nodes | 01 |
| 2 | Duplicate key events (D-pad = arrows) | Android forwards the pad to Anland | `gamepad-isolate` Magisk module + `excluded-input-devices.xml` | 05 |
| 3 | Nodes lost after reboot | service not running / stale nodes | `input-nodes.service`, stale-node cleanup | 01, 04 |
| 4 | Touch acts as mouse, not direct | gamescope `touch_click_mode` default `1` (left click) | set `STEAM_TOUCH_CLICK_MODE=4` (passthrough) and keep it with `anland-touch-direct.service` | 06 |
| 5 | Wired GameSir shows only arrow keys | XInput interface (`3537:1116`) has no driver; only the keyboard interface binds | use PS mode (`054c:09cc`) or Bluetooth | 01 |
| 6 | PS4/PS-mode pad not detected | event node missing + Steam scan race | `input-nodes.sh` + `udevadm trigger` | 01 |
| 7 | Decky Loader not installing | stable release ships x86_64 `PluginLoader` only | use `v3.3.0-pre1` `PluginLoader-arm64` | 03 |
| 8 | Decky gone after container reboot | custom unit in `/etc/systemd/system` invisible to systemd's first scan (overlay) | put the unit + `wants` symlink in `/usr/lib/systemd/system` | 04 |
| 9 | Steam stuck at spinner after Deck mode | `IClientSystemDisplayManager::GetState` timeouts + CEF transport errors + MangoApp swapchain war | revert to Big Picture; keep `--mangoapp` off; fix branch (see 10) | 02, 06 |
| 10 | Bluetooth pad no longer hot-plugs | Steam client switched from `steamdeck_publicbeta` to `steamdeck_stable` | restore `package/beta` = `steamdeck_publicbeta` | 02 |
| 11 | GameSir re-enumerates / switches to Switch Pro mode | Steam HIDAPI reads reset the pad (`hid_read failure`) | force evdev: `chmod 660` its hidraw | 01 |
| 12 | Game sees no pad but Steam UI works | `/dev/uinput` is `0600 root:root`; Steam cannot create the virtual Xbox pad | `chmod 666 /dev/uinput` | 01 |
| 13 | Hot-plug delayed / flaky | 2 s polling + Steam rescan | poll every 0.5 s + state-change `udevadm trigger` | 01 |
| 14 | No picture on the Anland display | phone locked / notification shade covering SecondaryActivity | `cmd statusbar collapse`, `am start ...SecondaryActivity`, raise screen timeout | 04 |
| 15 | `systemctl is-system-running` stuck at `starting` | phone-specific units (`qteesupplicant`, `sheng-devauth`, `xiaomi-sheng-thp`, `bluetooth`) block the boot transaction | mask them in `/usr/lib/systemd/system` | 04 |
| 16 | `systemctl --user` fails | user manager exited when the last session ended | `loginctl enable-linger steamos` | 04 |
| 17 | Startup animation download spinning | Steam client updating / download queue busy; it is a Points Shop item, not Workshop | wait for update; buy in Points Shop, then select in Settings | 07 |
| 18 | `steamloopback.host` transport errors | UI thread blocked by the display manager timeouts | resolved by removing Deck mode; name already resolves to 127.0.0.1 | 02 |
| 19 | Wired pad disappears after Steam HIDAPI opens it | same as 11 | same as 11 | 01 |
| 20 | Container restarted by itself / PID changed | normal; custom units re-created at each boot in `/usr/lib` | none | 04 |

## General debugging commands

```bash
# host side
su -c 'cat /proc/bus/input/devices'
su -c 'lsusb'
su -c 'dmesg' | grep -i usb
dumpsys usb | sed -n '/host_manager/,/}/p'
dumpsys window | grep mCurrentFocus

# container side
droidspaces --name=steamos run ls -l /dev/input /dev/hidraw* /dev/uinput
droidspaces --name=steamos run cat /run/input-nodes.state
droidspaces --name=steamos run journalctl -t input-nodes -n 20
droidspaces --name=steamos run tail -30 /home/steamos/.local/share/Steam/logs/controller.txt
droidspaces --name=steamos run grep -c GetState /home/steamos/.local/share/Steam/logs/console_log.txt
droidspaces --name=steamos run systemctl --failed
```

## Verification of the final state

- `systemctl is-system-running` → `running`
- `systemctl --failed` → 0 units
- `plugin_loader.service` active, log shows `Loading Decky frontend!`
- `input-nodes.service` active, `/dev/input/eventN` and `/dev/uinput` are `0666` for gamepads
- Steam opens `/dev/input/eventN` (evdev) for the pad and creates `Microsoft X-Box 360 pad N`
- Steam branch is `steamdeck_publicbeta`
