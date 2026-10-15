# Requirement & evidence ledger

Source of truth for scope: `Initial_Prompt_v2.md` (section numbers in brackets). Acceptance criteria are not
lowered to match unfinished work.

**State legend** (cumulative letters, never a bare check mark):
`I` implemented in source · `B` built into the packaged game/server · `T` covered by automated tests ·
`W` verified at runtime on Windows (packaged build unless noted) · `X` externally unverified (permitted gap,
see notes) · `—` not started · `~` partial (details in Evidence).

## Delivery & platform [2, 5, 19]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| DEL-01 | Packaged self-contained Windows x64 game launches with a fresh profile, no dev tools or login | — | |
| DEL-02 | Source, assets (+ editable sources), build tools, tests, docs in repo | ~ | repo layout; AGENTS.md |
| DEL-03 | Linux x86_64 game export + practical Steam Deck path (controller-first, 1280x800 preset, packaging notes); device/runtime checks may be X | ~ | Linux x86_64 game export built; tools/verify/portability_check.py: ELF64 x86-64, embedded data, glibc <= 2.28 libs only, case-exact res:// paths, no Windows-only code, tar.gz exec bits; runtime on Linux/Deck = X (no local Linux userland) |
| DEL-04 | Separate headless dedicated server: Windows package; Linux server build | ~ | Windows/Linux dedicated-server exports build (package.ps1); server features pending networking merge |
| DEL-05 | Reproducible build/package scripts | ~ | tools/build/package.ps1 (+make_tar.py): import, check, tests, 4 exports, manifest with sha256, archives |
| DEL-06 | Top-level README (launch/build/test), final verification report with artifact paths/versions/results | — | |
| DEL-07 | Git connected to github.com/adambennett/PokeMMA, reviewed incremental commits & pushes, no force push; push limits reported | ~ | local commits; remote reachable (empty private repo) |
| DEL-08 | Platform services (identity/invites/workshop/achievements) behind interfaces with local implementations; Steam work documented as deferred, not claimed | I | src/platform/platform.gd local backend (identity, invites text, presence, achievements, workshop export, cloud folder list); docs/PLATFORM.md (Steam deferred, not claimed) |
| DEL-09 | Early documented targets: OS versions/arches, min/recommended HW, presets, max fighters, server capacity, perf budgets | ~ | docs/DESIGN.md §Targets |
| DEL-10 | macOS/Android/iOS feasibility notes only; no unbacked claims | ~ | D-001 |

## Performance [5, 17]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| PERF-01 | Stable 60 fps combat at 1080p on the documented PC baseline (measured here: i7-7700K + RTX 4070 Ti SUPER); frame-time distribution recorded for busy scenes | — | |
| PERF-02 | Deck-class preset for 1280x800 @ 60 fps; layout/readability checked at 1280x800; real Deck test = X | — | |
| PERF-03 | Loading time and memory use measured | ~ | --boot-report: 7.7 s to title in the editor binary on a loaded machine; bench reports match load (~0.25 s) and memory; packaged quiet-machine numbers pending |
| PERF-04 | Server simulation cost measured (8-fighter busy scene, playlist soak) | — | |
| PERF-05 | Quality presets scale expensive effects while keeping combat readable; benchmarks run at stated settings | — | |

## Combat & controls [6]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| CMB-01 | Documented hybrid active-ragdoll model; bodies react to strikes, block, stumble, recover | ~ | D-003; src/sim/rig.gd, fighter.gd; probes stand/jab/guard |
| CMB-02 | Attacks depend on actual contact & positioning (server contact validation with closing speed) | ~ | src/sim/combat.gd; probe jab/string |
| CMB-03 | Projectiles, area effects, zones, movement tools, other unusual mechanics | I T | src/sim/effects.gd (projectiles fixed to fire forward, floor-relative offsets), zones/areas/pulls; tests core/test_elements, test_tutorial ability exercise |
| CMB-04 | Basic play = left stick + Light/Heavy (+Guard); depth through timing, spacing, defence, combos, resources, abilities | ~ | Controls defaults; Fighter state machine |
| CMB-05 | Camera, movement frame, targeting assistance, core actions, guard/parry/dodge, input buffer, cancels, stamina/poise/hype, knockdowns, ring boundaries, win conditions, recovery: specified in DESIGN.md and implemented | ~ | |
| CMB-06 | Simple grab/throw/pummel/escape layer (no Cage Rules ground game) | ~ | Fighter grab states |
| CMB-07 | No unavoidable infinites or permanent stun locks (combo scaling, stun budget burst, wake-up invulnerability, OTG cap) — tested | ~ | Tuning keys combo_*/stun_budget |
| CMB-08 | Readable windups, impact feedback, recovery cues, predictable control | — | |
| CMB-09 | Different body shapes without unreadable reach advantages/broken collisions (reach cap 1.6 m, tests) | — | |
| CMB-10 | Cosmetic physics separate from authority | I | Cosmetic layer is view-only: CreatureView bruises/flash/detached gore piece on the debris layer, Vfx, KO stars; sim never reads them |
| CMB-11 | Repeatable combat scenarios + debug visualizations | I T | Probes (--probe stand|walk|jab|string|heavy|guard|grab|ability|spar), tutorial/kit scenario tests, CombatDebugDraw overlay (F3/--debug-draw: hit capsules, weapon phases, reach circle, targets, hit labels) |
| CMB-12 | Controller-first: an Xbox-style pad operates every workflow; mouse+keyboard fully supported | I T | Controls + UiNav (stick nav, focus guard, hot-plug); UI tests drive every flow with injected pad/key/mouse events (test/ui) |

