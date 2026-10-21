# Moveset combat (v0.9.18)

Critterweight 0.9.18 turns creature combat into fights between named, learnable movesets:
flamethrowers, poison darts, bubble streams, hydro cannons, lightning and spectral lanterns, thrown
in a real-time physical cage fight. This document is the design the implementation follows. The
v0.9.17 combat survives whole as **Classic**, chosen by a match rule.

Status: design, 2026-10-20. Numbers are starting values; balance changes are recorded in the kit
docs (`docs/kits/`) and the release notes.

## 1. Two combat styles, one rule

| | **Movesets** (default everywhere) | **Classic** |
|---|---|---|
| Offence | four equipped named moves from the fighter's move pool | Light string, Heavy (hold to charge), two abilities |
| Ultimate | the fighter's JUICE ultimate | JUICE |
| Defence | Guard (tap = parry), Dodge, Grapple, plus each loadout's counters and deflects | Guard, Dodge, Grab |
| Progression | learn, equip, replace and drill moves | techniques, supplements (unchanged) |

* **Rule.** `combat`: `"moves"` | `"classic"` in the rules dictionary (RulesValidator `FIELDS`,
  group Fighters, label "Combat style", values "Movesets" / "Classic"). It is a real match rule:
  normalized and validated like every other field, sent in `S_MATCH_START`, re-validated by every
  client, whitelisted for co-op campaign fights, stored in replays and results. A missing key means
  `"moves"` for every rules dictionary the game builds (versus, teams, tag, bonus modes, practice,
  spectating, campaigns, Career, Bookie fights, playlists, dedicated servers, tutorials, hub
  sparring, AI Lab outside policy training).
* **No half modes.** The simulation reads the rule once per fighter (`Fighter.combat_style`). The
  style decides which action table `_try_actions` uses, what the HUD and prompts show, what bots
  press, which upgrades apply and how judges count. Classic is the v0.9.17 code path unchanged;
  the v0.9.17 art, VFX and commentary apply to both styles.
* **Older files.** User rules presets (`rules_preset` v1 → v2) gain `"combat": "moves"`: they were
  written before the choice existed, every explicit field they set is kept, and the Rules Editor
  shows Classic one click away; the migration records `migrated_from`. Built-in presets name the
  style explicitly. Saved runs, careers and profiles migrate as in §8.

## 2. Controls

### 2.1 Ordinary roster (seven fighters)

| Pad | Keyboard / mouse | Movesets | Classic |
|---|---|---|---|
| X | J / LMB | **Move 1** | Light |
| Y | K / RMB | **Move 2** | Heavy (hold = charge) |
| LB | Q | **Move 3** | Ability 1 |
| RB | E | **Move 4** | Ability 2 |
| RT | R | **Ultimate** (JUICE) | JUICE |
| B | F / MMB | **Grapple** (or the context action: ball, revive, hub, objective) | Grab |
| LT | Shift / L | Guard (tap = parry) | Guard |
| A | Space | Dodge | Dodge |
| Left stick | WASD | move; **aims** streams and aimed moves while they are held | move |

* The four move inputs are the same physical inputs in both styles, so rebinding, the network
  input format and accessibility options stay as they are. Their names follow the style and the
  loadout: the HUD, button prompts and the Controls screen say "Flamethrower (X)", not "Heavy".
* **Hold behaviour is per move**: `charge` (charges while held, fires on release; Hydro Cannon,
  Furnace Haymaker), `sustain` (keeps going while held, up to a maximum; Flamethrower, Bubble
  Stream), or none.
* **The basic strike** (every fighter has one) is a string: press again to continue it, a fourth
  press at the end of the string is the finisher, and pressing it out of a dodge is the dash
  strike. It costs little and has no cooldown, so a fighter always has something useful to do.

### 2.2 Varga (advanced controls, §6)

