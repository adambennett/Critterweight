# Bosses — Bilge, Conduit, Commissioner Snappington

Spec: `docs/design/ENEMIES_BOSSES.md` §2. These are the boss **creatures**: bodies (authored with the
content, untouched here), stats and the regular movesets the boss's BotBrain plays between BossMode's
scripted patterns (`game/content/core/boss_fights/*.json`, `game/src/sim/modes/boss_mode.gd`). Data:
`game/content/core/bosses/boss_bilge.json`, `boss_conduit.json`, `boss_snappington.json` (all
`npc_only`). Tests: `game/src/test/kits/test_kit_bosses.gd`.

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game --fixed-fps 120 -- --test test_kit_bosses                     # boss kits (8 tests + aids)
& $g --headless --path game --fixed-fps 120 -- --test test_kit_bosses.gd::test_balance --balance [--balance-bouts 10] [--kit-boss boss_bilge]
& $g --headless --path game --fixed-fps 120 -- --test test_kit_bosses.gd::test_zz_report_ranges --kit-report --kit-boss boss_conduit
```

Common rules for all three:

- **Big readable telegraphs**: nothing damaging comes out in under 0.5 s (asserted for every move and
  ability); the boss bot **rests 1.4–3.0 s after every attack** (kit hint `rest`) and queues nothing during
  a recovery — one big move, a breather, the punish window.
- **Armor**: every basic attack is armored through its startup (lights for L1/L2/grab, all-but-heavy
  for the heavies and Shell Spin).
- **Weight**: 260–480 kg bodies, poise 160–240, they never block or dodge (`block`/`dodge` −1).
- **Grabbable only while Dazed**: BossMode sets `boss_ungrabbable` and clears it during Dazed; the kits
  add nothing to that. BossMode's `grab_throw` grabs with the `head` segment and throws with the
  creature's `throw_fwd/side/back` (all three present, knockdown).
- `power` / `defense` stay 1.0 — BossMode's scripted attacks are fired by the boss and scale with them.
- `ai` `bulky: true` (read by bots FIGHTING the boss): their reach is measured to the boss's nearest body
  part (its head/shell is in reach long before its root) and the recovery of its long moves (after the
  last hit window / effect) is an opening to punish, not a threat to dodge. Without it, roster bots
  stayed out of reach behind Bilge's head and dodged through every recovery.

## Bilge (`boss_bilge`) — the Cannery Hound

Quadruped, 15 segments, 320 kg, 2.08 m. Health 420, poise 200, walk 3.4 m/s, stamina 200.
AI: `{"style": "playful brute", "aggression": 0.0, "grab": 0.08, "ability": -0.1, "reach": {"l1": 3.0},
"rest": [1.8, 3.0]}`.

| Slot | Move | S / A / R | Dmg | KB | Stun | Poise | Sludge | Armor | Range vs Stoke | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| L1 | Chomp | 0.50 / 0.16 / 0.86 | 14 | 3.6 | 0.5 | 30 | 30 | 0–0.5 lights | 2.4–3.2 m (miss 3.8; inside 2 m he is past it) | neck lunge bite |
| L2 | Paw Swat | 0.50 / 0.18 / 0.57 | 9 | 3.4 side | 0.4 | 20 | 15 | 0–0.5 lights | 1.6–2.4 m | front paw sweeps to his right (`kb_side −1` = right, per MoveDef) |
| Heavy | Shake-Off | 0.62 / area / 0.98 | 8 (r 2.2) | 4.0 | 0.3 | — | 20 | 0–1.0 all-but-heavy | 1.6–2.0 m | radial shove (≥ 0.6 m) |
| Grab | Lunge-Chomp | 0.85 / 0.45 / 1.00 | — | — | — | — | — | 0–0.8 lights | grabs 2.4–4.2 m | long lunge, `jaws`/`head`; throws 10 / 9 / 8 (4 / 3.5 / 3 m), knockdown |
| Pummel | Gnaw | — | 4 | — | — | — | 10 | — | — | |
| A1 (7 s) | Bilge Spit | 0.72 / proj / 0.48 | 6 ×3 | 2.0 | 0.2 | 10 | 35 | — | 2.4–6 m | three lobbed globs (40° spread, 9 m/s, range 8); each leaves a sludge puddle r 1.0 m 4 s (0.25 dmg ticks — a slowing hazard; three full-strength puddles stacked to ~4.5 dps) |
| A2 (10 s) | Belly Flop | 1.00 / leap / 1.90 | 12 (r 2.5) + ring 4 | 5.0 / 2.5 | 0.5 | 40 / 15 | brine 40 / 20 | — | lands on the target (≤ 4 m leap) | the ring 2.5–4 m is class `wave`: **trips a Soaked target** (passive `wave_trips_soaked`) |
| JUICE | Off the Chain | 0.85 / 1.95 / 1.00 | 12 ×3 | 4.4 | 0.4 | 30 | 25 | — | 2.4–4.2 m | three 9 m/s lunging bites, then 6 s: speed ×1.12, armor vs lights, hits add Brine 15 |

## Conduit (`boss_conduit`) — the live wire

Serpent, 9 segments, 260 kg, 3.31 m reared, ~7 m long. Health 520, poise 160, walk 3.2 m/s.
AI: `{"style": "ambusher", "aggression": 0.05, "grab": 0.06, "ability": 0.15, "reach": {"l1": 2.1,
"grab": 2.1}, "rest": [1.8, 3.0], "abilities": {"ability2": {"chance": 0.2, "when": [{"target_winding":
true}]}}}` — answers a perceived wind-up with Scrap Shuffle.

| Slot | Move | S / A / R | Dmg | KB | Stun | Poise | Static | Armor | Range vs Stoke | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| L1 | Fang Strike | 0.58 / 0.34 / 0.48 | 10 | 3.0 | 0.45 | 22 | 20 | 0–0.5 lights | 1.6–2.0 m | the strike **arcs down** from jaws at 1.3 m to 0.9 m (1.8–1.9 m out): it meets every roster height (Jitters at 1.6 m) |
| L2 | Whip Tail | 0.66 / area / 0.79 | 9 (cone 180°, r 2.8) | 3.6 | 0.35 | 25 | 25 | 0–0.6 lights | 1.6–2.0 m in the string | catches the target the Fang Strike knocked back |
| Heavy | Coil Slam | 1.00 / area / 1.15 | 14 (r 2.0) | 4.0 | 0.5 | — | 45 | 0–0.95 all-but-heavy | 1.6–4.2 m | rears up and slams |
| Grab | Jaw Clamp | 0.78 / 0.34 / 0.58 | — | — | — | — | — | 0–0.7 lights | grabs 1.6–2.0 m (2.4 vs low bodies) | same arc as the Fang Strike; on the throw (8/8/7, 2.5 m) **discharges**: r 1.5 area 6 dmg, static 30 (passive `clamp_discharge`) |
| Pummel | Live Current | — | 4 | — | — | — | 15 | — | — | |
| A1 (6 s) | Arc Spit | 0.82 / proj / 0.58 | 5 ×2 | 1.5 | 0.2 | 10 | 40 | — | 1.6–6 m | two orbs (6 m/s, 1.6 s) that **home** 120°/s — they land on a side-stepping target |
| A2 (9 s) | Scrap Shuffle | blink at 0.4 | — | — | — | — | — | invuln 0.3 | — | submerges and resurfaces 4.5 m away after 0.5 s, leaving grit rubble (slow) |
| JUICE | Overvolt | 1.00 / area / 1.50 | 15 (r 3.5) | 5.0 | 0.6 | 50 | 60 | — | 1.6–3.6 m | then 6 s "Plugged In": speed ×1.15, armor vs lights, hits add static 15 |

## Commissioner Snappington (`boss_snappington`) — the snapping-turtle commissioner

Crab plan, 16 segments, 480 kg, 1.44 m shell top. Health 650, poise 240, walk 2.4 m/s, stamina 220.
AI: `{"style": "by the book", "aggression": 0.0, "grab": 0.05, "ability": 0.12, "reach": {"l1": 2.5},
"rest": [1.4, 2.4], "abilities": {"ability2": {"chance": 0.25, "when": [{"target_winding": true}]}}}` —
answers a perceived wind-up with Withdraw.

| Slot | Move | S / A / R | Dmg | KB | Stun | Poise | Grit | Armor | Range vs Stoke | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| L1 | Claw Jab | 0.55 / 0.25 / 0.50 | 9 | 2.0 | 0.4 | 20 | 15 | 0–0.5 lights | 1.6–2.4 m | head up out of the claw's way during the jab |
| L2 | Objection! | 0.55 / area / 0.55 | 4 (cone 110°, r 4.0) | 6.0 | 0.3 | 10 | — | 0–0.5 lights | 1.6–2.8 m (string) | gavel shockwave; carries 4 m so it catches the target the jab shoved |
| Heavy | Gavel Claw | 0.82 / 0.16 / 0.97 | 16 + wave 8 | 4.0 / 2.5 | 0.6 | 40 / 20 | 40 / 20 | 0–0.9 all-but-heavy | claw 1.6–2.0 m, wave to 2.8 m | overhead claw slam on the centre line, then a 3 m ground wave |
| Grab | Snap | 0.62 / 0.24 / 0.59 | — | — | — | — | — | 0–0.6 lights | grabs 2.0–2.4 m | beak/claw snap; throws 10 / 9 / 8 knockdown; a wall splat adds a 2-dmg "Disqualified!" burst (passive) |
| Pummel | Contempt of Court | — | 4 | — | — | — | 10 | — | — | |
| A1 (6 s) | Shell Spin | 0.75 / area ×2 / 1.35 | 8 + 8 (r 2.5) | 3.6 | 0.2 | 20 | 20 | 0–1.4 all-but-heavy | 1.6–2.4 m | spins two full turns (~10 rad/s) and stays upright |
| A2 (14 s) | Withdraw | 0.3 → 3.0 s | counter 10 | 3.0 | 0.3 | 25 | 20 | — | — | status `withdrawn` (**guard_arc 360°, absorb 0.8**: blocks from every side) + counter stance (KB taken ×0.5) + reflect projectiles |
| A1 juiced | Juice Spray | 0.82 / proj / 0.68 | 6 ×5 | 2.0 | 0.15 | 8 | 35 | — | ≤ 8 m | `ability1@juiced`: five globs in a 60° fan |
| JUICE | Title Slam | 1.20 / leap / 2.00 | 22 (r 3.0) | 5.4 | 0.6 | 60 | 50 | — | lands on the target (≤ 5 m) | knockdown; then 8 s "Off the Books": speed ×1.25, move ×1.15, armor vs lights |

## BossMode / campaign contract (`test_boss_mode_contract`)

- Every boss fight in `content/core/boss_fights` names one of these creatures and the campaign's
  `CreatureResolver` reports **no problems** for it, so fights run on the real bosses (no stand-ins);
  the `grab_throw` segments (`head`) exist on each body.
- A head-segment grab (`begin_grab(victim, head, 0)`, as BossMode does) holds the victim and the creature's
  throw hurts and knocks down.
- The element cycle (Snappington phase 2) writes `mods["element_<slot>"]`; her melee (Claw Jab) carries
  the cycled element (`Fighter.element_for`).

## Balance (boss bot at regular, bot-slot health)

Outside the campaign a boss in a bot slot has **2× the highest fighter HP and no phases**
(ENEMIES_BOSSES.md "Custom rules"); the bouts use that rule (`BOT_SLOT_HP`, 90 s rounds, 10 bouts per
matchup, seeds 500+). A = boss wins.

| Boss | vs regular roster bots (boss wins) | vs pro roster bots (boss wins) | pro-tier roster wins |
|---|---|---|---|
| Bilge | 43 / 60 (72 %) | 46 / 60 (77 %) | Gusto 6/10, Jitters 4/10, Stoke 3/10, Dredge 1/10 |
| Conduit | 54 / 60 (90 %) | 45 / 60 (75 %) | Dozer 7/10, Gusto 5/10, Stoke 3/10 |
| Snappington | 44 / 60 (73 %) | 47 / 60 (78 %) | Stoke 10/10, Gusto 2/10, Dredge 1/10 |

Per matchup (boss wins of 10, roster at regular / pro): Bilge — Stoke 5 / 7, Dredge 9 / 9, Gusto 1 / 4,
Dozer 10 / 10, Slurry 10 / 10, Jitters 8 / 6. Conduit — Stoke 10 / 7, Dredge 10 / 10, Gusto 5 / 5,
Dozer 9 / 3, Slurry 10 / 10, Jitters 10 / 10. Snappington — Stoke 1 / 0, Dredge 10 / 9, Gusto 3 / 8,
Dozer 10 / 10, Slurry 10 / 10, Jitters 10 / 10. Measured with the merged Stoke/Gusto and Dredge/Dozer kits
(main 144efdc); Slurry and Jitters are still stubs — re-run when their kits land. The asserted targets:
the boss beats regular-tier roster bots most of the time, and pro-tier roster bots win some.
## Tests (`test_kit_bosses.gd`)

| Test | Checks |
|---|---|
| `test_boss_kits_complete_and_valid` | parse with no errors, `npc_only`, design HP/poise, `head` segment, three throws, every slot, no stubs, ≥ 0.5 s telegraphs, armored startups, bot keys (`block`/`dodge` −1, `bulky`, `rest`) |
| `test_boss_mode_contract` | the section above |
| `test_moves_connect_in_range_and_miss_outside` | each basic move/ability lands at its near gaps vs Stoke, misses at its far gap, damage in band; upright, inside the cage |
| `test_armor_shrugs_lights_in_startup` | light hits in a heavy's startup do not stop it; it still lands |
| `test_bilge_signature_moves` | Shake-Off shoves, Lunge-Chomp grabs and throws (knockdown), the Belly Flop wave trips a Soaked target 7 m away, Spit leaves puddles |
| `test_conduit_signature_moves` | Jaw Clamp's throw discharges, Arc Spit homes on a strafing target, Scrap Shuffle relocates ≥ 2 m and leaves rubble, Overvolt bursts |
| `test_snappington_signature_moves` | Withdraw blocks/counters, Shell Spin spins upright through jabs, Title Slam knocks down, juiced A1 is Juice Spray |
| `test_balance_vs_roster` | smoke (both sides land hits); `--balance` runs the table above with its assertions |

Result (merged with main 144efdc): 8 / 8 boss tests pass; `--balance --balance-bouts 10` passes for all three.

## Evidence

GUI sandbox autoplay captures: `docs/evidence/kits/boss_bilge_01_chomp.png`, `_02_counter_bite.png`,
`_03_spit_puddle.png`, `_04_paw_swat.png`; `boss_conduit_01_reared.png`, `_02_fang_strike.png`,
`_03_vs_gusto.png`; `boss_snappington_01_claw_jab.png`, `_02_gavel_claw.png`, `_03_counter.png`.

## Engine changes used

`bot_brain.gd` kit hints `rest`, `bulky`, `reach` (see the table in `docs/kits/minions.md`) and the shield
statuses (`guard_arc`/`guard_absorb`) for Withdraw. Two touch points in the generic think loop: the
attacker's reach adds `_kit_target_bulk()` and `attacking` excludes `_kit_opening()` — both return 0/false
unless the target's `ai` has `bulky`.

## Deviations and known gaps

- **Bilge's stance** carries the head lower than the body's rest pose (neck 18°/12°, head −12°); roster
  strikes re-aim to his 2.08 m rest height, so jabs still meet the head.
- **Element cycle and effects**: BossMode's cycle re-elements melee hits (`element_for`), but area /
  projectile effects keep their authored element (EffectsSystem reads the effect's own `element`), so
  Snappington's Objection / Gavel wave / Shell Spin stay Grit in phase 2 (engine/campaign follow-up).
- **Chomp's sweet spot**: inside ~2 m Bilge is past his own bite; he uses Paw Swat / Shake-Off there.
- **Balance against stubs**: the roster kits on main are partly stubs; the boss tables should be re-run
  when they are replaced.
- **Audio**: as for minions, `Audio.creature_audio` does not read the `bosses` kind's `audio` blocks.
