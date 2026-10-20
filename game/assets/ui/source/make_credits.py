"""Writes game/assets/ui/credits.json (data for the credits screen) with full licence texts embedded,
so the notices ship inside the game even when raw .txt files are not exported.
Usage: python make_credits.py <game dir>"""
import json
import os
import sys

game = sys.argv[1]
fonts = os.path.join(game, "assets", "fonts")

def read(p):
    with open(p, "r", encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n").strip()

data = {
    "_doc": "Credits screen data (src/ui/screens/credits_screen.gd). Edit freely; 'notices' must keep every required licence text. Inventory: docs/THIRD_PARTY.md.",
    "title": "CRITTERWEIGHT",
    "tagline": "Eight over-juiced fighters. One cage. Zero regulations.",
    "sections": [
        {"heading": "Project lead", "lines": ["Adam Bennett"]},
        {"heading": "Design, engineering and art direction",
         "lines": ["Developed with AI-assisted tooling (Anthropic Claude) under the project lead's direction.",
                   "All names, characters, writing, UI and icons are original to this project."]},
        {"heading": "Reference project",
         "lines": ["Cage Rules, by Jeremy — its code, ideas and project-owned assets are reused with permission.",
                   "Varga adapts Jeremy's original fighter model, rig, standing poses and strike definitions.",
                   "The referee is Jeremy's original referee model and outfit, with his poses and ring positioning ported to Critterweight.",
                   "The Barlow typefaces came to this project through Cage Rules (their own OFL licence still applies)."]},
        {"heading": "Creature art (Blender revamp)",
         "lines": ["Creature models and concept direction assisted by OpenAI Codex (Astra), under the project lead's direction.",
                   "Made in Blender (Blender Foundation and contributors); concept references from OpenAI image generation.",
                   "Optional Blender MCP bridge by Siddharth Ahuja and contributors (MIT). Varga's guest model is credited under Reference project."]},
        {'heading': 'Campaign event art', 'lines': ["29 original event illustrations generated with OpenAI image_gen under the project lead's direction.", 'Art prompts and provenance are recorded in docs/evidence/art/events/prompts.json.']},
        {"heading": "Engine and middleware",
         "lines": ["Godot Engine 4.5.1 — godotengine.org — MIT License",
                   "Jolt Physics (built into Godot) — Jorrit Rouwe and contributors — MIT License",
                   "Godot's bundled libraries are listed with their licences under Notices."]},
        {"heading": "Typefaces",
         "lines": ["Barlow and Barlow Condensed — Jeremy Tribby — SIL Open Font License 1.1",
                   "Bungee — David Jonathan Ross — SIL Open Font License 1.1"]},
        {"heading": "Audio",
         "lines": ["Funkorama, Backbay Lounge, Furious Freak and Volatile Reaction — Kevin MacLeod (incompetech.com) — CC BY 4.0.",
                   "Kenney Impact Sounds, Interface Sounds, RPG Audio and Music Jingles — CC0 1.0.",
                   "OpenGameArt: Waterflow Sound by TyberiusGames; crowd ambience by StarNinjas; applause by eXpl0it3r — CC0 1.0.",
                   'Dialogue: BreezeBlue TTS 2, using Devon, Kendall and Coach Buck library voices selected by the project lead. Original game writing; paid-plan commercial-use outputs.',
                   "OpenGameArt music by MintoDog: eight loopable tracks — CC0 1.0."]},
        {"heading": "In-world thanks",
         "lines": ["The Gullet Bay Athletic Commission, for sanctioning absolutely everything.",
                   "Glandco, for the JUICE. Side effects not included in these credits."]},
    ],
    "notices": [
        {'title': 'BreezeBlue generated dialogue', 'license': 'Commercial-use generated outputs under an active paid subscription', 'source': 'https://breezeblue.ai/legal/terms', 'text': 'Original Critterweight dialogue generated on 2026-10-18 with BreezeBlue TTS 2 and library voices Devon, Kendall and Coach Buck. BreezeBlue Terms of Service, effective September 10, 2026, section 5: paid-subscription outputs may be used commercially; that permission survives cancellation. The outputs are not CC0 and this does not grant rights in Breeze models or voices. Generation text, voice IDs, instructions, hashes and budget evidence are retained in docs/audio/breeze/.'},
        {"title": "Barlow / Barlow Condensed", "license": "SIL Open Font License 1.1",
         "source": "https://github.com/jpt/barlow", "text": read(os.path.join(fonts, "OFL.txt"))},
        {"title": "Bungee", "license": "SIL Open Font License 1.1",
         "source": "https://github.com/djrrb/Bungee (via https://github.com/google/fonts/tree/main/ofl/bungee)",
         "text": read(os.path.join(fonts, "Bungee-OFL.txt"))},

        {"title": "Kevin MacLeod music", "license": "Creative Commons Attribution 4.0 International (CC BY 4.0)",
         "source": "https://incompetech.com/music/royalty-free/licenses/",
         "text": "Funkorama, Backbay Lounge, Furious Freak and Volatile Reaction by Kevin MacLeod (incompetech.com). Licensed under CC BY 4.0. Source: https://incompetech.com/music/royalty-free/licenses/. License: https://creativecommons.org/licenses/by/4.0/. The supplied MP3 recordings are used without editing; loop and playback gain are configured in game."},
        {"title": "MintoDog OpenGameArt music", "license": "Creative Commons Zero (CC0 1.0)",
         "source": "https://opengameart.org/content/sci-fi-puzzle-stage-select; https://opengameart.org/content/trance-boss-battle; https://opengameart.org/content/jazzy-battle-theme; https://opengameart.org/content/fairy-battles; https://opengameart.org/content/hard-battle-1; https://opengameart.org/content/hard-battle-2; https://opengameart.org/content/hard-boss-battle-1; https://opengameart.org/content/hard-boss-battle-2",
         "text": "Eight loopable music tracks by MintoDog, downloaded from the linked OpenGameArt pages. Each page marks its track CC0 1.0; no fee or attribution is required, and commercial redistribution is allowed. CC0 deed: https://creativecommons.org/publicdomain/zero/1.0/. Audio files are unedited; loop and playback gain are configured in game."},
        {"title": "Kenney audio packs", "license": "Creative Commons Zero (CC0 1.0)",
         "source": "https://kenney.nl/assets/impact-sounds; https://kenney.nl/assets/interface-sounds; https://kenney.nl/assets/rpg-audio; https://kenney.nl/assets/music-jingles",
         "text": "Selected clips from Kenney Impact Sounds, Interface Sounds, RPG Audio and Music Jingles. Each pack is marked Creative Commons Zero (CC0 1.0), which waives copyright and related rights to the extent permitted by law. License deed: https://creativecommons.org/publicdomain/zero/1.0/. Supplied clips are used without editing."},
        {"title": "Waterflow Sound", "license": "Creative Commons Zero (CC0 1.0)",
         "source": "https://opengameart.org/content/waterflow-sound",
         "text": "Waterflow Sound by TyberiusGames, OpenGameArt. CC0 1.0; attribution is not required. License deed: https://creativecommons.org/publicdomain/zero/1.0/. Supplied MP3 used without editing."},
        {"title": "Crowd Shouting/Speaking Ambience", "license": "Creative Commons Zero (CC0 1.0)",
         "source": "https://opengameart.org/content/crowd-shoutingspeaking-ambience",
         "text": "Crowd Shouting/Speaking Ambience by StarNinjas, OpenGameArt. CC0 1.0. License deed: https://creativecommons.org/publicdomain/zero/1.0/. Supplied OGG used without editing."},
        {"title": "Applause in a Large Hall or Church", "license": "Creative Commons Zero (CC0 1.0)",
         "source": "https://opengameart.org/content/applause-in-a-large-hall-or-church",
         "text": "Applause in a Large Hall or Church by eXpl0it3r, OpenGameArt. CC0 1.0. License deed: https://creativecommons.org/publicdomain/zero/1.0/. Supplied WAV used without editing."}

    ],
}

out = os.path.join(game, "assets", "ui", "credits.json")
with open(out, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, indent="\t", ensure_ascii=False)
    f.write("\n")
print("wrote", out)
