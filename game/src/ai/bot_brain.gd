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
var _heavy_hold_until := 0.0      ## kit hint "charge_heavy": Heavy held into the charged version


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
	if _kit_pre_poll(f):
		return
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
	f.input.move = _edge_safe(f, sim, _move)
	f.input.set_held(FighterInput.GUARD, _guard and _t < _guard_until)
	f.input.set_held(FighterInput.GRAB, _t < _hold_until)
	f.input.set_held(FighterInput.HEAVY, _t < _heavy_hold_until)
	if f.state == Fighter.State.HELD:
		if rng.randf() < float(p["mash_escape"]) * 0.5:
			f.input.press(FighterInput.LIGHT if rng.randf() < 0.5 else FighterInput.HEAVY)


## Ring-out arenas: a ring-out costs health and time, so bots keep off open edges. Within
## EDGE_CAUTION of one, the outward part of the intended move is cancelled and an inward pull
## added (stronger closer to the edge and for better spacing). Dodges use the corrected move, so
## they never point off the roof. A bot carrying someone still walks them out to throw.
const EDGE_CAUTION := 1.7


func _edge_safe(f: Fighter, sim: MatchSim, mv: Vector3) -> Vector3:
	if sim == null or sim.arena == null or f.state == Fighter.State.GRABBING:
		return mv
	if not bool(sim.rules.get("ringouts", true)) or not sim.arena.has_open_edges():
		return mv
	var d := sim.arena.edge_distance(f.pos(), true)
	if d >= EDGE_CAUTION:
		return mv
	var inward := sim.arena.open_edge_inward(f.pos())
	if inward == Vector3.ZERO:
		return mv
	var out := mv.dot(-inward)
	if out > 0.0:
		mv += inward * out
	mv += inward * (1.0 - d / EDGE_CAUTION) * lerpf(0.5, 1.0, float(p["spacing"]))
	return mv.limit_length(1.0)


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
	var authored: Dictionary = c.ai.get("reach", {})   # kit hint "reach" (long bodies that strike by bending)
	if authored.has(slot):
		_reach_cache[key] = float(authored[slot])
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
	var my_reach := reach_of(c, "l1") + _kit_target_bulk(f, tgt)
	var their_reach := reach_of(tgt.creature, "heavy") if tgt else 1.0
	var mistake := rng.randf() < float(p["mistake"])
	# ---- defence: react to a perceived windup ----
	var per_state := int(per.get("state", Fighter.State.NEUTRAL))
	var attacking := (per_state == Fighter.State.ATTACK or per_state == Fighter.State.ABILITY) and not _kit_opening(per, tgt)
	var winding := attacking and float(per.get("st", 0.0)) < float(per.get("first", 0.0))
	if attacking and dist < their_reach + 0.6 and not mistake and f.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD]:
		if _kit_ability(f, tgt, dist, dir, per, true):   # kit hint: reactive abilities (counters, armor)
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
			_guard_until = _t + rng.randf_range(0.3, 0.7)
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
	if _kit_think(f, sim, tgt, dist, dir, attacking and not mistake, my_reach, their_reach):
		return
	# ---- JUICE ----
	if f.hype >= 100.0 and rng.randf() < float(p["juice"]) * 0.5 and dist < 3.5:
		f.input.press(FighterInput.JUICE)
		return
	# ---- abilities ----
	if _kit_ability(f, tgt, dist, dir, per, false):   # kit hints from the creature "ai" block
		return
	for slot in ["ability1", "ability2"]:
		if _kit_hint_for(c, slot).is_empty() and c.abilities.has(slot) and float(f.cooldown_left.get(slot, 0.0)) <= 0.0 and rng.randf() < float(p["ability"]) * 0.35:
			var ar := reach_of(c, slot, true)
			if dist <= ar and dist >= minf(1.2, ar * 0.3):
				f.input.press(FighterInput.AB1 if slot == "ability1" else FighterInput.AB2)
				return
	# ---- offence ----
	var stamina_ok := f.stamina > 18.0 or rng.randf() < 0.2
	var aggression := float(p["aggression"]) * (1.25 if f.health_frac() > tgt.health_frac() else 0.9)
	if dist <= my_reach + 0.1 and stamina_ok and rng.randf() < aggression + 0.2:
		var t_guarding := per_state == Fighter.State.GUARD
		if (t_guarding or _kit_grab_target(tgt)) and rng.randf() < float(p["grab"]) * 2.0:
			f.input.press(FighterInput.GRAB)
		elif f.state == Fighter.State.ATTACK and f.move_slot in ["l1", "l2"] and rng.randf() < float(p["combo"]):
			if f.move_slot == "l2" and rng.randf() < 0.4:
				f.input.press(FighterInput.HEAVY)
			else:
				f.input.press(FighterInput.LIGHT)
		elif rng.randf() < 0.28:
			f.input.press(FighterInput.HEAVY)
			_kit_maybe_charge()
		elif rng.randf() < float(p["grab"]) * 0.4:
			f.input.press(FighterInput.GRAB)
		else:
			f.input.press(FighterInput.LIGHT)
		_move = dir * 0.4
		return
	if f.state == Fighter.State.ATTACK and f.move_hit_any and rng.randf() < float(p["combo"]):
		f.input.press(FighterInput.LIGHT)
	# ---- footwork ----
	var want := my_reach * lerpf(0.7, 0.95, float(p["spacing"]))
	var kit_range := _kit_range()
	if not kit_range.is_empty():
		want = lerpf(float(kit_range[1]), float(kit_range[0]), float(p["spacing"]))
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
	if rng.randf() < 0.01 and f.hype < 100.0 and dist > 3.0:
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
# Kit hints: optional keys of the creature "ai" block (added with the Dredge/Dozer kits,
# extended with the NPC kits: Kid Lamprey, minions, bosses). Absent keys keep the generic
# behaviour above.
#   "range": [near, far]        preferred engagement distance (root to root) for footwork
#   "keep_distance": m          ranged-unit shorthand (the campaign's Pelter recipe): range m +- 0.4
#                               plus an implicit hint for its ranged ability ("ranged_slot", default
#                               the longest-reaching ability) fired from 1.5 m out to its reach.
#                               "prefers": "ranged" alone means 4 m.
#   "charge_heavy": p           chance a Heavy press is held into the charged version (scaled by skill)
#   "grab_status": [ids]        targets carrying one of these statuses are grabbed like guarding ones
#   "abilities": {slot: {"min": m, "max": m, "chance": c, "apart": m, "when": [cond, ...]}}
#       an ability with a hint is used only by its hint (replaces the generic reach test). `apart`:
#       never while an ally within that many metres is performing the same ability (Blisters do not
#       inflate side by side). `when` is a list of alternatives (any may hold; absent = always);
#       each is a dict whose keys must all hold: min / max (distance), self_poise_below,
#       self_health_below (fractions), target_status (id or element), target_heavy (perceived
#       Heavy / Charged Heavy windup), target_winding (any windup), target_ranged (the target has a
#       projectile ability), wall_behind_target (an arena wall within this many metres beyond the
#       target, on the line from this fighter).
#       Reactive conditions (target_heavy / target_winding) are also checked while defending:
#       counters, armor and evasions answering a wind-up.
#   "pack": n                   at most n allies with a "pack" key attack one target at once; the
#                               rest wait at "pack_ring" m (default 2.2), circling toward its flank,
#                               and raise "pack_guard" (an ability slot, or "guard") when it swings
#                               at them. Ranged units (range / keep_distance) never wait.
#   "ally_ko_flinch": s         seconds the unit freezes after an ally within 3 m is knocked out
#   "rest": [min, max]          seconds the unit waits after each of its own attacks / abilities
#                               before it starts another (it only circles meanwhile): a boss's
#                               breather that keeps its rhythm readable and leaves a punish window
#   "reach": {slot: m}          authored reach for slots whose strike comes from bending a long
#                               body rather than lunging (read by reach_of before its estimate)
#   "bulky": true               read from the TARGET's block (bosses): bots fighting it measure
#                               their reach to its nearest body part instead of its root (its head
#                               or shell is in reach long before its root is), and treat the
#                               recovery of its long moves (after the last hit window / effect) as
#                               an opening to punish instead of a threat to dodge.
# =====================================================================================

