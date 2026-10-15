# PokeMMA — complete game implementation brief

## 1. The outcome I want

We're building an original, polished 3D creature cage-fighting game. The point is to make something genuinely fun to play: approachable arcade fighting, expressive physical combat, interesting creatures, and roguelike builds that make me want another run. I may eventually sell it on Steam for around $10 or less, if the finished game earns that. This should feel like a cohesive commercial indie game with its own identity.

**Deliver the entire game described here as a fully implemented, technically verified release candidate for me to evaluate. This is intentionally a large scope. A prototype, vertical slice, engine demo, partially implemented feature list, or plan for finishing later is not the requested final product.**

I intend to let an implementing agent work for an extended period with little or no further input. Make the design and engineering decisions needed to finish. Work through implementation, integration, review, verification, and refinement. Do not treat the first playable build or an intermediate milestone as completion.

This document is the authoritative implementation brief and supersedes `Initial_Prompt.md`. Preserve the original file. Every required feature below belongs in the first delivery. Only the explicit exceptions in section 2 are outside that completion boundary. Do not downgrade features because they are difficult or because the current build does not contain them.

Choose an original working title early. `PokeMMA` is a placeholder. Use original terminology for creatures, elements, modes, abilities, and difficulty levels. A new display name does not require renaming the existing repository or workspace paths.

## 2. Delivery boundary and explicit exceptions

### Required first delivery

- A complete, packaged Windows game, its source, assets, build tools, tests, and documentation.
- Windows and Linux support, including a practical Steam Deck delivery path. Linux support is an implementation/build target, not just a future roadmap item.
- Every gameplay system in this brief: physical creature combat, both campaigns, both co-op formats, PvP, NPCs, custom rules, bonus modes, hosting, dedicated servers, playlists, local modding, spectator/autobattler play, a real AI Lab, a bounded arena editor, and modest cosmetic gore.
- Finished presentation and content, usable settings and onboarding, reliable persistence, and the verification described below.
- A technically verified release candidate for my evaluation. My subjective playtest approval is not required before this implementation goal can finish.

### Explicitly deferred commercial and Steam work

Do not create Steam accounts, buy an app ID, spend money, enroll in services, accept new commercial agreements on my behalf, prepare or publish a store listing, upload a public release, or perform commercial release administration. Real Steam/Workshop integration that requires those accounts, credentials, SDK access, or release setup is deferred.

Build a complete standalone game and local mod ecosystem now. Keep platform services behind clear interfaces so Steam invitations, identity, distribution, and Workshop can be added later. Document the specific integration work that remains; do not claim an adapter or mock is a functioning Steam integration. Lack of Steam access must not prevent offline play, direct/LAN multiplayer, hosting, or local mods.

Commercial approval, legal clearance for sale, and extensive hardware/platform certification happen after I evaluate this delivery. Record provenance and unresolved release considerations now, without pretending to certify them.

### Platform verification allowance

This machine provides Windows runtime access. I expressly accept best-effort non-Windows verification for this first delivery. Use available cross-compilation, portable tests, build configuration checks, and existing local tooling where practical. Do not rent cloud machines, buy hardware, or provision paid CI to test other platforms.

Unexecuted Linux/Steam Deck device tests are an allowed handoff gap, not a reason to hold this goal open forever. Implement the Linux target and attempt the builds/checks that the environment supports. If producing a Linux binary is genuinely unavailable here, provide complete build configuration and reproducible instructions, attempted-check evidence, and the exact remaining native-build/runtime checks. This allowance excuses unavailable verification; it does not excuse known portability defects or deliberately Windows-only implementations of required systems.

macOS, Android, and iOS are desirable extensions, not required first-delivery ports. Assess their feasibility during engine selection and avoid unnecessary architectural barriers. Implement them only if practical after required work is complete; do not let speculative ports displace the game. Do not claim support or testing that has not happened.

### Scope of the smaller features

Keep gore and the arena editor deliberately modest. Include a small, polished cosmetic gore implementation and a useful cage/arena editor; neither requires an elaborate dismemberment simulation or a general open-world authoring suite. The AI Lab is a substantial required feature, including real local learning and multiple training approaches.

## 3. How to work autonomously

