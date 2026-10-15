class_name BotBrain
extends InputSource
## Scripted NPC opponent. Plays by the same rules as a human: it only writes FighterInput,
## perceives opponents through a reaction-time delay (no omniscience), and makes deliberate,
## tunable mistakes. Difficulty profiles differ in reaction time, defence, combo discipline,
## spacing, ability use and error rate (docs/DESIGN.md "Bots").

const PROFILES := {
	"rookie": {"reaction": 0.45, "think": 0.2, "aggression": 0.4, "block": 0.12, "parry": 0.0, "dodge": 0.04,
		"combo": 0.2, "ability": 0.2, "grab": 0.08, "mistake": 0.35, "spacing": 0.25, "juice": 0.4, "wake": 0.9, "mash_escape": 0.35},
	"regular": {"reaction": 0.32, "think": 0.14, "aggression": 0.55, "block": 0.32, "parry": 0.04, "dodge": 0.12,
		"combo": 0.5, "ability": 0.45, "grab": 0.18, "mistake": 0.18, "spacing": 0.5, "juice": 0.75, "wake": 0.6, "mash_escape": 0.6},
	"pro": {"reaction": 0.23, "think": 0.1, "aggression": 0.62, "block": 0.5, "parry": 0.14, "dodge": 0.22,
		"combo": 0.75, "ability": 0.65, "grab": 0.28, "mistake": 0.09, "spacing": 0.75, "juice": 0.9, "wake": 0.4, "mash_escape": 0.85},
	"champion": {"reaction": 0.17, "think": 0.07, "aggression": 0.68, "block": 0.62, "parry": 0.3, "dodge": 0.32,
		"combo": 0.9, "ability": 0.8, "grab": 0.35, "mistake": 0.04, "spacing": 0.92, "juice": 1.0, "wake": 0.25, "mash_escape": 1.0},
	# Hall-of-Famer (CAMPAIGN.md difficulty tiers): 0.14 s reactions, 2% mistakes, reads charge-ups
	"hall_of_famer": {"reaction": 0.14, "think": 0.06, "aggression": 0.7, "block": 0.68, "parry": 0.4, "dodge": 0.38,
		"combo": 0.95, "ability": 0.85, "grab": 0.38, "mistake": 0.02, "spacing": 0.95, "juice": 1.0, "wake": 0.2, "mash_escape": 1.0},
}

var difficulty := "regular"
var p := {}
var rng := RandomNumberGenerator.new()
var personality := {}            ## creature ai block: {"aggression": +0.1, "prefers": "ranged", ...}
var _t := 0.0
var _next_think := 0.0
var _history: Array = []          ## [{t, pos, state, slot, st, first_active, guarding}]
var _move := Vector3.ZERO
var _guard := false
var _guard_until := 0.0
var _strafe := 1.0
var _strafe_until := 0.0
var _wake_at := -1.0
var _press_queue: Array = []      ## [{b, at}]
var _reach_cache := {}
var _last_target: Fighter = null
var objective_override := {}      ## set by modes / autobattler
var label_text := ""
var _hold_until := 0.0


func _init(diff := "regular", seed_value := 0) -> void:
	difficulty = diff if PROFILES.has(diff) else "regular"
	p = PROFILES[difficulty].duplicate()
	rng.seed = seed_value if seed_value != 0 else randi()


func label() -> String:
	return label_text if label_text != "" else "Bot (%s)" % difficulty.capitalize()


func set_personality(ai: Dictionary) -> void:
	personality = ai
	for k in ["aggression", "block", "dodge", "ability", "grab"]:
		if ai.has(k):
			p[k] = clampf(float(p[k]) + float(ai[k]), 0.0, 1.0)


