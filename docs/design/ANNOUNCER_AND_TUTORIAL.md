# CRITTERWEIGHT — Announcer and Tutorial

## 1. The announcer: BARNABY BELLOWS

| Field | Spec |
|---|---|
| Who | A pelican in a sequined jacket. Former fish-market auctioneer, forty years calling fights at the cannery. His gullet pouch is a natural megaphone. He cries at every title fight and denies it. |
| Role | All in-fight callouts, campaign boss intros, event flavor, menu idle quips, results eulogies. Delivered as **subtitles + synthesized babble**. |
| Personality | Boundless, sincere enthusiasm. Auctioneer cadence: fast runs of syllables that land on one big word. He loves every fighter, especially the one losing. He has sponsor obligations and resents them audibly. He never insults the player; he insults the Commission, Glandco, and physics. |
| Voice (babble synthesis) | Base: a brassy, honking formant tone (think a trombone mute with a pelican in it), 110–180 Hz fundamental for normal lines, up to 260 Hz on excitement. Syllables = 8 short "honk" grains (60–110 ms) chosen by letter class (vowels open/long, plosives short/clicky, sibilants a breathy hiss). Rate ≈ 11 syllables/s. **Pitch contour from punctuation**: rises through a line ending in "!", falls on ".", rises then falls on "?", flat on "…"; ALL-CAPS words get +40% amplitude and a pitch jump; a fighter's name gets a two-syllable "fanfare" grain. Line length caps babble at 4 s (long lines speed up). Under "Reduced announcer" setting the babble is 50% shorter and quieter; subtitles always show. |
| Catchphrase rule | None. He is not allowed a catchphrase. He has *tics*: he counts things ("that's the third…"), he says "folks", he addresses Glandco directly, and he calls the cage "the Gullet" like it is a person. |
| Volume bus | Announcer/dialogue bus; ducks music −6 dB while babbling; never ducks impacts. |

### 1.1 Lines

Ids are stable; `{p}` = player fighter name, `{o}` = opponent name, `{n}` = a number the engine fills, `{a}` = arena name. All lines ≤ 90 characters.

#### Match intro — per fighter (on the fighter walk-in)

| Id | Trigger | Line |
|---|---|---|
| `ann_intro_stoke_01` | intro, Stoke | Eighty-five kilos of newt and a furnace where his conscience should be: STOKE! |
| `ann_intro_stoke_02` | intro, Stoke | He's been angry since birth, folks. Birth was a Tuesday. Here's STOKE! |
| `ann_intro_dredge_01` | intro, Dredge | From the dock, by way of the dock, going back to the dock: DREDGE! |
| `ann_intro_dredge_02` | intro, Dredge | One hundred sixty kilos and a chain. He brought the chain. DREDGE! |
| `ann_intro_gusto_01` | intro, Gusto | He flew in. He'll fly out. He will absolutely tell you about it: GUSTO! |
| `ann_intro_gusto_02` | intro, Gusto | Fifty-five kilos, forty of it hairdo. Make some noise for GUSTO! |
| `ann_intro_dozer_01` | intro, Dozer | He has one plan. The plan is forward. Here comes DOZER! |
| `ann_intro_dozer_02` | intro, Dozer | Please clear the front row. Please clear the second row. DOZER! |
| `ann_intro_slurry_01` | intro, Slurry | Up from the drain, folks, and the drain is glad: SLURRY! |
| `ann_intro_slurry_02` | intro, Slurry | Don't touch the floor near it. Don't touch anything near it. SLURRY! |
| `ann_intro_jitters_01` | intro, Jitters | Forty-five kilos and nine thousand volts of nerves: it's JITTERS! |
| `ann_intro_jitters_02` | intro, Jitters | He's not scared, folks, he's just like that. Give it up for JITTERS! |

#### Round start

| Id | Trigger | Line |
|---|---|---|
| `ann_round_01` | round start | Touch gloves, claws, beaks, whatever you've got, and FIGHT! |
| `ann_round_02` | round start | The Gullet is open for business, folks! |
| `ann_round_03` | round start, round 2+ | Round {n}! Somebody's cornerman is lying to them right now. |
| `ann_round_04` | round start, final round | Last round. Glandco reminds you hydration is legally a choice. |
| `ann_round_05` | round start | Bell! Go! That's the whole rulebook! |
| `ann_round_06` | round start, campaign | Card's live, {p}. Make the undercard remember you. |

#### First blood

