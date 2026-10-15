# Minions — Scrapling, Scrapling Pelter, Blister

Spec: `docs/design/ENEMIES_BOSSES.md` §1. NPC-only creatures (`"npc_only": true`) for Chum Rush waves,
campaign encounters (`game/content/core/encounters/minion_loadouts.json` patches these bases) and
boss arenas. Data: `game/content/core/minions/npc_scrapling.json`, `npc_scrapling_pelter.json`,
`npc_blister.json`. Bodies/art were authored with the content (see `docs/CREATURES.md`); these kits
fill the movesets, abilities, passives and AI.

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game --fixed-fps 120 -- --test test_kit_minions          # minion kits (14 tests + aids)
& $g --headless --path game --fixed-fps 120 -- --test test_kit_npc_extensions   # engine extensions (6 tests)
& $g --headless --path game --fixed-fps 120 -- --test test_kit_minions.gd::test_zz_report_ranges --kit-report
```

## Scrapling (`npc_scrapling`) — pipe, bin lid, bad attitude

Biped, 8 segments, 40 kg, 0.97 m. Health 30, poise 20, walk 3.2 m/s, stamina 60, dash 2.0 m.

| Slot | Move | S / A / R | Dmg | KB | Stun | Poise | Stam | Notes |
|---|---|---|---|---|---|---|---|---|
| L1 | Pipe Swing | 0.30 / 0.16 / 0.44 | 5 | 2.0 | 0.35 | 10 | 5 | body-twisting overhand with the pipe (lean yaw twist, lunge 3.6 m/s); lands 0.6–1.0 m vs Stoke, up to 1.2–1.4 m vs short/low bodies |
| L2 | Lid Bash | 0.25 / 0.11 / 0.39 | 3 | 4.4 | 0.30 | 8 | 6 | shoves with the lid (0.8–1.6 m push); lands 0.6–1.2 m |
| Heavy | Pipe Smash | 0.45 / 0.15 / 0.57 | 8 | 3.6 | 0.50 | 18 | 8 | two-handed overhead smash; lands 0.6–1.0 m |
| Dash attack | Bin Rush | 0.02 / 0.26 / 0.17 | 3 | 3.6 | 0.30 | 8 | 5 | lid-first charge; lands 0.8–1.8 m |
| Grab | Scrap Hug | 0.12 / 0.18 / 0.30 | — | — | — | — | 5 | short reach |
| Pummel | Can Knock | — | 2 | — | — | — | — | |
| Throws | fwd / back / side | — | 5 / 4 / 3 | 1.6 / 1.4 / 1.8 m | — | — | — | weak |
| Taunt | Lid Clang | 1.2 s | — | — | — | — | 0 | lid on pipe |
| A1 (4 s) | Lid Up | 1.8 s | — | — | — | — | 4 | raises the lid: status `lid_up` 1.5 s with **guard_arc 120°, guard_absorb 0.9** — hits from the front 120° are blocked (90 % absorbed) while it keeps acting; from behind it is open (turn rate 1.0 while raised) |
| Passive | Scrap projectile | — | 6 | 3.0 | 0.3 | 20 | — | a thrown Scrapling becomes a projectile: 0.45 s after the throw a 1 m burst at its landing spot, **credited to the thrower** (hits the thrower's enemies, knockdown) |

String L1 → L2. AI (`ai`): `{"style": "pack", "pack": 2, "pack_ring": 2.2, "pack_guard": "ability1",
"ally_ko_flinch": 0.5, "aggression": 0.05, "dodge": -0.08, "grab": -0.12}` — at most two pack members
attack one target; the rest circle at 2.2 m toward its flank and raise the lid when it swings at them;
a Scrapling within 3 m of a knocked-out ally freezes for 0.5 s.

Clean hits to kill one (standing, `test_scrapling_dies_in_a_few_clean_hits`): reference biped
(`dev_biped`, power 1) **2 clean lights** (+ chip; dead in 6 s) or **1 clean heavy**; Kid Lamprey (power
0.72) kills one in 16 s of lights / 12 s of heavies; Dredge's and Dozer's scripted light streams do not finish one in
20 s (their scripted lights mostly knock it down and then hit it on the floor).

## Scrapling Pelter (`npc_scrapling_pelter`) — the ranged variant

`"extends": "npc_scrapling"` + `npc_only`. Adds A2 **Bolt Toss** (cooldown 2 s, 1.0 s move): at 0.4 s a
lobbed bolt (8 m/s, range 5 m, r 0.18, life 1.5 s) for 3 damage, 0.3 KB, 5 poise, 0.15 stun, the same
numbers as the campaign's `scrapling_pelter` recipe. AI: pack keys removed (`null`), `{"prefers":
"ranged", "keep_distance": 4.0, "ability": 0.3, "ranged_slot": "ability2"}` — keeps ~4 m, pelts, and
fights back in melee when cornered.

**Chum Rush** spawns `"npc_scrapling#pelter"`: `chum_rush_mode.gd` `_resolve()` now maps `"<id>#<variant>"`
to the creature `"<id>_<variant>"` (falling back to the base id, then dev_biped). The campaign uses its
own recipe (`minion_loadouts.json`: base `npc_scrapling` + the Bolt Toss patch + the same `ai` keys);
both run the same bot logic (`keep_distance` is an alias of main's kit hint `range` + an implicit hint
for the ranged ability).

## Blister (`npc_blister`) — sludge balloon with a short fuse

Hopper, 3 segments, 25 kg, 0.68 m. Health 20, poise 10, walk 2.8 m/s (hops), stamina 50, dash 1.5 m.

| Slot | Move | S / A / R | Dmg | KB | Stun | Poise | Sludge | Notes |
|---|---|---|---|---|---|---|---|---|
| L1 | Hop | 0.32 / 0.28 / 0.15 | 2 | 2.0 | 0.15 | 5 | 5 | lands 0.6–1.4 m |
| Heavy | Belly Bump | 0.45 / 0.33 / 0.27 | 4 | 3.0 | 0.25 | 10 | 10 | lands 0.6–1.8 m |
| Dash attack | Splat Slide | 0.02 / 0.28 / 0.15 | 2 | 2.0 | 0.15 | 5 | 5 | |
| Grab / pummel | Cling / Squelch | 0.10 / 0.20 / 0.20 | 1 | — | — | — | 10 | |
| Throws | all | — | 2 | 1.2–1.4 m | — | — | — | no knockdown |
| Taunt | Wobble | 1.5 s | — | — | — | — | — | |
| A1 (1 s) | **Inflate & Pop** | 1.2 s inflate | 12 (r 2.0) | 4.0 | 0.25 | 20 | 40 | armored (all) for the whole 1.2 s inflate; pops: area r 2 m (class `pop`), a sludge puddle r 1.2 m 3 s, and the Blister is consumed (`self_damage` 999 **lethal**, after marking itself `blister_spent`) |
| Passive | Death Pop | — | 6 (r 1.0) | 3.0 | 0.2 | 10 | 20 | knocked out before popping (not `blister_spent`): a half-size burst — dangerous to whoever killed it in melee, harmless at range |
| Passive | Live bomb | — | 12 (r 2.0) | 4.0 | 0.25 | 20 | 40 | thrown: it marks itself spent, then 0.55 s later pops **at its landing spot, credited to the thrower** (hits the thrower's enemies, never the thrower) and is consumed |
| Passive | Pop chain | — | ×2 | — | — | — | — | a `pop` class hit on a Blister deals double — one Blister's pop sets off its neighbours |

AI: `{"style": "kamikaze", "aggression": 0.3, "block": -1, "dodge": -1, "grab": -1, "ability": 0.6,
"abilities": {"ability1": {"min": 0.5, "max": 1.8, "apart": 1.5}}}` — walks in and inflates within 1.8 m,
never side by side with another inflating Blister (kit hint `apart`).

## How the properties are implemented (engine extensions, all generic and data-driven)

Each block is appended in a clearly separated "NPC-kit" section of its file and covered by
`test_kit_npc_extensions.gd` (plus the integration tests in `test_kit_minions.gd`).

| File | Function / block | What and why |
|---|---|---|
| `game/src/sim/hooks.gd` | `EVENTS_NPC`, `validate()` | hook events `knocked_out` (fired on the KO'd fighter, `other` = who KO'd it) and `thrown` (on the thrown fighter, `other` = thrower, `point` = expected landing) — Death Pop, live bombs, thrown Scraplings |
| | `_conditions()` | condition `"not": {...}` (holds when the nested conditions do not all hold) — "only if not already spent" |
| | `_act()` → `_act_on_behalf()` | effect actions with `"source": "other"` are fired BY the event's other fighter (damage credit, teams, targeting are the thrower's) and centred on the event point; an event point also centres the fighter's own effects that give no `at`; `self_damage` with `"lethal": true` goes through EffectsSystem |
| `game/src/sim/effects.gd` | `"self_damage"` type, `_self_damage()` | plain `self_damage` leaves 1 HP (as before); `"lethal": true` subtracts and lets the mode handle the depletion like any KO (a Blister consumed by its own pop) |
| `game/src/sim/fighter.gd` | `knock_out()` | fires `knocked_out` |
| | `_do_throw()` → `_npc_thrown_event()` | fires `thrown` with the landing point (clamped to the arena) |
| | `guards_against()` → `_shield_guards()`, `shield_damage_mult()`, `_shield_status()` | **shield statuses**: a status with `guard_arc` (degrees in front, 360 = all round) blocks hits from inside the arc while the fighter is on its feet and acting (neutral/attack/ability/guard/taunt), without the GUARD state; `guard_absorb` replaces the guard's damage absorption; the widest active shield applies — Lid Up, Snappington's Withdraw |
| `game/src/sim/combat.gd` | `deliver()` (one line) | the guard damage multiplier goes through `shield_damage_mult()` |
| `game/src/sim/status_set.gd` | doc comment | documents `guard_arc` / `guard_absorb` |
| `game/src/sim/modes/chum_rush_mode.gd` | `_resolve()` | `"<id>#<variant>"` → creature `"<id>_<variant>"`, else the base id |
| `game/src/ai/bot_brain.gd` | kit-hint block (shared with the Dredge/Dozer hints) | `pack` / `pack_ring` / `pack_guard`, `ally_ko_flinch`, `apart`, `keep_distance` / `prefers: ranged` (alias of `range` + implicit ranged-ability hint), `reach`, `rest`, `bulky` (bosses, see bosses.md) |

## Campaign compatibility (minion loadouts)

`game/content/core/encounters/minion_loadouts.json` patches these bases into the ENEMIES_BOSSES.md §1.3
variants; the patches were retargeted to how these kits implement each piece (checked by
`test_technique_lint.gd::test_minion_loadout_patches_hit_their_base_bodies` — every patch hits an
existing field — and by `test_campaign_loadouts_really_differ`):

| Loadout | Patches |
|---|---|
| `scrapling_pelter` | creates A2 Bolt Toss (same numbers and hand offset as `npc_scrapling_pelter`), `ai` keep_distance 4 |
| `scrapling_hot_pipe` | Pipe Swing and Pipe Smash: Scorch 15 |
| `scrapling_gravel_lid` | Lid Bash: Grit 15; Lid Up's status `guard_absorb` 1.0 (the lid absorbs 100 %) |
| `scrapling_leaky_pipe` | Pipe Swing and Pipe Smash: Sludge 15; passive `leaky_puddle` (`knocked_out` → 0.6 m sludge puddle 4 s) |
| `blister_ember` | element Scorch: Inflate & Pop's area Scorch and its zone `scorch_patch`; Death Pop and the live bomb Scorch; sac `#FF6B2B` |
| `blister_fuse` | element Static: the pop Static with a 0.4 s stun, zone `static_field`; Death Pop and the live bomb Static + 0.4 s stun; sac `#F7E04A` |
## Tests (`test_kit_minions.gd`)

