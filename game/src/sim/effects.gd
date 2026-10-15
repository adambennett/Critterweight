class_name EffectsSystem
extends RefCounted
## Runs the timed effect events of abilities/moves (projectiles, area pulses, zones, buffs,
## dashes, leaps, pulls, heals, shields, blinks, props) and owns the resulting simulation
## entities. Everything here is authoritative simulation; views mirror `entities` and events.
##
## Effect vocabulary and parameters are documented in docs/MODDING.md#effects and validated by
## content/schemas/effect.schema.json. Unknown effect types are rejected at load time.

const TYPES := ["projectile", "area", "zone", "buff", "debuff", "heal", "shield", "dash", "leap",
	"pull", "push", "blink", "prop", "self_damage", "cleanse", "hype"]

var sim: MatchSim
var entities: Array = []         ## projectiles and zones (Dictionaries; see _spawn_*)
var _fired := {}                 ## fighter index -> PackedByteArray of fired effect indices
var _next_id := 1


func _init(match_sim) -> void:
	sim = match_sim


static func validate(effect: Dictionary) -> String:
	var t := str(effect.get("type", ""))
	if not TYPES.has(t):
		return "unknown effect type '%s'" % t
	if not effect.has("t"):
		return "effect '%s' needs a time 't'" % t
	return ""


func begin_move(f: Fighter, m: MoveDef) -> void:
	var fired := PackedByteArray()
	fired.resize(m.effects.size())
	_fired[f.index] = fired


func tick_move(f: Fighter, m: MoveDef, t: float, _dt: float) -> void:
	var fired: PackedByteArray = _fired.get(f.index, PackedByteArray())
	if fired.size() != m.effects.size():
		begin_move(f, m)
		fired = _fired[f.index]
	for i in m.effects.size():
		if fired[i] == 0 and t >= float(m.effects[i].get("t", 0.0)):
			fired[i] = 1
			fire(f, m.effects[i], m)
	_fired[f.index] = fired


func end_move(f: Fighter, _m: MoveDef) -> void:
	_fired.erase(f.index)
	if f.flags.has("leaping"):
		f.flags.erase("leaping")
		f.rig.support = 1.0


