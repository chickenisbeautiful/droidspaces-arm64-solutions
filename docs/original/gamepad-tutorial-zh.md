# Xbox 蓝牙手柄在 DroidSpaces（SteamOS）容器内完整识别教程

> 适用环境：
> - 手机：OnePlus Ace 3（Android 17，内核 5.15.180-Gold_bug aarch64，已 root：SukiSU Ultra）
> - 容器：DroidSpaces v6.6.0 的 `steamos` 容器（SteamOS / Arch 系）
> - 显示层：Anland（com.anland.consumer，负责把容器的 Wayland 画面投到手机屏幕）
> - 手柄：Xbox Wireless Controller（蓝牙 MAC `ac:7a:94:30:86:9a`，USB ID `045e:02e0`）

---

## 一、问题现象与根因

### 现象 1：手柄完全无反应，只有方向键能用

DroidSpaces 容器启动时会清空 `/dev/input/` 目录，只剩 udev 留下的 `by-path` 符号链接。真实设备节点（`event10` 等）不存在，Steam / SDL 无文件可读，因此识别不到手柄。

此前手柄"只能上下左右"，其实是 Anland 在转发 Android 的按键事件，不是 Steam 真的认到了手柄。

### 现象 2：按一次方向键，输入两次（一次手柄 + 一次键盘）

Android 的输入系统仍然能看到蓝牙手柄（`dumpsys input` 里有 `Xbox Wireless Controller` 和 Steam 生成的虚拟手柄 `Microsoft X-Box 360 pad 0`）。Anland 会把这些设备的按键事件转发成键盘方向键进容器。

于是同一次按键：

- **路径 A**：内核 evdev → 容器内 Steam 直接读到 → 手柄输入 ✅（我们要的）
- **路径 B**：Android InputReader → Anland 转发 KEYCODE_DPAD_* → 容器内键盘方向键 ❌（多余）

修复方向：路径 A 保留（补齐设备节点），路径 B 关闭（让 Android 忽略这些设备）。

---

## 二、方案总览

| 步骤 | 目标 | 方法 |
|------|------|------|
| 1 | 修好 SSH 远程访问 | `systemctl enable --now sshd` |
| 2 | 容器内补出手柄节点 | `mknod` + systemd 常驻服务 `input-nodes.service` |
| 3 | 让 Steam 重新枚举 | 重启 `anland-game-mode.service` |
| 4 | 消除键盘重复输入 | 修改 `/vendor/etc/excluded-input-devices.xml`，让 Android 忽略手柄 |
| 5 | 持久化 | SukiSU 模块 `gamepad-isolate` 开机自动 bind mount |

---

## 三、操作步骤

### 步骤 1：建立访问通道（ADB + SSH）

```powershell
adb shell "su -c id"   # 确认 root 可用
```

进入容器的命令格式（后面都用它）：

```powershell
adb shell "su -c '/data/local/Droidspaces/bin/droidspaces --name=steamos run <命令>'"
```

容器内启用并自启 SSH（默认用户 `steamos`，密码 `1234`）：

```bash
systemctl enable --now sshd
```

然后即可从 PC 直连：

```powershell
ssh steamos@192.168.5.22      # 密码 1234
```

`steamos` 用户已属于 `input` 组（gid 994），可以读取手柄节点。

### 步骤 2：手动补出一次设备节点（验证用）

在手机 shell（root）里执行：

```bash
mknod /dev/input/event10 c 13 74
chmod 666 /dev/input/event10 /dev/uinput
```

其中主设备号 13 是固定的 input 设备，次设备号在主机的 `/sys/class/input/event10/dev` 里查看（本例为 `13:74`）。

重启游戏模式让 Steam 重新枚举：

```bash
# 手机 shell：
/data/local/Droidspaces/bin/droidspaces -n steamos -u steamos run \
  env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user restart anland-game-mode.service
```

Steam 日志确认识别：

```bash
cat /home/steamos/.steam/steam/logs/controller.txt
```

应看到类似：

```
Local Device Found type: 045e 02e0
Xbox One Wireless Controller
Steam controller device opened for index 0
SDL Mapping ... leftx:a0,lefty:a1 ...
```

### 步骤 3：常驻服务自动补节点（解决容器重启后失效）

手动 `mknod` 在容器重启后会失效，所以写一个每 2 秒扫描并重建节点的服务。

**`/usr/local/bin/input-nodes.sh`**（注意：只创建手柄类设备，见后文"只暴露手柄"一节）：

