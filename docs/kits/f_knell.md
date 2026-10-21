# Knell - the Hollow Diver

Playable fighter eight in the local v0.9.15 preview. An empty deep-sea diving suit walks into the ring, its bronze helmet lit by a violet ghost. Knell uses the normal Critterweight control layout.

## The kit

120 health, 100 stamina, 75 poise, 2.9 m/s movement and 105% power. A deliberate close-range fighter whose weighted suit and spectral escape compensate for slower footwork. The regular light chain, heavy/charged heavy, dodge, grab, directional throws and JUICE finisher all remain available.

- **Ghost Light (ability 1):** send a slowly homing spectral flame toward the opponent. Base damage 9, buildup 35, 6-second cooldown. The orb travels at 6 m/s and lasts 2.2 seconds.
- **Through the Veil (ability 2):** phase 3.2 metres in the input direction after a short windup, with a brief invulnerable period. Reappearing sends a small spectral pulse (base damage 5, buildup 30). 9-second cooldown.
- **Last Bell (JUICE):** three expanding spectral pulses, each dealing base damage 6 and buildup 25, followed by six seconds of protection: 20% less damage and 25% less knockback.

On a controller, these are LB, RB and the existing JUICE binding; keyboard bindings and current glyphs are shown in the fighter sheet and HUD.

Spectral buildup applies **Haunted** for five seconds: cooldowns recover at 75% speed and healing is 20% weaker. Spectral is strong against Scrap and weak against Static, using the game's modest 15% matchup modifiers. Spectral plus Scrap triggers **Bell Ringer**; Spectral plus Brine triggers **Grave Chill**. These additions preserve the original six elements' relationships.

Campaign build directions:

- **Lantern Keeper:** longer-lived Ghost Light and greater Haunted buildup.
- **Deep Diver:** 20 additional health and reduced knockback.
- **Veil Walker:** shorter escape cooldown and a stronger emergence pulse.

## Movesets (v0.9.18)

In Movesets (the default combat style, `docs/design/MOVESET_COMBAT.md` §4) Knell fights with four of the eight moves of his pool on Move 1-4 (X / Y / LB / RB; J / K / Q / E). Classic is the v0.9.17 kit above, unchanged. Every move but the basic strike has a cooldown and a stamina cost; every hit of the new moves builds Haunted.

| Move | Category | Hold | How to use it | What it is for |
|---|---|---|---|---|
| **Sounding Jab** (basic) ★A ★B | strike | – | Sounding Jab, Port Hook, Deadweight, and the Rising Bell uppercut on the fourth press (a knockdown); Wake Breaker out of a dodge. No cooldown. | Always something to do up close. |
| **Anchor Fist** ★B | strike (heavy) | charge | Tap for the Anchor Fist (14); hold to wind up and release into the Deep Anchor (19, up to 60% more at full charge, 0.8 s). Cancels only when it lands. | The big punish once Hex Chain has dragged someone in. |
| **Ghost Light** ★A | projectile | – | The v0.9.17 lantern: 6 m/s, turns 65°/s for 2.2 s, 9 damage, 35 Haunted. 6 s, 12 stamina. | Pressure at range that makes the target move. |
| **Through the Veil** ★A | utility | – | The v0.9.17 escape: sinks out of the world for 0.3 s (untouchable), resurfaces 3.2 m along the stick in a 1.6 m pulse (5 damage, 30 Haunted). 9 s, 16 stamina. | Out of a corner or a beating; back to beam range. |
| **Night Shade** ★A | stream | sustain | Hold: a violet beam from the porthole, 5 m long and 0.7 m wide, for up to 2.2 s. It ticks every 0.12 s (1.5 damage, about 13 per second, 6 Haunted), slows whatever it touches to 70%, drains 11 stamina per second and makes a guard in it lose stamina 2.5 times as fast. The stick steers it at 1.8 rad/s; with the stick neutral it tracks the target. 7 s, 6 stamina. | Holding a lane at range: slow, Haunt and wear down whoever stands in it. |
| **Hex Chain** ★B | control | – | A chain thrown at the target (16 m/s, 6.4 m): 4 damage, a 0.45 s catch, a yank of about two metres toward Knell, then Hexed for 2.5 s (speed ×0.6, dodges ×0.6). Parryable. 9 s, 10 stamina. | Pulling a runner or a zoner into fist range and keeping them there. |
| **Lantern Swarm** ★B | volley | – | Three wisps pour out of the gauge on his chest in an 84° fan and home in (140°/s) from three sides: 4.5 damage and 18 Haunted each, 6 m/s for 2.2 s. Parryable. 8 s, 10 stamina. | Pressure while closing in; hard to sidestep. |
| **Toll** | counter | – | Knell claps his bronze gauntlets over his helmet (0.2 s) and the suit tolls: his elemental statuses and build-up are shaken off, then for 1 s he stands armoured in the echo (no stagger, knockback ×0.4) and the first melee hit sets off a counter-shock: 9 damage, 5.5 knockback, a 0.5 s stun, 30 Haunted. 10 s, 10 stamina. | The answer to rushdown and to status pressure (Sizzle, Soaked, Gunked). |

