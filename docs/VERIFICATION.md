# Verification report

**Release 0.9.16, 2026-10-20.** [The v0.9.16 report](evidence/verification/v0.9.16/README.md): Career,
10-point scoring, the referee and the Cage Rules preset. 437 scripts; full source suite on the release
commit 862 run, 861 passed, 0 failed, 1 graphical-audio skip. PACKAGED

**Local v0.9.15 fighters preview, 2026-10-18.** [Fighter build report](releases/v0.9.15-fighters-preview.md): Varga (Scrap) and Knell (Spectral), 406 scripts compile, 130 focused source tests and 62 packaged tests pass with zero failures/skips. The Windows export includes the concurrent announcer expansion. The earlier changing-source full run is diagnostic only; physical controller, visual presentation and balance await the owner. No graphical launch or release publication.

**Local v0.9.15 preview 3, 2026-10-18.** [The current report](evidence/verification/v0.9.15-preview3/README.md) records the completed rooftop canvas, clean Windows export from 9d8f44e and packaged verification: 403 scripts, 89 tests passed, zero failed, one source-only skip. It includes every preview 2 change and all 764 voice clips/names. No graphical launch or publication; owner playtesting is next.

**Local v0.9.15 preview 2, 2026-10-18.** [The current report](evidence/verification/v0.9.15-preview2/README.md) records the full suite, corrected fixture reruns, 764 recorded voice clips and clean Windows export from a527f2d. Packaged headless checks pass; physical controller, monitor, visuals and listening remain for the owner. The rooftop canvas is a follow-on request. No .15 release has been published.

**Preview 0.9.13, 2026-10-17.** The [v0.9.13 report](evidence/verification/v0.9.13/README.md) records the free audio replacements, Random fighter choices, source and packaged checks, and release evidence. The preceding [v0.9.12 playtest report](evidence/verification/v0.9.12/README.md) records the menu and gameplay fixes carried forward here. This is a preview, not the release candidate. The release-candidate run, whole-brief audit (VER-07) and open items in `docs/PROGRESS.md` remain separate. This report distinguishes verified checks from what has not been verified. Requirement-level states live in `docs/REQUIREMENTS.md`.

Machine for every result below: Windows 10 (19045), i7-7700K, RTX 4070 Ti Super, Godot 4.5.1 (official
build). Networking results are **loopback** on this one PC unless stated otherwise.

## Builds

Every release is a GitHub pre-release with the Windows game (`.exe`, `.zip`), the Windows and Linux
dedicated servers, the Linux game, `BUILD_MANIFEST.json` and `SHA256SUMS.txt` (`docs/RELEASES.md`).

| Version | Commit | Source suite before release | Packaged checks |
|---|---|---|---|
| 0.9.16 | `v0.9.16` (see RELEASES.md) | 862 run: 861 passed, 0 failed, 1 graphical-only skip | PACKAGED |
| 0.9.15 | `f8e4bbb` (`v0.9.15`) | 775 run: 774 passed, 0 failed, 1 graphical-only skip (combined build `8f9baff`) | combined preview package 72 checks: 70 passed, 2 source-only skips; release smoke: 406 scripts, title boot 4.3 s (no rendered filter) |
| 0.9.14 | `95c857a` (`v0.9.14`) | focused audio suite 20/20 (full suite not rerun for the menu-audio mix) | Tagged Windows: 394 scripts, title in 5.7 s, 20/20 rendered; packaged audio 18 passed, 2 source-only skips |
| 0.9.13 | `cdacbcf` (`v0.9.13`) | 718 run: 717 passed, 0 failed, 1 graphical-only skip; fighter selection 24/24, AI Lab picker 8/8, source audio 10/10 | Tagged Windows: 394 scripts, title in 4.5 s, 20/20 rendered; packaged audio 8 passed, 0 failed, 2 source-only skips; four targets built; seven uploaded asset digests verified; [report](evidence/verification/v0.9.13/README.md) |
| 0.9.12 | `0e8b20f` (`v0.9.12`) | 711 run: 710 passed, 0 failed, 1 graphical-only skip; full-suite warnings documented in the linked report | Tagged Windows build: 391 scripts, title in 4.5 s, 20/20 rendered regressions, no shutdown warnings; all four targets built and seven uploaded asset digests verified |
| 0.9.9 | eecaa39 | 684 / 685 (the one failure was the cross-drive lab-test check, fixed and re-run green) | release smoke: script check, packaged boot to the title |
| 0.9.8 | 57613cc | 685 / 685 passed (2026-10-16) | release smoke: script check, packaged boot to the title |
| 0.9.7 | 9e9d93c | 684 / 684 passed (2026-10-16) | release smoke: script check, packaged boot to the title |
| 0.9.6 | 68673c1 | 682 / 682 passed (2026-10-16) | release smoke: script check, packaged boot to the title in 4.5 s |
| 0.9.5 | d699dfa | 679 / 679 passed | release smoke, boot 4.4 s |
| 0.9.4 | f908db2 | full suite green | release smoke |
| 0.9.3 | fd71dc9 | full suite green | release smoke |
| 0.9.2 | a8f0a54 | full suite green | **full packaged verification: every step passed** (below) |

## How it is verified

**1. Source suite:** `tools/dev/run_suite.ps1`. It runs the whole Godot test suite headless at 120 Hz, at
below-normal priority, one full run at a time on the machine. It covers:
- unit and property tests;
- headless match simulations;
- campaign runs with real bot-fought fights in both variants;
- networking in separate processes (dedicated server, listen host, latency/loss conditioner,
  disconnect/rejoin, incompatible content, playlists, 2-4 player co-op runs);
