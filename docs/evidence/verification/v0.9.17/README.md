# Critterweight v0.9.17 verification

**Scope:** the owner's v0.9.17 specification (`Version 17 and 18 Updates.md`, first release):
commentary overhaul, full-roster art with expressions and secondary motion, the "Legacy Varga skin"
option, and new ability effects for every fighter. Gameplay is unchanged. Ledger rows C17-01..05,
ART-10, ART-11, VFX-01, SAV-04 (docs/REQUIREMENTS.md). Checklist:
[docs/releases/v0.9.17-v0.9.18-checklist.md](../../../releases/v0.9.17-v0.9.18-checklist.md).

Machine: Windows 10 (19045), i7-7700K, RTX 4070 Ti Super, Godot 4.5.1 (official), Blender 5.2.2.
Networking is loopback on this PC.

## Baseline (before the work)

- `main` = `origin/main` = `0465a05` (v0.9.16 published, tag `v0.9.16`), clean; playable roster
  Stoke, Dredge, Gusto, Dozer, Slurry, Jitters, Varga, Knell. A detached checkout of `0465a05`
  (`B:\Critterweight-work\baseline-src`) produced every "before" capture and measurement below.

## Commentary

The same twelve seeded bouts and two scripted sequences were played in real time on the untouched
v0.9.16 checkout and on this branch (`33134f2`), across a game restart, with every line logged
(`tools/audio/commentary_audit.ps1`; details and the full table in docs/audio/COMMENTARY.md §8;
logs and metrics in [commentary/](commentary/)).

| | v0.9.16 | v0.9.17 |
|---|---:|---:|
| Distinct lines heard | 125 | 338 |
| Exact repeats in a bout / in the next two bouts / across the restart | 137 / 106 / 32 | 15 / 7 / 10 |
| Same joke family twice in a row | 91 | 9 |
| Situational lines backed by a matching event | 94% | 96% |
| Referee stoppage called as a stoppage | no (called a KO) | yes |
| Decisions announced | 3 / 3 | 3 / 3 |
| Lines per live minute / share of time talking | 9.5 / 51% | 10.8 / 64% |

One defect found by the audit was fixed afterwards: lull "pressure" observations could use hits
older than the pressure window (four lines); the observation now counts only recent unanswered
hits (`test_commentary`).

## Recorded speech

521 clips installed (426 Devon, 93 Kendall, 2 Coach Buck; 33.7 min; mono 16-bit 24 kHz), every WAV
matching its catalog SHA-256. The technical speech audit (`tools/audio/breeze/audit_speech.py`:
levels, clipping, endings, pauses, pace, pitch range; heuristics, not listening) flagged 51 of the
521 new clips; 19 were retaken with direction notes (four cut-off endings, four flat deliveries on
big calls, three long pauses, the eight fastest deliveries), one retake was rejected and replaced by
a second take, and one had a stray sound after 0.4 s of digital silence trimmed. After the retakes
the four endings close at -67 to -99 dB, the pauses are under 0.4 s and the fastest lines dropped
from 26–30 to 17–25 characters per second. Breeze total for the goal: 3,255.8 of 10,000 credits
(provider report in docs/audio/breeze/v0.9.17/budget-final.json). Nothing was listened to by a
person in this session; listening approval remains with the owner.

## Fighter art

All eight playable fighters were rebuilt (docs/ART_REVAMP.md, v0.9.17 section): every model binds
the unchanged segment skeleton, passes `audit_models.js` (30k budget: 26.4k–29.8k triangles), the
art tests (`test_new_fighters`, `test_hub_cosmetics`, `test_content_audit`) and rebuilds
byte-identically from its committed source. Before/after images: [art/](art/) (front and back
comparisons and face close-ups per fighter). The whole roster side by side, the same
camera, light and pose in both builds: [art/roster_front.jpg](art/roster_front.jpg) and
[art/roster_back.jpg](art/roster_back.jpg) (v0.9.16 above, v0.9.17 below; `tools/vfx/roster_wall.ps1`,
`tools/vfx/roster_compare.ps1`), and [art/f_stoke_cmp.jpg](art/f_stoke_cmp.jpg) for the pilot fighter
(before and after, front and back).

## Legacy Varga skin

