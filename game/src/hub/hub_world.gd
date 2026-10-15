class_name HubWorld
extends RefCounted
## Builds the PHYSICAL Cannery from HubLayout under a parent node (the hub MatchSim, so every
## body shares the fight world): floor slabs, walls split around door openings, solid furniture,
## sloped stairs, fighter-only invisible blockers, the practice-cage fence, the elevator's chain
## gate, the loose panel, the boiler, NPC collision, the three hanging bags, the crates and the
## carryable parts. Visuals are built separately by HubView (headless tests stay lean).
##
## Collision layers: level geometry = Rig.LAYER_WORLD; props (bags, crates, parts) = LAYER_PROPS
## and scan WORLD|PROPS only, so they fly over/through the fighter-only blockers, which sit on
## LAYER_FIGHTERS with an empty mask (fighters scan FIGHTERS, so they are stopped).

const FIGHTER_BLOCK := Rig.LAYER_FIGHTERS
const PROP_MASK := Rig.LAYER_WORLD | Rig.LAYER_PROPS
const CRATE_COUNT := 10
const CRATE_SIZE := 0.62
const CRATE_MASS := 18.0

var parent: Node3D
var out := {}


static func build(p: Node3D) -> Dictionary:
	var w := HubWorld.new()
	w.parent = p
	w._build_all()
	return w.out


func _build_all() -> void:
	out = {"walls": [], "statics": [], "bags": {}, "bag_anchors": {}, "crates": [], "items": {}, "panel": null, "gate": [],
		"boiler": null, "npc_bodies": {}, "cage": [], "blockers": []}
	var mat := PhysicsMaterial.new()
	mat.friction = 0.65
	for f in HubLayout.floors():
		var r: Rect2 = f["rect"]
		var th := float(f.get("thick", 1.0))
		_box("Floor_" + str(f["name"]), Vector3(r.position.x + r.size.x * 0.5, float(f["y"]) - th * 0.5, r.position.y + r.size.y * 0.5),
			Vector3(r.size.x, th, r.size.y), Rig.LAYER_WORLD, mat)
	for w in HubLayout.walls():
		_wall(w)
	for s in HubLayout.solids():
		var b: AABB = s["box"]
		out["statics"].append(_box("Solid_" + str(s["name"]), b.get_center(), b.size, Rig.LAYER_WORLD, mat))
	for rp in HubLayout.ramps():
		_ramp(rp, mat)
	for bl in HubLayout.blockers():
		if bl.has("box"):
			var bb: AABB = bl["box"]
			out["blockers"].append(_box("Block_" + str(bl["name"]), bb.get_center(), bb.size, FIGHTER_BLOCK, null))
		else:
			out["blockers"].append(_sloped_blocker(bl))
	_cage()
	_elevator_gate()
	_panel()
	_boiler()
	_npcs()
	_bags()
	_crates()
	_items()


func _box(nm: String, center: Vector3, size: Vector3, layer: int, mat: PhysicsMaterial, basis := Basis.IDENTITY) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = layer
	sb.collision_mask = 0
	if mat:
		sb.physics_material_override = mat
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_transform = Transform3D(basis, center)
	return sb


## A wall segment split into solid pieces around its openings ("door"/"panel" cut collision,
## "window"/"glass" are visual only).
func _wall(w: Dictionary) -> void:
	var cuts := []
	for o in w["openings"]:
		if str(o[4]) in ["door", "panel"]:
			cuts.append([float(o[0]), float(o[1]), float(o[2]), float(o[3])])
	cuts.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var y0 := float(w["y0"])
	var y1 := float(w["y1"])
	var cursor := float(w["from"])
	var pieces := []   # [from, to, y0, y1]
	for c in cuts:
		if float(c[0]) > cursor:
			pieces.append([cursor, float(c[0]), y0, y1])
		if float(c[2]) > y0 + 0.01:
			pieces.append([float(c[0]), float(c[1]), y0, float(c[2])])
		if float(c[3]) < y1 - 0.01:
			pieces.append([float(c[0]), float(c[1]), float(c[3]), y1])
		cursor = maxf(cursor, float(c[1]))
	if cursor < float(w["to"]):
		pieces.append([cursor, float(w["to"]), y0, y1])
	var c0 := float(w["c"])
	for i in pieces.size():
		var pc: Array = pieces[i]
		var a := float(pc[0])
		var b := float(pc[1])
		var h0 := float(pc[2])
		var h1 := float(pc[3])
		if b - a < 0.01 or h1 - h0 < 0.01:
			continue
		var center: Vector3
		var size: Vector3
		if str(w["axis"]) == "x":
			center = Vector3((a + b) * 0.5, (h0 + h1) * 0.5, c0)
			size = Vector3(b - a + HubLayout.WALL_T * 0.0, h1 - h0, HubLayout.WALL_T)
		else:
			center = Vector3(c0, (h0 + h1) * 0.5, (a + b) * 0.5)
			size = Vector3(HubLayout.WALL_T, h1 - h0, b - a)
		out["walls"].append(_box("Wall_%s_%d" % [str(w.get("space", "")), out["walls"].size()], center, size, Rig.LAYER_WORLD, null))