Varga keeps his Cage Rules layout: four limbs (X/Y/A/B), three modifiers (LB hooks / RB straights
/ LT overhands; for legs: none, body, head, low), stance switch (D-left), check (D-down), two
abilities (D-up / D-right), JUICE (View), guard on RT. In Movesets his strikes become fighting-type
techniques chosen per modifier group.

## 3. Moves

### 3.1 Categories

| Category | Behaviour | Typical counterplay |
|---|---|---|
| strike | close-range melee (basic strings, haymakers, holds) | guard, parry, out-range |
| projectile | one precise shot, aim-assisted at the locked target | dodge, guard, deflect, close in |
| volley | several projectiles in a fan or a burst | dodge sideways, guard |
| stream | sustained while held, aimed with the stick, drains stamina | dodge sideways (it turns slowly), get behind, interrupt |
| blast | charged while held, released as a big area or beam; recoil and recovery | interrupt the charge, punish the recovery |
| rush | movement attack: charge, dash, leap or blink with a hit | sidestep, guard, counter |
| counter | a stance that answers a hit | grapple it, wait it out, use projectiles |
| control | zones, pulls, traps, area denial | leave the area, dodge through, fight elsewhere |
| support | buffs, shields, cleanses, healing | pressure while it is active, wait |
| utility | positioning: hover, blink, props | track and punish the landing |

### 3.2 Move data

A move pool entry (creature JSON `movepool`, Movesets only; Classic ignores it):

```jsonc
"flamethrower": {
  "name": "Flamethrower", "short": "Sustained flame cone you aim with the stick",
  "desc": "Hold to pour fire...", "category": "stream", "role": "special",
  "element": "scorch", "cooldown": 6, "charges": 1,
  "hold": "sustain", "max_hold": 2.4, "drain": 10,       // stamina per second while held
  "aim": {"turn_rate": 2.2},                               // rad/s the stick (or the target) steers it
  "move": { ...an ordinary MoveDef: duration, keys, hit windows, "sustain": [t0, t1], effects... },
  "styles": {"wide": {"name": "Wide Nozzle", "desc": "...", "patch": [...]},
             "jet": {"name": "Pressure Jet", "desc": "...", "patch": [...]}},
  "ai": {"range": [0.8, 3.2], "hold": [0.8, 1.8], "when": ["target_close"]}
}
```

* `use` instead of `move` builds a pool entry on a v0.9.17 move (`"use": "heavy"`, `"charged":
  "heavy_charged"`, `"use": "ability1"`): the same animation, hit windows and effects, so the
  upgrades written for that move keep improving it (§7). Basic strikes name their `string`
  (`["l1", "l2", "l3", "finisher"]`) and `dash` move.
* `role`: `basic` (no cooldown, cost ≤ 6), `heavy` (the big committal hits), `special`
  (everything with a cooldown) or `support`; it is what translated upgrades key on (§7).
* Every fighter ships two named recommended **loadouts** (`loadouts`, `default_loadout`) that play
  differently.

### 3.3 Engine additions (EffectsSystem, MoveDef, Fighter)

* **Repeating effects**: `every` (seconds) with `until` (`"release"`, seconds, or a `count`) fire an
  effect repeatedly inside a move: streams, bubble emitters, dart bursts. They run on the move's own
  clock, not the (rewindable) animation time.
* **Sustain**: a move's `sustain: [t0, t1]` window loops while its input is held (up to
  `max_hold`, while stamina lasts); `drain` stamina per second; release or empty stamina plays the
  rest of the move (its recovery).
* **Charge for any move**: the v0.9.17 heavy charge (hold at 70% of the wind-up, lights armour while
  charging) generalizes to every `hold: charge` move and its own input. `charge_scale` on effects
  scales damage, radius, speed, knockback and recoil by the charge.
