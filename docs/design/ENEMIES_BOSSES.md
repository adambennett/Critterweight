# CRITTERWEIGHT — Enemies and Bosses

NPC-only combatants: two cheap minion types for campaign encounters and the Chum Rush horde mode, and three bosses, one per campaign act. All attacks are composed from the engine's effect vocabulary. Numbers are solo-player baselines; co-op scaling is in CAMPAIGN.md §10.

## 1. Minions

Minions are deliberately simple: one body plan each, 2–3 attacks, one big tell. They exist to be thrown at other minions, exploded near each other, and mopped up in style. Both use the same ragdoll pipeline as fighters, at reduced segment counts.

### 1.1 SCRAPLING — `npc_scrapling`

| Field | Value |
|---|---|
| Species | Junk gremlin: a knee-high biped made of cannery scraps, wearing a **trash-can lid** as a shield and swinging a length of pipe. |
| Plan | biped, 8 segments (head, torso, 2 arms, 2 legs, lid, pipe) |
| Size / mass | 1.0 m / 40 kg |
| HP / Poise / Speed | 30 / 20 / 3.2 m/s |
| Element | Neutral by default; **loadouts** add an element to the pipe (Scorch "Hot Pipe", Grit "Gravel Lid", Sludge "Leaky Pipe") |
| Palette | Dented tin `#A7A9A0`, rust `#8C3B2B`, one glowing eye `#FFD23F` behind a bottle-cap goggle |
| Silhouette | Small round lid in front, pipe over one shoulder. Reads as a "walking dustbin". |

**Attacks**

| Attack | Vocabulary | Telegraph | S/A/R | Dmg | KB | Poise | Notes |
|---|---|---|---|---|---|---|---|
| **Pipe Swing** | melee, pipe tip, overhead arc 1.0 m | pipe raised straight up 0.3 s | 0.30/0.10/0.50 | 5 | 0.8 | 10 | Loadout element build-up 15 |
| **Lid Bash** | melee, lid as weapon, 0.8 m forward shove | lid pulled back to the hip | 0.25/0.10/0.40 | 3 | 1.5 (push) | 8 | Used to push a target toward other Scraplings |
| **Lid Up** | shield (front only) | crouches behind the lid | 0.1/1.5/0.2 | — | — | — | Front arc 120° absorbs 90%; back and sides are open; grabs ignore it |
| **Pelter loadout: Bolt Toss** | projectile, lobbed, 5 m, 8 m/s | winds up over the head | 0.4/—/0.6 | 3 | 0.3 | 5 | 2 s cooldown; Pelters keep 4 m distance |