func poll(f: Fighter, sim: MatchSim, dt: float) -> void:
	_t += dt
	var tgt := f.target
	if tgt != _last_target:
		_history.clear()
		_last_target = tgt
	if tgt:
		_history.append({"t": _t, "pos": tgt.pos(), "state": tgt.state, "slot": tgt.move_slot, "st": tgt.state_time,
			"first": tgt.move.first_active() if tgt.move else 0.0, "dur": tgt.move.duration if tgt.move else 0.0})
		while _history.size() > 2 and _t - float(_history[1]["t"]) > float(p["reaction"]):
			_history.pop_front()
	# pending timed presses
	for q in _press_queue.duplicate():
		if _t >= float(q["at"]):
			f.input.press(int(q["b"]))
			_press_queue.erase(q)
	if _t >= _next_think:
		_next_think = _t + float(p["think"]) * rng.randf_range(0.7, 1.3)
		_think(f, sim)
	f.input.move = _move
	f.input.set_held(FighterInput.GUARD, _guard and _t < _guard_until)
	f.input.set_held(FighterInput.GRAB, _t < _hold_until)
	# a Heavy press is a tap unless the kit tactics decided to hold it into the charged Heavy
	# (press() also sets the held bit; left set, every bot Heavy used to charge to full)
	f.input.set_held(FighterInput.HEAVY, _t < _heavy_hold_until)
	if f.state == Fighter.State.HELD:
		if rng.randf() < float(p["mash_escape"]) * 0.5:
			f.input.press(FighterInput.LIGHT if rng.randf() < 0.5 else FighterInput.HEAVY)


func _perceived() -> Dictionary:
	return _history[0] if not _history.is_empty() else {}


func _queue(b: int, delay: float) -> void:
	_press_queue.append({"b": b, "at": _t + delay})


## Estimated reach (metres from root) of a move: farthest animated effector target in a hit
## window plus lunge travel plus weapon radius.
func reach_of(c: CreatureDef, slot: String, abilities := false) -> float:
	var key := c.id + ":" + slot
	if _reach_cache.has(key):
		return _reach_cache[key]
	var m: MoveDef = (c.abilities if abilities else c.moves).get(slot)
	var r := 0.0
	if m:
		for k in m.keys:
			for cname in k["chains"]:
				var v = k["chains"][cname]
				if typeof(v) == TYPE_VECTOR3:
					r = maxf(r, (v as Vector3).z)
		var lunge_d := 0.0
		for l in m.lunges:
			if l.size() >= 3:
				lunge_d += (float(l[1]) - float(l[0])) * float(l[2])
		var wr := 0.12
		for w in m.windows:
			for wn in w["weapons"]:
				var wd: BodyDef.Weapon = c.body.weapons.get(wn)
				if wd:
					wr = maxf(wr, wd.radius)
					var wseg: BodyDef.Seg = c.body.segments[wd.seg]
					var rest_z := (wd.local + wseg.pivot).z
					r = maxf(r, rest_z)
		r = r + lunge_d * 0.7 + wr
		for e in m.effects:
			match str(e.get("type", "")):
				"projectile":
					r = maxf(r, float(e.get("speed", 10.0)) * float(e.get("life", 1.0)) * 0.7)
				"area":
					r = maxf(r, float(e.get("radius", 2.0)) * 0.9)
				"leap":
					r = maxf(r, float(e.get("distance", 4.0)))
	_reach_cache[key] = maxf(r, 0.4)
	return _reach_cache[key]