- the AI Lab;
- mod hardening;
- UI navigation;
- the audio bank.

About 38 minutes. A release needs a green run of the exact commit.

**2. Release smoke:** `tools/build/release.ps1`. On the packaged game it runs a script check and a boot to
the title screen before anything is published. `-TestFilter` additionally runs matching tests with the
native Windows renderer and requires a nonempty result with no failures, skips or engine/script errors.
The v0.9.12 release uses `-TestFilter test_playtest` for the 20 playtest regressions.

**3. Full packaged verification:** `tools/verify/run_verification.ps1`, on the packages `release.ps1`
built. Its steps:
- the whole test suite inside the exported game;
- dedicated-server load with 8 fighters;
- boot time and memory;
- captures from the real packaged renderer of every mode, arena and main screen;
- an online session between two packaged clients and the server package;
- frame-time benches.

**Latest full run: 0.9.2, `docs/evidence/verification/20261016-115413/NOTES.md`. Every step passed.**

| Check | Result (packaged 0.9.2) |
|---|---|
| Packaged suite | 677 tests: 672 passed, 5 skipped (source-only checks), 0 failed, 29 min |
| Server load, 8 fighters (PERF-04) | 30.0 % of one core (budget < 35 %) |
| Boot to the title / memory in an 8-fighter match | 3.9 s / 585 MB |
| Captures | 28 steps, 31 images, all passed (committed as JPEG) |
| Online session (`net_session_check.ps1`) | Duel result on both clients; 30 snapshots/s, 39 ms interpolation, 9 ms RTT; TCP admin, token refusal and shutdown OK; no log errors |
| Frame bench, 1920x1080 High | 8 fighters 255 fps on average, p99 6.7 ms, no frame over 16.7 ms; duel 541 fps |

The earlier run on 0.9.1 (`20261015-211605/NOTES.md`) found 21 packaged-only test failures and a duel
check that could not resolve. All were test or tooling problems, and they were fixed in 0.9.2. That run
also corrected a wrong server-CPU figure.

**4. Presets and 1280x800:** packaged 0.9.2, `docs/evidence/verification/presets-20261016/`. Every quality
preset runs the busy 8-fighter scene with no frame over 16.7 ms; the Deck preset runs at 1280x800. The
folder has 1280x800 captures of the main screens and a layout sweep of the rest, which found three layout
bugs; there are before and after captures of each fix. These measurements are from this PC, not a Steam
Deck.

**5. UI polish pass:** 2026-10-16. Every menu and in-game screen was screenshotted at 1600x900 and
1280x800 from source builds, and the rough ones were reworked. Those changes shipped in 0.9.3 and 0.9.4
(`docs/PROGRESS.md`). The working screenshots were not committed; the committed before/after evidence is
the sweep in `presets-20261016`.

**6. Client soak:** 2026-10-16, `docs/evidence/verification/client-soak-20261016/` (`--bench client_soak`). 48 presented
matches back to back, about 32 minutes of fighting at 4x, each left the way the app leaves it. Memory
levels off at 326 MB after the first loads (+0.003 MB per match afterwards), nodes stay at 976, orphan
nodes at 0, and video memory is flat: no leak.

**7. Linux server in a container:** 2026-10-16, `docs/evidence/verification/linux-container-20261016/`. The packaged
Linux server ran in Debian 12 (Docker on WSL2) and hosted a full duel for two packaged Windows clients.
It found a cross-platform bug: JSON float text differs between Windows and Linux, so arena and save
hashes differed. Fixed with `Canon`.

**8. Audio:** the windowed showcase (`audio_showcase.gd -- --quick`) plays the whole chain with real output
and exits 0 when everything played (docs/AUDIO.md §7).

## Changes since the last full packaged verification

From 0.9.3 to 0.9.6:
- the UI polish pass;
- the Slurry balance change (D-034);
- the review fixes:
  - Chum Rush supplement picks;
  - Chumball KO scoring;
  - the Rooftop railings;
  - bots steering round props;
  - a flaky resume test.

Each was released after a green source suite and the release smoke. The regression tests are named in
`docs/PROGRESS.md`. The Rooftop fix was also checked against before and after captures. The full packaged
verification will be repeated for the release candidate.

## Not verified (disclosed gaps)

- **Two PCs or the internet:** online play has only run over loopback on one PC.
- **Steam Deck and Linux runtime:** the Linux game and server packages are built and pass the
  portability checks, but they have not been run on Linux or a Deck. No Linux environment is available
  here (except the server package, which ran in a Debian 12 container, see step 7). The exact remaining checks:
  - **Ubuntu 24.04 LTS x86-64, game package:**
    - boot to the title with a fresh profile;
    - the tutorial;
    - a duel and an 8-fighter match with a controller;
    - sound on the default device;
    - settings saved and reloaded;
    - join a Windows host's lobby and play a match.
  - **Ubuntu 24.04, server package:** start with the example config; a Windows client joins; TCP admin
    works; graceful shutdown.
  - **Steam Deck (SteamOS 3), native Linux build:**
    - the Deck preset at 1280x800 holds 60 fps in the busy 8-fighter scene;
    - controller navigation and glyphs in every menu;
    - text readable at 1280x800;
    - suspend and resume mid-match;
    - a campaign fight;
    - Proton only as a fallback.
- **Physical controller:** controller paths are verified with injected input events only (ARN-03, UI-02).
- **Player judgement:** readability, feel and balance have not been playtested by the user. Bot-measured
  balance is in docs/BOTS.md and PROGRESS.md: some matchups are lopsided, and the Journeyman bot loses
  most bouts to button-mashing.
- **Final audit:** the whole-brief audit (VER-07) and a full packaged verification of the release
  candidate are still to do.