**Behavior**: packs of 3–6. They spread into a loose semicircle and take turns stepping in (only 2 may attack at once; the rest hold Lid Up or circle to the target's back). Pelters stay behind the pack. On an ally's death nearby, the pack flinches for 0.5 s (readable, forgiving).

**Counters**: get behind the lid; throw one into the others (a thrown Scrapling is a 6 dmg projectile that knocks down other Scraplings); any area/zone effect; Dozer's Bulldoze through the pack.

**Cosmetic gore**: the lid flies off on death and rolls; the gremlin collapses into a small pile of parts (no limb logic).

### 1.2 BLISTER — `npc_blister`

| Field | Value |
|---|---|
| Species | A bulging, bouncing sac of Glandco runoff that got ideas. |
| Plan | hopper, 3 segments (core, two flappy nubs) |
| Size / mass | 0.7 m / 25 kg (inflates to 1.1 m before popping) |
| HP / Poise / Speed | 20 / 10 / 2.8 m/s (hops) |
| Element | **Sludge** by default; variants **Ember Blister** (Scorch), **Fuse Blister** (Static) |
| Palette | Sickly green `#8BD426` sac with darker veins `#4F7F1A`; Ember variant orange `#FF6B2B`, Fuse variant yellow `#F7E04A`. Variant is also shown by a **shape**: Ember has a flame-shaped nub, Fuse has a zigzag seam. |
| Silhouette | A lumpy egg on no legs. |

**Attacks**

| Attack | Vocabulary | Telegraph | Timing | Dmg | KB | Build-up | Notes |
|---|---|---|---|---|---|---|---|
| **Inflate & Pop** | area circle r 2.0 m | grows 1.5× over 1.2 s with a rising whistle, veins glow | 1.2 s then pop | 12 | 2.5 (radial) | 40 of its element | Leaves a 1.2 m zone of its element for 3 s |
| **Death Pop** | area circle r 1.0 m | none (it died) | instant | 6 | 1.5 | 20 | Half-size pop when killed before inflating |
| **Hop** | leap 1.5 m | crouch | 0.3 s | 2 (contact) | 0.5 | 5 | Movement that also bumps |

**Behavior**: hops straight at the nearest enemy; when within 1.5 m it starts inflating and stops moving. It can be **grabbed and thrown** as a live bomb (lands → full Pop at the landing point, credited to the thrower). Blisters never inflate within 1.5 m of another inflating Blister (no chain-nukes, but a thrown Blister's pop *does* set off nearby Blisters' Death Pops).

**Counters**: kill it at range (Death Pop is half damage), dodge away at the whistle, throw it at Scraplings, or Steam/Dilute its zone.

**Cosmetic gore**: pops into confetti-like goo flakes; the two nubs flop to the floor.

### 1.3 Minion loadouts used by encounters

| Loadout id | Base | Change |
|---|---|---|
| `scrapling_basic` | Scrapling | — |
| `scrapling_pelter` | Scrapling | Bolt Toss, keeps range |
| `scrapling_hot_pipe` | Scrapling | Pipe hits apply Scorch 15 |
| `scrapling_gravel_lid` | Scrapling | Lid Bash applies Grit 15; lid absorbs 100% |
| `scrapling_leaky_pipe` | Scrapling | Pipe hits apply Sludge 15; leaves a 0.6 m puddle on death |
| `blister_sludge` | Blister | — |
| `blister_ember` | Blister | Scorch pop; leaves a Scorch patch |
| `blister_fuse` | Blister | Static pop; 0.4 s stun in radius |

---

## 2. Bosses

Boss rules (all three):
- **Two phases**, phase 2 at **50% HP** (65% on Dose 8+). Phase transition: 2.0 s invulnerable cinematic beat, arena change, announcer line.
- **Dazed**: when a boss's poise hits 0 it is Dazed for 3.0 s (staggered, muscles slack): grabs connect, throws deal ×2, all hits +20%. Poise then refills to full. This is the intended "break then punish" rhythm.
- Immune to their own primary element's status. Everything else applies (statuses, reactions, trips on Soaked, etc.).
- Boss HP, poise and damage scale with difficulty preset (CAMPAIGN.md §8) and party size (§10).
- Every attack has a telegraph of ≥ 0.5 s, shown as animation + a ground decal (cone/circle/line in the attack's element color **and** a hatched pattern).
- Bosses reuse player body plans on purpose (quadruped, serpent, crab) so gait code is shared; they are scaled up and get extra segments where noted.

### 2.1 Act 1 — BILGE, the Cannery Hound — `boss_bilge`

| Field | Value |
|---|---|
| Concept | The cannery's old guard dog: bloated, rust-stained, sludge-soaked, chained to a bollard by the neck. Sweet eyes, terrible breath. He just wants to play. Playing is biting. |
| Plan | quadruped, 14 segments (adds a second neck segment and a chain segment) |
| Size / mass | 2.0 m at the shoulder, 3.6 m long / 320 kg |
| Element | **Sludge** primary (immune to Gunked), Brine secondary |
| HP / Poise / Speed | 420 / 200 / 3.4 m/s (phase 2: 3.8) |
| Arena | **Drydock** (ARENAS.md §2.2) |
| Palette | Wet brown-grey hide `#5A4E45`, sludge-green drool `#8BD426`, rusted chain `#8C3B2B`, one red collar light `#E03A2B` |
| Silhouette | A barrel-chested dog with a neck longer than it should be and a chain. |

**Phase 1 — "Chained" (100% → 50%)**
Bilge is on a **7 m chain** anchored to the bollard at the arena's east end. He cannot reach the far west 3 m (the "safe" strip), but he spits there. The chain is a physical prop: it drags, it can trip fighters who cross it while it is taut (0.3 s stumble, no damage).

| Attack | Vocabulary | Telegraph | S/A/R | Dmg | KB | Poise dmg | Build-up | Counter |
|---|---|---|---|---|---|---|---|---|
| **Chomp** | melee, jaws, lunge 1.5 m at chest height | head lifts, growl, mouth opens 0.5 s | 0.50/0.12/0.90 | 14 | 1.5 | 30 | Sludge 30 | Dodge sideways; punish the 0.9 s recovery |
| **Shake-Off** | spin, whole body, 2.0 m radius, 1 rotation | shoulders drop, ears flatten | 0.60/0.40/0.60 | 10 | 2.5 (radial) | 20 | Sludge 20 | Back off 2.5 m or guard (it is 1 hit) |
| **Bilge Spit** | projectile ×3 lobbed, fan ±20°, 8 m | gulps, cheeks swell 0.7 s | 0.70/—/0.50 | 8 each | 1.0 | 10 | Sludge 35 | Each leaves a 1.2 m puddle 5 s. Dodge between the arcs; Steam Vent destroys them |
| **Lunge-Chomp** | charge 5 m then jaws | haunches lower, chain tightens 0.8 s | 0.80/0.6/1.0 | 18 | 3.0 | 40 | Sludge 40 | On hit: **grab** then **Shake** throw 4 m (knockdown). Sidestep late; he overshoots and hits the chain's end (0.8 s stumble) |
| **Bollard Yank** (reposition) | pull on self | — | — | — | — | — | — | He drags himself along the chain to re-center; not an attack |

Phase 1 arena interplay: the Drydock's **tidal gutter** floods every 20 s; his puddles that land in the gutter **Dilute** (bigger, weaker). Static fighters can Short-Out him when he's standing in the flooded gutter (he is not immune to Soaked).

**Phase 2 — "Off the Chain" (< 50%)**
Transition: he rips the bollard out of the concrete, the chain whips free, and he pulls the **drain plug** with his teeth: the whole floor floods ankle-deep for the rest of the fight.

- Floor = **Brine zone** (15 build-up/s to everyone, Bilge included). Everyone is Soaked most of the time: slower, heavier, and Static hits Short-Out constantly (player risk and reward: bring Jitters and he eats Short-Outs, but a Fuse Blister pop will stun the whole party).
- The loose **chain** is a swinging hazard: it sweeps a 4 m arc around the torn bollard every 4 s (trip + 6 dmg).
- Mooring blocks (3 raised props, 1.2 m × 1.2 m × 0.4 m) are dry: standing on one avoids the Brine zone and the wave.

| New attack | Vocabulary | Telegraph | S/A/R | Dmg | KB | Poise dmg | Build-up | Counter |
|---|---|---|---|---|---|---|---|---|
| **Belly Flop** | leap to the target point (≤ 4 m), landing area r 2.5 m + ground wave ring r 4 m | crouches, tongue out, a big circle decal 1.0 s | 1.0/0.2/1.2 | 16 (area), 6 (wave) | 3.0 | 40 | Brine 40 | Wave trips Soaked fighters. Stand on a mooring block or dodge *toward* him through the gap under his chin. His 1.2 s recovery is the big punish window. |
| **Rabid Rush** | charge ×3, 4 m each, 90° turns | barks three times | 0.8/1.8/1.0 | 12 per hit | 3.0 | 30 | Sludge 25 | Each leg is straight; sidestep each; the third ends in a stumble |
| **Bilge Spit** (upgraded) | ×5 fan | same | same | 8 | 1.0 | 10 | Sludge 35 | Puddles on water Dilute immediately (bigger, weaker) |

**Dazed window**: break 200 poise (his Chomp and Belly Flop recoveries are when heavies land). While Dazed he collapses on his side; throws on him are "shoving him over" (×2 damage).

**Defeat**: he sits down, panting, and the announcer declares him "a very good boy with a very bad record."

### 2.2 Act 2 — CONDUIT, the Live Wire — `boss_conduit`

| Field | Value |
|---|---|
| Concept | A 7-segment electric serpent that nests in the scrapyard crusher's power cabinet. It communicates in arcs. It is not angry; it is current. |
| Plan | serpent, 9 segments (head + 7 body + a tail "plug" segment) |
| Size / mass | reared 3.2 m, 7.5 m long / 260 kg |
| Element | **Static** primary (immune to Jolted), Grit secondary |
| HP / Poise / Speed | 520 / 160 / 3.2 m/s (4.0 across steel plates) |
| Arena | **The Crusher** (ARENAS.md §2.3) |
| Palette | Insulation-black `#1E1E24` with yellow warning stripes `#F7E04A`, copper head crest `#B87333`, segment seams glow cyan-white `#CFF4FF` |
| Silhouette | A tall S with a hazard-striped body and a plug on the tail. |

**Phase 1 — "Loose Wire" (100% → 50%)**
It slithers between the scrap piles (destructible walls) and strikes from behind cover.

| Attack | Vocabulary | Telegraph | S/A/R | Dmg | KB | Poise dmg | Build-up | Counter |
|---|---|---|---|---|---|---|---|---|
| **Whip Tail** | melee, tail tip, 180° sweep at knee height, radius 2.2 m | tail rises and quivers 0.6 s, arc decal | 0.60/0.15/0.70 | 12 | 2.0 | 25 | Static 25 | Trips Soaked. Hop over (Jitters, Gusto) or dodge out of the arc |
| **Jaw Clamp** | melee jaws 1.6 m lunge, then 0.5 s hold, then discharge | head rears back, mouth arcs 0.7 s | 0.70/0.12/0.80 | 15 + hold | 2.5 (discharge) | 30 | Static 50 | Mashing out of the hold works (6 presses); the discharge is an area r 1.5 m that hits bystanders too |
| **Arc Spit** | projectile ×2 slow-homing, 6 m/s, 120°/s, 8 m | mouth glows, two orbs form 0.8 s | 0.80/—/0.60 | 7 each | 0.5 | 10 | Static 40 | Reflectable (Hard Hat Dozer, Molting Dredge); the orbs die on scrap piles |
| **Coil Slam** | rear & crash, head + 2 segments, 2.0 m ahead, area r 2 m | rears to full height 0.9 s, circle decal | 0.90/0.15/1.10 | 18 | 2.5 | 45 | Static 45 | Its longest recovery: the intended Heavy window |
| **Scrap Shuffle** | leap/blink behind a scrap pile (≤ 6 m) | hisses, dives | 0.4/0.5/0.3 | — | — | — | — | It repositions after taking 60 damage in 3 s |

Phase 1 arena interplay: hitting it while it touches a **scrap pile** makes the pile shed a Grit rubble zone (its own secondary element — it enjoys Caked targets: Caked halves the magnet's pull in phase 2, so the boss plants rubble to make you Caked, then you fight the magnet less but dodge worse. Readable tradeoff).

**Phase 2 — "Plugged In" (< 50%)**
Transition: it bites the crusher's main cable; the warning stripes glow, the crane magnet wakes up.

- The floor's **3×3 steel plates** electrify in telegraphed patterns: a plate lights (yellow outline + hatched decal) for 1.0 s, then becomes a **Static field** for 1.5 s (8 dmg + 40 build-up on entry/tick). Patterns: cross, checkerboard, ring, then a random plate every 3 s. Three **rubber mats** (props, 1.5 m squares) are insulated and never electrify.
- The **crane magnet** activates every 12 s: 1.5 s telegraph (siren + spotlight on the center plate), then **pull** everything within 4 m of the center toward it for 1.5 s (2.5 m/s). Caked fighters resist 50%. It always precedes a Coil Slam on the center.
- **Short Circuit**: if any fighter is Soaked (a Brine barrel prop is in the arena; Dredge's puddles count), any Conduit hit on them Short-Outs. The fight rewards *not* bringing water.

| New attack | Vocabulary | Telegraph | S/A/R | Dmg | KB | Poise dmg | Build-up | Counter |
|---|---|---|---|---|---|---|---|---|
| **Ground Loop** | ground wave line ×2 (from head, 90° apart), 8 m long × 1.5 m wide | head touches the floor, two line decals 0.8 s | 0.80/0.3/1.0 | 10 | 1.5 | 20 | Static 35 | Stand between the lines or on a mat |
| **Overvolt Spit** | projectile ×4 slow-homing | same as Arc Spit, longer glow | 1.0/—/0.6 | 7 | 0.5 | 10 | Static 40 | Dodge late; they turn slowly |
| **Discharge** | area circle r 3.5 m centered on itself | whole body glows white 1.0 s, circle decal | 1.0/0.1/1.4 | 20 | 3.0 | 50 | Static 60 | Its biggest punish window (1.4 s). Dodge out of the ring or hover over it. |

**Dazed window**: 160 poise. Rubber Core Jitters and Rockbreaker Dozer break it fastest; when Dazed its segments go slack and the plates stop electrifying for the 3 s.

**Defeat**: it unplugs itself from the cable and curls up in the power cabinet, blinking politely.

### 2.3 Act 3 — COMMISSIONER SNAPPINGTON, Her Honor — `boss_snappington`

| Field | Value |
|---|---|
| Concept | The ancient snapping turtle who runs the Circuit, never seen leaving her desk, undefeated since 1973 because she writes the rulebook. For the title fight she brings the desk. Phase 2 she drinks an entire crate of Glandco JUICE and forgets which rules apply to her. |
| Plan | crab (low shell body, 4 walking legs, 2 clawed arms, beaked head on a long neck), 16 segments |
| Size / mass | 2.4 m shell, 1.6 m tall (neck extended 2.6 m) / 480 kg |
| Element | **Grit** primary (immune to Caked) in phase 1; **cycling** in phase 2 |
| HP / Poise / Speed | 650 / 240 / 2.4 m/s (phase 2: 3.0) |
| Arena | **The Gullet, Title Night** (ARENAS.md §2.1) |
| Palette | Shell moss-green `#4F6B3A` with gold trim `#C9A227`, skin olive `#8A8C5A`, reading glasses, a tiny gavel on a chain, phase-2 cracks glow the current element's color |
| Silhouette | A dome with a gavel. Phase 2: a cracked dome with a lightning-shaped seam. |

**Phase 1 — "By the Book" (100% → 50%)**
Slow and deliberate. Every attack is big and clearly telegraphed; the fight is about discipline.

| Attack | Vocabulary | Telegraph | S/A/R | Dmg | KB | Poise dmg | Build-up | Counter |
|---|---|---|---|---|---|---|---|---|
| **Gavel Claw** | melee, right claw overhead slam 1.4 m ahead + ground wave line 3 m | claw rises 0.8 s with a gavel "clack", line decal | 0.80/0.12/1.0 | 16 | 2.0 | 40 | Grit 40 | Sidestep the line; punish the 1.0 s recovery |
| **Snap** | melee jaws, neck extends 1.6 m | neck retracts into the shell 0.6 s then shoots out | 0.60/0.10/0.80 | 14 | 1.0 | 30 | Grit 25 | On hit: **grab** then **"Disqualified!"** throw 4 m into the cage wall (wall splat 6 dmg). Dodge sideways — it is a straight line |
| **Shell Spin** | spin, whole body, radius 2.5 m, 2 rotations | tucks limbs 0.7 s, circle decal | 0.70/0.60/0.80 | 8 ×2 | 2.5 (radial) | 20 | Grit 20 | Back off or hop over |
| **Withdraw** | shield + reflect + counter_stance, 3 s | pulls into the shell with a "recess" gong | 0.3/3.0/0.5 | 10 (retaliation pulse r 2 m) | 2.0 | 25 | Grit 20 | Reflects projectiles; melee on the shell triggers the pulse. **Grabs work on the shell**: a throw rolls her 2 m and ends Withdraw early |
| **Objection** | push cone 3 m | raises a claw, points | 0.5/0.1/0.5 | 4 | 3.0 | 10 | — | Used to shove fighters off her when 2+ are adjacent (co-op crowd control) |

Phase 1 arena interplay: her slams near the cage walls knock **sponsor boards** loose (place_prop: 2 m × 1.2 m boards fall inward and become low walls for 15 s, 30 HP). Confetti cannons fire on every knockdown (cosmetic).

**Phase 2 — "Off the Books" (< 50%)**
Transition: she cracks open a crate of Glandco JUICE with her beak, drinks the crate, and the shell cracks along glowing seams. The center of the canvas opens into the **Juice Vat** (r 2.5 m zone, permanent): standing in it builds +15 Hype/s but costs 2 HP/s for anyone, her included. Big risk/reward for players who want a second JUICE.

- **Element cycle**: every 8 s her active element changes in a fixed order — **Scorch → Static → Sludge → Brine → Gale → Grit** — shown by a big icon over her shell and the seam color. All her attacks carry the active element (build-up as listed, element swapped). She is immune only to the *active* element's status; a status she already carries **persists** when she cycles. Her own attacks never react on herself. The intended play is to set up reactions across phases: apply a status while she is not immune to it, then hit her with the reacting element. Example: Gunk her during her Scorch phase (she is only Gunked-immune during Sludge), then Stoke's Finisher Flare-Ups her for 10 damage plus the burn; or Soak her during Grit and let Jitters Short-Out her during Static.
- **Juice Spray** and **Title Slam** are added. Sponsor boards now fall more often. The crowd's noise level affects nothing but the announcer's blood pressure.

| New attack | Vocabulary | Telegraph | S/A/R | Dmg | KB | Poise dmg | Build-up | Counter |
|---|---|---|---|---|---|---|---|---|
| **Juice Spray** | projectile ×5 straight fan ±30°, 10 m/s, 8 m | she shakes a can, foam decal cone 0.8 s | 0.80/—/0.7 | 6 each | 1.0 | 8 | active element 35 | Stand between the streams or guard (they are weak individually) |
| **Title Slam** | leap to target point (≤ 5 m), landing area r 3 m | she rises on her hind legs, a shadow circle grows for 1.2 s | 1.2/0.2/1.4 | 22 | 3.5 | 60 | active element 50 | Dodge at 1.0 s; her 1.4 s recovery is the longest window in the game. Knockdown on hit. |
| **Gavel Claw / Snap / Shell Spin** | as phase 1 | same | −15% startup | same | same | same | active element | Faster, same shapes |
| **Withdraw** (phase 2) | as phase 1 + the Juice Vat erupts: ground wave ring r 4 m from the vat on exit | same | same | 8 (ring) | 2.0 | 20 | active element 30 | Hop the ring or stand on a fallen sponsor board |

**Dazed window**: 240 poise. Caked does not apply to her in Grit phase but does in every other phase: Dozer's Rockslide line in phase 2 is a real plan. While Dazed she tips onto her shell (the classic), legs waving: throws on her ×2, and the announcer loses his mind.

**Defeat**: she rights herself, adjusts her glasses, signs the belt over with the gavel, and says the Commission will "review the footage." The crowd throws cans.

### 2.4 Boss summary

| Boss | Act | Plan | Element | HP / Poise | Arena | Phase-2 twist | Key counter |
|---|---|---|---|---|---|---|---|
| Bilge | 1 | quadruped | Sludge / Brine | 420 / 200 | Drydock | Floods the floor (Soaked everyone), loose chain hazard | Mooring blocks, punish Belly Flop recovery, Static fishing |
| Conduit | 2 | serpent | Static / Grit | 520 / 160 | The Crusher | Electrified plate patterns, crane magnet, Short Circuit | Rubber mats, Caked vs magnet, punish Discharge |
| Snappington | 3 | crab | Grit → cycling | 650 / 240 | The Gullet (Title Night) | Element cycle every 8 s, Juice Vat Hype/HP tradeoff, Title Slam | Reaction setups across phases, Title Slam recovery, grabs on the shell |

### 2.5 How bosses appear in other modes
- **Chum Rush** (MODES.md): a boss appears as the wave 10 / 20 / 30 "headliner" at 60% HP with phase 2 disabled on waves 10 and 20.
- **Practice**: any boss can be loaded as a training dummy with phase selection and attack-only toggles.
- **Custom rules**: `bots.allow_bosses=true` lets a boss fill a bot slot in FFA/teams (HP scaled to 2× the highest fighter HP, no phases, no arena changes). Off in ranked/standard.
