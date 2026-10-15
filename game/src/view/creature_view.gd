class_name CreatureView
extends Node3D
## Renders one fighter from a stream of segment transforms (local sim or network snapshots).
## Uses the creature's forged skinned model when available (art.model), otherwise builds a
## stylized segment model from the body's shapes. Also owns per-creature cosmetic feedback:
## hit flash, localized bruises, JUICE glow, status tint and the end-of-fight gore gag.
##
## The node itself stays at the world origin; bones/segments carry world transforms.
##
## Forged models (tools/forge, docs/ART_PIPELINE.md): a Skeleton3D whose bone NAMES are segment
## ids (bind pose = segment pivot in fighter rest space), one surface per material class
## (skin/iron/cloth/eye/ember/team...) with LINEAR vertex colours as albedo and PBR hints read
## from the imported materials, an optional unskinned "gore_piece" mesh (used by detach_piece)
## and vertex alpha = emissive strength on glowing surfaces (the fighter's "Hype feature").
##
## Cosmetics (view-only, the profile owner's fighter; FighterCosmetics.dress): attachments riding a
## segment (CosmeticAttachments: gold tooth, trash-can lid, replica belt, scarf) and a JUICE colour
## variant (juice glow + the glowing surfaces' colour, e.g. Stoke's white-hot Sizzle).

const MAX_BRUISES := 8
const DEFAULT_JUICE := Color(1.0, 0.55, 0.1)

var creature: CreatureDef
var body: BodyDef
var team_color := Color.WHITE
var hype := 0.0                           ## 0..1, drives the emissive "Hype feature" brightness
var _prev: Array[Transform3D] = []
var _curr: Array[Transform3D] = []
var _seg_nodes: Array[Node3D] = []        ## fallback mode: one node per segment
var _skeleton: Skeleton3D = null
var _bone_of_seg: PackedInt32Array = PackedInt32Array()
var _bone_order: PackedInt32Array = PackedInt32Array()   ## bones sorted parents-first
var _seg_of_bone: PackedInt32Array = PackedInt32Array()
var _bone_global: Array[Transform3D] = []
var _materials: Array[ShaderMaterial] = []
var _glow_materials: Array[ShaderMaterial] = []
var _gore_mesh: Mesh = null
var _bruises: Array = []                  ## [{seg, local: Vector3, s: float}]
var _flash := 0.0
var juice_amount := 0.0
var status_color := Color(0, 0, 0, 0)
var gore_level := 2                       ## 0 off, 1 reduced, 2 full
var detached := false
var visible_alpha := 1.0
var juice_color := DEFAULT_JUICE
var glow_color := Color(1, 1, 1, 0)       ## rgb = colour the glowing surfaces shift to, a = how far
## While the round is live the walkout pieces (lid, belt) are put away; the hub and the walkout
## (intro, celebrations) show everything.
var cosmetic_combat := false
var _seg_global: Array[Transform3D] = []
var _attachments: Array = []               ## [{node: Node3D, seg: int, local: Transform3D, kind, id, walkout: bool, popped: bool}]
var _vis_points := {}                      ## segment index -> PackedVector3Array: the forged model's vertices (segment-local, rest)


func setup(c: CreatureDef, tint := Color.WHITE) -> void:
	creature = c
	body = c.body
	team_color = tint
	name = "View_" + c.id
	var model_path := str(c.art.get("model", ""))
	if model_path != "" and _try_load_model(model_path):
		pass
	else:
		_build_fallback()
	_prev.resize(body.segments.size())
	_curr.resize(body.segments.size())
	_seg_global.resize(body.segments.size())


func _palette(key: String, fallback: Color) -> Color:
	var pal: Dictionary = creature.art.get("palette", {})
	if pal.has(key):
		return Color.from_string(str(pal[key]), fallback)
	return fallback


func _make_material(color: Color, roughness := -1.0, metallic := 0.0, glow := false) -> ShaderMaterial:
	var m := Materials.creature_material()
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("roughness_v", float(creature.art.get("roughness", 0.65)) if roughness < 0.0 else roughness)
	m.set_shader_parameter("metallic_v", metallic)
	m.set_shader_parameter("vertex_glow", 1.0 if glow else 0.0)
	m.set_shader_parameter("time_offset", randf() * 10.0)
	m.next_pass = Materials.outline_material(float(creature.art.get("outline", 0.012)))
	_materials.append(m)
	if glow:
		_glow_materials.append(m)
	return m


