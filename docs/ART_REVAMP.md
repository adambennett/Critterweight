# Creature art revamp

Status: **adopted 2026-10-17.** The user compared the alt builds (0.9.8-alt.1, 0.9.9-alt.1) with the main builds and chose this art. PR #1 is merged into `main` and ships from 0.9.10, with D-041 and the requirement updates below applied to `docs/DECISIONS.md` and `docs/REQUIREMENTS.md`. The requests below are handled: the cage and HUD occlusion was fixed in 0.9.9 (`docs/PROGRESS.md`), and the in-game credits (`game/assets/ui/credits.json`) match `docs/CREDITS.md`. Gameplay data is unchanged. The text below is the art branch's original record.

## Plan and scope

Use original Blender meshes to replace swollen SDF junctions, noisy colour boundaries and hard-to-read faces. Keep each creature's identity, palette, body plan and signature props. The immutable collision geometry sets the proportions: the concepts guide expression and shape language, not hit reach. Retain vertex-colour albedo/glow and the shared toon shader.

Work order: six fighters; Bilge, Conduit and Snappington; Scrapling, Blister and the sparring Kid Lamprey. Take Stoke through source, reproducible export, import, preview, live fight and tests first, then apply the verified path to the cast. Preserve the ten optional hub/crowd originals. Complete identical-camera comparisons, silhouette/contact/effect checks, desktop benches, targeted tests and one locked full suite before opening a draft PR.

## Per-creature decisions

All twelve combat models use compressed editable Blender sources. Historical forge definitions remain available with `--legacy --out <scratch>`; default forge builds preserve Blender-owned outputs.

| Creature | Original issue | Adopted visual treatment | Tool / decision |
|---|---|---|---|
| Stoke | Swollen shoulder junctions and boiler; unclear eyes | Fitted furnace plate, confident newt face, clean fist wraps and separated elbows | Blender; adopt |
| Jitters | Crowded cap/coil forms and vague face | Nervous eyes, pale jelly window, curved luminous coil fitted to the body | Blender; adopt |
| Dredge | Shell/claws read as rounded lumps | Cleaner carapace, open crusher/cutter contrast, weary stalk eyes, chain on the crusher | Blender; adopt |
| Slurry | Inflated neck/head junction and muddy collars | Continuous tapered moray body, crisp brass collars, fangs and sly mouth | Blender; adopt |
| Gusto | Lumpy wing roots and noisy feather edges | Clean head, compact quiff, narrow feather vanes, three-toed feet and shin tape | Blender; adopt; wing width remains constrained by the existing capsules |
| Dozer | Overstuffed armour and unfocused head | Fitted shoulder scutes, friendly eyes and nose, curved shovel face and headlamp | Blender; adopt; torso volume remains the gameplay body |
| Bilge | Dense neck junctions and unreadable face | Sweet hound eyes, clear jaw/drool, smooth neck and fitted chain collar | Blender; adopt |
| Conduit | Swollen repeated segments and broken hazard paint | Continuous electrical serpent, crisp hazard bands, fitted copper crown and plug | Blender; adopt |
| Snappington | Unclear shell hierarchy, glasses and gavel | Clean shell seams, stern beak/eyes, fitted glasses, visible short gavel on the right claw | Blender; adopt; gavel stays inside the existing reach |
| Scrapling | Detail noise at small scale | One strong goggle, cheeky tooth, pipe/lid asymmetry and simple tin body | Blender; adopt |
| Blister | Undifferentiated egg mass | Clean sac, anxious face, two nubs and glowing vein accents | Blender; adopt |
| Kid Lamprey (combat) | Hood/face merge, jagged tooth ring | Crisp hood rim and collar, readable sucker mouth, simple sleeves/tail and rounded sneaker corners | Blender; adopt; deliberately lower detail to meet the 2k minion budget |
| Eight hub NPCs | Optional consistency pass | Original models retained; no replacement was developed and verified to be better | Existing forge; retain |
| Two crowd fans | Background scale and low cost | Original silhouettes retained | Existing forge; retain |

## Contract and measured budgets

