# Modding Critterweight

Mods are **data packages**: JSON content plus optional images, sounds and glTF models. The base
game itself is a package (`game/content/core`) in exactly the same format, so anything the game
ships with can be extended, rebalanced or replaced by a mod — but a mod can never run code.

- Package loader and validator: `game/src/mods/mod_manager.gd` (autoload `Mods`)
- Content registry: `game/src/data/content.gd` (autoload `Content`)
- Schemas: `game/content/schemas/*.schema.json`
- Examples (sources): `mods/examples/*` → packed into `game/mods_examples/*.critmod`
- Packer: `python tools/mods/pack_mod.py <folder> --out <dir>` (or `--examples`)
- Tests: `game/src/test/mods/test_mods.gd` (`godot --headless --path game -- --test test_mods`)

## 1. Package layout

```
my_mod/
  manifest.json          required
  creatures/*.json       fighters (playable or npc_only)
  minions/*.json         campaign minions        bosses/*.json  boss bodies
  rules/*.json           match rule presets      modes/*.json   mode data
  arenas/*.json          arena layouts           props/*.json   prop data
  supplements/*.json     campaign supplements    techniques/*.json
  meta_upgrades/*.json   events/*.json  encounters/*.json  boss_fights/*.json  ladder/*.json
  playlists/*.json       server playlists        announcer/*.json  presentation only
  tuning.json            global tuning overrides elements.json  element overrides
  models/*.glb  textures/*.png  sounds/*.ogg      assets referenced by relative paths
```

Each JSON file in a kind folder holds one entry (`{"id": ...}`) or many (`{"items": [ ... ]}`).
Files load in sorted order. Distribute a package as a folder or as a zip renamed to
`<id>-<version>.critmod` (`pack_mod.py` produces deterministic archives; a single top-level
folder inside the zip is fine).

## 2. manifest.json

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | 3–32 chars `[a-z0-9_]`, unique, never `core`. All entry ids must start with `<id>:` |
| `name` | yes | Display name (≤ 48 chars) |
| `version` | yes | Semantic version `MAJOR.MINOR.PATCH` |
| `game_version` | yes | Oldest game version the mod was made for (see compatibility below) |
| `api` | no | Mod API version (this build: **1**); higher values are rejected |
| `author`, `description` | no | Shown in the Mods screen |
| `requires` | no | `[{"id": "other_mod", "version": "1.2.0"}]` — hard dependencies (`core` allowed) |
| `load_after` | no | `["other_mod"]` — soft ordering when both are enabled |
| `capabilities` | no | `replaces_core` (overrides core entries — needs player consent), `large_assets` (allows up to 256 MB) |
| `client_only` | no | `true` = presentation only (announcer lines, cosmetic art); may not contain gameplay kinds |

**Version rules.** `"1.2.0"`, `">=1.2.0"`, `"^1.2.0"` mean *at least 1.2.0 with the same major*
(for `0.x`, the same minor); `"=1.2.0"` means exactly; `"*"` means any. `game_version` uses the
same rule against the running game (`Saves.game_version()`).

**Load order** is deterministic: dependencies and `load_after` first, ties broken by id. A mod
whose dependency is missing, disabled, the wrong version, or part of a cycle is not loaded and
the Mods screen says exactly why.

## 3. Ids, overrides and inheritance

- Mod entries use namespaced ids: `my_mod:spicy_duel`. Entries without the prefix are rejected
  with an actionable message.
- To **replace** a core entry deliberately, reuse its bare id, add `"override": true`, and
  declare the `replaces_core` capability. The player is asked once per mod version before it
  is enabled; matches and runs using it are marked Modded.
- Creature entries (`creatures`, `minions`, `bosses`) can **extend** another creature and only
  write what changes:

```json
{
  "id": "stoke_variants:overheated_stoke",
  "extends": "f_stoke",
  "title": "Overheated",
  "stats": {"power": 1.08},
  "moves": {"heavy": {"damage": 15}, "taunt": null},
  "art": {"palette": {"primary": "#2B6FD9"}}
}
```

  Objects merge recursively, arrays and scalars replace, and `null` deletes a key (the `taunt`
  slot above). Chains up to 4 deep are allowed; cycles and unknown parents are reported. The
  merged result is validated against `creature.schema.json`.

