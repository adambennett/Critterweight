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
    "tagline": "Six over-juiced critters. One cage. Zero regulations.",
    "sections": [
        {"heading": "Project lead", "lines": ["Adam Bennett"]},
        {"heading": "Design, engineering and art direction",
         "lines": ["Developed with AI-assisted tooling (Anthropic Claude) under the project lead's direction.",
                   "All names, characters, writing, UI and icons are original to this project."]},
        {"heading": "Reference project",
         "lines": ["Cage Rules, by Jeremy — its code, ideas and project-owned assets are reused with permission.",
                   "The Barlow typefaces came to this project through Cage Rules (their own OFL licence still applies)."]},
        {"heading": "Engine and middleware",
         "lines": ["Godot Engine 4.5.1 — godotengine.org — MIT License",
                   "Jolt Physics (built into Godot) — Jorrit Rouwe and contributors — MIT License",
                   "Godot's bundled libraries are listed with their licences under Notices."]},
        {"heading": "Typefaces",
         "lines": ["Barlow and Barlow Condensed — Jeremy Tribby — SIL Open Font License 1.1",
                   "Bungee — David Jonathan Ross — SIL Open Font License 1.1"]},
        {"heading": "In-world thanks",
         "lines": ["The Gullet Bay Athletic Commission, for sanctioning absolutely everything.",
                   "Glandco, for the JUICE. Side effects not included in these credits."]},
    ],
    "notices": [
        {"title": "Barlow / Barlow Condensed", "license": "SIL Open Font License 1.1",
         "source": "https://github.com/jpt/barlow", "text": read(os.path.join(fonts, "OFL.txt"))},
        {"title": "Bungee", "license": "SIL Open Font License 1.1",
         "source": "https://github.com/djrrb/Bungee (via https://github.com/google/fonts/tree/main/ofl/bungee)",
         "text": read(os.path.join(fonts, "Bungee-OFL.txt"))},
    ],
}

out = os.path.join(game, "assets", "ui", "credits.json")
with open(out, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, indent="\t", ensure_ascii=False)
    f.write("\n")
print("wrote", out)
