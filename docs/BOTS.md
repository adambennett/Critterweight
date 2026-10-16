# Bots — difficulty tiers (AI-01, brief §11 / §13)

Code: `game/src/ai/bot_brain.gd` (`BotBrain`, profiles + behaviour), `game/src/ui/bot_tiers.gd` (the one
player-facing tier → profile table), `game/content/core/ladder/difficulty.json` (campaign tiers name the same
profiles). Decision: D-028. Tests: `game/src/test/core/test_naive_play.gd`, the tier bench
(`--bench tiers`), kit tests (bot-vs-bot balance smoke), campaign and tutorial tests.

## What a bot may know (no omniscience)

A bot is an `InputSource`: each tick it writes only a `FighterInput` (stick, presses, held buttons) — exactly
what a player's controller writes — and every combat rule applies to it unchanged.

* **Perception delay.** Every tick it records what it can see of its target: position, body extent, state,
  the move being performed and how far into it the target is. Every decision uses the record that is
  `reaction` seconds old; nothing newer is visible to it. It never reads the opponent's input or anything that
  has not happened yet.
* **What a practised player knows on top:** the timing of a move it has *seen begin* (its animation: when the
  hit frames come, how long the recovery is); its own state (stamina, armor, cooldowns — the HUD); its own
  blocks, parries and hits taken; the pattern of attacks it has seen; and, learned during the fight, how far
  its own moves connect and how long after an attack starts that attack reaches it.
* An attack seen begin is answered at once (a reaction time already includes deciding), other decisions are
  taken every `think` seconds.

## How the tiers differ

| Tier (profile) | reaction | think | mistakes | block / parry / dodge shares | punish | read | combo | aggression |
|---|---|---|---|---|---|---|---|---|
| Punching Bag (`rookie`) | 0.50 s | 0.20 s | 35 % | 0.12 / 0 / 0.04 | 0 | 0 | 0.2 | 0.40 |
| Journeyman (`regular`) | 0.36 s | 0.14 s | 15 % | 0.45 / 0.05 / 0.12 | 0.25 | 0.5 | 0.5 | 0.55 |
| Contender (`pro`) | 0.25 s | 0.10 s | 10 % | 0.55 / 0.25 / 0.22 | 0.5 | 0.6 | 0.75 | 0.62 |
| Headliner (`champion`) | 0.15 s | 0.07 s | 5 % | 0.75 / 0.4 / 0.3 | 0.75 | 0.9 | 0.9 | 0.66 |
| Hall-of-Famer (`hall_of_famer`) | 0.09 s | 0.04 s | 1 % | 1.0 / 0.55 / 0.36 | 1.0 | 1.0 | 1.0 | 0.75 |

Creature `ai` blocks add their personality offsets (aggression, block, dodge, ability, grab) on top.
Reaction time is the strongest lever between two bots: a perception delay plus the ~0.04 s it takes a fresh
guard to come up must undercut jab start-ups (0.06–0.16 s) to block from neutral, so the ladder is spaced
evenly across that threshold (measured: a Headliner at 0.13 s beat a 0.22 s Contender 81 % of 36 bouts, at
0.16 s only 50 %).

### Behaviour, by skill

* **One answer per attack.** Each attack the bot sees begin gets one answer, rolled once from the tier's
  shares: a timed **parry tap** (needs time to see the wind-up coming; aimed at when that attack has been
  reaching it), a **block** (held through the attack — and, for a cancelable Light, through the follow-up it
  threatens), a **dodge** (only against Heavies, abilities and grabs: a dodge's recovery hands a string free
  hits), a **counter-poke** into a slow unarmored wind-up, or nothing. A mistake (per attack) leaves it
  unanswered; the answer is prepared even in hitstun, so a guard held through a combo is up when it ends.
* **Guard habit.** Inside the opponent's reach and not attacking, a careful player keeps his guard up (rate
  ∝ block share); good readers do not raise a guard on spec below 30 stamina.
* **Punishes.** A blocked, dodged or whiffed move that cannot be cancelled (Heavies, Finishers, abilities) is
  punished with the strongest own move whose start-up and range fit the opening; a parried attacker (stunned)
  likewise.