## Roster, elements & content targets [7]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| CNT-01 | 6 finished original fighters (moves, physics, animation, effects, audio, UI, AI use, multiplayer) | ~ | Bodies, forged models and art for all six (docs/CREATURES.md, docs/evidence/art); full kits being authored (docs/kits/) |
| CNT-02 | Identity, silhouette, element relations, strengths/weaknesses, signatures, counterplay, ≥3 build directions each | ~ | ROSTER.md (design) |
| CNT-03 | 6 original elements with statuses, 11 reactions, zones, resist/weak; icons+text+colour | ~ | ELEMENTS.md; Elements/StatusSet engine |
| CNT-04 | Committed numeric content targets (DESIGN.md §Content targets) all met | — | |
| CNT-05 | Polished primary cage + useful arena customization & saved layouts | ~ | ArenaView (The Gullet look in progress) |
| CNT-06 | 4 difficulty presets + The Dosage ladder (10 levels, distinct modifiers, progressive unlock) | — | |
| CNT-07 | Visibly different seeded runs (events/upgrades/enemies) | — | |
| CNT-08 | 3 bosses with 2 phases | — | |

## Campaigns & co-op [8]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| CMP-01 | Off the Street (fresh-run): no permanent power; only stats/cosmetics/records/ladder persist; unlocks keep parity | — | |
| CMP-02 | Clearing the highest unlocked Dose unlocks the next, max Dose 10 | — | |
| CMP-03 | Fight Camp (persistent): permanent upgrades; between runs the player explores the 3D hub | — | |
| CMP-04 | Hub: ≥5 connected spaces, characters, activities, secrets, upgrade stations, real movement | — | |
| CMP-05 | Both: branching routes, risk/reward, synergies, random events, bosses, rewards, victory/defeat/replay | — | |
| CMP-06 | Pacing/run length defined; seeded reproducible generation; no impossible routes/invalid rewards/softlocks (tested) | — | |
| CMP-07 | How custom runs affect progression/records defined and shown | — | |
| COOP-01 | Online co-op in both campaigns, ≥2 humans (limit 4) | — | |
| COOP-02 | Tag-team and simultaneous allied combat; simultaneous default (reasoned); tag via settings; 1v1 stays the solo norm | — | |
| COOP-03 | Run ownership, route voting, per-player choices, reward distribution w/o duplication, progression compatibility | — | |
| COOP-04 | Downed/defeated players, tag-out participation, pause rules | — | |
| COOP-05 | Disconnect/rejoin, host departure recovery, save/resume party, continue with absent player | — | |
| COOP-06 | Permanent campaign power kept out of PvP; active custom rules visible | — | |