| Test | Checks |
|---|---|
| `test_minion_kits_complete_and_valid` | no creature errors, `npc_only`, slot convention for the campaign recipes, Pelter extends without the pack |
| `test_scrapling_moves_connect_in_range_and_miss_outside` | Pipe Swing / Lid Bash / Pipe Smash / Bin Rush land at range vs Stoke and miss beyond |
| `test_lid_up_shields_only_the_front` | a Pelter bolt is blocked from the front, lands from behind |
| `test_thrown_scrapling_is_a_projectile` | a thrown Scrapling bursts on the pack at its landing spot, credited to the thrower |
| `test_scrapling_pack_takes_turns` | at most two attack one target, the rest hold the ring |
| `test_scrapling_dies_in_a_few_clean_hits` | 2 clean lights / 1 clean heavy from the reference biped |
| `test_pelter_lobs_bolts_and_keeps_distance` | bolts every 2 s, ~3 dmg, keeps ~4 m |
| `test_chum_rush_resolves_pelter_variant` | `npc_scrapling#pelter` resolves to the Pelter |
| `test_blister_moves_connect_in_range_and_miss_outside` | Hop / Belly Bump ranges |
| `test_blister_inflate_and_pop` | armored inflate, one ~12 pop, sludge build-up, puddle, consumed |
| `test_blister_death_pop` | melee kill → ~6 Death Pop on the killer; ranged kill → nobody hit |
| `test_thrown_blister_is_a_live_bomb` | lands, pops for the thrower, chains a neighbour, never hits the thrower |
| `test_blisters_never_inflate_side_by_side` | the `apart` hint |
| `test_campaign_loadouts_really_differ` | every campaign loadout resolves on these bases and really differs (elements, zones, full lid block, death puddle, Ember/Fuse pops); a Leaky Pipe KO leaves its puddle, a Fuse Death Pop builds Static |

Result (merged with main 144efdc): 14 / 14 minion tests and 6 / 6 extension tests pass.

## Evidence

`docs/evidence/kits/npc_scrapling_01_pipe_and_lid.png`, `npc_scrapling_02_counter_hit.png`,
`npc_scrapling_03_chum_rush_wave.png` (Chum Rush wave 1 at the gate), `npc_scrapling_pelter_01_cornered.png`,
`npc_blister_01_belly_bump.png`, `npc_blister_02_cage_slammed.png`, `npc_blister_03_death_pop.png` (the
green burst as Dozer's cage slam knocks it out). GUI sandbox autoplay captures.

## Known gaps

- **Lid box vs fists**: the Scrapling's lid is a box; the engine detects melee contacts on thin capsule
  approximations of box hurt shapes, so a punch the lid physically stops may register nothing (the
  Lid Up test uses a projectile).

- A thrown Blister's pop leaves no puddle (the passive has no zone).
- **Audio**: `Audio.creature_audio` reads `audio` blocks only from the `creatures` content kind, so
  minions (and bosses) fall back to the generic voice/material (audio owner).