## A sloped slab whose TOP face is the walking surface from a (bottom centre) to b (top centre).
func _ramp(rp: Dictionary, mat: PhysicsMaterial) -> void:
	var a: Vector3 = rp["a"]
	var b: Vector3 = rp["b"]
	var th := float(rp["thick"])
	var dir := (b - a)
	var length := dir.length()
	var fwd := dir / length
	var side := Vector3(0, 0, 1) if absf(fwd.z) < 0.9 else Vector3(1, 0, 0)
	var up := side.cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
		side = -side
	var basis := Basis(fwd, up, side)
	var center := (a + b) * 0.5 - up * th * 0.5
	out["statics"].append(_box("Ramp_" + str(rp["name"]), center, Vector3(length, th, float(rp["width"])), Rig.LAYER_WORLD, mat, basis))


func _sloped_blocker(bl: Dictionary) -> StaticBody3D:
	var a: Vector3 = bl["a"]
	var b: Vector3 = bl["b"]
	var h := float(bl["h"])
	var dir := b - a
	var length := dir.length()
	var fwd := dir / length
	var side := Vector3(0, 0, 1)
	var up := side.cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
		side = -side
	var center := (a + b) * 0.5 + up * h * 0.5
	return _box("Block_" + str(bl["name"]), center, Vector3(length, h, 0.3), FIGHTER_BLOCK, null, Basis(fwd, up, side))


func _cage() -> void:
	var pts := HubLayout.cage_points()
	for i in pts.size():
		if i == HubLayout.CAGE_GATE_SIDE:
			continue
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		var ang := atan2(b.y - a.y, b.x - a.x)
		var basis := Basis(Vector3.UP, -ang)
		out["cage"].append(_box("CageFence%d" % i, Vector3(mid.x, 1.1, mid.y), Vector3(len + 0.2, 2.2, 0.16), Rig.LAYER_WORLD, null, basis))


func _elevator_gate() -> void:
	var r := HubLayout.ELEVATOR_RECT
	out["gate"].append(_box("ElevatorGateS", Vector3(r.position.x + r.size.x * 0.5, 1.2, r.end.y), Vector3(r.size.x, 2.4, 0.12), Rig.LAYER_WORLD, null))
	out["gate"].append(_box("ElevatorGateW", Vector3(r.position.x, 1.2, r.position.y + r.size.y * 0.5), Vector3(0.12, 2.4, r.size.y), Rig.LAYER_WORLD, null))


func _panel() -> void:
	var r := HubLayout.PANEL_RECT
	out["panel"] = _box("LoosePanel", Vector3(r.position.x + r.size.x * 0.5, 1.05, r.position.y + r.size.y * 0.5), Vector3(r.size.x, 2.1, r.size.y), Rig.LAYER_WORLD, null)


func _frozen_body(nm: String, shape: Shape3D, shape_offset: Vector3, pos: Vector3, layer: int) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = nm
	rb.freeze = true
	rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rb.collision_layer = layer
	rb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = shape_offset
	rb.add_child(cs)
	parent.add_child(rb)
	rb.global_position = pos
	return rb


