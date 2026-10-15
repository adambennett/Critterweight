# CRITTERWEIGHT — Roster

Six fighters, six body plans, six elements. Every number below is a design default for the engine's PD-controller/effector-path system; tune in-engine, keep the ratios.

## 0. Shared combat defaults (reference frame for all kits)

| System | Default |
|---|---|
| Health | 80–140 per fighter; KO at 0 |
| Stamina | 90–110 max; regen 12/s idle, 6/s guarding, 0 during attacks; **low stamina (< 20)**: startup +30%, next Heavy that is guarded breaks the guard |
| Poise | 40–90 max; regen 15/s after 1.5 s unhit; at 0 → knockdown (limp 1.2 s, get-up 0.8 s, wake-up invulnerability 0.5 s) |
| Hype | 0–100. Gains: land Light +2, land Heavy +4, land ability +3, take a hit +1 (+2 if Heavy), parry +10, knockdown scored +6, taunt +8 (D-pad Up, 1.5 s animation, no armor). JUICE costs 100. |
| Light string | L1 → L2 → L3. Cancel window = last 0.10 s of active + first 0.15 s of recovery of each hit. Heavy pressed in the window = **Finisher**. |
| Heavy | Tap = Heavy. Hold ≥ 0.35 s = Charged Heavy (max hold 1.2 s; release or auto-fire). Charged Heavies carry **armor** (ignore stagger from Lights) during startup unless noted. |
| Guard (LT hold) | Absorbs 75% damage, 50% poise damage, 50% build-up; guarding a hit costs 50% of that attack's stamina cost. Guard startup 0.08 s. Grabs beat guard. |
| Parry | Guard pressed ≤ 0.12 s before impact. Negates damage/build-up, attacker staggers 0.6 s, parrier +10 Hype and 0.4 s of free cancel. Cannot parry grabs, projectiles (unless kit says), or JUICE pulses. |
| Dodge (A + direction) | 0.3 s dash, i-frames 0.05–0.25 s, distance per fighter, costs 12 stamina. Light during the dash = **Dash Attack**. |
| Grab (B) | Startup 0.25 s, reach 1.0 m unless noted, hold max 2.0 s. Pummel = Light (per-fighter). Throw = direction + Grab. Mash escape: 6 presses (or 1.0 s). Strikes beat grab startup; grabs beat guard. Bosses: grabbable only while **Dazed** (poise broken). |
| Abilities (LB/RB) | Cooldown and/or stamina cost per move. Cooldowns tick during everything but JUICE activation. |
| JUICE (RT) | Needs 100 Hype. Activation is 0.5 s with full armor + 0.3 s invulnerability, then the effect. Hype drains to 0. |
| Knockback | Meters of root displacement on a standing target of 100 kg; scaled by mass ratio (lighter flies farther, cap ×1.6). |
| Stun | Seconds the target's muscles go slack-ish (reduced gains, no inputs). Combo scaling and stun budgets are engine-side. |
| Damage scale | Lights 4–8, Heavies 10–18, abilities 5–16, JUICE pulses 8–14 |
| Reach cap | No normal melee weapon point travels beyond 1.6 m from the fighter's root |
| Rounds | Standard 1v1: best of 3 rounds × 99 s. Campaign: 1 round, 150 s, then sudden death (first hit wins). FFA: last standing or 180 s. |

### Weight class table

| Fighter | Plan | Element | Height | Mass | Class | HP | Walk m/s | Stamina | Poise | Dash m |
|---|---|---|---|---|---|---|---|---|---|---|
| STOKE | biped | Scorch | 1.5 m | 85 kg | Scrapper | 110 | 3.4 | 100 | 60 | 2.8 |
| DREDGE | crab | Brine | 1.1 m (2.0 m wide) | 160 kg | Absolute Unit | 140 | 2.6 fwd / 3.2 side | 90 | 90 | 2.2 fwd / 3.0 side |
| GUSTO | avian | Gale | 1.9 m | 55 kg | Pipsqueak | 85 | 4.3 | 110 | 40 | 3.6 |
| DOZER | quadruped | Grit | 1.2 m shoulder, 2.0 m long | 140 kg | Lunker | 130 | 3.0 | 95 | 85 | 3.2 |
| SLURRY | serpent | Sludge | 2.0 m reared, 3.2 m long | 95 kg | Scrapper | 100 | 3.0 | 105 | 55 | 3.0 |
| JITTERS | hopper | Static | 0.9 m | 45 kg | Pipsqueak | 80 | 3.8 | 100 | 45 | 3.4 |

---

## 1. STOKE — the Boiler Newt

**Id** `f_stoke` · **Plan** biped (head, chest, pelvis, 2×upper arm, 2×forearm/fist, 2×thigh, 2×shin/foot, short tail = 12 segments) · **Element** Scorch

### Concept
A stocky bipedal newt with a cast-iron boiler for a belly. The furnace door on his stomach glows; a stovepipe crest on his head puffs smoke when he's hyped. Hands wrapped in off-white bandage. He's a pressure boxer: impatient, forward, hot-tempered. Idle: bounces on his toes, blows steam from his nostrils, clanks a fist against his belly door.

| Visual | Spec |
|---|---|
| Silhouette | Wide shoulders, short legs, round boiler belly, tall thin crest. Reads as a "barrel with fists". |
| Palette | Body burnt orange `#D9532B`; belly plate iron `#3A3A42` with ember glow `#FF7A1A`; wraps `#EDE6D6`; eyes yellow `#FFD23F`; crest black iron `#2B2B30` |
| Materials | Glossy amphibian skin (soft rim), matte cast iron with emissive seams, cloth wraps |
| Distinctive | The furnace door opens for Steam Vent and JUICE. Crest smoke density = Hype meter (readable at a glance). |
| Detachable piece (cosmetic gore) | A **tooth** pings off on the KO hit and bounces off the cage. |

### Playstyle
Pressure boxer. **Beginner hook:** mash Light for jab–cross–hook that just works; hold Heavy for a big overhand; everything you touch heats up until it Sizzles.

| Strengths | Weaknesses | Counterplay against him |
|---|---|---|
| Fast lights, best Finisher in the roster, Sizzle drains stamina so he wins long exchanges, armor on heavies | Short reach (1.0–1.1 m), average poise, no ranged tool beyond a 2 m cone, Stoke the Fire costs HP | Keep him at 1.3 m+ (Slurry, Gusto); Brine hits Steam Burst his Sizzle away; grab him out of Stoke the Fire; dodge the obvious overhand and punish its 0.4 s recovery |

### Moveset