- Make reasonable design decisions instead of repeatedly asking me to choose between viable options. Research when useful, decide, record the reason, and implement.
- Ask only when a genuinely necessary action requires authorization or access you do not have, or when proceeding would contradict an explicit requirement. Continue independent work while a dependency is unresolved.
- Use the client's supported persistent-goal mechanism when available and already requested by the launch prompt. Preserve one full objective across milestones. Do not invent unsupported commands or claim that a goal is active without confirmation.
- Make concrete progress each work cycle: implement an unmet requirement, integrate a system, investigate a failure, or improve an evidenced quality problem. Avoid indefinite planning, architecture rewrites, and polishing one corner while required systems remain absent.
- Use small feasibility experiments for consequential uncertainties. Record the result and commit to a coherent approach. Do not endlessly retry identical failing commands or treat a hard problem as proof that the whole game is impossible.
- Maintain concise status and a precise next action in the repository so work can resume after context compaction, interruption, or a usage limit. A quota limit or session ending means the work is incomplete, not successful.
- Do not purchase additional usage, switch to paid API fallback, or provision services. Work within the available subscription, permissions, and local resources. Do not manufacture a completion claim to end a long run, and do not waste usage after the goal is actually achieved.
- Verify current files and runtime evidence when resuming. Earlier summaries are navigation aids, not proof of current completion.

Maintain these practical records, or an equally clear compact structure:

- `docs/REQUIREMENTS.md`: stable requirement IDs covering every substantive obligation in this brief; acceptance criteria; dependencies; current state; implementation references; verification evidence; and permitted external gaps.
- `docs/DESIGN.md`: the chosen combat, camera, controls, roster, elements, content targets, campaigns, co-op, and mode rules.
- `docs/DECISIONS.md`: consequential engine, physics, networking, persistence, platform, and tooling decisions with reasons.
- `docs/PROGRESS.md`: current milestone, integrated work, blockers, most recent checks, and the next concrete actions.
- `docs/VERIFICATION.md`: commands, environment, results, runtime evidence, performance measurements, and known issues.

Assign separate states for implemented, built, automatically tested, Windows runtime verified, and externally unverified where relevant. A feature checklist must not collapse these distinctions into an unsupported green check. Do not rewrite acceptance criteria downward to match unfinished work. Keep these records concise enough to remain useful.

## 4. Workspace, reuse, and coordination

The implementation workspace is `C:\Users\eX_Di\git\PokemonMMA\PokeMMA`. The reference project is `C:\Users\eX_Di\git\PokemonMMA\Cage Rules\MMAsim`.

I authorize reuse of Jeremy's Cage Rules code, ideas, and project-owned assets where useful. Reusing some basic cage assets is fine. Favor original creature art, animation, UI, music, and distinctive presentation so this game has its own identity. Preserve third-party licenses and attribution in anything reused; my permission for Cage Rules does not change licenses of its bundled dependencies. Read or copy from the reference project without altering it or interfering with other projects.

Use `https://github.com/adambennett/PokeMMA` for this project. Inspect local and remote state before initialization or pushes. Initialize or connect the repository if necessary, preserve existing history and unrelated changes, and make reviewed incremental commits and pushes using existing authorized access. Do not force-push or replace remote history. If authentication is unavailable, preserve local commits and document the exact push step instead of blocking game development indefinitely. Missing external Git access may be reported as an administrative handoff gap; it does not excuse missing source or local checkpoints.

Create a concise `AGENTS.md` with actual build/test/run commands, architecture boundaries, style, and verification rules. If the implementing client reads another instruction filename, provide a small compatible entry point referring to the same canonical guidance rather than maintaining conflicting copies. Add reusable skills/scripts only when they serve concrete workflows.

Use multiple agents where this improves progress or review quality. One lead owns architecture, integration, and the completion audit. Delegate bounded tasks with agreed interfaces and clear file/module ownership. Review the integrated result, not only isolated agent reports. Keep a runnable main build as the project grows. Review code and run relevant checks before committing; independent review is preferred for significant changes. Prefer Fable 5.1 (or newer, if available) as the agent to use for any creative work - designing abilities, gameplay systems, and other content.

Write code that is straightforward for both people and agents to maintain: clear names, cohesive modules, explicit contracts, limited hidden state, documented invariants, reproducible commands, and useful diagnostics. Modders and their agents should be able to understand the extension points without reverse-engineering the game.

## 5. Engine, platforms, and performance

There is no required engine, language, graphics API, or scripting language. Unreal, Unity, another maintained engine, or a custom C++/Rust approach are all acceptable. I find Unreal appealing, but that is not a mandate. Choose based on the complete game's needs and measured delivery risk.

Compare realistic options briefly against physical combat, animation/content tooling, UI, networking, modding, headless servers, Windows/Linux/Deck deployment, performance, build automation, licensing, monetization, and maintenance. Verify current official documentation and license terms rather than assuming that a custom engine is faster or commercially simpler. Then select an approach and proceed.

Use a maintained physics engine/library. Custom combat controllers and rules are welcome; building a general-purpose physics library is not part of this project. Avoid spending the project recreating engine infrastructure that does not improve the game.

