# CRITTERWEIGHT — Modes

Standard formats first, then four bonus modes that change the objective or constraint rather than the numbers. All modes run through the same rules-editor preset schema; each lists the rule options and markers it needs so presets validate.

## 1. Standard formats

| Format | Players | Teams | Default rules | Notes |
|---|---|---|---|---|
| **1v1** | 2 (humans or bots) | — | Best of 3 rounds × 99 s; KO or time (higher HP% wins; tie → sudden death 15 s, first hit wins) | The normal solo and ranked format |
| **Free-for-All** | 3–8 | — | 1 round, 180 s or last standing; score = KOs ×3 + damage/20 + knockdowns; respawns **off** by default (optional: 3 lives) | The Gullet, The Crusher, The Rooftop |
| **Teams** | 4–8 | 2v2, 3v3, 4v4, 2v2v2v2 | Best of 3 rounds; a round ends when one team is fully KO'd (or 120 s → team HP% total) | Friendly fire off by default (reactions follow ELEMENTS.md §7) |
| **Co-op Simultaneous** | 2–4 humans + bots | humans vs enemy groups | Campaign rules (CAMPAIGN.md §11); also available as a custom "Allied Brawl" vs bot groups | Default co-op format |
| **Co-op Tag-Team** | 2 humans per side (or 1 human + 1 bot) | 2 sides | One active fighter per side; tag with D-pad Down; tagged-out regen/cheer/assist (CAMPAIGN.md §11) | Campaign setting; also a PvP format (2v2 tag) |
| **Practice** | 1 (+ dummy/bot) | — | No timer; dummy modes: stand / guard / parry / counter / record-and-replay; telemetry HUD (hit speed, clean %, poise, build-up bars, frame data overlay) | Any arena, any hazard toggles, any boss as a dummy |
| **Spectator / AI vs AI** | 0 humans, 2–8 bots | any | Any format; free camera, follow cam, auto-director; HUD toggles; 0.5×–4× speed | Used by playlists when the server is empty |
| **The Bookie's Table (autobattler run)** | 1 human (choices) | — | A full campaign card where the AI pilots the fights; the human picks fighter, route, rewards, shop, rest; "Unattended" lets Teddy pick by tag synergy and keeps going; pause/take-over at any node; speed 1×–4×, camera presets | Records on its own board; Clout at 50% |

### Shared options every preset exposes (rules editor)

| Group | Options |
|---|---|
| Format | rounds, round time, win condition (KO / time / score / objective), sudden death on/off |
| Resources | HP ×, stamina ×, poise ×, Hype gain ×, starting Hype, regen × |
| Damage | damage ×, knockback ×, build-up ×, friendly fire on/off (and %), reactions on/off |
| Players | human slots, bot slots, bot tier, team assignment, respawns/lives, revive on/off |
| Restrictions | abilities on/off per slot, JUICE on/off, grabs on/off, taunts on/off, element lock |
| Arena | base, layout, hazard timers (×), hazards on/off, gravity ×, ring-outs on/off |
| Meta | Gym Bonuses (Fight Camp meta upgrades) on/off — visible tag; techniques/supplements loadouts allowed in custom (visible tag) |

### Scoring and referee (standard 1v1, v0.9.16)

Two independent options of the standard mode, Duel format only (DECISIONS D-044, D-046):

| Option | Values | What it does |
|---|---|---|
| Scoring | **Health** (default) / **10-point must** | Health: today's rules (KO wins the round, at time the healthier fighter wins it, best of N). 10-point must: fighters cannot be knocked out by damage (HP stays full and the bars are hidden); every round is fought; three judges (Even card, Volume, Impact) score each round 10-9 (10-10 too close to call, 10-8 dominant) from damage, clean strikes, knockdowns, throws, ring-outs, parries and guard breaks; the cards decide (Unanimous/Majority/Split Decision or Draw). A drawn decision goes to sudden death when Sudden death is on, otherwise it is a draw. |
| Referee | off (default) / on | No hits land on a downed fighter; the referee counts strike knockdowns and waves the fighter up after 4 s (getting up earlier is allowed; staying down recovers stamina faster); bots back off; five strike knockdowns in one round stop it (10-point: T.K.O. ends the fight; Health: ends the round). Jeremy's Cage Rules referee walks the cage, holds the attacker off, waves fights off and raises the winner's arm (view only). |

The built-in **Cage Rules** preset is the Standard Duel with 10-point scoring and the referee on (D-047).

## 2. Bonus modes

### 2.1 SPOTLIGHT HOG — `mode_spotlight_hog` (objective control)

