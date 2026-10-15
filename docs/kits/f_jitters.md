# JITTERS (`f_jitters`) — the Battery Jelly · kit

Hopper **Pipsqueak**, element **Static**, trickster / disruptor (ROSTER §6). Body, model and art
are the forge's; this kit authors everything Jitters does. Data:
`game/content/core/creatures/f_jitters.json`. Six segments (body, inner coil, two stubby arms, two
antenna bulbs), no chains: slaps are arm-joint swings plus lunges, everything else is the whole
body (hops, slams, leaps) and Static effects.

## Stats

| HP | Walk | Accel | Turn | Stamina | Poise | Dodge | Mass | Power / Defense | Trait stats |
|---|---|---|---|---|---|---|---|---|---|
| 80 | 3.8 m/s | 36 | 12 rad/s | 100 | 45 | 3.4 m / 0.3 s | 45 kg (body) | **1.25** / 1.0 | `getup_speed 1.3`, `held_time 0.7` |

## Moves (final numbers)

S/A/R = startup / active / recovery (first hit window or effect time). Damage is the base before
power ×1.25 and the engine's contact-quality / hurt-part / combo scaling (melee); effects deal it
×1.25 flat. KB is the engine impulse (m/s); "seen" is the measured dummy displacement 0.45 s after the hit
in the kit test. Ranges are root-to-root gaps in the test setup (dev_biped = tall biped dummy,
Slurry = serpent).

| Slot | Move | Weapon | S/A/R | Dmg | KB (seen) | Stun | Poise | Stam | CD | Static | Connects at | Properties |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| L1 | Slap | left arm | 0.06/0.10/0.16 | 4 | 2.6 (0.50 m) | 0.20 | 4 | 3 | — | 12 | dev_biped / Slurry 0.7–0.9 | arm swings across the front with a 5.5 m/s hop-lunge (~0.8 m reach) |
| L2 | Double Slap | right arm | 0.06/0.11/0.17 | 4 | 2.6 (0.62 m) | 0.20 | 5 | 3 | — | 12 | dev_biped 0.7–0.9, Slurry 0.7–1.1 | mirrored slap, leaning 16°, 5.8 m/s lunge |
| L3 | Headbonk | body + cap | 0.14/0.32/0.12 | 7 | 4.6 (0.97 m) | 0.40 | 14 | 6 | — | 20 | Slurry 0.8–1.4, dev_biped 0.8–1.1 | 1.0 m hop into the target; **bounces back** on contact (dash −3.4 m/s) |
| Heavy | Squash | body | 0.32/0.76/0.27 | 12 (+3 Bonk) | 5.0 radial (0.97 m) | 0.60 | 28 | 11 | — | 30 | dev_biped 1.0–2.0, Slurry 1.0–2.5 | leap ≤ 2.0 m to the target, apex 0.7 m; **landing circle r 1.0 m 4 dmg Static 10** (reaches ~3 m); **Bonk +3 on a head hit** |
| Heavy (pad) | Squash | body | 0.06/1.14/0.15 | 12 (+3 Bonk) | 5.0 radial | 0.60 | 28 | **0** | — | 30 | — | used automatically while `pad_launched`: the free Squash off a Spring Pad; it starts in mid-air, so the slam stays live until the landing ~1.0–1.4 s later |
| Charged Heavy | Super Squash | body | 0.52/0.96/0.27 | 16 (+3 Bonk) | 6.5 radial + **launch 4.0** (1.7 m) | 0.80 | 45 | 15 | — | 45 | dev_biped 1.5–3.0, Slurry 1.5–3.5 | leap ≤ 3.0 m, apex 1.1 m; **landing circle r 1.6 m 6 dmg Static 20**; **guard-crush**; **knock-up**; no armor |
| Finisher | Static Cling | discharge circle | 0.14/—/0.46 | 9 | 1.2 (0.10 m) | 0.50 | 18 | 9 | — | 35 | ≤ 1.8 m after a Slap | presses in (2.6 m/s) and discharges at `forward:0.55` r 0.35; **+10 Hype if it triggers Jolted** |
| Dash Attack | Pinball | body | 0.06/0.28/0.28 | 6 | 6.0 (2.1 m) | 0.40 | 12 | 7 (+dodge) | — | 15 | dev_biped / Slurry 2.0–3.5 (from a dodge) | spinning 7 m/s charge 1.8 m; **bounces once off a wall toward the lock-on target** (~1.5 m second leg); **×2 damage when pad-launched** |
| Grab | Suction Hug | hug + both slaps | 0.14/0.18/0.30 | — | — | — | — | 6 | — | — | dev_biped 0.6–0.8, Slurry 0.6–1.0 | pummel **Zap** 2 dmg + Static 15, one per **0.25 s** (fastest; max 3) |
| Ability 1 | Arc Lash | homing orb (6 m/s, 90°/s, 1.5 s) | 0.18/—/0.30 | 6 | 3.0 (0.44 m) | 0.20 | 10 | 9 | 6 s | 45 | up to ~9 m | **slow homing**; **expiry pulse r 1.2 m 3 dmg Static 20** (never after a direct hit); reflectable |
| Ability 2 | Spring Pad | prop | 0.20/—/0.25 | — | launch 2.5 m up, 3 m fwd | 0.4 on landing | — | 8 | 7 s | — | pad at 2.2 m ahead, r 1.2, 10 s, **max 2** | launches anyone who steps on it; enemies land stunned 0.4 s; Jitters gets `pad_launched` (free Squash, ×2 Pinball) |
| JUICE | Overcharge | burst circle r 3 m | 0.42/—/0.18 (0.6 s activation) | 10 | 6.4 (2.0 m) | 0.40 | 25 | — | Hype 100 | 50 | ≤ 3.0 m | see below |
| Taunt | Jitterbug | — | 1.5 s | — | — | — | — | 0 | — | — | — | +8 Hype, no armor |

