# Ability VFX (v0.9.17)

Every fighter's abilities, JUICE, charged heavies, projectiles, ground effects, elemental hits and
reactions are drawn by one view-only system shared by local matches, online clients and the hub.
This page is the design and the maintenance guide. Evidence (before/after captures, contact sheets,
performance) lives under `docs/evidence/v0.9.17/`.

## 1. Architecture

| Piece | File | Role |
|---|---|---|
| `AbilityVfx` | `game/src/view/fx/ability_vfx.gd` | The director: reads simulation **events** (`move_start`, `effect`, `hit`, `reaction`, `juice`, `submerge`, `hover`, `counter`, `carry`, `arc`, `spring`, ...), the replicated **entity list** (projectiles, zones, props, delayed strikes) and per-fighter **view state** (ground, yaw, state, JUICE, hidden, heavy-charge level). Never writes back. |
| `FxKit` | `game/src/view/fx/fx_kit.gd` | Shared shaders, materials, palettes (paint / glow / stain per element) and procedural meshes (hex grit chunks, ring walls, spirals, crests). |
| `fx_area.gdshader` | `game/src/view/shaders/` | The **true footprint** of an area or zone, computed per pixel from the effect's own numbers, in the element's floor pattern. |
| `fx_flow.gdshader` | | Animated surfaces: shockwave and tidal walls, vortex spirals, crests, jets, ribbons (trails, wind streaks, lightning). |
| `fx_debris.gdshader` / `fx_puff.gdshader` | | GPU particle programs: solid pieces that fly, tumble, bounce and settle (grit, drops, gobs, shards, cinders, sparks, feathers) and soft volumes that grow, drift and swirl (steam, smoke, dust, flames, mist, wisps, wind). |
| `fx_puff_draw.gdshader` | | How one puff looks: cloud, flame tongue, mote/bubble, wisp, droplet, four-point glint. |