Deliver an installable or self-contained desktop game appropriate for the selected engine, rather than defaulting to a browser/Electron recreation of Cage Rules. Keep game rules, simulation, rendering, platform services, persistence, and content definitions sufficiently separated for testing, servers, and mods.

Early in development, record supported Windows/Linux versions and CPU architectures, minimum/recommended hardware assumptions, graphics presets, maximum fighter count, server capacity, and performance budgets. Use Windows x64 and Linux x86-64 as initial targets unless a documented compatibility reason requires otherwise. Target Ubuntu 24.04 LTS and a realistic Steam Deck/SteamOS path; do not promise every future Linux version.

Target stable 60 fps combat at 1280x800 on Steam Deck-class hardware with an appropriate preset, and at 1080p on a documented mainstream PC baseline. Measure the actual available Windows machine; do not present estimates as Deck measurements. Record frame-time distributions, loading time, memory use, and server simulation cost in representative busy scenes. Choose numeric budgets early and fix regressions rather than lowering settings invisibly during benchmarks. Scale expensive effects while preserving readable combat.

Prove controller input, a representative animated/physical fighter, audio, asset import, packaging, and the intended renderer before extensive content production. Establish Linux build feasibility early. Keep optional mobile/Apple feasibility notes separate from verified shipping targets.

## 6. Combat and controls

Cage Rules is the main reference for the physical feel, active ragdolls, contact, impact, and cartoony presentation. Build something recognizably physical and expressive. Preserve the appeal of bodies reacting to strikes, blocking, stumbling, and recovering. Some attacks should depend meaningfully on actual contact and positioning. Creature abilities can also include projectiles, area effects, movement tools, and other ranged or unusual mechanics.

Choose and document a coherent active-ragdoll or hybrid combat model. Explain how authored attacks, hit validation, physical contacts, impact reactions, animation, and gameplay authority fit together. Conventional animation may support readability and control, but replacing all physical combat with unrelated canned animations would miss the brief. Do not copy Cage Rules' simulation rate or humanoid anatomy blindly; profile the needs of this roster and multiplayer model.

Controller-first means an Xbox-style controller can operate every required player workflow, including menus, tutorial, fights, campaigns, AI Lab, mod management, and arena editing. Mouse and keyboard must also be fully supported. Text-heavy authoring can be more convenient with a keyboard, but basic operation must not strand a controller user.

The basic experience should work with the left stick and a few easy-to-remember buttons. A new player should be able to move around and mash attacks against an easy opponent and have a good time. Build depth through timing, spacing, defense, combinations, resource management, ability interactions, and matchup knowledge. Avoid mandatory complicated input sequences, punitive input precision, or excessive buttons for basic competency.

Settle camera, movement reference frame, targeting/assistance, core actions, defense, input buffering, cancel rules, stamina/resources, knockdowns, ring boundaries, win conditions, and recovery behavior in the design brief. Decide how much clinching or grappling improves this simpler game; do not import the full control complexity of Cage Rules. Make losses understandable and prevent unavoidable infinite combinations or permanent stun locks.

Require readable windups, impact feedback, recovery cues, and predictable control. Handle different body shapes without unreadable reach advantages or broken collisions. Keep cosmetic physics separate from authoritative outcomes where needed for consistency. Provide repeatable combat scenarios and useful debug visualizations for tuning and diagnosis.

## 7. Creatures, elements, and bounded content

Deliver 4–10 finished, original playable creatures. Choose the exact count early within that range; aim for a small roster with clear reasons for every fighter to exist. Four excellent, distinct fighters satisfy the count more honestly than ten unfinished ones. A fighter is not finished until its moves, physical behavior, animation, effects, audio, UI representation, AI use, and multiplayer behavior are integrated.

Define each fighter's identity, silhouette, element relationships, strengths, weaknesses, signature abilities, counterplay, and multiple useful build directions. Avoid elemental recolors or duplicate kits. Each fighter should offer a different way to approach a fight without becoming incomprehensible to beginners.

Design an original element system that creates meaningful interactions in real-time combat and roguelike builds. Record its rules, presentation, balance rationale, and edge cases. Elements should create tactical opportunities and interesting combinations without routine matchups becoming unwinnable solely because of selection. Use text/icons as well as color to communicate important information.

Before mass content production, commit to exact first-delivery targets for elements, arenas, encounters, bosses, run length, events, upgrades, overworld activities/secrets, and difficulty tiers. Use the following functional minimums to prevent a token implementation:

