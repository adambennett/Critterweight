class_name ArenaBuilder
## Builds the PHYSICAL side of an ArenaDef under a parent node (normally the MatchSim): floor
## (with real holes for pits), walls, one physics body per solid prop, and the ArenaHazards
## runtime that drives hazards/props every tick. Visuals are built separately by ArenaView so
## headless servers stay lean.
##
## Returned `arena_nodes` contract (MatchSim stores it):
##   floor: StaticBody3D (first floor body) · floors: [StaticBody3D] · walls: [StaticBody3D]
##   props: [PhysicsBody3D] one per prop that has a body, in ArenaDef.all_props() order. These are
##          NEVER freed during a match (destroyed props are disabled and parked far below the
##          floor), so views may index them every frame (MatchScene does).
##   prop_index: [int] parallel to `props`: index into ArenaDef.all_props()
##   dynamic_props: [RigidBody3D] pushables and heavy bags
##   hazards: ArenaHazards runtime (null when the parent is not a MatchSim)
## Body flavours: StaticBody3D = solid AND a wall-splat surface; a frozen RigidBody3D is solid
## but never splats (tire stacks, bumpers, ramps, mooring blocks) — Fighter's splat check skips
## RigidBody3D props by design.

## Legacy hazard zones (format-1 arenas): permanent zones registered with the effects system.
static var HAZARD_TYPES := {
	"fire_grate": {"element": "", "tick_damage": 4.0, "tick": 0.5, "vfx": "fire"},
	"puddle": {"element": "", "tick_damage": 0.0, "tick": 0.5, "vfx": "puddle", "status": {"id": "slick", "speed": 0.8, "duration": 0.6}},
	"spring_pad": {"launch": 9.0, "vfx": "spring"},
	"shock_plate": {"element": "", "tick_damage": 3.0, "tick": 0.6, "vfx": "shock", "status": {"id": "zapped", "duration": 0.6, "speed": 0.7}},
}
const FLOOR_THICKNESS := 1.0
const PARK_Y := -100.0


## Catalog id for a prop type (old format-1 names are mapped by ArenaDef.LEGACY_PROPS).
static func catalog_type(t: String) -> String:
	return str(ArenaDef.LEGACY_PROPS.get(t, t))


static func build(parent: Node3D, a: ArenaDef) -> Dictionary:
	var out := {"floor": null, "floors": [], "walls": [], "props": [], "prop_index": [], "dynamic_props": [], "hazards": null}
	var rules: Dictionary = parent.get("rules") if parent.get("rules") is Dictionary else {}
	_build_floor(parent, a, out)
	_build_walls(parent, a, out, rules)
	var all := a.all_props()
	var bodies: Array = []
	for i in all.size():
		var p: Dictionary = all[i]
		var def := ArenaCatalog.prop(catalog_type(str(p["type"])))
		var body: Node3D = null
		if not def.is_empty() and str(def["body"]) != "none" and not bool(def["is_marker"]):
			body = build_prop_body(parent, p, def, i)
			if body:
				out["props"].append(body)
				out["prop_index"].append(i)
				if body is RigidBody3D and not (body as RigidBody3D).freeze or str(def["body"]) in ["dynamic", "bag"]:
					out["dynamic_props"].append(body)
		bodies.append(body)
	if parent is MatchSim:
		out["hazards"] = ArenaHazards.new(parent, a, all, bodies)
	return out


# =====================================================================================
# Floor
# =====================================================================================

static func _build_floor(parent: Node3D, a: ArenaDef, out: Dictionary) -> void:
	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	var holes: Array = []
	for p in a.all_props():
		var def := ArenaCatalog.prop(catalog_type(str(p["type"])))
		if not def.is_empty() and str(def["behaviour"]) == "pit":
			holes.append(ArenaCatalog.footprint_aabb(p, def))
	var rects: Array = []
	if a.shape == "circle":
		# legacy round arenas: one cylinder (pits are not supported there)
		var body := _floor_body(parent, mat, "Floor")
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = a.radius + (0.2 if a.ringout else 3.0)
		cyl.height = FLOOR_THICKNESS
		cs.shape = cyl
		cs.position = Vector3(0, -FLOOR_THICKNESS * 0.5, 0)
		body.add_child(cs)
		out["floors"].append(body)
		out["floor"] = body
		return
	if a.has_open_edges():
		for piece in a.floor_pieces():
			var r := Rect2((piece as PackedVector2Array)[0], Vector2.ZERO)
			for v in (piece as PackedVector2Array):
				r = r.expand(v)
			rects.append(r)
	else:
		rects.append(a.extent().grow(3.0))
	var body2 := _floor_body(parent, mat, "Floor")
	out["floor"] = body2
	out["floors"].append(body2)
	for r in rects:
		for box in subtract_rects(r, holes):
			var b: Rect2 = box
			if b.size.x < 0.01 or b.size.y < 0.01:
				continue
			var cs2 := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(b.size.x, FLOOR_THICKNESS, b.size.y)
			cs2.shape = bs
			cs2.position = Vector3(b.get_center().x, -FLOOR_THICKNESS * 0.5, b.get_center().y)
			body2.add_child(cs2)