## Fires one effect for fighter f immediately.
func fire(f: Fighter, e: Dictionary, m: MoveDef = null) -> void:
	var t := str(e.get("type", ""))
	match t:
		"projectile":
			var count := int(e.get("count", 1))
			var spread := deg_to_rad(float(e.get("spread_deg", 0.0)))
			for k in count:
				var off := 0.0 if count == 1 else lerpf(-spread * 0.5, spread * 0.5, float(k) / float(count - 1))
				_spawn_projectile(f, e, off)
		"area":
			_area(f, e, _point(f, e), m)
		"zone":
			_spawn_zone(f, e, _point(f, e))
		"buff", "debuff":
			var st: Dictionary = e.get("status", {}).duplicate()
			if not st.has("id"):
				st["id"] = "%s_%s" % [f.creature.id, e.get("name", t)]
			st["source"] = f
			if t == "buff":
				f.statuses.add(st)
			else:
				for o: Fighter in _enemies_in(f, _point(f, e), float(e.get("radius", 2.5))):
					o.statuses.add(st)
		"heal":
			f.heal(float(e.get("amount", 10.0)))
		"shield":
			f.flags["shield"] = float(e.get("amount", 20.0))
			f.flags["shield_until"] = f.time + float(e.get("duration", 4.0))
		"dash":
			var dir := f.forward()
			f.rig.apply_body_impulse(dir * float(e.get("speed", 8.0)) * f.rig.total_mass)
			if bool(e.get("evade", false)):
				f.evade_until = f.time + float(e.get("time", 0.2))
		"leap":
			var dist := float(e.get("distance", 4.0))
			var to := f.forward() * dist
			if f.target and bool(e.get("to_target", true)):
				to = f.target.pos() - f.pos()
				to.y = 0.0
				if to.length() > dist:
					to = to.normalized() * dist
			var air := float(e.get("time", 0.55))
			var vy := 9.81 * air * 0.5 + float(e.get("height", 0.0))
			f.rig.support = 0.0
			f.flags["leaping"] = true
			f.rig.freeze_motion()
			f.rig.apply_body_impulse((to / air + Vector3.UP * vy) * f.rig.total_mass)
		"pull", "push":
			var p := _point(f, e)
			var s := float(e.get("strength", 5.0)) * (-1.0 if t == "pull" else 1.0)
			for o: Fighter in _enemies_in(f, p, float(e.get("radius", 3.0))):
				var d := o.pos() - p
				d.y = 0.0
				o.rig.apply_body_impulse(d.normalized() * s * o.rig.total_mass * sqrt(Tuning.v("ref_mass") / maxf(20.0, o.rig.total_mass)))
				if float(e.get("stun", 0.0)) > 0.0:
					o.stun(float(e["stun"]), false)
		"blink":
			var dist2 := float(e.get("distance", 3.0))
			var dest := f.pos() + f.forward() * dist2
			dest = sim.clamp_to_arena(dest, 0.6)
			f.rig.place(Vector3(dest.x, f.rig.ground_y, dest.z), f.facing_yaw)
			f.motor.reset_feet()
			f.invuln_until = f.time + float(e.get("invuln", 0.25))
		"prop":
			_spawn_zone(f, e, _point(f, e))
		"self_damage":
			f.health = maxf(1.0, f.health - float(e.get("amount", 5.0)))
		"cleanse":
			for st2 in f.statuses.active.duplicate():
				if st2.get("element", "") != "":
					f.statuses.active.erase(st2)
		"hype":
			f.hype = clampf(f.hype + float(e.get("amount", 10.0)), 0.0, 100.0)
	sim.emit_event({"type": "effect", "fighter": f.index, "effect": t, "pos": _point(f, e), "element": e.get("element", ""), "vfx": e.get("vfx", t)})


## Resolves where an effect happens: "self" (default), "forward:<m>", "target", "weapon:<name>".
func _point(f: Fighter, e: Dictionary) -> Vector3:
	var at := str(e.get("at", "self"))
	var p := f.ground_pos()
	if at.begins_with("forward"):
		var parts := at.split(":")
		var d := float(parts[1]) if parts.size() > 1 else 1.2
		p += f.forward() * d * f.creature.body.scale
	elif at == "target" and f.target:
		p = f.target.ground_pos()
	elif at.begins_with("weapon:"):
		var wn := at.substr(7)
		var w: BodyDef.Weapon = f.creature.body.weapons.get(wn)
		if w:
			p = f.rig.bodies[w.seg].global_transform * w.local
	return p


func _enemies_in(f: Fighter, p: Vector3, r: float) -> Array:
	var out := []
	for o: Fighter in sim.fighters:
		if o == f or o.is_out() or not sim.can_hit(f, o) or o.is_evading():
			continue
		var d := o.pos() - p
		d.y *= 0.5
		if d.length() <= r + 0.3:
			out.append(o)
	return out


func _area(f: Fighter, e: Dictionary, p: Vector3, _m: MoveDef) -> void:
	var r := float(e.get("radius", 2.0))
	var cone := deg_to_rad(float(e.get("cone_deg", 360.0)))
	for o: Fighter in _enemies_in(f, p, r):
		if cone < TAU - 0.01:
			var to: Vector3 = o.pos() - f.pos()
			to.y = 0.0
			if absf(f.forward().signed_angle_to(to, Vector3.UP)) > cone * 0.5:
				continue
		_effect_hit(f, o, e, p)