func _think(f: Fighter, sim: MatchSim) -> void:
	_press_queue = _press_queue.filter(func(q): return float(q["at"]) - _t < 0.6)
	var c := f.creature
	match f.state:
		Fighter.State.DOWN:
			if _wake_at < 0.0:
				_wake_at = _t + rng.randf_range(0.0, float(p["wake"]) * 2.0)
			if _t >= _wake_at:
				f.input.press(FighterInput.LIGHT)
				_wake_at = -1.0
			return
		Fighter.State.KNOCKDOWN, Fighter.State.KO, Fighter.State.DOWNED, Fighter.State.INACTIVE:
			_move = Vector3.ZERO
			_guard = false
			return
		Fighter.State.GRABBING:
			# throw toward the nearest wall for a slam, else straight ahead
			var dir := f.forward()
			if sim.arena and rng.randf() < float(p["spacing"]):
				var out := Vector3(f.pos().x, 0, f.pos().z)
				if out.length() > 0.5:
					dir = out.normalized()
			_move = dir
			if f.state_time > rng.randf_range(0.15, 0.6):
				f.input.press(FighterInput.HEAVY if rng.randf() < 0.7 else FighterInput.LIGHT)
			return
	var obj: Dictionary = objective_override if not objective_override.is_empty() else (sim.mode.bot_objective(f) if sim.mode else {})
	if obj.has("target"):
		var ti := int(obj["target"])
		if ti >= 0 and ti < sim.fighters.size() and not sim.fighters[ti].is_out():
			f.target = sim.fighters[ti]
	if _objective_actions(f, obj):
		return
	var tgt := f.target
	if tgt == null or tgt.is_out():
		_guard = false
		if obj.has("pos"):
			_move = _toward(f.pos(), obj["pos"])
		else:
			_move = Vector3.ZERO
		return
	var per := _perceived()
	var tpos: Vector3 = per.get("pos", tgt.pos())
	var to := tpos - f.pos()
	to.y = 0.0
	var dist := to.length()
	var dir := to / maxf(dist, 0.01)
	var my_reach := float(personality.get("attack_range", reach_of(c, "l1")))
	var their_reach := reach_of(tgt.creature, "heavy") if tgt else 1.0
	var mistake := rng.randf() < float(p["mistake"])
	# ---- defence: react to a perceived windup ----
	var per_state := int(per.get("state", Fighter.State.NEUTRAL))
	var attacking := per_state == Fighter.State.ATTACK or per_state == Fighter.State.ABILITY
	var winding := attacking and float(per.get("st", 0.0)) < float(per.get("first", 0.0))
	if attacking and dist < their_reach + 0.6 and not mistake and f.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD]:
		if _kit_defend(f, tgt, per, winding, dir):
			return
		var roll := rng.randf()
		if winding and roll < float(p["parry"]):
			# time the tap for the expected active frame
			var eta := maxf(0.0, float(per["first"]) - float(per["st"]) - float(p["reaction"]))
			_queue(FighterInput.GUARD, maxf(0.0, eta - 0.06))
			_guard = true
			_guard_until = _t + eta + 0.25
		elif roll < float(p["parry"]) + float(p["dodge"]):
			var side := dir.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
			_move = (side - dir * 0.5).normalized()
			f.input.press(FighterInput.DODGE)
			return
		elif roll < float(p["parry"]) + float(p["dodge"]) + float(p["block"]):
			_guard = true
			_guard_until = _t + minf(rng.randf_range(0.3, 0.7), float(personality.get("guard_max", 9.0)))
			if not f.input.is_held(FighterInput.GUARD):
				f.input.press(FighterInput.GUARD)
			_move = -dir * 0.3
			return
	if _t >= _guard_until:
		_guard = false
	# ---- objective modes may pull the bot elsewhere ----
	if obj.has("pos") and dist > float(obj.get("engage", 3.0)):
		_move = _toward(f.pos(), obj["pos"])
		return
	# ---- JUICE ----
	if f.hype >= 100.0 and rng.randf() < float(p["juice"]) * 0.5 and _kit_juice_ok(f, sim, tgt, dist):
		f.input.press(FighterInput.JUICE)
		return
	# ---- abilities ----
	if _kit_abilities(f, sim, tgt, dist):
		return
	for slot in ["ability1", "ability2"]:
		if _kit_has_rules(slot):
			continue
		if c.abilities.has(slot) and float(f.cooldown_left.get(slot, 0.0)) <= 0.0 and rng.randf() < float(p["ability"]) * 0.35:
			var ar := reach_of(c, slot, true)
			if dist <= ar and dist >= minf(1.2, ar * 0.3):
				f.input.press(FighterInput.AB1 if slot == "ability1" else FighterInput.AB2)
				return
	# ---- offence ----
	var stamina_ok := f.stamina > 18.0 or rng.randf() < 0.2
	var aggression := float(p["aggression"]) * (1.25 if f.health_frac() > tgt.health_frac() else 0.9)
	if dist <= my_reach + 0.1 and stamina_ok and rng.randf() < aggression + 0.2:
		var t_guarding := per_state == Fighter.State.GUARD
		if t_guarding and rng.randf() < float(p["grab"]) * 2.0:
			f.input.press(FighterInput.GRAB)
		elif _kit_commit(f, sim, tgt):
			pass
		elif f.state == Fighter.State.ATTACK and f.move_slot in ["l1", "l2"] and rng.randf() < float(p["combo"]):
			if f.move_slot == "l2" and rng.randf() < 0.4:
				f.input.press(FighterInput.HEAVY)
			else:
				f.input.press(FighterInput.LIGHT)
		elif rng.randf() < 0.28:
			_kit_press_heavy(f, tgt)
		elif rng.randf() < float(p["grab"]) * 0.4:
			f.input.press(FighterInput.GRAB)
		else:
			f.input.press(FighterInput.LIGHT)
		_move = dir * 0.4
		return
	if f.state == Fighter.State.ATTACK and f.move_hit_any and rng.randf() < float(p["combo"]):
		f.input.press(FighterInput.LIGHT)
	if _kit_movement(f, sim, tgt, dist, dir):
		return
	# ---- footwork ----
	var want := _kit_want(my_reach * lerpf(0.7, 0.95, float(p["spacing"])))
	if f.stamina < 15.0 and rng.randf() < float(p["spacing"]):
		want = their_reach + 0.8
	if _t >= _strafe_until:
		_strafe = -1.0 if rng.randf() < 0.5 else 1.0
		_strafe_until = _t + rng.randf_range(0.5, 1.6)
	var side2 := dir.cross(Vector3.UP) * _strafe
	if dist > want + 0.25:
		_move = (dir + side2 * 0.25).normalized()
		if dist > 4.0 and rng.randf() < float(p["aggression"]) * 0.1:
			f.input.press(FighterInput.DODGE)
	elif dist < want - 0.35:
		_move = (-dir + side2 * 0.4).normalized() * 0.8
	else:
		_move = side2 * lerpf(0.3, 0.7, float(p["spacing"]))
	if mistake:
		_move = _move.rotated(Vector3.UP, rng.randf_range(-1.0, 1.0))
	if personality.has("taunt_if"):
		_kit_taunt(f, sim, tgt, dist)
	elif rng.randf() < 0.01 and f.hype < 100.0 and dist > 3.0:
		f.input.press(FighterInput.TAUNT)