Throws (from Suction Hug): **Spit-Bounce** (forward) 2.5 m, 8 dmg · **Fling** (side) 2.5 m, 8 dmg ·
**Over-the-Top** (back) 7 dmg, an arc over Jitters' own body (1.3 m throw + 2.2 m/s extra lift ≈ 2 m)
(all ×1.25 power, all knock down).

**Overcharge (JUICE)**: 0.6 s activation with full armor and 0.3 s invulnerability (engine), Hype →
0; at 0.42 s the burst (10 dmg, Static 50, KB 6.4, r 3 m). Then 8 s of JUICE state:
- **immune to stagger from Lights** (`armor: lights` for the whole state);
- every **landing** (Squash / Super Squash / pad launches / Headbonk) pulses r 2 m: 5 dmg, Static 25;
- every **Light hit** also fires a **chain arc** to the nearest other enemy within 2 m: 3 dmg, Static 15;
- ending downside: the engine JUICE crash (2 s at 0.75× speed, half stamina regen).

Passives: **static_cling_window** (Finisher start → 0.4 s flag), **static_cling_hype** (Static
status applied while flagged → +10 Hype), **pad_pinball** (Dash Attack while `pad_launched` →
damage ×2).

## How the ROSTER properties are implemented

| ROSTER property | Implementation |
|---|---|
| Headbonk bounces back | `on_hit dash speed −3.4` (inline hook). Test: Jitters moves back ≥ 0.25 m after contact. |
| Squash leap + landing circle + Bonk | `leap distance 2.0 height 0.7 to_target ballistic` with `on_land area squash_landing r 1.0`; `on_hit {if hit_part head → damage_add 3}` (new `hit_part` condition). Test: slam + landing hit at 1.5 m, landing circle alone at 2.8 m. |
| Super Squash guard-crush, knock-up 0.8 m, landing r 1.6, no armor | `guard_break 2.5` + `on_hit {if target_guarding → guard_crush ×2}`, `launch 4.0`, `on_land area super_squash_landing r 1.6`, no `armor`. Tests: guard drain ≥ 30, dummy rises > 0.25 m, landing hit, empty armor list. |
| Static Cling +10 Hype on Jolted | passives `static_cling_window` + `static_cling_hype` (`status_applied`, element static + flag). Test: +10.0 Hype when a pre-charged dummy is Jolted by it. |
| Pinball wall bounce toward the target, ×2 from a pad | `charge` with `bounce 1, bounce_distance 2.2` (charge-bounce extension) and the shared `recovery 0.32` (the spin and hit window play out after the charge) + passive `pad_pinball`. Tests: one bounce, Jitters turns to face the target and travels > 1.1 m back; damage ratio 2.00 with `pad_launched`. |
| Fastest pummel (0.25 s) | `pummel` move `interval: 0.25` (the shared pummel cadence field). Test: 3 zaps 0.24–0.34 s apart, 2.4 dmg each. |
| Grabs on Jitters hold 30 % shorter | trait stat `held_time 0.7` (× any run `held_time_mult` mod). Test: an unescaped hold auto-throws after 1.40 s (2.00 s without the trait). |
| Knockdown recovery +30 % | trait stat `getup_speed 1.3` (× any run `getup_speed` mod, e.g. Rubber Core). Test: knockdown → up in < 85 % of the time without the trait. |
| Arc Lash homing, expiry pulse, reflectable | projectile `homing_deg 90`, `on_expire area arc_lash_pulse`, `burst_on_hit false`. Tests: hits a strafing target, no pulse after a direct hit, pulse hits a target 10.2 m away, reflect flag bounces it, 6 s cooldown blocks a second cast. |
| Spring Pad launches / stun / free Squash / max 2 | effect `prop spring_pad` (`launch_up 2.5, launch_forward 3, enemy_stun 0.4, max_active 2`) + `heavy@pad_launched` variant with 0 stamina. Tests: enemy launched > 1.2 m and stunned on landing, 3 placements leave 2 pads, Jitters bounces off its own pad and its Heavy becomes `heavy@pad_launched` at no stamina; the pad Squash slam connects at the bottom of its arc. |
| Overcharge: Light-stagger immunity, landing pulses, chain arcs | `juice_state armor lights`, hooks `land → area overcharge_pulse`, `hit_dealt move_class light → chain_arc`. Tests: no hitstun from jabs, pulse after a Squash landing, arc hits a second dummy. |
| Taunt 1.5 s, +8 Hype | `taunt` move 1.5 s; Hype from the engine. |

