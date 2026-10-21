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

## Movesets (v0.9.18)

In Movesets (the default `combat` rule) Varga is still the fighter with the deep controls: the limb, the held modifier and the stance choose every strike, exactly as above. What changes is what the strikes *are*: each modifier group carries a fighting-type **technique** of gold aura, four **contextual combinations** answer what is happening in the fight, and his plain strikes flare with aura. Classic (`combat: classic`) is the v0.9.17 Varga, unchanged. The Legacy Varga skin is only a skin: both models play the same in both styles.

### Controls

| Input (controller / keyboard) | Classic | Movesets |
|---|---|---|
| Hand, no modifier (X, Y / U, I) | lead / rear uppercut | **Aura Uppercut**; the **Shockwave Uppercut** on a target within 1.2 m; the **Thousand-Fist Flurry** as the third strike of a landed string |
| Hooks + hand (LB / Q) | lead / rear hook | the equipped **hooks technique** |
| Straights + hand (RB / E) | jab / cross | the equipped **straights technique**; with Check held: the **Iron Counter** |
| Overhands + hand (LT / R) | lead / rear overhand | the equipped **overhands technique** |
| Leg, no modifier (A, B / J, K) | lead teep / rear knee | **Pressure-Wave Teep** / **Aura Knee** |
| Hooks / Straights / Overhands + leg | body / head / low kick | the equipped **kicks technique** (its body, head or low kick) |
| Stance (D-left / X) and Slip (right-stick click / Shift) | stance switch, slip | either order (or together) within 0.25 s: the **Afterimage Rush** |
| D-up / D-right (F1 / F2) | Cut the Angle / Second Wind | the same: his abilities stay his D-pad abilities |
| Release View (V) | Championship Rounds | the same |

Guard, the low shell, the check, the double-tap shove, the grapple, pummels and throws work as in Classic. Southpaw swaps the lead side, so every technique has a mirrored southpaw version: the left-hand button always throws with the left hand.

### Loadouts

A Varga loadout is **one technique per modifier group** (hooks, straights, overhands, kicks); his plain strikes and his abilities are always there. Any mix is valid; two techniques for one group, or a group left empty, is refused.

* **Aura Boxer** (A, the default): Comet Hook, Pressure Palm, Thunder Chop, Iron Shins. Hands first: poke with palm blasts, open with chops, clip crowds with comet arcs, and kick through trades on iron shins.
* **Shockwave Kicker** (B): Spiral Hook, Force Palm, Meteor Hammer, Shockwave Kicks. Control: drag them in and turn them, crack guards and floors, and own the range with waves from the legs.

### Techniques

Each technique starts from the Cage Rules strike it replaces (same limb, timing family and hit window), so the controls feel the same; each has two drillable styles.

