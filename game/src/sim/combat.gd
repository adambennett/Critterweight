class_name Combat
extends RefCounted
## Authoritative hit validation and damage resolution.
##
## A melee hit requires a weapon point (sphere on a moving segment, active only inside its move's
## hit window) to physically reach one of the target's hurt shapes with a closing speed of at least
## the move's `vmin` along the contact normal. Damage then scales with how fast and how square the
## contact was, where it landed, guard/parry state, counters, combo protection and elements.
## See docs/DESIGN.md "Combat model".

var sim: MatchSim
var debug_contacts: Array = []   ## recent contact probes for debug drawing


func _init(match_sim) -> void:
	sim = match_sim


## Scans every active weapon against every hittable fighter. Call once per tick after fighters moved.
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
			var w: BodyDef.Weapon = a.creature.body.weapons.get(wname)
			if w == null:
				continue
			var rb := a.rig.bodies[w.seg]
			var wp := rb.global_transform * w.local
			for b: Fighter in sim.fighters:
				if b == a or not sim.can_hit(a, b):
					continue
				if a.move_hits.has(b.index):
					if not a.move.multi_hit or int(a.move_hits[b.index]) == widx:
						continue
				if b.is_evading() or b.state == Fighter.State.KO or b.state == Fighter.State.INACTIVE:
					continue
				if b.pos().distance_squared_to(wp) > 9.0:
					continue
				var c := find_contact(wp, w.radius, b)
				if c.is_empty():
					continue
				if a.move.kind == "grab" or a.move_slot == "grab":
					_try_grab(a, b, w, c)
					continue
				var wv := a.rig.point_velocity(w.seg, wp)
				_resolve_melee(a, b, widx, wp, wv, c)
				if a.state != Fighter.State.ATTACK and a.state != Fighter.State.ABILITY:
					break


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
	a.move_hits[b.index] = 0
	if b.held_by or b.holding or b.is_down() or b.is_out():
		return
	if b.state == Fighter.State.ATTACK and b.move_slot == "grab" and b.state_time < b.move.first_active() + 0.1:
		# grab vs grab: both bounce off
		var away := (b.pos() - a.pos())
		away.y = 0.0
		away = away.normalized()
		a.rig.apply_body_impulse(-away * 3.0 * a.rig.total_mass)
		b.rig.apply_body_impulse(away * 3.0 * b.rig.total_mass)
		sim.emit_event({"type": "grab_tech", "fighter": a.index, "victim": b.index})
		return
	# grab the closest body segment (prefer the core so throws carry the whole creature)
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
	if vn < m.vmin:
		return  # a touch, not a strike; may still land later in the window
	a.move_hits[b.index] = widx
	a.move_hit_any = true
	var clean := vn / maxf(spd, 0.01)
	if clean < Tuning.v("min_clean"):
		sim.emit_event({"type": "glance", "fighter": a.index, "target": b.index, "point": c["point"]})
		return
	var q := clampf((vn - m.vmin) / (m.vref - m.vmin), 0.0, 1.0)
	var seg: BodyDef.Seg = b.creature.body.segments[seg_i]
	var dmg := m.damage * (0.55 + 0.6 * q) * (0.75 + 0.25 * clean) * seg.hurt_mult
	dmg *= 1.0 + a.move_charge * m.charge_damage
	dmg *= float(a.mods["damage"]) * a.eff("power")
	dmg *= float(b.mods["defense"]) * b.eff("defense") * b.statuses.damage_taken_mult()
	if a.time < a.juiced_until:
		dmg *= 1.15
	dmg *= Elements.damage_mult(m.element, b.creature.element)
	var counter := b.is_winding_up()
	if counter:
		dmg *= Tuning.v("counter_mult")
	dmg *= b.combo_damage_scale()
	var downed := b.is_down()
	if downed:
		if b.otg_hits >= int(Tuning.v("otg_max_hits")):
			return
		dmg *= Tuning.v("otg_damage_mult")
	var blocked := false
	var parried := false
	var guard_drain := 0.0
	if not m.unblockable and (b.guards_against(a.pos()) or (seg.guard and b.state == Fighter.State.GUARD)):
		if b.in_parry_window():
			parried = true
		else:
			blocked = true
			guard_drain = m.damage * Tuning.v("guard_stamina_per_damage") * m.guard_break
			dmg *= Tuning.v("guard_damage_mult")
	dmg = minf(dmg, Tuning.v("max_single_hit"))
	var kb := Vector3.ZERO
	var local_imp := Vector3.ZERO
	if not parried:
		var nh := Vector3(-n.x, 0.0, -n.z)
		var dir := (nh.normalized() * 0.5 + a.forward() * 0.5)
		dir = dir.normalized() if dir.length_squared() > 1e-6 else a.forward()
		var kb_speed := m.knockback * (0.6 + 0.4 * q) * float(a.mods["knockback_dealt"]) * float(b.mods["knockback_taken"])
		kb_speed *= sqrt(Tuning.v("ref_mass") / maxf(20.0, b.rig.total_mass))
		if blocked:
			kb_speed *= 0.35
		kb = dir * kb_speed
		if not blocked:
			kb += Vector3.UP * m.launch
		local_imp = -n * clampf(dmg * 0.8, 0.5, 18.0)
	var stun := m.stun * (0.7 + 0.3 * q)
	if counter:
		stun += Tuning.v("counter_stun_bonus")
	var h := {
		"attacker": a, "damage": dmg if not parried else 0.0, "point": c["point"], "normal": n,
		"seg": seg_i, "part": seg.part, "blocked": blocked, "parried": parried, "counter": counter,
		"knockback": kb, "local_impulse": local_imp, "stun": stun if not blocked else 0.0,
		"poise": m.poise * (0.6 + 0.4 * q), "knockdown": m.knockdown and not blocked,
		"guard_drain": guard_drain, "hype_mult": m.hype, "quality": q, "element": m.element,
	}
	if not blocked and not parried:
		a.stamina = minf(a.max_stamina, a.stamina + m.stamina * Tuning.v("hit_stamina_refund"))
	b.receive_hit(h)
	if not blocked and not parried and m.element != "" and m.buildup > 0.0:
		b.statuses.add_buildup(m.element, m.buildup * (0.6 + 0.4 * q), a)
	sim.emit_event({"type": "hit", "fighter": a.index, "target": b.index, "damage": h["damage"],
		"point": c["point"], "normal": n, "blocked": blocked, "parried": parried, "counter": counter,
		"part": seg.part, "element": m.element, "quality": q, "move": m.id, "slot": a.move_slot,
		"knockdown": h["knockdown"], "otg": downed})


## Non-weapon damage (pummels, throws, slams, effects, hazards). Respects defense and guard
## only where noted; never parried.
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
		"knockdown": bool(extra.get("knockdown", false)), "hype_mult": 1.0}
	b.receive_hit(h)
	sim.emit_event({"type": "hit", "fighter": source.index if source else -1, "target": b.index,
		"damage": dmg, "point": b.pos(), "normal": Vector3.UP, "blocked": false, "parried": false,
		"counter": false, "part": "core", "element": str(extra.get("element", "")), "quality": 1.0,
		"move": kind, "slot": kind, "knockdown": h["knockdown"], "otg": false})
