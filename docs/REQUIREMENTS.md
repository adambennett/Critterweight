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
| CNT-05 | Polished primary cage + useful arena customization & saved layouts | I T | 4 bases (Gullet day/night/title night, Drydock, Crusher, Rooftop) with hazards/quirks, 30-entry prop catalog, 6 example layouts, saved layouts (docs/ARENAS_AND_EDITOR.md); tests arena/*; docs/evidence/arenas |
| CNT-06 | 4 difficulty presets + The Dosage ladder (10 levels, distinct modifiers, progressive unlock) | I T | content/core/ladder/{difficulty,doses}.json: Sparring/Amateur/Pro/Title Shot + 5 bot tiers (Punching Bag/Journeyman/Contender/Headliner/Hall-of-Famer), 10 cumulative Doses with distinct modifiers; unlock rule in CampaignProgression; test_campaign_run (ladder, difficulty/Dose modifiers), test_campaign_generation (Dose 10) |
| CNT-07 | Visibly different seeded runs (events/upgrades/enemies) | I T | seeded MapGenerator/EncounterBuilder/RewardRoller/EventRunner via RunRng streams (29 events, 45 encounters, 50 supplements, 36 techniques); test_campaign_generation (same seed = same card, varied cards, 500 seeds valid) |
| CNT-08 | 3 bosses with 2 phases | ~ T | BossMode + boss_fights/{bilge,conduit,snappington}.json: 2 phases, telegraphed attacks, Dazed (test_campaign_fights). Real boss creature kits do not parse yet, so fights run on documented stand-in bodies |

## Campaigns & co-op [8]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| CMP-01 | Off the Street (fresh-run): no permanent power; only stats/cosmetics/records/ladder persist; unlocks keep parity | I T | Off the Street variant: no carried power, cosmetic-only Clout wallet, stats/records/history/ladder persist (CampaignProgression); test_campaign_run, test_campaign_full_runs |
| CMP-02 | Clearing the highest unlocked Dose unlocks the next, max Dose 10 | I T | CampaignProgression.apply_ladder_clear (first Amateur+ clear opens The Dosage; clearing the highest unlocked Dose unlocks the next, max 10, only on the profile's own open ladder; Dose credit/records/badges/ach_fully_dosed only within the profile's dose_cap; Doses clamped at run creation, none on Sparring); test_campaign_run::test_ladder_unlock_rule, test_campaign_run::test_dose_credit_needs_the_profiles_own_ladder, test_campaign_ui::test_hub_sign_up_offers_no_dose_on_sparring, test_campaign_coop::test_host_dose_clamped_to_own_ladder |
| CMP-03 | Fight Camp (persistent): permanent upgrades; between runs the player explores the 3D hub | I T | Fight Camp: 24 Cannery upgrades (meta_upgrades/cannery.json, meta_bonus) bought with Clout at 6 hub stations (hub_services.gd) or the Cannery Ledger; applied only in Fight Camp runs (test_campaign_run, test_campaign_full_runs, test_hub_services); main menu Fight Camp opens The Cannery and run summaries return there; upgrades show in the world (docs/HUB_SYSTEMS.md, docs/evidence/hub) |
| CMP-04 | Hub: ≥5 connected spaces, characters, activities, secrets, upgrade stations, real movement | I T | The Cannery (src/hub): 11 connected spaces walked by a real fighter (stairs, hatch, ladders, freight elevator, pier), 8 NPCs with idle/look-at/barks/talk and reactions to the last run, 3 scored activities (bag challenge, chum cannon drill, crate toss) + sparring + Bookie's Table, 10 in-world secrets (first unlocks ach_confidant), corkboard map with fast walk, time of day from the last result; tests test_hub_{geometry,interactions,activities,secrets,services,ui,wander}; perf --hub-bench 2.68 ms avg at 1080p High (docs/evidence/hub); docs/HUB_SYSTEMS.md |
| CMP-05 | Both: branching routes, risk/reward, synergies, random events, bosses, rewards, victory/defeat/replay | I T | branching 3-act maps, elites/treasure, synergy tags, events, 3 bosses, rewards, victory/defeat summary with Run it back/New card/Raise the Dose; test_campaign_full_runs (real fights, both variants, victory and defeat), test_campaign_ui |
| CMP-06 | Pacing/run length defined; seeded reproducible generation; no impossible routes/invalid rewards/softlocks (tested) | I T | pacing rules + estimates (25-40 min), 53-bit seeds, deterministic generation, claim ledger, safe-layout fallback; test_campaign_generation (500 seeds, every route paced and valid), test_campaign_run (duplicate rewards; events pass when nothing can be taken), test_campaign_ui (forfeit when a fight cannot be built; Rest -> Train opens its pick without a screen loop, also from a stuck save and at the Bookie's Table) |
| CMP-07 | How custom runs affect progression/records defined and shown | I T | custom runs (stand-ins, reduced game speed, custom rules) keep stats/history, no records/ladder/unlocks/achievements/camp milestones, Clout 50%, shown on the summary card; live reasons re-checked before every fight and on Run it back, a custom run stays custom (logged); test_campaign_run::test_custom_runs_keep_stats_but_no_records, test_campaign_run::test_custom_fight_camp_runs_set_no_camp_milestones, test_campaign_ui::test_custom_rechecked_at_each_fight, test_campaign_ui::test_run_it_back_rechecks_custom |
| COOP-01 | Online co-op in both campaigns, ≥2 humans (limit 4) | ~ T | CoopSession (2-4) over PartyTransport, both variants; tested over LoopbackTransport (loopback). NetPartyTransport waits for Net app messages (docs/CAMPAIGN_SYSTEMS.md#co-op-protocol) |
| COOP-02 | Tag-team and simultaneous allied combat; simultaneous default (reasoned); tag via settings; 1v1 stays the solo norm | I T | simultaneous default + tag-team format (CampaignMatchMode party tag group); test_campaign_coop::test_tag_team_format (loopback), test_campaign_fights |
| COOP-03 | Run ownership, route voting, per-player choices, reward distribution w/o duplication, progression compatibility | I T | host-owned RunController, route votes with Captain tie-break, per-player picks/Scrip, claim ledger, per-player crediting; sender = transport peer id, host-only messages only from the host, results/tickets verified against their decision log, group-event ballots only with choices the whole party can pay (failed picks dropped, a member's choice is a vote); test_campaign_coop (loopback) |
| COOP-04 | Downed/defeated players, tag-out participation, pause rules | I T | downed/revive on MatchMode's machinery with shrinking timers, tag-out/cheer/assist, ref-timeout pause budget; test_campaign_fights::test_downed_and_revive_in_coop, test_campaign_coop (loopback) |
| COOP-05 | Disconnect/rejoin, host departure recovery, save/resume party, continue with absent player | I T | bot takes a disconnected member's fighter, rejoin at node boundary, host departure -> member replica resumes, party slot suspend/resume, absent-member move-on; test_campaign_coop (loopback) |
| COOP-06 | Permanent campaign power kept out of PvP; active custom rules visible | I T | meta_bonus upgrades applied only by BuildApplier in Fight Camp (or visible Gym Bonuses custom rule); rule tags shown on the fight card/HUD; test_campaign_run::test_fight_camp_meta_applies_only_in_fight_camp |

## Match types, rules editor, arena editor [9]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| MCH-01 | Practice vs NPCs | I T | PracticeMode (dummy behaviours, telemetry), Tutorial freestyle; tests core/test_modes_extra |
| MCH-02 | 1v1 PvP (online; local two-pad as bonus) | — | |
| MCH-03 | ≥4 simultaneous fighters for FFA/teams/custom; documented maximum (8) | I T | MatchSim up to 24 fighters (8 players + spawned minions); FFA/teams presets; HUD 4-column card grid for 5-8 |
| MCH-04 | ≥3 genuinely different bonus modes (4 designed) with NPCs and documented player/team counts | I T | Spotlight Hog, Chumball, Absolute Unit, Chum Rush, Tag Team (src/sim/modes); tests core/test_modes, test_modes_extra, test_containment; captures/mode2_*.png |
| MCH-05 | Rules editor: format, teams, rounds, timers, score/win, health/resources, damage/knockback, respawn/revive, ability limits, hazards, bots, mode options; validation + explanations | I T | RulesValidator (every rule: range, help, per-mode options, validation with explanations) + rules_editor screen; fighter_mods whitelisted with ranges, rules values clamped again where the sim applies them; tests core/test_rules_presets, core/test_rules_hardening |
| MCH-06 | Presets: save/duplicate/rename/import/export/share, versioned; usable locally, hosted, in dedicated playlists, with compatible mods | ~ | RulePresets: save/version/duplicate/rename/delete/export/import, registered in Content (local + host lists); hosted/playlist use pending net merge |
| ARN-01 | Arena editor: choose base; place/adjust props, obstacles, hazards, spawns, boundaries within limits | I T | src/editor/arena_editor_screen.gd (Create › Arena Editor): base + look, palette with costs, grid/free placement, boundary within the base range, base hazards/built-ins/pits toggles; tests arena/test_arena_editor_screen; docs/evidence/arenas/11-12 |
| ARN-02 | Select, move/rotate, delete, undo/redo, save/load, validate, test-play | I T | ArenaEditCommands stack (bounded, dirty tracking), ArenaLibrary saves (v2, v1 migration), live validation with clickable issues, test play round trip; tests arena/test_arena_editor*, test_arena_editor_screen |
| ARN-03 | Mouse/keyboard and controller operation | I T X | full mouse/keyboard and controller maps (docs/ARENAS_AND_EDITOR.md §3), PromptBar glyphs; injected-event tests; physical controller unverified (X) |
| ARN-04 | Validation: spawn safety, bounds, budget, required mode markers | I T | src/editor/arena_validator.gd (budget 100, 24 props, 8 hazards, 4 pickups, 45% clear floor, spawn 1.5 m, walls/edges/pits, clusters 6 m, mode markers); tests arena/test_arena_validation |
| ARN-05 | Authored arenas playable in normal matches; export/import as content packages usable by compatible peers; examples shipped | ~ | (implemented + tested except the lobby transfer) saved layouts registered in Content (`user:` ids) and resolved by App; zip packages with manifest, sha256, content/package hashes and hardened import (import_bytes for peers); 6 example layouts; lobby transfer of user layouts not wired (~) |

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
| AI-03 | Bookie's Table autobattler: player picks fighter/route/upgrades/build, AI fights, shared campaign systems | I T | BookieTable + Bookie screen: player builds/decides or Teddy decides, bots fight, shared campaign systems; test_campaign_bookie, test_campaign_ui::test_bookie_screen_setup_live_and_stop |
| AI-04 | Unattended mode with auto decisions, pause, speed/camera, take-over; extended unattended run tested | ~ T | unattended autopilot (CampaignAutoPilot), pause (freezes fight physics), speed 1-4x (re-applied for every presented fight: test_campaign_ui::test_bookie_speed_holds_for_every_presented_fight), take over/hand back; 3 complete unattended runs with real fights (test_campaign_bookie). Camera = the standard fight camera |
| LAB-01 | Actual local learning (parameters change from experience) | I T W | ES and behaviour cloning train MLP weights in worker processes (src/lab/lab_es.gd, lab_bc.gd); test_lab_worker (ES beats its start on held-out drill seeds), test_lab_bc; docs/evidence/lab: 3 ES seeds +28..+48 test reward, BC validation loss 4.7 → 1.5 / 0.33. W: editor binary, not a packaged build |
| LAB-02 | ≥2 distinct training approaches (evolution strategies RL + behaviour cloning) documented | I T | evolution strategies (reward), behaviour cloning (imitation), BC → ES; docs/AI_LAB.md §2; test_policy_mlp, test_lab_bc, test_lab_worker |
| LAB-03 | Lab UI: fighter, approach, objectives/styles, opponents/scenarios, seed, resource/time limits | I W | src/lab/ui/lab_screen.gd (Train/Runs/Policies/Recording tabs, controller + mouse/keyboard, per-term reward weights, seed, limits); captures docs/evidence/lab/ui via lab_ui_capture.gd (editor binary) |
| LAB-04 | Real combat rules, headless accelerated simulation, same observation/action contract in training and matches | I T W | LabEpisode = MatchSim + standard MatchMode in its own World3D; workers --headless --fixed-fps 120 (~16x real time per process); one PolicyInputSource/obs_v1/act_v1 for training, recording and MatchScene; test_policy_contract, test_lab_recording |
| LAB-05 | CPU defaults, modest workloads, optional GPU documented, no paid services | I | CPU only, pure GDScript; defaults 1 worker (UI suggests min(3, cores/2-1)), low priority, 20-minute limit; GPU not used and why, no paid services/accounts/Python: docs/AI_LAB.md §8 |
| LAB-06 | Progress/episodes/time/resources/metrics; pause/resume, checkpoints, cancel, failure recovery; game stays responsive | I T W | progress/metrics/checkpoint/control files; test_lab_worker (pause/resume/cancel, kill + resume from checkpoint, helper heartbeat, starved-but-alive worker); UI pause/resume/cancel and frame times (median 16.7 ms while a worker trains): docs/evidence/lab/ui/ui_report.json |
| LAB-07 | Save/version/name/export/import/load policies; compatibility validation; never executes code | I T | PolicyData/PolicyIO/PolicyLibrary (versioned JSON, checksum, atomic writes, .bak recovery, JSON + base64 only); test_policy_io (damaged, tampered, oversized, newer, incompatible files; import id collision) |
| LAB-08 | Evaluation vs fixed baselines and held-out seeds, separate from training; honest reports | I T W | LabEval + eval jobs; disjoint train/val/test seed streams; every episode reported with n, mean, 95% CI and Wilson win intervals, scripted reference on the same episodes; docs/evidence/lab/runs/*/report.json (a non-significant BC → ES gain is reported as such) |
| LAB-09 | Saved bots can be fought/spectated; hosts can use compatible policies; inference budget measured | I T W | MatchScene fighter kind "policy" (PolicyInputSource.for_match, scripted fallback); Lab Fight/Spectate this bot (docs/evidence/lab/match); lookup API PolicyLibrary.get_policy for hosts/servers; inference 138.5 us per tick for 8 fighters (budget 250): test_policy_inference, docs/evidence/lab/bench |
| LAB-10 | Docs, reproducible small examples, sample policies; controlled learnable task with recorded improvement | I T W | docs/AI_LAB.md; docs/evidence/lab (jobs, runs, curves, README); 3 sample policies in content/core/policies (test_policy_samples); drill task improvement on 3 seeds |

