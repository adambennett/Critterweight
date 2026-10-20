# Architecture and module contracts

One integration owner (lead) owns this file. Subsystem owners must keep their module inside its
folder and talk to others only through the contracts below.

## Layers
```
content (JSON packages: core + mods) ──► Content registry ──► sim / campaign / ui
sim (authoritative, headless) ──► events + state ──► view (visuals/audio/HUD) │ net (snapshots) │ lab (training)
input sources (player / bot / net / policy / script) ──► FighterInput ──► sim
persist (atomic versioned JSON) ◄── settings, profiles, runs, presets, arenas, policies, mods
```

## Autoloads (game/project.godot, in load order)
| Name | File | Contract |
|---|---|---|
| `Log` | src/core/log.gd | `Log.i/w/e/d(tag, msg)`; `Log.open(channel, dir)` bounded rotating files |
| `Paths` | src/persist/paths.gd | user-data root and subfolders (profiles, mods, arenas, presets, policies, playlists, runs, careers, logs, lab, captures); `--user-root <dir>` override for tests; never writes into the install folder |
| `Saves` | src/persist/saves.gd | `write_json(path, kind, version, data) -> Error` (temp + flush + rename + .bak), `read_json(path, kind, migrator) -> SaveResult` (validates checksum, recovers from .bak/.tmp, never silently overwrites a recoverable file) |
| `Settings` | src/persist/settings.gd | schema of every option (default/range/apply/restart flag); `get_value(key)`, `set_value(key, v)`, `reset(category)`, `changed(key)` signal; applies display/audio/input/accessibility |
| `Profiles` | src/persist/profiles.gd | active profile: stats, records, unlocks, ladder (The Dosage), Fight Camp meta-progression, cosmetics |
| `Content` | src/data/content.gd | loads packages (core + enabled mods) in deterministic order; typed getters `creature(id)`, `arena(id)`, `rules_preset(id)`, `mode(id)`, `upgrade(id)`, `event(id)`, `encounter(id)`, `playlist(id)`; `errors`; `content_hash()` for multiplayer compatibility |
| `Mods` | src/mods/mod_manager.gd | discovery, manifests, dependency/order resolution, enable/disable, mod sets, package import/export (zip), trust/capability prompts |
| `Controls` | src/input/controls.gd | input actions, rebinding, device tracking, prompts, `fill(FighterInput, cam_basis)` |
| `Audio` | src/audio/audio.gd | buses (Master/Music/SFX/Voice/UI/Ambience), `sfx(id, pos?, vol_db, pitch)`, `music(track, fade)`, `announce(line_id)`, subtitles signal |
| `Net` | src/net/net.gd | sessions: `host(cfg)`, `join(addr, port, pwd)`, `start_dedicated(cfg)`, `leave()`; lobby state + signals; LAN discovery |
| `Platform` | src/platform/platform.gd | service boundary (identity, invites, workshop, achievements) — `LocalPlatform` implementation now, Steam later |
| `App` | src/app/app.gd | screen router (`goto(screen, params)`, `push_overlay`, `back()`), match launching, CLI modes, quit |

## Simulation contract (src/sim)
- `MatchSim.setup({arena, rules, seed, mode, fighters:[{creature, team, source, name, kind, mods}]})`; `step(dt)` at 120 Hz.
- Inputs only through `FighterInput` (world-space move vector, held bitmask, per-button press counters).
- Outputs: `fighters[i]` state (vitals, `state`, `rig.segment_transforms()`), `effects.entities`, `events` (append-only with `seq`).
- Determinism: same build + same seed + same input stream ⇒ identical outcome **in a fresh process stepped at a
  fixed rate** (`--fixed-fps 120`; test `test_fixed_step_runs_are_reproducible_across_processes`). Several sims
  created one after another inside a single real-time-paced process can diverge slightly (Godot/Jolt body
  bookkeeping), so tests that need exact reproducibility use child processes. Cross-machine float determinism is
  NOT assumed; networking is server-authoritative.
- Content types consumed: `CreatureDef` (body + moves + abilities), `ArenaDef`, rules dictionaries, `MatchMode` subclasses.

## Content packages (game/content/<id>/ or user mods/<id>/)
```
manifest.json            {id, name, version, game_version, requires:[{id,version}], load_after:[], capabilities:[], content:{...}}
creatures/*.json          CreatureDef (body inline or by id)
arenas/*.json             ArenaDef
rules/*.json              rules presets
modes/*.json              data-defined modes (built on ModeController hooks + trigger DSL)
upgrades/*.json           supplements, techniques, meta upgrades
campaign/*.json           encounters, events, bosses, acts, ladder
playlists/*.json, announcer/*.json, hub/*.json, tuning.json, elements.json
models/*.glb, audio/*.wav|ogg, textures/*.png   (presentation, client-only)
```
Ids: core uses bare ids (`f_stoke`); mods must prefix `<modid>:` unless explicitly overriding a core id (`"override": true`).
Gameplay-affecting content contributes to `Content.content_hash()`; presentation-only files do not.

## Scene flow
`App` owns a screen stack of `Screen` controls (src/ui/screens). Matches run in `MatchScene` (local authority)
or `NetMatchScene` (client view of a remote server). The hub is `HubScene`. Every screen must be fully operable
by controller (focus neighbours, ui_accept/ui_cancel) and mouse/keyboard.

## Processes
- Game client: `CritterWeight.exe` (Windows) / `CritterWeight.x86_64` (Linux).
- Dedicated server: same engine binary with the server pack, `--server --config server.cfg` (headless).
- AI Lab workers: the game binary spawned headless with `--lab-worker <job.json>`; communicate through job files.
