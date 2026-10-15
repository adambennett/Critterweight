class_name StatusSet
extends RefCounted
## Elemental build-up meters, active statuses (element statuses, buffs, debuffs) and the
## aggregated multipliers they impose on their fighter. Statuses are data: an element's
## "status" block in elements.json, or ad-hoc buffs created by abilities/upgrades/modes.
##
## Status dictionary fields (all optional): id, name, element, duration, dps, tick (s),
## speed, damage_taken, damage_dealt, heal, stamina_regen, pulse_stun, pulse_interval,
## knockback_taken, source (Fighter), icon.

const BUILDUP_THRESHOLD := 100.0
const BUILDUP_DECAY := 12.0          ## per second, after the delay
const BUILDUP_DELAY := 1.5
const IMMUNITY_AFTER := 1.5          ## same element cannot re-trigger for this long

var fighter                          ## Fighter
var buildup := {}                    ## element -> amount
var _buildup_delay := {}             ## element -> seconds until decay
var active: Array = []               ## Array[Dictionary] with "left", "_tick"
var _immune := {}                    ## element -> seconds


func _init(f) -> void:
	fighter = f


func clear() -> void:
	buildup.clear()
	_buildup_delay.clear()
	active.clear()
	_immune.clear()


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


func add_buildup(element: String, amount: float, source) -> void:
	if element == "" or amount <= 0.0 or fighter.is_out():
		return
	if float(_immune.get(element, 0.0)) > 0.0:
		return
	var resist := 1.0
	var edef: Dictionary = Elements.defs.get(element, {})
	if fighter.creature.element == element:
		resist = float(edef.get("self_buildup_mult", 0.5))
	buildup[element] = float(buildup.get(element, 0.0)) + amount * resist * float(fighter.mods.get("buildup_taken", 1.0))
	_buildup_delay[element] = BUILDUP_DELAY
	if float(buildup[element]) >= BUILDUP_THRESHOLD:
		buildup[element] = 0.0
		_trigger_element(element, source)


func _trigger_element(element: String, source) -> void:
	var edef: Dictionary = Elements.defs.get(element, {})
	var st: Dictionary = edef.get("status", {}).duplicate(true)
	if st.is_empty():
		return
	st["element"] = element
	if not st.has("id"):
		st["id"] = "status_" + element
	st["source"] = source
	# reactions with any other active element status
	var reacted := false
	for other in active.duplicate():
		var oel: String = other.get("element", "")
		if oel == "" or oel == element:
			continue
		var r := Elements.reaction(element, oel)
		if r.is_empty():
			continue
		reacted = true
		if fighter.sim:
			fighter.sim.effects.trigger_reaction(r, fighter, source, element, oel)
		if bool(r.get("consumes", true)):
			active.erase(other)
	_immune[element] = float(st.get("duration", 3.0)) + IMMUNITY_AFTER
	if reacted and bool(Elements.reaction(element, element).get("skip_status", false)):
		return
	add(st)
	if fighter.sim:
		fighter.sim.emit_event({"type": "status", "fighter": fighter.index, "status": st["id"], "element": element})


## Adds (or refreshes) a status/buff.
func add(st: Dictionary) -> void:
	var id: String = st.get("id", "")
	for s in active:
		if s.get("id", "") == id and id != "":
			s["left"] = maxf(float(s["left"]), float(st.get("duration", 3.0)))
			return
	var copy := st.duplicate()
	copy["left"] = float(st.get("duration", 3.0))
	copy["_tick"] = 0.0
	copy["_pulse"] = 0.0
	active.append(copy)


func remove(id: String) -> void:
	for s in active.duplicate():
		if s.get("id", "") == id:
			active.erase(s)


func tick(dt: float) -> void:
	for el in _immune.keys():
		_immune[el] = float(_immune[el]) - dt
		if float(_immune[el]) <= 0.0:
			_immune.erase(el)
	for el in buildup.keys():
		var d := float(_buildup_delay.get(el, 0.0)) - dt
		_buildup_delay[el] = d
		if d <= 0.0:
			buildup[el] = maxf(0.0, float(buildup[el]) - BUILDUP_DECAY * dt)
	if active.is_empty():
		return
	for s in active.duplicate():
		s["left"] = float(s["left"]) - dt
		var dps := float(s.get("dps", 0.0))
		if dps > 0.0 and not fighter.is_out():
			var tick_len := float(s.get("tick", 0.5))
			s["_tick"] = float(s["_tick"]) + dt
			if float(s["_tick"]) >= tick_len:
				s["_tick"] = float(s["_tick"]) - tick_len
				if fighter.sim:
					fighter.sim.combat.apply_simple_damage(s.get("source"), fighter, dps * tick_len, "status:" + str(s.get("id", "")), {"element": s.get("element", "")})
		var pulse := float(s.get("pulse_interval", 0.0))
		if pulse > 0.0 and not fighter.is_out():
			s["_pulse"] = float(s["_pulse"]) + dt
			if float(s["_pulse"]) >= pulse:
				s["_pulse"] = 0.0
				fighter.stun(float(s.get("pulse_stun", 0.15)), true)
		if float(s["left"]) <= 0.0:
			active.erase(s)


func _product(key: String) -> float:
	var m := 1.0
	for s in active:
		if s.has(key):
			m *= float(s[key])
	return m


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


func summary() -> Array:
	var out := []
	for s in active:
		out.append({"id": s.get("id", ""), "element": s.get("element", ""), "left": s["left"]})
	return out
