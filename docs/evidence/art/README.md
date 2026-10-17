# Art evidence (forged models, 2026-10-15)

The later Blender adoption is documented in [revamp/README.md](revamp/README.md), with paired captures, motion/effect fixtures, 48 px silhouettes, audits and test results. The files below preserve the original forge evidence.

Real rendered frames (Godot 4.5.1, Forward+, downscaled from 3840×2160 to 1280 wide). Produced with
`game/src/view/model_preview.gd` (walls, close-ups, gore) and `--sandbox --autoplay --capture`
(matches). Rebuild the models with `node tools/forge/forge.js`; see docs/ART_PIPELINE.md.

| File | Shows |
|---|---|
| `01_fighters_wall.png` | the six fighters in rest pose, creature shader, Hype 0.5 (barrel / anvil / T / wedge / question mark / ball silhouettes) |
| `02_stoke_jitters.png`, `03_dredge_slurry.png`, `04_gusto_dozer.png` | close-ups: faces, team-tint bands (red = team A, blue = team B), crisp paint seams, materials |
| `05_bosses_minions_wall.png` | Bilge, Conduit, Commissioner Snappington, Scrapling, Blister |
| `06_hub_npcs_crowd.png` | the eight Cannery NPCs (Granny Haymaker, Needles, Doc Sutura, Kid Lamprey, Ludlow, Teddy Two-Tooth, Barnaby Bellows, Snappington at her desk) and the two crowd fans, imported standard materials |
| `07_gore_pieces_hype.png` | `detach_piece` using the forged gore meshes (tooth, battery cap, horn tip, glasses) and the emissive Hype features at full glow |
| `08`–`12_sandbox_*.png` | live matches: skinned models following the active ragdolls (fighters vs fighters, Bilge vs Stoke, Conduit vs Scrapling) |