var _flinch_until := -1.0
var _ev_cursor := -1
var _was_busy := false               ## attacking / using an ability last tick (for "rest")
var _rest_until := -1.0


func _kit_hint(slot: String) -> Dictionary:
	var ab = personality.get("abilities", {})
	if typeof(ab) != TYPE_DICTIONARY:
		return {}
	var h = (ab as Dictionary).get(slot, {})
	return h if typeof(h) == TYPE_DICTIONARY else {}


## The hint that drives `slot`: the authored one, or the implicit hint of a ranged unit's ranged
## ability (keep_distance / prefers ranged). Empty = the generic ability logic uses the slot.
func _kit_hint_for(c: CreatureDef, slot: String) -> Dictionary:
	var h := _kit_hint(slot)
	if not h.is_empty() or _kit_keep_distance() <= 0.0:
		return h
	var ranged := str(personality.get("ranged_slot", ""))
	if ranged == "":
		var best := 0.0
		for s in ["ability1", "ability2"]:
			if c.abilities.has(s) and reach_of(c, s, true) > best:
				best = reach_of(c, s, true)
				ranged = s
	if slot != ranged or not c.abilities.has(slot):
		return {}
	return {"min": 1.5, "max": reach_of(c, slot, true), "chance": 2.5}


func _kit_keep_distance() -> float:
	return float(personality.get("keep_distance", 4.0 if str(personality.get("prefers", "")) == "ranged" else 0.0))


