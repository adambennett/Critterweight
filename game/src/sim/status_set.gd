class_name StatusSet
extends RefCounted
## Elemental build-up meters, active statuses (element statuses, buffs, debuffs, restrictions)
## and the aggregated multipliers/flags they impose on their fighter (docs/design/ELEMENTS.md §2).
##
## Status dictionary fields (all optional): id, name, element, duration, dps, tick, cannot_kill,
## speed, dash, knockback_taken, push_taken, stamina_regen, heal, guard_cost, poise_max,
## poise_regen, dodge_cost, heavy_poise_taken, cooldown_rate, damage_taken, damage_dealt,
## pulse_interval, pulse_stun, hit_buildup {el: amount}, buildup_received {el: mult},
## flags: no_hover no_leap no_blink no_dodge no_guard grab_lock armor_lights armor_all,
## hooks [Hooks dicts active while the status lasts], source (Fighter), icon.

var fighter                          ## Fighter
var buildup := {}                    ## element -> amount
var _buildup_delay := {}             ## element -> seconds until decay starts
var active: Array = []               ## Array[Dictionary] (+ "left", "_tick", "_pulse")
var _immune := {}                    ## element -> seconds of post-status immunity
var _reaction_cd := 0.0


func _init(f) -> void:
	fighter = f


static func rule(key: String, fallback: float) -> float:
	return float(Elements.rules.get(key, fallback))


func clear() -> void:
	for s in active:
		if s.has("hooks"):
			fighter.hooks.remove_source("status:" + str(s.get("id", "")))
	buildup.clear()
	_buildup_delay.clear()
	active.clear()
	_immune.clear()
	_reaction_cd = 0.0


func has(id: String) -> bool:
	for s in active:
		if s.get("id", "") == id:
			return true
	return false


func has_element(el: String) -> bool:
	for s in active:
		if s.get("element", "") == el:
			return true
	return false


func get_status(id: String) -> Dictionary:
	for s in active:
		if s.get("id", "") == id:
			return s
	return {}


func element_status(el: String) -> Dictionary:
	for s in active:
		if s.get("element", "") == el:
			return s
	return {}


## Adds elemental build-up from `source` (Fighter or null). `scale` already includes guard (0.5)
## and resist/weak multipliers when called from Combat.
func add_buildup(element: String, amount: float, source, scale := 1.0) -> void:
	if element == "" or amount <= 0.0 or fighter.is_out() or fighter.is_down():
		return
	if not Elements.defs.has(element):
		return
	# fighters never suffer their own primary element's status from their own attacks
	if source == fighter and fighter.creature.element == element:
		return
	if float(_immune.get(element, 0.0)) > 0.0:
		return
	var mult := scale * _received_mult(element) * float(fighter.mods.get("buildup_taken", 1.0))
	if fighter.flags.get("boss", false) and fighter.creature.element == element:
		return
	buildup[element] = float(buildup.get(element, 0.0)) + amount * mult
	_buildup_delay[element] = rule("decay_delay", 1.5)
	if float(buildup[element]) >= rule("threshold", 100.0):
		buildup[element] = 0.0
		_trigger_element(element, source)


func _received_mult(element: String) -> float:
	var m := 1.0
	for s in active:
		var br: Dictionary = s.get("buildup_received", {})
		if br.has(element):
			m *= float(br[element])
	return m


func _trigger_element(element: String, source) -> void:
	var edef: Dictionary = Elements.defs.get(element, {})
	var st: Dictionary = edef.get("status", {}).duplicate(true)
	if st.is_empty():
		return
	st["element"] = element
	if not st.has("id"):
		st["id"] = "status_" + element
	st["source"] = source
	# reactions: an incoming element meeting another element's active status
	var reacted := false
	if _reaction_cd <= 0.0:
		for other in active.duplicate():
			var oel: String = other.get("element", "")
			if oel == "" or oel == element:
				continue
			var r := Elements.reaction(element, oel)
			if r.is_empty():
				continue
			reacted = true
			_reaction_cd = rule("reaction_cooldown", 1.5)
			var consumes := str(r.get("consumes", "present"))
			if consumes == "both" or consumes == oel or consumes == "present":
				_remove(other)
			if fighter.sim:
				fighter.sim.effects.trigger_reaction(r, fighter, source, element, oel)
			if consumes == "both" or consumes == element:
				_immune[element] = rule("post_status_immunity", 2.0)
				return
			break
	if has_element(element):
		refresh_element(element)
		return
	add(st)
	if fighter.sim:
		fighter.sim.emit_event({"type": "status", "fighter": fighter.index, "status": st["id"], "element": element, "reacted": reacted})
		if source and source != fighter:
			source.hooks.fire("status_applied", {"other": fighter, "element": element, "status": st["id"]})
		fighter.hooks.fire("status_received", {"other": source, "element": element, "status": st["id"]})


func refresh_element(element: String) -> void:
	for s in active:
		if s.get("element", "") == element:
			s["left"] = float(s.get("duration", 3.0))


