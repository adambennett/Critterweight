# Art pipeline — creature forge and Blender

Creature art has two editable source paths. The original SDF forge remains available for every
historical model and continues to own the hub/crowd models. The creature revamp adds original Blender
meshes with deterministic GLB export; `tools/blender/adopted.json` identifies the models it owns.
No third-party character geometry or texture is used. See `ART_REVAMP.md` for adoption and verification
status, and the proposed D-041 update to D-012.

The GLB generator string and root extras identify the source path. Blender sources retain the original
GLB as a hidden, non-exported registration reference, exact segment bones, vertex colours and weights.

## 1. Rebuild

```powershell
node tools/forge/forge.js                      # rebuild forge-owned models; preserve Blender-owned outputs
powershell -File tools/blender/rebuild.ps1      # export adopted .blend sources (Blender + Node required)
node tools/forge/forge.js --list               # definitions and their output paths
node tools/forge/measure.js [--md]             # chain lengths, weapon reach tables (docs/CREATURES.md)
& $g --headless --path game --import           # then let Godot (re)import the .glb files
```

Options: `--out <dir>`, `--res <m>` (voxel size override), `--tris <n>` (triangle target override),
`--quiet`, `--stats <json>`. `--legacy --out <scratch-directory>` explicitly rebuilds historical
definitions, and refuses the shipping model directory. The forge writes
`tools/forge/build/stats.json` (triangles, vertices, bytes, bounds, dominant bone per vertex count).

Preview / inspect without the game (`model_preview.gd`, see §6):

```powershell
$gui = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64.exe"
& $gui --path game --resolution 1600x900 --script res://src/view/model_preview.gd -- --creatures res://content/core/creatures/f_stoke.json,res://content/core/creatures/f_dredge.json --yaw 30 --spacing 2.2 --capture B:\Critterweight-art\captures\wall.png
& $gui --path game --resolution 1600x900 --script res://src/view/model_preview.gd -- --models res://assets/models/hub/granny_haymaker.glb --capture B:\Critterweight-art\captures\granny.png
& $g --headless --path game --script res://src/view/model_preview.gd -- --inspect res://assets/models/creatures/f_stoke.glb
```

## 2. How a model is built

```
definition (.js/.json)  ──►  SDF field (parts splatted into a voxel grid, in order)
      │                              │
      │  bones = body segments       ▼  surface nets (closed manifold mesh)
      │  (from the creature JSON)    ▼  colour keys per dense vertex (zone + decals + discrete paints)
      │                              ▼  QEM decimation to the triangle target; colour seams are kept
      │                              ▼  normals = SDF gradient (smooth, cartoon-friendly)
      │                              ▼  per-vertex colour/material/glow, crisp splits at key boundaries
      └────────────────────────────► ▼  skin weights from the parts' own segment bindings (≤ 4 per vertex)
                                     ▼  glTF 2.0 binary: mesh (one primitive per material), skin, gore piece
```

