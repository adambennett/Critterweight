# Third-party inventory (PRV-02, PRV-04)

Every third-party asset, dependency and reused item that ships in CRITTERWEIGHT or is required to build it.
Each subsystem owner appends rows for what they add (source URL, creator, licence/version, commercial-use and
redistribution terms, required notices, modifications, where used). Created by the UI owner on 2026-10-15; rows below
were verified by that owner. This is a working inventory, **not** a legal clearance (see "Open items").

## Engine and middleware

| Item | Version | Source | Creator / copyright | Licence | Commercial use & redistribution | Required notices | Modifications | Where used |
|---|---|---|---|---|---|---|---|---|
| Godot Engine (editor, runtime, export templates) | 4.5.1-stable (official build, `f62fdbde1`) | https://godotengine.org · https://github.com/godotengine/godot | Juan Linietsky, Ariel Manzur (2007–2014); Godot Engine contributors (2014–present) | MIT (Expat) | Allowed, royalty-free; may redistribute binaries | Godot licence text **and** the licences of its bundled components (FreeType, HarfBuzz, ICU, ThorVG, Mbed TLS, SDL, …; Apache-2.0, BSD, Zlib, MPL-2.0, OFL, FTL, …) | None (official binaries/templates) | Whole game. In-game: Credits › Notices prints `Engine.get_license_text()`, the component list `Engine.get_copyright_info()` and every licence text `Engine.get_license_info()` from the running binary |
| Jolt Physics | as bundled in Godot 4.5.1 (`thirdparty/jolt_physics`) | https://github.com/jrouwe/JoltPhysics | Copyright 2021 Jorrit Rouwe | MIT (Expat) | Allowed | Included in Godot's component notices (shown in Credits › Notices) | None (engine module) | 3D physics (project setting `3d/physics_engine = "Jolt Physics"`) |

## Fonts

| Item | Version / files | Source | Creator / copyright | Licence | Commercial use & redistribution | Required notices | Modifications | Where used |
|---|---|---|---|---|---|---|---|---|
| Barlow, Barlow Condensed | `Barlow-400/600.woff2`, `BarlowCondensed-500/700/900.woff2` (WOFF2 web subsets) | Reused from the Cage Rules reference project (`MMAsim/lib/fonts`, byte-identical); upstream https://github.com/jpt/barlow | Copyright 2017 The Barlow Project Authors (Jeremy Tribby) | SIL Open Font License 1.1 (no Reserved Font Name declared) | Allowed: embed/bundle in commercial software; the fonts may not be sold on their own; derivatives stay OFL | Copyright + OFL text must accompany redistribution: `game/assets/fonts/OFL.txt`, embedded in `game/assets/ui/credits.json`, shown in Credits › Notices | None (Godot imports them into its font cache) | All UI text and the fight HUD |
| Bungee (Regular) | v2.000 (`Bungee-Regular.ttf`, SHA-256 `c4f5361ce120af3e6b9156d0bf379fa19cda2ea0cd18ac01fd99596c6bf66e3f`) | Downloaded 2026-10-15 from https://github.com/google/fonts/tree/main/ofl/bungee (raw files `Bungee-Regular.ttf`, `OFL.txt`; METADATA: upstream https://github.com/djrrb/Bungee commit `eb03cf69adab5094f6b84e95357789cdf3bfeb99`) | Copyright 2023 The Bungee Project Authors (David Jonathan Ross) | SIL Open Font License 1.1 (no Reserved Font Name declared) | Same as above | `game/assets/fonts/Bungee-OFL.txt`, embedded in `credits.json`, shown in Credits › Notices | None | Wordmark (title, main menu, credits), display title cards (results winner) |

## Imported audio replacements (v0.9.13)

Selected recordings under game/assets/audio/replacements/ are packaged with the game. All were downloaded without payment on 2026-10-17. Only the listed open licences are used; no paid track version is included.

