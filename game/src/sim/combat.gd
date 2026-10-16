class_name Combat
extends RefCounted
## Authoritative hit validation and the single damage-delivery funnel.
##
## Melee: a weapon sphere (moving segment, active only inside its move's hit window) must reach a
## hurt shape with closing speed ≥ the move's vmin along the contact normal. Quality and
## cleanliness of the contact scale damage. Everything else (projectiles, areas, zones,
## reactions, throws, slams) builds a hit dictionary and goes through `deliver`, so guard/parry,
## armor, counters, hooks, element build-up and events behave identically for every source.
## See docs/DESIGN.md §2 "Combat model".

var sim: MatchSim
var debug_contacts: Array = []


func _init(match_sim) -> void:
	sim = match_sim


static func move_class(slot: String) -> String:
	match slot:
		"l1", "l2", "l3", "dash_attack", "pummel":
			return "light"
		"heavy", "finisher":
			return "heavy"
		"ability1", "ability2":
			return "ability"
		"juice":
			return "juice"
		"grab", "throw":
			return "grab"
	if slot.begins_with("l"):
		return "light"
	return "ability"


## Scans every active weapon against every hittable fighter. Call once per tick.
func detect_hits() -> void:
	debug_contacts.clear()
	for a: Fighter in sim.fighters:
		if a.move == null or not (a.state == Fighter.State.ATTACK or a.state == Fighter.State.ABILITY):
			continue
		var widx := a.move.window_index(a.state_time)
		if widx < 0:
			continue
		var weps: PackedStringArray = a.move.windows[widx]["weapons"]
		for wname in weps:
			if a.move == null:
				break
			var w: BodyDef.Weapon = a.creature.body.weapons.get(wname)
			if w == null:
				continue
			var rb := a.rig.bodies[w.seg]
			var wp := rb.global_transform * w.local
			var wr := w.radius * float(a.mods.get("reach_radius", 1.0))
			if a.move.damage > 0.0:
				sim.effects.hit_props(wp, wr, a.move.damage * 0.5)
			if not sim.hittables.is_empty():
				_hit_objects(a, w, wp, wr, widx)
			for b: Fighter in sim.fighters:
				if a.move == null:
					break
				if b == a or not sim.can_hit(a, b):
					continue
				if a.move_hits.has(b.index):
					var last: Dictionary = a.move_hits[b.index]
					if not a.move.multi_hit or (int(last["w"]) == widx and a.state_time - float(last["t"]) < a.move.rehit):
						continue
				if b.is_evading() or b.state == Fighter.State.KO or b.state == Fighter.State.INACTIVE:
					continue
				if b.pos().distance_squared_to(wp) > 9.0:
					continue
				var c := find_contact(wp, wr, b)
				if c.is_empty():
					continue
				if a.move.kind == "grab":
					_try_grab(a, b, w, c)
					continue
				var wv := a.rig.point_velocity(w.seg, wp)
				_resolve_melee(a, b, widx, wp, wv, c)
				if a.state != Fighter.State.ATTACK and a.state != Fighter.State.ABILITY:
					break


## Weapons striking registered mode objects (Chumball's ball, bags...). Needs real closing speed.
func _hit_objects(a: Fighter, w: BodyDef.Weapon, wp: Vector3, wr: float, widx: int) -> void:
	for h in sim.hittables:
		var body: RigidBody3D = h.get("body")
		if body == null or not is_instance_valid(body):
			continue
		var key := "obj:" + str(h["id"])
		if a.move_hits.has(key):
			continue
		# objects can declare a vertical reach column (balls on the floor are hit by punches too)
		var c := MathX.closest_on_segment(wp, body.global_position, body.global_position + Vector3.UP * float(h.get("reach_up", 0.0)))
		if wp.distance_to(c) - float(h["radius"]) > wr:
			continue
		var n := (wp - c).normalized() if wp.distance_squared_to(c) > 1e-8 else -a.forward()
		var wv := a.rig.point_velocity(w.seg, wp)
		var vn := (wv - body.linear_velocity).dot(-n)
		if vn < a.move.vmin * 0.6:
			continue
		a.move_hits[key] = {"w": widx, "t": a.state_time}
		a.move_hit_any = true
		var dir := (-n * 0.5 + a.forward() * 0.5)
		dir.y = maxf(dir.y, 0.0)
		dir = dir.normalized()
		var on_hit: Callable = h["on_hit"]
		on_hit.call(a, dir, a.move.knockback, a.move.launch, a.element_for(a.move), wp)
		sim.emit_event({"type": "object_hit", "fighter": a.index, "object": str(h["id"]), "point": wp, "element": a.element_for(a.move)})