* **Recoil**: effect type `recoil` {speed, up}: the shooter is pushed back (Hydro Cannon).
* **Aim**: while an aimed move is active the left stick turns the fighter at the move's
  `aim.turn_rate`; with the stick neutral it tracks the locked target at the same rate. Projectiles
  keep the v0.9.17 aim assist (`aim: "target"`), lobs land on the target point.
* **Attribution**: every hit and effect event carries the pool move id and its category, so judges,
  commentary, hooks, statistics and the HUD know which move landed.
* **Tick throttles**: hits from repeating effects (`tick: true`) give 30% hype, refund no stamina,
  stun at most once per 0.5 s per target, count once per 0.5 s in combo scaling and the stun budget,
  and never trigger hit pause or camera shake. A stream cannot stun-lock or snowball hype.
* **Denied presses**: a move press without enough stamina, or on cooldown, is consumed with a
  `move_denied` event (HUD flash, a dry click) instead of silently disappearing.

### 3.4 Resources

* **Stamina** (existing pool and regeneration): every move costs stamina at the start; streams drain
  it per second; dodges, guard chip and grapples use it as before. Below 20 the fighter slows (as
  in v0.9.17); at 0 only basic strikes can start, and a basic costs ≤ 6 (half a second of regen).
* **Cooldowns and charges** per move (Sludge Lob keeps its two charges).
* **Hype → Ultimate** (JUICE) exactly as in v0.9.17.
* Elements build statuses on hit (Sizzle, Soaked, Jolted, Gunked, Caked, Winded, Rattled,
  Haunted) as before.

### 3.5 Targeting

Soft lock-on stays (nearest enemy in front; Target switches). Projectiles and volleys aim at the
locked target with assist; lobs land on its position (capped by range); streams follow the stick
(else the target) at their turn rate; cones and lines fire along the facing and draw their true
footprint; rushes go toward the target and some steer (Bulldoze). Moves never auto-aim through
walls or props.

### 3.6 Defence

* **Guard** blocks the front arc (80°) with chip damage and stamina drain. Streams chip guards with
  little knockback but keep draining guard stamina (`guard_break` per move), so turtling against a
  flamethrower ends in a guard break: dodge out of its arc instead.
* **Parry** (a fresh guard press up to 0.12 s before contact) answers strikes and the projectiles
  marked `parryable` (darts, slashes, bolts): a parried projectile is destroyed and the shooter
  loses the hype.
* **Dodge** keeps its invulnerability and passes through projectiles, areas and stream ticks.
* **Grapple** beats guard and counters (as Grab did).
* **Loadout defences**: counters (Anchor Drop, Toll), deflects and blockers (Steam Vent destroys
  projectiles, bubbles block shots, Rock Slide rocks are cover), and supports (Shell Brace, Iron
  Hide).

### 3.7 Types

Elements matter in four layers: the matchup table (±15% damage), status build-up (each element's
status), the 14 status reactions (Steam Burst, Short-Out, Flare-Up, Stormfront...) and the 11 zone
reactions (fire on a sludge puddle burns, static in water electrifies it, wind carries fire). v0.9.18
makes them part of each move:

* moves carry their element into effects, streams and zones (a Flamethrower over Slurry's sludge
  ignites it; Bubble Stream puts out scorch patches; Chain Lightning jumps further between Soaked
  targets);
* the three reactions that did nothing (Bell Ringer, Grave Chill, Crack Guard) now apply their damage,
  stun and statuses as the Compendium always said;
* spectral projectiles pass through cover props; grit cover blocks every other projectile.

## 4. Movesets

Every ordinary fighter has eight pool moves: one **basic** strike string, its v0.9.17 heavy (now a
`hold: charge` move), its two v0.9.17 abilities, and four new moves. Its Ultimate is its JUICE.
(★ = in a recommended loadout; A/B name the loadout.)

### Stoke (scorch) — furnace brawler

