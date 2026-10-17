# Progress

## Status (2026-10-16) — paused for the playtest week at v0.9.7

Work is **paused at a playable preview**, not at the finished release candidate. The latest build is
published as a GitHub pre-release (see `docs/RELEASES.md`). The goal stays open: the items under
"Remaining for the release candidate" must be done before a completion audit can pass.

**Fixed in v0.9.6 (2026-10-16).** Astra reviewed the code and found two bugs:
- Chum Rush supplement picks did nothing: the mode read a format no supplement uses. The mode now applies
  the campaign format, and offers only OTC and Prescription supplements, never side effects.
- Chumball counted KOs as goals.
Also fixed: the rooftop railings and bot steering (Swarm Night, below). All have regression tests.

**Audio revamp in parallel (from 2026-10-16).** The user has a separate agent (Astra, in the Codex app)
re-producing the music and sound in Ableton Live 12. It works in its own clone on the B: drive, on the
branch `audio/ableton-revamp`, and ends in a draft pull request. It changes only the audio area
(`game/assets/audio`, `tools/audio`, `game/src/audio`, the audio tests and docs). Decision number
**D-040** is reserved for its audio decision, which supersedes D-013 for the replaced assets. The pull
request is merged into `main` only after the user approves it by listening, followed by a green full
suite. Don't edit audio files on `main` meanwhile.

**Creature art revamp in parallel (from 2026-10-16).** A second Astra agent redesigns the creature models.
It works in its own clone at B:\Critterweight-art, on the branch `art/creature-revamp`, and ends in a draft
pull request. It changes only the forge definitions, the generated models, view-side code and the art docs,
never the creature bodies, stats or moves. Decision number **D-041** is reserved for its art decision.
Merge it after the user approves and a full suite passes.
**The user's instruction (2026-10-16): don't merge the art pull request straight away.** First publish a separate
"alt" pre-release built from `main` plus that branch, so the user can compare the two builds side by side.
For example, a local `alt/creature-art` branch tagged `v<next>-alt.1`. Note that `release.ps1` releases
from `main` only, so it will need a branch option. Merge into `main` only if the user picks the new art.

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

## UI polish pass (2026-10-16)

On request, every menu and in-game screen was screenshotted at 1600x900 and 1280x800 and polished. Done:
- **Campaign screens.** The Fight Card and the Bookie's Table setup were rebuilt on the shared menu kit
  (option rows, help panel, prompt bar), so they match Versus and Settings. Reward and rest cards no longer
  stretch. The run summary is tidied and its subtitle glitch fixed. Route-map labels are larger, and the
  Ledger's chips and Back button are cleaned up.
- **Tutorial.** The coach box covered the controls bar at every resolution.
- **Mods screen.** Its buttons overflowed at 1280x800.
- **Campaign menu.** Labels collapsed at 1280x800.

Checked and fine: main menu, character select, versus/spectate, settings, online, the lobby (hosted),
profile, rules and arena editors, AI Lab, credits, pause, the results card, the fight HUD (duel and
8 fighters), the hub, the event and shop screens. Evidence is in
`docs/evidence/verification/presets-20261016`.

The capture tool for screens that need game state (`test_zz_capture_ui.gd`: windowed run, CAPTURE_UI_DIR)
is in the session scratchpad's balance_handoff folder, not in the repo.

Possible follow-ups: the AI Lab shows internal ids ("Dozer (f_dozer)"); the campaign modal dialogs
(CampaignUI.confirm) still use the older campaign style.

## Remaining for the release candidate (exact next actions)

1. **Online co-op follow-ups** (COOP-01..06 mostly done). Party runs are played end to end over the network
   in both campaigns and formats (loopback):
   - two humans in separate processes;
   - since 2026-10-16, **three and four**:
     - `test_party_run_three_players_majority_route` seats a host plus two members, each with their own
       fighter, and three human-driven fighters fight together. A route vote splits 2-1 and the majority
       decides.
     - `test_party_run_four_players_captain_breaks_tie` does the same with four humans. The vote ties
       2-2 and the Captain breaks it.
     - In both, each profile is credited once.

   Remaining:
   - a real two-PC/internet session;
   - a group event decided by vote;
   - the Captain's "move on" for an idle member (no pilot hooks yet: an idle-at flag for a member and a
     move-on press for the host);
   - crediting a member who returns after the host left the summary;
   - sturdier scripted test fighters (tests rely on fixed seeds 193/4);
   - dedicated-server party runs.
