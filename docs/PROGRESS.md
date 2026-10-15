# Progress

## Current milestone
M1/M2 — engine + pipeline proof: physical combat slice, representative arena, controls, packaging, networking
proof; content specs authored (docs/design).

## Integrated so far (2026-10-14)
- Godot 4.5.1 project (`game/`), Jolt @120 Hz, export templates for Windows/Linux installed (junction to D:).
- Active-ragdoll rig with Jolt 6DOF springs, IK/gait motor, Fighter state machine, contact-validated combat,
  effects system, statuses/elements engine, arena physics, MatchSim + standard rounds mode.
- Views: creature (fallback segment meshes + creature shader with bruises/flash/juice), arena "The Gullet" look,
  VFX, fight camera, HUD; local MatchScene; generic bot brain; Controls autoload.
- Records: AGENTS.md, ARCHITECTURE.md, DECISIONS.md, REQUIREMENTS.md ledger, DESIGN.md.

## Next concrete actions
1. Persistence foundation (Paths/Saves/Settings/Profiles) and Content registry; App router.
2. Body plans + kits for the 6 fighters (engine features: conditionals, statuses, zones, props, hover, carry).
3. Parallel: networking layer, creature forge (glTF), audio synthesis, UI screens/settings.
4. Packaging scripts (Windows/Linux, client/server) and first packaged run.

## Blockers
None. (C: drive has ~4 GB free — large build outputs go to `dist/` but must stay lean; caches on D:.)
