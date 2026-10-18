# Releases and versioning

Builds are published as GitHub Releases of this repository
(https://github.com/adambennett/PokeMMA/releases). Each release is one git tag and one set of files
built from exactly that commit.

## Download and play (testers)

1. Open the latest release and download **`Critterweight-<version>-windows-x64.exe`** — the whole game
   in one file (Windows 10/11, 64-bit, a Vulkan-capable GPU). Double-click it. Or download the
   `-windows-x64.zip` for the same game plus the player guide, modding guide and licences.
2. Windows SmartScreen may say "Windows protected your PC" because the build is not code-signed:
   choose **More info → Run anyway**.
3. Your profile, settings and saves go to `%APPDATA%\Critterweight`, never next to the exe, so a newer
   build keeps your progress.
4. The version and commit are shown in the main menu's footer (and the first lines of
   `%APPDATA%\Critterweight\logs\`): quote them in bug reports.

Other files in a release: the dedicated server (`-server-windows-x64.zip`, `-server-linux-x86_64.tar.gz`),
the Linux game (`-linux-x86_64.tar.gz`, not runtime-tested on Linux yet), `BUILD_MANIFEST.json`
(per-file SHA-256 of the packages) and `SHA256SUMS.txt`.

The repository is private: a tester needs to be added as a collaborator (or the repository made
public) to see its releases.

## Versioning

- **Single source of truth:** `application/config/version` in `game/project.godot`. The game uses it for
  mod compatibility (`ModManager.version_satisfies`) and the network handshake (online play needs the
  same version on every machine).
- **Tags:** every release is the commit tagged `v<version>` (annotated). A tag never moves.
- **Build stamp:** `tools/build/package.ps1` writes `game/build_info.json` (version, tag, commit, dirty
  flag, time) into the export; `BuildInfo.label()` shows `0.9.0 (5533dcd)` for a tagged build,
  `0.9.0+5533dcd` for an untagged one and `0.9.0-dev` when running from source.
- **Numbers:** preview builds are `0.9.x` (GitHub pre-releases); release candidates are `1.0.0-rc.N`;
  the release itself `1.0.0`. The bundled example mods target the same version (0.x: same minor, 1.x:
  same major), so the release script updates and repacks them on every bump.

## Cutting a release

```powershell
# from the repository root, on a clean, pushed main
powershell -ExecutionPolicy Bypass -File tools/build/release.ps1 -Version 0.9.4 -Bump -Prerelease -NotesFile notes.md
```

`release.ps1` sets the version (with `-Bump`) and commits it, checks the tree is clean and on `main`,
creates the annotated tag, builds all four packages (`package.ps1 -Archive`), smoke-tests the packaged
game (script check + boot to the title screen), writes `SHA256SUMS.txt`, pushes the tag and creates the
GitHub release with the assets (`gh`). `-DryRun` does everything except pushing and publishing.
Use `-TestFilter test_playtest` to require the rendered playtest regressions to pass in the exported
Windows game before publication. Every required game/server archive must exist; missing assets abort the release.

### Alt builds (side-by-side comparisons)

An alt build lets the user try a branch under review next to the main build, without merging it. It is a
pre-release such as `v0.9.7-alt.1`, built from a local `alt/<name>` branch. For example, the creature-art
pull request: the user asked to compare it before deciding.

```powershell
git switch -c alt/creature-art main
git merge --no-ff origin/art/creature-revamp      # the branch under review
powershell -ExecutionPolicy Bypass -File tools/dev/run_suite.ps1   # green, as for any release
powershell -ExecutionPolicy Bypass -File tools/build/release.ps1 -Version 0.9.7-alt.1 -Bump -Alt -NotesFile notes.md
```

`-Alt` behaves differently from a normal release:
- It needs an `X.Y.Z-alt.N` version and an `alt/` branch.
- It always publishes a pre-release, titled as an alt build.
- It pushes the alt branch and its tag, and leaves `main` untouched.

Online play needs the same version on both ends, so alt and main builds can't play each other. If the user
picks the alt build, its branch is merged into `main` and released normally. Otherwise the alt branch
just stays where it is.

The creature-art alt builds ended this way: the user picked the new art, PR #1 was merged into `main`,
and 0.9.10 ships it. `alt/creature-art` is retired.

## Release log

| Version | Tag | Date | Notes |
|---|---|---|---|
| 0.9.13 (preview, audio replacements) | [v0.9.13](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.13) -> pending | 2026-10-17 | 126 CC BY 4.0 / CC0 replacement recordings with in-game credits and hash inventory; Random in every fighter picker; source suite 717 passed / 1 graphical-only skip / 0 failed; packaged audio 8 passed / 2 source-only skips; tagged smoke and publication pending; [release notes](releases/v0.9.13.md) |
| 0.9.12 (preview, playtest fixes) | [v0.9.12](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.12) -> 0e8b20f | 2026-10-17 | Campaign progression/resume, controller scrolling/focus, Compendium, visible Bookie fights/free camera, Cannery activities, editor/settings and ambience fixes (D-042); source suite 710 passed / 1 graphical-only skip / 0 failed; tagged Windows build 20/20 rendered regressions, title in 4.5 s; seven uploaded asset digests verified; [verification and limits](evidence/verification/v0.9.12/README.md) |
| 0.9.11 (preview, playtest build) | [v0.9.11](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.11) -> 1024039 | 2026-10-17 | Combat feel (D-035): hit pause, camera punch, body jolt, lingering health chunk; walls and crowd between camera and fighters fade or shrink; suite 691/691 |
| 0.9.10 (preview, playtest build) | [v0.9.10](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.10) -> fa0725f | 2026-10-17 | The new creature art: PR #1 merged (D-041), twelve Blender-modelled combat creatures, credits; suite 685/685; packaged boot to the title in 4.4 s |
| 0.9.9-alt.1 (**alt build**, comparison) | [v0.9.9-alt.1](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.9-alt.1) -> 19d029a on `alt/creature-art` | 2026-10-17 | 0.9.9 plus the creature art revamp (PR #1) and its credits; suite 685/685 |
| 0.9.9 (preview, playtest build) | [v0.9.9](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.9) -> eecaa39 | 2026-10-17 | Busy fights readable: steeper crowd camera, plates 5-8 at the top corners; short-soak and cross-drive test fixes; built on B:; protocol 5 |
| 0.9.8-alt.1 (**alt build**, comparison) | [v0.9.8-alt.1](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.8-alt.1) -> 33e80fb on `alt/creature-art` | 2026-10-17 | 0.9.8 plus the creature art revamp (PR #1: twelve Blender-remodelled creatures) and its credits, for a side-by-side choice; `main` untouched |
| 0.9.8 (preview, playtest build) | [v0.9.8](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.8) -> 57613cc | 2026-10-16 | Cross-platform hashes (Canon): the Linux dedicated server now hosts Windows players (first Linux run, Debian 12 container); saves and party tickets agree across platforms; Docker notes; `--arena-hash`; built on B: (C: nearly full); protocol 5 |
| 0.9.7 (preview, playtest build) | [v0.9.7](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.7) -> 9e9d93c | 2026-10-16 | Bookie's Table camera presets (Broadcast / Director / Free); its control bar no longer hides the fighter plates; client soak (48 matches, no leak); missing-mod save resume and display Keep/Revert tested; ledger audit; protocol 5 |
| 0.9.6 (preview, playtest build) | [v0.9.6](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.6) -> 68673c1 | 2026-10-16 | Review fixes: Chum Rush supplement picks apply (OTC/Prescription offers), Chumball KOs no longer score, Rooftop railings along the short edges (were fencing the floor), bots steer round props (Swarm Night stall), flaky resume test fixed; protocol 5 |
| 0.9.5 (preview, playtest build) | [v0.9.5](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.5) -> d699dfa | 2026-10-16 | Slurry's Head Butt starts at 0.13 s with a shorter lunge (D-034): Dozer vs Slurry 6-6 (was 3-9), Slurry vs Stoke 7-5 (was 9-3); Fight Camp full-run test on seed 1003; protocol 5 |
| 0.9.4 (preview, playtest build) | [v0.9.4](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.4) -> f908db2 | 2026-10-16 | UI polish pass: the Fight Card and Bookie setup on the shared menu kit, compact reward/rest cards, tidier run summary, readable route map, cleaner Ledger; 3-4 player co-op tests; protocol 5 |
| 0.9.3 (preview, playtest build) | [v0.9.3](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.3) -> fd71dc9 | 2026-10-16 | Tutorial coach box no longer covers the controls bar; Mods and campaign screens fit 1280x800; preset/Deck-resolution checks; full packaged verification of 0.9.2 passed; protocol 5 |
| 0.9.2 (preview, playtest build) | [v0.9.2](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.2) -> a8f0a54 | 2026-10-16 | Top bots beat button-mashing (Headliner 17/24, Hall-of-Famer 20/24); point-blank bursts guardable; dedicated server ~30 % of a core (own frame pacing, one worker thread) with line-flushed logs; packaged-test fixes; protocol 5 |
| 0.9.1 (preview, playtest build) | [v0.9.1](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.1) -> 1f941a3 | 2026-10-15 | Online co-op campaign runs end to end (both campaigns and formats, loopback-tested), smarter top bots; protocol 5 |
| 0.9.0 (preview) | [v0.9.0](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.0) -> 82653e6 | 2026-10-15 | First published build: six fighters, both campaigns + hub, modes, editors, mods, AI Lab, online versus; online co-op runs sync route votes only; balance/bot tuning in progress |
