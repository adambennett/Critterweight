class_name EffectsSystem
extends RefCounted
## Runs timed effect events of moves/abilities/hooks and owns simulation entities (projectiles,
## zones, props, delayed strikes). Authoritative; views mirror `entities` and events.
## Effect vocabulary (validated at load; documented in docs/MODDING.md#effects):
##   projectile area zone buff debuff heal shield dash leap hover charge counter_stance reflect
##   pull push blink prop delayed destroy_projectiles chain_arc self_damage cleanse hype juice_state
## Common fields: t (seconds into the move), at ("self" | "forward:<m>" | "target" | "weapon:<n>"
## | "stick:<m>"), element, buildup, damage, knockback, launch, stun, poise, knockdown, status {}.

const TYPES := ["projectile", "area", "zone", "buff", "debuff", "heal", "shield", "dash", "leap", "hover",
	"charge", "counter_stance", "reflect", "pull", "push", "blink", "prop", "delayed", "destroy_projectiles",
	"chain_arc", "self_damage", "cleanse", "hype", "juice_state"]

var sim: MatchSim
var entities: Array = []         ## projectiles, zones, props, delayed strikes (Dictionaries)
var _fired := {}                 ## fighter index -> PackedByteArray of fired effect indices
var _next_id := 1
var _zone_count := 0


func _init(match_sim) -> void:
	sim = match_sim


static func validate(effect: Dictionary) -> String:
	var t := str(effect.get("type", ""))
	if not TYPES.has(t):
		return "unknown effect type '%s'" % t
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


# =====================================================================================
# Firing
# =====================================================================================

func fire(f: Fighter, e: Dictionary, m: MoveDef = null) -> void:
	var t := str(e.get("type", ""))
	var p := _point(f, e)
	match t:
		"projectile":
			if f.is_out():
				return
			var count := int(e.get("count", 1))
			var spread := deg_to_rad(float(e.get("spread_deg", 0.0)))
			for k in count:
				var off := 0.0 if count == 1 else lerpf(-spread * 0.5, spread * 0.5, float(k) / float(count - 1))
				_spawn_projectile(f, e, off)
		"area":
			area(f, e, p)
		"zone":
			spawn_zone(f, e, p)
		"buff":
			var st: Dictionary = e.get("status", {}).duplicate(true)
			if not st.has("id"):
				st["id"] = "%s_%s" % [f.creature.id, e.get("name", "buff")]
			st["source"] = f
			f.statuses.add(st)
		"debuff":
			var st2: Dictionary = e.get("status", {}).duplicate(true)
			st2["source"] = f
			for o: Fighter in enemies_in(f, p, float(e.get("radius", 2.5))):
				o.statuses.add(st2)
		"heal":
			f.heal(float(e.get("amount", 10.0)))
		"shield":
			f.set_flag("shield", float(e.get("duration", 4.0)))
			f.shield_hp = float(e.get("amount", 20.0))
		"dash":
			var dir := f.forward()
			if str(e.get("dir", "forward")) == "stick" and f.input.move.length() > 0.3:
				dir = f.input.move.normalized()
			f.rig.apply_body_impulse(dir * float(e.get("speed", 8.0)) * f.rig.total_mass)
			if bool(e.get("evade", false)):
				f.evade_until = f.time + float(e.get("time", 0.2))
		"leap":
			_leap(f, e)
		"hover":
			if not f.statuses.flag("no_hover"):
				f.start_hover(float(e.get("height", 2.0)), float(e.get("duration", 1.2)), float(e.get("speed", 3.0)))
		"charge":
			f.start_charge(e)
		"counter_stance":
			f.start_counter(e)
		"reflect":
			f.set_flag("reflect", float(e.get("duration", 0.6)))
		"pull", "push":
			var s := float(e.get("strength", 5.0)) * (-1.0 if t == "pull" else 1.0)
			push_objects(f, p, float(e.get("radius", 3.0)), s, str(e.get("element", "")))
			for o: Fighter in enemies_in(f, p, float(e.get("radius", 3.0))):
				var d := o.pos() - p
				d.y = 0.0
				var push_mult := o.statuses.mult("push_taken")
				o.rig.apply_body_impulse(d.normalized() * s * push_mult * o.rig.total_mass * sqrt(Tuning.v("ref_mass") / maxf(20.0, o.rig.total_mass)))
				if float(e.get("stun", 0.0)) > 0.0:
					o.stun(float(e["stun"]), false)
		"blink":
			_blink(f, e)
		"prop":
			_spawn_prop(f, e, p)
		"delayed":
			_spawn_delayed(f, e, p)
		"destroy_projectiles":
			_destroy_projectiles(f, p, float(e.get("radius", 2.0)), float(e.get("cone_deg", 360.0)))
		"chain_arc":
			_chain_arc(f, e, p)
		"self_damage":
			f.health = maxf(1.0, f.health - float(e.get("amount", 5.0)))
		"cleanse":
			f.statuses.cleanse_elements()
		"hype":
			f.hype = clampf(f.hype + float(e.get("amount", 10.0)), 0.0, 100.0)
		"juice_state":
			f.apply_juice_state(e)
	sim.emit_event({"type": "effect", "fighter": f.index, "effect": t, "pos": p, "element": e.get("element", ""),
		"vfx": e.get("vfx", t), "radius": float(e.get("radius", 0.0)), "shape": str(e.get("shape", "circle")),
		"yaw": f.facing_yaw, "move": m.id if m else ""})


