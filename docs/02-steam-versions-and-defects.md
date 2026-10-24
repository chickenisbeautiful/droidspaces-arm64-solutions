# Steam Client Versions & Defects on ARM64

> Bilingual pair: [02-steam-versions-and-defects.zh-CN.md](02-steam-versions-and-defects.zh-CN.md) (Chinese)

Everything in this document was observed on a **SteamOS ARM64 container** (DroidSpaces) with the
ARM64 Steam client (`steamrtarm64/steam`) and Proton 11.0 (ARM64). The Steam Deck UI (Deck mode)
was enabled and disabled several times during the session; each change produced measurable
behaviour differences in controller hot-plug and UI startup.

---

## 1. Branches and builds observed

| Branch | Manifest name | Build | Hot-plug behaviour |
|--------|---------------|-------|--------------------|
| `steamdeck_publicbeta` | `steam_client_steamdeck_publicbeta_linuxarm64` | **1792192922** (original) / 1792711043 (later) | **Bluetooth hot-plug works** |
| `steamdeck_stable` | `steam_client_steamdeck_stable_linuxarm64` | 1792618285 | **Regression: BT hot-plug broken** |
| (plain public) | `steam_client_linuxarm64` | — | not used on this device |

### Where the branch is stored

```
~/.local/share/Steam/package/beta
```

A plain text file whose content is the branch name, e.g. `steamdeck_publicbeta`.

- **Delete the file** → the Steam client falls back to the platform default, which on this ARM64
  SteamOS image is `steamdeck_stable`.
- **Restore / write the name** → back to `steamdeck_publicbeta`.

Switching branches triggers a **~500 MB** client download followed by a self-update, then the
client restarts. This is exactly what happened during the Deck-mode experiment and is the most
likely cause of the hot-plug regression.

### How to inspect

```bash
cat /home/steamos/.local/share/Steam/package/beta
grep -n steam_client_ /home/steamos/.local/share/Steam/logs/bootstrap_log.txt
grep "Client version" /home/steamos/.local/share/Steam/logs/steamui.txt
```

---

## 2. Launch flags

### Steam client (`gamescope_steam.sh`)

| Flag | Effect |
|------|--------|
| `-gamepadui` | Big Picture / gamepad UI |
| `-cef-enable-debugging` | exposes the CEF remote-debugging port (`8080`) — **required by Decky Loader** |
| `-steamdeck` | enables the Steam Deck UI (Deck mode) |
| `-steamos3` / `-steampal` | enable SteamOS-specific integrations (display manager, PAM) — used by the Deck UI |

Pre-Deck working line:

```bash
exec steam -gamepadui -cef-enable-debugging "$@"
```

Deck mode line used for the performance panel:

```bash
exec steam -gamepadui -steamdeck -steamos3 -steampal -cef-enable-debugging "$@"
```

### Gamescope (`--backend anland`)

| Flag | Effect |
|------|--------|
| `--mangoapp` | starts the MangoHud overlay; powers the Steam performance HUD |
| `--default-touch-mode` | `0` hover, `1` left click, `2` right, `3` middle, `4` passthrough (direct touch) |

Working line used:

```bash
exec "$GAMESCOPE_BIN" --backend anland -f -e --mangoapp -- "$@"
```

Without `--mangoapp`, the HUD is gone but the UI is much more stable.

---

## 3. Defects observed on ARM64

### 3.1 SteamUI thread stalls (5–58 s)

`logs/steamui.txt`:

```
[01:51:16] Warning: SteamUI thread frame stalled for: 6220 ms
[01:24:42] Warning: SteamUI thread frame stalled for: 5205 ms
[00:58:43] Warning: SteamUI thread frame stalled for: 58097 ms
```

The first frame of the Deck/Big Picture UI can take **1–2 minutes** to appear on ARM64. It is not
a network problem (manifest download was HTTP 200). The spinner is not a deadlock; the UI does
eventually load.

### 3.2 `IClientSystemDisplayManager::GetState took too long`

`logs/console_log.txt` — **3609 occurrences**, each ~50 ms:

```
IPC function call IClientSystemDisplayManager::GetState took too long: 50 msec
```

The Deck UI queries the SteamOS **display manager** for display/refresh/performance info. In this
container the real Valve `steamos-manager` is replaced by an Anland session broker, and the
custom gamescope does not implement the expected interface → the calls time out and the UI thread
starves. This is the main reason Deck mode feels unusably slow here.

### 3.3 CEF `Transport Error` (steamloopback.host)