| Item | Creator | Source | Licence and use | Changes / location |
|---|---|---|---|---|
| Funkorama, Backbay Lounge, Furious Freak, Volatile Reaction | Kevin MacLeod | [Incompetech](https://incompetech.com/music/royalty-free/licenses/) | CC BY 4.0; commercial use and redistribution are allowed with attribution. No fee paid. Required credit is in docs/CREDITS.md and in-game Credits. | Supplied MP3s used without editing; loop, gain and track mapping are configured in game. replacements/music/ |
| Impact Sounds | Kenney | [kenney.nl/assets/impact-sounds](https://kenney.nl/assets/impact-sounds) | CC0 1.0; no attribution required. | Selected impact and footstep OGGs used without editing. replacements/impact/, replacements/footsteps/; included pack notice: replacements/licenses/Kenney-Impact-Sounds-License.txt |
| Interface Sounds | Kenney | [kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds) | CC0 1.0; no attribution required. | Selected UI OGGs used without editing. replacements/interface/; included pack notice. |
| RPG Audio | Kenney | [kenney.nl/assets/rpg-audio](https://kenney.nl/assets/rpg-audio) | CC0 1.0; no attribution required. | Selected coin and book OGGs used without editing. replacements/rpg/; included pack notice. |
| Music Jingles | Kenney | [kenney.nl/assets/music-jingles](https://kenney.nl/assets/music-jingles) | CC0 1.0; no attribution required. | Two result stings used without editing. replacements/jingles/; included pack notice. |
| Waterflow Sound | TyberiusGames | [OpenGameArt](https://opengameart.org/content/waterflow-sound) | CC0 1.0; no attribution required. | Supplied MP3 used without editing as quiet dock ambience. replacements/water/ |
| Crowd Shouting/Speaking Ambience | StarNinjas | [OpenGameArt](https://opengameart.org/content/crowd-shoutingspeaking-ambience) | CC0 1.0; no attribution required. | Supplied OGG used without editing at low gain as a crowd bed. replacements/crowd/ |
| Applause in a Large Hall or Church | eXpl0it3r | [OpenGameArt](https://opengameart.org/content/applause-in-a-large-hall-or-church) | CC0 1.0; no attribution required. | Supplied WAV used without editing as a long crowd reaction. replacements/crowd/ |

CC0 deed: https://creativecommons.org/publicdomain/zero/1.0/. The exact files, SHA-256 hashes, licences and bank references are recorded in game/assets/audio/replacements/replacement-audio-inventory.json. Original creature calls and custom announcer/coach lines remain generated: the optional Kenney human-fighter pack does not preserve named creature identities or written lines. The Freesound crowd alternatives were not used because their download page required an account; public CC0 OpenGameArt clips were used instead.

## Reused from the Cage Rules reference project

The brief authorises reuse of Cage Rules code, ideas and project-owned assets. Reuse by the UI: **only the Barlow font
files above** (their own OFL licence applies; Cage Rules' permission does not change it). Cage Rules also bundles
`three.min.js`, `rapier3d-compat.js` and `peerjs.min.js`; the game uses none of them. Integration audit (2026-10-15): a
repository-wide search finds no other Cage Rules code, models, textures or audio — combat, art, audio, arenas, hub,
networking and the AI Lab were written for this project. Cage Rules informed the physical feel only (ideas, not files;
see D-003 and D-023..D-026 for where this game deliberately differs, e.g. 120 Hz instead of 240 Hz).

## Original assets made for this project (no third-party content)

| Item | Where | Notes |
|---|---|---|
| UI icon set (38 glyphs) and the six element icons | `game/assets/ui/icons/*.svg` | Hand-authored SVG paths following ELEMENTS.md / ART_DIRECTION; regenerate or edit via `game/assets/ui/source/make_icons.py` (Python 3 standard library only). Authored with AI assistance (Anthropic Claude) under the project lead's direction |
| Badge mark (cage + JUICE can + fist) | `game/assets/ui/logo_mark.svg` | Same tool/provenance |
| Wordmark rendering, controller/keyboard prompt glyphs, toggles, stat bars, clipboard frame | `game/src/ui/widgets/*.gd` | Drawn procedurally at runtime; no platform-supplied glyph art is used |
| Credits/notices data | `game/assets/ui/credits.json` | Built by `game/assets/ui/source/make_credits.py` from the OFL files above |
| Creature, boss, minion, hub-NPC and crowd models (`.glb`) | `game/assets/models/**` | Procedurally generated by our own tool `tools/forge` (Node.js, no dependencies) from editable definitions in `tools/forge/defs/**`; glTF `asset.generator` records the tool; rebuild with `node tools/forge/forge.js` (docs/ART_PIPELINE.md, D-012). No third-party meshes or textures |
| Arena, cage, crowd, hub and VFX visuals | `game/src/view/**`, `game/src/hub/view/**`, `*.gdshader` | Built at runtime from primitive meshes and our own shaders; arena layouts are JSON in `game/content/core/arenas` |
| Music, SFX, ambience, announcer/coach babble | `game/assets/audio/**` | Synthesized by our own tools `tools/audio` (scores, parametric SFX, grain banks) from editable sources in the repo; `node tools/audio/build.js --check` re-renders and verifies every committed file (docs/AUDIO.md, D-013). No samples, no TTS |
| Shipped AI policies | `game/content/core/policies/*.policy.json` | Trained locally by the in-game AI Lab (evolution strategies / behaviour cloning) on this game's simulation; training jobs and logs in `docs/evidence/lab` |
| Writing (announcer, coach, NPC, campaign, item text) | `game/content/**` | Original to this project, authored with AI assistance under the project lead's direction |

Build-time tooling used by the UI: Python 3 standard library (the two scripts above, not shipped). Screenshot
conversion for `docs/evidence/ui/` used Pillow on the developer machine (evidence only, not shipped, not required to
build).

## Open items for commercial review (not legal advice)

* **Platform names and button glyphs.** Settings offers "Xbox" and "PlayStation" prompt styles and the glyphs draw
  lettered/coloured face buttons and the ✕ ○ □ △ shapes procedurally. These identify third-party hardware; before a
  commercial (e.g. Steam) release, check each platform holder's trademark/guideline terms or switch to Steam Input /
  platform-provided glyphs.
* **Font licences.** Both families are OFL 1.1 without Reserved Font Names; the licence texts ship in-game. If fonts are
  ever subset or converted outside Godot, keep the original names only where the OFL allows.
* **Engine notices.** The in-game Notices tab reads the licence data from the running engine; if a custom engine build is
  ever used, re-check that its component list matches what ships.
* **Credits names.** `credits.json` credits the project lead by the name on the repository's commits; confirm before
  release.


## Creature revamp provenance (2026-10-16)

The art branch adds original editable Blender geometry under `tools/blender` and GLBs under
`game/assets/models/creatures`. `tools/blender/adopted.json` records source ownership; the original forge
continues to own the remaining models. This supersedes the all-forge inventory above only for adopted
models. No third-party meshes, textures, HDRIs, asset-library items or generated 3D services were used.

The **thirteen concept sheets for twelve creatures** in `docs/evidence/art/concepts/*-turnaround-v*.jpg` were generated with
Codex's built-in OpenAI `image_gen` on 2026-10-16. The underlying model identifier was not exposed.
Every exact prompt, output file, original PNG hash, date, tool/model disclosure and processing note is
in [`evidence/art/concepts/prompts.json`](evidence/art/concepts/prompts.json), with usage and terms described
in [ART_PIPELINE.md, section 8](ART_PIPELINE.md#8-generated-concept-provenance). Source PNGs are retained on B:;
committed copies are JPEG quality 86. These creature sheets are design references only and are not shipped as model textures. The separate v0.9.15 event artwork is documented below.
Applicable terms: https://openai.com/policies/terms-of-use/ and, where applicable to the account,
https://openai.com/policies/services-agreement/ (checked 2026-10-16). Output rights follow the applicable
agreement and law; output may not be unique. Designs and meshes were made for Critterweight under the
project lead's direction, without franchise or third-party character references.

Build-only tools: Blender **5.2.2 LTS** (Blender Foundation/contributors, GNU GPL; https://www.blender.org/about/license/)
and optional **mcp-for-blender 2.1.9** (Siddharth Ahuja/contributors, MIT;
https://github.com/ahujasid/mcp-for-blender, commit `7a0373ec9199183cb460068c4f96aed9c579fb4f`).
The bridge and its dependencies are local tools, not shipped or embedded in committed `.blend` files.
The bridge's optional asset/AI services and telemetry are disabled. Native MCP status reports add-on 1.8 / protocol 13. A local, non-shipping configuration stub supplies disabled telemetry because that optional module is absent from the source archive; no service credentials are present. Blender's own Python API is used by the original
model/export helpers. No additional Blender extensions or asset libraries were used.


## v0.9.15 event illustrations

All 29 campaign-event illustrations in `game/assets/art/events/` are original project assets generated
with Codex's built-in OpenAI image_gen tool on 2026-10-18. One image was generated per event; the tool
did not expose its underlying model identifier. Exact prompts, file sizes and SHA-256 hashes are in
`docs/evidence/art/events/prompts.json`. The original 1536x1024 PNGs are the shipped masters.
No third-party reference artwork was supplied to the generator. The owner's Slay the Spire screenshot
informed the functional arrangement of the UI, not the subject or artwork of these original scenes.
The OpenAI account's applicable service terms govern generated outputs (the terms references in the
concept-art section above apply); no claim of exclusive copyright or guaranteed uniqueness is made.

v0.9.15 restores the original synthesized crowd_murmur and crowd_cheer bank entries. The downloaded
CC0 crowd recordings remain in the asset inventory but are no longer wired to those entries.

The new campaign route icons and Compendium trash icon are original hand-authored SVG sources.


## v0.9.15 recorded dialogue (2026-10-18)

Original Critterweight script rendered through BreezeBlue's hosted `breeze-tts-2` model using
Devon (`voc_g53htd8kmjsj`), Kendall (`voc_j66xnnsxfeet`), and Coach Buck (`voc_b36c5rxpfuzb`).
The owner selected these voices, confirmed their existing subscription, and authorized up to
3,500 credits. See `docs/audio/breeze/plan.json`, `generation-ledger.jsonl`, and the final budget
record for exact text, instructions, voice/model IDs, timestamps, raw/processed SHA-256 hashes
and spending. Raw masters stay on B:; normalized mono PCM WAVs ship in `assets/audio/speech/`.
Processing trims excessive silence, adds short edge fades and adjusts level without pitch changes.

Terms checked 2026-10-18: https://breezeblue.ai/legal/terms (effective 2026-09-10), section 5.
Outputs generated while a paid subscription is active may be used commercially, including
public-library voices; permission survives subscription cancellation. The output-rights grant
does not cover the voice models or provider technology. These are commercially usable generated
outputs, not public-domain or CC0 assets. No voice model, API key or provider SDK ships.
