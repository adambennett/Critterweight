# AGENTS.md — working on CRITTERWEIGHT (repo: PokeMMA)

Canonical guidance for humans and coding agents. `CLAUDE.md` just points here.

## What this is
A physical creature cage-fighting game (Godot 4.5.1, typed GDScript, Jolt physics). The brief is
`Initial_Prompt_v2.md` (authoritative). Records: `docs/REQUIREMENTS.md` (ledger), `docs/DESIGN.md`,
`docs/ARCHITECTURE.md` (module contracts), `docs/DECISIONS.md`, `docs/PROGRESS.md` (status + next
actions), `docs/VERIFICATION.md`. Creative specs: `docs/design/*.md`.

## Commands (run from repo root; Windows PowerShell)
```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game --import                 # (re)import assets + refresh class cache (after adding class_name scripts or assets)
& $g --headless --path game -- --check               # every script compiles
& $g --headless --path game -- --test [filter]       # automated tests (exit code = failures)
& $g --headless --path game --fixed-fps 120 -- --probe jab   # combat probes (stand|walk|jab|string|heavy|guard|grab|ability|spar)
& $g --path game -- --sandbox [--autoplay]           # dev sandbox match (windowed)
powershell -File tools/build/package.ps1             # export Windows + Linux game/server packages into dist/
```
Add `--capture <png> --capture-at <s>` to any windowed run to save a real rendered frame.

## Architecture boundaries (details: docs/ARCHITECTURE.md)
- `game/src/sim/` — authoritative simulation (MatchSim, Fighter, Rig, combat, effects, modes). No rendering,
  no input devices, no UI, no files except content parsing. Runs headless (server, AI Lab).
- `game/src/view/` — visuals that READ sim state/events; never change gameplay outcomes.
- `game/src/net/` — transport/protocol; clients never decide damage, rewards or progression.
- `game/src/ai/` (bots), `game/src/lab/` (training), `game/src/campaign/`, `game/src/hub/`,
  `game/src/editor/`, `game/src/mods/`, `game/src/persist/`, `game/src/platform/`, `game/src/ui/`.
- Content is data: `game/content/<package>/` JSON validated against `game/content/schemas/`.
  The base game is the `core` package; mods use the same format.

## Style
- Typed GDScript everywhere (`var x: int`, typed arrays). No `:=` on Variant expressions (warnings are errors).
- `class_name` for shared types; after adding one run the `--import` command above.
- Fighter space convention: +Z forward, +Y up, +X = creature's LEFT. Units: metres, kg, seconds.
- Keep files cohesive; document invariants at the top of each file; no hidden global state beyond autoloads.

## Verification rules
- Tie checks to requirement IDs in `docs/REQUIREMENTS.md`; update its state columns honestly
  (implemented / built / auto-tested / Windows-runtime verified / externally unverified).
- Never weaken an acceptance criterion or delete a meaningful test to pass. Loopback network tests are labeled loopback.
- Before committing: `--check` and relevant `--test` filters pass. Commit messages end with the Co-Authored-By line.