| Id | Trigger | Line |
|---|---|---|
| `ann_first_01` | first hit of the match | First touch! Somebody tell the judges to wake up! |
| `ann_first_02` | first hit of the match | And we're off, folks. That one counted. They all count. |
| `ann_first_03` | first hit, player landed | {p} lands first! The crowd approves, loudly, with cans! |
| `ann_first_04` | first hit, opponent landed | {o} gets there first. Shake it off, {p}, you've got plenty of face left. |
| `ann_first_05` | first hit was a Heavy | FIRST hit of the night and it was a big one! That's a mission statement! |

#### Big hit (Heavy or Charged Heavy landing clean)

| Id | Trigger | Line |
|---|---|---|
| `ann_big_01` | big hit | OH! That one came with a return address! |
| `ann_big_02` | big hit | HE FELT THAT in the parking lot! |
| `ann_big_03` | big hit | That's a Glandco Heavy Hit of the Night, folks, and it is NOT even night! |
| `ann_big_04` | big hit, charged | Fully charged! Somebody check the cage for dents! |
| `ann_big_05` | big hit | Physics just filed a complaint! |
| `ann_big_06` | big hit, wall splat | INTO THE SPONSOR BOARD! The sponsor is thrilled! |
| `ann_big_07` | big hit, launcher | UP goes the critter! Gravity's turn now! |
| `ann_big_08` | big hit on the player | Oof. Okay. That's gonna be a photo on the wall, {p}. |
| `ann_big_09` | big hit, counter (hit during startup) | Caught him WINDING UP! That's a counter, folks, that's reading the mail! |
| `ann_big_10` | big hit, over 15 damage | Fifteen-plus! The commissioner is pretending not to look! |

#### Combo (full L1–L3 string or Finisher landing)

| Id | Trigger | Line |
|---|---|---|
| `ann_combo_01` | three-hit string | One, two, THREE! That's arithmetic, folks! |
| `ann_combo_02` | finisher lands | FINISHER! And the follow-through had a follow-through! |
| `ann_combo_03` | four-plus hits | Four in a row! Somebody's been doing their bag work! |
| `ann_combo_04` | finisher lands, player | {p} closes the string! Granny's gonna want that on tape! |
| `ann_combo_05` | six-plus hits | SIX hits! The judges are just drawing little hearts now! |
| `ann_combo_06` | combo ended by scaling | And the combo's done, folks, that's the rules. Even here we have one rule. |

#### Parry

| Id | Trigger | Line |
|---|---|---|
| `ann_parry_01` | parry | PARRIED! Timed to the hair! |
| `ann_parry_02` | parry | That's a read, folks! He saw it before it was thrown! |
| `ann_parry_03` | parry by the player | {p} slaps it away! Now hit him back, kid, he's wide open! |
| `ann_parry_04` | parry of a Heavy | A HEAVY, parried! That's a crime in six districts! |
| `ann_parry_05` | parry against the player | {o} read you like a sponsor card, {p}. Mix it up! |
| `ann_parry_06` | three parries in a round | Third parry! Someone's gonna have to just stand there and take it. |

#### Knockdown

| Id | Trigger | Line |
|---|---|---|
| `ann_kd_01` | knockdown | DOWN! Down goes the critter! |
| `ann_kd_02` | knockdown | Timber, folks! That's a full ragdoll! |
| `ann_kd_03` | knockdown, poise break | Legs said no! The rest of him agreed! |
| `ann_kd_04` | knockdown, player scores | {p} puts him on the canvas! Let him up or don't, I'm not the ref! |
| `ann_kd_05` | knockdown, player down | {p} is down, folks. Wake-up window. Get up smart, not fast. |
| `ann_kd_06` | knockdown by throw | THROWN! He's gonna land in a different weight class! |
| `ann_kd_07` | knockdown by trip | Tripped! It's the little ones that get you! |
| `ann_kd_08` | third knockdown of a fight | Three knockdowns! The canvas is filing for a restraining order! |

#### Comeback (a fighter below 25% HP lands 3 hits in a row, or wins a round from behind)

| Id | Trigger | Line |
|---|---|---|
| `ann_comeback_01` | comeback | WAIT a minute! He's not done! He's NOT done, folks! |
| `ann_comeback_02` | comeback | Where is this coming from?! Not Glandco, I checked! |
| `ann_comeback_03` | comeback, player | {p} is BACK in it! Crowd's on its feet! The seats are on their feet! |
| `ann_comeback_04` | comeback, opponent | {o} is swinging back, {p}! Nobody in this cage ever reads the script! |
| `ann_comeback_05` | round won from behind | He was DEAD and buried and he took the ROUND! I need a minute! |

#### JUICE activation — per fighter

