class_name ArenaSetDressing
## Per-base structures and backdrops (ARENAS.md §2): The Gullet's eight-sided cage in the gutted
## cannery hall (Day / Night / Title Night), Drydock's concrete pit with the crane and harbour,
## The Crusher's compactor pit with the magnet gantry and scrapyard, The Rooftop's open roof with
## the neon sign and the bay below. Everything is procedural (ArenaMeshKit + arena shaders) and
## purely cosmetic; animated parts are returned in `out` for ArenaView to drive from sim state.

const PERSON_PALETTE := [Color("#7a5cff"), Color("#ff6b6b"), Color("#ffd166"), Color("#06d6a0"), Color("#4cc9f0"), Color("#f72585"), Color("#adb5bd"), Color("#c9a227")]

static var _person: ArrayMesh


static func person_mesh() -> ArrayMesh:
	if _person:
		return _person
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := CapsuleMesh.new()
	body.radius = 0.24
	body.height = 0.95
	body.radial_segments = 8
	body.rings = 2
	st.append_from(body, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.48, 0)))
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.34
	head.radial_segments = 8
	head.rings = 4
	st.append_from(head, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0)))
	var arm := CapsuleMesh.new()
	arm.radius = 0.07
	arm.height = 0.5
	arm.radial_segments = 6
	arm.rings = 1
	st.append_from(arm, 0, Transform3D(Basis(Vector3.FORWARD, 0.5), Vector3(-0.28, 0.72, 0)))
	st.append_from(arm, 0, Transform3D(Basis(Vector3.FORWARD, -0.5), Vector3(0.28, 0.72, 0)))
	_person = st.commit()
	return _person


