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
powershell -ExecutionPolicy Bypass -File tools/build/release.ps1 -Version 0.9.1 -Bump -Prerelease -NotesFile notes.md
```

`release.ps1` sets the version (with `-Bump`) and commits it, checks the tree is clean and on `main`,
creates the annotated tag, builds all four packages (`package.ps1 -Archive`), smoke-tests the packaged
game (script check + boot to the title screen), writes `SHA256SUMS.txt`, pushes the tag and creates the
GitHub release with the assets (`gh`). `-DryRun` does everything except pushing and publishing.

## Release log

| Version | Tag | Date | Notes |
|---|---|---|---|
| 0.9.0 (preview) | [v0.9.0](https://github.com/adambennett/PokeMMA/releases/tag/v0.9.0) -> 82653e6 | 2026-10-15 | First published build: six fighters, both campaigns + hub, modes, editors, mods, AI Lab, online versus; online co-op runs sync route votes only; balance/bot tuning in progress |