- Complete runs in both campaign variants, with a beginning, branching route decisions, escalating encounters, bosses, victory, defeat, rewards, and replay.
- Several meaningful route decisions per run and more than one viable build direction for every fighter.
- Distinct event, upgrade, and enemy combinations sufficient to produce visibly different seeded runs; repeating a single encounter with changed statistics is insufficient.
- At least three bonus modes with different gameplay objectives or constraints, beyond standard 1v1 and basic free-for-all/team fights.
- A polished primary cage plus genuinely useful arena customization and saved layouts.
- Multiple difficulty presets and a defined, progressively unlocked challenge ladder with several distinct modifiers.
- An explorable hub with multiple connected spaces, meaningful interactions, and discoverable secrets/upgrades.

Make the numeric content plan ambitious enough for a satisfying small commercial game, then implement it. Do not use content counts as a substitute for quality or expand them endlessly after the required experience is complete. Any revision must preserve these minimums and the original purpose, with an explicit design reason rather than a shortcut to completion.

## 8. Campaigns and co-op

Build two campaign variants using shared systems where practical:

1. **Fresh-run campaign:** no permanent power advantages between runs. Build power comes from choices within the run. Statistics, cosmetics, records, and access to harder difficulties may persist. Define unlocks so they do not quietly undermine the intended starting-power parity. Clearing the highest unlocked challenge level unlocks the next until a defined maximum. Give this ladder an original name.
2. **Persistent-progression campaign:** permanent upgrades and progression support repeated runs. Between runs, the player explores a real 3D overworld/hub with characters, activities, secrets, upgrades, and meaningful movement through connected spaces. It should have more exploration than a small menu room while remaining a practical, bounded location. A collection of menus does not satisfy the explorable-world requirement.

Both need branching paths, meaningful risk/reward choices, build synergies, random events, bosses, rewards, and satisfying complete run loops. Define pacing and run duration instead of allowing endless fights. Use seeds and reproducible generation for debugging and tests. Resolve impossible routes, invalid rewards, and softlocks.

Support online co-op in both campaigns, with at least two human players. I delegate the exact party limit, route/reward decisions, and run structure to you. A useful direction is individual fighters and builds participating in a coordinated shared run, so each ally has decisions and agency. Borrow the principle rather than copying another game's naming or implementation.

Implement both tag-team combat and simultaneous allied combat. Choose one as the default and explain why it works; expose the other through clear campaign/session settings. Preserve standard 1v1 as the normal solo fighting format. Co-op should be deliberately balanced and enjoyable rather than simply doubling the number of actors.

Define and implement run ownership, route voting, per-player choices, reward distribution, progression compatibility, downed/defeated players, participation during tag-outs, pause rules, disconnect/rejoin, host departure, saving/resuming the party, and continuation when a participant is absent. Host migration is not mandatory if reliable recovery and clear behavior solve host departure. Make per-player progress outcomes understandable and prevent reward duplication.

Keep permanent campaign power separate from standard PvP fairness. Custom matches may deliberately enable unusual rules, but participants must be able to see what is active. Define how customized runs affect progression and records without unnecessarily restricting single-player experimentation.

## 9. Match types, custom rules, and arena editor

Support practice against NPCs, normal 1v1 PvP, and matches with more than two combatants. Support at least four simultaneous fighters for team/free-for-all/custom play, then choose a documented maximum consistent with performance and readability.

Create at least three genuinely different bonus modes. Think of the variety enabled by Halo custom games: different objectives, interactions, or constraints that make players use the same game in a fresh way. Avoid presenting three damage multipliers as three creative modes. Integrate NPCs where sensible and clearly describe supported player/team counts.

Provide a substantial in-game rules editor: match format, teams, rounds, timers, score/win conditions, health/resources, damage and knockback, respawns/revival where relevant, ability restrictions, hazards, bots, and the special rules needed by the shipped modes. Validate combinations and show useful explanations. Save, duplicate, rename, import/export, and share versioned presets. The same presets must work in local play, hosted sessions, dedicated playlists, and compatible mods.

Include a bounded arena editor centered on cages and small arenas. Let players choose a supported arena base and place/adjust permitted props, obstacles, hazards, spawn points, and playable boundaries within valid limits. Support selection, movement/rotation, deletion, undo/redo, save/load, validation, and a test-play loop. Provide mouse/keyboard and usable controller operation. Validate spawn safety, bounds, budget limits, and required mode markers.

An authored arena must be playable in a normal match and exportable/importable as a local content package that compatible multiplayer peers can use. Include examples. This is not a requirement for terrain sculpting, arbitrary 3D modeling, a scripting IDE, or a general open-world editor.

## 10. Multiplayer, servers, and playlists