## Resolves where an effect happens.
func _point(f: Fighter, e: Dictionary) -> Vector3:
	if e.has("at_point"):
		var ap: Vector3 = e["at_point"]
		return Vector3(ap.x, f.rig.ground_y, ap.z)
	var at := str(e.get("at", "self"))
	var p := f.ground_pos()
	if at.begins_with("forward"):
		var parts := at.split(":")
		var d := float(parts[1]) if parts.size() > 1 else 1.2
		p += f.forward() * d
	elif at == "target" and f.target:
		p = f.target.ground_pos()
	elif at.begins_with("weapon:"):
		var w: BodyDef.Weapon = f.creature.body.weapons.get(at.substr(7))
		if w:
			var wp := f.rig.bodies[w.seg].global_transform * w.local
			p = Vector3(wp.x, f.rig.ground_y, wp.z)
	elif at.begins_with("stick"):
		var parts2 := at.split(":")
		var d2 := float(parts2[1]) if parts2.size() > 1 else 3.0
		var dir := f.input.move.normalized() if f.input.move.length() > 0.3 else f.forward()
		p += dir * d2
	elif at.begins_with("target_point"):
		var parts3 := at.split(":")
		var maxd := float(parts3[1]) if parts3.size() > 1 else 3.0
		var to := (f.target.ground_pos() - p) if f.target else f.forward() * maxd
		to.y = 0.0
		if to.length() > maxd:
			to = to.normalized() * maxd
		p += to
	return sim.clamp_to_arena(p, 0.3)


func enemies_in(f: Fighter, p: Vector3, r: float, include_allies := false) -> Array:
	var out := []
	for o: Fighter in sim.fighters:
		if o.is_out() or o.is_evading():
			continue
		if f and o == f:
			continue
		if f and not include_allies and not sim.can_hit(f, o):
			continue
		var d := o.pos() - p
		d.y *= 0.5
		if d.length() <= r + 0.3:
			out.append(o)
	return out


## Instant area: shape circle (default), cone (cone_deg, from self facing), line (length/width
## forward from self), ring (inner/outer), cone_back.
func area(f: Fighter, e: Dictionary, p: Vector3) -> void:
	var shape := str(e.get("shape", "circle"))
	var r := float(e.get("radius", 2.0))
	push_objects(f, p, r + 0.3, float(e.get("knockback", 0.0)) + float(e.get("strength", 0.0)), str(e.get("element", "")))
	if shape == "line":
		r = float(e.get("length", 3.0)) + 1.0
	var origin := p
	if shape in ["cone", "line"]:
		origin = f.ground_pos()
	for o: Fighter in enemies_in(f, origin if shape != "circle" else p, r + 1.0, bool(e.get("affects_allies", false))):
		var to: Vector3 = o.pos() - origin
		to.y = 0.0
		match shape:
			"cone", "cone_back":
				var fwd := f.forward() if shape == "cone" else -f.forward()
				var cone := deg_to_rad(float(e.get("cone_deg", 60.0)))
				if to.length() > r + 0.3 or absf(fwd.signed_angle_to(to, Vector3.UP)) > cone * 0.5:
					continue
			"line":
				var fwd2 := f.forward()
				var along := to.dot(fwd2)
				var across := absf(to.dot(fwd2.cross(Vector3.UP)))
				if along < -0.3 or along > float(e.get("length", 3.0)) or across > float(e.get("width", 1.0)) * 0.5 + 0.3:
					continue
			"ring":
				var dd := Vector2(o.pos().x - p.x, o.pos().z - p.z).length()
				if dd > r + 0.3 or dd < float(e.get("inner", 0.0)):
					continue
			_:
				if Vector2(o.pos().x - p.x, o.pos().z - p.z).length() > r + 0.3:
					continue
		effect_hit(f, o, e, origin if shape != "circle" else p)


## Applies an effect's damage package to a target (projectiles, areas, zones, reactions).
func effect_hit(f: Fighter, o: Fighter, e: Dictionary, from: Vector3) -> void:
	var away := o.pos() - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 1e-6 else (f.forward() if f else Vector3.FORWARD)
	var kb_dir := away
	match str(e.get("kb_dir", "away")):
		"forward":
			kb_dir = f.forward() if f else away
		"toward":
			kb_dir = -away
	var mass_k := sqrt(Tuning.v("ref_mass") / maxf(20.0, o.rig.total_mass))
	var h := {"attacker": f, "damage": float(e.get("damage", 0.0)), "point": o.pos() + Vector3.UP * 0.4,
		"normal": -away, "seg": 0, "part": "core", "blocked": false, "parried": false, "counter": false,
		"knockback": kb_dir * float(e.get("knockback", 0.0)) * mass_k + Vector3.UP * float(e.get("launch", 0.0)),
		"local_impulse": Vector3.ZERO, "stun": float(e.get("stun", 0.2)), "poise": float(e.get("poise", 8.0)),
		"knockdown": bool(e.get("knockdown", false)), "hype_mult": 1.0, "guard_drain": float(e.get("damage", 0.0)) * Tuning.v("guard_stamina_per_damage"),
		"element": str(e.get("element", "")), "buildup": float(e.get("buildup", 0.0)), "quality": 1.0,
		"move": str(e.get("id", e.get("type", "effect"))), "slot": "effect", "move_class": str(e.get("class", "ability")),
		"unblockable": bool(e.get("unblockable", false)), "parryable": bool(e.get("parryable", false)),
		"from": from, "status": e.get("status", {}), "splat": e.get("splat", {}), "melee": false,
		"no_otg_limit": false, "ally": f != null and not sim.are_enemies(f, o)}
	sim.combat.deliver(f, o, h)