## Applies an effect's damage package to a target (projectiles, areas, zone ticks).
func _effect_hit(f: Fighter, o: Fighter, e: Dictionary, from: Vector3) -> void:
	var dmg := float(e.get("damage", 0.0))
	var away := o.pos() - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 1e-6 else (f.forward() if f else Vector3.FORWARD)
	var kb := away * float(e.get("knockback", 0.0)) * sqrt(Tuning.v("ref_mass") / maxf(20.0, o.rig.total_mass)) + Vector3.UP * float(e.get("launch", 0.0))
	var blocked := false
	if f and not bool(e.get("unblockable", false)) and o.guards_against(from + Vector3.UP * 0.5):
		if o.in_parry_window():
			o.receive_hit({"attacker": f, "parried": true, "damage": 0.0, "point": o.pos()})
			return
		blocked = true
		dmg *= Tuning.v("guard_damage_mult")
		kb *= 0.35
		o.spend_stamina(float(e.get("damage", 0.0)) * Tuning.v("guard_stamina_per_damage"))
	if f:
		dmg *= float(f.mods["damage"]) * f.eff("power") * f.statuses.damage_dealt_mult()
	dmg *= float(o.mods["defense"]) * o.eff("defense") * o.statuses.damage_taken_mult()
	dmg *= Elements.damage_mult(str(e.get("element", "")), o.creature.element)
	dmg *= o.combo_damage_scale()
	var h := {"attacker": f, "damage": dmg, "point": o.pos(), "normal": -away, "seg": 0, "part": "core",
		"blocked": blocked, "parried": false, "counter": false, "knockback": kb,
		"local_impulse": Vector3.ZERO, "stun": 0.0 if blocked else float(e.get("stun", 0.2)),
		"poise": float(e.get("poise", 8.0)), "knockdown": bool(e.get("knockdown", false)) and not blocked,
		"hype_mult": 1.0, "guard_drain": 0.0}
	o.receive_hit(h)
	var el := str(e.get("element", ""))
	if not blocked and el != "" and float(e.get("buildup", 0.0)) > 0.0:
		o.statuses.add_buildup(el, float(e["buildup"]), f)
	if not blocked and e.has("status"):
		var st: Dictionary = e["status"].duplicate()
		st["source"] = f
		o.statuses.add(st)
	sim.emit_event({"type": "hit", "fighter": f.index if f else -1, "target": o.index, "damage": dmg,
		"point": o.pos() + Vector3.UP * 0.5, "normal": -away, "blocked": blocked, "parried": false,
		"counter": false, "part": "core", "element": el, "quality": 1.0, "move": str(e.get("id", e.get("type", ""))),
		"slot": "effect", "knockdown": h["knockdown"], "otg": false})


# ---------------------------------------------------------------------------------------
# Entities
# ---------------------------------------------------------------------------------------

func _spawn_projectile(f: Fighter, e: Dictionary, yaw_off: float) -> void:
	var origin := f.pos() + MathX.yaw_basis(f.facing_yaw) * (MathX.vec3(e.get("offset", [0, 0.3, 0.6])) * f.creature.body.scale)
	var from_w := str(e.get("from", ""))
	if from_w != "" and f.creature.body.weapons.has(from_w):
		var w: BodyDef.Weapon = f.creature.body.weapons[from_w]
		origin = f.rig.bodies[w.seg].global_transform * w.local
	var dir := MathX.yaw_basis(f.facing_yaw + yaw_off) * Vector3.FORWARD
	if f.target and str(e.get("aim", "forward")) == "target":
		var to := f.target.pos() + Vector3.UP * 0.3 - origin
		dir = MathX.yaw_basis(yaw_off) * to.normalized()
	var spd := float(e.get("speed", 12.0))
	var vel := dir * spd + Vector3.UP * float(e.get("lob", 0.0))
	var ent := {"id": _next_id, "kind": "projectile", "owner": f.index, "team": f.team, "pos": origin, "vel": vel,
		"radius": float(e.get("radius", 0.25)), "life": float(e.get("life", 1.6)), "gravity": float(e.get("gravity", 0.0)),
		"homing": float(e.get("homing", 0.0)), "bounces": int(e.get("bounce", 0)), "pierce": bool(e.get("pierce", false)),
		"boomerang": float(e.get("boomerang", 0.0)), "age": 0.0, "hit": {}, "e": e, "element": str(e.get("element", "")),
		"vfx": str(e.get("vfx", "orb"))}
	_next_id += 1
	entities.append(ent)


