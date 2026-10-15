# CRITTERWEIGHT — Campaign

Both campaign variants share one seeded roguelike run called a **fight card**: three acts (**Undercard → Main Card → Title Card**), each a branching node map with six rows and a boss. Everything below has a stable `snake_case` id.

## 1. The two variants

| | **OFF THE STREET** (fresh-run) | **FIGHT CAMP** (persistent) |
|---|---|---|
| Starting power | Base fighter, 0 supplements, 0 techniques, 60 Scrip | Base fighter + **Cannery upgrades** bought with Clout (§9) |
| Between runs | Main menu. Persist: stats, records, cosmetics, **The Dosage** unlocks (§8) | **The Cannery** hub (HUB.md): explore, talk, train, buy, find secrets |
| Challenge ladder | The Dosage (Dose 1–10), unlocked by clearing the highest unlocked Dose | The Dosage also applies, but ladder records are kept separately ("Camp" board) |
| Records | "Street" leaderboard: fastest clear, highest Dose, no-hit bosses | "Camp" leaderboard |
| PvP isolation | Nothing persists into PvP | Cannery upgrades are flagged `meta_bonus` and are **never** loaded outside Fight Camp runs or custom matches that explicitly enable "Gym Bonuses" (visible rule tag) |
| Co-op | Yes, 2–4 (§10) | Yes, 2–4; each player's own Cannery upgrades apply to their own fighter |
| Default difficulty | Amateur | Amateur |

Why share systems: both variants use the same map generator, encounter pool, event pool, supplement pool and boss set. Fight Camp adds a layer on top; it never forks the run logic.

## 2. Run structure and pacing

| Parameter | Value |
|---|---|
| Acts | 3 (Undercard, Main Card, Title Card) |
| Rows per act | 6 node rows + 1 boss row |
| Lanes | 3–4 per row; rows branch and merge; every node has 1–3 forward edges; every lane reaches the boss |
| Nodes visited per act | 6 + boss |
| Target run length | **25–40 min** solo (≈ 8–12 min per act); 4-player co-op ≈ 35–50 min |
| Fights per run | 12–15 (incl. 3 bosses), at 60–120 s each |
| Non-fight nodes per run | 6–9 |
| Seed | 64-bit; map, encounter rolls, event picks, reward offers and shop stock are all derived from it (sub-seeds per act/row/node); two runs with the same seed, difficulty and fighter produce the same card |
| Suspend/resume | Any node boundary; resumes to the node screen |

### Row composition rules (generator)

| Row | Rule |
|---|---|
| 1 | All **Fight** nodes (3–4 lanes) |
| 2–5 | Mix drawn from weights: Fight 40%, Event 20%, Mystery 12%, Shop 10%, Rest 8%, Elite 10% (Elites only in rows 3–5, max 2 per act, never adjacent in the same lane) |
| 6 | **Rest or Shop** on every lane (at least one of each across the row) |
| 7 | **Boss** (single node, all lanes merge) |
| Per-act guarantees | ≥ 1 Shop, ≥ 1 Rest, ≥ 1 Elite, ≥ 1 Event, ≤ 2 Mystery; a **Treasure** node replaces one Mystery in acts 2–3 (hidden until revealed) |
| Anti-degenerate | No path may contain 4 consecutive Fights; no path may skip both Shop and Rest before the boss; every node is reachable from row 1 |

## 3. Node types and rewards

| Node | Icon | What happens | Rewards |
|---|---|---|---|
| **Fight** | crossed fists | A normal encounter template (§5) | 1 pick from 3 supplements (rarity roll §7.3), +40–70 Scrip, +Hype carry (see below) |
| **Elite** | fist with a star | An elite template (§5), stronger with a special rule | 1 pick from 3 with ≥ 1 Prescription+, **plus** a technique pick (1 of 2 for your fighter), +90–130 Scrip |
| **Event** | speech bubble | A random event (§6) | Varies |
| **Shop** | JUICE can | Needles' pop-up stall (§7.5) | Spend Scrip |
| **Rest** | bandaged paw | Doc Sutura's table (§7.6) | Heal or train |
| **Mystery** | "?" | Revealed on entry: Fight 40%, Event 35%, Shop 10%, Treasure 15% | As revealed |
| **Treasure** | crate | A free pick from 3 with ≥ 1 Black Market, or 150 Scrip | — |
| **Boss** | belt | Act boss (ENEMIES_BOSSES.md) | 1 pick from 3 with ≥ 1 Black Market and 5% Banned, +1 technique pick (1 of 3), +200 Scrip, full heal 50% (Undercard) / 35% (Main Card) / — (Title Card: run ends) |

Hype carries between fights at 50% of its end-of-fight value (cap 50) so a big finish gives momentum into the next node.

**Health between nodes**: HP persists. Fights heal 0 unless a supplement says so. Rest heals.

## 4. Currencies

| Currency | Scope | Earned | Spent | Notes |
|---|---|---|---|---|
| **Scrip** | per run, lost at run end | Fight 40–70, Elite 90–130, Boss 200, events, selling items (50% value) | Shops, some events, rerolls (30 Scrip per reward reroll, max 2 per node) | Glandco company scrip; "redeemable at participating cages" |
| **Clout** | persistent (Fight Camp) | 10 per fight won, 25 per elite, 60 per boss, 150 per completed run; × difficulty multiplier (§8) | Cannery upgrades (§9) | Also earned in Off the Street at 50% (it buys cosmetics there, never power) |

## 5. Encounter templates

Enemy fighters are the six roster fighters piloted by bots at the preset's bot tier, with named **builds** (technique sets from ROSTER.md) where noted. "HP ×" is applied after preset multipliers. Arenas reference ARENAS.md. Special rules are custom-rules presets the rules editor can also expose.

### Special rule glossary