## Preferred engagement distance [near, far] for footwork, or [] for the generic spacing.
func _kit_range() -> Array:
	var r = personality.get("range")
	if r is Array and (r as Array).size() >= 2:
		return r
	var kd := _kit_keep_distance()
	return [kd - 0.4, kd + 0.4] if kd > 0.0 else []


func _kit_ability(f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary, reactive: bool) -> bool:
	for slot in ["ability1", "ability2"]:
		var h := _kit_hint_for(f.creature, slot)
		if h.is_empty() or not f.creature.abilities.has(slot) or int(f.charges_left.get(slot, 1)) <= 0:
			continue
		var ab: MoveDef = f.creature.abilities[slot]
		if f.stamina < ab.stamina * 0.5:
			continue
		var gate := float(p["ability"]) * (0.8 if reactive else 0.35) * float(h.get("chance", 1.0))
		if rng.randf() >= gate:
			continue
		if dist < float(h.get("min", 0.0)) or dist > float(h.get("max", 99.0)):
			continue
		if h.has("apart") and _kit_ally_using(f, slot, float(h["apart"])) != null:
			continue
		var whens = h.get("when", [])
		var ok: bool = typeof(whens) != TYPE_ARRAY or (whens as Array).is_empty()
		if reactive:
			ok = false
		if typeof(whens) == TYPE_ARRAY:
			for w in whens:
				if typeof(w) == TYPE_DICTIONARY and _kit_when(f, tgt, dist, dir, per, w as Dictionary, reactive):
					ok = true
					break
		if ok:
			f.input.press(FighterInput.AB1 if slot == "ability1" else FighterInput.AB2)
			return true
	return false


func _kit_when(f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary, w: Dictionary, reactive: bool) -> bool:
	if reactive and not (w.has("target_heavy") or w.has("target_winding")):
		return false
	var p_state := int(per.get("state", Fighter.State.NEUTRAL))
	var p_attacking := p_state == Fighter.State.ATTACK or p_state == Fighter.State.ABILITY
	var p_winding := p_attacking and float(per.get("st", 0.0)) < float(per.get("first", 0.0))
	for k in w:
		var v = w[k]
		match str(k):
			"min":
				if dist < float(v):
					return false
			"max":
				if dist > float(v):
					return false
			"self_poise_below":
				if f.poise / maxf(1.0, f.effective_max_poise()) >= float(v):
					return false
			"self_health_below":
				if f.health_frac() >= float(v):
					return false
			"target_status":
				if tgt == null or not (tgt.statuses.has(str(v)) or tgt.statuses.has_element(str(v))):
					return false
			"target_heavy":
				if (p_winding and str(per.get("slot", "")).begins_with("heavy")) != bool(v):
					return false
			"target_winding":
				if p_winding != bool(v):
					return false
			"target_ranged":
				if _kit_is_ranged(tgt) != bool(v):
					return false
			"wall_behind_target":
				if f.sim == null or f.sim.arena == null:
					return false
				if f.sim.arena.inside(f.pos() + dir * (dist + float(v)), 0.3):
					return false
	return true


