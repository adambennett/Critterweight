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
}

## Chance that a chosen Heavy is held into a Charged Heavy (lower tiers never charge).
const CHARGE_CHANCE := {"rookie": 0.0, "regular": 0.25, "pro": 0.4, "champion": 0.5}

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
var _kit_hold_until := 0.0        ## kit rule committed the stick (e.g. dive away): skip thinking
var _charge_until := 0.0          ## holding Heavy to charge it until this time


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
	# presses set their button's held bit; release them after the press tick so a Heavy is only
	# charged when the bot means to (it holds Heavy while _charge_until is running)
	f.input.held &= ~((1 << FighterInput.LIGHT) | (1 << FighterInput.HEAVY) | (1 << FighterInput.DODGE))
	if _t >= _next_think:
		_next_think = _t + float(p["think"]) * rng.randf_range(0.7, 1.3)
		_think(f, sim)
	f.input.set_held(FighterInput.HEAVY, _t < _charge_until)
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
	if _t < _kit_hold_until:
		return
	var my_reach := float(personality.get("reach", reach_of(c, "l1")))
	var their_reach := reach_of(tgt.creature, "heavy") if tgt else 1.0
	var mistake := rng.randf() < float(p["mistake"])
	# ---- defence: react to a perceived windup ----
	var per_state := int(per.get("state", Fighter.State.NEUTRAL))
	var attacking := per_state == Fighter.State.ATTACK or per_state == Fighter.State.ABILITY
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
	# ---- JUICE ----
	if f.hype >= 100.0 and rng.randf() < float(p["juice"]) * 0.5 and dist < 3.5:
		f.input.press(FighterInput.JUICE)
		return
	# ---- abilities ----
	if _kit_actions(f, tgt, dist, dir, per):
		return
	var rules: Dictionary = personality.get("abilities", {})
	for slot in ["ability1", "ability2"]:
		if rules.has(slot):
			continue   # the kit's own rule (above) decides this slot
		if c.abilities.has(slot) and float(f.cooldown_left.get(slot, 0.0)) <= 0.0 and rng.randf() < float(p["ability"]) * 0.35:
			var ar := reach_of(c, slot, true)
			if dist <= ar and dist >= minf(1.2, ar * 0.3):
				f.input.press(FighterInput.AB1 if slot == "ability1" else FighterInput.AB2)
				return
	# ---- don't idle in the opponent's puddles / patches ----
	if dist > my_reach + 0.4 and _avoid_enemy_zone(f, sim, dir):
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
			if rng.randf() < float(CHARGE_CHANCE.get(difficulty, 0.25)):
				_charge_until = _t + rng.randf_range(0.5, 1.0)
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
	var band = personality.get("range")
	if typeof(band) == TYPE_ARRAY and (band as Array).size() == 2 and f.stamina >= 15.0:
		# kit preferred distance band (zoners keep away, rushdown stays close)
		var lo := float(band[0])
		var hi := float(band[1])
		want = clampf(want, lo, hi) if dist <= my_reach + 0.1 else (lo + hi) * 0.5
		if dist >= lo and dist <= hi:
			want = dist
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


# =====================================================================================
# Kit-driven extras (data from the creature "ai" block; generic, never by fighter id)
#   reach: m                  melee reach of the light string (joint-driven bodies)
#   range: [lo, hi]           preferred distance band for footwork
#   abilities: {slot: {min, max, chance, poise_below, target_down, away}}
#   heavy_vs_windup: p        Heavy when the target shows a long startup (> 0.3 s left)
#   dash_in: {min, max, chance}  dodge toward the target then Light (dash attack)
# =====================================================================================

## Steps out of an enemy zone that hurts or builds up (puddles, patches) instead of idling in it,
## sideways relative to the target so the bot keeps facing the fight. Skill-scaled (spacing).
func _avoid_enemy_zone(f: Fighter, sim: MatchSim, dir: Vector3) -> bool:
	if rng.randf() >= float(p["spacing"]):
		return false
	var fp := f.pos()
	for z in sim.effects.entities:
		if str(z["kind"]) != "zone" or int(z["owner"]) < 0 or int(z["team"]) == f.team:
			continue
		var e: Dictionary = z["e"]
		if float(e.get("tick_damage", 0.0)) <= 0.0 and float(e.get("buildup", 0.0)) <= 0.0:
			continue
		var off := Vector3(fp.x - float(z["pos"].x), 0.0, fp.z - float(z["pos"].z))
		if off.length() > float(z["radius"]) + 0.3:
			continue
		var out := off.normalized() if off.length_squared() > 1e-4 else dir.cross(Vector3.UP)
		var side := dir.cross(Vector3.UP)
		_move = (out + side * (1.0 if side.dot(out) >= 0.0 else -1.0) * 0.5).normalized()
		return true
	return false


func _kit_actions(f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary) -> bool:
	var c := f.creature
	var rules: Dictionary = personality.get("abilities", {})
	for slot in ["ability1", "ability2"]:
		if not rules.has(slot) or not c.abilities.has(slot):
			continue
		var r: Dictionary = rules[slot]
		if int(f.charges_left.get(slot, 1)) <= 0:
			continue
		if dist < float(r.get("min", 0.0)) or dist > float(r.get("max", 99.0)):
			continue
		if r.has("poise_below") and f.poise / maxf(1.0, f.effective_max_poise()) >= float(r["poise_below"]):
			continue
		if bool(r.get("target_down", false)) and not tgt.is_down():
			continue
		if rng.randf() >= float(r.get("chance", 0.5)) * float(p["ability"]):
			continue
		if bool(r.get("away", false)):
			_move = -dir
			_kit_hold_until = _t + 0.35
		f.input.press(FighterInput.AB1 if slot == "ability1" else FighterInput.AB2)
		return true
	var hw := float(personality.get("heavy_vs_windup", 0.0))
	if hw > 0.0 and f.state == Fighter.State.NEUTRAL and dist <= float(personality.get("heavy_reach", 2.2)):
		var st := int(per.get("state", Fighter.State.NEUTRAL))
		var left := float(per.get("first", 0.0)) - float(per.get("st", 0.0))
		if (st == Fighter.State.ATTACK or st == Fighter.State.ABILITY) and left > 0.3 and rng.randf() < hw:
			f.input.press(FighterInput.HEAVY)
			return true
	var di: Dictionary = personality.get("dash_in", {})
	if not di.is_empty() and f.state == Fighter.State.NEUTRAL and dist >= float(di.get("min", 2.0)) and dist <= float(di.get("max", 3.0)):
		if f.stamina > 25.0 and rng.randf() < float(di.get("chance", 0.2)) * float(p["aggression"]):
			_move = dir
			_kit_hold_until = _t + 0.3
			f.input.press(FighterInput.DODGE)
			_queue(FighterInput.LIGHT, 0.14)
			return true
	return false


func _toward(from: Vector3, to: Vector3) -> Vector3:
	var d := to - from
	d.y = 0.0
	return d.normalized() if d.length() > 0.2 else Vector3.ZERO