* **After a blocked Light (`read`).** The bot feels the block at once and knows from the blocked move's
  animation when the attacker can strike again: its cancel point (a string goes on only once the strike has
  landed) plus the start-up of his quickest follow-up (the string's next hit — strings loop — or his
  Finisher). The blocked move is the one it saw begin, or, when a slow reaction has not seen it yet, the next
  Light of the string it counts along (a Finisher instead fools it). A gap wider than its own quickest fitting
  move is hit back (Dredge's, Slurry's and Gusto's middle hits leave one; Stoke's string leaves none);
  otherwise the parry share decides a **parry tap** timed for the string's next hit, guard held until then.
  Contacts it feels (blocks, parries, hits) teach it how late each of the attacker's moves actually reaches
  it, which those taps aim at.
* **Strings.** Decided once per Light, after its hit frames: better players continue what lands (or what the
  next hit of the string can still reach — Dozer's Hoof Stomp after a Light that sails past at point blank)
  and stop a blocked or whiffed string; worse ones press on regardless.
* **Reads (`read`).** **Pressure** (≥ 5 attacks begun in the last 2 s it saw, mostly Lights — from a masher or
  a fast bot): a fuller guard, a move whose armor covers Lights from its first frame (Dozer's and Dredge's
  Heavies), kit tools gated by the `target_mashing` hint condition (Dozer's Dust Bowl), a step back out of the
  pocket when too close for its own strikes, and Heavies blocked (then punished) instead of dodged — a dodge's
  recovery hands the stream free hits. A **button-masher** — pressure from someone not seen guarding or dodging
  for 8 s (any bot defends sooner) — is also not traded with in neutral (the reader waits for the openings his
  stream gives) and is misread less often (mistakes × (1 − read/2)). A reader does not taunt an opponent who
  keeps attacking or never defends. **Charge-ups:** a Heavy held in its wind-up (the move time it sees stands still) is not
  parry-tapped (its release cannot be timed) but grabbed (a grab beats charge armor) or stepped away from.
  Winded readers sidestep Heavies instead of blocking them (a blocked Heavy below 20 stamina breaks the
  guard).
* **Ranges.** Reach is judged to the target's body surface (the hurt shapes hits are tested against), not its
  root, so long bodies are in range sooner; a strike also needs its weapon to travel *into* the target, so a
  body nearer than where the weapon rests is too close for it. The prior is the move's geometry (78 % of its
  animated reach — a weapon at full stretch has no closing speed left); during the fight the bot learns how
  its own uncancelled moves actually connected by distance band. Careless players (1 − read) jab regardless:
  visible whiffs. Spaced players (spacing ≥ 0.5) stand where their own strikes can still connect.
* **Offence** starts at a rate per second (aggression × 3/s in range), so a quicker thinker is not a more
  aggressive one; a bot armored against Lights (Dust Bowl, JUICE) trades instead of guarding.

The Punching Bag stays forgiving by construction: 0.5 s reactions, a mistake on 35 % of the attacks it sees,
a 0.12 block share, no parry share (no taps — asserted by `test_naive_play`), no punishes and no reads.

## Kit hints (the one per-kit mechanism)

Per-kit behaviour stays in the creature `ai` block read by the `_kit_*` functions (see the header of the kit
hint section in `bot_brain.gd`). Added here: the `when` condition **`target_mashing`** (true only as often as
the bot's `read` skill notices the mashing); Dozer's Dust Bowl (`ability2`) uses it. The Slurry/Jitters hints
(`stick`, `range_needs_tools`, `heavy_vs_windup`, `avoid_zones`) are kept verbatim.

## Measurements

**Current code (2026-10-16), acceptance run** (`NAIVE_BOUTS=4`: 24 mirror bouts per tier at the test's
seeds, The Gullet, one 45 s round). M = masher won, b = bot won. The wide-sample column plays 8 bouts per
fighter (48 per tier).

| Tier | bot won (acceptance) | Stoke | Dredge | Gusto | Dozer | Slurry | Jitters | 48-bout sample | Target |
|---|---|---|---|---|---|---|---|---|---|
| Punching Bag | 1 / 24 (masher 96 %) | MMMM | MbMM | MMMM | MMMM | MMMM | MMMM | - | masher >= 65 %: met |
| Journeyman | 5 / 24 (masher 79 %) | MMMM | Mbbb | MMMM | MMMM | MMMM | MbMb | 9 / 48 | masher 25-75 %: **not met** |
| Headliner | 17 / 24 (71 %) | bbbb | bbbb | bMbb | MMMM | bMbM | bbbb | 37 / 48 (77 %) | >= 70 %: met |
| Hall-of-Famer | 20 / 24 (83 %) | bbbb | bbbb | bbMb | MbbM | bbMb | bbbb | 42 / 48 (88 %) | >= 80 %: met |

What changed (D-033):
- **Gap counters are learned.** Each one his next hit interrupts asks for 0.04 s more gap. After three more
  lost than landed, the bot taps parries instead. Gusto's had lost 14 of 15.
- **Ranges are learned faster.** A whiff or connect at one distance band also counts for the bands next to
  it, so ranges are learned in a few tries.
- **A walking attacker's reach is extrapolated.** The bot counts what he covers over its reaction delay and
  his wind-up. The Slurry bot had judged 44 of a masher's attacks out of reach and taken them unguarded.
- **Pressure is blocked.** Under a stream of attacks it has read, the bot's guard bridges the short gaps
  (0.25 s). A read masher is blocked pre-emptively even mid-stream. A guard raised afresh for every hit was
  still coming up when the hit landed.
- **Reads were raised:** Headliner 0.75 to 0.9, Contender 0.45 to 0.6, Journeyman 0.3 to 0.5. Journeyman
  block also went to 0.45 and its mistakes to 15 %.
- **Combat fix (D-032).** A burst at the attacker's own body, such as Dozer's hoof stomp, is guarded by facing
  him. At point blank its centre used to lie beside or behind the defender.

Tier ladder (`--bench tiers --bouts 12`, 60 s rounds):
- Journeyman 9-3 vs Punching Bag;
- Contender 10-2 vs Journeyman;
- Headliner 9-3 vs Contender;
- Hall-of-Famer 5-7 vs Headliner on 12 bouts (noise), **23-13 (64 %) on 36 bouts** (`--pair headliner,hall_of_famer`);
- Hall-of-Famer 12-0 vs Punching Bag.

Open: the Journeyman still loses about four in five to the masher. Its 0.36 s reaction cannot block a jab
stream, and raising reads, block, fewer mistakes or a 0.33 s reaction moved it by little. The Dozer mirror is
still the hardest kit for the Headliner.

**Earlier diagnostic runs (before 2026-10-16).** Main's string-cancel rule (a string goes on only once the strike has landed or
its hit frames are over, e34d9b5) made the button-masher much stronger: his Lights now land instead of being
cancelled before contact. The numbers below are diagnostic runs (The Gullet, one 45 s round, mirror matches over
the six roster fighters, seeds 7000 + 17k — not yet the acceptance seeds of `test_naive_play`); M = masher won,
b = bot won.

| Run (code) | Tier | masher won | Stoke | Dredge | Gusto | Dozer | Slurry | Jitters |
|---|---|---|---|---|---|---|---|---|
| main's rule, before the after-block reads | Punching Bag | 12 / 12 | MM | MM | MM | MM | MM | MM |
| same | Journeyman | 10 / 12 | MM | bb | MM | MM | MM | MM |
| same | Headliner | 7 / 12 | MM | bb | MM | MM | Mb | bb |
| same | Hall-of-Famer | 4 / 12 | bb | bb | Mb | MM | Mb | bb |
| this commit (after-block reads) | Headliner | 10 / 24 | bbbb | bbbb | MMMb | MMMb | MMMM | bbbb |
| same | Hall-of-Famer | 4 / 20 | bbbb | bbbb | bbbb | MMMM | bbbb | (not run) |

Targets: the masher beats the Punching Bag ≥ 65 % (met), loses to the Headliner ≥ 70 % (58 % — not met: the
Gusto, Dozer and Slurry kits), to the Hall-of-Famer ≥ 80 % (80 % of 20 — at the line), Journeyman about even
(not re-measured after the after-block reads).

Tier bench before main's cancel rule (`--bench tiers --bouts 12`, 60 s rounds, commit 1b4b1ce, Contender /
Headliner / Hall-of-Famer reactions then 0.26 / 0.16 / 0.10 s): Journeyman 10–2 vs Punching Bag, Contender 8–4
vs Journeyman, Headliner 6–6 vs Contender, Hall-of-Famer 8–4 vs Headliner, Hall-of-Famer 12–0 vs Punching Bag
(main at 8986502: 7–5, 6–6, 4–8, 8–2, 7–5). 36-bout ladder runs then: Contender 67 % vs Journeyman, Headliner
64 % vs Contender, Hall-of-Famer 78 % vs Headliner. Not re-run on the current code.

