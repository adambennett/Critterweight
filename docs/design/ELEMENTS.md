# CRITTERWEIGHT — Elements

Six elements. Every elemental hit adds **build-up**; at threshold the element's **status** triggers. Elements also **react** in pairs and interact with **zones** (persistent ground patches) and arena hazards. Numbers here are design defaults; the engine owns the final tuning constants.

## 1. The six elements

| Element | Icon (shape, readable without color) | Color | Status | One-line identity |
|---|---|---|---|---|
| **SCORCH** | Flame: a tilted teardrop with one inner notch | `#FF6B2B` | **Sizzle** | Attrition: burn over time, starves stamina |
| **BRINE** | Wave: a single rolling crest with a curl | `#2E9BE0` | **Soaked** | Control: heavy, slow, easy to shove, conducts Static |
| **STATIC** | Bolt: a 3-segment zigzag | `#F7E04A` | **Jolted** | Disruption: twitches interrupt, cooldowns drag |
| **SLUDGE** | Blob: a circle with three drips off the bottom | `#8BD426` | **Gunked** | Poison and anti-heal, leaves puddles |
| **GRIT** | Nugget: a hexagon with a crack line | `#B8905E` | **Caked** | Poise breaker: crumbling stance, costly dodges |
| **GALE** | Swirl: a spiral with three tails | `#CFF4F2` (outline `#4FB3B8`) | **Winded** | Displacement: lightweight, gassed, flies when pushed |

Icons are always drawn with the element color **and** the shape; HUD status pips also print the status name on hover/large UI. Colorblind-safe pairings: Scorch/Grit are the closest hues, so the flame is tall-and-pointed and the nugget is wide-and-flat.

## 2. Build-up and status rules

| Rule | Default |
|---|---|
| Threshold | 100 build-up per element, per target |
| Build-up per hit (guideline) | Light L1/L2: 10–12 · L3: 18–22 · Heavy: 28–32 · Charged Heavy: 40–45 · Ability: 35–45 · JUICE: 50–60 · Zone tick: 15–20 per second |
| Decay | Build-up decays 15/s after 1.5 s without an elemental hit of that element |
| Status trigger | Build-up ≥ 100 → status starts, build-up resets to 0 |
| Status refresh | While a status is active, further hits of that element add build-up normally; at 100 again the status **refreshes to full duration** (does not stack magnitude) |
| Post-status immunity | 2 s immunity to the same status after it ends |
| Multiple statuses | A target can carry up to **3** different statuses at once; a 4th replaces the oldest |
| Resist/weak | Damage **and** build-up of the hit ±15% (see §4) |
| Guard | A guarded elemental hit applies 50% build-up |
| Parry | A parried hit applies 0 build-up |
| Bosses | Immune to their own primary element's status; everything else applies |
| Self-application | Fighters are immune to their own primary element's status from their own attacks (Stoke never Sizzles from Stoke) but **can** be affected by reactions they trigger (Flare-Up burns Stoke if he stands in it) |

### Status effects

| Status | Duration | Effects (all applied together) | Readable tell |
|---|---|---|---|
| **Sizzle** (Scorch) | 5 s | 2 HP/s damage · stamina regen −50% · hits on the target add +5 Scorch build-up (fire feeds fire) | Ember sparks drift up, darkened patches on the body, crest/feathers smoke |
| **Soaked** (Brine) | 6 s | Move speed −15% · dash distance −20% · knockback taken +25% · Static build-up received +50% | Drip particles, darker/glossy material, squelch footsteps |
| **Jolted** (Static) | 4 s | Every 1.0 s a 0.15 s micro-flinch that **interrupts charges, holds, grabs-in-progress and ability channels** · ability cooldowns tick at 70% speed · cannot hover/glide | Arc sparks crawl over the body, the ragdoll twitches, antenna/crest hair stands up |
| **Gunked** (Sludge) | 6 s | 1.5 HP/s damage · healing received −50% · guarding costs +50% stamina (slick guard) | Green drip trail, bubbles, cough animation on idle |
| **Caked** (Grit) | 5 s | Poise max −30% · poise regen −50% · dodge stamina cost +50% · heavy hits on the target deal +20% poise damage | Dust cakes the limbs, cracked-clay decals, dust puffs when hit |
| **Winded** (Gale) | 4 s | Stamina regen 0 · dodge stamina cost ×2 · knockback taken +30% · push/pull effects on the target ×2 | Fighter visibly gasps, feather/fur ruffles constantly, breath puffs |