# ---------------------------------------------------------------------------------------
# Movement-type effects
# ---------------------------------------------------------------------------------------

func _leap(f: Fighter, e: Dictionary) -> void:
	if f.statuses.flag("no_leap"):
		return
	var dist := float(e.get("distance", 4.0))
	var to := f.forward() * dist
	if f.target and bool(e.get("to_target", true)):
		to = f.target.pos() - f.pos()
		to.y = 0.0
		if to.length() > dist:
			to = to.normalized() * dist
	var dest := sim.clamp_to_arena(f.pos() + to, 0.5)
	to = dest - f.pos()
	to.y = 0.0
	var air := float(e.get("time", 0.55))
	var apex := float(e.get("height", 1.0))
	var vy := maxf(sim.gravity * air * 0.5, sqrt(2.0 * sim.gravity * maxf(apex, 0.1)))
	air = 2.0 * vy / sim.gravity
	f.begin_airborne(e.get("on_land", []), air)
	f.rig.freeze_motion()
	f.rig.apply_body_impulse((to / air + Vector3.UP * vy) * f.rig.total_mass)


func _blink(f: Fighter, e: Dictionary) -> void:
	if f.statuses.flag("no_blink"):
		return
	var dist := float(e.get("distance", 3.0))
	var dir := f.forward()
	if str(e.get("dir", "forward")) == "stick" and f.input.move.length() > 0.3:
		dir = f.input.move.normalized()
	var dest := sim.clamp_to_arena(f.pos() + dir * dist, 0.6)
	var delay := float(e.get("delay", 0.0))
	f.invuln_until = f.time + delay + float(e.get("invuln", 0.25))
	if delay > 0.0:
		f.begin_submerge(dest, delay, e.get("on_emerge", []))
	else:
		f.rig.place(Vector3(dest.x, f.rig.ground_y, dest.z), f.facing_yaw)
		f.motor.reset_feet()


# ---------------------------------------------------------------------------------------
# Entities
# ---------------------------------------------------------------------------------------

func _spawn_projectile(f: Fighter, e: Dictionary, yaw_off: float) -> void:
	# offset is in fighter space like body pivots: floor at y = 0, +Z forward, +X the fighter's left
	var origin := f.ground_pos() + MathX.yaw_basis(f.facing_yaw) * MathX.vec3(e.get("offset", [0, 1.1, 0.5]))
	var from_w := str(e.get("from", ""))
	if from_w != "" and f.creature.body.weapons.has(from_w):
		var w: BodyDef.Weapon = f.creature.body.weapons[from_w]
		origin = f.rig.bodies[w.seg].global_transform * w.local
	var spd := float(e.get("speed", 12.0))
	var dir := MathX.forward_of_yaw(f.facing_yaw + yaw_off)   # fighter space: +Z is forward
	var vel := dir * spd
	var grav := float(e.get("gravity", 0.0))
	if bool(e.get("lob", false)):
		# ballistic arc to the target's position (or max range ahead), horizontal speed = speed
		grav = sim.gravity
		var maxr := float(e.get("range", 7.0))
		var tp := f.target.pos() if f.target else origin + dir * maxr
		var to := tp - origin
		var horiz := Vector3(to.x, 0.0, to.z)
		if horiz.length() > maxr:
			horiz = horiz.normalized() * maxr
		if horiz.length() < 0.5:
			horiz = dir * 0.5
		horiz = horiz.rotated(Vector3.UP, yaw_off)
		var tflight := horiz.length() / spd
		var dy := (tp.y - origin.y) * 0.0 - 0.3
		vel = horiz / tflight + Vector3.UP * ((dy + 0.5 * grav * tflight * tflight) / tflight)
	elif f.target and str(e.get("aim", "forward")) == "target":
		var to2 := f.target.pos() + Vector3.UP * 0.3 - origin
		vel = (MathX.yaw_basis(yaw_off) * to2.normalized()) * spd
	var ent := {"id": _next_id, "kind": "projectile", "owner": f.index, "team": f.team, "pos": origin, "vel": vel,
		"radius": float(e.get("radius", 0.25)), "life": float(e.get("life", 1.6)), "gravity": grav,
		"homing": deg_to_rad(float(e.get("homing_deg", 0.0))), "bounces": int(e.get("bounce", 0)), "pierce": bool(e.get("pierce", false)),
		"boomerang": float(e.get("boomerang", 0.0)), "age": 0.0, "hit": {}, "e": e, "element": str(e.get("element", "")),
		"vfx": str(e.get("vfx", "orb")), "reflectable": bool(e.get("reflectable", true))}
	_next_id += 1
	entities.append(ent)


## Spawns a zone. `kind` refers to elements.json zones/derived_zones; explicit fields override.
func spawn_zone(f: Fighter, e: Dictionary, p: Vector3) -> Dictionary:
	var spec := {}
	var kind := str(e.get("kind", ""))
	if kind != "":
		spec = Elements.zone_def(kind).duplicate(true)
	for k in e:
		if not k in ["type", "t", "at", "kind"]:
			spec[k] = e[k]
	var el := str(spec.get("element", ""))
	if el != "" and not bool(e.get("skip_zone_reaction", false)):
		var reacted := _zone_reaction(f, el, p, float(spec.get("radius", 1.5)))
		if reacted:
			return {}
	var mult := float(f.mods.get("zone_size", 1.0)) if f else 1.0
	var ent := {"id": _next_id, "kind": "zone", "zone_kind": kind, "owner": f.index if f else -1, "team": f.team if f else -1,
		"pos": Vector3(p.x, 0.0, p.z), "radius": float(spec.get("radius", 2.0)) * sqrt(mult),
		"life": float(spec.get("duration", 4.0)) + float(f.mods.get("zone_duration_add", 0.0) if f else 0.0),
		"tick": float(spec.get("tick", 0.5)), "_t": 0.0, "age": 0.0, "e": spec, "element": el,
		"vfx": str(spec.get("vfx", kind if kind != "" else "zone")), "friendly": bool(spec.get("friendly", false)),
		"follow": bool(spec.get("follow_owner", false)), "inside": {}, "line_dir": spec.get("line_dir", Vector3.ZERO)}
	_next_id += 1
	entities.append(ent)
	_zone_count += 1
	_enforce_zone_cap()
	return ent


