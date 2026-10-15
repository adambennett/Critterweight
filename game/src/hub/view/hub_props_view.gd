class_name HubPropsView
extends Node3D
## Moving and state-dependent props of The Cannery (view only): the three hanging bags (the Body
## bag is shaped like the Commissioner), crates, carryable parts (fuse, cable spool, red button,
## the sign's fallen A, the trash-can lid), chum buckets in flight, the loose panel, the elevator
## chain gate, the pier-ladder tarp, the Wall of Fame photos and the secret world states (open belt
## case, boiler hatch, lit sign letter). Every transform mirrors the physics body each frame.

var v: HubView
var mode: HubMode
var bag_nodes := {}                ## bag id -> Node3D (origin = bag bottom, like the body)
var chain_nodes := {}              ## bag id -> MeshInstance3D (stretched between hang point and bag top)
var crate_nodes: Array[Node3D] = []
var item_nodes := {}               ## item id -> Node3D
var bucket_nodes := {}             ## bucket id -> Node3D
var panel_node: Node3D
var gate_node: Node3D
var tarp_node: Node3D
var photos_node: Node3D
var boiler_hatch: Node3D
var _bucket_mesh: Mesh
var _bucket_mat: Material


func build(view: HubView) -> void:
	v = view
	mode = view.mode
	name = "HubProps"
	for bid in HubLayout.BAGS:
		_make_bag(str(bid))
	for i in mode.world["crates"].size():
		crate_nodes.append(_crate_visual())
	for item_id in HubLayout.ITEMS:
		item_nodes[item_id] = _item_visual(str(item_id))
	panel_node = _box_node(Vector3(0.12, 2.0, 1.55), Color("#86614f"), HubMeshKit.BRICK)
	panel_node.position = Vector3(HubLayout.PANEL_RECT.position.x + 0.15, 1.0, 4.9)
	add_child(panel_node)
	gate_node = _gate()
	tarp_node = _tarp()
	boiler_hatch = _box_node(Vector3(0.04, 0.42, 0.42), Color("#3a2e27"), HubMeshKit.PLAIN)
	boiler_hatch.position = HubLayout.BOILER_POS + Vector3(-HubLayout.BOILER_R - 0.04, 1.25, 0)
	add_child(boiler_hatch)
	var bm := CylinderMesh.new()
	bm.top_radius = 0.17
	bm.bottom_radius = 0.13
	bm.height = 0.3
	_bucket_mesh = bm
	_bucket_mat = Materials.toon(Color("#b0b6ba"), 0.5, 0.3)
	refresh_world()
	refresh_photos()


func _box_node(size: Vector3, col: Color, pattern := HubMeshKit.PLAIN) -> Node3D:
	var k := HubMeshKit.new()
	k.box(Vector3.ZERO, size, col, pattern, true, Basis.IDENTITY, false)
	var mi := k.commit("Box", v.surface_mat)
	var n := Node3D.new()
	n.add_child(mi)
	return n


