class_name BossMode
extends CampaignMatchMode
## Boss fights (ENEMIES_BOSSES.md §2), data-driven from content/core/boss_fights/*.json:
##   * two phases: phase 2 at phase2_at x max HP (0.5; 0.65 on Dose 8+). The transition is a 2 s
##     invulnerable beat that announces the phase, applies its arena changes (hazards added or
##     removed, props, speed) — a boss can never skip phase 2 by being depleted early;
##   * special attacks are scripted patterns built from the effects vocabulary: a telegraph
##     (>= 0.5 s, emitted as "boss_telegraph" with decal shape/position/name), timed actions
##     (area/projectile/zone/leap/dash/push/pull/delayed/prop/... plus the pattern actions below)
##     and a recovery window (the punish). BossBrain holds the boss during patterns; between them
##     its BotBrain uses the creature's own moveset;
##   * Dazed: poise break -> 3 s stagger (slack muscles), damage taken +20%, throws x2, and the
##     ONLY time a boss can be grabbed (boss_ungrabbable is cleared); poise then refills.
##     Other knockdown sources never floor a boss;
##   * arena interplay: leash (Bilge's chain), element cycle (Snappington), damage-triggered
##     repositioning (Conduit's Scrap Shuffle), co-op target rotation every 8 s, run modifiers
##     from events (start HP, skipped attack, player start Hype) and Film Room early tells.
## Pattern actions beyond EffectsSystem.TYPES: grab_throw, withdraw, aim, telegraph_only and
## rush {speed_mult, duration} (the boss runs at its aim point under a temporary speed buff).
## Any action may carry "yaw_offset" (degrees) to fire a facing-based shape at an angle.

const PATTERN_ACTIONS := ["grab_throw", "withdraw", "aim", "telegraph_only", "rush"]

var boss: Fighter
var brain: BossBrain
var bdata := {}
var phase_no := 1
var phases_allowed: Array = [1, 2]
var phase2_at := 0.5
var transitioning_until := -1.0
var dazed_until := -1.0
var _current := {}               ## running pattern
var _next_attack := 0.0
var _cooldowns := {}             ## attack id -> time
var _skip := {}                  ## attack id -> remaining skips (run modifiers)
var _damage_log: Array = []      ## [{t, dmg}] damage taken by the boss (reposition trigger)
var _element_i := -1
var _element_next := 0.0
var _rotate_next := 0.0
var _grab_release_at := -1.0
var _grabbable_until := -1.0
var _rush_until := -1.0
var _boss_events_cursor := 0
var _defeated := false
var tell_lead := 0.0


func id() -> String:
	return "boss"


func setup(match_sim) -> void:
	super.setup(match_sim)
	bdata = cfg.get("boss", {})
	phase2_at = float(cfg.get("phase2_at", bdata.get("phase2_at", 0.5)))
	tell_lead = float(cfg.get("tell_lead", 0.0))
	for f: Fighter in sim.fighters:
		if str(role_of(f).get("role", "")) == "boss":
			boss = f
			var ph: Array = role_of(f).get("phases", [])
			if not ph.is_empty():
				phases_allowed = ph
			break
	if boss == null:
		return
	var src = sim.input_sources[boss.index]
	brain = src if src is BossBrain else null
	boss.flags["boss"] = true
	boss.flags["boss_ungrabbable"] = true
	var mods: Dictionary = cfg.get("boss_mods", {})
	var frac := float(role_of(boss).get("start_hp_frac", 1.0)) * float(mods.get("start_hp_frac", 1.0))
	boss.health = boss.max_health * clampf(frac, 0.05, 1.0)
	if mods.has("skip_attack"):
		_skip[str(mods["skip_attack"])] = 1
	if float(mods.get("player_start_hype", 0.0)) > 0.0:
		for f2: Fighter in sim.fighters:
			if is_party(f2):
				f2.hype = maxf(f2.hype, float(mods["player_start_hype"]))
	_apply_phase_setup(_phase_data(1), false)


func _phase2_allowed() -> bool:
	for x in phases_allowed:
		if int(x) == 2:
			return true
	return false


func _phase_data(n: int) -> Dictionary:
	var phases: Array = bdata.get("phases", [])
	return phases[n - 1] if n >= 1 and n <= phases.size() else {}


