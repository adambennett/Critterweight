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
	if _npc_pre_poll(f):
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
	f.input.move = _move
	f.input.set_held(FighterInput.GUARD, _guard and _t < _guard_until)
	f.input.set_held(FighterInput.GRAB, _t < _hold_until)
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
	var authored: Dictionary = c.ai.get("reach", {})   # NPC-kit extension: bodies whose strikes come from bending
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
	var my_reach := reach_of(c, "l1") + _npc_target_bulk(f, tgt)
	var their_reach := reach_of(tgt.creature, "heavy") if tgt else 1.0
	var mistake := rng.randf() < float(p["mistake"])
	# ---- defence: react to a perceived windup ----
	var per_state := int(per.get("state", Fighter.State.NEUTRAL))
	var attacking := (per_state == Fighter.State.ATTACK or per_state == Fighter.State.ABILITY) and not _npc_opening(per, tgt)
	var winding := attacking and float(per.get("st", 0.0)) < float(per.get("first", 0.0))
	if attacking and dist < their_reach + 0.6 and not mistake and f.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD]:
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
	if _npc_think(f, sim, tgt, dist, dir, attacking and not mistake, winding, my_reach, their_reach):
		return
	# ---- JUICE ----
	if f.hype >= 100.0 and rng.randf() < float(p["juice"]) * 0.5 and dist < 3.5:
		f.input.press(FighterInput.JUICE)
		return
	# ---- abilities ----
	for slot in ["ability1", "ability2"]:
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
		elif f.state == Fighter.State.ATTACK and f.move_slot in ["l1", "l2"] and rng.randf() < float(p["combo"]):
			if f.move_slot == "l2" and rng.randf() < 0.4:
				f.input.press(FighterInput.HEAVY)
			else:
				f.input.press(FighterInput.LIGHT)
		elif rng.randf() < 0.28:
			f.input.press(FighterInput.HEAVY)
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
# Personality extensions for NPC kits (Kid Lamprey, minions, bosses; docs/kits/*.md).
# Optional keys of a creature's "ai" block:
#   charge          offset to the tier's chance to HOLD a Heavy into its charged version
#                   (CHARGE_BY_TIER: Punching Bag never charges)
#   keep_distance   metres a ranged unit keeps ("prefers": "ranged" alone means 4 m); it fires
#                   its ranged ability ("ranged_slot", default the longest-reaching one) between
#   pack            at most this many allies with a "pack" key attack one target at once; the
#                   rest wait at "pack_ring" m (default 2.2), circling toward the target's flank,
#                   and raise "pack_guard" (an ability slot, or "guard") when it swings at them
#   ability_space   {slot: metres}: never start that ability within that distance of an ally
#                   who is using it (Blisters never inflate next to an inflating Blister)
#   counter_slot    ability answering a perceived wind-up the generic defence did not answer,
#                   with probability "counter_chance" (default 0.5) scaled by the tier's block
#   ally_ko_flinch  seconds the unit freezes after an ally within 3 m is knocked out
#   reach           {slot: metres} authored reach for slots whose strike comes from bending a
#                   long body rather than lunging (read by reach_of before its geometric guess)
#   rest            [min, max] seconds the unit waits after each of its own attacks/abilities
#                   before it starts another (it only circles meanwhile): the breather after a big
#                   boss move that keeps its rhythm readable and leaves the punish window
#   bulky           true on a big body (bosses): bots fighting it measure their reach to its
#                   nearest body part instead of its root (its head or shell is in reach long
#                   before its root is), and treat the recovery of its long moves (after the last
#                   hit window / effect) as the opening to punish instead of a threat to dodge.
#                   Read from the TARGET's ai block; fights between ordinary bodies are unchanged.
# Momentary buttons are released every tick (pressing alone used to leave Heavy held down for
# good, turning every bot Heavy into a full charge); Heavy is held only for a deliberate charge.
# =====================================================================================

const CHARGE_BY_TIER := {"rookie": 0.0, "regular": 0.2, "pro": 0.35, "champion": 0.45, "hall_of_famer": 0.5}
const MOMENTARY := [FighterInput.LIGHT, FighterInput.HEAVY, FighterInput.DODGE, FighterInput.AB1,
	FighterInput.AB2, FighterInput.JUICE, FighterInput.TAUNT, FighterInput.TARGET, FighterInput.TAG]