Implement real online PvP and co-op, in-game listen-server hosting, and a separately runnable headless dedicated server for ongoing matches. Provide Windows server delivery and Linux server build support under the platform allowance. Document installation, configuration, direct/LAN connection, ports, logs, administration, and shutdown/restart behavior.

Choose a coherent simulation/networking model early. Document authority, fixed simulation steps, ownership of randomness, prediction/reconciliation or rollback as appropriate, serialization, bandwidth, tick rates, and version compatibility. Do not assume cross-platform floating-point physics is deterministic without proving what the chosen protocol needs. Clients must not directly dictate authoritative damage, rewards, or progression.

Prove hosted and dedicated matches with independent client processes before substantial campaign content depends on networking. Then verify combat, co-op decisions, saves, custom rules, authored arenas, and supported mods through the real networking path. Define and test timeouts, disconnect/reconnect, invalid data, incompatible builds/content, and server shutdown. Surface connection failures clearly.

Required standalone connectivity includes direct address and LAN play plus the UI/configuration needed for a remote user-hosted server. Document any manual port-forwarding/NAT limitations. Seamless internet invitations/relay traversal may use a suitable already available solution, but do not require new paid services or a Steam account. Do not claim tested off-machine internet connectivity from a loopback test.

Inspect Project Reclaimer's public/local documentation where accessible for ideas about hosting and playlists. The actual required behavior is defined here; do not spend excessive time reverse-engineering that project or modify any existing live servers.

Implement weighted playlists that rotate mode/arena/rule combinations, allow player voting, and support bots where appropriate. Specify candidate selection, meaning of weights, tie/no-vote handling, repeat avoidance, empty-server behavior, minimum player counts, invalid entries, missing content, and restart persistence. Provide editable example playlists and useful validation errors. Confirm that rounds end cleanly and advance without manual intervention.

Dedicated servers need long-running stability, bounded logs/resources, safe configuration defaults, and administration that does not expose unrestricted remote commands. Validate inbound data and resource limits. Keep administration local/authenticated as appropriate. Do not provision or publicize an actual hosted fleet as part of this task.

## 11. NPCs, spectator play, and the AI Lab

Ship competent NPC opponents with clearly different difficulty levels, including forgiving beginner behavior and demanding advanced play. Tune reaction times, mistakes, strategy, and ability usage. Do not silently make the hard bot omniscient or bypass combat rules. Test every creature and relevant match type with bots.

Provide ordinary AI-vs-AI spectating with useful camera/HUD controls. Also provide a roguelike autobattler mode in which the player chooses a fighter, route, upgrades, and build while AI performs the fights. Share appropriate campaign systems. Include an unattended option that can make between-fight decisions and continue automatically, with pause, speed/camera controls where practical, and a clear way to take over decisions again. Test extended unattended operation and valid run transitions.

The AI Lab must perform actual local learning. Difficulty presets, parameter sliders, prewritten scripts, or simulated progress bars do not satisfy it.

- Implement at least two meaningfully distinct usable training approaches. For example, reward-based reinforcement/evolutionary policy optimization and imitation from recorded play. Choose methods appropriate to the simulation and available hardware; document what each learns and why.
- Let the user choose a fighter, training approach, objectives/styles, opponents/scenarios, seed, and resource/time limits through the game UI.
- Train against the real combat rules. Support headless/accelerated simulation where useful without changing the rules being learned. Use the same observation/action contract during training and matches.
- Provide CPU-capable defaults with modest workloads. Optional GPU acceleration may use available hardware. No paid APIs, cloud training, or new service accounts are required.
- Show meaningful progress, episodes, elapsed time, resource use, and learning/evaluation metrics. Support pause/resume, checkpointing, cancellation, failure recovery, and continued use of the game without freezing the interface.
- Save, version, name, export/import, and load trained policy artifacts. Validate compatibility and data; loading a policy must not silently execute arbitrary external code.
- Evaluate against fixed baseline opponents and held-out seeds/scenarios, keeping training and evaluation results separate. Report policy quality honestly instead of cherry-picking one win.
- Allow saved bots to be fought and spectated, and allow hosts to use compatible policies where supported. Keep inference within a measured runtime budget.
- Include documentation, reproducible small training examples, and sample policies. Demonstrate real parameter/policy changes and a controlled learnable task with recorded improvement over its starting baseline. Do not require every training run to beat expert opponents; long-term strength depends on training and is not a completion promise.

The full Lab workflow must work at delivery: configure, train, checkpoint/resume, evaluate, save/load, and fight/spectate. Shipping an external research notebook alone is insufficient. Large future training experiments are optional; verified short training and the complete integrated tool are required.

## 12. Art, animation, graphics, audio, and tone

