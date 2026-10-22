# v0.9.18 release verification — in progress

Owner scope: `Version 17 and 18 Updates.md`, second release. v0.9.17 was published and verified
first at `e2870289c69c721024ac4ed200a5e6eda7ae4288`. This integration began from Claude's `7eba366`,
merged the shipped base in `6e891f7`, then completed the separate progression branch in `6b6329a`.
This report is not a claim that v0.9.18 is already released.

## Focused source checks

All 499 GDScript files compile. Passing checks so far: moves 123; commentary 22; campaign moves 13;
upgrade translation 8 (2,212 upgrade/build/style combinations); co-op 19; Career 62; hub services 8;
Movesets UI 10; tutorials 12; profile loadouts 5; older saves 6; network moves 5; move VFX 8. The
final integrated run will supersede these intermediate totals. The expanded rules suite passes
6/6, running all 16 built-in presets with their actual mode implementations and attack inputs,
including Chum Rush's first spawned wave. Benchmark input checks pass 2/2: a bot cannot cancel
the injected sustained hold, and the same driver exercises Classic abilities.

Three bot readiness checks and 13 existing kit-extension checks pass after correcting the AI's
ability lookup to use equipped move charges. The old lookup could choose an unavailable or
unequipped ability instead of a useful alternative. Classic retains its own ability slots.

The network checks include actual ENet server/two-client loopback sessions: selected loadouts reach
both clients; a sustained attack works from a reassigned input and ends on release; Varga's held
modifier and limb input produce the equipped Pressure Palm; and Classic agrees on server and clients.
This is local loopback evidence, not a cross-machine or internet playtest.

Initial failures and script errors are preserved beside passing reruns. They found a charge aiming
bug, missing Chumball input interception, an obsolete campaign fixture, unbeneficial upgrade offers,
hard-coded flame dimensions and misleading Varga loadout labels. Engine logs are checked for script
errors in addition to the test runner summary.

## Rendered review

`test_moves_showcase` generated 297 Windows frames: 57 moves across the roster plus eight-fighter
Movesets and Classic fights. Initial captures are 3840×2160: the game's display setting overrode the
engine resolution flag. Follow-ups use the application's own size override and are 1600×900.
Reviewed three-phase sheets for all eight fighters, individual stream/projectile/ground-effect
frames, and the crowded match. Distinct forms include rock pillars, feather/wind slashes, poison
needles, bubbles, sprung pads, spectral lanterns and martial waves.

The review identified a weak smooth-cone Flamethrower. It now has animated tongues, subdivided
geometry, broken tips, saturated fire and an optional inner core; the revised frames were reviewed.
Hydro Cannon's direction was checked: the
camera placed its attacker on the right; its claw-to-endpoint transform also passes a geometry test.
The original Varga capture bypassed his input mapping and placed the dummy beyond several contact
ranges. Captures now use real limb/modifier inputs, at the move's contact distance (0.75 m for
Force Palm, 0.85 m for Thunder Chop, 1.05 m for the others). Force Palm and Thunder Chop now show
their wind-up, impact, actual health loss and recovery; all eight techniques were recaptured.

`test_varga_skin_capture` ran bot fights with all four combinations of Movesets/Classic and
default/legacy skin, including live changes and changes back. Eight frames were saved and each
combination was visually reviewed. The gameplay rule remains independent of the cosmetic setting.

Rendered UI checks pass: ten Movesets UI tests, the four Off the Street/Fight Camp learn/drill
paths through actual rest/reward controls, Career learn/drill and Career pre-bout loadout changes.
The map test reaches its rest with synthetic prior fight results; it verifies the real menus,
saved decisions and replay, not manual completion of those preceding fights. Eighteen initial
captures cover the menus and live Practice HUD. Review confirmed readable cards, controller focus,
scrolling, descriptions and equipped move names. Varga's Practice pause menu now also exposes
Change moves; its selected preset applies live, persists and survives Restart fight. The focused
technique description updates with the preset. Final Movesets UI rerun: 10/10, 19.1 seconds.

## Bot matchups and performance diagnosis

