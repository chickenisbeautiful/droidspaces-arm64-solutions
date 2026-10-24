# 排障记录（按时间顺序）

> 双语配对：[08-troubleshooting-log.md](08-troubleshooting-log.md)（英文）

下表每一行都是本次会话中真实遇到的问题及其解决方法。

| # | 现象 | 根因 | 修复 | 文档 |
|---|------|------|------|------|
| 1 | 容器里看不到手柄 | 容器 `/dev` 是独立 devtmpfs，节点不会自动出现 | `input-nodes.sh` 轮询 `/sys/class/input` 并 `mknod` | 01 |
| 2 | 重复按键（D-pad 变方向键） | Android 把手柄转发给 Anland | Magisk 模块 `gamepad-isolate` + `excluded-input-devices.xml` | 05 |
| 3 | 重启后节点丢失 | 服务没跑 / 僵尸节点 | `input-nodes.service` + 清理僵尸节点 | 01、04 |
| 4 | 触摸是模拟鼠标而非直触 | gamescope `touch_click_mode` 默认 `1`（左键） | 设 `STEAM_TOUCH_CLICK_MODE=4`（passthrough），用 `anland-touch-direct.service` 保持 | 06 |
| 5 | 有线 GameSir 只有方向键 | XInput 接口（`3537:1116`）没有驱动，只有键盘接口被绑定 | 用 PS 模式（`054c:09cc`）或蓝牙 | 01 |
| 6 | PS4 / PS 模式手柄识别不到 | event 节点缺失 + Steam 扫描竞态 | `input-nodes.sh` + `udevadm trigger` | 01 |
| 7 | Decky Loader 装不上 | 稳定版只提供 x86_64 `PluginLoader` | 用 `v3.3.0-pre1` 的 `PluginLoader-arm64` | 03 |
| 8 | 容器重启后 Decky 消失 | 自定义 unit 放在 `/etc/systemd/system`，systemd 首次扫描时 overlay 还没挂上 | unit + `wants` 软链放 `/usr/lib/systemd/system` | 04 |
| 9 | Deck 模式后 Steam 卡转圈 | `IClientSystemDisplayManager::GetState` 超时 + CEF transport 错误 + MangoApp swapchain 冲突 | 回退大屏幕、关掉 `--mangoapp`、修正分支（见 10） | 02、06 |
| 10 | 蓝牙手柄不能热插拔 | Steam 客户端从 `steamdeck_publicbeta` 切到了 `steamdeck_stable` | 恢复 `package/beta` = `steamdeck_publicbeta` | 02 |
| 11 | GameSir 反复重枚举 / 跳到 Switch Pro 模式 | Steam HIDAPI 读取导致复位（`hid_read failure`） | 强制 evdev：hidraw `chmod 660` | 01 |
| 12 | Steam 界面能用、游戏识别不到手柄 | `/dev/uinput` 是 `0600 root:root`，Steam 建不了虚拟 Xbox 手柄 | `chmod 666 /dev/uinput` | 01 |
| 13 | 热插拔有延迟 / 不稳定 | 2 秒轮询 + Steam 重扫 | 轮询改 0.5 秒 + 状态变化时 `udevadm trigger` | 01 |
| 14 | Anland 显示没有画面 | 手机锁屏 / 通知栏遮挡 SecondaryActivity | `cmd statusbar collapse`、`am start ...SecondaryActivity`、加大屏幕超时 | 04 |
| 15 | `systemctl is-system-running` 永远 `starting` | 手机专属服务（`qteesupplicant`、`sheng-devauth`、`xiaomi-sheng-thp`、`bluetooth`）卡住启动事务 | 在 `/usr/lib/systemd/system` 屏蔽 | 04 |
| 16 | `systemctl --user` 报连接失败 | 最后一个会话结束后用户管理器退出 | `loginctl enable-linger steamos` | 04 |
| 17 | 启动动画下载一直转圈 | Steam 客户端在更新 / 下载队列被占用；它是点数商店物品，不是创意工坊 | 等更新；点数商店购买后在设置里选中 | 07 |
| 18 | `steamloopback.host` transport 错误 | UI 线程被 display manager 超时拖死 | 去掉 Deck 模式后解决；域名本身已解析到 127.0.0.1 | 02 |
| 19 | 有线手柄被 Steam HIDAPI 打开后消失 | 同 11 | 同 11 | 01 |
| 20 | 容器重启后 PID 变化 | 正常；自定义 unit 每次开机都会在 `/usr/lib` 重建 | 无需处理 | 04 |

## 通用排查命令

```bash
# 宿主侧
su -c 'cat /proc/bus/input/devices'
su -c 'lsusb'
su -c 'dmesg' | grep -i usb
dumpsys usb | sed -n '/host_manager/,/}/p'
dumpsys window | grep mCurrentFocus

# 容器侧
droidspaces --name=steamos run ls -l /dev/input /dev/hidraw* /dev/uinput
droidspaces --name=steamos run cat /run/input-nodes.state
droidspaces --name=steamos run journalctl -t input-nodes -n 20
droidspaces --name=steamos run tail -30 /home/steamos/.local/share/Steam/logs/controller.txt
droidspaces --name=steamos run grep -c GetState /home/steamos/.local/share/Steam/logs/console_log.txt
droidspaces --name=steamos run systemctl --failed
```

## 最终状态验证

- `systemctl is-system-running` → `running`
- `systemctl --failed` → 0 个
- `plugin_loader.service` active，日志出现 `Loading Decky frontend!`
- `input-nodes.service` active，手柄相关 `/dev/input/eventN` 与 `/dev/uinput` 都是 `0666`
- Steam 通过 evdev（`/dev/input/eventN`）打开手柄，并创建 `Microsoft X-Box 360 pad N`
- Steam 分支是 `steamdeck_publicbeta`
