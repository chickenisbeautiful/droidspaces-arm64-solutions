# Steam Startup Animations (Boot Videos)

> Bilingual pair: [07-steam-startup-animation.zh-CN.md](07-steam-startup-animation.zh-CN.md) (Chinese)

## 1. What they actually are

Startup animations (boot videos) are **Steam Points Shop** items, **not** Steam Workshop items.
The famous Chinese one is *Special Delivery* / 「特别快递」, priced **3000 Steam Points**.

There is nothing to "download" in the Workshop sense. The flow is:

1. Open **Points Shop** → **Startup Movies**.
2. Buy / redeem the item with Steam Points.
3. Go to **Settings → Customization → Startup Movie** (in Big Picture / Deck UI).
4. Select the movie — Steam downloads the video file automatically.

`config/config.vdf` then contains:

```
"StartupMovie"
{
    "MovieID"   "0"      // 0 = none
}
```

No `config/movies` directory and no workshop content appear until a movie is actually selected.

## 2. "It keeps spinning" — what to check

The download button on the Points Shop page is just a web page inside Steam's CEF. It can spin
while:

- The Steam client is still **updating** in the background (check
  `logs/bootstrap_log.txt` for `Downloading manifest` / `正在展开安装包`).
- The network/CDN is slow. This device's Steam uses the Chinese CDN
  (`dl.steam.clngaa.com`, `xz.pphimalayanrt.com`); the download itself was HTTP 200.
- A large game download is occupying the download queue (Steam throttles small downloads behind
  big ones — check the download page).

Checklist:

```bash
tail -20 /home/steamos/.local/share/Steam/logs/bootstrap_log.txt
tail -20 /home/steamos/.local/share/Steam/logs/content_log.txt
grep -i "StartupMovie" /home/steamos/.local/share/Steam/config/config.vdf
```

## 3. Where the file is stored

After selection, Steam stores the video in the Steam install tree (the exact path varies by
client version). The authoritative record is `config.vdf` (`StartupMovie` → `MovieID`).

## 4. Relation to Deck mode

The setting lives in the customization page of the Steam UI. In **Deck mode** the page is part of
the Deck UI; in **Big Picture** it is under Settings → Customization. Both work, but Deck mode on
ARM64 is slow (see [doc 02](02-steam-versions-and-defects.md)).

## 5. Troubleshooting summary

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| Spinning forever on the Points Shop page | client update / slow network | wait for the update; check `bootstrap_log` |
| Item bought but not listed | not selected yet | Settings → Customization → Startup Movie |
| Nothing downloads | download queue busy with a game | pause the game download and retry |
| Video doesn't play | codec/CEF issue on ARM64 | restart Steam; if it persists, use a short WebM |