## 4. Extension points

| What | Where | Notes |
|---|---|---|
| Fighters & abilities | `creatures/` | Body (segments, chains, weapons, poses), stats, moves by slot (`l1 l2 l3 heavy heavy_charged finisher dash_attack grab pummel taunt`), `abilities` (`ability1 ability2 juice`), `passives` (hooks), `art`, `audio`, `ai` weights. Schema: `creature.schema.json`; fighter space is +Z forward, +Y up, +X = the creature's left |
| Balance | `tuning.json`, entries with `override` | `tuning.json` keys merge over core (unknown keys are reported) |
| Rules & modes | `rules/`, `modes/`, `playlists/` | Any built-in mode (`standard`, `spotlight_hog`, `chumball`, `absolute_unit`, `chum_rush`, `tag_team`, `practice`) with its options, plus the data hooks below |
| Arenas | `arenas/` | Base shape, size, walls/ring-out, props, hazards, spawns, mode markers (`goal`, `ball_spawn`, `spotlight`, `wave_gate`). Schema: `arena.schema.json` |
| Campaign | `supplements/ techniques/ events/ encounters/ meta_upgrades/ boss_fights/ ladder/` | See `docs/CAMPAIGN_SYSTEMS.md` for formats |
| Presentation | `art` blocks, `announcer/`, models/textures/sounds | `client_only` packages may contain only these |

**Rule-level data hooks** (usable by any rules preset, including custom rules made in the
in-game editor):

```json
{
  "gravity_mult": 0.45,
  "fighter_mods": {"damage": 1.2, "knockback_taken": 1.1, "no_grabs": true},
  "fighter_hooks": [
    {"on": "wall_splat", "do": [{"type": "heal", "amount": 4}], "cooldown": 1.0}
  ]
}
```

`gravity_mult` (0.3–2.0) scales world gravity and every body's muscle support. `fighter_mods`
multiply numeric fighter modifiers (or set flags). `fighter_hooks` are installed on every fighter.

**Hooks** are the one behaviour language shared by kits, statuses, techniques, supplements,
modes and mods (`game/src/sim/hooks.gd`):

```json
{"on": "hit_dealt", "if": {"move_class": "heavy", "target_status": "soaked"},
 "do": [{"type": "buildup", "element": "static", "amount": 30, "target": "other"}],
 "chance": 1.0, "cooldown": 0.5, "max_uses": 0}
```

- Events: `pre_hit_dealt pre_hit_taken hit_dealt hit_taken blocked parried parry_success
  knockdown_dealt knocked_down ko_dealt dodge taunt ability_used juice_start juice_end
  move_start land grab_start throw wall_splat status_applied status_received reaction
  round_start tick` (with `"every": seconds`).
- Conditions: `slot(s) move_class charged target_status self_status target_element
  self_health_below/above target_health_below target_guarding target_down self_juiced
  distance_below/above in_zone flag`.
- Actions: every effect type (`projectile area zone buff debuff heal shield dash leap hover
  charge counter_stance reflect pull push blink prop delayed destroy_projectiles chain_arc
  self_damage cleanse hype juice_state`), hit modifiers in `pre_*` events (`damage_add
  damage_mult knockback_mult launch knockdown stun_add poise_mult guard_crush buildup
  refresh_status`), and `set_flag stamina hype self_damage cleanse`.
- Limits: 32 hooks per fighter, 16 actions per firing, recursion depth 2.

## 5. Assets

Reference assets with paths relative to the package root, e.g. `"art": {"model":
"models/my_fighter.glb"}`. Paths may not be absolute or contain `..`/drive letters. glTF models
are loaded at runtime with Godot's `GLTFDocument` (meshes, skins, materials, textures only).
Bones named after body segment ids drive the mesh (see `docs/design/ART_DIRECTION.md` and the
forge pipeline in `tools/forge` for a complete, reproducible example).

## 6. Trust model and limits

- **Data only.** Packages containing scripts, binaries, scenes, engine resources, shaders or
  resource packs (`.gd .cs .dll .so .exe .pck .tscn .tres .gdshader .py .js …`) are rejected;
  a manifest that declares `scripts` is rejected. Archives are never mounted into the game's
  file system, so a mod can't replace engine files.
