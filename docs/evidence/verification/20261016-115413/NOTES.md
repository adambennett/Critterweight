# Notes on verification run 20261016-115413 (packaged 0.9.2, tag v0.9.2 → a8f0a54)

`tools/verify/run_verification.ps1` ran on the 0.9.2 packages that `release.ps1` built (`dist/`). The machine
was quiet: an i7-7700K, Windows 10, RTX 4070 Ti Super, with nothing else heavy running. **Every step passed**
(`summary.md`):

- **Packaged suite:** 677 tests, 0 failed, 672 passed, 5 skipped, in 29 min. The skips are source-only checks:
  two `test_net_parity` tests, `test_settings_wired`, and two `test_audio_bank` tests. The 0.9.1 run had 21
  failures and took 112 min (`../20261015-211605/NOTES.md`).
- **Server load (PERF-04):** 30.0 % of one core with 8 fighters, measured as the dedicated server package's
  main-thread load (`test_net_measure`, 1 client + 7 bots). The sim-only bench measured 29 % as process CPU
  time. The DESIGN.md budget is < 35 %.
- **Boot to the title:** 3.9 s. **Memory, 8-fighter match:** 585 MB.
- **Captures:** all 28 capture steps passed (31 images), from the real packaged renderer.
- **Online session (net_session_check.ps1):** the server package plus two packaged clients on loopback.
  - The duel result reached both clients.
  - 30 snapshots/s, 39 ms interpolation, 9 ms RTT.
  - TCP admin, wrong-token refusal and graceful shutdown all worked, and none of the 5 logs had an error.
- **Frame bench (1920×1080 High):**
  - 8 fighters: 255 fps on average, p95 5.7 ms, p99 6.7 ms, no frame over 16.7 ms. 0.9.1 had 187 fps and
    p99 63 ms.
  - Duel: 541 fps.

The captures are committed as JPEG (quality 82, `*.jpg`). The original PNGs (25 MB) stay in the local run
folder.
