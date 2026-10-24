# Steam 启动动画（开机动画）

> 双语配对：[07-steam-startup-animation.md](07-steam-startup-animation.md)（英文）

## 1. 它到底是什么

启动动画（开机动画）是 **Steam 点数商店**物品，**不是**创意工坊物品。国内最知名的是
*Special Delivery* /「特别快递」，价格 **3000 Steam 点数**。

不存在「创意工坊下载」这回事。正确流程：

1. 打开**点数商店** → **启动动画**。
2. 用 Steam 点数购买 / 兑换。
3. 进入**设置 → 自定义 → 启动动画**（大屏幕或 Deck UI）。
4. 选中动画，Steam 会自动下载影片文件。

之后 `config/config.vdf` 里会出现：

```
"StartupMovie"
{
    "MovieID"   "0"      // 0 = 未选择
}
```

在真正选中之前，本地不会有 `config/movies` 目录，也没有任何 workshop 内容。

## 2. 「一直转圈」的排查

点数商店页面是 Steam CEF 里的一个网页，转圈可能是因为：

- Steam 客户端正在**后台更新**（看 `logs/bootstrap_log.txt` 里的
  `Downloading manifest` / `正在展开安装包`）。
- 网络/CDN 慢。本设备走国内 CDN（`dl.steam.clngaa.com`、`xz.pphimalayanrt.com`），
  下载本身是 HTTP 200。
- 下载队列被大游戏占用（Steam 会让小文件排在大文件后面，见下载页面）。

检查清单：

```bash
tail -20 /home/steamos/.local/share/Steam/logs/bootstrap_log.txt
tail -20 /home/steamos/.local/share/Steam/logs/content_log.txt
grep -i "StartupMovie" /home/steamos/.local/share/Steam/config/config.vdf
```

## 3. 文件存哪里

选中之后，Steam 会把影片存放在 Steam 安装目录（具体路径随客户端版本变化）。权威记录在
`config.vdf`（`StartupMovie` → `MovieID`）。

## 4. 与 Deck 模式的关系

该设置在 Steam UI 的自定义页面里。**Deck 模式**下属于 Deck UI 的一部分，**大屏幕**下在
设置 → 自定义。两者都能用，只是 ARM64 上 Deck 模式很慢（见
[文档 02](02-steam-versions-and-defects.zh-CN.md)）。

## 5. 排查速查表

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| 点数商店页面一直转圈 | 客户端更新 / 网络慢 | 等更新；看 `bootstrap_log` |
| 已购买但列表里没有 | 还没选中 | 设置 → 自定义 → 启动动画 |
| 什么都没下载 | 下载队列被游戏占用 | 暂停游戏下载后重试 |
| 影片无法播放 | ARM64 上编解码/CEF 问题 | 重启 Steam；仍不行就换短一点的 WebM |
