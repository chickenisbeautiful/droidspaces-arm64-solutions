# ARM64 上安装 Decky Loader

> 双语配对：[03-decky-loader-arm64.md](03-decky-loader-arm64.md)（英文）

## 1. 官方安装脚本为什么在这里不行

官方 Decky 安装器会从 GitHub 最新 release 下载 `PluginLoader` 二进制。稳定版 release 只提供
**x86_64** 的 `PluginLoader`。在 aarch64 SteamOS 容器里根本跑不起来，安装器复制完文件就停了，
服务 unit 缺失，也不会注入。

## 2. 可用的 ARM64 构建

`v3.3.0-pre1`（预发布）提供了明确的 ARM64 资产：

```
PluginLoader-arm64
```

Release 说明：*"feat(loader): support ARM Linux, experimental builds for every platform that
exists"*（PR #990）。

实测下载到的是真正的 aarch64 ELF（`e_machine = 0x00B7`）。

## 3. 手动安装步骤

```bash
# 1. 二进制
mkdir -p /home/steamos/homebrew/services
cp PluginLoader-arm64 /home/steamos/homebrew/services/PluginLoader
chmod 755 /home/steamos/homebrew/services/PluginLoader

# 2. unit —— 必须放 /usr/lib（见文档 04 的 /etc overlay 问题）
cp plugin_loader.service /usr/lib/systemd/system/plugin_loader.service
ln -sf /usr/lib/systemd/system/plugin_loader.service \
       /usr/lib/systemd/system/multi-user.target.wants/plugin_loader.service

# 3. 启动
systemctl daemon-reload
systemctl enable --now plugin_loader.service
```

unit 文件：[services/plugin_loader.service](../services/plugin_loader.service)

## 4. 前提条件

- Steam 客户端必须带 **`-cef-enable-debugging`**。Decky 通过远程调试端口（8080）注入
  Steam CEF 界面；没有这个参数，loader 什么都不输出，插件图标也不会出现。
- Steam 必须在运行；`Loading Decky frontend!` 这行只有在 CEF 界面起来之后才会出现。

## 5. 验证

```bash
systemctl is-active plugin_loader.service
journalctl -u plugin_loader.service -n 20
```

预期输出：

```
[main][INFO]: Starting Decky version v3.3.0-pre1
[loader][INFO]: plugin_path: /home/steamos/homebrew/plugins
[main][INFO]: Loading Decky frontend!
```

## 6. 关于 Decky 插件（LSFG-VK）

商店里的 **Decky LSFG-VK** 插件依赖 x86_64 的 `lsfg-vk` Vulkan 层，在 ARM64 上是坏的
（复制 x86-64 库后中断）。可用的替代是 ARM64 社区分支：

- `Janleyx/decky-lsfg-vk-for-Ayn-Odin-2`（Odin 2 Pro 实测，骁龙 8 Gen 2 / Adreno 740，
  与一加 Ace 3 同 GPU 家族）
- `razoomnik/lsfg-vk2-arm64-odin3`
- `BakaPute/ArmadaLSFG` / `drewano/armada-lsfg-adaptive`

性能叠加层与 Steam UI 在 ARM64 上的互相影响见
[02-steam-versions-and-defects.zh-CN.md](02-steam-versions-and-defects.zh-CN.md)。

## 7. 卸载 Decky

```bash
systemctl disable --now plugin_loader.service
rm -f /usr/lib/systemd/system/plugin_loader.service \
      /usr/lib/systemd/system/multi-user.target.wants/plugin_loader.service
rm -rf /home/steamos/homebrew
```
