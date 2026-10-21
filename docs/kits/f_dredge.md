# DREDGE — the Dock Crab (`f_dredge`)

Crab plan, Brine, Absolute Unit. Spec: `docs/design/ROSTER.md` §2. Data:
`game/content/core/creatures/f_dredge.json` (moves, throws, abilities, JUICE, passives, `ai`).
Tests: `game/src/test/kits/test_kit_f_dredge.gd` (shared harness `dd_kit_base.gd`).

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game --fixed-fps 120 -- --test test_kit_f_dredge
$env:KIT_BOUTS = "20"; & $g --headless --path game --fixed-fps 120 -- --test test_kit_f_dredge.gd::test_zz_balance   # balance bouts
```

Playstyle: a grappler wall that scuttles sideways. Long, slow claws; armored slams; the best grab
reach and throws; Brine puddles that soak opponents (Soaked targets get tripped by the slam's
wave line and held by Double Clamp).

The sections up to "Known gaps" describe the Classic kit (v0.9.17, unchanged). Dredge's Movesets
move pool and loadouts are in [Movesets (v0.9.18)](#movesets-v0918) at the end.

## Stats (engine keys)

| health | walk / side walk | accel | turn | stamina | poise | dash fwd / side | power / defense / weight |
|---|---|---|---|---|---|---|---|
| 140 | 2.6 / **3.2** m/s (`side_speed`) | 22 | 5.5 rad/s | 90 (regen 12) | 90 (regen 15) | 2.2 / **3.0** m (`dodge_distance` / `dodge_side_distance`), 0.3 s | **0.92** / 1 / 1 (160 kg body; power: see Balance) |

## Move list (final numbers)

Times are startup / active / recovery (s) from the hit windows; damage is nominal (the engine
scales by closing speed, contact cleanliness and the struck part: shells 0.6–0.7, limbs 0.4–0.6,
heads 1.3–1.5). Knockback (KB) is the engine's m/s; "measured" is the displacement of a 100 kg
standing dummy (`test_zy_measure_table`), which is what the ROSTER's metres mean; "model" marks
values set from the fitted braking model (KB ≈ hitstun braking at 6.5 m/s², then full braking)
where the biped dummy's raised forearms stop the overhead slams from landing cleanly.

Heights: the engine re-aims limb strikes to the target's size (CMB-09: chain-target heights ×
target height / own height, clamped 0.5–1.3). Dredge stands 1.11 m, so the claw targets in the JSON
are authored for a same-size opponent (the tuned heights ÷ 1.3): against the 1.72 m biped dummy
(and other standard-height fighters) they rise ×1.3 to exactly the poses measured below, against
Dozer (1.20 m) ×1.08, in the mirror ×1.0. The heights quoted in this table are the biped-relative
ones.

| Move | Weapon | S / A / R | Dmg | KB m/s → measured | Stun | Poise | Stam | Brine | Properties |
|---|---|---|---|---|---|---|---|---|---|
| L1 Cutter Snip | claw_cutter | 0.16 / 0.08 / 0.22 | 5 | 2.55 → 0.6 m | 0.30 | 8 | 5 | 12 | straight snap at chest height, shoulder twist; reach 1.2 m + step (hits ≤ 1.55 m root gap, misses 1.8) |
| L2 Backhand Claw | claw_crusher | 0.20 / 0.12 / 0.30 | 6 | 2.2 side → 1.3 m | 0.40 | 14 | 7 | 14 | right→left 90°+ sweep at chest height, body twist; shoves to Dredge's left; multi-target |
| L3 Double Clamp | both claws | 0.22 / 0.10 / 0.35 | 8 | 2.6 → 1.0 m | 0.50 | 18 | 8 | 20 | pincer from ±50° meeting ~1.1 m ahead; **Clamp Hold**: +0.4 s stun on a Soaked target; vs Dozer it lands from 1.4 m root gap out (full-quality body hits at 1.5–1.7 m) |
| Heavy Crusher Slam | claw_crusher | 0.32 / 0.12 / 0.45 | 14 | 4.0 → ≈1.0 m (model; wave line alone shoves 0.8 m) | 0.60 | 30 | 12 | 30 | claw raised overhead (~1.7 m) then slammed 1.1 m ahead; armor (all) 0–0.32 s; **wave line** 3.5 m × 1 m from Dredge (4 dmg, Brine 8) that **trips Soaked** targets |
| Charged: Hull Breaker | claw_crusher | 0.55 / 0.14 / 0.60 | 17 (+12% at full charge) | 6.4 → ≈2.5 m (model) | 0.90 | 50 | 16 | 45 | longer rise, body lifts; armor 0–0.55 s; **guard-crush**; **Brine puddle** r 1.5 m 4 s at impact |
| Finisher Bilge Pump | claw_crusher | 0.17 / 0.13 / 0.50 | 10 | 6.8 radial → 2.3 m | 0.50 | 25 | 10 | 25 | clamp, squeeze, shove straight back; **wall splat** +4 dmg +0.3 s within 1 s |
| Dash: Scuttle Check | shell edge / sides | 0.06 / 0.19 / 0.30 | 7 | 6.4 → 2.1 m | 0.40 | 15 | 8 (+12 dodge) | 10 | slide on the dodge's momentum + step; out of a **side** dash: +1 dmg, ×1.25 KB |
| Grab: Clamp | claw_crusher | 0.28 / 0.12 / 0.38 | — | — | — | — | 6 | — | **1.3 m reach** (grabs at 1.45 m root gap, misses 1.8) |
| Pummel: Squeeze | — | every 0.4 s | 4 | — | — | — | — | 10 | `interval` 0.4 s, max 3 per hold |
| Throw fwd Overhead Hurl | — | — | 12 | 3 m, up 2 | — | — | — | — | knockdown |
| Throw side Swing-and-Release | — | — | 9 | 2.5 m | — | — | — | — | knockdown |
| Throw back Over-the-Shell | — | — | 8 | 2 m, up 2.5 | — | — | — | — | lands behind Dredge **facing away**, knockdown |
| Taunt: Dock Clack | — | 1.5 s | — | — | — | — | 0 | — | claws clack twice, cutter taps the floor; +8 Hype, no armor |
| A1 Tide Spit (6 s) | lobbed glob | 0.30 / — / 0.40 | 6 | 4.5 → 1.0 m | 0.30 | 8 | 10 | 40 | arc to the target ≤ 7 m at 9 m/s; **Brine puddle** r 1.2 m 5 s on impact/expiry; reflectable |
| A2 Anchor Drop (10 s) | stance | 0.15 / 2.5 / 0.30 | — | — | — | — | 8 | — | body lowers 0.2 m, claws planted; 2.5 s **armor (all)**, KB taken −50%, cannot walk, turns 90°/s; **counter**: any melee hit triggers a claw snap at the attacker (6 dmg, 20 poise, Brine 15); grabs still work |
| JUICE High Tide | both claws | 0.5 activation (+0.1) | 10 ring | 5.0 | 0.50 | 40 | — | 60 | ring r 5 m, knockdown; then the floor floods for 8 s (Brine 20/s to everyone else); walk ×1.385, throws +30%, Crusher Slam wave 5.1 m (4 m past the impact); ends with the shared 2 s crash |

## How each ROSTER property is implemented

| Property | Implementation |
|---|---|
| Asymmetric claws (cutter `arm_l`, crusher `arm_r`) | L1 = cutter; L2, heavies, finisher, grab = crusher; L3 = both |
| Strike heights vs any opponent | claw chain targets authored for a same-size (1.11 m) opponent; the engine's strike re-aim (CMB-09) scales them to the target (×1.3 vs bipeds) |
| Sideways strength | `side_speed` 3.2 (engine lerps by sideness); new stat `dodge_side_distance` 3.0 (forward 2.2) |
| Backhand multi-target | melee windows hit every fighter the sweep touches; `kb_dir: side`, `kb_side: +1` (left) |
| Clamp Hold on Soaked | L3 `on_hit` `{if target_status soaked → stun_add 0.4}` |
| Slam armor during startup | `armor [[0, 0.32]]` (level all) |
| Ground wave line, trips Soaked | `area` line 3.5 × 1 m, `class: heavy`; kit passive `pre_hit_dealt {slot: effect, move_class: heavy, target_status: soaked} → knockdown` |
| Charged Heavy via hold | `heavy.charge_time 0.9`; the engine freezes the slam's windup (armored vs lights) and switches to `heavy_charged`, whose first key matches the frozen pose |
| Guard-crush | `guard_break 2.0` + `on_hit {if target_guarding → guard_crush ×2}` (measured: > 2× the tap slam's guard drain) |
| Brine puddle at impact | `zone` `brine_puddle` r 1.5 m 4 s at `weapon:claw_crusher` |
| Bilge Pump wall splat | `splat {damage 4, stun 0.3, window 1.0}` + radial shove |
| Scuttle Check side bonus | engine flag `dodge_side` (set by sideways dodges) + `on_hit {if flag dodge_side → damage_add 1, knockback_mult 1.25}` |
| Grab 1.3 m, pummel 0.4 s | crusher reach (weapon radius 0.16); pummel `interval` 0.4 |
| Tide Spit lob + puddle + reflect | `projectile` `lob` with `on_expire` zone; `reflectable` |
| Anchor Drop | `counter_stance` (armor all, `anchored` status KB ×0.5, counter package) in a 2.95 s move with `move_mult 0`, `turn_rate 1.571` |
| High Tide ring / flood / buffs | `area` ring r 5 + `zone` r 11 (8 s, owner immune, no zone reactions) + `juice_state` status {speed 1.385, throw_distance 1.3}; `heavy@juiced` variant with the 5.1 m wave |
| Crusher Slam wave 4 m in JUICE | `heavy@juiced` (engine fix: variants of `heavy` still charge into Hull Breaker) |

## Bot behaviour (`ai` block)

Personality "patient": aggression −0.1, block +0.2, grab +0.12, dodge −0.04. Preferred range
1.25–1.6 m. Grabs Soaked targets as eagerly as guarding ones (`grab_status`). Holds Heavy into Hull
Breaker 25 % of the time (scaled by bot skill). Tide Spit only at 3–7 m (forces approach). Anchor
Drop within 2.4 m when its poise is below 40 % or when it perceives a Heavy / Charged Heavy windup
(checked even while defending). Bots throw toward the nearest wall (generic brain). Not implemented:
the "anchor spot" wall preference and tier-specific grab/wall-walk rules.

## Verification

`test_kit_f_dredge.gd` (all pass): kit completeness and no stubs; every strike connects at its
intended gaps and misses outside (L1 1.3–1.45 / 1.8, L2 1.3–1.45 / 1.75, L3 1.3–1.5 / 1.95, slam
1.25–1.35 / 1.8, finisher 1.25–1.4 / 1.85) with damage, stagger and Brine build-up; string
L1→L2→L3→Finisher by input; slam armor through a jab, wave line hit at 2.6 m and trip only when
Soaked, High Tide wave reaching 4.2 m; Hull Breaker via a held Heavy (on Dozer), puddle,
guard-crush; Clamp Hold (on Dozer at 1.5 m); Bilge Pump wall splat; Scuttle Check forward and sideways; side dash vs forward dash
lengths and the side walk speed; grab reach, pummels (with interval), all three throws (damage,
direction, back throw lands behind facing away); Tide Spit hit, puddle, 6 s cooldown, reflection;
Anchor Drop counter (melee only), armor, no walking, grabbable, 10 s cooldown; High Tide ring
knockdown, flood soaking, self-immunity, crash, speed and throw buffs; taunt Hype; every move
(whiffed) stays upright (min up > 0.85), no spin-out (< 60°), no self-clip (claw overlap ≤ rest +
8 cm), stays in the cage, weapon ≤ 1.6 m from the root; holding Heavy does not drift; measurement
table; balance bouts. Evidence (scripted `MatchScene` captures):
`docs/evidence/kits/f_dredge_01_crusher_slam_windup.png`, `_02_crusher_slam_impact.png`,
`_03_double_clamp.png`, `_04_hull_breaker_puddle.png`, `_05_high_tide_flood.png`.

## Balance (bot vs bot, "pro", The Gullet, 1 round × 99 s)

The knob is `power` (the engine's outgoing-damage multiplier): **Dredge 0.92, Dozer 1.15**.
Dredge's front is claws and shell (hurt 0.5–0.7) while Dozer leads with his head (hurt 1.3), so at
equal power every exchange favoured the crab (the first pass went 19–1). Final kits, sides
alternating every bout:

| Pairing | Bouts | Wins | Damage dealt (hits, per hit) | KOs | Avg bout |
|---|---|---|---|---|---|
| Dredge vs Dozer, test seeds (`test_zz_balance`) | 24 | Dredge 13 – 11 Dozer (54 %) | 2727 (451, 6.0) – 2828 (486, 5.8) | 13 – 11 | 72 s |
| Dredge vs Dozer, seeds 500 | 24 | 15 – 9 | 2713 (437, 6.2) – 2814 (452, 6.2) | 15 – 9 | 60 s |
| Dredge vs Dozer, seeds 900 | 24 | 8 – 16 | 2786 (473, 5.9) – 2946 (512, 5.8) | 8 – 15 | 74 s |
| **Dredge vs Dozer, all** | **72** | **36 – 36 (50 %)** | 8226 (1361, 6.0) – 8588 (1450, 5.9) | 36 – 35 | 69 s |
| Dredge mirror (spawn side 0 – side 1) | 20 | 7 – 13 | 2175 (433, 5.0) – 2421 (486, 5.0) | 4 – 8 | 94 s |

Single 24-bout sets spread from 33 % to 62.5 % for Dredge (bot noise is about ±10 points per 24
bouts), so the 72-bout total is the number to trust; the test's own seed set sits at 54 %.
Per bout in the cross, Dredge used 3.3 Tide Spits, 2.3 Anchor Drops (0.8 counters), 2.2 grabs
(0.6 throws), 0.7 Hull Breakers, 0.4 High Tides and 14.7 dodges; Dozer 2.0 Bulldozes, 1.0 Dust
Bowl, 2.0 Quarry Rams, 1.4 grabs, 0.17 Landslides and 7.4 dodges (16 Bulldoze/throw splats and 2
wall-bonks in 72 bouts).

Tuning history of the cross (Dredge – Dozer): 19–1 at equal power (first pass); 6–14 at Dredge
0.92 / Dozer 1.2 once Quarry Ram struck through its dash; 16–8 at 1.0 / 1.0 after the Horn Lunge
drift fix; 10–14 at 0.96 / 1.1; main's strike re-aim (CMB-09) then lowered Dredge's claws against
Dozer and the same powers went 45–27 (62.5 %) over 72 bouts; 0.92 / 1.15 brings it to 36–36.

Mirror: no draws and equal damage per hit on both sides, but long, tanky bouts (94 s average,
12 KOs in 20; the rest go to the decision) since both crabs block and counter. Spawn side 1 has won
every Dredge mirror run so far (33–47 over 80 bouts at several powers), while side 0 leads the
Dozer mirrors; the cross alternates sides, so this does not bias the matchup number.

## Deviations from the ROSTER (and why)

- **Crusher raised to ~1.7 m, not 2.0 m**: the arm (0.92 m) plus body lift cannot reach higher;
  the windup is still the tallest silhouette in the kit. That is against standard-height
  opponents: the engine's strike re-aim lowers the whole slam against shorter ones (~1.35 m
  windup vs Dozer, ~1.25 m in the mirror).
- **Backhand radius ~1.25 m (+ step-in)**: whole-body twists are resisted by the planted legs, so
  the arc comes mostly from the arm; it connects up to a 1.45 m root gap.
- **Body tweak**: `claw_crusher` weapon radius 0.11 → 0.16. The weapon sphere sat inside the claw's
  own collision sphere (r 0.12) and capsule (r 0.16), so a direct thrust was always stopped ~1 cm
  short and never registered. The weapon point (and therefore reach and the 1.6 m cap) is unchanged.
- **High Tide walk**: one speed multiplier (×1.385) gives 3.6 m/s forward and 4.4 m/s sideways
  (the ROSTER says 3.6 in any direction).
- **Flood zone** is a Brine zone without a zone kind, so Grit/Static zone reactions cannot delete
  the whole 8 s flood (normal Tide Spit / Hull Breaker puddles are regular `brine_puddle`s).
- **Over-the-Shell "lands facing away"** comes from the trajectory (the victim keeps its facing
  while flying over him); the engine's get-up turns it back toward its target over 0.8 s.
- **Hull Breaker armor** is "all" during startup (like the tap slam) rather than lights-only.
- **Charged Heavy timing**: the engine adds the hold (≥ ~0.55 s) before Hull Breaker's own
  0.55 s startup.

## Known gaps

- Hits are physical: against bipeds with raised forearms the overhead slams often land on the
  arms (hurt 0.4–0.5), so their damage there is lower than nominal.
- Double Clamp point-blank on Dozer (≤ 1.3 m root gap, his head already between the claws) closes
  under his chest at a glancing angle and does not register; it lands from 1.4 m out.
- The bot's wall/anchor-spot preference and tier-specific behaviours from the AI notes are not
  modelled.

## Movesets (v0.9.18)

In Movesets (the default combat style, `docs/design/MOVESET_COMBAT.md`) Dredge fights with four
equipped moves out of an eight-move pool; the Classic kit above is untouched. Data: the
`movepool`, `loadouts` and `default_loadout` blocks at the end of `f_dredge.json`. Effects:
`game/src/view/fx/moves/f_dredge.gd`. Tests: `game/src/test/kits/test_moves_dredge.gd`.

### The pool

Damage is nominal (Dredge's `power` 0.92 and the element table still apply; Brine is +15% on
Scorch). Costs are stamina at the start of the move.

| Move | Category | Hold | Cooldown / cost | How to use it | What it is for |
|---|---|---|---|---|---|
| **Claw Snap** (basic) | strike | – | – / per strike (5–10) | press again to walk Cutter Snip → Backhand Claw → Double Clamp → Bilge Pump; out of a dodge it is the Scuttle Check | the always-available string: every claw builds Soaked, the Double Clamp holds a Soaked fighter, the Bilge Pump splats on the wall |
| **Crusher Slam** (heavy) | strike | charge | – / 12 (16 charged) | tap for the slam and its 3.5 m floor wave; hold (0.9 s) for the Hull Breaker | the wave trips Soaked fighters (kit passive); the Hull Breaker crushes guards and leaves a puddle |
| **Tide Spit** | projectile | – | 6 s / 10 | at a target 3–7 m away | the v0.9.17 lob: soaks on a hit and leaves a 5 s brine puddle |
| **Anchor Drop** | counter | – | 10 s / 8 | just before a melee rush lands | the v0.9.17 stance: 2.5 s planted, armour, half knockback, every strike that lands answered with a claw snap |
| **Bubble Stream** | stream | sustain, up to 2.5 s (9 stamina/s) | 6 s / 6 | hold; the stick sweeps it at 1.9 rad/s (else it tracks the target) | a bubble from the mouth every 0.15 s, drifting ~4 m at 2.6 m/s and rising a little: each pops on contact for 1.8 damage and 9 Soaked (≈12 damage a second on a fighter who stands in it); every bubble stops the first enemy shot it touches |
| **Hydro Cannon** | blast | charge, 1.2 s (from 0.32 s in) | 9 s / 14 | hold to pump it, release to fire; a tap squirts a short jet | a line beam from his feet: 3.6 → 6 m long, 0.9 → 1.2 m wide, 7 → 18 damage, knockback 4 → 9.6 m/s plus lift, from a tap to a full charge; the recoil slides Dredge back (up to ~0.8 m); one second of recovery |
| **Whirlpool** | control | – | 11 s / 12 | at a fighter 2–4 m away | a pool 2.4 m in radius opening 1.6 m ahead for 3.5 s: the opening yanks everyone inside toward its centre (3 damage, Soaked 20), then it keeps dragging them in (≈1 m/s against a fighter standing still; walking out, Stoke still makes ≈1.7 m/s), slows them (×0.8 "Undertow"), soaks them (12 every 0.4 s) and churns (1 damage every 0.4 s); Dredge and his allies are not pulled |
| **Shell Brace** | support | – | 12 s / 10 | before a flurry, or to plant himself in someone's face | 3 s of damage taken ×0.6, knockback taken ×0.5, walk ×0.7 |

Animation: Bubble Stream gulps (claws drawn in, eyestalks back), then spreads the claws wide and
pumps them in and out while the shell bobs; Hydro Cannon cocks the crusher claw back, levels it
across his front with the cutter cradling it (the pose holds while charging), then the recoil kicks
the claw up and the shell back; Whirlpool raises both claws, stirs them left and right with a twist
of the shell, and drives them into the floor; Shell Brace clamps both claws over the eyestalks,
folds the eyestalks down and drops the shell 18 cm with a shudder.

Engine use: the bubbles are a repeating `projectile` (`every` 0.15 s, `until: release`) with
`intercept` and `burst_on_hit: false`, so their hits are throttled stream ticks (30% hype, a stun
at most every 0.5 s, no stamina refund); the cannon's beam and recoil carry `charge_scale`; the
whirlpool is a `brine_puddle` zone (fire, static and grit still react with it later) with a
negative `push_out` (a pull), `owner_immune`, `affects_allies: false`, `skip_zone_reaction` (it
always forms) and a per-tick slow status; the brace is a `buff` status.

### Loadouts

* **Tidecaller** (A, the default): Claw Snap, Bubble Stream, Hydro Cannon, Anchor Drop. Dredge as
  a zoner: the bubbles screen out projectiles and soak whoever walks through them, the cannon
  punishes from range (a Soaked fighter takes 25% more knockback and walks slower, so the full beam
  lands and throws him into the cage), and Anchor Drop answers anyone who rushes through the stream.
* **Breakwater** (B): Claw Snap, Crusher Slam, Whirlpool, Shell Brace. Dredge as a brawler:
  pull them in, brace, crush. The whirlpool drags a fighter in front of him and soaks him, the
  brace lets him take the exchange, and the Crusher Slam's wave trips the Soaked fighter for a
  Hull Breaker or a grab.

Tide Spit is in neither build: it trades the bubbles' screen for a puddle at range.

### Styles (drills)

| Move | Style | What it changes |
|---|---|---|
| Claw Snap | Pistol Shrimp | the Bilge Pump fires a 1.1 m cavitation burst at the claw (3 damage, Soaked 15) that also clips anyone beside the target |
| | Tidepool Grip | Backhand Claw and Double Clamp pull the target back in (0.4 m) instead of shoving it, so the string stays in range |
| Crusher Slam | Riptide Wave | the floor wave rolls 5 m instead of 3.5 and builds Soaked 20 instead of 8 |
| | Keelhaul | the Hull Breaker hauls its target in and always knocks it down, but comes out 12% slower |
| Tide Spit | Skipping Spit | the glob skips once off the floor before it bursts (2.4 s life) |
| | Brine Bomb | the landing bursts in a 1.6 m splash (4 damage, Soaked 30, a shove) on top of the puddle |
| Anchor Drop | Keel Over | the counter-snap knocks the attacker down |
| | Sea Wall | while anchored, enemy projectiles within 1.8 m in front (150°) are washed away |
| Bubble Stream | Froth Fan | two bubbles per puff in a 30° fan, each with 60% of the damage and Soaked |
| | Bubble Mines | bigger (0.3 m), slow (1.2 m/s) bubbles every 0.25 s that hang ~3 s and burst in a 0.9 m soaking splash when they pop on their own |
| Hydro Cannon | Wide Bore | a 40° spray cone (2.6 → 4 m deep with the charge) instead of the line, with less knockback |
| | Riptide | the beam pulls its target toward Dredge (up to 6.2 m/s at full charge) and the recoil is gentler |
| Whirlpool | Eye of the Storm | a smaller (2.2 m), weaker, 3 s pool that opens on Dredge and travels with him |
| | Geyser | when the pool closes its centre erupts: 1.4 m, 6 damage, launch 4.5, Soaked 35 |
| Shell Brace | Barnacle Crust | while braced, a hit taken from within 1.9 m is answered by a 1.5 m shard burst (3 damage, at most every 0.8 s) |
| | Hunker Down | armour against light hits and 4 s long, but he walks at half speed |

### Bots

Each new move's `ai` hint: Bubble Stream at 0.4–3.4 m, held 0.9–2 s, when a projectile is coming,
against a ranged fighter or at random; Hydro Cannon at 1.6–5.6 m, held 0.7–1.6 s; Whirlpool at
1–4 m when the target is at least 2.2 m away, ranged, or Dredge's poise is low; Shell Brace within
3 m, also as an answer to a heavy wind-up it sees (`reactive`), when hurt, or against a fighter
closing in. Claw Snap, Crusher Slam, Tide Spit and Anchor Drop are pressed by the Classic brain
through the loadout, with their v0.9.17 hints.

### Tips and counters

* Soak first: Bubble Stream or the Whirlpool make the target Soaked, which the Crusher Slam's wave
  turns into a knockdown and the Hydro Cannon into a long flight (+25% knockback).
* Against the bubbles: they are slow and the stream turns slowly, so sidestep it, circle behind
  Dredge, or wait out the 2.5 s; a guard holds but drains like any stream. Shots fired into it
  pop the bubbles instead of reaching him.
* Against the cannon and the whirlpool: the charge has only light armour and a one-second
  recovery follows the shot, so close in while he pumps or punish after; walk or dodge out across
  the whirlpool's rim (hovering fighters float over it). A braced or anchored Dredge can still be
  grabbed.

### Known limits

* The whirlpool's churn ticks go through the engine's zone damage, which carries no pool
  attribution; its opening yank does (category `control`).
* The beam's footprint is a line from Dredge's feet along his facing; it is drawn from the crusher
  claw, which the cannon pose holds just right of his centre line.