## AI (bots)

Personality **pest**, written as kit hints on the shared bot mechanism (`ai` block): aggression
+0.08, dodge +0.08, ability +0.20; `attack_range` 0.85 m; `range` **[0.6, 1.1]** (keeps hopping in
close). Ability hints: **Arc Lash** at 2.2–7 m (chance 1.4 × 0.35 × skill), **Spring Pad** at
1.8–4.2 m (chance 1.0 × 0.35 × skill), placed toward the target. **Squash against long windups**
(`heavy_vs_windup 0.55`: a target showing > 0.3 s of startup within 2.4 m), **Pinball in**
(`dash_in`: dodge-in + Light from 2.0–4.5 m, chance 0.7 × aggression), `charge_heavy` 0.5 and
`avoid_zones`. The generic bot adds the Static Cling finisher off Slap strings and JUICE at 100 Hype.

## Verification

`& $g --headless --path game --fixed-fps 120 -- --test test_kit_f_jitters` →
`game/src/test/kits/test_kit_f_jitters.gd` (18 tests, ~40 s, **all pass**; the first checks the creature parses with zero errors). Every move connects at
its range against dev_biped and Slurry and whiffs outside it, with damage, knockback, stagger,
Static build-up, active-weapon reach ≤ 1.6 m (max seen 0.66 m), no tipping, no spin-out, no floor
clipping, no cage exit, upright at the end. Plus: Headbonk bounce, Squash landing circle, Super
Squash launch / guard-crush / landing / no armor, Static Cling Jolt Hype, Pinball wall bounce and
pad ×2, Suction Hug zaps (cadence) and all three throws, slippery hold and quick get-up, Arc Lash
homing / pulse / reflect / cooldown, Spring Pad enemy launch + stun, max 2, own launch + free
Squash and its slam, Overcharge start / burst / armor / pulses / chain arcs / end / crash, guard
and parry (Arc Lash: block, never parry), taunt, a bot smoke test and the six campaign techniques
(below). Engine extensions:
`test_kit_extensions_sj.gd`.

## Campaign techniques (ROSTER §6 technique table)

