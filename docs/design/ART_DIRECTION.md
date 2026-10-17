# CRITTERWEIGHT — Art Direction

A cohesive cartoony 3D style for a physical, readable, slightly grubby combat sport. The reference project's feel (chunky active ragdolls, soft stylized lighting, a cage that looks like a cage) is the starting point; the identity is ours: harbor rust, sponsor neon, and six critters you can tell apart from the cheap seats.

## 1. Style statement

**"Saturday-morning cartoon shot with sports-broadcast lighting."** Chunky, rounded shapes; strong silhouettes; stylized PBR with a soft rim light; one-color-per-fighter identity; desaturated environments so the fighters and effects own the saturation. Grit, not grime: rust and stains are painted decals with clean edges, never noise textures.

## 2. Silhouettes and proportions

| Rule | Spec |
|---|---|
| Thumbnail test | Every fighter must be identifiable as a 48 px black silhouette. Roster shapes: barrel (Stoke), anvil (Dredge), T (Gusto), wedge (Dozer), question mark (Slurry), ball-with-ears (Jitters). |
| Proportions | Heads and weapon points are **oversized** (+15–25% over realistic) so contact reads. Hands/claws/horns/beaks are the biggest "unit" on the body after the torso. Legs are short on heavy plans (biped, quadruped, crab) and long on light plans (avian). |
| Segment visibility | Ragdoll segments are visually distinct volumes (a visible joint crease, a color break, or a strap) so a limp ragdoll looks like a cartoon ragdoll, not a broken doll. |
| Rounding | Minimum edge radius 2 cm at fighter scale; no knife edges except Gusto's wing feathers (which are the point). |
| Scale cues | Each fighter carries one human-scale object (Stoke's wraps, Dredge's chain, Dozer's headlamp, Slurry's pipe collars, Jitters' battery cap, Gusto's shin tape) so size reads against the cage. |
| NPC/minion | Scraplings are deliberately low-detail (6 colors, flat shading tier) so a crowd of 16 stays readable. |

The creature revamp keeps these silhouettes inside the existing collision bodies. Expressive eyes,
clean colour boundaries and fitted plates replace swollen junctions; concepts do not authorize larger
heads, fists or wings than their hit volumes. Fine facial details share the toon effects but omit the
inflated outline pass, so outlines describe the silhouette instead of obscuring the face.

## 3. Palettes

### 3.1 Global

| Role | Hex | Use |
|---|---|---|
| Canvas / floor | `#E9E2CF` | The Gullet floor; the neutral everything sits on |
| Cage steel | `#5B6168` | Fences, posts, trusses |
| Rust | `#8C3B2B` | Accents everywhere; never on a fighter's primary |
| Glandco green | `#8BD426` | JUICE, sponsor, the hub's neon; also Sludge's hue (intentional: Glandco *is* sludge) |
| Circuit gold | `#C9A227` | Belts, title night, UI highlights |
| Night rim | `#35C1C9` | Rim light in night arenas and the main menu |
| Warm key | `#FFD9A0` | Key light in day/indoor arenas |
| Shadow tint | `#2B2F3A` | Shadows are cool, never black |

### 3.2 Element colors (ELEMENTS.md §1)

Scorch `#FF6B2B` · Brine `#2E9BE0` · Static `#F7E04A` · Sludge `#8BD426` · Grit `#B8905E` · Gale `#CFF4F2` (outline `#4FB3B8`). These are reserved: environments use them only for hazards and zones.

### 3.3 Fighter palettes (ROSTER.md)

Each fighter has a **primary** (60% of surface), **secondary** (30%), **accent** (10%, usually the element glow), and a **team tint** slot (a 10% stripe/band that takes team color in team modes: Team A `#FF5A5A`, Team B `#4DA3FF`, Team C `#FFC43D`, Team D `#B06BFF`).

| Fighter | Primary | Secondary | Accent |
|---|---|---|---|
| Stoke | `#D9532B` | `#3A3A42` | `#FF7A1A` |
| Dredge | `#8C3B2B` | `#B9B3A6` | `#2E9BE0` (barnacle glow) |
| Gusto | `#F2F2EC` | `#7FA4B8` | `#FF8A3D` |
| Dozer | `#6E6A66` | `#C7A160` | `#FFE066` |
| Slurry | `#2A2F2E` | `#C7E66B` | `#E04FB0` |
| Jitters | `#BDEFFF` | `#B59CE0` | `#FFF27A` |