var _charge_move: MoveDef = null     ## the Heavy whose charge decision was made
var _charge_st := 0.0                ## its state_time when last seen (a drop = a new move)
var _charge_to := 0.0                ## charge level to hold it to (0 = a tap)
var _flinch_until := -1.0
var _ev_cursor := -1
var _was_busy := false               ## attacking / using an ability last tick (for "rest")
var _rest_until := -1.0


## Every tick, before anything else: releases momentary buttons, holds Heavy for deliberate
## charges and freezes a flinching unit. Returns true when this tick is fully decided.
func _npc_pre_poll(f: Fighter) -> bool:
	var keep_heavy := false
	if f.state == Fighter.State.ATTACK and f.move != null and f.move_slot == "heavy" and f.move.charge_time > 0.0:
		if f.move != _charge_move or f.state_time + 1e-4 < _charge_st:
			_charge_move = f.move
			var chance := float(CHARGE_BY_TIER.get(difficulty, 0.2)) + float(personality.get("charge", 0.0))
			_charge_to = rng.randf_range(0.45, 1.0) if rng.randf() < chance else 0.0
		_charge_st = f.state_time
		keep_heavy = _charge_to > 0.0 and f.move_charge < _charge_to
	else:
		_charge_move = null
	for b in MOMENTARY:
		if b != FighterInput.HEAVY or not keep_heavy:
			f.input.set_held(b, false)
	if keep_heavy:
		f.input.set_held(FighterInput.HEAVY, true)
	var busy := f.state == Fighter.State.ATTACK or f.state == Fighter.State.ABILITY
	var rest: Array = personality.get("rest", [])
	if _was_busy and not busy and rest.size() >= 2:
		_rest_until = _t + rng.randf_range(float(rest[0]), float(rest[1]))
	_was_busy = busy
	if _t < _flinch_until:
		f.input.move = Vector3.ZERO
		f.input.held = 0
		return true
	return false


## Personality behaviours that replace the rest of a think step. Returns true when they decided it.
func _npc_think(f: Fighter, sim: MatchSim, tgt: Fighter, dist: float, dir: Vector3, attacking: bool,
		winding: bool, my_reach: float, their_reach: float) -> bool:
	if personality.is_empty():
		return false
	var c := f.creature
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
	var cslot := str(personality.get("counter_slot", ""))
	if cslot != "" and attacking and winding and dist < their_reach + 0.6 and _ability_ready(f, cslot):
		if rng.randf() < float(personality.get("counter_chance", 0.5)) * (0.4 + float(p["block"])):
			f.input.press(_ability_button(cslot))
			_move = Vector3.ZERO
			return true
	if _t < _rest_until and f.state == Fighter.State.NEUTRAL:
		if _t >= _strafe_until:
			_strafe = -1.0 if rng.randf() < 0.5 else 1.0
			_strafe_until = _t + rng.randf_range(0.6, 1.6)
		var circle := dir.cross(Vector3.UP) * _strafe * 0.45
		_move = (circle + dir * 0.5).normalized() * 0.6 if dist > my_reach + 1.0 else circle
		return true
	var space: Dictionary = personality.get("ability_space", {})
	for slot in space:
		var s := str(slot)
		if _ability_ready(f, s) and dist <= reach_of(c, s, true):
			var busy := _ally_using(f, sim, s, float(space[slot]))
			if busy != null:
				var away := f.pos() - busy.pos()
				away.y = 0.0
				_move = (away.normalized() + dir.cross(Vector3.UP) * 0.6).normalized()
				return true
	var kd := float(personality.get("keep_distance", 4.0 if str(personality.get("prefers", "")) == "ranged" else 0.0))
	if kd > 0.0:
		return _keep_distance(f, c, dist, dir, kd, my_reach)
	var pack := int(personality.get("pack", 0))
	if pack > 0 and not _pack_attacker(f, sim, tgt, pack):
		_pack_hold(f, dist, dir, attacking, their_reach)
		return true
	return false


