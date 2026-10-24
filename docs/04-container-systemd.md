# Container systemd & Session Management

> Bilingual pair: [04-container-systemd.zh-CN.md](04-container-systemd.zh-CN.md) (Chinese)

The container runs a full systemd. Two facts made everything else in this repo necessary:

1. `/etc` is an **overlay mount** inside the container.
2. The container's `systemd-udevd` runs in its **own network namespace** (see doc 01).

---

## 1. The `/etc` overlay problem

```
devtmpfs on /dev type devtmpfs ...
overlay on /etc type overlay (lowerdir=/etc, upperdir=/var/lib/overlays/etc/upper ...)
```

systemd performs its **first unit scan before the overlay is visible**. Consequence: custom units
placed in `/etc/systemd/system/` are invisible to the boot transaction. They show up only after
`systemctl daemon-reload` (or the next boot with the overlay mounted).

Symptom:

```
systemctl is-enabled my-unit     -> enabled
systemctl is-active my-unit      -> inactive (dead)
systemctl show my-unit -p WantedBy -> (empty)
```

**Fix:** put custom units and their `multi-user.target.wants` symlinks in `/usr/lib/systemd/system`
instead, which is on the rootfs and always visible at boot.

---

## 2. Masked phone-specific units

The SteamOS ARM64 image ships hardware services that cannot work in a container and blocked boot
completion (jobs stayed in `systemctl list-jobs` forever):

| Unit | Problem |
|------|---------|
| `qteesupplicant.service` | `After=dev-tee0.device`; `/dev/tee0` never appears in the container |
| `sheng-devauth.service` | Xiaomi DevAuth; `After=qteesupplicant`, `WantedBy=sysinit.target` |
| `xiaomi-sheng-thp.service` | Xiaomi touch processor; restarted in a loop (150 restarts observed) |
| `bluetooth.service` | bluetoothd cannot access the mgmt interface in the container |

Effect: `systemctl is-system-running` was stuck at `starting` and the restart loops burned CPU.

Mask them (with backups) and reload:

```bash
cd /usr/lib/systemd/system
for u in qteesupplicant sheng-devauth xiaomi-sheng-thp bluetooth; do
  [ -f "$u.service" ] && cp -a "$u.service" "$u.service.droidspaces-backup"
  ln -sf /dev/null "$u.service"
done
systemctl daemon-reload
systemctl reset-failed
```

Script: [scripts/mask-phone-units.sh](../scripts/mask-phone-units.sh)

Result: `systemctl is-system-running` → `running`, `systemctl --failed` → 0 units.

---

## 3. User manager and linger

`systemctl --user` failed with "Failed to connect to user scope bus" after the user manager
exited. Fix:

```bash
loginctl enable-linger steamos
systemctl start user@1000.service
```

Now the user manager (and `anland-game-mode`, `anland-touch-direct`, `steamos-manager`) survives
even when no user session exists.

---

## 4. Units used in this setup

| Unit | Purpose | Location |
|------|---------|----------|
| `plugin_loader.service` | Decky Loader (ARM64) | `/usr/lib/systemd/system` |
| `input-nodes.service` | `/dev/input` + `/dev/uinput` maintenance | `/usr/lib/systemd/system` |
| `anland-touch-direct.service` | keeps gamescope in touch-passthrough mode | user unit (`~/.config/systemd/user`) |
| `anland-game-mode.service` | gamescope + Steam Big Picture session | user unit |
| `steamos-manager.service` | Anland session broker | user unit (replaces Valve's) |

Files: [services/](../services/)

---

## 5. `gamescope_steam.sh` patches

The launch script drives both gamescope and Steam. Changes made during this session:

| Change | Line | Why |
|--------|------|-----|
| add `-cef-enable-debugging` | `exec steam -gamepadui -cef-enable-debugging "$@"` | Decky needs the CEF debug port |
| add `-steamdeck -steamos3 -steampal` | same line | enable Deck UI + performance panel (only when needed) |
| add `--mangoapp` | `exec "$GAMESCOPE_BIN" --backend anland -f -e --mangoapp -- "$@"` | MangoHud HUD (only when needed) |

Working "daily driver" line (Big Picture, no HUD):

```bash
exec steam -gamepadui -cef-enable-debugging "$@"
exec "$GAMESCOPE_BIN" --backend anland -f -e -- "$@"
```

Patch scripts: [scripts/fix-steam-cef.sh](../scripts/fix-steam-cef.sh),
[scripts/patch-performance.sh](../scripts/patch-performance.sh),
[scripts/enable-deck-flags.sh](../scripts/enable-deck-flags.sh),
[scripts/revert-deck-flags.sh](../scripts/revert-deck-flags.sh),
[scripts/remove-mangoapp.sh](../scripts/remove-mangoapp.sh).

---

## 6. Android-side session prerequisites

- The Anland **display activity** (`com.anland.consumer/.SecondaryActivity`) must be in the
  foreground. If the phone locks or the notification shade covers it, the surface is destroyed
  and gamescope never starts Steam:
  ```
  dumpsys window | grep mCurrentFocus
  ```
  Recovery:
  ```bash
  adb shell cmd statusbar collapse
  adb shell am start -n com.anland.consumer/.SecondaryActivity --activity-reorder-to-front
  ```
- The screen timeout was raised to 30 minutes and `stay_on_while_plugged_in=7` was set:
  ```bash
  su -c 'settings put system screen_off_timeout 1800000'
  su -c 'settings put global stay_on_while_plugged_in 7'
  ```

---

## 7. Recovery playbook

```bash
# kill a hung Steam client and restart the session
droidspaces --name=steamos run pkill -9 -f steamrtarm64/steam
droidspaces --name=steamos run pkill -9 -f steamwebhelper
droidspaces -n steamos -u steamos run env XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user restart anland-game-mode.service

# check boot health
droidspaces --name=steamos run systemctl is-system-running
droidspaces --name=steamos run systemctl --failed
droidspaces --name=steamos run systemctl list-jobs
```
