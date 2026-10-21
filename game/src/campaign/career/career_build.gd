class_name CareerBuild
extends RefCounted
## Career stats -> fighter (design contract D2). ONE function, `apply_block`, turns six trained
## stats (+ carried injuries) into a campaign apply block, and `compose` feeds it through
## BuildApplier.compose as the pseudo player's only run effect. The player AND every generated
## opponent are built here, so a 0.70 Power means the same on both sides.
## Fixed mapping (MAP), each value linear in (s - 0.5) so 0.5 is the creature's own kit:
##   stamina  stamina_add (add), stamina_regen (mul)
##   chin     poise_add (add), getup_speed (mul)                    -- NEVER the "poise" multiplier
##   speed    speed (mul: walking, strafing, dashes), move_speed (mul: strike/ability tempo)
##   power    damage (mul), patch moves.*.poise (mul: knockdown force of every move)
##   clinch   grab_hold_add (add), grab_escape_add (add, whole presses), throw_distance (mul),
##            splat_damage_add (add) on the grabber side; held_time_mult (mul < 1 above 0.5)
##            on the victim side (escapes holds sooner)
##   defence  guard_absorb_mult (mul < 1), parry_window_add (add), dodge_iframes_add (add),
##            dodge_cost (mul < 1)                                    -- NEVER "defense"
## Injuries in (carry x region injury): head -> poise_add < 0, body -> stamina_regen mul < 1,
## legs -> speed mul < 1 (never move_speed).
## Isolation: the block exists only in career fight configs (CareerFight). The pseudo state's
## variant is "career", so Fight Camp meta never applies, and versus/online never call this.
## Coefficients come from rules.build (CareerDefaults); the keys are fixed here.
## Drilled move styles (v0.9.18, CareerMoves.drill_effects) ride the same path: each is a run effect
## of the pseudo player BEFORE the stats block, so the style shapes the move and the career stats
## scale the result (Power's moves.*.poise multiplies a style's own poise).

## [stat, mod key, op] — op "add", "mul" or "add_int" (whole numbers: grab_escape_add is int-cast)
const MAP := [
	["stamina", "stamina_add", "add"], ["stamina", "stamina_regen", "mul"],
	["chin", "poise_add", "add"], ["chin", "getup_speed", "mul"],
	["speed", "speed", "mul"], ["speed", "move_speed", "mul"],
	["power", "damage", "mul"],
	["clinch", "grab_hold_add", "add"], ["clinch", "grab_escape_add", "add_int"], ["clinch", "throw_distance", "mul"],
	["clinch", "splat_damage_add", "add"], ["clinch", "held_time_mult", "mul"],
	["defence", "guard_absorb_mult", "mul"], ["defence", "parry_window_add", "add"],
	["defence", "dodge_iframes_add", "add"], ["defence", "dodge_cost", "mul"],
]
## [stat, patch path] — creature patches (op mul)
const PATCHES := [["power", "moves.*.poise"]]
## Fighter mods the career must never touch (they invert or square the intended effect).
const FORBIDDEN := ["defense", "poise"]
## mul values are kept inside this band so no stat combination can break a fighter
const MUL_MIN := 0.5
const MUL_MAX := 1.6


static func _coef(rules: Dictionary, stat: String, key: String) -> float:
	var b: Dictionary = (rules.get("build", {}) as Dictionary).get(stat, {})
	if b.has(key):
		return float(b[key])
	var d: Dictionary = (CareerDefaults.rules()["build"] as Dictionary).get(stat, {})
	return float(d.get(key, 0.0))


## The apply block {"mods": [...], "patches": [...]} for these stats (+ carried injuries).
static func apply_block(rules: Dictionary, stats: Dictionary, injury: Dictionary = {}) -> Dictionary:
	var mods := []
	for m in MAP:
		var stat := str(m[0])
		var x := clampf(float(stats.get(stat, 0.5)), 0.0, 1.0) - 0.5
		var c := _coef(rules, stat, str(m[1])) * x
		match str(m[2]):
			"mul":
				mods.append({"key": str(m[1]), "mul": clampf(1.0 + c, MUL_MIN, MUL_MAX)})
			"add_int":
				mods.append({"key": str(m[1]), "add": float(roundi(c))})
			_:
				mods.append({"key": str(m[1]), "add": c})
	var patches := []
	for pt in PATCHES:
		var x2 := clampf(float(stats.get(str(pt[0]), 0.5)), 0.0, 1.0) - 0.5
		patches.append({"op": "mul", "path": str(pt[1]), "value": clampf(1.0 + _coef(rules, str(pt[0]), str(pt[1])) * x2, MUL_MIN, MUL_MAX)})
	mods.append_array(injury_mods(rules, injury))
	return {"mods": mods, "patches": patches}


## Fight-start handicap from carried injuries (design contract D2 "injuries in").
static func injury_mods(rules: Dictionary, injury: Dictionary) -> Array:
	var out := []
	if injury.is_empty():
		return out
	var ii: Dictionary = rules.get("injury_in", {})
	var carry := float(ii.get("carry", 0.5))
	var min_mult := float(ii.get("min_mult", 0.7))
	var head := maxf(0.0, float(injury.get("head", 0.0))) * carry
	var body := maxf(0.0, float(injury.get("body", 0.0))) * carry
	var legs := maxf(0.0, float(injury.get("legs", 0.0))) * carry
	if head > 0.0:
		out.append({"key": "poise_add", "add": -minf(float(ii.get("head_poise_max", 15.0)), head * float(ii.get("head_poise_per_point", 0.3)))})
	if body > 0.0:
		out.append({"key": "stamina_regen", "mul": maxf(min_mult, 1.0 - body / maxf(1.0, float(ii.get("body_regen_div", 160.0))))})
	if legs > 0.0:
		out.append({"key": "speed", "mul": maxf(min_mult, 1.0 - legs / maxf(1.0, float(ii.get("legs_speed_div", 200.0))))})
	return out


## The pseudo run player BuildApplier composes (no techniques, supplements or meta: base kit +
## the drilled styles, if any, + the career block).
static func pseudo_player(fighter: String, block: Dictionary, id := "career", drills: Array = []) -> Dictionary:
	var effects: Array = []
	for d in drills:
		if typeof(d) == TYPE_DICTIONARY:
			effects.append((d as Dictionary).duplicate(true))
	effects.append({"source": "career", "apply": block})
	return {"id": id, "fighter": fighter, "techniques": [], "supplements": [], "side_effects": [],
		"run_effects": effects}


## BuildApplier.compose result for a career fighter: {creature, creature_dict, mods, ...}.
## `drills`: CareerMoves.drill_effects of the career fighter (opponents have none).
static func compose(catalog: CampaignCatalog, rules: Dictionary, fighter: String, stats: Dictionary, injury: Dictionary = {}, id := "career", drills: Array = []) -> Dictionary:
	var pseudo := pseudo_player(fighter, apply_block(rules, stats, injury), id, drills)
	var st := {"variant": "career", "dose": 0, "players": [pseudo]}
	var res := BuildApplier.compose(catalog, st, pseudo, {"party": "solo"})
	# belt and braces: the forbidden multipliers are never part of a career build
	var mods: Dictionary = res.get("mods", {})
	for k in FORBIDDEN:
		mods.erase(k)
	return res