| Id | Trigger | Line |
|---|---|---|
| `ann_juice_stoke_01` | JUICE, Stoke | MELTDOWN! The door's open and the newt's not home! |
| `ann_juice_stoke_02` | JUICE, Stoke | Stoke hits the JUICE! Fire marshal, please report to the Gullet! |
| `ann_juice_dredge_01` | JUICE, Dredge | HIGH TIDE! Everybody's ankles just got heavy! |
| `ann_juice_dredge_02` | JUICE, Dredge | Dredge hits the JUICE! The dock is in the cage now! |
| `ann_juice_gusto_01` | JUICE, Gusto | HURRICANE STRUT! He's faster and, somehow, louder! |
| `ann_juice_gusto_02` | JUICE, Gusto | Gusto hits the JUICE and the hairdo achieves liftoff! |
| `ann_juice_dozer_01` | JUICE, Dozer | LANDSLIDE! Please move your vehicles! |
| `ann_juice_dozer_02` | JUICE, Dozer | Dozer hits the JUICE! He has become a road! |
| `ann_juice_slurry_01` | JUICE, Slurry | OVERFLOW! Evacuate the floor! The floor is leaving anyway! |
| `ann_juice_slurry_02` | JUICE, Slurry | Slurry hits the JUICE! Nobody drink from the drain this week! |
| `ann_juice_jitters_01` | JUICE, Jitters | OVERCHARGE! The jelly is BIGGER and that's a problem for everyone! |
| `ann_juice_jitters_02` | JUICE, Jitters | Jitters hits the JUICE! That hum is coming from inside the building! |

#### Low health

| Id | Trigger | Line |
|---|---|---|
| `ann_low_01` | a fighter below 20% | He's running on fumes and sponsor obligations! |
| `ann_low_02` | player below 20% | {p}'s hurt, folks. Guard up, breathe, pick your shot. |
| `ann_low_03` | opponent below 20% | {o} is one good shot from the wall of fame! The sad part of the wall! |
| `ann_low_04` | both below 20% | Both of them! Whoever blinks loses and nobody in here has eyelids! |
| `ann_low_05` | a fighter below 10% | Ten percent! That's a rounding error with legs! |
| `ann_low_06` | player below 20%, co-op | {p}'s hurt! Partner, that's your cue, that's the whole cue! |

#### Timeout and sudden death

| Id | Trigger | Line |
|---|---|---|
| `ann_time_01` | 10 s left | Ten seconds! The judges are reaching for their coins! |
| `ann_time_02` | time out, HP decision | Time! Goes to the cards, and the cards say {p}. Don't ask what cards. |
| `ann_time_03` | sudden death start | SUDDEN DEATH! One hit, folks! Everyone is made of glass! Be the hammer! |
| `ann_time_04` | sudden death won | ONE TOUCH and it's over! That's the most honest thing this league does! |
| `ann_time_05` | timer paused (ref timeout) | Ref timeout! Somebody's shoe came off. Somebody who doesn't wear shoes. |

#### KO

| Id | Trigger | Line |
|---|---|---|
| `ann_ko_01` | KO | IT'S OVER! Goodnight, good luck, and good grief! |
| `ann_ko_02` | KO | KNOCKED OUT! Call Doc Sutura! Call her gently! |
| `ann_ko_03` | KO by Heavy | KO by HEAVY! That's a headline, folks, I'll write it myself! |
| `ann_ko_04` | KO by throw | KO by THROW! He went from fighter to luggage! |
| `ann_ko_05` | KO by JUICE | KO by the JUICE! Glandco would like you to know it's "probably fine"! |
| `ann_ko_06` | KO by zone/status damage | He got burned out, folks! The floor did the paperwork! |
| `ann_ko_07` | KO, player loses | And {p} is OUT. Chin up, kid. The dog started somewhere too. |
| `ann_ko_08` | KO, detachable piece flies | AND THERE GOES A PIECE OF HIM! Somebody grab that, it's a souvenir! |
| `ann_ko_09` | KO in under 30 s | Under thirty seconds! Refunds are not available, that's in the waiver! |
| `ann_ko_10` | KO, ring-out | OFF THE ROOF! He's fine! Probably! It's a tall building! |

#### Victory — per fighter (results card)