func _try_load_model(path: String) -> bool:
	var scene: PackedScene = null
	if path.begins_with("res://"):
		# core content only (Content refuses res:// paths from mods), and only imported models
		if path.get_extension().to_lower() == "glb" and ResourceLoader.exists(path):
			scene = load(path) as PackedScene
	elif Content.is_package_asset(path) and path.get_extension().to_lower() == "glb":
		# a mod's model: only files Content validated as part of a loaded package
		scene = ModelLoader.load_gltf_scene(path)
	elif path != "":
		push_warning("%s: model '%s' is not a validated package file; using the built-in look" % [creature.id, path])
	if scene == null:
		return false
	var inst := scene.instantiate()
	add_child(inst)
	_skeleton = _find_skeleton(inst)
	if _skeleton == null:
		inst.queue_free()
		return false
	var nb := _skeleton.get_bone_count()
	_bone_of_seg.resize(body.segments.size())
	_seg_of_bone.resize(nb)
	_seg_of_bone.fill(-1)
	var missing := 0
	for s: BodyDef.Seg in body.segments:
		var bi := _skeleton.find_bone(s.id)
		_bone_of_seg[s.index] = bi
		if bi >= 0:
			_seg_of_bone[bi] = s.index
		else:
			missing += 1
	if missing > 0:
		push_warning("%s: model %s is missing %d segment bone(s)" % [creature.id, path, missing])
	# parents-first bone order so hierarchical skeletons (any importer layout) pose correctly
	_bone_order = PackedInt32Array()
	_bone_global.resize(nb)
	var pending: Array[int] = []
	for b in _skeleton.get_parentless_bones():
		pending.append(b)
	while not pending.is_empty():
		var b: int = pending.pop_front()
		_bone_order.append(b)
		for c in _skeleton.get_bone_children(b):
			pending.append(c)
	for mi in _find_meshes(inst):
		if mi.name == "gore_piece":
			_gore_mesh = mi.mesh
			mi.visible = false
			continue
		_collect_points(mi, inst)
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si)
			var rough := -1.0
			var metal := 0.0
			var glow := false
			var tint := Color.WHITE
			if src is BaseMaterial3D:
				var bm := src as BaseMaterial3D
				rough = bm.roughness
				metal = bm.metallic
				glow = bm.emission_enabled
				if bm.resource_name == "team":
					tint = team_color
			mi.set_surface_override_material(si, _make_material(tint, rough, metal, glow))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return true


## The skinned model's vertices grouped by their dominant bone = segment, in segment-local rest
## space (bind pose: bones on the pivots, identity orientation). Cosmetic anchors fit to these, so
## a ring sits on the visible skin rather than on the (smaller) collision shapes.
func _collect_points(mi: MeshInstance3D, inst: Node) -> void:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != inst:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var sk := mi.skin
	# gathered in plain Arrays: a packed array read out of a Dictionary is a copy, so appending to it
	# in place would be lost
	var acc := {}
	for surf in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(surf)
		if arr.size() <= Mesh.ARRAY_WEIGHTS:
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty() or arr[Mesh.ARRAY_BONES] == null or arr[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := int(bones.size() / float(verts.size()))
		if per <= 0:
			continue
		var step := maxi(1, int(verts.size() / 2500.0))
		for vi in range(0, verts.size(), step):
			var best := -1
			var best_w := -1.0
			for k in per:
				if weights[vi * per + k] > best_w:
					best_w = weights[vi * per + k]
					best = bones[vi * per + k]
			var bone := best
			if sk != null and best >= 0 and best < sk.get_bind_count():
				bone = sk.get_bind_bone(best)
				if bone < 0:
					bone = _skeleton.find_bone(sk.get_bind_name(best))
			if bone < 0 or bone >= _seg_of_bone.size() or _seg_of_bone[bone] < 0:
				continue
			var si := _seg_of_bone[bone]
			if not acc.has(si):
				acc[si] = []
			(acc[si] as Array).append(xf * verts[vi] - (body.segments[si] as BodyDef.Seg).pivot)
	for si2 in acc:
		var pts: PackedVector3Array = _vis_points.get(si2, PackedVector3Array())
		pts.append_array(PackedVector3Array(acc[si2] as Array))
		_vis_points[si2] = pts


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


func _find_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_meshes(c))
	return out


