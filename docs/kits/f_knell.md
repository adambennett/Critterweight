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

## Art and verification

Original procedural model: `tools/forge/defs/creatures/f_knell.js`; rebuild it with `node tools/forge/forge.js f_knell`. The gameplay definition is `game/content/core/creatures/f_knell.json`. The concept, mesh, materials and Spectral icon were created for this fighter; no external model or texture was downloaded.

`test_new_fighters` covers the model's segment bindings, regular melee hits, homing projectile damage, blink displacement, all three bell pulses, protective status, campaign technique composition, statuses and a real bot bout. Physical controller feel, rendered in-game appearance and competitive balance remain for owner playtesting.