`game/content/core/techniques/jitters.json` changes this kit only through data patches, run mods
and hooks; patches follow how the kit really implements each move, and
`test_campaign_techniques_deliver` applies each technique the way the campaign does and checks the
effect (plus `test_technique_lint.gd`: every patch hits a real field).

| Technique | Effect | How it lands on this kit | Measured |
|---|---|---|---|
| Capacitor | Hype gain +20 %; Overcharge 8 → 10 s | `juice.duration` and the `juice_state` duration ×1.25, run mod `hype_gain ×1.2` | 10 s state, ×1.2 Hype |
| Bouncy Castle | Spring Pad max 2 → 3, cooldown 7 → 5 s | `prop.max_active +1`, `cooldown ×0.714` | 4 placements leave 3 pads; 5.0 s |
| Chain Reaction | hitting a Jolted enemy leaks 10 Static to every enemy within 1.5 m | hook `hit_dealt` + `target_status static` → Static-10 circle r 1.5 m | a bystander ~1 m away gets Static 10 only with the technique |
| Rubber Core | get-up +50 % on top of the kit's +30 %; poise 45 → 60 | `stats.poise +15`, run mod `getup_speed ×1.5`; the kit's own +30 % is the `getup_speed` **stat**, so the two multiply (×1.95) — as a creature `mods` entry it was overwritten by the run value | poise 60, get-up ×1.95 |
| Head Hunter | Bonk +3 → +7; Squash leap +0.5 m, target point ≤ 2.5 m | hook slots include `heavy@pad_launched` (pad Squash hits report that slot); leap patches on both Squash variants; slam window, recovery and the two last keys shift +0.24 s so the slam stays live until the later landing | leaps 1.2 m / 2.5 m; head Bonk on Slurry 14.9 → 23.0; still connects at 2.2 m on Jitters (whiffed without the timing shift) and off a pad |
| Short Fuse | Arc Lash homing 90 → 180°/s, 2 charges; stamina regen −20 % | `homing_deg ×2`, `ability1.charges = 2`, run mod `stamina_regen ×0.8` | data checks |

Head Hunter's higher arc lands more head Bonks on most of the roster (Dozer, Dredge, Gusto, Stoke,
Slurry: 21–31 dmg) but can clip a raised arm on bipeds (dev_biped, Stoke from 2.2 m: ~4 dmg).

## Evidence (GUI captures, the_gullet, vs Slurry)

- `docs/evidence/kits/f_jitters_l1_slap.png` — Slap landing (static flash)
- `docs/evidence/kits/f_jitters_heavy_squash_air.png` — Squash leap
- `docs/evidence/kits/f_jitters_heavy_squash_impact.png` — Squash impact
- `docs/evidence/kits/f_jitters_dash_pinball.png` — Pinball impact
- `docs/evidence/kits/f_jitters_ability1_arc_lash.png` — Arc Lash orb in flight
- `docs/evidence/kits/f_jitters_juice_overcharge.png` — Overcharge burst (JUICED)

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

Final kit (after the campaign-technique pass and the pad Squash fix) on top of main 9533454; the
same seeds before the pad Squash fix gave 29–19 / 28–20. A 20-bout sample carries about ±11 %
noise: the first 20 Jitters-mirror bouts alone went 6–14 (14–6 in an earlier run), so the 48-bout
mirror is the one to read. Time-outs (decided on health fraction): 1 of 48 regular, 6 of 48 pro,
none in the Slurry mirror (the zoner closes in once its lobs are on cooldown), 1 of 48 in the
Jitters mirror. Damage sources (regular cross, 48 bouts): Slurry — Sludge Lob 871, Venom Spit 492,
Gunked 447, Head Butt 439, puddle ticks 379, Rear & Crash 250, Tail Flick 126, Tail Sweep 115;
Jitters — Arc Lash 831, Static Cling 601, Pinball 508, Squash 439 (+264 landing circles, +296 pad
Squash), Slaps 475, Headbonk 186.

## Generic engine extensions this kit relies on