## Match types, rules editor, arena editor [9]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| MCH-01 | Practice vs NPCs | I T | PracticeMode (dummy behaviours, telemetry), Tutorial freestyle; tests core/test_modes_extra |
| MCH-02 | 1v1 PvP (online; local two-pad as bonus) | — | |
| MCH-03 | ≥4 simultaneous fighters for FFA/teams/custom; documented maximum (8) | I T | MatchSim up to 24 fighters (8 players + spawned minions); FFA/teams presets; HUD 4-column card grid for 5-8 |
| MCH-04 | ≥3 genuinely different bonus modes (4 designed) with NPCs and documented player/team counts | I T | Spotlight Hog, Chumball, Absolute Unit, Chum Rush, Tag Team (src/sim/modes); tests core/test_modes, test_modes_extra, test_containment; captures/mode2_*.png |
| MCH-05 | Rules editor: format, teams, rounds, timers, score/win, health/resources, damage/knockback, respawn/revive, ability limits, hazards, bots, mode options; validation + explanations | I T | RulesValidator (every rule: range, help, per-mode options, validation with explanations) + rules_editor screen; tests core/test_rules_presets |
| MCH-06 | Presets: save/duplicate/rename/import/export/share, versioned; usable locally, hosted, in dedicated playlists, with compatible mods | ~ | RulePresets: save/version/duplicate/rename/delete/export/import, registered in Content (local + host lists); hosted/playlist use pending net merge |
| ARN-01 | Arena editor: choose base; place/adjust props, obstacles, hazards, spawns, boundaries within limits | — | |
| ARN-02 | Select, move/rotate, delete, undo/redo, save/load, validate, test-play | — | |
| ARN-03 | Mouse/keyboard and controller operation | — | |
| ARN-04 | Validation: spawn safety, bounds, budget, required mode markers | — | |
| ARN-05 | Authored arenas playable in normal matches; export/import as content packages usable by compatible peers; examples shipped | — | |

## Multiplayer, servers, playlists [10]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| NET-01 | Real online PvP and co-op; in-game listen-server hosting | — | |
| NET-02 | Headless dedicated server; docs for install/config/direct+LAN connect/ports/logs/admin/shutdown-restart | — | |
| NET-03 | Documented model: authority, fixed steps, randomness ownership, interpolation, serialization, bandwidth, tick rates, version compatibility | ~ | D-014 |
| NET-04 | Clients cannot dictate damage, rewards or progression | — | |
| NET-05 | Hosted + dedicated matches proven with independent client processes; combat, co-op decisions, saves, custom rules, authored arenas, mods verified through the real network path | — | |
| NET-06 | Timeouts, disconnect/reconnect, invalid data, incompatible builds/content, server shutdown: defined, tested, clear UI errors | — | |
| NET-07 | Direct address + LAN play; UI/config for a remote user-hosted server; NAT/port-forward limits documented; loopback evidence labeled | — | |
| NET-08 | Weighted playlists (mode/arena/rules), voting, bots, tie/no-vote, repeat avoidance, empty server, min players, invalid/missing content, restart persistence, examples, validation errors, automatic round advance | — | |
| NET-09 | Server stability, bounded logs/resources, safe defaults, local/authenticated admin only, inbound validation & limits | — | |
| NET-10 | Latency/jitter/loss profiles tested | — | |

## NPCs, spectating, AI Lab [11]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| AI-01 | Distinct bot difficulties (forgiving → demanding), reaction/mistakes/strategy/ability use, no omniscience, every creature & mode tested | ~ | src/ai/bot_brain.gd (perception delay) |
| AI-02 | AI-vs-AI spectating with camera/HUD controls | I T | SpectatorDirector auto-director, viewer focus lock, free camera, hide HUD, 0.25x-2x speed; tests core/test_spectator; --spectate |
| AI-03 | Bookie's Table autobattler: player picks fighter/route/upgrades/build, AI fights, shared campaign systems | — | |
| AI-04 | Unattended mode with auto decisions, pause, speed/camera, take-over; extended unattended run tested | — | |
| LAB-01 | Actual local learning (parameters change from experience) | — | |
| LAB-02 | ≥2 distinct training approaches (evolution strategies RL + behaviour cloning) documented | — | |
| LAB-03 | Lab UI: fighter, approach, objectives/styles, opponents/scenarios, seed, resource/time limits | — | |
| LAB-04 | Real combat rules, headless accelerated simulation, same observation/action contract in training and matches | ~ | headless multi-world probe (D-002) |
| LAB-05 | CPU defaults, modest workloads, optional GPU documented, no paid services | — | |
| LAB-06 | Progress/episodes/time/resources/metrics; pause/resume, checkpoints, cancel, failure recovery; game stays responsive | — | |
| LAB-07 | Save/version/name/export/import/load policies; compatibility validation; never executes code | — | |
| LAB-08 | Evaluation vs fixed baselines and held-out seeds, separate from training; honest reports | — | |
| LAB-09 | Saved bots can be fought/spectated; hosts can use compatible policies; inference budget measured | — | |
| LAB-10 | Docs, reproducible small examples, sample policies; controlled learnable task with recorded improvement | — | |