func _kit_is_ranged(tgt: Fighter) -> bool:
	if tgt == null:
		return false
	for slot in tgt.creature.abilities:
		var m: MoveDef = tgt.creature.abilities[slot]
		for e in m.effects:
			if typeof(e) == TYPE_DICTIONARY and str(e.get("type", "")) == "projectile":
				return true
	return false


func _kit_grab_target(tgt: Fighter) -> bool:
	var gs = personality.get("grab_status", [])
	if tgt == null or typeof(gs) != TYPE_ARRAY:
		return false
	for s in gs:
		if tgt.statuses.has(str(s)) or tgt.statuses.has_element(str(s)):
			return true
	return false


## After a Heavy press: maybe keep holding it so the charged version comes out (skill-scaled).
func _kit_maybe_charge() -> void:
	var ch := float(personality.get("charge_heavy", 0.0)) * float(p["combo"])
	if ch > 0.0 and rng.randf() < ch:
		_heavy_hold_until = _t + rng.randf_range(0.6, 1.1)


## Every tick, before anything else: starts a "rest" when an attack ends and keeps a flinching
## unit frozen. Returns true when this tick is fully decided.
func _kit_pre_poll(f: Fighter) -> bool:
	var busy := f.state == Fighter.State.ATTACK or f.state == Fighter.State.ABILITY
	var rest = personality.get("rest", [])
	if _was_busy and not busy and rest is Array and (rest as Array).size() >= 2:
		_rest_until = _t + rng.randf_range(float(rest[0]), float(rest[1]))
	_was_busy = busy
	if _t < _flinch_until:
		f.input.move = Vector3.ZERO
		f.input.held = 0
		return true
	return false


## Kit behaviours that replace the rest of a think step (flinch, rest, pack). Returns true when
## they decided it.
func _kit_think(f: Fighter, sim: MatchSim, tgt: Fighter, dist: float, dir: Vector3, attacking: bool,
		my_reach: float, their_reach: float) -> bool:
	if personality.is_empty():
		return false
	var flinch := float(personality.get("ally_ko_flinch", 0.0))
	if flinch > 0.0:
		if _ev_cursor < 0:
			_ev_cursor = sim.event_seq
		for ev in sim.events_since(_ev_cursor):
			_ev_cursor = int(ev["seq"])
			if str(ev["type"]) != "ko":
				continue
			var ki := int(ev.get("fighter", -1))
			if ki >= 0 and ki < sim.fighters.size() and ki != f.index:
				var k: Fighter = sim.fighters[ki]
				if k.team == f.team and k.pos().distance_to(f.pos()) < 3.0:
					_flinch_until = _t + flinch
		if _t < _flinch_until:
			_move = Vector3.ZERO
			_guard = false
			return true
	var rest = personality.get("rest", [])
	if rest is Array and (rest as Array).size() >= 2 and (f.state == Fighter.State.ATTACK or f.state == Fighter.State.ABILITY) \
			and f.move != null and f.state_time > _kit_last_threat(f.move) + 0.05:
		return true   # nothing new is queued in a recovery: the rest follows the move
	if _t < _rest_until and f.state == Fighter.State.NEUTRAL:
		if _t >= _strafe_until:
			_strafe = -1.0 if rng.randf() < 0.5 else 1.0
			_strafe_until = _t + rng.randf_range(0.6, 1.6)
		var circle := dir.cross(Vector3.UP) * _strafe * 0.45
		_move = (circle + dir * 0.5).normalized() * 0.6 if dist > my_reach + 1.0 else circle
		return true
	var pack := int(personality.get("pack", 0))
	if pack > 0 and _kit_range().is_empty() and not _kit_pack_attacker(f, sim, tgt, pack):
		_kit_pack_hold(f, dist, dir, attacking, their_reach)
		return true
	return false


