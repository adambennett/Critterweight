# GUSTO (`f_gusto`) — kit

Hit-and-run showboat, Gale, avian Pipsqueak (wings are the arm chains `wing_l/wing_r`). Spec:
`docs/design/ROSTER.md` §3. Data: `game/content/core/creatures/f_gusto.json`. Tests:
`game/src/test/kits/test_kit_f_gusto.gd` (shared harness `kit_harness_stoke_gusto.gd`). Body, art
and model unchanged.

## Stats (engine keys)

| health | walk_speed | stamina | poise | dodge_distance / dodge_time | weight / power / defense | mass |
|---|---|---|---|---|---|---|
| 85 | 4.3 | 110 (regen 12) | 40 (regen 15) | 3.6 m / 0.30 s (longest) | 1.0 / 1.0 / 1.0 | 55 kg |

"Cheapest dodges": passive `gusto_light_dodges` refunds 4 of the dodge's 12 stamina (net 8; not
while juiced, when dodges are free). The stub's `dodge_speed` became `dodge_distance`.

## Move list (final numbers)

S/A/R = startup / active / recovery (s). KB = engine value (m/s on 80 kg); measured = displacement
of a standing Stoke dummy (85 kg) and damage of one clean contact from the lab runs. Stoke's boxing
stance keeps both forearms in front of his chest, so chest-height wing and foot strikes usually meet
an arm (0.4–0.5× damage) unless they come in at head height.

