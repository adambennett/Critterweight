class_name ArenaView
extends Node3D
## Visual side of an ArenaDef: themed floor/mat, fence or ropes, posts, apron, lighting rig,
## crowd, environment (HDR tonemapping, SSAO, glow, fog) and prop/hazard visuals.
## Graphics quality comes from Settings via apply_quality().

const THEMES := {
	"can": {"mat": "#d6cfc2", "line": "#b8322a", "apron": "#1d2140", "post": "#151219", "pad": "#c23a2b",
		"bg": "#0f0b14", "key": "#ffe9cf", "spot": "#cfe0ff", "crowd_rim": "#ff8a3d", "fence": "#9aa0aa"},
	"rooftop": {"mat": "#c9c2b6", "line": "#2a8fb8", "apron": "#2b2b33", "post": "#33333d", "pad": "#2a8fb8",
		"bg": "#2b3550", "key": "#ffd2a8", "spot": "#ffe6c0", "crowd_rim": "#7fb6ff", "fence": "#8f969e"},
	"scrapyard": {"mat": "#b8a98f", "line": "#e0a21c", "apron": "#3b2f25", "post": "#4a3b2c", "pad": "#e0a21c",
		"bg": "#1a140f", "key": "#ffd9a0", "spot": "#ffe2b0", "crowd_rim": "#ff6a2a", "fence": "#7d7468"},
	"sewer": {"mat": "#9fb0a4", "line": "#3fc27a", "apron": "#1b2a24", "post": "#1d2621", "pad": "#3fc27a",
		"bg": "#08110d", "key": "#d9ffe6", "spot": "#b8ffd8", "crowd_rim": "#3fc27a", "fence": "#6f8478"},
}

var arena: ArenaDef
var theme := {}
var env: WorldEnvironment
var key_light: DirectionalLight3D
var spots: Array[SpotLight3D] = []
var prop_nodes: Array[Node3D] = []
var hazard_nodes: Array[Node3D] = []
var _crowd: MultiMeshInstance3D
var _fence_mat: ShaderMaterial
var _logo_vp: SubViewport


func build(a: ArenaDef) -> void:
	arena = a
	name = "ArenaView"
	theme = THEMES.get(a.theme, THEMES["can"])
	_build_environment()
	_build_lights()
	_build_floor()
	if a.wall_height > 0.01:
		_build_fence()
	else:
		_build_platform_edge()
	_build_rig()
	_build_crowd()
	for p in a.props:
		prop_nodes.append(_build_prop(p))
	for h in a.hazards:
		hazard_nodes.append(_build_hazard(h))


func _c(key: String) -> Color:
	return Color.from_string(str(theme.get(key, "#ffffff")), Color.WHITE)


func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = _c("bg")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _c("bg").lightened(0.35)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.ssao_enabled = true
	e.ssao_radius = 0.9
	e.ssao_intensity = 1.6
	e.fog_enabled = true
	e.fog_light_color = _c("bg").lightened(0.15)
	e.fog_density = 0.012
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.05
	e.adjustment_saturation = 1.08
	env.environment = e
	add_child(env)


func _build_lights() -> void:
	key_light = DirectionalLight3D.new()
	key_light.light_color = _c("key")
	key_light.light_energy = 1.15
	key_light.shadow_enabled = true
	key_light.light_angular_distance = 1.5
	key_light.directional_shadow_max_distance = 26.0
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key_light.rotation_degrees = Vector3(-62, 28, 0)
	add_child(key_light)
	var fill := DirectionalLight3D.new()
	fill.light_color = _c("crowd_rim")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-18, 210, 0)
	add_child(fill)
	var r := arena.radius
	for i in 4:
		var s := SpotLight3D.new()
		var a := TAU * i / 4.0 + PI * 0.25
		s.position = Vector3(cos(a) * r * 0.9, 7.2, sin(a) * r * 0.9)
		s.look_at_from_position(s.position, Vector3(cos(a) * r * 0.15, 0, sin(a) * r * 0.15))
		s.light_color = _c("spot")
		s.light_energy = 5.5
		s.spot_range = 14.0
		s.spot_angle = 34.0
		s.spot_angle_attenuation = 0.6
		s.shadow_enabled = i < 2
		add_child(s)
		spots.append(s)


