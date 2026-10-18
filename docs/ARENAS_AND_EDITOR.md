# Arenas and the arena editor

Owner: arenas. Scope: `game/src/sim/arena_def.gd`, `arena_catalog.gd`, `arena_builder.gd`, `arena_hazards.gd`,
`game/src/view/arena_view.gd` (+ `arena_mesh_kit.gd`, `arena_prop_visuals.gd`, `arena_set_dressing.gd`, arena shaders),
`game/src/editor/**`, `game/content/core/arenas/**`, `game/content/core/props/**`, `game/content/schemas/arena.schema.json`,
`prop.schema.json`, `game/src/test/arena/**`. Design source: `docs/design/ARENAS.md`, `docs/design/MODES.md`.
Requirements: CNT-05, ARN-01…ARN-05. Evidence: `docs/evidence/arenas/`.

## 1. The four bases

Every arena is a **base** (geometry, walls or open edges, built-in parts, timed hazards, quirks, lighting variants) plus a
**layout** (props, markers, size within the base's range, switched-off hazards or built-ins). The base arenas themselves
ship as `arena_gullet`, `arena_drydock`, `arena_crusher`, `arena_rooftop` (`the_gullet` is kept as an alias of the Gullet
for older references).

| Base | Floor | Walls | Timed hazards (first / period, telegraph, active) | Quirks and built-ins | Variants |
|---|---|---|---|---|---|
| **The Gullet** | octagon 12 m (9–12) | 2.4 m cage | none — the clean competitive baseline | springy walls: splats rebound 0.5 m (bounce 0.45); corners shove you out (+10% knockback within 1.6 m of a corner) | Day, Night, Title Night (confetti, pyro, gold accents) |
| **Drydock** | 16 × 10 m (12–16 × 8–10) | 2 m concrete + fence | **Tidal gutter** (20 s / 20 s, 1.5 s, 8 s): Brine flood across the middle strip, soaks and builds Brine · **Crane hook** (30 s / 30 s, 1.5 s, 2 s): snatches whoever stands in the lit circle, lifts and drops them | wet planks along the long walls (dodges slide), mooring blocks, bollards | Overcast |
| **Crusher** | 12 × 12 m (9–12) | 3 m scrap walls | **Electrified plates** (10 s / 10 s, 1 s, 2 s): one cell of a 3 × 3 grid goes live, never adjacent to the previous one; rubber mats insulate · **Crane magnet** (25 s / 25 s, 1.5 s, 1.5 s): pulls everyone within 3 m toward its spot, then drops a scrap bundle (a new wall) | scrap piles (break into rubble), rubber mats | Night |
| **Rooftop** | notched 14 × 12 m (10–14 × 9–12) | none: open edges | **Wind gusts** (18 s / 18 s, 1.5 s, 1 s): pushes everyone 1.5 m one way (Gale-resistant fighters half) | **ring-outs** (below), HVAC units, water-tower legs, breakable edge railings, 8 edge respawn markers | Night |

Every hazard is drawn at all times as a static hatched footprint decal with its icon **shape** (wave, hook, bolt, magnet,
arrows, flame…; colour is never the only cue). About a second before it fires it telegraphs (the decal glows and pulses,
the set piece animates: water rises, the hook lowers under a spotlight, plates hum, the magnet trolley moves, flags snap
to the wind) and an `Audio.sfx` cue plays (§7). Hazards are deterministic: all choices come from an RNG seeded by
`(arena id, match seed)`, and the hazard clock only runs during the fight phase.

**Ring-outs** (open edges and pits). A fighter who falls below the base's `fall_y` (−1.2 m) is out: the **mode** prices
it through `MatchMode.on_ringout` (rules `ringout_damage` = 8% of max health, `ringout_eliminates`, and mode overrides
such as Absolute Unit's), and a fighter the mode leaves standing is held for `ringout_out_time` (2.5 s) and returned
by the arena at the **nearest edge/respawn marker**, health kept, with 1 s of invulnerability. With the rule
`ringouts` off, invisible guard walls line every open edge.

### Editor-only Rooftop Canvas (v0.9.15)

Choose **Rooftop Canvas** in the editor's Base selector or New layout menu. It starts as a
32 x 32 metre plain rooftop platform. In Details > Layout, width and depth can independently
range from 12 to 64 metres in half-metre steps. All four sides are open ledges, marked with
hazard stripes, above the rooftop city/bay backdrop. No fixed HVAC, railings, wind hazards,
poles, sign or floating decoration occupy the blank stage. The normal prop/marker palette,
validation, undo/redo, save, import/export and test-play tools all apply.

Starting spawn/team/boss/wave/respawn markers are provided and remain valid at minimum size.
Resizing preserves object and marker positions: move them to suit the new shape; validation
flags anything left outside the boundary. Width and depth are separate undoable changes.
The inspector and orbit camera support the full enlarged stage. Existing prop/budget limits
and the existing ringout rules described above still apply; this does not add a new game mode.

The creation template lives in `assets/data/editor_arena_templates.json`, outside playable
Content. Its `rooftop_canvas` base resolves in every runtime, but the blank template is absent
from regular arena selectors and the Compendium. Saving a custom variant makes that variant
available normally. Packages preserve its dimensions, props and markers. Older releases do
not understand this new base and should not be used to import its packages.

## 2. Example layouts

| Id | Base / look | Modes | Props (budget) | Idea |
|---|---|---|---|---|
| `layout_gullet_classic` | Gullet, night | duel, ffa, teams, coop | 0 (0) | the ranked default and the editor's blank example |
| `layout_glandco_showcase` | Gullet, title night | ffa, teams, absolute_unit | 9 (27) | sponsor night: vents push fights into the aisle, a pad launches people over the boards |
| `layout_drydock_pitch` | Drydock, overcast | chumball, teams | 8 (18) | the long axis is a pitch; the gutter floods mid-field |
| `layout_crusher_king` | Crusher, night | spotlight_hog, ffa | 5 (16) | plates off; hold the centre, get blown off it |
| `layout_rooftop_gauntlet` | Rooftop, night | chum_rush, coop | 6 (18) | waves pour from the corners; pads fling minions off the roof |
| `layout_unit_pit` | Gullet, night | absolute_unit, ffa | 15 (49) | the Unit spawns in a tiny inner cage; everyone bounces in and out on pads |

Each base arena ships 8 individual spawns (a ring), two team clusters of 4, a boss marker and the markers of every mode
it supports (MODES.md). Every shipped arena passes the editor's validator and the content audit.

## 3. Using the editor

Main menu › **Create › Arena Editor**. Pick a base (and its look) or open an example, place items from the palette,
watch the budget and the live validation, test-play, save, share.

| | Mouse / keyboard | Controller |
|---|---|---|
| Place the armed palette item / select | left click (hold **Alt** to place off-grid) | **A** at the cursor (left stick moves it) |
| Move | drag the item (or its far end for drains) | **A** on the selection picks it up, move, **A** drops (B cancels) |
| Rotate 15° | **R** / **Shift+R** | **Y** |
| Delete · duplicate | **Del** · **Ctrl+D** | **X** · menu |
| Nudge | arrow keys | D-pad (with a selection) |
| Palette tab · item | **Q / E**, PgUp / PgDn, [ / ] · **1–9** | **LB / RB** · D-pad up/down (nothing selected) |
| Undo · redo | **Ctrl+Z** · **Ctrl+Y** (Ctrl+Shift+Z) | menu |
| Camera | right-drag orbit · middle-drag pan · wheel zoom | right stick orbit / tilt · LT / RT zoom · R3 reset |
| Grid snap · marker team | **G** · **T** | L3 · menu (Team button) |
| Side panels | click | **View** (B returns to the canvas) |
| Save · test play · menu · help | **Ctrl+S** · **F5** · **Esc** · **H** | menu (**Start**) |

* The footer shows context prompts with the right glyphs for the device in use (shared `PromptBar`).
* **Budget** panel: points (≤ 100), props (≤ 24; markers are free), hazards (≤ 8), pickups (≤ 4), clear floor (≥ 45%).
* **Validation** sits under the budget: every issue names its culprit — click it (or A) to select the item; the 3D view pins
  each issue too. Shapes and words (✖ error, ▲ warning), never colour alone.
* **Layout** panel: boundary size within the base's range, supported modes (their required markers are checked), base
  hazards on/off, "allow pits" (Gullet/Drydock/Crusher), built-in props kept/removed.
* **Test play** runs a real match on the layout (1v1 vs a bot, FFA, 2v2 from the team clusters, or 4 bots). **F5** or
  **View** returns to the editor with the layout, undo history, camera and selection intact; so does the match ending.
* Saving writes `<user>/arenas/<slug>.arena.json` and registers the layout as `user:<slug>`, so it appears in Versus /
  Practice / Spectate next to the shipped arenas and can be hosted. Unsaved changes are confirmed on exit.

### Validation rules (`ArenaValidator`)

Errors: unknown prop · budget > 100 · > 24 props · > 8 hazards (timed or elemental-destructible; pads, bumpers, pits and
drains are free of that cap) · > 4 pickups or > 2 of one pickup · clear floor < 45% (0.25 m coverage map) · item out of
bounds · pit on a base that does not allow pits · pit without a respawn marker within 4 m · spawn outside the floor ·
spawn < 1.5 m from an obstacle or hazard (base hazards included) · spawn < 1.0 m from a wall · spawn < 2 m from an open
edge or a pit · too many spawns/markers · team cluster centres < 6 m apart · missing markers for a declared mode.
Warnings: overlapping props, tall props hugging a wall, no modes declared, element-zone budget.

Mode markers: duel 2 spawns · ffa 8 spawns · teams/coop both clusters · Spotlight Hog 3 anchors + 8 spawns · Chumball both
goals (team-tagged) + ball spawn + clusters · Absolute Unit unit spawn + 8 spawns · Chum Rush 2 wave gates + player cluster ·
boss 1 boss marker.

## 4. Prop catalog

Data: `content/core/props/props.json` (schema `prop.schema.json`); every entry carries its physics (`body`, `footprint`,
`height`, `hp`, `push`, `bounce`), behaviour (`behaviour` + `params`, `timed`, `touch`, `on_destroy`, `pickup`) and
visuals (`visual`, `icon`, `element`). Bodies: `static` (solid, wall-splat surface), `static_nosplat` (solid, never
splats: tires, bumpers), `dynamic` (pushable, frozen until shoved ≥ 2 m/s), `bag` (pinned swinging bag), `ramp`, `none`.

| Tab | Id | Name | Cost | Behaviour | Body / HP / element | Footprint | What it does |
|---|---|---|---|---|---|---|---|
| obstacles | `prop_bollard` | Bollard | 1 |  | static | circle d 0.8 m | Indestructible cast-iron post. |
| obstacles | `prop_crate` | Crate | 2 | crate | dynamic, 40 HP | box 1 x 1 m | Pushable (needs a 2 m/s shove), 40 HP, can be stood on. |
| obstacles | `prop_heavy_bag` | Heavy bag | 2 | heavy_bag | bag | circle d 0.5 m | Hanging bag: swings when hit, blocks projectiles, deals no damage. |
| obstacles | `prop_heavy_crate` | Heavy crate | 3 |  | static, 80 HP | box 1.5 x 1.5 m | Immovable cover, 80 HP. |
| obstacles | `prop_ramp` | Ramp | 2 | ramp | ramp | box 1 x 2 m | 15 degree ramp up to crate height; charges and dashes get +0.5 m air off the lip. |
| obstacles | `prop_tire_stack` | Tire stack | 2 |  | static_nosplat | circle d 1 m | Bouncy: fighters slammed into it rebound 1.5 m, no splat damage. |
| walls | `prop_fence_segment` | Chain-link fence | 4 |  | static | box 3 x 0.12 m | Indestructible 3 m cage panel; builds interior cages. |
| walls | `prop_sponsor_board` | Sponsor board wall | 3 |  | static | box 2 x 0.3 m | Indestructible low wall; wall splats apply. |
| hazards | `prop_battery` | Car battery | 3 | crate | dynamic, 30 HP, static | box 0.8 x 0.5 m | Pushable, 30 HP. Shorts into a Static field (r 1.5 m, 2 s) + 0.4 s stun. |
| hazards | `prop_brine_barrel` | Brine barrel | 2 |  | static, 30 HP, brine | circle d 0.6 m | 30 HP. Splits into a Brine puddle (r 1.8 m, 6 s). |
| hazards | `prop_bumper` | Pinball bumper | 3 | bumper | static_nosplat | circle d 1 m | Pushes 3 m on contact, 2 dmg, ding. |
| hazards | `prop_drain_pair` | Drain pair | 5 | drain_pair | none | pair (2 ends, d 1 m) | Two linked drains: step on one to pop out of the other (0.5 s, 3 s cooldown). |
| hazards | `prop_electric_plate` | Electrified plate | 4 | electric_plate | none, static | box 2 x 2 m | Every 10 s: 1 s telegraph, then a 2 s Static field (20 build-up/s, flinch on entry). |
| hazards | `prop_fan_unit` | Industrial fan | 4 | fan | static, 50 HP, gale | box 1 x 1 m | Always on: 5 x 1.5 m push line at 1.5 m/s away from the fan. 50 HP. |
| hazards | `prop_fire_barrel` | Fire barrel | 3 |  | static, 30 HP, scorch | circle d 0.6 m | 30 HP. Burns anyone touching it (10 Scorch build-up/s); bursts into a Scorch patch (r 1.5 m, 4 s) + 6 dmg. |
| hazards | `prop_gravel_sack` | Gravel sack | 2 |  | static, 20 HP, grit | box 0.8 x 0.6 m | 20 HP. Bursts into Grit rubble (r 1.5 m, 4 s). |
| hazards | `prop_pit` | Pit | 4 | pit | none | box 2 x 2 m | Ring-out hole. Rooftop, or any base whose layout allows pits; needs a respawn marker within 4 m. |
| hazards | `prop_sludge_drum` | Sludge drum | 3 |  | static, 30 HP, sludge | circle d 0.6 m | 30 HP. Ruptures into a Sludge puddle (r 1.8 m, 6 s). |
| hazards | `prop_spring_pad` | Spring pad | 3 | spring_pad | none | circle d 1.2 m | Launches anyone 2.5 m up and 3 m forward. |
| hazards | `prop_steam_vent` | Steam vent | 3 | steam_vent | none, scorch | box 1 x 1 m | Every 8 s: 1 s telegraph, then a 2 m Scorch cone: 6 dmg, 30 Scorch, push 1.5 m. |
| pickups | `prop_chum_bucket` | Chum bucket | 3 | pickup | none | circle d 0.6 m | Heals 15 HP on touch; respawns after 30 s. Max 2 per layout. |
| pickups | `prop_hype_can` | JUICE can | 3 | pickup | none | circle d 0.3 m | +25 Hype on touch; respawns after 45 s. Max 2 per layout. |
| markers | `marker_ball_spawn` | Chumball spawn | 0 |  | — | — | Where the ball drops. One required. |
| markers | `marker_boss` | Boss spawn | 0 |  | — | — | Required for boss layouts. |
| markers | `marker_goal` | Chumball goal | 0 |  | — | — | Two required, team-tagged (A and B). 3 x 2 m frame. |
| markers | `marker_respawn` | Respawn point | 0 |  | — | — | Ring-out/pit return point (edges and pits need one within 4 m). |
| markers | `marker_spawn` | Spawn point | 0 |  | — | — | Up to 8 individual spawns (a ring) + team clusters A/B (up to 4 each). 1.5 m clearance. |
| markers | `marker_spotlight_anchor` | Spotlight anchor | 0 |  | — | — | Spotlight Hog: the light moves between anchors (3 or more). |
| markers | `marker_unit_spawn` | Unit spawn | 0 |  | — | — | Absolute Unit: where the Unit spawns. |
| markers | `marker_wave_gate` | Wave gate | 0 |  | — | — | Chum Rush minion entry (2 or more). A cosmetic door. |

Built-in parts (placed by bases, not in the palette): `prop_scrap_pile` (breaks into rubble), `prop_scrap_bundle` (dropped
by the magnet), `prop_rubber_mat` (insulates from plates), `prop_mooring_block`, `prop_hvac_unit`, `prop_water_tower_leg`,
`prop_edge_railing` (40 HP; breaks when someone is splatted into it, opening the edge).

Destructibles take weapon damage (melee and projectiles hit their proxy entities; low props are checked against weapon
overlap), splat-able props behave like walls for wall splats, elemental ones leave their element's zone so reactions
(Live Puddle, Steam…) happen as with any kit zone.

## 5. Data format

Arena entries live in `content/<package>/arenas/*.json` (schema `arena.schema.json`); saved layouts use the same object
inside a Saves envelope (kind `arena_layout`, version 2, checksum). **Format 2**:

```json
{"id": "layout_crusher_king", "name": "Crusher King", "base": "crusher", "variant": "night", "format": 2,
 "size": [12.0, 12.0], "modes": ["spotlight_hog", "ffa"], "flags": {"electrified_plates": false},
 "removed_builtins": [],
 "props": [{"type": "prop_battery", "pos": [-1.0, 0.0, 0.6], "yaw": 0.0},
           {"type": "prop_drain_pair", "pos": [-3, 0, 0], "pos2": [3, 0, 0]}],
 "markers": {"spawn": [{"pos": [0, 0, -3.4], "yaw": 0.0, "team": -1}],
             "spotlight_anchor": [{"pos": [0, 0, 0]}]}}
```

* Positions are metres `[x, y, z]` on the floor, yaw in degrees (0 faces +Z). Floats are stored rounded (2 decimals,
  1 for degrees) so saves and hashes are stable.
* `base`: `gullet | drydock | crusher | rooftop`, or `<mod>:<base>` for a mod's base (an arena entry carrying `base_def`).
* `flags`: base hazard switches (`tidal_gutter`, `crane_hook`, `electrified_plates`, `crane_magnet`, `wind_gusts`) and
  `allow_pits`. `removed_builtins`: ids of the base's built-in parts the layout removes.
* Marker team: `-1` individual, `0`/`1` cluster or goal A/B.
* **Format 1** (still accepted, e.g. the bundled `rust_bucket` mod): `base: octagon|square|circle|platform`, `radius`,
  `wall_height`, `ringout`, `theme`, `spawns: [[x, z, yaw_deg]]`, old prop names (`crate`, `barrel`, `pillar`,
  `low_wall` …) and `hazards: [{type, pos, radius}]`. Marker entries may be `[x, z]`, `[x, z, y]` or
  `{"pos": [x, y, z] | [x, z], "yaw", "team", "size"}`; the older `spotlight` marker name means `spotlight_anchor`.
  Saved format-1 layouts are migrated on load (octagon/circle → Gullet, square → Crusher, platform → Rooftop).
* Base arenas carry `base_def` (geometry, size range, walls/open edges, quirks, hazards, areas, built-ins, variants,
  ring-out numbers).

Public API kept for other systems: `ArenaDef.from_dict/to_dict`, `clamp_point`, `inside` (clear of walls; open edges
never block), `on_floor`, `spawn_point(i, count)` (spreads fighters over the ring), `marker_points`, `markers_of`,
`team_spawns`, `content_hash`, `with_variant(look)`. User layouts resolve through `ArenaLibrary.resolve(id)` (content
first, then the user's folder); `App.resolve_match_config` uses it and applies `context.variant` when it names one of
the base's looks (the campaign's `gullet_day` / `gullet_title` fights).

## 6. Runtime (`ArenaHazards`) — for views, bots, audio and tools

`ArenaBuilder.build` creates the floor (real holes for pits), walls (from the same boundary polygon as `clamp_point` and
the view; 5 m above the visible fence so launches never clear the cage), one body per solid prop, and the runtime,
registered as `MatchSim.hazards` (`MatchSim.step` calls `update(dt)` after effects and before its environment checks).

* `view_state()` → `{clock, enabled, hazards: [{id, type, phase: idle|telegraph|active, t, len, next_in, cycle, cell|spot|dir|pos|hooked}],
  props: [{i, type, destroyed, available, hp, hp_max, phase, t, len, spawned, pos?, yaw?, xform?, respawn_in?}], ringouts}` —
  everything a view needs; `ArenaView` binds to a sim automatically or takes `apply_state()`.
* `danger_at(p)` → 0..1 (active hazard 1.0, telegraphed 0.6, near an open edge 0.7) — for bots.
* `damage_prop(i, amount)`, `respawn_point_near(p)`, `reset_round()`, `debug_advance(seconds)` (tests/tools).
* Events (`sim.emit_event`): `arena_hooked`, `arena_dropped`, `arena_zap`, `arena_shoved`, `arena_corner_shove`,
  `arena_rebound`, `arena_bounce`, `arena_bumper`, `arena_vent`, `arena_drain`, `arena_ramp`, `arena_pickup`,
  `arena_pickup_respawn`, `arena_prop_hit`, `arena_prop_destroyed`, `arena_prop_cycle`, `arena_drop`, `ringout`
  (with `arena: true`), `ringout_return`.
* Rules (rules editor › Arena): `hazards` (on/off), `hazard_timer_mult` (0.25–4× time between events), `ringouts`
  (off = guard walls), plus `ringout_damage` / `ringout_eliminates` and per-match `gravity_mult`.
* `hazards_live()`: the base's timed hazards run only while `rules.hazards` is on **and** the mode does not own a
  `hazards` runner. Campaign fights (CampaignMatchMode / BossMode) schedule their hazards from campaign data
  (CampaignHazards), so on the same bases the arena's own timers stay off and their decals hide — nothing fires twice.
  Props, pickups, quirks and ring-outs keep working in every mode.

## 7. Audio cues (`Audio.sfx`, ids from `assets/audio/bank.json`)

| Hazard / event | Telegraph | Active | End |
|---|---|---|---|
| Tidal gutter | `hazard_gutter_telegraph` | `hazard_gutter_flood` | — |
| Crane hook | `hazard_crane_telegraph` | `hazard_crane_drop` | — |
| Electrified plates / plate prop | `hazard_plate_telegraph` | `hazard_plate_live` | — |
| Crane magnet | `hazard_magnet_telegraph` | `hazard_magnet_pull` | `prop_break_metal` (bundle lands) |
| Wind gust | `hazard_wind_telegraph` | `hazard_wind_gust` | — |
| Steam vent prop | `zone_steam` | `react_steam_burst` | — |

Events: bumper `bumper_ding` · pickups `pickup_health` / `pickup_hype` · drain `drain_teleport` · spring pad `spring_pad` ·
springy wall `wall_splat_fence` (−6 dB) · tire bounce `land_soft` · destroyed props `prop_break_wood`, `prop_break_metal`,
`gravel_scatter`, or `prop_burst_<element>` for elemental ones. Ring-outs, wall slams and KOs are voiced by Audio's
own match bridge. The editor plays no hazard audio.

## 8. Sharing and multiplayer

* **Export** (editor menu): a zip in `<user>/packages/arenas/` shaped like a content package — `manifest.json`
  (`format: critterweight-arena-package`, `format_version: 1`, `kind: arena_package`,
  `arenas: [{id, file, sha256, content_hash, base}]`, `package_hash`), `arenas/<slug>.json`, optional `preview.png`.
* **Import** never trusts the archive: the central directory is parsed before anything is decompressed (≤ 16 entries,
  ≤ 2 MB zip and 2 MB total, ≤ 256 KB per JSON, ≤ 1 MB preview, compression ratio ≤ 60, no encryption), names are
  whitelisted (no absolute paths, drive letters, backslashes or `..`), sizes and sha256 must match the manifest, the
  manifest and every arena are schema-validated, their bases must exist, ≤ 8 arenas. Then the layouts are installed as
  saved layouts (`user:` ids). `ArenaPackage.import_bytes(bytes)` does the same for data received over the network.
* **Peers** reference an arena by id plus `content_hash` (sha256 of the canonical layout JSON); shipped and mod arenas
  are covered by the content hash of their package. For a user layout the host can send the package bytes
  (`package_hash` = sha256 of the sorted `id|content_hash` lines) and the client installs them with
  `ArenaPackage.import_bytes` under the same checks; identical layouts always produce identical hashes. Sending the
  bytes from the lobby is the networking layer's job and is not wired here.

## 9. Modding: new props and bases

* **Props**: add entries to `props/*.json` in a package (schema `prop.schema.json`); a palette entry needs `id`, `name`,
  `class`, `cost`, `tab`, `footprint`, `height`, `body` and, for behaviour, one of the built-in behaviours
  (`crate, fan, steam_vent, electric_plate, spring_pad, bumper, pit, drain_pair, heavy_bag, pickup, ramp, mat, railing,
  block`) with its `params` / `timed` / `touch` / `on_destroy` / `pickup` blocks (see the shipped entries).
  `visual` picks a look from the prop library (any shipped prop id); unknown visuals fall back to a plain block of the
  footprint and height.
* **Bases**: an arena entry with a `base_def` block defines base `<mod>:<id>`; layouts then use `"base": "<mod>:<id>"`.
  Shapes `octagon | rect | notched_rect | circle`; hazards use the five built-in hazard types; `style` picks the set
  dressing (`gullet | drydock | crusher | rooftop`).

## 10. Tests and evidence

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game --fixed-fps 120 -- --test src/test/arena/     # 46 arena tests
& $g --headless --path game --fixed-fps 120 -- --test                    # full suite
```

* `test_arena_content.gd` — catalog, bases and dimensions, every layout loads and validates, budgets, spawn spreading,
  round trips, schema, format-1 mod arenas.
* `test_arena_hazards.gd` — deterministic hazard cycles per seed, gutter soak, crane hook, plates and mats, magnet and
  scrap bundle, wind vs hover, fans, destructibles and their zones, weapon damage on low props, drains, pickups, Rooftop
  ring-out (8%, nearest edge marker, invulnerability), `ringout_eliminates`, mode overrides of `on_ringout`, team
  clusters, the rules switches, modes that own their hazards (campaign).
* `test_arena_validation.gd` — budget, caps, clear floor, spawn safety (props, pits, edges), clusters, bounds, mode
  markers, issue refs carry editor uids.
* `test_arena_editor.gd` — undo/redo command stack, save/load and v1 migration, saved layouts playable and registered in
  Content, package export/import round trip, malicious packages rejected.
* `test_arena_editor_screen.gd` — controller (place, rotate, delete, undo, carry), mouse/keyboard (select, drag, keys),
  test-play round trip, layout fits and text ≥ 18 px at 1280×800 and 1920×1080.

Captures (`game/src/test/arena/arena_shots.tscn`, windowed, 1600×900):
`godot --path game --resolution 1600x900 res://src/test/arena/arena_shots.tscn -- --arena arena_drydock --fighters 4
--hazard-at 16 --at 3 --when tidal_gutter:active:1.2 --out shot.jpg` (`--editor [--editor-script menu|help|load|test]`,
`--gallery [--half left|right]`, `--variant`, `--cam overview|match|low|top`).
`docs/evidence/arenas/`: 01–03 the Gullet (night, day, title night with the Glandco showcase), 04–05 Drydock flood and
crane, 06–07 Crusher plates and magnet, 08 Rooftop wind, 09–10 Unit Pit and Rooftop Gauntlet, 11–12 the editor and its
menu, 13–14 the full prop and marker catalog.

## 11. Known gaps and deviations

* No physical controller was available: controller operation is tested with engine-level injected events.
* The Unit Pit's spring pads sit at r 3.2 m instead of ARENAS.md's ~4 m: with the eight spawns and the inner cage, a 4 m
  ring always lands a pad inside a spawn's 1.5 m clearance.
* Tire stacks block bodies but not projectiles; heavy bags do.
* Edge railings break from splats and accumulated damage only (no partial bending).
* Loading a saved layout that names a mod base needs that mod enabled; otherwise the layout reports an unknown base.
* Online play with a user layout: `ArenaPackage.import_bytes` is ready, but the lobby does not send packages yet.
* `Audio.set_arena` picks ambience and splat sounds from the arena **id**; a user layout on Drydock/Crusher/Rooftop whose
  name does not contain the base gets the Gullet ambience (fix in the audio bridge: pass `arena.style`).
* The plate-grid cell footprints are subtle at a distance; the live cell is clear (glow, arcs, sound).
* Snappington's boss layout is not built (the boss marker exists on every base).
* Ring-out damage follows the rules preset (`ringout_damage`); a base's own `ringout.damage_frac` only applies to sims
  without a mode.
