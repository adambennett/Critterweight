class_name HitFeel
extends RefCounted
## How hard a landed hit is felt: hit pause, camera shake and zoom punch, spark size and the
## victim's flash. View-side only: the simulation never sees any of it. The local and online
## scenes share these numbers, and tests pin them (test_hit_feel).
##
## Only hits that involve a local player get the strong treatment (the pause and the punch), plus
## every KO, so a busy bot brawl or a spectated fight never stutters.

## Engine.time_scale while a hit pause holds (the simulation all but stops, audio plays on)
const PAUSE_SCALE := 0.04


## Seconds a local match freezes for a hit (0 = no pause).
static func hit_pause(dmg: float, blocked: bool, counter: bool, involved: bool) -> float:
	if not involved or dmg < 0.5:
		return 0.0
	if blocked:
		return 0.035
	return clampf(0.04 + dmg * 0.005, 0.05, 0.12) + (0.03 if counter else 0.0)


static func ko_pause() -> float:
	return 0.2


## Camera trauma added by a hit (FightCamera squares it into the shake).
static func trauma(dmg: float, involved: bool) -> float:
	return clampf(0.2 + dmg / 25.0, 0.2, 0.65) if involved else clampf(dmg / 40.0, 0.05, 0.45)


## Zoom punch for the fight camera, 0..1 (0 = none).
static func punch(dmg: float, blocked: bool, involved: bool) -> float:
	if not involved:
		return 0.0
	return clampf(dmg / 12.0, 0.3, 1.0) * (0.4 if blocked else 1.0)


static func spark_scale(dmg: float, involved: bool) -> float:
	return clampf(dmg / 7.0, 0.7, 1.8) if involved else clampf(dmg / 10.0, 0.4, 1.5)


## Strength of the victim's white flash.
static func flash(dmg: float) -> float:
	return clampf(dmg / 10.0, 0.45, 1.0)


## Controller rumble [weak, strong, seconds] for the local player's hit (given or taken).
static func rumble(dmg: float, blocked: bool) -> Array:
	if blocked:
		return [0.15, 0.0, 0.08]
	return [clampf(dmg / 18.0, 0.2, 0.7), clampf(dmg / 24.0, 0.15, 0.9), 0.16]