- **Allowed files:** `json txt md png jpg jpeg webp ogg wav glb`.
- **Limits:** 64 MB per package (256 MB with `large_assets`), 32 MB per file, 4 MB per JSON
  file, 2 000 files, 160-character paths, 8 folder levels.
- **Archive checks happen before extraction:** sizes come from the zip directory (zip bombs are
  refused unopened); encrypted, multi-part and ZIP64 archives are refused; every entry path is
  checked for traversal; extraction goes to a private cache keyed by the archive hash.
- **No file-system or network access** exists in the data formats; hooks only act inside a
  match. Asset paths are confined to the package.
- **Servers** load only the packages their configuration names; they never download or run mod
  code. Clients see exactly which mods differ before joining.
- **Consent:** `replaces_core` asks once per mod version (stored in `mods/modsets.json`).

## 7. Installing, sets and sharing (players)

- Mods screen: main menu → Mods. Toggle mods on/off (dependencies are enabled with them and
  dependents are disabled with them), read problems and notes, switch/rename/delete **mod sets**.
- Install: *Import package…* (file browser), drag a `.critmod` onto the window, or put packages
  in the user `downloads` folder and use *Import from Downloads* (controller friendly). A newer
  version upgrades in place and keeps its enabled state; an older one asks before downgrading.
- Share: *Export / share* writes `<id>-<version>.critmod` into the user `packages` folder.
- Uninstall moves the package to `mods/.removed/` (nothing is deleted). Sets that used it list it
  as **MISSING** until it is reinstalled or turned off.
- Safe start: launch with `-- --safe-mode` (or `--no-mods`) to start with core content only;
  `-- --mods id1,id2` starts with exactly those mods (also used by dedicated servers).
- User folders (Windows: `%APPDATA%\Critterweight`, Linux: `~/.local/share/Critterweight`):
  `mods/` (installed packages, `modsets.json`, `.cache/`, `.removed/`), `downloads/`, `packages/`.

## 8. Multiplayer and saves

- Every package has a hash (archive SHA-256, or a hash over a folder's files). `Mods.compare()`
  checks the host's gameplay package list against yours and names each **missing**, **extra**
  or **different version** mod. `client_only` packages never block joining.
- The gameplay content hash (`Content.content_hash()`) covers every gameplay kind from every
  loaded package; presentation kinds are excluded.
- Saves that depend on content (suspended runs, rule presets, arenas, AI policies) record
  `Mods.fingerprint()`. On load, `Mods.check_requirements()` explains what is missing without
  changing or deleting anything; re-enable or reinstall the mod to continue.

## 9. Workshop (deferred)

Steam Workshop publishing/subscription is deferred commercial work. The service boundary is
`Platform` (`supports_workshop()`, `workshop_publish(id)`, `workshop_list()`); the local
implementation exports a shareable package instead. A Workshop adapter would download items
into the user `downloads` folder and hand them to `Mods.import_package()`, so every check above
still applies. See `docs/PLATFORM.md`.

## 10. Bundled examples

| Package | Demonstrates |
|---|---|
| `stoke_variants` | Fighter customization via `extends`: palette, stats, a stronger heavy and a new passive hook |
| `moon_rules` | Rules/mode mod: low-gravity FFA with lives and a splat hook, a Juice Frenzy duel preset, and a playlist |
| `rust_bucket` | Arena mod: square pit with props, a hazard, spawns and markers for Chumball/Spotlight Hog |

Edit a source folder under `mods/examples/`, run `python tools/mods/pack_mod.py --examples`, and
the game picks up the new archive. Bundled examples can be disabled but not uninstalled; an
installed package with the same id takes precedence.

## 11. Troubleshooting

| Message | Fix |
|---|---|
| `mod ids must start with '<id>:'` | Prefix every entry id, or use `override` + `replaces_core` |
| `requires 'x' 1.2.0, which is not installed` | Install/enable the dependency or lower the requirement |
| `dependency cycle` | Remove a `requires`/`load_after` edge |
| `made for game version …` | Update `game_version` after testing on this build |
| `'file.ext' is code or an engine resource` | Remove it — mods are data-only |
| `extends unknown creature 'x'` | Check the parent id (and that its mod loads first) |
| `asset path … must stay inside the package` | Use a relative path inside the package |