func _enforce_zone_cap() -> void:
	var cap := int(sim.rules.get("max_zones", Elements.rules.get("max_zones", 24)))
	var zones := entities.filter(func(x): return x["kind"] == "zone" and not x["e"].has("hazard"))
	while zones.size() > cap:
		var oldest: Dictionary = zones.pop_front()
		entities.erase(oldest)


## Zone-on-zone interactions (ELEMENTS.md §3 zone versions). Returns true if the incoming zone
## was consumed by the reaction.
func _zone_reaction(f: Fighter, incoming_el: String, p: Vector3, r: float) -> bool:
	for z in entities.duplicate():
		if z["kind"] != "zone" or str(z.get("zone_kind", "")) == "":
			continue
		var d := Vector2(z["pos"].x - p.x, z["pos"].z - p.z).length()
		if d > float(z["radius"]) + r * 0.5:
			continue
		var zr := Elements.zone_reaction(str(z["zone_kind"]), incoming_el)
		if zr.is_empty():
			continue
		var result := str(zr.get("result", ""))
		if bool(zr.get("removes_existing", false)):
			entities.erase(z)
		match result:
			"grow":
				z["radius"] = float(z["radius"]) * float(zr.get("grow", 1.5))
				z["tick"] = float(z["tick"]) / maxf(0.1, float(zr.get("tick_mult", 1.0)))
			"rubble_prop":
				_spawn_prop(f, {"prop": "rubble", "hp": 20.0, "radius": 0.75, "duration": 10.0}, z["pos"])
			"smear":
				z["radius"] = float(z["radius"]) * 0.8
				var dir := f.forward() if f else Vector3.FORWARD
				for k in 3:
					spawn_zone(f, {"kind": "sludge_puddle", "radius": 0.7, "duration": 3.0, "skip_zone_reaction": true}, z["pos"] + dir * (1.0 + k * 1.0))
			"slide":
				var dir2 := f.forward() if f else Vector3.FORWARD
				z["pos"] = sim.clamp_to_arena(z["pos"] + dir2 * float(zr.get("slide", 2.0)), 0.5)
				z["radius"] = float(z["radius"]) * sqrt(float(zr.get("grow", 1.5)))
			_:
				if result != "":
					spawn_zone(f, {"kind": result, "skip_zone_reaction": true}, z["pos"])
		sim.emit_event({"type": "zone_reaction", "result": result, "pos": z["pos"], "a": z["element"], "b": incoming_el})
		return result in ["steam", "burning_puddle", "mud", "fizzing_puddle", "storm", "rubble_prop"]
	return false


func _spawn_prop(f: Fighter, e: Dictionary, p: Vector3) -> void:
	var kind := str(e.get("prop", "spring_pad"))
	var max_active := int(e.get("max_active", 0))
	if max_active > 0 and f:
		var mine := entities.filter(func(x): return x["kind"] == "prop" and x["prop"] == kind and int(x["owner"]) == f.index)
		while mine.size() >= max_active:
			var old: Dictionary = mine.pop_front()
			_remove_prop(old)
	var ent := {"id": _next_id, "kind": "prop", "prop": kind, "owner": f.index if f else -1, "team": f.team if f else -1,
		"pos": Vector3(p.x, 0.0, p.z), "radius": float(e.get("radius", 1.0)), "life": float(e.get("duration", 10.0)),
		"age": 0.0, "hp": float(e.get("hp", 0.0)), "e": e, "element": "", "vfx": kind, "body": null, "cool": {}}
	_next_id += 1
	if kind in ["boulder", "rubble"]:
		var sb := StaticBody3D.new()
		sb.collision_layer = Rig.LAYER_PROPS
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sp := CylinderShape3D.new()
		sp.radius = float(e.get("radius", 0.8)) * 0.5 if kind == "boulder" else float(e.get("radius", 0.75))
		sp.height = 0.8 if kind == "boulder" else 0.5
		cs.shape = sp
		sb.add_child(cs)
		sim.add_child(sb)
		sb.global_position = Vector3(p.x, sp.height * 0.5, p.z)
		ent["body"] = sb
		ent["radius"] = sp.radius
	entities.append(ent)
	sim.emit_event({"type": "prop_spawn", "prop": kind, "pos": ent["pos"], "id": ent["id"], "fighter": f.index if f else -1})


func _remove_prop(ent: Dictionary) -> void:
	if ent.get("body") and is_instance_valid(ent["body"]):
		(ent["body"] as Node).queue_free()
	entities.erase(ent)