| Move | Cat. | Hold | Behaviour |
|---|---|---|---|
| Ember Jab (basic) ★A★B | strike | – | Jab, Cross, Lead Hook, Gut Furnace finisher, Stoke Step dash strike; each hit builds Sizzle |
| Furnace Haymaker ★B | blast | charge | Overhand Boiler → Furnace Haymaker when charged; lights armour while charging |
| Steam Vent ★A | blast | – | the v0.9.17 cone of steam: knockback, destroys projectiles |
| Stoke the Fire ★A | support | – | the v0.9.17 stack-venting buff |
| **Flamethrower** ★A | stream | sustain | a 40° cone of fire 3.2 m long, ticks every 0.12 s, aimed with the stick, drains stamina; leaves a scorch patch where it lingers |
| **Cinder Shot** ★B | projectile | – | a lobbed fireball that bursts on landing and leaves a scorch patch |
| **Flare Rush** ★B | rush | – | a burning dash punch; recoil throws Stoke back on contact |
| **Fire Spin** | control | – | a ring of flame around Stoke for 3 s that pushes out and burns |

A "Furnace": sustained flame pressure behind Steam Vent's shield. B "Brawler": charge, rush and
lob, all-in damage.

### Dredge (brine) — tide crab

| Move | Cat. | Hold | Behaviour |
|---|---|---|---|
| Claw Snap (basic) ★A★B | strike | – | Cutter Snip, Backhand Claw, Double Clamp, Bilge Pump, Scuttle Check |
| Crusher Slam ★B | strike | charge | Crusher Slam → Hull Breaker |
| Tide Spit | projectile | – | the v0.9.17 lob that leaves a brine puddle |
| Anchor Drop ★A | counter | – | the v0.9.17 counter stance |
| **Bubble Stream** ★A | stream | sustain | blows a stream of slow bubbles that drift 4 m and pop for damage and Soaked; bubbles stop enemy projectiles |
| **Hydro Cannon** ★A | blast | charge | a long charge, then a 6 m water beam with huge knockback; recoil slides Dredge back, long recovery |
| **Whirlpool** ★B | control | – | a whirlpool zone that drags fighters toward its centre and soaks them |
| **Shell Brace** ★B | support | – | 3 s of damage ×0.6 and knockback ×0.5 at reduced speed |

A "Tidecaller": bubbles and the cannon at range, Anchor Drop for anyone who rushes in. B
"Breakwater": pull them in, brace, crush.

### Gusto (gale) — vortex bird

| Move | Cat. | Hold | Behaviour |
|---|---|---|---|
| Wing Snap (basic) ★A★B | strike | – | Wing Snap, Beak Peck, Scissor Kick, Tailspin, Skid Kick; air versions while hovering |
| Crosswind Slash | strike | charge | Crosswind Slash → Downdraft |
| Gust Bomb ★B | projectile | – | the v0.9.17 gust bomb |
| Hang Time ★A | utility | – | the v0.9.17 hover; moves can be used in the air |
| **Air Slash** ★A | projectile | – | a fast precision crescent (9 m) that pierces; parryable |
| **Feather Darts** ★A | volley | – | five darts in a 30° fan; Winded build-up |
| **Twister** ★B | control | – | a vortex that travels forward 5 m, pushing and lifting |
| **Tailwind** ★B | support | – | speed ×1.3 and cheaper dodges for 4 s |

A "Skyhook": hover and shoot. B "Cyclone": wind control and speed.

### Dozer (grit) — armoured digger

| Move | Cat. | Hold | Behaviour |
|---|---|---|---|
| Snout Jab (basic) ★A★B | strike | – | Snout Jab, Hoof Stomp, Scoop, Gravel Toss, Shoulder Barge |
| Horn Lunge | strike | charge | Horn Lunge → Quarry Ram |
| Bulldoze ★A | rush | – | the v0.9.17 steerable charge that carries its target |
| Dust Bowl ★A | control | – | the v0.9.17 dust zone and buff |
| **Rock Slide** ★A | control | – | a 5 m line of rocks bursting from the floor; they stay 3 s as cover that blocks projectiles |
| **Boulder Toss** ★B | projectile | – | a lobbed boulder: big damage and a knockdown on a direct hit |
| **Quake Stomp** ★B | blast | – | a ring around Dozer that trips anything not airborne |
| **Iron Hide** ★B | support | – | armour against light hits for 4 s |

