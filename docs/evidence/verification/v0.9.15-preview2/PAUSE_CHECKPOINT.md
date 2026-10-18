# v0.9.15 preview 2 — paused checkpoint

Paused at the owner's request on 2026-10-18 so Halo can use uncontested system resources. Do not resume tests, image generation, builds or other implementation work until the owner asks to resume.

## Process shutdown

Stopped queued follow-up checks first (PowerShell PID 31032), then the full-suite engine and console wrapper (5836 / 17620), plus owned networking test children (7228 / 20260 / 14644). Confirmed zero preview2 Godot processes remain. The suite wrapper exited. No graphical game was launched.

## Workspace and delivery state

- Repository: B:/Critterweight/PokeMMA-v0.9.13, branch preview/v0.9.15; starting HEAD 5c96fc8. Current batch is saved but uncommitted. Preserve every current modification and untracked asset; no reset/clean.
- All work/build/download/temp files stay on B:. The owner allowed generated-image outputs to land briefly on C: and be moved immediately to B:; all 29 illustrations are already transferred.
- v0.9.14 is still the published release. Do not publish or tag this work.
- The OLD verified executable remains B:/Critterweight/release-work/v0.9.15-preview/Critterweight-0.9.15-preview.exe. It only includes the earlier monitor and menu-tick fixes.
- The NEW intended executable is B:/Critterweight/release-work/v0.9.15-preview2/Critterweight-0.9.15-preview.exe. It has NOT been built. Do not direct the owner to the old build as though it contained this batch.
- Logs are in B:/Critterweight/release-work/v0.9.15-preview2. TEMP/TMP should be B:/Critterweight/tmp.

## Implemented scope, awaiting final verification

The complete change list is in docs/releases/v0.9.15-preview2.md. This batch implements editor menu/canvas controller separation, menu focus and save safeguards; custom arena edit/delete confirmations; New Rules Cancel removal; offline patch notes; a scrollable campaign route chart with new icons; unique artwork for all 29 events and persistent run stats; campaign modal/abandon fixes; top-aligned fight health and separate subtitle space; cooldowns on input glyphs; spectator invert Y; per-context jukebox playlists; a live red/green crate-toss line; shared fighter information panels and right-stick scrolling; no menu ambience and restored pre-v0.9.13 combat crowd; compact team setup columns. Earlier monitor persistence and the approved single quiet menu tick remain.

Artwork is under game/assets/art/events. Exact prompts and hashes are in docs/evidence/art/events/prompts.json. All 29 masters were inspected, their hashes matched the manifest, and total PNG size was 76,348,895 bytes. In-game composition still needs owner review. No external reference image was submitted to the image generator.

## Verification completed before pause

- Source check: 400 scripts, zero failures (check-final.log), before the latest small follow-up edits listed below.
- New preview regression suite: 13 run, 13 passed (target-new6.log), before those follow-up edits.
- Existing playtest UI regression: 8 run, 7 passed, 1 expected headless skip (target-ui.log).
- Audio generation/inventory checks passed: 636 generated files, approximately 128.8 MB. Original crowd assets were verified unchanged against v0.9.12; the replacement overrides were removed. The approved fixed-pitch tick_001 at -14 dB remains.
- Full suite (suite-final.log) was deliberately interrupted at the owner's request. It is NOT a passing complete run. Hundreds of tests passed; there were two known failures whose fixes have not yet been rerun.

## Known failures and edits requiring fresh checks

1. test_campaign_ui::test_controller_walks_the_map_and_screens_to_the_summary exposed a summary heading lookup that assumed the heading was child zero before the new run-stat strip. Fixed source by naming the scaffold heading Heading and resolving it by name. Needs a fresh process test.
2. test_net_measure::test_measure_duel_and_ffa8 expected 2 fighters but measured 0: the duel ended by normal KO before the measurement window finished. Log timing established this. Fixture now uses health_mult 4 and damage_mult 0.25 to keep the match alive; assertions remain unchanged. Needs a fresh network measurement test.
3. Latest unverified refinements: editor menu-mode footer and minimized sidebar retain menu mode; Compendium removes the duplicate fighter heading; hub music calls consistently pass hub context; menu silence stops all Crowd-bus players including fading loops and pooled reactions; HUD hides despawned wave cards and refreshes reused fighter names.
4. Regression assertions were added for minimized sidebar focus, fading crowd silence, and wave-card reuse. The running full suite had cached old scripts, so it cannot validate these edits.

## Resume sequence