## Art, animation, graphics, audio, tone [12]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| ART-01 | Art direction guide | I | docs/design/ART_DIRECTION.md: style statement, silhouettes/proportions, global/element/fighter palettes, stylized PBR materials, active-ragdoll animation principles, per-element VFX shape language (readable without colour), impact/hit-flash rules, UI style and typography, wordmark, readability in 4-8 fighter scenes, asset standards for the forge pipeline |
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
| SAV-01 | Offline, no login; persist settings, profiles, campaign, suspended runs, unlocks, presets, arenas, mod selections, policies | ~ T | campaign: suspended runs (RunStore), campaign profile fields (records, ladder, Clout, history); test_campaign_persistence. Other data kinds belong to their owners |
| SAV-02 | Versioned formats, atomic writes, backups, migrations; tested interrupted/damaged/updated/missing-mod/removed-content/incompatible-policy cases; non-destructive failures | ~ T | campaign saves: versioned, atomic via Saves, .bak recovery, v0 migration, damaged/missing/newer/removed-content non-destructive; slots left with only .tmp/.bak are listed; floats stabilized for JSON (RunStore.json_stable); test_campaign_persistence. Newer-format files never written (settings/profiles/mod sets read-only with a player message; newer campaign runs never moved or deleted), a damaged main file never costs the last valid .bak, recovery by write sequence not clock; core/test_persistence_safety |
| SAV-03 | Co-op persistence & ownership; duplicate-reward and invalid-resume protection | I T | party tickets with checksums (replica checkpoints) accepted only from the host and only if they follow from their decision log (RunController.verify/verify_from), claims keyed by node, idempotent crediting, party slots cleared at run end and never resumed solo, a suspended run is never replaced without confirmation (abandon credited; a newer version's run is never replaced); test_campaign_persistence, test_campaign_coop (loopback), test_campaign_ui |
| SAV-04 | User data outside install; non-admin; spaces/non-ASCII paths; focus/suspend/controller-disconnect/shutdown handling | ~ | User data under %APPDATA%/Critterweight (never install dir); --user-root; tests use an isolated _test_root; unicode/space path test |

## Modding [15]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| MOD-01 | Documented stable extension points: creatures/abilities, balance/data, rules/modes, arenas, presentation | I T | Data extension points: creatures (+extends), rules (+fighter_hooks/fighter_mods/gravity), modes, arenas, campaign kinds, presentation; docs/MODDING.md |
| MOD-02 | Versioned manifests/schemas, stable ids, dependencies, deterministic order, validation, actionable errors, compatibility rules | I T | Manifest schema, ids, requires/load_after, deterministic order, game/API version rules, actionable errors; patterns matched whole, no whitespace/control characters in ids/versions, exact lowercase folder names on every OS; tests mods/test_mods, mods/test_mod_hardening |
| MOD-03 | In-game discovery/enable/disable, mod sets; restart/new-run notices; save compatibility & missing-mod recovery | I T | Mods screen (enable/disable, sets, problems, import/export/uninstall), missing-mod recovery; tests mods/test_mods |
| MOD-04 | Trust model (scripts/packages, fs/net/native access, limits); path/size/manifest validation; explicit consent for risky capabilities; no silent server code | I T | Data-only trust model: code/engine files rejected, zip directory checks before extraction (bombs, traversal, encryption, ZIP64, layouts other zip readers see differently; extraction must match the checked listing and hash), size limits, portable entry names, links never followed, only validated files loaded/copied/exported, asset paths confined to validated package files, core overrides only with declared + consented replaces_core and never of other mods' entries (D-027), client_only = presentation only at install and load, mod text never BBCode; tests mods/test_mod_hardening |
| MOD-05 | Multiplayer content/mod comparison with clear mismatches; local sharing/import workflow; reject unsafe packages; client-only vs required documented | ~ | Mods.compare() names missing/extra/mismatched gameplay mods; client_only never blocks; share/import workflow; network handshake wiring pending net merge |
| MOD-06 | Example mods (ability/fighter customization, rule/mode, arena) demonstrated: install, UI, gameplay, MP compat, upgrade/removal, errors; modder docs + schemas | ~ | Examples stoke_variants, moon_rules, rust_bucket (mods/examples -> game/mods_examples/*.critmod); install/upgrade/removal/error tests; MP demo pending |
| MOD-07 | Workshop behind a documented service boundary (deferred) | I | Platform.workshop_* boundary (local export), docs/PLATFORM.md §1-2 |

## Provenance [16]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| PRV-01 | Original names, designs, writing, UI identity, audio | ~ | docs/design |
| PRV-02 | Third-party inventory incl. Cage Rules reuse and engine/deps | I | docs/THIRD_PARTY.md: engine/middleware, fonts (Barlow via Cage Rules, Bungee) with sources, licences, notices; Cage Rules reuse audited repo-wide (fonts only; its bundled three.js/rapier/peerjs unused); original-asset inventory (models, visuals, audio, policies, writing) |
| PRV-03 | Generated assets: tool/source recorded, editable sources kept | I | Models: tools/forge from tools/forge/defs (docs/ART_PIPELINE.md, generator recorded in each .glb); audio: tools/audio sources with byte-identical re-render check (docs/AUDIO.md); icons: game/assets/ui/source/make_icons.py; policies: Lab jobs/logs in docs/evidence/lab |
| PRV-04 | Credits/notices; unresolved legal/platform items recorded; no certification claims | I | In-game Credits + Notices (engine licence/component texts from the running binary, OFL texts); docs/CREDITS.md and THIRD_PARTY.md + OFL files ship in every package (tools/build/package.ps1); open legal/platform items listed in THIRD_PARTY.md (no certification claims) |
## Verification gates [17, 19]
| ID | Requirement / acceptance | State | Evidence |
|---|---|---|---|
| VER-01 | Unit/property tests: damage, effects, resources, modifiers, rewards, progression, unlocks, seeds, rule validation, playlists, serialization/migrations, AI contracts | ~ | Unit tests: persistence/migrations, schema, elements, combat rules (infinites, ranges, determinism), modes, mods, rules validation/presets, tutorial, spectator, audio, UI; campaign/net/lab pending merges |
| VER-02 | Integration: campaign transitions, victory/defeat, co-op decisions/recovery, save/resume, mod loading, authored arenas, policy training/loading, hosted/dedicated networking | ~ T | campaign transitions, victory/defeat, co-op decisions/recovery (loopback), save/resume covered (test_campaign_*); other integration areas belong to their owners |
| VER-03 | Runtime (packaged Windows): fresh profile, tutorial, every mode, full runs both variants, both co-op formats, controller/menu navigation, sound/graphics, settings, error flows | — | |
| VER-04 | Multiplayer: independent clients + headless server, latency/jitter/loss, disconnect/rejoin, incompatible content, playlist transitions, authoritative outcomes (loopback labeled) | — | |
| VER-05 | Stability/performance: repeated matches, extended spectator/playlist, Lab resource limits, server soak, busy scenes, loading, memory trends, frame times | — | |
| VER-06 | Asset/content: missing refs, imports, rigs/materials, schemas, safe spawns/bounds, reachable rewards/routes, licenses/credits | ~ | test_content_audit (content errors, assets, weapons/chains/windows, safe spawns, presets/tutorial/achievements, example mods); portability_check.py; audio bank validation |
| VER-07 | Independent review of significant changes; final integrated audit against the whole brief | — | |
| PRC-01 | Records maintained (this ledger, DESIGN, DECISIONS, PROGRESS, VERIFICATION, AGENTS.md) | ~ | |