Scenes: `MatchScene` (local play, practice, Career, spectating, AI Lab presentations),
`NetMatchScene` (online clients: same events through `NetEventCodec`, entities through
`NetSnapshot`) and `HubScene` (the player's own fighter). The old generic area ring, reaction burst
and JUICE burst in those scenes were removed; hit sparks, words ("PARRY!", reaction names), KO stars
and the rest of `Vfx` are unchanged.

## 2. Truthful timing and areas

* **Preparation** runs from the move's start (`move_start`) until the move's first `effect` event.
  Its look is timed by the move definition (`first_effect_t`), but the real windup is slower at
  low stamina (0.77x) or under speed statuses, so the pieces that last through it (stack puffs,
  drips, antenna sparks, glows, area telegraphs) hold until that event arrives, end when the move is
  cut off (the fighter leaves ABILITY) and stop at `PREP_CAP` x the definition's time at the latest.
* **Contact** is drawn when the simulation emits the `effect` event, never earlier.
* **Areas** are drawn from the numbers the simulation used. `EffectsSystem.fire` adds the rest of
  the footprint to the (presentation-only) effect event: `cone_deg`, `length`, `width`, `inner`,
  `duration`, `distance`, `delay`, `speed`, `origin` for cones and lines (they start at the
  fighter's feet, see `EffectsSystem.area`; a `cone_back` is measured from `pos`) and, for dashes,
  `dir` (the way the dash really went: "stick" dashes keep the facing on the opponent). The `hover`
  event carries the hover's effective `duration` (0 = a dive ends the hover). Nothing reads these
  back; the authoritative outcome, state hashes and event counts are unchanged. Unknown keys already
  travel online (`NetEventCodec`), so clients draw the same footprints.
* The simulation tests areas on the floor plane, so footprints and rings lie on the floor under the
  point even when it went off in the air (a Gust Bomb or Arc Lash orb expiring mid-flight). Bursts
  thrown from a box along a line (Brine Wave, Landslide, Overflow) turn the box to the line's yaw.
* Preparation telegraphs that show an area before contact (Meltdown, Landslide, Overcharge, High
  Tide) use the move definition's own numbers and stay on the fighter's feet (Landslide's line also
  on his facing) through the windup, since he may still walk and turn; they fade at contact.
* Projectiles, zones and props follow the replicated entities frame by frame; zones are redrawn at
  their current radius (zone reactions grow, shrink and slide them); when an entity disappears its
  visual dissipates (streams stop, decals fade) instead of popping.
* Delayed strikes: only a Static strike (Stormfront, storm zones) is a bolt from the sky; any other
  strike (Gusto's and Slurry's follow-ups, thrown Blisters and Scraplings) flashes its true circle
  with its element's burst. A projectile whose look is called "bolt" is a projectile, not lightning.
* Fighter looks stay with their fighters: Bulldoze's plume is Dozer's and Anchor Drop's whirlpool
  Dredge's; other charges (Jitters' Pinball) and counter stances (Snappington, Kid Lamprey) get a
  generic kick-off or bracing ring. Bulldoze tears up the floor only while Dozer moves, and stops
  when he is knocked out of the move (wall bonk, flinch, stun, KO).
* Heavy charge: local play knows the charge level; online clients only know whether a fighter is
  holding a heavy (snapshot flag `NetSnapshot.F_CHARGING`, bit 128 of the existing flags byte), so a
  held heavy glows by time and a tapped one shows nothing.

## 3. Identity per fighter

| Fighter | Language | Abilities |
|---|---|---|
| Stoke (scorch) | furnace pressure and ignition | **Steam Vent**: the boiler glows and the stacks hiss while hot motes rush into the firebox; at contact a flat steam jet and scalding clouds fill the true 60° cone, cinders fly, the floor is scorched in the cone. **Stoke the Fire**: ignition roars out of both back stacks, a flame ring kicks off his feet, the stacks keep burning and his fists shed cinders while Stoked lasts. **Meltdown** (JUICE): white-hot core, the blast footprint spreading under him, then a fire wall rolls out to exactly 3 m with flame tongues on the rim, a scorched circle and cinder rain. JUICE aura: stack flames, cinders. Charged heavy: an ember glow builds on the striking fist, flash on release, a fire trail through the swing. |
| Dredge (brine) | tidal force | **Tide Spit**: water gathers at the mouth; a wobbling ball of seawater sheds drops and spray in flight; it lands in a splash crown and a rippling puddle. **Anchor Drop**: a whirlpool turns on the floor around him for the whole stance; the counter crashes a wave onto the attacker. **High Tide** (JUICE): a rising water column, then a breaking crest rolls out to the 5 m ring with spray, and the 11 m flood covers the cage in rippling water. Crusher Slam: a wave rolls along its 3.5 × 1 m line. |
| Gusto (gale) | vortices | **Gust Bomb**: wind spirals into the beak; the bomb is a knot of crossed spinning swirls trailing wind; it bursts in a radial gust. **Hang Time**: downdraft rings pulse onto the floor under him for exactly as long as he hovers (a dive, another move or a knockdown ends them). **Hurricane Strut** (JUICE): a vortex winds up around him, then curling streaks sweep through the 90° cone carrying feathers and dust; JUICE dodges leave small turning tornadoes (Gale Vortex zones). Crosswind, Downdraft and Tailspin get a slash, a pressed-down ring and a spinning ring. |
| Dozer (grit) | crushing debris | **Bulldoze**: hooves scrape and spray grit; the charge drags a heavy dust plume, kicks gravel, sparks off the horn and tears the floor along its path; scooping a victim or hitting a wall bursts into chunks. **Dust Bowl**: a turning wall of dust follows him. **Landslide** (JUICE): the 6 × 2 m line cracks into hex cells and rock spires burst out of the floor one after another along it, then crumble. Gravel Toss sprays gravel through its cone. |
| Slurry (sludge) | viscous sludge | **Sludge Lob**: goo drips from the fang; the lob is a lumpy glossy gob shedding drips; it splats into a bubbling puddle. **Drain Dive**: the floor opens into a sludge pool, bubbles trace the path under the floor, a second pool swells where he will rise, and he erupts in a gooey ring. **Overflow** (JUICE): a sludge surge rolls along the 4 × 1.6 m line throwing gobs, the puddles bubble. |
| Jitters (static) | electrical discharge | **Arc Lash**: sparks snap between the antennae; the orb is a crackling ball snapping arcs, ending in a forked pulse. **Spring Pad**: a riveted, charged coil pad springs out of the floor and crackles; it compresses and sparks when it launches someone. **Overcharge** (JUICE): arcs crawl over the body, then lightning forks out to exactly 3 m with a charged ring; while juiced he keeps crackling. Squash landings and Static Cling discharge in sparks and forks; chain arcs are bolts between the fighters. |
| Varga (scrap) | precise martial impact | **Cut the Angle**: crisp speed lines off the chest and fists along the dash (where the stick sends him, not where he faces). **Second Wind**: a clean breath ring, rising focus motes, glints on the fists. **Championship Rounds** (JUICE): a tight gold shock ring and a star-burst exactly on the 1.3 m area. His landed strikes add a four-point glint with short impact lines (struck-metal sparks on the big ones); his heavies leave a gold arc. |
| Knell (spectral) | spectral motion | **Ghost Light**: a lantern flame kindles where it will leave his hand; it drifts as a violet lantern flame shedding grave-light wisps. **Through the Veil**: he comes apart into grave-mist, a wisp streaks to the destination and he gathers again; the arrival burst is a spectral ring. **Last Bell** (JUICE): a ghostly bell hangs over him and swings with each toll; each toll is a ring of sound rolling out to exactly its reach (2, 2.7, 3.4 m). |

Every elemental hit adds that element's small burst (scorch tongues and cinders, brine drops, gale
wisps, grit pebbles and dust, sludge gobs, static sparks and forks, scrap sparks and shards,
spectral wisps); status triggers add the medium burst and a short wrap around the body; every
reaction combines both parents' shapes and then its own large effect (steam cloud, flare-up
fireball, backdraft fire vortex, short-out forks over water, mud, dilute splash, catalyze fizz,
stormfront funnel and the delayed sky bolt, crust shell, sludge spray, sandblast, bell-ringer rings,
grave chill, crack guard shards).