## Stylized fallback: smooth primitive per shape, coloured by body part.
func _build_fallback() -> void:
	var primary := _palette("primary", Color(0.85, 0.55, 0.3))
	var secondary := _palette("secondary", primary.darkened(0.25))
	var accent := _palette("accent", Color(0.95, 0.85, 0.7))
	var part_colors := {"core": primary, "head": primary.lightened(0.08), "arm": secondary, "leg": secondary,
		"tail": secondary, "wing": accent, "shell": accent.darkened(0.2), "horn": accent, "fin": accent}
	var seg_colors: Dictionary = creature.art.get("segment_colors", {})
	for s: BodyDef.Seg in body.segments:
		var holder := Node3D.new()
		holder.name = s.id
		add_child(holder)
		_seg_nodes.append(holder)
		var col: Color = part_colors.get(s.part, primary)
		if seg_colors.has(s.id):
			col = Color.from_string(str(seg_colors[s.id]), col)
		var mat := _make_material(col)
		for sh: BodyDef.Shape in s.shapes:
			var mi := MeshInstance3D.new()
			match sh.type:
				BodyDef.SHAPE_CAPSULE:
					var seg_len := sh.a.distance_to(sh.b)
					if seg_len < 0.005:
						var sp := SphereMesh.new()
						sp.radius = sh.radius
						sp.height = sh.radius * 2.0
						mi.mesh = sp
						mi.position = sh.a
					else:
						var cap := CapsuleMesh.new()
						cap.radius = sh.radius
						cap.height = seg_len + sh.radius * 2.0
						cap.radial_segments = 20
						cap.rings = 6
						mi.mesh = cap
						mi.transform = Transform3D(Basis(MathX.rotation_between(Vector3.UP, sh.b - sh.a)), (sh.a + sh.b) * 0.5)
				BodyDef.SHAPE_SPHERE:
					var sp2 := SphereMesh.new()
					sp2.radius = sh.radius
					sp2.height = sh.radius * 2.0
					sp2.radial_segments = 24
					sp2.rings = 12
					mi.mesh = sp2
					mi.position = sh.a
				BodyDef.SHAPE_BOX:
					var bx := BoxMesh.new()
					bx.size = sh.size
					mi.mesh = bx
					mi.position = sh.a
			mi.material_override = mat
			holder.add_child(mi)
		if s.part == "head":
			_add_eyes(holder, s)


func _add_eyes(holder: Node3D, s: BodyDef.Seg) -> void:
	var sh: BodyDef.Shape = s.shapes[0]
	var r := sh.radius
	var white := Materials.toon(Color(0.98, 0.97, 0.94), 0.4, 0.0, 0.0)
	var pupil := Materials.toon(Color(0.06, 0.05, 0.08), 0.2, 0.0, 0.0)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = r * 0.28
		em.height = r * 0.56
		eye.mesh = em
		eye.material_override = white
		eye.position = sh.a + Vector3(side * r * 0.38, r * 0.18, r * 0.82)
		holder.add_child(eye)
		var pu := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = r * 0.12
		pm.height = r * 0.24
		pu.mesh = pm
		pu.material_override = pupil
		pu.position = eye.position + Vector3(0, 0, r * 0.2)
		holder.add_child(pu)


## Called once per simulation tick with world transforms of every segment.
func push_transforms(xf: Array[Transform3D]) -> void:
	for i in xf.size():
		_prev[i] = _curr[i] if _curr[i] != Transform3D() else xf[i]
		_curr[i] = xf[i]


## Snap without interpolation (spawn / teleport).
func snap_transforms(xf: Array[Transform3D]) -> void:
	for i in xf.size():
		_prev[i] = xf[i]
		_curr[i] = xf[i]