func _apply_phase_setup(ph: Dictionary, announce: bool) -> void:
	if ph.is_empty():
		return
	for k in ph.get("remove_hazards", []):
		hazards.remove_kind(str(k))
	var lz: Dictionary = ph.get("leash", {})
	if not lz.is_empty():
		var a: Array = lz.get("anchor", [0.8, 0.0])
		hazards.anchor = Vector3(float(a[0]), 0.0, float(a[1])) * hazards.radius()
	for h in ph.get("hazards", []):
		if not hazards.has_kind(str(h.get("kind", ""))):
			hazards.add(h)
	if float(ph.get("speed_mult", 1.0)) != 1.0:
		boss.mods["speed"] = float(boss.mods["speed"]) * float(ph["speed_mult"])
	var ec: Dictionary = ph.get("element_cycle", {})
	if not ec.is_empty():
		_element_i = -1
		_element_next = sim.time
	if announce:
		sim.emit_event({"type": "boss_phase", "fighter": boss.index, "phase": phase_no, "name": str(ph.get("name", "")),
			"line": str(ph.get("transition", {}).get("line", ""))})


func _on_bell() -> void:
	super._on_bell()
	if boss:
		_next_attack = sim.time + 2.0
		_rotate_next = sim.time + float(bdata.get("target_rotate", 8.0))
		sim.emit_event({"type": "boss_intro", "fighter": boss.index, "name": str(bdata.get("name", boss.display_name)),
			"line": str(bdata.get("intro_line", ""))})


# =============================================================================================
# Tick
# =============================================================================================

func tick_fight(dt: float) -> void:
	super.tick_fight(dt)
	if boss == null or boss.is_out():
		if boss and boss.is_out() and not _defeated:
			_defeated = true
			sim.emit_event({"type": "boss_defeated", "fighter": boss.index, "line": str(bdata.get("defeat_line", ""))})
		return
	_scan_boss_events()
	# phase gate
	if phase_no == 1 and _phase2_allowed() and boss.health <= boss.max_health * phase2_at:
		_transition()
	if sim.time < transitioning_until:
		return
	if dazed_until > 0.0:
		if sim.time >= dazed_until:
			_end_daze()
		else:
			if boss.state == Fighter.State.NEUTRAL:
				boss.stun(dazed_until - sim.time, true)
			return
	if _grabbable_until > 0.0 and sim.time >= _grabbable_until:
		_grabbable_until = -1.0
		boss.flags["boss_ungrabbable"] = true
	_tick_grab()
	_tick_leash(dt)
	_tick_element_cycle()
	_tick_target_rotation()
	if not _current.is_empty():
		_run_pattern(dt)
	elif sim.time >= _next_attack and boss.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD]:
		_start_next_attack()


func _scan_boss_events() -> void:
	for ev in sim.events_since(_boss_events_cursor):
		_boss_events_cursor = int(ev["seq"])
		match str(ev.get("type", "")):
			"hit":
				if int(ev.get("target", -1)) == boss.index:
					_damage_log.append({"t": sim.time, "dmg": float(ev.get("damage", 0.0))})
			"throw":
				if int(ev.get("victim", -1)) == boss.index and dazed_until > sim.time:
					# throws on a Dazed boss deal double: add the throw's damage again
					var thrower: Fighter = sim.fighters[int(ev.get("fighter", 0))]
					var td: Dictionary = thrower.creature.throws.get(str(ev.get("kind", "throw_fwd")), {})
					var extra := float(td.get("damage", Tuning.v("throw_damage"))) * (float(bdata.get("dazed", {}).get("throw_mult", 2.0)) - 1.0)
					sim.combat.apply_simple_damage(thrower, boss, extra, "dazed_throw")
	while not _damage_log.is_empty() and sim.time - float(_damage_log[0]["t"]) > 3.0:
		_damage_log.pop_front()