func _octagon_points(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var sides := 8
	match arena.base:
		"square":
			sides = 4
		"circle", "platform":
			sides = 40
	var circumradius := radius / cos(PI / sides) if arena.base in ["octagon", "square"] else radius
	for i in sides:
		var a := TAU * i / sides + (PI / sides if arena.base == "octagon" else (PI * 0.25 if arena.base == "square" else 0.0))
		pts.append(Vector2(cos(a), sin(a)) * circumradius)
	return pts


## Flat polygon (top at y) + vertical skirt down to y_bottom.
func _slab(pts: PackedVector2Array, y: float, y_bottom: float, mat_top: Material, mat_side: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		st.set_uv(Vector2.ZERO)
		st.add_vertex(Vector3(0, y, 0))
		st.add_vertex(Vector3(a.x, y, a.y))
		st.add_vertex(Vector3(b.x, y, b.y))
	var top := st.commit()
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var n := Vector3(a.x + b.x, 0, a.y + b.y).normalized()
		st2.set_normal(n)
		st2.add_vertex(Vector3(a.x, y, a.y))
		st2.add_vertex(Vector3(b.x, y_bottom, b.y))
		st2.add_vertex(Vector3(b.x, y, b.y))
		st2.add_vertex(Vector3(a.x, y, a.y))
		st2.add_vertex(Vector3(a.x, y_bottom, a.y))
		st2.add_vertex(Vector3(b.x, y_bottom, b.y))
	st2.commit(top)
	var mi := MeshInstance3D.new()
	mi.mesh = top
	mi.set_surface_override_material(0, mat_top)
	mi.set_surface_override_material(1, mat_side)
	add_child(mi)
	return mi


func _make_logo_texture() -> Texture2D:
	_logo_vp = SubViewport.new()
	_logo_vp.size = Vector2i(1024, 1024)
	_logo_vp.transparent_bg = true
	_logo_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_logo_vp)
	var root := Control.new()
	root.size = Vector2(1024, 1024)
	_logo_vp.add_child(root)
	var ring := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = _c("line")
	sb.set_border_width_all(28)
	sb.set_corner_radius_all(512)
	ring.add_theme_stylebox_override("panel", sb)
	ring.position = Vector2(64, 64)
	ring.size = Vector2(896, 896)
	root.add_child(ring)
	var title := Label.new()
	title.text = "CRITTERWEIGHT"
	title.add_theme_font_override("font", load("res://assets/fonts/BarlowCondensed-900.woff2"))
	title.add_theme_font_size_override("font_size", 150)
	title.add_theme_color_override("font_color", _c("line"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = Vector2(1024, 1024)
	title.rotation = 0.0
	root.add_child(title)
	var sub := Label.new()
	sub.text = "FERAL FIGHT NIGHT"
	sub.add_theme_font_override("font", load("res://assets/fonts/BarlowCondensed-700.woff2"))
	sub.add_theme_font_size_override("font_size", 64)
	sub.add_theme_color_override("font_color", _c("apron").lightened(0.1))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0, 600)
	sub.size = Vector2(1024, 100)
	root.add_child(sub)
	return _logo_vp.get_texture()


func _build_floor() -> void:
	var r := arena.radius
	# outside floor
	var outer := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	outer.mesh = pm
	outer.position = Vector3(0, -0.95, 0)
	outer.material_override = Materials.toon(_c("bg").lightened(0.08), 0.95, 0.0, 0.0)
	add_child(outer)
	# apron ring (slightly below the mat) and mat
	var apron_pts := _octagon_points(r + 0.9)
	_slab(apron_pts, -0.02, -0.95, Materials.toon(_c("apron"), 0.6, 0.0, 0.1), Materials.toon(_c("apron").darkened(0.35), 0.7))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/view/shaders/mat.gdshader")
	mat.set_shader_parameter("base_color", _c("mat"))
	mat.set_shader_parameter("line_color", _c("line"))
	mat.set_shader_parameter("apothem", r)
	mat.set_shader_parameter("logo", _make_logo_texture())
	mat.set_shader_parameter("logo_size", r * 0.9)
	_slab(_octagon_points(r + 0.12), 0.0, -0.05, mat, Materials.toon(_c("apron"), 0.7))


func _build_fence() -> void:
	var r := arena.radius
	var h := arena.wall_height
	var pts := _octagon_points(r + 0.12)
	_fence_mat = ShaderMaterial.new()
	_fence_mat.shader = load("res://src/view/shaders/fence.gdshader")
	_fence_mat.set_shader_parameter("wire_color", _c("fence"))
	var rail_mat := Materials.toon(_c("post"), 0.5, 0.1, 0.25)
	var pad_mat := Materials.toon(_c("pad"), 0.45, 0.0, 0.3)
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var len := a.distance_to(b)
		var mid := (a + b) * 0.5
		var ang := atan2(b.y - a.y, b.x - a.x)
		# chain link panel
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(len, h)
		q.mesh = qm
		q.material_override = _fence_mat
		q.position = Vector3(mid.x, h * 0.5, mid.y)
		q.rotation = Vector3(0, -ang, 0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(q)
		# padded top rail and bottom rail
		for y in [h, 0.12]:
			var rail := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.07 if y > 1.0 else 0.05
			cm.height = len + 0.1
			rail.mesh = cm
			rail.material_override = rail_mat
			rail.position = Vector3(mid.x, y, mid.y)
			rail.rotation = Vector3(0, -ang, PI * 0.5)
			add_child(rail)
		# post at vertex a
		if arena.base != "circle":
			var post := MeshInstance3D.new()
			var pc := CylinderMesh.new()
			pc.top_radius = 0.16
			pc.bottom_radius = 0.18
			pc.height = h + 0.25
			post.mesh = pc
			post.material_override = pad_mat
			post.position = Vector3(a.x, (h + 0.25) * 0.5, a.y)
			add_child(post)
			var cap := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.17
			sm.height = 0.2
			cap.mesh = sm
			cap.material_override = rail_mat
			cap.position = Vector3(a.x, h + 0.27, a.y)
			add_child(cap)


func _build_platform_edge() -> void:
	var r := arena.radius
	var edge := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.05
	tm.outer_radius = r + 0.12
	edge.mesh = tm
	edge.material_override = Materials.toon(_c("pad"), 0.4, 0.0, 0.4, _c("pad") * 0.3)
	edge.position = Vector3(0, 0.02, 0)
	edge.scale = Vector3(1, 0.4, 1)
	add_child(edge)


func _build_rig() -> void:
	var r := arena.radius + 0.6
	var truss_mat := Materials.toon(Color(0.12, 0.12, 0.14), 0.4, 0.7, 0.15)
	var lamp_mat := Materials.toon(Color(1, 0.97, 0.9), 0.2, 0.0, 0.0, Color(1.0, 0.95, 0.85))
	var pts := _octagon_points(r)
	for i in pts.size():
		if arena.base == "circle" or arena.base == "platform":
			if i % 5 != 0:
				continue
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var len := a.distance_to(b)
		var mid := (a + b) * 0.5
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(len, 0.25, 0.25)
		beam.mesh = bm
		beam.material_override = truss_mat
		beam.position = Vector3(mid.x, 7.6, mid.y)
		beam.rotation = Vector3(0, -atan2(b.y - a.y, b.x - a.x), 0)
		add_child(beam)
		var lamp := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.22
		lm.bottom_radius = 0.28
		lm.height = 0.35
		lamp.mesh = lm
		lamp.material_override = lamp_mat
		lamp.position = Vector3(mid.x, 7.35, mid.y)
		add_child(lamp)


func _build_crowd() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var fan := CapsuleMesh.new()
	fan.radius = 0.24
	fan.height = 0.9
	fan.radial_segments = 8
	fan.rings = 2
	mm.mesh = fan
	var count := 0
	var rows := 7
	var placements := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for row in rows:
		var rad := arena.radius + 4.4 + row * 1.0
		var n := int(TAU * rad / 0.62)
		for k in n:
			var a := TAU * k / n + rng.randf() * 0.03
			placements.append([Vector3(cos(a) * rad, -0.4 + row * 0.55, sin(a) * rad), a])
	count = placements.size()
	mm.instance_count = count
	var pal := [Color("#7a5cff"), Color("#ff6b6b"), Color("#ffd166"), Color("#06d6a0"), Color("#4cc9f0"), Color("#f72585"), Color("#adb5bd")]
	for i in count:
		var p: Vector3 = placements[i][0]
		var s := rng.randf_range(0.62, 0.95)
		var xf := Transform3D(Basis(Vector3.UP, -placements[i][1]).scaled(Vector3(s, s, s)), p + Vector3(0, 0.45 * s, 0))
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, (pal[rng.randi() % pal.size()] as Color).darkened(rng.randf_range(0.62, 0.85)))
	_crowd = MultiMeshInstance3D.new()
	_crowd.multimesh = mm
	var cm := ShaderMaterial.new()
	cm.shader = load("res://src/view/shaders/crowd.gdshader")
	cm.set_shader_parameter("rim", _c("crowd_rim"))
	_crowd.material_override = cm
	_crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crowd)
	# bleacher steps (annular tiers)
	var step_mat := Materials.toon(_c("bg").lightened(0.12), 0.9)
	for row in rows:
		var rad2 := arena.radius + 4.4 + row * 1.0
		var tier := MeshInstance3D.new()
		tier.mesh = _annulus(rad2 - 0.5, rad2 + 0.5, -0.95 + row * 0.55 + 0.55, -0.95, 64)
		tier.material_override = step_mat
		add_child(tier)


## Hollow ring (top face + inner/outer walls) between radii r0..r1, from y_top down to y_bottom.
func _annulus(r0: float, r1: float, y_top: float, y_bottom: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		st.set_normal(Vector3.UP)
		st.add_vertex(d0 * r0 + Vector3.UP * y_top)
		st.add_vertex(d1 * r1 + Vector3.UP * y_top)
		st.add_vertex(d0 * r1 + Vector3.UP * y_top)
		st.add_vertex(d0 * r0 + Vector3.UP * y_top)
		st.add_vertex(d1 * r0 + Vector3.UP * y_top)
		st.add_vertex(d1 * r1 + Vector3.UP * y_top)
		# inner wall faces the cage
		st.set_normal(-d0)
		st.add_vertex(d0 * r0 + Vector3.UP * y_top)
		st.add_vertex(d0 * r0 + Vector3.UP * y_bottom)
		st.add_vertex(d1 * r0 + Vector3.UP * y_bottom)
		st.add_vertex(d0 * r0 + Vector3.UP * y_top)
		st.add_vertex(d1 * r0 + Vector3.UP * y_bottom)
		st.add_vertex(d1 * r0 + Vector3.UP * y_top)
	return st.commit()


## Excitement 0..1 drives the crowd's bounce (from announcer/hype events).
func set_crowd_energy(v: float) -> void:
	if _crowd:
		(_crowd.material_override as ShaderMaterial).set_shader_parameter("energy", clampf(v, 0.0, 1.0))


func _build_prop(p: Dictionary) -> Node3D:
	var def: Dictionary = ArenaBuilder.PROP_TYPES.get(p["type"], {})
	var n := Node3D.new()
	n.name = "PropView_" + str(p["type"])
	add_child(n)
	if def.is_empty():
		return n
	var sc: float = p["scale"]
	var mi := MeshInstance3D.new()
	var colors := {"crate": Color("#a8743a"), "barrel": Color("#3b6ea8"), "pillar": Color("#6d6875"), "low_wall": Color("#8d8a86"),
		"bumper": Color("#ff5d8f"), "tire_stack": Color("#2a2a2e"), "turnbuckle": Color("#c23a2b"), "bench": Color("#7a5230")}
	var col: Color = colors.get(p["type"], Color.GRAY)
	var h := 1.0
	if def["shape"] == "box":
		var bm := BoxMesh.new()
		bm.size = MathX.vec3(def["size"]) * sc
		mi.mesh = bm
		h = bm.size.y
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = float(def["radius"]) * sc
		cm.bottom_radius = float(def["radius"]) * sc
		cm.height = float(def["height"]) * sc
		mi.mesh = cm
		h = cm.height
	var m := Materials.toon(col, 0.7, 0.0, 0.3)
	mi.material_override = m
	n.add_child(mi)
	var pp: Vector3 = p["pos"]
	n.transform = Transform3D(Basis(Vector3.UP, p["yaw"]), Vector3(pp.x, pp.y + h * 0.5, pp.z))
	return n


func _build_hazard(h: Dictionary) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var p: Vector3 = h["pos"]
	n.position = Vector3(p.x, 0.01, p.z)
	var r: float = h["radius"]
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.03
	cm.radial_segments = 32
	disc.mesh = cm
	var col := Color("#444")
	var emit := Color.BLACK
	match str(h["type"]):
		"fire_grate":
			col = Color("#2b2522")
			emit = Color("#ff5a1f") * 0.6
		"puddle":
			col = Color("#3a6f9a")
		"spring_pad":
			col = Color("#ffd166")
		"shock_plate":
			col = Color("#2a3550")
			emit = Color("#6ad0ff") * 0.5
	var m := Materials.toon(col, 0.2 if h["type"] == "puddle" else 0.6, 0.3, 0.2, emit)
	disc.material_override = m
	n.add_child(disc)
	var label := Label3D.new()
	label.text = str(h["type"]).replace("_", " ").to_upper()
	label.font_size = 28
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 0.25, 0)
	label.modulate = Color(1, 1, 1, 0.55)
	label.visible = false
	n.add_child(label)
	return n


func set_prop_transform(i: int, xf: Transform3D) -> void:
	if i < prop_nodes.size():
		prop_nodes[i].global_transform = xf


## Applies graphics preset values (see Settings): shadow/AO/effects quality.
func apply_quality(q: Dictionary) -> void:
	var e := env.environment
	e.ssao_enabled = int(q.get("ao", 2)) > 0
	e.glow_enabled = int(q.get("effects", 2)) > 0
	key_light.shadow_enabled = int(q.get("shadows", 2)) > 0
	for i in spots.size():
		spots[i].shadow_enabled = int(q.get("shadows", 2)) >= 2 and i < 2
	e.adjustment_brightness = float(q.get("brightness", 1.0))
	e.fog_enabled = int(q.get("effects", 2)) > 0