func _spawn_delayed(f: Fighter, e: Dictionary, p: Vector3) -> void:
	var ent := {"id": _next_id, "kind": "delayed", "owner": f.index if f else -1, "team": f.team if f else -1,
		"pos": Vector3(p.x, 0.0, p.z), "radius": float(e.get("radius", 1.5)), "life": float(e.get("delay", 0.6)),
		"age": 0.0, "e": e, "element": str(e.get("element", "")), "vfx": "marker"}
	_next_id += 1
	entities.append(ent)


func _destroy_projectiles(f: Fighter, p: Vector3, r: float, cone_deg: float) -> void:
	for ent in entities.duplicate():
		if ent["kind"] != "projectile" or (f and int(ent["team"]) == f.team):
			continue
		var to: Vector3 = ent["pos"] - p
		to.y = 0.0
		if to.length() > r:
			continue
		if cone_deg < 359.0 and f and absf(f.forward().signed_angle_to(to, Vector3.UP)) > deg_to_rad(cone_deg) * 0.5:
			continue
		entities.erase(ent)
		sim.emit_event({"type": "projectile_destroyed", "pos": ent["pos"], "fighter": f.index if f else -1})


func _chain_arc(f: Fighter, e: Dictionary, p: Vector3) -> void:
	var src: Fighter = f.target if f.target and not f.target.is_out() else null
	var origin := src.pos() if src else p
	var best: Fighter = null
	var bd := float(e.get("range", 2.0))
	for o: Fighter in enemies_in(f, origin, bd):
		if o == src:
			continue
		var d := o.pos().distance_to(origin)
		if d <= bd:
			bd = d
			best = o
	if best:
		effect_hit(f, best, e, origin)
		sim.emit_event({"type": "arc", "from": origin, "to": best.pos(), "fighter": f.index, "element": str(e.get("element", ""))})


## Radial push on hittable mode objects (positive = away from p, negative = toward p).
func push_objects(f: Fighter, p: Vector3, r: float, strength: float, element: String) -> void:
	if strength == 0.0:
		return
	for h in sim.hittables:
		var hb: RigidBody3D = h.get("body")
		if hb == null or not is_instance_valid(hb):
			continue
		var d := hb.global_position - p
		d.y = 0.0
		if d.length() > r:
			continue
		var dir := d.normalized() if d.length_squared() > 1e-6 else (f.forward() if f else Vector3.FORWARD)
		if strength < 0.0:
			dir = -dir
		var on_hit: Callable = h["on_hit"]
		on_hit.call(f, dir, absf(strength), 0.0, element, hb.global_position)


func spawn_hazard_zone(p: Vector3, e: Dictionary) -> void:
	var ent := {"id": _next_id, "kind": "zone", "zone_kind": str(e.get("hazard", "")), "owner": -1, "team": -1,
		"pos": Vector3(p.x, 0.0, p.z), "radius": float(e.get("radius", 1.0)), "life": 1e9, "tick": float(e.get("tick", 0.5)),
		"_t": 0.0, "age": 0.0, "e": e, "element": str(e.get("element", "")), "vfx": str(e.get("vfx", "zone")),
		"friendly": true, "follow": false, "inside": {}}
	_next_id += 1
	entities.append(ent)


func fighter_in_zone(f: Fighter, zone_kind: String) -> bool:
	var p := f.pos()
	for z in entities:
		if z["kind"] != "zone":
			continue
		if zone_kind != "" and str(z.get("zone_kind", "")) != zone_kind and str(z.get("element", "")) != zone_kind:
			continue
		if Vector2(p.x - z["pos"].x, p.z - z["pos"].z).length() <= float(z["radius"]):
			return true
	return false


# =====================================================================================
# Update
# =====================================================================================