| Rule | Effect |
|---|---|
| `handicap_1vN` | Player side is outnumbered; enemies have HP × 0.7–0.85 (listed) |
| `low_gravity_X` | Gravity × X; leaps/knock-ups go higher, falls slower |
| `tag_bout` | Enemy side has 2 fighters tagging; tagged-out enemy regenerates 3 HP/s; player side fights one at a time (solo player gets one free Granny assist per fight: a 1-hit cameo) |
| `ffa` | Enemies fight each other too; last standing wins |
| `timed_sudden_death_X` | X-second timer; at 0 everyone drops to 1 HP, first hit wins |
| `waves` | Enemies arrive in groups; next wave spawns when the current one is at ≤ 1 alive |
| `hazards_on` | Base hazards enabled at listed timers; listed props placed |
| `hype_x2` | Hype gains ×2 for everyone |
| `enemy_hype_50` | Enemy fighters start with 50 Hype |
| `puddles_x2` | All zones last ×2 |
| `blister_fast` | Blisters inflate in 0.8 s |

### 5.1 Act 1 — The Undercard (arenas: The Gullet Day, Drydock)

| Id | Name | Enemies | Arena | Special rule | Notes |
|---|---|---|---|---|---|
| `enc_a1_dock_rats` | Dock Rats | 4× `scrapling_basic` | Drydock | — | Teaches throwing minions into minions |
| `enc_a1_open_tryout` | Open Tryout | 1× fighter (Stoke/Gusto/Jitters, no techniques) | The Gullet (Day) | — | The run's first 1v1 |
| `enc_a1_blister_pack` | Blister Pack | 3× `blister_sludge`, 2× `scrapling_basic` | Drydock | `hazards_on` (crane hook 30 s) | Pop them at range |
| `enc_a1_pelter_gallery` | Pelter Gallery | 3× `scrapling_pelter`, 1× `scrapling_basic` | The Gullet (Day) + 2 sponsor boards | — | Cover and closing distance |
| `enc_a1_wet_floor` | Wet Floor | 1× Dredge (no techniques) | Drydock | `hazards_on` (gutter floods every 10 s) | Soaked spacing lesson |
| `enc_a1_two_for_one` | Two for One | 2× fighters (random, HP × 0.7) | The Gullet (Day) | `handicap_1vN` | First outnumbered fight |
| `enc_a1_hot_pipes` | Hot Pipes | 4× `scrapling_hot_pipe` | The Gullet (Day) + 2 fire barrels | `hazards_on` | Sizzle and barrels |
| `enc_a1_tag_tryout` | Tag Tryout | Stoke + Slurry (no techniques), tagging | The Gullet (Day) | `tag_bout` | Enemy regen teaches urgency |
| `enc_a1_timed_scrap` | Timed Scrap | 6× `scrapling_basic` in 2 waves | Drydock | `waves`, `timed_sudden_death_60` | Fast clear |
| `enc_a1_low_tide` | Low Tide | 1× Slurry (no techniques), 2× `blister_sludge` | Drydock | `puddles_x2` | Dilute in the gutter |
| `elite_a1_dock_foreman` | **Elite: The Dock Foreman** | Dredge (Hurler: Mooring Chain + Wall-and-Chain), 2× `scrapling_basic` | Drydock | `hazards_on` (crane hook 15 s) | Wall splats hurt |
| `elite_a1_showboat` | **Elite: The Showboat** | Gusto (Showboat: Crowd Work + Hollow Bones) | The Gullet (Day) | `enemy_hype_50`, `hype_x2` | He will JUICE; punish taunts |
| `elite_a1_blister_bloom` | **Elite: Blister Bloom** | 8× `blister_sludge` in 3 waves, 2× `scrapling_pelter` | Drydock | `waves`, `low_gravity_0.7`, `blister_fast` | Thrown Blisters fly far |
| `boss_a1` | **Boss: Bilge** | ENEMIES_BOSSES.md §2.1 | Drydock | — | — |

### 5.2 Act 2 — The Main Card (arenas: The Crusher, The Rooftop, The Gullet Night)

| Id | Name | Enemies | Arena | Special rule | Notes |
|---|---|---|---|---|---|
| `enc_a2_scrapyard_gang` | Scrapyard Gang | 3× `scrapling_gravel_lid`, 2× `scrapling_pelter` | The Crusher | `hazards_on` (magnet 15 s, plates on) | Lids block fronts; the magnet un-groups them |
| `enc_a2_live_wire_lite` | Live Wire Lite | Jitters (Capacitor), 2× `blister_fuse` | The Crusher | `hazards_on` (plates) | Static everywhere; foreshadows Conduit |
| `enc_a2_rooftop_brawl` | Rooftop Brawl | Dozer (Quarry Legs) | The Rooftop | `hazards_on` (wind 10 s) | Ring-outs both ways |
| `enc_a2_three_way` | Three-Way Dance | 2× fighters (random, 1 technique) | The Rooftop | `ffa` | Let them fight; take the winner |
| `enc_a2_tag_bout` | Tag Bout | Stoke (Pressure Cooker) + Slurry (Septic Bloom), tagging | The Crusher | `tag_bout` | Flare-Up risk when both are in |
| `enc_a2_bomb_squad` | Bomb Squad | 4× `blister_sludge`, 2× `blister_ember`, 2× `scrapling_pelter` | The Crusher | `blister_fast` | Ember pops ignite sludge pops |
| `enc_a2_low_gravity` | Thin Air | Gusto (Air Superiority), 1× `scrapling_pelter` | The Rooftop | `low_gravity_0.6` | Everyone can hop-glide |
| `enc_a2_sludge_pit` | Sludge Pit | Slurry (Swamp: Septic Bloom + Grease Trap) | The Crusher + 3 sludge drums | `hazards_on` | Fizzing puddles when plates fire |
| `enc_a2_handicap` | Two-on-One | Dredge + Jitters (HP × 0.8, 1 technique each) | The Gullet (Night) | `handicap_1vN` | Short-Out bait for the player |
| `enc_a2_sudden_death` | Sudden Death | 1× fighter (random, 2 techniques) | The Crusher | `timed_sudden_death_60` | Tension |
| `elite_a2_crusher_crew` | **Elite: Crusher Crew** | Dozer (Freight Train: Quarry Legs + Demolition Permit + Pack Mule), 4× `scrapling_gravel_lid` | The Crusher (scrap piles pre-destroyed) | `hazards_on` (magnet 20 s) | Open square, nowhere to hide from Bulldoze |
| `elite_a2_the_twins` | **Elite: The Twins** | 2× Stoke (Furnace: Pressure Cooker + Afterburner, HP × 0.85), tagging | The Rooftop | `tag_bout`, `hazards_on` (wind 12 s) | Backdraft off the roof |
| `elite_a2_pinball_wizard` | **Elite: Pinball Wizard** | Jitters (Trampoline: Bouncy Castle + Head Hunter + Rubber Core) | The Gullet (Night) + 6 spring pads, 2 batteries | `hazards_on` | Use his pads against him |
| `boss_a2` | **Boss: Conduit** | ENEMIES_BOSSES.md §2.2 | The Crusher | — | — |

