# Performance HUD & Deck Mode

> Bilingual pair: [06-performance-hud-and-deck-mode.zh-CN.md](06-performance-hud-and-deck-mode.zh-CN.md) (Chinese)

Two different things are often called "performance panel":

1. **Steam's performance panel** (TDP / GPU clock / FPS limit / performance HUD) — only available
   in **Deck mode** UI.
2. **MangoHud overlay** — the actual on-screen HUD, driven by gamescope's `--mangoapp`.

## 1. Enabling Deck mode (performance panel)

`gamescope_steam.sh`:

```bash
exec steam -gamepadui -steamdeck -steamos3 -steampal -cef-enable-debugging "$@"
```

On first launch this may trigger a client update to the `steamdeck_*` branch (see
[doc 02](02-steam-versions-and-defects.md)). **Check the branch afterwards** and switch back to
`steamdeck_publicbeta` if you want working hot-plug.

The panel appears in the quick-access menu (PS/Xbox/Nintendo guide button + A/Cross/B, or
`Ctrl+2` with a keyboard).

**Reality check on this device:** TDP / GPU clock sliders have no real hardware to control
(a phone SoC, not a handheld APU). What *does* work is the FPS limiter and the HUD.

## 2. Enabling the HUD (`--mangoapp`)

```bash
exec "$GAMESCOPE_BIN" --backend anland -f -e --mangoapp -- "$@"
```

`mangoapp` (`/usr/sbin/mangoapp`, from the `mangohud` package) renders the overlay. Verify:

```bash
pgrep -af mangoapp
```

Screenshot shows the HUD: `FPS 50  [frame time] GPU% ... CPU% ... BATT ...` at the top of the
screen.

## 3. The trade-off you must accept

With `--mangoapp` enabled, gamescope logged **3607** warnings in one session:

```
[gamescope] [Error] wlserver: create_swapchain: Surface already had a gamescope_swapchain! Warning!
```

The overlay and the Steam UI contend for the same swapchain. Result:

- The HUD works.
- The Steam UI becomes noticeably less responsive and the `SteamUI thread frame stalled` warnings
  get worse.

**Recommendation:** keep `--mangoapp` off for daily use; only enable it when you want to profile
a game. Then remove it again:

```bash
sh scripts/remove-mangoapp.sh
```

## 4. Per-game alternative (no Deck mode needed)

If you only want FPS/temperature in a specific game, MangoHud can be used per game:

```
MANGOHUD=1 %command%
```

This avoids the Deck mode UI entirely and does not touch the Steam UI swapchain.

## 5. Verification checklist

```bash
# Deck mode enabled?
grep 'exec steam' /home/steamos/gamescope_steam.sh
# HUD enabled?
grep 'mangoapp' /home/steamos/gamescope_steam.sh
pgrep -af mangoapp
# which Steam branch (hot-plug behaviour)?
cat /home/steamos/.local/share/Steam/package/beta
# UI health
grep -c GetState /home/steamos/.local/share/Steam/logs/console_log.txt
tail -20 /home/steamos/.local/share/Steam/logs/steamui.txt
```

## 6. Turning everything back off

```bash
sh scripts/revert-deck-flags.sh   # back to -gamepadui -cef-enable-debugging
sh scripts/remove-mangoapp.sh     # remove --mangoapp
systemctl --user restart anland-game-mode
```