| Move | Weapon | Path (spatial) | S/A/R (s) | Dmg | KB m | Stun s | Poise | Stam | CD | Build-up | Properties |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **L1 Jab** | left fist | chamber at chin → 1.0 m forward at head height, straight line | 0.12/0.08/0.18 | 4 | 0.3 | 0.25 | 5 | 4 | — | Scorch 10 | — |
| **L2 Cross** | right fist | right shoulder → 1.1 m forward at head height; hips rotate 40° | 0.14/0.08/0.22 | 5 | 0.5 | 0.30 | 8 | 5 | — | Scorch 12 | — |
| **L3 Lead Hook** | left fist | from 60° outside-left, arcs horizontally into the target's head side, 1.0 m | 0.18/0.10/0.30 | 7 | 1.0 (sideways) | 0.45 | 14 | 7 | — | Scorch 18 | Turns the target 30° (side-shove) |
| **Heavy: Overhand Boiler** | right fist | loops up over the shoulder and comes down to head height 1.0 m out | 0.28/0.10/0.40 | 13 | 1.5 | 0.60 | 25 | 12 | — | Scorch 30 | Armor during active |
| **Charged Heavy: Furnace Haymaker** | right fist | full torso wind-up (back foot pivot) then a wide right hook, 1.1 m, chest-to-head height | 0.50/0.12/0.50 | 18 | 3.0 | 0.80 | 45 | 16 | — | Scorch 45 | Guard-crush (2× poise vs guard); knock-up 1.2 m if the target is Sizzling |
| **Finisher: Gut Furnace** | right fist | 0.4 m step in, fist drives 1.0 m forward at belly height; furnace door flashes | 0.16/0.10/0.45 | 10 | 2.0 | 0.60 | 20 | 10 | — | Scorch 25 | On a Sizzling target: +4 dmg and Sizzle refreshed |
| **Dash Attack: Stoke Step** | left fist | slide 1.2 m, fist rises from waist to head height 0.9 m out (lead uppercut) | 0.14/0.10/0.35 | 8 | 1.2 | 0.50 | 15 | 8 (+dodge) | — | Scorch 15 | Launcher (knock-up 0.8 m) |
| **Grab: Clinch** | both hands | collar tie at 1.0 m | 0.25 | — | — | — | — | 6 | — | — | Pummel = knee (3 dmg, Scorch 8, 0.35 s each). Throws: Fwd **Belly Toss** hip-throw 2 m, 9 dmg, knockdown · Back **Dump** 2 m · Side **Shove-off** 2.5 m, 4 dmg, no knockdown (spacing tool) |
| **Ability 1: Steam Vent** (LB) | area cone | furnace door opens: cone 2 m long, 60° wide, from the belly | 0.20/0.15/0.40 | 6 | 2.5 (push) | 0.30 | 10 | 15 | 7 s | Scorch 35 | Destroys enemy projectiles entering the cone |
| **Ability 2: Stoke the Fire** (RB) | buff (self) | crest flares, body glows | 0.25/4.0/— | — | — | — | — | 10 | 12 s | — | For 4 s: startup and recovery −20%, every hit +5 Scorch build-up, stamina regen 0, **self-burn 1 HP/s** (cannot kill) |
| **JUICE: Meltdown** | area + buff | furnace door blows open; molten fists | 0.5 activation | 12 (pulse) | 3.0 | 0.5 | 30 | — | Hype 100 | Scorch 50 (pulse) | Pulse circle r 3 m on activation. For 6 s: armor vs everything but Heavies; every hit +25 Scorch build-up and leaves a Scorch patch r 1.5 m 3 s at the impact point. Ends with a 2 s "burnt out" state: −30 stamina, no armor. |

### Techniques (6) and build directions

| Id | Technique | Effect | Tags |
|---|---|---|---|
| `tech_stoke_pressure_cooker` | **Pressure Cooker** | Sizzle on an enemy also drains 2 stamina/s | status, burn |
| `tech_stoke_iron_chin` | **Iron Chin** | Poise 60 → 85; after Stoke is knocked down, his next 3 hits deal +30% | tank, comeback |
| `tech_stoke_lead_hand_learner` | **Lead Hand Learner** | Jab startup 0.12 → 0.09; string becomes L1·L1·L2·L3 (an extra jab, same cancel rules) | light, combo |
| `tech_stoke_afterburner` | **Afterburner** | Stoke Step leaves a Scorch patch r 1.0 m 2 s along the slide; dash distance +0.6 m | mobility, zone |
| `tech_stoke_counter_clock` | **Counter-Puncher's Clock** | Parry window 0.12 → 0.16 s; after a parry the next Heavy has half startup | parry |
| `tech_stoke_overcooked` | **Overcooked** | Charged Heavy +40% damage and +40% poise damage; each use costs 8 HP (cannot kill) | heavy, glass |

| Build | Techniques | Supplement synergy tags | How it plays |
|---|---|---|---|
| **Furnace** | Pressure Cooker + Afterburner (+ Stoke the Fire uptime) | burn, zone, status | Set the floor on fire, win the stamina war, Finisher every string |
| **Pocket Pressure** | Lead Hand Learner + Counter-Puncher's Clock | light, parry, combo | Four-hit strings, parry into half-startup Heavy, never stops |
| **Big Burn** | Iron Chin + Overcooked | heavy, tank, glass | Walk through lights, trade HP for 25-damage haymakers |

### AI notes (bots)
Personality **"Pressure"**. Prefers distance 0.9–1.1 m, walks forward, throws L1–L2 as pokes, commits to L3/Finisher when the target is Sizzling. Uses Steam Vent reactively against projectiles and to reset spacing when poise < 30%. Uses Stoke the Fire when the opponent is knocked down (safe window). JUICE when the opponent is cornered. Journeyman and below never Charged-Heavy; Headliner+ parries Heavies 35% of the time.

### Sound palette
Vocal: gravelly amphibian grunts with a metallic ring, like a kettle that swears. Impacts: dull thuds with an ember crackle tail; Heavies add a furnace "whump". Movement: bare slaps + a soft iron clank from the belly door. JUICE: boiler whistle rising to a bang.

---

## 2. DREDGE — the Dock Crab

**Id** `f_dredge` · **Plan** crab (body shell, 4 walking legs × 2 segments, 2 claw arms × 2 segments + eyestalk head = 14 segments) · **Element** Brine

### Concept
A massive harbor crab, shell barnacled like a rusted hull. The right claw is an oversized **crusher** wrapped in mooring chain; the left is a quick **cutter**. A weary, salty old dockworker who has seen every kind of fool walk into the cage. Idle: taps the cutter against the floor, blows a slow bubble, eyestalks swivel to track the camera.

| Visual | Spec |
|---|---|
| Silhouette | Low, very wide, one huge claw. Reads as a "rusty anvil with a fist". |
| Palette | Shell rust-red `#8C3B2B`; barnacle crust grey `#B9B3A6`; underbelly `#E8D9B8`; claw tips dark `#2E2A28`; chain steel `#7A7F85`; eyes pale `#DDF3FF` |
| Materials | Chipped painted iron, wet-look chitin on the joints, dull chain |
| Distinctive | Crusher claw is 2× the cutter; chain rattles on every Heavy. Barnacles glow faintly when Anchor Drop is active. |
| Detachable piece | The **cutter claw's tip** pops off and skitters. |

### Playstyle
Grappler wall. **Beginner hook:** you are the biggest thing in the cage; Grab (B) wins — anything you catch gets thrown into a wall. Hold Guard and lights bounce off.

