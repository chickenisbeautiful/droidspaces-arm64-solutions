# 性能面板与 Deck 模式

> 双语配对：[06-performance-hud-and-deck-mode.md](06-performance-hud-and-deck-mode.md)（英文）

常被叫做「性能面板」的其实是两件事：

1. **Steam 性能面板**（TDP / GPU 频率 / FPS 限制 / 性能 HUD）——只在 **Deck 模式** UI 里有。
2. **MangoHud 叠加层**——屏幕上真正显示的 HUD，由 gamescope 的 `--mangoapp` 驱动。

## 1. 开启 Deck 模式（性能面板）

`gamescope_steam.sh`：

```bash
exec steam -gamepadui -steamdeck -steamos3 -steampal -cef-enable-debugging "$@"
```

首次启动可能触发客户端切到 `steamdeck_*` 分支并更新（见
[文档 02](02-steam-versions-and-defects.zh-CN.md)）。**之后务必检查分支**，如果想要热插拔
正常就切回 `steamdeck_publicbeta`。

面板在快捷访问菜单里（PS/Xbox/Nintendo 的 guide 键 + A/×/B，或键盘 `Ctrl+2`）。

**在本设备上的实际表现**：TDP / GPU 频率滑块没有真实硬件可控（手机 SoC，不是掌机 APU）。
真正能用的是 FPS 限制和 HUD。

## 2. 开启 HUD（`--mangoapp`）

```bash
exec "$GAMESCOPE_BIN" --backend anland -f -e --mangoapp -- "$@"
```

`mangoapp`（`/usr/sbin/mangoapp`，来自 `mangohud` 包）负责绘制叠加层。验证：

```bash
pgrep -af mangoapp
```

截图上能看到屏幕顶部的 `FPS 50  [帧时间] GPU% ... CPU% ... BATT ...`。

## 3. 必须接受的取舍

启用 `--mangoapp` 后，一次会话里 gamescope 打了 **3607** 条警告：

```
[gamescope] [Error] wlserver: create_swapchain: Surface already had a gamescope_swapchain! Warning!
```

叠加层和 Steam UI 争抢同一个 swapchain，结果：

- HUD 能用。
- Steam UI 明显变卡，`SteamUI thread frame stalled` 警告更多。

**建议**：日常关闭 `--mangoapp`，只在需要给游戏测帧时开，用完立刻关：

```bash
sh scripts/remove-mangoapp.sh
```

## 4. 不开 Deck 模式的替代方案

只想在某个游戏里看帧率/温度，可以用每游戏的 MangoHud：

```
MANGOHUD=1 %command%
```

完全绕开 Deck 模式 UI，也不影响 Steam UI 的 swapchain。

## 5. 验证清单

```bash
# Deck 模式开了吗？
grep 'exec steam' /home/steamos/gamescope_steam.sh
# HUD 开了吗？
grep 'mangoapp' /home/steamos/gamescope_steam.sh
pgrep -af mangoapp
# 当前 Steam 分支（影响热插拔）
cat /home/steamos/.local/share/Steam/package/beta
# UI 健康度
grep -c GetState /home/steamos/.local/share/Steam/logs/console_log.txt
tail -20 /home/steamos/.local/share/Steam/logs/steamui.txt
```

## 6. 全部关掉

```bash
sh scripts/revert-deck-flags.sh   # 回到 -gamepadui -cef-enable-debugging
sh scripts/remove-mangoapp.sh     # 移除 --mangoapp
systemctl --user restart anland-game-mode
```
