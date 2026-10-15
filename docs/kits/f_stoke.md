# STOKE (`f_stoke`) — kit

Pressure boxer, Scorch, biped Scrapper. Spec: `docs/design/ROSTER.md` §1. Data:
`game/content/core/creatures/f_stoke.json`. Tests: `game/src/test/kits/test_kit_f_stoke.gd`
(shared harness `kit_harness_stoke_gusto.gd`). Body, art and model are unchanged except the fist
hit spheres (see Deviations).

## Stats (engine keys)

| health | walk_speed | stamina | poise | dodge_distance / dodge_time | weight / power / defense | mass |
|---|---|---|---|---|---|---|
| 110 | 3.4 | 100 (regen 12) | 60 (regen 15) | 2.8 m / 0.30 s | 1.0 / 1.0 / 1.0 | 85 kg |

The stub's `dodge_speed` (not an engine key, it made the creature invalid) became `dodge_distance`.

## Move list (final numbers)

S/A/R = startup (first hit window) / active (window span) / recovery, in seconds. KB is the engine
value (m/s on an 80 kg reference); "measured" columns are root displacement of a standing dummy
(Stoke mirror, 85 kg) and the damage of one clean contact, from the lab runs
(`--kit-lab`, see Commands). Stamina is the cost; a whiff costs +25 % (engine rule).

