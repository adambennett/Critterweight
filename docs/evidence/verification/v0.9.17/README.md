# Critterweight v0.9.17 verification

**Scope:** the owner's v0.9.17 specification (`Version 17 and 18 Updates.md`, first release):
commentary overhaul, full-roster art with expressions and secondary motion, the "Legacy Varga skin"
option, and new ability effects for every fighter. Gameplay is unchanged. Ledger rows C17-01..05,
ART-10, ART-11, VFX-01, SAV-04 (docs/REQUIREMENTS.md). Checklist:
[docs/releases/v0.9.17-v0.9.18-checklist.md](../../../releases/v0.9.17-v0.9.18-checklist.md).

Machine: Windows 10 (19045), i7-7700K, RTX 4070 Ti Super, Godot 4.5.1 (official), Blender 5.2.2.
Networking is loopback on this PC.

## Published release

[v0.9.17](https://github.com/adambennett/Critterweight/releases/tag/v0.9.17) was published on
2026-10-21 at 22:39:35 UTC from the clean, tested commit
`e2870289c69c721024ac4ed200a5e6eda7ae4288`. The annotated tag is immutable.

- Final integrated source run: **925 run, 924 passed, one expected graphical-audio skip, zero
  failures**, 3139.6 seconds. Source stayed clean and unchanged. [Run metadata](final-source-run.json),
  [all results](full-source-results.json), [log](full-source.log).
- Final ten-minute soak: 13 matches, zero orphan nodes, static-memory slope +0.0074 MB/min and
  working-set slope +0.0306 MB/min; clean server exit. [Report](soak/final-ten-minute-report.json).
- Tagged Windows build: 455 scripts compile; title in 5461 ms; all 20 rendered playtests pass
  with no skips/failures or engine/script errors. [Release smoke](publication/release-smoke/).
- All **seven actual GitHub downloads**, uploaded SHA-256 digests, checksum-list entries,
  manifest source/version, four archives' members and Linux executable permissions verify. The
  standalone Windows executable matches the packaged executable exactly.
  [Publication verification](publication/verification.json), [manifest](publication/BUILD_MANIFEST.json).
- The downloaded standalone Windows game reaches the title in **5717 ms**, reports the expected
  tagged build stamp, and exits cleanly with no engine/script errors.
  [Downloaded-game smoke](publication/downloaded-smoke/).

The source-only audio skip is covered by the rendered packaged audio/UI checks. Physical-controller,
human listening, external-network, Linux-runtime and Steam Deck checks are not claimed. The final
performance measurements below retain occasional frame-time spikes; they do not establish a
constant 60 FPS on this PC or the Deck. Earlier failures remain as chronological evidence.

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
from 26–30 to 17–25 characters per second. This release used 3,255.8 credits
(provider report in docs/audio/breeze/v0.9.17/budget-final.json). Claude also generated v0.9.18
recordings before the takeover: the latest combined ledger is 4,425.0 of the single 10,000-credit
allowance, leaving 5,575.0 for the rest of the goal. Nothing was listened to by a person in this
session; the owner can judge delivery quality in the published build.

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

`test_varga_skins` (7/7): the legacy model is the v0.9.16 file byte for byte
(sha256 `4fa78a8a…0460fc`), the upgraded model is the default, the setting persists, its Settings row
is a controller focus stop that toggles with A, previews/matches swap live with the same body, and
Varga's gameplay data and the content hash are identical under both skins. [varga/varga_skins.jpg](varga/varga_skins.jpg): one moment of a Varga mirror bout with the default
look, then the same bout after the option was switched on mid-fight (the models swap live, the fight
carries on; `test_varga_skin_capture`). [varga/settings_graphics.jpg](varga/settings_graphics.jpg):
the Settings › Graphics tab with the "Legacy Varga skin" row (captured in the game at 1920x1080).

## Ability effects

`test_ability_vfx` (18/18 in the corrected rendered source and package): the simulation's effect events carry the true footprint (cone angle, line
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

Paired before/after benchmark (`tools/vfx/paired_release_bench.ps1`: the rendered 8-fighter pro-bot
brawl in the primary cage, v0.9.16 and v0.9.17 alternated before, after, after, before; each run 5 s
warm-up and 30 s measured; plain, and with every fighter using an ability every 3 s), measured
2026-10-21 with the machine otherwise idle (another project's builds paused for the window; an
earlier attempt alongside them was discarded). Median frame time and frame rate, both runs per build
([perf/summary.md](perf/summary.md)):

| Scene | v0.9.16 | v0.9.17 |
|---|---:|---:|
| 1280x800 (Deck preset), plain | 5.25 ms, 210-216 fps | 7.05 ms, 145-147 fps |
| 1280x800, every fighter's abilities | 6.1 ms, 170-182 fps | 8.65 ms, 108-110 fps |
| 1920x1080 (High), plain | 5.95 ms, 182-186 fps | 7.8 ms, 123-126 fps |
| 1920x1080, every fighter's abilities | 6.6 ms, 160 fps | 9.1 ms, 102-105 fps |

The new look costs about 1.8-2.5 ms per frame in this crowded scene on the development PC (i7-7700K,
RTX 4070 Ti Super): about twice the surfaces and bones per fighter (plain-scene draw calls
553 -> 641 at 1280x800 and 899 -> 1054 at 1080p), the face rigs and secondary-motion springs,
and the richer effects. Frames
over 16.7 ms stay at about 1 % or less, and the 95th percentile at 9-14 ms, well inside the 60 fps
budget (docs/DESIGN.md: 16.6 ms). Before release the fighter views were optimised (cached skeleton
data, the springs in packed arrays with each link composed once, material values written only when
they change, and springs stepping every second or fourth frame on fighters small on screen, never
under ~30 Hz): the views' own script time for eight fighters fell from 2.1-2.5 ms to 1.4-1.6 ms per
frame at full detail (v0.9.16: 0.4-0.5 ms; `tools/vfx/view_cost.ps1`, [perf/view_cost.json](perf/view_cost.json)).
Not measured: the Steam Deck itself (no Deck here); its 60 fps target in this scene remains to be
checked on the device.

### Intermediate continuation measurement

After the raised-rail fading repair, before the subsequent small post-cap correction, the same 16-run comparison was repeated on 2026-10-21
(`perf/final/`, including every raw sample and engine log). The development desktop was in use:
two five-second process samples observed ReclaimerServerMonitor at 44.4% and 72.5% of one core.
That may contribute to variability, but does not establish the cause of any particular spike.

The final candidate's two ordinary 1280x800 runs averaged 120.8/122.4 FPS (p95 13.87/12.83 ms);
at 1080p they averaged 107.2/106.3 FPS (p95 14.37/15.27 ms). Simultaneous abilities were more
variable: 73.9/143.8 FPS at 1280x800 (p95 27.43/10.97 ms) and 76.3/99.3 FPS at 1080p
(p95 22.09/14.60 ms). The first old-build 1280x800 run was also an outlier: 84.1 FPS/p95 50.87 ms,
versus 181.2 FPS/p95 9.08 ms on its repeat. All observations are retained, including the two
candidate effect-heavy runs with 15.8-17.2% of frames over 16.7 ms. This repeat confirms average
headroom on this PC; it does not establish a consistently met 60 FPS frame-time budget under this
desktop load. The earlier quiet-machine comparison above remains separately identified.

### Final clean release commit

All sixteen paired runs were repeated on `e287028` with a 15-second warm-up and 30-second measurement
per run. An initial attempt overlapped a running TAM game and was stopped after eleven completed
reports. The owner closed TAM, and the complete comparison was restarted in a fresh folder.
Both the interrupted data and the process-load sample are retained in `perf/interrupted-desktop/`;
the final sixteen reports, logs, load sample and review are in [perf/clean-release/](perf/clean-release/).
All final benchmark engine logs are free of warnings/errors. All measured windows have the requested
resolution, and every abilities run includes ten simultaneous bursts across the eight fighters.

| Scene | v0.9.16 FPS, both runs | v0.9.17 FPS, both runs | v0.9.17 p95 frame time | v0.9.17 frames over 16.7 ms |
|---|---|---|---|---|
| 1280x800, plain | 197.2 / 187.4 | 128.0 / 129.1 | 11.41 / 10.94 ms | 0.86% / 0.34% |
| 1280x800, simultaneous abilities | 182.2 / 172.4 | 104.2 / 96.1 | 15.22 / 16.52 ms | 2.75% / 4.89% |
| 1920x1080, plain | 180.1 / 337.0 | 113.1 / 107.2 | 12.92 / 14.38 ms | 0.94% / 2.39% |
| 1920x1080, simultaneous abilities | 150.7 / 157.5 | 85.3 / 88.8 | 17.63 / 17.21 ms | 7.26% / 6.00% |

The late 1080p plain baseline is substantially faster than its first pass; no cause is asserted and
neither result is discarded. The upgraded art/effects have measurable cost, with average frame-rate
headroom in all four measured scenes. The heaviest 1080p scenario exceeds the 16.7 ms budget in
6-7% of frames, so a consistently met 60 FPS frame-time target is **not** claimed. The original
quiet-machine and intermediate results remain separate rather than replacing these final observations.

## Source checks

The earlier continuation suite on `1161cfe` completed 924 tests: 922 passed, one graphical-audio
skip and one short-soak failure. The final integrated run on `e287028` with `-SoakMinutes 10`
subsequently passed, as recorded above. The original run on `16b2dc3` had two different failures,
both passing in this continuation run and the final run:

- `test_hub_unlocks::test_vintage_bellows_calls_matches_when_selected` asked the 1973 Barnaby pack
  for a KO call without saying the fight had ended; its "It's OVER!" line is gated to a fight-ending
  knockout since the commentary review. The test now asks for one (`7dafebe`); focused and integrated checks pass.
- `test_net_party_campaign::test_party_run_three_players_majority_route`: the three-player co-op
  party lost its scripted first fight while another project's game ran on this PC (203 s instead of
  116 s); the fresh integrated run passes it in 105 s.

