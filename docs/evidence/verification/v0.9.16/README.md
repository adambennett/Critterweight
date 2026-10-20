# Critterweight v0.9.16 verification

**Scope:** the owner-requested Career (persistent fighter recreated from Cage Rules' career, first in
the Campaign menu), optional 10-point must scoring and an independent referee for the standard duel
(Jeremy's Cage Rules referee imported through `tools/cage_rules`), and the built-in Cage Rules rules
preset. Decisions D-044..D-048; ledger rows CMP-08, MCH-07, MCH-08, MCH-09, ART-09.

Machine: Windows 10 (19045), i7-7700K, RTX 4070 Ti Super, Godot 4.5.1 (official). Networking is
loopback on this PC.

## Baseline (before the work)

- The checkout matched the published v0.9.15 (`f8e4bbb`, `origin/main`, tag `v0.9.15`), clean.
- The deleted local checkouts (Recycle Bin, 2026-10-19) were audited: every local branch tip was
  already on GitHub and every uncommitted v0.9.15 edit was already in the release. Only the
  never-adopted Ableton audio experiment (D-040) exists solely in the Recycle Bin; nothing was restored.
- Baseline full suite on `f8e4bbb`: 775 run, 773 passed, 1 skipped, 1 failed
  (`test_net_soak::test_soak_server_with_bots`, memory growth 1.60 MB/min while other processes ran).
  Re-run alone on the same build: 1/1 passed. Load-sensitive, not a regression.

## Source checks (release commit `9d0a29c`, "Release 0.9.16")

- Script check: **437 scripts, 0 failures**.
- Full suite (`tools/dev/run_suite.ps1`): **862 run, 861 passed, 0 failed, 1 skipped**
  (`test_playtest_ui::test_dropdown_keeps_music_and_rapid_ambience_switches_settle`: needs the
  graphical audio backend). [Results](full-source-results.json). 87 tests are new in v0.9.16.
- Calibration (DECISIONS D-045): 52 headless Cage Rules bot duels plus 16 re-runs with the final
  constants that matched the offline prediction card for card; career fight-of-the-night pace and
  injury scale from the same data.
- Changes after the full suite and before tagging are documentation and
  `game/assets/data/patch_notes.json` (the v0.9.16 entry), covered by the release script's packaged
  checks and `test_preview_0915` (which now also asserts that the newest entry is this build).

## Packaged checks (Windows export of the release commit, release-script dry run)

- Build: [manifest](prerelease-build-manifest.json) (`9d0a29c`, clean); `Critterweight.exe`
  299,583,920 bytes, sha256 `5de246af…5c85`. All four game/server targets exported and archived.
- Release smoke: fresh script check, boot to the title in **4.4 s**
  ([boot report](prerelease-packaged-boot.json)), rendered playtest regressions **20/20**, no skips
  ([results](prerelease-packaged-rendered-tests.json)).
- New-feature suites against the exported executable, each with its own user root, no script errors
  in the engine logs:

  | Mode | Suite | Result |
  |---|---|---|
  | headless | test_ten_point_scoring | 9/9 |
  | headless | test_referee_rules | 7/7 |
  | headless | test_referee_view | 11/11 |
  | headless | test_career_state / progression / build / fights | 11/11, 17/17, 9/9, 2/2 |
  | headless | test_rules_presets, test_net_snapshot | 7/7, 5/5 |
  | headless | test_audio_announcer, test_recorded_speech | 9/9, 9/9 |
  | windowed (rendered) | test_ten_point_ui | 7/7 |
  | windowed (rendered) | test_career_ui | 11/11 |
  | windowed (rendered) | test_ui_navigation | 8/8 |

  Totals: 96 headless + 26 rendered, 0 failed, 0 skipped (`packaged-*-results.json`).
- A packaged Cage Rules sandbox capture shows Jeremy's referee model (not the primitive fallback),
  no HP bars and the "ROUND 1 / 3 · 3 JUDGES · 10-POINT MUST" HUD
  ([capture](captures/packaged-cage-rules.png)).

## Rendered evidence captures (source build, reviewed)

[Between-rounds scorecard](captures/round-scorecard.png) · [T.K.O. results](captures/tko-results.png) ·
[referee arm raise](captures/referee-raise.png) · [career camp](captures/career-hub-camp.png) ·
[career result](captures/career-result.png). Runners: `res://src/test/ui/ten_point_shots.tscn`,
`res://src/test/core/referee_shots.tscn`, `res://src/test/campaign/career_shots.tscn` (windowed,
not tests).

## Bug hunt

An independent find-and-verify pass over the whole v0.9.16 diff (simulation, career, UI/network,
docs lenses) confirmed one real bug — quitting a career bout during the decision ceremony withdrew
instead of booking the decided result — fixed with a regression test
(`test_career_ui::test_pause_quit_after_the_decision_books_the_result`), and seven text
inaccuracies, all corrected.

## Not verified

- No human or physical-controller playtest; judging closeness and the Career economy have only been
  measured with bots.
- Online play only over loopback (snapshot budget, parity, mirror HUD and referee from replicated
  data are covered by tests).
- Linux packages are built but not run.

## Published release

Tagged-release evidence (tag, asset hashes) is added after publication below.