| Id | Trigger | Line |
|---|---|---|
| `ann_win_stoke_01` | win, Stoke | STOKE takes it! Somebody open a window, the newt's still cooking! |
| `ann_win_stoke_02` | win, Stoke | Your winner, by furnace: STOKE! He'd like to thank nobody! |
| `ann_win_dredge_01` | win, Dredge | DREDGE wins! He will now return to the dock and feel nothing! |
| `ann_win_dredge_02` | win, Dredge | Your winner, by tonnage: DREDGE! The chain stays on! |
| `ann_win_gusto_01` | win, Gusto | GUSTO wins and he knew it an hour ago! |
| `ann_win_gusto_02` | win, Gusto | Your winner, by altitude: GUSTO! He's taking a bow! He's taking three! |
| `ann_win_dozer_01` | win, Dozer | DOZER wins! Now somebody turn him around! |
| `ann_win_dozer_02` | win, Dozer | Your winner, in a straight line: DOZER! Good lad! Good LAD! |
| `ann_win_slurry_01` | win, Slurry | SLURRY wins! Please do not shake its hand, it doesn't have one! |
| `ann_win_slurry_02` | win, Slurry | Your winner, by puddle: SLURRY! Mop crew, you have my sympathies! |
| `ann_win_jitters_01` | win, Jitters | JITTERS wins and he's just as surprised as you are! |
| `ann_win_jitters_02` | win, Jitters | Your winner, by voltage: JITTERS! Unplug him before the ceremony! |

#### Campaign boss intros and phase changes

| Id | Trigger | Line |
|---|---|---|
| `ann_boss_bilge_01` | Bilge intro | The cannery's own guard dog! Three hundred twenty kilos of good boy: BILGE! |
| `ann_boss_bilge_02` | Bilge intro | He's on a chain, folks. The chain is a suggestion. BILGE! |
| `ann_boss_bilge_p2` | Bilge phase 2 | HE'S OFF THE CHAIN! And he pulled the PLUG! Everybody's wet! Everybody! |
| `ann_boss_conduit_01` | Conduit intro | From the power cabinet, the one with the warning sticker: CONDUIT! |
| `ann_boss_conduit_02` | Conduit intro | Do not touch the serpent. Do not touch the floor. CONDUIT! |
| `ann_boss_conduit_p2` | Conduit phase 2 | IT'S PLUGGED IN! The floor is a weapon now! The rubber mats are your friends! |
| `ann_boss_snap_01` | Snappington intro | Undefeated since nineteen seventy-three! Her Honor, COMMISSIONER SNAPPINGTON! |
| `ann_boss_snap_02` | Snappington intro | She wrote the rules, folks. Tonight she's reading them to you. SNAPPINGTON! |
| `ann_boss_snap_p2` | Snappington phase 2 | SHE DRANK THE CRATE! The whole crate! That's not in the rules! She knows! |

#### Event flavor (campaign node screens)

| Id | Trigger | Line |
|---|---|---|
| `ann_evt_01` | enter a Shop node | Needles has a stall up. Everything's legal. He said so. He's sweating. |
| `ann_evt_02` | enter a Rest node | Doc's table. Eight hands, one opinion. Hold still. |
| `ann_evt_03` | enter an Event node | Something's happening on the card, folks. Something always is. |
| `ann_evt_04` | enter a Mystery node | Question mark node! My favorite punctuation! After the exclamation! |
| `ann_evt_05` | enter an Elite node | Elite bout! That's a star on the poster and a bruise on you! |
| `ann_evt_06` | Treasure node | A crate! Nobody's name on it! That makes it yours, that's maritime law! |
| `ann_evt_07` | pick a Banned Substance | A Banned Substance! I saw nothing! I'm a pelican, I see fish! |
| `ann_evt_08` | enter the boss node | Boss bout. Folks, I'm going to need the big microphone. The BIG one. |

#### Menu idle quips (30 s of inactivity on menus)

| Id | Trigger | Line |
|---|---|---|
| `ann_idle_01` | menu idle | Take your time, kid. The cage isn't going anywhere. The cage is bolted down. |
| `ann_idle_02` | menu idle | Glandco JUICE: it's probably fine. That's the slogan. They paid for that. |
| `ann_idle_03` | menu idle | I've called four thousand fights. Three of them had a referee. |
| `ann_idle_04` | menu idle | The weight classes are decorative, folks. So is the drug testing. |
| `ann_idle_05` | menu idle | Pick the crab. Nobody picks the crab. The crab notices. |
| `ann_idle_06` | menu idle | If you're waiting for a sign, folks, the sign fell off the roof in March. |
| `ann_idle_07` | menu idle | My jacket has eleven hundred sequins. I counted during a Dredge fight. |
| `ann_idle_08` | menu idle | The Commissioner says hello. She didn't, but she would, legally. |
| `ann_idle_09` | menu idle | Tutorial's under Practice, kid. Granny's waiting. Granny's always waiting. |
| `ann_idle_10` | menu idle | Gusto has asked me to mention Gusto. Consider Gusto mentioned. |
| `ann_idle_11` | menu idle | Fun fact: the Gullet has eight sides and zero fire exits. Allegedly. |
| `ann_idle_12` | menu idle | Still here? Me too, folks. Forty years. The booth has a cot. |