## Art, animation, graphics, audio, tone [12]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| ART-01 | Art direction guide | ~ | docs/design/ART_DIRECTION.md (in progress) |
| ART-02 | Cohesive cartoony 3D style, original creatures; representative fighter & arena early | I | Forged original creatures (docs/evidence/art), The Gullet arena; tools/forge |
| ART-03 | glTF import path validated; PBR, soft shadows, SSAO, HDR tonemapping; scalable quality | I | glTF pipeline (forge -> .glb -> Godot import; runtime GLTFDocument for mods), PBR hints, AgX, SSAO, soft shadows, quality presets |
| ART-04 | Readable locomotion, attacks, abilities, hit reactions, blocking, knockdowns/recovery, win/loss per anatomy | — | |
| ART-05 | Effects communicate range/timing/contact/elements/outcomes; legible busy scenes | ~ | Vfx |
| ART-06 | Localized injury feedback + modest cosmetic gore (default on) with reduced/off and non-gory equivalents | I | Bruises + flash (creature.gdshader), detachable gore piece on KO (Full), Reduced = no piece, Off = no bruises; non-gory KO stars at every level (access.gore) |
| ART-07 | Original satire, memorable announcer, fictional PED theme, coherent tone | ~ | GAME_PITCH.md |
| ART-08 | Editable source assets and reproducible import/export steps | I | Editable sources: tools/forge defs, tools/audio scores, assets/ui/source; rebuild commands in docs/ART_PIPELINE.md, docs/AUDIO.md |
| AUD-01 | Menu/combat music, impact/ability/creature sounds, UI feedback, ambience, mixing | I T | Synthesized score (8 tracks), 312 SFX ids, voices, announcer (tools/audio, docs/AUDIO.md); audio bridge attached per match; tests test/audio |
| AUD-02 | Variations, transitions, volume buses, visual alternatives for essential cues, no missing assets, no clipping | I T | Variations/layers/stingers, buses + settings, subtitles for every line, loudness checks (-1 dBFS peak), bank validation tests |

## Menus, settings, accessibility, onboarding [13]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| UI-01 | Polished consistent menus; every displayed control works | ~ | Theme/widget library, all core screens (docs/UI.md, docs/evidence/ui); remaining owner screens hidden until merged |
| UI-02 | Predictable controller focus (dialogs/tabs/errors/returns), hot-plug, device switching | ~ | Controls device tracking |
| UI-03 | Settings from main menu and in-game; persistence, reset, validation, immediate feedback or restart notice | I T | Settings screen generated from Settings.SCHEMA (main menu + in-game), persistence, reset, rollback; UI tests |
| UI-04 | Display: resolution, window mode, display select, presets, frame limit, VSync, render scale, shadow/AO/effects, brightness, UI scale, confirm/rollback | I T | Display options with 15 s confirm/rollback (settings.gd + settings screen) |
| UI-05 | Audio: master/music/effects/announcer, mute/background, device selection | I | Audio sliders, mute in background, device selection (Settings + Audio) |
| UI-06 | Input: rebinding, dead zones, sensitivity, inversion, vibration, prompts, hold/toggle | I T | Full rebinding (both columns, conflicts, reset), dead zone, sensitivity, inversion, vibration, prompts, guard hold/toggle |
| UI-07 | Accessibility: text scale, subtitles, colour-independent cues, shake/flash/motion reduction, gore, assists | — | |
| UI-08 | Gameplay/system: difficulty, tutorial access, pause/suspend, save/profile, diagnostics, preset management | — | |
| UI-09 | Network: host/join options, limits, privacy/password, mod compatibility, status, clear errors | — | |
| UI-10 | 1280x800 readability + controller operability (layout check; device test = X) | I T | 1280x800 layout test (no text < 18 px), Deck preset; HUD essentials >= 23 du; real Deck = X |
| UI-11 | Single-player freedom; custom vs standard progression clearly labeled; MP restrictions explained | — | |
| UI-12 | Tutorial with live binding prompts, staged exercises, feedback, retry/skip/replay, practice; naive play supported | I T | Granny Haymaker tutorial: 10 data-driven exercises with live prompts, hints, retry/skip/replay, saved progress (src/tutorial); tests core/test_tutorial (all 10 completable) |