Use a cohesive cartoony 3D style inspired by Cage Rules, with original creature designs and a distinct game's identity. Create a brief art direction guide covering silhouettes, proportions, palettes, materials, animation, effects, typography, and UI. Finish a representative fighter and arena early to establish the quality target before scaling the roster.

Favor original art and editable source assets. Use reusable licensed assets where they help, especially mundane environment pieces, but bring everything into a consistent style. Preserve source masters, rigs, animations, textures, audio projects when available, and reproducible import/export steps. Procedural art is acceptable if it achieves the intended quality; unfinished primitives or inconsistent placeholder packs are not final presentation.

Implement glTF mesh/material/texture import or a validated import path through the selected engine, PBR-capable materials, soft shadows, SSAO or an equivalent ambient-occlusion implementation, and an internal HDR lighting/tonemapping pipeline. These should serve the stylized look and have scalable quality settings. HDR monitor output is not a separate required feature. Validate representative imports and finished scenes rather than checking only that renderer options exist.

Fighters need readable locomotion, attacks, ability execution, hit reactions, blocking/defense, knockdowns/recovery, and win/loss states appropriate to their anatomy. Effects must communicate range, timing, contact, element interactions, and outcomes without obscuring combat. Ensure arena boundaries, obstacles, and fighters remain legible in busy multiplayer scenes.

Include localized visible injury/damage feedback. Add modest silly cosmetic gore, such as exaggerated impacts or an end-of-fight detachable-piece effect, enabled by default. Keep it cosmetic: no required limb-dependent move sets, lasting mutilation mechanics, or changes to authoritative hitboxes/damage. Provide reduced/off settings and equivalent non-gory information. Avoid spending disproportionate effort on this minor feature.

Include original combat-sport satire, a memorable original announcer, and a small fictional performance-enhancement/drug theme. Use vulgarity only where it improves the humor. Keep the cartoony mature tone coherent. Avoid copied real-person voices, signature catchphrases, logos, or thinly renamed characters. An announcer inspired by the spectacle of fighting should have an original personality and lines.

Ship menu and combat music, impact/ability/creature sounds, UI feedback, ambient sound, and clear audio mixing. Use variations to reduce repetition, sensible transitions, controllable volume buses, and readable visual alternatives for essential cues. No missing-asset warnings, silent required cues, or clipping in normal play.

## 13. Menus, settings, accessibility, and onboarding

Create polished, consistent menus with deliberate hierarchy, typography, spacing, color, focus states, transitions, and useful explanations. Every displayed control must work. Controller focus must remain predictable through dialogs, tabs, errors, and returning screens. Support device hot-plugging and changing between controller and keyboard/mouse.

Include settings from the main menu and sensible in-game access. At minimum, implement the applicable controls below, with persistence, reset-to-default, validation, and immediate feedback or an explicit restart requirement:

- Display/graphics: resolution, window mode, display selection where supported, quality presets, frame limit, VSync, render scale where applicable, shadow/AO/effect quality, brightness, UI scale, and safe confirmation/rollback for disruptive display changes.
- Audio: master, music, effects, dialogue/announcer, mute/background behavior, and supported device selection.
- Input: rebinding, controller dead zones, sensitivity, inversion where applicable, vibration, button prompts, and appropriate hold/toggle choices.
- Accessibility/presentation: readable scalable text, subtitles for spoken information, color-independent cues, camera shake and flashing/motion reductions, gore controls, and assistance options that fit the combat design.
- Gameplay/system: difficulty, tutorial access, pause/suspend behavior, save/profile controls, useful diagnostics, and customization/preset management.
- Network/session: hosting/joining options, player limits, privacy/password where supported, content/mod compatibility, connection status, and understandable error messages.

Do not add irrelevant fake options to imitate a AAA settings menu. Keep defaults good enough to play immediately. At Steam Deck resolution, menus and gameplay information must be readable and controller-operable; label actual device testing separately from resolution/layout checks.

Give single-player users broad freedom to change rules, difficulty, assists, and builds. Clearly distinguish custom settings from standard progression/records where necessary; do not police harmless offline experimentation. Explain multiplayer restrictions and active server rules.

Include a short playable tutorial with current binding prompts, staged exercises, feedback, retry/skip/replay, and a practice environment. Teach movement, a basic attack, defense, an ability, and the next layer of depth without front-loading every advanced mechanic. Verify that an easy opponent and the tutorial support the intended naive play style.

## 14. Saves, profiles, and reliability

Single-player and local tools must work offline without a service login. Persist settings, profiles, campaign progress, suspended runs, challenge unlocks, custom presets/arenas, mod selections, and AI policies appropriately.

