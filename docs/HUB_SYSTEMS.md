# The Cannery — hub systems

How THE CANNERY (the Fight Camp hub, design: [design/HUB.md](design/HUB.md)) is built. Requirements:
CMP-03 (between runs the player explores the 3D hub) and CMP-04 (≥ 5 connected spaces, characters,
activities, secrets, upgrade stations, real movement).

Code lives in `game/src/hub/**`, data in `game/content/core/hub/*.json`, tests in
`game/src/test/hub/**`, evidence in `docs/evidence/hub/`.

## 1. Entry points

| How | What happens |
|---|---|
| `Cannery.enter(params)` | Clears the screen stack, creates a `HubScene` as `App.current_scene` and starts it. The one call every other route ends in. |
| `App.goto("hub", params)` | App screen `"hub"` (`ui/hub_entry_screen.gd`) defers to `Cannery.enter(params)`, so any menu can open the hub. |
| Main menu → **Fight Camp** | `App.goto("hub", {"from": "menu"})`. |
| Run summary (Fight Camp) → **BACK TO THE CANNERY** | `App.goto("hub", {"from": "run"})`; the run's result changes the time of day and adds a Wall of Fame photo. |
| End of a spar / lesson / tape, leaving the Bookie's Table or the AI Lab | Back into the hub where you were (`from` = `spar`, `tutorial`, `tape`, `bookie`, `lab`). |
| Command line | `godot --path game -- --hub [--hub-spot <space>] [--hub-fighter <id>] [--hub-demo <presets>] [--hub-board <board>] [--hub-cam-yaw <deg>] [--hub-pos x,y,z[,yaw]] [--hub-zoom <f>] [--hub-pitch <deg>] [--hub-juice]` |
| `Cannery.leave()` | Saves and returns to the main menu (pause board → Leave the Cannery). |

`params`: `spot` (space id to arrive in; default: where you left off, the Main Floor on the first
visit), `fighter` (creature to walk with; default: your locker choice, else the last Fight Camp
fighter, else `Tutorial.DEFAULT_FIGHTER`, else the first roster fighter whose kit the campaign can
use — always a roster fighter `f_*`; the dev biped only when no roster is installed or a developer
names it with `--hub-fighter`), `from` (only changes the welcome), `spar` (a sparring result to pay
out).

QA flags (`--hub-demo` writes into the active profile — use `--user-root <scratch dir>`): `clout`,
`upgraded`, `half` (12 upgrades), `evening`, `night`, `loss`, `secrets`, `toured`, `dressed` (the
locker's wearables unlocked and equipped, Vintage Bellows on), `catches` (every fished can, both
arena looks), comma-separated.
`--hub-board talk:granny | station:gym_floor | run | spar | lockers | records | booth | map | pause |
lessons | shop | rest | activity:drill | activity:crates | activity:bag:heavy`. Capture helpers:
`--hub-zoom` (camera distance factor), `--hub-pitch` (one fixed camera pitch), `--hub-juice` (JUICE
glow held on, to show the Sizzle colour).

## 2. Layout

