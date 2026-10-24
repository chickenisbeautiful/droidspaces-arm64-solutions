# 容器 systemd 与会话管理

> 双语配对：[04-container-systemd.md](04-container-systemd.md)（英文）

容器里跑着完整 systemd。本仓库其它内容之所以必要，基于两个事实：

1. 容器内 `/etc` 是 **overlay 挂载**。
2. 容器的 `systemd-udevd` 跑在**独立 netns**（见文档 01）。

---

## 1. `/etc` overlay 问题

```
devtmpfs on /dev type devtmpfs ...
overlay on /etc type overlay (lowerdir=/etc, upperdir=/var/lib/overlays/etc/upper ...)
```

systemd 在 **overlay 可见之前**就完成了首次 unit 扫描。结果：放在 `/etc/systemd/system/` 的
自定义 unit 对启动事务不可见，只有 `systemctl daemon-reload` 之后（或下次 boot）才会被加载。

症状：

```
systemctl is-enabled my-unit     -> enabled
systemctl is-active my-unit      -> inactive (dead)
systemctl show my-unit -p WantedBy -> (空)
```

**修复**：把自定义 unit 和 `multi-user.target.wants` 软链放到 `/usr/lib/systemd/system`，
它在 rootfs 上，开机一定可见。

---

## 2. 屏蔽手机专属服务

SteamOS ARM64 镜像带了一些硬件服务，在容器里无法工作，还把启动事务卡住
（`systemctl list-jobs` 里永远有任务）：

| unit | 问题 |
|------|------|
| `qteesupplicant.service` | `After=dev-tee0.device`；容器里 `/dev/tee0` 永远不出现 |
| `sheng-devauth.service` | 小米 DevAuth；`After=qteesupplicant`、`WantedBy=sysinit.target` |
| `xiaomi-sheng-thp.service` | 小米触控处理；重启风暴（观察到 150 次） |
| `bluetooth.service` | 容器里 bluetoothd 拿不到 mgmt 接口 |

后果：`systemctl is-system-running` 永远停在 `starting`，重启循环白白烧 CPU。

屏蔽（保留备份）并 reload：

```bash
cd /usr/lib/systemd/system
for u in qteesupplicant sheng-devauth xiaomi-sheng-thp bluetooth; do
  [ -f "$u.service" ] && cp -a "$u.service" "$u.service.droidspaces-backup"
  ln -sf /dev/null "$u.service"
done
systemctl daemon-reload
systemctl reset-failed
```

脚本：[scripts/mask-phone-units.sh](../scripts/mask-phone-units.sh)

结果：`systemctl is-system-running` → `running`，`systemctl --failed` → 0 个。

---

## 3. 用户管理器与 linger

用户管理器退出后 `systemctl --user` 会报
"Failed to connect to user scope bus"。修复：

```bash
loginctl enable-linger steamos
systemctl start user@1000.service
```

这样即使没有用户会话，用户管理器（以及 `anland-game-mode`、`anland-touch-direct`、
`steamos-manager`）也不会退出。

---

## 4. 本次使用过的 unit

| unit | 作用 | 位置 |
|------|------|------|
| `plugin_loader.service` | Decky Loader（ARM64） | `/usr/lib/systemd/system` |
| `input-nodes.service` | 维护 `/dev/input` + `/dev/uinput` | `/usr/lib/systemd/system` |
| `anland-touch-direct.service` | 让 gamescope 保持触控 passthrough | 用户 unit（`~/.config/systemd/user`） |
| `anland-game-mode.service` | gamescope + Steam 大屏幕会话 | 用户 unit |
| `steamos-manager.service` | Anland 会话 broker | 用户 unit（替代 Valve 原版） |

文件：[services/](../services/)

---

## 5. `gamescope_steam.sh` 补丁

该脚本同时驱动 gamescope 和 Steam。本次会话中的改动：

| 改动 | 行 | 原因 |
|------|----|------|
| 加 `-cef-enable-debugging` | `exec steam -gamepadui -cef-enable-debugging "$@"` | Decky 需要 CEF 调试端口 |
| 加 `-steamdeck -steamos3 -steampal` | 同上 | 启用 Deck UI + 性能面板（仅需要时） |
| 加 `--mangoapp` | `exec "$GAMESCOPE_BIN" --backend anland -f -e --mangoapp -- "$@"` | MangoHud HUD（仅需要时） |

日常可用配置（大屏幕、无 HUD）：

```bash
exec steam -gamepadui -cef-enable-debugging "$@"
exec "$GAMESCOPE_BIN" --backend anland -f -e -- "$@"
```

补丁脚本：[scripts/fix-steam-cef.sh](../scripts/fix-steam-cef.sh)、
[scripts/patch-performance.sh](../scripts/patch-performance.sh)、
[scripts/enable-deck-flags.sh](../scripts/enable-deck-flags.sh)、
[scripts/revert-deck-flags.sh](../scripts/revert-deck-flags.sh)、
[scripts/remove-mangoapp.sh](../scripts/remove-mangoapp.sh)。

---

## 6. Android 侧会话前提

- Anland 的**显示活动**（`com.anland.consumer/.SecondaryActivity`）必须在前台。手机锁屏或
  通知栏遮挡都会让 surface 被销毁，gamescope 就不会启动 Steam：
  ```
  dumpsys window | grep mCurrentFocus
  ```
  恢复：
  ```bash
  adb shell cmd statusbar collapse
  adb shell am start -n com.anland.consumer/.SecondaryActivity --activity-reorder-to-front
  ```
- 屏幕超时改为 30 分钟、`stay_on_while_plugged_in=7`：
  ```bash
  su -c 'settings put system screen_off_timeout 1800000'
  su -c 'settings put global stay_on_while_plugged_in 7'
  ```

---

## 7. 恢复手册

```bash
# kill 卡死的 Steam 并重启会话
droidspaces --name=steamos run pkill -9 -f steamrtarm64/steam
droidspaces --name=steamos run pkill -9 -f steamwebhelper
droidspaces -n steamos -u steamos run env XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user restart anland-game-mode.service

# 检查启动健康度
droidspaces --name=steamos run systemctl is-system-running
droidspaces --name=steamos run systemctl --failed
droidspaces --name=steamos run systemctl list-jobs
```