Use versioned formats, atomic writes/checkpoints, recovery/backups where appropriate, and migrations for supported changes. Test interrupted writes, invalid or damaged saves, updates, missing mods, removed content, and incompatible AI policies. Fail clearly and non-destructively. Do not silently reset progress or overwrite a recoverable save.

Define co-op persistence and per-player ownership consistently with section 8. Protect against duplicate rewards and invalid resume states. Separate user data from installed game files and support ordinary non-administrator accounts and paths with spaces/non-ASCII characters. Handle focus changes, suspend/resume where testable, controller disconnects, and orderly shutdown.

## 15. Modding as a supported product feature

Build a real local mod ecosystem with documented, stable extension points for creatures/abilities, balance/data, rules/modes, arenas, and appropriate presentation content. Choose data-driven definitions and scripting where useful. Arbitrary native-code plugins are not required for the baseline.

Provide versioned manifests/schemas, stable identifiers, dependency handling, deterministic load order, validation, actionable errors, and compatibility rules. Implement in-game discovery/enable/disable and profile/mod-set management. Explain when a restart or new run is required. Keep save compatibility and missing-mod recovery explicit.

Document the trust model for scripts and imported packages, including filesystem/network/native access, resource limits, and unsupported capabilities. Do not silently execute code downloaded from an arbitrary server. Validate paths, sizes, dependencies, and manifests. Require explicit user choice for risky capabilities, and keep ordinary data mods straightforward.

Multiplayer must compare relevant build/rules/content/mod versions and identify mismatches clearly. Implement a practical content-sharing/import workflow without depending on Workshop. Reject unsafe or incompatible packages instead of corrupting sessions. Document what is client-only versus required by the server and all players.

Ship runnable example mods, including a new ability or fighter customization and a new rule/mode or arena. Demonstrate packaged-game installation, UI management, actual gameplay, multiplayer compatibility, upgrade/removal behavior, and useful failure messages. Include step-by-step modder documentation and machine-readable schemas/examples that other agents can use.

Keep future Steam Workshop integration behind a documented service boundary. A working local ecosystem is mandatory now; actual Steam upload/subscription/download integration remains in the deferred commercial phase.

## 16. Provenance and commercial readiness

Create original names, creature designs, writing, UI identity, and audio. The inspirations explain desired qualities; they are not permission to copy protected characters, brands, or distinctive assets from unrelated games. Do not rely on renaming, parody labels, or avoiding a single mechanic as proof of legal clearance.

Maintain a third-party inventory with source URLs, creator, license/version, commercial use and redistribution terms, required notices, modifications, and where each asset/dependency is used. Include reused Cage Rules material and its third-party dependencies. Verify rights before inclusion; use a suitable alternative when rights are unclear. Do not purchase assets or subscribe to tools without separate authorization.

For generated assets, record the tool/source and applicable terms where available, and preserve editable source material. Prefer owned or suitably licensed assets in modding examples/source packages. Permission to include an asset in a compiled game does not automatically permit redistribution of its source in an SDK.

Provide credits and required notices. Record unresolved legal/platform-release considerations for my later commercial review. Do not present the release candidate as legally certified, Steam-approved, or independently cleared for sale.

## 17. Verification and quality gates

Use tests because they prove meaningful behavior, not to inflate counts. Keep checks reproducible and tie them to requirement IDs.

- Unit/property tests: damage, effects, resources, modifiers, rewards, progression, challenge unlocks, seeds/generation, rule validation, playlist selection, serialization/migrations, and AI observation/action contracts.
- Integration tests: complete campaign transitions, victory/defeat, co-op decisions and recovery, save/resume, actual mod loading, authored-arena play, policy training/loading, and hosted/dedicated networking.
- Runtime tests: packaged Windows launch with a fresh profile, tutorial, every mode, full campaign runs in both variants, both co-op formats, controller/menu navigation, sound/graphics, settings, and recoverable error flows.
- Multiplayer tests: independent clients and a headless server, chosen latency/jitter/loss profiles, disconnect/rejoin, incompatible content, round/playlist transitions, and authoritative outcomes. Loopback evidence must be labeled as such.
- Stability/performance tests: repeated matches, extended spectator/playlist operation, AI Lab resource limits, server soak, representative busy scenes, loading, memory/resource trends, and frame-time measurements. Choose and record durations/workloads early; run finite meaningful checks rather than an endless soak.
- Asset/content tests: missing references, import correctness, valid rigs/materials, mod/schema validation, safe spawns/bounds, available rewards/routes, and licenses/credits.