func _make_bag(bid: String) -> void:
	var d: Dictionary = HubLayout.BAGS[bid]
	var r := float(d["radius"])
	var len := float(d["length"])
	var k := HubMeshKit.new()
	match bid:
		"light":
			k.cyl(Vector3(0, 0.0, 0), Vector3(0, len, 0), r, Color("#d9532b"), 14, HubMeshKit.PLAIN, true, true, r * 0.92)
			k.cyl(Vector3(0, len * 0.45, 0), Vector3(0, len * 0.55, 0), r + 0.01, Color("#f2f2ec"), 14)
		"heavy":
			k.cyl(Vector3(0, 0.0, 0), Vector3(0, len, 0), r, Color("#3a3a42"), 16, HubMeshKit.PLAIN, true, true, r)
			k.cyl(Vector3(0, len * 0.12, 0), Vector3(0, len * 0.2, 0), r + 0.01, Color("#c9a227"), 16)
			k.cyl(Vector3(0, len * 0.8, 0), Vector3(0, len * 0.88, 0), r + 0.01, Color("#c9a227"), 16)
		"body":
			# a dummy shaped like the Commissioner: stubby legs, domed shell, head and beak
			k.cyl(Vector3(0, 0.0, 0), Vector3(0, 0.3, 0), r * 0.55, Color("#6b5a48"), 10)
			k.sphere(Vector3(0, 0.75, 0), r * 1.05, Color("#4f6b3a"), 6, 12, HubMeshKit.PLAIN, true, Vector3(1.0, 0.85, 1.0))
			k.sphere(Vector3(0, 0.78, 0.0), r * 1.1, Color("#3f5a2e"), 5, 12, HubMeshKit.PLAIN, true, Vector3(1.02, 0.25, 1.02))
			k.sphere(Vector3(0, 1.3, 0.12), r * 0.42, Color("#6f7d4a"), 5, 10)
			k.cyl(Vector3(0, 1.28, 0.25), Vector3(0, 1.22, 0.42), 0.07, Color("#d9c27a"), 8, HubMeshKit.PLAIN, true, true, 0.02)
			k.sphere(Vector3(0.08, 1.36, 0.27), 0.03, Color.WHITE, 3, 5)
			k.sphere(Vector3(-0.08, 1.36, 0.27), 0.03, Color.WHITE, 3, 5)
			k.box(Vector3(0, 1.0, r * 0.95), Vector3(0.36, 0.2, 0.02), Color("#e9e2cf"), HubMeshKit.PAINT)
	k.cyl(Vector3(0, len, 0), Vector3(0, len + 0.06, 0), 0.06, Color("#5b6168"), 8)
	var n := Node3D.new()
	n.name = "BagView_" + bid
	n.add_child(k.commit("Bag", v.surface_mat))
	add_child(n)
	bag_nodes[bid] = n
	var chain := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.02
	cm.height = 1.0
	chain.mesh = cm
	chain.material_override = Materials.toon(Color("#9fa6ad"), 0.4, 0.8)
	add_child(chain)
	chain_nodes[bid] = chain


func _crate_visual() -> Node3D:
	var s := HubWorld.CRATE_SIZE
	var k := HubMeshKit.new()
	k.box(Vector3.ZERO, Vector3.ONE * s, Color("#a8743a"), HubMeshKit.PLANK, true, Basis.IDENTITY, false)
	for e in [-1.0, 1.0]:
		k.box(Vector3(0, e * s * 0.42, s * 0.505), Vector3(s, 0.06, 0.01), Color("#6b4a2a"))
		k.box(Vector3(0, e * s * 0.42, -s * 0.505), Vector3(s, 0.06, 0.01), Color("#6b4a2a"))
	k.box(Vector3(0, 0, s * 0.506), Vector3(s * 0.9, 0.05, 0.01), Color("#6b4a2a"), HubMeshKit.PLAIN, true, Basis(Vector3(0, 0, 1), 0.78))
	var n := Node3D.new()
	n.add_child(k.commit("Crate", v.surface_mat))
	add_child(n)
	return n


