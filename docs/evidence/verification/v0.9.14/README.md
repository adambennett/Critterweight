# Critterweight v0.9.14 verification

**Scope:** quieter menu focus feedback after the v0.9.13 audio replacement release. The approved navigation sound uses three short Kenney Interface Sounds ticks at -14 dB. The tagged release is commit `95c857aa0110dacf8e73f451de7089ac9bbd6b1a`; the release build, temporary user data, logs and downloaded/test artifacts stayed on B:.

## Checks

- Godot 4.5.1 script check: **394 scripts, 0 failures**. [Packaged check log](packaged-script-check.log). The package was built from the clean `v0.9.14` tag; the [build manifest](tagged-build-manifest.json) records all four targets and `working_tree_dirty: false`.
- Source audio suite on v0.9.14: **20 run, 20 passed, 0 failed, 0 skipped**. This includes `test_menu_focus_uses_soft_interface_ticks`, which checks the three exact bank clips, the -14 dB ceiling, stream loading and short duration. [Results](source-audio-tests.json) · [runtime log](source-audio-tests.log).
- Packaged Windows audio suite: **20 run, 18 passed, 0 failed, 2 source-only checks skipped**. The new menu tick test passed against the exported PCK. The skipped checks scan source files that are not shipped in exports. [Results](packaged-audio-tests.json) · [runtime log](packaged-audio-tests.log).
- Packaged Windows game booted to the title in **5684 ms** and its rendered regression suite passed **20/20**, with no skips. [Boot report](packaged-boot.json) · [test results](packaged-rendered-tests.json) · [runtime log](packaged-rendered-tests.log).
- The four game/server targets were exported and archived. All **seven** GitHub release assets have sizes and SHA-256 digests matching their local files and the GitHub API. [Published asset verification](release-assets.json) · [published checksum file](release-SHA256SUMS.txt).

The full source suite was not rerun for this focused menu-audio mix change. Linux targets were built but Linux runtime playback was not tested. The headless audio tests pass with exit code 0; Godot also prints its ObjectDB/resource-in-use shutdown diagnostic after the tests, as in the prior audio test run. Automated checks verify wiring and playback resource loading, while the owner approved the sound by listening in-game.

## Published release

GitHub prerelease **[v0.9.14](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.14)** points to `95c857a`. The release notes are [here](../../../releases/v0.9.14.md).