#### Tutorial encouragement (Barnaby chimes in from the booth during the tutorial)

| Id | Trigger | Line |
|---|---|---|
| `ann_tut_01` | tutorial start | New kid in the practice cage! Granny's got 'em! Granny's got everybody! |
| `ann_tut_02` | first light string landed | Three hits! Folks, we have a prospect! |
| `ann_tut_03` | first heavy landed | THAT'S a heavy! Even the bag felt bad about it! |
| `ann_tut_04` | first guard | Guard's up! That's the second-best advice in this building! |
| `ann_tut_05` | first dodge | Slipped it! Nothing hits what isn't there, kid! |
| `ann_tut_06` | first ability | An ABILITY! It's got a cooldown, folks, same as my knees! |
| `ann_tut_07` | first parry | PARRIED! Granny, did you SEE that? She saw it. She's not smiling. She is inside. |
| `ann_tut_08` | tutorial complete | Tutorial done! Folks, I'd put money on this one! Teddy, I'd put SCRIP on it! |

#### Ring-outs, reactions, taunts, draws, modes, minions

| Id | Trigger | Line |
|---|---|---|
| `ann_ringout_01` | ring-out | OVER THE EDGE! The next roof will be in touch! |
| `ann_ringout_02` | ring-out, player | {p} goes off the roof! You get a do-over, kid, this league is merciful once! |
| `ann_ringout_03` | ring-out by wind | THE WIND did that! The weather is undefeated! |
| `ann_ringout_04` | double ring-out | BOTH of them! Off opposite sides! That's symmetry! I love symmetry! |
| `ann_react_01` | any reaction | REACTION! That's chemistry, folks, that's the part I failed! |
| `ann_react_02` | Flare-Up | FLARE-UP! The puddle went BOOM! The puddle was ambitious! |
| `ann_react_03` | Short-Out | SHORT-OUT! Water plus volts! Every parent told you! |
| `ann_react_04` | Stormfront | STORMFRONT! Move! Move! Oh, he didn't move! |
| `ann_taunt_01` | taunt | He's TAUNTING! That's Hype in the bank, or a mistake, we'll see! |
| `ann_taunt_02` | taunt punished | Taunt, PUNISHED! Confidence is a resource, folks, and he spent it! |
| `ann_taunt_03` | taunt, Gusto | Gusto's taunting again! He has a tab at the taunt bar! |
| `ann_taunt_04` | taunt at low health | Taunting at ten percent! That's either courage or a concussion! |
| `ann_draw_01` | draw | A DRAW! Nobody wins! Everybody's mad! Welcome to the Circuit! |
| `ann_draw_02` | draw | Dead even! The judges have left! They may have never arrived! |
| `ann_mode_spot_01` | Spotlight Hog: light swings | The light's moving, folks! Follow the light! The light is the money! |
| `ann_mode_chum_01` | Chumball: goal | GOAL! A bale of chum crossed a line and I have never been happier! |
| `ann_mode_unit_01` | Absolute Unit: new Unit | NEW UNIT! He drank the crate! He IS the crate! |
| `ann_mode_rush_01` | Chum Rush: wave 10 headliner | WAVE TEN! Bargain night's headliner is here! Did we pay him? We did not! |
| `ann_mode_rush_02` | Chum Rush: wave start | Here comes the trash, folks! Respectfully! They're trying their best! |
| `ann_mode_rush_03` | Chum Rush: all down | And bargain night claims another! Cheap seats, expensive lesson! |
| `ann_minion_01` | thrown Scrapling hits another | SCRAPLING into SCRAPLING! Recycling! Glandco is very proud! |
| `ann_minion_02` | Blister thrown and pops | He threw the BLISTER! That's a bomb with feelings, folks! |
| `ann_minion_03` | ten minions down | Ten down! Somebody's clearing the undercard like a buffet! |

**Count: 163 lines** (longest 80 characters). Subtitle rule: ≤ 90 characters each (verified by script in the design pass; keep it in the content tests).

### 1.2 Delivery rules
- One line at a time; a new high-priority trigger (KO, JUICE, phase change) interrupts; low-priority triggers (combo, parry) are dropped if a line is playing.
- Priority: KO > phase change > JUICE > knockdown > reaction > big hit > parry > comeback > combo > first blood > low health > taunt > idle.
- A line is not repeated within the same match; per-trigger pools rotate by seed.
- Co-op: `{p}` resolves to the fighter that triggered the event.
- Every line is a subtitle; the "Reduced announcer" setting halves the frequency and keeps KO/round/JUICE lines only.