All geometry is data in `HubLayout` (`hub_layout.gd`): spaces, wall runs with door/window openings,
solids, floors, real stair ramps, fighter-only blockers, interactables, items, NPC spots, the nav
graph. **Everything stands at y ≥ 0** (the match sim's ring-out check never fires) and the hub's
MatchSim runs on `HubArenaDef`, a wall-less legacy square whose `inside()`/`clamp_point()` cover the
whole hub.

| Space | Rect (x, z, w, d) / floor | Connections | In it |
|---|---|---|---|
| Main Floor | −12, −8, 24 × 16 / 0, 7 m tall | roller door N (4 m) → Dock; doors W → Juice Bar, E → Med Bay, S → Locker Room; stairs → Office; hatch → Boiler Room; freight elevator → Roof (secret #6); loose panel → Crawlspace (secret #1) | 3 bags, practice cage (octagon, apothem 3 m), mats, Granny's corner, bleachers, corkboard map, fight posters |
| Juice Bar | −22, −8, 10 × 8 | Main Floor | Needles' counter, JUICE neon can, vending machine, radio |
| Med Bay | 12, −8, 8 × 8 | Main Floor | Doc, exam table, cot, the dumpster ice bath |
| Loading Dock (exterior) | −10, −18.6, 20 × 10.6 | roller door; pier ladder (secret #8) | crate pile + throw line + rings, chum cannon + drill square, forklift, Ludlow's workbench, the water |
| Locker Room | −12, 8, 12 × 8 | Main Floor; ladder → Booth | lockers, Kid Lamprey, Wall of Fame/Shame, belt case |
| Commissioner's Office | 6, 8, 8 × 6 / +4 m | stairs + landing from the Main Floor | Snappington's desk, sign-up stand, ledger lectern, filing cabinets |
| Broadcast Booth | 0, 8, 6 × 4 / +3 m | ladder from the Locker Room | Barnaby, mixing desk on the glass over the Main Floor, ON AIR sign |
| Boiler Room (basement) | 40, −5, 14 × 10 | hatch up to the Main Floor | boiler, Teddy's card table (Bookie's Table), AI Lab terminal, ledger desk |
| Roof (secret) | 40, −36, 16 × 12 | freight elevator | GL_NDCO sign, water tower, AC units, trunk, rooftop practice ring |
| Pier (secret) | 20, −44, 8 × 4 | pier ladder | fishing rod, bait crate |
| Crawlspace (secret) | −15.4, 3.7, 3.4 × 2.4 | behind the loose panel | Granny's tooth in a jar |

Doors are cut out of the walls (collision split around each opening), the stairs are real ramps the
rig hovers up, the dock edge, stair rail, landing rail, roof and pier edges are **fighter-only
blockers** (layer FIGHTERS, empty mask) so thrown crates and the letter fly over them into the
water/at the sign. The Boiler Room, Roof and Pier are separate regions at ground level reached
through the hatch/elevator/ladders (a 0.3 s fade, then the fighter is placed at the other end) —
see §13. `HubLayout.NAV` / `NAV_LINKS` is the navigation graph (clear straight segments) used by
Ludlow's rounds, the Scrapling, Fast walk and the tests.

**Room for every body plan.** The spaces are sized for the real kits, not the stub biped: the office
stairs and landing are 2.9 m wide (`STAIRS_Z`/`STAIRS_W`; Dredge's claws wedged between rail and
wall at 2 m), the crawlspace and its panel opening are 2.4 m deep (`PANEL_RECT`), the Body bag hangs
far enough from the wall for a crab to get round it, the belt case (`BELT_CASE_POS`) stands clear of
the walk to the booth ladder, and every arrival point (booth, office, locker room, boiler room, roof,
pier) leaves room behind a serpent's tail or a quadruped's rump. `test_hub_wander` walks all of it
with every roster fighter (§12).

## 3. Simulation (`HubMode`)

The hub is a real `MatchSim` with the player's real fighter (rig, motor, fight controls) and a
`HubMode` (`MatchMode`): no rounds, no timer, no damage, no knockdowns.

- **Interact**: each interactable is a ~2 m volume; the focus is the closest one you face (`focus_of`).
  The HUD shows its prompt with your bound button. Keyboard **Enter** and pad **A** (the `interact`
  action) interact; on pads A is also Dodge, so `HubPlayerInput` restores the Dodge press counter
  whenever the press became an interaction — the fighter never also dodges. Away from interactables
  A dodges as usual. (`HubMode.intercept_actions` does the same for a buffered Dodge when
  `dodge_interacts` is on, which the headless tests use.)
- **Fight controls work**: Light/Heavy (charged Heavy too) hit the bags, the boiler and NPCs; Guard
  crouches (secret #5); Taunt plays (secret #4); Grab picks up crates, parts, the lid, the letter
  (`on_grab_pressed`), Grab/Light tosses, holding Heavy heaves with a charge. Throw distance follows
  the fighter (`throw_strength`): the longest throw in the fighter's own kit (`throw_fwd/side/back`
  distance) relative to the installed roster's average, times a body factor `(mass / 85 kg)^0.4`
  (0.75–1.3: an 18 kg crate is easier for a 160 kg crab than for a jelly), clamped to 0.6–1.5, times
  the fighter's `throw_distance` modifiers. So the heavy grapplers (Dredge, Dozer) out-heave the
  mid-weights, Stoke reaches the 8 m ring with a full heave and Jitters doesn't, whatever the exact
  kit numbers are.
- **No damage, no knockdowns**: `on_depleted` restores health; `_keep_standing` undoes knockdowns;
  NPCs and the boiler are `Combat` hittables that only emit events (NPCs answer with a "hit" line).
- **Spaces**: the current space (`hub_space` events, first-visit discovery, the first tour of the 8
  public spaces), transitions (`begin_transition` → fade → `complete_transition`), `fast_walk`.
- **Ludlow** walks his mop round (Dock ↔ Main Floor), stops to talk, and waits for you rather than
  shoving you. Other NPCs are static colliders.
- The mode emits `hub_*` events; `HubScene` turns them into boards, sounds, VFX and HUD — the mode
  never opens UI itself.

After a board closes the fighter gets no input for 0.26 s of simulated time, so the B that closed a
board never also grabs.

## 4. NPCs

Eight NPCs from `content/core/hub/npcs.json` (moddable like any content): Granny Haymaker (Main
Floor corner), Commissioner Snappington (Office desk), Needles (Juice Bar), Doc Sutura (Med Bay),
Kid Lamprey (Locker Room), Ludlow (Dock / mop round), Teddy Two-Tooth (Boiler Room), Barnaby Bellows
(Booth). Each has:

- a model with the fighters' toon shader and outline, an idle rhythm and a limited look-at toward you
  (per-character bob/sway/turn — Snappington never turns, Kid fidgets), a speech bubble and voice
  babble with subtitles (`Audio.say`);
- **barks** when you walk past (5 m, one per NPC every 26 s, 7 s between any two), **talk** lines when
  you open a conversation, **hit** lines, and **run** lines reacting to your most recent Fight Camp
  run (`none | loss | loss_act2 | loss_act3 | win | title`, with `{fighter} {boss} {act} {kos} {dose}
  {clout} {secrets} {player}` tokens);
- a conversation board with their services (station, lessons, bag challenges, sign-up sheet, shop/rest
  previews, sparring, Bookie's Table, AI Lab, announcer settings, re-calling your last fight, "How did I
  do?", Ludlow's hint and elevator parts).

Ambient cast (`HubAmbient`, view only): two dock gulls that steal from the chum cannon and sit on
the pier ladder, the referee goat on a smoke break by the roller door, three crowd regulars in the
bleachers that react to your hits and spars, the sleeping Scrapling under the stairs and, once found,
the frozen Blister pet that follows you.

## 5. Activities

Tuning in `content/core/hub/activities.json`; each tier pays Clout once (bags: once per tier **per
fighter per bag**).

| Activity | Start | Rules | Rewards |
|---|---|---|---|
| Heavy Bag Score Challenge (`HubBagChallenge`) | the bag signs or Granny | 3 s countdown, 30 s. Every weapon hit on the bag is scored with the combat damage formula: move damage × (0.55 + 0.6 q) × (0.75 + 0.25 clean) × charge bonus, × 3 points, × 1.5 Heavy / × 2 Finisher, × combo (+0.1 per hit within 0.6 s, max × 2). Light bag: flat bonus, faster combo; Heavy bag: quality weighted; Body bag (Snappington-shaped): only head/shell zones count | 300 / 600 / 1000 → 10 / 25 / 50; Heavy 600 wakes the Scrapling (#3); Body 1000 → Granny's hint about #1 |
| Chum Cannon Dodge Drill (`HubChumDrill`) | Ludlow's cannon sign | 45 s in the painted 4 × 4 m square; buckets are ballistic projectiles aimed at where you're heading, faster over time. Resolved with the real combat checks: dodge i-frames pass, a parry pops it (+5), a front guard blocks, else a hit costs 3 drill HP (never health) and the streak. Leaving the square or 0 drill HP ends it | streak 15 / 30 / 50 → 10 / 25 / 50; 50 unlocks the "Soaked" frame |
| Crate Toss (`HubCrateToss`) | the crate pile | 10 crates, picked up with Grab and thrown from behind the line (Grab/Light toss, hold Heavy to heave). Where a crate first lands scores 5 / 10 / 20 (rings at 3 / 5 / 8 m); over the line is a foul | 30 / 60 / 100 → 10 / 25 / 50; 100 with Jitters → Ludlow's hint about #8 |
| Ring Sparring (`HubSparring`) | Kid Lamprey or the cage gate | A real match in the shared `practice_cage` arena (`Tutorial.practice_cage()`): Kid Lamprey or any roster fighter, any bot tier, Spar (one round) or Practice (no KO, HUD telemetry), optional low gravity / hazards. Not recorded (`no_record`); back to the cage afterwards. Kid Lamprey fights with his own kit (`npc_kid_lamprey`) as soon as it parses cleanly for the campaign resolver (`HubSparring.kid_ready()`); until then a roster fighter stands in under his name | first win vs Kid at Contender: 25 Clout; a per-fighter "beat a Headliner" badge |
| The Bookie's Table | Teddy | the campaign's autobattler screen (`bookie`) | as the campaign defines (Clout at 50%) |

Also on the Main Floor: **Granny's corner → Lessons in the cage** (`Tutorial.start(index, fighter,
on_exit)`; you come back to the Main Floor), and the **Rooftop practice** ring.

## 6. Presentation (`HubView`)

- Walls, floors and furniture are generated procedurally (`HubMeshKit`, SurfaceTool) and batched into
  **one mesh per space** with `hub_surface.gdshader` (vertex-coloured procedural brick/tile/plank/
  concrete/plaster patterns). Glass, water (`hub_water`), neon (`hub_neon`, instance uniforms) and
  TextMesh/Label3D signage are separate.
- **No ceilings are drawn** (roofs are shadow-only casters) and the surface shader dithers away
  anything inside a cylinder between the camera and your fighter (skipped in the shadow pass), so every
  room reads from the follow camera.
- `HubCamera`: an elevated 3/4 follow camera with per-space pitch/distance; the Locker Room and the
  Office look south (at the lockers and at Snappington, who face their doors), the Loading Dock looks
  west along the quay. While the camera turns itself into a new space and you keep walking, your
  heading is held until you let go of the stick. Right stick / Z, C turn it. While a board is open
  your fighter is framed beside it (or above a conversation).
- `HubDressing` (set dressing per space), `HubNpcView`, `HubPropsView` (mirrors bags/crates/items),
  `HubUpgradeProps` (§9), `HubAmbient` (§4).
- **Time of day** follows your most recent Fight Camp run: morning after a loss (or no run), evening
  after a run that beat a boss, night after a title — sun/moon, sky, ambient light, interior light and
  neon multipliers; gulls sleep at night, the regulars come in the evening.
- **Audio**: footsteps and hits through the match audio bridge, rooms (`Audio.set_room`), the diegetic
  radio in the Juice Bar (`cannery_radio`, toggled at the radio), the Walkout track on the dock's sound
  system once bought.

## 7. Secrets (`HubSecrets`)

All ten are real in-world triggers. Found secrets persist in `camp.secrets` and the world keeps
their changes (panel off the wall, elevator running, sign lit, gulls gone, pet following). The first
one found unlocks the **Ludlow's Confidant** achievement (`Platform.unlock_achievement("ach_confidant")`).
The corkboard map lists them (found ones named, hinted ones with Ludlow's hint, the rest as
silhouettes) and Ludlow drops **one hint per visit** about the nearest unfound one.

| # | Trigger as built | Reward |
|---|---|---|
| 1 `sec_loose_panel` | A **charged Heavy** on bag 3 (the Body bag) swings it wide and reveals the panel; **Grab** next to it pulls it off | 50 Clout, Ludlow's "panel pal" line, the crawlspace opens |
| 2 `sec_crawlspace_tooth` | Walk into the crawlspace, interact with the jar | Gold Tooth (gag piece) |
| 3 `sec_sleeping_scrapling` | 600+ on the Heavy bag wakes it; it drops its lid and runs for the dock (2.6 m/s, a little slower than any fighter). Grab the lid; **Grab the Scrapling** before it crosses the roller door | Trash-can lid (idle prop); +25 Clout for the catch |
| 4 `sec_belt_case_combo` | **Taunt** three times within 20 s in front of the case; Kid Lamprey: "...it's not even locked"; press A | Replica belt (back piece) |
| 5 `sec_booth_tape` | **Guard** (crouch) under Barnaby's desk and press A | Vintage Bellows line pack; Barnaby plays the 1973 tape: a 40 s AI-vs-AI fight vs a silhouette |
| 6 `sec_freight_elevator` | Carry Ludlow the **fuse** (by the boiler), the **cable spool** (behind the forklift) and the **button** (filing cabinet #2 — needs Scouting Report bought) | The elevator runs: the Roof |
| 7 `sec_roof_sign` | Grab the fallen **A** by the water tower and throw it into the sign's gap | 100 Clout, Sign Fixer frame, Rooftop full-neon unlock |
| 8 `sec_pier_ladder` | A crate thrown 8 m+ that lands in the water scares the gulls off the ladder | The Pier: 20 s fishing casts; the first catch is Pier Night (Chum Rush arena variant), then OTC supplement variants |
| 9 `sec_boiler_face` | Ten **Scorch** hits on the boiler (other elements don't count) | Sizzle JUICE colour; Teddy's "don't do that again" |
| 10 `sec_doc_dumpster` | Stand in the ice bath for 30 s (the screen frosts), then press A | Frozen Blister pet, 50 Clout |

## 8. HUD and boards

`HubHud`: the space and time of day, Clout (animated gains), the activity panel (time, score/streak),
countdowns, banners (new place, tiers, secrets), subtitles, the interaction prompt with the bound
button, carry hints and the frost overlay.

Every menu is a **diegetic board** (`HubBoard`, App screen `hub_board`, an overlay over the live hub):
Granny's clipboard / Doc's chart / Needles' menu / Snappington's ledger / Ludlow's workbench / Teddy's
ledger (stations), the sign-up sheet (run start), the corkboard map, your locker (walking fighter and
hub cosmetics), the Wall of Fame & Shame (records), Barnaby's desk (announcer settings and line
packs), conversations, lessons, the shop and rest previews, sparring, the pause board. They are built
from the shared widget library, so focus always starts inside the board, the D-pad/stick moves it, A
selects and B closes (a board with nothing to select gets a focused Close). Text is ≥ 18 px at
1280×800 (tested, §12).

## 9. Services: stations, run start, Bookie's Table, AI Lab (`HubServices`)

`HubServices` is the one adapter between the hub and the campaign module; it calls the campaign API
directly (`FightCamp`, `CampaignCatalog`, `CampaignFlow`, `RunRng`). Tests can inject a backend
object with the same calls.

- **Stations** (6): `FightCamp.list_upgrades/buy_upgrade` with the profile — Clout, levels and gates
  (e.g. Grappling Dummy needs Act 1 beaten) are the campaign's rules. Gym Floor (6), Med Bay (3),
  Juice Bar (4), Office (6), Loading Dock (3), Boiler Room (2) = the 24 Cannery upgrades. Rows show
  level pips, the next cost or the lock reason, the effect and **what changes in the world**.
- **Purchases change the world** (`HubUpgradeProps`, refreshed on `HubState.changed("upgrade")`):
  every upgrade has a visible prop per level (new bags, bikes by the mats, the ice bath's lid, filing
  cabinet #2, the dock's sound system, ...). At 12+ upgrades the Main Floor's dead fluorescents are
  replaced by working ones; at all 24 the Glandco banner over the cage becomes a banner of your fighter.
- **Run start** at Snappington's desk (the sign-up stand or her conversation): fighter, difficulty,
  Dose, seed text and co-op format → `FightCamp.run_config` (Cannery upgrades carried as meta) →
  `CampaignFlow.start(catalog, cfg).show_current()`; the campaign menu (suspended runs, co-op lobby) is
  one button away. The campaign's **development stand-ins** (a custom run, no records) are a developer
  tool: the sheet (like the campaign menu and the Bookie's Table) offers them only behind the dev flag
  (`CampaignFlow.dev_tools()`: `--dev`, `--campaign-stand-ins` or Settings → Diagnostics → Developer
  tools) and only while some roster kit is still unusable.
- **Bookie's Table**: `App.goto("bookie", {from_hub})`; leaving the table walks you back to Teddy.
- **AI Lab terminal**: `App.goto("lab", {from_hub, boiler_room_key})`; Back returns to the terminal.
  Without the screen installed, Teddy says the terminal is dark.
- Needles' **shop preview** and Doc's **rest preview** read the campaign catalog (prices in Scrip);
  they are previews — buying happens on the run.

## 10. Persistence

Everything lives in the profile (`Profiles.current`), wrapped by `HubState`:
`camp.clout / clout_total / upgrades / secrets / flags / hub_spot` (shared with FightCamp) and
`camp.hub = {discovered, tour_done, visits, rewards, best, bag_tiers, spar, parts, hints, loadout,
last_result, last_seen_run, boiler_hits, packs}`; hub cosmetics go to `unlocks.cosmetics` (ids
prefixed `hub_`). The scene saves when state changes (at most every 2 s), on secrets and purchases,
and when it leaves.

## 11. Performance

`godot --path game -- --hub --hub-bench [--bench-seconds 6] [--preset high] [--out f.json]`
(`HubBench`): places the fighter in every space and walks its nav points while sampling frames, VSync
and the frame cap off. Measured on the reference PC (i7-7700K, RTX 4070 Ti SUPER), reports in
`docs/evidence/hub/bench_hub_*.json`:

| Run | Mean | p95 | p99 | Frames over 16.7 ms | Draw calls (mean / p95) |
|---|---|---|---|---|---|
| 1920×1080, High, 6 s per space (24 612 frames) | 2.68 ms (373 fps) | 4.46 ms | 5.53 ms | 7 (0.03 %) — first frames after being placed in a new space | 168 / 268 |
| 1280×800, Deck preset, 4 s per space (17 733 frames) | 2.48 ms | 4.54 ms | 5.56 ms | 4 (0.02 %) | 141 / 242 |

Building the hub takes ~10 ms (sim) + 0.2–0.35 s (view) on that machine.

## 12. Tests and evidence

`godot --headless --path game --fixed-fps 120 -- --test test_hub_` — 54 tests:

| File | Covers |
|---|---|
| `test_hub_geometry` | layout data consistency; **every space reachable on foot** (a real fighter walks the nav graph through all 11 spaces, taking stairs, hatch, ladders, elevator, pier ladder); walls/blockers hold; a thrown crate flies over the dock-edge blocker; stairs up/down |
| `test_hub_interactions` | every interactable fires its event; **A interacts instead of dodging** (and still dodges in the open); carry/heave a crate; **the throw rule** for every roster fighter (kit's best throw / roster average × body factor) and its consequences (Dredge and Dozer out-heave Stoke, Stoke out-heaves Jitters, Stoke reaches the 8 m ring and Jitters only the 5 m one, a quick toss is short); hits on NPCs are shrugged off, nobody goes down; transitions and Fast walk |
| `test_hub_activities` | bag points formula; bag challenge with real hits pays Clout tiers per fighter; chum drill counts dodges/guards/parries/hits; crate toss rings, tiers, foul, Jitters hint; sparring config |
| `test_hub_secrets` | all ten secrets through their real triggers, Ludlow's one hint per visit, found secrets persisting into the world |
| `test_hub_services` | every station lists its upgrades (24 at 6 stations, each with a world change); purchase flow spends Clout and respects gates; purchases change the world (12+ lights, 24 banner); run options/config; **run start hands over to the campaign's run screens**; **the Bookie's Table and the AI Lab open for real and return to the Boiler Room**; injected backend |
| `test_hub_wander` | **two minutes of scripted wandering with every roster fighter** (biped, crab, quadruped, avian, serpent, hopper; least-visited goals, hatch/ladder/elevator rides, fight buttons mashed at a player's pace): never below the floor, never off the map, never left down, no damage, no ring-out, rarely stuck (≤ 2 legs timed out, ≤ 8 waypoints given up on). `HUB_WANDER_ONLY=f_dredge` runs one |
| `test_hub_cosmetics` | the locker's wearables on all six roster bodies and the dev biped: fitted to the forged model (vertices collected per segment; on the skin, rings hugging the body, nothing over the mouth), on the right part, following the body, no collision, lid and belt put away mid-round; the gold tooth pops as the gag piece; in a headless `MatchScene` only the profile owner is dressed, Sizzle recolours Stoke only, the frame wraps the owner's HUD card; frames on results and profile; the locker only offers what shows; the can shelf |
| `test_hub_unlocks` | Rooftop full neon replaces the night look once unlocked (dead A before), Pier Night is a hidden Chum Rush look in the versus setup's Look row; Vintage Bellows calls matches when selected; dev stand-ins hidden in normal play; Kid Lamprey's real kit is picked up automatically |
| `test_hub_ui` | the real `HubScene` via `Cannery.enter()`: **every board** (all stations, every NPC's conversation, map, locker, records, booth, run, spar, lessons, shop, rest, pause) opens with focus inside, D-pad moves it, **B closes back to walking** without grabbing; boards and HUD fit and read ≥ 18 px at 1280×800; Enter / pad A talk instead of dodging; the **first secret unlocks ach_confidant** |

Screenshots (`docs/evidence/hub/`, captured with `--hub --hub-demo ... --capture`): every space,
the secret Roof (night, sign fixed) and Pier, time-of-day and upgrade states, your banner after all
24 upgrades, the chum drill in progress, the main boards (and one at 1280×800); `22`–`29`: the
wearables on every body and close-ups, the fight-view walkout with the framed name card, Stoke's
Sizzle, the profile screen's frame, the can shelf, Rooftop night vs full neon, Pier Night.

## 13. Deviations from HUB.md

- **Basement, Roof and Pier are separate regions at ground level** reached through a short fade
  (hatch, freight elevator, pier ladder) instead of a −4 m basement and a +7 m roof streamed in place.
  The sim's ring-out check treats anything below y −1.2 as falling out of the arena, so the hub keeps
  every floor at y ≥ 0; a separate region also keeps lighting/occlusion of the main building simple.
- **Ladders are interactions** (booth ladder, pier ladder): the active-ragdoll rig cannot climb, so
  "climb" is the same short fade.
- **Bag-2 Flare-Up**: the bags are props, not fighters, so they have no status system; the Heavy bag
  keeps its own elemental build-up from element-tagged hits and fires the real `Elements.reaction`
  (Flare-Up → Granny's line) when two elements pass the threshold.
- **Kid Lamprey**: until his creature kit (`npc_kid_lamprey`) parses cleanly, sparring uses a roster
  fighter named Kid Lamprey (Gusto, else Jitters, else Stoke); the switch to the real kit is
  automatic. The Locker Room NPC uses its own hub model.
- **The 1973 tape** is a live 40 s AI-vs-AI fight between two headliner bots (Snappington — her
  stand-in body until the boss kit exists — vs a challenger drawn as a silhouette) under a sepia
  broadcast overlay with Vintage Bellows calls, rather than a recorded replay (there is no replay
  recording format).
- **Development stand-ins** for unfinished kits are a developer option only (dev flag, §9).
- The Locker Room's "lockers (cosmetics/loadouts)" board covers the hub's walking fighter and hub
  cosmetics; run loadouts are chosen on the sign-up sheet.
- **Fished supplement cans** are a collection on a locker-room shelf rather than an equippable "can"
  slot (a held can had nowhere sensible to show on six different body plans).
- **Pier Night** is a look you pick (the versus setup's Look row for Chum Rush on the Drydock); the
  **Rooftop full neon** replaces the stock night look everywhere once the sign is fixed.

## 14. Known gaps

- Cosmetics are local and view-only: on your screen your own fighter wears them; other players'
  cosmetics are not sent in online matches (no field for them in the networked match config yet).
- Frames wrap the name card where the active profile's card is shown: the fight HUD, the results
  table and the profile screen. There is no separate lobby name card to frame.
- Attachments are fitted automatically to each body (§16); a kit can pin any of them with
  `art.attach.<kind>` if an automatic fit ever looks off on a new model.
- Real kits for the bosses will replace the stand-ins without hub changes.
- The frame-time numbers are from one machine (the reference PC); a Steam Deck run is not verified.

## 15. Files outside the hub folders

| File | Change | Why |
|---|---|---|
| `src/app/app.gd` | `SCREENS["hub"]`, `SCREENS["hub_board"]` | App screens for the entry and the boards |
| `src/app/main.gd` | `--hub` start flag and its options | open the hub directly (QA, captures, bench) |
| `src/ui/screens/main_menu.gd` | Fight Camp → `hub` | the main menu enters the Cannery |
| `src/campaign/ui/run_summary_screen.gd` | BACK TO THE CANNERY button for Fight Camp runs | runs end back in the hub |
| `src/campaign/ui/bookie_screen.gd` | `return_to_hub` (from `params.from_hub`) | leaving the Bookie's Table walks back to Teddy |
| `src/lab/ui/lab_screen.gd` | `return_to_hub` (from `params.from_hub`) | Back from the AI Lab walks back to the terminal |
| `src/view/cosmetic_attachments.gd` (new) | fitted anchors + meshes for tooth, lid, belt, scarf | §16: the wearables in the fight view |
| `src/view/fighter_cosmetics.gd` (new) | profile → attachments, JUICE style, frame; `dress(view, profile)` | §16: one place that reads the locker for every view |
| `src/view/creature_view.gd` | per-segment model vertices, `set_cosmetics`, `set_juice_style`, walkout hiding, the gold-tooth gag | §16 (view-only; no sim access) |
| `src/view/shaders/creature.gdshader` | `glow_color` uniform | Sizzle recolours glowing surfaces |
| `src/app/match_scene.gd` | `owner_index`; dresses the owner's view; walkout pieces off while the round is live; JUICE VFX use the view's colour | §16 |
| `src/ui/widgets/profile_frame.gd` (new), `src/ui/fight_hud.gd`, `src/ui/screens/results_screen.gd`, `src/ui/screens/profile_screen.gd` | `ProfileFrame.wrap` round the owner's name card | profile/nameplate frames |
| `src/view/arena_variants.gd` (new), `src/app/app.gd`, `src/ui/screens/versus_setup.gd`, `src/editor/arena_editor_screen.gd` | unlock-aware arena looks; `resolve_match_config` upgrades night → full neon; the Look row; the editor hides locked looks | the two arena variants |
| `src/view/arena_set_dressing.gd`, `src/view/arena_view.gd`, `content/core/arenas/arena_rooftop.json`, `arena_drydock.json` | per-letter GLANDCO sign (dead A unless `sign_full`), the neon border; Drydock night sky; the `night_neon` and `pier_night` variants | the two arena variants |
| `src/audio/audio.gd`, `content/core/announcer/barnaby_vintage.json` (new) | announcer line packs (`pack` lines, `set_announcer_pack`, profile `announcer_pack` read at `begin_match`) | Vintage Bellows in matches |
| `src/campaign/campaign_flow.gd`, `src/campaign/ui/campaign_menu_screen.gd`, `src/campaign/ui/bookie_screen.gd`, `src/persist/settings.gd` | `CampaignFlow.dev_tools()`; stand-in switches behind it; `diag.dev_tools` setting | dev stand-ins hidden in normal play |

## 16. What the locker unlocks, in the game

Everything the locker offers shows outside the hub too; all of it is presentation — the simulation
never sees it. `FighterCosmetics` reads the profile (`camp.hub.loadout.cosmetics`, filtered by
`unlocks.cosmetics`) and `FighterCosmetics.dress(view, profile)` applies it to a `CreatureView`.
Only the **profile owner's** fighter is dressed (the first local player in `MatchScene`, your walker
in the hub); bots and other players are not.

| Unlock (`content/core/hub/cosmetics.json`) | From | Shows |
|---|---|---|
| Gold Tooth (`piece`) | secret #2 | in the mouth; at the end-of-fight gag it pops out instead of the kit's gag piece (a debris-layer body that never touches the sim) |
| Trash-Can Lid Shield (`idle_prop`) | secret #3 | strapped to the outer side of the left forearm/wing (armless bodies: slung on the back, or flat on top of a horizontal body); on walkouts, celebrations and in the hub, put away while the round is live |
| Replica Belt (`back`) | secret #4 | a sash over the shoulder (a girth strap round a horizontal body, a waist belt low on a hopper); walkout piece like the lid |
| Rooftop Scarf (`neck`) | the roof trunk | a scarf where the head meets the body, tails trailing; always on |
| Sign Fixer / Soaked frames, Headliner badges (`frame`) | secret #7, the chum drill, sparring | `ProfileFrame` round the owner's name card in the fight HUD, the results table and the profile screen (border, glow, tag line) |
| Sizzle (`juice`) | secret #9 | Stoke only: his JUICE glow and glowing surfaces go white-hot (creature shader `glow_color`), the JUICED! burst in that colour |
| Rooftop: full neon (`arena_variant`) | secret #7 | the Rooftop's `night_neon` look replaces the stock night (every GLANDCO letter lit, neon border; stock night has a dead A) — `ArenaVariants.upgrade` in `App.resolve_match_config` |
| Pier Night (`arena_variant`) | first catch on the pier | a hidden Drydock look for Chum Rush: the versus setup's **Look** row offers it once fished up (match context `variant`) |
| Vintage Bellows line pack (`pack`) | secret #5 | Barnaby's desk sets the profile's `announcer_pack`; `Audio.begin_match` reads it and 1973 Barnaby calls the match (triggers the pack lacks fall back to the standard bank) |
| Fished cans (`collection`) | fishing | a shelf in the Locker Room |
| Frozen Blister (`pet`) | secret #10 | follows you round the hub |

**How the wearables are fitted** (`CosmeticAttachments`): each piece rides one body segment and is
placed from the forged model's own vertices (`CreatureView` collects them per bone/segment; fallback
bodies use their body shapes), so it fits all six roster bodies, the dev biped and future kits without
per-creature data:

- *rings* (belt, scarf) are ellipses fitted to the body's outline where a plane cuts it — the furthest
  vertex in 16 directions, snouts, beaks and jaws dropped — drawn as an elliptical tube that hugs oval
  bodies;
- *scarf*: on a neck, the narrowest well-filled cut between head and neck; a head sitting on the body
  gets a ring round its base (Dredge: round the eye stalks); a ring that would cross the mouth is
  tipped forward about its back so it dips under the chin (Stoke);
- *tooth*: the front of the lower face, weighted toward the middle line (eyes either side lose); a head
  with nothing on its middle line (eye stalks) wears it on the body just below;
- *lid*: the outer side of the distal left arm or wing.

A kit can pin any piece with `art.attach.<kind> = {segment, offset, rotation_deg, size}`.

**Dev stand-ins and Kid Lamprey.** The campaign's development stand-ins (for kits that don't parse
yet) appear only behind `CampaignFlow.dev_tools()` — never in normal play. Sparring switches to Kid
Lamprey's own kit (`npc_kid_lamprey`) by itself as soon as the campaign resolver accepts it.
