# Notes on verification run 20261015-211605 (packaged 0.9.1, commit 1f941a3)

This run of `tools/verify/run_verification.ps1` tested the published 0.9.1 package on a quiet machine.
The text results are committed here. The 31 captures (about 26 MB of PNG) are not committed: they live
in the local run folder, and the release-candidate run will commit its own.

## What failed, and why

**Packaged test suite: 21 of 677 failed.** None of the failures is a game defect. All are packaged-only
problems in the tests, fixed in the commit after 0.9.1:

- **Network tests, 18 failures** (`test_net_multiprocess`, `test_net_measure`, `test_net_soak`,
  `test_net_party_campaign`, `test_online_ui`). The tests spawn child processes with
  `--path <ProjectSettings.globalize_path("res://")>`. In an exported build that path is empty, so
  the child got an invalid `--path` and quit before doing anything. Every expectation then timed out.
  The run had no child `.engine.log` files. In a rerun of `test_tcp_admin` inside this package, no
  child process stayed running and none wrote a log. Fix: `net_test_util.gd` leaves out `--path` in
  exported builds, as the AI Lab's worker spawning already did.
- **`test_lab_datasets::test_recording_again_adds_new_episodes`.** The test builds paths relative to
  the project folder, which an exported build does not have. Fix: in exported builds the paths stay
  absolute. The rest of the test still runs.
- **`test_net_parity`, two tests.** These read GDScript source, and exported builds ship compiled
  scripts (`script_export_mode=2`). Fix: they are reported as **skip** in exported builds and run in
  the source suite. The test runner now counts skips separately and never counts them as passes.
  Three tests that used to return silently in exported builds now report skip too:
  `test_settings_wired`, `test_audio_bank` literal ids, and `test_audio_bank` manifest.

**Online session check: duel had no result.** Both packaged clients joined, and the server, TCP admin
and spectator steps passed. Both clients got the default fighter (Dozer), though. The scripted
attacker only swings within 1.7 m of the target's root, and two Dozers never get that close. The duel
reached sudden death, and the clients quit unresolved. Fix: `net_session_check.ps1` names the fighters
(Stoke and Jitters), as `test_net_multiprocess` does.

## Corrected figure: server simulation cost

The table says "~96 % of one core". That number is wrong. The old formula added the mean sim-step time
to `Performance.TIME_PHYSICS_PROCESS`, and that monitor is the engine's worst physics frame of each
second, which already includes the sim step.

The measured cost in this run is 1.93 ms of wall time per 120 Hz tick, everything included, with 8
fighters and pro bots. That is about **23 % of one core** at 120 Hz. The bench now also measures
process CPU time, physics threads included, and `run_verification.ps1` checks it against the
DESIGN.md target of < 35 %.

## Re-test of the fixes in a fresh packaged build (2026-10-16)

The rerun of the network tests found a second packaged-only cause. Release builds buffer printed lines
in 4 KB blocks, so a running server's `--log-file` stayed empty and the tests never saw its `ready:`
line. This also affects real operators: a dedicated server's console output must reach a service
manager line by line. `application/run/flush_stdout_on_print` is now on in all builds (DECISIONS
D-029).

With both fixes, all 21 previously failing tests pass inside a freshly exported Windows build:
`test_net_multiprocess` 13/13, `test_net_party_campaign` 2/2, `test_net_measure`, `test_net_soak`,
`test_online_ui` join, and `test_lab_datasets`. `test_net_parity` reports 2 skips.

The server cost in that build, measured by `test_net_measure` on the real server process:
- duel: 20.4 % of one core;
- 8 fighters: **43.2 %** of one core (1.76 ms sim + 0.28 ms network per tick on the main thread), above
  the 35 % target;
- sim-only bench: 2.48 ms CPU per tick, 29.7 %.

## Also fixed after this run

`test_combat_rules` started its reproducibility probe processes without `--user-root`. They ran
against the player's real profile folder (`%APPDATA%\Critterweight`), which this run's 21:19 log
shows. The writes were harmless: the same profile index was rewritten. Test processes still must
never touch real user data, and the probe now gets its own user root.