The remaining failure compared a one-fighter Chum Rush match with a four-fighter Spotlight Hog
match over the second minute: 2.08 MB growth, 1.86 MB/min. The subsequent ten-minute soak completed
13 rotations, no orphan nodes, -0.05 MB/min static-memory trend and +0.02 MB/min working-set trend
over the second half. This supports bounded allocations as match sizes/content change, not sustained
growth in that run. Neither the memory threshold nor the assertions were weakened. Original failures
are retained separately: [16b2dc3](full-source-results-16b2dc3.json),
[1161cfe short soak](full-source-results-1161cfe-short-soak.json); raw short and long samples are in
[soak/](soak/).

All 455 scripts compile, including fresh checks during candidate packaging. Subsequent changes are
verification tooling, documentation, corrected credit/release-note text and a camera-occlusion fix;
authoritative gameplay source is unchanged. The VFX test helper now waits in real process time,
matching the effect clock, instead of assuming that process frames run at 120 Hz. The earlier
packaged timing failure is retained in `packaged-initial/`; assertions were preserved.

**Gameplay unchanged.** The same seeded pro-bot fights, stepped headless at the fixed 1/120 s tick in
the v0.9.16 checkout and in this one, play out identically: 17 of 17 fights (every fighter, both
corners, and an eight-fighter brawl), every hit, knockdown, ability, status and result on the same
tick with the same damage ([gameplay/cross_build_fights.md](gameplay/cross_build_fights.md),
`tools/verify/cross_build_fights.ps1`). The new art, effects, commentary and the Legacy Varga skin
are presentation only.

