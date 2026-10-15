# KID LAMPREY — the Gutter Rookie (`npc_kid_lamprey`)

A lamprey in a hoodie, hood always up, a ring of teeth where a face should be: cocky out loud,
insecure underneath. NPC only (`"npc_only": true`): the tutorial's sparring partner
(`game/src/tutorial/tutorial.gd` `PARTNER`) and the Ring Sparring opponent. Fair and readable — every
attack is telegraphed, nothing is unblockable, his best tricks are punishable.

- Data: `game/content/core/creatures/npc_kid_lamprey.json` (body, moves, throws, abilities, JUICE,
  passives, `ai`, `audio`, `art`).
- Model: skinned, forged from `tools/forge/defs/creatures/npc_kid_lamprey.js` (`node tools/forge/forge.js`)
  to `game/assets/models/creatures/npc_kid_lamprey.glb` — 9 000 triangles, 7 658 vertices, 515 KB,
  materials cloth / eye / skin / team; gore piece: a tooth.
- Tests: `game/src/test/kits/test_kit_npc_kid_lamprey.gd` (shared harness
  `game/src/test/kits/npc_kit_case.gd`).

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game --fixed-fps 120 -- --test test_kit_npc_kid_lamprey             # kit tests
& $g --headless --path game --fixed-fps 120 -- --test test_kit_npc_kid_lamprey.gd::test_balance --balance   # 20-bout tables
& $g --headless --path game --fixed-fps 120 -- --test test_kit_npc_kid_lamprey.gd::test_zz_report_ranges --kit-report --kit-target f_dredge
& $g --headless --path game --fixed-fps 120 -- --test test_kit_npc_kid_lamprey.gd::test_zz_string_contacts --kit-string
```

## Body

Biped, 13 segments, ~60 kg, 1.41 m (hood top), root `pelvis` (hover 0.55): `chest`, `head` (hood +
sucker mouth), `uarm_l/farm_l`, `uarm_r/farm_r` (sleeves, chains `arm_l/arm_r`), `thigh_*/shin_*`
(sneaker boxes, chains `leg_l/leg_r`), and an eel tail `tail1 → tail2` hanging behind. Weapons
`fist_l/fist_r` (r 0.12), `mouth`, `hood`, `shoulder_l/r`, `body`, `tail_tip`. Stance: sleeves up at
the chin, slight hunch; guard: forearms over the hood. Probe (`--probe stand/walk`): upright 1.000 / ≥
0.995 walking, head 1.09 m, max |ω| 3.8 rad/s walking.

## Stats

| health | walk | accel | turn | stamina | poise | dash | power / defense / weight |
|---|---|---|---|---|---|---|---|
| 80 | 3.5 m/s | 30 | 10 rad/s | 100 (regen 12) | 45 (regen 15) | 3.0 m, 0.3 s | **0.72** / 1 / 1 |

`power` 0.72 scales every hit he lands (the table below lists the nominal damage; see Balance).

## Move list (final numbers)

S / A / R = startup / active / recovery (s) from the hit windows. Damage is nominal (× power 0.72,
then the engine scales by closing speed, contact cleanliness and the struck part).

| Slot | Move | S / A / R | Dmg | KB | Stun | Poise | Stam | Properties |
|---|---|---|---|---|---|---|---|---|
| L1 | Sleeve Jab | 0.07 / 0.15 / 0.14 | 4 | 1.5 | 0.25 | 5 | 4 | low, flat body jab chambered at the belly (see Heights); lands 0.9–1.0 m root-to-root vs Stoke, misses at 1.35 |
| L2 | Sleeve Cross | 0.09 / 0.16 / 0.17 | 5 | 1.9 | 0.30 | 8 | 5 | mirrored low cross with a chest twist; lands 1.0–1.2 m in the string |
| L3 | Hood Butt | 0.18 / 0.16 / 0.24 | 7 | 3.2 | 0.40 | 12 | 7 | lunging hood/mouth butt (joint-driven), shoves — ends the string; lands 0.9–1.6 m, misses 2.3 |
| Heavy | Big Swing | 0.32 / 0.16 / 0.38 | 11 | 4.0 | 0.55 | 22 | 12 | looping overhand hook to the body; lands 1.0–1.2 m, misses 1.65; hold to charge |
| Charged | Showboat Haymaker | 0.38 / 0.20 / 0.42 | 16 | 5.8 | 0.70 | 40 | 16 | wind-up wiggle, **armor vs lights 0–0.42 s**; obvious and punishable |
| Finisher | Gutter Uppercut | 0.10 / 0.17 / 0.35 | 9 | 2.6 | 0.50 | 18 | 10 | Heavy inside the string's cancel window; launches (~0.5 m lift); lands 1.0–1.2 m |
| Dash attack | Slippery Slide | 0.04 / 0.26 / 0.20 | 6 | 3.6 | 0.40 | 12 | 7 | shoulder slide off a dodge; lands 1.6–2.0 m, misses 3.2 |
| Grab | Latch | 0.18 / 0.14 / 0.30 | — | — | — | — | 6 | mouth + both fists, lunge 2.2 m/s |
| Pummel | Rasp | every hit | 3 | — | — | — | — | each pummel heals him 1 (passive `rasp`) |
| Throws | fwd / back / side | — | 8 / 7 / 4 | 2.2 / 2.0 / 2.5 m | — | — | — | fwd and back knock down, side does not |
| Taunt | Rematch! | 1.5 s | — | — | — | — | 0 | fists up, hood bob, +Hype; no armor |
| A1 (7 s) | Latch Lunge | 0.32 / 0.20 / 0.38 | 7 | 2.6 | 0.45 | 14 | 10 | 6 m/s lunge-bite (mouth/hood) from 1.2–1.6 m; heals 2 on hit |
| A2 (10 s) | Hood Up | 0.1 → 1.2 s stance | — | — | — | — | 8 | counter stance: KB taken ×0.6, a melee hit on him triggers a 5-dmg hood snap (15 poise, 3.0 KB) |
| JUICE | Feeding Frenzy | 0.25 pulse | 8 (r 2.5) | 4.0 | 0.40 | 20 | — | pulse knocks back everyone near; 6 s state: speed ×1.15, armor vs lights, every hit he lands heals 2 (0.25 s cooldown); the shared stamina crash (−30) when it ends |

## Strike heights (CMB-09 re-aim)

Main re-aims limb strikes to the target's size (chain-target heights × target height / own height,
clamped 0.5–1.3). The Kid's string was first tuned before that, against the stub roster, with a
descending jab and a crouch dip that the re-aim then pushed onto the tops of the new crab and rhino
bodies and under Slurry's hood. Final authoring: the jab and cross are **low and flat** — chambered at
the belly (0.86–0.88 m in his rest space) and driven to 0.64–0.66 m at 0.86 m ahead — with hit windows
that open as the fist accelerates (point-blank contacts happen during the extension). Re-aimed, that
line goes under an upright guard's hands (Stoke ×1.09, Gusto ×1.3), under Slurry's hood (×1.22) and
into a crab's shell face (Dredge ×0.79) or a rhino's snout (Dozer ×0.85). The hood butt is
joint-driven and not re-aimed.

## How each property is implemented

| Property | Implementation |
|---|---|
| Readable string | L1 → L2 → L3 with cancels at the end of each active window (KidScript chains on the first cancel frame, so early cancels cut the punches short) |
| Shove / launch / stun | L3 knockback 3.2 (+lunge), Finisher `launch`, stun values in the table |
| Charged Heavy armor | `heavy.charge_time`; `heavy_charged.armor [[0, 0.42]]` level `lights` |
| Heals | `rasp` passive (`hit_dealt` + `slot pummel` → heal 1); Latch Lunge `on_hit` heal 2; JUICE state hook `hit_dealt → heal 2` (cooldown 0.25) |
| Counter stance | EffectsSystem `counter_stance` with a counter package |
| Throws | creature `throws` (fwd/back knockdown, side none) |
| NPC only | `"npc_only": true` (hidden from character select) |

## Bot behaviour (`ai` block, kit hints in `bot_brain.gd`)

`{"style": "showoff rookie", "aggression": -0.15, "block": -0.05, "grab": -0.06, "charge_heavy": 0.15,
"abilities": {"ability2": {"chance": 0.8, "when": [{"target_winding": true}]}}}` — a little timid,
blocks a little worse than his tier, rarely grabs; holds a Heavy into the Haymaker 15 % × the tier's
combo skill (Punching Bag 3 %, Journeyman 7.5 %); answers a perceived wind-up with Hood Up (reactive
kit hint; the generic logic never fires Hood Up on its own).

## Tutorial partner

The tutorial drives the Kid with its own scripted `KidScript` (it approaches to ~1.05 m root-to-root and
throws his string / Heavy / Charged Heavy on cue). `test_tutorial_partner_behaviours` runs the real
exercises against him for every roster fighter: "Hands up" (≥ 2 blocked hits of one string, ≤ 10 %
health lost) and "The read" (his Light and Heavy parried) with Stoke, Dredge, Gusto, Slurry, Jitters;
"Not there" (dodge his telegraphed Heavy, then Dash Attack) with dev_biped (the stub roster has no Dash
Attack); Dozer's snout keeps KidScript out of its fixed approach distance, so for Dozer the test checks
the Kid's string meets a guarding Dozer at 1.3 m instead (known gap below).

## Tests (`test_kit_npc_kid_lamprey.gd`)

| Test | Checks |
|---|---|
| `test_kit_is_complete_and_valid` | no creature errors, `npc_only`, every slot, no stubs, throws, light string, cooldowns, taunt 1.5 s, JUICE 0.5 s, ~60 kg, ~1.4 m, stats set, no `dodge_speed`, the Hood Up kit hint |
| `test_moves_connect_in_range_and_miss_outside` | every move lands at its near gaps vs a standing Stoke, misses at its far gap, damage within its band (× power), reach ≤ 1.6 m, upright, inside the cage |
| `test_string_shove_launch_and_stun` | string lands in order, L3 shoves, Finisher from the cancel window lifts, stun |
| `test_guard_blocks_and_parry_staggers` | guard blocks the string, the jab is parryable, parry staggers |
| `test_charged_heavy_armor_shrugs_lights` | the Haymaker lands through light hits |
| `test_abilities_cooldowns_and_counter_stance` | Latch Lunge reach/heal/cooldown, Hood Up counters |
| `test_grab_pummel_and_throws` | grab range, Rasp heals, three throws |
| `test_taunt_builds_hype` | +Hype, no armor |
| `test_juice_feeding_frenzy` | pulse, speed, heals on hit, crash |
| `test_tutorial_partner_behaviours` | the tutorial exercises above |
| `test_balance_vs_roster` | smoke (both land hits); with `--balance` the 20-bout tables below |

Result (merged with main 144efdc): 11 / 11 kit tests pass (plus opt-in aids).

## Balance

BALANCE_TABLE_PLACEHOLDER

## Evidence

GUI captures (sandbox autoplay vs Stoke, and the tutorial's "Hands up" exercise with Stoke):
`docs/evidence/kits/npc_kid_lamprey_01_fight_stance.png`, `_02_body_jab.png`,
`_03_counter_lands_first.png`, `_04_tutorial_hands_up.png`.

## Engine changes used

None specific to the Kid. His `ai` uses main's kit hints (`charge_heavy`, reactive `abilities`); the
NPC-kit engine extensions are listed in `docs/kits/minions.md`.

## Deviations and known gaps

- **Power 0.72 / health 80**: after the re-aim retune his body shots landed so reliably that he won most
  same-tier bouts; lowered so a rookie partner loses most of them.
- **Dozer in the tutorial**: KidScript's fixed ~1.05 m approach cannot get past Dozer's snout, so the
  guard/parry lessons do not start for a Dozer player (tutorial owner; the Kid's kit itself reaches a
  guarding Dozer from where the bodies meet).
- **Single matchups**: against the current roster stubs he still wins most bouts vs Jitters and takes
  decisions vs Dredge inside the 60 s test rounds (slow, few KOs); the aggregate per tier is what the
  balance test asserts.
- **Audio**: `audio.voice = "lamprey"` is authored, but `Audio.creature_audio` only reads audio blocks
  of the `creatures` kind — fine for the Kid (he is one), see minions/bosses for the gap there.
