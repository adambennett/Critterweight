# CRITTERWEIGHT — Arenas

Four arena bases (one polished signature cage, three themed), six example authored layouts for the arena editor, the prop palette, and budget rules. Dimensions are in meters; the fighters are 0.9–2.2 m tall, so a 12 m cage is "big enough for four, tight for eight."

## 1. Arena rules shared by all bases

| Rule | Default |
|---|---|
| Boundary | Cage walls are physical (fighters splat on them); **The Rooftop** has no walls and uses **ring-outs** instead |
| Wall splat | A fighter shoved into a wall at ≥ 3 m/s takes the attack's listed splat bonus (usually +4 dmg) and bounces 0.5 m; cosmetic cage rattle |
| Ring-out (Rooftop only) | Falling off = 8% max HP damage, 2.5 s out, respawn at the nearest edge marker with 1.0 s invulnerability; in Chumball/Spotlight Hog it also drops any carried objective |
| Spawns | 1v1: opposite points 6 m apart. FFA: evenly on a ring. Teams: two clusters. Campaign: player cluster at "home", enemies at "away". Every base ships with 8 spawn markers + 2 team clusters + a "boss" marker. |
| Floor | Flat by default; raised props (mooring blocks, crates) are the only elevation. No slopes except editor ramps (max 15°). |
| Crowd | Cosmetic: bleachers/dock/rooftop crowd silhouettes react to knockdowns, JUICE and KO |
| Lighting | Each base has a key light, a rim color, and an "event" light (JUICE activation tints the rim for 1 s) |
| Hazard visibility | Every hazard has: a static decal (its footprint, hatched), a 1.0 s telegraph (glow + sound), and a color-blind-safe shape per element (ELEMENTS.md §1) |

## 2. Arena bases

### 2.1 THE GULLET — signature cage — `arena_gullet`

