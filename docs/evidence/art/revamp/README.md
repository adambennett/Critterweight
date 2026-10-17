# Creature art revamp evidence

Original and replacement models were rendered in Godot 4.5.1 Forward+ with the same preview camera, yaw (25 degrees), floor and arena-style lighting. The comparison images use a shared union crop for each pair; neither side is retouched. Source PNGs, intermediate captures and working files remain under `B:\Critterweight-art\captures`. Committed JPEGs use quality 87. [image-processing.json](image-processing.json) records source hashes and crop rectangles.

The original set is commit `ae86c73eb1a57c404f101d821170fafdf7575d1f`. All 22 original forge GLBs rebuilt byte-identically before editing. The final twelve replacements are recorded in [art-stats.json](verification/art-stats.json), with compressed editable sources in `tools/blender`. The ten optional hub/crowd models remain byte-identical to the originals.

## Per-creature review

| Creature | Before / after | In motion | Collision overlay | Effects |
|---|---|---|---|---|
| Stoke | [Comparison](f_stoke-comparison.jpg) | [Four frames](f_stoke-motion.jpg) | [Overlay](f_stoke-collision.jpg) | [Normal/Hype/JUICE/hit](f_stoke-effects-normal.jpg), [status/bruise/cosmetics/gore](f_stoke-effects-status.jpg) |
| Jitters | [Comparison](f_jitters-comparison.jpg) | [Four frames](f_jitters-motion.jpg) | [Overlay](f_jitters-collision.jpg) | [Normal/Hype/JUICE/hit](f_jitters-effects-normal.jpg), [status/bruise/cosmetics/gore](f_jitters-effects-status.jpg) |
| Dredge | [Comparison](f_dredge-comparison.jpg) | [Four frames](f_dredge-motion.jpg) | [Overlay](f_dredge-collision.jpg) | [Normal/Hype/JUICE/hit](f_dredge-effects-normal.jpg), [status/bruise/cosmetics/gore](f_dredge-effects-status.jpg) |
| Slurry | [Comparison](f_slurry-comparison.jpg) | [Four frames](f_slurry-motion.jpg) | [Overlay](f_slurry-collision.jpg) | [Normal/Hype/JUICE/hit](f_slurry-effects-normal.jpg), [status/bruise/cosmetics/gore](f_slurry-effects-status.jpg) |
| Gusto | [Comparison](f_gusto-comparison.jpg) | [Four frames](f_gusto-motion.jpg) | [Overlay](f_gusto-collision.jpg) | [Normal/Hype/JUICE/hit](f_gusto-effects-normal.jpg), [status/bruise/cosmetics/gore](f_gusto-effects-status.jpg) |
| Dozer | [Comparison](f_dozer-comparison.jpg) | [Four frames](f_dozer-motion.jpg) | [Overlay](f_dozer-collision.jpg) | [Normal/Hype/JUICE/hit](f_dozer-effects-normal.jpg), [status/bruise/cosmetics/gore](f_dozer-effects-status.jpg) |
| Bilge | [Comparison](boss_bilge-comparison.jpg) | [Four frames](boss_bilge-motion.jpg) | [Overlay](boss_bilge-collision.jpg) | [Normal/Hype/JUICE/hit](boss_bilge-effects-normal.jpg), [status/bruise/cosmetics/gore](boss_bilge-effects-status.jpg) |
| Conduit | [Comparison](boss_conduit-comparison.jpg) | [Four frames](boss_conduit-motion.jpg) | [Overlay](boss_conduit-collision.jpg) | [Normal/Hype/JUICE/hit](boss_conduit-effects-normal.jpg), [status/bruise/cosmetics/gore](boss_conduit-effects-status.jpg) |
| Snappington | [Comparison](boss_snappington-comparison.jpg) | [Four frames](boss_snappington-motion.jpg) | [Overlay](boss_snappington-collision.jpg) | [Normal/Hype/JUICE/hit](boss_snappington-effects-normal.jpg), [status/bruise/cosmetics/gore](boss_snappington-effects-status.jpg) |
| Scrapling | [Comparison](npc_scrapling-comparison.jpg) | [Four frames](npc_scrapling-motion.jpg) | [Overlay](npc_scrapling-collision.jpg) | [Normal/Hype/JUICE/hit](npc_scrapling-effects-normal.jpg), [status/bruise/cosmetics/gore](npc_scrapling-effects-status.jpg) |
| Blister | [Comparison](npc_blister-comparison.jpg) | [Four frames](npc_blister-motion.jpg) | [Overlay](npc_blister-collision.jpg) | [Normal/Hype/JUICE/hit](npc_blister-effects-normal.jpg), [status/bruise/cosmetics/gore](npc_blister-effects-status.jpg) |
| Kid Lamprey | [Comparison](npc_kid_lamprey-comparison.jpg) | [Four frames](npc_kid_lamprey-motion.jpg) | [Overlay](npc_kid_lamprey-collision.jpg) | [Normal/Hype/JUICE/hit](npc_kid_lamprey-effects-normal.jpg), [status/bruise/cosmetics/gore](npc_kid_lamprey-effects-status.jpg) |

Motion sheets show 20/23/26/29 seconds of each creature fighting Stoke. Blister uses 8/9/10/11 seconds because its self-pop can end the duel before the standard window. These are sampled live ragdoll poses, not authored animation or exhaustive coverage of every attack. Reviewed contact parts remain on their owning segments; no obvious stretched skin or remote fists/heads/tails was found in the sampled poses.