`test_varga_skins` (6/6): the legacy model is the v0.9.16 file byte for byte
(sha256 `4fa78a8a…0460fc`), the upgraded model is the default, the setting persists, its Settings row
is a controller focus stop that toggles with A, previews/matches swap live with the same body, and
Varga's gameplay data and the content hash are identical under both skins. [varga/varga_skins.jpg](varga/varga_skins.jpg): one moment of a Varga mirror bout with the default
look, then the same bout after the option was switched on mid-fight (the models swap live, the fight
carries on; `test_varga_skin_capture`). [varga/settings_graphics.jpg](varga/settings_graphics.jpg):
the Settings › Graphics tab with the "Legacy Varga skin" row (captured in the game at 1920x1080).

## Ability effects

`test_ability_vfx` (5/5): the simulation's effect events carry the true footprint (cone angle, line
length/width, ring radii, origin) and the drawn decals use exactly those numbers; every fighter's
events and entities are drawn and cleaned up; JUICE auras follow JUICE; Low quality drops light
flashes and thins particles; Reduce flashing dims flashes; the new event fields reach online
clients. Before/after showcase: 40 shots (five per fighter: both abilities, JUICE, the charged heavy
or Varga's heavy, an elemental reaction), each at the same simulation times in v0.9.16 and v0.9.17:
[vfx/](vfx/) holds one overview strip per fighter. The final frames were captured in one reserved batch (`tools/vfx/release_captures.ps1`) from the
release branch and reviewed shot by shot: every ability, JUICE, charged heavy and reaction shows a
build-up, a strike, motion and a fade in its fighter's style, nothing is drawn where nothing happens,
and no frame is missing or broken. The strips show the frame the sheet picks for each shot; a few
effects peak later in the shot (Jitters' Stormfront reaction marks its target and strikes 0.6 s after
contact, which the later frames of the full capture show).

## Saves

`test_saves_from_older_build` (3/3): an Off the Street run, a Career after a bout, settings and a user
rules preset written by the v0.9.16 checkout load in v0.9.17; the run's decision log still rebuilds it
and it plays on to the end; the career books its next bout; the settings keep their values with the
new option at its default.

## Performance

PERF_RESULTS

## Source checks

SUITE_RESULTS

## Packaged checks

PACKAGED_RESULTS

## Bug hunt

Three independent code reviews read the whole v0.9.17 diff (commentary engine, ability effects,
fighter art and the skin option) for real bugs, each finding checked against the code before it was
reported. 30 were confirmed and all were fixed with regression tests; none changed gameplay.

- **Commentary (10):** the talk budget stuck at 100% after any interrupted line (starving the rest of
  the match); a referee stoppage that ended only a round was called as the end of the bout; legacy
  `{p}`/`{o}` lines named the wrong fighters (and a ringout of the opponent was called as the
  player's); spectators got lines addressed to a player and team rounds were misattributed; landed
  abilities were sometimes called misses; 10-point decisions did not end the bout's commentary and
  every decision was called close; count and scorecard lines followed throw knockdowns,
  "first hit of the night" played every round, "It's over!" played on round KOs; a second interrupt
  inside the 0.12 s fade silenced the new line; ceremonial winner names replaced unrecorded names.
  `test_commentary` 19/19, `test_audio_announcer` 9/9, `test_recorded_speech` 9/9.
- **Ability effects (13):** delayed strikes drew Stormfront's lightning; Bulldoze and Anchor Drop looks
  fired for other fighters' charges and counters; areas from expiring projectiles were drawn in the
  air; box bursts ignored the line's direction; zone decals kept their spawn size; Hang Time's
  downdraft played on dives; Cut the Angle was drawn along the facing instead of the dash; Reduce
  flashing left a 12 Hz floor flicker; pre-contact warnings did not follow the fighter; online, every
  tapped heavy showed a charge glow (now a replicated charging bit); build-up glows ignored the light
  cap and the move's real speed. `test_ability_vfx` 18/18, `test_net_snapshot` 6/6.
- **Art and skin (7):** secondary-motion springs swung the wrong way except when hanging straight down
  (now a 3D spring about the link's real direction, with gravity); new shader terms ignored the tint
  (the 1973 tape silhouette) and older models silently received the new finish (now only the
  v0.9.17 roster art does); a skin swap reset popped cosmetics; comparison and import tooling could
  overwrite shipped or legacy models; three test assertions could not fail; the hub never drove
  expressions. `test_creature_fx_rig` 3/3, `test_creature_finish` 3/3, `test_varga_skins` 7/7,
  `test_saves_from_older_build` 3/3, `test_hub_flow` 12/12.

## Not verified

- No human listening review of the new recordings and no human or physical-controller playtest.
- Online play only over loopback.
- Linux packages are built but not run.