All data-driven, none keyed to a fighter id; unit tests in `test_kit_extensions_sj.gd`.
- `creature_def.gd` / `fighter.gd`: trait stats `getup_speed` / `held_time` (default 1.0),
  multiplied with the run/rules mods `getup_speed` / `held_time_mult` in
  `Fighter.getup_speed_mult()` / `held_time_mult()` — slippery holds and quick get-ups that stack
  with campaign bonuses (a spawn entry replaces `Fighter.mods` values, so a kit base kept there was
  overwritten).
- `hooks.gd`: condition `hit_part` (the Bonk; main later added an equivalent one, merged).
- `fighter.gd`: charge `bounce` / `bounce_distance` (Pinball; the move then plays out through the
  shared charge `recovery`), `is_airborne()`.
- `effects.gd`: projectile `burst_on_hit` (Arc Lash pulses only on timeout), spring pads ignore
  airborne fighters (a Squash flying over a pad is not relaunched).
- `rig.gd` / `effects.gd`: leap and spring-pad option `ballistic` — the flight is not braked by
  the ground drive while the body is still within hover range of the floor (Jitters' leaps and pads
  opt in; every other airborne phase keeps the original rule).
- `bot_brain.gd`: extra optional keys on the shared kit-hint mechanism — `heavy_vs_windup` /
  `heavy_reach`, `avoid_zones` (plus the shared `attack_range`, `abilities`, `range`, `dash_in`,
  `charge_heavy`).

## Deviations from ROSTER (and why)

- **Power 1.25** (ROSTER lists no power): with 80 HP and 4-damage Lights Jitters lost every trade to
  Slurry's reach and puddles; ×1.2 on everything brought the cross matchup into 35–65 %, and ×1.25
  (with the tighter bot range) kept it there after the shared bot hints were unified.
- **Static Cling is a discharge circle** at `forward:0.55` (r 0.35) instead of a weapon hit: a body
  pressed into the target has no closing speed, so the engine's contact validation never counted it.
- **Squash / Super Squash leap heights** 0.7 m / 1.1 m (ROSTER 1.8 m / 2.5 m up): the leap effect's
  apex. A 1.8 m apex alone is ~1.2 s of airtime, far beyond the 0.30/0.14/0.40 frame budget and easy
  to walk out of; the lower arcs keep the moves at 1.35 s / 1.75 s in total.
- **Leaping moves keep the body slam live for the whole flight**: Squash 0.32/0.76/0.27, pad Squash
  0.06/1.14/0.15, Super Squash 0.52/0.96/0.27, Headbonk 0.14/0.32/0.12 (ROSTER 0.30/0.14/0.40,
  0.50/0.16/0.50, 0.16/0.12/0.30), because where the body comes down depends on how the target moves.
- **Knockback** values are engine impulses (m/s) tuned by measurement, not ROSTER metres.
- **Arc Lash flies ≈ 9 m** (6 m/s × 1.5 s); the ROSTER's "range 7 m" contradicts its own speed and
  lifetime — speed and lifetime were kept.
- **Spring Pad hover**: no separate hover state; the 2.5 m launch arc itself is the air time, and the
  free Squash comes from the `pad_launched` flag.
- **Overcharge landing pulses** fire on the engine's `land` event (leaps, pad launches, Squash and
  Headbonk landings), not on every locomotion hop of the hopper gait; the 1.5× inflation is not
  shown (cosmetic, model scale is view-side).
- **Pinball second leg**: `bounce_distance 2.2` budget ≈ 1.5 m of actual travel, because the
  rig first has to reverse its momentum after the wall.
- **Mirror note**: the Squash Bonk (+3 on head hits) never triggers against another Jitters (no
  head segment) — by design of the body.
- **Body tweak** (weapon spheres only): `slap_l` / `slap_r` radius 0.10 → 0.13 so the stubby arms'
  slaps register against thin limbs; points unchanged.

## Known gaps

- ROSTER technique details the campaign data does not carry: Bouncy Castle's "allies launched from a
  pad get 0.5 s evasion" (the spring pad has no ally option) and Chain Reaction as a per-second leak
  (it is an on-hit leak). Both are technique-content choices outside this kit.

- AI does not place the pad *between* itself and the target to bait, seek crowds in FFA / horde, or
  place pads under knocked-down enemies (Headliner+).
- Overcharge 1.5× scale and Coil-brightness-equals-Hype are visual (view) features, not authored here.