func _transition() -> void:
	phase_no = 2
	var ph := _phase_data(2)
	var tr: Dictionary = ph.get("transition", {})
	var invuln := float(tr.get("invuln", 2.0))
	transitioning_until = sim.time + invuln
	boss.invuln_until = sim.time + invuln
	_cancel_pattern()
	if brain:
		brain.hold = true
		brain.move_override = Vector3.ZERO
	_apply_phase_setup(ph, true)
	_next_attack = transitioning_until + 1.0
	_hold_release_at(transitioning_until)


func _hold_release_at(t: float) -> void:
	_current = {"atk": {"id": "_wait", "telegraph": 0.0, "actions": [], "recovery": 0.0}, "t0": sim.time, "end": t,
		"fired": [], "aim": boss.ground_pos(), "wait": true}


# =============================================================================================
# Dazed (poise break) — the only time a boss can be grabbed
# =============================================================================================

func intercept_knockdown(f: Fighter, reason: String, by: Fighter) -> bool:
	if f != boss:
		return super.intercept_knockdown(f, reason, by)
	if reason == "poise" and dazed_until < sim.time and sim.time >= transitioning_until:
		var dz: Dictionary = bdata.get("dazed", {})
		var dur := float(dz.get("duration", 3.0))
		dazed_until = sim.time + dur
		_cancel_pattern()
		if brain:
			brain.hold = true
			brain.move_override = Vector3.ZERO
		boss.flags["boss_ungrabbable"] = false
		boss.statuses.add({"id": "dazed", "name": "Dazed", "duration": dur, "damage_taken": float(dz.get("damage_taken", 1.2))})
		boss.stun(dur, true)
		boss.rig.muscle = 0.35
		boss.poise = 0.0
		sim.emit_event({"type": "boss_dazed", "fighter": boss.index, "seconds": dur, "by": by.index if by else -1})
	return true


func _end_daze() -> void:
	dazed_until = -1.0
	boss.flags["boss_ungrabbable"] = true
	boss.rig.muscle = 1.0
	boss.poise = boss.effective_max_poise()
	if brain:
		brain.hold = false
	_next_attack = sim.time + 0.8
	sim.emit_event({"type": "boss_recovered", "fighter": boss.index})


func on_depleted(f: Fighter, attacker: Fighter, hit: Dictionary) -> void:
	if f == boss and phase_no == 1 and _phase2_allowed():
		# never skip phase 2: hold at the threshold and transition
		f.health = maxf(1.0, f.max_health * phase2_at * 0.95)
		_transition()
		return
	super.on_depleted(f, attacker, hit)


# =============================================================================================
# Arena interplay
# =============================================================================================

func _tick_leash(_dt: float) -> void:
	var lz: Dictionary = _phase_data(phase_no).get("leash", {})
	if lz.is_empty():
		return
	var to := boss.ground_pos() - hazards.anchor
	to.y = 0.0
	var r := float(lz.get("radius", 7.0)) * hazards.radius() / 5.0
	if to.length() <= r:
		return
	var v := boss.rig.com_velocity()
	var outward := to.normalized()
	var vout := v.dot(outward)
	if vout > 0.0:
		boss.rig.apply_body_impulse(-outward * vout * boss.rig.total_mass)
	boss.rig.apply_body_impulse(-outward * (to.length() - r) * 2.0 * boss.rig.total_mass * 0.1)
	if not _current.is_empty() and bool(_current.get("charging", false)):
		# overshot on the chain: stumble (the punish for a sidestepped lunge)
		_cancel_pattern()
		boss.stun(float(lz.get("stumble", 0.8)), true)
		sim.emit_event({"type": "boss_stumble", "fighter": boss.index})
		_next_attack = sim.time + 1.5


func _tick_element_cycle() -> void:
	var ec: Dictionary = _phase_data(phase_no).get("element_cycle", {})
	if ec.is_empty() or sim.time < _element_next:
		return
	var order: Array = ec.get("order", ["scorch", "static", "sludge", "brine", "gale", "grit"])
	_element_i = (_element_i + 1) % order.size()
	var el := str(order[_element_i])
	_element_next = sim.time + float(ec.get("every", 8.0))
	boss.creature.element = el
	for slot in CreatureDef.MOVE_SLOTS + CreatureDef.ABILITY_SLOTS:
		boss.mods["element_" + str(slot)] = el
	sim.emit_event({"type": "boss_element", "fighter": boss.index, "element": el})