The first real round robin completed 112 bouts: every ordered fighter pair, one 60-second round,
pro bots, the same seeds in Movesets and Classic. Each fighter used several moves. Varga won
2/14 in Movesets and 0/14 in Classic, dealing 73.9 versus 24.9 damage per bout. This small sample
describes these bots and default builds, not a human balance verdict. The report exposed frequent
denied attempts and prompted the equipped-charge fix above; a follow-up uses the corrected AI.

The corrected-AI follow-up completes all 56 Movesets bouts with a result. Denied attempts fall from
1,432 to 174 (87.8% fewer); all fighters still use multiple moves. The two reports are retained in
`balance/`. Varga remains a weak bot in this small sample (2/14 wins); no damage buff was applied
to make this particular bot result look balanced. Stoke's situational self-buff did not occur in
these default-build bouts; its actual effect is exercised by the fighter-specific tests.

An eight-fighter, 60-simulated-second headless profile measured almost unchanged simulation cost:
2.624 ms/tick for v0.9.17 and 2.604 for v0.9.18 (wall time), with simulation logic means 2.319 and
2.324 ms. Rendered measurements are separate. The first rendered comparison stopped on its last
baseline phase because a shared test profile had migrated to v0.9.18; v0.9.17 correctly refused
the newer file. The harness now isolates each build's profile. The valid records and aborted log
are retained, and corrected-AI samples are recorded separately.

A subsequent repeat exposed another harness defect: focus loss paused two matches, producing
false 218/239 FPS results with zero effects or hits. That run was stopped and retained as invalid.
The final benchmark disables pause-on-focus-loss in its private profile and records simulation
seconds/ticks; its wrapper rejects samples without a live advancing fight or attack effects.
Both comparison checkouts use the identical harness. The event consumer also now scans only the
new tail rather than all 512 historical event dictionaries per update; rollover, sparse sequence,
empty/future cursor and independent-array tests pass (2/2), preserving gameplay/event order.

The final 16-case comparison plus one documented baseline replacement are retained in `perf/`.
Average FPS over the two repeats, v17 → v18: Deck/plain 119.5 → 114.5, Deck/forced attacks
100.4 → 97.9, High/plain 108.7 → 98.5, High/forced attacks 84.1 → 85.2. The High/plain v18 samples
varied from 84.0 to 112.9 FPS, so a further ABBA confirmation doubled sampling to 60 seconds.
That confirmation gives v17 101.0/104.2 and v18 99.9/108.5 FPS; p95 is 15.824/14.947 versus
16.053/14.082 ms. The apparent large ordinary-High slowdown did not reproduce consistently.
The revised bot readiness and event-tail work address identified overhead without removing effects
or reducing their quality. The heavy-effects averages remain close to baseline; there are still
slow-frame spikes (the 30-second High/forced v18 samples have 7.3–12.5% above 16.7 ms).
This is no constant-60-FPS or Steam Deck claim. All original values, exclusions, active-fight
guards and repeat provenance are in `perf/README.md`; no inconvenient valid result was discarded.

The patch-note generator omitted `title` in v0.9.17 and the first v0.9.18 draft. The screen's old
test only checked version and focus, so it passed despite engine errors. The generator now fills
titles, the screen has a legacy fallback, and the test asserts every archived body actually renders.
The v0.9.17 report records that historical defect; its published assets remain immutable.

## Persistence and accounting

Seven fixtures were written by the downloaded published v0.9.17 Windows executable using its own
stores. The JSON and hashes/executable provenance are in `game/src/test/fixtures/saves_v0917/`.
Six older-save checks pass: v0.9.16 and v0.9.17 runs migrate, re-equip, finish and verify their logs;
Careers retain their record and play a real headless next bout; settings and preset fields survive.
Five profile-loadout checks include both releases' profiles, retaining every existing profile field.

Combined Breeze spending is **4,425.0 / 10,000 credits**, per the saved journals/provider report:
3,255.8 for v0.9.17, 818.4 for v0.9.18 commentary, 350.8 for v0.9.18 tutorials. No additional paid
generation occurred during takeover.

The installed v0.9.18 speech integrity audit passes all 254 clips (132 commentary and 122 tutorial
fragments, 671.405 seconds). Every WAV matches its catalog and completed request journal, decodes
as mono 24 kHz PCM16, has a matching duration, is non-silent and peaks at or below -3 dBFS.
The retained retake selections comprise ten commentary and thirteen tutorial replacements.