## Crowd silhouettes (MultiMesh, crowd shader energy bounce). placements: [[pos, yaw, scale], ...]
static func crowd(parent: Node3D, placements: Array, rim: Color, seed := 1234, dim := 0.7) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = person_mesh()
	mm.instance_count = placements.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in placements.size():
		var p: Array = placements[i]
		var s: float = float(p[2]) * rng.randf_range(0.85, 1.1)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(p[1])).scaled(Vector3(s, s, s)), p[0]))
		var c: Color = PERSON_PALETTE[rng.randi() % PERSON_PALETTE.size()]
		mm.set_instance_color(i, c.darkened(rng.randf_range(dim - 0.1, dim + 0.12)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var cm := ShaderMaterial.new()
	cm.shader = load("res://src/view/shaders/crowd.gdshader")
	cm.set_shader_parameter("rim", rim)
	mi.material_override = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Box truss between two points (four chords + zig-zag lacing), radius ~ size/2.
static func truss(parent: Node3D, a: Vector3, b: Vector3, size: float, mat: Material) -> void:
	var dir := (b - a)
	var len := dir.length()
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var h := size * 0.5
	var offs := [side * h + up * h, side * h - up * h, -side * h - up * h, -side * h + up * h]
	for o in offs:
		ArenaMeshKit.add(parent, ArenaMeshKit.tube(PackedVector3Array([a + o, b + o]), 0.05, 6), mat)
	var steps := maxi(2, int(len / size))
	for k in steps:
		var p0 := a + dir * len * float(k) / steps
		var p1 := a + dir * len * float(k + 1) / steps
		for j in 4:
			var o0: Vector3 = offs[j]
			var o1: Vector3 = offs[(j + 1) % 4]
			ArenaMeshKit.add(parent, ArenaMeshKit.tube(PackedVector3Array([p0 + o0, p1 + o1]), 0.025, 4), mat, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)


static func _c(v: Dictionary, key: String, fallback: String) -> Color:
	return Color.from_string(str(v.get(key, fallback)), Color(fallback))


# =====================================================================================
# THE GULLET
# =====================================================================================

static func build_gullet(parent: Node3D, a: ArenaDef, v: Dictionary, out: Dictionary) -> void:
	var poly := a.boundary_polygon()
	var r := a.radius
	var title := bool(v.get("pyro", false))
	var green := Color("#8BD426")
	var gold := Color("#C9A227")
	var steel := ArenaPropVisuals.paint(Color("#5B6168"), 0.4, 0.75)
	var pad_g := ArenaPropVisuals.toon(green, 0.5, 0.0, 0.3)
	var pad_gold := ArenaPropVisuals.toon(gold, 0.35, 0.5, 0.35)
	# apron platform + gold trim + steps
	var apron := Geometry2D.offset_polygon(poly, 1.3)
	if not apron.is_empty():
		var am := ArenaMeshKit.slab(apron[0], -0.03, -1.0)
		var ami := ArenaMeshKit.add(parent, am, ArenaPropVisuals.toon(Color("#1D2140"), 0.6, 0.0, 0.1), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		ami.set_surface_override_material(1, ArenaPropVisuals.toon(Color("#151834"), 0.7))
		var trim := MeshInstance3D.new()
		trim.mesh = ArenaMeshKit.outline_band(apron[0], 0.0, 0.12, -0.02)
		trim.material_override = pad_gold
		parent.add_child(trim)
		var step := Geometry2D.offset_polygon(poly, 2.3)
		if not step.is_empty():
			ArenaMeshKit.add(parent, ArenaMeshKit.slab(step[0], -0.5, -1.0), ArenaPropVisuals.toon(Color("#151834"), 0.7), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	# centre drain (cosmetic)
	ArenaMeshKit.add(parent, ArenaMeshKit.cylinder(0.28, 0.3, 0.02, 24, 0.005), ArenaPropVisuals.toon(Color("#3A3A42"), 0.4, 0.7), Vector3(0, 0.005, 0))
	for k in 6:
		ArenaMeshKit.box(parent, Vector3(0.36, 0.012, 0.035), ArenaPropVisuals.toon(Color("#121316"), 0.9), Vector3(0, 0.018, -0.15 + 0.06 * k), Vector3.ZERO, 0.003)
	# cage: posts, padded rails, chain-link panels, sponsor boards on alternate panels
	var h := a.wall_height
	var fence := ArenaPropVisuals.fence_mat(Color("#9AA0AA"))
	for i in poly.size():
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var mid := (p0 + p1) * 0.5
		var len := p0.distance_to(p1)
		var ang := atan2(p1.y - p0.y, p1.x - p0.x)
		var outward := Vector2(mid.x, mid.y).normalized()
		var q := QuadMesh.new()
		q.size = Vector2(len - 0.3, h - 0.15)
		var fm := ArenaMeshKit.add(parent, q, fence, Vector3(mid.x, h * 0.5 + 0.04, mid.y), Vector3(0, -ang, 0))
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var rail := ArenaMeshKit.tube(PackedVector3Array([Vector3(p0.x, 0, p0.y), Vector3(p1.x, 0, p1.y)]), 0.09, 10)
		ArenaMeshKit.add(parent, rail, pad_g, Vector3(0, h + 0.02, 0))
		ArenaMeshKit.add(parent, ArenaMeshKit.tube(PackedVector3Array([Vector3(p0.x, 0, p0.y), Vector3(p1.x, 0, p1.y)]), 0.045, 8), steel, Vector3(0, 0.12, 0))
		# gold stripes on the padded rail
		for f in [0.33, 0.66]:
			var sp := p0.lerp(p1, f)
			ArenaMeshKit.add(parent, ArenaMeshKit.cylinder(0.1, 0.1, 0.16, 12, 0.01), pad_gold, Vector3(sp.x, h + 0.02, sp.y), Vector3(0, -ang, PI * 0.5))
		# post with pads and cap
		ArenaMeshKit.add(parent, ArenaMeshKit.cylinder(0.17, 0.19, h + 0.3, 18, 0.03), pad_g, Vector3(p0.x, (h + 0.3) * 0.5, p0.y))
		for yy in [0.35, h * 0.55, h + 0.1]:
			ArenaMeshKit.add(parent, ArenaMeshKit.cylinder(0.2, 0.2, 0.12, 18, 0.02), pad_gold, Vector3(p0.x, yy, p0.y))
		ArenaMeshKit.add(parent, ArenaMeshKit.cylinder(0.12, 0.2, 0.14, 18, 0.03), ArenaPropVisuals.toon(Color("#1A1D24"), 0.4, 0.5), Vector3(p0.x, h + 0.37, p0.y))
		if i % 2 == 0:
			var board_pos := mid + outward * 0.2
			var sp_def: Array = ArenaPropVisuals.SPONSORS[int(i * 0.5) % ArenaPropVisuals.SPONSORS.size()]
			var board := ArenaPropVisuals.paint(Color(str(sp_def[1])), 0.6, 0.1)
			ArenaMeshKit.box(parent, Vector3(len - 0.8, 0.85, 0.08), board, Vector3(board_pos.x, 0.55, board_pos.y), Vector3(0, -ang, 0), 0.02)
			ArenaMeshKit.box(parent, Vector3(len - 0.7, 0.08, 0.12), ArenaPropVisuals.toon(Color("#2B2F3A"), 0.5, 0.5), Vector3(board_pos.x, 1.0, board_pos.y), Vector3(0, -ang, 0), 0.02)
			var face := -outward
			ArenaMeshKit.label(parent, str(sp_def[0]), 120, Color(str(sp_def[2])), Vector3(board_pos.x + face.x * 0.045, 0.55, board_pos.y + face.y * 0.045), Vector3(0, atan2(face.x, face.y), 0), Color(0, 0, 0, 0), "res://assets/fonts/BarlowCondensed-900.woff2", 0.0045)
		if title:
			# confetti cannons and pyro jets on every other post
			if i % 2 == 1:
				ArenaMeshKit.add(parent, ArenaMeshKit.cylinder(0.1, 0.14, 0.35, 12, 0.02), pad_gold, Vector3(p0.x, h + 0.62, p0.y), Vector3(0.3 * cos(atan2(p0.y, p0.x)), 0, -0.3 * sin(atan2(p0.y, p0.x))))
				out["confetti"].append(_confetti(parent, Vector3(p0.x, h + 0.85, p0.y)))
			else:
				out["pyro"].append(_pyro(parent, Vector3(p0.x, h + 0.5, p0.y)))
	# bleachers rising into the fog + crowd
	var bleacher := ArenaPropVisuals.surface(1, Color("#2A2830"), Color("#232129"), Color("#18161C"), {"cell": Vector2(3, 3)})
	var rows := 8
	var placements := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for row in rows:
		var rad := r + 4.6 + row * 1.05
		var y_top := -0.45 + row * 0.6
		var tier := MeshInstance3D.new()
		tier.mesh = _annulus(rad - 0.52, rad + 0.53, y_top, -1.2, 64)
		tier.material_override = bleacher
		parent.add_child(tier)
		var n := int(TAU * rad / 0.66)
		for k in n:
			if rng.randf() < 0.12:
				continue
			var ang2 := TAU * k / n + rng.randf() * 0.04
			var pos := Vector3(cos(ang2) * rad, y_top, sin(ang2) * rad)
			placements.append([pos, -ang2 - PI * 0.5 + PI, rng.randf_range(0.75, 0.95)])
	out["crowd"] = crowd(parent, placements, _c(v, "rim", "#35C1C9"), 1234, 0.72)
	# rusted trusses with light banks over the cage
	var rust := ArenaPropVisuals.paint(Color("#8C3B2B"), 0.7, 0.5, Color("#4A2218"))
	var span := r + 6.0
	for k2 in 2:
		var z := (-1.0 if k2 == 0 else 1.0) * (r * 0.62)
		truss(parent, Vector3(-span, 8.2, z), Vector3(span, 8.2, z), 0.7, rust)
		truss(parent, Vector3(z, 8.9, -span), Vector3(z, 8.9, span), 0.7, rust)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var bank := Node3D.new()
			bank.position = Vector3(sx * r * 0.62, 7.7, sz * r * 0.62)
			parent.add_child(bank)
			ArenaMeshKit.box(bank, Vector3(1.4, 0.5, 0.9), ArenaPropVisuals.toon(Color("#1A1D24"), 0.5, 0.6), Vector3.ZERO, Vector3(0.5 * sz, 0, -0.5 * sx), 0.06)
			for j in 3:
				ArenaMeshKit.add(bank, ArenaMeshKit.cylinder(0.17, 0.17, 0.08, 14, 0.01), ArenaPropVisuals.glow(_c(v, "spot", "#FFF1DA"), 4.0), Vector3(-0.42 + 0.42 * j, -0.26, 0), Vector3(0.5 * sz, 0, -0.5 * sx), Vector3.ONE, false)
	# hanging cannery hooks far above (sway in ArenaView)
	var hook_mat := ArenaPropVisuals.toon(Color("#3A3A42"), 0.4, 0.8)
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 5
	for k3 in 12:
		var ang3 := hrng.randf() * TAU
		var rad3 := hrng.randf_range(r + 1.5, r + 8.0)
		var top_y := 16.0
		var low_y := hrng.randf_range(10.0, 13.5)
		var hook := Node3D.new()
		hook.position = Vector3(cos(ang3) * rad3, top_y, sin(ang3) * rad3)
		parent.add_child(hook)
		ArenaMeshKit.add(hook, ArenaMeshKit.tube(PackedVector3Array([Vector3.ZERO, Vector3(0, low_y - top_y, 0)]), 0.03, 5), hook_mat, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		var tm := TorusMesh.new()
		tm.inner_radius = 0.16
		tm.outer_radius = 0.22
		ArenaMeshKit.add(hook, tm, hook_mat, Vector3(0, low_y - top_y - 0.2, 0), Vector3(PI * 0.5, 0, 0), Vector3.ONE, false)
		out["hooks"].append(hook)
	# gutted hall walls with tall windows (sunbeams in the Day variant)
	var hall_r := r + 15.0
	var brick := ArenaPropVisuals.surface(6, Color("#4A2E26"), Color("#5A3A2E"), Color("#2A1E1A"), {"use_uv": true})
	for k4 in 12:
		var a4 := TAU * k4 / 12.0
		var seg_len := 2.0 * hall_r * tan(PI / 12.0) + 0.2
		var wall := ArenaMeshKit.add(parent, ArenaMeshKit.chamfer_box(Vector3(seg_len, 22.0, 0.8), 0.05), brick, Vector3(cos(a4) * hall_r, 9.0, sin(a4) * hall_r), Vector3(0, -a4 + PI * 0.5, 0), Vector3.ONE, false)
		wall.name = "HallWall%d" % k4
		for w in 2:
			var wy := 12.0
			var off := (-1.0 if w == 0 else 1.0) * seg_len * 0.22
			var wp := Vector3(cos(a4) * (hall_r - 0.42), wy, sin(a4) * (hall_r - 0.42)) + Vector3(-sin(a4), 0, cos(a4)) * off
			var win := ArenaPropVisuals.glow(Color("#FFE2B0") if bool(v.get("sunbeams", false)) else Color("#2A3550"), 2.4 if bool(v.get("sunbeams", false)) else 0.6)
			ArenaMeshKit.box(parent, Vector3(1.6, 5.0, 0.1), win, wp, Vector3(0, -a4 + PI * 0.5, 0), 0.01)
	if bool(v.get("sunbeams", false)):
		var beam := StandardMaterial3D.new()
		beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		beam.albedo_color = Color(1.0, 0.82, 0.55, 0.07)
		beam.cull_mode = BaseMaterial3D.CULL_DISABLED
		for k5 in 5:
			var a5 := -0.6 + k5 * 0.32
			var start := Vector3(cos(a5) * hall_r, 12.0, sin(a5) * hall_r)
			var end := Vector3(cos(a5) * 2.0, 0.0, sin(a5) * 2.0)
			var mid2 := (start + end) * 0.5
			var shaft := MeshInstance3D.new()
			shaft.mesh = ArenaMeshKit.chamfer_box(Vector3(1.4, start.distance_to(end), 3.2), 0.0)
			shaft.material_override = beam
			shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(shaft)
			shaft.look_at_from_position(mid2, end, Vector3.UP)
			shaft.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	# ceiling darkness
	var ceil := MeshInstance3D.new()
	ceil.mesh = ArenaMeshKit.floor_disc(hall_r + 1.0, 24)
	ceil.material_override = ArenaPropVisuals.toon(Color("#120F14"), 1.0)
	ceil.position = Vector3(0, 20.0, 0)
	ceil.rotation = Vector3(PI, 0, 0)
	parent.add_child(ceil)
	# outer floor
	ArenaMeshKit.add(parent, ArenaMeshKit.floor_disc(hall_r + 2.0, 32), ArenaPropVisuals.surface(1, Color("#2A2620"), Color("#24211C"), Color("#1A1714"), {"cell": Vector2(4, 4)}), Vector3(0, -1.2, 0), Vector3.ZERO, Vector3.ONE, false)


static func _confetti(parent: Node3D, pos: Vector3) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = 120
	gp.lifetime = 2.6
	gp.one_shot = true
	gp.explosiveness = 0.92
	gp.emitting = false
	gp.local_coords = false
	gp.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color("#C9A227"))
	grad.add_point(0.33, Color("#8BD426"))
	grad.add_point(0.66, Color("#F2F2EC"))
	grad.set_color(grad.get_point_count() - 1, Color("#E04FB0"))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_initial_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.11)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	gp.draw_pass_1 = q
	parent.add_child(gp)
	return gp


static func _pyro(parent: Node3D, pos: Vector3) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = 90
	gp.lifetime = 0.9
	gp.one_shot = true
	gp.explosiveness = 0.3
	gp.emitting = false
	gp.local_coords = false
	gp.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3(0, 1.0, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.scale_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.6, 1.0))
	grad.set_color(1, Color(1.0, 0.35, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	gp.draw_pass_1 = q
	parent.add_child(gp)
	return gp


## Hollow ring (top face + inner wall) between radii r0..r1 from y_top down to y_bottom.
static func _annulus(r0: float, r1: float, y_top: float, y_bottom: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		ArenaMeshKit._quad(st, d0 * r0 + Vector3.UP * y_top, d1 * r0 + Vector3.UP * y_top, d1 * r1 + Vector3.UP * y_top, d0 * r1 + Vector3.UP * y_top, Vector3.UP)
		ArenaMeshKit._quad(st, d0 * r0 + Vector3.UP * y_top, d1 * r0 + Vector3.UP * y_top, d1 * r0 + Vector3.UP * y_bottom, d0 * r0 + Vector3.UP * y_bottom, -d0)
	return st.commit()


# =====================================================================================
# DRYDOCK
# =====================================================================================

static func build_drydock(parent: Node3D, a: ArenaDef, v: Dictionary, out: Dictionary) -> void:
	var ext := a.extent()
	var wall_h := a.wall_height
	var conc := ArenaPropVisuals.surface(1, Color("#A3A39B"), Color("#8E8E86"), Color("#6E5A4A"), {"use_uv": true, "cell": Vector2(2.0, 2.0)})
	var conc_top := ArenaPropVisuals.surface(1, Color("#8C8B84"), Color("#7C7B74"), Color("#5E4E40"), {"cell": Vector2(3.0, 3.0)})
	# gutter channel trims, grates and water
	for h in a.hazard_defs():
		if str(h.get("type", "")) != "tidal_gutter":
			continue
		var rect := a.strip_rect(h)
		var trim := ArenaPropVisuals.toon(Color("#4A4F57"), 0.45, 0.7)
		for zz in [rect.position.y, rect.end.y]:
			ArenaMeshKit.box(parent, Vector3(rect.size.x, 0.05, 0.1), trim, Vector3(rect.get_center().x, 0.02, zz), Vector3.ZERO, 0.01)
		ArenaMeshKit.add(parent, ArenaMeshKit.floor_quad(rect.size - Vector2(0.0, 0.1)), ArenaPropVisuals.surface(1, Color("#5E625F"), Color("#53574F"), Color("#3E3A30"), {"cell": Vector2(1.5, 1.5), "wet": 0.8}), Vector3(rect.get_center().x, 0.004, rect.get_center().y), Vector3.ZERO, Vector3.ONE, false)
		for xx in [rect.position.x + 0.5, rect.end.x - 0.5]:
			for k in 5:
				ArenaMeshKit.box(parent, Vector3(0.06, 0.03, rect.size.y - 0.2), ArenaPropVisuals.toon(Color("#2B2F3A"), 0.4, 0.7), Vector3(xx - 0.24 + 0.12 * k, 0.015, rect.get_center().y), Vector3.ZERO, 0.005)
		var wm := ShaderMaterial.new()
		wm.shader = load("res://src/view/shaders/arena_water.gdshader")
		wm.set_shader_parameter("half_size", rect.size * 0.5)
		var water := ArenaMeshKit.add(parent, ArenaMeshKit.floor_quad(rect.size - Vector2(0.05, 0.06)), wm, Vector3(rect.get_center().x, -0.2, rect.get_center().y), Vector3.ZERO, Vector3.ONE, false)
		out["gutter_water"] = water
		out["gutter_mat"] = wm
	# wet planks along the long walls
	for ar in a.areas():
		if str(ar["type"]) != "wet_planks":
			continue
		var r: Rect2 = ar["rect"]
		var planks := ArenaPropVisuals.surface(4, Color("#6B4F3A"), Color("#5A4130"), Color.BLACK, {"wet": 0.75})
		ArenaMeshKit.add(parent, ArenaMeshKit.chamfer_box(Vector3(r.size.x, 0.03, r.size.y), 0.008), planks, Vector3(r.get_center().x, 0.015, r.get_center().y), Vector3.ZERO, Vector3.ONE, false)
		for k2 in int(r.size.x / 2.0) + 1:
			ArenaMeshKit.box(parent, Vector3(0.08, 0.04, r.size.y), ArenaPropVisuals.toon(Color("#3E2E22"), 0.8), Vector3(r.position.x + k2 * 2.0, 0.02, r.get_center().y), Vector3.ZERO, 0.01)
	# concrete pit walls (2 m) with tide line, ladders, chain fence on top
	var thick := 0.7
	for e in a.boundary_edges():
		var ea: Vector2 = e["a"]
		var eb: Vector2 = e["b"]
		var n: Vector2 = e["n"]
		var t := (eb - ea).normalized()
		var len := ea.distance_to(eb) + thick * 2.0
		var mid := (ea + eb) * 0.5 + n * thick * 0.5
		var yaw := atan2(-t.y, t.x)
		ArenaMeshKit.add(parent, ArenaMeshKit.chamfer_box(Vector3(len, wall_h + 1.0, thick), 0.06), conc, Vector3(mid.x, (wall_h - 1.0) * 0.5, mid.y), Vector3(0, yaw, 0))
		ArenaMeshKit.box(parent, Vector3(len - thick * 2.0, 0.35, 0.03), ArenaPropVisuals.toon(Color("#5C625A"), 0.4), Vector3((ea + eb).x * 0.5 - n.x * 0.005, 0.5, (ea + eb).y * 0.5 - n.y * 0.005), Vector3(0, yaw, 0), 0.005)
		# ladders
		var lad := ArenaPropVisuals.toon(Color("#C9A227"), 0.5, 0.5)
		for f in [0.25, 0.75]:
			var lp := ea.lerp(eb, f) - n * 0.08
			for side in [-0.25, 0.25]:
				var sp: Vector2 = lp + t * float(side)
				ArenaMeshKit.add(parent, ArenaMeshKit.tube(PackedVector3Array([Vector3(sp.x, 0.0, sp.y), Vector3(sp.x, wall_h + 0.6, sp.y)]), 0.025, 6), lad)
			for k3 in 6:
				var yy := 0.3 + k3 * 0.35
				ArenaMeshKit.add(parent, ArenaMeshKit.tube(PackedVector3Array([Vector3(lp.x - t.x * 0.25, yy, lp.y - t.y * 0.25), Vector3(lp.x + t.x * 0.25, yy, lp.y + t.y * 0.25)]), 0.02, 5), lad)
		# fence on the top
		var ftop := ea + n * 0.25
		var fend := eb + n * 0.25
		var q := QuadMesh.new()
		q.size = Vector2(ea.distance_to(eb), 1.2)
		ArenaMeshKit.add(parent, q, ArenaPropVisuals.fence_mat(Color("#8F969E")), Vector3((ftop.x + fend.x) * 0.5, wall_h + 0.6, (ftop.y + fend.y) * 0.5), Vector3(0, yaw, 0))
		ArenaMeshKit.add(parent, ArenaMeshKit.tube(PackedVector3Array([Vector3(ftop.x, wall_h + 1.2, ftop.y), Vector3(fend.x, wall_h + 1.2, fend.y)]), 0.04, 6), ArenaPropVisuals.toon(Color("#5B6168"), 0.4, 0.7))
		var posts := int(ea.distance_to(eb) / 2.0) + 1
		for k4 in posts:
			var pp := ftop.lerp(fend, float(k4) / float(maxi(1, posts - 1)))
			ArenaMeshKit.add(parent, ArenaMeshKit.tube(PackedVector3Array([Vector3(pp.x, wall_h, pp.y), Vector3(pp.x, wall_h + 1.25, pp.y)]), 0.04, 6), ArenaPropVisuals.toon(Color("#5B6168"), 0.4, 0.7))
	# dock deck around the pit (yellow edge paint) with crowd leaning on the rail
	var deck_poly := Geometry2D.offset_polygon(a.boundary_polygon(), 9.0, Geometry2D.JOIN_SQUARE)
	var deck_hole := Geometry2D.offset_polygon(a.boundary_polygon(), 0.05, Geometry2D.JOIN_SQUARE)
	if not deck_poly.is_empty() and not deck_hole.is_empty():
		_slab_with_holes(parent, deck_poly[0], deck_hole[0], wall_h, conc_top)
	var edge_paint := MeshInstance3D.new()
	edge_paint.mesh = ArenaMeshKit.outline_band(Geometry2D.offset_polygon(a.boundary_polygon(), 1.1, Geometry2D.JOIN_SQUARE)[0], 0.0, 0.25, wall_h + 0.005)
	edge_paint.material_override = ArenaPropVisuals.toon(Color("#E0B42A"), 0.6)
	parent.add_child(edge_paint)
	var placements := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for side in [-1.0, 1.0]:
		var z: float = float(side) * (ext.size.y * 0.5 + 1.0)
		var x := ext.position.x + 0.5
		while x < ext.end.x - 0.5:
			if rng.randf() > 0.2:
				placements.append([Vector3(x + rng.randf_range(-0.15, 0.15), wall_h, z + side * rng.randf_range(0.0, 1.4)), 0.0 if side < 0 else PI, rng.randf_range(0.85, 1.0)])
			x += rng.randf_range(0.55, 0.85)
	for side2 in [-1.0, 1.0]:
		var x2: float = float(side2) * (ext.size.x * 0.5 + 1.0)
		var z2 := ext.position.y + 1.0
		while z2 < ext.end.y - 1.0:
			if rng.randf() > 0.45:
				placements.append([Vector3(x2 + side2 * rng.randf_range(0.0, 1.0), wall_h, z2), -PI * 0.5 * side2 + PI, rng.randf_range(0.85, 1.0)])
			z2 += rng.randf_range(0.6, 1.0)
	out["crowd"] = crowd(parent, placements, _c(v, "rim", "#C9D3D8"), 99, 0.55)
	# containers and dock clutter on the deck
	var cont_cols := [Color("#3E5C76"), Color("#8C3B2B"), Color("#5E8C8A"), Color("#B89A3E")]
	for k5 in 6:
		var ang := -0.5 + 0.5 * float(k5 % 3) + (PI if k5 >= 3 else 0.0)
		var cpos := Vector3(cos(ang) * (ext.size.x * 0.5 + 6.5), wall_h, sin(ang) * (ext.size.y * 0.5 + 6.5))
		var cm := ArenaPropVisuals.surface(5, cont_cols[k5 % 4], cont_cols[k5 % 4], Color("#5E3426"), {"use_uv": true, "cell": Vector2(0.6, 2.6)})
		ArenaMeshKit.box(parent, Vector3(6.0, 2.6, 2.4), cm, cpos + Vector3(0, 1.3, 0), Vector3(0, ang + PI * 0.5, 0), 0.04)
		if k5 % 2 == 0:
			ArenaMeshKit.box(parent, Vector3(6.0, 2.6, 2.4), ArenaPropVisuals.surface(5, cont_cols[(k5 + 1) % 4], cont_cols[(k5 + 1) % 4], Color("#5E3426"), {"use_uv": true, "cell": Vector2(0.6, 2.6)}), cpos + Vector3(0, 3.9, 0), Vector3(0, ang + PI * 0.5 + 0.08, 0), 0.04)
	# crane: lattice boom reaching over the hook spot
	var crane_spot := Vector2.ZERO
	for h2 in a.hazard_defs():
		if str(h2.get("type", "")) == "crane_hook":
			var spots: Array = h2.get("spots", [])
			if not spots.is_empty():
				crane_spot = spots[0]
	var yellow := ArenaPropVisuals.paint(Color("#D9A520"), 0.55, 0.4, Color("#7A3E2A"))
	var base_pos := Vector3(crane_spot.x - 3.0, wall_h, ext.end.y + 4.5)
	ArenaMeshKit.box(parent, Vector3(2.4, 1.2, 2.4), ArenaPropVisuals.toon(Color("#2B2F3A"), 0.5, 0.5), base_pos + Vector3(0, 0.6, 0), Vector3.ZERO, 0.08)
	truss(parent, base_pos + Vector3(0, 1.2, 0), base_pos + Vector3(0, 9.0, 0), 1.0, yellow)
	ArenaMeshKit.box(parent, Vector3(2.0, 1.6, 2.6), yellow, base_pos + Vector3(0, 9.8, 0), Vector3.ZERO, 0.1)
	var tip := Vector3(crane_spot.x, 9.6, crane_spot.y)
	truss(parent, base_pos + Vector3(0, 10.2, 0), tip, 0.75, yellow)
	truss(parent, base_pos + Vector3(0, 10.2, 0), base_pos + Vector3(0.0, 10.6, 3.5), 0.6, yellow)
	ArenaMeshKit.box(parent, Vector3(1.6, 1.2, 1.4), ArenaPropVisuals.toon(Color("#5B6168"), 0.4, 0.6), base_pos + Vector3(0, 10.4, 3.6), Vector3.ZERO, 0.06)
	var hook := Node3D.new()
	hook.name = "CraneHook"
	hook.position = Vector3(tip.x, 7.0, tip.z)
	parent.add_child(hook)
	var iron := ArenaPropVisuals.toon(Color("#2B2F3A"), 0.35, 0.8)
	ArenaMeshKit.box(hook, Vector3(0.5, 0.45, 0.32), ArenaPropVisuals.paint(Color("#D9A520"), 0.5, 0.4), Vector3(0, 0.4, 0), Vector3.ZERO, 0.05)
	var ht := TorusMesh.new()
	ht.inner_radius = 0.18
	ht.outer_radius = 0.28
	ArenaMeshKit.add(hook, ht, iron, Vector3(0, -0.05, 0), Vector3(PI * 0.5, 0, 0), Vector3(1, 1, 1.4))
	var cable := MeshInstance3D.new()
	cable.mesh = ArenaMeshKit.cylinder(0.025, 0.025, 1.0, 6, 0.0, false)
	cable.material_override = iron
	parent.add_child(cable)
	var spot := SpotLight3D.new()
	spot.light_color = Color("#FFF2C8")
	spot.light_energy = 0.0
	spot.spot_range = 12.0
	spot.spot_angle = 12.0
	spot.position = tip + Vector3(0, -0.3, 0)
	spot.rotation = Vector3(-PI * 0.5, 0, 0)
	spot.shadow_enabled = false
	parent.add_child(spot)
	out["crane"] = {"hook": hook, "cable": cable, "tip": tip, "spot": spot, "rest_y": 7.0}
	# harbour water around the dock, distant cranes
	var harbour := ShaderMaterial.new()
	harbour.shader = load("res://src/view/shaders/arena_water.gdshader")
	harbour.set_shader_parameter("ripple_scale", 0.6)
	harbour.set_shader_parameter("speed", 0.5)
	harbour.set_shader_parameter("deep", Color("#2C4B5C"))
	harbour.set_shader_parameter("shallow", Color("#46707F"))
	harbour.set_shader_parameter("opacity", 1.0)
	ArenaMeshKit.add(parent, ArenaMeshKit.floor_quad(Vector2(240, 240)), harbour, Vector3(0, -1.5, 0), Vector3.ZERO, Vector3.ONE, false)
	var dark := ArenaPropVisuals.toon(Color("#5E6970"), 0.8)
	for k6 in 3:
		var bx := -40.0 + k6 * 38.0
		truss(parent, Vector3(bx, -1.5, -55.0), Vector3(bx, 22.0, -55.0), 2.2, dark)
		truss(parent, Vector3(bx - 6.0, 22.0, -55.0), Vector3(bx + 18.0, 24.0, -50.0), 1.6, dark)
	# gulls circling overhead
	var gull_mat := ArenaPropVisuals.toon(Color("#F2F2EC"), 0.7)
	for k7 in 5:
		var g := Node3D.new()
		g.position = Vector3(0, 11.0 + k7 * 1.3, 0)
		parent.add_child(g)
		for side3 in [-1.0, 1.0]:
			ArenaMeshKit.box(g, Vector3(0.45, 0.03, 0.12), gull_mat, Vector3(side3 * 0.2, 0.05, 0), Vector3(0, 0, side3 * 0.35), 0.01)
		ArenaMeshKit.box(g, Vector3(0.1, 0.08, 0.3), gull_mat, Vector3.ZERO, Vector3.ZERO, 0.03)
		g.set_meta("orbit", [4.0 + k7 * 1.7, 0.25 + 0.06 * k7, float(k7) * 1.3])
		out["gulls"].append(g)


## Concrete deck: polygon slab at height y with a rectangular hole (the pit).
static func _slab_with_holes(parent: Node3D, outer: PackedVector2Array, hole: PackedVector2Array, y: float, mat: Material) -> void:
	var r := Rect2(hole[0], Vector2.ZERO)
	for p in hole:
		r = r.expand(p)
	var ro := Rect2(outer[0], Vector2.ZERO)
	for p2 in outer:
		ro = ro.expand(p2)
	for piece in ArenaBuilder.subtract_rects(ro, [r]):
		var pr: Rect2 = piece
		var poly := PackedVector2Array([pr.position, Vector2(pr.end.x, pr.position.y), pr.end, Vector2(pr.position.x, pr.end.y)])
		ArenaMeshKit.add(parent, ArenaMeshKit.slab(poly, y, y - 0.6), mat, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)


# =====================================================================================
# THE CRUSHER
# =====================================================================================

static func build_crusher(parent: Node3D, a: ArenaDef, v: Dictionary, out: Dictionary) -> void:
	var ext := a.extent()
	var wall_h := a.wall_height
	var plate := ArenaPropVisuals.surface(5, Color("#4F555C"), Color("#4F555C"), Color("#7A3E2A"), {"use_uv": true, "cell": Vector2(2.0, 1.5)})
	var stripe := ArenaPropVisuals.surface(10, Color.WHITE, Color.WHITE, Color.WHITE, {"seam_a": Color("#F7E04A"), "seam_b": Color("#1E1E24")})
	var dark := ArenaPropVisuals.toon(Color("#25272C"), 0.5, 0.6)
	var thick := 0.6
	var edges := a.boundary_edges()
	for e in edges:
		var ea: Vector2 = e["a"]
		var eb: Vector2 = e["b"]
		var n: Vector2 = e["n"]
		var t := (eb - ea).normalized()
		var len := ea.distance_to(eb) + thick * 2.0
		var mid := (ea + eb) * 0.5 + n * thick * 0.5
		var yaw := atan2(-t.y, t.x)
		ArenaMeshKit.add(parent, ArenaMeshKit.chamfer_box(Vector3(len, wall_h, thick), 0.05), plate, Vector3(mid.x, wall_h * 0.5, mid.y), Vector3(0, yaw, 0))
		var band_mid := (ea + eb) * 0.5 + n * 0.02
		ArenaMeshKit.add(parent, ArenaMeshKit.chamfer_box(Vector3(len - thick * 2.0, 0.28, 0.06), 0.01), stripe, Vector3(band_mid.x, wall_h - 0.2, band_mid.y), Vector3(0, yaw, 0))
		ArenaMeshKit.add(parent, ArenaMeshKit.chamfer_box(Vector3(len, 0.18, thick + 0.12), 0.03), dark, Vector3(mid.x, wall_h + 0.09, mid.y), Vector3(0, yaw, 0))
		# vertical ribs on the inside face
		for k in int(ea.distance_to(eb) / 2.0):
			var rp := ea.lerp(eb, (float(k) + 0.5) / float(int(ea.distance_to(eb) / 2.0))) + n * 0.03
			ArenaMeshKit.box(parent, Vector3(0.14, wall_h - 0.5, 0.1), dark, Vector3(rp.x, wall_h * 0.5 - 0.1, rp.y), Vector3(0, yaw, 0), 0.02)
	# hydraulic rams behind the east and west plates
	for sx in [-1.0, 1.0]:
		var outer_face: float = ext.size.x * 0.5 + thick
		for z in [-2.5, 2.5]:
			ArenaMeshKit.add(parent, ArenaMeshKit.cylinder(0.45, 0.45, 3.4, 20, 0.05), ArenaPropVisuals.paint(Color("#C9A227"), 0.45, 0.4), Vector3(float(sx) * (outer_face + 1.95), wall_h * 0.55, z), Vector3(0, 0, PI * 0.5))
			ArenaMeshKit.add(parent, ArenaMeshKit.cylinder(0.22, 0.22, 0.3, 14, 0.03), ArenaPropVisuals.toon(Color("#C8CCD2"), 0.2, 0.9), Vector3(float(sx) * (outer_face + 0.12), wall_h * 0.55, z), Vector3(0, 0, PI * 0.5))
			ArenaMeshKit.box(parent, Vector3(0.12, 1.1, 1.1), ArenaPropVisuals.toon(Color("#25272C"), 0.5, 0.6), Vector3(float(sx) * (outer_face + 0.05), wall_h * 0.55, z), Vector3.ZERO, 0.03)
	# yard ground around the pit (at the top of the walls) and crushed-car stacks
	var yard := ArenaPropVisuals.surface(1, Color("#3A3632"), Color("#34302C"), Color("#5E3426"), {"cell": Vector2(4, 4)})
	_slab_with_holes(parent, Geometry2D.offset_polygon(a.boundary_polygon(), 22.0, Geometry2D.JOIN_SQUARE)[0], Geometry2D.offset_polygon(a.boundary_polygon(), thick, Geometry2D.JOIN_SQUARE)[0], wall_h, yard)
	var paints := [Color("#5E8C8A"), Color("#8C3B2B"), Color("#B89A3E"), Color("#6E6A66"), Color("#3E5C76"), Color("#7A4B6E")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for k2 in 14:
		var ang := TAU * k2 / 14.0 + rng.randf() * 0.2
		var dist := ext.size.x * 0.5 + 3.5 + rng.randf() * 5.0
		var base := Vector3(cos(ang) * dist, wall_h, sin(ang) * dist)
		var layers := rng.randi_range(1, 3)
		for l in layers:
			var col: Color = paints[rng.randi() % paints.size()]
			ArenaMeshKit.box(parent, Vector3(2.0, 0.9, 1.4), ArenaPropVisuals.paint(col, 0.6, 0.4), base + Vector3(rng.randf_range(-0.15, 0.15), 0.45 + l * 0.9, rng.randf_range(-0.15, 0.15)), Vector3(0, ang + rng.randf_range(-0.3, 0.3), 0), 0.07)
	# sodium lamp poles at the corners
	var lamp_col := _c(v, "key", "#FFB347")
	for sx2 in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var pole := Vector3(sx2 * (ext.size.x * 0.5 + 1.6), wall_h, sz * (ext.size.y * 0.5 + 1.6))
			ArenaMeshKit.add(parent, ArenaMeshKit.cylinder(0.1, 0.14, 7.5, 10, 0.02), dark, pole + Vector3(0, 3.75, 0))
			ArenaMeshKit.add(parent, ArenaMeshKit.tube(PackedVector3Array([pole + Vector3(0, 7.4, 0), pole + Vector3(-sx2 * 1.2, 7.7, -sz * 1.2)]), 0.06, 6), dark)
			ArenaMeshKit.box(parent, Vector3(0.7, 0.22, 0.4), dark, pole + Vector3(-sx2 * 1.3, 7.6, -sz * 1.3), Vector3(0, atan2(sx2, sz), 0), 0.04)
			ArenaMeshKit.add(parent, ArenaMeshKit.floor_quad(Vector2(0.55, 0.3)), ArenaPropVisuals.glow(lamp_col, 4.0), pole + Vector3(-sx2 * 1.3, 7.48, -sz * 1.3), Vector3(PI, atan2(sx2, sz), 0), Vector3.ONE, false)
	# magnet gantry: rails north/south, bridge (moves on x), trolley + magnet (moves on z)
	var rail_y := wall_h + 6.6
	var rail_mat := ArenaPropVisuals.paint(Color("#D9A520"), 0.5, 0.4, Color("#7A3E2A"))
	for sz2 in [-1.0, 1.0]:
		var rz: float = float(sz2) * (ext.size.y * 0.5 + 0.4)
		ArenaMeshKit.box(parent, Vector3(ext.size.x + 3.0, 0.5, 0.35), rail_mat, Vector3(0, rail_y, rz), Vector3.ZERO, 0.04)
		for sx3 in [-1.0, 1.0]:
			ArenaMeshKit.box(parent, Vector3(0.45, rail_y - wall_h, 0.45), rail_mat, Vector3(sx3 * (ext.size.x * 0.5 + 1.2), (rail_y + wall_h) * 0.5, rz), Vector3.ZERO, 0.04)
	var bridge := Node3D.new()
	bridge.name = "MagnetBridge"
	bridge.position = Vector3(0, rail_y + 0.4, 0)
	parent.add_child(bridge)
	ArenaMeshKit.box(bridge, Vector3(0.6, 0.6, ext.size.y + 1.4), rail_mat, Vector3.ZERO, Vector3.ZERO, 0.05)
	var trolley := Node3D.new()
	trolley.name = "Trolley"
	bridge.add_child(trolley)
	ArenaMeshKit.box(trolley, Vector3(1.2, 0.7, 1.0), ArenaPropVisuals.toon(Color("#3A3A42"), 0.5, 0.6), Vector3(0, -0.2, 0), Vector3.ZERO, 0.06)
	var magnet := Node3D.new()
	magnet.name = "Magnet"
	magnet.position = Vector3(0, -3.4, 0)
	trolley.add_child(magnet)
	ArenaMeshKit.add(magnet, ArenaMeshKit.cylinder(1.0, 1.05, 0.4, 28, 0.06), ArenaPropVisuals.toon(Color("#2B2F3A"), 0.4, 0.7), Vector3.ZERO)
	var coil := TorusMesh.new()
	coil.inner_radius = 0.92
	coil.outer_radius = 1.08
	var coil_mat := ArenaPropVisuals.glow(Color("#E04FB0"), 0.2).duplicate() as StandardMaterial3D
	ArenaMeshKit.add(magnet, coil, coil_mat, Vector3(0, -0.12, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	ArenaMeshKit.add(magnet, ArenaMeshKit.cylinder(0.3, 0.45, 0.35, 16, 0.04), ArenaPropVisuals.toon(Color("#B87333"), 0.3, 0.9), Vector3(0, 0.35, 0))
	var chains := MeshInstance3D.new()
	chains.mesh = ArenaMeshKit.cylinder(0.04, 0.04, 1.0, 6, 0.0, false)
	chains.material_override = ArenaPropVisuals.toon(Color("#3A3A42"), 0.4, 0.8)
	trolley.add_child(chains)
	var mlight := OmniLight3D.new()
	mlight.light_color = Color("#E04FB0")
	mlight.light_energy = 0.0
	mlight.omni_range = 5.0
	mlight.position = Vector3(0, -0.6, 0)
	magnet.add_child(mlight)
	# parked over the east edge between drops so it never hangs over the fight
	var rest := Vector2(ext.size.x * 0.5 + 0.6, 0.0)
	bridge.position.x = rest.x
	out["magnet"] = {"bridge": bridge, "trolley": trolley, "magnet": magnet, "chains": chains, "glow": coil_mat, "light": mlight, "rest": rest, "rail_y": rail_y}
	# the stray dog's silhouette on the north rim
	var dog := Node3D.new()
	dog.position = Vector3(2.8, wall_h + 0.18, ext.end.y + 1.0)
	dog.rotation.y = 0.4
	parent.add_child(dog)
	var fur := ArenaPropVisuals.toon(Color("#17161A"), 0.9)
	ArenaMeshKit.box(dog, Vector3(0.8, 0.32, 0.3), fur, Vector3(0, 0.42, 0), Vector3.ZERO, 0.1)
	ArenaMeshKit.box(dog, Vector3(0.28, 0.26, 0.24), fur, Vector3(0.48, 0.66, 0), Vector3(0, 0, 0.3), 0.08)
	ArenaMeshKit.box(dog, Vector3(0.1, 0.16, 0.06), fur, Vector3(0.52, 0.84, 0.07), Vector3(0, 0, 0.2), 0.02)
	for lx in [-0.3, 0.3]:
		for lz in [-0.1, 0.1]:
			ArenaMeshKit.box(dog, Vector3(0.08, 0.32, 0.08), fur, Vector3(lx, 0.16, lz), Vector3.ZERO, 0.02)
	ArenaMeshKit.box(dog, Vector3(0.36, 0.06, 0.06), fur, Vector3(-0.5, 0.6, 0), Vector3(0, 0, 0.7), 0.02)
	# perimeter fence far out
	var fence := ArenaPropVisuals.fence_mat(Color("#6F767E"))
	for k3 in 4:
		var ang2 := TAU * k3 / 4.0
		var q := QuadMesh.new()
		q.size = Vector2(40.0, 3.0)
		ArenaMeshKit.add(parent, q, fence, Vector3(cos(ang2) * 18.0, wall_h + 1.5, sin(ang2) * 18.0), Vector3(0, -ang2 + PI * 0.5, 0))
	out["crowd"] = crowd(parent, _rim_crowd(ext, wall_h, 2.0, 31, 0.35), _c(v, "rim", "#E04FB0"), 31, 0.75)


static func _rim_crowd(ext: Rect2, y: float, out_dist: float, seed: int, density: float) -> Array:
	var placements := []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for side in 4:
		var len := ext.size.x if side < 2 else ext.size.y
		var k := 0.0
		while k < len:
			if rng.randf() < density:
				var pos := Vector3.ZERO
				var yaw := 0.0
				match side:
					0:
						pos = Vector3(ext.position.x + k, y, ext.position.y - out_dist - rng.randf() * 1.5)
						yaw = 0.0
					1:
						pos = Vector3(ext.position.x + k, y, ext.end.y + out_dist + rng.randf() * 1.5)
						yaw = PI
					2:
						pos = Vector3(ext.position.x - out_dist - rng.randf() * 1.5, y, ext.position.y + k)
						yaw = PI * 0.5
					3:
						pos = Vector3(ext.end.x + out_dist + rng.randf() * 1.5, y, ext.position.y + k)
						yaw = -PI * 0.5
				placements.append([pos, yaw, rng.randf_range(0.85, 1.0)])
			k += rng.randf_range(0.6, 1.1)
	return placements


# =====================================================================================
# THE ROOFTOP
# =====================================================================================

static func build_rooftop(parent: Node3D, a: ArenaDef, v: Dictionary, out: Dictionary) -> void:
	var poly := a.boundary_polygon()
	var ext := a.extent()
	# crumble lip: thick slab sides + broken chunks along the edge
	var lip := ArenaPropVisuals.surface(1, Color("#8E8A84"), Color("#7A766F"), Color("#4E3A30"), {"use_uv": true, "cell": Vector2(1.5, 1.5)})
	var side_mi := ArenaMeshKit.add(parent, ArenaMeshKit.slab(poly, -0.005, -0.45), lip, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	side_mi.set_surface_override_material(0, lip)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for i in poly.size():
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var len := p0.distance_to(p1)
		var dir := (p1 - p0) / maxf(len, 0.01)
		var nrm := Vector2(dir.y, -dir.x)
		if Geometry2D.is_point_in_polygon(p0.lerp(p1, 0.5) + nrm * 0.3, poly):
			nrm = -nrm
		var k := 0.3
		while k < len - 0.3:
			var c := p0 + dir * k + nrm * 0.12
			ArenaMeshKit.box(parent, Vector3(rng.randf_range(0.25, 0.6), rng.randf_range(0.2, 0.4), 0.22), lip, Vector3(c.x, -0.35 - rng.randf() * 0.15, c.y), Vector3(rng.randf() * 0.3, atan2(-dir.y, dir.x), rng.randf() * 0.3), 0.04)
			k += rng.randf_range(0.5, 1.4)
	# 0.2 m hazard stripe band along every edge
	var stripe := ArenaPropVisuals.surface(10, Color.WHITE, Color.WHITE, Color.WHITE, {"seam_a": Color("#F7E04A"), "seam_b": Color("#1E1E24")})
	var band := MeshInstance3D.new()
	band.mesh = ArenaMeshKit.outline_band(poly, 0.0, 0.2, 0.008)
	band.material_override = stripe
	parent.add_child(band)
	# the cannery facade dropping away below the roof
	var facade := ShaderMaterial.new()
	facade.shader = load("res://src/view/shaders/arena_city.gdshader")
	facade.set_shader_parameter("wall", Color("#3A2620"))
	facade.set_shader_parameter("lit_ratio", 0.16)
	facade.set_shader_parameter("glow", 0.9)
	facade.set_shader_parameter("window", Vector2(2.2, 3.2))
	var below := ArenaMeshKit.slab(poly, -0.45, -32.0)
	var bmi := ArenaMeshKit.add(parent, below, facade, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	bmi.set_surface_override_material(0, ArenaPropVisuals.toon(Color("#0A0A0C"), 1.0))
	# neon sign on scaffolding past the north edge
	var sign := Node3D.new()
	sign.name = "NeonSign"
	sign.position = Vector3(-1.0, 0.0, ext.end.y + 3.2)
	parent.add_child(sign)
	var scaffold := ArenaPropVisuals.toon(Color("#2B2F3A"), 0.5, 0.6)
	for x in [-5.0, -1.7, 1.7, 5.0]:
		ArenaMeshKit.add(sign, ArenaMeshKit.tube(PackedVector3Array([Vector3(x, -4.0, 0.4), Vector3(x, 6.6, 0.4)]), 0.07, 6), scaffold)
	for y in [2.0, 6.4]:
		ArenaMeshKit.add(sign, ArenaMeshKit.tube(PackedVector3Array([Vector3(-5.4, y, 0.4), Vector3(5.4, y, 0.4)]), 0.06, 6), scaffold)
	var neon_g := ArenaPropVisuals.neon(Color("#8BD426"), 3.2, 0.0, 1.0)
	var neon_p := ArenaPropVisuals.neon(Color("#E04FB0"), 3.5, 0.6, 2.0)
	out["neon"].append(neon_p)
	# one Label3D per letter: on a normal night the "A" is a dead tube ("GL NDCO" — it fell off and
	# lies on the Cannery's roof); the "night_neon" variant (variant.sign_full, unlocked by fixing
	# the sign in the Fight Camp hub) lights every letter and adds a neon border
	var full := bool(v.get("sign_full", false))
	var letters := Node3D.new()
	letters.name = "Letters"
	letters.position = Vector3(0.6, 4.3, 0.2)
	letters.rotation = Vector3(0, PI, 0)
	sign.add_child(letters)
	var lfont: Font = load("res://assets/fonts/BarlowCondensed-900.woff2")
	var word := "GLANDCO"
	var widths: Array[float] = []
	var total := 0.0
	for ch in word:
		var w := lfont.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 220).x * 0.012
		widths.append(w)
		total += w
	var x := -total * 0.5
	var letter_nodes: Array = []
	for i in word.length():
		var l := Label3D.new()
		l.name = "Letter%d_%s" % [i, word[i]]
		l.text = word[i]
		l.font = lfont
		l.font_size = 220
		l.pixel_size = 0.012
		var dead := i == 2 and not full
		l.modulate = Color(0.3, 0.1, 0.24) if dead else Color(2.2, 0.6, 1.6)
		l.outline_size = 18
		l.outline_modulate = Color(0.1, 0.03, 0.08) if dead else Color(0.7, 0.1, 0.4)
		l.position = Vector3(x + widths[i] * 0.5, 0, 0)
		l.shaded = false
		l.set_meta("lit", not dead)
		letters.add_child(l)
		letter_nodes.append(l)
		x += widths[i]
	out["sign_label"] = letters
	out["sign_letters"] = letter_nodes
	if full:
		var frame_pts := PackedVector3Array([Vector3(-total * 0.5 - 0.2, 5.25, 0.25), Vector3(total * 0.5 + 0.2, 5.25, 0.25),
			Vector3(total * 0.5 + 0.2, 3.45, 0.25), Vector3(-total * 0.5 - 0.2, 3.45, 0.25)])
		var border_mat := ArenaPropVisuals.neon(Color("#E04FB0"), 3.6, 0.0, 3.0)
		out["neon"].append(border_mat)
		var border := ArenaMeshKit.add(sign, ArenaMeshKit.tube(frame_pts, 0.06, 6, true), border_mat)
		border.name = "FullNeonBorder"
		border.position = Vector3(0.6, 0, 0)
	var sub := Label3D.new()
	sub.text = "JUICE  •  FEEL THE GLAND"
	sub.font = load("res://assets/fonts/BarlowCondensed-700.woff2")
	sub.font_size = 96
	sub.pixel_size = 0.01
	sub.modulate = Color(1.2, 2.2, 0.5)
	sub.outline_size = 10
	sub.outline_modulate = Color(0.2, 0.5, 0.05)
	sub.position = Vector3(0.6, 2.7, 0.2)
	sub.rotation = Vector3(0, PI, 0)
	sub.shaded = false
	sign.add_child(sub)
	# the neon drop logo
	var drop := PackedVector3Array()
	for k2 in 25:
		var t := TAU * k2 / 24.0
		var rr := 0.9
		var px := sin(t) * rr * (1.0 - 0.45 * cos(t))
		var py := -cos(t) * rr
		if t > PI * 0.8 and t < PI * 1.2:
			py = -rr - (0.6 - absf(t - PI) * 2.0)
		drop.append(Vector3(px - 4.2, py + 4.3, 0.3))
	ArenaMeshKit.add(sign, ArenaMeshKit.tube(drop, 0.07, 6, true), neon_g)
	var sign_light := OmniLight3D.new()
	sign_light.light_color = Color("#E04FB0")
	sign_light.light_energy = 3.2 if full else 2.2
	sign_light.omni_range = 11.0
	sign_light.position = Vector3(0, 4.0, -1.0)
	sign.add_child(sign_light)
	out["sign_light"] = sign_light
	# wind flags at the edge midpoints (point downwind on gusts)
	for side in ["n", "s", "e", "w"]:
		var e := a.edge_on_side(side)
		if e.is_empty():
			continue
		var m: Vector2 = ((e["a"] as Vector2) + (e["b"] as Vector2)) * 0.5 + (e["n"] as Vector2) * 0.35
		var pole := Node3D.new()
		pole.position = Vector3(m.x, 0, m.y)
		parent.add_child(pole)
		ArenaMeshKit.add(pole, ArenaMeshKit.cylinder(0.035, 0.05, 3.2, 8, 0.01), scaffold, Vector3(0, 1.6, 0))
		var flag := Node3D.new()
		flag.position = Vector3(0, 2.9, 0)
		pole.add_child(flag)
		var fq := QuadMesh.new()
		fq.size = Vector2(0.9, 0.5)
		var fm := ArenaPropVisuals.toon(Color("#8BD426") if side in ["n", "s"] else Color("#E04FB0"), 0.7)
		fm = fm.duplicate()
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		ArenaMeshKit.add(flag, fq, fm, Vector3(0.45, 0, 0))
		out["flags"].append(flag)
	# pigeons
	var pige := ArenaPropVisuals.toon(Color("#8E95A3"), 0.8)
	for pp in [Vector3(1.2, 1.05, 0.2), Vector3(1.45, 1.05, -0.3), Vector3(-6.9, 0.95, 3.0), Vector3(6.92, 0.95, -3.4)]:
		var bird := Node3D.new()
		bird.position = pp
		bird.rotation.y = rng.randf() * TAU
		parent.add_child(bird)
		ArenaMeshKit.add(bird, SphereMesh.new(), pige, Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(0.14, 0.12, 0.2))
		ArenaMeshKit.add(bird, SphereMesh.new(), pige, Vector3(0, 0.15, 0.08), Vector3.ZERO, Vector3(0.08, 0.08, 0.08))
		out["pigeons"].append(bird)
	# the next roof over: lawn-chair crowd
	var other := Vector3(ext.end.x + 9.5, -1.6, 0.0)
	ArenaMeshKit.add(parent, ArenaMeshKit.chamfer_box(Vector3(9.0, 0.6, 16.0), 0.05), ArenaPropVisuals.surface(3, Color("#2A2626"), Color("#5E5A56"), Color.BLACK), other + Vector3(0, -0.3, 0), Vector3.ZERO, Vector3.ONE, false)
	ArenaMeshKit.add(parent, ArenaMeshKit.chamfer_box(Vector3(9.0, 30.0, 16.0), 0.05), facade, other + Vector3(0, -15.6, 0), Vector3.ZERO, Vector3.ONE, false)
	var placements := []
	var chair := ArenaPropVisuals.toon(Color("#35C1C9"), 0.6)
	for k3 in 22:
		var cp := other + Vector3(-3.5 + (k3 % 4) * 1.4 + rng.randf() * 0.3, 0.0, -6.5 + int(k3 / 4.0) * 2.3)
		placements.append([cp + Vector3(0, 0.1, 0), -PI * 0.5, 0.85])
		ArenaMeshKit.box(parent, Vector3(0.6, 0.08, 0.55), chair, cp + Vector3(0, 0.35, 0), Vector3.ZERO, 0.02)
		ArenaMeshKit.box(parent, Vector3(0.08, 0.6, 0.55), chair, cp + Vector3(0.3, 0.6, 0), Vector3(0, 0, -0.3), 0.02)
	out["crowd"] = crowd(parent, placements, _c(v, "rim", "#E04FB0"), 55, 0.6)
	# the bay far below: glittering water + skyline
	var bay := ShaderMaterial.new()
	bay.shader = load("res://src/view/shaders/arena_water.gdshader")
	bay.set_shader_parameter("deep", Color("#06101C"))
	bay.set_shader_parameter("shallow", Color("#0E2236"))
	bay.set_shader_parameter("ripple_scale", 0.4)
	bay.set_shader_parameter("speed", 0.4)
	bay.set_shader_parameter("glitter", 1.0)
	bay.set_shader_parameter("opacity", 1.0)
	ArenaMeshKit.add(parent, ArenaMeshKit.floor_quad(Vector2(600, 600)), bay, Vector3(0, -32.0, 0), Vector3.ZERO, Vector3.ONE, false)
	# skyline across the bay: low enough that the roof stays the tallest thing nearby
	var city := ShaderMaterial.new()
	city.shader = load("res://src/view/shaders/arena_city.gdshader")
	city.set_shader_parameter("lit_ratio", 0.22)
	city.set_shader_parameter("glow", 1.4)
	city.set_shader_parameter("window", Vector2(2.2, 3.4))
	var crng := RandomNumberGenerator.new()
	crng.seed = 9
	for k4 in 52:
		var ang := k4 * TAU / 52.0 + crng.randf() * 0.05
		if absf(wrapf(ang - PI * 0.5, -PI, PI)) < 0.45:
			continue   # leave the view toward the neighbouring roof open
		var dist := crng.randf_range(150.0, 230.0)
		var hgt := crng.randf_range(14.0, 46.0)
		var w := crng.randf_range(10.0, 22.0)
		ArenaMeshKit.add(parent, ArenaMeshKit.chamfer_box(Vector3(w, hgt, w * 0.8), 0.0), city, Vector3(sin(ang) * dist, -40.0 + hgt * 0.5, cos(ang) * dist), Vector3(0, ang, 0), Vector3.ONE, false)


# =====================================================================================
# Shared floor material per style
# =====================================================================================

static func floor_material(a: ArenaDef, logo: Texture2D) -> Material:
	match a.style:
		"drydock":
			return ArenaPropVisuals.surface(1, Color("#A09F97"), Color("#8C8B83"), Color("#5E4E40"), {"cell": Vector2(2.0, 2.0), "grid_origin": Vector2(a.extent().position.x, a.extent().position.y), "wet": 0.15})
		"crusher":
			var e := a.extent()
			var g: Array = [3, 3]
			for h in a.base_hazards_all():
				if str(h.get("type", "")) == "plate_grid":
					g = h.get("grid", [3, 3])
			return ArenaPropVisuals.surface(2, Color("#5E656D"), Color.GRAY, Color("#7A3E2A"), {"cell": Vector2(e.size.x / float(g[0]), e.size.y / float(g[1])), "grid_origin": e.position, "seam": 0.26})
		"rooftop":
			return ArenaPropVisuals.surface(3, Color("#2F2B2B"), Color("#6E6A66"), Color.BLACK)
	var m := ArenaPropVisuals.surface(0, Color("#E9E2CF"), Color.GRAY, Color.BLACK, {"apothem": a.radius + 0.12 if a.shape == "octagon" else 0.0,
		"border": 0.42, "border_color": Color("#1D2140"), "stripe_color": Color("#8BD426"), "logo_size": a.radius * 1.15})
	m = m.duplicate()
	m.set_shader_parameter("logo", logo)
	return m