func active_element() -> String:
	return boss.creature.element if boss else ""


func _tick_target_rotation() -> void:
	if sim.time < _rotate_next or brain == null:
		return
	_rotate_next = sim.time + float(bdata.get("target_rotate", 8.0))
	var party := 0
	for f: Fighter in sim.fighters:
		if is_party(f) and not f.is_out() and not is_parked(f):
			party += 1
	if party >= 2:
		brain.press(FighterInput.TARGET)


# =============================================================================================
# Patterns
# =============================================================================================

func _phase_attacks() -> Array:
	return _phase_data(phase_no).get("attacks", [])


func _start_next_attack() -> void:
	var tgt := boss.target
	if tgt == null or tgt.is_out():
		return
	var dist := boss.pos().distance_to(tgt.pos())
	var forced := ""
	var rep: Dictionary = _phase_data(phase_no).get("reposition", {})
	if not rep.is_empty():
		var recent := 0.0
		for d in _damage_log:
			recent += float(d["dmg"])
		if recent >= float(rep.get("after_damage", 60.0)):
			forced = str(rep.get("attack", ""))
			_damage_log.clear()
	var cands := []
	var weights := []
	for atk in _phase_attacks():
		var aid := str(atk.get("id", ""))
		if forced != "" and aid != forced:
			continue
		if forced == "" and bool(atk.get("only_forced", false)):
			continue
		if sim.time < float(_cooldowns.get(aid, 0.0)):
			continue
		var rg: Array = atk.get("range", [0.0, 99.0])
		if forced == "" and (dist < float(rg[0]) or dist > float(rg[1])):
			continue
		var req: Dictionary = atk.get("requires", {})
		if req.has("adjacent") and _adjacent_enemies(float(req.get("radius", 2.5))) < int(req["adjacent"]):
			continue
		cands.append(atk)
		weights.append(float(atk.get("weight", 1.0)))
	if cands.is_empty():
		_next_attack = sim.time + 0.5
		return
	var i := _weighted(weights)
	var atk2: Dictionary = cands[i]
	var aid2 := str(atk2.get("id", ""))
	_cooldowns[aid2] = sim.time + float(atk2.get("cooldown", 6.0))
	if int(_skip.get(aid2, 0)) > 0:
		_skip[aid2] = int(_skip[aid2]) - 1
		sim.emit_event({"type": "boss_skip", "fighter": boss.index, "attack": aid2})
		_next_attack = sim.time + 1.0
		return
	_begin_pattern(atk2)


func _weighted(ws: Array) -> int:
	var total := 0.0
	for w in ws:
		total += float(w)
	var roll := sim.rng.randf() * total
	var acc := 0.0
	for i in ws.size():
		acc += float(ws[i])
		if roll < acc:
			return i
	return ws.size() - 1


func _adjacent_enemies(r: float) -> int:
	var n := 0
	for f: Fighter in sim.fighters:
		if is_party(f) and not f.is_out() and not is_parked(f) and f.pos().distance_to(boss.pos()) <= r:
			n += 1
	return n


func _aim_point(atk: Dictionary) -> Vector3:
	var at := str(atk.get("aim", "target"))
	if at == "self" or boss.target == null:
		return boss.ground_pos()
	if at == "center":
		return Vector3.ZERO
	if at == "away":
		var away := boss.ground_pos() - boss.target.ground_pos()
		away.y = 0.0
		away = away.normalized() if away.length() > 0.1 else -boss.forward()
		return sim.clamp_to_arena(boss.ground_pos() + away * float(atk.get("max_reach", 5.0)), 0.6)
	var tp := boss.target.ground_pos()
	var maxd := float(atk.get("max_reach", 99.0))
	var to := tp - boss.ground_pos()
	to.y = 0.0
	if to.length() > maxd:
		tp = boss.ground_pos() + to.normalized() * maxd
	return sim.clamp_to_arena(tp, 0.4)


