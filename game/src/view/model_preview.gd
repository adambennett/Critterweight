extends SceneTree
## Forge model preview / inspection (docs/ART_PIPELINE.md). Runs as a standalone SceneTree script:
##
##   godot --headless --path game --script res://src/view/model_preview.gd -- --inspect res://assets/models/creatures/f_stoke.glb
##   godot --path game --script res://src/view/model_preview.gd -- --models a.glb,b.glb [--spacing 1.4] [--yaw 30]
##         [--creatures res://content/core/creatures/f_stoke.json,...] [--hype 0..1] [--detach] --capture out.png
##
## --inspect prints the imported scene tree, skeleton bones (name, parent, rest translation),
## mesh surfaces and materials. The windowed mode lines the models up on a floor under the
## arena-style lighting, posed in their rest pose (or their creature's stance height when a
## creature JSON is given), and saves a capture after a few frames.

var _args: PackedStringArray
var _frames := 0
var _capture := ""
var _detach_views: Array[CreatureView] = []


func _init() -> void:
	_args = OS.get_cmdline_user_args()
	if _args.has("--inspect"):
		_inspect(_arg("--inspect", ""))
		quit(0)
		return
	_build_preview()


func _arg(flag: String, fallback: String) -> String:
	var i := _args.find(flag)
	if i >= 0 and i + 1 < _args.size():
		return _args[i + 1]
	return fallback


func _load_scene(path: String) -> PackedScene:
	if path.begins_with("res://"):
		return load(path) as PackedScene
	return ModelLoader.load_gltf_scene(path)


func _inspect(path: String) -> void:
	var ps := _load_scene(path)
	if ps == null:
		print("INSPECT: could not load ", path)
		return
	var inst := ps.instantiate()
	print("INSPECT ", path)
	_dump(inst, 0)
	inst.free()


func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var line := "%s%s (%s)" % [pad, n.name, n.get_class()]
	if n is Node3D:
		line += " t=%s" % [str((n as Node3D).transform.origin)]
	print(line)
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		for b in sk.get_bone_count():
			print("%s  bone %d '%s' parent=%d rest=%s" % [pad, b, sk.get_bone_name(b), sk.get_bone_parent(b), str(sk.get_bone_rest(b).origin)])
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				var arrays := mi.mesh.surface_get_arrays(s)
				var vcount := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var icount := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
				var has_col := arrays[Mesh.ARRAY_COLOR] != null
				var has_bones := arrays[Mesh.ARRAY_BONES] != null
				var mname := m.resource_name if m else "<none>"
				var extra := ""
				if m is BaseMaterial3D:
					var bm := m as BaseMaterial3D
					extra = " rough=%.2f metal=%.2f emis=%s vcol=%s" % [bm.roughness, bm.metallic, bm.emission_enabled, bm.vertex_color_use_as_albedo]
				print("%s  surface %d mat='%s' verts=%d tris=%d colors=%s bones=%s%s" % [pad, s, mname, vcount, icount / 3, has_col, has_bones, extra])
		print("%s  skin=%s skeleton=%s" % [pad, mi.skin != null, str(mi.skeleton)])
	for c in n.get_children():
		_dump(c, depth + 1)


func _build_preview() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	# environment + lights (same recipe as ArenaView "can" theme)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#1a1d28")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#3a3f52")
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	e.glow_enabled = true
	e.glow_intensity = 0.4
	env.environment = e
	root_node.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#ffe9cf")
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-55, 35, 0)
	root_node.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#35c1c9")
	fill.light_energy = 0.4
	fill.rotation_degrees = Vector3(-20, 200, 0)
	root_node.add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = Materials.toon(Color("#d6cfc2"), 0.9, 0.0, 0.0)
	root_node.add_child(floor_mi)
	# models
	var models := _arg("--models", "").split(",", false)
	var creatures := _arg("--creatures", "").split(",", false)
	var spacing := float(_arg("--spacing", "1.6"))
	var yaw := deg_to_rad(float(_arg("--yaw", "25")))
	var n := maxi(models.size(), creatures.size())
	var total_w := spacing * (n - 1)
	var max_h := 1.0
	for i in n:
		var holder := Node3D.new()
		holder.position = Vector3(-total_w * 0.5 + i * spacing, 0, 0)
		holder.rotation = Vector3(0, yaw, 0)
		root_node.add_child(holder)
		if i < creatures.size():
			var c := CreatureDef.load_json(creatures[i])
			if c.is_valid():
				var v := CreatureView.new()
				holder.add_child(v)
				v.setup(c, Color("#ff5a5a") if i % 2 == 0 else Color("#4da3ff"))
				var xf: Array[Transform3D] = []
				for s: BodyDef.Seg in c.body.segments:
					xf.append(Transform3D(Basis.IDENTITY, s.pivot))
				v.snap_transforms(xf)
				v.render(1.0)
				v.hype = float(_arg("--hype", "0"))
				if _args.has("--detach"):
					_detach_views.append(v)
				max_h = maxf(max_h, c.body.height)
				continue
			print("preview: invalid creature ", creatures[i], " ", c.errors)
		if i < models.size():
			var ps := _load_scene(models[i])
			if ps:
				var inst := ps.instantiate()
				holder.add_child(inst)
				var aabb := _scene_aabb(inst)
				max_h = maxf(max_h, aabb.end.y)
				for mi in _meshes(inst):
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			else:
				print("preview: could not load ", models[i])
	var cam := Camera3D.new()
	var dist := maxf(total_w * 0.8, max_h * 1.9) + 1.6
	cam.fov = 40
	root_node.add_child(cam)
	cam.look_at_from_position(Vector3(0.2, max_h * 0.62, dist), Vector3(0, max_h * 0.46, 0))
	cam.current = true
	_capture = _arg("--capture", "")


func _scene_aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(n):
		# transform relative to the model root (nodes may not be inside the tree yet)
		var xf := Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != n:
			if walk is Node3D:
				xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		var b := xf * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		# --detach: pop every creature's forged gore piece (KO gag) so it shows in the capture
		for v in _detach_views:
			var piece := v.detach_piece(Vector3(0.6, 0, 1))
			if piece:
				piece.linear_velocity = Vector3(0.3, 1.2, 0.8)
				piece.angular_velocity = Vector3(2, 3, 1)
	if _frames == 12 and _capture != "":
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_capture)
		print("CAPTURED ", _capture, " ", img.get_size())
		quit(0)
	elif _frames > 400:
		quit(0)
	return false