Use available game-native automation, replay/input injection, captures, and UI interaction to verify player-visible behavior. Inspect actual screenshots and motion/captures where possible. Report what was observed and how; a screenshot alone does not prove input or sound works. If a physical controller is unavailable, validate its binding/navigation path through supported simulated input and disclose the missing hardware check.

For AI learning, run a small reproducible experiment through each approach, verify saved-policy round trips and evaluation, and demonstrate learning on a controlled task. For combat quality, review representative fights, responsiveness, readable feedback, and basic versus deliberate strategies. Do not claim that bots or an agent's self-rating prove human fun.

Review significant changes independently when possible. Fix findings and add focused regressions. Before handoff, review the integrated game against the entire brief, including interactions among systems. Do not hide warnings, delete meaningful tests, mock away the feature under test, or reduce acceptance thresholds just to pass.

Missing non-Windows hardware, Steam access, final human playtesting, and commercial approval are handled by section 2. Known Windows failures that violate required acceptance criteria or block normal play, missing required gameplay, broken Linux-specific code discovered by checks, placeholders, and unimplemented local workflows are not permitted completion gaps. Disclosed minor issues may remain only when they do not violate required acceptance criteria or prevent normal use; do not reclassify a missing or broken requirement as a minor issue.

## 18. Milestones that preserve the whole scope

Use this order as a starting point, adapting dependencies intelligently:

1. Inspect the workspace and references, establish requirement IDs and content/performance targets, choose the engine, and prove the platform/physics/asset pipeline.
2. Establish a compelling physical combat slice with two distinctive fighters, one finished arena, controls, tutorial foundations, visual/audio feedback, and representative performance. Prove networking early, including hosted and dedicated matches.
3. Complete the shared campaign/run/save systems, both progression policies, hub exploration, and both co-op formats. Continue expanding the finished roster and content.
4. Integrate custom rules, bonus modes, playlists, dedicated-server operations, local mods, arena editing, and spectator/autobattler workflows. Build the AI Lab on the stable combat/observation contracts and verify real learning.
5. Finish all committed content, presentation, settings/accessibility, documentation, packaging, and platform configuration. Eliminate placeholders and incomplete player flows.
6. Perform the full integrated completion audit, correct failures, verify release artifacts, and deliver the release candidate.

These are progress gates, not alternative finish lines. Do not pause for approval after each milestone. Keep working through all of them unless an actual external blocker requires intervention. Parallelize after shared contracts are clear and preserve integration ownership.

## 19. Definition of done and final handoff

Mark the implementation goal complete only when all of the following are true:

1. Every required feature in this brief is integrated into the packaged game with its intended player-facing behavior. All recorded first-delivery content commitments and acceptance criteria are met.
2. A fresh Windows package launches and the full game can be exercised using documented controls without development tools or a service login. Dedicated-server and local authoring/training/modding workflows are delivered and usable.
3. Relevant automated checks, Windows runtime checks, networking checks, training demonstrations, performance checks, and integrated review have passed with current evidence. Known crashes, save corruption, progression softlocks, missing features, and other release-blocking defects have been fixed.
4. Linux game/server targets, portable code and dependencies, build instructions, and all feasible checks are complete. Any unavailable Linux/Deck build/device verification is specifically disclosed under the authorized allowance. Optional platform claims match actual evidence.
5. Finished assets/content are present, credits/provenance are recorded, and there are no placeholder-only required features, decorative nonfunctional menus, or undocumented workarounds needed to play.
6. Source, source assets where distributable, build/package scripts, tests, examples, and useful player/modder/server/AI Lab documentation are included. Git state and any external push limitation are accurately reported.
7. The final audit distinguishes verified requirements from the narrowly permitted external gaps. My future playtesting and Steam release approval are explicitly outside this completion gate.

Deliver a clear top-level README with launch/build/test instructions, the Windows distribution and server package, any other successfully produced builds, example mods/arenas/playlists/policies, and a final verification report. Include exact artifact paths, versions/revisions, commands/results, representative captures, performance context, and remaining issues with severity and reproduction steps.

Surface a concise requirement-by-requirement completion/evidence digest in the final conversation as well as saving the detailed report. Goal evaluators and I should be able to see what was actually proved. Do not merely announce that a checklist is green.

If a required item remains incomplete, keep working or report the specific genuine blocker and unfinished state. If only the expressly permitted external validation/commercial steps remain, deliver the release candidate and identify those follow-ups accurately. Do not keep the implementation goal open waiting for Steam enrollment, unavailable devices, or my subjective approval.

## 20. Start now

Read the brief in full, inspect the workspace and Cage Rules, establish the requirement ledger and a short implementation plan, and immediately begin the first concrete unit of work. Make and document the delegated design decisions. Continue through the full game and its completion audit.
