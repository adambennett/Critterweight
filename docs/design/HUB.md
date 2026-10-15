# CRITTERWEIGHT — The Cannery (Fight Camp hub)

The persistent-progression campaign (**Fight Camp**) is played from **The Cannery**: the Circuit's decommissioned fish cannery, now the league's training compound. It is a real, walkable 3D place: seven connected spaces, eight NPCs, five activities, upgrade stations, ten secrets, and ambient life. The player walks it with the fight controls (move, Light/Heavy work on bags and crates, Grab picks things up, A interacts).

## 1. Layout

Overall footprint ≈ **46 × 34 m** on two levels plus a basement and a roof. Walk time corner to corner ≈ 25 s at 3.4 m/s. Nothing requires a load screen; the roof and basement stream in.

```
                         N (harbor side)
   +----------------------------------------------------------------+
   |                      LOADING DOCK (exterior)                   |
   |   20 x 12 m   crates . forklift . chum cannon . water edge     |
   |   [crate toss]   [chum cannon dodge drill]   (secret: pier)     |
   +------------+-------------------[roller door 4m]----------------+
   |  JUICE BAR |                                        |  MED BAY  |
   |  10 x 8 m  |            MAIN FLOOR (gym)            |  8 x 8 m  |
   |  Needles   |            24 x 16 m                   | Doc Sutura|
   |  [shop]    |   heavy bags . practice cage . mats    | [rest st.]|
   |  [upgrade] |   [heavy bag score] [ring sparring]    | [upgrade] |
   |            |   Granny's corner (tutorial)           |           |
   +----[door]--+----------+-----------------+-----------+--[door]---+
   |  LOCKER ROOM          |  stairs up ->   |  BROADCAST BOOTH      |
   |  12 x 8 m             |  OFFICE (mezz.) |  6 x 4 m (glass, +3m) |
   |  Wall of Fame/Shame   |  8 x 6 m        |  Barnaby Bellows      |
   |  Kid Lamprey . lockers|  Snappington    |  [announcer settings] |
   |  [belt case] [records]|  [run start]    |                       |
   +-----------------------+--[hatch down]---+-----------------------+
                           |  BOILER ROOM (basement) 14 x 10 m       |
                           |  Teddy Two-Tooth . AI Lab terminal      |
                           |  [Bookie's Table]  [AI Lab]  (secrets)  |
                           +-----------------------------------------+
   ROOF (secret, 16 x 12 m): reached by the broken freight elevator (fixed via secret #6)
```