## 4. Readability on any floor

The cage canvas is bright, so purely additive glows wash out to white. Every effect material is
premultiplied: a saturated **paint** colour covers (`cover`), a darker **stain** marks footprints
(scorch, wet floor, goo, dust) and an HDR **glow** colour is added on top (`glow_k`), which the
arena's glow pass blooms on dark floors. Palettes per element are in `FxKit.PAINT/GLOW/STAIN`.
Gale paints in its outline teal rather than its near-white body colour.

## 5. Settings and budget

| Effects quality | Particles | Lights (flashes and build-up glows) | Trails, auras, zone particles |
|---|---|---|---|
| Low (0) | 35 % | none | off (footprints, walls and key bursts stay: combat cues readable) |
| Medium (1) | 65 % | up to 3 | on |
| High (2) | 100 % | up to 6 | on |

With more than four fighters every amount is scaled by a further 0.7. **Reduce flashing** dims
light flashes to 35 %, halves the travelling front of footprints, slows lightning re-forking to a
steady flicker, slows the static floor pattern's re-forking from 12 Hz to 3 Hz (`flicker_hz`) and
thins bright motes and glints. One-shot emitters are pooled (10 per preset);
continuous emitters free themselves after their particles die; one weapon trail per fighter
(ART_DIRECTION §10). Materials and particle programs are built during the match intro (warm-up).

## 6. Verifying and capturing

* Focused tests: `game/src/test/vfx/test_ability_vfx.gd` (true footprints in the simulation's
  events and in the drawn decals, every fighter's events and entities drawn and cleaned up, JUICE
  auras follow JUICE, quality and Reduce flashing, online round trip of the new event fields; and
  the review fixes: strikes, fighter-only looks, air bursts on the floor, box bursts along lines,
  zone radius, hover length, the real dash, the floor flicker, telegraphs that follow, build-ups
  that last until contact, the light cap, the online charge glow, cone_back) and
  `game/src/test/net/test_net_snapshot.gd` (`F_CHARGING`).
* Before/after evidence: `game/src/test/vfx/test_vfx_showcase.gd` makes every fighter perform its
  abilities, JUICE, charged heavy and one elemental reaction against a still mirror dummy and saves
  the real rendered frame at fixed simulation times (prep, contact, motion, after, linger). It uses
  only APIs that existed in v0.9.16, so the same file captures the "before" frames from the v0.9.16
  checkout:

  ```
  godot --path game --resolution 1600x900 -- --user-root <tmp> --test test_vfx_showcase --vfx-showcase <out dir> [--vfx-fighters f_stoke,f_dredge] [--vfx-shots ability1,juice]
  powershell -ExecutionPolicy Bypass -File tools/vfx/contact_sheet.ps1 -Before <before dir> -After <after dir> -Out <sheets dir>
  ```
* Performance: `--bench busy` (see `docs/VERIFICATION.md`) with simultaneous abilities.