func render(alpha: float) -> void:
	var n := _curr.size()
	if _skeleton:
		# Desired GLOBAL pose of every segment bone = the segment's interpolated world transform
		# (the skeleton sits at the world origin). Converted to parent-relative poses parents-first,
		# so both flat and nested bone layouts end up with the same world placement.
		for bi in _bone_order:
			var si := _seg_of_bone[bi]
			var parent := _skeleton.get_bone_parent(bi)
			var parent_global := _bone_global[parent] if parent >= 0 else Transform3D.IDENTITY
			var global: Transform3D
			if si >= 0 and si < n:
				var a := _prev[si]
				var b := _curr[si]
				global = Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), alpha)), a.origin.lerp(b.origin, alpha))
			else:
				global = parent_global * _skeleton.get_bone_rest(bi)
			_bone_global[bi] = global
			if si >= 0 and si < n:
				_seg_global[si] = global
			var local := parent_global.affine_inverse() * global
			_skeleton.set_bone_pose_position(bi, local.origin)
			_skeleton.set_bone_pose_rotation(bi, local.basis.get_rotation_quaternion())
	else:
		for i in n:
			var a := _prev[i]
			var b := _curr[i]
			var t := Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), alpha)), a.origin.lerp(b.origin, alpha))
			if i < _seg_nodes.size():
				_seg_nodes[i].global_transform = t
			_seg_global[i] = t
	_update_attachments()
	_update_materials()


func segment_world(i: int) -> Transform3D:
	return _curr[i] if i < _curr.size() else Transform3D()


# ---- cosmetics (view-only) ---------------------------------------------------------------------

## items: [{kind: tooth|lid|belt|scarf, color, accent, id}] (FighterCosmetics.attachments). Replaces
## whatever was attached; kinds this body has no place for are skipped.
func set_cosmetics(items: Array) -> void:
	for a in _attachments:
		var old: Node3D = a["node"]
		if is_instance_valid(old):
			old.queue_free()
	_attachments.clear()
	for it in items:
		var d: Dictionary = it
		var kind := str(d.get("kind", ""))
		var anc := CosmeticAttachments.anchor(creature, kind, _vis_points)
		if anc.is_empty():
			continue
		var xf: Transform3D = anc["xf"]
		var node := CosmeticAttachments.build(kind, d, float(anc["size"]), xf.basis, anc.get("radii", Vector2.ZERO))
		node.set_meta("cosmetic_id", str(d.get("id", kind)))
		add_child(node)
		_attachments.append({"node": node, "seg": int(anc["seg"]), "local": Transform3D(Basis.IDENTITY, xf.origin), "kind": kind,
			"id": str(d.get("id", kind)), "walkout": CosmeticAttachments.WALKOUT_ONLY.has(kind), "popped": false})
	_update_attachments()


## The attached cosmetic entries (inspection/tests): [{node, seg, kind, id, walkout, popped}].
func cosmetics() -> Array:
	return _attachments


## The JUICE glow colour and the glowing surfaces' colour shift (alpha = amount; 0 keeps the model's).
func set_juice_style(juice: Color, glow := Color(1, 1, 1, 0)) -> void:
	juice_color = Color(juice.r, juice.g, juice.b, 1.0)
	glow_color = glow
	for m in _materials:
		m.set_shader_parameter("juice_color", juice_color)
		m.set_shader_parameter("glow_color", glow_color)


func _update_attachments() -> void:
	for a in _attachments:
		var node: Node3D = a["node"]
		if not is_instance_valid(node):
			continue
		var si := int(a["seg"])
		node.visible = not bool(a["popped"]) and not (cosmetic_combat and bool(a["walkout"])) and visible_alpha > 0.0
		if si < _seg_global.size() and _seg_global[si] != Transform3D():
			node.global_transform = _seg_global[si] * (a["local"] as Transform3D)
		elif si < _curr.size() and _curr[si] != Transform3D():
			node.global_transform = _curr[si] * (a["local"] as Transform3D)


func flash(amount := 1.0) -> void:
	_flash = maxf(_flash, amount)


func add_bruise(seg: int, world_point: Vector3, strength: float) -> void:
	if seg < 0 or seg >= _curr.size():
		return
	var local := _curr[seg].affine_inverse() * world_point
	for b in _bruises:
		if b["seg"] == seg and (b["local"] as Vector3).distance_to(local) < 0.07:
			b["s"] = minf(1.0, float(b["s"]) + strength * 0.5)
			return
	_bruises.append({"seg": seg, "local": local, "s": clampf(strength, 0.15, 1.0)})
	if _bruises.size() > MAX_BRUISES:
		_bruises.sort_custom(func(x, y): return x["s"] > y["s"])
		_bruises.resize(MAX_BRUISES)


func clear_bruises() -> void:
	_bruises.clear()
	detached = false
	for a in _attachments:
		a["popped"] = false


