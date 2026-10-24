# Magisk 模块：`gamepad-isolate`（Android 侧输入隔离）

> 双语配对：[05-magisk-module.md](05-magisk-module.md)（英文）

这是整套方案里唯一**改动 Android 系统层**的地方，而且以 Magisk/SukiSU 模块形式提供，
不会真正写入 `/vendor` 分区。

## 1. 作用

否则 Android 的 `InputManagerService` 会抢下所有手柄，把按键当作 key event 转发给
Anland。容器里同一个输入会收到两次（一次内核 evdev，一次 Anland 转发）。本模块让 Android
忽略手柄，同时内核 evdev 节点仍然完整暴露给容器。

## 2. 文件

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

两个关键点：

- `chcon` 把 SELinux 标签设成 `vendor_configs_file`，标签不对 InputManagerService 读不到。
- `mount --bind` 只覆盖原文件的视图，真实分区不动。

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

**匹配是精确全名**，不能写通配符。震动马达的两个条目（`qti-haptics`、`qcom-hv-haptics`）
也要加，否则它们的输入设备会以方向键形式泄漏进容器。

## 3. 什么时候生效

`InputManagerService` **只在开机读一次**。改完 XML 后：

```bash
# 软重启 Android 框架
su -c 'stop; start'
# 或重启手机
```

验证：

```bash
su -c 'dumpsys -t 30 input' | grep ExcludedDeviceNames
su -c 'cat /proc/bus/input/devices'   # 应该看不到手柄
```

## 4. 加新手柄

1. 取精确名字：
   ```bash
   su -c 'cat /proc/bus/input/devices' | grep 'N: Name='
   ```
2. 每个输入设备加一行（有的手柄会创建多个输入设备，如 `... Touchpad`、
   `... Motion Sensors`，要全部加）。
3. 推进模块目录并重跑 `post-fs-data.sh`（或直接软重启）：
   ```bash
   su -c 'cp /data/local/tmp/excluded-input-devices.xml /data/adb/modules/gamepad-isolate/excluded-input-devices.xml'
   su -c 'chmod 644 /data/adb/modules/gamepad-isolate/excluded-input-devices.xml'
   su -c 'chcon u:object_r:vendor_configs_file:s0 /data/adb/modules/gamepad-isolate/excluded-input-devices.xml'
   su -c 'sh /data/adb/modules/gamepad-isolate/post-fs-data.sh'
   ```

## 5. 卸载

删掉模块目录并重启：

```bash
su -c 'rm -rf /data/adb/modules/gamepad-isolate'
```