## Mode objectives that are not plain fighting: hold a button at a spot (revives), strike an
## object toward an aim point (balls), throw a carried object, or just stand on a point.
## Returns true when the objective fully decided this think step.
func _objective_actions(f: Fighter, obj: Dictionary) -> bool:
	if obj.is_empty() or not obj.has("pos"):
		return false
	var p: Vector3 = obj["pos"]
	var to := p - f.pos()
	to.y = 0.0
	var dist := to.length()
	var rad := float(obj.get("radius", 0.5))
	if obj.has("hold"):
		if dist > rad:
			_move = to.normalized()
			return true
		_move = Vector3.ZERO
		f.input.set_held(FighterInput.GRAB, true)
		_hold_until = _t + float(p_think()) * 2.0
		return true
	if bool(obj.get("throw", false)) and f.has_flag("carrying"):
		var aim: Vector3 = obj.get("aim", p)
		var ad := aim - f.pos()
		ad.y = 0.0
		_move = ad.normalized()
		f.input.press(FighterInput.GRAB)
		return true
	if bool(obj.get("strike", false)) and dist < 1.6:
		var aim2: Vector3 = obj.get("aim", p)
		var from_ball := aim2 - p
		from_ball.y = 0.0
		_move = (to.normalized() * 0.6 + from_ball.normalized() * 0.4).normalized()
		if rng.randf() < 0.75:
			f.input.press(FighterInput.HEAVY if rng.randf() < 0.3 else FighterInput.LIGHT)
		elif bool(obj.get("grab_ball", false)):
			f.input.press(FighterInput.GRAB)
		return true
	if f.target == null or f.target.pos().distance_to(f.pos()) > float(obj.get("engage", 3.0)):
		if dist > rad:
			_move = to.normalized()
			return true
	return false


func p_think() -> float:
	return float(p["think"])


func _toward(from: Vector3, to: Vector3) -> Vector3:
	var d := to - from
	d.y = 0.0
	return d.normalized() if d.length() > 0.2 else Vector3.ZERO


# =====================================================================================
# Kit tactics (data-driven from the creature "ai" block; every key optional)
# =====================================================================================
#   "range": [min, max]           preferred root-to-root distance for footwork (m)
#   "attack_range": m             distance at which strikes start (default: L1 reach estimate)
#   "abilities": {slot: [rule]}   rule = {"if": [cond...], "chance": p, "min_dist": m, "max_dist": m};
#                                 a slot with rules is used only by them (no random generic use)
#   "juice_if": [cond...]         JUICE only when every condition holds (default: target within 3.5 m)
#   "taunt_if": [cond...]         taunt (rate "taunt_chance" per think, x3 for rookie bots)
#   "guard_max": s                longest guard hold; "dodge_for_guard": p turns that share of
#                                 guard reactions into sidesteps
#   "dash_in": {"min", "max", "chance"}  dodge toward the target, then Light = Dash Attack
#   "dash_out": p                 chance to dodge back out after an attack inside range.min
#   "commit_if": [cond...]        strings go to L3 / the Finisher when these hold
#   "charge_heavy": {"from": profile, "chance": p}  hold Heavy into the charged Heavy
#   "parry_heavy": {"from": profile, "chance": p}   time a parry against incoming Heavies
# Conditions: projectile_incoming, target_down, target_cornered, target_winding_heavy,
#   target_closing, in_enemy_zone, juiced, self_poise_below:<frac>, self_health_below:<frac>,
#   target_far:<m>, target_near:<m>, target_status:<element or status id>, random:<p>.
# Profiles in skill order: rookie (Punching Bag) < regular (Journeyman) < pro (Contender)
#   < champion (Headliner) < hall_of_famer.

