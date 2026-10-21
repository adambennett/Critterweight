# SLURRY (`f_slurry`) — the Drain Wyrm · kit

Serpent **Scrapper**, element **Sludge**, trapper / zoner (ROSTER §5). Body, model and art are the
forge's; this kit authors everything Slurry does. Data: `game/content/core/creatures/f_slurry.json`.
Slurry has no limb chains: every move is joint-driven (head, body1–6, tail) plus root `lean`,
`height` and lunges, with rearing poses on the rear segments.

## Stats

| HP | Walk | Accel | Turn | Stamina | Poise | Dodge | Mass | Power / Defense |
|---|---|---|---|---|---|---|---|---|
| 100 | 3.0 m/s | 22 | 5.0 rad/s (slow turn) | 105 | 55 | 3.0 m / 0.3 s | 95 kg (body) | 1.0 / 1.0 |

## Moves (final numbers)

S/A/R = startup / active / recovery in seconds (first hit window or effect time). KB is the
engine knockback impulse (m/s, mass-scaled); "KB seen" is the measured displacement of the dummy
0.45 s after the hit in the kit test (vs the dummy named). Damage is the base before the engine's
contact-quality / hurt-part / combo scaling (melee) — effects deal it flat. Ranges are root-to-root
gaps measured in the test setup (dev_biped = tall biped dummy; Jitters = 0.9 m ball).

| Slot | Move | Weapon | S/A/R | Dmg | KB (seen) | Stun | Poise | Stam | CD | Sludge | Connects at | Properties |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| L1 | Head Butt | head + fang | 0.13/0.11/0.20 | 5 | 2.4 (0.58 m) | 0.30 | 8 | 5 | — | 12 | Jitters 0.9–1.7, dev_biped 0.9–1.5 | bows then drives the head ~1.3 m forward (3 m/s lunge), low enough to hit a 0.9 m target |
| L2 | Tail Flick | tail tip | 0.14/0.22/0.20 | 4 | 3.0 (0.65 m) | 0.25 | 5 | 4 | — | 12 | dev_biped 1.1–1.5, Jitters 0.9–1.7 | whole body spins, the tail whips in from behind at knee height |
| L3 | Fang Snap | fang + head | 0.12/0.11/0.37 | 7 | pull (−0.36 m) | 0.45 | 12 | 7 | — | 22 | Jitters 0.9–1.7, dev_biped 1.1–1.5 | bite, jerk back, **pull** (yank 0.14 s after the bite) |
| Heavy | Tail Sweep | tail tip | 0.32/0.34/0.29 | 12 | 6.0 (3.0 m on 45 kg) | 0.50 | 25 | 11 | — | 28 | Jitters 1.1–2.1, dev_biped 1.3–1.7 | ~220° spin sweep at knee height with a 3.2 m/s slide, **multi-target**, **trips Gunked targets** |
| Charged Heavy | Rear & Crash | head + fang + body_upper + coil | 0.54/0.24/0.47 | 17 | 6.2 (2.2 m) | 0.80 | 45 | 16 | — | 40 | dev_biped 1.0–2.0, Jitters 1.0–2.2 | rears up 0.24 m and slides forward, then the upper body crashes down ~1.5 m ahead; **armor vs Lights 0–0.52 s**, **guard-crush**, **puddle r 1.3 m 4 s** at the impact |
| Finisher | Venom Spit | projectile (14 m/s, 0.26 s ≈ 4 m) | 0.14/—/0.40 | 8 | 5.0 (1.28 m) | 0.50 | 15 | 9 | — | 40 | ≤ 5.0 m after a Head Butt | Light → Heavy in the cancel window; **reflectable**; guardable, never parryable |
| Dash Attack | Slither Strike | head + fang | 0.04/0.22/0.28 | 6 | 4.2 (2.4 m) | 0.35 | 10 | 7 (+dodge) | — | 15 | Jitters 2.5–3.5, dev_biped 2.0–3.0 (from a dodge) | low 6.5 m/s slither; **in a Sludge puddle: +2 dmg, +10 build-up** |
| Grab | Coil | coil + body_upper + head + fang | 0.20/0.22/0.33 | — | — | — | — | 6 | — | — | Jitters / Slurry 0.9–1.7, dev_biped 0.9–1.3 | head tilts down and wraps; pummel **Squeeze** 4 dmg + Sludge 10, one per 0.4 s (max 3) |
| Ability 1 | Sludge Lob | lobbed projectile (10 m/s, ≤ 9 m) | 0.25/—/0.35 | 6 | 4.3 (0.89 m) | 0.30 | 8 | 10 | 7 s × **2 charges** | 40 | hits at 6 m, lands ≤ 9 m | arc arrives 0.45 m above the floor at the target point; **puddle r 1.3 m 5 s** on impact/expiry; reflectable |
| Ability 2 | Drain Dive | blink (stick, 4.5 m, 0.5 s) | 0.20/0.50/0.25 | 5 (emerge) | launch 3.0 | 0.30 | 10 | 12 | 9 s | 25 | emerge circle r 1.2 m (hits at 5.0–5.8 m gaps when diving at the target) | **invulnerable while submerged**; **emerging in its own puddle refunds 3 s** |
| JUICE | Overflow | wave (line 4 × 1.6 m) + river | 0.40/—/0.20 (0.6 s activation) | 8 (wave) | 5.2 (1.33 m) | 0.40 | 20 | — | Hype 100 | 50 | wave ≤ 3.0 m | see below |
| Taunt | Hypnotic Sway | — | 1.5 s | — | — | — | — | 0 | — | — | — | +8 Hype, no armor |