| Space | Size | Connections | Purpose |
|---|---|---|---|
| **Main Floor** | 24 × 16 m, 7 m ceiling | Roller door N → Loading Dock; doors W → Juice Bar, E → Med Bay; S → Locker Room, stairs → Office, Broadcast Booth window above | Central gym: 3 heavy bags, a practice cage (a 6 m mini-Gullet), mats, Granny's corner. Hub spawn point. |
| **Juice Bar** | 10 × 8 m | Main Floor | Needles' counter: shop preview, Juice Bar upgrade station, vending machine |
| **Med Bay** | 8 × 8 m | Main Floor | Doc Sutura: Med Bay upgrade station, Rest preview, the dumpster ice bath |
| **Loading Dock** (exterior) | 20 × 12 m, open sky | Main Floor (roller door), pier ladder (secret) | Crate Toss, Chum Cannon drill, Dock upgrade station (Ludlow's workbench), the water's edge |
| **Locker Room** | 12 × 8 m | Main Floor | Lockers (cosmetics/loadouts), Wall of Fame/Shame (records), belt case, Kid Lamprey |
| **Commissioner's Office** (mezzanine, +4 m) | 8 × 6 m | Stairs from Main Floor; window over the floor | Snappington's desk = **run start** (pick fighter, difficulty, Dose, co-op); Office upgrade station; filing cabinets |
| **Broadcast Booth** (+3 m) | 6 × 4 m, glass front | Ladder from Locker Room | Barnaby Bellows; announcer settings (volume, line packs unlocked); replay viewer |
| **Boiler Room** (basement, −4 m) | 14 × 10 m | Hatch under the stairs | Teddy's Bookie's Table (autobattler), the AI Lab terminal, the boiler (secret), the Boiler Room upgrade station |
| **Roof** (secret) | 16 × 12 m | Freight elevator (after secret #6) | A view, a neon sign, a secret cosmetic, and the Rooftop arena's "practice" variant |

Doors are 2 m wide; the roller door is 4 m. Every space has at least two light sources and one landmark visible from its entrance (the bags, the neon can, the belt case, the desk, the boiler) so navigation never needs a minimap. A corkboard **map** by the roller door shows the layout anyway.

## 2. NPCs

| NPC | Species | Role | Where | Personality | Sample dialogue |
|---|---|---|---|---|---|
| **Granny Haymaker** | possum, 4 feet tall, tracksuit, one gold tooth | Head coach; runs the tutorial and the heavy-bag challenge; comments on your last run | Main Floor, Granny's corner (a folding chair and a cooler) | Gruff, warm, zero patience for excuses, bare-knuckle champ of the cannery era | "You lost to a *dog*? Fine. Dogs are fast. Show me your guard." · "Hands up. Chin down. Everything else is details." · "Hit the bag like it owes you Scrip." |
| **Commissioner Snappington** | ancient snapping turtle, reading glasses, gavel | Runs the league; starts runs; sells Office upgrades; final boss | Office desk (never seen moving) | Dry, bureaucratic, faintly menacing, means every word of the rulebook she wrote | "Sign here. And here. The waiver is mostly decorative." · "The Commission has reviewed your conduct and found it entertaining." · "Title shots are earned. Or purchased. Mostly earned." |
| **Needles** | porcupine in a lab coat two sizes too big | Juice Bar vendor; supplements, side effects, denials | Juice Bar counter | Fast-talking, sincere, believes every label; sweats constantly | "Everything here is natural. *Everything*. Some of it was natural very recently." · "Side effects? Define 'side'." · "This one makes your heavy hit harder. Also your hair might fall out. Mostly the first thing." |
| **Doc Sutura** | octopus veterinarian, eight hands, one cigarette she never lights | Cut-woman; Rest; Med Bay upgrades | Med Bay | Brisk, unimpressed, competent; talks while stitching | "Hold still. Hold stiller." · "That's not blood, that's JUICE. That's worse." · "You'll live. That's a medical opinion and a threat." |
| **Kid Lamprey** | lamprey in a hoodie, hood always up, mouthful of teeth | Sparring partner; rival; tutorial opponent (easy bot) | Locker Room, leaning on lockers; appears in the practice cage when challenged | Cocky, insecure, secretly a huge fan | "I'd fight you but my coach says I'd get sued." · "Rematch. Rematch. Rematch. I'm just saying the word now." · (after losing) "I let you have that one. The next thirty too, probably." |
| **Ludlow** | elderly walrus janitor, mop, ring-crew jacket from decades ago | Keeper of secrets; Dock upgrades; hints; fixes the elevator | Loading Dock, wandering the Main Floor with the mop | Slow, kind, remembers everything, speaks in trailing sentences | "Used to be a freight elevator there. Still is, I suppose. Just doesn't..." · "There's a loose panel behind bag three. Don't tell the Commissioner. Tell me what you find." · "Bellows wasn't always a pelican. Well. He was. But he was a *quieter* one." |
| **Teddy Two-Tooth** | rat bookie, tiny visor, enormous ledger | Runs the Bookie's Table (autobattler) and Boiler Room upgrades | Boiler Room, at a card table under one bulb | Wheedling, cheerful, always counting | "No real money. Just Scrip. Fake Scrip. Fake-er Scrip." · "Odds on the bird are long. The bird keeps winning. I don't understand the bird." · "Sit. Watch. Pick. Don't touch the dice." |
| **Barnaby Bellows** | pelican in a sequined jacket, gullet pouch like a megaphone | Announcer; replays; line packs | Broadcast Booth | Boundless enthusiasm, auctioneer cadence, cries at every title fight | "WELCOME, welcome, WELCOME to the booth, where the magic — the *magic* — is me." · "I've called four thousand fights and I remember every single one of yours, kid. Both of them." · "Say the word and I'll re-call your last fight. Louder." |

Ambient NPCs (non-interactive, cosmetic): two dock gulls that steal from the chum cannon, a sleeping Scrapling under the stairs (wakes if you hit the bag hard enough; secret #3), a referee goat on a smoke break by the roller door, three crowd regulars in the practice cage bleachers who react to your sparring.

## 3. Activities

| Activity | Where | How it works | Rewards |
|---|---|---|---|
| **Heavy Bag Score Challenge** | Main Floor, bag 1 (Granny) | 30 s. The bag is a physics prop; each hit scores from closing speed and clean contact (same formula as combat), ×1.5 for a Heavy, ×2 for a Finisher, +combo multiplier for hits within 0.6 s. Three bags: **Light bag** (speed), **Heavy bag** (power), **Body bag** (shaped like Snappington; score only counts head/shell hits). | Score tiers: 300 / 600 / 1000 → 10 / 25 / 50 Clout (once per tier per fighter); bag 3's 1000 unlocks secret #1's hint |
| **Chum Cannon Dodge Drill** | Loading Dock (Ludlow's cannon) | A pneumatic cannon lobs chum buckets at you in a 4 × 4 m square for 45 s with rising speed; buckets are physical projectiles (3 dmg, no real HP loss — "drill HP"). Dodge, parry (parrying a bucket pops it for +5), or guard. Streak counter. | Streak 15 / 30 / 50 → 10 / 25 / 50 Clout; streak 50 unlocks the "Soaked" profile frame |
| **Crate Toss** | Loading Dock | Grab (B) a crate, throw it into painted target rings at 3 / 5 / 8 m (physics throw, same as a fighter throw with the fighter's throw stats). 10 crates. Dredge and Dozer throw far; Jitters throws... less. | 30 / 60 / 100 points → 10 / 25 / 50 Clout; 100 with Jitters unlocks secret #8's hint |
| **Ring Sparring** | Main Floor practice cage | Challenge Kid Lamprey (easy bot, any fighter) or any fighter at any bot tier; optional modifiers (low gravity, hazards). No stakes. Doubles as practice mode with HUD telemetry (hit speed, clean %, poise). | First win vs Kid Lamprey at Contender: 25 Clout; per-fighter "beat Headliner" badge |
| **The Bookie's Table** | Boiler Room | The autobattler (MODES.md §2.8): you pick fighter, route, picks; Teddy's "dice" (AI) fight. Watch, speed up, or walk away (unattended mode) and come back. | Clout at 50% of a played run; Bookie's board records |

## 4. Upgrade stations (Clout → Cannery upgrades, CAMPAIGN.md §10)

| Station | Where | Sells |
|---|---|---|
| **Gym Floor station** (Granny's clipboard) | Main Floor | Heavy Bag, Speed Bag, Squat Rack, Cardio Bikes, Grappling Dummy, Mat Room |
| **Med Bay station** (Doc's chart) | Med Bay | Ice Bath, Cut Corner, Sutures |
| **Juice Bar station** (Needles' menu) | Juice Bar | Juice Bar Tab, Needles' Connection, Label Reader, Antidote Stash |
| **Office station** (Snappington's ledger) | Office | Sponsorship Deal, Scouting Report, Reroll Token, Cornerman's Eye, Film Room, Title Contender |
| **Dock station** (Ludlow's workbench) | Loading Dock | Crowd Connection, Walkout Music, Second Skin |
| **Boiler Room station** (Teddy's ledger) | Boiler Room | Bookie's Favor, Boiler Room Key |

Each purchase is **visible in the world**: bags appear, bikes line up, the ice bath gains a lid, the Office gets a second filing cabinet, the Loading Dock gets a sound system. At 12+ purchases the Main Floor's dead fluorescents are replaced with working ones; at all 24 the Glandco banner over the practice cage is replaced by one with the player's fighter on it.

## 5. Secrets (10)

| # | Id | What | Where | How to find | Reward |
|---|---|---|---|---|---|
| 1 | `sec_loose_panel` | Loose wall panel | Main Floor, behind heavy bag 3 | Hit bag 3 with a Charged Heavy; it swings wide and reveals a panel; Grab it to pull it off | 50 Clout + Ludlow's "Panel Pal" dialogue; opens a crawlspace to secret #2 |
| 2 | `sec_crawlspace_tooth` | Granny's old tooth in a jar | The crawlspace behind #1 (3 m tunnel) | Walk in; the jar is on a shelf | Cosmetic: "Gold Tooth" detachable-piece swap for any fighter (the gag piece becomes a gold tooth) |
| 3 | `sec_sleeping_scrapling` | Sleeping Scrapling under the stairs | Main Floor, under the Office stairs | Score 600+ on the heavy bag; it wakes and runs to the Loading Dock, dropping its lid | Cosmetic: trash-can lid "shield" idle prop; +25 Clout if you catch it before the roller door (Grab) |
| 4 | `sec_belt_case_combo` | The belt case opens | Locker Room | Taunt in front of the case three times; Kid Lamprey says "...it's not even locked"; press A | The replica belt (cosmetic back-piece for the walkout); the real one is "at the cleaners" |
| 5 | `sec_booth_tape` | A dusty tape labeled "1973" | Broadcast Booth, under Barnaby's chair | Crouch (guard) under the desk and press A | Replay of the Commissioner's 1973 title fight (a 40 s AI-vs-AI replay vs a silhouette), unlocks the "Vintage Bellows" announcer line pack |
| 6 | `sec_freight_elevator` | The broken freight elevator | Main Floor, NE corner, a chain gate | Ludlow needs 3 parts: a **fuse** (Boiler Room, on the boiler's side, Grab), a **cable spool** (Loading Dock, behind the forklift), and a **button** (Office, in the second filing cabinet — needs Scouting Report bought). Give them to Ludlow. | Opens the **Roof** |
| 7 | `sec_roof_sign` | The neon sign's missing letter | Roof | The sign reads "GL NDCO"; the "A" is lying by the water tower leg; Grab and throw it at the sign (Crate Toss skill) | Sign fixed: Rooftop arena night variant gets full neon; cosmetic profile frame "Sign Fixer"; 100 Clout |
| 8 | `sec_pier_ladder` | The pier under the dock | Loading Dock, water's edge | Throw a crate 8 m+ into the water (Crate Toss 100 points, Jitters version hints at it); a ladder is revealed when the splash scares the gulls off it | A tiny pier with a fishing rod: a 20 s mini-idle "fishing" that reels in one random OTC supplement cosmetic variant and, once, the **Chum Rush** mode's hidden arena variant "Pier Night" |
| 9 | `sec_boiler_face` | A face in the boiler | Boiler Room | Hit the boiler with any Scorch attack (Stoke, or a Flavor Pack Scorch Heavy) 10 times; it hisses, and a hatch opens | The "Sizzle" alternate JUICE VFX color for Stoke; Teddy's dialogue "don't do that again" |
| 10 | `sec_doc_dumpster` | Something at the bottom of the ice bath | Med Bay dumpster | Stand in the ice bath for 30 s (the screen frosts); press A at the bottom | A frozen Blister that follows you around the hub as a pet (cosmetic), and 50 Clout |

Secrets are tracked on the corkboard map as silhouettes; Ludlow drops one hint per visit about the nearest unfound one.

## 6. Ambient life and world rules

- **Time of day** advances per run: morning after a loss, evening after a win, night after a title. Lights, gull activity and crowd regulars change with it.
- **Reactions to your record**: NPC barks reference your last fight (fighter, boss, knockdowns). The Wall of Fame hangs a photo per run (green win, red loss, gold title) up to 24, then rotates.
- **Physics toys**: crates, chum buckets and the three heavy bags are real props; the practice cage respects every combat rule including zones and reactions (so a Flare-Up on bag 2 is possible and Granny comments).
- **No combat damage in the hub**: hits on NPCs are shrugged off with a line (Granny: "Cute."). Fighters cannot be knocked down in the hub.
- **Controller-first**: every station is a 2 m interaction volume with an A prompt; menus open as diegetic boards/ledgers; the corkboard map and a **"Fast walk"** (hold A on the map) lets the player jump to any discovered space after the first tour.
- **Hub music** (AUDIO_DIRECTION.md) is diegetic: the Loading Dock's sound system plays the Walkout track once bought; the Juice Bar has a radio.