## How much closer than its root a "bulky" target's body is to this unit (metres, less a 0.25 m
## allowance for segment thickness), added to the unit's reach. 0 for ordinary bodies.
func _npc_target_bulk(f: Fighter, tgt: Fighter) -> float:
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
func _npc_opening(per: Dictionary, tgt: Fighter) -> bool:
	if tgt == null or not bool(tgt.creature.ai.get("bulky", false)):
		return false
	var slot := str(per.get("slot", ""))
	var m: MoveDef = tgt.creature.moves.get(slot, tgt.creature.abilities.get(slot))
	if m == null:
		return false
	var last := 0.0
	for w in m.windows:
		last = maxf(last, float(w["t1"]))
	for l in m.lunges:
		last = maxf(last, float(l[1]))
	for e in m.effects:
		last = maxf(last, float(e.get("t", 0.0)) + float(e.get("time", 0.0)) + float(e.get("delay", 0.0)))
	return float(per.get("st", 0.0)) > last + 0.1


func _ability_button(slot: String) -> int:
	return FighterInput.AB1 if slot == "ability1" else FighterInput.AB2


func _ability_ready(f: Fighter, slot: String) -> bool:
	return f.creature.abilities.has(slot) and int(f.charges_left.get(slot, 1)) > 0 and not bool(f.mods.get("no_abilities", false))


## An ally within `r` m currently performing ability `slot`, or null.
func _ally_using(f: Fighter, sim: MatchSim, slot: String, r: float) -> Fighter:
	for o: Fighter in sim.fighters:
		if o == f or o.despawned or o.is_out() or o.team != f.team:
			continue
		if o.state == Fighter.State.ABILITY and o.move_slot.split("@")[0] == slot and o.pos().distance_to(f.pos()) < r:
			return o
	return null


## True when `f` is one of the `n` pack members closest to the target (only they attack).
func _pack_attacker(f: Fighter, sim: MatchSim, tgt: Fighter, n: int) -> bool:
	var mine := f.pos().distance_to(tgt.pos())
	var closer := 0
	for o: Fighter in sim.fighters:
		if o == f or o.despawned or o.is_out() or o.team != f.team or o.target != tgt:
			continue
		var oai: Dictionary = o.creature.ai
		if int(oai.get("pack", 0)) <= 0 or float(oai.get("keep_distance", 0.0)) > 0.0:
			continue
		if o.pos().distance_to(tgt.pos()) < mine:
			closer += 1
	return closer < n


## Waiting pack member: hold a ring around the target, drift toward its flank, shield up when
## it swings this way.
func _pack_hold(f: Fighter, dist: float, dir: Vector3, attacking: bool, their_reach: float) -> void:
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
		if g.begins_with("ability") and _ability_ready(f, g):
			f.input.press(_ability_button(g))
		else:
			_guard = true
			_guard_until = _t + 0.5
			f.input.press(FighterInput.GUARD)


## Ranged unit: fire the ranged ability between keep-distance footwork; fight back up close.
func _keep_distance(f: Fighter, c: CreatureDef, dist: float, dir: Vector3, kd: float, my_reach: float) -> bool:
	var slot := str(personality.get("ranged_slot", ""))
	if slot == "":
		var best := 0.0
		for s in ["ability1", "ability2"]:
			if c.abilities.has(s) and reach_of(c, s, true) > best:
				best = reach_of(c, s, true)
				slot = s
	if slot != "" and _ability_ready(f, slot) and dist >= 1.5 and dist <= reach_of(c, slot, true) and f.state == Fighter.State.NEUTRAL:
		if rng.randf() < 0.35 + float(p["ability"]) * 0.5:
			f.input.press(_ability_button(slot))
			_move = Vector3.ZERO
			return true
	if dist <= my_reach + 0.1 and rng.randf() < float(p["aggression"]) * 0.6:
		return false
	if _t >= _strafe_until:
		_strafe = -1.0 if rng.randf() < 0.5 else 1.0
		_strafe_until = _t + rng.randf_range(0.5, 1.6)
	var side := dir.cross(Vector3.UP) * _strafe
	if dist < kd - 0.6:
		_move = (-dir + side * 0.35).normalized()
	elif dist > kd + 0.8:
		_move = (dir + side * 0.25).normalized()
	else:
		_move = side * 0.6
	return true
