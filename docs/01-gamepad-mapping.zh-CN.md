# ARM64 SteamOS 容器上的手柄识别与映射

> 双语配对：[docs/01-gamepad-mapping.md](01-gamepad-mapping.md)（英文）

这是本仓库**最详细**的一篇。它解释一个手柄如何从 Android 的蓝牙/USB 连接，一路到 Proton 里
运行的 Windows 游戏；每一层在这套 ARM64 环境里会坏在哪里，以及实际应用的修复方法。

---

## 1. 「识别」其实是三层互相独立的机制

| 层 | 位置 | 匹配规则 | 作用 |
|----|------|----------|------|
| 1. Android 排除表 | `/vendor/etc/excluded-input-devices.xml` | **精确全名匹配** | 让 Android InputManager 忽略手柄，避免 Anland 把按键重复转发进容器 |
| 2. 容器节点管理 | 容器内 `input-nodes.sh` | **关键词 / 通配符**匹配内核输入设备名 | 创建 `/dev/input/eventN` 并 `chmod 666`，让 Steam/Proton 能打开 |
| 3. Steam / SDL / Steam Input | 容器内 | VID:PID + SDL 映射 + `uinput` | 识别手柄，并为游戏创建虚拟 Xbox 手柄 |

判断「手柄没识别」时，第一步就是确定**是哪一层**没过。

---

## 2. 第一层：Android 侧（精确全名）

### 2.1 Android 如何看到设备

蓝牙配对由 Android 蓝牙栈完成（按 MAC）。连接成功后内核创建输入设备，名字就是 HID
上报的**产品字符串**：

```
/sys/class/input/eventN/device/name = "Xbox Wireless Controller"
```

### 2.2 排除表

`/data/adb/modules/gamepad-isolate/excluded-input-devices.xml`：

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

**规则：**

- 匹配是**精确、区分大小写**的。这里写 `*Xbox*` **无效**，必须整串一致。
- 只影响 Android 的 InputManagerService，不影响内核、容器和 Steam。
- InputManagerService **只在开机读一次**。改完后需要软重启（`su -c 'stop; start'`）
  或重启手机才生效。

### 2.3 为什么需要这一层

没有它，Android 会把每个手柄按键当作 key event 转发给 Anland，容器里同一个输入会
**出现两次**（一次来自内核 evdev，一次来自 Anland 键盘转发）——这就是「重复输入」症状。

### 2.4 精确名字示例

| 手柄 | 需要加入的名字 |
|------|----------------|
| Xbox 蓝牙（XInput） | `Xbox Wireless Controller` |
| GameSir-X5 Lite | `GameSir-X5 Lite` |
| DS4 / PS 模式 | `Sony Computer Entertainment Wireless Controller`（另加两个传感器设备） |
| Steam 虚拟手柄 | `Steam Virtual Gamepad` |
| 通用 360 克隆 | `Microsoft X-Box 360 pad`（以及 `Microsoft X-Box 360 pad 0`..`3`） |

**注意**：排除表用精确全名；品牌关键词（见第 4 节）是给容器脚本用的，加进 XML 无效。
加新名字前在手机上执行：

```bash
su -c 'cat /proc/bus/input/devices' | grep 'N: Name='
```

把字符串**原样**复制进 XML。

---

## 3. 第二层：容器侧（`input-nodes.sh`）

### 3.1 为什么需要脚本

容器有**自己的** `/dev`（独立 `devtmpfs`，`stat -c %d` 与宿主不同），而且
`systemd-udevd` 跑在**独立 netns**。内核热插拔 uevent 只广播给 init netns，容器 udev
收不到。结果是：

- 新设备的节点**不会**自动出现；
- `/run/udev/data/*` 不会为热插拔设备更新（只有启动时的冷插拔）。

脚本靠轮询 `/sys/class/input`（这个**是**与宿主共享的）来补建容器 `/dev/input` 的节点。

### 3.2 每 0.5 秒做的事

1. 扫描 `/sys/class/input/event*`。
2. 读 `/sys/class/input/eventN/device/name`。
3. 命中**关键词表**（或 udev 数据 `ID_INPUT_JOYSTICK=1`）就 `mknod /dev/input/eventN`，
   然后 `chmod 666`。
4. 删除 sysfs 已消失的僵尸节点（僵尸节点会让 Steam 枚举到死 fd）。
5. 处理同设备的 `hidraw` 节点（见 3.5）。
6. `chmod 666 /dev/uinput`（见 3.4）。
7. 维护 `/run/input-nodes.state`（**物理**手柄 event 号集合）。集合变化时（手柄插拔），
   对所有手柄节点执行 `udevadm trigger --action=add`，让 Steam 有机会重扫。

### 3.3 关键词匹配

`is_gamepad()` 用 shell `case` 通配，**区分大小写**，子串匹配（`*关键词*`）：