| Field | Value |
|---|---|
| Pitch | A roaming stage spotlight. Stand in it alone to score. The cameras love a hog. |
| Players | 2–8; FFA or 2–4 teams |
| Objective | A spotlight (r 2.0 m) sits on one **spotlight anchor** (layout marker) for 25 s, then "swings" (1.5 s travel, telegraphed by a sweeping beam) to the next anchor in a seeded order. A fighter standing in it **alone** (no enemy inside) scores **1 point per second**; a team scores if only that team is inside. Contested (enemies from 2+ sides inside) = nobody scores. Knockdowns inside the light do not score for the downed fighter. |
| Win | First to 60 points, or highest at 5 min. Ties → the light shrinks to r 1 m and sudden-death: first 5 uncontested seconds wins. |
| KO rules | KO'd fighters respawn after 5 s at the spawn farthest from the light. KOs give +3 points. |
| Bot behavior | Bots path to the light, fight on it, and leave when outnumbered 2+; Headliner bots pre-move to the next anchor at 22 s. |
| Special rules (editor) | Light radius, dwell time, point target, contest rule (strict / majority), KO points, spawn distance, "Hot Light" (the light is also a Scorch zone 5 build-up/s — optional, off by default) |
| Markers | ≥ 3 `marker_spotlight_anchor`; 8 spawns |
| HUD | Score bar per side across the top; a **beam indicator** on the screen edge pointing at the light; a 3-2-1 countdown ring on the light before it swings; "HOG" tag over whoever is scoring |
| Best arenas | The Crusher (Crusher King layout), The Gullet |

### 2.2 CHUMBALL — `mode_chumball` (physics ball)

| Field | Value |
|---|---|
| Pitch | A 25 kg bale of chum wrapped in tape. Two goals. Hit it, throw it, Bulldoze it, Gust Bomb it. Fighters are the sticks. |
| Players | 2–8 in 2 teams (1v1 to 4v4) |
| The ball | A physics sphere r 0.5 m, 25 kg, high restitution. **Any weapon-point contact** with closing speed moves it with the hit's knockback × 2; projectiles push it by their knockback; pushes/pulls/vortices affect it; **Grab (B)** picks it up (carrier walks at −20% speed, cannot attack, can throw with a direction: 6 m lob). Being hit while carrying drops it. The ball takes elements: it carries the last element that hit it for 3 s and applies 20 build-up on contact with a fighter (so a Scorch-hit ball Sizzles the goalie who guards it). |
| Objective | Push the ball across the opponent's **goal** line (3 m wide marker on a wall). Goal = 1 point; the ball respawns at the center after 3 s; both teams reset to spawns (no reset on the "Chaos" option). |
| Win | First to 5, or most at 4 min. Tie → golden goal. |
| KO rules | KO'd fighters respawn at their goal after 6 s. KOs give nothing; the ball gives everything. |
| Bot behavior | One bot per team is "keeper" (stays within 4 m of the goal, guards the ball, punches it clear); the others chase, with Dozer/Dredge preferring to body the ball and Gusto/Jitters preferring to lob. |
| Special rules (editor) | Ball mass (10–60 kg), ball count (1–3), goal width, goal target, "No carry" (grab disabled), "Hot ball" (the ball deals 4 dmg on contact at > 6 m/s), own-goal rule (on/off), "Chaos" (no reset after goals) |
| Markers | 2 `marker_goal` (team-tagged), 1 `marker_ball_spawn`, 2 team spawn clusters |
| HUD | Score per team; a ball indicator on screen edge; carrier tag; a "goal flash" with the scorer's name; last-touch element icon on the ball |
| Best arenas | Drydock (Drydock Pitch layout), The Gullet |

### 2.3 ABSOLUTE UNIT — `mode_absolute_unit` (asymmetric juggernaut)