## Adds (or refreshes) a status/buff. Max simultaneous element statuses = rules.max_statuses.
func add(st: Dictionary) -> void:
	var id: String = st.get("id", "")
	for s in active:
		if s.get("id", "") == id and id != "":
			s["left"] = maxf(float(s["left"]), float(st.get("duration", 3.0)))
			return
	if str(st.get("element", "")) != "":
		var count := 0
		var oldest: Dictionary = {}
		for s in active:
			if str(s.get("element", "")) != "":
				count += 1
				if oldest.is_empty():
					oldest = s
		if count >= int(rule("max_statuses", 3.0)) and not oldest.is_empty():
			_remove(oldest)
	var copy := st.duplicate()
	if str(st.get("element", "")) != "":
		# build modifiers (e.g. a side effect) may lengthen elemental statuses on this fighter
		copy["duration"] = float(st.get("duration", 3.0)) * float(fighter.mods.get("status_duration_taken", 1.0))
	copy["left"] = float(copy.get("duration", 3.0))
	copy["_tick"] = 0.0
	copy["_pulse"] = 0.0
	active.append(copy)
	if copy.has("hooks"):
		for h in copy["hooks"]:
			fighter.hooks.add(h, "status:" + id, copy["left"])


func _remove(s: Dictionary) -> void:
	active.erase(s)
	if s.has("hooks"):
		fighter.hooks.remove_source("status:" + str(s.get("id", "")))
	var el := str(s.get("element", ""))
	if el != "":
		_immune[el] = rule("post_status_immunity", 2.0)


func remove(id: String) -> void:
	for s in active.duplicate():
		if s.get("id", "") == id:
			_remove(s)


func remove_element(el: String) -> void:
	for s in active.duplicate():
		if s.get("element", "") == el:
			_remove(s)


func cleanse_elements() -> void:
	for s in active.duplicate():
		if str(s.get("element", "")) != "":
			_remove(s)
	buildup.clear()


## Remaining damage-over-time of an element status (for Dilute/Catalyze bursts).
func remaining_dot(el: String) -> float:
	var s := element_status(el)
	if s.is_empty():
		return 0.0
	return float(s.get("dps", 0.0)) * float(s.get("left", 0.0))


func tick(dt: float) -> void:
	_reaction_cd = maxf(0.0, _reaction_cd - dt)
	for el in _immune.keys():
		_immune[el] = float(_immune[el]) - dt
		if float(_immune[el]) <= 0.0:
			_immune.erase(el)
	for el in buildup.keys():
		var d := float(_buildup_delay.get(el, 0.0)) - dt
		_buildup_delay[el] = d
		if d <= 0.0:
			buildup[el] = maxf(0.0, float(buildup[el]) - rule("decay_per_s", 15.0) * dt)
	if active.is_empty():
		return
	for s in active.duplicate():
		s["left"] = float(s["left"]) - dt
		var dps := float(s.get("dps", 0.0)) * float(s.get("dps_mult", 1.0))
		if dps > 0.0 and not fighter.is_out():
			var tick_len := float(s.get("tick", 0.5))
			s["_tick"] = float(s["_tick"]) + dt
			if float(s["_tick"]) >= tick_len:
				s["_tick"] = float(s["_tick"]) - tick_len
				if fighter.sim:
					var no_kill: bool = bool(s.get("cannot_kill", false)) or bool(fighter.is_down())
					fighter.sim.combat.apply_dot(s.get("source"), fighter, dps * tick_len, str(s.get("id", "")), str(s.get("element", "")), no_kill)
		var pulse := float(s.get("pulse_interval", 0.0))
		if pulse > 0.0 and not fighter.is_out():
			s["_pulse"] = float(s["_pulse"]) + dt
			if float(s["_pulse"]) >= pulse:
				s["_pulse"] = 0.0
				fighter.flinch(float(s.get("pulse_stun", 0.15)))
		if float(s["left"]) <= 0.0:
			_remove(s)


func _product(key: String) -> float:
	var m := 1.0
	for s in active:
		if s.has(key):
			m *= float(s[key])
	return m


func mult(key: String) -> float:
	return _product(key)


func flag(name_: String) -> bool:
	for s in active:
		if bool(s.get(name_, false)):
			return true
	return false


func speed_mult() -> float:
	return _product("speed")


func damage_taken_mult() -> float:
	return _product("damage_taken")


func damage_dealt_mult() -> float:
	return _product("damage_dealt")


func heal_mult() -> float:
	return _product("heal")


func stamina_regen_mult() -> float:
	return _product("stamina_regen")


func knockback_taken_mult() -> float:
	return _product("knockback_taken")


## Extra build-up the attacker's hit adds because of statuses on this fighter (Sizzle feeds fire).
func hit_buildup_bonus() -> Dictionary:
	var out := {}
	for s in active:
		var hb: Dictionary = s.get("hit_buildup", {})
		for el in hb:
			out[el] = float(out.get(el, 0.0)) + float(hb[el])
	return out


func summary() -> Array:
	var out := []
	for s in active:
		out.append({"id": s.get("id", ""), "name": s.get("name", s.get("id", "")), "element": s.get("element", ""), "left": s["left"]})
	return out


func buildup_summary() -> Dictionary:
	return buildup.duplicate()