Magnitudes are flat (no stacking). Co-op allies can never be status-locked by each other (see §7).

## 3. Reactions

A reaction triggers when an elemental hit (or zone tick, or pulse) of element **B** connects with a target that currently carries the status of element **A** (A ≠ B). Pairs are unordered: a Brine hit on a Jolted target and a Static hit on a Soaked target both produce Short-Out. Unless noted, the reaction **consumes** status A; B's build-up still applies. Per-target reaction cooldown: **1.5 s**. The attacker who triggered the reaction is credited for its damage.

| # | Pair | Reaction | Effect | Zone/arena version |
|---|---|---|---|---|
| 1 | Scorch + Brine | **STEAM BURST** | Cleanses both statuses. Cone 2 m from the target pointing away from the attacker: push 2 m, 15 poise dmg, 4 dmg. Mist cloud zone r 2 m, 2 s (cosmetic; bots lose target lock for 1 s). | Scorch patch over a Brine puddle: both removed, steam cloud 3 s |
| 2 | Scorch + Sludge | **FLARE-UP** | Explosion r 2 m at the target: 10 dmg, knock-up 1.2 m, **60 Scorch build-up to everything in radius, attacker included**. Consumes Gunked. | Sludge puddle hit by Scorch → **Burning Puddle** 3 s: 3 dmg/s + 20 Scorch build-up/s |
| 3 | Scorch + Gale | **BACKDRAFT** | Sizzle refreshed to full and **spreads** (60 Scorch build-up) to all other fighters within 2.5 m; the Gale hit's push on this target ×2. Does not consume Sizzle. | Scorch patch pushed by Gale slides 2 m along the push and grows 50% |
| 4 | Brine + Static | **SHORT-OUT** | 8 dmg + hard stun 0.9 s (ragdoll twitch). Consumes Soaked. Everyone else standing in the same Brine puddle: 6 dmg + 0.5 s stun. | Brine puddle hit by Static → **Live Puddle** 2 s: 20 Static build-up/s + micro-flinch to anyone inside |
| 5 | Brine + Grit | **MUDBOUND** | **Mud** zone r 2.5 m, 4 s under the target: inside, move −30%, dodge distance −50%, no leap/hover/blink. Consumes both. | Brine puddle + Grit rubble → Mud zone (same) |
| 6 | Brine + Sludge | **DILUTE** | Cleanses Gunked; half of the remaining Gunked damage is dealt instantly as one burst (max 5). Defensive utility: allies can wash each other. | Sludge puddle hit by Brine: grows 50% in radius, ticks at half rate |
| 7 | Static + Sludge | **CATALYZE** | Remaining Gunked damage is dealt over 1 s instead of its remaining duration (burst); +20 Static build-up to all within 1.5 m. Consumes Jolted. | Sludge puddle + Static → **Fizzing Puddle** 3 s: both ticks |
| 8 | Static + Gale | **STORMFRONT** | A marked ring r 1.5 m under the target; **0.6 s later** a bolt strikes: 12 dmg, 25 poise, 50 Static build-up to everything inside. Dodgeable. Consumes the status that was present. | Gale vortex + Static → the vortex becomes a 2 s **Storm** zone: random bolts every 0.7 s |
| 9 | Sludge + Grit | **CRUST** | Target is **Encrusted** 2.5 s: cannot dodge or blink, takes −25% damage, knockback −50%; grabs on an Encrusted target can't be mashed out for the first 1 s. Consumes both. | Sludge puddle + Grit → puddle hardens into a 1.5 m **rubble** prop (blocks projectiles, 20 HP) |
| 10 | Sludge + Gale | **SPRAY** | 40 Sludge build-up to all *other* fighters within 2 m of the target; leaves a 1.5 m Sludge puddle 3 s. Consumes Gunked. | Sludge puddle pushed by Gale streaks 4 m along the push (thin line puddle) |
| 11 | Grit + Gale | **SANDBLAST** | Guard forced open 1.5 s (cannot guard or parry), 6 dmg; cone 2 m behind the target receives 30 Grit build-up. Consumes Caked. | Grit rubble + Gale → one-shot sand cone 3 m: 30 Grit build-up, guard open 1 s |
| 12 | Scorch + Static | — | No reaction. Both apply. | — |
| 13 | Scorch + Grit | — | No reaction. Both apply. | — |
| 14 | Static + Grit | — | No reaction. Passive note: a **Caked** target receives −25% Static build-up (grounded). | — |
| 15 | Brine + Gale | — | No reaction. Both apply. | — |

