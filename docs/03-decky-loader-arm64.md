# Decky Loader on ARM64

> Bilingual pair: [03-decky-loader-arm64.zh-CN.md](03-decky-loader-arm64.zh-CN.md) (Chinese)

## 1. Why the official installer does not work here

The official Decky installer downloads a `PluginLoader` binary from the latest GitHub release.
The stable releases only ship an **x86_64** binary (`PluginLoader`). On an aarch64 SteamOS
container that binary simply cannot run, and the installer stops after copying files — leaving
the service unit missing and no injection.

## 2. The ARM64 build that works

`v3.3.0-pre1` (pre-release) ships an explicit ARM64 asset:

```
PluginLoader-arm64
```

Release notes: *"feat(loader): support ARM Linux, experimental builds for every platform that
exists"* (PR #990).

We verified the downloaded file is a real aarch64 ELF (`e_machine = 0x00B7`).

## 3. Installation steps (manual)

```bash
# 1. binary
mkdir -p /home/steamos/homebrew/services
cp PluginLoader-arm64 /home/steamos/homebrew/services/PluginLoader
chmod 755 /home/steamos/homebrew/services/PluginLoader

# 2. unit — MUST live in /usr/lib (see doc 04: the /etc overlay problem)
cp plugin_loader.service /usr/lib/systemd/system/plugin_loader.service
ln -sf /usr/lib/systemd/system/plugin_loader.service \
       /usr/lib/systemd/system/multi-user.target.wants/plugin_loader.service

# 3. start
systemctl daemon-reload
systemctl enable --now plugin_loader.service
```

Unit file: [services/plugin_loader.service](../services/plugin_loader.service)

## 4. Prerequisites

- **`-cef-enable-debugging`** on the Steam client. Decky injects into the Steam CEF UI through
  the remote-debugging port (8080). Without the flag the loader logs nothing and no plugin icon
  appears.
- Steam must be running; the loader's `Loading Decky frontend!` line appears only after the CEF
  UI is up.

## 5. Verifying

```bash
systemctl is-active plugin_loader.service
journalctl -u plugin_loader.service -n 20
```

Expected:

```
[main][INFO]: Starting Decky version v3.3.0-pre1
[loader][INFO]: plugin_path: /home/steamos/homebrew/plugins
[main][INFO]: Loading Decky frontend!
```

## 6. A note on Decky plugins (LSFG-VK)

The popular **Decky LSFG-VK** plugin from the store is built around an x86_64 `lsfg-vk` Vulkan
layer. On ARM64 it is broken (it copies the x86-64 library and aborts). Working alternatives are
the ARM64 community forks:

- `Janleyx/decky-lsfg-vk-for-Ayn-Odin-2` (tested on Odin 2 Pro, Snapdragon 8 Gen 2 / Adreno 740,
  same GPU family as the OnePlus Ace 3)
- `razoomnik/lsfg-vk2-arm64-odin3`
- `BakaPute/ArmadaLSFG` / `drewano/armada-lsfg-adaptive`

See [02-steam-versions-and-defects.md](02-steam-versions-and-defects.md) for the interaction
between the performance overlay and the Steam UI on ARM64.

## 7. Removing Decky

```bash
systemctl disable --now plugin_loader.service
rm -f /usr/lib/systemd/system/plugin_loader.service \
      /usr/lib/systemd/system/multi-user.target.wants/plugin_loader.service
rm -rf /home/steamos/homebrew
```