## Saves & reliability [14]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| SAV-01 | Offline, no login; persist settings, profiles, campaign, suspended runs, unlocks, presets, arenas, mod selections, policies | — | |
| SAV-02 | Versioned formats, atomic writes, backups, migrations; tested interrupted/damaged/updated/missing-mod/removed-content/incompatible-policy cases; non-destructive failures | — | |
| SAV-03 | Co-op persistence & ownership; duplicate-reward and invalid-resume protection | — | |
| SAV-04 | User data outside install; non-admin; spaces/non-ASCII paths; focus/suspend/controller-disconnect/shutdown handling | ~ | User data under %APPDATA%/Critterweight (never install dir); --user-root; tests use an isolated _test_root; unicode/space path test |

## Modding [15]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| MOD-01 | Documented stable extension points: creatures/abilities, balance/data, rules/modes, arenas, presentation | I T | Data extension points: creatures (+extends), rules (+fighter_hooks/fighter_mods/gravity), modes, arenas, campaign kinds, presentation; docs/MODDING.md |
| MOD-02 | Versioned manifests/schemas, stable ids, dependencies, deterministic order, validation, actionable errors, compatibility rules | I T | Manifest schema, ids, requires/load_after, deterministic order, game/API version rules, actionable errors; tests mods/test_mods |
| MOD-03 | In-game discovery/enable/disable, mod sets; restart/new-run notices; save compatibility & missing-mod recovery | I T | Mods screen (enable/disable, sets, problems, import/export/uninstall), missing-mod recovery; tests mods/test_mods |
| MOD-04 | Trust model (scripts/packages, fs/net/native access, limits); path/size/manifest validation; explicit consent for risky capabilities; no silent server code | I T | Data-only trust model: code/engine files rejected, zip directory checks before extraction (bombs, traversal, encryption, ZIP64), size limits, consent for replaces_core |
| MOD-05 | Multiplayer content/mod comparison with clear mismatches; local sharing/import workflow; reject unsafe packages; client-only vs required documented | ~ | Mods.compare() names missing/extra/mismatched gameplay mods; client_only never blocks; share/import workflow; network handshake wiring pending net merge |
| MOD-06 | Example mods (ability/fighter customization, rule/mode, arena) demonstrated: install, UI, gameplay, MP compat, upgrade/removal, errors; modder docs + schemas | ~ | Examples stoke_variants, moon_rules, rust_bucket (mods/examples -> game/mods_examples/*.critmod); install/upgrade/removal/error tests; MP demo pending |
| MOD-07 | Workshop behind a documented service boundary (deferred) | I | Platform.workshop_* boundary (local export), docs/PLATFORM.md §1-2 |

## Provenance [16]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| PRV-01 | Original names, designs, writing, UI identity, audio | ~ | docs/design |
| PRV-02 | Third-party inventory incl. Cage Rules reuse and engine/deps | ~ | docs/THIRD_PARTY.md (Godot, Jolt, fonts incl. Bungee); Cage Rules reuse to be completed |
| PRV-03 | Generated assets: tool/source recorded, editable sources kept | — | |
| PRV-04 | Credits/notices; unresolved legal/platform items recorded; no certification claims | — | |

## Verification gates [17, 19]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| VER-01 | Unit/property tests: damage, effects, resources, modifiers, rewards, progression, unlocks, seeds, rule validation, playlists, serialization/migrations, AI contracts | ~ | Unit tests: persistence/migrations, schema, elements, combat rules (infinites, ranges, determinism), modes, mods, rules validation/presets, tutorial, spectator, audio, UI; campaign/net/lab pending merges |
| VER-02 | Integration: campaign transitions, victory/defeat, co-op decisions/recovery, save/resume, mod loading, authored arenas, policy training/loading, hosted/dedicated networking | — | |
| VER-03 | Runtime (packaged Windows): fresh profile, tutorial, every mode, full runs both variants, both co-op formats, controller/menu navigation, sound/graphics, settings, error flows | — | |
| VER-04 | Multiplayer: independent clients + headless server, latency/jitter/loss, disconnect/rejoin, incompatible content, playlist transitions, authoritative outcomes (loopback labeled) | — | |
| VER-05 | Stability/performance: repeated matches, extended spectator/playlist, Lab resource limits, server soak, busy scenes, loading, memory trends, frame times | — | |
| VER-06 | Asset/content: missing refs, imports, rigs/materials, schemas, safe spawns/bounds, reachable rewards/routes, licenses/credits | ~ | test_content_audit (content errors, assets, weapons/chains/windows, safe spawns, presets/tutorial/achievements, example mods); portability_check.py; audio bank validation |
| VER-07 | Independent review of significant changes; final integrated audit against the whole brief | — | |
| PRC-01 | Records maintained (this ledger, DESIGN, DECISIONS, PROGRESS, VERIFICATION, AGENTS.md) | ~ | |