## How it was tuned (and what did not work)

Before (main at 8986502): the masher beat the Headliner 5 of 6; the tier bench read Journeyman 7–5 vs Punching
Bag, Contender 6–6 vs Journeyman, Headliner 4–8 vs Contender, Hall-of-Famer 8–2 vs Headliner and only 7–5 vs
Punching Bag. Causes found: defence was re-rolled every think (a top bot dodged nearly every perceived jab and
the dodge recovery handed the masher free hits), the timed-parry branch raised the guard before its press (so it
never parried), offence fired on almost every think (top bots were mashers themselves), and bot reach was
judged root to root (Dozer mirrors fought inside each other's heads, where neither horn connects).

Measured along the way (36-bout ladders unless noted): reaction time is the lever that separates two bots — a
Headliner at 0.13 s beat a 0.22 s Contender 81 %, at 0.16 s only 50 %; more aggression, a stronger guard habit,
a larger parry share or perfect punish/read alone moved the rung by little or nothing (±10 % noise at 18–36
bouts). Parry taps timed off the seen wind-up work; adding the learned contact delay to *those* taps made them
fire on attacks a reaction-delayed bot cannot time and cost the Contender its well-timed late guard presses
(its successful parries fell from 22 to 12 per 36 bouts), so the contact delay is used only for taps after a
block. Under main's cancel rule, parry taps chained forward from the rhythm of the attacks seen begin ("beat
taps") parried only 7 of 123 hits against the masher: a tap planned for a hit two moves ahead dropped the guard
for the hit in between, and contacts were matched to the previous move when the next had not been seen yet.
Taps anchored on a felt block (the string's next hit, guard held until the tap) parried 11 of 22 and replaced
them; contacts now belong only to the move whose hit frames (or the time before the attacker's next move could
strike) hold them.

Known limits: the Dozer mirror still favours the masher against the top tiers (his Hoof Stomps are area hits at
point blank, the bodies end up overlapping, only the stomp and grabs work there, and after a blocked stomp the
string's next hit — a horn — whiffs, so taps timed for it parry nothing); the Gusto (dodges for guard, short
guard holds) and Slurry (keeps range, needs its tools) kit personalities hand a masher openings; Stoke's string
leaves no gap to hit back in. Kit balance tables in `docs/kits/` were measured with the earlier bots.

## Obstacle steering (2026-10-16)

Bots walk round solid props in their way (`BotBrain._steer_around`, applied before the edge-safety filter):
- A ray at hip height follows the intended move, on the prop layer only, so fighters never trigger it.
- A steep prop face within 1.2 m past the body bends the move along that face, eased off it so the body
  clears the corner. Ramps and other sloped surfaces don't count.
- A glancing move keeps its own direction along the face.
- Head on, the lower fighter index turns one way and the higher the other. That way two bots on opposite
  sides of a prop go round the same side and meet, instead of circling it forever.

Before this, a bot and its target on opposite sides of the rooftop's HVAC units (or a railing) could each
walk into the prop for minutes. Swarm Night lost to sudden death that way; PROGRESS.md has the case.
