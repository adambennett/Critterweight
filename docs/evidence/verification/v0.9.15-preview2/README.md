# v0.9.15 preview 2 — verified local build

The owner resumed work on 2026-10-18 and authorized the full Breeze dialogue batch up to
3,500 credits, with Coach Buck for coaching. PAUSE_CHECKPOINT.md is a historical checkpoint;
its former hold and research-only voice status are superseded by that authorization.
No graphical game launch or release publication is authorized for this preview.

## Completed source checks

- Script check before the voice integration: 400 scripts, zero failures.
- New preview regressions: 13/13 passed after the compact-team focus and spare-charge fixes.
- UI: 93 tests, 92 passed, one expected headless skip, zero failures.
- Existing audio: 20/20; settings: 7/7; hub flow: 10/10.
- Network measurement: independent loopback duel and eight-fighter FFA pass. The test fixture
  now keeps the duel alive for the full measurement window without weakening its assertions.
- All 29 unique event-art files match their provenance hashes (76,348,895 bytes).
- Original crowd files match the v0.9.12 assets; the approved single menu tick is unchanged.
- All 764 Breeze WAVs match their catalog/journal hashes, are mono 16-bit PCM, and have peaks
  no higher than -3 dBFS. 31.99 minutes, 92,153,056 bytes. Final provider budget: 3,230.2 used,
  zero reserved, 269.8 remaining. Full casting/accounting: docs/audio/breeze/.

The full suite completed: 733 run, 730 passed, two failed, one expected headless skip
(2,759.2 seconds). It began before voice integration. Both failures were test-fixture issues:
- Editor naming test inherited another test's restored editor session; now explicitly starts a
  new Gullet layout. Its isolated rerun and combined UI rerun pass (93 run, 92 passed, one headless skip).
- Four-player campaign voting used a seed whose roster-dependent content was Timed Scrap,
  not the assumed Dock Rats opener. A verified seed/route and preflight assertions preserve
  the untimed minion fight, personal-event vote, captain tie-break and save-credit checks.
  Final loopback four- and three-player reruns each pass (145.1 s and 126.7 s).

Final voice integration checks: 402 scripts, zero failures; audio 28/28; tutorials 18/18;
hub flow 10/10; hub UI 4/4; preview regressions 13/13; settings 7/7. After adding the approved
custom names, recorded-speech tests pass 9/9, including all 764 decoded clips and aliases.
All jobs used isolated B: roots, BelowNormal priority and sequential Godot execution.
Several combined source runs retain the pre-existing shutdown-only ObjectDB/four-resource
warning; there are no script/parse errors in the completed successful checks.

## Delivery target and boundaries

Executable: B:/Critterweight/release-work/v0.9.15-preview2/Critterweight-0.9.15-preview.exe.
Windows export from clean source commit a527f2d, version 0.9.15, 241,886,992 bytes.
SHA-256: b359fdc81057449360208355783e6432791cf4c60207dc22da618b52f155727c.
BUILD_MANIFEST.json records every package file. The delivery copy matches the packaged exe.

Packaged headless checks: 402 scripts, zero failures; recorded speech 9/9; preview regressions
13/13; settings 6 passed plus one expected source-scan skip; hub flow 10/10; tutorials 18/18.
The tutorial/hub combination retains the same shutdown-only resource warning as source runs.
No script/parse errors or test failures. All packaged checks used isolated B: user roots and
CreateNoWindow. No graphical launch, tag, push or release publication occurred.

This completes the previous playtest-fix and dialogue batch. The subsequent rooftop canvas
request is a separate follow-on change and will produce a newer local preview.

No new graphical Windows-runtime claim is made. Physical controller feel, real multi-monitor
placement, visual composition and listening taste require the owner's playtest. Code-capable
mods remain research only. Duplicate Cancel candidates are listed in
../../../releases/v0.9.15-follow-up-notes.md; only New rules was changed.