const KIT_PROFILE_ORDER := ["rookie", "regular", "pro", "champion", "hall_of_famer"]

var _heavy_hold_until := 0.0
var _kit_last_dist := -1.0
var _kit_dash_until := 0.0


func _kit_profile_at_least(name_: String) -> bool:
	return KIT_PROFILE_ORDER.find(difficulty) >= maxi(0, KIT_PROFILE_ORDER.find(name_))


func _kit_has_rules(slot: String) -> bool:
	return (personality.get("abilities", {}) as Dictionary).has(slot)


## True when every condition string holds. A list of lists means "any of these groups".
func _kit_conds(conds: Array, f: Fighter, sim: MatchSim, tgt: Fighter, dist: float) -> bool:
	if not conds.is_empty() and typeof(conds[0]) == TYPE_ARRAY:
		for group in conds:
			if _kit_conds(group, f, sim, tgt, dist):
				return true
		return false
	for cs in conds:
		var parts: PackedStringArray = str(cs).split(":")
		var arg := parts[1] if parts.size() > 1 else ""
		var ok := false
		match parts[0]:
			"projectile_incoming":
				ok = _kit_projectile_incoming(f, sim)
			"target_down":
				ok = tgt != null and tgt.is_down()
			"target_cornered":
				ok = tgt != null and sim.arena != null and not sim.arena.inside(tgt.pos(), 1.3)
			"target_winding_heavy":
				ok = tgt != null and tgt.is_winding_up() and tgt.current_move_class() == "heavy"
			"target_closing":
				ok = _kit_last_dist > 0.0 and _kit_last_dist - dist > 0.08
			"in_enemy_zone":
				ok = _kit_in_enemy_zone(f, sim)
			"juiced":
				ok = f.has_flag("juiced")
			"self_poise_below":
				ok = f.poise < f.effective_max_poise() * float(arg)
			"self_health_below":
				ok = f.health_frac() < float(arg)
			"target_far":
				ok = dist > float(arg)
			"target_near":
				ok = dist < float(arg)
			"target_status":
				ok = tgt != null and (tgt.statuses.has(arg) or tgt.statuses.has_element(arg))
			"random":
				ok = rng.randf() < float(arg)
		if not ok:
			return false
	return true


func _kit_projectile_incoming(f: Fighter, sim: MatchSim) -> bool:
	for e in sim.effects.entities:
		if e["kind"] != "projectile" or int(e["team"]) == f.team:
			continue
		var rel: Vector3 = f.pos() - Vector3(e["pos"])
		rel.y = 0.0
		var vel: Vector3 = e["vel"]
		vel.y = 0.0
		if rel.length() < 4.0 and vel.dot(rel) > 0.0:
			return true
	return false


func _kit_in_enemy_zone(f: Fighter, sim: MatchSim) -> bool:
	for z in sim.effects.entities:
		if z["kind"] != "zone" or int(z["owner"]) == f.index or int(z.get("team", -1)) == f.team:
			continue
		if Vector2(f.pos().x - z["pos"].x, f.pos().z - z["pos"].z).length() <= float(z["radius"]):
			return true
	return false


## Parry incoming Heavies (profile-gated) or sidestep instead of holding a long guard.
func _kit_defend(f: Fighter, tgt: Fighter, per: Dictionary, winding: bool, dir: Vector3) -> bool:
	var ph: Dictionary = personality.get("parry_heavy", {})
	if winding and not ph.is_empty() and _kit_profile_at_least(str(ph.get("from", "champion"))) \
			and tgt != null and tgt.current_move_class() == "heavy" and rng.randf() < float(ph.get("chance", 0.35)):
		var eta := maxf(0.0, float(per["first"]) - float(per["st"]) - float(p["reaction"]))
		_queue(FighterInput.GUARD, maxf(0.0, eta - 0.06))
		_guard = true
		_guard_until = _t + eta + 0.25
		return true
	if personality.has("dodge_for_guard") and rng.randf() < float(p["block"]) * float(personality["dodge_for_guard"]) and f.stamina > 12.0:
		var side := dir.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
		_move = (side - dir * 0.6).normalized()
		f.input.press(FighterInput.DODGE)
		return true
	return false