func update(dt: float) -> void:
	for ent in entities.duplicate():
		ent["age"] = float(ent["age"]) + dt
		match str(ent["kind"]):
			"projectile":
				_update_projectile(ent, dt)
			"zone":
				_update_zone(ent, dt)
			"prop":
				_update_prop(ent, dt)
		if float(ent["age"]) >= float(ent["life"]) and entities.has(ent):
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
		var want: Vector3 = (f.target.pos() + Vector3.UP * 0.3 - Vector3(ent["pos"]))
		var cur_h := Vector3(vel.x, 0, vel.z)
		var want_h := Vector3(want.x, 0, want.z)
		if cur_h.length() > 0.01 and want_h.length() > 0.01:
			var ang := cur_h.signed_angle_to(want_h, Vector3.UP)
			var step := clampf(ang, -hom * dt, hom * dt)
			vel = vel.rotated(Vector3.UP, step)
	var boom := float(ent["boomerang"])
	if boom > 0.0 and float(ent["age"]) > boom and f:
		var back: Vector3 = (f.pos() + Vector3.UP * 0.4 - Vector3(ent["pos"]))
		vel = vel.lerp(back.normalized() * vel.length(), clampf(6.0 * dt, 0.0, 1.0))
		if back.length() < 0.6:
			ent["life"] = 0.0
	var p: Vector3 = ent["pos"] + vel * dt
	# gale vortices push projectiles off course
	for z in entities:
		if z["kind"] == "zone" and float(z["e"].get("deflect_projectiles", 0.0)) > 0.0:
			if Vector2(p.x - z["pos"].x, p.z - z["pos"].z).length() < float(z["radius"]):
				vel = vel.rotated(Vector3.UP, deg_to_rad(float(z["e"]["deflect_projectiles"])) * dt * 2.0)
	if p.y < float(ent["radius"]) * 0.5:
		if int(ent["bounces"]) > 0:
			ent["bounces"] = int(ent["bounces"]) - 1
			vel.y = absf(vel.y) * 0.6
			p.y = float(ent["radius"]) * 0.5
		else:
			ent["life"] = 0.0
	var clamped: Vector3 = sim.clamp_to_arena(p, float(ent["radius"]))
	if sim.arena.wall_height > 0.0 and clamped.distance_squared_to(Vector3(p.x, clamped.y, p.z)) > 1e-4:
		if int(ent["bounces"]) > 0:
			ent["bounces"] = int(ent["bounces"]) - 1
			var n := (clamped - p)
			n.y = 0.0
			vel = vel.bounce(n.normalized())
			p = clamped
		else:
			ent["life"] = 0.0
	# blocking props
	for pr in entities:
		if pr["kind"] == "prop" and pr["body"] != null:
			if Vector2(p.x - pr["pos"].x, p.z - pr["pos"].z).length() < float(pr["radius"]) + float(ent["radius"]) and p.y < 1.0:
				ent["life"] = 0.0
				_damage_prop(pr, float(ent["e"].get("damage", 4.0)))
	ent["vel"] = vel
	ent["pos"] = p
	if float(ent["life"]) <= 0.0:
		return
	for h in sim.hittables:
		var hb: RigidBody3D = h.get("body")
		if hb and is_instance_valid(hb) and hb.global_position.distance_to(p) < float(h["radius"]) + float(ent["radius"]):
			var on_hit: Callable = h["on_hit"]
			on_hit.call(f, vel.normalized(), float(ent["e"].get("knockback", 2.0)), float(ent["e"].get("launch", 0.0)), str(ent["element"]), p)
			if not bool(ent["pierce"]):
				ent["life"] = 0.0
				return
	for o: Fighter in sim.fighters:
		if f and (o == f or not sim.can_hit(f, o)):
			continue
		if o.is_out() or o.is_evading() or ent["hit"].has(o.index):
			continue
		if o.pos().distance_squared_to(p) > 6.0:
			continue
		var c: Dictionary = sim.combat.find_contact(p, float(ent["radius"]), o)
		if c.is_empty():
			continue
		if o.has_flag("reflect") and bool(ent["reflectable"]):
			ent["owner"] = o.index
			ent["team"] = o.team
			ent["vel"] = -vel
			ent["hit"] = {}
			ent["age"] = 0.0
			sim.emit_event({"type": "reflect", "fighter": o.index, "pos": p})
			return
		ent["hit"][o.index] = true
		effect_hit(f, o, ent["e"], p - vel.normalized() * 0.5)
		if not bool(ent["pierce"]):
			ent["life"] = 0.0
			break


func _update_zone(ent: Dictionary, dt: float) -> void:
	var f := _owner(ent)
	if ent["follow"] and f and not f.is_out():
		var fp := f.ground_pos()
		ent["pos"] = Vector3(fp.x, 0.0, fp.z)
	var e: Dictionary = ent["e"]
	var r := float(ent["radius"])
	# entry effects (flinch on entry, spring launches) are checked every tick
	for o: Fighter in sim.fighters:
		if o.is_out():
			continue
		var inside := Vector2(o.pos().x - ent["pos"].x, o.pos().z - ent["pos"].z).length() <= r
		var was: bool = ent["inside"].get(o.index, false)
		ent["inside"][o.index] = inside
		if inside and not was:
			if float(e.get("flinch_on_entry", 0.0)) > 0.0 and _zone_affects(ent, f, o):
				o.flinch(float(e["flinch_on_entry"]))
			if e.has("launch"):
				o.rig.apply_body_impulse(Vector3.UP * float(e["launch"]) * o.rig.total_mass)
		if inside and float(e.get("push_out", 0.0)) > 0.0 and _zone_affects(ent, f, o):
			var away := o.pos() - Vector3(ent["pos"])
			away.y = 0.0
			o.rig.apply_body_impulse(away.normalized() * float(e["push_out"]) * dt * o.rig.total_mass * 3.0)
	ent["_t"] = float(ent["_t"]) + dt
	if float(ent["_t"]) < float(ent["tick"]):
		return
	ent["_t"] = 0.0
	if bool(e.get("cosmetic", false)):
		return
	for o: Fighter in sim.fighters:
		if o.is_out() or not ent["inside"].get(o.index, false):
			continue
		if not _zone_affects(ent, f, o):
			continue
		var ally := f != null and o != f and not sim.are_enemies(f, o)
		var dmg_mult: float = float(sim.rules.get("ally_reaction_damage_mult", Elements.rules.get("ally_reaction_damage_mult", 0.25))) if ally else 1.0
		if float(e.get("tick_damage", 0.0)) > 0.0:
			sim.combat.apply_simple_damage(f, o, float(e["tick_damage"]) * float(dmg_mult), "zone", {"element": e.get("element", "")})
		var el := str(e.get("element", ""))
		if el != "" and float(e.get("buildup", 0.0)) > 0.0 and not (o.creature.element == el):
			o.statuses.add_buildup(el, float(e["buildup"]), f, 0.5 if ally else 1.0)
		for xel in e.get("extra_buildup", {}):
			o.statuses.add_buildup(str(xel), float(e["extra_buildup"][xel]), f)
		if e.has("status"):
			var st: Dictionary = e["status"].duplicate()
			st["source"] = f
			o.statuses.add(st)
		if float(e.get("flinch_on_tick", 0.0)) > 0.0:
			o.flinch(float(e["flinch_on_tick"]))
		if float(e.get("heal", 0.0)) > 0.0 and f and not sim.are_enemies(f, o):
			o.heal(float(e["heal"]))
	if e.has("random_bolt"):
		var rb: Dictionary = e["random_bolt"]
		var off := Vector3(sim.rng.randf_range(-r, r), 0, sim.rng.randf_range(-r, r)) * 0.7
		_spawn_delayed(f, {"radius": float(rb.get("radius", 0.8)), "delay": 0.25, "damage": rb.get("damage", 6), "poise": rb.get("poise", 12), "element": "static", "buildup": float(rb.get("buildup", {}).get("static", 25))}, Vector3(ent["pos"]) + off)


