# Platform services and store integration

**Status in this build: local backend only. Steam (or any store) integration is deferred commercial work
and is not claimed anywhere in the game, its menus or its documentation.** The game needs no account, no
login and no network service to run; online play uses direct/LAN connections to player-run hosts and
dedicated servers (`docs/NETWORKING.md`, `docs/SERVER.md`).

All platform calls go through one autoload, `Platform` (`game/src/platform/platform.gd`). No other script
touches a store SDK, so a store backend replaces one file.

## 1. The interface and the local backend

| Area | Call | Local backend (shipped) | Store backend must… |
|---|---|---|---|
| Identity | `user_id()` | Random 128-bit id stored in the active profile (`platform_id`), created on first use; no personal data | return the store account id (e.g. SteamID64 as a string) |
| | `user_display_name()` | Profile name | return the persona name |
| Invites / overlay | `supports_invites()` | `false` | `true` |
| | `invite_text(address, port, has_password)` | Copyable "Join my game: host:port" line for out-of-band sharing | open the friends/invite overlay and map an accepted invite to `Net.join(...)` |
| | `open_overlay(page)` | `false` (no overlay) | open the store overlay page |
| Rich presence | `set_presence(text)`, `presence()` | Stored in memory (shown nowhere) | publish presence ("Fighting in The Gullet — Round 2") |
| Achievements | `unlock_achievement(id)`, `is_unlocked(id)`, `achievement_defs()`, signal `achievement_unlocked` | Stored per profile with a timestamp (`achievements`), toast in the UI; definitions in `content/core/achievements/achievements.json` (14) | mirror unlocks to the store; definitions must match the store's achievement ids |
| Workshop (MOD-07) | `supports_workshop()`, `workshop_publish(mod_id)`, `workshop_list()` | `false`; "publish" exports a shareable `.critmod` to the user `packages` folder; no subscriptions | upload/update items; download subscribed items into the user `downloads` folder and pass each to `Mods.import_package()` so every validation, trust and compatibility rule in `docs/MODDING.md` still applies |
| Cloud saves | `supports_cloud_saves()`, `cloud_save_folders()` | `false`; lists the folders a backend would sync (`profiles`, `presets`, `arenas`, `runs`, `policies`, `mods/modsets.json` — all under the user-data root) | configure Auto-Cloud for exactly those paths; saves are already atomic, versioned and checksummed, so conflicts resolve by "newest valid copy" (`Saves.read_json`) |

Achievement call sites today: first win, house rules (win with a user preset), full card (a win with each of
the six fighters), JUICE KO, Chumball hat trick, Chum Rush wave 20, tutorial complete, watching a full bot
fight (`App._record_match`, `MatchScene`, `TutorialMode`). Campaign, hub and AI Lab achievements
(`ach_off_the_street`, `ach_made_camp`, `ach_fully_dosed`, `ach_order_in_court`, `ach_confidant`,
`ach_mad_scientist`) are unlocked by those systems through the same call.

## 2. Deferred Steam work (not done, not claimed)

What a Steam release would still need, in order:

1. **Steamworks partner setup** (account, app id, store page, payments, tax/legal) — business work, out of scope.
2. **SDK binding**: a Steamworks GDExtension for Godot 4.5 (e.g. the community GodotSteam extension) shipped
   next to the executable on Windows and Linux; `steam_appid.txt` only for development builds.
3. **`SteamPlatform` backend** implementing every row of the table above, selected at startup when the SDK
   initialises (fallback: the local backend, so the game still runs without Steam).
4. **Networking choice**: keep direct/LAN/dedicated play as-is and optionally add Steam lobbies + Steam
   Datagram Relay as an additional transport behind `Net` (the sim and protocol are transport-agnostic).
5. **Workshop**: item visibility rules, moderation/reporting, and the download → `Mods.import_package` path.
6. **Achievements/stats** registered in Steamworks with the ids in `achievements.json`.
7. **Steam Input**: action sets mirroring `Controls.GAME_ACTIONS` (the game already reads raw pads via
   Godot and shows Xbox/PlayStation/keyboard glyphs; Steam Input would add per-device remapping UI).
8. **Steam Deck verification** (Valve-run): see §3 for what is already prepared.
9. **Build/depot scripts** (SteamPipe) using the existing `tools/build/package.ps1` outputs.

## 3. Steam Deck / Linux readiness (what exists now)

- Native Linux x86-64 export (`dist/linux/`), Vulkan Forward+ renderer, no Windows-only APIs.
- Controller-first UI: every screen works with a pad; glyphs switch with the last device; on-screen keyboard
  for text entry; no mouse-only interactions.
- 1280×800 layout checked by the UI tests (no text below 18 px, footer on screen) and a **Deck** graphics
  preset (1280×800, low shadows, AO off, medium effects).
- Suspend/resume: the window focus handler pauses offline matches; saves are atomic.
- Not verified here: real Deck hardware, SteamOS game mode, Proton (not needed for the native build).
  These remain external checks (`docs/VERIFICATION.md`).