| Field | Value |
|---|---|
| Pitch | One fighter drinks the whole crate. Everyone else tries to take it off them. |
| Players | 3–8, FFA |
| The Unit | The current Unit is scaled to **1.6× size and 3× mass**, HP = 2.5 × their base, permanent armor vs Lights, damage × 1.5, knockback dealt × 1.5, **cannot dodge**, abilities on 2× cooldown, JUICE disabled, walk speed −15%. Visibly glowing green with a crown of JUICE cans. |
| Objective | Score **1 point per second as the Unit**. Whoever lands the KO on the Unit becomes the next Unit (spawns at the `marker_unit_spawn` after a 2 s transformation with 1 s invulnerability). Non-Units deal full damage to each other but it is a waste of time. |
| Win | First to 90 points as the Unit, or highest at 5 min. |
| KO rules | Non-Unit fighters respawn after 4 s at a spawn ≥ 6 m from the Unit. |
| Bot behavior | Bots converge on the Unit; Headliner bots time grabs for when the Unit's armor doesn't matter (grabs beat armor: throws work on the Unit at 0.5× distance). The Unit bot targets whoever has the most points. |
| Special rules (editor) | Unit size/mass/HP multipliers, point target, "Hot potato" (the Unit loses 1 point per 5 s not hitting anyone), "Pass the crate" (Unit can hand off by grabbing an ally — team variant), Unit JUICE allowed (off) |
| Markers | 1 `marker_unit_spawn`; 8 spawns |
| HUD | The Unit's HP bar top center with a crown; points list on the right; a halo arrow to the Unit; a "YOU ARE THE UNIT" banner on transformation |
| Best arenas | The Gullet (The Unit Pit layout), The Rooftop (ring-outs on the Unit count as a KO credited to the last hitter) |

### 2.4 CHUM RUSH — `mode_chum_rush` (survival waves with NPCs)

| Field | Value |
|---|---|
| Pitch | Bargain night. The league throws every Scrapling and Blister it owns through the gates, then a headliner every ten waves. Survive. |
| Players | 1–4 co-op (simultaneous) + optional bots as allies |
| Waves | Endless, seeded. Wave n spawns `3 + n` minions (cap 16 alive) through the layout's **wave gates** over 10 s; composition shifts by wave: 1–4 Scraplings, 5–9 adds Blisters and Pelters, 10 is a **headliner** (Bilge at 60% HP, phase 1 only), 11–19 elemental loadouts, 20 headliner (Conduit, 60%, phase 1), 21–29 mixed + enemy roster fighters (1 per wave, 1 technique), 30 headliner (Snappington, 60%, phase 1), then loop with +10% HP per 10 waves. A wave ends when all enemies are dead; 8 s break; every 5th break offers a **pick** (3 supplements, OTC/Prescription) and a `prop_chum_bucket` respawn. |
| Objective | Highest wave reached; score = kills × 10 + wave clears × 100 + headliner kills × 500 − downs × 50. |
| Win / end | The run ends when all players are Out (downed timers as in co-op). "Quit at break" banks the score. |
| Revives | As in co-op (hold B 2 s); the downed timer resets to 15 s each wave. |
| Bot behavior | Minions as ENEMIES_BOSSES.md; ally bots (optional) prioritize revives, then Blisters. |
| Special rules (editor) | Starting wave, wave size ×, headliner interval, alive cap, Blister ratio, picks on/off, "Last Call" (10-minute hard cap, score only), "Night Shift" (all minions carry elements) |
| Markers | ≥ 2 `marker_wave_gate`; player spawn cluster; optional chum buckets |
| HUD | Wave number and enemies-remaining counter top center; a gate indicator when a wave spawns; down timers over allies; pick banner on 5th breaks |
| Best arenas | The Rooftop (Rooftop Gauntlet layout), Drydock, the secret "Pier Night" variant (HUB.md secret #8) |

## 3. Mode summary

| Mode | Objective | Constraint | Players | Teams | NPCs |
|---|---|---|---|---|---|
| Spotlight Hog | hold a moving zone | contested = nobody scores | 2–8 | FFA or 2–4 | bots |
| Chumball | score with a physics ball | the ball is the only thing that scores | 2–8 | 2 | keeper bots |
| Absolute Unit | be the Unit | the Unit cannot dodge; KO the Unit to become it | 3–8 | FFA | bots |
| Chum Rush | survive waves | endless escalation, revives | 1–4 | co-op | minions + headliners |

All four are supported by playlists (weights, voting), by bots, by the arena editor (markers listed), by custom rules, and by dedicated servers. None depends on a damage multiplier for its identity.

## 4. Playlist defaults (examples the server ships)

| Playlist | Entries (weight) | Min players |
|---|---|---|
| **Fight Night** | 1v1 Gullet (5), 1v1 Drydock (2), 2v2 Gullet (3) | 2 |
| **Bargain Bin** | FFA Crusher (3), Spotlight Hog Crusher King (3), Absolute Unit Unit Pit (2), Chumball Drydock Pitch (2) | 3 |
| **Cannery Co-op** | Chum Rush Rooftop Gauntlet (4), Chum Rush Drydock (2) | 1 |

Vote between 3 candidates drawn by weight with repeat avoidance (the last 2 played are excluded); no votes → the highest-weight candidate; an empty server runs AI-vs-AI on the same rotation.
