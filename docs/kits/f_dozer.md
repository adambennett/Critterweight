# DOZER — the Shovelsnout (`f_dozer`)

Quadruped plan, Grit, Lunker. Spec: `docs/design/ROSTER.md` §4. Data:
`game/content/core/creatures/f_dozer.json`. Tests: `game/src/test/kits/test_kit_f_dozer.gd`
(shared harness `dd_kit_base.gd`).

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game --fixed-fps 120 -- --test test_kit_f_dozer
$env:KIT_BOUTS = "20"; & $g --headless --path game --fixed-fps 120 -- --test test_kit_f_dozer.gd::test_zz_balance   # mirror bouts
```

Playstyle: a charger tank. No arms: every attack is driven by the neck/head joints, root lean,
height and lunges, plus the leg chains for hoof work. Armored heavies, the best launchers, and a
steerable Bulldoze that carries victims into the cage wall.

## Stats (engine keys)

| health | walk | accel | turn | stamina | poise | dash | power / defense / weight |
|---|---|---|---|---|---|---|---|
| 130 | 3.0 m/s | 24 | 4.5 rad/s (wide turning) | 95 (regen 12) | 85 (regen 15) | 3.2 m, 0.3 s | **1.15** / 1 / 1 (140 kg body; power: see Balance) |

## Move list (final numbers)

Same conventions as `docs/kits/f_dredge.md` (S/A/R from hit windows; KB in m/s → displacement of
a 100 kg dummy).

| Move | Weapon | S / A / R | Dmg | KB m/s → measured | Stun | Poise | Stam | Grit | Properties |
|---|---|---|---|---|---|---|---|---|---|
| L1 Snout Jab | snout | 0.14 / 0.08 / 0.22 | 5 | 3.1 → 0.4 m | 0.30 | 10 | 5 | 12 | head pops up then the body thrusts 0.5 m (the snout already sits at full extension); waist height; hits ≤ 1.8 m root gap |
| L2 Hoof Stomp | fore-hoof + ground pulse | 0.19 / — / 0.30 | 5 | 2.55 → 0.6 m | 0.30 | 12 | 5 | 12 + 5 | left fore-hoof lifts ~0.6 m and stamps ~0.85 m ahead; the stomp's **pulse r 0.8 m** at the landing point delivers the hit (see deviations) |
| L3 Scoop | snout | 0.20 / 0.10 / 0.35 | 7 | up, launch 4.9 → **1.1 m knock-up** | 0.50 | 16 | 7 | 18 | snout dips to the floor and scoops up to chest height; **launcher** |
| Heavy Horn Lunge | horn, head | 0.26 / 0.12 / 0.40 | 13 | 5.8 → 1.8–2.0 m | 0.60 | 30 | 12 | 30 | head rears back, then a 0.6 m root lunge drives the horn forward-down; **armor 0–0.38 s** (startup + active) |
| Charged: Quarry Ram | horn, head, snout | 0.12 / 0.68 / 0.55 | 16 (+12% at full charge) | 7.7, launch 5.4 → ~3 m, **knock-up ~1.2 m** | 0.80 | 50 | 16 | 45 | 3 m dash at 6 m/s head-low, then a horn uppercut; **armor throughout**; **guard-crush**; turns only 1.5 rad/s |
| Finisher Gravel Toss | snout + cone | 0.18 / 0.12 / 0.45 | 10 + 3 | 6.6 side → 2.5 m | 0.60 | 25 | 10 | 25 + 20 | scoop then a sideways flick to his left; **gravel cone** 2 m × 60° (3 dmg, Grit 20) |
| Dash: Shoulder Barge | shoulders, chest, head | 0.06 / 0.20 / 0.30 | 7 | 6.4 → 2.0 m | 0.40 | 15 | 8 (+12 dodge) | 12 | 1.6 m slide with the body twisted 34° so the right shoulder plate leads |
| Grab: Snout Hook | horn, head | 0.25 / 0.12 / 0.31 | — | — | — | — | 6 | — | 1.0 m reach (grabs at 1.3 m root gap, misses 1.6) |
| Pummel: Headbutt Shake | — | every 0.4 s | 3 | — | — | — | — | 10 | `interval` 0.4 s |
| Throw fwd Launch | — | — | 10 | 3 m, up 3 (knock-up) | — | — | — | — | knockdown |
| Throw side Rake | — | — | 9 | 2.5 m | — | — | — | — | knockdown |
| Throw back Buck | — | — | 9 | 3 m, up 4.5 | — | — | — | — | tossed over his own back, knockdown |
| Taunt: Snuffle | — | 1.5 s | — | — | — | — | 0 | — | snuffles the floor, paws, sneezes; +8 Hype, no armor |
| A1 Bulldoze (8 s) | whole body | 0.30 / ≤0.88 / 0.40 | 11 | 6.0 → carried | 0.60 | 35 | 14 | 35 | paws 0.3 s, charges ≤ 6 m at 7 m/s steering ±20°/s; **armor throughout**; carries the target; **wall splat** +5 dmg +0.4 s knockdown; wall with no target → **0.6 s stagger**; 0.4 s recovery |
| A2 Dust Bowl (11 s) | zone | 0.30 / 4.0 / 0.20 | — | — | — | — | 10 | 12/s | four-hoof stomp; cloud r 2.5 m follows him 4 s: enemies inside get Grit 12/s and **no poise regen**; **enemy projectiles entering are destroyed**; Dozer has **armor vs Lights** |
| JUICE Landslide | wave line | 0.5 activation (+0.1) | 14 | 4.5 | 0.60 | 60 | — | 60 | rears up and drops: line 6 × 2 m, knockdown; 6 s: **permanent armor**, **Bulldoze cooldown 0** and **10 m range**, every Bulldoze hit drops a **boulder** (0.8 m, 40 HP, 20 s) |

## How each ROSTER property is implemented

| Property | Implementation |
|---|---|
| Body-driven moves | `joints` keys on `neck`/`head` (parent-relative eulers, kept within ±35°), root `lean`, `height`, `lunge`; `leg_fl/fr/bl/br` chain keys for paws and stomps. The engine's strike re-aim (CMB-09) only scales chain targets, so the head strikes are unaffected; the leg lifts scale with the target's height (×1.3 vs bipeds, ×0.93 vs Dredge) and the stomps still land on the floor |
| Hoof Stomp pulse | `area` r 0.8 at `weapon:hoof_fl` carrying the stomp (`class: light`, parryable) |
| Scoop launcher | `kb_dir: up` + `launch` 4.9 (measured knock-up 1.1 m on 100 kg) |
| Armor on every Heavy | `armor` windows (Horn Lunge 0–0.38 s, Quarry Ram whole move); the charge hold itself is armored vs lights |
| Quarry Ram dash + uppercut | `lunge [[0, 0.5, 6.0]]`, then neck/head pitch up; `launch` 5.4; guard-crush = `guard_break 2` + `on_hit guard_crush ×2` |
| Gravel Toss cone | `area` cone 2 m / 60°, `class: heavy`; snout hit `kb_dir: side` |
| Bulldoze | `charge` effect {speed 7, distance 6, steer 20°/s, carry, splat, wall_stagger 0.6, **recovery 0.4**} |
| Dust Bowl | follow-owner Grit `zone` with an enemy-only status {poise_regen 0} + self `buff` {armor_lights, tick hook `destroy_projectiles` r 2.5 every 0.08 s} |
| Landslide | `area` line 6 × 2 knockdown + `juice_state` {armor all, hook `ability_used ability1 → cooldown set 0`}; `ability1@juiced` variant (10 m, `on_hit` → `prop` boulder) |

## Bot behaviour (`ai` block)

Personality "linebacker": aggression +0.12, block −0.08, grab −0.04, dodge −0.06, ability +0.1.
Preferred range 1.2–1.5 m. Holds Heavy into Quarry Ram 35 % of the time (skill-scaled). Bulldoze
from 3 m when a wall is within 3 m behind the target (charge-and-splat), otherwise from 4 m, up to
6.5 m. Dust Bowl at 3.5–7 m against opponents with a projectile ability, or within 2.5 m when its
poise is below 45 % (60 % chance gate). The low turn rate (4.5 rad/s, 1.5 rad/s inside Quarry
Ram, 0.35 rad/s while pawing for Bulldoze) makes it commit to straight lines. Not modelled: the
deliberate low-tier wall-bonks and saving Scoop for Caked targets.

## Verification

`test_kit_f_dozer.gd` (all pass): completeness/no stubs/armor on both heavies; every strike
connects at its intended gaps and misses outside (L1 1.4–1.6 / 2.05, L3 1.3–1.5 / 1.95, Horn Lunge
1.5–1.7 / 2.15, Gravel Toss 1.3–1.5 / 1.95) with damage, stagger and Grit; Hoof Stomp pulse hit and
build-up, nothing at 2.1 m; string L1→L2→L3→Finisher by input; Scoop knock-up; Horn Lunge through a
crab's jab (armor) and its 0.6 m lunge; Quarry Ram via a held Heavy (3 m dash, knock-up,
guard-crush); Gravel Toss cone reach; Shoulder Barge from a dodge; grab reach, pummel interval,
three throws (Launch knock-up, Buck lands behind); Bulldoze carry + wall splat, wall-bonk stagger
~0.6 s, 6 m travel + recovery, 8 s cooldown, armor; a wall splat that KOs the carried target ends
the round cleanly (engine fix in `Fighter._finish_charge`: the round-end `celebrate()` dropped the
carry mid-call); Dust Bowl armor vs lights, Grit, poise-regen stop, cloud
following, projectile destruction, 11 s cooldown; Landslide knockdown line, Bulldoze spam
(cooldown reset), a juiced Bulldoze hit on a target 7 m away drops a boulder, permanent armor,
6 s duration; taunt; physical sanity of every move; the hook `cooldown` action; holding Heavy does
not drift; measurement table. Evidence:
`docs/evidence/kits/f_dozer_01_horn_lunge_windup.png`, `_02_horn_lunge_impact.png`,
`_03_scoop_launcher.png`, `_04_bulldoze_carry_splat.png`, `_05_quarry_ram_uppercut.png`,
`_06_landslide_rear_up.png`.

## Balance (bot vs bot, "pro", The Gullet, 1 round × 99 s)

Knob: `power` (outgoing-damage multiplier) **Dozer 1.15, Dredge 0.92** — Dozer leads with his
head (hurt 1.3) into a crab whose front is claws and shell (0.5–0.7), so equal power went 19–1 for
Dredge. The cross-matchup is run by `test_kit_f_dredge.gd::test_zz_balance` (details and tuning
history in `docs/kits/f_dredge.md`):

| Pairing | Bouts | Wins | Damage dealt (hits, per hit) | KOs | Avg bout |
|---|---|---|---|---|---|
| Dredge vs Dozer (3 seed sets, sides alternate) | 72 | Dredge 36 – 36 Dozer (50 %; sets 54 / 62.5 / 33 %) | Dredge 8226 (1361, 6.0) – Dozer 8588 (1450, 5.9) | 36 – 35 | 69 s |
| Dozer mirror, test seeds (`test_zz_balance`, side 0 – side 1) | 20 | 10 – 10 | 2340 (330, 7.1) – 2238 (270, 8.3) | 9 – 10 | 71 s |
| Dozer mirror, seeds 700 | 20 | 12 – 8 | 2349 (309, 7.6) – 2296 (295, 7.8) | 11 – 8 | 70 s |

Per bout against Dredge: 2.0 Bulldozes, 1.0 Dust Bowl, 2.0 Quarry Rams, 1.4 grabs, 0.17
Landslides, 7.4 dodges. The mirror is a short, heavy-hitting fight (7–8 damage per hit, ~70 s,
mostly KOs). Spawn side 0 has led most Dozer mirror runs (85–55 over 140 bouts across powers and
seeds; the Dredge mirror leans the other way). The cause is not identified — the kits are
identical and damage per hit is equal; a suspect is the fixed fighter update order when two
armored chargers trade — and the cross-matchup alternates sides, so its number is unaffected.

## Deviations from the ROSTER (and why)

- **Hoof Stomp hits through its ground pulse.** The fore-leg cannot swing the hoof past ~0.7 m
  ahead of the chest (a thigh swing beyond ~70° breaks the Jolt joint spring) and Dozer's own head
  keeps standing targets beyond that, so the hoof never touched a target. The pulse (r 0.8 m at the
  landing hoof) now carries the stomp's 5 dmg / 0.3 s / 12 + 5 Grit.
- **Quarry Ram active 0.12–0.80 s** (ROSTER 0.50/0.30): a target met during the 3 m dash is struck
  at full closing speed instead of being shoved along and uppercut at point-blank with no speed.
- **Horn Lunge lunge starts at 0.19 s**: the engine freezes a held heavy at 0.7 × its startup;
  an earlier lunge window made Dozer drift forward for the whole charge hold (regression-tested).
- **Bulldoze carry** lasts until the charge ends (6 m budget, ~2 m when used from > 3 m as the AI
  does) rather than a fixed 2 m.
- **Landslide boulders** drop in the charge's wake (1.9 m behind Dozer) instead of directly behind
  the target, so a static prop never spawns inside fighters; they still block movement and
  projectiles for 20 s.
- **Dust Bowl skips zone reactions** (a Grit cloud on a Brine puddle would otherwise be consumed
  by Mudbound and the ability wasted).
- **Buck** uses 3 m + extra height so the victim clears his 2.2 m body ("over his own back").
- **Shoulder Barge** also counts the head/snout: the head physically leads any forward slide.

## Known gaps

- Strikes are physical: the shell-heavy crab and low targets are often met on legs/claws
  (hurt 0.4–0.6), so damage on them is below nominal.
- Dust Bowl's projectile destruction runs as a 0.08 s tick hook (12 effect events per second
  while active).