Throws (from Coil): **Whip Toss** (forward) 3.0 m, 10 dmg · **Slingshot** (side) 3.0 m, 9 dmg ·
**Gulp-and-Spit** (back) 2.0 m, 9 dmg + Sludge 30 build-up. All knock down.

**Overflow (JUICE)**: 0.6 s activation with full armor and 0.3 s invulnerability (engine), Hype →
0. At 0.4 s: the ground wave (8 dmg, Sludge 50, class juice) and a **river** of three own puddles
(r 1.5 m, 8 s) at 1.5 / 4.5 / 7.5 m ahead. Then 6 s of JUICE state:
- every Light also fires **overflow_spit** (3 dmg, Sludge 10, 14 m/s × 0.26 s ≈ 4 m, aimed);
- Slurry heals **1 HP every 0.5 s** (2 HP/s) while standing in sludge (`in_zone` sludge; hook id
  `slurry_overflow_heal`);
- Gunked enemies anywhere take an extra **Overflowing** 1.5 dps debuff (= 2× Gunked damage);
- ending downside: the engine JUICE crash (2 s at 0.75× speed, half stamina regen).

Passive **slurry_dive_refund**: on `emerge`, if Slurry stands in a Sludge zone, `cooldown ability2 add −3 s`.

## How the ROSTER properties are implemented