## Closest hurt-shape contact of a weapon sphere against fighter b, or {} if none.
func find_contact(wp: Vector3, wr: float, b: Fighter) -> Dictionary:
	var best := {}
	var best_d := INF
	var body := b.creature.body
	for s: BodyDef.Seg in body.segments:
		var t := b.rig.bodies[s.index].global_transform
		for sh: BodyDef.Shape in s.shapes:
			var pa := t * sh.hit_a
			var pb := t * sh.hit_b
			var q := MathX.closest_on_segment(wp, pa, pb)
			var d := wp.distance_to(q) - sh.hit_r
			if d < wr and d < best_d:
				best_d = d
				var n := (wp - q)
				n = n.normalized() if n.length_squared() > 1e-10 else Vector3.UP
				best = {"seg": s.index, "point": q + n * sh.hit_r, "normal": n, "depth": wr - d}
	return best


func _try_grab(a: Fighter, b: Fighter, w: BodyDef.Weapon, c: Dictionary) -> void:
	a.move_hits[b.index] = {"w": 0, "t": a.state_time}
	if b.held_by or b.holding or b.is_down() or b.is_out() or b.flags.get("boss_ungrabbable", false):
		return
	if b.state == Fighter.State.ATTACK and b.move and b.move.kind == "grab" and b.state_time < b.move.first_active() + 0.1:
		var away := (b.pos() - a.pos())
		away.y = 0.0
		away = away.normalized()
		a.rig.apply_body_impulse(-away * 3.0 * a.rig.total_mass)
		b.rig.apply_body_impulse(away * 3.0 * b.rig.total_mass)
		sim.emit_event({"type": "grab_tech", "fighter": a.index, "victim": b.index})
		return
	var seg_i: int = c["seg"]
	var part: String = b.creature.body.segments[seg_i].part
	if part != "core" and part != "head":
		seg_i = 0
	a.begin_grab(b, w.seg, seg_i)


