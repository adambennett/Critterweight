# Progress

## Current milestone (2026-10-15)
M3 — integration: merging the parallel owners' systems into `main`, finishing fighter kits, hub, Linux and
performance checks, then the packaged-build audit (`docs/REQUIREMENTS.md` is the per-requirement ledger).

## Integrated on `main`
- **Engine**: active-ragdoll rig (Jolt 6DOF springs, 120 Hz), IK/gait motor, fighter state machine,
  contact-validated combat, effects/statuses/elements/reactions/zones, hooks DSL, rule-level hooks, gravity,
  cage containment (collision walls now match the fence), spawn/despawn with slot reuse.
- **Modes**: standard rounds/FFA/teams/co-op, Spotlight Hog, Chumball, Absolute Unit, Chum Rush, Tag Team,
  Practice, Tutorial; 15 core rules presets.
- **Content/art/audio**: creature forge (6 fighter bodies + models, 2 minions, 3 bosses, 8 hub NPCs, fans);
  synthesized score, 312 SFX ids, babble voices, announcer bridge wired into every match.
- **UI**: theme + widget library, title/main menu/settings/profile/credits/pause/results/versus/character
  select/spectate/tutorial menu, rules editor, mods screen, HUD (≥ 18 px at 1280×800, 5–8 fighter grid).
- **Systems**: mods (data-only packages, validation, sets, sharing, examples), rules presets, tutorial (10
  exercises), spectator director, platform boundary + local achievements, packaging script, bench harness.
- **Tests**: 76 automated tests (`godot --headless --path game --fixed-fps 120 -- --test`), all passing.

## In flight (parallel owners, worktree branches)
- Fighter kits: Stoke+Gusto, Dredge+Dozer, Slurry+Jitters.
- Networking/servers/playlists, AI Lab, campaign (both variants, co-op, Bookie's Table), arenas + editor.

## Next concrete actions
1. Merge each finished branch, resolve conflicts, rerun the suite, recapture evidence.
2. Hub (The Cannery) on top of the campaign services; Kid Lamprey sparring kit; minion/boss kits.
3. Wire playlists/hosting to user presets and mods compatibility (`Mods.compare`).
4. Performance captures on a quiet machine (`--bench busy|sim|soak`), Linux checks, packaged-build audit,
   README/PLAYER_GUIDE/VERIFICATION, final evidence digest.

## Blockers / notes
- Linux runtime checks need a Linux userland (none installed; Docker engine absent). Building the Linux
  export works here; running it is an external check unless a local Linux environment becomes available.
- Benchmarks taken while seven agents share the CPU are noisy; final numbers will be re-captured.