---

## 2. The coach: GRANNY HAYMAKER

| Field | Spec |
|---|---|
| Who | A possum, four feet tall, in a tracksuit, with one gold tooth and a folding chair. Bare-knuckle champion of the cannery era. She has trained every fighter on the roster and is disappointed in each of them in a specific way. |
| Role | Runs the tutorial (Granny's corner, Main Floor, or Practice → Tutorial from the main menu), comments on your runs in the hub. |
| Voice | Subtitle + babble: a dry, low, nasal grain set, slow rate (7 syllables/s), flat contour, a rising "eh?" grain on questions. Never shouts. When she is pleased the grain gets a tiny warble. |
| Rules of the tutorial | Every exercise shows the **current binding prompts** (controller or keyboard icons from the live bindings). Each exercise can be **retried**, **skipped**, or **replayed** from a list. The sparring partner is **Kid Lamprey** at Punching Bag tier with attack toggles controlled by the script. The player uses the fighter they picked (default: Stoke; the tutorial adapts move names per fighter from ROSTER.md). |

### 2.1 Tutorial script (10 exercises)

| # | Exercise | Goal | Success condition | Granny — intro | Granny — on success | Granny — hint on failure / 20 s idle |
|---|---|---|---|---|---|---|
| 1 | **Footwork** | Move around the cage; soft lock-on faces the target | Walk to three marked spots (floor rings) and circle Kid Lamprey once while facing him (lock-on holds for 3 s) | "Stick moves you. Camera does the thinking. Walk to the rings. Then walk around the Kid without taking your eyes off him. He's harmless. Today." | "Good. Feet first. Everything you'll ever do starts with where you're standing." | "You're facing him automatically. That's the lock-on. You just move; it does the looking." |
| 2 | **Hands** (Light string) | Land L1–L2–L3 | Land one full three-hit string on the Kid (he holds a loose stance, no guard) | "Light button. Three taps, three hits. Jab, cross, hook — or whatever your body calls them. Don't think. Tap." | "That's a string. It'll work on a lot of people. Not on the good ones. We'll fix that." | "Tap it three times in a row. Don't hold it. The third hit's the one with the shove." |
| 3 | **The big one** (Heavy and Charged Heavy) | Land a Heavy; then land a Charged Heavy | Land one Heavy, then hold Heavy ≥ 0.35 s and land the charged version | "Heavy button. It's slower, it hurts more, and it shrugs off little hits while it's coming. Now hold it. Feel that? That's a charge. Let it go." | "That's the one that ends arguments. It's also the one you'll miss most. Don't fall in love with it." | "Hold the Heavy button until your fighter's whole body winds up. Then let go near him." |
| 4 | **Hands up** (Guard) | Block a string | Hold Guard through the Kid's three-hit string without losing more than 10% HP | "Guard. Hold it. He's gonna throw three. You'll take a little. You won't take a lot. That's the deal with guard — it costs stamina, so don't live there." | "Hands up, chin down, everything else is details." | "Hold Guard before his hands start moving and keep it held. Let go after the third." |
| 5 | **Not there** (Dodge and Dash Attack) | Dodge a Heavy, then land a Dash Attack | Dodge through/around a telegraphed Heavy (no damage taken), then press Light during a dodge and land it | "Dodge button plus a direction. Short, quick, and for a split second nothing can touch you. Now — press Light *while* you're dodging. That's a dash attack. It closes distance." | "Nothing hits what isn't there. And when you come back, come back swinging." | "Wait for his big wind-up, then dodge sideways. For the dash attack, press Light while you're still sliding." |
| 6 | **Your trick** (Ability 1) | Use Ability 1 and land/apply it | Use LB once and have it connect (Steam Vent cone hits, Tide Spit lands, Gust Bomb hits, Bulldoze connects, Sludge Lob puddle under the Kid, Arc Lash hits) | "Left bumper. That's yours. Every critter's got two tricks, and that's the first one. It's got a cooldown — see the ring? Use it, watch the ring, use it again." (fighter-specific second sentence from ROSTER.md playstyle hook) | "That's what makes you *you*. Everything else, everyone's got." | "Press LB when he's in front of you. Watch the little ring on the HUD — when it's full, it's ready." |
| 7 | **Hands on** (Grab and Throw) | Grab the Kid through his guard and throw him | Grab while the Kid is guarding, then throw with a direction | "He's guarding. Guard beats hands. Grab beats guard. Grab button, then push a direction to throw him. Toward the wall if you're feeling mean." | "Strikes beat grabs. Grabs beat guard. Guard beats strikes. There's your triangle. Everything in this cage is three things." | "Walk right up to him while his guard's up, press Grab, then push the stick toward the wall." |
| 8 | **The read** (Parry) | Parry a Light and a Heavy | Press Guard within 0.12 s before a hit lands, twice (the Kid telegraphs with a visible shoulder dip) | "Here's the next layer. Guard, but *late* — right as it lands. That's a parry. He stumbles, you're free. Watch his shoulder. The shoulder never lies." | "That's a read. Do that to the Commissioner and I'll put your picture up myself." | "Don't hold Guard. Tap it the instant his hand reaches you. Early is a block. Late is a bruise. The window's small — it's supposed to be." |
| 9 | **Close it** (Finisher and JUICE) | Land a Finisher, then build Hype and hit the JUICE | Land L1–L2 then Heavy in the cancel window (Finisher); then build 100 Hype (hits + taunt with D-pad Up) and activate JUICE with RT | "Two lights, then Heavy *in the middle of the string*. That's your finisher. Now the fun part: see the meter? That's Hype. Hits fill it. Getting hit fills it. Taunting fills it — up on the pad — if you've got the nerve. Full meter, right trigger. That's the JUICE." (fighter-specific line: "Yours is called {JUICE name}. Don't ask what's in it.") | "That's the whole kit. Hands, heavy, guard, dodge, grab, two tricks, and the JUICE. Everything after this is *timing*." | "Light, Light, then Heavy quickly. For the JUICE: fill the meter — taunt with D-pad Up when he's far away — then hold the right trigger." |
| 10 | **Freestyle** | Win a 60 s round | Beat Kid Lamprey (Punching Bag tier, fighting back for real) by KO or HP% at 60 s | "Alright. He's gonna fight back now. Sixty seconds. Use whatever you learned. Use whatever you didn't. Go." | "Hm. Fine. Granny's corner is always open. Go lose to someone better and come tell me about it." | (at 30 s if losing) "Guard when he winds up. Hit him when he's done. Three things, kid." |

### 2.2 Tutorial design notes
- Exercises 1–7 teach the whole basic layer in ~6 minutes; 8–10 are the "next layer" and are explicitly skippable ("Skip to freestyle").
- The practice cage is the 6 m mini-Gullet; HUD highlights the relevant meter per exercise (stamina in 4, cooldown ring in 6, Hype in 9).
- Every success fires one Barnaby tutorial line from the booth (`ann_tut_*`); failure never fires Barnaby.
- The script reads move names and ability names from the fighter data so it is correct for all six fighters; Granny has one fighter-specific jab per fighter at the start: Stoke "Try not to set the mats on fire this time." · Dredge "Both claws, Dredge. I know the small one's shy." · Gusto "Less hair, more hitting." · Dozer "Turn. Turning is a thing. We'll work on it." · Slurry "No puddles in my gym. Fine. *One* puddle." · Jitters "Breathe. You don't breathe. Do the thing that's like breathing."
- Completion unlocks nothing mechanical (parity rule); it hangs a photo on the Wall of Fame in Fight Camp.

### 2.3 Every fighter, every exercise (implementation notes)

The course must be completable, with the inputs each exercise teaches, by every fighter against the Kid
the game actually launches (`src/tutorial/`, data in `content/core/tutorial/exercises.json`).

**Sparring partner.** Kid Lamprey's own kit, `npc_kid_lamprey` (`docs/kits/npc_kid_lamprey.md`), for
every fighter. Without it (a content set that drops him) `Tutorial.partner_for` picks a roster stand-in:
Gusto, unless he stands more than 1.6× the player's height, then Stoke (a Gusto player spars Stoke).
Gusto's wing and kick strikes are authored at a 1.84 m bird's neck height; size matching cannot bring them
onto Jitters (0.97 m) or past Dredge's raised claws from any distance, so those drills would be impossible
(or, for the dodge drill, pass without any threat).

**How the Kid drills** (`TutorialMode.KidScript`), the same for any partner body:
- *One strike at a time.* His strings press the next Light only once the last strike connected or
  finished its swing. A buffered Light is consumed at the move's cancel time, which for some kits (Stoke,
  Gusto) is the tick the active window opens, so a mashed string never lands.