func _begin_pattern(atk: Dictionary) -> void:
	var tel := maxf(0.5, float(atk.get("telegraph", 0.8)))
	var aim := _aim_point(atk)
	_current = {"atk": atk, "t0": sim.time + tell_lead, "tel": tel, "aim": aim, "fired": [], "charging": false,
		"end": sim.time + tell_lead + tel + _actions_span(atk) + float(atk.get("recovery", 0.8))}
	for a in atk.get("actions", []):
		_current["fired"].append(false)
	if brain:
		brain.hold = true
		brain.move_override = Vector3.ZERO
	_face(aim)
	var decal: Dictionary = atk.get("decal", {"shape": "circle", "radius": 2.0})
	var at_self := str(decal.get("at", "aim")) == "self"
	if tell_lead > 0.0:
		sim.emit_event({"type": "boss_tell", "fighter": boss.index, "attack": atk.get("id", ""), "name": str(atk.get("name", "")), "lead": tell_lead})
	sim.emit_event({"type": "boss_telegraph", "fighter": boss.index, "attack": atk.get("id", ""), "name": str(atk.get("name", "")),
		"shape": str(decal.get("shape", "circle")), "radius": float(decal.get("radius", 2.0)), "length": float(decal.get("length", 0.0)),
		"width": float(decal.get("width", 0.0)), "cone_deg": float(decal.get("cone_deg", 0.0)),
		"pos": boss.ground_pos() if at_self else aim, "yaw": boss.facing_yaw, "time": tel + tell_lead,
		"element": _el(str(decal.get("element", atk.get("element", ""))))})


func _actions_span(atk: Dictionary) -> float:
	var s := 0.0
	for a in atk.get("actions", []):
		s = maxf(s, float(a.get("t", 0.0)))
	return s


func _el(el: String) -> String:
	return active_element() if el == "active" else el


func _face(p: Vector3) -> void:
	var to := p - boss.pos()
	to.y = 0.0
	if to.length() > 0.05:
		boss.facing_yaw = atan2(to.x, to.z)


func _cancel_pattern() -> void:
	_current = {}
	_grab_release_at = -1.0
	_rush_until = -1.0
	if brain:
		brain.hold = dazed_until > sim.time or sim.time < transitioning_until
		brain.move_override = Vector3.ZERO


func _run_pattern(_dt: float) -> void:
	var c := _current
	if _rush_until > 0.0 and sim.time >= _rush_until:
		_rush_until = -1.0
		c["charging"] = false
		if brain:
			brain.move_override = Vector3.ZERO
	if bool(c.get("wait", false)):
		if sim.time >= float(c["end"]):
			_current = {}
			if brain:
				brain.hold = false
		return
	var atk: Dictionary = c["atk"]
	var t := sim.time - float(c["t0"])
	if t < float(c["tel"]):
		if bool(atk.get("track", false)):
			c["aim"] = _aim_point(atk)
		_face(c["aim"])
		return
	var ta := t - float(c["tel"])
	var actions: Array = atk.get("actions", [])
	for i in actions.size():
		if not bool(c["fired"][i]) and ta >= float(actions[i].get("t", 0.0)):
			c["fired"][i] = true
			_do_action(actions[i], c)
			if _current.is_empty():
				return
	if sim.time >= float(c["end"]):
		_current = {}
		if brain:
			brain.hold = false
		var gap: Array = _phase_data(phase_no).get("attack_gap", [2.0, 3.5])
		_next_attack = sim.time + float(gap[0]) + sim.rng.randf() * (float(gap[1]) - float(gap[0]))