static func _floor_body(parent: Node3D, mat: PhysicsMaterial, n: String) -> StaticBody3D:
	var fb := StaticBody3D.new()
	fb.name = n
	fb.collision_layer = Rig.LAYER_WORLD
	fb.collision_mask = 0
	fb.physics_material_override = mat
	parent.add_child(fb)
	return fb


## Splits rect `r` into axis-aligned rects that avoid every hole (grid decomposition, row-merged).
static func subtract_rects(r: Rect2, holes: Array) -> Array:
	var xs: Array = [r.position.x, r.end.x]
	var zs: Array = [r.position.y, r.end.y]
	var inside: Array = []
	for h in holes:
		var hr: Rect2 = h
		if not hr.intersects(r):
			continue
		inside.append(hr)
		for x in [hr.position.x, hr.end.x]:
			if x > r.position.x and x < r.end.x and not xs.has(x):
				xs.append(x)
		for z in [hr.position.y, hr.end.y]:
			if z > r.position.y and z < r.end.y and not zs.has(z):
				zs.append(z)
	if inside.is_empty():
		return [r]
	xs.sort()
	zs.sort()
	var out: Array = []
	for j in zs.size() - 1:
		var run_start := -1
		for i in xs.size():
			var keep := false
			if i < xs.size() - 1:
				var c := Vector2((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)
				keep = true
				for hr2 in inside:
					if (hr2 as Rect2).has_point(c):
						keep = false
						break
			if keep and run_start < 0:
				run_start = i
			elif not keep and run_start >= 0:
				out.append(Rect2(xs[run_start], zs[j], xs[i] - xs[run_start], zs[j + 1] - zs[j]))
				run_start = -1
	return out


# =====================================================================================
# Walls
# =====================================================================================

static func _build_walls(parent: Node3D, a: ArenaDef, out: Dictionary, rules: Dictionary) -> void:
	var wall_mat := PhysicsMaterial.new()
	wall_mat.friction = 0.3
	wall_mat.bounce = float(a.quirk("wall_bounce", 0.25))
	var ringouts := bool(rules.get("ringouts", true))
	var i := 0
	for e in a.boundary_edges():
		var walled := bool(e["wall"])
		var h := a.wall_height + 1.0
		if not walled:
			if ringouts:
				continue
			h = 1.2   # ring-outs disabled by the rules: invisible guard rail along open edges
		var ea: Vector2 = e["a"]
		var eb: Vector2 = e["b"]
		var n: Vector2 = e["n"]
		var t := (eb - ea).normalized()
		var length := ea.distance_to(eb) + 0.3
		var wb := StaticBody3D.new()
		wb.name = "Wall%d" % i
		wb.collision_layer = Rig.LAYER_WORLD
		wb.collision_mask = 0
		wb.physics_material_override = wall_mat
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(length, h, 0.3)
		cs.shape = bs
		wb.add_child(cs)
		parent.add_child(wb)
		var mid := (ea + eb) * 0.5 + n * 0.15
		wb.global_transform = Transform3D(Basis(Vector3.UP, atan2(-t.y, t.x)), Vector3(mid.x, h * 0.5, mid.y))
		wb.set_meta("wall", walled)
		out["walls"].append(wb)
		i += 1


# =====================================================================================
# Props
# =====================================================================================

## Origin transform of a prop body: centre of its collision volume, rotated by the prop's yaw.
static func prop_body_transform(p: Dictionary, def: Dictionary) -> Transform3D:
	var pos: Vector3 = p["pos"]
	var h := float(def["height"]) * float(p.get("scale", 1.0))
	if str(def["body"]) == "bag":
		var hang := float(def["params"].get("hang", 2.3))
		return Transform3D(Basis.IDENTITY, Vector3(pos.x, pos.y + hang - 0.15 - h * 0.5, pos.z))
	return Transform3D(Basis(Vector3.UP, float(p.get("yaw", 0.0))), Vector3(pos.x, pos.y + h * 0.5, pos.z))


static func build_prop_body(parent: Node3D, p: Dictionary, def: Dictionary, index: int) -> Node3D:
	var kind := str(def["body"])
	var size := ArenaCatalog.footprint_size(p, def)
	var h := float(def["height"]) * float(p.get("scale", 1.0))
	var shape_kind := ArenaCatalog.footprint_shape(def)
	var pm := PhysicsMaterial.new()
	pm.friction = float(def["push"].get("friction", 0.6))
	pm.bounce = 0.6 if not def["bounce"].is_empty() else 0.1
	var body: PhysicsBody3D
	match kind:
		"static":
			var sb := StaticBody3D.new()
			sb.collision_layer = Rig.LAYER_PROPS
			sb.collision_mask = 0
			sb.physics_material_override = pm
			body = sb
		"static_nosplat", "ramp":
			var fr := RigidBody3D.new()
			fr.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			fr.freeze = true
			fr.collision_layer = Rig.LAYER_PROPS
			fr.collision_mask = 0
			fr.physics_material_override = pm
			body = fr
		"dynamic":
			var rb := RigidBody3D.new()
			rb.mass = float(def["push"].get("mass", 40.0)) * pow(float(p.get("scale", 1.0)), 3.0)
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rb.freeze = true            # thawed by ArenaHazards when shoved hard enough
			rb.collision_layer = Rig.LAYER_PROPS
			rb.collision_mask = Rig.LAYER_WORLD | Rig.LAYER_FIGHTERS | Rig.LAYER_PROPS
			rb.physics_material_override = pm
			rb.angular_damp = 1.5
			rb.linear_damp = 0.4
			body = rb
		"bag":
			var bag := RigidBody3D.new()
			bag.mass = float(def["params"].get("mass", 35.0))
			bag.collision_layer = Rig.LAYER_PROPS
			bag.collision_mask = Rig.LAYER_WORLD | Rig.LAYER_FIGHTERS | Rig.LAYER_PROPS
			bag.linear_damp = 0.3
			bag.angular_damp = 1.2
			bag.can_sleep = false
			body = bag
		_:
			return null
	body.name = "Prop_%s_%d" % [str(def["id"]), index]
	var cs := CollisionShape3D.new()
	if kind == "ramp":
		var cp := ConvexPolygonShape3D.new()
		var hw := size.x * 0.5
		var hd := size.y * 0.5
		var hh := h * 0.5
		cp.points = PackedVector3Array([Vector3(-hw, -hh, -hd), Vector3(hw, -hh, -hd), Vector3(-hw, -hh, hd), Vector3(hw, -hh, hd),
			Vector3(-hw, hh, hd), Vector3(hw, hh, hd)])
		cs.shape = cp
	elif kind == "bag":
		var cap := CapsuleShape3D.new()
		cap.radius = size.x * 0.5
		cap.height = h
		cs.shape = cap
	elif shape_kind == "box":
		var bx := BoxShape3D.new()
		bx.size = Vector3(size.x, maxf(h, 0.05), size.y)
		cs.shape = bx
	else:
		var cy := CylinderShape3D.new()
		cy.radius = size.x * 0.5
		cy.height = maxf(h, 0.05)
		cs.shape = cy
	body.add_child(cs)
	parent.add_child(body)
	body.global_transform = prop_body_transform(p, def)
	body.set_meta("prop_type", str(def["id"]))
	body.set_meta("prop_id", str(p.get("id", "")))
	body.set_meta("prop_index", index)
	if kind == "bag":
		var anchor := StaticBody3D.new()
		anchor.name = "BagAnchor%d" % index
		anchor.collision_layer = 0
		anchor.collision_mask = 0
		parent.add_child(anchor)
		var pos: Vector3 = p["pos"]
		var hang := float(def["params"].get("hang", 2.3))
		anchor.global_position = Vector3(pos.x, pos.y + hang, pos.z)
		var j := PinJoint3D.new()
		j.name = "BagPin%d" % index
		parent.add_child(j)
		j.global_position = anchor.global_position
		j.node_a = j.get_path_to(anchor)
		j.node_b = j.get_path_to(body)
		body.set_meta("anchor", anchor)
	return body


## Disables a prop body and parks it far below the floor (never freed mid-match, see contract).
static func park_body(body: Node3D, slot: int) -> void:
	if body == null or not is_instance_valid(body):
		return
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.freeze = true
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	(body as CollisionObject3D).collision_layer = 0
	(body as CollisionObject3D).collision_mask = 0
	body.global_position = Vector3(float(slot) * 3.0, PARK_Y, 0.0)


static func unpark_body(body: Node3D, xf: Transform3D, def: Dictionary) -> void:
	if body == null or not is_instance_valid(body):
		return
	var co := body as CollisionObject3D
	co.collision_layer = Rig.LAYER_PROPS
	if str(def["body"]) in ["dynamic", "bag"]:
		co.collision_mask = Rig.LAYER_WORLD | Rig.LAYER_FIGHTERS | Rig.LAYER_PROPS
	body.global_transform = xf
	if body is RigidBody3D:
		(body as RigidBody3D).linear_velocity = Vector3.ZERO
		(body as RigidBody3D).angular_velocity = Vector3.ZERO


# =====================================================================================
# After fighters exist (MatchSim.setup calls this)
# =====================================================================================

## Legacy hazard zones + the arena runtime's post-spawn setup (team spawn clusters).
static func spawn_hazards(sim, a: ArenaDef) -> void:
	for h in a.hazards:
		var def: Dictionary = HAZARD_TYPES.get(h["type"], {})
		if def.is_empty():
			continue
		var e: Dictionary = def.duplicate(true)
		for k in h["params"]:
			e[k] = h["params"][k]
		e["radius"] = h["radius"]
		e["duration"] = 1e9
		e["friendly"] = true
		e["hazard"] = h["type"]
		sim.effects.spawn_hazard_zone(h["pos"], e)
	var rt = sim.arena_nodes.get("hazards") if typeof(sim.arena_nodes) == TYPE_DICTIONARY else null
	if rt is ArenaHazards:
		(rt as ArenaHazards).on_fighters_ready()
