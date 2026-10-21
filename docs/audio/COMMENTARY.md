# Commentary (v0.9.17)

How the booth decides what to say, how it avoids repeating itself, how it stays accurate, and how
it was measured. Code: `game/src/audio/commentary_director.gd`, `commentary_selector.gd`,
`commentary_history.gd`, the announcer section of `game/src/audio/audio.gd`, and the line banks in
`game/content/core/announcer/`. Recordings: `game/assets/audio/speech/` (see `docs/AUDIO.md` and
`docs/audio/breeze/README.md` for provenance).

## 1. Goals

The booth should sound like two people watching the same fight as the player: calls arrive while
they are still true, the important moment always wins, quiet stretches get observations or a joke
instead of silence or a repeat, and nothing it says contradicts what is on screen (a referee
stoppage is not a knockout; a fence joke needs a fence; "his JUICE" needs JUICE).

## 2. Director: what to talk about (`CommentaryDirector`)

The director reads simulation events and the 4 Hz match tick (health, clock, positions near the
edge, stamina) and emits requests `{trigger, ctx, vars, class, ttl, tag, energy, speaker_pref,
follow}`. It never touches gameplay.

| Register | Examples | Class (priority, TTL) |
|---|---|---|
| play-by-play | knockout, stoppage, decision, round result, knockdown, big or counter hit, string, parry, guard break, JUICE, ability use and ability hit, reaction, slam, referee count and wave-up | critical (100, 5 s) / high (85, 3 s) / medium (60, 1.8 s) |
| observations | pressure (four unanswered hits in six seconds), close fight, someone hurt or tired, the clock, an element taking hold, momentum swinging, whiffs (a committed attack that touched nothing) | medium / low (40, 1.4 s) |
| color | booth banter, fighter / element / matchup lines, rare conversations, Career context (title fights, debuts, streaks) | color (15, 2 s), only in lulls |

Pacing: per-situation cooldowns; a talk budget (the share of the last 30 s spent talking: low and
color requests yield above 55 %, medium above 80 %); breathing room after each line (1.1 s before a
low line, 0.3 s before a medium one, none for high and critical, none between the turns of a
conversation); lull detection (4.5 s without significant action before observations, 7 s before
color). Ability calls key on the ability's name (`ability_key`), so every fighter's abilities get
their own calls and the director knows whether an ability actually hit.

## 3. History: what the player has already heard (`CommentaryHistory`)

A bounded ring of the last spoken lines (id, topic/joke families, the match it was heard in, its
order), kept across rematches, consecutive Career bouts and game restarts in
`profiles/commentary_history.json` (one file per user-data root; it describes what this machine's
player has heard, so it is not part of any profile, save or network state). A missing or damaged
file just starts an empty history.

## 4. Selection: which line (`CommentarySelector`)

Every candidate already satisfies the request's context (its `when` matched), so each one is
accurate; the score decides which accurate line sounds best now:

* `+2.5` per matched situational `when` key (capped at three). Standing facts of the match (venue,
  fence, open edges, night, hazards, props, referee, scoring, format, rounds, size gap, ...) decide
  whether a line is TRUE but never count as specificity.
* freshness: a line heard this match is excluded while anything else is left; heard one, two or
  three to five matches ago: -7, -4, -2..-1.4; older plays still yield slightly to rarer ones;
  never heard: +1.
* families: a joke or topic family used in the last few lines is penalised (-4 within two lines,
  -2 within six, -0.8 within fourteen) and gets one appearance per match.
* `-1.2` for a line borrowed from another trigger through `also`; small bonuses for the preferred
  speaker (the other voice answers a lull) and the requested energy; seeded jitter so equal choices
  vary between matches but replay identically for a seed.

## 5. Queue: when to say it (`Audio`)

Requests are queued by priority and expire after their time-to-live, so a call is never late. A
critical result invalidates everything older (no "he's down!" after the bout is over); a newer call
about the same tag replaces an older one. Higher priority interrupts lower-priority speech at a
sentence boundary. Conversation answers (`follow_id`) ride with their question.

## 6. Accuracy gates

* Booth context (`Audio.booth_context`, from `MatchScene.audio_context` and `CareerFight`): venue,
  outdoor, fence or open edges, night, hazards, props, referee, scoring (ten-point or not), format,
  objective, special rules, rounds, Career title fights, debuts, champions, streaks, tiers. Lines that
  assert any of those carry the matching `when` key and are only eligible when it is true.