func _do_action(a: Dictionary, c: Dictionary) -> void:
	var t := str(a.get("type", ""))
	var aim: Vector3 = c["aim"]
	match t:
		"telegraph_only":
			return
		"aim":
			c["aim"] = _aim_point(c["atk"])
			_face(c["aim"])
			sim.emit_event({"type": "boss_telegraph", "fighter": boss.index, "attack": c["atk"].get("id", ""), "name": str(c["atk"].get("name", "")),
				"shape": "line", "radius": 0.0, "length": float(a.get("length", 4.0)), "width": float(a.get("width", 1.5)),
				"cone_deg": 0.0, "pos": boss.ground_pos(), "yaw": boss.facing_yaw, "time": float(a.get("telegraph", 0.5)), "element": ""})
			return
		"grab_throw":
			_grab_throw(a)
			return
		"withdraw":
			var dur := float(a.get("duration", 3.0))
			sim.effects.fire(boss, {"type": "counter_stance", "duration": dur, "counter": a.get("counter", {"damage": 10, "poise": 25, "knockback": 2.0})})
			sim.effects.fire(boss, {"type": "reflect", "duration": dur})
			boss.flags["boss_ungrabbable"] = false
			_grabbable_until = sim.time + dur
			return
		"rush":
			_face(aim)
			c["charging"] = true
			var rdur := float(a.get("duration", 0.45))
			boss.statuses.add({"id": "boss_rush", "name": "Rushing", "duration": rdur, "speed": float(a.get("speed_mult", 3.0))})
			if brain:
				var dir := aim - boss.ground_pos()
				dir.y = 0.0
				brain.move_override = dir.normalized() if dir.length() > 0.1 else boss.forward()
				_rush_until = sim.time + rdur
			return
	var e: Dictionary = a.duplicate(true)
	e.erase("t")
	var yaw_off := deg_to_rad(float(e.get("yaw_offset", 0.0)))
	e.erase("yaw_offset")
	if e.has("element"):
		e["element"] = _el(str(e["element"]))
	if e.has("on_expire") and typeof(e["on_expire"]) == TYPE_DICTIONARY and e["on_expire"].has("element"):
		e["on_expire"]["element"] = _el(str(e["on_expire"]["element"]))
	if str(e.get("at", "")) == "aim":
		e.erase("at")
		e["at_point"] = aim
	match t:
		"leap":
			_face(aim)
			var d := boss.ground_pos().distance_to(aim)
			e["to_target"] = false
			e["distance"] = minf(d, float(e.get("distance", 5.0)))
		"dash":
			_face(aim)
			c["charging"] = true
	if yaw_off != 0.0:
		var keep := boss.facing_yaw
		boss.facing_yaw = MathX.wrap_angle(keep + yaw_off)
		sim.effects.fire(boss, e)
		boss.facing_yaw = keep
	else:
		sim.effects.fire(boss, e)


func _grab_throw(a: Dictionary) -> void:
	var reach := float(a.get("range", 2.0))
	var best: Fighter = null
	var bd := reach
	for f: Fighter in sim.fighters:
		if not sim.are_enemies(boss, f) or f.is_out() or f.is_evading() or f.held_by or f.holding or f.is_down() or is_parked(f):
			continue
		var to := f.pos() - boss.pos()
		to.y = 0.0
		if to.length() > bd:
			continue
		if absf(boss.forward().signed_angle_to(to, Vector3.UP)) > deg_to_rad(70.0):
			continue
		bd = to.length()
		best = f
	if best == null:
		return
	var seg := int(boss.creature.body.seg_index.get(str(a.get("segment", "head")), 0))
	boss.begin_grab(best, seg, 0)
	if boss.holding == best:
		_grab_release_at = sim.time + float(a.get("hold", 0.6))
		sim.emit_event({"type": "boss_grab", "fighter": boss.index, "victim": best.index, "name": str(a.get("name", ""))})


func _tick_grab() -> void:
	if _grab_release_at < 0.0 or brain == null:
		return
	if boss.holding == null:
		_grab_release_at = -1.0
		return
	if sim.time >= _grab_release_at:
		_grab_release_at = -1.0
		# throw toward the nearest cage wall (wall splat), else straight ahead
		var out := Vector3(boss.pos().x, 0.0, boss.pos().z)
		brain.move_override = out.normalized() if out.length() > 0.5 else boss.forward()
		brain.press(FighterInput.HEAVY)


func build_result() -> Dictionary:
	var res := super.build_result()
	if res.has("campaign"):
		res["campaign"]["boss"] = {"id": str(bdata.get("id", "")), "creature": boss.creature.id if boss else "",
			"phase": phase_no, "defeated": boss != null and boss.is_out()}
	return res


func hud_status() -> String:
	var base := super.hud_status()
	if boss == null:
		return base
	var s := "PHASE %d" % phase_no
	if dazed_until > sim.time:
		s += "  ·  DAZED — GRAB NOW"
	if _element_i >= 0:
		s += "  ·  " + Elements.display_name(active_element()).to_upper()
	return s + "  ·  " + base