## Owner-element and ally rules for zones (ELEMENTS.md §5/§7).
func _zone_affects(ent: Dictionary, f: Fighter, o: Fighter) -> bool:
	if f == null:
		return true
	if o == f:
		return bool(ent["e"].get("affects_owner", true)) and not bool(ent["e"].get("owner_immune", false))
	if not sim.are_enemies(f, o):
		return bool(ent["friendly"]) or bool(ent["e"].get("affects_allies", true))
	return true


func _update_prop(ent: Dictionary, _dt: float) -> void:
	var e: Dictionary = ent["e"]
	if str(ent["prop"]) == "spring_pad":
		var cool: Dictionary = ent["cool"]
		for o: Fighter in sim.fighters:
			if o.is_out() or o.is_down():
				continue
			var d := Vector2(o.pos().x - ent["pos"].x, o.pos().z - ent["pos"].z).length()
			if d > float(ent["radius"]):
				continue
			if float(cool.get(o.index, -1.0)) > sim.time:
				continue
			cool[o.index] = sim.time + 1.0
			var fwd := o.forward()
			var up := float(e.get("launch_up", 2.5))
			var vy := sqrt(2.0 * sim.gravity * up)
			var air := 2.0 * vy / sim.gravity
			o.rig.freeze_motion()
			o.begin_airborne([], air)
			o.rig.apply_body_impulse((fwd * float(e.get("launch_forward", 3.0)) / air + Vector3.UP * vy) * o.rig.total_mass)
			var owner := _owner(ent)
			if owner and sim.are_enemies(owner, o):
				o.pending_land_stun = float(e.get("enemy_stun", 0.4))
			elif owner == o:
				o.set_flag("pad_launched", air + 0.6)
			sim.emit_event({"type": "spring", "fighter": o.index, "pos": ent["pos"]})


func _damage_prop(pr: Dictionary, dmg: float) -> void:
	if float(pr["hp"]) <= 0.0:
		return
	pr["hp"] = float(pr["hp"]) - dmg
	if float(pr["hp"]) <= 0.0:
		_remove_prop(pr)
		sim.emit_event({"type": "prop_destroyed", "pos": pr["pos"], "prop": pr["prop"]})


## Melee weapons can break props (Combat calls this with the weapon sphere).
func hit_props(wp: Vector3, wr: float, dmg: float) -> void:
	for pr in entities.duplicate():
		if pr["kind"] == "prop" and pr["body"] != null:
			if Vector2(wp.x - pr["pos"].x, wp.z - pr["pos"].z).length() < float(pr["radius"]) + wr and wp.y < 1.2:
				_damage_prop(pr, dmg)


func _expire(ent: Dictionary) -> void:
	if ent["kind"] == "prop":
		_remove_prop(ent)
		return
	entities.erase(ent)
	var f := _owner(ent)
	var e: Dictionary = ent["e"]
	if ent["kind"] == "delayed":
		var area_e: Dictionary = e.duplicate()
		area_e["radius"] = float(ent["radius"])
		if f:
			area(f, area_e, ent["pos"])
		else:
			for o: Fighter in enemies_in(null, ent["pos"], float(ent["radius"])):
				effect_hit(null, o, area_e, ent["pos"])
		sim.emit_event({"type": "effect", "fighter": int(ent["owner"]), "effect": "strike", "pos": ent["pos"], "element": ent["element"], "vfx": "bolt", "radius": float(ent["radius"]), "shape": "circle", "yaw": 0.0, "move": ""})
		return
	if e.has("on_expire"):
		var ex: Dictionary = e["on_expire"]
		var et := str(ex.get("type", "area"))
		if et == "area" and f:
			area(f, ex, ent["pos"])
		elif et == "zone":
			spawn_zone(f, ex, Vector3(ent["pos"].x, 0, ent["pos"].z))
		sim.emit_event({"type": "effect", "fighter": int(ent["owner"]), "effect": et, "pos": ent["pos"], "element": ex.get("element", e.get("element", "")), "vfx": ex.get("vfx", "burst"), "radius": float(ex.get("radius", 1.0)), "shape": "circle", "yaw": 0.0, "move": ""})


# =====================================================================================
# Reactions (ELEMENTS.md §3)
# =====================================================================================

