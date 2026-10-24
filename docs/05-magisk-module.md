# Magisk Module: `gamepad-isolate` (Android-side input isolation)

> Bilingual pair: [05-magisk-module.zh-CN.md](05-magisk-module.zh-CN.md) (Chinese)

This is the only **Android system-level** change in the whole setup, and it is delivered as a
Magisk/SukiSU module so nothing is written to the real `/vendor` partition.

## 1. Purpose

Android's `InputManagerService` would otherwise grab every connected gamepad and forward its
buttons to the Anland app as key events. The container then receives the same input twice (once
from kernel evdev, once from Anland). The module hides gamepads from Android while leaving the
kernel evdev node fully available to the container.

## 2. Files

```
magisk-module/gamepad-isolate/
├── module.prop
├── post-fs-data.sh
└── excluded-input-devices.xml
```

### `module.prop`

```
id=gamepad-isolate
name=Gamepad Input Isolation
version=1.0
description=Exclude gamepads from Android input so Anland does not forward duplicate key events
```

### `post-fs-data.sh`

```bash
#!/system/bin/sh
MODDIR=${0%/*}
chcon u:object_r:vendor_configs_file:s0 "$MODDIR/excluded-input-devices.xml" 2>/dev/null
mount --bind "$MODDIR/excluded-input-devices.xml" /vendor/etc/excluded-input-devices.xml
```

Two details matter:

- `chcon` sets the SELinux label to `vendor_configs_file`; without it the label is wrong and
  InputManagerService cannot read the file.
- `mount --bind` overlays the stock file read-only. Nothing on the real partition is modified.

### `excluded-input-devices.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<devices>
    <device name="qti-haptics"/>
    <device name="qcom-hv-haptics"/>
    <device name="Xbox Wireless Controller"/>
    <device name="Microsoft X-Box 360 pad"/>
    <device name="Microsoft X-Box 360 pad 0"/>
    ...
    <device name="Sony Computer Entertainment Wireless Controller"/>
    <device name="Sony Computer Entertainment Wireless Controller Touchpad"/>
    <device name="Sony Computer Entertainment Wireless Controller Motion Sensors"/>
    <device name="GameSir-X5 Lite"/>
    <device name="Steam Virtual Gamepad"/>
</devices>
```

**Matching is exact and full-name.** No wildcards. The haptics entries (`qti-haptics`,
`qcom-hv-haptics`) are included because their input devices otherwise leak into the container as
arrow keys.

## 3. When changes take effect

`InputManagerService` reads this file **once at boot**. After editing the XML:

```bash
# soft restart of the Android framework
su -c 'stop; start'
# or reboot the phone
```

Then verify:

```bash
su -c 'dumpsys -t 30 input' | grep ExcludedDeviceNames
su -c 'cat /proc/bus/input/devices'   # should NOT list the gamepad
```

## 4. Adding a new controller

1. Get the exact name:
   ```bash
   su -c 'cat /proc/bus/input/devices' | grep 'N: Name='
   ```
2. Add one line per device (some pads create several input devices — add all of them, e.g.
   `... Touchpad`, `... Motion Sensors`).
3. Push the file into the module directory and re-run `post-fs-data.sh` (or just soft-reboot):
   ```bash
   su -c 'cp /data/local/tmp/excluded-input-devices.xml /data/adb/modules/gamepad-isolate/excluded-input-devices.xml'
   su -c 'chmod 644 /data/adb/modules/gamepad-isolate/excluded-input-devices.xml'
   su -c 'chcon u:object_r:vendor_configs_file:s0 /data/adb/modules/gamepad-isolate/excluded-input-devices.xml'
   su -c 'sh /data/adb/modules/gamepad-isolate/post-fs-data.sh'
   ```

## 5. Uninstall

Remove the module directory and reboot:

```bash
su -c 'rm -rf /data/adb/modules/gamepad-isolate'
```