func _spawn_zone(f: Fighter, e: Dictionary, p: Vector3) -> void:
	var ent := {"id": _next_id, "kind": "zone", "owner": f.index if f else -1, "team": f.team if f else -1,
		"pos": p, "radius": float(e.get("radius", 2.0)), "life": float(e.get("duration", 4.0)),
		"tick": float(e.get("tick", 0.5)), "_t": 0.0, "age": 0.0, "e": e, "element": str(e.get("element", "")),
		"vfx": str(e.get("vfx", "zone")), "friendly": bool(e.get("friendly", false))}
	_next_id += 1
	entities.append(ent)


func spawn_hazard_zone(p: Vector3, e: Dictionary) -> void:
	_spawn_zone(null, e, p)


func update(dt: float) -> void:
	for ent in entities.duplicate():
		ent["age"] = float(ent["age"]) + dt
		if ent["kind"] == "projectile":
			_update_projectile(ent, dt)
		else:
			_update_zone(ent, dt)
		if float(ent["age"]) >= float(ent["life"]):
			_expire(ent)


func _owner(ent: Dictionary) -> Fighter:
	var i := int(ent["owner"])
	return sim.fighters[i] if i >= 0 and i < sim.fighters.size() else null


func _update_projectile(ent: Dictionary, dt: float) -> void:
	var f := _owner(ent)
	var vel: Vector3 = ent["vel"]
	vel.y -= float(ent["gravity"]) * dt
	var hom := float(ent["homing"])
	if hom > 0.0 and f and f.target and not f.target.is_out():
		var want: Vector3 = (f.target.pos() + Vector3.UP * 0.3 - Vector3(ent["pos"])).normalized() * vel.length()
		vel = vel.lerp(want, clampf(hom * dt, 0.0, 1.0))
	var boom := float(ent["boomerang"])
	if boom > 0.0 and float(ent["age"]) > boom and f:
		var back: Vector3 = (f.pos() + Vector3.UP * 0.4 - Vector3(ent["pos"]))
		vel = vel.lerp(back.normalized() * vel.length(), clampf(6.0 * dt, 0.0, 1.0))
		if back.length() < 0.6:
			ent["life"] = 0.0
	var p: Vector3 = ent["pos"] + vel * dt
	# floor / arena bounds
	if p.y < float(ent["radius"]) * 0.5:
		if int(ent["bounces"]) > 0:
			ent["bounces"] = int(ent["bounces"]) - 1
			vel.y = absf(vel.y) * 0.6
			p.y = float(ent["radius"]) * 0.5
		else:
			ent["life"] = 0.0
	var clamped: Vector3 = sim.clamp_to_arena(p, float(ent["radius"]))
	if clamped.distance_squared_to(Vector3(p.x, clamped.y, p.z)) > 1e-4:
		if int(ent["bounces"]) > 0:
			ent["bounces"] = int(ent["bounces"]) - 1
			var n := (clamped - p)
			n.y = 0.0
			n = n.normalized()
			vel = vel.bounce(n)
			p = clamped
		else:
			ent["life"] = 0.0
	ent["vel"] = vel
	ent["pos"] = p
	# fighters
	for o: Fighter in sim.fighters:
		if f and (o == f or not sim.can_hit(f, o)):
			continue
		if o.is_out() or o.is_evading() or ent["hit"].has(o.index):
			continue
		if o.pos().distance_squared_to(p) > 6.0:
			continue
		var c := sim.combat.find_contact(p, float(ent["radius"]), o)
		if c.is_empty():
			continue
		# reflectors bounce projectiles back at their owner
		if o.flags.get("reflect_until", -1.0) > o.time:
			ent["owner"] = o.index
			ent["team"] = o.team
			ent["vel"] = -vel
			ent["hit"] = {}
			sim.emit_event({"type": "reflect", "fighter": o.index, "pos": p})
			return
		ent["hit"][o.index] = true
		_effect_hit(f, o, ent["e"], p - vel.normalized() * 0.5)
		if not bool(ent["pierce"]):
			ent["life"] = 0.0
			break