| Field | Value |
|---|---|
| Look | The Circuit's main cage inside the cannery's gutted main hall: an **eight-sided chain-link cage**, 12 m flat-to-flat, walls 2.4 m with a padded top rail in Glandco green `#8BD426` and gold `#C9A227`. Canvas floor `#E9E2CF` with a giant JUICE can logo. A cosmetic drain at dead center. Sponsor boards every other wall panel. Stadium lights on rusted trusses, bleachers rising into fog, hanging cannery hooks far above (cosmetic). |
| Size | 12 m across, 8 corner posts, 8 wall panels of 4.6 m |
| Hazards (default) | **None.** The Gullet is the clean competitive baseline. |
| Quirks | Cage walls are springy: wall splats rebound 0.5 m (sets up Dredge follow-ups). The eight corners are real corners: a fighter in a corner takes +10% knockback *out* of it (the engine's wall-normal shove) which makes cornering feel dangerous but not sticky. |
| Variants | **Day** (undercard, dusty sunbeams), **Night** (main card, cyan rim), **Title Night** (confetti cannons on knockdowns, pyro jets on the posts fire cosmetically on JUICE; the Snappington boss layout adds the Juice Vat and loose sponsor boards) |
| Palette | Floor `#E9E2CF`, cage steel `#5B6168`, pads `#8BD426`/`#C9A227`, rim light cyan `#35C1C9`, key light warm `#FFD9A0` |
| Best for | 1v1, teams up to 4v4, every bonus mode; ranked default |

### 2.2 DRYDOCK — `arena_drydock`

| Field | Value |
|---|---|
| Look | An outdoor concrete dry dock at low tide: rectangular pit 16 × 10 m with 2 m concrete sides topped by chain fence; dock crowd leaning over the rail with beers; a rusted crane arm overhead; gulls. Wet planks along the long edges; a **tidal gutter** 1.5 m wide runs the full length down the middle. |
| Size | 16 × 10 m, walled |
| Hazards | **Tidal gutter** — every 20 s it floods for 8 s (telegraph: gurgle + foam line 1.5 s). While flooded it is a **Brine zone** (15 build-up/s). **Crane hook** — every 30 s it lowers over a marked 1.5 m circle (telegraph: chain rattle, spotlight 1.5 s); any fighter standing there is hooked, lifted 2 m for 2 s, and dropped (8 dmg, knockdown). A hooked fighter can be hit by others. |
| Props (built-in) | 3 **mooring bollards** (0.8 m, indestructible, cylindrical cover), 3 **mooring blocks** (1.2 × 1.2 × 0.4 m, raised, dry) |
| Quirks | Wet planks (1.5 m strips along the long walls): dodges there travel +30% and cannot be stopped early (slippery). The long axis rewards charges (Dozer) and lobs (Slurry); the gutter rewards Static fishing (Short-Out). |
| Palette | Concrete `#9A9A92`, planks `#6B4F3A`, water `#2E9BE0`, rust `#8C3B2B`, sky overcast `#C9D3D8`, key light cool daylight |
| Boss | Bilge (Act 1): phase 2 floods the entire floor permanently and frees the chain |
| Best for | Chumball (long axis = pitch), campaign Act 1, 2v2 |

### 2.3 THE CRUSHER — `arena_crusher`

| Field | Value |
|---|---|
| Look | The pit of a scrapyard car-compactor at night: square 12 × 12 m, walls are the compactor's steel plates (fixed, 3 m), floor is a 3×3 grid of 4 m steel plates with yellow hazard stripes between them. A crane magnet hangs over the center. Scrap piles make cover. Sodium lights, sparks, a stray dog's silhouette on the rim. |
| Size | 12 × 12 m, walled |
| Hazards | **Electrified plate** — one plate at a time on a 10 s cycle: 1.0 s telegraph (yellow outline + hatched decal + buzz), then a **Static field** for 2.0 s (8 dmg + 40 build-up on entry/tick). The pattern is seeded, never two adjacent plates in a row. **Crane magnet** — every 25 s, 1.5 s telegraph over a random plate, then **pull** everything within 3 m toward the plate's center for 1.5 s at 2.5 m/s, then it drops a **scrap bundle** (1.5 m wall prop, 60 HP) there. |
| Props (built-in) | 4 **scrap piles** (2 × 1 × 1.5 m destructible walls, 60 HP; shed Grit rubble r 1 m 3 s when destroyed), 3 **rubber mats** (1.5 m squares; insulated: never electrify, immune to the magnet) |
| Quirks | Plates are slick steel: dash distance +10%. Caked fighters resist the magnet by 50%. Destroying every scrap pile opens the arena into a pure square (strategic choice for chargers). |
| Palette | Steel `#5B6168`, stripes `#F7E04A`/`#1E1E24`, rust `#8C3B2B`, sodium light `#FFB347`, rim light magenta `#E04FB0` |
| Boss | Conduit (Act 2): phase 2 takes over the plates and the magnet |
| Best for | Spotlight Hog, FFA 4–8, campaign Act 2 |

### 2.4 THE ROOFTOP — `arena_rooftop`

| Field | Value |
|---|---|
| Look | The cannery's roof at night, 14 × 12 m of tar and gravel with **no cage**. A giant flickering Glandco neon sign, rooftop HVAC units, a water tower leg, pigeons, the whole bay glittering below. The crowd is on the next roof over, with lawn chairs. |
| Size | 14 × 12 m irregular (two 2 m notches cut from opposite corners), **open edges on all sides** |
| Hazards | **Wind gust** — every 18 s, from a random cardinal direction: 1.5 s telegraph (flags snap, gust sound), then a **push 1.5 m over 1.0 s** on everyone (Winded fighters: ×2, i.e. 3 m). **Edges** — ring-outs (§1). |
| Props (built-in) | 3 **HVAC units** (1.2 × 1.2 × 1.0 m, indestructible, cover and a ledge), 1 **water tower leg** (0.6 m cylinder), 2 **edge railings** on the short sides (0.9 m, 40 HP, break when splatted into — then it is open edge) |
| Quirks | Knockback is king: Dredge, Dozer and Gusto love it; Jitters' Spring Pads can launch people off (and save himself: hover ignores the wind). Gale-element fighters take the gust's push at 50%. Ring-out damage is capped at 8% so it is a positional loss, never a one-shot. |
| Palette | Tar `#2F2B2B`, gravel `#6E6A66`, neon green `#8BD426` and pink `#E04FB0`, night sky `#101624`, rim light neon mix |
| Best for | Absolute Unit, FFA, Chum Rush (edges shed minions), campaign Act 2 |

## 3. Prop palette for the arena editor

Every prop has a footprint, a budget cost, and a validation class. Hazard props produce the matching zone from ELEMENTS.md §5.

| Id | Prop | Size (m) | Cost | Class | Effect |
|---|---|---|---|---|---|
| `prop_crate` | Crate | 1 × 1 × 1 | 2 | obstacle | Pushable (needs ≥ 2 m/s shove), 40 HP destructible, can be stood on |
| `prop_heavy_crate` | Heavy crate | 1.5 × 1.5 × 1.2 | 3 | obstacle | Immovable cover, 80 HP |
| `prop_sponsor_board` | Sponsor board wall | 2 × 0.3 × 1.2 | 3 | wall | Indestructible low wall; wall splats apply |
| `prop_fence_segment` | Chain-link fence | 3 × 0.1 × 2.4 | 4 | wall | Indestructible; defines interior cages |
| `prop_tire_stack` | Tire stack | 1 × 1 × 1 | 2 | obstacle | Bouncy: splats into it rebound 1.5 m, no splat damage |
| `prop_bollard` | Bollard | 0.8 Ø × 1.0 | 1 | obstacle | Indestructible post |
| `prop_fire_barrel` | Fire barrel (Scorch) | 0.6 Ø × 0.9 | 3 | hazard | 30 HP; on destruction: Scorch patch r 1.5 m 4 s + 6 dmg burst; it also burns anyone touching it (10 build-up/s) |
| `prop_sludge_drum` | Sludge drum | 0.6 Ø × 0.9 | 3 | hazard | 30 HP; on destruction: Sludge puddle r 1.8 m 6 s |
| `prop_brine_barrel` | Brine barrel | 0.6 Ø × 0.9 | 2 | hazard | 30 HP; on destruction: Brine puddle r 1.8 m 6 s |
| `prop_battery` | Car battery (Static) | 0.8 × 0.5 × 0.4 | 3 | hazard | 30 HP; on destruction: Static field r 1.5 m 2 s + 0.4 s stun; pushable |
| `prop_gravel_sack` | Gravel sack (Grit) | 0.8 × 0.6 × 0.6 | 2 | hazard | 20 HP; on destruction: Grit rubble r 1.5 m 4 s |
| `prop_fan_unit` | Industrial fan (Gale) | 1 × 1 × 1.5 | 4 | hazard | Always on: push line 5 m long × 1.5 m wide at 1.5 m/s away from the fan; 50 HP |
| `prop_steam_vent` | Steam vent | 1 × 1 floor grate | 3 | hazard (timed) | Every 8 s: 1 s telegraph then a 2 m Scorch cone upward/forward: 6 dmg, Scorch 30, push 1.5 m |
| `prop_electric_plate` | Electrified plate | 2 × 2 floor | 4 | hazard (timed) | Every 10 s: 1 s telegraph then Static field 2 s |
| `prop_spring_pad` | Spring pad | 1.2 Ø | 3 | hazard | Launches anyone 2.5 m up, 3 m forward (same as Jitters' ability, permanent) |
| `prop_bumper` | Pinball bumper | 1 Ø × 1 | 3 | hazard | Push 3 m on contact, 2 dmg, "ding" |
| `prop_pit` | Pit | 2 × 2 floor | 4 | hazard | Ring-out hole; only valid where the base permits (Rooftop, or any base if the layout marks it; validation requires a respawn marker within 4 m) |
| `prop_drain_pair` | Drain pair | 2 × (1 Ø) | 5 | hazard | Two linked drains: stepping on one teleports you to the other (0.5 s, 3 s cooldown per fighter) |
| `prop_heavy_bag` | Heavy bag | 0.5 Ø × 1.4, hanging | 2 | obstacle | Swings when hit (physics), blocks projectiles, no damage |
| `prop_chum_bucket` | Chum bucket (health) | 0.6 Ø | 3 | pickup | Heals 15 HP on touch; respawns 30 s; max 2 per layout in standard modes |
| `prop_hype_can` | JUICE can (Hype) | 0.3 Ø | 3 | pickup | +25 Hype on touch; respawns 45 s; max 2 per layout |
| `prop_ramp` | Ramp | 2 × 1 × 0.5 | 2 | obstacle | 15° slope up to a crate height; charges and dashes get +0.5 m air off the lip |
| `marker_spawn` | Spawn point | — | 0 | marker | Up to 8 individual + 2 team clusters; validated for 1.5 m clearance |
| `marker_boss` | Boss spawn | — | 0 | marker | Required for boss layouts |
| `marker_spotlight_anchor` | Spotlight anchor | — | 0 | marker | Spotlight Hog: the light moves between anchors (≥ 3 required) |
| `marker_goal` | Chumball goal | 3 × 0.2 × 2 | 0 | marker | Two required, team-tagged |
| `marker_ball_spawn` | Chumball spawn | — | 0 | marker | One required |
| `marker_wave_gate` | Wave gate | 2 × 0.2 × 2.4 | 0 | marker | Chum Rush minion entry; ≥ 2 required; a gate is a cosmetic door in the wall |
| `marker_unit_spawn` | Unit spawn | — | 0 | marker | Absolute Unit: where the Unit spawns (center by default) |

### Budget suggestions

| Budget | Value |
|---|---|
| Total prop points per layout | **100** |
| Max props | 24 (markers free) |
| Max hazards (timed or destructible-elemental) | 8 |
| Max pickups | 4 (2 health, 2 Hype) |
| Max live zones the arena may create at once | 24 (engine cap) |
| Min clear floor | 45% of the base area must be free of obstacles (validation computes a coverage map) |
| Spawn validation | Each spawn: 1.5 m radius clear of obstacles and hazards; team clusters ≥ 6 m apart; no spawn within 2 m of a pit or open edge |
| Mode markers | Validation requires the markers each mode needs (see MODES.md); a layout can declare which modes it supports |

## 4. Example authored layouts (ship with the editor)

| Id | Name | Base | Modes | Props | Budget used | Intent |
|---|---|---|---|---|---|---|
| `layout_gullet_classic` | **Gullet Classic** | The Gullet (Night) | all standard | none (8 spawns, 2 team clusters) | 0 | The ranked default; the editor's "blank" example |
| `layout_glandco_showcase` | **Glandco Showcase** | The Gullet (Title Night) | FFA, teams, Absolute Unit | 4 steam vents on the posts at N/E/S/W (12), 2 sponsor boards making a center "aisle" (6), 1 spring pad dead center (3), 2 JUICE cans in opposite corners (6), 1 unit spawn | 27 | A loud sponsor night: vents push fights into the aisle, the pad launches people over the boards |
| `layout_drydock_pitch` | **Drydock Pitch** | Drydock | Chumball, teams | 2 goals on the short walls, ball spawn center, 4 crates as midfield obstacles (8), 2 tire stacks as "boards" (4), 2 sludge drums near the goals (6) | 18 | The long axis is a pitch; the gutter floods mid-field every 20 s and drums at the goals punish campers |
| `layout_crusher_king` | **Crusher King** | The Crusher | Spotlight Hog, FFA | 5 spotlight anchors (center + 4 corner plates), electrified plates disabled (layout flag), 4 scrap piles kept, 2 batteries by the center (6), 2 chum buckets at mid-walls (6), 1 fan unit blowing across the center (4) | 16 | Hold the center, get blown off it; the magnet still drops walls every 25 s |
| `layout_rooftop_gauntlet` | **Rooftop Gauntlet** | The Rooftop | Chum Rush, co-op | 4 wave gates (stair doors at the corners), 2 fire barrels near the sign (6), 1 chum bucket at the water tower (3), 2 spring pads on the long edges (6), both railings kept, 1 heavy crate as a choke (3) | 18 | Waves pour from the corners; the edges are your friend; the pads fling Blisters off the roof |
| `layout_unit_pit` | **The Unit Pit** | The Gullet (Night) | Absolute Unit, FFA | 6 spring pads in a ring at r 4 m (18), 4 batteries at the diagonals (12), 1 fence ring r 2 m around the center with a 2 m gap (16), unit spawn center, 1 JUICE can center (3) | 49 | The Unit spawns in a tiny inner cage; everyone bounces in and out on the pads; the batteries stun whoever is winning |

Each example ships as an exported content package and is used by the editor's "Load example" list and by the tests for validation (spawn clearance, budget, markers).

## 5. Arena readability rules (for 4–8 fighters)

- Floors are low-detail and desaturated; fighters and hazards are saturated. The canvas, steel and tar never use a fighter's primary hue at full saturation.
- Every hazard footprint is drawn on the floor at all times (hatched, 40% alpha), not only when active.
- Wall-adjacent props never exceed 1.2 m so the camera can look over them.
- Zones draw an outline plus an element pattern (ELEMENTS.md §7) and sort below fighters.
- Pickups float 0.3 m with a slow bob and a 1.5 m soft light; max 4 per layout.
- The Rooftop edge is marked by a continuous 0.2 m yellow-black hazard stripe plus a 0.4 m "crumble" lip so the drop reads at any camera angle.