`model-audit-final.json` checks GLB 2.0, exact bone names/pivots/inverse binds, normalized skin weights, normals/colours, team material, emissive hints and an unskinned KO piece. All twelve pass. The models use at most **two influences per vertex**, no textures and no keyframed animations. `export-determinism.json` records byte-identical re-export from all twelve saved `.blend` files and unchanged retained GLBs.

The twelve GLBs total **4,707,268 bytes**, down from **8,092,892 bytes**. Inclusive triangle count falls from **143,260 to 122,724**. Editable compressed sources total **9,105,085 bytes**, including hidden original-mesh registration references. Individual counts are in [CREATURES.md §4](CREATURES.md#4-models-blender-adoption-and-retained-forge-output).

The rest-space vertex audit reports at most **5.9 cm** outside the union of the existing body shapes; per-model 95th percentiles are 1.6–3.8 cm. This is a diagnostic of exported surface vertices, not proof of every triangle interior or every simulated pose. Collision overlays and live motion review complement it. Slimmer limbs still cover their capsules; contact parts remain attached to the owning segment. No body, masses, joints, weapons, stats, moves, poses or timings are edited.

The runtime change is limited to omitting the inflated outline pass on `detail_` materials. Facial details still use the same shader, lighting, flash, JUICE, Hype, status and bruise effects. The shader itself is unchanged. Preview-only additions provide reliable standalone startup, correct world placement for cosmetic inspection, Hype before rendering, silhouettes, collision overlays and effect fixtures.

## Evidence and verification

- Base before comparison: `ae86c73eb1a57c404f101d821170fafdf7575d1f` (0.9.6). All **22** original forge outputs rebuilt byte-identically before editing.
- Baseline tests: content audit 5/5; content targets 7/7; hub cosmetics 6/6. Final targeted rerun: **18/18 pass**; script compile check **378 scripts, zero failures**. Every test run uses `tools/dev/run_suite.ps1` and the B: test root.
- Concepts: [thirteen sheets for twelve creatures](evidence/art/concepts/) with [exact prompts/provenance](evidence/art/concepts/prompts.json). The second Kid Lamprey sheet corrects the turnaround views. Original PNGs remain in `B:\Critterweight-art\concepts`.
- Before captures were regenerated after correcting the preview framing/Hype setup: five category walls, all 22 individual models, duels and eight-fighter scenes at 1920×1080 and 1280×800, plus twelve silhouettes. Sandbox shots use 20 seconds so they show combat rather than the introduction. The new models were restored and imported automatically afterward.
- Final [before/after gallery, five cast walls, collision/effect fixtures, live motion sheets and 48 px silhouettes](evidence/art/revamp/README.md) are complete and visually reviewed. The six fighter body plans remain distinct; Slurry and Conduit share a serpent plan and rely on scale/colour details. No obvious skin drift was found in the sampled combat poses. Blister was recaptured at 8–11 seconds, with focus-loss pausing disabled only in its isolated capture profile. Performance results are below.
- Merged `origin/main` at `48139c7` without conflict; tested merge commit is `12b11b42d55826b5150031e7f5dc3b1cb251305d`. Import, 378-script compilation and the 18 targeted tests pass again. The unfiltered full suite completed with **684/684 passed, zero failures and 0 skipped** in 42.4 minutes, using default TEMP and the isolated B: root. [Full output](evidence/art/revamp/verification/art-full-suite.txt) and [run metadata](evidence/art/revamp/verification/art-full-suite-run.json) record the check. Subsequent commits contain final documentation/evidence only. Release packaging, merging and shipping remain Claude's work after user approval.

Baseline busy benchmark: i7-7700K / RTX 4070 Ti SUPER, Godot 4.5.1 Forward+, eight fighters, seed 7, five-second warmup and thirty-second measurement. Deck preset at 1280×800: **215.936 fps**, frame p95 **7.362 ms**. High at 1920×1080: **186.047 fps**, p95 **7.914 ms**. These are desktop measurements with those presets, not Steam Deck hardware results.

The separated first after run was slower (Deck 185.322 fps / p95 8.582 ms; High 154.512 fps / p95 9.468 ms), so it was retained and investigated with a consecutive **original/new/new/original** comparison under one shared lock. Two runs per model set/preset, using the same busy-scene code, gave:

| Preset / resolution | Original mean fps | New mean fps | Original mean run p95 | New mean run p95 | Frames >16.7 ms, original → new |
|---|---:|---:|---:|---:|---:|
| Deck / 1280×800 | 173.820 | 189.987 | 9.697 ms | 8.691 ms | 0.978% → 0.535% |
| High / 1920×1080 | 180.002 | 209.455 | 10.378 ms | 8.176 ms | 1.463% → 0.239% |

These are means of the two run fps/p95 values, not a pooled p95. The paired aggregates show no regression in these metrics, with fewer draw calls/primitives and lower video memory. Individual runs vary substantially with the shared machine; this is not a claim of a precise causal speedup. [Performance summary](evidence/art/revamp/verification/performance-summary.json) and [every raw paired run](evidence/art/revamp/verification/paired-bench/) are retained alongside the initial measurements.

## Log — 2026-10-16

Created the isolated B: clone and branch. Configured B: caches, temporary data, Blender preferences and three-minute autosaves. Installed the free MIT Blender MCP bridge locally, disabled optional remote services/telemetry and smoke-tested scene access. Blender 5.2.2 LTS; no other extensions, third-party meshes, textures or HDRIs used.

Recorded original-model hashes and rebuilt the forge byte-identically. Captured a baseline and ran the eighteen targeted tests. Generated fighter concepts, then boss/minion turnarounds. The user authorized brief built-in imagegen staging on C: followed immediately by moving each image to B:. Every staged image was only a few MB; PNG masters and all working data reside on B:.

Completed Stoke's first full pipeline, including byte-identical source re-export, import, preview, live combat and targeted tests. Rejected and refined the first blunt Dredge pincers and pipe-like Gusto wings. Reduced Dozer to budget. Fitted extended crests, barnacles, crowns and glasses to the unchanged body envelopes. Gave Snappington's gavel a visible front position within her existing claw volume.

The cosmetic tests caught Dredge's sparse shell surface samples and Jitters' raised coil being mistaken for the mouth anchor. Added Dredge shell rings and explicit cap-centre topology; curved the coil against Jitters' body. All six cosmetic tests then passed unchanged. No test, fitting algorithm or physics data was weakened to pass.

Reviewed all twelve same-camera comparisons, 48 px silhouettes, collision overlays, effect fixtures and four-frame combat samples. Retained all twelve replacements for clearer faces/colour boundaries and fitted geometry. The first separated after benchmark was slower, so completed an ABBA comparison under one lock and retained all measurements; paired aggregates improve fps and p95 at both presets. Rebuilt the ten retained forge models and confirmed all 22 shipped GLBs stayed byte-identical. An early Blister sample showed the results screen; an earlier retry lost focus, so the final capture uses 8–11 seconds and the game's Settings/Saves API to disable focus-loss pausing in the scratch profile only.

C: free space initially measured 1,725,509,632 bytes. It later dipped to roughly 0.96 GB; heavy art work stopped while tracing it. Task outputs/caches remained on B:, and the user confirmed separate work was using C:. Space subsequently recovered to about 1.94 GB. Final model exports changed C: usage only by a few KB.

An early capture helper inherited a redirected B: TEMP, so some earlier art jobs did not share the default-TEMP suite lock. On discovery, heavy work stopped. The wrappers now resolve the user-level default TEMP independently and acquire the real lock before Blender, imports, captures and benches. Final full-suite execution preserves the default TEMP unchanged. No other agent's files or processes were modified.

The final full suite finished on 2026-10-16 at commit `12b11b42d55826b5150031e7f5dc3b1cb251305d`: `tests: 684 run, 0 failed, 684 passed, 0 skipped in 2542.2 s`. C: free space measured 1,820,606,464 bytes before and 3,294,261,248 bytes after. All source/asset work was complete before this run; only final evidence and documentation were changed afterward.

The successful full-suite run also prints Godot shutdown diagnostics: `ObjectDB instances leaked at exit` and `5 resources still in use at exit`. A Jolt maximum-job warning also occurs during the hub wander test. The same Jolt/shutdown diagnostics and resource count appear in the existing [2026-10-16 packaged-test evidence](evidence/verification/20261016-115413/packaged_tests.log.err). They remain visible in the new log; the runner exits 0 and reports all 684 tests passed. This art branch does not claim to resolve that existing shutdown diagnostic.

After publishing the draft art PR, added the user's requested [Blender machine guide](../tools/blender/README.md). It records verified local paths/preferences, the optional MCP bridge and its repairs, batch export, coordination and transferable art/capture/benchmark lessons. Live bridge status and preferences were rechecked; this addition is documentation only.

## Requests for Claude

Main's current integration notes (`docs/PROGRESS.md`) request an alternate preview build from main plus this branch for the user's side-by-side comparison before any merge. This PR remains draft; Claude owns that build/release step and the later integration suite. No release, tag or packaging work is performed by the art branch.

No body JSON change is requested. The locked proportions support the adopted cleanup; broader concept wings/crests and oversized props were reduced to the existing reach instead of changing gameplay.

The current eight-fighter capture at 1280×800 shows foreground cage rails and the bottom HUD obscuring some fighters. This is an existing camera/UI constraint outside the allowed art files. Please review spectator framing and cage fading, and the compact FFA HUD layout, against the paired before/after captures. Clearer creature meshes do not by themselves resolve that occlusion.

Synchronize the creature-art acknowledgement in `docs/CREDITS.md` with the in-game credits data (`game/assets/ui/credits.json` and its generator) when integrating. Those files are outside this art branch's edit allowance. Optional facial expressions/secondary motion and hub idles are not added or claimed.

### Proposed D-041 text

For the twelve models listed in `tools/blender/adopted.json`, supplement D-012's deterministic SDF forge with original, editable Blender sources. Keep compressed `.blend` masters, concept provenance and deterministic scripted GLB export. Preserve the existing segment skeleton, collision registration, vertex colour/glow, team tint and unskinned KO piece. Keep the forge for retained hub/crowd models and historical comparison; ordinary forge builds must not overwrite Blender-owned outputs. No third-party character geometry or gameplay-data changes.

### Proposed requirement evidence updates

- **ART-01:** Art direction now documents fitted cartoon forms, facial-detail outlines, current source masters and the inclusive triangle/texture limits.
- **ART-02:** Twelve original combat creatures rebuilt in one shared material/eye/shape vocabulary. Before/after comparisons and retained-cast walls are the visual review evidence; final appeal remains the user's judgement.
- **ART-03:** Blender-to-GLB-to-Godot import passes; runtime retains the common PBR hints, toon shading, SSAO, AgX and quality presets. Desktop preset benches are recorded separately from actual Deck hardware validation.
- **ART-04:** Four sampled live combat frames per creature show the new meshes following unchanged ragdoll segments. Collision overlays and exact rest-bone audits complement those samples. This is not exhaustive validation of every move or pose.
- **ART-05:** Effect fixtures and busy eight-fighter captures verify retained flash, glow, status, bruises, team tints and KO pieces; twelve detachment logs confirm a mesh was spawned. The existing cage/HUD occlusion is a separate review gap. No VFX range/timing data changes.
- **ART-08:** Twelve compressed editable Blender sources, exact reference bones, export/audit/capture helpers and byte-identical saved-source export ledger. Retained models remain reproducible from forge definitions.
- **PRV-03:** Exact generated-image prompts, dates, tool/model disclosure and applicable terms recorded; imagegen does not expose a model identifier. Original geometry, Blender/bridge versions and tool licences recorded in ART_PIPELINE/THIRD_PARTY/CREDITS.

### Proposed progress/release text

Draft for user visual approval; merged-main validation passes all 684 tests: replaces twelve combat-creature visual models with cleaner faces, fitted shapes and readable signature details; adds editable Blender sources and reproducible export. Preserves every gameplay body and kit, the common shader effects, team tint and cosmetic attachments. Ten optional hub/crowd models retain their original art. Claude should first provide the separate alternate preview requested on main, then wait for the user's art choice before integration and release-ledger updates.

## v0.9.17 roster pass (2026-10-20)

The owner asked for a substantial visual upgrade of the whole playable roster (Stoke, Dredge, Gusto,
Dozer, Slurry, Jitters, Varga, Knell), obvious at normal gameplay distance, with useful expressions
and visual motion, keeping the cohesive style and every gameplay body. Stoke was the pilot; the other
seven were built in parallel from one brief (`fighters_v17*.py`, ART_PIPELINE §5b/§7b). Every model
binds the unchanged segment skeleton (exact pivots), keeps the team-tint material and the unskinned
KO piece, passes `audit_models.js` (30k budget) and the art tests (`test_new_fighters`,
`test_hub_cosmetics`, `test_content_audit`), and rebuilds byte-identically from its committed source.

| Fighter | What changed | Triangles | Outside collision (p95 / max) |
|---|---|---:|---|
| Stoke | Salamander blotches, saw-tooth ember crest and back spines, riveted boiler with gauge and grille, two back stacks fed by shoulder pipes, ember gills on springs, toes and knuckles, rigged eyes/lids/brows/jaw | 26,376 | 4.7 / 10.1 cm (crest spines) |
| Dredge | Lacquered crab plates with "H" grooves and worn rims, glowing barnacle clusters, toothed crusher with a mooring chain on springs, slim cutter, stalk eyes with weary lids, brows, mandible jaw, seaweed on springs | 29,668 | 3.9 / 7.6 cm |
| Gusto | Layered feathered wings (three covert rows, 16 secondaries, 6 black-tipped primaries) with a turquoise Hype sheen, wayfarer shades with a strap, slimmer beak with an opening jaw, half-lidded eyes and feather brows, two-row pompadour and a seven-feather tail fan on springs, cream chest, feathered thighs, scaly shins and webbed feet | 29,428 | 4.4 / 8.1 cm |
| Dozer | Shingled ochre armour bands, pauldrons and rump shield with rims, rivets and dust-packed cracks; dished steel shovel snout; headlamp (Hype, `lamp`) with a strapped battery pack; hog face with lids, brows and a tusked jaw; ears, corkscrew tail and collar tag on springs; mud and dust paint | 29,444 | 5.3 / 9.3 cm |
| Slurry | Moray skull with a toothy grin, slit-pupil eyes under slanted lid folds, brows, wide jaw with tongue and glowing gullet; glossy back with two rows of glowing slime pores; ruffled dorsal fin, gill frills and tail fin on springs; brass collars with goo seams and drips | 28,620 | 2.9 / 7.4 cm |
| Jitters | Battery jellyfish: frilled jelly bell, eight tentacles on spring chains, glowing coil under the rim, lightning bolts and a charge badge on the back, bulb electrode antennae, steel battery cap, mitten arms with team cuffs, worried face with blush and sweat bead | 28,700 | 6.0 / 7.6 cm |
| Varga | Sculpted fighter build (pecs, abs, lats, deltoid caps, calves), full beard and moustache, boxer's nose and cauliflower ears, amber eyes with heavy lids, brows and a kiai jaw, topknot and team headband, wraps and hair on springs, red shorts with gold trim, fingerless gloves, ankle tape, glowing copper scrap markings | 29,518 | 3.7 / 7.8 cm |
| Knell | Haunted diving suit: copper helmet with brass ports and a violet ghost face (eyes, lids, brows, mouth) in the front port, bolted corselet with wing nuts, weathered canvas with patches, weight belt with an anchor buckle, lead boots, Ghost Light lantern; air hose, wisps and an anchor charm on springs | 29,808 | 5.2 / 8.5 cm |

The legacy Varga skin is the untouched v0.9.16 model (`f_varga_legacy.glb`, sha256 `4fa78a8a…0460fc`).

Known limitations (from the per-fighter reviews): springs swing in two directions only, so upright
fins and tentacles can lean into sudden moves and dip briefly into the body; face animation was
checked in stills, sandbox frames and posed previews, not watched as video; Dredge's four-lobed
outline and Dozer's barrel body follow their locked collision shapes; Knell's hose rides the head
bone; Jitters' rigged lids read heavy from the high front camera; Varga's rest pose sits 17.5 cm
below his floor (static previews lift it, see `CreatureView.rest_sink`).