`logs/cef_log.txt`:

```
Uncaught (in promise) Transport Error: no transport is available for request
source: https://steamloopback.host/index.html?...ARCH=arm64...IS_STEAMOS=true&ON_STEAMOS_CLIENT_BRANCH=true&IN_GAMESCOPE=true
```

Notes:

- `steamloopback.host` is Steam's private loopback hostname. It resolves to `127.0.0.1`
  (via systemd-resolved or `/etc/hosts`); DNS is **not** the problem.
- The "no transport" error is a symptom of the UI thread being blocked (3.2), not of the name
  failing to resolve.
- If you *do* see resolution problems, add to `/etc/hosts`:
  ```
  127.0.0.1 steamloopback.host
  ```

### 3.4 MangoApp swapchain conflict

With `--mangoapp` enabled, gamescope logged **3607** lines like:

```
[gamescope] [Error] wlserver: create_swapchain: Surface already had a gamescope_swapchain! Warning!
[Gamescope WSI] Created swapchain for xid: ... Destroyed swapchain: ...
```

The overlay and the Steam UI fight over the same swapchain, making the UI stalls worse.
**Trade-off:** MangoHud HUD works, but the UI becomes noticeably less responsive.

### 3.5 Deck UI startup

On this hardware the Deck UI spinner can persist for **1–2 minutes** even in a good case.
Recovering from a stuck spinner: `pkill -9 -f steamrtarm64/steam` and restart the game-mode
session (`systemctl --user restart anland-game-mode`). Repeated kills during a client update are
generally safe; the bootstrap verifies and repairs.

---

## 4. Controller hot-plug regression is branch-dependent

| | `steamdeck_publicbeta` | `steamdeck_stable` |
|--|------------------------|--------------------|
| BT pad reconnect detected | yes (with 0.5 s poll + trigger) | **no** until a USB pad forces a rescan |
| `controller.txt` on disconnect | `Controller device closed after hid_read failure` | same |
| After reconnect | `Local Device Found` / `PollState 2` | **nothing**; stale `eventN (deleted)` fd |

Experimental evidence gathered while diagnosing:

1. Renaming `/dev/input/event10` → `event20` left Steam holding `event10 (deleted)`. Steam never
   opened the new path.
2. Creating a **new uinput** device *did* make Steam scan (it opened the new node instantly).
3. Plugging/unplugging a USB pad forces a full rescan, which is why that trick revives the
   Bluetooth pad.

Conclusion: on `steamdeck_stable`, Steam's SDL controller hot-plug does not recover a reconnected
Bluetooth pad that reuses its event number. `steamdeck_publicbeta` behaves correctly.

---

## 5. Startup animations

See [07-steam-startup-animation.md](07-steam-startup-animation.md).

Short version: startup movies are **Points Shop** items (e.g. *Special Delivery* / 特别快递,
3000 points), not Workshop downloads. After purchase you select them in
Settings → Customization → Startup Movie and Steam downloads the video automatically.

---

## 6. Recovery playbook

```bash
# 1. kill a stuck Steam client
droidspaces --name=steamos run pkill -9 -f steamrtarm64/steam
droidspaces --name=steamos run pkill -9 -f steamwebhelper

# 2. restart the session (also restarts MangoApp/Decky injections)
droidspaces -n steamos -u steamos run env XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user restart anland-game-mode.service

# 3. switch Steam branch
droidspaces --name=steamos run sh -c 'echo steamdeck_publicbeta > /home/steamos/.local/share/Steam/package/beta'
```

Also useful:

```bash
# current branch + build
droidspaces --name=steamos run cat /home/steamos/.local/share/Steam/package/beta
droidspaces --name=steamos run grep "Client version" /home/steamos/.local/share/Steam/logs/steamui.txt | tail -1
# stuck UI state
droidspaces --name=steamos run tail -20 /home/steamos/.local/share/Steam/logs/steamui.txt
droidspaces --name=steamos run grep -c GetState /home/steamos/.local/share/Steam/logs/console_log.txt
```

---

## 7. Practical recommendations

1. Stay on **`steamdeck_publicbeta`** for this ARM64 container.
2. Use **Big Picture** (`-gamepadui`) for daily use; it is faster than Deck mode.
3. Only turn on Deck mode when you specifically need the performance panel — and accept the
   1–2 min startup and the `GetState` stalls.
4. Keep `--mangoapp` off unless you need the HUD; it degrades UI responsiveness.
5. After any Steam update, re-check controller hot-plug before launching a game.
