# Quality presets and 1280x800 layout (packaged 0.9.2, 2026-10-16)

These were measured on this Windows PC: i7-7700K, RTX 4070 Ti Super, Windows 10. They are **not Steam
Deck measurements**, and a real Deck test is still to do.

`scratchpad presets.ps1` ran the busy 8-fighter scene (`--bench busy --n 8`, 30 s, 5 s warm-up, uncapped)
once per quality preset. Deck ran at 1280x800 and the others at 1920x1080:

| Preset | Resolution | Avg fps | p95 frame (ms) | p99 frame (ms) | Frames over 16.7 ms |
|---|---|---|---|---|---|
| deck | 1280x800 | 306.7 | 5.308 | 6.458 | 0.0 % |
| low | 1920x1080 | 312.9 | 5.267 | 6.301 | 0.0 % |
| medium | 1920x1080 | 255.6 | 5.695 | 6.6 | 0.0 % |
| high | 1920x1080 | 252.5 | 5.819 | 6.992 | 0.0 % |
| ultra | 1920x1080 | 238.7 | 5.981 | 7.277 | 0.0 % |

Every preset holds 60 fps with large headroom. The presets scale render cost (Low is fastest, Ultra
slowest), but with 8 fighters the simulation is most of the frame, so the spread is small.

The `capture_1280x800_*.jpg` files are the packaged game at 1280x800 with the default UI scale:
- Main menu, character select, settings and hub: no clipping or overlap.
- Campaign menu: **bug found and fixed** in the commit after 0.9.2. The Dosage and Seed rows used wrapping
  labels inside a row, and in the narrower column they collapsed to one letter per line
  (`capture_1280x800_campaign_menu.jpg`, packaged 0.9.2). They now use `CampaignUI.inline_label`, and the
  Seed field fills the row (`capture_1280x800_campaign_menu_fixed.jpg`, from source).
- 8-fighter HUD: two rows of four plates. Names and health are readable, the sub-labels (Hype, ability
  readiness) are small but legible, and Settings > Display > UI scale enlarges them.
