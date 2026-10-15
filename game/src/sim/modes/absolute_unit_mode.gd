class_name AbsoluteUnitMode
extends MatchMode
## ABSOLUTE UNIT (docs/design/MODES.md §2.3): one fighter is the Unit — 1.6× size, 3× mass,
## 2.5× HP, armor vs Lights, +50% damage/knockback dealt, no dodge, 2× ability cooldowns, no JUICE,
## −15% walk speed. The Unit scores 1 point/s. Whoever KOs the Unit becomes the next Unit after a
## 2 s transformation. Free-for-all; first to the target or most at time wins.

const UNIT_SCALE := 1.6
const UNIT_WEIGHT := 3.0

var unit: Fighter = null
var _pending: Fighter = null
var _pending_at := -1.0
var _base_creature := {}         ## fighter index -> original CreatureDef id
var _base_mods := {}             ## fighter index -> mods snapshot before becoming the Unit
var _last_hit_by_unit := 0.0


func id() -> String:
	return "absolute_unit"


func setup(match_sim) -> void:
	var defaults := {"round_time": 300.0, "rounds": 1, "win": "score", "score_target": 90, "respawn": true,
		"respawn_delay": 4.0, "unit_scale": UNIT_SCALE, "unit_weight": UNIT_WEIGHT, "unit_hp": 2.5, "hot_potato": false, "unit_juice": false}
	for k in defaults:
		if not match_sim.rules.has(k):
			match_sim.rules[k] = defaults[k]
	super.setup(match_sim)
	for f: Fighter in sim.fighters:
		scores[f.team] = 0.0
		_base_creature[f.index] = f.creature.id


func tick(dt: float) -> void:
	var was_intro := phase == Phase.INTRO
	super.tick(dt)
	if was_intro and phase == Phase.FIGHT and unit == null and _pending == null:
		var pool := sim.active_fighters()
		if not pool.is_empty():
			_pending = pool[sim.rng.randi_range(0, pool.size() - 1)]
			_pending_at = sim.time + 0.2


func _unit_spawn() -> Array:
	var us := sim.arena.marker_points("unit_spawn")
	var p: Vector3 = us[0] if not us.is_empty() else Vector3.ZERO
	return [p, 0.0]


func _make_unit(f: Fighter) -> void:
	var scaled := Content.scaled_creature(str(_base_creature.get(f.index, f.creature.id)), float(rules["unit_scale"]), float(rules["unit_weight"]))
	if scaled == null:
		return
	_base_mods[f.index] = f.mods.duplicate()
	var sp := _unit_spawn()
	if f.is_out():
		f.respawn(sp[0], sp[1])
	f.rebuild(scaled, sp[0], sp[1])
	f.mods["damage"] = float(f.mods["damage"]) * 1.5
	f.mods["knockback_dealt"] = float(f.mods["knockback_dealt"]) * 1.5
	f.mods["speed"] = float(f.mods["speed"]) * 0.85
	f.mods["cooldown"] = float(f.mods["cooldown"]) * 0.5
	f.mods["no_juice"] = not bool(rules["unit_juice"])
	f.max_health = f.creature.stat("health") * float(rules["unit_hp"])
	f.health = f.max_health
	f.statuses.add({"id": "absolute_unit", "name": "Absolute Unit", "duration": 1e9, "armor_lights": true, "no_dodge": true})
	f.invuln_until = f.time + 1.0
	unit = f
	_last_hit_by_unit = sim.time
	sim.emit_event({"type": "unit_crowned", "fighter": f.index})


func _unmake_unit(f: Fighter) -> void:
	if _base_mods.has(f.index):
		f.mods = _base_mods[f.index]
		_base_mods.erase(f.index)
	f.statuses.remove("absolute_unit")
	var base := Content.creature(str(_base_creature.get(f.index, f.creature.id)))
	if base and base != f.creature:
		f.rebuild(base, f.pos(), f.facing_yaw)
	if unit == f:
		unit = null