* Results: `round_end` carries `decided`; stoppages, decisions and knockouts have their own triggers
  and their own lines; decision calls name the kind (unanimous, split, majority, draw) and the
  winner; ceremonial winner names come from the `{w}` token (only for names recorded ceremonially).
  A knockout or referee stoppage waits for the round_end of the same tick: `ends` is `fight`,
  `round` (Health scoring with rounds to go: the bout and its commentary go on) or `none` (an
  elimination); lines that sound final ("It's over!", "your winner by T.K.O.") carry `ends: fight`.
  Under Health scoring the clock's decision call comes with the round_end that settles the bout and
  names its winner; a tied round's sudden death ends with that round. 10-point closeness ("a close
  fight") comes from the cards, not from health (which 10-point holds full).
* Knockdowns carry `counted`: true only for strike knockdowns by an opponent (what the referee
  counts and the judges score, `RoundJudge.STRIKE_KD_REASONS`); count and scorecard lines require it.
  First hits carry `round` (`first` / `2plus`): "first of the night" lines need `first`.
* Who: `who`/`target` are relative to the local player and only set when there is one (never while
  spectating, locally or online; never for a teammate). The legacy `{p}`/`{o}` lines are written
  from the player's corner, so whenever the player is involved `{p}` names the player and `{o}` the
  other fighter; otherwise `{p}` is the actor.
* Names: whole-sentence name variants are preferred; in a mirror match the spoken name is only used
  when it is unambiguous (`SpeechLibrary.spoken_name`).
* Talk budget: a line cut off by a bigger call or by a stop ends its talk interval there (an
  interval never counts past 12 s), so interruptions cannot starve the rest of the match.
* 59 old lines were retired (wrong facts: ropes and corner crews in a cage, feints the game does not
  have, "Devon" on air, wrong Haunted descriptions, Port Hook); the reviewed classification of all
  1045 legacy lines is `docs/audio/commentary/classification.json`, reproducible with
  `node tools/audio/retag_commentary.js`.

## 7. Content

| Bank | Lines | Notes |
|---|---|---|
| `barnaby.json`, `barnaby_vintage.json`, `announcer_expansion.json` | legacy, re-tagged | situation tags, `when` gates, families, energy, retired lines |
| `commentary_v0917.json` | 344 | 337 new lines + 7 corrected re-records (`cmt17_*`): stoppages, decisions, round results, every fighter's abilities and ability hits, observations, Career context, conversations, ceremonial winner names |

The v0.9.17 lines were recorded with the approved Breeze voices (Devon for Barnaby, Kendall, Coach
Buck): 521 clips, 3,132.2 credits, every request journaled before sending (`docs/audio/breeze/v0.9.17/`).
Shipped speech is offline (WAV under `game/assets/audio/speech/v0917/` with `catalog.json`).

## 8. Audit

`--bench commentary` (`game/src/test/audio/commentary_audit.gd`, driven by
`tools/audio/commentary_audit.ps1`) plays scripted event sequences and twelve real bot bouts in real
time across a game restart (sessions A and B share one user-data root, so history persists), logging
every line with its trigger, speaker, text, timing and what cut it off. `tools/audio/commentary_report.js`
turns the logs into the metrics below.

Results, 2026-10-20/21: the baseline is the untouched v0.9.16 checkout (`0465a05`), the revised run
is this branch at `33134f2` (no game files changed after it); both played the same two scripted
sequences and the same twelve seeded bouts (nine duels, among them Stoke vs Dredge and Gusto vs
Jitters three times each, and three Career Cage Rules bouts, Varga vs Knell twice) across a game
restart between bouts 6 and 7.