2. **Bot difficulty** (AI-01, UI-12): **top tiers met** on 2026-10-16 (D-032, D-033, docs/BOTS.md).
   Acceptance seeds against a pure masher:
   - Headliner 17 / 24 (77 % on 48 bouts), target ≥ 70 %;
   - Hall-of-Famer 20 / 24 (88 % on 48), target ≥ 80 %;
   - Punching Bag loses 23 / 24, so it stays forgiving.

   The ladder is ordered. Still open: the Journeyman wins only 5 / 24 (target "about even", 25-75 %); its
   reaction cannot block a jab stream. The Dozer mirror is still the hardest kit for the Headliner.
3. **Roster balance pass**. Measured 2026-10-16 with the new bots:
   `--bench roster --bouts 12 --tier pro`, The Gullet, mirrors included.

   Overall win rates, target 40-60 %:

   | Fighter | Win rate |
   |---|---|
   | Dozer | 56 % |
   | Dredge | **38 %** |
   | Gusto | 43 % |
   | Jitters | 57 % |
   | Slurry | 60 % |
   | Stoke | 46 % |

   Earlier: Stoke 25 %, Slurry 71 %. 7 of 15 pairings are outside 30-70 %:

   | Pairing | Result |
   |---|---|
   | Slurry over Dredge | 12-0 |
   | Stoke over Gusto | 11-1 |
   | Dozer over Jitters | 11-1 |
   | Jitters over Stoke | 11-1 |
   | Slurry over Dozer | 9-3 |
   | Dozer over Dredge | 9-3 |
   | Slurry over Stoke | 9-3 |

   Diagnose each extreme pairing the way the masher work did (per-bout hits / states, then kit or AI
   personality), with the user's playtest feedback first.

   Started on Slurry vs Dredge with `--bench roster --pair f_dredge,f_slurry`: Slurry lands about 50 hits a
   minute at about 4 damage each against Dredge's 13 at 5, out-damaging him about 3:1. Giving Dredge's bot
   `avoid_zones` changed nothing (still 0-12), so the puddles are not the cause. A per-move breakdown
   (4 Contender bouts) found the cause: Slurry's **L1 Head Butt** landed 37 times for 213 damage, against
   7 Dredge L1 hits. The jab starts in 0.09 s against Dredge's 0.16 s, and it reaches 1.7 m root gap with a
   3 m/s lunge against Dredge's 1.55 m. So Slurry wins every jab exchange from just outside Dredge's range.
   **Done (2026-10-16, D-034):** Slurry's L1 hit window now opens at 0.13 s (was 0.09) and its lunge is
   2.4 m/s (was 3.0). Dozer vs Slurry is 6-6 (was 3-9) and Slurry vs Stoke 7-5 (was 9-3), but Dredge vs
   Slurry is still 0-12, so a second cause sits in Dredge's own play. Slurry's jab still lands 35 times against
   5 for Dredge's. Dredge's bot holds 1.25-1.6 m, where Slurry's lunge reaches and Dredge's claw does not.
   Tried at 12 bouts per pairing; neither variant was a clear win, so Dredge is unchanged:
   - range 1.05-1.4 m with aggression 0: Slurry 3-9, Dozer 6-6, Stoke 8-4, Gusto 5-7, but Jitters 1-11 (was 4-8);
   - range 1.15-1.5 m: Slurry 1-11, Jitters 3-9, Dozer 9-3.
   Next: per-opponent spacing, or Dredge's kit reach, measured on 36-bout pairings.
   **24-bout baseline (2026-10-16, pro tier, after D-034):** Dredge has the slowest jab in the roster: 0.16 s,
   against Dozer 0.14, Slurry 0.13, Stoke 0.12, Gusto 0.09 and Jitters 0.06. His records:
   - Slurry 1-23;
   - Dozer 12-12;
   - Jitters 6-18;
   - Stoke 14-10;
   - Gusto 9-15.
   That is 35 % overall.

   **Tried and reverted:** a jab at Dozer's speed. The hit window moved to 0.14-0.22, the windup keys about
   0.02 s earlier, and the lunge went from 2.0 to 2.4 m/s. Results: Slurry 0-24, Dozer 9-15, Jitters 6-18,
   so jab speed is not the lever. Look at Dredge's AI next (he holds 1.25-1.6 m, inside Slurry's lunge) or at
   his kit reach.

   Per-move breakdowns of the other extreme pairings (4 Contender bouts each, different seeds):
   - **Jitters vs Stoke 4-0.** Stoke's jab lands 7 times against Jitters, against 19 times on Gusto. Jitters
     outhits him with L1 21x, L2 12x, arc lash and squash landings. Stoke's strikes seem to miss the small
     body.
   - **Gusto vs Stoke 1-3.** Gusto's projectile does most of its damage (32 hits, 191); Stoke wins with
     L1 19x and heavy.
   - **Dozer vs Jitters 2-2**, against 11-1 in the round robin.

   **Swarm Night, resolved 2026-10-16:** the seed-1002 Fight Camp test run with Dredge lost Act 3's Swarm
   Night on the rooftop. It wasn't damage: Dredge took 15-26 HP. Bots on both sides stood still for minutes,
   then sudden death dropped Dredge to 1 HP and a minion finished him. Two causes, both fixed:
   - **Level bug:** the rooftop's two railings had a quarter turn too much (`ArenaDef` yaw of spanning
     edge builtins). They lay across the floor from each short side toward the middle and, with the HVAC
     units, fenced the arena in half. This was visible in play too.
   - **Bots didn't steer round props.** They now bend along a prop face in their way, and two bots on
     opposite sides go round the same side (docs/BOTS.md).
   Seeds 1002-1004 now clear the fight in 20-60 s, and the full-run test is back on seed 1002 as the
   regression check.

   Seeds swing these pairings far more than the ±14 % a 12-bout sample suggests. **Measure on 36 or more
   bouts before tuning any of them.** The other options were:
   - Slurry L1 start-up 0.09 to about 0.12 s, or a shorter lunge;
   - or Dredge's bot keeping a closer range than its [1.25, 1.6] m.

   Breakdown tool: `test_zz_diag_pair.gd`, in the session scratchpad's balance_handoff folder (DIAG_A /
   DIAG_B / DIAG_TIER env).

   Also needed: **reliable mashed strings for every kit.** A roster-wide test, kept out of the suite until
   the kits are tuned, has the masher stand where his first jab reaches, mash Light for 2 s against a
   standing dummy and check l1-l2-l3. Results on 2026-10-16:
   - Gusto: nothing lands;
   - Dozer: l1 only;
   - Jitters: misses l1;
   - Slurry: misses l2;
   - Stoke: misses l3;
   - Dredge: all three.

   The results swing with the starting distance, because each strike's knockback pushes the target out
   of the next strike's reach. Tune string knockback and lunges per kit so a mashed string connects. The
   test is `test_mash_strings.gd`, in the session scratchpad's balance_handoff folder; recreate it from
   this description if it is gone.
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

- Online play tested on one PC only (loopback); 3-4 human parties tested in separate processes on that PC.
- Some matchups lopsided (roster balance pass pending); the Journeyman bot still loses to button-mashing (the top tiers beat it since 2026-10-16).
- Linux packages built and portability-checked but not run on Linux (no Linux environment here; disclosed).
- Boot to the title is ~7.5 s packaged on this PC (target < 10 s cold).

## Working rules for resuming

- Full test suites only through `tools/dev/run_suite.ps1` (one at a time, below-normal priority).
- Releases through `tools/build/release.ps1` (`docs/RELEASES.md`).
- Merge agent branches one at a time, re-import, `--check`, full suite, then commit/push.
