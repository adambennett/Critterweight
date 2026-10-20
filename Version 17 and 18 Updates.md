# Critterweight: Version 17 and 18 Updates

Autonomously complete and publish two sequential Critterweight releases: first v0.9.17 with the commentary and fighter-art/VFX overhaul, then v0.9.18 with a major redesign of combat around customizable, beautifully animated creature movesets. Both versions must be playable, tested, and published on GitHub. Keep this goal active until BOTH releases are complete.

Work in `B:\git\Critterweight`. The GitHub repository is `adambennett/Critterweight`. Inspect the current checkout, remote, release state, and concurrent work before starting. Preserve the completed v0.9.16 features and unrelated work.

I authorize the full development and release process for BOTH versions: code, assets, necessary tooling changes, testing, commits, integration into main, pushes, annotated tags, and GitHub publication. Make routine design decisions autonomously. Ask only about genuine blockers you cannot resolve responsibly.

Read AGENTS.md and the relevant architecture, audio, art, campaign, networking, verification, and release documentation. Follow the established workflows and machine-load safeguards. Keep heavy assets, caches, captures, and builds on B:.

Release sequencing is mandatory:
1. Finish, test, publish, and verify v0.9.17.
2. Report that milestone and immediately continue into v0.9.18.
3. Finish, test, publish, and verify v0.9.18.
Do not delay v0.9.17 by folding the combat redesign into it. Do not stop the overall goal after publishing v0.9.17.

### Breeze authorization
I loaded the existing Breeze key with 10,000 credits. You may use up to that amount without further authorization for new recordings, auditions, and retakes. This is one total allowance across this instruction; it does not reset for v0.9.18.

Spend what is needed to complete the v0.9.17 commentary work properly. Any remaining allowance may support v0.9.18’s new combat terminology. Reuse recordings where appropriate. Keep release-specific generation plans, request journals, provenance, raw masters, processed assets, and spending reports. Reconcile uncertain requests before retrying. Use the existing secure key-loading workflow and approved voices. Shipped speech must work offline.

### FIRST: RELEASE v0.9.17

This version has two feature workstreams: commentary, and fighter art including ability VFX. Preserve gameplay mechanics in this release, except for necessary bug fixes.

### Commentary
- Improve both the selection logic and the recorded content. Audit what actually plays, what repeats, which recordings rarely get selected, and which situational lines are incorrectly treated as generic chatter.
- Retain bounded recent history across rematches, consecutive campaign bouts, and game restarts.
- Avoid repeated exact lines and repeated joke/topic families. Prefer eligible fresh alternatives without letting specificity trap selection in a tiny pool.
- Add enough purposeful recordings for frequent situations: openings, ordinary combat events, defensive successes, abilities/JUICE, momentum changes, round transitions, results, Career, judges, and referee events.
- Make calls describe the actual fight. Distinguish knockdowns, knockouts, referee stoppages, and decisions correctly.
- Improve priorities, interruption behavior, conversation pacing, and expiration of stale queued calls.
- Balance concise play-by-play, useful observations, personality, and breathing room. Keep the existing humor while making the commentators sound like they are following this particular match.
- Use varied natural deliveries and energy levels. Retake awkward joins, wrong pronunciations, flat or inappropriate performances, and technically defective audio.
- Preserve announcer settings, subtitles, correct speaker identification, dynamic bindings/names, and sensible fallback behavior.
- Do not solve repetition by making commentary largely disappear.

Compare baseline and revised behavior over a reproducible event sequence and at least ten consecutive ordinary bouts, including repeated matchups/rematches and Career/Cage Rules fights. Record actual playback selections and evaluate repetition, contextual accuracy, interruptions, and pacing.

### Fighter art
Give the entire current playable roster a substantial visual upgrade: Stoke, Dredge, Gusto, Dozer, Slurry, Jitters, Varga, and Knell. Verify the current roster at the start.

Improve forms, faces, recognizable details, materials, and overall finish. Add useful expressions and visual motion to features such as eyes, crests, coils, chains, and other signature details. Preserve the cohesive stylized identity while making the improvement obvious at normal gameplay distance.

You may establish the approach on representative pilots, then carry it through the full roster. Use editable source assets and reproducible exports. Extend the art pipeline, shaders, or view code when necessary. Inspect the result in Godot as well as in the authoring tools.

For v0.9.17, preserve combat timing, damage, reach, collision bodies, physics, stats, and authoritative outcomes. Maintain team identification, cosmetics, status feedback, and supported detachment behavior.

### Varga specifically
- Give him the same serious art attention as the rest of the cast.
- Make the upgraded appearance the default.
- Add a controller-accessible Settings option labeled “Legacy Varga skin”.
- Enabling it restores the actual original appearance from before this overhaul. Preserve that asset and its provenance.
- Persist the setting and apply it consistently in previews, Career, practice, spectating, local matches, and online presentation.
- It is a local cosmetic preference. Both skins use identical gameplay data.
- Ensure asset regeneration cannot overwrite either appearance accidentally.