| Move | Weapon / path | S/A/R | Dmg | KB → measured | Stun | Poise | Stam | Build-up | Properties |
|---|---|---|---|---|---|---|---|---|---|
| L1 Jab | left fist, chin chamber → straight at head height | 0.12/0.08/0.18 | 4 (6.4 on the head) | 2.0 → 0.29 m | 0.25 | 5 | 4 | Scorch 10 | lunge 0.15 m |
| L2 Cross | right fist, right shoulder → head height, chest turns 40° | 0.14/0.08/0.22 | 5 (8.0 head) | 2.6 → 0.42 m | 0.30 | 8 | 5 | Scorch 12 | |
| L3 Lead Hook | left fist from 60° outside-left, horizontal arc at temple height | 0.18/0.10/0.30 | 7 (11.2 head) | 3.2 sideways → 0.82 m to Stoke's right | 0.45 | 14 | 7 | Scorch 18 | `kb_dir: side`, `kb_side: -1`, `turn_target: 30` (measured 28°) |
| Heavy: Overhand Boiler | right fist rises beside the head, loops over and down onto the head | 0.27/0.11/0.40 | 12 (19.3 on Gusto's head) | 5.4 → 1.5 m | 0.60 | 25 | 12 | Scorch 30 | armor vs Lights during the active window (`armor [[0.28,0.38]]`, `armor_level: lights`); lunge 2.6 m/s from 0.20 s, after the charge hold point (0.7 × startup), so holding the charge does not slide Stoke forward |
| Charged: Furnace Haymaker | full torso wind-up (chest −46°, crouch), wide right hook at head height | 0.48/0.14/0.50 | 18 (28.5 head) | 7.6 → 2.6–3.9 m | 0.80 | 45 | 16 | Scorch 45 | Light armor through startup; guard-crush `guard_break: 2.0` (2× stamina drain on a guarding target); on a Sizzling target `on_hit` adds launch 4.9 m/s (knock-up) |
| Finisher: Gut Furnace | 0.6 m step-in, right fist drives into the belly | 0.14/0.12/0.45 | 10 (11.5 chest) | 6.3 → 2.48 m | 0.60 | 20 | 10 | Scorch 25 | on a Sizzling target `on_hit`: +4 damage and `refresh_status: scorch` |
| Dash: Stoke Step | slide, left uppercut waist → head | 0.10/0.14/0.35 | 8 | 4.8 + launch 3.9 → 1.0–1.5 m, target rises 0.47 m | 0.50 | 15 | 8 (+12 dodge) | Scorch 15 | launcher |
| Grab: Clinch | both fists to a collar tie | 0.25/0.11/0.34 | — | — | — | — | 6 | — | connects 0.9–1.6 m root-to-root on the mirror, 0.9–1.2 m on Gusto (size matching lifts the hands toward his taller shoulders); grabs beat guard |
| Pummel: Clinch Knee | (engine pummel, no animation) | one per 0.35 s | 3 | — | — | 4 | 0 | Scorch 8 | pummel `interval: 0.35`; max 3 per hold (engine) |
| Throw fwd: Belly Toss | hip-throw forward | — | 9 | distance 2.0 → > 1.4 m (test) | — | — | — | Scorch 15 | knockdown |
| Throw back: Dump | high arc over Stoke's head | — | 8 | distance 2.0, up 3.0 → > 1.4 m (test) | — | — | — | — | knockdown |
| Throw side: Shove-off | spacing shove | — | 4 | distance 2.5 → > 1.8 m (test) | 0.6 | — | — | — | no knockdown (`stun: 0.6` keeps the shove distance) |
| Taunt: Belly Clank | chest out, clanks the belly door twice, "come on" | 1.5 s | — | — | — | — | 0 | — | +8 Hype (engine), no armor |
| A1 Steam Vent (LB) | furnace door opens, cone 2 m × 60° from the belly | effect at 0.20, 0.75 s total | 6 | 7.8 → 2.3 m push | 0.30 | 10 | 15 | Scorch 35 | `destroy_projectiles` cone 2 m / 60° at 0.20, 0.25, 0.30, 0.35 s; **cooldown 7 s** |
| A2 Stoke the Fire (RB) | crouch, crest flare, arms up | buff at 0.25, 0.6 s total | — | — | — | — | 10 | — | 4 s status `stoked`: `move_speed 1.25` (startup/recovery −20 %), `stamina_regen 0`, `dps 1` with `cannot_kill`, hook `hit_dealt → +5 Scorch`; **cooldown 12 s** |
| JUICE Meltdown (RT) | crouch, burst up with the door blown open | 0.5 s activation | 12 (pulse) | 7.5 → 2.7 m | 0.50 | 30 | — | Scorch 50 | engine: full armor 0.5 s + 0.3 s invulnerability. Pulse = area r 3 m (`class: juice`). Then `juice_state` 6 s: `armor: all_but_heavy`, hooks `hit_dealt → +25 Scorch`, `hit_dealt (cooldown 1.2 s) → scorch_patch r 1.5 m 3 s at the impact point (owner_immune)`; `end: stamina −30`, then the engine's 2 s crash (stamina regen ×0.5, speed ×0.75) = "burnt out" |

Reach: every weapon point stays ≤ 1.3 m from the root during every move (cap 1.6 m, measured by
the tests). Stamina costs match ROSTER exactly.

**Size matching** (main's CMB-09, `strike_height_follow`): when a move starts, the engine scales the
height of every chain target by target height / own height (Stoke 1.53 m, Gusto 1.84 m). Stoke's
strikes are authored against the mirror and re-aim ×1.20 against Gusto: jab, cross, hook,
Overhand and Haymaker meet his head (7 / 8.6 / 6.5 / 15.6 / 28.5 damage), the Gut Furnace his torso
(13.2). Connect ranges against Gusto: Jab 1.0–1.3 m, Cross 1.0–1.4, Hook 0.9–1.3, Overhand 1.1–1.3,
Haymaker 1.0–1.4, Gut Furnace 1.2–1.8 (root to root).

## How each ROSTER property is implemented

* **String / Finisher**: `"string": ["l1","l2","l3"]`; light windows open the cancel at the start of
  the active window (`cancel` = startup), Heavy in that window is the Gut Furnace (engine rule).
  Light, Light, Heavy lands the Gut Furnace on the mirror; Gusto (55 kg) slides out of its reach
  after the cross, so Light, Heavy is his string (both tested).
* **Side-shove + 30° turn (Lead Hook)**: `kb_dir: "side"`, `kb_side: -1` (main's corrected sign:
  +1 = attacker's left, so −1 pushes toward Stoke's right, the direction the left hook travels),
  `turn_target: 30`.
* **Armor on the Overhand** (active only) and **charged armor** (whole Haymaker startup, plus the
  engine's Light armor while the charge is held): `armor` windows with `armor_level: "lights"`.
* **Guard-crush**: `guard_break: 2.0` doubles the stamina a guarding target loses (the engine has no
  guard poise; the guard-break threshold is stamina) — measured 16 vs 6 stamina for the Overhand.
* **Conditional knock-up / bonus damage / Sizzle refresh**: per-move `on_hit` hooks with
  `{"target_status": "scorch"}` and the actions `launch`, `damage_add`, `refresh_status`.
* **Launcher** (Stoke Step): `launch: 3.9` m/s (target rises ~0.5 m).
* **Steam Vent**: `area` cone + repeated `destroy_projectiles` through the active window.
* **Stoke the Fire**: a `buff` status (data only). Self-burn uses the status `dps` with
  `cannot_kill`, so it never takes Stoke below 1 HP.
* **Meltdown**: `juice_state` with armor level, temporary hooks and an end effect (see table).
* **Throws**: `throws` table; the side throw uses the new throw `stun` key (engine extension 4).

## Engine extensions (Stoke/Gusto kit pass)

Generic, data-driven, in clearly marked "Kit extension" blocks; unit tests in
`game/src/test/core/test_kit_engine_ext.gd` (dev biped, no kit dependency).

1. **Hover lift** (`fighter.gd`, `_hover_tick()` + `sim_tick`): the `hover` effect's lift is added
   after `motor.update()` (it was overwritten, so hovers never left the ground); legs tuck while
   hovering and re-plant when the fighter is back near stance height.
2. **Zones ignore hovering fighters** (`effects.gd`, `zone_ignores()` checked first in
   `_zone_affects()`): ground patches do not tick, flinch or push a fighter with the `hovering` flag.
3. **Throw hook slot** (`fighter.gd`, `_do_throw()`): the `throw` hook context carries
   `"slot": "throw_fwd" | "throw_back" | "throw_side"`, so hooks can filter by direction.
4. **Throw stun** (`fighter.gd`, `_do_throw()`): a `throws` entry may set `"stun"` (seconds) for
   no-knockdown spacing throws.
5. **Bot hints** (`bot_brain.gd` "Kit hints", the one mechanism shared with Dredge/Dozer): the
   Stoke/Gusto keys `attack_range`, `charge_heavy {"chance", "from"}` (profile-gated), `parry_heavy`,
   `guard_max` / `dodge_for_guard`, `dash_in` / `dash_out`, `juice_when`, `taunt_when` /
   `taunt_chance`, `commit_when`, and the `when` conditions `target_down`, `target_cornered`,
   `target_closing`, `projectile_incoming`, `in_enemy_zone`, `self_juiced`, `chance`. (Bots used to
   keep the Heavy held bit set, so every bot Heavy charged to full; main's hints fix this the same way.)

## AI ("Pressure", `ai` block; bot_brain.gd "Kit hints")

`range [1.0, 1.2]` and `attack_range 1.35`: walks in and pokes with L1/L2. `commit_when:
[{"target_status": "scorch"}]`: strings into L3 and the Gut Furnace on a Sizzling target. Ability
hints (`chance 4.5` scales the skill gate `ability × 0.35` back to roughly the bot's ability stat):
Steam Vent only reactively — an enemy projectile within 4 m heading at him (80 %), or poise < 30 %
with the target within 1.8 m (60 %); Stoke the Fire only while the target is down (80 %).
`juice_when`: the target cornered (within 1.3 m of the fence) and within 3 m, he is below 25 % health
with the target within 3 m, or 25 % of the time point blank (≤ 1.8 m). `charge_heavy {"from": "pro",
"chance": 0.33}` (× skill: ~25 % of a Contender's Heavies; Journeyman and below never charge);
Heavy parry 35 % from `champion` (Headliner) up. Personality offsets: aggression +0.12,
dodge −0.04, grab +0.02.

## Tests and evidence

```powershell
& $g --headless --path game --fixed-fps 120 -- --test test_kit_f_stoke      # 13 tests (+ 3 gated: lab, showcase, balance)
& $g --headless --path game --fixed-fps 120 -- --test test_kit_f_stoke.gd::test_zz_lab --kit-lab l1@1.2,heavy@1.0:1.8:0.1
& $g --headless --path game --fixed-fps 120 -- --test test_kit_f_stoke.gd::test_zz_balance --kit-balance 24 regular
& $gui --path game --fixed-fps 120 --resolution 1600x900 -- --test test_kit_f_stoke.gd::test_zz_showcase --kit-showcase <dir>
```

Result: 13/13 pass, alone and in the full suite. The strike test drives every strike against a
standing Stoke and a standing Gusto inside its range (must connect: contact inside a hit window,
damage, stun, poise damage, Scorch build-up) and beyond it (must not), and checks for every run:
root uprightness ≥ 0.85, no segment spinning > 80 rad/s, no weapon centre inside its own trunk,
weapon points ≤ 1.6 m from the root, no cage escape. Other tests: knockback scale vs ROSTER
(±50 %) and ordering, hook shove and turn, string/finisher, charge hold (no forward drift while
holding) + armors (a Light during the Overhand's active window does not stagger, during its windup
it does), guard-crush and Sizzle knock-up, Gut Furnace Sizzle bonus, Stoke Step from a dodge,
Clinch through guard + pummel (one knee per 0.35 s) + all three throws, Steam Vent
cone/push/projectile destruction/7 s cooldown, Stoke the Fire buff/self-burn cannot kill/+5
Scorch/12 s cooldown, Meltdown activation/pulse/armor levels/+25 Scorch/patch/6 s/crash/−30
stamina, taunt (1.5 s, +8 Hype, no armor), guard and parry.

Evidence (rendered match frames, `docs/evidence/kits/`): `f_stoke_haymaker_0.png` (Haymaker
wind-up), `f_stoke_overhand_1.png` (Overhand landing), `f_stoke_gut_furnace.png`,
`f_stoke_stoke_step.png`, `f_stoke_steam_vent.png`, `f_stoke_meltdown_0.png` (JUICE pulse).

## Balance (bot vs bot, The Gullet, 1 round × 60 s, decision on health)

`test_zz_balance` (harness `bout()` / `balance()`): two `BotBrain`s that read each creature's `ai`
block through main's "Kit hints", The Gullet as merged from main (12 × 12 m, spawns 6 m apart), one
60 s round decided by KO or remaining health, spawn sides alternating, bout seeds 100+ (each mirror
also with `--kit-seed 200`). Journeyman bots never charge Heavies or parry; Contender bots charge
(~25 % / ~20 % of Heavies) and dodge/parry more. Measured after merging main 2a5beaa (8381ad3 only
changed test stepping, which these bouts do not use).

| Pairing | Bots | Bouts | Wins (first named) | KOs | Avg time | Dmg/bout | Dmg/hit | Hits/bout |
|---|---|---|---|---|---|---|---|---|
| Stoke vs Gusto | regular (Journeyman) | 40 | 22–18 (55.0 %) | 39 | 45.8 s | 74.4 vs 88.8 | 8.81 vs 3.21 | 8.4 vs 27.7 |
| Stoke vs Gusto | pro (Contender) | 24 | 9–15 (37.5 %) | 13 | 56.9 s | 61.8 vs 94.1 | 8.89 vs 3.23 | 7.0 vs 29.2 |
| Stoke mirror | regular | 24 | 18–6 (75.0 %) | 24 | 42.9 s | 106.5 vs 88.7 | 7.20 vs 6.74 | 14.8 vs 13.2 |
| Stoke mirror (seeds 200+) | regular | 24 | 15–9 (62.5 %) | 24 | 39.8 s | 102.9 vs 91.6 | 7.62 vs 6.98 | 13.5 vs 13.1 |
| Gusto mirror | regular | 24 | 6–18 (25.0 %) | 23 | 46.6 s | 71.3 vs 84.8 | 4.31 vs 4.23 | 16.5 vs 20.0 |
| Gusto mirror (seeds 200+) | regular | 24 | 15–9 (62.5 %) | 24 | 47.5 s | 80.7 vs 72.3 | 4.11 vs 4.03 | 19.6 vs 18.0 |

**Cross matchup: Stoke 22–18 over 40 Journeyman bouts (55.0 %) and 9–15 over 24 Contender bouts
(37.5 %) — inside the 35–65 % target.** Mirrors: the same kit and AI on both sides with
alternating spawns, so "first named" means nothing and the splits are seed variance — 24-bout blocks
swing widely (Gusto 6–18 with seeds 100+ and 15–9 with seeds 200+; Stoke 18–6 and 15–9 here,
12–12 / 13–11 / 9–15 in earlier blocks). Where the damage comes from (regular cross, damage per
bout, hits in 40 bouts): Stoke — Overhand 33.6 (73), Jab 13.2 (111), Gut Furnace 9.4 (37), Cross
6.0 (50); Gusto — effects 43.9 (477: Gust Bomb hits and bursts, Downdraft landings, Tailspin burst,
JUICE cone), Wing Snap 15.3 (127), Crosswind 12.4 (111), Beak Peck 8.8 (173).

History (regular cross): ROSTER damage numbers 10–0 (10 bouts, before the `ai` blocks); with the
`ai` blocks, Gusto's first damage buffs and the 2.6 m/s Overhand lunge 14–10 (24); with a Gusto
"hop over the Heavy" rule 20–4 (24, rule dropped); after main's size matching on the old 10 m
Gullet 27–13 (40: Stoke's punches re-aimed to Gusto's head, Gusto's wings to Stoke's guard), then
Crosswind 8+8 and Gust Bomb 7: 25–15, plus Overhand 12: 25–15 (40); on main's 12 m Gullet 19–21
(40); final numbers above after folding the AI into main's Kit hints.

Commands: `--kit-balance 40 regular --kit-pair f_stoke-f_gusto` (one pairing; without
`--kit-pair` it runs the cross and both mirrors), `--kit-seed 200` for another seed block.

## Deviations from ROSTER (with reasons)

* **Fist hit spheres 0.13 → 0.18 m** (body `weapons.fist_l/r.radius`, the only body edit). The fist's
  physics sphere is 0.12 m, so the hit sphere reached a target only 1 cm before the physics solver
  stopped the fist; contacts with the heavy torso then registered with ~0 closing speed and did not
  count. 0.18 m gives the contact test one tick of travel (measured: Gut Furnace connects reliably
  from 1.2 to 1.8 m instead of at scattered distances).
* Timings within ±0.04 s of ROSTER: Overhand startup 0.27 (0.28), Haymaker 0.48/0.14 (0.50/0.12),
  Gut Furnace 0.14/0.12 (0.16/0.10), Stoke Step 0.10/0.14 (0.14/0.10) — windows start where the fist
  actually reaches the target, before bodies collide.
* Gut Furnace step-in ~0.6 m (ROSTER 0.4 m) so it still lands after the jab and cross push a
  same-size target back (~0.7 m together). Gusto slides further (55 kg), see String / Finisher.
* **Overhand damage 13 → 12** (balance): with main's size matching the Overhand comes down on
  Gusto's head (×1.4) and was half of Stoke's damage in the cross matchup (27–13 over 40 bouts
  before this and Gusto's Crosswind/Gust Bomb buffs; see Balance).
* Overhand lunge 2.6 m/s (≈0.3 m step) — the earlier 3.2 m/s let it connect from 1.9 m and it
  decided the Gusto matchup (see Balance). It starts at 0.20 s: a lunge that spans the engine's
  charge hold point (0.7 × startup) keeps driving the whole time Heavy is held (an earlier version
  slid 1.2 m forward while charging and fired the Haymaker from point-blank range).
* Back throw "Dump": the engine throw is an impulse straight back, which drives the victim into
  Stoke's own body; it is thrown in a high arc over his head (`up: 3.0`) to land behind him.
* Pummels are not animated (engine); the ROSTER's 0.35 s per knee is the pummel `interval`.
* Meltdown Scorch patches: at most one per 1.2 s (hook cooldown) and they do not burn Stoke
  (`owner_immune`); the engine stacks overlapping same-element zone ticks (ELEMENTS.md says they must
  not), so a patch per hit would multiply the burn.
* Knockdown hits apply no build-up (engine resolves the knockdown before the build-up and ignores
  build-up on downed fighters), so the Haymaker's Scorch 45 does not land when it knocks Gusto down.