* **Comet Hook** (hooks). The hook drags a comet tail of gold shockwave: a 120-degree arc 2.3 m deep (3.5 damage, a short shove) that clips anyone beside or behind his man, even when the fist misses. Hook damage ×0.9, +2.5 stamina, 0.06 s longer recovery. *Counter:* the arc only goes forward; guard it or back out and punish the follow-through. *Styles:* **Long Tail** (80 degrees, 3.2 m) · **Heavy Comet** (arc ×1.5 damage, ×2 poise, +3 stamina).
* **Spiral Hook** (hooks). A gold vortex at the fist pulls fighters near it toward him; a clean hit drags the target in and spins him 75 degrees, so his guard faces the wrong way for the next strike. Damage ×0.8, +2 stamina. *Counter:* a blocked Spiral Hook neither spins nor pulls far; keep the guard up and turn back. *Styles:* **Whirlpool** (pulls from 2 m, spins only 30 degrees) · **Corkscrew** (spins 150 degrees, +2 stamina).
* **Pressure Palm** (straights; hold). Palm strikes that throw a ball of aura at the target (3 damage, about 6 m, parryable). Tap for a quick palm and a small blast; hold the hand (up to 0.9 s; light hits don't stop the charge) and release for a blast up to ×3 damage, ×2 size and ×1.35 speed, and a palm 60% harder. Palm damage ×0.75, +2.5 stamina, a little more recovery. *Counter:* it is a projectile: dodge through it, guard it, parry it with a timed guard tap, and rush him while he charges. *Styles:* **Focused Palm** (full charge in 0.45 s, blast grows to ×1.5 only) · **Great Aura** (a full blast is ×2.8 the size, slower, and passes through every fighter).
* **Force Palm** (straights). A slower palm that hits like a heavy: a guard loses 2.5 times the stamina (twice that again on contact), a guard already under 20 stamina breaks at once, and a clean hit sets off a point-blank burst (3 damage, knockback 5.5). Wind-up ×1.15, +3 stamina. *Counter:* beat it to the punch, stay out of its short reach, or grab him. *Styles:* **Guard Breaker** (guard crush doubled again; the burst only shoves) · **Palm Shove** (the burst throws twice as far and splats on the fence).
* **Meteor Hammer** (overhands). An overhead whose wind-up shrugs off light hits; where the fist lands the floor cracks in a 1.25 m ring (4 damage, a small launch) that catches everyone in it. Wind-up ×1.15, damage ×1.1, +3 stamina. *Counter:* step out of the ring or stop him with something heavier than a jab. *Styles:* **Crater** (1.8 m ring and two seconds of broken floor that slows others to 70%) · **Falling Star** (the hammer knocks down, the ring shrinks to 0.9 m).
* **Thunder Chop** (overhands). A quick chop, 15% faster than the overhand with less reach (damage ×0.85); a clean hit sparks and stuns 0.3 s longer, enough to land the next strike. *Counter:* stay just outside its reach; a guard stops the spark. *Styles:* **Rolling Thunder** (the spark jumps to a second fighter within 2 m) · **Flash Chop** (10% faster again, ×1.5 Rattled build-up, half the extra stun).
* **Shockwave Kicks** (kicks). Body kick: the **Shockwave Roundhouse** throws a 110-degree wave arc 2.5 m out (4 damage, knockback 3.5). Head kick: the **Crescent Moon Kick** launches a crescent of aura that flies about 6.5 m through every fighter in its path (5 damage, parryable). Low kick: the **Sweep Quake** shakes the floor where the kick lands and trips anyone standing within 1.15 m who isn't guarding. The kicks themselves hit softer (×0.8 to ×0.85) and cost 2 to 3 more stamina; the quake kick is slower. *Counter:* the waves only go forward: sidestep, guard (a guard stops the trip) or parry the crescent. *Styles:* **Wide Waves** (160-degree arc, a third more crescent range and quake size, waves ×0.8) · **Earthshaker** (waves ×1.5, quake 1.5 m, +3 stamina).
* **Iron Shins** (kicks). Body kick: the **Iron Shin** is armoured through its whole swing against everything but heavies and grabs, with ×1.5 poise damage. Head kick: the **Axe Kick** drops from above and knocks down on a clean hit (slower wind-up, light armour while it rises). Low kick: the **Leg Breaker** builds Rattled twice as fast and slows the target to 75% speed (and 30% dearer dodges) for 3 s. Each kick costs 2 to 3 more stamina. *Counter:* armour is not invulnerability: he still takes the damage, heavies and grabs stop him, and a guard stops the knockdown and the slow. *Styles:* **Tempered Steel** (armour against everything but grabs, +3 stamina) · **Bone Breaker** (5 s slow, ×2 Rattled on the Axe Kick, the Iron Shin loses its armour).

**Plain strikes.** The no-modifier strikes (Aura Uppercut, Pressure-Wave Teep, Aura Knee) keep every Classic number; in Movesets a clean hit flares with gold aura (the teep sends a short pressure cone through the target).

### Combinations

Checked in this order when a limb is pressed: Iron Counter, Thousand-Fist Flurry, Shockwave Uppercut, then the technique or plain strike.

* **Thousand-Fist Flurry.** Connect with two strikes in a row (hit or blocked, the second chained in the first one's recovery), then press a hand with **no modifier**: six aura fists hit in front of him (1.8 damage each, 0.06 s apart), then a rear straight (6.5) bursts on contact (2.5, knockback 5). 12 stamina; without it the press is the plain uppercut. Any limbs and techniques can make the first two strikes; a modifier on the third press throws that strike instead, so the flurry is a choice. On a guard the barrage still grinds its stamina down. *Counter:* guard the barrage (each fist is blockable) and punish its long finish, or break the string before the third press.
* **Iron Counter.** Hold Check (D-down / O) and press a straight (Straights + a hand): Varga braces like iron for 0.3 s (armoured). The first strike that reaches him from within 2.4 m does nothing and is answered at once with an aura burst (8 damage, knockback 5.5, stun 0.5); then he throws the straight (×1.2 damage). One answer per counter, 6 stamina. *Counter:* wait it out and punish the straight, grab him, or use projectiles from range.
* **Afterimage Rush.** Switch stance and slip within 0.25 s of each other (either order, or together): the slip becomes a gold afterimage dash at the target, about 2 m, untouchable for 0.28 s and through projectiles, ending in twin palms (7.5 damage, knockback 4.5). 5 stamina on top of the slip; the stance switches as usual. *Counter:* step aside from its straight line and punish the palms' recovery.
* **Shockwave Uppercut.** A hand with no modifier while the target is within 1.2 m: the uppercut launches him (straight up, 0.55 s stun) and a shockwave ring rolls out 1.7 m from Varga's feet (2 damage, knockback 3). ×1.15 damage, +3 stamina, 0.1 s longer recovery. *Counter:* don't stand on top of him; guard it (a blocked uppercut hardly lifts).

### Tips

* Thunder Chop's spark makes strings easy: chop, chop, then a plain hand for the Flurry. A Shockwave Uppercut that launches also counts as a landed strike.
* Pressure Palm taps are a ranged jab; charge it when the opponent is far, stunned or knocked down, or behind your Iron Shins armour.
* Spiral Hook turns the guard away: follow it immediately with a straight or the Force Palm.
* Force Palm against turtles; Meteor Hammer and the Sweep Quake against fighters who crowd or lie down near him.
* Iron Counter is for strikers who keep pressing; it does nothing against a grab or a projectile from range.
* Afterimage Rush closes distance through a projectile volley; switching stance first and slipping a moment later is the same rush.
* In southpaw everything mirrors: the lead side changes, the techniques follow.
* Bots: the current bot layer presses limbs with random modifiers, so a bot Varga uses whatever his loadout gives each group (it does not read the techniques' `ai` hints yet, and it holds limbs long enough to charge the lead Pressure Palm).

## What the engine adaptation preserves

The source fighter's mesh, limb choices, modifier scheme, strike poses/timing/costs, opponent-relative footwork, high/low guard, checks, slips and stance switching are carried into the authoritative Critterweight simulation. Source files and hashes are retained under `tools/cage_rules/source`.

Grappling uses Critterweight's multiplayer-safe clinch, pummel and directional-throw rules: grapple to catch, press limb buttons to pummel, then grapple plus a direction to throw. The original ground-position and submission simulation is not included. Damage, reach, retargeting and several leg/arm poses are adapted for the differently sized creature roster and Jolt's 120 Hz rig, rather than running Jeremy's separate physics engine.

Network protocol 6 carries the additional inputs. All players in a network match need this preview or a compatible later build.

## Verification

`test_new_fighters` covers both stances, every limb/modifier combination, actual physical hits and recovery, guard exceptions, live input isolation, View chords, tutorial inputs, all abilities, campaign upgrades and expanded network samples. Model inspection renders use poses exported from the actual headless rig. Graphical in-game appearance, physical controller feel and competitive balance remain for owner playtesting.

`test_moves_varga` covers Movesets: the technique pool, loadout validation and every style patch; that each technique replaces exactly its group's strikes in both stances (and that Classic replaces none); each technique's effect from the real limb and modifier buttons; the plain strikes' aura; the four combinations in Movesets and their absence in Classic; Classic Varga's v0.9.17 strike data and dispatch; the legacy skin leaving his gameplay identical in both styles; and the effects kit (`src/view/fx/moves/f_varga.gd`) drawing every effect and cleaning up headless, at High and Low quality. The Movesets data (technique, combination and aura moves, the pool and loadouts) is appended to `f_varga.json` after the importer's output; re-running `tools/cage_rules/import.js` rewrites that file and would drop it.