func _boiler() -> void:
	var cyl := CylinderShape3D.new()
	cyl.radius = HubLayout.BOILER_R
	cyl.height = 3.4
	out["boiler"] = _frozen_body("Boiler", cyl, Vector3(0, 1.7, 0), HubLayout.BOILER_POS, Rig.LAYER_WORLD)


## Every NPC is solid (a kinematic capsule) and hittable (hits are shrugged off, HUB.md §6).
func _npcs() -> void:
	for id in HubLayout.NPC_SPOTS:
		var spot: Dictionary = HubLayout.NPC_SPOTS[id]
		var cap := CapsuleShape3D.new()
		cap.radius = 0.38 if id != "snappington" else 0.2
		cap.height = 1.4
		var rb := _frozen_body("Npc_" + str(id), cap, Vector3(0, 0.7, 0), spot["pos"], Rig.LAYER_WORLD)
		if id == "snappington":
			rb.collision_layer = 0   # her desk/shell blockers already exist
		out["npc_bodies"][id] = rb


func _bags() -> void:
	for id in HubLayout.BAGS:
		var d: Dictionary = HubLayout.BAGS[id]
		var hang: Vector3 = d["hang"]
		var anchor := StaticBody3D.new()
		anchor.name = "BagAnchor_" + str(id)
		anchor.collision_layer = 0
		anchor.collision_mask = 0
		parent.add_child(anchor)
		anchor.global_position = hang
		var rb := RigidBody3D.new()
		rb.name = "Bag_" + str(id)
		rb.mass = float(d["mass"])
		rb.collision_layer = Rig.LAYER_PROPS
		rb.collision_mask = PROP_MASK
		rb.can_sleep = false
		rb.linear_damp = 0.35
		rb.angular_damp = 2.2
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = float(d["radius"])
		cap.height = float(d["length"])
		cs.shape = cap
		cs.position = Vector3(0, float(d["length"]) * 0.5, 0)
		rb.add_child(cs)
		parent.add_child(rb)
		rb.global_position = Vector3(hang.x, float(d["bottom"]), hang.z)
		var pj := PinJoint3D.new()
		pj.name = "BagChain_" + str(id)
		parent.add_child(pj)
		pj.global_position = hang
		pj.node_a = pj.get_path_to(anchor)
		pj.node_b = pj.get_path_to(rb)
		out["bags"][id] = rb
		out["bag_anchors"][id] = anchor


func _crates() -> void:
	for i in CRATE_COUNT:
		var rb := RigidBody3D.new()
		rb.name = "Crate%d" % i
		rb.mass = CRATE_MASS
		rb.collision_layer = Rig.LAYER_PROPS
		rb.collision_mask = PROP_MASK
		rb.continuous_cd = true
		rb.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		rb.linear_damp = 0.0
		var pm := PhysicsMaterial.new()
		pm.friction = 0.8
		pm.bounce = 0.05
		rb.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * CRATE_SIZE
		cs.shape = bs
		rb.add_child(cs)
		parent.add_child(rb)
		rb.global_position = crate_home(i)
		out["crates"].append(rb)


## Pile position of crate i (two rows of five, stacked two high at the back).
static func crate_home(i: int) -> Vector3:
	var p := HubLayout.CRATE_PILE
	var row := floori(i / 5.0)
	var col := i % 5
	var layer := 0
	if col >= 3:
		layer = 1
		col -= 3
	return p + Vector3((col - 1) * (CRATE_SIZE + 0.06), CRATE_SIZE * 0.5 + layer * CRATE_SIZE + 0.01, row * (CRATE_SIZE + 0.08) + layer * 0.2)


func _items() -> void:
	for id in HubLayout.ITEMS:
		var d: Dictionary = HubLayout.ITEMS[id]
		var rb := RigidBody3D.new()
		rb.name = "Item_" + str(id)
		rb.mass = float(d["mass"])
		rb.collision_layer = Rig.LAYER_PROPS
		rb.collision_mask = PROP_MASK
		rb.continuous_cd = true
		rb.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		rb.linear_damp = 0.0
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = d["size"]
		cs.shape = bs
		rb.add_child(cs)
		parent.add_child(rb)
		rb.global_position = d["pos"]
		out["items"][id] = rb