```bash
is_gamepad() {
  case "$1" in
    # Xbox / PlayStation / Nintendo 模式与通用名
    *Xbox*|*X-Box*|*X-BOX*|*Microsoft*|*Controller*|*Gamepad*|*Joystick*|*"2.4G"*|*"Wireless Controller"*|*DualSense*|*DualShock*|*Sony*|*Nintendo*|*"Switch Pro"*|*"Pro Controller"*)
      return 0 ;;
    # 国产品牌
    *GameSir*|*Flydigi*|*VADER*|*APEX*|*Direwolf*|*BETOP*|*BTP-*|*Beitong*|*KunPeng*|*Pangu*|*Asura*|*Sparta*)
      return 0 ;;
    *ShanWan*|*8BitDo*|*BIGBIG*|*Machenike*|*IINE*|*Ajazz*|*Dareu*|*Rapoo*|*Thunderobot*|*RedMagic*|*"Black Shark"*)
      return 0 ;;
    # 国外品牌
    *Razer*|*Wolverine*|*Kishi*|*Logitech*|*SteelSeries*|*Stratus*|*Nimbus*|*PowerA*|*PDP*|*HORI*|*Nacon*|*SCUF*|*"Turtle Beach"*|*Thrustmaster*)
      return 0 ;;
  esac
  return 1
}
```

说明：

- 匹配的是**内核名**，内核名永远是英文产品串；飞智/北通/盖世小鸡/山弯这些中文名
  不会出现在设备名里，所以关键词用英文品牌与产品线。
- `is_physical_gamepad()` 会把 Steam 自己的虚拟手柄（`Microsoft X-Box 360 pad*`、
  `Steam Virtual Gamepad`）排除在状态触发之外，避免重扫循环；但这些节点仍然 `chmod 666`，
  游戏可以打开。

### 3.4 `/dev/uinput` 必须 0666

Steam Input 用 `uinput` 创建**虚拟 Xbox 手柄**（`Microsoft X-Box 360 pad 0`），这是
Proton/Wine 游戏看到的设备。如果 `/dev/uinput` 是 `0600 root:root`，以普通用户 `steamos`
运行的 Steam 创建不了它，游戏就看不到手柄——而 Steam 界面却能正常用（界面直接读物理
evdev）。症状就是「**Steam 界面能操作，游戏识别不到**」。修复：`chmod 666 /dev/uinput`
（脚本强制执行）。

### 3.5 hidraw 与 evdev：GameSir 的坑

- `evdev`（`/dev/input/eventN`）是传统 Linux 输入通道。
- `hidraw` 被 Steam 的 **HIDAPI** 后端使用，能读写 HID feature 报文，很多手柄下 Steam
  优先用它。

**GameSir-X5 Lite** 上这条路径出了问题：Steam 的 HIDAPI 读取会导致设备重新枚举、在
模式间跳变（`3537:1116` GameSir ↔ `057e:2009` Switch Pro），Steam 日志出现
`Controller device closed after hid_read failure`。修复是**禁止** Steam 打开 GameSir 的
hidraw：

```bash
chown root:input /dev/hidrawN
chmod 660 /dev/hidrawN      # steamos 打不开 → SDL 退化为 evdev
```

其它品牌的 hidraw 保持 `0666`；只有 `*GameSir*` 强制走 evdev。

### 3.6 状态触发（热插拔）

光创建节点**不够**：Steam 的 SDL 在设备断开后不会自动重扫。实验证据：

- 把 `/dev/input/event10` 改名成 `event20`，Steam 仍持有 `event10 (deleted)` 旧 fd，
  从不打开 `event20`。
- 新建一个 **uinput** 设备却能让 Steam 立刻扫描（打开了新节点）。
- 插一次 USB 手柄会强制全量重扫——这就是「插拔有线手柄」能救回蓝牙手柄的原因。

因此脚本用 `/run/input-nodes.state` 跟踪物理手柄集合，集合变化时对所有手柄节点执行
`udevadm trigger --action=add`。配合 0.5 秒轮询，总热插拔延迟约：

| 阶段 | 时间 |
|------|------|
| 蓝牙重连 | 1–2 秒 |
| 节点创建（轮询） | ≤ 0.5 秒 |
| Steam 控制器重扫 | 1–2 秒 |
| **总计** | **约 2–4 秒** |

### 3.7 有线 GameSir-X5 Lite 的 USB 枚举缺陷

手机上该手柄枚举成 `3537:1116`（GameSir），并反复断开重连。针对同类 GameSir 手柄的内核
补丁说明了原因：手柄**根据主机读取配置描述符的方式**选择 XInput 还是 DInput；没有
`USB_QUIRK_WINDOWS_CONFIG_REQ_SIZE` 这类 quirk 时就会不断复位。手机原厂内核没有该 quirk，
`xpad` 也不支持 `3537:1116`，所以：

- Xbox 模式在手机上基本不可用（XInput 接口没有驱动）；
- PS/DS4 模式（`054c:09cc`）可用；
- 禁止 Steam 的 HIDAPI 打开 GameSir 的 hidraw 后，复位循环消失。

---

## 4. 关键词与真实名称对照表

