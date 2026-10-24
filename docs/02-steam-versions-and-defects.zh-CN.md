# ARM64 上 Steam 客户端版本与缺陷

> 双语配对：[02-steam-versions-and-defects.md](02-steam-versions-and-defects.md)（英文）

本文所有内容都是在 **SteamOS ARM64 容器**（DroidSpaces）上实测得到：ARM64 Steam 客户端
（`steamrtarm64/steam`）+ Proton 11.0 (ARM64)。会话中反复启停 Deck 模式，每次改动都在
手柄热插拔和 UI 启动速度上产生了可测量的差异。

---

## 1. 观察到的分支与构建

| 分支 | manifest 名 | 构建号 | 热插拔表现 |
|------|-------------|--------|-----------|
| `steamdeck_publicbeta` | `steam_client_steamdeck_publicbeta_linuxarm64` | **1792192922**（原始）/ 1792711043（后期） | **蓝牙热插拔正常** |
| `steamdeck_stable` | `steam_client_steamdeck_stable_linuxarm64` | 1792618285 | **回归：蓝牙热插拔失效** |
| （普通 public） | `steam_client_linuxarm64` | — | 本设备未使用 |

### 分支保存在哪

```
~/.local/share/Steam/package/beta
```

一个纯文本文件，内容就是分支名，例如 `steamdeck_publicbeta`。

- **删掉文件** → 客户端回退到平台默认；在这套 ARM64 SteamOS 镜像上默认是
  `steamdeck_stable`。
- **写回分支名** → 回到 `steamdeck_publicbeta`。

切换分支会触发约 **500 MB** 的客户端下载 + 自更新 + 重启。Deck 模式实验时就是这样切走
的，这也是热插拔回归最可能的原因。

### 查看方法

```bash
cat /home/steamos/.local/share/Steam/package/beta
grep -n steam_client_ /home/steamos/.local/share/Steam/logs/bootstrap_log.txt
grep "Client version" /home/steamos/.local/share/Steam/logs/steamui.txt
```

---

## 2. 启动参数

### Steam 客户端（`gamescope_steam.sh`）

| 参数 | 作用 |
|------|------|
| `-gamepadui` | 大屏幕 / 手柄 UI |
| `-cef-enable-debugging` | 打开 CEF 远程调试端口（`8080`），**Decky Loader 依赖它** |
| `-steamdeck` | 启用 Steam Deck UI（Deck 模式） |
| `-steamos3` / `-steampal` | 启用 SteamOS 专属集成（display manager、PAM），Deck UI 使用 |

Deck 模式之前的可用配置：

```bash
exec steam -gamepadui -cef-enable-debugging "$@"
```

为性能面板测试过的 Deck 模式配置：

```bash
exec steam -gamepadui -steamdeck -steamos3 -steampal -cef-enable-debugging "$@"
```

### Gamescope（`--backend anland`）

| 参数 | 作用 |
|------|------|
| `--mangoapp` | 启动 MangoHud 叠加层，提供 Steam 性能 HUD |
| `--default-touch-mode` | `0` hover、`1` 左键、`2` 右键、`3` 中键、`4` passthrough（直触） |

实测使用过的行：

```bash
exec "$GAMESCOPE_BIN" --backend anland -f -e --mangoapp -- "$@"
```

去掉 `--mangoapp`，HUD 会消失，但 UI 稳定性明显更好。

---

## 3. ARM64 上观察到的缺陷

### 3.1 SteamUI 线程卡顿（5–58 秒）

`logs/steamui.txt`：

```
[01:51:16] Warning: SteamUI thread frame stalled for: 6220 ms
[01:24:42] Warning: SteamUI thread frame stalled for: 5205 ms
[00:58:43] Warning: SteamUI thread frame stalled for: 58097 ms
```

Deck/大屏幕 UI 的首帧在 ARM64 上要 **1–2 分钟**才出现。不是网络问题（manifest 下载是
HTTP 200），转圈也不是死锁，UI 最终能进。

### 3.2 `IClientSystemDisplayManager::GetState took too long`

`logs/console_log.txt` 出现 **3609 次**，每次约 50 ms：

```
IPC function call IClientSystemDisplayManager::GetState took too long: 50 msec
```

Deck UI 会向 SteamOS 的 **display manager** 查询显示/刷新率/性能信息。在这个容器里，
Valve 原版 `steamos-manager` 被 Anland 会话 broker 替代，定制 gamescope 也没实现对应接口
→ 调用超时，UI 线程被拖死。这是 Deck 模式在这里「卡到没法用」的主因。

### 3.3 CEF `Transport Error`（steamloopback.host）

`logs/cef_log.txt`：

