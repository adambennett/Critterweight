# Client soak (source build 0.9.6+, 2026-10-16)

`--bench client_soak --matches 48` (`game/src/test/bench.gd`), windowed at 1920x1080 on this PC: an
i7-7700K, an RTX 4070 Ti Super, Windows 10.

The run played 48 matches back to back, through `App.start_match` with the full presentation:
- rendering, HUD, VFX, audio, camera and arena dressing;
- 40 s of fighting each, at 4x sim speed, about 32 minutes in all;
- the four arenas in turn, alternating duels and 4-fighter free-for-alls.
After each match it went back to the main menu the way the app does, and sampled memory, objects, nodes,
orphan nodes and video memory (`client_soak_48.json`).

| Measure | After match 1 | Match 16 | Match 48 | Per match, second half |
|---|---|---|---|---|
| Static memory | 286.5 MB | 326.2 MB | 326.6 MB | +0.003 MB |
| Objects | 4,445 | about 5,430 | 5,425 | -0.04 |
| Nodes (back at the menu) | 976 | 976 | 976 | 0 |
| Orphan nodes | 0 | 0 | 0 | 0 |
| Video memory | 319.6 MB | 348.2 MB | 348.2 MB | +0.003 MB |

Memory grows while each arena and fighter loads for the first time (caches and pools), then levels off. No
leak shows in memory, objects, nodes or video memory over 48 matches. A 16-match run earlier the same day
showed the same plateau.
