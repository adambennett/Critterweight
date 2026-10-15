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
| Journeyman (`regular`) | 0.36 s | 0.14 s | 18 % | 0.35 / 0.05 / 0.12 | 0.25 | 0.3 | 0.5 | 0.55 |
| Contender (`pro`) | 0.26 s | 0.10 s | 10 % | 0.55 / 0.25 / 0.22 | 0.5 | 0.45 | 0.75 | 0.62 |
| Headliner (`champion`) | 0.16 s | 0.07 s | 5 % | 0.75 / 0.4 / 0.3 | 0.75 | 0.75 | 0.9 | 0.66 |
| Hall-of-Famer (`hall_of_famer`) | 0.10 s | 0.04 s | 1 % | 1.0 / 0.55 / 0.36 | 1.0 | 1.0 | 1.0 | 0.75 |

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
  likewise. Lights in a string are not punished: the kits' strings are tight by design.
* **Strings.** Decided once per Light, after its hit frames: better players continue what lands (or what the
  next hit of the string can still reach — Dozer's Hoof Stomp after a Light that sails past at point blank)
  and stop a blocked or whiffed string; worse ones press on regardless.
* **Reads (`read`).** **Pressure** (≥ 5 attacks begun in the last 2 s it saw, mostly Lights — from a masher or
  a fast bot): a fuller guard, parry taps on the pattern of the hits (the gap after each move, learned from
  what it saw, aimed at when those hits have been reaching it), a move whose armor covers Lights from its first
  frame (Dozer's and Dredge's Heavies), kit tools gated by the `target_mashing` hint condition (Dozer's Dust
  Bowl), a step back out of the pocket when too close for its own strikes. A **button-masher** — pressure from
  someone not seen guarding or dodging for 8 s (any bot defends sooner) — is also not traded with in neutral
  (the reader waits for the openings his stream gives) and is misread less often (mistakes × (1 − read/2)). **Charge-ups:** a Heavy held in its wind-up (the move time it sees stands still) is not
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

MEASUREMENTS_PLACEHOLDER

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
(its successful parries fell from 22 to 12 per 36 bouts), so the contact delay is used only for taps on a
masher's pattern, where it lifted the Hall-of-Famer from 71 % to 92 % against the masher. A "gap read"
(counter-pokes between a string's hits) never fired: the kits' strings leave no gap wider than a jab start-up.

Known limits: the Dozer mirror still favours the masher against the top tiers (his Hoof Stomps are area hits at
point blank, the bodies end up overlapping, and only the stomp and grabs work there); Stoke's own masher is weak
for a kit reason (its Light cancel windows open as the hit frames start, so pressing every 0.18 s cancels each
jab before the fist arrives). Kit balance tables in `docs/kits/` were measured with the earlier bots.