- *Feet planted at his spacing.* Before each drill attack he walks in (easing off as he arrives) or steps
  back to his spacing and settles, so every strike starts from rest; walking momentum carried him into
  raised guards (Dredge's claws stand 0.9 m out front), where strikes are smothered.
- *Adaptive spacing.* He starts at 0.8 of the move's estimated reach (the estimate overshoots: his jab
  estimates 1.16 m and lands at 0.9–1.0 m, early in its window, where a parry is timed). Each attack kind
  keeps a record per spacing; one that lands less than half the time (two strikes of a string, else the
  strike; blocked and parried count, dodged ones don't) gives way to the next.
- *Holds his ground in Hands.* Once a string starts landing he can't be knocked further than he stood at
  the first hit (+0.15 m). Strings that knock a light body out of the next hit's reach (Stoke's jab and
  cross, Dozer's stomp before the Scoop) would otherwise make Hands luck; inside that distance he reacts
  to every hit normally.
- *Freestyle:* Punching Bag bot with the Sparring difficulty's opponent handicaps (0.8× HP, 0.7× damage,
  `content/core/ladder/difficulty.json`). Even his deliberately weak kit splits 60 s rounds with a slow
  fighter (measured: a strong Dredge needed two rounds without them; one with them).

**Checks read the fighter's real kit.**
- *Hands*: the kit's first three string slots, named from the kit (`{l_names}`). The chain resets when
  it goes cold. Lights mashed so fast that one cancels the last before it lands
  (`TutorialMode.rushable`: Stoke, Gusto) get Granny's `rush` line: "tap, let it land, tap again". Her
  hint opens with "step in and plant your feet": a string started on arrival from a walk carries the
  momentum into the Kid (Gusto's Scissor Kick then starts with the foot against his body and can't
  land); from a set stance every roster string lands on him.