| Metric | baseline | revised |
|---|---:|---:|
| Bouts (+ scripted sequences) | 12 | 12 |
| Lines played | 449 | 506 |
| Lines per live minute | 9.53 | 10.8 |
| Share of time talking | 51.4% | 64.2% |
| Silence between lines, median / p90 (s) | 1.86 / 7.19 | 1.11 / 5.26 |
| Lines cut off by another line | 26 | 32 |
| Distinct lines | 125 | 338 |
| Exact repeats within a bout | 137 | 15 |
| Exact repeats in the next two bouts | 106 | 7 |
| Exact repeats across the restart | 32 | 10 |
| Same joke family twice in a row | 91 / 435 | 9 / 492 |
| Lull lines that claim a situation (backed by an event) | 15 of 74 (2 backed) | 0 of 10 (0 backed) |
| Situational lines backed by an event | 250 / 267 (94%) | 204 / 213 (96%) |
| Stale knockdown calls after the result | 0 | 0 |
| Stoppages called as stoppages | 0 / 1 | 1 / 1 |
| Stoppages called as knockouts | 1 | 0 |
| Decisions announced | 3 / 3 | 3 / 3 |
| Round-only KOs called as the end of the fight | 0 | 0 |

* **Repetition** fell by an order of magnitude: exact repeats inside a bout 137 to 15, in the next
  two bouts (rematches) 106 to 7, across the restart 32 to 10, and the same joke family twice in a
  row 91 to 9, while the booth used 338 distinct lines instead of 125. The baseline's most played
  lines were two Cut the Angle explanations (28 and 26 plays); the revised maximum is 7 (a Gust Bomb
  hit call).
* **Accuracy:** the referee stoppage is now called as a stoppage (the baseline called it a
  knockout), every decision was announced, no knockdown was called after a result, and no lull line
  claimed a situation that was not happening (the baseline's colour played 15 situational lines in
  lulls, 13 of them unfounded). Situational lines were backed by a matching event 96% of the time
  (204 of 213; baseline 94%). Lines tagged for several situations are judged by the request they
  were played for (the run logs the director's requests). Of the nine unbacked lines, four were
  lull "pressure" observations built from hits older than the pressure window (fixed after the
  audit: the observation now counts only recent unanswered hits, `test_commentary`); the others
  meet the director's definition of a big hit, combo or hurt fighter but not the report's stricter
  one.
* **Pacing:** commentary did not thin out: 10.8 lines per live minute (baseline 9.5), median silence
  1.1 s and 90th percentile 5.3 s. The booth talks 64% of the time (baseline 51%) because more
  fight calls are made; colour and observations yield once the booth has talked for 55% of the
  last 30 s (the talk budget, §2), so quiet stretches still get breathing room. 32 lines were cut off by a bigger call (baseline 26).
* The real-time bouts are not tick-identical between runs of the same build (round transitions
  follow the presentation's pace), so later rounds of some bouts played out differently in the two
  runs; the metrics are totals over the same matchups and seeds. Gameplay identity between v0.9.16
  and v0.9.17 is checked separately with fixed-step headless fights (docs/evidence/verification/v0.9.17).
* Evidence: `docs/evidence/verification/v0.9.17/commentary/` (report, JSON metrics and both runs'
  session logs, gzipped; `node tools/audio/commentary_report.js <baseline dir> <revised dir>` rebuilds
  the table from unpacked logs).

## 9. Tests

`game/src/test/audio/test_commentary.gd`: history persists across restarts and stays bounded; the
selector prefers specific fresh lines but never traps on them and spaces joke families; the queue
expires stale calls and results invalidate older ones; interrupts fade and low lines wait for room;
the director distinguishes knockdown, stoppage, knockout and decisions, detects whiffs, exchanges
and pressure, does not spam repeated abilities, paces lulls with observations and color, and
receives the Career bout context; after the v0.9.17 code review it also checks that the talk budget
recovers from interrupted and stopped lines, that a stoppage in a best-of ends only the round, that
names follow the player's corner, that spectating never addresses a player, that landed abilities
are never called misses, that clock decisions and sudden death name the real winner, that count,
scorecard and first-of-the-night lines fit the moment, that ceremonial names never replace other
names, and that a second interrupt inside the fade keeps the new line. `test_audio_announcer.gd`
covers event mapping and referee / ten-point calls; `test_recorded_speech.gd` covers full clips, token resolution, mirror-safe names
and ceremonial winner names.

## 10. Adding lines

1. Write the line in the right bank with its `trigger`, optional `also`, `when` gates for every fact
   it asserts, `families`, `energy` and `speaker`.
2. Re-run the classification check (`node tools/audio/retag_commentary.js --check`) and the audio
   tests.
3. Record it through the Breeze workflow (`docs/audio/breeze/README.md`): plan, journal, generate,
   audit (`tools/audio/breeze/audit_speech.py`), then add it to the catalog.
4. Run the audit and compare with the last report.