```bash
#!/bin/bash
# Maintain /dev/input nodes for joystick/gamepad devices only.
mkdir -p /dev/input
sync_nodes() {
  local e k m major minor db
  for e in /sys/class/input/event*; do
    [ -e "$e" ] || continue
    k=${e##*/}
    m=$(cat "$e/dev" 2>/dev/null) || continue
    major=${m%%:*}
    minor=${m##*:}
    db="/run/udev/data/c${major}:${minor}"
    grep -q '^E: ID_INPUT_JOYSTICK=1' "$db" 2>/dev/null || continue
    if [ ! -e "/dev/input/$k" ]; then
      mknod "/dev/input/$k" c "$major" "$minor" 2>/dev/null
    fi
    chmod 666 "/dev/input/$k" 2>/dev/null
  done
  [ -e /dev/uinput ] && chmod 666 /dev/uinput 2>/dev/null
}
sync_nodes
while :; do
  sleep 2
  sync_nodes
done
```

**`/etc/systemd/system/input-nodes.service`**：

```ini
[Unit]
Description=Maintain /dev/input event nodes for container
After=multi-user.target

[Service]
ExecStart=/usr/local/bin/input-nodes.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

安装并启用：

```bash
chmod 755 /usr/local/bin/input-nodes.sh
systemctl daemon-reload
systemctl enable --now input-nodes.service
```

验证：删掉节点后约 4 秒会自动重建。

> **为什么只创建 `ID_INPUT_JOYSTICK=1` 的节点？**
> 容器启动后新热插拔的设备，devtmpfs 会自动创建节点。如果不加过滤，`uinput_nav`（OnePlus 指纹导航虚拟设备，正好只有上下左右键）、触摸屏、电源键等也会暴露给容器，导致指纹滑动在游戏里变成方向键等怪问题。所以按 udev 属性过滤，只放行手柄。

### 步骤 4：消除"手柄 + 键盘"重复输入

关键点：Android 的 InputManagerService 启动时会读取 `/vendor/etc/excluded-input-devices.xml`（本机为 Qualcomm 提供，原本只有两条 haptics 条目），列表里的设备名会被 Android 输入系统直接忽略——但内核的 evdev 节点不受影响，容器照常可用。这正好是我们要的效果。

先查看当前条目：

```bash
cat /vendor/etc/excluded-input-devices.xml
```

准备新版文件（保留原有条目，追加手柄）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<devices>
    <device name="qti-haptics"/>
    <device name="qcom-hv-haptics"/>
    <device name="Xbox Wireless Controller"/>
    <device name="Microsoft X-Box 360 pad 0"/>
    <device name="Microsoft X-Box 360 pad 1"/>
    <device name="Microsoft X-Box 360 pad 2"/>
    <device name="Microsoft X-Box 360 pad 3"/>
    <device name="Steam Virtual Gamepad"/>
</devices>
```

> 注意：Steam Input 会通过 uinput 生成一个虚拟手柄 `Microsoft X-Box 360 pad 0`，它同样会被 Anland 转发成键盘输入，所以必须一起排除。设备名必须与主机 `/proc/bus/input/devices` 中 `Name=` 完全一致。

用 bind mount 立即生效（`/vendor` 是 erofs 只读分区，不能直接写）：

```bash
cp excluded-input-devices.xml /data/local/tmp/
chcon u:object_r:vendor_configs_file:s0 /data/local/tmp/excluded-input-devices.xml
mount --bind /data/local/tmp/excluded-input-devices.xml /vendor/etc/excluded-input-devices.xml
```

> SELinux 标签必须改成 `vendor_configs_file`，否则 system_server 读不到文件，等于没有排除表。

由于该列表只在 InputManagerService 启动时读取，需要让框架重新启动。软重启（不影响容器进程，但会重启 Android UI，Anland 应用会被杀掉需要重新打开）：

```bash
su -c 'stop; start'
# 或者直接重启手机
```

### 步骤 5：验证

框架起来后检查：

```bash
dumpsys -t 30 input | grep ExcludedDeviceNames
```

期望输出：

```
ExcludedDeviceNames: [qti-haptics, qcom-hv-haptics, Xbox Wireless Controller,
 Microsoft X-Box 360 pad 0, Microsoft X-Box 360 pad 1,
 Microsoft X-Box 360 pad 2, Microsoft X-Box 360 pad 3, Steam Virtual Gamepad]
```

同时 `dumpsys -t 30 input` 的设备列表里**不应再出现** `Xbox Wireless Controller` 和 `Microsoft X-Box 360 pad 0`。

容器侧确认手柄仍在：

```bash
ls -l /dev/input          # 应有 event10 / event11
tail -20 /home/steamos/.steam/steam/logs/controller.txt
```