**Loadouts.** **A "Lamplighter"** (the default): Sounding Jab, Night Shade, Ghost Light, Through the Veil. Lantern and beam at range: the beam holds a lane and slows whoever walks into it, the lantern makes them move, and the Veil gets him out when someone gets close. Good against slow brawlers and in open cages. **B "Undertow"**: Sounding Jab, Anchor Fist, Hex Chain, Lantern Swarm. Chain them in, then the anchor: the wisps and the chain bring the target to him, the hex stops it walking or dodging away, and the Deep Anchor lands. Good against runners and zoners. Toll is in neither build: swap it in against rushdown and status-heavy fighters.

**Styles** (a drill picks one per move, for the run or career):

| Move | Style | Style |
|---|---|---|
| Sounding Jab | *Deep Sounding*: every punch builds half again as much Haunted | *Undertow Hook*: the Deadweight pulls the target in instead of knocking it away, so the Rising Bell stays in reach |
| Anchor Fist | *Lead Weight*: the Deep Anchor knocks down | *Diver's Brace*: both swings shrug off light hits |
| Ghost Light | *Long Wick*: burns 4.4 s and turns 95°/s | *Grave Lantern*: bursts where it ends (1.4 m, 3 damage, 20 Haunted) |
| Through the Veil | *Long Haul*: travels 5 m | *Riptide*: a 2.2 m pulse that drags fighters toward Knell |
| Night Shade | *Deep Lamp*: 7 m long and 0.45 m wide, turning at 1.3 rad/s | *Undertow Beam*: drags what it touches toward Knell |
| Hex Chain | *Shackle*: no yank, but Hexed for 3.5 s at 45% speed | *Grave Haul*: a 4.8 m chain with a much harder yank and a 0.65 s catch |
| Lantern Swarm | *Corpse Candles*: five weaker wisps in a 110° fan | *Ward Lights*: slower, longer-lived wisps that snuff out the enemy projectiles they touch |
| Toll | *Great Bell*: the counter-shock knocks down and builds twice the Haunted | *Sanctuary Bell*: the toll also heals 8, but the echo lasts 0.5 s |

**Tips and counters.**

- Night Shade is narrow and turns slowly: step (or dodge) sideways across it instead of backing away down its length, or get inside a metre of Knell where it cannot follow you. Guarding it only bleeds stamina.
- Hex Chain is a projectile: sidestep it in flight, guard it (no hex and a weak yank) or parry it (Knell is stunned). A missed cast leaves him hauling in nothing for half a second.
- Toll only answers melee: grapple him (grapples beat counters), wait the second out, or hit him from range. Lantern wisps converge, so a dodge as they arrive makes them overshoot.

**Effects** (`game/src/view/fx/moves/f_knell.gd`, all vfx names prefixed `knell_`): Night Shade is a violet searchlight out of the porthole that reaches its length (dipping onto a short fighter standing in it), breathes slowly, sheds motes, wisps and grave-mist, and shows its true floor band now and then; it goes out on release or when Knell is cut off. Hex Chain coils light around the casting arm, flies as a spinning barb on a banded chain from his left hand, and on a bite becomes a sagging tether with a sigil turning under the catch for as long as the hex lasts. Lantern Swarm lights the chest gauge, and its wisps are small lantern flames with pale cores that gutter out where they end. Toll swings a ghost bell over the helmet with bronze glints where the gauntlets meet and rings of sound on the floor; its echo pulses until the counter-shock breaks it in a cone of the bell's force. Every effect is anchored to a body point (porthole, gauge, gauntlets), so it stays on Knell when size matching lowers his poses against a short opponent. Particle amounts follow the Effects quality and flashes dim under Reduce flashing.

**Engine notes.** Hex Chain's drag is the bite's knockback toward Knell (one yank) plus the Hexed slow: the engine has no tether that keeps pulling one target. The counter-shock names its move in its own data (`"pool": "toll"`), because `counter_stance` does not pass the move's attribution on to its counter hit.

Tests: `game/src/test/kits/test_moves_knell.gd` (pool and loadouts, every style patch, one duel per new move, the carried-over moves and Classic, styles that change play, and the effects kit headless).

## Art and verification

Original procedural model: `tools/forge/defs/creatures/f_knell.js`; rebuild it with `node tools/forge/forge.js f_knell`. The gameplay definition is `game/content/core/creatures/f_knell.json`. The concept, mesh, materials and Spectral icon were created for this fighter; no external model or texture was downloaded.

`test_new_fighters` covers the model's segment bindings, regular melee hits, homing projectile damage, blink displacement, all three bell pulses, protective status, campaign technique composition, statuses and a real bot bout. Physical controller feel, rendered in-game appearance and competitive balance remain for owner playtesting.