### Ability VFX
Substantially improve the presentation of every fighter’s abilities and JUICE, plus relevant charged attacks, projectiles, ground effects, and elemental reactions.

Give effects purposeful preparation, motion, contact, and dissipation. Use distinctive shapes, particles, trails, modeled pieces, materials, and shader work where appropriate. Express each fighter’s identity: furnace pressure and ignition, tidal force, vortices, crushing debris, viscous sludge, electrical discharge, spectral motion, or precise martial impact.

A recolor or larger glow alone is insufficient. Keep attack timing and affected areas truthful, maintain visibility during crowded fights, respect quality/reduced-effects settings, and keep effects efficient.

Produce comparable before/after gameplay captures for every fighter and their abilities. Iterate on weak results. Spend the remainder of this release’s effort heavily on the art and VFX after commentary meets its requirements.

### Verify and publish v0.9.17
- Run appropriate focused tests and the required final integrated suite.
- Check recorded speech, commentary history and queues, Varga’s setting and persistence, both Varga appearances, every fighter’s effects, existing saves, and the v0.9.16 Career/judging/referee features.
- Review rendered gameplay and available audiovisual captures. Compilation and asset counts alone do not prove improvement.
- Compare matched performance at 1280×800 and 1920×1080, including crowded matches with simultaneous abilities.
- Build and test the packaged game.
- Update versioning, release notes, in-game patch notes, credits, provenance, requirements, and verification evidence.
- Publish the normal v0.9.17 GitHub prerelease with all required game/server packages, manifest, and checksums. Verify its tag, downloads, and uploaded hashes.

Once that release is fully published and verified, continue immediately.

### SECOND: DESIGN, IMPLEMENT, AND RELEASE v0.9.18

This is an intentional MAJOR COMBAT OVERHAUL.

I want Critterweight’s creature fighters to feel much more like fantastical Pokémon-style combatants. I want beautifully animated flamethrowers, poison darts, bubble streams, hydro cannons, electrical attacks, spectral techniques, and other distinctive moves.

The new combat experience must have actual movesets that players can customize throughout runs. The generic Attack / Heavy Attack / Grab loop should no longer define the default creature combat.

This authorizes changing combat architecture, move data, attack behavior, animation, resources, controls where necessary, progression, balance, and supporting systems. The gameplay-preservation restriction above applies to v0.9.17; it must not prevent the v0.9.18 redesign.

Keep the real-time physical cage-fighting identity. Build a coherent refreshed combat system around it.

Start by documenting a concrete combat design and a per-fighter moveset plan, then proceed with implementation autonomously. Decide and explain the equipped-slot structure, available move pools, resource model, targeting, defensive options, customization flow, and Varga’s advanced controls. Do not stop after producing the design.

### New movesets
- Replace the generic offensive loop with distinct named actions that genuinely differ in behavior, purpose, animation, and effects.
- Include differences such as sustained attacks, precision projectiles, spreading volleys, charged blasts, movement attacks, close-range techniques, counters, control moves, and support options.
- A flamethrower should behave like a sustained, aimable flame attack. Poison darts should behave like darts. A bubble stream should have its own motion and tactical purpose. A hydro cannon should communicate charge, recoil, force, and recovery.
- Coordinate the fighter’s body animation, emission points, projectiles, sound, impacts, and lingering effects. The result must be convincing in motion.
- Give every fighter a recognizable identity and enough learnable alternatives to support at least two meaningfully different builds.
- Make types materially affect move properties, interactions, and tactical choices.
- Keep meaningful positioning, counterplay, defensive responses, and resource decisions. Avoid a system where all moves are unavailable and the player has nothing useful to do.
- Use the upgraded v0.9.17 art as the foundation and extend it wherever the new moves need additional animation or effects.

### Controls
For the ordinary roster, preserve the approachable control philosophy: movement plus a small, readable set of direct move inputs. Use clear names, descriptions, controller glyphs, and HUD feedback. Most fighters should remain easy to pick up.

Varga is the deliberate exception. Reimagine him as a fantastical fighting-type martial artist while preserving the expressive depth inspired by Jeremy’s original control scheme: limb choices, modifiers, stance changes, and contextual combinations.

Give those inputs spectacular, purposeful techniques such as aura-charged palms, pressure-wave kicks, shockwave uppercuts, afterimage rushes, or other coherent fighting-type moves. Preserve his distinctive control depth rather than forcing him into the ordinary roster’s layout. Update his guide and tutorial accordingly.

The legacy Varga skin and Classic combat are independent:
- New appearance + new combat.
- Legacy appearance + new combat.
- New appearance + Classic combat.
- Legacy appearance + Classic combat.
All combinations must work.