A "Bulldozer": charge through, wall off. B "Quarry": siege from a distance, then stomp.

### Slurry (sludge) — drain wyrm

| Move | Cat. | Hold | Behaviour |
|---|---|---|---|
| Venom Fangs (basic) ★A★B | strike | – | Head Butt, Tail Flick, Fang Snap, Venom Spit, Slither Strike |
| Tail Sweep | strike | charge | Tail Sweep → Rear & Crash |
| Sludge Lob ★A | projectile | – | the v0.9.17 lob (two charges) that leaves a sludge puddle |
| Drain Dive ★A | utility | – | the v0.9.17 submerge and emerge |
| **Poison Darts** ★A | volley | – | three fast darts in a 0.12 s burst; each sticks and adds Gunked; parryable |
| **Acid Spray** ★B | stream | sustain | a short, wide acid cone that builds Gunked quickly |
| **Coil Crush** ★B | strike | – | coils around the target and squeezes: a hold that ignores guard |
| **Shed Skin** ★B | support | – | cleanses statuses and grants a moment of evasion |

A "Venomous": poke and dive. B "Swamp": close in, smother, squeeze.

### Jitters (static) — battery jelly

| Move | Cat. | Hold | Behaviour |
|---|---|---|---|
| Slap (basic) ★A★B | strike | – | Slap, Double Slap, Headbonk, Static Cling, Pinball |
| Squash | strike | charge | Squash → Super Squash |
| Arc Lash ★A | projectile | – | the v0.9.17 homing orb |
| Spring Pad ★A | utility | – | the v0.9.17 launch pad |
| **Thunder Jolt** ★A | projectile | – | a very fast bolt; Jolted build-up |
| **Discharge** ★B | blast | – | a ring of lightning around Jitters |
| **Chain Lightning** ★B | projectile | – | a bolt that jumps to a second target within 3 m (further between Soaked targets) |
| **Static Field** ★B | control | – | a field that flinches anyone entering it |

A "Live Wire": bounce and zap. B "Overload": crowd control.

### Knell (spectral) — haunted diver

| Move | Cat. | Hold | Behaviour |
|---|---|---|---|
| Sounding Jab (basic) ★A★B | strike | – | Sounding Jab, Port Hook, Deadweight, Rising Bell, Wake Breaker |
| Anchor Fist ★B | strike | charge | Anchor Fist → Deep Anchor |
| Ghost Light ★A | projectile | – | the v0.9.17 homing lantern |
| Through the Veil ★A | utility | – | the v0.9.17 submerge, reappear and burst |
| **Night Shade** ★A | stream | sustain | a ghostly beam that slows and Haunts what it touches |
| **Hex Chain** ★B | control | – | a spectral chain that tethers a target: slowed and dragged closer |
| **Lantern Swarm** ★B | volley | – | three homing wisps |
| **Toll** | counter | – | the bell rings: cleanse, brief armour, and a counter-shock against the next hit |

A "Lamplighter": lantern and beam at range, vanish when pressed. B "Undertow": chain them in,
then the anchor.

## 5. Customization and progression

* **Drills (improving a move)** choose one of the move's two **styles**, permanent for that run or
  career (Flamethrower *Wide Nozzle*: a wider, shorter cone; *Pressure Jet*: narrow, long, pushes).
  Styles change behaviour, not only numbers.