1. Read AGENTS.md, this checkpoint, git status, and current processes. Do not disturb other work. Continue on B: without launching the graphical game.
2. Run a fresh headless source check and targeted suites for ui, audio, settings, hub_flow and test_net_measure; inspect SCRIPT ERROR output as well as exit codes. Resolve failures before claiming verification.
3. Run the required full suite using tools/dev/run_suite.ps1 only, one Godot test job at a time at BelowNormal priority. Networking child processes can start at Normal priority, so check them. The interrupted suite must not be described as green.
4. Finish verification evidence and requirements ledger honestly (I/T/B distinctions), update progress, and commit only after required checks pass. Commit footer: Co-Authored-By: Codex <codex@openai.com>.
5. Build the local Windows Desktop package with tools/build/package.ps1 into B:/Critterweight/release-work/v0.9.15-preview2/package. Do not use release.ps1, which publishes/launches. Do not repeat all tests through packaging unnecessarily.
6. Copy the packaged executable to the intended preview2 path, verify SHA256, and run packaged headless checks/regressions. Use ProcessStartInfo.ArgumentList for executable arguments; never use the reserved PowerShell $Args variable. No graphical launch.
7. Record the actual build/hash and test results. Final handoff must include the new executable path, remaining physical-controller/visual/audio playtest boundaries, research answers, and Cancel candidates below.

## Research completed; no code mods or paid voice generation authorized

Code mods: ModManager explicitly rejects scripts, engine extension libraries, PCK/scene/resource/shader formats and script capabilities. The data-only message is accurate and is a loader policy, not a Godot limitation. A trusted opt-in script API is possible but requires versioned hooks, compatibility, multiplayer/determinism/replay rules and clear trust boundaries; native GDScript is not a strong OS sandbox. Rough estimates: 1–2 engineering weeks for a limited prototype, 4–8 for a supported ecosystem; a strong sandbox is a larger project. Official reference: https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html . Do not implement this unless separately requested.

Breeze references inspected read-only in B:/git/ThirdAgeModern: audio/voice/voice-registry.json, Design/Product/Production/Voice_Production_Workflow.md, and .agents/skills/breeze-voice-production/scripts/generate_lines.py. Stable line/take ledger, owner-selected voice IDs, weighted-character dry run and no blind retries are useful precedents. No API calls, voice generation or credits spent.

Current authored inventory: Barnaby announcer 163 lines / 9,585 characters; vintage 28 / 1,507; Granny 40 / 3,372. Total announcer scripts: 231 unique lines / 14,464 characters; 26 contain dynamic placeholders. Across the current core spoken-content inventories there are 491 authored entries, 470 unique (speaker,text) pairs and 31,553 characters across 8 speaking roles. Excludes non-spoken event UI, mod content, custom-name expansions and future easter eggs. Unique counts by speaker: Barnaby 223, Granny 107, Ludlow 34, Snappington 25, Teddy 21, Kid 21, Doc 20, Needles 19.

Official pricing was checked at https://breezeblue.ai/pricing : 1 credit per 10 weighted characters (CJK counts double). Baselines: announcers 1,446.4 credits; whole core 3,155.3 credits. Practical budgets: about 2,000 / 4,000 first pass, or 3,000–4,000 / 6,000–8,000 allowing retakes and name variants. Exact expansion cost depends on the chosen name strategy. Terms at https://breezeblue.ai/legal/terms (effective September 10, 2026, section 5d) require an active paid subscription at generation for commercial use of library outputs; the rights survive cancellation. Free/top-up generation without an active paid subscription is noncommercial. Recheck if significant time passes.

User's proposed Devon (voc_g53htd8kmjsj) is the likely Barnaby lead and Kendall (voc_j66xnnsxfeet) the comic/Granny audition based on the owner's description; these have NOT been auditioned by this agent. Two voices cover existing commentary/coach, three if adding a separate color commentator, eight for the full current speaking cast. Player 1–8 / Rookie / selected fixed names can replace custom names; whole sentence recordings avoid audible splice seams. Easter-egg names remain a later choice.

## Duplicate Cancel candidates for owner review (unchanged)

- Rules preset actions and Rules import chooser.
- Arena editor New base, Load, Import and Test play choosers; Controls Close and Back to editing are related candidates.
- Shared text-entry dialogs used for profile/name/seed.
- Mods Rename Set and controller Import downloads chooser.

Keep intentional cancel choices in destructive delete/reset/uninstall confirmations. AI Lab cancel-job actions are not redundant menu dismissal.