Reactions are announced with a 0.4 s on-screen word (the reaction name) at the point of impact plus the two element icons colliding, so a player learns the table by seeing it.

## 4. Resist / weak matrix

One six-step cycle: **Scorch > Gale > Sludge > Grit > Static > Brine > Scorch** ("beats" = +15% damage and build-up dealt, −15% taken from that element).

| Attacker ↓ / Defender → | Scorch | Brine | Static | Sludge | Grit | Gale |
|---|---|---|---|---|---|---|
| **Scorch** | 0 | −15% | 0 | 0 | 0 | **+15%** |
| **Brine** | **+15%** | 0 | −15% | 0 | 0 | 0 |
| **Static** | 0 | **+15%** | 0 | 0 | −15% | 0 |
| **Sludge** | −15% | 0 | 0 | 0 | **+15%** | 0 |
| **Grit** | 0 | 0 | **+15%** | −15% | 0 | 0 |
| **Gale** | −15% | 0 | 0 | **+15%** | 0 | 0 |

A fighter's "element" for defense is its primary element. Neutral (non-elemental) hits are unaffected. Roster consequence: each fighter has exactly one favored and one unfavored matchup; everything else is neutral.

| Fighter (element) | Favored vs | Unfavored vs |
|---|---|---|
| Stoke (Scorch) | Gusto | Dredge |
| Dredge (Brine) | Stoke | Jitters |
| Jitters (Static) | Dredge | Dozer |
| Dozer (Grit) | Jitters | Slurry |
| Slurry (Sludge) | Dozer | Gusto |
| Gusto (Gale) | Slurry | Stoke |

## 5. Zones

Zones are persistent ground patches (`zone` effect). Default shape: circle; some abilities make lines.

| Zone | Default size / life | Per-second effect on fighters inside | Extra |
|---|---|---|---|
| **Scorch patch** | r 1.5 m / 3 s | 3 dmg + 15 Scorch build-up | Ignites Sludge puddles it touches (Flare-Up), evaporates Brine puddles (Steam) |
| **Brine puddle** | r 1.5 m / 5 s | 15 Brine build-up | Conducts Static (Live Puddle); cleanses Sizzle on entry (Steam Burst at the fighter) |
| **Static field** | r 1.5 m / 2 s | 20 Static build-up + one micro-flinch on entry | Rare as a free-standing zone; mostly produced by reactions and hazards |
| **Sludge puddle** | r 1.5 m / 6 s | 1.5 dmg + 15 Sludge build-up | Burns (Scorch), fizzes (Static), hardens (Grit), smears (Gale), thins (Brine) |
| **Grit rubble** | r 1.5 m / 4 s | 15 Grit build-up, move −10% | Blocks nothing by itself; Crust turns it into a solid prop |
| **Gale vortex** | r 1.2 m / 2 s | Outward push 2 m/s + 15 Gale build-up | Pushes projectiles off course by 20° |
| **Mud** (reaction only) | r 2.5 m / 4 s | Move −30%, dodge −50%, no leap/hover/blink | — |

