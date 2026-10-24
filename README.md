# DroidSpaces ARM64 Solutions

> **⚠️ AI-generated repository**
>
> All documentation, scripts and modules in this repository were written by an AI assistant
> (**MiMo-V2.6-Pro / opencode**) on 2026-10-25, during a live debugging session on real
> hardware. They have **not** been independently reviewed. Verify every command before you run
> it. See [DISCLAIMER.md](DISCLAIMER.md).
>
> 中文版：[README.zh-CN.md](README.zh-CN.md)

Bilingual documentation and tooling for a **SteamOS ARM64 container (DroidSpaces)** running on a
smartphone (OnePlus Ace 3 / Snapdragon 8 Gen 2 / Adreno 740). The same techniques apply to any
Linux+SteamOS-like environment on ARM64.

## Topics

| # | Topic | Where |
|---|-------|-------|
| 1 | **Gamepad identification & mapping** (core) | [docs/01-gamepad-mapping.md](docs/01-gamepad-mapping.md) |
| 2 | **Steam client versions & defects** (core) | [docs/02-steam-versions-and-defects.md](docs/02-steam-versions-and-defects.md) |
| 3 | Decky Loader on ARM64 | [docs/03-decky-loader-arm64.md](docs/03-decky-loader-arm64.md) |
| 4 | Container systemd & session | [docs/04-container-systemd.md](docs/04-container-systemd.md) |
| 5 | Magisk module for input isolation | [docs/05-magisk-module.md](docs/05-magisk-module.md) |
| 6 | Performance HUD / Deck mode | [docs/06-performance-hud-and-deck-mode.md](docs/06-performance-hud-and-deck-mode.md) |
| 7 | Steam startup animations | [docs/07-steam-startup-animation.md](docs/07-steam-startup-animation.md) |
| 8 | Troubleshooting log | [docs/08-troubleshooting-log.md](docs/08-troubleshooting-log.md) |

## Hardware / software used

- Phone: OnePlus Ace 3 (PJE110), Snapdragon 8 Gen 2, Android, Magisk/SukiSU
- Container: DroidSpaces (`droidspaces`), SteamOS ARM64 rootfs, NAT network, Anland display
- Controllers tested:
  - Xbox Wireless Controller (Bluetooth, name `Xbox Wireless Controller`)
  - GameSir-X5 Lite (USB + 2.4 GHz dongle, name `GameSir-X5 Lite`, VID:PID `3537:1116`)
  - DualShock 4 / PS4 mode of a multi-mode pad (`054c:09cc`)
- Steam: ARM64 client (`steamrtarm64/steam`), Proton 11.0 (ARM64), Steam Input, Decky Loader
- Gamescope 3.16.28-anland-experimental (custom ARM64 build)

## Repository layout

```
README.md / README.zh-CN.md      bilingual overview
DISCLAIMER.md                    AI-generated notice
docs/                            bilingual documents (EN + .zh-CN)
scripts/                         shell scripts and one C helper
services/                        systemd unit files
magisk-module/gamepad-isolate/   Android-side input isolation module
screenshots/                     screenshots taken during the debugging session
```

## Quick start

**Container side** (inside the SteamOS container):

```bash
# keep /dev/input + /dev/uinput usable for gamepads
cp scripts/input-nodes.sh /usr/local/bin/input-nodes.sh
cp services/input-nodes.service /etc/systemd/system/
# NOTE: custom units must live in /usr/lib/systemd/system (see doc 04)
cp services/plugin_loader.service /usr/lib/systemd/system/
ln -sf /usr/lib/systemd/system/plugin_loader.service \
       /usr/lib/systemd/system/multi-user.target.wants/plugin_loader.service
systemctl daemon-reload
systemctl enable --now input-nodes plugin_loader
```

**Android side** (Magisk/SukiSU module): see
[magisk-module/gamepad-isolate/](magisk-module/gamepad-isolate/). It bind-mounts
`excluded-input-devices.xml` over `/vendor/etc/excluded-input-devices.xml` so Android's
InputManager ignores gamepads (prevents Anland from forwarding duplicate key events).

## Key takeaways

1. **Gamepad hot-plug on ARM64 containers is fragile.** The container has its own `/dev`
   (separate devtmpfs) and its udev runs in a separate network namespace, so it never sees host
   kernel hot-plug uevents. `input-nodes.sh` fills the gap by polling `/sys/class/input` and
   `mknod`-ing nodes. See doc 01.
2. **`/dev/uinput` must be 0666**, otherwise Steam (running as a normal user) cannot create the
   virtual gamepad that Proton/Wine games expect.
3. **Do not let Steam's HIDAPI open certain pads.** For the GameSir-X5 Lite, HIDAPI reads made the
   device re-enumerate and switch modes; forcing evdev by keeping its `hidraw` at 0660 fixed it.
4. **Steam branch matters.** `steamdeck_publicbeta` and `steamdeck_stable` behave differently for
   controller hot-plug on ARM64. See doc 02.
5. **Deck mode has real defects on ARM64.** `--mangoapp` conflicts with the Steam UI swapchain;
   `IClientSystemDisplayManager::GetState` stalls the UI thread. See doc 02 and 06.

## Screenshots

See [screenshots/](screenshots/). They show the Steam Big Picture UI, Deck UI spinner, MangoHud
overlay, lock-screen failures and the DroidSpaces container panel used during debugging.

## License / usage

Use at your own risk. No license is granted beyond personal use; the material is provided as-is.