Rule: no two fighters share a primary hue family; Stoke (orange-red) and Dredge (rust-red) are the closest and are separated by value (Dredge is darker and desaturated) and shape.

## 4. Materials (stylized PBR)

| Material class | Albedo | Roughness | Extras |
|---|---|---|---|
| Skin/hide | flat color + 2-tone painted shading (AO baked, no noise) | 0.6–0.8 | Soft **rim light** (Fresnel, 0.25 strength, tinted by the arena rim) on everything organic |
| Chitin/plates | flat + edge highlight | 0.35 | Slight clearcoat on Dredge/Snappington |
| Metal (iron, steel, chain) | `#3A3A42`–`#9FA6AD` | 0.4–0.5, metallic 1 | Painted chips as decals |
| Jelly (Jitters, Blisters) | translucent, 60% alpha | 0.15 | Inner emissive coil; fake subsurface via a wrap-lighting term; no real refraction (performance) |
| Cloth (wraps, tape, Kid's hoodie) | flat | 0.9 | Stitch decals |
| Emissive accents | element color | — | Intensity drives from Hype (0.3 at 0 Hype → 1.0 at 100) on each fighter's "Hype feature" (crest smoke, barnacle glow, coil, headlamp, drip rate, feather sheen) |
| Floors | desaturated, low-frequency gradients | 0.7 | Decal layer for stains, logos, hazard footprints |

Revamp implementation: vertex colours provide all albedo and glow masks. Jitters uses an opaque painted
jelly window and a fitted luminous coil; there is no transparency sorting or refraction cost. The existing
shared creature shader retains its toon ramp, rim, Hype, JUICE, flash, status and bruise effects.

Lighting: one key, one fill (sky), one rim per arena; **soft shadows** (PCF 3×3 at the Deck preset, 5×5 at high); SSAO at 0.6 intensity (scalable to off); HDR with a filmic tonemap and a slight warm lift. The look must survive the lowest preset: everything that matters is albedo + silhouette, not lighting.

## 5. Animation principles for active ragdolls

| Principle | How it applies to PD-driven bodies |
|---|---|
| **Anticipation** | Every attack's target-pose sequence begins with a 2–4 frame counter-motion away from the strike (chamber, rear, dip). Authored into the effector path as the first waypoint. Heavies anticipate ≥ 0.25 s; Lights 0.08–0.12 s. |
| **Readable wind-ups** | The wind-up pose is held at the end of startup for ≥ 1 frame at the extreme (hand at the top of the loop, snout at the floor) so the eye catches it. Bosses hold 0.3 s+. |
| **Follow-through** | Effector paths overshoot the contact point by 10–15% and the recovery pose returns via a curved path, so misses look committed. |
| **Squash and stretch** | Cosmetic only, on the visual mesh: 8% squash on landings/impacts, 5% stretch on leaps; the physics segments never scale. |
| **Secondary motion** | Tails, crests, chains, wraps, feathers are light physics chains (2–4 segments) or spring bones with low mass; they never affect hits. |
| **Hit reactions** | Driven by physics (the shove), plus a 0.1 s "flinch" target pose toward the hit so the face/head reads the impact. |
| **Knockdown** | Muscles cut over 0.15 s (not instantly) so the collapse has a beat; wake-up blends gains back in over 0.4 s with a "shake it off" head motion. |
| **Idle personality** | Each fighter has a 3–5 s idle loop built as target poses (ROSTER.md idle notes), with a 10% random jitter so a row of four is never synchronized. |
| **Gait** | Procedural, but with authored "style" parameters: Stoke bounces (step height 0.12 m, cadence 2.6 Hz), Dredge glides sideways, Gusto struts (exaggerated knee lift), Dozer trots heavy (cadence 2.0 Hz, body bob 0.05 m), Slurry undulates (wave amplitude 0.15 m), Jitters hops (arc 0.4 m). |

## 6. VFX language per element (shape + color; must read without color)

| Element | Primitive shape language | Particle behavior | Status overlay on the body | Zone floor pattern |
|---|---|---|---|---|
| **Scorch** | Tall pointed tongues, upward tapering | Rises, flickers, sparks | Ember motes drifting up; darkening patches | Radial "licks" from the center, hatched with rising ticks |
| **Brine** | Rounded crests and droplets | Falls, splashes, ripples outward | Drip streaks downward; glossy sheen | Concentric ripple rings |
| **Static** | Angular zigzags, right angles | Instant, jittering, snaps between points | Arc lines crawling over the body; limbs twitch | Lightning-fork lines in a radial burst |
| **Sludge** | Lumpy blobs with drips | Sags, stretches, pops bubbles | Dripping green mass hanging off the lower body | Blobby outline with bubbles |
| **Grit** | Hexagonal chunks and angular grains | Tumbles, settles, puffs | Dust caked on the limbs; cracked-clay decals | Hex-cell cracks |
| **Gale** | Spirals and streaks | Swirls, carries, dissipates | Ruffled fur/feathers; breath puffs; motion streaks | Spiral swirl lines |

Every element VFX uses **one shape** at three scales: small (per hit), medium (status trigger), large (reaction/JUICE). Reactions combine both parents' shapes for 0.4 s and print the reaction name (ELEMENTS.md §3).

## 7. Impact and hit-flash rules

| Event | Visual |
|---|---|
| Light hit | 2-frame white flash on the struck segment, a 0.2 m star-burst sprite at the contact point (shape: 4-point), a 0.1 m radial dust puff; camera: none |
| Heavy hit | 3-frame flash, 0.4 m 6-point burst, slow-mo 0.08 s (optional setting), camera shake 0.15 (scalable to off), a "hit line" streak along the weapon's path |
| Guarded hit | Blue-grey 0.3 m shield ripple at the contact, no flash on the body, a small "chip" number |
| Parry | A 0.5 m ring expands from the contact point in white→gold; 0.12 s freeze; the attacker's segment flashes red |
| Knockdown | 0.6 m ground dust ring, 2 dust puffs, a "DOWN" word pop (also subtitle-safe) |
| Status trigger | The element's medium VFX wraps the body for 0.4 s, status icon pops in on the nameplate |
| Reaction | Both parent shapes collide at the point for 0.4 s, reaction name in the element's font treatment |
| JUICE activation | Screen rim tint in the fighter's accent for 1 s, 3 m ring, the fighter's Hype feature goes to max emissive, the crowd silhouettes jump |
| KO | 0.3 s freeze, a wide burst, confetti (Title Night), the **detachable piece** pops with a 2-point sparkle and bounces as a cosmetic rigid body (off/reduced gore settings swap it for a "star" burst with the same timing) |
| Damage numbers | Off by default; "Telemetry" setting shows them in Barlow Condensed 700 |

Readability: hit flashes are white (not element color) so a hit always reads the same; element identity comes from the burst shape and the trail.

## 8. UI style

| Aspect | Spec |
|---|---|
| Layout | Combat HUD: nameplate + HP (top-left/right for 1v1; stacked column on the left in FFA/co-op, each with the fighter's silhouette icon), stamina under HP, poise as a thin bar under stamina, Hype as a vertical can-shaped meter beside the nameplate, abilities as two rings bottom-right (cooldown sweep + stamina cost pip), JUICE as the RT prompt that lights up. Round timer top center. Status pips (icon + 2-letter code: SZ, SK, JL, GK, CK, WD) under the HP bar. |
| Colors | Background panels `#1A1D24` at 85% with a 2 px `#C9A227` edge on focused elements; text `#F2F2EC`; muted text `#9AA0AB`; danger `#FF5A5A`; success `#8BD426`; HP bars use fighter accent on a `#2B2F3A` trough; team modes tint nameplates by team. |
| Typography | **Barlow Condensed 900** for headers, numbers, fighter names (uppercase, tracking +2%); **Barlow Condensed 700** for HUD labels and damage numbers; **Barlow 400/600** for body text, menus, subtitles. Display face for the wordmark and title cards: **Bungee** (OFL) — chunky, sign-painter, reads at any size, used sparingly (title, "FIGHT!", "KO", round cards). All three are OFL-licensed; Barlow is already in the reference project's `lib/fonts`. |
| Subtitle style | Barlow 600, 28 px at 1080p (scales with UI scale), `#F2F2EC` on a `#1A1D24` 70% pill, speaker name in Barlow Condensed 700 in the speaker's color (Barnaby gold `#C9A227`, Granny `#B06BFF`, Needles `#8BD426`). |
| Menus | Diegetic flavor, functional structure: the main menu is a fight-night poster; campaign map is a corkboard fight card with pinned node cards and string; shops are Needles' price board; settings are a clipboard. Controller focus is a thick gold outline plus a 4% scale; focus never relies on color alone. |
| Iconography | Flat, 2 px outline, single-color glyphs in `#F2F2EC` with an optional element fill; every icon has a distinct silhouette (node types: fists / star fist / bubble / can / paw / ? / crate / belt). Status and element icons are the ELEMENTS.md shapes. Button prompts use the current device's glyph set. |
| Motion | 120–180 ms eases; "stamp" transitions (a card slams in with a 2-frame overshoot) for results; no parallax on the HUD. Reduced-motion setting removes stamps and shakes. |
| Deck legibility | Minimum text 18 px at 1280×800; HUD at 1280×800 uses the compact layout (abilities as pips, status codes only). |

## 9. Logo and wordmark

- **Wordmark**: "CRITTERWEIGHT" in Bungee, slightly arched, with the "W" drawn as two upturned claws. Two-color: `#F2F2EC` fill, `#C9A227` offset shadow (6 px at 1080p), on `#1A1D24`.
- **Mark**: a hexagonal "cage" badge (eight sides at larger sizes — The Gullet's shape) with a JUICE can silhouette crossed by a fist. Reads at 32 px as "cage + can".
- **Sub-brand**: "Glandco" is a fake corporate logo (a rounded square with a drop and a sparkle) used *inside* the world only; it never sits next to the game's wordmark on real marketing surfaces (keeps the satire in-fiction).
- **Title card animation**: the wordmark stamps in, the sequins on the "I" glint, a can falls past and clips the "T".

## 10. Readability in 4–8 fighter scenes

| Technique | Spec |
|---|---|
| Nameplates | Always on in 4+ fighter modes, with the fighter's silhouette icon and team tint; distance-fade to a dot at > 12 m |
| Outline | A 1.5 px silhouette outline in the team color (or white for the player) when a fighter is occluded by another fighter or a prop |
| Camera | 3–4 fighters: a framing camera that keeps all in view (min FOV 60°, max 85°); 5–8: the player's camera follows their fighter at a fixed 3.5 m distance with a soft lock-on; spectator uses the framing camera |
| VFX budget | Per-fighter VFX cap: 1 status overlay + 1 trail + bursts; reaction bursts are the only large effects; zones are floor decals (cheap) with sparse particles |
| Floor contrast | Floors are ≤ 35% saturation; zones ≥ 70%; hazards have permanent hatched footprints |
| Flash control | Max one screen flash per 0.5 s (JUICE/KO); the "flash reduction" setting replaces flashes with a 100 ms vignette pulse |
| Color-blind safety | Nothing is encoded by color alone: elements have shapes, statuses have codes, teams have tints *and* nameplate badges (A/B/C/D), hazards have hatching, the player's own fighter has a white chevron over the head |

## 11. Asset standards (for the pipeline)

| Item | Target |
|---|---|
| Fighter mesh | 6–12k triangles including the KO piece; at most one 1024² atlas if needed, VRAM-compressed on import (revamp uses none); exact body-segment bones, ≤ 4 influences per vertex (revamp uses at most 2) |
| Minion mesh | ≤ 2k triangles including the KO piece; revamp uses vertex colours, no texture |
| Boss mesh | ≤ 25k triangles including the KO piece; revamp uses vertex colours, no texture |
| Arena | ≤ 150k triangles total scene, props ≤ 3k each, crowd as billboarded silhouettes (3 rows, 2 anim frames) |
| Source masters | Compressed editable `.blend` plus reproducible GLB exporter for adopted models; original forge definitions for retained models. Import the original GLB to preserve exact segment pivots. Fighter motion comes from the existing simulation and move/pose data; no keyframed fighter animations are exported. |
| Icons | SVG masters, exported at 64/128/256 |
| Style check | Every new asset is screenshot against the "style wall" (one fighter, one Scrapling, The Gullet, the HUD) under the Deck preset before approval |