## How much closer than its root a "bulky" target's body is to this unit (metres, less a 0.25 m
## allowance for segment thickness), added to the unit's reach. 0 for ordinary bodies.
func _kit_target_bulk(f: Fighter, tgt: Fighter) -> float:
	if tgt == null or tgt.rig == null or not bool(tgt.creature.ai.get("bulky", false)):
		return 0.0
	var me := Vector3(f.pos().x, 0.0, f.pos().z)
	var root_d := me.distance_to(Vector3(tgt.pos().x, 0.0, tgt.pos().z))
	var nearest := root_d
	for b in tgt.rig.bodies:
		var bp: Vector3 = b.global_position
		nearest = minf(nearest, me.distance_to(Vector3(bp.x, 0.0, bp.z)))
	return maxf(0.0, root_d - nearest - 0.25)


## True when a bulky target's perceived move is past its last threat (hit windows, lunges and
## timed effects, landing included, + 0.1 s): its recovery is an opening, not a threat.
func _kit_opening(per: Dictionary, tgt: Fighter) -> bool:
	if tgt == null or not bool(tgt.creature.ai.get("bulky", false)):
		return false
	var slot := str(per.get("slot", ""))
	var m: MoveDef = tgt.creature.moves.get(slot, tgt.creature.abilities.get(slot))
	if m == null:
		return false
	return float(per.get("st", 0.0)) > _kit_last_threat(m) + 0.1


## Time of a move's last threat: its last hit window, lunge or timed effect (landing included).
static func _kit_last_threat(m: MoveDef) -> float:
	var last := 0.0
	for w in m.windows:
		last = maxf(last, float(w["t1"]))
	for l in m.lunges:
		last = maxf(last, float(l[1]))
	for e in m.effects:
		last = maxf(last, float(e.get("t", 0.0)) + float(e.get("time", 0.0)) + float(e.get("delay", 0.0)))
	return last


func _kit_ability_ready(f: Fighter, slot: String) -> bool:
	return f.creature.abilities.has(slot) and int(f.charges_left.get(slot, 1)) > 0 and not bool(f.mods.get("no_abilities", false))


## An ally within `r` m currently performing ability `slot`, or null.
func _kit_ally_using(f: Fighter, slot: String, r: float) -> Fighter:
	if f.sim == null:
		return null
	for o: Fighter in f.sim.fighters:
		if o == f or o.despawned or o.is_out() or o.team != f.team:
			continue
		if o.state == Fighter.State.ABILITY and o.move_slot.split("@")[0] == slot and o.pos().distance_to(f.pos()) < r:
			return o
	return null


## True when `f` is one of the `n` pack members closest to the target (only they attack).
func _kit_pack_attacker(f: Fighter, sim: MatchSim, tgt: Fighter, n: int) -> bool:
	var mine := f.pos().distance_to(tgt.pos())
	var closer := 0
	for o: Fighter in sim.fighters:
		if o == f or o.despawned or o.is_out() or o.team != f.team or o.target != tgt:
			continue
		var oai: Dictionary = o.creature.ai
		if int(oai.get("pack", 0)) <= 0 or oai.has("range") or float(oai.get("keep_distance", 0.0)) > 0.0 \
				or str(oai.get("prefers", "")) == "ranged":
			continue
		if o.pos().distance_to(tgt.pos()) < mine:
			closer += 1
	return closer < n


## Waiting pack member: hold a ring around the target, drift toward its flank, shield up when
## it swings this way.
func _kit_pack_hold(f: Fighter, dist: float, dir: Vector3, attacking: bool, their_reach: float) -> void:
	var ring := float(personality.get("pack_ring", 2.2))
	if _t >= _strafe_until:
		_strafe = -1.0 if rng.randf() < 0.5 else 1.0
		_strafe_until = _t + rng.randf_range(0.6, 1.8)
	var side := dir.cross(Vector3.UP) * _strafe
	if dist < ring - 0.3:
		_move = (-dir + side * 0.6).normalized()
	elif dist > ring + 0.6:
		_move = (dir + side * 0.4).normalized()
	else:
		_move = side * 0.7
	if attacking and dist < their_reach + 0.8:
		var g := str(personality.get("pack_guard", "guard"))
		if g.begins_with("ability") and _kit_ability_ready(f, g):
			f.input.press(FighterInput.AB1 if g == "ability1" else FighterInput.AB2)
		else:
			_guard = true
			_guard_until = _t + 0.5
			f.input.press(FighterInput.GUARD)