func _resolve_melee(a: Fighter, b: Fighter, widx: int, wp: Vector3, wv: Vector3, c: Dictionary) -> void:
	var m := a.move
	var seg_i: int = c["seg"]
	var n: Vector3 = c["normal"]
	var tv := b.rig.point_velocity(seg_i, c["point"])
	var vrel := wv - tv
	var vn := vrel.dot(-n)
	var spd := vrel.length()
	debug_contacts.append({"point": c["point"], "normal": n, "vn": vn})
	if vn < m.vmin * float(a.mods.get("vmin_mult", 1.0)):
		return
	a.move_hits[b.index] = {"w": widx, "t": a.state_time}
	a.move_hit_any = true
	var clean := vn / maxf(spd, 0.01)
	if clean < Tuning.v("min_clean"):
		sim.emit_event({"type": "glance", "fighter": a.index, "target": b.index, "point": c["point"]})
		return
	var q := clampf((vn - m.vmin) / (m.vref - m.vmin), 0.0, 1.0)
	var seg: BodyDef.Seg = b.creature.body.segments[seg_i]
	var dmg := m.damage * (0.55 + 0.6 * q) * (0.75 + 0.25 * clean) * seg.hurt_mult
	dmg *= 1.0 + a.move_charge * m.charge_damage
	# knockback direction
	var nh := Vector3(-n.x, 0.0, -n.z)
	var dir := (nh.normalized() * 0.5 + a.forward() * 0.5)
	dir = dir.normalized() if dir.length_squared() > 1e-6 else a.forward()
	match m.kb_dir:
		"side":
			var side := Vector3.UP.cross(a.forward()) * (1.0 if m.kb_side >= 0.0 else -1.0)   # +1 = attacker's left (+X), as MoveDef documents
			dir = (side * 0.8 + a.forward() * 0.2).normalized()
		"up":
			dir = Vector3.ZERO
		"radial":
			var rad := b.pos() - a.pos()
			rad.y = 0.0
			dir = rad.normalized() if rad.length_squared() > 1e-6 else a.forward()
	var kb_speed := m.knockback * (0.6 + 0.4 * q)
	var kb := dir * kb_speed * sqrt(Tuning.v("ref_mass") / maxf(20.0, b.rig.total_mass)) + Vector3.UP * m.launch
	if m.pull > 0.0:
		var toward := a.pos() - b.pos()
		toward.y = 0.0
		kb = toward.normalized() * m.pull * 4.0
	var h := {
		"attacker": a, "damage": dmg, "point": c["point"], "normal": n, "seg": seg_i, "part": seg.part,
		"blocked": false, "parried": false, "counter": b.is_winding_up(), "knockback": kb,
		"local_impulse": -n * clampf(dmg * 0.8, 0.5, 18.0), "stun": m.stun * (0.7 + 0.3 * q),
		"poise": m.poise * (0.6 + 0.4 * q), "knockdown": m.knockdown, "guard_drain": maxf(m.stamina, 3.0) * Tuning.v("guard_stamina_cost_mult") * m.guard_break,
		"hype_mult": m.hype, "quality": q, "element": a.element_for(m), "buildup": m.buildup * (0.6 + 0.4 * q),
		"move": m.id, "slot": a.move_slot, "move_class": a.current_move_class(), "charged": a.move_charge > 0.05,
		"unblockable": m.unblockable, "parryable": true, "from": a.pos(), "guard_seg": seg.guard, "melee": true,
		"turn": m.turn_target, "splat": m.splat, "status": {}, "ally": false,
	}
	if h["counter"]:
		h["damage"] = float(h["damage"]) * Tuning.v("counter_mult")
		h["stun"] = float(h["stun"]) + Tuning.v("counter_stun_bonus")
	deliver(a, b, h)