### 5.3 Act 3 — The Title Card (arenas: The Gullet Night/Title Night, mixed)

| Id | Name | Enemies | Arena | Special rule | Notes |
|---|---|---|---|---|---|
| `enc_a3_main_event` | Main Event | 1× fighter (random, 3 techniques forming a build) | The Gullet (Night) | — | A real 1v1 |
| `enc_a3_gatekeepers` | The Gatekeepers | 2× fighters (2 techniques, HP × 0.8) | The Gullet (Night) | `handicap_1vN`, `enemy_hype_50` | They JUICE early |
| `enc_a3_swarm_night` | Swarm Night | 8× scraplings (mixed loadouts), 4× blisters (mixed) in 3 waves | The Rooftop | `waves` | Edges shed minions |
| `enc_a3_tag_title` | Tag Title | 2× fighters (2 techniques), tagging | The Gullet (Night) | `tag_bout` (enemy regen 5 HP/s) | Finish the tagged-in one fast |
| `enc_a3_juice_night` | JUICE Night | 1× fighter (2 techniques) | The Gullet (Title Night) + 2 JUICE cans | `hype_x2` | Multiple JUICEs per side |
| `enc_a3_hazard_hell` | Hazard Hell | 1× fighter (2 techniques) | The Crusher + 2 batteries | `hazards_on` (plates, magnet 12 s) | Positioning test |
| `enc_a3_rooftop_royale` | Rooftop Royale | 3× fighters (1 technique, HP × 0.8) | The Rooftop | `ffa`, `hazards_on` (wind 15 s) | Survive the brawl |
| `enc_a3_zero_g` | Zero-G | Gusto + Jitters (2 techniques each) | The Rooftop | `low_gravity_0.5`, `hazards_on` (wind 8 s) | Chaos, intentionally |
| `enc_a3_iron_man` | Iron Man | Dredge (The Wall: Barnacle Plating + Molting Season + Undertow) | Drydock | `hazards_on` (gutter always flooded) | Grabs beat his armor |
| `enc_a3_timed_rush` | Timed Rush | 2× fighters sequential (the second enters when the first is KO'd), 2 techniques | The Gullet (Night) | `timed_sudden_death_90` | Pace yourself |
| `elite_a3_contender` | **Elite: The Contender** | Mirror match: the player's own fighter with 4 techniques | The Gullet (Night) | — | Your kit, their hands |
| `elite_a3_bilge_rematch` | **Elite: Bilge Rematch** | Bilge at 60% HP, phase 1 only, 4× `scrapling_leaky_pipe` | Drydock | — | He remembers you |
| `elite_a3_commissioners_cut` | **Elite: The Commissioner's Cut** | 2× fighters (3 techniques), tagging | The Gullet (Title Night) + 4 steam vents | `tag_bout`, `hazards_on`, enemies start with 100 Hype | The last gate |
| `boss_a3` | **Boss: Commissioner Snappington** | ENEMIES_BOSSES.md §2.3 | The Gullet (Title Night) | — | Run ends on victory |

Random "fighter" picks never select the player's own fighter except in `elite_a3_contender`. Builds for random picks are drawn from that fighter's three ROSTER.md build directions.

## 6. Random events

Text is subtitle-length; choices show their cost and a risk tag. "Roll" outcomes use the node sub-seed. Fighter-/element-specific events only appear for that fighter/element.

| Id | Title | Setup (text) | Choices → outcomes |
|---|---|---|---|
| `evt_needles_sample` | Free Sample | Needles leans out of a van. "New batch. Totally legal. Probably." | **Take it**: random Prescription supplement + a random side effect (§7.4) · **Decline**: +15 Scrip (he pays for silence) |
| `evt_weigh_in` | The Weigh-In | The Commission wants you on the scale. The scale is broken. | **Cut weight**: max HP −8, walk speed +0.2 m/s this run · **Bulk up**: max HP +12, dash −0.3 m · **Bribe the scale** (40 Scrip): nothing changes, +10 Hype carry |
| `evt_sponsor_read` | Sponsor Read | A producer hands you a card. "Say it with feeling." | **Read it**: +50 Scrip, next fight starts at 0 Hype (you're embarrassed) · **Refuse**: next fight starts at +30 Hype (the crowd respects it) |
| `evt_dock_dice` | Dock Dice | Dockworkers roll bones on an upturned crate. | **Bet 30 Scrip**: roll — 45% win 70 Scrip, 40% lose the 30, 15% they're loaded dice: win 70 and a `prop_crate`-themed cosmetic · **Walk on**: nothing |
| `evt_lost_dog` | Lost Dog | A huge, sad, sludge-soaked hound is tied to a bollard. He looks hungry. (Act 1 only) | **Feed him** (lose 10 HP; he bites): Bilge starts the boss fight at 90% HP and skips his first Lunge-Chomp · **Pet him**: he's thrilled. +20 Hype carry · **Keep walking**: nothing |
| `evt_commission_hearing` | Commission Hearing | A notice: you are summoned for "conduct." Snappington isn't there. A clerk is. | **Pay the fine** (60 Scrip) · **Forfeit a supplement** (lose 1 random non-Banned) · **Contest it**: 50% dismissed (nothing), 50% both penalties |
| `evt_cut_woman` | Cut-Woman | Doc Sutura flags you down between bouts, eight hands already moving. | **Quick patch**: heal 20% · **Deep stitch**: heal 40%, max stamina −10 this run · **"I'm fine"**: +5 poise max this run |
| `evt_vending_machine` | Vending Machine | A Glandco machine hums. The glass is cracked. | **Insert 25 Scrip**: random OTC supplement · **Kick it**: 50% free OTC supplement, 50% it falls on you (−15 HP) · **Insert 60 Scrip**: random Prescription |
| `evt_the_bookie` | The Bookie | Teddy Two-Tooth: "Odds on your next fight are... unflattering." | **Bet on yourself** (40 Scrip): win the next fight without being knocked down → 120 Scrip, else lose the bet · **Bet against yourself** (free): if you get knocked down next fight, +50 Scrip (the game tracks it; the announcer notices) · **No bet** |
| `evt_press_conference` | Press Conference | Microphones. Cameras. Someone from Glandco mouthing "say the name". | **Trash talk**: next fight both sides start at 40 Hype · **Humble**: heal 10% · **Plug the sponsor**: +40 Scrip |
| `evt_scrap_crane` | Scrap Crane | A crane dangles a crate over the pit. Ludlow shrugs: "Could be anything." | **Grab it** (fight 3× `scrapling_basic` while the crane hook hazard runs): Treasure pick · **Leave it** |
| `evt_kid_lamprey_spar` | Sparring Offer | Kid Lamprey, hood up: "Three rounds. Lose and I tell everyone." | **Spar** (fight a copy of your fighter at HP × 0.6, no rewards on loss, no HP lost either way — it's sparring): win → 1 technique pick (1 of 2) · **Decline** |
| `evt_juice_crate` | A Crate of JUICE | Unmarked. Still cold. Nobody is watching. | **Drink one**: max HP +10, random side effect · **Drink three**: max HP +25, two side effects, +30 Hype carry · **Sell it**: +80 Scrip |
| `evt_crowd_favor` | Crowd Favorite | The crowd is chanting an element. (Rolls an element.) | If it matches yours: **Play to them**: Hype gain +10% this run · If not: **Give them a show anyway**: next fight `hype_x2` · **Ignore them**: +20 Scrip |
| `evt_blister_nest` | Blister Nest | A drain is full of Blisters. Something glints at the bottom. | **Clear it** (fight 6× `blister_sludge`): random Prescription + 30 Scrip · **Seal it**: nothing · **Throw a rock**: they all pop (−10 HP), 30 Scrip |
| `evt_weight_class` | Wrong Weight Class | A clerk insists you're in the wrong bracket. *(Pipsqueak/Scrapper variant)* "You're too small." *(Lunker/Absolute Unit)* "You're too big." | Small: **Accept the bump up**: enemies next 2 fights HP × 1.15, rewards × 1.3 · **Argue**: nothing · Big: **Accept the bump down**: enemies next 2 fights HP × 0.85, rewards × 0.8 · **Argue**: nothing |
| `evt_ref_bribe` | A Word With the Ref | The referee (a very tired goat) is counting Scrip. | **Slip him 50**: next fight, the first knockdown on you is waved off (poise refills) · **Report him**: +Clout 10 (Fight Camp) / +25 Scrip (Off the Street) · **Nothing** |
| `evt_ice_bath` | Ice Bath | Doc's ice bath. It is a dumpster. It has ice in it. | **Get in**: heal 25%, Soaked at the start of the next fight · **Toe dip**: heal 10% · **No** |
| `evt_wall_of_fame` | Wall of Fame | Photos of champions. One frame is empty. Ludlow is holding a camera. | **Pose**: unlock a profile frame cosmetic; +15 Hype carry · **Don't**: nothing |
| `evt_rooftop_pigeons` | Pigeons | Several hundred pigeons. One has a Scrip note. (Act 2+) | **Chase it**: 60% +40 Scrip, 40% nothing and −5 HP (pecked) · **Feed them**: next Rooftop fight, pigeons scatter on your JUICE (+10 Hype on activation) |
| `evt_glandco_audit` | Glandco Audit | Men in matching windbreakers. "We're checking labels." | **Hand over a Banned Substance** (if you have one): +150 Scrip · **Hide it**: 70% nothing, 30% lose it and 30 Scrip · **No Banned items**: they leave a coupon (shop 20% off next visit) |
| `evt_rest_stop` | Highway Rest Stop | A bench. A vending machine out of order. Peace. | **Nap**: heal 15%, Hype carry → 0 · **Stretch**: stamina max +5 this run · **Read the graffiti**: unlock a random announcer idle quip (cosmetic collection) |
| `evt_the_belt` | The Belt | A replica title belt in a pawn shop window. (Act 3) | **Buy it** (100 Scrip): start the final boss with 100 Hype · **Window-shop**: +10 Hype carry |
| `evt_boiler_inspector` | Boiler Inspector *(Stoke)* | A city inspector taps your belly with a wrench. "That's not up to code." | **Let him "fix" it**: Steam Vent cooldown 7 → 5 s this run, max HP −6 · **Bribe** (30 Scrip): Stoke the Fire self-burn removed this run · **Run** |
| `evt_molting` | Molting Day *(Dredge)* | Your shell is coming off. It always picks the worst time. | **Molt now**: lose 15 HP, then poise +20 and knockback taken −10% this run · **Hold it in**: next fight, Anchor Drop is free (no cooldown) once · **Ignore** |
| `evt_fan_club` | Fan Club *(Gusto)* | Six terns in matching crests want a feather. | **Give one each**: Crowd Work-style taunt bonus (+4 Hype per taunt) this run · **Sell them merch**: +45 Scrip · **Sign nothing** |
| `evt_headlamp` | Dead Battery *(Dozer)* | Your headlamp went out. You walked into a wall. | **Buy a battery** (20 Scrip): Bulldoze steering +10°/s this run · **Fight in the dark**: next fight is at night with the rim light off; win → Black Market pick |
| `evt_drain_backup` | Drain Backup *(Slurry)* | The cannery drain is overflowing. It's your drain. | **Clear it**: Drain Dive cooldown 9 → 7 s this run, −8 HP · **Leave it**: your puddles +1 s this run · **Blame Ludlow** |
| `evt_static_storm` | Storm Warning *(Jitters or any Static-move build)* | A thunderhead rolls over the bay. Your bulbs are humming. | **Stand in it**: start the next fight with Jolted immunity and +40 Hype, but −10 HP · **Hide**: nothing · **Charge a battery** (place a free `prop_battery` in your next fight's arena) |

28 events. Each outcome is implementable as: modify HP / max HP / stamina / poise, grant item, grant Scrip/Clout, set a per-run or per-next-fight rule flag, or launch a mini-encounter.

## 7. Upgrades

### 7.1 Supplement rarities

| Rarity | Label color / frame | Base drop weight (Fight) | Notes |
|---|---|---|---|
| **Over-the-Counter** | white frame, plain label | 60% | Clean stat bumps, gear |
| **Prescription** | blue frame, pharmacy label | 28% | Bigger numbers, usually a side effect |
| **Black Market** | black frame, no label | 10% | Build-defining |
| **Banned Substance** | red frame, "BANNED" stamp | 2% | Run-defining, always a cost |

Rarity weights shift per act: Act 2 adds +6% Prescription/+3% Black Market from OTC; Act 3 adds +10%/+6%/+1% Banned. Elite/Boss/Treasure guarantees are in §3. A pick always offers 3 distinct items; items the player already has at max stack are excluded. Stacking: most supplements stack up to **2** (listed), gear does not stack.

### 7.2 Generic supplements and gear (50 ids)

| Id | Name | Rarity | Effect | Side effect | Stack | Tags |
|---|---|---|---|---|---|---|
| `sup_tusk_dust` | Tusk Dust | Prescription | Heavy damage +12% | Stamina regen −10% | 2 | heavy, glass |
| `sup_marrow_shake` | Marrow Shake | OTC | Max HP +12 | Walk speed −3% | 2 | tank |
| `sup_gland_tonic` | Gland Tonic | OTC | Hype gain +15% | Taunt animation +0.3 s | 2 | hype |
| `sup_pre_workout_bile` | Pre-Workout Bile | Prescription | Light startup −8% | Light stamina cost +10% | 1 | light, combo |
| `sup_cartilage_chews` | Cartilage Chews | OTC | Poise +15 | — | 2 | tank |
| `sup_adrenal_drip` | Adrenal Drip | Prescription | First 10 s of every fight: damage +20% | Max stamina −10 | 1 | burst |
| `sup_liver_spots` | Liver Spots | Prescription | Build-up dealt +20% | Statuses on you last +20% | 1 | status |
| `sup_hair_of_the_dog` | Hair of the Dog | Prescription | Heal 10% max HP after every fight | Healing received during fights −20% | 1 | sustain |
| `sup_knuckle_wax` | Knuckle Wax | OTC | Light damage +1 | — | 2 | light |
| `sup_mouthguard` | Mouthguard | OTC (gear) | Poise damage taken −15% | — | 1 | tank |
| `sup_shin_tape` | Shin Tape | OTC (gear) | Dodge stamina cost 12 → 9 | — | 1 | mobility |
| `sup_double_wraps` | Double Wraps | OTC (gear) | Heavy poise damage +20% | — | 1 | heavy |
| `sup_scrip_clip` | Scrip Clip | OTC | Scrip rewards +25% | — | 1 | economy |
| `sup_sponsor_patch` | Sponsor Patch | OTC | Shops show +1 item and prices −10% | — | 1 | economy |
| `sup_glass_jaw_serum` | Glass Jaw Serum | Black Market | Damage dealt +20% | Damage taken +20% | 1 | glass |
| `sup_iron_lung` | Iron Lung | Prescription | Max stamina +25 | — | 1 | stamina |
| `sup_second_wind_sachet` | Second Wind Sachet | Black Market | Once per fight at < 25% HP: stamina refills, 1.5 s armor | — | 1 | comeback |
| `sup_juice_concentrate` | JUICE Concentrate | Black Market | JUICE duration +25% | JUICE activation costs 5 HP | 1 | juice |
| `sup_hype_syrup` | Hype Syrup | **Banned** | Start every fight with 50 Hype | Damage taken +10% while above 50 Hype | 1 | hype |
| `sup_flavor_pack_scorch` | Flavor Pack: Scorch | Prescription | Your Heavy and Charged Heavy carry Scorch (replaces their element) | — | 1 | element:scorch |
| `sup_flavor_pack_brine` | Flavor Pack: Brine | Prescription | Heavies carry Brine | — | 1 | element:brine |
| `sup_flavor_pack_static` | Flavor Pack: Static | Prescription | Heavies carry Static | — | 1 | element:static |
| `sup_flavor_pack_sludge` | Flavor Pack: Sludge | Prescription | Heavies carry Sludge | — | 1 | element:sludge |
| `sup_flavor_pack_grit` | Flavor Pack: Grit | Prescription | Heavies carry Grit | — | 1 | element:grit |
| `sup_flavor_pack_gale` | Flavor Pack: Gale | Prescription | Heavies carry Gale | — | 1 | element:gale |
| `sup_counter_cream` | Counter Cream | Prescription | Parry window +0.03 s | — | 1 | parry |
| `sup_thick_skin_balm` | Thick Skin Balm | Prescription | Every hit on you deals −1 damage (min 1) | — | 2 | tank |
| `sup_zone_fertilizer` | Zone Fertilizer | Prescription | Your zones +25% radius and +1 s | — | 1 | zone |
| `sup_projectile_polish` | Projectile Polish | OTC | Your projectiles +20% speed, +1 m range | — | 1 | projectile |
| `sup_grab_glue` | Grab Glue | OTC | Grab hold +0.5 s; mash-escape needs 8 presses | — | 1 | grab |
| `sup_hurling_salve` | Hurling Salve | Prescription | Throw distance +30%, throw damage +2 | — | 1 | grab, arena |
| `sup_wake_up_call` | Wake-Up Call | OTC | Wake-up invulnerability +0.3 s, knockdown recovery +20% | — | 1 | tank |
| `sup_hype_leech` | Hype Leech | Prescription | Taking a hit gives +2 Hype instead of +1 | — | 1 | hype, tank |
| `sup_stim_patch` | Stim Patch | **Banned** | All ability cooldowns −30% | Stamina regen −30% | 1 | ability |
| `sup_bulk_powder` | Bulk Powder | OTC | Mass +15% (knockback taken −12%) | Walk speed −5% | 1 | tank |
| `sup_featherweight_tea` | Featherweight Tea | OTC | Mass −15%, dash +0.4 m | Knockback taken +15% | 1 | mobility |
| `sup_combo_candy` | Combo Candy | Prescription | L3 +3 damage, Finisher +3 damage | — | 1 | combo |
| `sup_dash_chalk` | Dash Chalk | OTC | Dash attacks +25% damage | — | 1 | mobility |
| `sup_reflex_gum` | Reflex Gum | Black Market | Dodge i-frames +0.05 s | — | 1 | mobility, parry |
| `sup_rest_easy` | Rest Easy Tea | OTC | Rest nodes heal +15% | — | 1 | sustain |
| `sup_bargain_bin` | Bargain Bin Card | Prescription | Every shop shows one extra Black Market item | — | 1 | economy |
| `sup_blood_money` | Blood Money | OTC | +40 Scrip per non-minion KO | −10 Scrip per knockdown suffered | 1 | economy |
| `sup_antidote_lozenge` | Antidote Lozenge | OTC (consumable) | Removes all your current side effects when taken (immediately on pick) | — | — | cleanse |
| `sup_crowd_pleaser` | Crowd Pleaser | Prescription | Taunting grants 1 s of armor | — | 1 | hype |
| `sup_minion_repellent` | Minion Repellent | OTC | Minions deal −30% damage to you | — | 1 | horde |
| `sup_elite_bounty` | Elite Bounty | Prescription | Elites offer 4 picks instead of 3 | — | 1 | economy |
| `sup_overdose_pill` | Overdose Pill | **Banned** | Damage dealt +35% | Max HP −25% | 1 | glass |
| `sup_pocket_ref` | Pocket Ref | Black Market | Once per fight, a knockdown on you is prevented (poise refills) | — | 1 | tank |
| `sup_lucky_tooth` | Lucky Tooth | Black Market | The first Heavy you land each fight breaks poise outright | — | 1 | heavy |
| `sup_tag_team_tonic` | Tag-Team Tonic | OTC | Co-op/tag: your assists and revives are 30% faster; solo: +5 max HP | — | 1 | coop |

### 7.3 Synergy tags (what the reward roller and the "build hint" UI use)

`heavy light combo parry grab pull arena zone status projectile blink mobility tank glass hype juice burst comeback sustain stamina economy horde coop cleanse charge air prop crowd counter element:<x>`. After the player holds ≥ 2 items sharing a tag, reward rolls give that tag's items +20% weight (max +40%), so builds converge without forcing.

### 7.4 Side effects (the satire layer)

Applied by some supplements, by `evt_needles_sample`/`evt_juice_crate`, and by **Dose 7**. Removed by Antidote Lozenge or the Rest "Rub-down".

| Id | Side effect | Effect |
|---|---|---|
| `se_tremors` | Tremors | Startup +5% on everything |
| `se_bloat` | Bloat | Walk speed −5% |
| `se_road_rage` | Road Rage | Hype decays 1/s while you are not attacking |
| `se_dry_mouth` | Dry Mouth | Stamina regen −10% |
| `se_hair_loss` | Hair Loss | Cosmetic only: crest/feathers/fin thin out. No effect. The label still warns about it. |
| `se_mood_swings` | Mood Swings | Each fight rolls damage ±10% |
| `se_cold_sweats` | Cold Sweats | Brine build-up taken +20% |
| `se_heartburn` | Heartburn | Scorch build-up taken +20% |
| `se_ringing_ears` | Ringing Ears | Parry window −0.02 s |
| `se_itchy_feet` | Itchy Feet | Dodge distance +0.3 m but dodges cost +3 stamina |

### 7.5 Shops (Needles' pop-up stall)

| Slot | Stock | Price (Scrip) |
|---|---|---|
| 3× supplements | rarity roll: OTC 50%, Prescription 35%, Black Market 13%, Banned 2% | OTC 40 · Prescription 75 · Black Market 130 · Banned 200 |
| 1× technique | one of the player's fighter techniques not yet owned | 90 |
| 1× service | one of: **Rub-down** (remove all side effects, 35), **Antidote** (one Antidote Lozenge, 30), **Reroll stock** (25, once per shop), **Sell** (any item for 50% of its price) | listed |
| Act 3 | adds a 4th supplement slot | — |

Prices × 1.3 on Dose 9+. Sponsor Patch and Bargain Bin modify slots as listed. Needles always has one line per visit (HUB.md has the dialogue pool).

### 7.6 Rest (Doc Sutura's table)

Pick **one**:

| Option | Effect |
|---|---|
| **Patch up** | Heal 30% max HP (+15% with Rest Easy Tea; 50% on Sparring difficulty; halved on Dose 10) |
| **Train** | Learn 1 technique (1 of 2 offered) — the only non-Elite/Boss/Shop technique source |
| **Rub-down** | Remove all side effects and heal 10% |
| **Film study** | Reveal the next act's elite and boss modifiers; +15 Hype carry |

## 8. Difficulty presets

| Preset | Enemy HP | Enemy damage | Bot tier | Reward modifier | Records |
|---|---|---|---|---|---|
| **Sparring** | × 0.8 | × 0.7 | Punching Bag (reaction 0.5 s, 35% mistakes, no parries or punishes) | Scrip × 0.85, Clout × 0.6 | Flagged "Sparring" on boards |
| **Amateur** (default) | × 1.0 | × 1.0 | Journeyman (reaction 0.36 s, 18% mistakes, rare parries) | × 1.0 | Standard |
| **Pro** | × 1.2 | × 1.25 | Contender (reaction 0.26 s, 10% mistakes, parries a quarter of the time) | Scrip × 1.15, Clout × 1.4 | Standard |
| **Title Shot** | × 1.4 | × 1.5 | Headliner (reaction 0.16 s, 5% mistakes, parries 40%, punishes, reads button-mashing, uses techniques well) | Scrip × 1.3, Clout × 2.0 | Required for Dose 6+ records |

Bot tiers above Headliner: **Hall-of-Famer** (reaction 0.1 s, 1% mistakes, reads charge-ups and mashing) exists only on Dose 10 and in custom matches. Bots never get hidden stat buffs; difficulty is HP/damage multipliers plus skill. Tier numbers were retuned against measured play (D-028, docs/BOTS.md).

## 9. The Dosage (challenge ladder)

Unlocked by completing a run on Amateur or higher. Clearing the highest unlocked Dose unlocks the next, up to Dose 10. Modifiers are cumulative. Each Dose has its own records board and a cosmetic (a JUICE-can profile badge, color-coded per Dose).

| Dose | Name | Modifier added |
|---|---|---|
| 1 | **Thin Wallet** | Scrip rewards −20% |
| 2 | **Extra Cardio** | Enemies +15% HP |
| 3 | **Cut Weight** | Your max HP −10% |
| 4 | **Mean Streak** | Enemies +15% damage |
| 5 | **Undercard Swarm** | Every normal Fight adds +1 Scrapling (loadout matches the arena) |
| 6 | **Juiced Opponents** | Enemy fighters start every fight with 50 Hype and one extra technique |
| 7 | **Side Effects** | Every supplement you take also applies a random side effect (§7.4) |
| 8 | **No Mercy** | Bosses enter phase 2 at 65% HP instead of 50% |
| 9 | **Hostile Venue** | All arena hazards always on at their shortest timers; shop prices +30% |
| 10 | **Lethal Dose** | Enemy bots are Hall-of-Famers; Rest heals half; the Title Card's elite is always The Commissioner's Cut |

Dose requires Amateur difficulty or higher; Doses 6+ require Pro or higher for the record board (they can still be played on Amateur for fun, flagged).

## 10. Fight Camp: persistent progression

Permanent upgrades are bought with **Clout** at stations in The Cannery (HUB.md). They are tagged `meta_bonus`, apply only inside Fight Camp runs (and to custom matches that enable "Gym Bonuses", shown as a rule tag), and never load in standard PvP, Off the Street, or ranked anything.

### 10.1 Cannery upgrades (24)

| Id | Upgrade | Station | Cost (Clout) | Levels | Effect per level | Unlock gate |
|---|---|---|---|---|---|---|
| `meta_heavy_bag` | Heavy Bag | Gym Floor | 80 / 160 / 320 | 3 | Damage +2% | — |
| `meta_speed_bag` | Speed Bag | Gym Floor | 80 / 160 / 320 | 3 | Light startup −2% | — |
| `meta_squat_rack` | Squat Rack | Gym Floor | 100 / 200 / 400 | 3 | Max HP +4 | — |
| `meta_cardio_bikes` | Cardio Bikes | Gym Floor | 100 / 200 | 2 | Max stamina +6 | — |
| `meta_grappling_dummy` | Grappling Dummy | Gym Floor | 120 / 240 | 2 | Throw damage +1, grab reach +0.05 m | Beat Act 1 once |
| `meta_mat_room` | Mat Room | Gym Floor | 150 | 1 | Poise +8 | Beat Act 1 once |
| `meta_ice_bath` | Ice Bath | Med Bay | 120 / 240 | 2 | Rest "Patch up" heals +8% | — |
| `meta_cut_corner` | Cut Corner | Med Bay | 150 | 1 | Boss victories heal +15% | Beat Act 2 once |
| `meta_sutures` | Sutures | Med Bay | 100 / 200 | 2 | Heal 4% max HP after every fight | — |
| `meta_juice_bar_tab` | Juice Bar Tab | Juice Bar | 100 / 200 | 2 | Shop prices −8% | — |
| `meta_needles_connect` | Needles' Connection | Juice Bar | 250 | 1 | Shops always stock one Black Market item | Beat Act 2 once |
| `meta_label_reader` | Label Reader | Juice Bar | 150 | 1 | Side effects are shown before you pick | — |
| `meta_antidote_stash` | Antidote Stash | Juice Bar | 200 | 1 | Start each run with one Antidote Lozenge | — |
| `meta_sponsorship` | Sponsorship Deal | Office | 120 / 240 / 480 | 3 | Start each run with +40 Scrip | — |
| `meta_scouting_report` | Scouting Report | Office | 200 | 1 | The map reveals node types one row further | — |
| `meta_reroll_token` | Reroll Token | Office | 180 / 360 | 2 | +1 free reward reroll per run | — |
| `meta_cornermans_eye` | Cornerman's Eye | Office | 220 | 1 | Row 1 Fights also offer a technique pick (1 of 2) | Beat Act 1 once |
| `meta_film_room` | Film Room | Office | 160 | 1 | Boss phase-2 tells are shown on the HUD (attack names appear 0.3 s earlier) | Beat Act 2 once |
| `meta_crowd_connection` | Crowd Connection | Loading Dock | 140 / 280 | 2 | Hype gain +5% | — |
| `meta_walkout` | Walkout Music | Loading Dock | 200 | 1 | Start every fight with 15 Hype | Beat a run once |
| `meta_second_skin` | Second Skin | Loading Dock | 300 | 1 | Knockback taken −8% | Beat a run once |
| `meta_bookies_favor` | Bookie's Favor | Boiler Room | 150 | 1 | Clout rewards +15% | — |
| `meta_boiler_room_key` | Boiler Room Key | Boiler Room | 100 | 1 | Unlocks the AI Lab terminal's "train vs my saved builds" scenario list | — |
| `meta_title_contender` | Title Contender | Office | 500 | 1 | Dose records from Fight Camp count toward the shared cosmetics track | Clear Dose 3 |

### 10.2 Unlock pacing

| Milestone | Approx. Clout earned | Expected purchases |
|---|---|---|
| First run (lost at Act 1 boss) | 60–120 | one Gym Floor level |
| First Act 1 clear | +150 | two upgrades |
| First full run (Amateur) | +400 | six to eight upgrades total |
| Ten runs | ~2,500 | all level-1s, half the level-2s |
| All 24 maxed | ~7,600 | ~25–30 runs on Amateur, ~15 on Title Shot |

Fight Camp's total combat power at max is roughly **+6% damage, +12 HP, +12 stamina, +8 poise**: real, but far smaller than one run's supplements. The point of the tree is convenience and consistency (shops, rerolls, scouting), not raw power — so a Fight Camp Dose 10 clear is still a skill achievement.

## 11. Co-op recommendations

Both variants support 2–4 humans. **Simultaneous allied combat** is the default; **tag-team** is a session setting. Each player picks their own fighter and runs their own build; the party shares one map.

| Topic | Recommendation |
|---|---|
| Run ownership | The host owns the save; every member receives a **party ticket** (seed + decisions log) after each node so the run can be resumed by any member if the host is gone (§ below). |
| Route voting | 10 s vote at each row. Majority wins. **Tie** → the **Captain** decides. Captain = host for Act 1, then rotates to the next player each act (so everyone captains once in a 3-player party; in 4-player the lowest-HP player at the act boundary captains). No vote = abstain; all abstain = Captain's pick (auto-random after 10 s if the Captain is idle). |
| Reward picks | Each player gets their own 3-option draft from their own sub-seed; techniques are fighter-specific so duplicates are impossible; supplements may be identical across players (that's fine: they're separate inventories). Treasure/Boss picks are per player. Scrip wallets are per player; events that cost Scrip charge the **choosing** player unless they are "group" events (marked, split evenly, rounding up on the Captain). |
| Event choices | The player who enters the event node's prompt first decides, except group events which vote (tie → Captain). Fighter-specific events only trigger for the matching player and only affect them. |
| Shop/Rest | Each player uses the shop/rest independently with a 90 s timer; "Ready" skips. |
| Downed / revive (simultaneous) | At 0 HP a player is **Downed** (limp ragdoll, 15 s timer, can crawl 0.5 m/s). An ally revives by holding **Grab (B)** within 1.5 m for 2.0 s (interrupted by any hit). Revived at 30% HP with 1 s invulnerability. Timer expiry → **Out** for the rest of the fight. All downed/out → defeat. The downed timer shortens by 5 s per prior down in the same fight (15 → 10 → 5). After a won fight, Out players return at 50% HP. |
| Tag-team participation | One active fighter per side. Tag = D-pad Down (1.5 s entry invulnerability, 8 s tag cooldown, no tag while being hit or grabbed). Tagged-out partner: regenerates 3 HP/s and 10 stamina/s, can **Cheer** (D-pad Up, +5 Hype to the active fighter, 3 s cooldown) and can call **one Assist per 20 s** (LB: a 1-hit cameo of their Dash Attack or Ability 1 at the active fighter's lock-on target). Being tagged out is never idle: cheering and assist timing are the job. |
| Disconnect | A bot (tier = preset tier, capped at Contender) takes the fighter immediately; picks are auto-chosen by tag synergy; the player can rejoin at any node boundary and reclaim the fighter with its current state. |
| Host departure | The run pauses 60 s for the host to return. If not, the party ticket lets the next member (Captain first) resume as host from the last node boundary; if everyone leaves, the run is suspended and resumable later by the original host, who can invite the same or new members. No host migration mid-fight; a fight in progress is re-run from its start on resume. |
| Pause | Solo: real pause. Co-op: a "ref timeout" (hold Start): the fight freezes for up to 30 s per player per run; otherwise, menus do not pause. |
| Scaling (simultaneous) | Enemy count × 1 / 1.5 / 2 / 2.5 for 1–4 players (round up; when the template has a single fighter, add Scraplings instead of duplicating fighters until 3+ players, at which point a second fighter is added). Enemy HP × (1 + 0.35 × (players − 1)). Enemy damage × (1 + 0.10 × (players − 1)). Boss HP × (1 + 0.6 × (players − 1)); bosses rotate targets every 8 s and use Objection-style pushes to split groups. |
| Scaling (tag-team) | Enemy count × 1. Boss HP × 1.3 regardless of party size (one active fighter). Enemy tag bouts become symmetric tag bouts. |
| Rewards in co-op | Scrip per player at 100% (no split). Clout per player at 100%. Records for the party are tagged with the party size. |
| Progression compatibility | A Fight Camp player and an Off the Street player can co-op: the session takes the host's variant; Cannery upgrades apply only to Fight Camp hosts' sessions and only to players who have them (shown as a rule tag "Gym Bonuses: Player 1, Player 3"). |
| Absent participant | If a member has not acted for 60 s at a node boundary, the Captain can "move on"; the absent player's picks are auto-chosen. |

## 12. Victory, defeat, replay

| Moment | Flow |
|---|---|
| Victory | Snappington signs the belt over → results card (time, Dose, fighter, build, KOs, biggest hit, taunts) → cosmetics unlocked (per-fighter belt skin on first clear, Dose badge) → Clout tally → "Run it back" (same seed), "New card" (new seed), or "Raise the Dose" if a new Dose unlocked. |
| Defeat | Announcer eulogy → results card → the run's build is saved as a **saved build** (used by the AI Lab scenario list and the mirror-match elite) → "Run it back" / "New card". |
| Records | Per fighter × variant × difficulty × Dose: fastest clear, fewest knockdowns suffered, no-hit boss flags, highest Scrip hoard. |
| Unlock pacing (Off the Street) | First clear on Amateur: The Dosage. Each fighter's first clear: that fighter's title cosmetic. Dose 5: alternate announcer jacket (cosmetic). Dose 10: "Lethal Dose" badge and a crowd chant. Nothing unlocks power. |
| Autobattler | The Bookie's Table (MODES.md §2.8) runs the same card with AI piloting the fights; its records are a separate board. |
