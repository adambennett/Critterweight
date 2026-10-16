# Progress

## Status (2026-10-15) — paused for the playtest week at v0.9.1

Work is **paused at a playable preview**, not at the finished release candidate. The latest build is
published as a GitHub pre-release (see `docs/RELEASES.md`). The goal stays open: the items under
"Remaining for the release candidate" must be done before a completion audit can pass.

## Integrated on `main` (all merged, full suite green before each release)

- Combat: active-ragdoll rigs, contact-validated hits, guard/parry/dodge, grabs, elements and reactions,
  knockdowns, ring-outs, containment; string cancels wait for the strike to land (naive mashing works).
- Roster: six full fighter kits (Stoke, Dredge, Gusto, Dozer, Slurry, Jitters), Kid Lamprey, Scrapling
  (+ Pelter), Blister, bosses Bilge/Conduit/Snappington; techniques and minion loadouts lint-checked.
- Modes: versus (1v1 to 8 fighters, teams), practice, spectate (auto-director), tutorial (completable
  with every fighter), bonus modes Spotlight Hog / Chumball / Absolute Unit / Chum Rush, Tag Team.
- Campaigns: Off the Street, Fight Camp with The Cannery hub (11 spaces, NPCs, activities, secrets,
  upgrade stations, cosmetics), The Dosage ladder, The Bookie's Table autobattler + unattended mode,
  local co-op decisions (CoopSession) in both formats.
- Online: listen hosting, dedicated server (Windows/Linux packages), Online + Lobby screens, LAN and
  direct join, playlists with voting, mod/content comparison, arena/preset transfer, policy bots.
- Creation: rules editor and presets, arena editor with four bases and six example layouts, local mods
  (three examples, hardened loader), AI Lab (ES + behaviour cloning, workers, evaluation, sample
  policies for every fighter).
- Reviews done and fixed: modes, mods/persistence, campaign/co-op, AI Lab, hub (≈80 findings).
- Tooling: `tools/build/package.ps1` (4 targets + manifest), `tools/build/release.ps1` (tag + GitHub
  release), `tools/verify/run_verification.ps1` (packaged checks), `tools/dev/run_suite.ps1` (one full
  suite at a time), `tools/verify/ledger_digest.py`, portability check.

## Remaining for the release candidate (exact next actions)

1. **Online co-op follow-ups** (COOP-01..06 mostly done in 0.9.1): party runs are played end to end over
   the network in both campaigns and formats (two humans in separate processes, loopback). Remaining:
   a real two-PC/internet session, a multi-process test with 3-4 humans incl. group-event votes and the
   Captain's move-on, crediting a member who returns after the host left the summary, sturdier scripted
   test fighters (tests currently rely on fixed seeds 193/4), dedicated-server party runs.
2. **Bot difficulty** (AI-01, UI-12): 0.9.1 has string-aware blocks/punishes (Headliner 58 %, Hall-of-Famer 80 %
   vs a pure masher on diagnostic seeds). Target: Headliner ≥ 70 %, Hall-of-Famer ≥ 80 %, Punching Bag still loses ≥ 65 % to the masher
   (docs/BOTS.md next steps: Gusto/Slurry/Dozer-mirror habits, Journeyman re-measure) while keeping the tier
   ladder monotonic (`--bench tiers --bouts 12`). Test: `test_naive_play` (handoff material in the bots
   branch).
3. **Roster balance pass**: cross-roster round robin (`--bench roster --bouts 12 --tier pro`) had Stoke
   at 25 % and Slurry at 71 % (4 bouts/pair, before the bot changes); target 40–60 % overall, 30–70 % per
   pairing; plus reliable mashed strings for every kit (snippet: a masher must land l1-l2-l3).
4. **Server CPU** (PERF-04, target < 35 % of one core at 8 fighters): **met** on 2026-10-16.
   Packaged dedicated server, quiet machine, `test_net_measure` (1 client + 7 bots): 29.5-31.9 %
   main-thread load, duel 10-12 %. Two engine fixes got it there:
   - Godot's frame limiter busy-waited part of every frame on Windows. The server now paces its own
     frames (D-031).
   - The server export runs one physics worker thread (D-030).

   `run_verification.ps1` now checks the figure from the packaged suite. Remaining optional
   headroom: the bot history's body-surface query (0.24 ms per tick for 7 bots) and the rig's
   segment springs.
5. **Final verification** (VER-03/04/05/07, PERF-01/02/03/05, DEL-01/06): quiet machine, then
   `tools/verify/run_verification.ps1 -Build` (packaged suite, captures with exit codes, benches,
   online session check), portability check, an independent whole-brief audit, `docs/VERIFICATION.md`,
   README refresh, ledger digest (`python tools/verify/ledger_digest.py --open`), release 1.0.0-rc.1.
   A first packaged run on 0.9.1 (`docs/evidence/verification/20261015-211605`) passed boot,
   memory, all 31 captures and the frame benches. Its 21 test failures and the session-check duel
   were packaged-only test problems, fixed after 0.9.1 (NOTES.md there).

## Known issues in the current preview

- Online play tested on one PC only (loopback); 3-4 human parties only in-process.
- Some matchups lopsided; top bot tiers can be beaten by mashing.
- Linux packages built and portability-checked but not run on Linux (no Linux environment here; disclosed).
- Boot to the title is ~7.5 s packaged on this PC (target < 10 s cold).

## Working rules for resuming

- Full test suites only through `tools/dev/run_suite.ps1` (one at a time, below-normal priority).
- Releases through `tools/build/release.ps1` (`docs/RELEASES.md`).
- Merge agent branches one at a time, re-import, `--check`, full suite, then commit/push.