* **Space**: definitions are authored in **fighter rest space** — exactly the frame of the body JSON
  (+Z forward, +Y up, +X = the creature's left, metres, standing on y = 0). A part bound to segment
  `uarm_l` is simply drawn where that segment's collision capsule is; no local transforms to think about.
* **Bones**: one bone per body segment, **bone name = segment id**, bind translation = segment pivot,
  flat under a `rig` node. `CreatureView` maps segment ids to bones and sets each bone's pose to the
  rigid body's world transform, so the mesh follows the ragdoll one-to-one.
* **Colour**: vertex colours (`COLOR_0`, LINEAR) are the albedo; `COLOR_0.a` is an emissive strength used
  by glowing surfaces (the fighter's "Hype feature": furnace door, barnacles, coil, headlamp...).
  Materials carry PBR hints (roughness/metallic/emissive) that `CreatureView` copies into the creature shader
  per surface. The surface whose material is named `team` is tinted with the team colour at runtime.
* **Gore piece**: a separate unskinned mesh node `gore_piece` (tooth, claw tip, feathers, battery cap...)
  that `CreatureView.detach_piece` launches on the KO hit; `art.gore_piece` in the creature JSON says which
  segment and offset it pops from.

## 3. Definition format

Definitions are `.js` modules (`module.exports = {...}`, may use helpers and loops) or plain `.json`
files with the same shape. Files whose name starts with `_` are ignored. Fields:

| Field | Meaning |
|---|---|
| `id` | definition id (CLI selector); creatures use their creature id |
| `creature` | path to the creature JSON (repo-relative). Its `body.segments` become the bones. Omit for static models |
| `bones` | static models only: `[{id, pivot}]`; default one `root` bone at the origin |
| `out` | output path under `game/assets/models/` (default `creatures/<id>.glb`) |
| `resolution` | voxel size in metres (fighters 0.008–0.012, bosses 0.015–0.02, crowd 0.014) |
| `target_tris` | triangle budget after decimation (ART_DIRECTION §11: fighters 6–12k, minions ≤ 2k, bosses ≤ 25k) |
| `blend` | default smooth-union radius (m) |
| `skin_soft` | default skin falloff sigma (m, default 0.035) |
| `scale` | uniform scale applied to all parts (bosses that reuse a plan) |
| `palette` | named colours (`#rrggbb` sRGB); referenced as `"$name"` |
| `default_color` | colour for parts that give none (default `$primary`) |
| `materials` | `{name: {roughness, metallic, emissive?, alpha?}}`; `skin` always exists; `team` is the team-tint slot |
| `parts` | ordered list (nestable arrays) of primitives, see below |
| `paints` | ordered procedural pattern layers, see below |
| `gore` | `{parts, resolution, target_tris, offset?, color?}`: the detachable piece, authored around its own origin |
| `smooth`, `zone_penalty` | rarely needed tuning knobs |

### Parts (SDF primitives)

Common keys: `type`, `seg` (segment id, default: first bone), `color`, `material` (default `skin`),
`name` (zone name; parts sharing a name + material + colour form one colour zone), `op`
(`union` smooth = default, `sharp` plain min, `subtract` carve, `intersect`), `blend` (smooth radius for
this part), `paint: true` (colour-only decal, no geometry), `glow` (0–1 emissive strength), `mirror: true`
(also emit the x-mirrored twin, swapping `_l/_r`, `_fl/_fr`, `_bl/_br` in `seg`/`name`), `clip`
(`[{p, n}]` half-spaces that trim this part only: keeps the side where `(x−p)·n < 0`), `skin_soft`
(per-part skin falloff), `skin: false` (no skin influence), `weight` (skin influence multiplier).

| `type` | Keys | Notes |
|---|---|---|
| `sphere` | `c`, `r` | |
| `ellipsoid` | `c`, `r: [rx, ry, rz]`, `rot?` | `rot` = euler degrees (X, Y, Z intrinsic) |
| `capsule` | `a`, `b`, `r` | |
| `cone` | `a`, `b`, `ra`, `rb` | round cone / tapered capsule (exact distance) |
| `box` | `c`, `size`, `round?`, `rot?`, `taper?`, `taper_y?` | rounded box; `taper` = cross-section scale at the local +Z end |
| `box` (beam) | `a`, `b`, `w`, `h`, `round?`, `taper?` | local +Z runs a→b; good for wings, planks, blades |
| `cylinder` | `a`, `b`, `r`, `round?` | rounded capped cylinder |
| `torus` | `c`, `axis`, `R`, `r` | rings, collars, chain links, goggles |
| `half` | `p`, `n`, `extent?` | half-space; use with `op: "subtract"` to slice the whole field (prefer `clip` on one part) |

Helpers for `.js` definitions (`tools/forge/lib/helpers.js`): `eye({seg, c, r, dir, white, pupil, pupil_r,
iris?, shine?, lid?, brow?})`, `wrap({seg, a, b, r, turns, color})` (bandage/tape), `chain({seg, a, b, links,
R, r})`, `bumps({seg, a, b, count, r, jitter, seed})`, `crest({seg, a, b, count, h0, h1, up})`, `fist({seg, c, r,
fwd, side})`. Each returns an array of parts.

### Paint layers

Each layer has a `target` filter (`segs`, `zones` (part names), `materials`, `exclude_zones`) and either a
`color` or `lighten`/`darken`; discrete layers may also set `material` and `glow`.

| `type` | Keys | Result |
|---|---|---|
| `stripes` | `axis`, `period`, `duty`, `origin?`, `phase?` | hard-edged stripes along an axis |
| `spots` | `cell`, `radius`, `density`, `seed` | deterministic cell-noise spots |
| `band` | `axis`, `center`, `width`, `origin?` | one slab (team-tint rings, straps, collars) |
| `edge` | `width` | highlight where two zones meet (plate rims) |
| `gradient` | `axis`, `from`, `to`, `strength` | smooth blend along an axis (dusty legs, dark tail tips) |
| `facing` | `dir`, `start`, `end`, `strength` | smooth blend by surface normal (lighter bellies, darker backs) |

Discrete layers (stripes/spots/band/edge), decals and zones define **crisp** boundaries: the decimator
never collapses across them and splits boundary triangles so the edge stays hard. `gradient` and
`facing` shade smoothly.

### Skinning rules of thumb

* Bind each part to the segment that owns its volume; overlap neighbouring parts a little so the
  smooth union makes a crease, not a gap. The weights fall off as a gaussian of the part's surface
  distance (`skin_soft`), so a 3–4 cm band around every joint bends softly and everything else is rigid.
* Accessories that must stay rigid (plates, collars, chains) use a small `skin_soft` (0.01–0.02).
* Eyes/pupils/teeth are `op: "sharp"` so their colour edges are geometric and crisp.

## 4. Making a new creature (modders)

1. Write the creature JSON (body, stats, moves, `art`) — the body format is documented at the top of
   `game/src/sim/body_def.gd`, naming conventions and examples in `docs/CREATURES.md`. Probe it:
   `& $g --headless --path game --fixed-fps 120 -- --probe stand --creature res://content/<pkg>/creatures/<id>.json --gap 3`.
2. Copy a definition from `tools/forge/defs/creatures/` next to it, point `creature` at your JSON,
   draw parts over the body's shapes (same coordinates), bind them with `seg`.
3. `node tools/forge/forge.js <id> --out <your package>/models`, set `art.model` in the creature JSON
   to the `.glb` (packages shipped as mods are loaded at runtime through `ModelLoader`; core assets go
   through the editor import).
4. Preview with `model_preview.gd` (`--creatures`), then run the sandbox:
   `& $gui --path game -- --sandbox --autoplay --creature <json> --creature2 <json> --capture out.png --capture-at 5`.

Style checklist (docs/design/ART_DIRECTION.md): 48 px silhouette test, oversized weapon parts, exact
palette hexes, one human-scale object, visibly distinct segments, min 2 cm edge radius, triangle budget.

## 5. Runtime (view side)

`game/src/view/creature_view.gd` loads `art.model`, finds the `Skeleton3D`, maps segment ids to bones
(parents-first, so nested or flat skeletons both pose correctly), replaces every surface's material with
the creature shader (`shaders/creature.gdshader`: toon ramp over vertex-colour albedo, rim, flash, JUICE,
status tint, bruises, `vertex_glow` for the Hype feature) carrying the glb's roughness/metallic/emissive
hints, tints the `team` surface, hides the `gore_piece` node and uses its mesh for `detach_piece`.
Without a model it falls back to the segment-shape primitives.

## 6. Tools

| Tool | Purpose |
|---|---|
| `tools/forge/forge.js` | build models (`lib/`: `sdf`, `mesher`, `decimate`, `paint`, `skin`, `gltf`, `pipeline`, `helpers`) |
| `tools/forge/measure.js` | reach / chain / weapon tables from the creature JSON files |
| `game/src/view/model_preview.gd` | `--inspect` (skeleton, surfaces, materials of an imported glb), `--models` / `--creatures` style wall with the arena lighting, `--detach` (gore pieces), `--hype` (glow level) |

Evidence captures of the current set live in `docs/evidence/art/`.


## 7. Blender sources and export

Tool used: **Blender 5.2.2 LTS**, build `d13f752e3b9c` (2026-09-15), installed at
`B:\Blender\blender.exe`. Python 3.13 is bundled with it. `tools/blender/*.blend` are compressed
editable sources; imported references are hidden in a separate collection. No external textures,
linked assets, animation actions, simulations or paid add-ons are needed to export.

```powershell
# From this isolated clone. The wrapper serializes heavy jobs against the real default-TEMP lock.
. tools/blender/art_env.ps1
Set-ArtRuntimePaths
powershell -File tools/blender/rebuild.ps1 -Blender B:\Blender\blender.exe -Ids f_stoke
node tools/blender/audit_models.js --out B:\Critterweight-art\captures\model-audit.json
powershell -File tools/blender/check_art.ps1
```

The direct export operation inside the wrapper is:

```powershell
& B:\Blender\blender.exe -b tools/blender/f_stoke.blend -t 2 --python-exit-code 1 --python tools/blender/export_creature.py -- --out game/assets/models/creatures/f_stoke.glb --scratch B:\Critterweight-art\tmp
```

Use the wrapper when sharing this machine with another checkout. `rebuild.ps1 -BuildSources -Ids ...`
reconstructs the initial editable geometry from `build_creatures.py`, `fighters.py`, `bosses.py`,
`minions.py` and `mesh_tools.py`; it requires `-ReferenceRoot` containing the **original forge** GLBs.
Regenerate references with `node tools/forge/forge.js --legacy --out <B:-scratch-directory>`.
Normal rebuilds export the saved `.blend`, so subsequent artist edits are retained.

Apply geometry modifiers before saving the export source; the exporter rejects unapplied non-armature modifiers and shape keys instead of silently omitting them. The current models have no shape keys.

Only meshes marked `cw_role=body` or `gore` export. `cw_role=rig` is the exact reference armature.
The exporter verifies bone names, heads and the source's body-geometry hash, rejects missing or excessive
weights, normalizes up to four influences, and emits flat joints plus inverse bind matrices through
the existing deterministic GLB writer. Fighter `(x,y,z)` maps to Blender `(x,-z,y)`; units are metres.
A changed body hash requires a registration review, not an automatic skeleton rewrite.

`Color` stores linear RGB albedo and alpha glow. Emissive material hints enable the runtime alpha
mask. `team` remains a separate tintable material. `detail_` materials use the same creature shader
and effects with the inflated outline pass omitted, keeping eyes, mouth marks and thin wraps clear.
The shared toon ramp, hit flash, JUICE, status tint and bruise shader are unchanged.

`audit_models.js` counts **body plus detachable gore triangles**, checks the skeleton/binds/weights,
colour/normal data, team/gore/glow contracts and texture/animation absence. Distances outside collision
shapes are reported for review; they are not a claim that an entire mesh is visually registered in motion.

### Machine paths and coordination

Working files live under `B:\Critterweight-art`: `blender`, `concepts`, `captures`, `tools`, `tmp`,
`test_root`, and the isolated `PokeMMA-art` clone. `art_env.ps1` sets temporary, package and Blender
profile paths on B:. Blender preferences use the B: temporary directory and three-minute autosaves.
`Set-ArtRuntimePaths` also redirects runtime user/cache paths. The Blender wrapper limits workers to
two and uses BelowNormal priority. Captures and benches run serially.

`rebuild.ps1`, `capture_art.ps1` and `check_art.ps1` resolve the user-level **default TEMP** independently
of the redirected process TEMP, and acquire `critterweight_full_suite.lock` before heavy work.
Run targeted tests only through `tools/dev/run_suite.ps1 -Filter ... -UserRoot B:\Critterweight-art\test_root`.
For the final full suite use a fresh shell with its **default TEMP unchanged**, no `-Filter`, and the
same B: user root. Do not run a render, bake or remesh concurrently with a full suite.
`paired_bench.ps1` holds one lock across an original/new/new/original comparison (both presets twice),
restoring and importing the new GLBs in its `finally` block. Use it when machine-load drift makes separated benchmarks inconclusive; retain every run, not only the fastest.

`model_preview.gd` additionally supports `--silhouette` (black on white), `--collision` (cyan body
shape overlay), and per-creature `--effects normal,hype,juice,hit,status,bruise,cosmetics,gore`.
The preview applies Hype before rendering and initializes view dependencies after autoloads.
Use `--capture-at 20` for sandbox combat captures: five seconds can still show the round introduction.
Use both engine `--resolution` and user `--size`/`--windowed` flags to keep Settings from restoring a
previous fullscreen size. The capture helper records the complete arguments beside each image. Blister motion uses 8–11 seconds because its self-pop ends the standard duel before the 20-second window. The motion helper disables focus-loss pausing only in its scratch profile, using `configure_capture.gd` and the game's Settings/Saves API; player profiles are untouched.

`verify_exports.ps1` re-exports every adopted saved source and checks all model hashes.
`verify_forge.ps1` rebuilds the ten retained models and checks that all 22 shipped GLBs remain byte-identical.
Run `powershell -File tools/blender/package_evidence.ps1` with Windows PowerShell 5.1 for its System.Drawing conversion. It makes JPEG comparisons, motion contact sheets and 48 px silhouettes from the raw captures;
it records the shared crop and source hashes. In a fresh shell, `final_suite.ps1` validates the isolated B: cleanup
root and calls the required suite runner without a filter, preserving the default TEMP and recording the result.

### Optional Blender bridge

The local bridge is **mcp-for-blender 2.1.9**, MIT, by Siddharth Ahuja and contributors:
https://github.com/ahujasid/mcp-for-blender, commit `7a0373ec9199183cb460068c4f96aed9c579fb4f`.
Its add-on and Python dependencies live under `B:\Critterweight-art\tools`. The registered art server
uses localhost port 9877, separate from other tools. The native MCP scene/code/status calls were verified (add-on 1.8, protocol 13). The upstream source archive omitted its optional telemetry configuration module; the local installation supplies an offline configuration with telemetry disabled and empty service credentials. This repair is documented in `B:\Critterweight-art\tools\bridge-setup-notes.txt`; no bridge code is committed. Optional asset-store,
AI 3D-generation and remote-service integrations and telemetry are disabled. No bridge assets ship.
No other add-ons, external HDRIs, material libraries or third-party starting meshes were used.
The bridge is an editing convenience; a clean Blender + Node installation can reproduce the GLBs.

## 8. Generated concept provenance

The thirteen reference sheets for twelve creatures (including a revised Kid Lamprey turnaround) were generated on **2026-10-16** with **Codex's built-in `image_gen` tool**.
The service did **not expose a model identifier**, so none is guessed. Exact prompts, tool/model
disclosures, dates, source PNG SHA-256 values, use and processing notes are committed in
[`evidence/art/concepts/prompts.json`](evidence/art/concepts/prompts.json). The individual records cover
Stoke, Jitters, Dredge, Slurry, Gusto, Dozer, Bilge, Conduit, Snappington, Scrapling, Blister and Kid Lamprey.
Compressed sheets are alongside that ledger; original PNGs remain in `B:\Critterweight-art\concepts`.

Applicable service terms checked for this use: [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/)
and, where the account is governed by business terms, [OpenAI Services Agreement](https://openai.com/policies/services-agreement/).
The terms assign output rights as specified by the applicable agreement, subject to law; generated output
may not be unique. These records are provenance, not a legal opinion or exclusivity guarantee.

The user authorized brief staging in the built-in tool's C: output folder, followed immediately by moving
each image to B:. Each staged file was only a few MB. No image API keys, paid calls, new accounts or third-party
character references were used. Sheets establish expression, colour blocks and shape language; generated
view consistency and proportions were reviewed against the immutable body, not treated as engineering drawings.
The game ships original editable mesh geometry and vertex colours, not generated image textures.