Zone rules: a fighter standing in a zone of its own primary element takes no build-up from it (Slurry wades through its own sludge) but still takes zone damage unless the ability says otherwise. Two zones of the same element overlap without stacking ticks. Zones never apply build-up to a downed fighter (no wake-up status locks).

## 6. Arena interactions

| Arena (see ARENAS.md) | Element on tap | How it plays |
|---|---|---|
| The Gullet | none by default | Pure spacing; editor can add any hazard prop |
| Drydock | Brine | The tidal gutter floods on a timer: Soaked for anyone standing in it; Static fighters go fishing for Short-Outs; Scorch fighters hate it |
| The Crusher | Static, Grit | Electrified plates and a crane magnet; rubber mats are the safe spots; Caked fighters resist the magnet's pull by 50% |
| The Rooftop | Gale | Timed wind gusts push everyone 1.5 m; Winded fighters fly 3 m; ring-outs instead of walls |

Hazard props (barrels, vents, drums) in the editor produce the matching zone when triggered.

## 7. Edge cases

| Case | Rule |
|---|---|
| Stacking the same status | Never stacks magnitude; refresh-to-full only. |
| Status on downed fighters | Build-up pauses while downed and during wake-up invulnerability. Active statuses keep ticking damage but Sizzle/Gunked DoT cannot reduce a downed fighter below 1 HP. |
| Immunity windows | 2 s post-status immunity per status. Boss primary-element immunity. Fighter self-element immunity from own attacks. |
| Reaction spam | 1.5 s per-target reaction cooldown. Reactions never chain into other reactions within that window (Flare-Up's Scorch build-up can start Sizzle but cannot immediately Backdraft). |
| Friendly fire (co-op, teams) | Direct elemental hits from allies: 0 damage, 0 build-up. **Reaction areas and zones** affect allies at 25% damage, 100% displacement, 50% build-up (so Flare-Up still tosses your partner; Dilute still cleanses them). Allies are never hard-stunned by ally reactions (Short-Out stun becomes a 0.2 s flinch). |
| Self-hits | Own zones: no build-up, damage applies unless kit says otherwise. Own reaction areas: full effect (Stoke in his own Flare-Up gets Sizzle build-up). |
| Multi-element hits | A hit carries at most one element. Techniques that "add" an element replace the base element of that move. |
| Element tag on a build | Supplements can grant a secondary element to a specific move slot (e.g. Heavy becomes Static). That move then uses the matrix for its own element, not the fighter's primary. |
| Projectile reactions | A projectile hitting a zone of a reacting element triggers the zone reaction at the impact point and the projectile is consumed. |
| Reflected projectiles | Keep their element; the reflector becomes the credited attacker. |
| Timers vs pause | All status/zone timers are simulation-time, frozen on pause. |
| 8-fighter chaos cap | Max 24 live zones per arena (oldest removed); max 6 reactions resolved per simulation tick (rest queue to the next tick). |
| Spectator/HUD | Every status shows as icon + short label in the fighter's nameplate; reactions print their name at impact; zones draw a dashed outline in their element's color plus a pattern (hatching per element) for color-blind readability. |

## 8. Balance rationale

- **Mild matrix (±15%)**: a favored matchup is worth roughly one light hit per 7 landed. Enough to notice, never enough to decide by selection.
- **Build-up, not instant status**: five lights or three heavies to earn a status means a status is a *reward for pressure*, and defense (guard halves it, parry zeroes it) is a real counter.
- **Every status has one offensive and one defensive answer**: Sizzle is washed by Brine/Steam; Soaked is punished by Static but cleans Sizzle; Jolted punishes charge-heavy kits; Gunked is cleansed by Dilute and burst by Catalyze; Caked is a poise setup; Winded is a launcher setup.
- **Four "no reaction" pairs** keep the table learnable (11 reactions) and leave quiet matchups (Scorch vs Grit, Brine vs Gale) that are decided by spacing rather than chemistry.
- **Self-risk reactions** (Flare-Up, Spray) give zoners something to fear in close and give co-op partners something to coordinate.
- **Zones are short** (2–6 s) so arenas never become permanently unplayable in 8-fighter matches; the 24-zone cap is a hard guarantee.