## Remaining gates

The first clean integrated attempt (`6dccf14`, `source-attempt-1/`) was stopped after finding two
failures. The loadout screen requested the nonexistent `ui_confirm`; it now uses `ui_accept`.
The stream-audio test incorrectly included `line:` commentary actions in its impact count. It now
counts sound IDs only, requires exactly one impact across eight rapid ticks, and additionally checks
independent per-target cooldowns and audible recovery after the interval. Commentary still receives
every event; no playback was removed to satisfy that test. A fresh full run follows these repairs.

The second clean full run (`ae6aa78`, `source-attempt-2/`) completed: **1,122 run, 1,118 passed,
three failed, one graphical-audio skip**, in 3,222.2 seconds. Its ten-minute loopback soak passed
with thirteen matches, zero orphaned nodes and clean shutdown; static/working-set slopes were
0.139/0.149 MB per minute. The three failures and a rendered focus defect led to these repairs:

- The spectral-cover fixture now updates logical aim when placing the rig and includes an
  unobstructed control. Expanded tests exposed a real gap: spectral shots bypassed summoned rocks
  and splat proxies but were stopped by other solid arena props. Both cover paths now honor the
  trait. Three focused checks pass in Classic and Movesets, including damage and actual contact.
- The network policy check now explicitly selects Classic. A new real ENet check proves that the
  new preset uses a fallback bot and no longer advertises the unused Classic policy's hash.
  Both policy paths pass.
- Shared focus reveal no longer scrolls twice from stale container positions. It waits for layout,
  measures the scaled card in scroll-local coordinates and reserves focus-ring clearance. The
  middle-card regression, thirteen Career UI checks and the other headless UI checks pass.
  Real Career learn/drill navigation passes at 1600×900 and 1280×800; both captures were reviewed.
- Dredge's walking driver was repeatedly pushing diagonally into Ludlow. A full sidestep clears
  him. The wandering planner deliberately visits transport-only rooms in its second half if
  random exploration has not covered them yet. Duration, required progress, transport visits,
  allowed blockage and all safety limits remain unchanged. Both harness checks pass; all six
  walkers finish with no timeouts or floor/knockdown failures.

The broad rendered `ui` substring filter also selects built-in modes and other matching checks.
Its first follow-up ran 165 tests: 164 passed and the hub-secret test failed after its wall-clock
delay sent a taunt before recovery. The test now waits for the actual fighter cooldown
and neutral state, retains exactly three real key presses, and asserts each press produces one
taunt and recovery takes less than three simulated seconds. No cooldown or game behavior changed.
The complete rendered rerun passes **165/165**, with no skips or engine/script errors, in 516.3 s.
Both resolution-specific Career checks also pass again. The rerun is retained separately from
the failed attempt, which includes a Jolt worker-pool warning.

Original failed diagnostics and passing follow-ups are in `focused/source-regressions/`.
The original clipped `ui/career-drill-move.jpg` remains as historical evidence; the reviewed
full frames after repair are `ui/career-drill-move-final-1600.png` and
`ui/career-drill-move-final-1280.png`, with their own hash provenance.

Finish the full integrated suite and ten-minute soak, four-target packages and packaged checks, and publication/
download verification. Exact final commits and raw results will be recorded here. No physical-
controller, human listening/playtesting, Deck, Linux runtime or external-network claim is made.

Working evidence and full-resolution originals: `B:\Critterweight-work\v0.9.18\takeover`.

## Reviewed media

Three-phase move sheets: [Stoke](combat/stoke.jpg), [Dredge](combat/dredge.jpg),
[Gusto](combat/gusto.jpg), [Dozer](combat/dozer.jpg), [Slurry](combat/slurry.jpg),
[Jitters](combat/jitters.jpg), [Knell](combat/knell.jpg), [Varga](combat/varga.jpg).
The sheets use actual Windows Godot frames, cropped to the fighting area and resized for review;
`capture-provenance.json` records original paths and hashes. Stoke's final flame and Varga's
real-input captures replace the earlier inspection frames. The full screenshot copies in
`combat/` show final flame contact and all four Varga skin/combat combinations. `ui/` holds the
reviewed loadout, live Practice and campaign learning/drilling screens.