> 提示：软重启会短暂断开蓝牙，手柄可能掉线十几秒后自动重连；重连后 devtmpfs 会自动建节点，`input-nodes.service` 也会补上。

### 步骤 6：持久化（SukiSU 模块）

bind mount 重启后会消失，用内核 root 方案的模块在开机早期重新挂载：

```
/data/adb/modules/gamepad-isolate/
├── module.prop
├── excluded-input-devices.xml      # 第 4 步的完整 XML，chmod 644
└── post-fs-data.sh                 # chmod 755
```

**module.prop**：

```ini
id=gamepad-isolate
name=Gamepad Input Isolation
version=1.0
versionCode=1
author=<你的名字>
description=Exclude gamepads from Android input so Anland does not forward duplicate key events to the container
```

**post-fs-data.sh**：

```sh
#!/system/bin/sh
MODDIR=${0%/*}
chcon u:object_r:vendor_configs_file:s0 "$MODDIR/excluded-input-devices.xml" 2>/dev/null
mount --bind "$MODDIR/excluded-input-devices.xml" /vendor/etc/excluded-input-devices.xml
```

属性与标签：

```bash
chmod 644 /data/adb/modules/gamepad-isolate/module.prop \
           /data/adb/modules/gamepad-isolate/excluded-input-devices.xml
chmod 755 /data/adb/modules/gamepad-isolate/post-fs-data.sh
chcon u:object_r:vendor_configs_file:s0 /data/adb/modules/gamepad-isolate/excluded-input-devices.xml
```

原理：KernelSU/SukiSU 的 `post-fs-data` 阶段早于 zygote 和 system_server 启动，此时 `/vendor` 已挂载，bind mount 之后 InputManagerService 读到的就是新列表。

模拟测试（无需重启）：`umount /vendor/etc/excluded-input-devices.xml` 恢复原文件，再 `sh /data/adb/modules/gamepad-isolate/post-fs-data.sh` 看能否恢复条目。

---

## 四、开机后的自愈链路

本环境 `container.config` 中 `run_at_boot=0`，容器需要手动或用 DroidSpaces 应用启动。容器起来后：

1. `input-nodes.service`（容器内，已 enable）→ 2 秒内补出手柄节点并 chmod
2. `anland-session-autostart.service`（用户级）→ 自动起 gamescope + Steam
3. host 侧 `gamepad-isolate` 模块 → Android 忽略手柄，无键盘重复输入

不需要任何手动操作。

---

## 五、回退方法

| 想恢复 | 操作 |
|--------|------|
| Android 重新识别手柄 | 删除 `/data/adb/modules/gamepad-isolate`，重启手机；或 `umount /vendor/etc/excluded-input-devices.xml` 后 `stop; start` |
| 停止节点自动补建 | 容器内 `systemctl disable --now input-nodes.service` |
| 完全恢复原状 | 以上两项都做 |

---

## 六、已知代价与排错

**代价**：Android 系统本身不再识别这个手柄（手机上的 Android 游戏 / 界面用不了手柄），这是换取"容器内唯一输入路径"的必要代价。容器内不受影响。

**排错 checklist**：

| 症状 | 检查 |
|------|------|
| Steam 认不到手柄 | `ls /dev/input` 是否有节点；`systemctl status input-nodes.service`；`udevadm info /sys/class/input/eventN` 是否有 `ID_INPUT_JOYSTICK=1` |
| 仍有键盘重复输入 | `dumpsys -t 30 input` 看设备列表里是否还有手柄；`ExcludedDeviceNames` 是否包含手柄名；设备名是否与 `/proc/bus/input/devices` 完全一致 |
| 开机后排除失效 | `ls -Z /vendor/etc/excluded-input-devices.xml` 应为 `u:object_r:vendor_configs_file:s0`；模块是否被 SukiSU 禁用（有 `disable` 文件） |
| 手柄掉线不回来 | 蓝牙重连后 `/sys/class/input` 应重新出现 eventN；重连后重启一次游戏模式 |
| 个别键无效 | Steam → 设置 → 控制器，检查 Steam Input 映射 |

**相关文件速查**：

- 容器配置：`/data/local/Droidspaces/Containers/steamos/container.config`
- 节点补建脚本：容器内 `/usr/local/bin/input-nodes.sh`
- 节点服务：容器内 `/etc/systemd/system/input-nodes.service`
- 排除表：`/vendor/etc/excluded-input-devices.xml`（被模块 bind mount 覆盖）
- 模块：`/data/adb/modules/gamepad-isolate/`
- Steam 手柄日志：容器内 `/home/steamos/.steam/steam/logs/controller.txt`