func _item_visual(item_id: String) -> Node3D:
	var d: Dictionary = HubLayout.ITEMS[item_id]
	var sz: Vector3 = d["size"]
	var k := HubMeshKit.new()
	match item_id:
		"fuse":
			k.cyl(Vector3(0, -sz.y * 0.5, 0), Vector3(0, sz.y * 0.5, 0), 0.09, Color("#cfe3ea"), 10)
			k.cyl(Vector3(0, -sz.y * 0.5, 0), Vector3(0, -sz.y * 0.32, 0), 0.11, Color("#c9a227"), 10)
			k.cyl(Vector3(0, sz.y * 0.32, 0), Vector3(0, sz.y * 0.5, 0), 0.11, Color("#c9a227"), 10)
		"cable_spool":
			k.cyl(Vector3(0, 0, -sz.z * 0.5), Vector3(0, 0, sz.z * 0.5), 0.12, Color("#5e4a3a"), 10)
			k.cyl(Vector3(0, 0, -sz.z * 0.45), Vector3(0, 0, sz.z * 0.45), 0.24, Color("#2e2e33"), 14)
			k.cyl(Vector3(0, 0, -sz.z * 0.5), Vector3(0, 0, -sz.z * 0.42), 0.3, Color("#8a6a48"), 14)
			k.cyl(Vector3(0, 0, sz.z * 0.42), Vector3(0, 0, sz.z * 0.5), 0.3, Color("#8a6a48"), 14)
		"button":
			k.box(Vector3(0, -0.04, 0), Vector3(sz.x, 0.14, sz.z), Color("#c9a227"))
			k.cyl(Vector3(0, 0.03, 0), Vector3(0, 0.1, 0), 0.1, Color("#ff3b3b"), 12)
		"letter_a":
			var col := Color("#ff4fb8")
			k.box(Vector3(-0.22, 0, 0), Vector3(0.16, 1.0, 0.14), col, HubMeshKit.PLAIN, true, Basis(Vector3(0, 0, 1), -0.42))
			k.box(Vector3(0.22, 0, 0), Vector3(0.16, 1.0, 0.14), col, HubMeshKit.PLAIN, true, Basis(Vector3(0, 0, 1), 0.42))
			k.box(Vector3(0, -0.1, 0), Vector3(0.4, 0.12, 0.14), col)
		"trash_lid":
			k.cyl(Vector3(0, -0.03, 0), Vector3(0, 0.03, 0), 0.35, Color("#7d8288"), 14, HubMeshKit.CORRUGATED)
			k.box(Vector3(0, 0.07, 0), Vector3(0.22, 0.05, 0.05), Color("#5b6168"))
		_:
			k.box(Vector3.ZERO, sz, Color("#888888"))
	var n := Node3D.new()
	n.name = "ItemView_" + item_id
	n.add_child(k.commit("Item", v.surface_mat))
	add_child(n)
	return n


func _gate() -> Node3D:
	var n := Node3D.new()
	n.name = "ElevatorGate"
	var fence_mat := ShaderMaterial.new()
	fence_mat.shader = load("res://src/view/shaders/fence.gdshader")
	fence_mat.set_shader_parameter("wire_color", Color("#c9a227"))
	var r := HubLayout.ELEVATOR_RECT
	for side in 2:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(r.size.x if side == 0 else r.size.y, 2.4)
		q.mesh = qm
		q.material_override = fence_mat
		if side == 0:
			q.position = Vector3(r.get_center().x, 1.2, r.end.y)
		else:
			q.position = Vector3(r.position.x, 1.2, r.get_center().y)
			q.rotation = Vector3(0, PI * 0.5, 0)
		n.add_child(q)
	var k := HubMeshKit.new()
	k.cyl(Vector3(r.position.x, 1.2, r.end.y), Vector3(r.end.x, 1.2, r.end.y), 0.03, Color("#9fa6ad"), 6)
	k.box(Vector3(r.get_center().x, 1.2, r.end.y + 0.04), Vector3(0.18, 0.22, 0.08), Color("#c9a227"))
	n.add_child(k.commit("Chain", v.surface_mat))
	add_child(n)
	return n


func _tarp() -> Node3D:
	var k := HubMeshKit.new()
	k.box(Vector3(0, 0.08, 0), Vector3(1.4, 0.16, 1.0), Color("#355d7f"), HubMeshKit.PLAIN, true, Basis(Vector3.RIGHT, 0.08), false)
	var n := Node3D.new()
	n.name = "LadderTarp"
	n.add_child(k.commit("Tarp", v.surface_mat))
	n.position = Vector3(HubLayout.PIER_LADDER.x, 0.0, HubLayout.PIER_LADDER.z + 0.1)
	add_child(n)
	return n


## World states that follow found secrets / purchases (called at build and on hub events).
func refresh_world() -> void:
	var s := mode.secrets
	panel_node.visible = not s.panel_open()
	panel_node.rotation = Vector3(0, 0, 0.12) if s.panel_revealed() and not s.panel_open() else Vector3.ZERO
	panel_node.position.x = HubLayout.PANEL_RECT.position.x + (0.28 if s.panel_revealed() and not s.panel_open() else 0.15)
	gate_node.visible = not s.elevator_fixed()
	tarp_node.visible = not s.pier_revealed()
	boiler_hatch.rotation = Vector3(0, -1.2, 0) if mode.state.has_secret("sec_boiler_face") else Vector3.ZERO
	var dress := v.dressing
	if dress and dress.elevator_sign:
		dress.elevator_sign.text = "FREIGHT  -  TO THE ROOF" if s.elevator_fixed() else "FREIGHT  -  OUT OF ORDER"
		dress.elevator_sign.modulate = Color("#8bd426") if s.elevator_fixed() else Color("#ff5a5a")
	if dress:
		var a_letter: MeshInstance3D = dress.sign_letters.get("A2")
		if a_letter:
			a_letter.set_instance_shader_parameter("lit", 1.0 if s.sign_fixed() else 0.0)
	var glass := v.get_node_or_null("BeltCaseGlass") as Node3D
	if glass:
		glass.position.y = 1.64 + (0.5 if mode.state.has_secret("sec_belt_case_combo") else 0.0)