| 品牌 | 内核/蓝牙名 | 脚本关键词 |
|------|-------------|-----------|
| 飞智 Flydigi | `Flydigi VADER3/4/5`、`FLYDIGI APEX 5`、`Flydigi Direwolf` | `Flydigi` `VADER` `APEX` `Direwolf` |
| 盖世小鸡 GameSir | `GameSir-X5 Lite`、`GameSir-Nova 2 Lite`、`GameSir G7 SE`、`GameSir Cyclone 2` | `GameSir` |
| 北通 BETOP | `BETOP BTP-2585`、`BETOP KunPeng 40` | `BETOP` `BTP-` `Beitong` `KunPeng` `Pangu` `Asura` `Sparta` |
| 山弯 ShanWan | `ShanWan Wireless Gamepad` | `ShanWan` |
| 八位堂 8BitDo | `8BitDo Pro 2`、`8BitDo Ultimate`、`8BitDo SN30 Pro` | `8BitDo` |
| 墨将 BIGBIG WON | `BIGBIG WON Rainbow 2`、`BIGBIG WON Ovari` | `BIGBIG` |
| 机械师 Machenike | `Machenike G5 Pro` | `Machenike` |
| 良值 IINE | `IINE ...` | `IINE` |
| 黑爵 / 达尔优 / 雷柏 | `Ajazz ...`、`Dareu ...`、`Rapoo ...` | `Ajazz` `Dareu` `Rapoo` |
| 雷神 / 红魔 / 黑鲨 | `Thunderobot ...`、`RedMagic ...`、`Black Shark ...` | `Thunderobot` `RedMagic` `Black Shark` |
| Microsoft | `Xbox Wireless Controller`、`Microsoft X-Box 360 pad 0`、`Xbox One/Series X Controller` | `Xbox` `X-Box` `X-BOX` `Microsoft` |
| Sony | `Sony Computer Entertainment Wireless Controller`、`Wireless Controller`、`DualSense Wireless Controller` | `Sony` `DualSense` `DualShock` |
| Nintendo | `Pro Controller`、`Nintendo Switch Pro Controller` | `Nintendo` `Switch Pro` `Pro Controller` |
| Razer | `Razer Wolverine V2`、`Razer Kishi` | `Razer` `Wolverine` `Kishi` |
| Logitech / SteelSeries | `Logitech Gamepad F710`、`SteelSeries Stratus Duo` | `Logitech` `SteelSeries` `Stratus` `Nimbus` |
| PowerA / PDP / Hori / Nacon / SCUF / Turtle Beach / Thrustmaster | 对应产品名 | `PowerA` `PDP` `HORI` `Nacon` `SCUF` `Turtle Beach` `Thrustmaster` |
| 通用 | 任意含 `Controller` / `Gamepad` / `Joystick` / `2.4G` / `Wireless Controller` 的名字 | 这些词 |

用 `scripts/test-keywords.sh` 验证：

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

## 5. 故障现象与修复对照表

| 现象 | 根因 | 修复 |
|------|------|------|
| Steam 界面能操作，游戏识别不到 | `/dev/uinput` 是 `0600 root:root`，Steam 建不了虚拟手柄 | `chmod 666 /dev/uinput`，脚本强制 |
| 启动时正常，热插拔后失效 | Steam 持有已删除的旧 fd；容器 udev 收不到 uevent | 0.5 秒轮询 + 状态触发 `udevadm trigger`；更稳妥：先连手柄再启动 Steam，或重启会话 |
| GameSir 反复断开 / 跳到 Switch Pro 模式 | Steam HIDAPI 读取导致复位（`hid_read failure`） | 强制 evdev：hidraw 改 `chmod 660` |
| 容器里重复按键 | Android 把手柄转发给 Anland | 排除表加精确全名 + 软重启 |
| `/proc/bus/input/devices` 有，容器里没有 | 容器 `/dev` 是独立 devtmpfs | `input-nodes.sh` mknod |
| 有线 2.4G Xbox 接收器只有方向键 | XInput 接口无驱动（`3537:1116`），只有键盘接口被绑定 | 用 PS 模式（`054c:09cc`）或蓝牙 |
| Steam 日志随机 `hid_read failure` | 手柄在 Steam 底下重新枚举 | 同 GameSir 修复；并检查线材/供电（OTG 500mA 上限） |

---

## 6. 加新手柄的步骤

1. 手机上：
   ```bash
   su -c 'cat /proc/bus/input/devices' | grep 'N: Name='
   ```
2. 容器脚本：名字没有关键词就在 `scripts/input-nodes.sh` 的 `is_gamepad()` 加一条，
   然后 `systemctl restart input-nodes`。
3. Android 排除表：把**精确**名字加进 Magisk 模块的 `excluded-input-devices.xml`，
   然后软重启（`su -c 'stop; start'`）。
4. 验证：
   ```bash
   ls -l /dev/input
   cat /run/input-nodes.state
   tail -f /home/steamos/.local/share/Steam/logs/controller.txt
   ```

---

## 7. 脚本

完整源码：[scripts/input-nodes.sh](../scripts/input-nodes.sh)

服务文件：[services/input-nodes.service](../services/input-nodes.service)