## Packaged checks

The four candidate targets have been exported and every archived file matches the build manifest
(18 Windows-game files, 18 Linux-game files, 12 Windows-server files and 11 Linux-server files).
The Linux executable bits are also present. The initial matrix ran 200 checks: 198 passed, one
source-only GLB hash skip and the test-clock failure described above. After correcting that helper,
the four repeated rendered suites ran 54 checks: 53 passed, the same expected source-only skip,
zero failures (`packaged-recheck/`). The earlier headless feature suites passed all 126 checks,
including commentary, Career, judges, referees, old saves, snapshots, roster and server load.

The packaged dedicated server with eight fighters used 30.5% of one core on its main thread
(budget <35%); traffic was 25.6 KB/s down and 5.6 KB/s up per client. The actual server package,
two game clients and a rendered spectator pass all seven loopback-session checks: both clients
receive the same authoritative winner, admin authentication works, wrong tokens are refused, all
processes exit cleanly and the five logs contain no engine/script errors. The spectator frame
also revealed a raised horizontal cage rail excluded from fading because it was thin. The view
now accepts long thin raised geometry, with a regression that retains low-trim/tiny-prop exclusion.
Another spectator angle exposed the small caps and bands left opaque above a faded post; the
minimum span now includes those actual cage parts too, with a separate ray through a cap in the
regression. The final full-suite and performance runs on `e287028` include that completed fix.

The third candidate's rendered playtests also exposed a fixture precondition: the dropdown test
assumed its application had native foreground focus, although verification launches in the
background. Background audio muting was correct in that state. The fixture now requests and
asserts native game focus before opening and focusing the actual popup; all original popup/audio
assertions remain. The fourth candidate passes all 27 rendered combat-feel/playtest checks and
all seven loopback checks. The third candidate's failure is retained in `packaged-rail/`.
The fifth candidate includes the completed rail/cap repair: again all 27 rendered checks and
seven packaged loopback checks pass (`packaged-final-candidate/`). Its actual spectator frame
was reviewed. Script compilation remains 455/455; no authoritative gameplay changes were added.

The Linux portability audit passes all six checks: case-exact resource paths, no Windows-only
game constructs, both ELF64 x86-64 executables with embedded data and glibc <=2.28, and archive
execute bits. `res://build_info.json` is an explicitly generated export input, so the source-path
audit now recognizes that exact path. This is not Linux runtime verification.

These earlier candidates were built from an uncommitted documentation/evidence tree. The published
build was subsequently rebuilt from the clean verified release commit, as recorded above.

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
  `test_commentary` 20/20 in the continuation package, `test_audio_announcer` 9/9, `test_recorded_speech` 9/9.
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

Follow-up during v0.9.18 verification: the v0.9.17 full-suite log contains two patch-notes screen
script errors even though its test reported a pass. The generated v0.9.17 archive entry omitted
`title`; the test checked version/focus without checking the displayed body. v0.9.18 repairs the
generator and historical entry, adds a display fallback and asserts every archive body renders.
The published v0.9.17 assets and immutable tag remain unchanged. Its full log also contains four
expected native decoder errors from tests that deliberately reject serialized objects; these are
distinct from the patch-note defect.

- No human listening review of the new recordings and no human or physical-controller playtest.
- Online play only over loopback.
- Linux packages are built but not run.
