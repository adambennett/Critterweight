# Modding Critterweight

Mods are **data packages**: JSON content plus optional images, sounds and glTF models. The base
game itself is a package (`game/content/core`) in exactly the same format, so anything the game
ships with can be extended, rebalanced or replaced by a mod — but a mod can never run code.

- Package loader and validator: `game/src/mods/mod_manager.gd` (autoload `Mods`)
- Content registry: `game/src/data/content.gd` (autoload `Content`)
- Schemas: `game/content/schemas/*.schema.json`
- Examples (sources): `mods/examples/*` → packed into `game/mods_examples/*.critmod`
- Packer: `python tools/mods/pack_mod.py <folder> --out <dir>` (or `--examples`)
- Tests: `game/src/test/mods/` (`godot --headless --path game -- --test mods/`): `test_mods.gd`
  (workflow) and `test_mod_hardening.gd` (trust rules: links, overrides, client_only, assets,
  names, archives, imports)

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

Folder and file names are exact and **lowercase on every platform**: `Rules/` or `Tuning.json`
is not loaded anywhere (the Mods screen says so), so a package behaves the same on Windows and
Linux and peers compute the same content hash. `tuning.json` and `elements.json` change core
values, so they need the `replaces_core` capability (see §3).

## 2. manifest.json

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | 3–32 chars `[a-z0-9_]`, unique, never `core` or `user` (the player's own presets/arenas). All entry ids must start with `<id>:` |
| `name` | yes | Display name (≤ 48 chars) |
| `version` | yes | Semantic version `MAJOR.MINOR.PATCH` |
| `game_version` | yes | Oldest game version the mod was made for (see compatibility below) |
| `api` | no | Mod API version (this build: **1**); higher values are rejected |
| `author`, `description` | no | Shown in the Mods screen (always as plain text: BBCode tags are displayed, never applied) |
| `requires` | no | `[{"id": "other_mod", "version": "1.2.0"}]` — hard dependencies (`core` allowed) |
| `load_after` | no | `["other_mod"]` — soft ordering when both are enabled |
| `capabilities` | no | `replaces_core` (overrides core entries or ships `tuning.json`/`elements.json` — needs player consent), `large_assets` (allows up to 256 MB) |
| `client_only` | no | `true` = presentation only: `announcer/` content and asset files. Any other content folder (in any letter case) and `tuning.json`/`elements.json` are rejected |

Ids, versions, `game_version`, `requires` and `load_after` values may not contain spaces, line
breaks or other control characters; patterns such as the version rule are matched against the
whole string.

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
  is enabled; matches and runs using it are marked Modded. The rules (D-027), enforced when the
  content loads, whoever loads it:
  - an override must name an existing **core** entry (it cannot invent new bare ids);
  - without `replaces_core` in the manifest, or without the player's consent, the override is
    not loaded and the Mods screen says why (the core entry stays);
  - a mod can **never** replace another mod's entries (`other_mod:...`) or the player's own
    (`user:...`), with or without `override`. To build on another mod, `requires` it and add your
    own entries (creatures can `extends` its fighters);
  - two enabled mods replacing the same core entry conflict: the first in load order keeps it,
    the second is reported and its override is not loaded;
  - an override that fails validation (e.g. a broken `extends`) leaves the core entry in place.
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
| Fighters & abilities | `creatures/` | Body (segments, chains, weapons, poses), stats, moves by slot (`l1 l2 l3 heavy heavy_charged finisher dash_attack grab pummel taunt`), `abilities` (`ability1 ability2 juice`), `passives` (hooks), `art`, `audio`, `ai` weights, and the Movesets `movepool`, `loadouts` and `default_loadout` (below). Schema: `creature.schema.json`; fighter space is +Z forward, +Y up, +X = the creature's left |
| Balance | `tuning.json`, entries with `override` | `tuning.json` keys merge over core (unknown keys and non-numbers are reported); needs `replaces_core`. Every reload starts from the built-in defaults, so disabling the mod restores them |
| Rules & modes | `rules/`, `modes/`, `playlists/` | Any built-in mode (`standard`, `spotlight_hog`, `chumball`, `absolute_unit`, `chum_rush`, `tag_team`, `practice`) with its options, plus the data hooks below |
| Arenas | `arenas/`, `props/` | Format 2: a base (`gullet drydock crusher rooftop` or a mod base `<mod>:<id>` defined by an entry with `base_def`), size, props from the catalog, mode markers (`spawn`, `goal`, `ball_spawn`, `spotlight_anchor`, `wave_gate`, `unit_spawn`, `boss`, `respawn`); new palette props in `props/`. Format 1 (shape bases, `spawns`) still loads. Schemas: `arena.schema.json`, `prop.schema.json`; reference: `docs/ARENAS_AND_EDITOR.md` |
| Campaign | `supplements/ techniques/ events/ encounters/ meta_upgrades/ boss_fights/ ladder/` | See `docs/CAMPAIGN_SYSTEMS.md` for formats |
| Presentation | `art` blocks, `announcer/`, models/textures/sounds | `client_only` packages may contain only `announcer/` and asset files (checked at install and again at load, whatever the letter case), so they can never change gameplay and never block joining |

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
multiply numeric fighter modifiers (`*_add` keys and `start_hype` add), or set flags.
`fighter_hooks` are installed on every fighter.

Only these `fighter_mods` are accepted, each clamped to its range (`RulesValidator.FIGHTER_MODS`);
anything else is reported by the rules editor and ignored by the simulation, which clamps every
rules value again when it applies it (rules may come from a mod, an imported file or a host):

| Keys | Range |
|---|---|
| `damage defense cooldown poise stamina_regen knockback_taken knockback_dealt stamina_cost dodge_cost` | 0.1–4 |
| `speed move_speed` | 0.1–3 |
| `hype_gain` | 0–5 |
| `heal buildup_taken guard_absorb_mult status_duration_taken charge_steer` | 0–4 |
| `max_health getup_speed held_time_mult vmin_mult hover_duration` | 0.25–4 |
| `dodge_distance throw_distance charge_distance charge_speed zone_size` | 0.25–3 |
| `reach_radius` | 0.5–2 |
| `start_hype` (added, total ≤ 100) | 0–100 |
| `max_health_add` 0–200, `stamina_add` 0–100, `poise_add` 0–100, `parry_window_add` 0–0.3, `dodge_iframes_add` 0–0.3, `wakeup_invuln_add` 0–1, `grab_hold_add` 0–2, `grab_escape_add` 0–10, `splat_damage_add` 0–20, `splat_poise_add` 0–50, `zone_duration_add` 0–10 | added |
| `no_grabs no_juice no_abilities auto_charge all_moves_elemental` | `true`/`false` |

**Scoring and referee** (standard mode, Duel format; v0.9.16): `"scoring": "hp" | "ten_point"`
(default `hp`) and `"referee": true | false` (default `false`). A preset without them is HP scoring
without a referee, so every older preset and save keeps its behaviour; an unknown `scoring` value is
read as `hp`. The validator rejects `ten_point` outside a Duel, without a round timer or with a
score win, and a referee outside a Duel. The simulation applies them only to a two-fighter standard
match (anything else runs plain HP rules). Results then carry `scoring` (method, three judges'
cards and totals, per-round tallies) and/or `referee` (stoppages). The built-in `cage_rules` preset
is `duel` plus both. Details: docs/design/MODES.md, DECISIONS D-044..D-047.

**Combat style** (v0.9.18): `"combat": "moves" | "classic"`. `moves` (the default, and what every
built-in preset says) is Movesets combat: each fighter equips four moves from its pool on the four
attack buttons. `classic` is the 0.9.17 scheme (Light, Heavy, Grab and two ability buttons) as a
real rule: it is saved with the preset, shown before the fight, travels to online clients and is
checked by the validator; any other value is read as `moves`. Custom presets saved by 0.9.17 are
migrated to version 2 with `combat: "moves"` and a `migrated_from` note (import does the same), so
a player who wants the old feel picks Classic in the rules editor or on the versus screen.

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
  distance_below/above in_zone flag`, and under Movesets rules `move` (a pool move id) and
  `move_category`. A `slot` condition written for the old slots also matches the pool moves that
  stand in for it (a `heavy` hook fires for a fighter's `role: heavy` moves).
- Actions: every effect type (`projectile area zone buff debuff heal shield dash leap hover
  charge counter_stance reflect pull push blink prop delayed destroy_projectiles chain_arc
  self_damage cleanse hype juice_state`), hit modifiers in `pre_*` events (`damage_add
  damage_mult knockback_mult launch knockdown stun_add poise_mult guard_crush buildup
  refresh_status`), and `set_flag stamina hype self_damage cleanse`.
- Limits: 32 hooks per fighter, 16 actions per firing, recursion depth 2.
- NPC-kit additions (`docs/kits/minions.md`): events `knocked_out` (on the fighter just KO'd,
  `other` = who did it) and `thrown` (on the thrown fighter, `other` = the thrower, with its landing
  point); condition `"not": {...}`; any effect action may say `"source": "other"` to be fired by the
  event's other fighter (credit, teams and targeting are theirs), centred on the event point;
  `{"type": "self_damage", "lethal": true}` may knock the fighter out (plain `self_damage` leaves 1 HP).
- Shield statuses: a status with `"guard_arc"` (degrees in front, 360 = all round) blocks hits from that
  arc while its fighter is on its feet, without guarding; `"guard_absorb"` (0–1) is its damage absorption.
- Bot behaviour: the creature `ai` block takes kit hints (`range`, `charge_heavy`, `grab_status`,
  `abilities` with `min/max/chance/apart/when`, `pack`, `ally_ko_flinch`, `rest`, `reach`,
  `keep_distance`, `bulky`) — documented in the kit-hint block of `game/src/ai/bot_brain.gd`.

### Movesets: move pools and loadouts (v0.9.18)

Under Movesets rules a fighter fights with four moves chosen from its `movepool` (Classic rules
ignore the pool). Design and the shipped pools: `docs/design/MOVESET_COMBAT.md`. A creature without
a `movepool` still works: the game derives one from its v0.9.17 moves (a basic string from
`l1 l2 l3 finisher dash_attack`, its heavy, and its two abilities), so older fighter mods play
under either rule.

```jsonc
"movepool": {
  "ember_jab": {"name": "Ember Jab", "category": "strike", "role": "basic",
                "string": ["l1", "l2", "l3", "finisher"], "dash": "dash_attack"},
  "furnace_haymaker": {"name": "Furnace Haymaker", "category": "strike", "role": "heavy",
                       "use": "heavy", "charged": "heavy_charged", "hold": "charge"},
  "steam_vent": {"name": "Steam Vent", "category": "blast", "use": "ability1"},
  "flamethrower": {"name": "Flamethrower", "category": "stream", "hold": "sustain",
                   "max_hold": 2.4, "drain": 10, "aim": {"turn_rate": 2.2},
                   "cooldown": 6, "cost": 6,
                   "move": { /* an ordinary move: duration, keys, "sustain": [0.28, 0.5], effects */ },
                   "styles": {"wide_nozzle": {"name": "Wide Nozzle", "desc": "...", "patch": [ /* ContentPatch ops */ ]}},
                   "ai": {"range": [0.8, 3.2], "hold": [0.8, 1.8]}}
},
"loadouts": {"furnace": {"name": "Furnace", "moves": ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"]},
             "brawler": {"name": "Brawler", "moves": ["ember_jab", "furnace_haymaker", "flare_rush", "cinder_shot"]}},
"default_loadout": "furnace"
```

- A pool move is exactly one of `string` (a basic strike string, plus an optional `dash` strike),
  `use` (an existing move or ability by slot, with `charged` for its charged version) or `move` (a
  new move, any MoveDef fields). `use` keeps the animation, hit windows and effects, so upgrades and
  techniques written for that slot keep improving the move.
- `category`: `strike projectile volley stream blast rush control counter support utility` (the
  HUD, commentary, judges and bots read it). `role`: `basic` (no cooldown, cheap), `heavy`,
  `special` (default) or `support`; upgrades and hooks written for the old slots apply by role.
- `hold`: `charge` (hold to charge, release to fire; `charge_scale` on effects scales them by the
  charge) or `sustain` (the move's `sustain: [t0, t1]` window loops while held, up to `max_hold`
  seconds, draining `drain` stamina per second). `aim.turn_rate` (rad/s) lets the stick steer it.
- `cooldown`, `charges`, `cost` (stamina) apply per equipped move. `air: true` lets a move be used
  while hovering without ending the hover (Gusto's Hang Time).
- Effects may repeat inside a move: `"every": 0.12, "until": "release"` (or seconds, or a
  `"count"`). Hits from repeating effects are throttled (30% hype, no stamina refund, at most one
  stun per 0.5 s per target, no hit pause), so a stream cannot stun-lock. New effect type
  `recoil` {`speed`, `up`} pushes the user back; projectiles take `intercept` (they stop enemy
  projectiles) and `on_expire` (a list of effects fired where they land or burst).
- `styles`: two named variants per move; a style is a list of ContentPatch operations on the
  fighter's own definition (`set`, `mul`, `add`, `time_scale`, paths such as
  `abilities.ability1.effects[type=area].cone_deg`). Runs and Career choose one per move.
- `ai`: bot hints for the move (`range` [min, max] metres, `hold` [min, max] seconds, `when`).
- `sfx`: optional sound bank ids, `cast` (when the move starts) and `loop` (held while a sustained
  move pours). Without them a move of its own gets its category's cast sound and a sustained move
  its element's loop; effects keep their usual launch, impact and zone sounds.
- Loadouts list four pool ids, at least one `basic`; the first move goes on the Light button, then
  Heavy, Ability 1 and Ability 2. An invalid or unknown loadout (a stale save, an online request)
  falls back to `default_loadout`. Every hit and effect event carries the pool move id and its
  category (`pool`, `cat`), which hooks can test with the `move` and `move_category` conditions.

Visual effects for new moves are presentation scripts (`game/src/view/fx/moves/<creature>.gd`,
built-in only); a mod's moves show the generic effects for their effect types.

## 5. Assets

Reference assets with paths relative to the package root, e.g. `"art": {"model":
"models/my_fighter.glb"}`. In a mod entry's `art` and `audio` blocks (nested objects and lists
included), `art.model` and every string that looks like a path (it contains `/`, `\` or `:`,
starts with `.` or `~`, or ends in a file extension) must be:

- relative to the package root — no `res://`, `user://`, absolute or drive paths, no `..`;
- a file that is in the package, spelled exactly (names are case-sensitive);
- an asset type: `png jpg jpeg webp glb ogg wav`.

Otherwise the entry is not loaded and the Mods screen names the path. Other strings (colours such
as `"#2B6FD9"`, words such as `"head"` or audio ids such as `"stoke"`) are left alone. To reuse a
core model, `extends` the core creature instead of naming its file. The game only ever loads a
mod file that was validated as part of a loaded package. glTF models
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
  file, 2 000 files, 160-character paths, 8 folder levels (deeper folders are an error).
- **Portable names:** no hidden names (starting with `.`; folder packages simply skip them, like
  the packer), no Windows device names (`con prn aux nul com1-9 lpt1-9`, with any extension), no
  names ending in a dot or space, no `< > " | ? *` or control characters, and no two names that
  differ only in letter case.
- **Links are never followed.** Symbolic links and junctions inside a package folder are skipped
  (the Mods screen lists them), so nothing outside the folder is ever validated, loaded, copied
  into the mods folder or packed by *Export / share*. A package folder that is itself a link is
  not loaded; copy it into the mods folder instead.
- **Archive checks happen before extraction:** sizes come from the zip directory (zip bombs are
  refused unopened); encrypted, multi-part and ZIP64 archives are refused, and so is any archive
  where another zip reader could see something else (data after the end record, anything between
  the directory and the end record, prepended data); every entry path is checked for traversal.
  Extraction goes to a private cache keyed by the archive hash and only happens when the file
  still has that hash and Godot's zip reader lists exactly the checked entries with the checked
  sizes.
- **Only validated files are loaded:** the game reads a package's content from the list of files
  that passed these checks, never by listing folders again.
- **No file-system or network access** exists in the data formats; hooks only act inside a
  match. Asset paths are confined to the package (§5).
- **Servers** load only the packages their configuration names; they never download or run mod
  code. Clients see exactly which mods differ before joining.
- **Consent:** `replaces_core` asks once per mod version (stored in `mods/modsets.json`); the
  content loader refuses core overrides and `tuning.json`/`elements.json` from a package that did
  not declare it or was not allowed (§3, D-027).
- **Newer files stay untouched:** a `modsets.json` written by a newer game version is not
  rewritten (changes to mod sets are then not saved, and the Mods screen says so).

## 7. Installing, sets and sharing (players)

- Mods screen: main menu → Mods. Toggle mods on/off (dependencies are enabled with them and
  dependents are disabled with them), read problems and notes, switch/rename/delete **mod sets**.
- Install: *Import package…* (file browser), drag a `.critmod` onto the window, or put packages
  in the user `downloads` folder and use *Import from Downloads* (controller friendly). A newer
  version upgrades in place and keeps its enabled state; an older one asks before downgrading.
  The new copy is written and checked first; only then is the installed version moved to
  `mods/.removed/`, so a failed import never leaves the mod uninstalled. Importing the installed
  package itself changes nothing.
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
| `asset path … must be a relative path inside the package` / `is not a file in the package` | Use a relative path to a file in the package, spelled exactly, with an asset extension |
| `replaces the core entry 'x', so the manifest must declare the 'replaces_core' capability` | Declare `replaces_core` (players are asked once), or use your own `<id>:` entry |
| `'other_mod:x' belongs to 'other_mod'` | Mods cannot replace other mods' entries: add your own entry and `requires` the other mod |
| `'x' is already replaced by 'other_mod'` | Two enabled mods replace the same core entry: disable one |
| `tuning.json: changes core values` | Declare `replaces_core` |
| `client_only packages may only change presentation` | Remove gameplay folders and `tuning.json`/`elements.json`, or drop `client_only` |
| `'Rules/' is not loaded: content folders are lowercase` | Rename the folder to its lowercase kind name |
| `… is a link (symbolic link or junction) and was skipped` | Copy the real files into the package folder |
| `reserved device name`, `hidden names`, `differ only in letter case` | Rename the file so it works on every OS |