func trigger_reaction(r: Dictionary, victim: Fighter, source, el_a: String, el_b: String) -> void:
	var p := victim.ground_pos()
	var src: Fighter = source if (source != null and is_instance_valid(source) and source is Fighter) else null
	var id := str(r.get("id", ""))
	var ally_hit := src != null and not sim.are_enemies(src, victim) and src != victim
	var dmg_mult := float(sim.rules.get("ally_reaction_damage_mult", Elements.rules.get("ally_reaction_damage_mult", 0.25))) if ally_hit else 1.0
	match id:
		"steam_burst":
			victim.statuses.remove_element("scorch")
			victim.statuses.remove_element("brine")
			var away := victim.pos() - (src.pos() if src else victim.pos() - victim.forward())
			away.y = 0.0
			var e := {"damage": float(r.get("damage", 4)) * dmg_mult, "poise": r.get("poise", 15), "knockback": r.get("push", 2.0) * 2.0, "stun": 0.2}
			effect_hit(src, victim, e, victim.pos() - away.normalized())
			spawn_zone(src, {"kind": "steam", "skip_zone_reaction": true}, p)
		"flare_up":
			var e2 := {"damage": float(r.get("damage", 10)) * dmg_mult, "launch": r.get("launch", 4.8), "poise": 20, "stun": 0.3}
			effect_hit(src, victim, e2, p - Vector3.UP)
			var others := enemies_in(src, p, float(r.get("radius", 2.0)), true)
			if bool(r.get("hits_attacker", true)) and src and src.pos().distance_to(p) <= float(r.get("radius", 2.0)) + 0.3:
				others.append(src)
			for o: Fighter in others:
				if o != victim:
					var e3 := {"damage": float(r.get("splash_damage", 10)) * (0.25 if (src and not sim.are_enemies(src, o)) else 1.0), "launch": 3.0, "stun": 0.2}
					if o == src:
						sim.combat.apply_simple_damage(null, o, float(e3["damage"]) * 0.5, "flare_up")
					else:
						effect_hit(src, o, e3, p)
				o.statuses.add_buildup("scorch", float(r.get("splash_buildup", {}).get("scorch", 60)), null)
		"backdraft":
			victim.statuses.refresh_element("scorch")
			for o: Fighter in enemies_in(null, p, float(r.get("spread_radius", 2.5)), true):
				if o != victim:
					o.statuses.add_buildup("scorch", float(r.get("spread_buildup", {}).get("scorch", 60)), src)
			victim.flags["push_mult_once"] = float(r.get("push_mult", 2.0))
		"short_out":
			sim.combat.apply_simple_damage(src, victim, float(r.get("damage", 8)) * dmg_mult, "short_out", {"element": "static"})
			victim.stun(0.2 if ally_hit else float(r.get("stun", 0.9)), true)
			for z in entities:
				if z["kind"] == "zone" and str(z.get("zone_kind", "")) in ["brine_puddle", "live_puddle"] and Vector2(p.x - z["pos"].x, p.z - z["pos"].z).length() <= float(z["radius"]):
					for o: Fighter in sim.fighters:
						if o != victim and not o.is_out() and z["inside"].get(o.index, false):
							sim.combat.apply_simple_damage(src, o, float(r.get("puddle_damage", 6)), "short_out")
							o.stun(float(r.get("puddle_stun", 0.5)), true)
		"mudbound":
			spawn_zone(src, {"kind": "mud", "skip_zone_reaction": true}, p)
		"dilute":
			var rem := victim.statuses.remaining_dot("sludge")
			victim.statuses.remove_element("sludge")
			var burst := minf(float(r.get("burst_max", 5)), rem * float(r.get("burst_fraction", 0.5)))
			if burst > 0.0:
				sim.combat.apply_simple_damage(src, victim, burst * dmg_mult, "dilute")
		"catalyze":
			var st := victim.statuses.element_status("sludge")
			if not st.is_empty():
				var rem2 := float(st.get("dps", 1.5)) * float(st.get("left", 0.0))
				st["dps_mult"] = maxf(1.0, rem2 / maxf(0.1, float(r.get("accelerate_over", 1.0))) / maxf(0.1, float(st.get("dps", 1.5))))
				st["left"] = minf(float(st["left"]), float(r.get("accelerate_over", 1.0)))
			for o: Fighter in enemies_in(null, p, float(r.get("splash_radius", 1.5)), true):
				if o != victim:
					o.statuses.add_buildup("static", float(r.get("splash_buildup", {}).get("static", 20)), src)
		"stormfront":
			var ds: Dictionary = r.get("delayed_strike", {})
			_spawn_delayed(src if src else victim, {"radius": ds.get("radius", 1.5), "delay": ds.get("delay", 0.6), "damage": ds.get("damage", 12), "poise": ds.get("poise", 25), "element": "static", "buildup": float(ds.get("buildup", {}).get("static", 50)), "affects_allies": false}, p)
		"crust":
			var st2: Dictionary = r.get("status", {}).duplicate()
			victim.statuses.add(st2)
		"spray":
			for o: Fighter in enemies_in(null, p, float(r.get("splash_radius", 2.0)), true):
				if o != victim:
					o.statuses.add_buildup("sludge", float(r.get("splash_buildup", {}).get("sludge", 40)), src)
			spawn_zone(src, {"kind": "sludge_puddle", "radius": 1.5, "duration": 3.0, "skip_zone_reaction": true}, p)
		"sandblast":
			sim.combat.apply_simple_damage(src, victim, float(r.get("damage", 6)) * dmg_mult, "sandblast")
			victim.statuses.add(r.get("status", {}).duplicate())
			var cb: Dictionary = r.get("cone_behind", {})
			var back := victim.pos() - (src.pos() if src else victim.pos() - victim.forward())
			back.y = 0.0
			back = back.normalized()
			for o: Fighter in enemies_in(null, p + back * 1.0, float(cb.get("radius", 2.0)), true):
				if o != victim:
					o.statuses.add_buildup("grit", float(cb.get("buildup", {}).get("grit", 30)), src)
	sim.emit_event({"type": "reaction", "fighter": victim.index, "reaction": id, "name": str(r.get("name", id)), "a": el_a, "b": el_b, "pos": p, "by": src.index if src else -1})
	if src:
		src.hooks.fire("reaction", {"other": victim, "element": el_a, "status": id})
