# Matched performance: v0.9.17 and v0.9.18

Windows 10, i7-7700K, RTX 4070 Ti SUPER, Godot 4.5.1. Eight pro bots, seed 7, uncapped rendering;
15-second warm-up, 30-second samples, before/after/after/before. Both builds use the same benchmark.
Each new combat system runs its own attacks; this compares player-facing defaults, not identical gameplay.

| Build | Preset | Load | FPS | p95 ms | p99 ms | Frames >16.7 ms |
|---|---|---|---|---|---|---|
| before | deck | plain | 113.4 / 125.5 | 14.421 / 11.608 | 26.335 / 16.724 | 3.231 / 1.036 |
| before | deck | abilities | 103.7 / 97.0 | 14.902 / 16.08 | 18.986 / 22.573 | 1.896 / 3.951 |
| before | high | plain | 106.6 / 110.7 | 14.384 / 13.475 | 19.306 / 17.453 | 2.313 / 1.355 |
| before | high | abilities | 85.1 / 83.1 | 17.431 / 18.165 | 28.059 / 24.228 | 6.698 / 8.905 |
| after | deck | plain | 118.8 / 110.2 | 12.868 / 15.787 | 22.607 / 42.74 | 2.103 / 4.295 |
| after | deck | abilities | 92.2 / 103.5 | 17.775 / 15.324 | 48.498 / 19.89 | 6.616 / 2.93 |
| after | high | plain | 84.0 / 112.9 | 27.264 / 12.985 | 62.057 / 16.418 | 10.182 / 0.944 |
| after | high | abilities | 79.2 / 91.2 | 22.717 / 18.245 | 45.755 / 27.251 | 12.458 / 7.271 |

## Longer confirmation of the variable High/plain case

Same scene and 15-second warm-up, with 60-second samples in ABBA order. This is additional evidence;
the initial results above remain included.

| Run | FPS | p95 ms | p99 ms | Frames >16.7 ms |
|---|---|---|---|---|
| before-1 | 101.0 | 15.824 | 23.105 | 3.747 |
| after-1 | 99.9 | 16.053 | 22.767 | 4.169 |
| after-2 | 108.5 | 14.082 | 19.069 | 1.812 |
| before-2 | 104.2 | 14.947 | 20.918 | 2.736 |

## Provenance and exclusions

- The original first Deck/plain baseline overlapped contact-sheet CPU processing. Its repeat replaces it
  in `paired-summary.json`; both originals and repeat provenance are retained.
- `perf/` is the early run that stopped when v17 encountered a profile migrated by v18.
- `perf-final-fixes/` contains paused, zero-event samples and the interrupted retry. Those records are
  diagnostic only; they are excluded from the final comparison.
- Final runs isolate build profiles, disable focus-loss pausing, and require advancing simulation, hits
  and (for the burst case) effects. Every final sample passes these guards.
- No CPU-heavy capture processing, other game, or second Godot task overlapped the confirmation.
- These are scripted Windows desktop measurements. They do not prove constant 60 FPS or Steam Deck performance.