### Moveset customization
- Let players learn, equip, replace, and improve moves through the existing run/campaign flows.
- Give choices real tradeoffs in function and playstyle, beyond numeric upgrades.
- Integrate move choices into appropriate rewards, training, shops, and between-fight preparation.
- Support the new system in Off the Street, Fight Camp, and Career according to their different progression structures.
- Provide a usable loadout configuration path for non-campaign play and practice.
- Persist learned/equipped moves correctly through saves, resuming, and multiplayer campaign state.
- Audit existing techniques, supplements, gym bonuses, and Career upgrades. Translate them into meaningful effects in the new system; old patches must not silently become no-ops.
- Preserve player progress through explicit, tested migrations.

### Rules Editor and Classic combat
Add a clear match rules setting that selects the new moveset combat or the preserved Classic combat.

ALL shipped built-in game types and presets must default to the new style in v0.9.18. Cover fresh versus setups, teams, tag, bonus modes, practice, spectating, campaigns, Career, Bookie fights, playlists, and dedicated-server defaults.

Classic combat must remain fully playable through the Rules Editor, with the pre-overhaul offensive mechanics and appropriate controls. Preserve the v0.9.17 visual/audio improvements where compatible.

Make this a real serialized and validated match rule that the server and all clients agree on. Do not implement it as a cosmetic client setting or a partial toggle that leaves half the old combat active.

Treat existing saved runs and user-authored presets deliberately. Preserve their progress and explicit choices; document and test how older files acquire a combat-style value. Newly created games using built-in defaults must use the new style.

### Whole-game integration
- Teach bots to use the new moves and choose appropriate ranges, resources, targets, and defenses.
- Make tutorials, practice tools, move descriptions, Compendium entries, HUD, rebinding, and controller navigation match the actual equipped moves.
- Preserve mode interactions such as ball pickup/throwing, tagging, reviving, and objective interactions when the old generic Grab input is repurposed.
- Update judging for channels, multi-hit moves, projectiles, and statuses so scores reflect actual combat rather than arbitrary hit-event frequency.
- Keep referee protection, counts, stoppages, and the unlimited-HP scoring option coherent with the new attacks.
- Integrate networking, authoritative hit/effect resolution, snapshots, content hashes, save schemas, and mod validation.
- Handle AI Lab/control-policy compatibility explicitly when the action model changes.
- Update commentary triggers so it describes the new moves and outcomes accurately. Reuse the v0.9.17 recordings and any remaining authorized Breeze allowance.

Do not leave the new style confined to a demonstration arena or two prototype fighters. Every playable fighter and built-in mode must support the finished system.

### Verify and publish v0.9.18
- Test the distinct move behaviors, equipped-loadout changes, resources, targeting, defenses, damage/status interactions, progression, and save migration.
- Exercise every fighter in both new and Classic combat, including Varga’s advanced inputs and both skins.
- Verify all built-in defaults select the new style and that explicitly selecting Classic works.
- Test bots, multiplayer, campaigns, judging/referees, and noncombat mode interactions.
- Review real rendered combat across the roster, including crowded projectile/effect-heavy situations.
- Compare performance against v0.9.17 and correct material regressions.
- Run the required integrated and packaged checks, then publish v0.9.18 through the normal GitHub release workflow.
- Verify the annotated tag, exact build source, playable Windows package, all required platform/server artifacts, manifest, checksums, and uploaded hashes.

## QUALITY AND COMPLETION

Use meaningful tests and honest evidence. Where the redesign intentionally supersedes old requirements, update the requirements and test the new behavior while preserving Classic coverage. Do not weaken tests merely to hide failures.

Review the actual visual and audio results using the available tools. Never claim physical-controller, listening, hardware, or external-network checks you did not perform. Record limitations accurately.

Follow the repository’s 0.9.x published-prerelease convention. Both releases must be published with downloads, not left as drafts. Existing release tags and assets must remain intact.

The overall goal is complete only when:
- v0.9.17 is released with the improved commentary, full-roster art/VFX pass, and persistent legacy Varga skin option.
- v0.9.18 is released with the fully integrated combat redesign, customizable movesets, simple controls for the ordinary roster, advanced fantastical Varga controls, new-style defaults across all built-in game types, and working Classic combat.
- Both releases have appropriate source, rendered, packaged, persistence, compatibility, and performance evidence.
- Both GitHub releases and their uploaded artifacts have been verified.

Report the v0.9.17 release milestone when it happens, then continue. At the end provide both release URLs and commits, playable build locations, the total Breeze spend, verification/performance results, representative comparison media, and a concise guide to the new combat and Classic option.

Keep the complete objective intact across turns. Make v0.9.17 look and sound sick, ship it, then make v0.9.18 feel like a genuinely new creature-combat game and ship that too.