func _update_zone(ent: Dictionary, dt: float) -> void:
	ent["_t"] = float(ent["_t"]) + dt
	if float(ent["_t"]) < float(ent["tick"]):
		return
	ent["_t"] = 0.0
	var f := _owner(ent)
	var e: Dictionary = ent["e"]
	for o: Fighter in sim.fighters:
		if o.is_out():
			continue
		if f and o == f and not bool(e.get("affects_owner", false)):
			continue
		if f and o != f and not sim.can_hit(f, o) and not bool(ent["friendly"]):
			continue
		var d: Vector3 = o.pos() - Vector3(ent["pos"])
		d.y = 0.0
		if d.length() > float(ent["radius"]):
			continue
		if float(e.get("tick_damage", 0.0)) > 0.0:
			sim.combat.apply_simple_damage(f, o, float(e["tick_damage"]), "zone", {"element": e.get("element", "")})
		var el := str(e.get("element", ""))
		if el != "" and float(e.get("buildup", 0.0)) > 0.0:
			o.statuses.add_buildup(el, float(e["buildup"]), f)
		if e.has("status"):
			var st: Dictionary = e["status"].duplicate()
			st["source"] = f
			o.statuses.add(st)
		if float(e.get("heal", 0.0)) > 0.0 and f and not sim.are_enemies(f, o):
			o.heal(float(e["heal"]))


func _expire(ent: Dictionary) -> void:
	entities.erase(ent)
	var e: Dictionary = ent["e"]
	if e.has("on_expire"):
		var f := _owner(ent)
		var ex: Dictionary = e["on_expire"]
		if str(ex.get("type", "area")) == "area":
			if f:
				_area(f, ex, ent["pos"], null)
		elif str(ex.get("type", "")) == "zone":
			_spawn_zone(f, ex, ent["pos"])
		sim.emit_event({"type": "effect", "fighter": int(ent["owner"]), "effect": str(ex.get("type", "area")), "pos": ent["pos"], "element": ex.get("element", ""), "vfx": ex.get("vfx", "burst")})


## Elemental reaction effects: a burst on the victim (damage/knockdown/area), per elements.json.
func trigger_reaction(r: Dictionary, victim: Fighter, source, el_a: String, el_b: String) -> void:
	var p := victim.ground_pos()
	var src: Fighter = source if source is Fighter else null
	var dmg := float(r.get("damage", 0.0))
	if dmg > 0.0:
		sim.combat.apply_simple_damage(src, victim, dmg, "reaction", {"knockdown": bool(r.get("knockdown", false)), "stun": float(r.get("stun", 0.0))})
	if float(r.get("radius", 0.0)) > 0.0 and src:
		var area := {"radius": r["radius"], "damage": float(r.get("splash_damage", dmg * 0.5)), "knockback": float(r.get("knockback", 3.0)), "stun": float(r.get("stun", 0.2))}
		for o: Fighter in _enemies_in(src, p, float(r["radius"])):
			if o != victim:
				_effect_hit(src, o, area, p)
	if r.has("status"):
		var st: Dictionary = r["status"].duplicate()
		st["source"] = src
		victim.statuses.add(st)
	if r.has("zone"):
		_spawn_zone(src, r["zone"], p)
	sim.emit_event({"type": "reaction", "fighter": victim.index, "reaction": str(r.get("id", "")), "name": str(r.get("name", "")), "a": el_a, "b": el_b, "pos": p})
