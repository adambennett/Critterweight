class_name ArenaBuilder
## Builds the PHYSICAL side of an ArenaDef (floor, fence/walls, props, hazard zones) under a
## parent node. Visuals are built separately by ArenaView so headless servers stay lean.

## Prop catalog (overridable/extendable by content packages via props.json).
static var PROP_TYPES := {
	"crate": {"shape": "box", "size": [0.9, 0.9, 0.9], "dynamic": true, "mass": 45.0, "cost": 2},
	"barrel": {"shape": "cylinder", "radius": 0.36, "height": 0.95, "dynamic": true, "mass": 30.0, "cost": 2},
	"pillar": {"shape": "cylinder", "radius": 0.4, "height": 2.6, "dynamic": false, "cost": 3},
	"low_wall": {"shape": "box", "size": [2.0, 0.9, 0.35], "dynamic": false, "cost": 3},
	"bumper": {"shape": "cylinder", "radius": 0.55, "height": 0.9, "dynamic": false, "bounce": 0.95, "cost": 4},
	"tire_stack": {"shape": "cylinder", "radius": 0.5, "height": 0.75, "dynamic": true, "mass": 60.0, "bounce": 0.5, "cost": 2},
	"turnbuckle": {"shape": "cylinder", "radius": 0.18, "height": 1.6, "dynamic": false, "cost": 1},
	"bench": {"shape": "box", "size": [1.6, 0.5, 0.45], "dynamic": true, "mass": 35.0, "cost": 2},
}
static var HAZARD_TYPES := {
	"fire_grate": {"element": "", "tick_damage": 4.0, "tick": 0.5, "vfx": "fire"},
	"puddle": {"element": "", "tick_damage": 0.0, "tick": 0.5, "vfx": "puddle", "status": {"id": "slick", "speed": 0.8, "duration": 0.6}},
	"spring_pad": {"launch": 9.0, "vfx": "spring"},
	"shock_plate": {"element": "", "tick_damage": 3.0, "tick": 0.6, "vfx": "shock", "status": {"id": "zapped", "duration": 0.6, "speed": 0.7}},
}


static func build(parent: Node3D, a: ArenaDef) -> Dictionary:
	var out := {"floor": null, "walls": [], "props": [], "dynamic_props": []}
	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = Rig.LAYER_WORLD
	floor_body.collision_mask = 0
	floor_body.physics_material_override = mat
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var half := a.radius + (0.6 if a.ringout else 3.0)
	box.size = Vector3(half * 2.0, 1.0, half * 2.0)
	fs.shape = box
	if a.base in ["circle", "platform"]:
		var cyl := CylinderShape3D.new()
		cyl.radius = a.radius + (0.2 if a.ringout else 3.0)
		cyl.height = 1.0
		fs.shape = cyl
	fs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fs)
	parent.add_child(floor_body)
	out["floor"] = floor_body
	if a.wall_height > 0.01:
		var wall_mat := PhysicsMaterial.new()
		wall_mat.friction = 0.3
		wall_mat.bounce = 0.25
		var sides := 8
		match a.base:
			"square":
				sides = 4
			"circle":
				sides = 24
		var side_len := 2.0 * a.radius * tan(PI / sides) + 0.2
		# Collision walls rise well above the visible fence so launches never clear the cage.
		var wall_h := a.wall_height + 5.0
		for i in sides:
			# side normals at TAU*i/sides: the same polygon ArenaDef.clamp_point and ArenaView use
			var ang := TAU * i / sides
			var n := Vector3(cos(ang), 0.0, sin(ang))
			var wb := StaticBody3D.new()
			wb.name = "Wall%d" % i
			wb.collision_layer = Rig.LAYER_WORLD
			wb.collision_mask = 0
			wb.physics_material_override = wall_mat
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(side_len, wall_h, 0.3)
			cs.shape = bs
			wb.add_child(cs)
			parent.add_child(wb)
			wb.global_transform = Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), n * (a.radius + 0.15) + Vector3.UP * wall_h * 0.5)
			out["walls"].append(wb)
	for p in a.props:
		var def: Dictionary = PROP_TYPES.get(p["type"], {})
		if def.is_empty():
			continue
		var body: PhysicsBody3D
		var sc: float = p["scale"]
		if bool(def.get("dynamic", false)):
			var rb := RigidBody3D.new()
			rb.mass = float(def.get("mass", 30.0)) * sc * sc * sc
			rb.collision_layer = Rig.LAYER_PROPS
			rb.collision_mask = Rig.LAYER_WORLD | Rig.LAYER_FIGHTERS | Rig.LAYER_PROPS
			rb.can_sleep = true
			body = rb
			out["dynamic_props"].append(rb)
		else:
			var sb := StaticBody3D.new()
			sb.collision_layer = Rig.LAYER_PROPS
			sb.collision_mask = 0
			body = sb
		var pm := PhysicsMaterial.new()
		pm.friction = 0.6
		pm.bounce = float(def.get("bounce", 0.1))
		body.set("physics_material_override", pm)
		body.name = "Prop_%s_%d" % [p["type"], out["props"].size()]
		var cs2 := CollisionShape3D.new()
		var h := 1.0
		if def["shape"] == "box":
			var bx := BoxShape3D.new()
			bx.size = MathX.vec3(def["size"]) * sc
			cs2.shape = bx
			h = bx.size.y
		else:
			var cy := CylinderShape3D.new()
			cy.radius = float(def["radius"]) * sc
			cy.height = float(def["height"]) * sc
			cs2.shape = cy
			h = cy.height
		body.add_child(cs2)
		parent.add_child(body)
		var pp: Vector3 = p["pos"]
		body.global_transform = Transform3D(Basis(Vector3.UP, p["yaw"]), Vector3(pp.x, pp.y + h * 0.5, pp.z))
		body.set_meta("prop_type", p["type"])
		out["props"].append(body)
	return out


## Registers the arena's hazards as permanent zones in the effects system.
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