* **Off the Street**: a run starts with recommended loadout A equipped and the moves of loadout B
  learned too. Elite and boss rewards offer a **move tutor** next to techniques; the shop sells a
  **move scroll**; resting can **train** (learn) or **drill** (style); events can teach moves. The
  pre-fight screen has a **Moves** panel to equip any four learned moves (free). Every learn, equip
  and drill is a logged RunController decision, so runs verify and replay. (Implementation, the
  translation rules and the v1 → v2 run migration: docs/CAMPAIGN_SYSTEMS.md "Moves in runs".)
* **Fight Camp**: new Cannery upgrades (*Sparring Partner*: one more learned move at the start;
  *Film Study*: start with one drilled move); the existing upgrades translate (§7).
* **Career**: the training week adds *Learn a move* and *Drill a move*; the loadout is chosen before
  each bout and saved with the career.
* **Versus, practice, online**: every pool move is available. Fighter select has a Moves button with
  loadouts A and B and custom loadouts saved per profile; practice can swap moves live from its
  menu. The chosen loadout travels with the fighter entry and the server validates it.
* **Co-op campaign**: each member's learned and equipped moves live in their run state; equipping
  is a member intent that goes through the party's decision log.

## 6. Varga (advanced)

Varga stays the fighter for players who want depth. His strikes are still chosen by limb, modifier
and stance (the Cage Rules scheme). In Movesets each strike carries a fighting-type technique:

| Group | Technique A | Technique B |
|---|---|---|
| Hands, no modifier | **Aura Jab / Cross**: palms burst with gold aura on contact | – |
| Hands + hooks (LB) | **Comet Hook**: a trailing shockwave arc that clips a second target | **Spiral Hook**: a spinning aura that drags the target in |
| Hands + straights (RB) | **Pressure Palm**: hold to charge an aura blast that flies | **Force Palm**: point-blank burst that breaks guard |
| Hands + overhands (LT) | **Meteor Hammer**: an overhead that cracks the floor in a small ring | **Thunder Chop**: a fast overhead with a stun spark |
| Legs, no modifier | **Pressure-Wave Teep**: a push kick that sends a pressure cone | – |
| Legs + body (LB) | **Shockwave Roundhouse**: a wave arc at body height | **Iron Shin**: armoured kick through strikes |
| Legs + head (RB) | **Crescent Moon Kick**: an arcing wave projectile | **Axe Kick**: a downward kick that knocks down |
| Legs + low (LT) | **Sweep Quake**: a low kick whose quake trips | **Leg Breaker**: Rattled build-up, slows |

Contextual combinations: a completed three-hit string unlocks **Thousand-Fist Flurry** as its
finisher; check + straight is **Iron Counter**; stance switch + dodge is **Afterimage Rush**; an
uppercut on a nearby target is the **Shockwave Uppercut** launcher. His two D-pad abilities are
chosen from Cut the Angle, Second Wind, Afterimage Rush, Iron Counter and Focus Aura. His loadout =
one technique per modifier group + two abilities; A "Aura Boxer" and B "Shockwave Kicker". The guide
(`docs/kits/f_varga.md`, Compendium) and his tutorial text describe the techniques. Classic Varga is
the v0.9.17 Varga. Skins and combat styles are independent (all four combinations are tested).

## 7. Upgrades written for the old slots (no silent no-ops)

* Every v0.9.17 move is still in each pool (basic strings, heavies, the two abilities), so a patch
  written for `moves.heavy`, `moves.l1`, `abilities.ability1` keeps improving that move.
* **Translation by role**: in Movesets, slot-targeted patches also reach the equipped moves of the
  same role: `l1/l2/l3/finisher/dash_attack` → the basic strike; `heavy/heavy_charged` → moves with
  role `heavy`; `abilities.*` → `special` moves; `moves.*` → every move. Multipliers transfer
  directly; additive damage on a repeating move becomes the equivalent multiplier, so +1 damage
  never becomes +1 per stream tick.