## The single delivery funnel. `h` fields: see _resolve_melee. Applies guard/parry, hooks,
## status multipliers, armor, counter stances, damage, build-up, events and post-hooks.
func deliver(a: Fighter, b: Fighter, h: Dictionary) -> void:
	if b.is_out() or (b.is_evading() and not bool(h.get("ignore_evade", false))):
		return
	var ally := bool(h.get("ally", false))
	if ally:
		# direct elemental/ally hits do nothing; reaction areas/zones are scaled by EffectsSystem
		if bool(h.get("melee", false)):
			return
	# guard / parry
	var from: Vector3 = h.get("from", a.pos() if a else b.pos())
	var guard_from: Vector3 = h.get("guard_from", from)   # attacker-attached bursts: see EffectsSystem.area
	var guarding := not bool(h.get("unblockable", false)) and not b.statuses.flag("no_guard") and (b.guards_against(guard_from) or (bool(h.get("guard_seg", false)) and b.state == Fighter.State.GUARD))
	if guarding:
		var melee := bool(h.get("melee", false))
		if b.in_parry_window(a) and (melee or bool(h.get("parryable", false))):
			h["parried"] = true
		else:
			h["blocked"] = true
			var gd_mult := Tuning.v("guard_damage_mult") * float(b.mods.get("guard_absorb_mult", 1.0))
			gd_mult = b.shield_damage_mult(gd_mult)   # shield statuses (Fighter NPC-kit block)
			h["damage"] = float(h["damage"]) * gd_mult
			h["knockback"] = (h["knockback"] as Vector3) * 0.35
			h["stun"] = 0.0
			h["knockdown"] = false
			h["guard_drain"] = float(h.get("guard_drain", 0.0)) * b.statuses.mult("guard_cost")
			h["poise"] = float(h["poise"]) * 0.5
	if a and not bool(h["parried"]):
		var ctx := {"hit": h, "other": b, "slot": h.get("slot", ""), "move_class": h.get("move_class", ""), "charged": h.get("charged", false)}
		if a.move and bool(h.get("melee", false)):
			for oh in a.move.on_hit:
				a.hooks.run_inline(oh, ctx)
		a.hooks.fire("pre_hit_dealt", ctx)
		var ctx2 := {"hit": h, "other": a, "slot": h.get("slot", ""), "move_class": h.get("move_class", "")}
		b.hooks.fire("pre_hit_taken", ctx2)
	# damage multipliers (statuses, power/defense, juice, elements, combo scaling, OTG)
	if not bool(h["parried"]):
		var dmg := float(h["damage"])
		if a:
			dmg *= float(a.mods["damage"]) * a.eff("power") * a.statuses.damage_dealt_mult()
			if a.time < a.juiced_until:
				dmg *= 1.15
		dmg *= float(b.mods["defense"]) * b.eff("defense") * b.statuses.damage_taken_mult()
		dmg *= Elements.damage_mult(str(h.get("element", "")), b.creature.element)
		dmg *= b.combo_damage_scale()
		if b.is_down() and not bool(h.get("no_otg_limit", false)):
			if b.otg_hits >= int(Tuning.v("otg_max_hits")):
				return
			dmg *= Tuning.v("otg_damage_mult")
		if b.shield_hp > 0.0 and b.has_flag("shield"):
			var absorbed := minf(b.shield_hp, dmg)
			b.shield_hp -= absorbed
			dmg -= absorbed
		h["damage"] = minf(dmg, Tuning.v("max_single_hit"))
		h["knockback"] = (h["knockback"] as Vector3) * b.statuses.knockback_taken_mult() * float(b.mods["knockback_taken"]) * (float(a.mods["knockback_dealt"]) if a else 1.0)
		if b.flags.has("push_mult_once"):
			h["knockback"] = (h["knockback"] as Vector3) * float(b.flags["push_mult_once"])
			b.flags.erase("push_mult_once")
	else:
		h["damage"] = 0.0
	# counter stance: struck while countering -> instant retaliation at the attacker
	if a and b.counter_active() and bool(h.get("melee", false)) and not bool(h["parried"]):
		h["counter_triggered"] = true
	if not bool(h["blocked"]) and not bool(h["parried"]) and a:
		a.stamina = minf(a.max_stamina, a.stamina + (a.move.stamina if a.move else 0.0) * Tuning.v("hit_stamina_refund"))
	b.receive_hit(h)
	if bool(h.get("counter_triggered", false)):
		b.fire_counter(a)
	# element build-up (guard halves, parry zeroes, resist/weak scales)
	var el := str(h.get("element", ""))
	if not bool(h["parried"]) and not ally:
		var scale := 0.5 if bool(h["blocked"]) else 1.0
		scale *= Elements.damage_mult(el, b.creature.element)
		if el != "" and float(h.get("buildup", 0.0)) > 0.0:
			b.statuses.add_buildup(el, float(h["buildup"]), a, scale)
		if not bool(h["blocked"]):
			var bonus := b.statuses.hit_buildup_bonus()
			for bel in bonus:
				b.statuses.add_buildup(str(bel), float(bonus[bel]), a, 1.0)
			var st: Dictionary = h.get("status", {})
			if not st.is_empty():
				var stc := st.duplicate()
				stc["source"] = a
				b.statuses.add(stc)
	# wall splat window
	var sp: Dictionary = h.get("splat", {})
	if not sp.is_empty() and not bool(h["blocked"]) and not bool(h["parried"]):
		b.arm_splat(a, sp)
	if float(h.get("turn", 0.0)) != 0.0 and not bool(h["blocked"]):
		b.facing_yaw = MathX.wrap_angle(b.facing_yaw + deg_to_rad(float(h["turn"])))
	# post hooks + event
	if a:
		var ctx3 := {"hit": h, "other": b, "slot": h.get("slot", ""), "move_class": h.get("move_class", ""), "charged": h.get("charged", false)}
		if bool(h["parried"]):
			b.hooks.fire("parry_success", {"other": a})
			a.hooks.fire("parried", {"other": b})
		elif bool(h["blocked"]):
			a.hooks.fire("blocked", ctx3)
		else:
			a.hooks.fire("hit_dealt", ctx3)
			b.hooks.fire("hit_taken", {"hit": h, "other": a, "slot": h.get("slot", ""), "move_class": h.get("move_class", "")})
	sim.emit_event({"type": "hit", "fighter": a.index if a else -1, "target": b.index, "damage": float(h["damage"]),
		"point": h["point"], "normal": h["normal"], "blocked": h["blocked"], "parried": h["parried"], "counter": h.get("counter", false),
		"part": h.get("part", "core"), "element": el, "quality": h.get("quality", 1.0), "move": str(h.get("move", "")),
		"slot": str(h.get("slot", "")), "charged": bool(h.get("charged", false)), "move_class": str(h.get("move_class", "")),
		"knockdown": h.get("knockdown", false), "otg": b.is_down()})