| Move | Weapon / path | S/A/R | Dmg | KB → measured | Stun | Poise | Stam | Build-up | Properties |
|---|---|---|---|---|---|---|---|---|---|
| L1 Wing Snap | right wing edge (+ mid-wing) sweeps from behind, horizontal at neck height, torso whips −22° → +28° | 0.09/0.10/0.17 | 5 (6.1 on Stoke's head) | 2.9 → 0.7 m | 0.25 | 5 | 4 | Gale 10 | 0.6 m lunge; reach ~1.5–1.7 m root-to-root |
| L2 Beak Peck | neck lunges forward, beak first; second peck 0.1 s later | 0.12/0.12/0.24 | 2 + 2 | 0.9 per peck → 0.25 m | 0.25 | 3 + 3 | 4 | Gale 5 + 5 | multi-hit (2): the second peck is an `on_hit` delayed strike (r 0.45 m, 0.1 s) at the first impact point |
| L3 Scissor Kick | right foot snaps from the floor up to head height | 0.16/0.10/0.30 | 7 (8 on the mirror's head, 2.4 on Stoke's forearm) | 5.6 → 1.4–2.0 m | 0.45 | 12 | 7 | Gale 18 | `on_hit` on a Winded target: launch 3.4 m/s (knock-up); connects 1.0–1.5 m on the mirror |
| Heavy: Crosswind Slash | both wings swing in from the sides and cross at chest height (left then right) | 0.24/0.13/0.39 | 8 + 8 | 3.6 → 3.5 m (with the wind) | 0.50 | 10 + 10 | 11 | Gale 15 + 15 | multi-hit (2 windows); `push` effect r 1.4 m centred 0.7 m ahead at 0.37 s (strength 6 m/s): pushes even when the wings miss (measured 0.5–1 m at 2.3 m) |
| Charged: Downdraft | crouch, wings up, leap toward the target (apex ~0.5 m, ≤2.5 m) and stomp with both feet | 0.45/0.27/0.43 | 16 | 6.2 radial + launch 4.4 → 2–3.4 m, target rises 0.5–0.7 m | 0.70 | 40 | 15 | Gale 40 | `leap` effect (to_target) + flight lunge; `on_land` area r 1.5 m: 4 dmg, Gale 15; no armor in the air (the engine's Light armor while holding the charge on the ground still applies) |
| Finisher: Tailspin | whole-body spin (one full turn, wings out at full span), drifting forward | 0.15/0.43/0.42 | 3 × 3 | 1.6 per wing pass → 2.5–2.7 m total | 0.50 | 6 × 3 | 10 | Gale 10 per hit | 2 wing passes (multi-hit) + a closing radial burst (area r 1.6 m, 3 dmg, Gale 10) that pushes everyone around; drift ~0.9 m |
| Dash: Skid Kick | low slide, foot leads at knee height | 0.10/0.12/0.30 | 6 | 5.0 → 1.25–1.9 m | 0.40 | 10 | 7 (+8 dodge) | Gale 15 | `on_hit` trip (`knockdown`) if the target is Soaked or Winded |
| Grab: Talon Snatch | hop, talons raised, wing tips clutch the shoulders | 0.24/0.14/0.34 | — | — | — | — | 6 | — | wing-tip grab: connects 0.9–1.4 m on the mirror, 0.9–1.8 m on Stoke |
| Pummel: Peck | (engine pummel) | one per 0.25 s | 2 | — | — | 4 | 0 | Gale 6 | pummel `interval: 0.25`; max 3 per hold (engine) |
| Throw fwd: Carry-and-Drop | victim launched forward in an arc, Gusto leaps after it | — | 8 | distance 2.5, up 2.0 | — | — | — | Gale 15 | knockdown; passive hook `throw (slot throw_fwd) → leap 2.4 m` |
| Throw side: Wing Fling | | — | 7 | distance 3.0 | — | — | — | — | knockdown |
| Throw back: Toss-Over | high arc over Gusto | — | 7 | distance 2.0, up 3.0 | — | — | — | — | knockdown |
| Taunt: Check the Watch | fans a wing at the crowd, then checks his wrist | 1.5 s | — | — | — | — | 0 | — | +8 Hype, no armor |
| A1 Gust Bomb (LB) | beak spits an air ball, aimed at the target | fires at 0.20, 0.5 s | 7 | 8.9 → 2.5–2.75 m | 0.20 | 8 | 9 | Gale 25 (+15 burst) | projectile 12 m/s, life 0.67 s (8 m), r 0.3, reflectable; `on_expire` area r 1.5 m: push 6 m/s, Gale 15 (a direct hit also bursts: 40 total); **cooldown 5 s** |
| A2 Hang Time (RB) | crouch, wing beat, rises 2 m | hover from 0.15 s for 1.2 s | — | — | — | — | 12 | — | `hover` (height 2.0, 1.2 s, steer 3 m/s); ground zones ignore him (engine ext. 2); **cooldown 6 s** |
| Light while hovering: Dive Peck | ends the hover, beak-first dive toward the target | 0.12/0.63/0.20 | 8 | 3.0 | 0.40 | 25 | 5 | Gale 20 | `l1@hovering` variant: `hover` duration 0 ends the hover, lunge 4 m/s during the fall |
| Heavy while hovering: Downdraft | ends the hover, stomps down | 0.15/0.60/0.25 | 16 | 6.2 radial + launch 4.4 | 0.70 | 40 | 15 | Gale 40 | `heavy@hovering` variant (no hold) |
| JUICE Hurricane Strut (RT) | crouch, wings and crest flare | 0.5 s activation | — | 9.0 cone → 2.8–3.5 m | 0.30 | 20 | — | Gale 30 | engine: full armor + 0.3 s invulnerability. Activation cone 3 m × 90°. `juice_state` 7 s: status speed ×1.35 and `dodge_cost 0`; hooks `dodge → gale_vortex zone r 1.2 m 2 s where the dodge starts (affects_owner false)`, `taunt (cooldown 1 s) → heal 5`; ending downside: the engine's 2 s crash (stamina regen ×0.5, speed ×0.75) right after the strut |

Reach: weapon points ≤ 1.2 m from the root in every move (cap 1.6 m; the long ROSTER reaches come
from lunges/leaps).

**Size matching** (main's CMB-09, `strike_height_follow`): when a move starts, the engine scales the
height of every chain target by target height / own height. Gusto's computed height is 1.84 m (crest
top), Stoke's 1.53 m, so Gusto's strikes re-aim ×0.83 against Stoke. The strike targets (wings and
legs in L1, L3, Heavy, Downdraft, Tailspin, Skid Kick, Talon Snatch and both aerials) are authored
against the mirror: they are the earlier Stoke-tuned values ×1.20, so against Stoke the contacts
are the ones validated before CMB-09, and against the mirror the wing passes at neck/head height.
The Wing Snap got a low recovery key (0.26 s) so the raised wing no longer swings back through
Gusto's own head, and the Scissor Kick a longer, slightly lower extension (1.0–1.5 m on the mirror).

## How each ROSTER property is implemented

* **Multi-hits**: Crosswind (two windows, one per wing), Tailspin (two wing passes + closing burst),
  Beak Peck (first peck + delayed second peck).
* **Wind push even on a miss**: `push` effect timed after both wings, so it never pushes the target
  out of the wings' reach before they land.
* **Winded/Soaked follow-ups**: `on_hit` hooks with `target_status: gale|brine` → `launch`/`knockdown`.
* **Downdraft**: `leap` (to the target, ≤ 2.5 m) + `on_land` area; the leap's low arc keeps the body
  inside the hover-spring band, where the horizontal drive would brake it, so a flight `lunge` carries
  the forward speed.
* **Tailspin spin**: the root's yaw is spun with keyframed `lean.y` (0° → 360°); the root spring
  follows ~15 rad/s cleanly. See Deviations for the rotation count.
* **Gust Bomb**: projectile with `aim: target` (so it hits short fighters), `on_expire` burst,
  `reflectable`.
* **Hang Time**: `hover` effect; aerial moves are the engine's `<slot>@hovering` variants; Dive Peck
  ends the hover with a zero-length `hover` effect. Zone immunity: engine extension 2 (the list of
  the kit pass's engine extensions is in `docs/kits/f_stoke.md`).
* **Carry-and-Drop**: forward throw impulse plus a passive `throw` hook filtered by
  `slot: throw_fwd` (engine extension 3) that leaps Gusto 2.4 m after the victim.
* **Hurricane Strut**: `juice_state` status (`speed`, `dodge_cost`) + temporary hooks (`dodge` →
  zone, `taunt` → heal).

## AI ("Showboat", `ai` block; bot_brain.gd "Kit hints")

`range [1.6, 2.0]`, `attack_range 1.5`: hovers outside Stoke-type reach; `dash_in` (2.3–3.4 m,
chance 0.7 × aggression): dodges in and presses Light (Skid Kick); `dash_out 0.7`: dodges back out
when inside 1.6 m. `guard_max 0.5` and `dodge_for_guard 0.6`: never holds guard longer than 0.5 s,
most guard reactions become sidesteps. `taunt_when [{"min": 3.0}, {"target_down": true}]`: taunts
when the target is > 3 m away or knocked down (`taunt_chance 0.06`, ×3 for the Punching Bag
profile). Ability hints (`chance 4.5`, see Stoke's doc): Gust Bomb when the target is closing in
from 1.6–5 m (50 %), against a perceived Heavy windup within 3 m (60 %, also checked while
defending), or occasionally beyond 2.5 m (12 %); Hang Time when standing in an enemy zone (90 %).
A "hop over the Heavy wind-up" Hang Time rule was tried and dropped (with it the cross matchup went
20–4 for Stoke). `charge_heavy {"from": "pro", "chance": 0.27}` (× skill), Heavy parry 35 % from
`champion` up. Offsets: block −0.15, dodge +0.15, ability +0.05, grab −0.04.

## Tests and evidence

```powershell
& $g --headless --path game --fixed-fps 120 -- --test test_kit_f_gusto      # 11 tests (+ 2 gated: lab, showcase)
& $g --headless --path game --fixed-fps 120 -- --test test_kit_f_gusto.gd::test_zz_lab --kit-lab l1@1.0:1.6:0.1 --kit-def f_stoke
& $gui --path game --fixed-fps 120 --resolution 1600x900 -- --test test_kit_f_gusto.gd::test_zz_showcase --kit-showcase <dir>
```

Result: 11/11 pass, alone and in the full suite. Covered: every strike vs a standing Gusto and a
standing Stoke in range and out of range with the same invariants as Stoke's suite; double peck,
three Tailspin hits + drift, wind push on a whiff, Winded knock-up, Winded/Soaked trips, Skid Kick
from a dodge, 8-stamina dodges, Downdraft leap/direct hit/landing area/hold-to-charge (no forward
drift while holding, the held Downdraft lands), Hang Time height, zone immunity, steering,
landing, cooldown and both aerial variants, Gust Bomb hit/range/burst/reflect/cooldown, Talon
Snatch through guard + pecks (one per 0.25 s) + all throws incl. the Carry-and-Drop leap, Hurricane Strut
activation/speed/free dodges/vortex/taunt heal/7 s, taunt, guard and parry.

Evidence (`docs/evidence/kits/`): `f_gusto_crosswind_1.png` (wings crossing on Stoke),
`f_gusto_downdraft_0.png` (airborne stomp), `f_gusto_hang_time_1.png` (Dive Peck from the hover),
`f_gusto_gust_bomb.png`, `f_gusto_tailspin.png`, `f_gusto_hurricane_strut.png`.

## Balance

Measured together with Stoke's (`test_kit_f_stoke.gd::test_zz_balance`); full table and history in
`docs/kits/f_stoke.md`. Final (after merging main 2a5beaa): Gusto 18–22 against Stoke over 40
Journeyman bouts (45.0 % for Gusto) and 15–9 over 24 Contender bouts; Gusto mirror 6–18 over 24
bouts and 15–9 with seeds 200+ (alternating sides, so the splits are variance). Gusto lands ~3.3×
as many hits as Stoke (27.7 vs 8.4 per bout) for about 36 % of the damage per hit (3.21 vs 8.81):
his wings and kicks mostly meet Stoke's raised forearms while Stoke's punches reach his head, and
Stoke has 110 HP to his 85. Effect damage (mostly Gust Bomb hits and bursts) is 43.9 of his 88.8
damage per bout.

## Deviations from ROSTER (with reasons)

* **Damage**: Wing Snap 4 → 5, Crosswind 6+6 → 8+8, Gust Bomb 5 → 7. Gusto's sweeping wings and
  kicks meet the raised forearms of Stoke's boxing stance first (arms take 0.4–0.5× damage in the
  engine), while Stoke's straight punches reach Gusto's head (1.4×; with main's size matching they
  re-aim to Gusto's head height); with ROSTER numbers the matchup was 10–0 for Stoke over 10 bouts,
  and 27–13 over 40 after size matching with 5 / 7+7 / 6 (see Balance).
* **Tailspin**: one full rotation instead of two. The root's upright/yaw spring (14 rad/s) lags
  ~140° behind a 2-rotation target in 0.4 s and flips direction; 1.5 rotations would end facing
  backwards. The third hit is a closing radial burst.
* **Beak Peck**: the second peck is a delayed strike at the first impact point (the neck cannot
  retract and re-approach with closing speed within 0.1 s while pressed against the target).
* **Talon Snatch** holds with the wing tips (the talons are raised visually): a grab joint on a leg
  is pulled toward the floor by the gait and tipped Gusto ~50°.
* **Downdraft** apex ~0.5 m (ROSTER "1.5 m up") so it lands within the move's 1.15 s; the active
  window covers the whole descent (0.45–0.72 s).
* **Carry-and-Drop** is a forward throw arc plus a hop after the victim (the engine cannot carry a
  thrown body).
* Ranges (L1 1.4 m, Crosswind 1.5 m, Peck 1.2 m, Kick 1.3 m) come from lunges: the wing reaches
  ~1.0 m forward from the root. Crosswind connects 1.1–1.45 m and 1.55–1.8 m on the mirror (a
  grazing wing-on-wing contact at 1.5 m is a glance) and 1.3–1.8 m on Stoke.
* Crosswind lunge is split (0.12–0.15 s and 0.17–0.32 s, 6 m/s) around the engine's charge hold
  point (0.7 × startup = 0.168 s): a lunge spanning that time keeps driving while Heavy is held, and
  the first version slid Gusto forward through the whole charge.
* Pummels are not animated (engine); the ROSTER's 0.25 s per peck is the pummel `interval`.