func _update_materials() -> void:
	var dt := get_process_delta_time()
	_flash = maxf(0.0, _flash - dt * 6.0)
	var arr: Array[Vector4] = []
	arr.resize(MAX_BRUISES)
	for i in MAX_BRUISES:
		if i < _bruises.size() and gore_level > 0:
			var b: Dictionary = _bruises[i]
			var p: Vector3 = _curr[int(b["seg"])] * (b["local"] as Vector3)
			arr[i] = Vector4(p.x, p.y, p.z, float(b["s"]))
		else:
			arr[i] = Vector4.ZERO
	for m in _materials:
		m.set_shader_parameter("flash", _flash)
		m.set_shader_parameter("juice", juice_amount)
		m.set_shader_parameter("status_color", status_color)
		m.set_shader_parameter("bruises", arr)
	# ART_DIRECTION §4: emissive accents run 0.3 at 0 Hype -> 1.0 at 100 Hype (full while juiced)
	var glow := 0.3 + 0.7 * clampf(maxf(hype, juice_amount), 0.0, 1.0)
	for g in _glow_materials:
		g.set_shader_parameter("vertex_glow", glow)


## The cosmetic end-of-fight gag: a creature-specific piece pops off and bounces away.
## Purely visual (debris layer); never affects the simulation.
func detach_piece(impulse_dir: Vector3) -> RigidBody3D:
	if detached or gore_level < 2:
		return null
	detached = true
	for a in _attachments:
		if str(a["kind"]) == "tooth" and is_instance_valid(a["node"]):
			return _pop_gold_tooth(a, impulse_dir)
	var g: Dictionary = creature.art.get("gore_piece", {})
	var seg_id := str(g.get("segment", "head"))
	var si: int = body.seg_index.get(seg_id, 0)
	var xf := _curr[si]
	var piece := RigidBody3D.new()
	piece.collision_layer = Rig.LAYER_DEBRIS
	piece.collision_mask = Rig.LAYER_WORLD
	piece.mass = 0.3
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	var size := float(g.get("size", 0.06))
	sp.radius = size
	cs.shape = sp
	piece.add_child(cs)
	var mi := MeshInstance3D.new()
	if _gore_mesh != null:
		# the forged piece (vertex-coloured, modelled per creature: tooth, claw tip, feathers...)
		mi.mesh = _gore_mesh
		var pm := Materials.creature_material()
		pm.set_shader_parameter("tint", Color.WHITE)
		pm.set_shader_parameter("roughness_v", 0.35)
		pm.next_pass = Materials.outline_material(float(creature.art.get("outline", 0.012)) * 0.6)
		mi.material_override = pm
	else:
		match str(g.get("shape", "tooth")):
			"horn", "spike":
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.0
				cyl.bottom_radius = size
				cyl.height = size * 3.0
				mi.mesh = cyl
			_:
				var bm := BoxMesh.new()
				bm.size = Vector3(size, size * 1.4, size * 0.9)
				mi.mesh = bm
		mi.material_override = Materials.toon(Color.from_string(str(g.get("color", "#f4efe2")), Color.WHITE), 0.3)
	piece.add_child(mi)
	get_parent().add_child(piece)
	piece.global_position = xf * MathX.vec3(g.get("offset", [0, 0, 0.1]))
	piece.linear_velocity = impulse_dir.normalized() * 4.0 + Vector3.UP * 3.5
	piece.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(piece.queue_free)
	return piece


## With the gold tooth on, the gag piece IS the gold tooth: it pops out of the mouth (debris layer,
## never touches the simulation) and the attached one disappears until the next round.
func _pop_gold_tooth(a: Dictionary, impulse_dir: Vector3) -> RigidBody3D:
	var node: Node3D = a["node"]
	a["popped"] = true
	var piece := RigidBody3D.new()
	piece.name = "GoldTooth"
	piece.collision_layer = Rig.LAYER_DEBRIS
	piece.collision_mask = Rig.LAYER_WORLD
	piece.mass = 0.3
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.04
	cs.shape = sp
	piece.add_child(cs)
	var copy := node.duplicate() as Node3D
	piece.add_child(copy)
	copy.transform = Transform3D.IDENTITY
	get_parent().add_child(piece)
	piece.global_transform = node.global_transform
	node.visible = false
	piece.linear_velocity = impulse_dir.normalized() * 4.0 + Vector3.UP * 3.5
	piece.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(piece.queue_free)
	return piece