| ROSTER property | Implementation |
|---|---|
| Fang Snap pulls 0.5 m | `pull: 0.5` (the bite never knocks back) + inline `on_hit` **delayed** circle (0.14 s, at `forward:0.6`, r 1.0, 0 dmg, `kb_dir: toward`, 2.6 m/s): the yank lands after the head has jerked back out of the way. Test: target moves 0.36 m toward Slurry. |
| Tail Sweep multi-target | one weapon window; the engine tracks hits per target. Test: two Jitters side by side both hit. |
| Tail Sweep trips Gunked targets | `on_hit {if target_status sludge → knockdown}`. Test: knockdown only when pre-Gunked. |
| Rear & Crash armor during the rear | `armor [[0, 0.52]]`, `armor_level lights` (+ the engine's charge armor while held). Test: dummy jabs land, the crash still connects. |
| Rear & Crash puddle at impact | effect `zone sludge_puddle` at `forward:1.6`, r 1.3, 4 s, `owner_immune` (t 0.7). |
| Rear & Crash guard-crush | `guard_break 2.5` + `on_hit {if target_guarding → guard_crush ×2}`. Test: guard drain ≥ 30 stamina vs 5.5 for a guarded Tail Sweep. |
| Venom Spit reflectable | engine projectile default (`reflectable`). Test: a reflect flag bounces it; guard blocks it; a parry-timed press only blocks. |
| Slither Strike bonus in a puddle | `on_hit {if in_zone sludge → damage_add 2, buildup sludge 10}`. Test: +2.0 dmg and ≥ +9 build-up with a puddle under Slurry. |
| Coil grab, Squeeze pummel 4 dmg / 0.4 s | `grab` move (head tilted down so it wraps short targets) + `pummel` move with `interval: 0.4` (the shared pummel cadence field). |
| Gulp-and-Spit lands Gunked +30 | throw `buildup: 30` (engine applies the thrower's element). |
| Sludge Lob, 2 charges, puddle on impact or expiry | `charges: 2`, projectile `lob`, `range 9`, `arrive_y 0.45`, `on_expire zone sludge_puddle owner_immune` (bursts on hits too). Test: 2 shots then empty, one charge back after 7 s, two puddles. |
| Drain Dive invulnerable, emerge circle, refund 3 s | `blink dir stick 4.5 m delay 0.5` (the engine makes a submerged fighter untouchable), `on_emerge area drain_emerge`, passive `slurry_dive_refund` (new `emerge` hook event + the shared `cooldown {add: -3}` action). Test: no hits taken while submerged; travel ≤ 4.5 m; cooldown 3.0 s shorter when emerging in an own puddle. |
| Overflow river 8 m × 3 m, 8 s | three circular own puddles (zones are circles) r 1.5 m spaced 3 m. |
| Overflow: Light spits, 2× Gunked damage, heals 2 HP/s in sludge | `juice_state` hooks: `move_start move_class light → projectile`, `tick 0.5 → debuff require_status sludge (1.5 dps)`, `tick 0.5 in_zone sludge → heal 1`. Tests cover each. |
| Own puddles never hurt Slurry | every Slurry zone is `owner_immune` (ELEMENTS §7 "kit says otherwise"). Test: Slurry in its own puddle takes 0 damage while the enemy ticks. |
| Taunt 1.5 s, +8 Hype, no armor | `taunt` move 1.5 s; Hype from the engine. Test: Hype 8, interrupted by a jab. |

## AI (bots)

Personality **trapper**, written as kit hints on the shared bot mechanism (`ai` block):
aggression −0.12, block +0.08, dodge +0.04, ability +0.30, grab −0.04; `attack_range` 1.4 m;
`range` **[2.8, 5.5]** (footwork aims between 5.5 m and 2.8 m by skill) with
`range_needs_tools` — the range only holds while a Sludge Lob charge is ready, so with both lobs
on cooldown the bot closes in and fights in melee. Ability hints: **Sludge Lob** at 2.5–9 m
(chance 0.63 × 0.35 × skill per decision); **Drain Dive** within 2.6 m when its poise is below
40 % (`when: self_poise_below 0.4`), diving **away** (`stick: away`). `charge_heavy` 0.5 (× combo
skill: ~25 % of Heavies charged at regular, ~38 % at pro), `avoid_zones` (steps out of enemy
puddles). The generic bot adds Venom Spit via the string finisher and JUICE at 100 Hype.

## Verification

`& $g --headless --path game --fixed-fps 120 -- --test test_kit_f_slurry` →
`game/src/test/kits/test_kit_f_slurry.gd` (15 tests, ~45 s, **all pass**; the first checks the creature parses with zero errors). Every move connects at
its range against both dev_biped and Jitters and whiffs outside it, with damage, knockback (or
pull), stagger, Sludge build-up, active-weapon reach ≤ 1.6 m (max seen 1.53 m, Tail Flick), no
tipping (root up > 0.2), no spin-out (< 60 rad/s), no floor clipping, no cage exit, upright at
the end. Plus: guard / parry, Coil + pummels + all three throws, multi-target and Gunked trip,
armor / puddle / guard-crush, spit reflect, puddle bonus, lob charges / cooldown / puddles / owner
immunity, dive invulnerability / distance / refund, Overflow start / river / wave / spit / heal /
extra Gunked damage / end / crash, taunt, a bot smoke test and the six campaign techniques
(below). Engine extensions:
`test_kit_extensions_sj.gd`.

## Campaign techniques (ROSTER §5 technique table)

`game/content/core/techniques/slurry.json` changes this kit only through data patches, run mods and
hooks; every patch was retargeted to how the kit really implements the move, and
`test_campaign_techniques_deliver` applies each technique the way the campaign does and checks
the effect (plus `test_technique_lint.gd`: every patch hits a real field).

| Technique | Effect | How it lands on this kit | Measured |
|---|---|---|---|
| Septic Bloom | puddles 50 % larger, +2 s | run mods `zone_size ×2.25` (area) / `zone_duration_add +2`, read by every zone Slurry spawns (lob, Rear & Crash, Overflow) | Rear & Crash puddle r 1.3 → 1.95 m, 4 → 6 s |
| Lockjaw | Fang Snap pull 0.5 → 1.2 m; Coil reach 1.4 → 1.6 m | `moves.l3.pull ×2.4` **and the delayed yank's knockback ×2.4** (the yank is the kit's real pull); `moves.grab.lunge[*][2] ×1.4` (Coil's reach is its lunge; the drafted extra lunge segment overlapped the kit's own and added ~0.05 m) | pull on dev_biped 0.03 → 0.87 m, on Slurry 0.07 → 1.05 m, on Jitters 0.66 → 0.92 m from 1.6 m (stops against Slurry's body); Coil's longest grab dev_biped 1.45 → 1.65 m, Jitters 1.80 → 2.00 m |
| Blood Thinner | Gunked 1.5 → 2.25 HP/s; guard lets 35 % through | hooks only: `status_applied` (Sludge) → +0.75 dps bleed; `pre_hit_dealt` blocked hit on a Gunked target ×1.4 | bleed only with the technique; blocked Head Butt chip ×1.40 |
| Grease Trap | enemies in Slurry's puddles dodge −40 %; Slurry +15 % speed in any Sludge zone | Greased status merged into the lob puddle, the Rear & Crash puddle **and the three Overflow puddles** (added); `tick` hook for the glide | all five puddle sources Grease; an enemy in a puddle is Greased, Slurry is not; Slurry glides in Sludge |
| Double Dip | lob charges 2 → 3; emerge 5 → 9 dmg, r 1.2 → 1.6 m | `ability1.charges +1`, `blink.on_emerge[type=area]` damage / radius | 3 charges, 9 dmg, r 1.6 m |
| Hardened Arteries | poise 55 → 80; no dive refund, no Overflow self-heal | the kit tags the refund passive `slurry_dive_refund` and the heal hook `slurry_overflow_heal`; the technique removes both by id | poise 80, both gone (the base kit keeps them) |

## Evidence (GUI captures, the_gullet, vs Jitters)

- `docs/evidence/kits/f_slurry_l1_head_butt.png` — Head Butt impact
- `docs/evidence/kits/f_slurry_heavy_tail_sweep.png` — Tail Sweep, tail swinging through Jitters
- `docs/evidence/kits/f_slurry_charged_rear.png` — the rear (S-curve tell)
- `docs/evidence/kits/f_slurry_charged_crash.png` — the crash landing on Jitters
- `docs/evidence/kits/f_slurry_ability1_sludge_lob.png` — Sludge Lob glob in flight
- `docs/evidence/kits/f_slurry_juice_overflow.png` — Overflow wave and river (JUICED)

## Balance

Bot vs bot (`BotBrain` both sides, same tier), arena `the_gullet`, one round capped at 60 s (a
time-out goes to the higher health fraction), sides alternate every bout, fixed seeds. Final kit
and final bot hints, on top of the latest main. "Strike dmg/hit" counts landed strikes,
projectiles and circles; "all hits" also counts Slurry's 0.75-damage puddle ticks; Gunked
damage-over-time is extra (per bout).

| Pairing | Tier | Bouts | Wins | Win % | Strike dmg/hit | All hits dmg/hit | Gunked DoT / bout |
|---|---|---|---|---|---|---|---|
| Slurry vs Jitters | regular | 48 | 29–19 | **60 / 40** | 6.80 vs 7.24 | 3.25 vs 7.24 | 9.3 |
| Slurry vs Jitters | pro | 48 | 30–18 | **62 / 38** | 6.03 vs 6.97 | 3.46 vs 6.96 | 8.9 |
| Slurry mirror | regular | 20 | 9–11 | 45 / 55 | 6.59 vs 6.72 | 2.94 vs 2.91 | 5.7 vs 7.1 |
| Jitters mirror | regular | 48 | 22–26 | 46 / 54 | 6.63 vs 6.53 | 6.62 vs 6.52 | — |

Final kit (after the campaign-technique pass and the pad Squash fix) on top of main 7e5419f (the
regular sample is identical on 9533454); the same seeds before the pad Squash fix gave 29–19 / 28–20. A 20-bout sample carries about ±11 %
noise: the first 20 Jitters-mirror bouts alone went 6–14 (14–6 in an earlier run), so the 48-bout
mirror is the one to read. Time-outs (decided on health fraction): 1 of 48 regular, 6 of 48 pro,
none in the Slurry mirror (the zoner closes in once its lobs are on cooldown), 1 of 48 in the
Jitters mirror. Damage sources (regular cross, 48 bouts): Slurry — Sludge Lob 871, Venom Spit 492,
Gunked 447, Head Butt 439, puddle ticks 379, Rear & Crash 250, Tail Flick 126, Tail Sweep 115;
Jitters — Arc Lash 831, Static Cling 601, Pinball 508, Squash 439 (+264 landing circles, +296 pad
Squash), Slaps 475, Headbonk 186.

## Generic engine extensions this kit relies on

All data-driven, none keyed to a fighter id; unit tests in `test_kit_extensions_sj.gd`.
- `hooks.gd`: event `emerge` (a delayed blink resurfaced) — the Drain Dive refund, with the shared
  `cooldown {slot, add}` action.
- `effects.gd`: `debuff.require_status` (Overflow's extra Gunked damage), lob `arrive_y` (the glob
  arrives at body height instead of the floor).
- `fighter_motor.gd`: joints keyed by a move skip the serpent gait wave (the head stays on line).
- `bot_brain.gd`: extra optional keys on the shared kit-hint mechanism — `range_needs_tools`,
  ability `stick`, `avoid_zones` (plus the shared `attack_range`, `abilities` / `when`, `range` and
  `charge_heavy` keys).

## Deviations from ROSTER (and why)

- **String order**: L1 is Head Butt, L2 Tail Flick (ROSTER: Tail Flick first). The Tail Flick spins
  the whole body and commits Slurry's facing for ~0.4 s, a poor opener; the 0.09 s Head Butt is the
  natural jab. The bot string logic also reads slots in string order.
- **Tail Flick 0.14/0.22/0.20** (ROSTER 0.12/0.08/0.20) and **Tail Sweep 0.32/0.34/0.29** (ROSTER
  0.26/0.14/0.40): the tail is a 1.5 m whip driven by root yaw on a ragdoll, so the active window
  spans the arc it sweeps; the sweep is a ~220° spin rather than a flat 180° arc.
- **Head moves strike at ~0.8–1.0 m height** (ROSTER "chest height"): low enough to land on the
  0.9 m Jitters; against tall bipeds they hit the hips/arms. At point blank (< 0.9 m) head moves
  overshoot.
- **Damage / numbers tuned for balance**: Venom Spit 8 (9), Sludge Lob 6 dmg / 40 build-up / 7 s
  cooldown / puddle r 1.3 m 5 s (7 / 45 / 5 s / r 1.5 m 6 s). Knockback values are engine impulses
  calibrated by measurement, not ROSTER metres.
- **Drain Dive** travels 4.5 m (≤ 5 m) and is invulnerable for the full 0.5 s dive (≥ 0.4 s).
- **Overflow** activation is 0.6 s (0.5 s); the river is three r 1.5 m circles (zones are circles).
- **Gulp-and-Spit** flings the target backward, but Slurry's own head and coils (physical bodies)
  stop it after ~0.7 m: it lands at Slurry's front / side, knocked down and Gunked +30, not 2 m
  behind (a higher arc via the throw `up` field did not clear the head either).
- **Body tweak** (weapon spheres only, points unchanged so reach is unaffected): `fang` radius
  0.10 → 0.17, `head` 0.16 → 0.19, `tail_tip` 0.10 → 0.20 — Slurry's own collision capsules
  shadowed the thin spheres so strikes rarely registered.

## Known gaps

- AI does not lead lobs onto a predicted position, place puddles between itself and the target,
  pick Fang Snap for targets standing in sludge, lob *behind* targets (Headliner+) or avoid
  spitting near Scorch allies (Flare-Up awareness).
- Fang Snap's pull is knockback, so it is mass-scaled: 0.4–0.7 m on Jitters but under 0.1 m on
  heavy bodies (dev_biped, another Slurry) without Lockjaw.
- Gulp-and-Spit trajectory (above).

## Movesets (v0.9.18)

In Movesets (the default combat style, `docs/design/MOVESET_COMBAT.md` §4) Slurry fights with four
moves equipped from an eight-move pool; everything above is Classic and unchanged. Data: the
`movepool`, `loadouts` and `default_loadout` blocks of `f_slurry.json`. Effects:
`game/src/view/fx/moves/f_slurry.gd`. Tests: `game/src/test/kits/test_moves_slurry.gd`.

### The pool

| Move | Category | Input | How to use it | What it is for |
|---|---|---|---|---|
| **Venom Fangs** (basic) ★A ★B | strike | tap, tap… | Head Butt → Tail Flick → Fang Snap → Venom Spit (the 4th press); out of a dodge, Slither Strike. No cooldown. | The string that is always there; every hit builds Gunked, Fang Snap yanks the target in. |
| **Tail Sweep** | strike (heavy) | tap / hold | Tap: Tail Sweep (trips Gunked fighters). Hold to rear up (armour against light hits while rearing), release for Rear & Crash (guard-crush, sludge puddle). | The big committal hit. Not in either recommended build. |
| **Sludge Lob** ★A | projectile | tap | The v0.9.17 lob: two charges (7 s each), a puddle that Gunks for 5 s. | Zoning; puddles power Slither Strike and the Drain Dive refund. |
| **Drain Dive** ★A | utility | tap + stick | The v0.9.17 dive: untouchable for 0.5 s, comes up 4.5 m along the stick in a gooey burst; −3 s cooldown when it surfaces in its own puddle. | Escape when rushed, or engage from range. |
| **Poison Darts** ★A | volley | tap | Three darts spat 0.12 s apart from the fangs at the target (22 m/s, about 10 m): 2.6 damage and 18 Gunked each. A landed dart sticks for 2.5 s (Venom Dart: every hit the target takes builds +6 Gunked). Parryable. Cooldown 5 s, 8 stamina. | A fast poke that interrupts an approach and primes Gunked for the lobs and the string. |
| **Acid Spray** ★B | stream | hold (≤ 1.8 s) | A short, wide cone (80°, 2 m) from the jaws, a tick every 0.15 s while held: 1.6 damage, 13 Gunked, `guard_break` 3 and Corroded (no poise recovery for 1 s). Drains 12 stamina/s; the stick swings it at 2.6 rad/s. Cooldown 6.5 s, 6 stamina. | Smothering at close range: Gunked in about a second of contact, guards melt, and the target cannot get its balance back for a Coil Crush or Tail Sweep. |
| **Coil Crush** ★B | strike | tap | A 0.24 s coil-up, then a 1.3 m lunge: the unblockable wrap (4 damage) leaves the target **Coiled** for 1 s (cannot guard or dodge, speed ×0.2); three squeezes 0.26 s apart (2.2 damage, 14 Gunked, drawn in) and the crush (4.5 damage, 26 poise, thrown clear). 1.44 s in all. Cooldown 8 s, 12 stamina. | The guard-breaker: punishes turtles and Gunked targets. |
| **Shed Skin** ★B | support | tap | Untouchable from 0.04 to 0.4 s, washes off every elemental status and all build-up, slides about 1.2 m back; **Fresh Scales** for 2.5 s (build-up ×0.5, speed ×1.15). Cooldown 12 s, 10 stamina. | Shrugging off Sizzle, Jolted or Haunted, and slipping a wind-up. |

### Loadouts

* **A — Venomous** (default): Venom Fangs, Poison Darts, Sludge Lob, Drain Dive. *Poke and dive*:
  darts and lobs at range prime Gunked and lay puddles, Drain Dive gets out when rushed (refunded in
  its own puddles), Fang Snap and Slither Strike punish whoever wades in.
* **B — Swamp**: Venom Fangs, Acid Spray, Coil Crush, Shed Skin. *Close in, smother, squeeze*: the
  spray Gunks and corrodes, Coil Crush squeezes through any guard, Shed Skin answers statuses and
  wind-ups on the way in.

### Styles (drills)

| Move | Style | What changes |
|---|---|---|
| Venom Fangs | Spitting Cobra | the Venom Spit sprays three half-strength globs in a 24° fan |
| | Barbed Fangs | Fang Snap yanks twice as hard; Head Butt and Fang Snap build ×1.5 Gunked |
| Tail Sweep | Quick Coil | rears up into Rear & Crash in half the time |
| | Undertow | every Tail Sweep trips, Gunked or not; its wind-up is 15 % slower |
| Sludge Lob | Triple Gland | three charges; each glob ×0.75 damage, puddle ×0.8 radius |
| | Long Lob | 13 m range; the puddle lasts 8 s |
| Drain Dive | Deep Dive | 6.5 m under the floor |
| | Sinkhole | surfacing leaves a puddle (so it always refunds 3 s); the burst no longer launches |
| Poison Darts | Fan of Fangs | all three darts at once in a 24° fan, ×0.8 damage each |
| | Numbing Venom | a stuck dart also slows the target to ×0.8 speed |
| Acid Spray | Sticky Bile | the acid leaves 0.8 m sludge puddles where it lingers (one per 0.6 s) |
| | Searing Acid | a 55°, 1.7 m cone that drains guards twice as fast |
| Coil Crush | Strangler | the crush barely knocks back and Coiled lasts 1.7 s: about half a second free after the move |
| | Lunging Coil | the lunge reaches about 0.5 m further; the coil-up is 20 % slower |
| Shed Skin | Second Skin | also a 15-point shield for 2.5 s |
| | Venom Molt | the old skin bursts (3 damage, 25 Gunked) into a 1.2 m puddle where Slurry stood |

### Tips and counters

* After a dart volley, keep hitting: while a dart is stuck, every hit builds 6 more Gunked. Against
  Slurry, sidestep the burst or guard it; a parry timed on the first dart destroys it and staggers
  Slurry out of the rest.
* Acid Spray reaches 2 m and turns at 2.6 rad/s: back out of it or dodge to the side. Guarding only
  melts the guard (and Gunked makes guarding cost more).
* Coil Crush ignores guards, not dodges or counters: the coil-up is a clear 0.24 s tell, a counter
  stance (Anchor Drop, Toll) answers the wrap, and a whiff leaves Slurry stuck for about a second.
  Hitting Slurry during the squeeze ends the hold.
* Shed Skin has a 12 s cooldown: bait it out, then apply the status.

### How it is built

| Move | Engine features |
|---|---|
| Poison Darts | one projectile effect with `every 0.12`, `until 0.3` (three firings on the move clock; `count` would also multiply the darts of every firing), `aim: target`, `parryable`, `status` Venom Dart with `hit_buildup {sludge: 6}` |
| Acid Spray | `hold: sustain`, `sustain [0.26, 0.56]` (the loop sweeps the head side to side), `max_hold` 1.8, `drain` 12, `aim.turn_rate` 2.6; a cone area `every 0.15` `until: release` carrying the Corroded status (`poise_regen` 0) |
| Coil Crush | melee wrap with `unblockable`, `pull` 0.6 and an inline `on_hit` → `status` Coiled (`no_guard`, `no_dodge`, `speed` 0.2); squeezes: an area `every 0.26`, `count 3`, `unblockable`, `kb_dir: toward` (repeat ticks: 30 % hype, no stamina refund, at most one stun per 0.5 s, so the 0.26 s spacing lets the first and third squeezes re-stun and the hold has no gap before the crush); crush: an area with `kb_dir: forward`. The effects stop if Slurry is interrupted. |
| Shed Skin | `invuln [[0.04, 0.4]]`, `cleanse`, a `buff` (Fresh Scales: `buildup_received` ×0.5 for every element, `speed` 1.15) and a backward `dash` (`speed` −7.5, `evade`) |

### Effects (`f_slurry.gd`)

* **Poison Darts**: venom wells up in the fangs while Slurry rears back; each spit puffs green
  droplets. A dart is a glossy black needle with a glowing venom bead at the tip and Slurry's pink
  barb at the tail, trailing a fine mist; a landed dart sticks in the victim's body on Slurry's side
  and rides it for 2.5 s (three at most per fighter), then works loose.
* **Acid Spray**: acid bubbles gather at the jaws; while held, a flat, wide fan of acid pours from
  the jaws, follows the head as it hoses side to side, is exactly as wide as the cone and meets the
  floor at its reach; each tick throws droplets and gobs that rain down and hiss, and the true
  footprint flickers. Released, it dribbles off; cut off, it dies with the move.
* **Coil Crush**: goo is wrung out of the body during the coil-up; the wrap winds thick, glossy
  sludge coils up the victim (sized to its girth) that ride it, clench on every squeeze and fly
  apart in a sludge wave on the crush. Knocked out of the move, Slurry lets go; a whiff wrings only
  a little goo out of the air.
* **Shed Skin**: the old skin stays standing in Slurry's exact pose (a translucent shell over every
  body part), sags and flakes away; a slick smear marks the slip; the fresh scales gleam while they
  last.
* Effects quality: particles come from the shared presets (scaled down at Low); darts, coils, the
  spray and the husk are combat cues and always draw, trails and gleams are skipped at Low.
  Reduce flashing dims the venom glow and the spray.

### Bots

`ai` hints per move (bot_brain `_moves_think`): Poison Darts at 2.2–8.5 m when the target closes
in or stands beyond 3.2 m; Acid Spray within 1.9 m, held 0.8–1.6 s and kept on the target; Coil
Crush at 0.4–1.9 m on a Gunked or cornered target, when Slurry's own poise is low, or now and then;
Shed Skin reactively against a wind-up within 2.2 m, in an enemy zone, or at low poise. Sludge Lob
and Drain Dive keep their v0.9.17 hints. (The bot conditions have no "I carry a status" test, so
bots cannot yet use Shed Skin as a cleanse on purpose.)

### Tests

`test_moves_slurry.gd` (12 tests, all pass): the pool, both loadouts and every style patch (each
patch hits a real field and the drilled creature still parses); a duel per move against Dredge
(the dart burst's spacing, hits, attribution, sticking, extra Gunked and parry; the spray's ticks
while held, Gunked, Corroded, stamina drain, stop on release and stick steering; Coil Crush through
a held guard: Coiled, three squeezes, the crush, a whiff's commitment; Shed Skin's cleanse,
invulnerability, slip and halved build-up; the string, the lob, the dive and the charged heavy);
and the effects kit headless (registration, darts that fly, stick, ride and clean up, the spray's
life and width, coils that clench, ride, burst and let go, the husk, Low quality, Reduce flashing).

Known gap: `test_kit_f_slurry.gd` (the Classic coverage above) builds its fights through
`kit_sj_helpers.duel()`, which sets no `combat` rule, so they run in Movesets; there the Heavy input
is Poison Darts, the per-row light strings do not reach the pool's string, and cooldowns live in
loadout slots (`m3`, `m4`). Until that shared helper pins `"combat": "classic"` (as
`TestCase.make_sim` does for the pre-v0.9.18 tests), 7 of its 15 tests fail.
