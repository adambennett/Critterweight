# Critterweight v0.9.13 verification

**Scope:** free stock-audio replacements, Random in every fighter picker, and the v0.9.12 playtest fixes carried forward. The source clone, downloaded archive, test data and package output were kept on B:. The separate Ableton audio experiment remains in its own checkout.

## Source checks

- Full Godot source suite: **718 run, 717 passed, 0 failed, 1 skipped**, 2260.9 seconds. The skipped dropdown/ambience test requires the graphical audio backend. The run covers campaign progression and resume, the Cannery, menus, multiplayer, AI Lab and fighter selection. [Full runtime log](full-suite.log).
- Fighter-selection tests: **24/24 passed**. The AI Lab / hub service integration tests: **8/8 passed**, including the live AI Lab Random option and resolution to a playable fighter. [Fighter-selection log](fighter-selection-tests.log), [AI Lab log](ai-lab-picker-tests.log).
- Audio bank tests after the export-aware assertion change: **10/10 passed in source**. The Windows PCK run tested the same 10 cases: **8 passed, 0 failed, 2 source-file-only checks skipped**. All selected replacement streams load from the exported PCK. [Source result](source-audio-tests.json), [packaged result](packaged-audio-tests.json).
- Godot script check: **394 scripts, 0 failures**. [Log](script-check.log).
- Audio reproducibility check: all **638 generated renders match** the committed files. [Log](generated-audio-reproducibility.log).
- All four Windows/Linux game and dedicated-server targets exported and archived during the B: preflight. The release script repeats packaging and runs the tagged Windows boot and rendered playtest checks before publishing.

The source suite ran before a test-only adjustment made the replacement-asset check understand Godot's PCK imports. Production code did not change afterward. The adjusted test was rerun in source and in the packaged Windows game as recorded above.

## Audio and licensing

The release installs **126 audio files (about 34.8 MiB)**. Kevin MacLeod's four music tracks are under CC BY 4.0 and the required author/title/license attribution appears in the game Credits. The remaining installed clips are CC0 1.0. No paid license or purchase was used. File-level URLs, creators, license tags, hashes and bank references are in the [replacement inventory](../../../audio/replacement-audio-inventory.txt); the original downloaded files and provenance are under `game/assets/audio/replacements/`.

The source pages describe the music as free with attribution and provide the required credit wording; Kenney identifies its asset pages as CC0 for commercial use. The OpenGameArt pages identify the installed crowd, applause and water samples as CC0. See the links in [the replacement guide](../../../audio/REPLACEMENT_GUIDE.md).

Automated tests verify imports, bank wiring, hashes and package availability. They do not judge the sound aesthetically; the owner will audition the tracks in-game. Linux packages are built here but Linux runtime playback is not covered by this Windows test run.

## Engine diagnostics

The successful full source run recorded one Jolt job-pool capacity warning in a physics-heavy fixture, followed by Godot's full-run-only ObjectDB shutdown warning and **four resources still in use**. The malformed network-payload tests also print rejected Variant decoding diagnostics as expected. These did not fail any tests. The Jolt and shutdown warning pattern was recorded in the v0.9.12 full-run report as well; the clean tagged rendered smoke is checked separately by the release script.

## Tagged release

Release tag, commit, clean packaged manifest, packaged boot, rendered regression and uploaded asset digests are recorded here after the release script completes.