Effect rows read left to right in the order shown in the links. Team colour alternates red/blue. All twelve gore fixtures log a spawned piece with one mesh. Bruise visibility depends on surface and angle: Stoke's face is a clear example; a muzzle may occlude the head-shape sample on other creatures. Cosmetic fixtures cover tooth, lid, belt and scarf. The unchanged roster cosmetic tests pass; boss/minion fixtures are exploratory visual checks, not additional roster test coverage.

## Cast walls and fight-camera readability

| Category | Before | After |
|---|---|---|
| Six fighters | [Wall](before-wall-fighters.jpg) | [Wall](after-wall-fighters.jpg) |
| Three bosses | [Wall](before-wall-bosses.jpg) | [Wall](after-wall-bosses.jpg) |
| Three minions | [Wall](before-wall-minions.jpg) | [Wall](after-wall-minions.jpg) |
| Eight retained hub NPCs | [Wall](before-wall-hub.jpg) | [Wall](after-wall-hub.jpg) |
| Two retained crowd fans | [Wall](before-wall-crowd.jpg) | [Wall](after-wall-crowd.jpg) |
| Duel, 1920x1080 | [Capture](before-duel-1920x1080.jpg) | [Capture](after-duel-1920x1080.jpg) |
| Duel, 1280x800 | [Capture](before-duel-1280x800.jpg) | [Capture](after-duel-1280x800.jpg) |
| Eight fighters, 1920x1080 | [Capture](before-busy-1920x1080.jpg) | [Capture](after-busy-1920x1080.jpg) |
| Eight fighters, 1280x800 | [Capture](before-busy-1280x800.jpg) | [Capture](after-busy-1280x800.jpg) |

[48 px silhouette comparison](silhouettes-48px.jpg): each silhouette fits in a 48x48 canvas, alongside a 3x nearest-neighbour enlargement. The six fighter body plans remain distinct. Slurry and Conduit intentionally share a serpent plan; scale, palette and hazard bands distinguish the boss in-game. This is an art review, not a blind recognition study. Small crests and gavel details are less prominent because they were brought into the unchanged collision envelope.

Foreground cage rails and the bottom HUD obscure some fighters in the busy scene, especially at 1280x800. Those existing camera/UI limits are recorded under Requests for Claude in [ART_REVAMP.md](../../../ART_REVAMP.md). No claim is made that all eight fighters stay unobstructed in every view.

## Budgets and reproducibility

The twelve GLBs contain 122,724 triangles including detachable pieces (originals: 143,260), occupy 4,707,268 bytes (originals: 8,092,892), and use no textures. Compressed `.blend` sources total 9,105,085 bytes. Each model meets its inclusive fighter/boss/minion budget. Maximum skin influences: two.

[Model audit](verification/model-audit-final.json), [saved-source re-export](verification/export-determinism.json), [retained forge rebuild](verification/retained-forge-determinism.json). The rest-space vertex diagnostic peaks at 5.9 cm outside the union of colliders; it does not prove triangle interiors or every simulated pose. The collision and motion evidence above complements it. No gameplay JSON or move data changes.

## Performance and tests

The separated first after run was slower (Deck 185.322 fps / p95 8.582 ms; High 154.512 fps / p95 9.468 ms), so it was retained and investigated with a consecutive **original/new/new/original** comparison under one shared lock. Two runs per model set/preset, using the same busy-scene code, gave:

| Preset / resolution | Original mean fps | New mean fps | Original mean run p95 | New mean run p95 | Frames >16.7 ms, original → new |
|---|---:|---:|---:|---:|---:|
| Deck / 1280×800 | 173.820 | 189.987 | 9.697 ms | 8.691 ms | 0.978% → 0.535% |
| High / 1920×1080 | 180.002 | 209.455 | 10.378 ms | 8.176 ms | 1.463% → 0.239% |

These are means of the two run fps/p95 values, not a pooled p95. The paired aggregates show no regression in these metrics, with fewer draw calls/primitives and lower video memory. Individual runs vary substantially with the shared machine; this is not a claim of a precise causal speedup. [Performance summary](verification/performance-summary.json) and [every raw paired run](verification/paired-bench/) are retained alongside the initial measurements.

All runs use the same busy-scene implementation, seed 7, eight fighters, five-second warmup and thirty-second measurement on an i7-7700K / RTX 4070 Ti SUPER. These are desktop Deck-preset and High-preset results, not Steam Deck hardware measurements.

Content audit 5/5, content targets 7/7 and hub cosmetics 6/6 passed before and after (18 targeted checks). All 378 scripts compile. The same targeted checks pass after merging `origin/main` (`48139c7`) at `12b11b42d55826b5150031e7f5dc3b1cb251305d`; the unfiltered full suite passed at that commit: **684/684, zero failures, 0 skipped** (42.4 minutes). Subsequent changes are final documentation/evidence only. [Full output](verification/art-full-suite.txt) and [run metadata](verification/art-full-suite-run.json). Logs, commands and JSON results live in [verification](verification/). Tests are run only through `tools/dev/run_suite.ps1` at BelowNormal with the B: test root; the final unfiltered suite preserves default TEMP and shares the machine-wide lock.

Reproduction commands and source/provenance details: [ART_PIPELINE.md](../../../ART_PIPELINE.md). Concepts and exact generation prompts: [concepts](../concepts/).

The full run exits 0 but prints a Jolt maximum-job warning and ObjectDB/5-resources-in-use shutdown diagnostics. The same diagnostics and count are present in the earlier [packaged-test baseline](../../verification/20261016-115413/packaged_tests.log.err); they are preserved in the full-suite output above.

The committed full-suite text removes trailing whitespace only. The original runner log remains at `B:\Critterweight-art\captures\art-full-suite.log`.