## Non-weapon damage (pummels, throws, slams, hazards). Never guarded or parried.
func apply_simple_damage(source: Fighter, b: Fighter, amount: float, kind: String, extra := {}) -> void:
	if b.is_out():
		return
	var dmg := amount * float(b.mods["defense"]) * b.eff("defense") * b.statuses.damage_taken_mult()
	if source:
		dmg *= float(source.mods["damage"]) * source.eff("power")
	var h := {"attacker": source, "damage": dmg, "point": b.pos(), "normal": Vector3.UP, "seg": 0,
		"part": "core", "blocked": false, "parried": false, "counter": false,
		"knockback": extra.get("knockback", Vector3.ZERO), "local_impulse": Vector3.ZERO,
		"stun": float(extra.get("stun", 0.0)), "poise": float(extra.get("poise", 0.0)),
		"knockdown": bool(extra.get("knockdown", false)), "hype_mult": 1.0, "move_class": kind}
	b.receive_hit(h)
	sim.emit_event({"type": "hit", "fighter": source.index if source else -1, "target": b.index,
		"damage": dmg, "point": b.pos(), "normal": Vector3.UP, "blocked": false, "parried": false,
		"counter": false, "part": "core", "element": str(extra.get("element", "")), "quality": 1.0,
		"move": kind, "slot": kind, "knockdown": h["knockdown"], "otg": false})


## Damage-over-time tick from a status. `no_kill` keeps the target at ≥ 1 HP.
func apply_dot(source, b: Fighter, amount: float, status_id: String, element: String, no_kill: bool) -> void:
	if source != null and not is_instance_valid(source):
		source = null   # the applier's slot was reused
	if b.is_out() or amount <= 0.0:
		return
	if no_kill and b.health - amount < 1.0:
		amount = maxf(0.0, b.health - 1.0)
		if amount <= 0.0:
			return
	b.health -= amount
	b.stats_record["damage_taken"] += amount
	if source is Fighter and source != b:
		(source as Fighter).stats_record["damage_dealt"] += amount
	if b.health <= 0.0:
		sim.on_fighter_depleted(b, source if source is Fighter else null, {"dot": status_id})
	sim.emit_event({"type": "dot", "fighter": b.index, "damage": amount, "element": element, "status": status_id})