func on_depleted(f: Fighter, attacker: Fighter, hit: Dictionary) -> void:
	if f == unit:
		var heir := attacker if attacker and attacker != f and not attacker.despawned else sim.last_attacker_of(f)
		f.knock_out(attacker)
		sim.emit_event({"type": "unit_toppled", "fighter": f.index, "by": heir.index if heir else -1})
		unit = null
		_unmake_unit_later(f)
		if heir and heir != f:
			heir.stats_record["kos"] += 1
			_pending = heir
			_pending_at = sim.time + 2.0
			heir.invuln_until = heir.time + 2.0
			sim.emit_event({"type": "unit_transforming", "fighter": heir.index})
		else:
			_pending = null
		queue_respawn(f, float(rules["respawn_delay"]))
		return
	super.on_depleted(f, attacker, hit)


func _unmake_unit_later(f: Fighter) -> void:
	# swap back to the normal body while knocked out so it respawns at normal size
	if _base_mods.has(f.index):
		f.mods = _base_mods[f.index]
		_base_mods.erase(f.index)
	f.statuses.remove("absolute_unit")
	var base := Content.creature(str(_base_creature.get(f.index, f.creature.id)))
	if base and base != f.creature:
		f.rebuild(base, f.pos(), f.facing_yaw)
		f.knock_out(null)


func on_ringout(f: Fighter, attacker: Fighter) -> void:
	if f == unit:
		f.health = 0.0
		on_depleted(f, attacker if attacker else sim.last_attacker_of(f), {"ringout": true})
		return
	super.on_ringout(f, attacker)


func tick_fight(dt: float) -> void:
	if _pending and sim.time >= _pending_at:
		var p := _pending
		_pending = null
		if not p.despawned:
			_make_unit(p)
	if unit and not unit.is_out():
		scores[unit.team] = float(scores.get(unit.team, 0.0)) + dt
		if bool(rules["hot_potato"]):
			for ev in sim.events_since(maxi(0, sim.event_seq - 8)):
				if ev["type"] == "hit" and int(ev.get("fighter", -1)) == unit.index:
					_last_hit_by_unit = sim.time
			if sim.time - _last_hit_by_unit > 5.0:
				scores[unit.team] = maxf(0.0, float(scores[unit.team]) - 1.0)
				_last_hit_by_unit = sim.time
		if float(scores[unit.team]) >= float(rules["score_target"]):
			end_round(unit.team)


func check_round_over() -> void:
	pass


func choose_respawn(f: Fighter) -> Array:
	var avoid := unit.pos() if unit and not unit.is_out() else Vector3.INF
	return sim.safe_spawn_for(f, avoid, 6.0)


func hud_status() -> String:
	if _pending:
		return "%s is drinking the whole crate..." % _pending.display_name
	if unit:
		return "%s is the ABSOLUTE UNIT — take them down!" % unit.display_name
	return "Waiting for a Unit"


func hud_state() -> Dictionary:
	var rows := []
	for f: Fighter in sim.fighters:
		if f.despawned:
			continue
		rows.append({"label": f.display_name, "value": int(floor(float(scores.get(f.team, 0.0)))), "team": f.team, "highlight": f == unit})
	rows.sort_custom(func(a, b): return a["value"] > b["value"])
	var u := {}
	if unit:
		u = {"fighter": unit.index, "health": unit.health, "max_health": unit.max_health, "name": unit.display_name}
	return {"rows": rows, "status": hud_status(), "target": int(rules["score_target"]), "unit": u}


func view_state() -> Dictionary:
	var v := super.view_state()
	v["unit"] = unit.index if unit else -1
	v["pending"] = _pending.index if _pending else -1
	return v


func bot_objective(f: Fighter) -> Dictionary:
	if unit == null or unit.is_out():
		return {}
	if f == unit:
		# the Unit hunts whoever is leading
		var best: Fighter = null
		var bv := -1.0
		for o: Fighter in sim.fighters:
			if o != f and not o.is_out() and not o.despawned and float(scores.get(o.team, 0.0)) > bv:
				bv = float(scores.get(o.team, 0.0))
				best = o
		return {"target": best.index} if best else {}
	return {"pos": unit.pos(), "engage": 3.5, "target": unit.index}
