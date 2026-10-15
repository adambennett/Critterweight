# Critterweight — player guide

Welcome to the Critterweight Circuit. This guide covers controls, the fighting basics, every way to play,
and where your data lives. Everything here is also in the game: the **Controls** screen (pause menu or
Settings › Controls) shows your live bindings, and **Tutorial** teaches the basics with Granny Haymaker.

## 1. Controls (defaults; rebind anything in Settings › Controls)

| Action | Xbox-style controller | Keyboard & mouse |
|---|---|---|
| Move | Left stick | W A S D / arrow keys |
| Light attack (tap three times = string) | X | J / left mouse |
| Heavy attack (hold to charge) | Y | K / right mouse |
| Guard (tap right before a hit = parry) | Left trigger | Shift / L |
| Dodge (+ direction; Light during it = dash attack) | A | Space |
| Grab / throw (+ direction to throw) | B | F / middle mouse |
| Ability 1 / Ability 2 | LB / RB | Q / E |
| JUICE (needs full Hype) | Right trigger | R |
| Taunt (fills Hype, risky) | D-pad up | T |
| Switch target | Right stick click | Tab |
| Tag partner (tag-team) | D-pad down | G |
| Nudge camera | Right stick left/right | Z / C |
| Pause | Menu | Esc |

Menus: left stick / D-pad move, A select, B back, LB/RB switch tabs, Y and X are shown on screen when a
screen uses them. The mouse can click everything. Hold/toggle guard, dead zones, sensitivity, inversion,
vibration and the button-prompt style are in Settings › Controls.

## 2. Fighting basics

- **Your body is real.** Hits land where a fist, claw, beak or tail actually touches, and harder when it is
  moving fast. Spacing and timing matter more than button speed.
- **Light** strings are fast and safe; **Heavy** hits hard and shrugs off light hits while winding up;
  **Heavy during a Light string** is your **Finisher**.
- **Guard** absorbs most damage but costs stamina; **parry** (guard just before impact) staggers the
  attacker and gives you a free moment. **Grabs beat guard**, strikes beat grabs, guard beats strikes.
- **Dodge** has a short invulnerable moment; press Light while dodging for a **dash attack**.
- **Stamina** (green bar) fuels everything; at low stamina your attacks slow down. **Poise** breaks into a
  knockdown if you keep getting hit. Getting up gives a short invulnerability.
- **Hype** (orange bar) fills as you hit, get hit, parry and taunt; at 100 press **JUICE** for your
  fighter's ultimate state.
- **Elements**: each fighter carries one of six elements (Scorch, Brine, Static, Sludge, Grit, Gale).
  Repeated elemental hits build up a status (shown under the health bar with its name); two statuses
  together trigger a **reaction**. Element zones on the floor (puddles, fires, gusts) affect anyone inside.
- **The cage**: slamming someone into the fence hurts extra (wall splat / cage slam). Some arenas have open
  edges — falling off costs health.

## 3. Ways to play

| Menu | What |
|---|---|
| Fight › Quick Fight / Versus | You against bots (up to 8 fighters, teams, any rules preset and arena) |
| Fight › Practice | A dummy that stands, guards, parries, counters, replays your recording, or fights; hit telemetry |
| Fight › Spectate | Bots only; auto-director camera, LB/RB follow a fighter, D-pad speed, Y free camera, X hide HUD |
| Tutorial | Ten short exercises with Granny Haymaker; retry, skip or replay any of them |
| Bonus modes (rules presets) | **Spotlight Hog** (hold the moving light), **Chumball** (knock the ball into the goal), **Absolute Unit** (KO the giant to become the giant), **Chum Rush** (co-op waves), **Tag Team** |
| Campaign | **Off the Street** (fresh runs, no permanent power) and **Fight Camp** (persistent upgrades, The Cannery hub), plus **The Bookie's Table** (watch AI fight your build); The Dosage difficulty ladder 1–10; co-op with friends |
| Online | Host a game, join by address or LAN, or connect to a dedicated server with playlists |
| Create › Rules | Make, test-play, save, share and import your own rules presets |
| Create › Arena | Build arenas from props, hazards and spawns; test-play and share them |
| AI Lab | Train your own fighter AI on your PC, evaluate it, then fight or watch it |
| Mods | Turn mods on/off, keep mod sets, import/share packages (data-only, they never run code) |

Records: custom rules and mods are allowed everywhere single-player; results played with them are marked
"custom" and kept separate from standard records. Online, everyone needs the same gameplay mods as the host.

## 4. Settings highlights

Display (resolution, window mode, monitor, frame limit, VSync, render scale/upscaler, UI scale; risky changes
revert after 15 s unless you keep them), Graphics presets including **Steam Deck**, Audio (master, music,
effects, voice, UI, ambience, mute when unfocused, output device), Accessibility (text size, subtitles and
size, colour-vision palettes, screen shake, flashing reduction, motion reduction, gore Full/Reduced/Off, game
speed and assists), Gameplay (difficulty, announcer level), Network, Diagnostics (FPS/net overlays, logs).

## 5. Your data

Everything you create is stored in your user folder (Windows `%APPDATA%\Critterweight`, Linux
`~/.local/share/Critterweight`): `profiles/` (profiles and settings), `presets/`, `arenas/`, `runs/`
(suspended campaign runs), `mods/`, `policies/` (AI Lab), `logs/`. Saves are written atomically with a
backup and a checksum; a damaged file is set aside (never deleted) and the newest good copy is used.
Start with `-- --safe-mode` if a mod setup ever gets in your way.