```
Uncaught (in promise) Transport Error: no transport is available for request
source: https://steamloopback.host/index.html?...ARCH=arm64...IS_STEAMOS=true&ON_STEAMOS_CLIENT_BRANCH=true&IN_GAMESCOPE=true
```

说明：

- `steamloopback.host` 是 Steam 私有环回域名，解析到 `127.0.0.1`（systemd-resolved 或
  `/etc/hosts`），**不是 DNS 问题**。
- 「no transport」是 UI 线程被阻塞（见 3.2）的症状，不是解析失败。
- 如果真遇到解析问题，把下面一行加进 `/etc/hosts`：
  ```
  127.0.0.1 steamloopback.host
  ```

### 3.4 MangoApp 与 swapchain 冲突

启用 `--mangoapp` 后，gamescope 打了 **3607** 条：

```
[gamescope] [Error] wlserver: create_swapchain: Surface already had a gamescope_swapchain! Warning!
[Gamescope WSI] Created swapchain for xid: ... Destroyed swapchain: ...
```

叠加层和 Steam UI 抢同一个 swapchain，UI 卡顿更严重。**取舍**：MangoHud 有 HUD，但 UI 响应
明显变差。

### 3.5 Deck UI 启动

即使一切正常，Deck UI 的转圈在这套硬件上也可能持续 **1–2 分钟**。卡住时的恢复方法：
`pkill -9 -f steamrtarm64/steam` 然后重启 game-mode 会话
（`systemctl --user restart anland-game-mode`）。客户端更新期间反复 kill 是安全的，
bootstrap 会校验和修复。

---

## 4. 手柄热插拔回归依赖分支

| | `steamdeck_publicbeta` | `steamdeck_stable` |
|--|------------------------|--------------------|
| 蓝牙手柄重连被识别 | 是（0.5 秒轮询 + 触发） | **否**，除非插一次 USB 手柄强制重扫 |
| 断开时 `controller.txt` | `Controller device closed after hid_read failure` | 同样 |
| 重连后 | `Local Device Found` / `PollState 2` | **没有任何记录**，残留 `eventN (deleted)` 旧 fd |

排障时的实验证据：

1. 把 `/dev/input/event10` 改名成 `event20`，Steam 仍持有 `event10 (deleted)`，从不打开新路径。
2. 新建 **uinput** 设备能让 Steam 立刻扫描（秒开新节点）。
3. 插拔一次 USB 手柄会强制全量重扫——这就是「插拔有线手柄」能救回蓝牙手柄的原因。

结论：`steamdeck_stable` 上，Steam 的 SDL 热插拔无法恢复「复用原 event 号」的蓝牙手柄；
`steamdeck_publicbeta` 行为正常。

---

## 5. 启动动画

见 [07-steam-startup-animation.zh-CN.md](07-steam-startup-animation.zh-CN.md)。

简述：启动动画是**点数商店**物品（如「特别快递」，3000 点数），不是创意工坊下载。购买后在
设置 → 自定义 → 启动动画 中选中，Steam 会自动下载影片。

---

## 6. 恢复手册

```bash
# 1. kill 卡住的 Steam 客户端
droidspaces --name=steamos run pkill -9 -f steamrtarm64/steam
droidspaces --name=steamos run pkill -9 -f steamwebhelper

# 2. 重启会话（同时重启 MangoApp / Decky 注入）
droidspaces -n steamos -u steamos run env XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user restart anland-game-mode.service

# 3. 切换 Steam 分支
droidspaces --name=steamos run sh -c 'echo steamdeck_publicbeta > /home/steamos/.local/share/Steam/package/beta'
```

常用检查：

```bash
# 当前分支 + 构建
droidspaces --name=steamos run cat /home/steamos/.local/share/Steam/package/beta
droidspaces --name=steamos run grep "Client version" /home/steamos/.local/share/Steam/logs/steamui.txt | tail -1
# UI 卡住状态
droidspaces --name=steamos run tail -20 /home/steamos/.local/share/Steam/logs/steamui.txt
droidspaces --name=steamos run grep -c GetState /home/steamos/.local/share/Steam/logs/console_log.txt
```

---

## 7. 实用建议

1. 这套 ARM64 容器上**保持 `steamdeck_publicbeta`** 分支。
2. 日常用**大屏幕**（`-gamepadui`），比 Deck 模式快。
3. 只在确实需要性能面板时才开 Deck 模式，并接受 1–2 分钟启动和 `GetState` 卡顿。
4. 不需要 HUD 就别开 `--mangoapp`，它会拖慢 UI。
5. Steam 更新后，先验证一次手柄热插拔再进游戏。
