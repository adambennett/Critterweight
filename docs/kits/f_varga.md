# Varga - the Cage Rules Guest

Playable fighter seven in the local v0.9.15 preview. Scrap is Critterweight's martial-combat element. Varga imports Jeremy's original procedural human fighter, face, gloves, body rig and standing strike definitions from Cage Rules. He deliberately has a different control layout from the original roster.

## The kit

110 health, 105 stamina, 60 poise, 3.4 m/s movement. Forward/back movement closes or opens distance to the selected opponent; sideways input circles them. X / D-pad left switches orthodox and southpaw stance. There are four limb buttons and three held strike modifiers. The 18 original strike definitions supply the combinations in both stances, including lead/rear teep and knee variants.

- **No modifier:** left/right uppercut; lead-leg teep; rear-leg knee.
- **Hooks modifier:** left/right hook; left/right body kick.
- **Straights modifier:** left/right straight; left/right head kick.
- **Overhands modifier:** left/right overhand; left/right low kick.

Hold the modifier before pressing a limb. There is no standard charged-heavy input or automatic JUICE finisher on this fighter. Each limb press selects a particular move; the buffer remembers its modifier.

## Keyboard

- **U / I / J / K:** left hand / right hand / left leg / right leg.
- **Q / E / R:** Hooks / Straights / Overhands modifiers.
- **L** (or semicolon): Guard. Hold R with Guard for the low shell; double-tap Guard to shove.
- **Shift:** slip/dodge. **Space:** grapple. **X:** switch stance. **O:** check a low kick.
- **F1 / F2:** Cut the Angle / Second Wind. **Release V:** JUICE.
- **Tab:** switch target. **G:** tag partner. **T:** touch-gloves taunt.

Movement remains WASD. For example, hold E and tap U for a jab; hold E and tap K for a right head kick in orthodox stance. Bindings are editable independently of the standard fighter layout in Settings.

## Controller

- **X / Y / A / B:** left hand / right hand / left leg / right leg.
- **LB / RB / LT:** Hooks / Straights / Overhands modifiers.
- **RT:** Guard. RT + LT is the low shell. Double-tap RT to shove.
- **Right-stick click:** slip/dodge. **Left-stick click:** grapple.
- **D-pad left:** switch stance. **D-pad down:** check.
- **D-pad up / right:** ability 1 / ability 2. **Release View/Share:** JUICE.
- **View + D-pad left / down / up:** switch target / tag partner / taunt. These chords suppress the ordinary D-pad action and JUICE release.

The left stick supplies movement. In Cannery sparring, **View + RT** returns to the Cannery (keyboard V + L). This chord also suppresses JUICE. Start retains the normal pause menu.

## Abilities

- **Cut the Angle:** a short stick-directed evasive step, with a brief invulnerable window and +18% damage for two seconds. 7-second cooldown; 12 stamina. Follow it with a strike.
- **Second Wind:** double stamina regeneration and 50% more poise regeneration for four seconds. 15-second cooldown. It does not heal health.
- **Championship Rounds (JUICE):** seven seconds of faster attacks, +20% damage and +50% stamina regeneration, plus a small opening Scrap pulse. Uses the normal full Hype meter.

Scrap buildup applies **Rattled** for four seconds: guarding costs 25% more stamina and poise regenerates at 65% speed. Scrap is strong against Grit and weak against Spectral, using the game's modest 15% matchup modifiers. Scrap plus Spectral triggers **Bell Ringer**; Scrap plus Grit triggers **Crack Guard**.

Campaign build directions: **Pocket Technician** (attack speed and stamina recovery), **Cage Wrestler** (throws and poise), **Counter Specialist** (parry timing and Cut the Angle). Each has two working techniques.

## What the engine adaptation preserves

The source fighter's mesh, limb choices, modifier scheme, strike poses/timing/costs, opponent-relative footwork, high/low guard, checks, slips and stance switching are carried into the authoritative Critterweight simulation. Source files and hashes are retained under `tools/cage_rules/source`.

Grappling uses Critterweight's multiplayer-safe clinch, pummel and directional-throw rules: grapple to catch, press limb buttons to pummel, then grapple plus a direction to throw. The original ground-position and submission simulation is not included. Damage, reach, retargeting and several leg/arm poses are adapted for the differently sized creature roster and Jolt's 120 Hz rig, rather than running Jeremy's separate physics engine.

Network protocol 6 carries the additional inputs. All players in a network match need this preview or a compatible later build.

## Verification

`test_new_fighters` covers both stances, every limb/modifier combination, actual physical hits and recovery, guard exceptions, live input isolation, View chords, tutorial inputs, all abilities, campaign upgrades and expanded network samples. Model inspection renders use poses exported from the actual headless rig. Graphical in-game appearance, physical controller feel and competitive balance remain for owner playtesting.