- *Effect hits count for the move that fired them*: an effect with an `id` by that id (Slurry's
  Finisher spits the projectile `venom_spit`, which lands after the move has ended), an unnamed one by
  its same-tick `effect` event (Dozer's L2 Hoof Stomp is an area at the hoof).
- *Heavy*: any Heavy first, then a charged one: the dedicated `heavy_charged` (named in the goal,
  `{charged_name}`: Furnace Haymaker, Downdraft, Hull Breaker, Quarry Ram) or a Heavy held to ≥ 0.35 of its
  charge time (where Fighter switches to `heavy_charged`). Variant slots (`heavy@juiced`) count as their slot.
- *Dodge / Dash Attack, Finisher*: the Kid's Heavy by its base slot; dash attack and finisher hits by
  slot, effects included. The Finisher is Heavy inside a string Light's cancel window, which some kits
  open late (Slurry's Tail Flick at 0.42 s), so the hint says "then {heavy} as the second one lands",
  not "quickly": a Heavy pressed early expires in the input buffer.
- *Missing slots* are honest, not silent: each exercise's `adapt` block (`no_charge`, `no_dash`,
  `no_finisher`, `no_juice`, or `skip` when nothing is possible) replaces its intro/goal/hint/success lines
  and the progress text drops the missing part. No current roster kit lacks a slot; mod kits may.

| Fighter | Kit specifics the course handles |
|---|---|
| Test Dummy (`dev_biped`) | — |
| Stoke | jab and cross knock a light body out of the hook's reach (the Kid holds); mashed lights cancel before they land (rush line) |
| Gusto | his Scissor Kick needs room (lands from 0.85–1.45 m): from a set stance it gets it, out of a run his lunges jam him into the Kid; mashed lights cancel (rush line) |
| Dredge | guards with claws far out front (the Kid strikes from his settled spacing); a slow kit in the freestyle (Sparring handicaps) |
| Dozer | L2 Hoof Stomp is an area effect; the Quarry Ram needs room to travel (released against a body it only shoves: "give it room") |
| Slurry | its string lands from a long step out (the Head Butt drives the head ~1.3 m; its reach estimate is 0.97 m); Finisher Venom Spit is a projectile (counted by its effect id) |
| Jitters | 0.97 m body: the Kid's low body jabs reach it (the Gusto fallback stand-in cannot) |

Verification: `test_tutorial` runs the whole course with the pairing the game launches (default: the
Test Dummy, which is test-only now that the roster is complete); `tools/verify/tutorial_matrix.ps1`
runs it for the Test Dummy and every roster fighter in parallel (by hand:
`TUTORIAL_CREATURE=<id>`; `TUTORIAL_PARTNER=<id>` tries other Kid bodies, `TUTORIAL_TRACE=1` prints
each exercise's events). The driver stands in for a competent player: hit-confirm string rhythm, parry
and dodge timing learned from when his strikes actually land, spacing tried and varied like a person
would, the kit's own bot personality for the freestyle. `test_kit_npc_kid_lamprey` runs the Kid's side
of the drills for every roster fighter with its own drivers.