## The Wall of Fame / Shame: one photo per run, green = beat a boss, red = loss, gold = title.
func refresh_photos() -> void:
	if photos_node:
		photos_node.queue_free()
	photos_node = Node3D.new()
	photos_node.name = "WallOfFame"
	add_child(photos_node)
	var photos := mode.state.wall_photos()
	if photos.is_empty():
		return
	var k := HubMeshKit.new()
	var cols := {"title": Color("#c9a227"), "win": Color("#8bd426"), "loss": Color("#ff5a5a")}
	for i in photos.size():
		var p: Dictionary = photos[i]
		var row := floori(i / 6.0)
		var col := i % 6
		var center := Vector3(-11.78, 2.45 - row * 0.38, 9.95 + col * 0.42 + (0.6 if col >= 3 else 0.0))
		var frame_col: Color = cols.get(str(p["result"]), Color.WHITE)
		k.box(center, Vector3(0.03, 0.32, 0.34), frame_col)
		var fighter_col := Color.from_string(str(Content.get_entry("creatures", str(p["fighter"])).get("art", {}).get("palette", {}).get("primary", "#9aa0ab")), Color("#9aa0ab"))
		k.box(center + Vector3(0.02, -0.02, 0), Vector3(0.02, 0.18, 0.12), fighter_col)
		k.sphere(center + Vector3(0.025, 0.09, 0), 0.05, fighter_col.lightened(0.1), 3, 6)
	photos_node.add_child(k.commit("Photos", v.surface_mat))


func update(_dt: float) -> void:
	for bid in bag_nodes:
		var body: RigidBody3D = mode.world["bags"].get(bid)
		if body == null:
			continue
		var n: Node3D = bag_nodes[bid]
		n.global_transform = body.global_transform
		var d: Dictionary = HubLayout.BAGS[bid]
		var top := body.global_transform * Vector3(0, float(d["length"]) + 0.05, 0)
		var hang: Vector3 = d["hang"]
		var chain: MeshInstance3D = chain_nodes[bid]
		var mid := (top + hang) * 0.5
		var len := maxf(0.05, hang.distance_to(top))
		chain.global_transform = Transform3D(Basis(MathX.rotation_between(Vector3.UP, (hang - top).normalized())) * Basis.from_scale(Vector3(1, len, 1)), mid)
	for i in crate_nodes.size():
		var c: RigidBody3D = mode.world["crates"][i]
		crate_nodes[i].global_transform = c.global_transform
	for item_id in item_nodes:
		var n2: Node3D = item_nodes[item_id]
		var vis := mode.item_visible(str(item_id))
		n2.visible = vis
		if vis:
			var b: RigidBody3D = mode.world["items"][item_id]
			n2.global_transform = b.global_transform
	# chum buckets in flight
	var seen := {}
	for bk in mode.drill.buckets:
		var bid2 := int(bk["id"])
		seen[bid2] = true
		var node: MeshInstance3D = bucket_nodes.get(bid2)
		if node == null:
			node = MeshInstance3D.new()
			node.mesh = _bucket_mesh
			node.material_override = _bucket_mat
			add_child(node)
			bucket_nodes[bid2] = node
		node.global_position = bk["pos"]
		node.rotation = Vector3(float(bk["age"]) * 7.0, float(bk["age"]) * 3.0, 0)
	for id in bucket_nodes.keys():
		if not seen.has(id):
			(bucket_nodes[id] as Node).queue_free()
			bucket_nodes.erase(id)