* Hook conditions on `slot`/`slots`/`move_class` match through the same roles.
* Every upgrade says what it improves ("Improves: Furnace Haymaker, Hydro Cannon") and marks moves
  that are not equipped; run rewards prefer upgrades that touch the current loadout. A lint test
  checks that every technique, supplement, Cannery upgrade, event patch and hook condition affects
  at least one move of each recommended loadout in Movesets and a move in Classic.
* Career stats are mods (style-free); Career and gym upgrades keep working.

## 8. Saves and migrations

| File | v0.9.17 | v0.9.18 | Migration |
|---|---|---|---|
| Rules preset | rules_preset 1 | 2 | adds `combat: "moves"`, keeps every field, records `migrated_from` |
| Off the Street run | campaign_run 1 | 2 | each player gets learned = loadouts A ∪ B, equipped = A, no drills; the decision log replays with that start |
| Career | career 1 | 2 | the fighter gets the same starting moves |
| Profile | profile 1 | 2 | adds custom loadouts (empty) |

Each migration is explicit, tested with v0.9.17 fixtures, and older builds refuse the newer files
(the Saves version guard) instead of corrupting them.

## 9. Whole-game integration

* **Bots** build their options from the equipped loadout: each move's `ai` hints (range band,
  conditions, hold and sustain times, aim) drive when they press it; streams are aimed at the
  target, charges are held to the hinted level, counters are used against wind-ups, supports when
  it is safe. Difficulty tiers keep their reaction, accuracy and aggression.
* **AI Lab**: policies (`act_v1`/`obs_v1`) were learned on Classic inputs, so policy matches and Lab
  training run Classic; a policy-controlled fighter in a Movesets match falls back to the bot brain,
  and the Lab says so.
* **HUD**: four move cards (name, button glyph, cooldown veil, charges, hold type, cost) and the
  Ultimate gauge; a denied press flashes the card. Online clients get cooldowns and charges from the
  snapshot (which also fixes the v0.9.17 online cooldown veil).
* **Tutorial**: Granny teaches Movesets (each slot, hold to charge, sustain and aim, guard and
  parry, dodge, grapple, ultimate); Classic keeps its lessons; Varga's lessons describe his
  techniques.
* **Compendium and kit docs**: a page per fighter listing the pool, categories, styles and both
  loadouts; "Combat basics" explains Movesets and Classic.
* **Judging**: effect hits carry their move and category. "Landed" counts strikes, projectiles,
  volleys and blasts per hit and streams and zones once per second of contact per target; statuses
  count as pressure. Damage points are unchanged.
* **Referee**: protection voids every opponent hit on a downed fighter (strikes, projectiles,
  streams, zones); counts and stoppages are unchanged; unlimited-HP scoring keeps refilling.
* **Modes**: Chumball, the hub, tag, revive and objectives intercept their buttons before moves (as
  they did before Light/Heavy/Grab); Grapple (B) keeps the ball, revive and interact.
* **Commentary**: the director calls moves by name and category (a stream that connects, a charged
  cannon, a counter that worked), reusing the v0.9.17 ability recordings where a move is a v0.9.17
  ability and recording new calls within the remaining Breeze allowance.
* **Networking** (protocol 7): fighter entries carry the loadout and styles; snapshots carry
  cooldowns and charges per slot and the stream/beam state; rules carry `combat`; the content hash
  covers move pools. **Mods**: the creature schema gains `movepool`, `loadouts` and styles; a creature
  without a pool gets one built from its Classic moves (basic string, heavy, abilities).

## 10. Testing

Per-move behaviour (sustain, aim, charge scaling, recoil, volleys, attribution, throttles, denied
presses), loadout validation and changes, resources, targeting, defences against each category,
damage and status interactions, the rule's defaults across every built-in mode and preset, Classic
selected explicitly, every fighter in both styles, Varga's techniques and both skins, bots using
moves, online play with loadouts, campaigns and Career progression, migrations from v0.9.17 files,
judging and the referee with the new attacks, rendered captures and performance against v0.9.17.