| Strengths | Weaknesses | Counterplay against him |
|---|---|---|
| Highest HP and poise, best throws, 1.3 m grab reach, sideways speed, Brine puddles make others heavy and slow | Slow forward walk, long startups, huge target for projectiles and zones, Short-Out (Static on Soaked) hurts him because his own puddles soak him when pushed in | Stay off his front arc (his sides are slow to turn), poke at 1.4 m+, bait Anchor Drop and wait out its 2.5 s, grab him when he's anchored (grabs beat armor), Static fighters fish for Short-Outs in his own puddles |

### Moveset

| Move | Weapon | Path (spatial) | S/A/R (s) | Dmg | KB m | Stun s | Poise | Stam | CD | Build-up | Properties |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **L1 Cutter Snip** | left claw tip | claw snaps forward 1.2 m at chest height (0.9 m off the floor) | 0.16/0.08/0.22 | 5 | 0.5 | 0.30 | 8 | 5 | — | Brine 12 | — |
| **L2 Backhand Claw** | right claw (crusher) | sweeps right→left in a horizontal 90° arc at chest height, radius 1.4 m | 0.20/0.12/0.30 | 6 | 1.2 (sideways) | 0.40 | 14 | 7 | — | Brine 14 | Multi-target in the arc |
| **L3 Double Clamp** | both claw tips | both claws converge from ±50° to meet 1.0 m ahead at chest height (pincer) | 0.22/0.10/0.35 | 8 | 0.8 | 0.50 | 18 | 8 | — | Brine 20 | On a Soaked target: 0.4 s **Clamp Hold** (target can't act; sets up Grab) |
| **Heavy: Crusher Slam** | right claw | raises overhead (2.0 m) and slams down 1.1 m ahead to floor level | 0.32/0.12/0.45 | 14 | 1.0 | 0.60 | 30 | 12 | — | Brine 30 | Armor during startup; on landing a **ground wave line** 2.5 m long × 1 m wide: 4 dmg, trips Soaked targets |
| **Charged Heavy: Hull Breaker** | right claw | same arc, longer rise, body lifts on four legs | 0.55/0.14/0.60 | 18 | 2.5 | 0.90 | 50 | 16 | — | Brine 45 | Guard-crush; creates a **Brine puddle** r 1.5 m 4 s at impact |
| **Finisher: Bilge Pump** | right claw | clamps at 1.0 m, squeezes, then shoves the target 2.5 m straight back | 0.18/0.12/0.50 | 10 | 2.5 | 0.50 | 25 | 10 | — | Brine 25 | If the shoved target hits a wall or prop: **wall splat** +4 dmg, +0.3 s stun |
| **Dash Attack: Scuttle Check** | whole body (shell edge) | 1.5 m lateral or forward slide, shell leads | 0.10/0.15/0.30 | 7 | 2.0 | 0.40 | 15 | 8 (+dodge) | — | Brine 10 | From a sideways dash: +1 dmg, +0.5 m knockback |
| **Grab: Clamp** | right claw | crusher closes at **1.3 m** reach | 0.28 | — | — | — | — | 6 | — | — | Pummel = squeeze (4 dmg, Brine 10, 0.4 s each). Throws: Fwd **Overhead Hurl** 3 m, 12 dmg, knockdown · Side **Swing-and-Release** 2.5 m, 9 dmg · Back **Over-the-Shell** 2 m, 8 dmg, target lands facing away |
| **Ability 1: Tide Spit** (LB) | projectile (lobbed) | glob of brine from the mouthparts, arc to a point up to 7 m, speed 9 m/s | 0.30/—/0.40 | 6 | 1.0 | 0.30 | 8 | 10 | 6 s | Brine 40 | On impact or expiry: **Brine puddle** r 1.2 m 5 s. Reflectable. |
| **Ability 2: Anchor Drop** (RB) | shield + counter_stance | all four legs plant; chain drops; body lowers 0.2 m | 0.15/2.5/0.30 | — | — | — | — | 8 | 10 s | — | For 2.5 s: **armor** (ignores all stagger), knockback taken −50%, cannot walk (can rotate 90°/s), and **counter**: any melee hit that lands on Dredge triggers an instant claw snap at the attacker (6 dmg, 20 poise, Brine 15). Grabs still work on him. |
| **JUICE: High Tide** | area + zone | both claws slam the floor | 0.5 activation | 10 (ring) | 2.0 | 0.5 | 40 | — | Hype 100 | Brine 60 | **Ground wave ring** out to r 5 m: knockdown on everything it reaches. Then the whole arena floor is a **Brine zone for 8 s** (20 Brine build-up/s to everyone but Dredge). During it Dredge walks 3.6 m/s in any direction, throws go +30% distance, and Crusher Slam's wave line is 4 m. |

### Techniques (6) and build directions

| Id | Technique | Effect | Tags |
|---|---|---|---|
| `tech_dredge_mooring_chain` | **Mooring Chain** | Grab reach 1.3 → 1.6 m; a successful grab pulls the target 0.5 m in first (hits guard too) | grab, pull |
| `tech_dredge_barnacle_plating` | **Barnacle Plating** | Guard absorbs 85% instead of 75%; each blocked hit refunds +2 stamina | tank, guard |
| `tech_dredge_undertow` | **Undertow** | Every Brine puddle Dredge creates pulls non-Dredge fighters toward its center at 0.5 m/s | zone, pull |
| `tech_dredge_wall_and_chain` | **Wall-and-Chain** | Wall splats (from any Dredge throw or shove) deal +6 dmg and +15 poise | grab, arena |
| `tech_dredge_molting_season` | **Molting Season** | Anchor Drop ends with a shell-shed pulse r 2 m: 8 dmg, 1.5 m push, and Dredge is cleansed of all statuses; Anchor Drop cooldown +3 s | counter, cleanse |
| `tech_dredge_sidewinder` | **Sidewinder** | Sideways walk 3.2 → 3.8 m/s, sideways dash 3.0 → 3.6 m; Scuttle Check from a sideways dash deals ×1.5 | mobility |

| Build | Techniques | Synergy tags | How it plays |
|---|---|---|---|
| **Hurler** | Mooring Chain + Wall-and-Chain | grab, arena, heavy | Pull, hurl, splat. Loves small arenas and props. |
| **The Wall** | Barnacle Plating + Molting Season | tank, guard, counter | Stand still, get hit, hit back harder, shed everything they put on you. |
| **Riptide** | Undertow + Sidewinder | zone, mobility, status | Lay puddles, circle sideways, let the water drag them into Double Clamp holds. |

### AI notes
Personality **"Patient"**. Holds Guard when the opponent is in startup, looks for Grab when the target is Soaked or guarding, prefers to fight near walls (chooses a wall within 3 m as its "anchor spot"). Uses Tide Spit at > 3 m to force approach. Anchor Drop when poise < 40% or when a Charged Heavy is detected. Journeyman never grabs out of guard; Headliner+ walks opponents toward walls deliberately.

### Sound palette
Vocal: low bubbling rumble, occasional clack of mouthparts. Impacts: heavy wet "clock" of chitin plus chain rattle; slams add a sub-bass thud with a splash tail. Movement: six-point scuttle click-clack, wet. JUICE: foghorn + surging tide.

---

## 3. GUSTO — the Showboat Tern

**Id** `f_gusto` · **Plan** avian (head/beak, neck, torso, 2 wings × 2 segments as arm chains, 2 legs × 2 segments, tail = 11 segments; hop-glide) · **Element** Gale

### Concept
A lanky, loud seabird with sunglasses-shaped eye markings, a bleached pompadour crest, long taped shins, and wing-edge feathers like knives. He came to the Circuit for the cameras. Idle: struts in place, fans one wing at the crowd, checks an imaginary watch.

| Visual | Spec |
|---|---|
| Silhouette | Tall, thin, wide wingspan, big crest. Reads as a "capital T with a hairdo". |
| Palette | Body white `#F2F2EC`; wing tops grey-blue `#7FA4B8`; wing tips black `#2B2B2B`; beak and legs orange `#FF8A3D`; crest streak teal `#35C1C9`; eye markings black |
| Materials | Soft matte feathers with a satin rim, glossy beak, taped shins (cloth) |
| Distinctive | Crest flops when Winded. Wing edges flash white on Heavies. |
| Detachable piece | **Three tail feathers** burst out and flutter down slowly. |

### Playstyle
Hit-and-run rushdown. **Beginner hook:** fastest thing in the cage; Dodge then Light (A, X) all day; Taunt (D-pad Up) builds Hype faster than anyone so you JUICE first.

| Strengths | Weaknesses | Counterplay against him |
|---|---|---|
| Speed 4.3, longest dash, 1.5 m wing reach, hover ignores ground zones, Gale shoves set up ring-outs and wall splats, cheapest dodges | Lowest poise (40): two Heavies floor him; low HP; gets thrown ×1.6 distance because he's 55 kg; Winded enemies are needed for his launcher follow-ups | Hold your ground and guard the first wing slash, then Heavy: his recovery is where he dies. Grab him when he lands from Downdraft. Scorch (Stoke) burns him +15%. Don't chase him; make him come to you. |

### Moveset

| Move | Weapon | Path (spatial) | S/A/R (s) | Dmg | KB m | Stun s | Poise | Stam | CD | Build-up | Properties |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **L1 Wing Snap** | right wing edge | wing sweeps from behind the body forward, horizontal at neck height, reach 1.4 m | 0.10/0.08/0.18 | 4 | 0.4 | 0.25 | 5 | 4 | — | Gale 10 | — |
| **L2 Beak Peck** | beak | neck extends 1.2 m forward at head height, two quick jabs 0.1 s apart | 0.12/0.06+0.06/0.20 | 2+2 | 0.3 | 0.25 | 6 | 4 | — | Gale 10 | Multi-hit (2) |
| **L3 Scissor Kick** | right foot | leg snaps from the floor up to 1.3 m ahead, knee height → head height | 0.16/0.10/0.30 | 7 | 1.5 | 0.45 | 12 | 7 | — | Gale 18 | Knock-up 0.6 m if the target is Winded |
| **Heavy: Crosswind Slash** | both wing edges | wings sweep forward from both sides and cross at chest height 1.5 m out, 100° arcs | 0.24/0.12/0.40 | 6+6 | 2.0 (push) | 0.50 | 20 | 11 | — | Gale 30 | Multi-hit (2); a 2 m cone wind **push 1 m** on everything in it even if the wings miss |
| **Charged Heavy: Downdraft** | both feet | leap 1.5 m up to a target point ≤ 2.5 m ahead, drop with both feet | 0.45/0.15/0.50 | 16 | 2.0 (radial) | 0.70 | 40 | 15 | — | Gale 40 | Direct hit: knock-up 1.0 m; landing **area circle** r 1.5 m: 4 dmg, Gale 15; no armor (he's airborne; can be hit out of it) |
| **Finisher: Tailspin** | both wing edges | whole-body spin, wings out, radius 1.5 m, 2 rotations, drifting 1 m forward | 0.15/0.40/0.45 | 3×3 | 2.5 (radial) | 0.50 | 18 | 10 | — | Gale 10/hit | Multi-hit (3); pushes all nearby fighters; drifts forward |
| **Dash Attack: Skid Kick** | right foot | 1.5 m slide, foot leads at knee height 1.3 m out | 0.10/0.12/0.30 | 6 | 1.2 | 0.40 | 10 | 7 (+dodge) | — | Gale 15 | **Trip** (knockdown) if the target is Soaked or Winded |
| **Grab: Talon Snatch** | both feet | short hop, talons close on the head/shoulders at 1.0 m | 0.25 | — | — | — | — | 6 | — | — | Pummel = pecks (2 dmg, Gale 6, 0.25 s each). Throws: Fwd **Carry-and-Drop** leaps 2.5 m carrying the target and drops them (8 dmg, knockdown; repositioning tool) · Side **Wing Fling** 3 m, 7 dmg · Back **Toss-Over** 2 m, 7 dmg |
| **Ability 1: Gust Bomb** (LB) | projectile (straight) | a compressed-air ball from the beak, 12 m/s, range 8 m, radius 0.3 m | 0.20/—/0.30 | 5 | 2.5 (push) | 0.20 | 8 | 9 | 5 s | Gale 40 | On expiry or wall contact: **area circle** r 1.5 m push 1.5 m, Gale 15. Reflectable. |
| **Ability 2: Hang Time** (RB) | hover | hops 2 m up and hovers 1.2 s, steerable at 3 m/s | 0.15/1.2/0.25 | — | — | — | — | 12 | 6 s | — | Immune to ground zones and trips while hovering. **Light while hovering = Dive Peck**: leap to the lock-on target (≤ 3 m), beak first, 8 dmg, 25 poise, Gale 20, 0.4 s stun. Heavy while hovering = Downdraft without the hold. |
| **JUICE: Hurricane Strut** | buff + zone | crest flares, feathers whip | 0.5 activation | — | 3.0 (cone push on activation) | 0.3 | 20 | — | Hype 100 | Gale 30 (activation) | Activation: **cone 3 m** push 3 m. For 7 s: move speed +35%, dodges cost 0 stamina, every dodge leaves a **Gale vortex** zone r 1.2 m 2 s where it started, and a Taunt during the strut heals 5 HP (1 s cooldown). |

### Techniques (6) and build directions

| Id | Technique | Effect | Tags |
|---|---|---|---|
| `tech_gusto_crowd_work` | **Crowd Work** | Taunt +8 → +12 Hype and grants 1.5 s of +15% damage; taunt animation 1.5 → 1.1 s | hype |
| `tech_gusto_hollow_bones` | **Hollow Bones** | Dodge distance +0.8 m, dodge stamina cost −30%; knockback taken +15% | mobility, glass |
| `tech_gusto_feather_knives` | **Feather Knives** | Wing attacks (L1, Heavy, Finisher) +2 dmg per hit; Crosswind Slash gains a third hit (+5 dmg) | light, heavy |
| `tech_gusto_tailwind` | **Tailwind** | Winded enemies take +25% knockback from Gusto; Gust Bomb bounces off one wall | status, projectile |
| `tech_gusto_air_superiority` | **Air Superiority** | Hang Time 1.2 → 2.0 s; Dive Peck and Downdraft +30% poise damage; Hang Time cooldown 6 → 8 s | air, heavy |
| `tech_gusto_slippery_customer` | **Slippery Customer** | Parry window +0.04 s; parrying a Heavy refunds the next dodge's stamina and grants 1 s of evasion (i-frames while moving) | parry |

| Build | Techniques | Synergy tags | How it plays |
|---|---|---|---|
| **Showboat** | Crowd Work + Hollow Bones | hype, mobility, juice | Taunt, dodge, taunt, JUICE twice a fight. |
| **Razorwing** | Feather Knives + Tailwind | light, heavy, status | Wing strings and launched Winded victims into walls. |
| **Skyhook** | Air Superiority + Slippery Customer | air, parry, heavy | Live in the air, parry what comes up to meet you, dive on the recovery. |

### AI notes
Personality **"Showboat"**. Keeps 1.6–2.0 m, dashes in for Skid Kick or L1–L2, dashes out. Taunts when the opponent is > 3 m away or knocked down. Uses Gust Bomb to push an approaching Heavy user off. Hang Time when standing in an enemy zone. Never guards more than 0.5 s (he dodges instead). Punching Bag tier taunts too much (intended; it's funny and teaches punishing taunts).

### Sound palette
Vocal: nasal gull squawks shaped into laughter and catcalls. Impacts: sharp feather whip-cracks with an airy "whoosh" tail; kicks are snappy. Movement: light taps, wing flaps on dashes. JUICE: a rising gale with a crowd "ooooh" layered in.

---

## 4. DOZER — the Shovelsnout

**Id** `f_dozer` · **Plan** quadruped (head/snout+horn, neck, chest, pelvis, 4 legs × 2 segments, tail = 13 segments) · **Element** Grit

### Concept
A low, wide quarry hog with a steel shovel-blade snout, one short horn above it, cracked-stone plates on the shoulders, and a mining headlamp on a strap. He is a cheerful dope who is happiest when moving in a straight line. Idle: snuffles the floor, paws the ground, sneezes dust, headlamp flickers.

| Visual | Spec |
|---|---|
| Silhouette | Long low wedge with a bright dot (the headlamp). Reads as a "doorstop with a lamp". |
| Palette | Hide slate `#6E6A66`; shoulder plates ochre `#C7A160`; snout steel `#9FA6AD`; headlamp `#FFE066`; eyes black; dust decals `#D9C7A3` |
| Materials | Coarse matte hide, cracked clay plates with dust in the cracks, brushed steel snout |
| Distinctive | Headlamp brightness = Hype. Plates shed dust on every hit taken. |
| Detachable piece | The **horn tip** snaps off and embeds in the nearest sponsor board. |

### Playstyle
Charger tank. **Beginner hook:** hold Heavy and let go — you are a truck. Horn lunges knock people over. Ability 1 charges across the cage and carries whoever you hit into the wall.

| Strengths | Weaknesses | Counterplay against him |
|---|---|---|
| 130 HP / 85 poise, armor on every Heavy, best poise damage, Caked victims crumble, charges that carry targets into walls | Wide turn radius, almost nothing hits to his sides or behind, slow Lights, Bulldoze into a wall without a target staggers him 0.6 s, weak to Sludge (Slurry corrodes him +15%) | Sidestep his line and hit the flank; dodge Bulldoze late and punish the wall stagger; Mud/Soaked stops his charge distance; grabs when he's Caked by his own rubble? No — he's immune to his own Grit; use Brine to Mudbound him |

### Moveset

| Move | Weapon | Path (spatial) | S/A/R (s) | Dmg | KB m | Stun s | Poise | Stam | CD | Build-up | Properties |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **L1 Snout Jab** | snout | head thrusts 1.1 m forward at waist height (0.9 m) | 0.14/0.08/0.22 | 5 | 0.6 | 0.30 | 10 | 5 | — | Grit 12 | — |
| **L2 Hoof Stomp** | left fore-hoof | hoof lifts 0.5 m and stomps down 0.8 m ahead at floor level | 0.16/0.08/0.25 | 5 | 0.4 | 0.30 | 12 | 5 | — | Grit 12 | Small ground pulse r 0.8 m: +5 Grit build-up to anyone standing in it |
| **L3 Scoop** | snout | snout dips to the floor and scoops up to chest height 1.2 m ahead | 0.20/0.10/0.35 | 7 | 1.5 (up) | 0.50 | 16 | 7 | — | Grit 18 | **Launcher** (knock-up 1.0 m) |
| **Heavy: Horn Lunge** | horn | root lunges 0.6 m, horn drives forward to 1.2 m at chest height | 0.26/0.12/0.40 | 13 | 2.0 | 0.60 | 30 | 12 | — | Grit 30 | Armor during startup and active |
| **Charged Heavy: Quarry Ram** | horn + body | 3 m dash (6 m/s) then horn uppercut from knee height to 1.3 m | 0.50/0.30/0.55 | 17 | 3.5 | 0.80 | 50 | 16 | — | Grit 45 | Armor throughout; guard-crush; knock-up 1.2 m |
| **Finisher: Gravel Toss** | snout + area cone | scoop at 1.0 m then flick sideways; gravel sprays in a 2 m cone | 0.18/0.12/0.45 | 10 | 2.5 (sideways) | 0.60 | 25 | 10 | — | Grit 25 | Cone 2 m, 60°: 3 dmg, Grit 20 to everyone in it |
| **Dash Attack: Shoulder Barge** | whole body (shoulder plate) | 1.6 m slide, shoulder leads | 0.08/0.18/0.30 | 7 | 2.0 | 0.40 | 15 | 8 (+dodge) | — | Grit 12 | — |
| **Grab: Snout Hook** | snout/horn | hooks the target onto the snout at 1.0 m | 0.25 | — | — | — | — | 6 | — | — | Pummel = headbutt shake (3 dmg, Grit 10, 0.4 s each). Throws: Fwd **Launch** 3 m forward + knock-up 1.0 m, 10 dmg · Side **Rake** 2.5 m, 9 dmg · Back **Buck** tossed over his own back 2 m, 9 dmg, knockdown |
| **Ability 1: Bulldoze** (LB) | charge (whole body) | paws the ground 0.3 s, then drives forward up to 6 m at 7 m/s, steering ±20°/s | 0.30/≤0.9/0.40 | 11 | 3.5 | 0.60 | 35 | 14 | 8 s | Grit 35 | Armor throughout. On hit the target is **carried** ~2 m along the charge; if the charge ends on a wall with a carried target: **wall splat** +5 dmg, +0.4 s stun, knockdown. Hitting a wall with no target: Dozer staggers 0.6 s (punishable). |
| **Ability 2: Dust Bowl** (RB) | zone (self-centered) | stomps all four hooves; dust cloud r 2.5 m follows Dozer for 4 s | 0.30/4.0/0.20 | — | — | — | — | 10 | 11 s | Grit 12/s (enemies inside) | Enemies inside: poise regen 0, Grit 12/s. Enemy projectiles entering the cloud are destroyed. Dozer has **armor vs Lights** while inside. |
| **JUICE: Landslide** | area line + buff | rears up and drops | 0.5 activation | 14 (wave) | 2.5 | 0.6 | 60 | — | Hype 100 | Grit 60 | **Ground wave line** 6 m long × 2 m wide forward: knockdown. For 6 s: permanent armor, Bulldoze cooldown 0 with 10 m range, and every Bulldoze hit drops a **boulder prop** (0.8 m, 40 HP, blocks movement/projectiles, 20 s) behind the target. |

### Techniques (6) and build directions

| Id | Technique | Effect | Tags |
|---|---|---|---|
| `tech_dozer_quarry_legs` | **Quarry Legs** | Bulldoze speed 7 → 8.5 m/s and steering ±20 → ±30°/s; Quarry Ram dash 3 → 4 m | charge, mobility |
| `tech_dozer_pack_mule` | **Pack Mule** | Max HP +15; knockback taken −20% | tank |
| `tech_dozer_rockslide` | **Rockslide** | A Heavy on a Caked target whose poise is below 50% knocks it down outright | status, heavy |
| `tech_dozer_demolition_permit` | **Demolition Permit** | Wall splats from Bulldoze or throws leave a Grit rubble zone r 1.5 m 3 s at the wall | zone, arena |
| `tech_dozer_hard_hat` | **Hard Hat** | Dust Bowl also **reflects** projectiles; while inside it Dozer's Lights have armor | counter, zone |
| `tech_dozer_tusk_dust_habit` | **Tusk Dust Habit** | Horn attacks (Horn Lunge, Quarry Ram, Snout Hook throws) +25% damage; Dozer's poise regen halved (the shakes) | heavy, glass |

| Build | Techniques | Synergy tags | How it plays |
|---|---|---|---|
| **Freight Train** | Quarry Legs + Demolition Permit | charge, arena, zone | Charge across the cage, splat, leave rubble, charge again. |
| **Boulder** | Pack Mule + Hard Hat | tank, counter, zone | Stand in your dust, shrug off projectiles and lights, lunge when they come in. |
| **Rockbreaker** | Rockslide + Tusk Dust Habit | status, heavy, glass | Cake them, then every Heavy is a knockdown. |

### AI notes
Personality **"Linebacker"**. Lines up targets and commits to straight-line attacks; retargets slowly (turn rate is his real weakness and the AI respects it). Uses Bulldoze when the target is > 3 m away and between him and a wall. Dust Bowl when a projectile user is at range. Lower tiers Bulldoze into walls on purpose sometimes (reads as dopey, teaches the punish). Headliner+ saves Scoop launcher for Caked targets.

### Sound palette
Vocal: deep happy snorts, a goofy "hwuff" when he charges, a sneeze on idle. Impacts: gravelly crunches with a rock-tumble tail; horn hits add a steel "tink". Movement: four heavy hoof thuds, gravel scatter. JUICE: rockslide rumble + mining siren.

---

## 5. SLURRY — the Drain Wyrm

**Id** `f_slurry` · **Plan** serpent (head, 6 body segments; rears up on the rear 3 segments) · **Element** Sludge

### Concept
An oily moray-like serpent that lives in the cannery's main drain. Frilled fin crest, brass pipe-fitting collars around three of its segments, glowing green sludge seeping from every seam. Smug, patient, hypnotic. Idle: sways slowly, flicks its tongue, hiccups a bubble that pops with a tiny splat.

| Visual | Spec |
|---|---|
| Silhouette | A tall S-curve when reared, a long low line when moving. Reads as a "question mark". |
| Palette | Body oil-black `#2A2F2E` with green sheen `#5CCB3A`; belly yellow-green `#C7E66B`; collars brass `#B08A3E`; crest membrane `#8BD426`; eyes magenta `#E04FB0` |
| Materials | Wet oily skin with anisotropic sheen, brass with verdigris, translucent crest |
| Distinctive | Sludge drip rate = Hype. Crest fans fully open during Rear & Crash (the big tell). |
| Detachable piece | A **fang** pops out and sticks in the mat. |

### Playstyle
Zoner / trapper. **Beginner hook:** Spit (LB) from range, lay a puddle (RB), bite anything that walks through it. Grab is a coil-crush.

| Strengths | Weaknesses | Counterplay against it |
|---|---|---|
| Longest effective range (9 m lob), puddles control space, Gunked anti-heal beats rest-heavy builds, Drain Dive escapes, pull on L3 drags victims into puddles | Low poise while reared (55), slow turn, Scorch sets its own puddles off (Flare-Up burns it), Gale smears puddles and Spray hits its co-op partner, Gusto disperses it +15% | Approach through the gaps between puddles, Steam/Flare its puddles, punish Rear & Crash's 0.55 s recovery, grab it when its tail is extended after Tail Sweep |

### Moveset

| Move | Weapon | Path (spatial) | S/A/R (s) | Dmg | KB m | Stun s | Poise | Stam | CD | Build-up | Properties |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **L1 Tail Flick** | tail tip | tail whips from behind to 1.4 m ahead at knee height | 0.12/0.08/0.20 | 4 | 0.5 | 0.25 | 5 | 4 | — | Sludge 12 | — |
| **L2 Head Butt** | head | head lunges 1.3 m forward at chest height | 0.14/0.08/0.22 | 5 | 0.6 | 0.30 | 8 | 5 | — | Sludge 12 | — |
| **L3 Fang Snap** | head (jaws) | jaws lunge to 1.3 m, bite, jerk back 0.5 m | 0.18/0.10/0.32 | 7 | **pull 0.5 m** | 0.45 | 12 | 7 | — | Sludge 22 | Pulls the target 0.5 m toward Slurry |
| **Heavy: Tail Sweep** | tail tip | 180° horizontal arc at knee height, radius 1.5 m, from left to right | 0.26/0.14/0.40 | 12 | 2.0 | 0.50 | 25 | 11 | — | Sludge 28 | Multi-target; **trip** (knockdown) on Gunked targets |
| **Charged Heavy: Rear & Crash** | head + first 2 body segments | rears to 2.0 m then the whole upper body crashes down to a point 1.5 m ahead | 0.50/0.15/0.55 | 17 | 2.5 | 0.80 | 45 | 16 | — | Sludge 40 | Armor during the rear; leaves a **Sludge puddle** r 1.3 m 4 s at impact; guard-crush |
| **Finisher: Venom Spit** | projectile (straight, short) | point-blank spit, 4 m range, 14 m/s | 0.14/—/0.40 | 9 | 1.5 | 0.50 | 15 | 9 | — | Sludge 40 | After a full L1–L3 string (46 build-up) this usually tips the target into Gunked. Reflectable. |
| **Dash Attack: Slither Strike** | head | low 1.6 m dash, head leads at knee height then rises | 0.10/0.14/0.30 | 6 | 1.0 | 0.35 | 10 | 7 (+dodge) | — | Sludge 15 | If the dash passes through a Sludge puddle: +2 dmg, +10 build-up |
| **Grab: Coil** | body segments 2–4 | wraps the target at **1.4 m** | 0.30 | — | — | — | — | 6 | — | — | Pummel = squeeze (4 dmg, Sludge 10, 0.4 s each). Throws: Fwd **Whip Toss** 3 m, 10 dmg · Side **Slingshot** 3 m, 9 dmg · Back **Gulp-and-Spit** drags the target over its own body and spits it out 2 m behind, 9 dmg, target lands Gunked +30 build-up |
| **Ability 1: Sludge Lob** (LB) | projectile (lobbed) | glob from the mouth, arc to a point ≤ 9 m, 10 m/s | 0.25/—/0.35 | 7 | 1.0 | 0.30 | 8 | 10 | 5 s (2 charges) | Sludge 45 | On impact or expiry: **Sludge puddle** r 1.5 m 6 s. Reflectable. |
| **Ability 2: Drain Dive** (RB) | blink | dives into the floor (a drain cover pops), resurfaces ≤ 5 m away toward the stick direction after 0.5 s | 0.20/0.5/0.30 | 5 (emerge) | 0.5 (up) | 0.30 | 10 | 12 | 9 s | Sludge 25 | Invulnerable 0.4 s during the dive. Emerge **area circle** r 1.2 m. Emerging inside one of its own puddles refunds 3 s of cooldown. |
| **JUICE: Overflow** | zone line + buff | vomits a river | 0.5 activation | 8 (wave) | 1.5 | 0.4 | 20 | — | Hype 100 | Sludge 50 | **Ground wave** 4 m forward, then a **Sludge river zone** 8 m long × 3 m wide, 8 s. For 6 s: each Light also fires a tiny spit projectile (3 dmg, Sludge 10, 4 m), Gunked enemies take 2× Gunked damage, Slurry heals 2 HP/s while touching sludge. |

### Techniques (6) and build directions

| Id | Technique | Effect | Tags |
|---|---|---|---|
| `tech_slurry_septic_bloom` | **Septic Bloom** | Slurry's puddles are 50% larger and last +2 s | zone |
| `tech_slurry_lockjaw` | **Lockjaw** | Fang Snap pull 0.5 → 1.2 m; Coil reach 1.4 → 1.7 m | grab, pull |
| `tech_slurry_blood_thinner` | **Blood Thinner** | Gunked damage 1.5 → 2.25 HP/s; Gunked targets' guard absorbs 65% instead of 75% | status |
| `tech_slurry_grease_trap` | **Grease Trap** | Enemies in Slurry's puddles: dodge distance −40%; Slurry moves +15% faster in any Sludge zone | zone, mobility |
| `tech_slurry_double_dip` | **Double Dip** | Sludge Lob charges 2 → 3; Drain Dive emerge damage 5 → 9 and radius 1.2 → 1.6 m | projectile, blink |
| `tech_slurry_hardened_arteries` | **Hardened Arteries** | Poise 55 → 80; loses Drain Dive's cooldown refund and Overflow's self-heal | tank, glass |

| Build | Techniques | Synergy tags | How it plays |
|---|---|---|---|
| **Swamp** | Septic Bloom + Grease Trap | zone, mobility, status | Cover the floor; nobody can dodge; you glide. |
| **Constrictor** | Lockjaw + Hardened Arteries | grab, pull, tank | Drag them in from 1.7 m, coil, Gulp-and-Spit, stand your ground. |
| **Toxin** | Blood Thinner + Double Dip | status, projectile, blink | Three lobs, Gunked melts guards and HP, dive in and out. |

### AI notes
Personality **"Trapper"**. Keeps 3–6 m, lobs onto the target's predicted position, lays a puddle between itself and the target, uses Fang Snap when the target is 1.3 m away and standing in sludge. Drain Dive away when poise < 40% or when grabbed-at twice. Headliner+ places lobs *behind* the target to cut off retreat. Avoids spitting at targets standing next to allies when a Scorch user is present (Flare-Up awareness).

### Sound palette
Vocal: wet hisses, gurgles, a smug chuckle made of bubbles. Impacts: slaps with a squelch tail; the Rear & Crash is a wet slam plus a pipe clang from the collars. Movement: a slithering drag with drips. JUICE: a drain backing up, then a flood.

---

## 6. JITTERS — the Battery Jelly

**Id** `f_jitters` · **Plan** hopper (core = 2 segments: body + inner coil; 2 stubby arms × 1 segment; 2 antenna bulbs as light segments = 6 segments; bouncy hops, 0.8 s hover) · **Element** Static

### Concept
A beach-ball-sized translucent jelly with an arcing coil visible inside, two stubby arms, two antenna bulbs that spark, and a battery cap on top. Face: nervous cartoon eyes. Permanently over-caffeinated. Idle: vibrates, hums, antenna bulbs ping each other with tiny arcs; occasionally jumps at nothing.

| Visual | Spec |
|---|---|
| Silhouette | A sphere with two nubs on top and two nubs on the sides. Reads as a "ball with ears". |
| Palette | Body translucent cyan-white `#BDEFFF`; inner coil glow `#FFF27A`; antenna bulbs `#F7E04A`; arms lavender `#B59CE0`; cap dark steel `#3C4650`; eyes `#1F2A33` |
| Materials | Subsurface jelly (refraction-lite), emissive coil, matte rubber arms, brushed cap |
| Distinctive | Coil brightness = Hype. Squashes and stretches on every hop (procedural scale on the core segment, cosmetic). |
| Detachable piece | The **battery cap** pops off like a champagne cork. |

### Playstyle
Trickster / disruptor. **Beginner hook:** bounce on heads — hold Heavy to squash. Your zaps make enemies twitch (Jolted) so they drop what they're doing. Ability 2 places a spring pad: launch yourself, or them.

| Strengths | Weaknesses | Counterplay against him |
|---|---|---|
| Best mobility, Jolted interrupts charges/grabs/channels, props change the arena, hard to pin (knockdown recovery +30%), Overcharge dominates crowds (chain arcs) | Lowest HP (80), weak Lights (4), short reach (0.8–1.0 m), loses to Grit (Dozer +15%, and Caked halves his dodging), light enough to be thrown far | Guard his Squash and punish the landing, Grab (his escape is short-reach), stand on his Spring Pads so he can't use them (or use them yourself), Caked beats him |

### Moveset

| Move | Weapon | Path (spatial) | S/A/R (s) | Dmg | KB m | Stun s | Poise | Stam | CD | Build-up | Properties |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **L1 Slap** | left arm | arm swings forward 0.8 m at his chest height (0.6 m off the floor; hits others at waist/thigh) | 0.10/0.06/0.16 | 4 | 0.3 | 0.20 | 4 | 3 | — | Static 12 | — |
| **L2 Double Slap** | right arm | body leans 0.2 m, arm swings 0.9 m | 0.10/0.06/0.18 | 4 | 0.3 | 0.20 | 5 | 3 | — | Static 12 | — |
| **L3 Headbonk** | whole body | hops 1.0 m forward into the target at chest/head height | 0.16/0.12/0.30 | 7 | 1.0 | 0.40 | 14 | 6 | — | Static 20 | Bounces back 0.6 m after contact (safe spacing) |
| **Heavy: Squash** | whole body | leaps 1.8 m up and drops on a point ≤ 2.0 m ahead | 0.30/0.14/0.40 | 12 | 1.5 (radial) | 0.60 | 28 | 11 | — | Static 30 | Landing **area circle** r 1.0 m: 4 dmg, Static 10. If the body lands on the target's **head segment**: +3 dmg ("Bonk"). |
| **Charged Heavy: Super Squash** | whole body | leaps 2.5 m up, drops on a point ≤ 3.0 m ahead | 0.50/0.16/0.50 | 16 | 2.5 (radial) | 0.80 | 45 | 15 | — | Static 45 | Landing circle r 1.6 m: 6 dmg, Static 20; guard-crush; knock-up 0.8 m. No armor (airborne). |
| **Finisher: Static Cling** | whole body | presses into the target at 0.8 m and discharges | 0.14/0.10/0.40 | 9 | 0.2 | 0.50 | 18 | 9 | — | Static 35 | If this hit triggers Jolted, Jitters gains +10 Hype |
| **Dash Attack: Pinball** | whole body | long spinning hop 1.8 m | 0.08/0.20/0.30 | 6 | 1.8 | 0.40 | 12 | 7 (+dodge) | — | Static 15 | Bounces off a wall once toward the lock-on target (second leg 1.5 m); from a Spring Pad: ×2 damage |
| **Grab: Suction Hug** | both arms + body | hops 0.5 m in and latches at 0.9 m | 0.25 | — | — | — | — | 6 | — | — | Pummel = zaps (2 dmg, Static 15, **0.25 s** each — fastest pummel). Throws: Fwd **Spit-Bounce** 2.5 m, 8 dmg · Side **Fling** 2.5 m, 8 dmg · Back **Over-the-Top** 2 m, 7 dmg. Grabs on Jitters hold 30% shorter (slippery). |
| **Ability 1: Arc Lash** (LB) | projectile (slow-homing) | an orb from the antenna, 6 m/s, homing 90°/s, range 7 m, lifetime 1.5 s | 0.18/—/0.30 | 6 | 0.5 | 0.20 (micro) | 10 | 9 | 6 s | Static 45 | On expiry: **area pulse** r 1.2 m, 3 dmg, Static 20. Reflectable. |
| **Ability 2: Spring Pad** (RB) | place_prop | places a spring pad (r 1.2 m, 0.2 m tall) at a point ≤ 3 m ahead; lasts 10 s; max 2 active | 0.20/—/0.25 | — | — | — | — | 8 | 7 s | — | Any fighter stepping on it is launched 2.5 m up and 3 m forward (knock-up). Enemies land with 0.4 s stun. Jitters launched from it gets hover and a free (no stamina) Squash. Pinball from a pad = ×2. |
| **JUICE: Overcharge** | buff + area | inflates to 1.5× scale | 0.5 activation | 10 (pulse) | 2.0 | 0.4 | 25 | — | Hype 100 | Static 50 (pulse) | Activation **circle** r 3 m. For 8 s: every hop landing pulses r 2 m (5 dmg, Static 25); every Light also fires a **chain arc** to the nearest other enemy within 2 m (3 dmg, Static 15); immune to stagger from Lights. |

### Techniques (6) and build directions

| Id | Technique | Effect | Tags |
|---|---|---|---|
| `tech_jitters_capacitor` | **Capacitor** | Hype gain +20%; Overcharge 8 → 10 s | hype, juice |
| `tech_jitters_bouncy_castle` | **Bouncy Castle** | Spring Pad max 2 → 3, cooldown 7 → 5 s; allies launched from a pad get 0.5 s evasion | prop, coop |
| `tech_jitters_chain_reaction` | **Chain Reaction** | Jolted enemies leak 10 Static build-up/s to other enemies within 1.5 m | status, crowd |
| `tech_jitters_rubber_core` | **Rubber Core** | Knockdown recovery +50% faster (stacks with the base +30%); poise 45 → 60 | tank |
| `tech_jitters_head_hunter` | **Head Hunter** | Squash "Bonk" bonus +3 → +7 dmg; Squash leap +0.5 m and target point ≤ 2.5 m | heavy |
| `tech_jitters_short_fuse` | **Short Fuse** | Arc Lash homing 90 → 180°/s and 2 charges; Jitters' stamina regen −20% | projectile, glass |

| Build | Techniques | Synergy tags | How it plays |
|---|---|---|---|
| **Trampoline** | Bouncy Castle + Head Hunter | prop, heavy, coop | Three pads, free Squashes, bonk everything. Best co-op Jitters. |
| **Battery** | Capacitor + Chain Reaction | hype, status, crowd | JUICE early, JUICE often; crowds Jolt themselves. |
| **Spark Plug** | Rubber Core + Short Fuse | tank, projectile, glass | Two homing orbs, bounce back up from every knockdown, trade stamina for pressure. |

### AI notes
Personality **"Pest"**. Keeps hopping; places a Spring Pad between itself and the target then baits with Arc Lash. Squashes targets that are channeling/charging (reads startup > 0.3 s). Pinballs off walls to re-engage. In FFA/horde, fights where the most enemies are (chain arcs). Punching Bag tier places pads randomly (adorable). Headliner+ places pads under knocked-down enemies to launch them on wake-up (legal: wake-up invulnerability still applies; the launch is displacement only).

### Sound palette
Vocal: squeaky hum with crackles, a high "eep" when hit, a kazoo-ish giggle. Impacts: rubbery "boing" with an electric snap; Squash is a wet "splat" plus a bass pop. Movement: boing-boing hops, tiny arc ticks. JUICE: capacitor whine rising to a transformer "BZZT".

---

## 7. Roster-wide checks

| Check | Status |
|---|---|
| Six different body plans | biped, crab, avian, quadruped, serpent, hopper ✔ |
| Six different elements | Scorch, Brine, Gale, Grit, Sludge, Static ✔ |
| Reach cap ≤ 1.6 m | Max is Dredge's Mooring Chain grab (1.6 m) and Slurry's Lockjaw coil (1.7 m — grab, not strike; cap it at 1.6 m if the engine insists) |
| Beginner mash viability | Every L1–L3 string chains at 0.1–0.2 s startups, every Heavy has a visible wind-up and a payoff, every fighter has one "hold Heavy and win a trade" option |
| Deliberate depth | Every fighter has a parry build, a resource tradeoff technique (glass tag), and a status-dependent property on at least two moves |
| Tag/co-op | Each fighter has at least one tool that helps a partner: Steam Vent (projectile wall), Undertow puddles, Gust Bomb pushes, Dust Bowl anti-projectile, Dilute via Tide Spit, Spring Pads for allies |
| Distinct silhouettes at 8 fighters | barrel, anvil, T, wedge, question mark, ball — all different at thumbnail size |
