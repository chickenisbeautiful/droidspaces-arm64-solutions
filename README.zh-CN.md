# DroidSpaces ARM64 解决方案

> **⚠️ AI 生成仓库**
>
> 本仓库的全部文档、脚本和模块均由 AI 助手（**MiMo-V2.6-Pro / opencode**）于 2026-10-25
> 在真实硬件上的调试过程中生成，**未经人工独立审核**。执行任何命令前请自行验证。
> 详见 [DISCLAIMER.md](DISCLAIMER.md)。
>
> English version: [README.md](README.md)

面向 **SteamOS ARM64 容器（DroidSpaces）** 的双语文档与工具集。运行环境为一加 Ace 3
（骁龙 8 Gen 2 / Adreno 740）手机，Android + Magisk/SukiSU，容器内是 SteamOS ARM64。
同样的思路适用于任何 Linux/SteamOS-like 的 ARM64 环境。

## 内容索引

| # | 主题 | 位置 |
|---|------|------|
| 1 | **手柄识别与映射（核心）** | [docs/01-gamepad-mapping.zh-CN.md](docs/01-gamepad-mapping.zh-CN.md) |
| 2 | **Steam 各版本差别与缺陷（核心）** | [docs/02-steam-versions-and-defects.zh-CN.md](docs/02-steam-versions-and-defects.zh-CN.md) |
| 3 | ARM64 上安装 Decky Loader | [docs/03-decky-loader-arm64.zh-CN.md](docs/03-decky-loader-arm64.zh-CN.md) |
| 4 | 容器 systemd 与会话 | [docs/04-container-systemd.zh-CN.md](docs/04-container-systemd.zh-CN.md) |
| 5 | Magisk 输入隔离模块 | [docs/05-magisk-module.zh-CN.md](docs/05-magisk-module.zh-CN.md) |
| 6 | 性能 HUD / Deck 模式 | [docs/06-performance-hud-and-deck-mode.zh-CN.md](docs/06-performance-hud-and-deck-mode.zh-CN.md) |
| 7 | Steam 启动动画 | [docs/07-steam-startup-animation.zh-CN.md](docs/07-steam-startup-animation.zh-CN.md) |
| 8 | 排障记录 | [docs/08-troubleshooting-log.zh-CN.md](docs/08-troubleshooting-log.zh-CN.md) |

## 硬件 / 软件

- 手机：一加 Ace 3（PJE110），骁龙 8 Gen 2，Android，Magisk/SukiSU
- 容器：DroidSpaces，SteamOS ARM64 rootfs，NAT 网络，Anland 显示
- 测试手柄：
  - Xbox 无线手柄（蓝牙，内核名 `Xbox Wireless Controller`）
  - GameSir-X5 Lite（USB + 2.4G 接收器，内核名 `GameSir-X5 Lite`，VID:PID `3537:1116`）
  - 多模手柄 PS 模式（`054c:09cc`，DS4）
- Steam：ARM64 客户端（`steamrtarm64/steam`）、Proton 11.0 (ARM64)、Steam Input、Decky Loader
- Gamescope 3.16.28-anland-experimental（定制 ARM64 版）

## 目录结构

```
README.md / README.zh-CN.md      中英双语概述
DISCLAIMER.md                    AI 生成声明
docs/                            双语文档（EN + .zh-CN）
scripts/                         脚本与一个 C 辅助程序
services/                        systemd unit 文件
magisk-module/gamepad-isolate/   Android 侧输入隔离模块
screenshots/                     调试过程中的截图
```

## 快速开始

**容器内**（SteamOS 容器）：

```bash
cp scripts/input-nodes.sh /usr/local/bin/input-nodes.sh
cp services/input-nodes.service /etc/systemd/system/
# 注意：自定义 unit 必须放在 /usr/lib/systemd/system（见文档 04）
cp services/plugin_loader.service /usr/lib/systemd/system/
ln -sf /usr/lib/systemd/system/plugin_loader.service \
       /usr/lib/systemd/system/multi-user.target.wants/plugin_loader.service
systemctl daemon-reload
systemctl enable --now input-nodes plugin_loader
```

**Android 侧**（Magisk/SukiSU 模块）：见
[magisk-module/gamepad-isolate/](magisk-module/gamepad-isolate/)。它把
`excluded-input-devices.xml` bind-mount 覆盖到 `/vendor/etc/excluded-input-devices.xml`，
让 Android InputManager 忽略手柄，避免 Anland 转发重复按键。

## 核心结论

1. **ARM64 容器的热插拔很脆弱。** 容器 `/dev` 是独立 devtmpfs，udev 又在独立 netns，
   收不到宿主内核的热插拔 uevent。`input-nodes.sh` 通过轮询 `/sys/class/input` 并
   `mknod` 补齐节点来弥补。见文档 01。
2. **`/dev/uinput` 必须 0666**，否则以普通用户运行的 Steam 无法创建 Proton/Wine 游戏
   需要的虚拟手柄。
3. **不要让 Steam 的 HIDAPI 打开某些手柄。** GameSir-X5 Lite 被 HIDAPI 读取会导致设备
   复位/切模式；把它的 `hidraw` 保持 0660 强制走 evdev 后稳定。
4. **Steam 分支很重要。** `steamdeck_publicbeta` 与 `steamdeck_stable` 在 ARM64 上的
   手柄热插拔行为不同。见文档 02。
5. **Deck 模式在 ARM64 上有真实缺陷。** `--mangoapp` 与 Steam UI 抢 swapchain；
   `IClientSystemDisplayManager::GetState` 会拖垮 UI 线程。见文档 02 和 06。

## 截图

见 [screenshots/](screenshots/)。包含 Steam 大屏幕、Deck UI 转圈、MangoHud 叠加层、
锁屏失败画面，以及调试过程中用到的 DroidSpaces 容器面板。

## 许可 / 免责

风险自负。未授予任何超出个人使用范围的许可，材料按现状提供。