func _kit_juice_ok(f: Fighter, sim: MatchSim, tgt: Fighter, dist: float) -> bool:
	if personality.has("juice_if"):
		return _kit_conds(personality["juice_if"], f, sim, tgt, dist)
	return dist < 3.5


func _kit_abilities(f: Fighter, sim: MatchSim, tgt: Fighter, dist: float) -> bool:
	var rules: Dictionary = personality.get("abilities", {})
	for slot in rules:
		if not f.creature.abilities.has(slot) or int(f.charges_left.get(slot, 1)) <= 0:
			continue
		for r in rules[slot]:
			var rd: Dictionary = r
			if dist < float(rd.get("min_dist", 0.0)) or dist > float(rd.get("max_dist", 99.0)):
				continue
			if rng.randf() >= float(rd.get("chance", 1.0)) * (0.5 + 0.5 * float(p["ability"])):
				continue
			if _kit_conds(rd.get("if", []), f, sim, tgt, dist):
				f.input.press(FighterInput.AB1 if slot == "ability1" else FighterInput.AB2)
				return true
	return false


## Strings into L3 / the Finisher when the commit conditions hold (e.g. a Sizzling target).
func _kit_commit(f: Fighter, sim: MatchSim, tgt: Fighter) -> bool:
	if not personality.has("commit_if") or f.state != Fighter.State.ATTACK or not f.move_slot in ["l1", "l2", "l3"]:
		return false
	if not _kit_conds(personality["commit_if"], f, sim, tgt, 0.0) or rng.randf() > float(p["combo"]) + 0.15:
		return false
	f.input.press(FighterInput.HEAVY if f.move_slot in ["l2", "l3"] else FighterInput.LIGHT)
	return true


func _kit_press_heavy(f: Fighter, _tgt: Fighter) -> void:
	f.input.press(FighterInput.HEAVY)
	var ch: Dictionary = personality.get("charge_heavy", {})
	if not ch.is_empty() and _kit_profile_at_least(str(ch.get("from", "pro"))) and rng.randf() < float(ch.get("chance", 0.2)):
		_heavy_hold_until = _t + rng.randf_range(0.6, 0.9)


## Dash-in attacks and hit-and-run exits; returns true when it decided this think step.
func _kit_movement(f: Fighter, _sim: MatchSim, _tgt: Fighter, dist: float, dir: Vector3) -> bool:
	_kit_last_dist = dist   # "target_closing" compares against this on the next think
	var rg: Array = personality.get("range", [])
	var di: Dictionary = personality.get("dash_in", {})
	if not di.is_empty() and f.state == Fighter.State.NEUTRAL and _t > _kit_dash_until and f.stamina > 20.0 \
			and dist >= float(di.get("min", 1.6)) and dist <= float(di.get("max", 3.6)) and rng.randf() < float(di.get("chance", 0.3)) * float(p["aggression"]):
		_move = dir
		f.input.press(FighterInput.DODGE)
		_queue(FighterInput.LIGHT, rng.randf_range(0.11, 0.16))
		_kit_dash_until = _t + 0.9
		return true
	if personality.has("dash_out") and rg.size() == 2 and dist < float(rg[0]) and f.stamina > 16.0 and _t > _kit_dash_until \
			and (f.state == Fighter.State.NEUTRAL) and rng.randf() < float(personality["dash_out"]) * float(p["spacing"]):
		_move = (-dir + dir.cross(Vector3.UP) * (0.4 if rng.randf() < 0.5 else -0.4)).normalized()
		f.input.press(FighterInput.DODGE)
		_kit_dash_until = _t + 0.6
		return true
	return false


func _kit_want(default_want: float) -> float:
	var rg: Array = personality.get("range", [])
	if rg.size() == 2:
		return lerpf(float(rg[0]), float(rg[1]), rng.randf())
	return default_want


func _kit_taunt(f: Fighter, sim: MatchSim, tgt: Fighter, dist: float) -> void:
	if f.hype >= 100.0 or f.state != Fighter.State.NEUTRAL:
		return
	var chance := float(personality.get("taunt_chance", 0.05)) * (3.0 if difficulty == "rookie" else 1.0)
	if rng.randf() < chance and _kit_conds(personality["taunt_if"], f, sim, tgt, dist):
		f.input.press(FighterInput.TAUNT)
