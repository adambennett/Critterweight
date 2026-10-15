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

## Reused from the Cage Rules reference project

The brief authorises reuse of Cage Rules code, ideas and project-owned assets. Reuse by the UI: **only the Barlow font
files above** (their own OFL licence applies; Cage Rules' permission does not change it). Cage Rules also bundles
`three.min.js`, `rapier3d-compat.js` and `peerjs.min.js`; the UI uses none of them. Other owners record their own reuse
here.

## Original assets made for this project (no third-party content)

| Item | Where | Notes |
|---|---|---|
| UI icon set (38 glyphs) and the six element icons | `game/assets/ui/icons/*.svg` | Hand-authored SVG paths following ELEMENTS.md / ART_DIRECTION; regenerate or edit via `game/assets/ui/source/make_icons.py` (Python 3 standard library only). Authored with AI assistance (Anthropic Claude) under the project lead's direction |
| Badge mark (cage + JUICE can + fist) | `game/assets/ui/logo_mark.svg` | Same tool/provenance |
| Wordmark rendering, controller/keyboard prompt glyphs, toggles, stat bars, clipboard frame | `game/src/ui/widgets/*.gd` | Drawn procedurally at runtime; no platform-supplied glyph art is used |
| Credits/notices data | `game/assets/ui/credits.json` | Built by `game/assets/ui/source/make_credits.py` from the OFL files above |

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
