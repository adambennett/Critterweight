class_name ArenaPropVisuals
## Procedural visuals for every arena prop and marker (catalog visual id -> builder). Built from
## ArenaMeshKit pieces with bevels, trim, colour breaks and painted decals (ART_DIRECTION §4,
## ARENAS.md §5): props are mid-saturation, hazards carry their element colour AND shape icon.
## A prop node is built relative to its BODY origin (centre of the collision volume, see
## ArenaBuilder.prop_body_transform) when the prop has a body, else relative to its floor point.
## Animation hooks are stored as node metadata and driven by ArenaView:
##   spin (Node3D, rad/s in meta "spin_rate"), bob (Node3D), flame (Node3D), glow_mats (Array of
##   materials whose "glow"/emission is driven by telegraphs), light (OmniLight3D), chain.

const SPONSORS := [["GLANDCO JUICE", "#1E2A12", "#8BD426"], ["NEEDLES PHARMACY", "#8C3B2B", "#F2D27A"], ["CHUM CO. CANNERY", "#1D2140", "#E9E2CF"],
	["BARGAIN BIN", "#C9A227", "#1A1D24"], ["RUST & SONS SALVAGE", "#5B3426", "#F2E6D0"], ["THE DOSAGE", "#14171E", "#35C1C9"]]
const ICONS := {"": 0, "scorch": 1, "brine": 2, "static": 3, "sludge": 4, "grit": 5, "gale": 6, "hook": 7, "arrow": 8, "spiral": 9, "star": 10, "chevrons": 11, "magnet": 12}
const TEAM_COLORS := [Color("#FF5A5A"), Color("#4DA3FF"), Color("#FFC43D"), Color("#B06BFF")]

static var _mats := {}
static var _surface_shader: Shader
static var _decal_shader: Shader
static var _neon_shader: Shader
static var _fence_shader: Shader


# =====================================================================================
# Material factory (shared with the set dressing)
# =====================================================================================

static func surface(mode: int, a: Color, b := Color(0.5, 0.5, 0.5), c := Color(0.15, 0.15, 0.17), opts := {}) -> ShaderMaterial:
	var key := "s|%d|%s|%s|%s|%s" % [mode, a.to_html(), b.to_html(), c.to_html(), str(opts)]
	if _mats.has(key):
		return _mats[key]
	if _surface_shader == null:
		_surface_shader = load("res://src/view/shaders/arena_surface.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _surface_shader
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("color_c", c)
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	_mats[key] = m
	return m


## Painted metal with clean rust chips (UV in metres from ArenaMeshKit).
static func paint(color: Color, rough := 0.55, metal := 0.25, chip := Color("#5E3426")) -> ShaderMaterial:
	return surface(8, color, color, chip, {"use_uv": true, "rough": rough, "metal": metal})


static func toon(color: Color, rough := 0.6, metal := 0.0, rim := 0.3, emissive := Color.BLACK) -> StandardMaterial3D:
	return Materials.toon(color, rough, metal, rim, emissive)


static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "g|%s|%.2f" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.3)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	_mats[key] = m
	return m


static func neon(color: Color, intensity := 3.0, flicker := 0.0, seed := 0.0) -> ShaderMaterial:
	if _neon_shader == null:
		_neon_shader = load("res://src/view/shaders/arena_neon.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _neon_shader
	m.set_shader_parameter("tube", color)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("flicker", flicker)
	m.set_shader_parameter("seed", seed)
	return m


static func fence_mat(color: Color) -> ShaderMaterial:
	if _fence_shader == null:
		_fence_shader = load("res://src/view/shaders/fence.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _fence_shader
	m.set_shader_parameter("wire_color", color)
	return m


## Hazard footprint / icon decal material (one per instance: glow and active are animated).
static func decal(color: Color, shape: int, size: Vector2, icon := 0, opts := {}) -> ShaderMaterial:
	if _decal_shader == null:
		_decal_shader = load("res://src/view/shaders/arena_decal.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _decal_shader
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("icon", icon)
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	m.render_priority = 1
	return m


## A flat decal quad (y slightly above the floor) carrying `mat`, added under `parent`.
static func decal_quad(parent: Node3D, mat: ShaderMaterial, size: Vector2, pos := Vector3.ZERO, yaw := 0.0) -> MeshInstance3D:
	var mi := ArenaMeshKit.add(parent, ArenaMeshKit.floor_quad(size), mat, pos + Vector3(0, 0.012, 0), Vector3(0, yaw, 0), Vector3.ONE, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Small painted icon plate (element shape on a prop's side). Faces local +Z.
static func icon_plate(parent: Node3D, icon_name: String, color: Color, pos: Vector3, rot: Vector3, sz := 0.34) -> MeshInstance3D:
	var m := decal(color, 1, Vector2(sz, sz), int(ICONS.get(icon_name, 0)), {"base_alpha": 1.0, "hatch_period": 100.0, "outline_w": 0.025, "icon_size": 0.62, "icon_spacing": 10.0})
	m.render_priority = 2
	var q := QuadMesh.new()
	q.size = Vector2(sz, sz)
	var mi := ArenaMeshKit.add(parent, q, m, pos, rot, Vector3.ONE, false)
	return mi


static func element_color(el: String) -> Color:
	if el == "":
		return Color("#F2D27A")
	return Elements.color(el) if Elements.defs.has(el) else Color.WHITE


# =====================================================================================
# Entry point
# =====================================================================================

## Builds the visual for a placed prop/marker. ctx: {editor: bool, index: int, base_style: String}.
static func build(def: Dictionary, item: Dictionary, ctx := {}) -> Node3D:
	var root := Node3D.new()
	var id := str(def.get("id", item.get("type", "")))
	root.name = "Prop_%s_%d" % [id, int(ctx.get("index", 0))]
	if def.is_empty():
		return root
	var s := ArenaCatalog.footprint_size(item, def)
	var h := float(def["height"]) * float(item.get("scale", 1.0))
	var has_body := str(def["body"]) != "none"
	var by := -h * 0.5 if has_body and str(def["body"]) != "bag" else 0.0
	root.set_meta("glow_mats", [])
	var seed := int(ctx.get("index", 0)) * 7 + int(absf(float(item["pos"].x) * 13.0 + float(item["pos"].z) * 7.0))
	match str(def.get("visual", id)):
		"prop_crate": _crate(root, s, h, by, seed, false)
		"prop_heavy_crate": _crate(root, s, h, by, seed, true)
		"prop_sponsor_board": _sponsor_board(root, s, h, by, seed)
		"prop_fence_segment": _fence(root, s, h, by)
		"prop_tire_stack": _tires(root, s, h, by, seed)
		"prop_bollard": _bollard(root, s, h, by)
		"prop_fire_barrel": _barrel(root, s, h, by, "scorch", seed)
		"prop_sludge_drum": _barrel(root, s, h, by, "sludge", seed)
		"prop_brine_barrel": _barrel(root, s, h, by, "brine", seed)
		"prop_battery": _battery(root, s, h, by)
		"prop_gravel_sack": _sack(root, s, h, by)
		"prop_fan_unit": _fan(root, s, h, by, def)
		"prop_steam_vent": _vent(root, s, def)
		"prop_electric_plate": _plate(root, s)
		"prop_spring_pad": _spring_pad(root, s)
		"prop_bumper": _bumper(root, s, h, by)
		"prop_pit": _pit(root, s)
		"prop_drain_pair": _drains(root, s, item)
		"prop_heavy_bag": _bag(root, s, h)
		"prop_chum_bucket": _bucket(root)
		"prop_hype_can": _can(root)
		"prop_ramp": _ramp(root, s, h, by)
		"prop_scrap_pile": _scrap(root, s, h, by, seed, 3)
		"prop_scrap_bundle": _scrap(root, s, h, by, seed, 1)
		"prop_rubber_mat": _mat(root, s)
		"prop_mooring_block": _block(root, s, h, by)
		"prop_hvac_unit": _hvac(root, s, h, by)
		"prop_water_tower_leg": _tower_leg(root, s, h, by)
		"prop_edge_railing": _railing(root, s, h, by)
		_:
			if bool(def.get("is_marker", false)):
				_marker(root, def, item)
			else:
				ArenaMeshKit.box(root, Vector3(s.x, maxf(h, 0.05), s.y), paint(Color("#8D8A86")), Vector3(0, by + h * 0.5, 0))
	return root


static func _glow_mat(root: Node3D, m: Material) -> void:
	var arr: Array = root.get_meta("glow_mats", [])
	arr.append(m)
	root.set_meta("glow_mats", arr)


# =====================================================================================
# Obstacles & walls
# =====================================================================================

static func _crate(root: Node3D, s: Vector2, h: float, by: float, seed: int, heavy: bool) -> void:
	var wood_a := Color("#A8743A") if not heavy else Color("#7E5530")
	var wood_b := Color("#8A5A2B") if not heavy else Color("#62401F")
	var wood := surface(9, wood_a, wood_b, Color.BLACK, {"use_uv": true, "seed": float(seed % 17)})
	var batten := toon(wood_b.darkened(0.35), 0.8)
	var cy := by + h * 0.5
	ArenaMeshKit.box(root, Vector3(s.x - 0.08, h - 0.08, s.y - 0.08), wood, Vector3(0, cy, 0), Vector3.ZERO, 0.02)
	var t := 0.09 if not heavy else 0.11
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			ArenaMeshKit.box(root, Vector3(t, h, t), batten, Vector3(sx * (s.x - t) * 0.5, cy, sz * (s.y - t) * 0.5), Vector3.ZERO, 0.02)
	for yy in [by + t * 0.5, by + h - t * 0.5]:
		for sz in [-1.0, 1.0]:
			ArenaMeshKit.box(root, Vector3(s.x, t, t), batten, Vector3(0, yy, sz * (s.y - t) * 0.5), Vector3.ZERO, 0.02)
		for sx in [-1.0, 1.0]:
			ArenaMeshKit.box(root, Vector3(t, t, s.y), batten, Vector3(sx * (s.x - t) * 0.5, yy, 0), Vector3.ZERO, 0.02)
	# diagonal braces on the four sides
	var diag := sqrt(s.x * s.x + h * h) * 0.86
	for sz in [-1.0, 1.0]:
		ArenaMeshKit.box(root, Vector3(diag, t * 0.8, 0.04), batten, Vector3(0, cy, sz * (s.y * 0.5 - 0.02)), Vector3(0, 0, atan2(h, s.x) * (1.0 if sz > 0 else -1.0)), 0.015)
	var diag2 := sqrt(s.y * s.y + h * h) * 0.86
	for sx in [-1.0, 1.0]:
		ArenaMeshKit.box(root, Vector3(0.04, t * 0.8, diag2), batten, Vector3(sx * (s.x * 0.5 - 0.02), cy, 0), Vector3(atan2(h, s.y) * (1.0 if sx > 0 else -1.0), 0, 0), 0.015)
	if heavy:
		var steel := paint(Color("#4A4F57"), 0.45, 0.6)
		for yy2 in [by + h * 0.28, by + h * 0.72]:
			ArenaMeshKit.box(root, Vector3(s.x + 0.03, 0.09, s.y + 0.03), steel, Vector3(0, yy2, 0), Vector3.ZERO, 0.02)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				for yy3 in [by + 0.08, by + h - 0.08]:
					ArenaMeshKit.box(root, Vector3(0.2, 0.18, 0.2), steel, Vector3(sx * (s.x * 0.5 - 0.07), yy3, sz * (s.y * 0.5 - 0.07)), Vector3.ZERO, 0.03)
	var words := ["GLANDCO", "FRAGILE", "CHUM CO.", "THIS SIDE UP"]
	var word: String = "HEAVY" if heavy else words[seed % words.size()]
	ArenaMeshKit.label(root, word, 72, Color(0.1, 0.07, 0.05, 0.75), Vector3(0, cy, s.y * 0.5 + 0.012), Vector3.ZERO, Color(0, 0, 0, 0), "res://assets/fonts/BarlowCondensed-900.woff2", 0.0036)
	ArenaMeshKit.label(root, word, 72, Color(0.1, 0.07, 0.05, 0.75), Vector3(0, cy, -s.y * 0.5 - 0.012), Vector3(0, PI, 0), Color(0, 0, 0, 0), "res://assets/fonts/BarlowCondensed-900.woff2", 0.0036)


static func _sponsor_board(root: Node3D, s: Vector2, h: float, by: float, seed: int) -> void:
	var sp: Array = SPONSORS[seed % SPONSORS.size()]
	var panel_col := Color(str(sp[1]))
	var text_col := Color(str(sp[2]))
	var frame := paint(Color("#2B2F3A"), 0.5, 0.5)
	var panel := paint(panel_col, 0.6, 0.1, panel_col.darkened(0.45))
	ArenaMeshKit.box(root, Vector3(s.x - 0.12, h - 0.16, s.y * 0.7), panel, Vector3(0, by + h * 0.5 + 0.02, 0), Vector3.ZERO, 0.03)
	for sx in [-1.0, 1.0]:
		ArenaMeshKit.box(root, Vector3(0.12, h, s.y), frame, Vector3(sx * (s.x * 0.5 - 0.06), by + h * 0.5, 0), Vector3.ZERO, 0.03)
		ArenaMeshKit.box(root, Vector3(0.3, 0.06, s.y + 0.25), frame, Vector3(sx * (s.x * 0.5 - 0.1), by + 0.03, 0), Vector3.ZERO, 0.02)
	ArenaMeshKit.box(root, Vector3(s.x, 0.08, s.y + 0.02), frame, Vector3(0, by + h - 0.04, 0), Vector3.ZERO, 0.025)
	ArenaMeshKit.box(root, Vector3(s.x - 0.2, 0.05, s.y * 0.72), toon(text_col, 0.5), Vector3(0, by + 0.18, 0), Vector3.ZERO, 0.01)
	for side in [1.0, -1.0]:
		ArenaMeshKit.label(root, str(sp[0]), 96, text_col, Vector3(0, by + h * 0.55, side * (s.y * 0.35 + 0.011)), Vector3(0, 0.0 if side > 0 else PI, 0), Color(0, 0, 0, 0.0), "res://assets/fonts/BarlowCondensed-900.woff2", 0.0042 * minf(1.0, (s.x - 0.3) / 1.8))


static func _fence(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var post := paint(Color("#5B6168"), 0.45, 0.7)
	for sx in [-1.0, 1.0]:
		ArenaMeshKit.cyl(root, 0.06, h + 0.05, post, Vector3(sx * s.x * 0.5, by + (h + 0.05) * 0.5, 0), Vector3.ZERO, 12, 0.015)
		ArenaMeshKit.cyl(root, 0.075, 0.06, toon(Color("#C9A227"), 0.4), Vector3(sx * s.x * 0.5, by + h + 0.06, 0), Vector3.ZERO, 12, 0.02)
	var rail := ArenaMeshKit.tube(PackedVector3Array([Vector3(-s.x * 0.5, 0, 0), Vector3(s.x * 0.5, 0, 0)]), 0.035, 8)
	for yy in [by + h - 0.05, by + 0.1, by + h * 0.5]:
		ArenaMeshKit.add(root, rail, post, Vector3(0, yy, 0))
	var q := QuadMesh.new()
	q.size = Vector2(s.x, h - 0.12)
	var mi := ArenaMeshKit.add(root, q, fence_mat(Color("#9AA0AA")), Vector3(0, by + h * 0.5, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _tires(root: Node3D, s: Vector2, h: float, by: float, seed: int) -> void:
	var rubber := toon(Color("#1C1C20"), 0.85, 0.0, 0.2)
	var n := 4
	var th := h / float(n)
	for k in n:
		var tm := TorusMesh.new()
		tm.inner_radius = s.x * 0.2
		tm.outer_radius = s.x * 0.5
		tm.rings = 18
		tm.ring_segments = 10
		var t := ArenaMeshKit.add(root, tm, rubber, Vector3(0.03 * sin(float(k + seed)), by + th * (k + 0.5), 0.03 * cos(float(k * 3 + seed))), Vector3(0, float(k) * 0.7, 0), Vector3(1, th / (s.x * 0.3), 1))
		t.name = "Tire%d" % k
	var band := TorusMesh.new()
	band.inner_radius = s.x * 0.44
	band.outer_radius = s.x * 0.51
	ArenaMeshKit.add(root, band, toon(Color("#F2C230"), 0.5), Vector3(0, by + th * (n - 0.5), 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	ArenaMeshKit.add(root, ArenaMeshKit.floor_disc(s.x * 0.2, 16), toon(Color("#0E0E10"), 0.9), Vector3(0, by + h - 0.02, 0))


static func _bollard(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var iron := toon(Color("#25272C"), 0.35, 0.6, 0.35)
	var r := s.x * 0.5
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 1.15, r * 1.2, 0.08, 20, 0.02), iron, Vector3(0, by + 0.04, 0))
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 0.72, r * 0.8, h * 0.72, 20, 0.02), iron, Vector3(0, by + 0.08 + h * 0.36, 0))
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 1.0, r * 0.72, h * 0.14, 20, 0.03), iron, Vector3(0, by + h * 0.87, 0))
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 0.85, r * 1.0, h * 0.06, 20, 0.02), iron, Vector3(0, by + h * 0.97, 0))
	var band := TorusMesh.new()
	band.inner_radius = r * 0.74
	band.outer_radius = r * 0.84
	ArenaMeshKit.add(root, band, toon(Color("#C9A227"), 0.5), Vector3(0, by + h * 0.6, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
	var rope := TorusMesh.new()
	rope.inner_radius = r * 0.78
	rope.outer_radius = r * 0.92
	ArenaMeshKit.add(root, rope, toon(Color("#B9A27A"), 0.9), Vector3(0, by + h * 0.3, 0), Vector3(0.25, 0, 0.1), Vector3(1, 1.3, 1))


static func _barrel(root: Node3D, s: Vector2, h: float, by: float, el: String, seed: int) -> void:
	var body_col := {"scorch": Color("#8C3B2B"), "sludge": Color("#2A2F2E"), "brine": Color("#B8C2C8")}.get(el, Color.GRAY) as Color
	var band_col := element_color(el)
	var r := s.x * 0.5
	var shell := paint(body_col, 0.5, 0.35)
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r, r, h, 22, 0.03), shell, Vector3(0, by + h * 0.5, 0))
	for f in [0.2, 0.5, 0.8]:
		var hoop := TorusMesh.new()
		hoop.inner_radius = r * 0.97
		hoop.outer_radius = r * 1.04
		ArenaMeshKit.add(root, hoop, toon(body_col.darkened(0.35), 0.4, 0.5), Vector3(0, by + h * f, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	var stripe := TorusMesh.new()
	stripe.inner_radius = r * 0.995
	stripe.outer_radius = r * 1.025
	ArenaMeshKit.add(root, stripe, toon(band_col, 0.45, 0.0, 0.3, band_col * 0.15), Vector3(0, by + h * 0.65, 0), Vector3.ZERO, Vector3(1, 2.4, 1))
	icon_plate(root, el, band_col, Vector3(0, by + h * 0.38, r + 0.01), Vector3.ZERO, r * 1.05)
	icon_plate(root, el, band_col, Vector3(0, by + h * 0.38, -r - 0.01), Vector3(0, PI, 0), r * 1.05)
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 0.95, r * 0.95, 0.03, 22, 0.01), toon(body_col.darkened(0.2), 0.5, 0.4), Vector3(0, by + h - 0.01, 0))
	match el:
		"scorch":
			var flame := Node3D.new()
			flame.name = "Flame"
			flame.position = Vector3(0, by + h, 0)
			root.add_child(flame)
			ArenaMeshKit.add(flame, ArenaMeshKit.cylinder(0.01, r * 0.75, 0.55, 10, 0.0), glow(Color("#FF6B2B"), 3.2), Vector3(0, 0.27, 0), Vector3.ZERO, Vector3.ONE, false)
			ArenaMeshKit.add(flame, ArenaMeshKit.cylinder(0.01, r * 0.45, 0.4, 8, 0.0), glow(Color("#FFD27A"), 4.0), Vector3(0.05, 0.2, -0.03), Vector3.ZERO, Vector3.ONE, false)
			var l := OmniLight3D.new()
			l.light_color = Color("#FF8A3D")
			l.light_energy = 1.6
			l.omni_range = 3.2
			l.position = Vector3(0, 0.5, 0)
			flame.add_child(l)
			root.set_meta("flame", flame)
			root.set_meta("light", l)
		"sludge":
			ArenaMeshKit.add(root, ArenaMeshKit.floor_disc(r * 1.6, 18), toon(Color("#6FA81E"), 0.2, 0.0, 0.3, Color("#8BD426") * 0.2), Vector3(r * 0.4, by + 0.012, r * 0.3), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
			ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 0.12, r * 0.18, h * 0.3, 8, 0.0), toon(Color("#8BD426"), 0.2, 0.0, 0.3, Color("#8BD426") * 0.3), Vector3(r * 0.85, by + h * 0.62, 0))
		"brine":
			ArenaMeshKit.add(root, ArenaMeshKit.floor_disc(r * 1.3, 18), toon(Color("#2E9BE0").darkened(0.2), 0.05), Vector3(-r * 0.3, by + 0.012, r * 0.4), Vector3.ZERO, Vector3(1.0, 1.0, 0.75))


static func _battery(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var case_m := toon(Color("#1D1F24"), 0.55, 0.0, 0.3)
	ArenaMeshKit.box(root, Vector3(s.x, h * 0.86, s.y), case_m, Vector3(0, by + h * 0.43, 0), Vector3.ZERO, 0.04)
	ArenaMeshKit.box(root, Vector3(s.x * 0.96, h * 0.14, s.y * 0.96), toon(Color("#33363D"), 0.5), Vector3(0, by + h * 0.9, 0), Vector3.ZERO, 0.03)
	ArenaMeshKit.box(root, Vector3(s.x * 0.7, h * 0.4, 0.02), toon(Color("#F7E04A"), 0.45), Vector3(0, by + h * 0.45, s.y * 0.5 + 0.005), Vector3.ZERO, 0.005)
	icon_plate(root, "static", Color("#1D1F24"), Vector3(0, by + h * 0.45, s.y * 0.5 + 0.018), Vector3.ZERO, h * 0.36)
	for k in 2:
		var tx := (-1.0 if k == 0 else 1.0) * s.x * 0.3
		ArenaMeshKit.cyl(root, 0.05, 0.1, toon(Color("#D9532B") if k == 1 else Color("#2B2F3A"), 0.4, 0.4), Vector3(tx, by + h + 0.04, 0), Vector3.ZERO, 10, 0.01)
	ArenaMeshKit.label(root, "12V", 64, Color("#F2F2EC"), Vector3(s.x * 0.33, by + h * 0.91 + 0.001, 0.0), Vector3(-PI * 0.5, 0, 0), Color(0, 0, 0, 0), "res://assets/fonts/BarlowCondensed-900.woff2", 0.003)


static func _sack(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var burlap := toon(Color("#B8905E"), 0.95, 0.0, 0.25)
	ArenaMeshKit.box(root, Vector3(s.x, h * 0.8, s.y), burlap, Vector3(0, by + h * 0.4, 0), Vector3.ZERO, minf(s.y, h) * 0.32)
	ArenaMeshKit.box(root, Vector3(s.x * 0.7, h * 0.25, s.y * 0.6), burlap, Vector3(0.05, by + h * 0.82, 0), Vector3(0, 0.2, 0), 0.08)
	ArenaMeshKit.cyl(root, 0.07, 0.12, toon(Color("#6B4F3A"), 0.9), Vector3(0.05, by + h * 0.96, 0), Vector3.ZERO, 8, 0.02)
	ArenaMeshKit.box(root, Vector3(s.x * 0.95, 0.025, 0.02), toon(Color("#6B4F3A"), 0.9), Vector3(0, by + h * 0.45, s.y * 0.5 - 0.02), Vector3.ZERO, 0.005)
	icon_plate(root, "grit", Color("#5E4326"), Vector3(-s.x * 0.12, by + h * 0.42, s.y * 0.5 + 0.02), Vector3.ZERO, h * 0.5)


static func _fan(root: Node3D, s: Vector2, h: float, by: float, def: Dictionary) -> void:
	var housing := paint(Color("#6E7A80"), 0.45, 0.5)
	var dark := toon(Color("#2B2F3A"), 0.6, 0.3)
	ArenaMeshKit.box(root, Vector3(s.x, 0.12, s.y), dark, Vector3(0, by + 0.06, 0), Vector3.ZERO, 0.03)
	for sx in [-1.0, 1.0]:
		ArenaMeshKit.box(root, Vector3(0.1, h * 0.92, s.y * 0.92), housing, Vector3(sx * (s.x * 0.5 - 0.05), by + h * 0.52, 0), Vector3.ZERO, 0.03)
	ArenaMeshKit.box(root, Vector3(s.x, 0.1, s.y * 0.92), housing, Vector3(0, by + h - 0.05, 0), Vector3.ZERO, 0.03)
	ArenaMeshKit.box(root, Vector3(s.x * 0.9, h * 0.85, 0.06), dark, Vector3(0, by + h * 0.53, -s.y * 0.42), Vector3.ZERO, 0.02)
	var hub_y := by + h * 0.55
	var ring := TorusMesh.new()
	ring.inner_radius = s.x * 0.36
	ring.outer_radius = s.x * 0.43
	ArenaMeshKit.add(root, ring, toon(Color("#C9A227"), 0.4, 0.4), Vector3(0, hub_y, s.y * 0.42), Vector3(PI * 0.5, 0, 0))
	for k in 4:
		ArenaMeshKit.box(root, Vector3(s.x * 0.8, 0.025, 0.025), toon(Color("#9FA6AD"), 0.4, 0.6), Vector3(0, hub_y, s.y * 0.45), Vector3(0, 0, PI * 0.25 * k), 0.005)
	var spin := Node3D.new()
	spin.name = "Blades"
	spin.position = Vector3(0, hub_y, s.y * 0.3)
	root.add_child(spin)
	for k2 in 3:
		ArenaMeshKit.box(spin, Vector3(0.16, s.x * 0.36, 0.03), toon(Color("#CFF4F2"), 0.35, 0.3), Vector3(0, s.x * 0.18, 0).rotated(Vector3.FORWARD, TAU * k2 / 3.0), Vector3(0.35, 0, TAU * k2 / 3.0), 0.01)
	ArenaMeshKit.cyl(spin, 0.07, 0.08, dark, Vector3.ZERO, Vector3(PI * 0.5, 0, 0), 12, 0.02)
	root.set_meta("spin", spin)
	root.set_meta("spin_axis", Vector3(0, 0, 1))
	root.set_meta("spin_rate", 14.0)
	icon_plate(root, "gale", Color("#4FB3B8"), Vector3(s.x * 0.5 + 0.01, by + h * 0.55, 0), Vector3(0, PI * 0.5, 0), 0.42)
	icon_plate(root, "gale", Color("#4FB3B8"), Vector3(-s.x * 0.5 - 0.01, by + h * 0.55, 0), Vector3(0, -PI * 0.5, 0), 0.42)
	# push-line footprint (hatched, swirl icons) on the floor ahead of the fan
	var params: Dictionary = def.get("params", {})
	var length := float(params.get("length", 5.0))
	var width := float(params.get("width", 1.5))
	var dm := decal(Color("#4FB3B8"), 0, Vector2(width, length), ICONS["gale"], {"icon_spacing": 1.5, "base_alpha": 0.32})
	decal_quad(root, dm, Vector2(width, length), Vector3(0, by, s.y * 0.5 + length * 0.5))
	_glow_mat(root, dm)


static func _vent(root: Node3D, s: Vector2, def: Dictionary) -> void:
	var frame := toon(Color("#2B2F3A"), 0.5, 0.6)
	var hot := glow(Color("#FF6B2B"), 0.0)
	ArenaMeshKit.add(root, ArenaMeshKit.floor_quad(Vector2(s.x - 0.1, s.y - 0.1)), toon(Color("#121316"), 0.9), Vector3(0, 0.006, 0))
	var bars := Node3D.new()
	root.add_child(bars)
	for k in 7:
		ArenaMeshKit.box(bars, Vector3(s.x - 0.16, 0.04, 0.05), frame, Vector3(0, 0.02, -s.y * 0.38 + s.y * 0.76 * k / 6.0), Vector3.ZERO, 0.01)
	for sx in [-1.0, 1.0]:
		ArenaMeshKit.box(root, Vector3(0.08, 0.06, s.y), frame, Vector3(sx * (s.x * 0.5 - 0.04), 0.03, 0), Vector3.ZERO, 0.015)
		ArenaMeshKit.box(root, Vector3(s.x, 0.06, 0.08), frame, Vector3(0, 0.03, sx * (s.y * 0.5 - 0.04)), Vector3.ZERO, 0.015)
	var glow_plate := MeshInstance3D.new()
	glow_plate.mesh = ArenaMeshKit.floor_quad(Vector2(s.x - 0.2, s.y - 0.2))
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.42, 0.17, 0.0)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_plate.material_override = gm
	glow_plate.position = Vector3(0, 0.004, 0)
	root.add_child(glow_plate)
	root.set_meta("heat", gm)
	var params: Dictionary = def.get("params", {})
	var length := float(params.get("length", 2.0))
	var dm := decal(Color("#FF6B2B"), 2, Vector2(length * 1.2, length), ICONS["scorch"], {"cone_deg": float(params.get("cone_deg", 70.0)), "icon_spacing": 1.2, "base_alpha": 0.32})
	decal_quad(root, dm, Vector2(length * 1.2, length), Vector3(0, 0, s.y * 0.5 + length * 0.5))
	var dm2 := decal(Color("#FF6B2B"), 0, s, ICONS["scorch"], {"icon_spacing": 4.0, "base_alpha": 0.45})
	decal_quad(root, dm2, s + Vector2(0.2, 0.2))
	_glow_mat(root, dm)
	_glow_mat(root, dm2)
	var plume := Node3D.new()
	plume.name = "Plume"
	plume.visible = false
	root.add_child(plume)
	var steam := StandardMaterial3D.new()
	steam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam.albedo_color = Color(1.0, 0.9, 0.82, 0.55)
	steam.cull_mode = BaseMaterial3D.CULL_DISABLED
	ArenaMeshKit.add(plume, ArenaMeshKit.cylinder(0.75, 0.3, length, 16, 0.0, false), steam, Vector3(0, 0.6, length * 0.45), Vector3(PI * 0.32, 0, 0), Vector3.ONE, false)
	ArenaMeshKit.add(plume, ArenaMeshKit.cylinder(0.55, 0.32, 1.6, 16, 0.0, false), steam, Vector3(0, 0.8, 0), Vector3.ZERO, Vector3.ONE, false)
	root.set_meta("plume", plume)
	_glow_mat(root, hot)


static func _plate(root: Node3D, s: Vector2) -> void:
	var steel := surface(2, Color("#6A7179"), Color.GRAY, Color("#7A3E2A"), {"cell": s, "grid_origin": Vector2(-s.x * 0.5, -s.y * 0.5), "seam": 0.0})
	ArenaMeshKit.box(root, Vector3(s.x, 0.04, s.y), steel, Vector3(0, 0.02, 0), Vector3.ZERO, 0.012)
	var dm := decal(Color("#F7E04A"), 0, s, ICONS["static"], {"icon_spacing": 1.0, "base_alpha": 0.42, "outline_w": 0.12})
	decal_quad(root, dm, s, Vector3(0, 0.03, 0))
	_glow_mat(root, dm)
	var live := MeshInstance3D.new()
	live.mesh = ArenaMeshKit.outline_band(PackedVector2Array([Vector2(-s.x * 0.5, -s.y * 0.5), Vector2(s.x * 0.5, -s.y * 0.5), Vector2(s.x * 0.5, s.y * 0.5), Vector2(-s.x * 0.5, s.y * 0.5)]), 0.0, 0.08, 0.05)
	var lm := glow(Color("#F7E04A"), 0.0)
	live.material_override = lm.duplicate()
	root.add_child(live)
	root.set_meta("live_mat", live.material_override)


static func _spring_pad(root: Node3D, s: Vector2) -> void:
	var r := s.x * 0.5
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r, r * 1.05, 0.06, 26, 0.02), toon(Color("#2B2F3A"), 0.5, 0.5), Vector3(0, 0.03, 0))
	for k in 3:
		var coil := TorusMesh.new()
		coil.inner_radius = r * 0.55
		coil.outer_radius = r * 0.68
		ArenaMeshKit.add(root, coil, toon(Color("#9FA6AD"), 0.3, 0.8), Vector3(0, 0.07 + k * 0.03, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	var top := Node3D.new()
	top.name = "Pad"
	top.position = Vector3(0, 0.16, 0)
	root.add_child(top)
	ArenaMeshKit.add(top, ArenaMeshKit.cylinder(r * 0.92, r * 0.92, 0.06, 26, 0.02), toon(Color("#C9A227"), 0.4, 0.2), Vector3.ZERO)
	var dm := decal(Color("#1A1D24"), 1, Vector2(r * 1.7, r * 1.7), ICONS["arrow"], {"base_alpha": 0.85, "hatch_period": 100.0, "outline_w": 0.04, "icon_spacing": 10.0, "icon_size": 0.7})
	decal_quad(top, dm, Vector2(r * 1.7, r * 1.7), Vector3(0, 0.02, 0))
	var foot := decal(Color("#C9A227"), 1, Vector2(s.x + 0.3, s.x + 0.3), 0, {"base_alpha": 0.4})
	decal_quad(root, foot, Vector2(s.x + 0.3, s.x + 0.3))
	root.set_meta("pad_top", top)
	_glow_mat(root, foot)


static func _bumper(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var r := s.x * 0.5
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 1.05, r * 1.1, 0.12, 24, 0.03), toon(Color("#C8CCD2"), 0.25, 0.9), Vector3(0, by + 0.06, 0))
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 0.8, r * 0.85, h * 0.6, 24, 0.03), toon(Color("#F2F2EC"), 0.4), Vector3(0, by + 0.12 + h * 0.3, 0))
	var rubber := TorusMesh.new()
	rubber.inner_radius = r * 0.82
	rubber.outer_radius = r * 1.0
	ArenaMeshKit.add(root, rubber, toon(Color("#E04FB0"), 0.5), Vector3(0, by + h * 0.45, 0), Vector3.ZERO, Vector3(1, 1.4, 1))
	var lamp := glow(Color("#FFE9C2"), 1.2).duplicate() as StandardMaterial3D
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 0.55, r * 0.78, h * 0.2, 24, 0.04), lamp, Vector3(0, by + h * 0.82, 0))
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r * 0.2, r * 0.5, h * 0.1, 18, 0.02), toon(Color("#35C1C9"), 0.3), Vector3(0, by + h * 0.96, 0))
	root.set_meta("lamp", lamp)
	var foot := decal(Color("#E04FB0"), 1, Vector2(s.x + 1.0, s.x + 1.0), ICONS["star"], {"base_alpha": 0.35, "icon_spacing": 10.0, "icon_size": 0.35})
	decal_quad(root, foot, Vector2(s.x + 1.0, s.x + 1.0), Vector3(0, by, 0))


static func _pit(root: Node3D, s: Vector2) -> void:
	var hx := s.x * 0.5
	var hz := s.y * 0.5
	var wall := toon(Color("#15161A"), 0.9)
	var depth := 6.0
	for k in 4:
		var q := QuadMesh.new()
		var along_x := k < 2
		q.size = Vector2(s.x if along_x else s.y, depth)
		var sign := -1.0 if k % 2 == 0 else 1.0
		var pos := Vector3(0, -depth * 0.5, sign * hz) if along_x else Vector3(sign * hx, -depth * 0.5, 0)
		var rot := Vector3(0, 0.0 if along_x else PI * 0.5, 0)
		if (along_x and sign < 0.0) or (not along_x and sign > 0.0):
			rot.y += PI
		var mi := ArenaMeshKit.add(root, q, wall, pos, rot, Vector3.ONE, false)
		mi.material_override = wall
	ArenaMeshKit.add(root, ArenaMeshKit.floor_quad(s), toon(Color("#050507"), 1.0), Vector3(0, -depth, 0), Vector3.ZERO, Vector3.ONE, false)
	var poly := PackedVector2Array([Vector2(-hx - 0.15, -hz - 0.15), Vector2(hx + 0.15, -hz - 0.15), Vector2(hx + 0.15, hz + 0.15), Vector2(-hx - 0.15, hz + 0.15)])
	var band := MeshInstance3D.new()
	band.mesh = ArenaMeshKit.outline_band(poly, 0.0, 0.16, 0.02)
	band.material_override = toon(Color("#F7E04A"), 0.6)
	root.add_child(band)
	var rim := s + Vector2(1.0, 1.0)
	var dm := decal(Color("#F7E04A"), 0, rim, ICONS["chevrons"], {"base_alpha": 0.38, "icon_spacing": 0.9, "hole": s + Vector2(0.3, 0.3)})
	decal_quad(root, dm, rim)
	_glow_mat(root, dm)


static func _drains(root: Node3D, s: Vector2, item: Dictionary) -> void:
	var r := s.x * 0.5
	var ends: Array = [Vector3.ZERO]
	if item.has("pos2"):
		var a: Vector3 = item["pos"]
		var b: Vector3 = item["pos2"]
		var local := Basis(Vector3.UP, float(item.get("yaw", 0.0))).inverse() * (b - a)
		ends.append(Vector3(local.x, 0.0, local.z))
	var link := Color("#35C1C9")
	for e in ends:
		var p: Vector3 = e
		ArenaMeshKit.add(root, ArenaMeshKit.cylinder(r, r * 1.05, 0.05, 26, 0.015), toon(Color("#2B2F3A"), 0.4, 0.7), p + Vector3(0, 0.025, 0))
		var ring := TorusMesh.new()
		ring.inner_radius = r * 0.88
		ring.outer_radius = r * 1.02
		ArenaMeshKit.add(root, ring, glow(link, 1.4), p + Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
		var dm := decal(Color("#9FE6EA"), 1, Vector2(s.x * 0.85, s.x * 0.85), ICONS["spiral"], {"base_alpha": 0.9, "hatch_period": 100.0, "icon_spacing": 10.0, "icon_size": 0.8})
		decal_quad(root, dm, Vector2(s.x * 0.85, s.x * 0.85), p + Vector3(0, 0.045, 0))
	if ends.size() == 2:
		var b2: Vector3 = ends[1]
		var steps := int(b2.length() / 0.5)
		for k in range(1, steps):
			var t := float(k) / float(steps)
			ArenaMeshKit.add(root, ArenaMeshKit.floor_disc(0.05, 8), toon(link.darkened(0.2), 0.5), b2 * t + Vector3(0, 0.01, 0), Vector3.ZERO, Vector3.ONE, false)


static func _bag(root: Node3D, s: Vector2, h: float) -> void:
	var leather := toon(Color("#9E2F28"), 0.55, 0.0, 0.35)
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(s.x * 0.5, s.x * 0.5, h * 0.82, 20, 0.08), leather, Vector3(0, -h * 0.05, 0))
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(s.x * 0.36, s.x * 0.5, h * 0.1, 20, 0.03), leather, Vector3(0, h * 0.41, 0))
	ArenaMeshKit.add(root, ArenaMeshKit.cylinder(s.x * 0.5, s.x * 0.34, h * 0.1, 20, 0.03), leather, Vector3(0, -h * 0.5, 0))
	for f in [0.25, -0.2]:
		var band := TorusMesh.new()
		band.inner_radius = s.x * 0.49
		band.outer_radius = s.x * 0.53
		ArenaMeshKit.add(root, band, toon(Color("#C9A227"), 0.45), Vector3(0, h * f, 0), Vector3.ZERO, Vector3(1, 1.6, 1))
	ArenaMeshKit.label(root, "PUNCH", 64, Color("#F2E6D0"), Vector3(0, 0.0, s.x * 0.51), Vector3(0, 0, PI * 0.5), Color(0, 0, 0, 0), "res://assets/fonts/BarlowCondensed-900.woff2", 0.003)
	for k in 4:
		var a := TAU * k / 4.0
		ArenaMeshKit.add(root, ArenaMeshKit.tube(PackedVector3Array([Vector3(cos(a) * s.x * 0.36, h * 0.46, sin(a) * s.x * 0.36), Vector3(0, h * 0.5 + 0.15, 0)]), 0.012, 6), toon(Color("#9FA6AD"), 0.35, 0.8))


static func _bucket(root: Node3D) -> void:
	var bob := Node3D.new()
	bob.name = "Bob"
	bob.position = Vector3(0, 0.3, 0)
	root.add_child(bob)
	var tin := paint(Color("#B9BEC4"), 0.35, 0.7)
	ArenaMeshKit.add(bob, ArenaMeshKit.cylinder(0.27, 0.21, 0.42, 22, 0.02, false), tin, Vector3(0, 0.21, 0))
	ArenaMeshKit.add(bob, ArenaMeshKit.cylinder(0.21, 0.21, 0.02, 22, 0.0), tin, Vector3(0, 0.01, 0))
	var rim := TorusMesh.new()
	rim.inner_radius = 0.25
	rim.outer_radius = 0.29
	ArenaMeshKit.add(bob, rim, tin, Vector3(0, 0.42, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	ArenaMeshKit.add(bob, ArenaMeshKit.tube(PackedVector3Array([Vector3(-0.26, 0.4, 0), Vector3(-0.2, 0.62, 0), Vector3(0, 0.7, 0), Vector3(0.2, 0.62, 0), Vector3(0.26, 0.4, 0)]), 0.012, 6), toon(Color("#5B6168"), 0.3, 0.8))
	ArenaMeshKit.add(bob, ArenaMeshKit.floor_disc(0.25, 20), toon(Color("#C7556B"), 0.6), Vector3(0, 0.38, 0))
	for k in 4:
		ArenaMeshKit.box(bob, Vector3(0.12, 0.08, 0.09), toon(Color("#E7A3A8") if k % 2 == 0 else Color("#C7C9CC"), 0.4), Vector3(-0.1 + 0.07 * k, 0.43, 0.05 * sin(float(k) * 2.0)), Vector3(0.3 * k, 0.5 * k, 0), 0.03)
	var cross := glow(Color("#FF5A5A"), 1.6)
	ArenaMeshKit.box(bob, Vector3(0.18, 0.06, 0.02), cross, Vector3(0, 0.22, 0.25), Vector3.ZERO, 0.005)
	ArenaMeshKit.box(bob, Vector3(0.06, 0.18, 0.02), cross, Vector3(0, 0.22, 0.25), Vector3.ZERO, 0.005)
	var l := OmniLight3D.new()
	l.light_color = Color("#FFB0A8")
	l.light_energy = 0.9
	l.omni_range = 1.5
	l.position = Vector3(0, 0.4, 0)
	bob.add_child(l)
	root.set_meta("bob", bob)
	root.set_meta("light", l)
	_pickup_ring(root, Color("#FF5A5A"))


static func _can(root: Node3D) -> void:
	var bob := Node3D.new()
	bob.name = "Bob"
	bob.position = Vector3(0, 0.3, 0)
	root.add_child(bob)
	var body := toon(Color("#8BD426"), 0.3, 0.3, 0.4, Color("#8BD426") * 0.15)
	ArenaMeshKit.add(bob, ArenaMeshKit.cylinder(0.15, 0.15, 0.3, 22, 0.02), body, Vector3(0, 0.17, 0))
	ArenaMeshKit.add(bob, ArenaMeshKit.cylinder(0.12, 0.15, 0.04, 22, 0.01), toon(Color("#C9A227"), 0.25, 0.8), Vector3(0, 0.34, 0))
	ArenaMeshKit.add(bob, ArenaMeshKit.cylinder(0.15, 0.12, 0.03, 22, 0.01), toon(Color("#C9A227"), 0.25, 0.8), Vector3(0, 0.005, 0))
	for side in [1.0, -1.0]:
		ArenaMeshKit.label(bob, "JUICE", 80, Color("#1A1D24"), Vector3(0, 0.17, side * 0.152), Vector3(0, 0.0 if side > 0 else PI, PI * 0.5), Color(0, 0, 0, 0), "res://assets/fonts/BarlowCondensed-900.woff2", 0.0028)
	var l := OmniLight3D.new()
	l.light_color = Color("#B8F06A")
	l.light_energy = 1.1
	l.omni_range = 1.5
	l.position = Vector3(0, 0.2, 0)
	bob.add_child(l)
	root.set_meta("bob", bob)
	root.set_meta("spin", bob)
	root.set_meta("spin_axis", Vector3.UP)
	root.set_meta("spin_rate", 1.4)
	root.set_meta("light", l)
	_pickup_ring(root, Color("#8BD426"))


static func _pickup_ring(root: Node3D, c: Color) -> void:
	var m := decal(c, 3, Vector2(1.1, 1.1), 0, {"base_alpha": 0.55, "hatch_period": 100.0})
	var ring := decal_quad(root, m, Vector2(1.1, 1.1))
	root.set_meta("ring", ring)
	root.set_meta("ring_mat", m)


static func _ramp(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := s.x * 0.5
	var hd := s.y * 0.5
	var a := Vector3(-hw, by, -hd)
	var b := Vector3(hw, by, -hd)
	var c := Vector3(hw, by + h, hd)
	var d := Vector3(-hw, by + h, hd)
	var e := Vector3(-hw, by, hd)
	var f := Vector3(hw, by, hd)
	var slope_n := Vector3(0, s.y, -h).normalized()
	ArenaMeshKit._quad(st, a, b, c, d, slope_n)
	ArenaMeshKit._quad(st, e, f, c, d, Vector3(0, 0, 1))
	ArenaMeshKit._tri(st, a, e, d, Vector3(-1, 0, 0))
	ArenaMeshKit._tri(st, b, f, c, Vector3(1, 0, 0))
	ArenaMeshKit._quad(st, a, b, f, e, Vector3.DOWN)
	var mesh := st.commit()
	ArenaMeshKit.add(root, mesh, surface(2, Color("#7A8088"), Color.GRAY, Color("#8C3B2B"), {"cell": Vector2(20, 20), "seam": 0.0}))
	for sx in [-1.0, 1.0]:
		ArenaMeshKit.add(root, ArenaMeshKit.tube(PackedVector3Array([Vector3(sx * hw, by + 0.02, -hd), Vector3(sx * hw, by + h + 0.02, hd)]), 0.035, 8), toon(Color("#F7E04A"), 0.5))
	ArenaMeshKit.box(root, Vector3(s.x, 0.06, 0.12), toon(Color("#F7E04A"), 0.5), Vector3(0, by + h - 0.01, hd - 0.05), Vector3.ZERO, 0.015)
	var dm := decal(Color("#1A1D24"), 0, Vector2(s.x * 0.6, s.y * 0.5), ICONS["arrow"], {"base_alpha": 0.7, "hatch_period": 100.0, "icon_spacing": 10.0, "icon_size": 0.6})
	var q := QuadMesh.new()
	q.size = Vector2(s.x * 0.6, s.y * 0.5)
	ArenaMeshKit.add(root, q, dm, Vector3(0, by + h * 0.5 + 0.03, 0), Vector3(-PI * 0.5 + atan2(h, s.y), 0, 0), Vector3.ONE, false)


static func _scrap(root: Node3D, s: Vector2, h: float, by: float, seed: int, layers: int) -> void:
	var paints := [Color("#5E8C8A"), Color("#8C3B2B"), Color("#B89A3E"), Color("#6E6A66"), Color("#3E5C76"), Color("#7A4B6E")]
	var y := by
	var lh := h / float(layers)
	for k in layers:
		var col: Color = paints[(seed + k * 2) % paints.size()]
		var w := s.x * (0.94 - 0.05 * float(k % 2))
		var d := s.y * (0.96 - 0.04 * float(k))
		var yaw := deg_to_rad(float(((seed * 7 + k * 13) % 9) - 4))
		ArenaMeshKit.box(root, Vector3(w, lh * 0.94, d), paint(col, 0.6, 0.4, Color("#5E3426")), Vector3(0.04 * float(k % 2), y + lh * 0.5, 0.03 * float(k % 3) - 0.03), Vector3(0, yaw, 0.03 * float(k % 2)), 0.06)
		# crushed details: window glass strip, bumper, light
		ArenaMeshKit.box(root, Vector3(w * 0.6, lh * 0.18, 0.03), toon(Color("#9BC7D1"), 0.15, 0.3), Vector3(0.1, y + lh * 0.62, d * 0.5 + 0.01), Vector3(0, yaw, 0.04), 0.01)
		ArenaMeshKit.box(root, Vector3(w * 0.9, lh * 0.12, 0.05), toon(Color("#C8CCD2"), 0.3, 0.8), Vector3(0, y + lh * 0.18, -d * 0.5 - 0.01), Vector3(0, yaw, 0.0), 0.02)
		y += lh
	if layers > 1:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.16
		tm.outer_radius = 0.34
		ArenaMeshKit.add(root, tm, toon(Color("#1C1C20"), 0.85), Vector3(s.x * 0.42, by + h * 0.55, s.y * 0.35), Vector3(PI * 0.5, 0.3, 0.2), Vector3(1, 1.4, 1))
	for sx in [-0.25, 0.25]:
		ArenaMeshKit.box(root, Vector3(0.05, h + 0.02, s.y + 0.04), toon(Color("#2B2F3A"), 0.5, 0.5), Vector3(s.x * sx, by + h * 0.5, 0), Vector3.ZERO, 0.01)
	icon_plate(root, "grit", Color("#B8905E"), Vector3(0, by + h * 0.5, s.y * 0.5 + 0.04), Vector3.ZERO, 0.32)


static func _mat(root: Node3D, s: Vector2) -> void:
	var rubber := surface(7, Color("#1E1E22"), Color.GRAY, Color.BLACK, {"use_uv": true})
	ArenaMeshKit.box(root, Vector3(s.x, 0.03, s.y), rubber, Vector3(0, 0.015, 0), Vector3.ZERO, 0.01)
	var poly := PackedVector2Array([Vector2(-s.x * 0.5, -s.y * 0.5), Vector2(s.x * 0.5, -s.y * 0.5), Vector2(s.x * 0.5, s.y * 0.5), Vector2(-s.x * 0.5, s.y * 0.5)])
	var band := MeshInstance3D.new()
	band.mesh = ArenaMeshKit.outline_band(poly, 0.03, 0.08, 0.032)
	band.material_override = toon(Color("#F7E04A"), 0.6)
	root.add_child(band)
	ArenaMeshKit.label(root, "INSULATED", 72, Color("#F7E04A"), Vector3(0, 0.034, 0), Vector3(-PI * 0.5, 0, 0), Color(0, 0, 0, 0), "res://assets/fonts/BarlowCondensed-900.woff2", 0.003)


static func _block(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var conc := surface(1, Color("#A3A39B"), Color("#8E8E86"), Color("#6E5A4A"), {"use_uv": false, "cell": Vector2(30, 30)})
	ArenaMeshKit.box(root, Vector3(s.x, h, s.y), conc, Vector3(0, by + h * 0.5, 0), Vector3.ZERO, 0.08)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.1
	ring.outer_radius = 0.16
	ArenaMeshKit.add(root, ring, toon(Color("#2B2F3A"), 0.4, 0.7), Vector3(0, by + h + 0.02, 0), Vector3(PI * 0.5, 0, 0))
	ArenaMeshKit.box(root, Vector3(s.x * 0.98, 0.05, s.y * 0.98), toon(Color("#C9A227"), 0.6), Vector3(0, by + h * 0.3, 0), Vector3.ZERO, 0.02)


static func _hvac(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var shell := paint(Color("#9FA6AD"), 0.45, 0.5)
	var dark := toon(Color("#2B2F3A"), 0.5, 0.4)
	ArenaMeshKit.box(root, Vector3(s.x + 0.1, 0.12, s.y + 0.1), dark, Vector3(0, by + 0.06, 0), Vector3.ZERO, 0.03)
	ArenaMeshKit.box(root, Vector3(s.x, h - 0.12, s.y), shell, Vector3(0, by + 0.12 + (h - 0.12) * 0.5, 0), Vector3.ZERO, 0.05)
	for k in 5:
		ArenaMeshKit.box(root, Vector3(s.x * 0.8, 0.035, 0.04), dark, Vector3(0, by + 0.3 + k * 0.1, s.y * 0.5 + 0.01), Vector3(0.4, 0, 0), 0.008)
		ArenaMeshKit.box(root, Vector3(0.04, 0.035, s.y * 0.8), dark, Vector3(s.x * 0.5 + 0.01, by + 0.3 + k * 0.1, 0), Vector3(0, 0, 0.4), 0.008)
	var ring := TorusMesh.new()
	ring.inner_radius = s.x * 0.3
	ring.outer_radius = s.x * 0.36
	ArenaMeshKit.add(root, ring, dark, Vector3(0, by + h + 0.01, 0))
	var spin := Node3D.new()
	spin.position = Vector3(0, by + h + 0.02, 0)
	root.add_child(spin)
	for k2 in 4:
		ArenaMeshKit.box(spin, Vector3(s.x * 0.55, 0.02, 0.09), toon(Color("#5B6168"), 0.4, 0.6), Vector3.ZERO, Vector3(0.3, TAU * k2 / 8.0, 0), 0.01)
	root.set_meta("spin", spin)
	root.set_meta("spin_axis", Vector3.UP)
	root.set_meta("spin_rate", 6.0)
	ArenaMeshKit.add(root, ArenaMeshKit.tube(PackedVector3Array([Vector3(-s.x * 0.5, by + 0.5, -s.y * 0.3), Vector3(-s.x * 0.5 - 0.25, by + 0.5, -s.y * 0.3), Vector3(-s.x * 0.5 - 0.25, by + 0.02, -s.y * 0.3)]), 0.06, 10), paint(Color("#C9A227"), 0.5, 0.4))
	ArenaMeshKit.label(root, "GLANDCO HVAC", 56, Color("#2B2F3A"), Vector3(0, by + h * 0.88, s.y * 0.5 + 0.012), Vector3.ZERO, Color(0, 0, 0, 0), "res://assets/fonts/BarlowCondensed-700.woff2", 0.003)


static func _tower_leg(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var steel := paint(Color("#6E5A4A"), 0.6, 0.5, Color("#8C3B2B"))
	ArenaMeshKit.box(root, Vector3(0.7, 0.08, 0.7), toon(Color("#2B2F3A"), 0.5, 0.5), Vector3(0, by + 0.04, 0), Vector3.ZERO, 0.02)
	ArenaMeshKit.cyl(root, s.x * 0.5, h + 6.0, steel, Vector3(0, by + (h + 6.0) * 0.5, 0), Vector3.ZERO, 14, 0.02)
	for k in 6:
		ArenaMeshKit.add(root, ArenaMeshKit.cylinder(s.x * 0.56, s.x * 0.56, 0.06, 14, 0.01), toon(Color("#4A4038"), 0.5, 0.6), Vector3(0, by + 0.6 + k * 1.6, 0))
	ArenaMeshKit.add(root, ArenaMeshKit.tube(PackedVector3Array([Vector3(0, by + 1.2, 0), Vector3(-1.6, by + 4.8, 1.6)]), 0.04, 6), steel)
	ArenaMeshKit.add(root, ArenaMeshKit.tube(PackedVector3Array([Vector3(0, by + 3.6, 0), Vector3(-1.6, by + 7.4, 1.6)]), 0.04, 6), steel)


static func _railing(root: Node3D, s: Vector2, h: float, by: float) -> void:
	var paint_m := paint(Color("#E0B42A"), 0.55, 0.4, Color("#7A3E2A"))
	var n := maxi(2, int(s.x / 1.25) + 1)
	for k in n:
		var x := -s.x * 0.5 + s.x * float(k) / float(n - 1)
		ArenaMeshKit.cyl(root, 0.035, h, paint_m, Vector3(x, by + h * 0.5, 0), Vector3.ZERO, 8, 0.01)
		ArenaMeshKit.box(root, Vector3(0.14, 0.03, 0.14), toon(Color("#2B2F3A"), 0.5, 0.5), Vector3(x, by + 0.015, 0), Vector3.ZERO, 0.01)
	for yy in [by + h - 0.03, by + h * 0.5]:
		ArenaMeshKit.add(root, ArenaMeshKit.tube(PackedVector3Array([Vector3(-s.x * 0.5, yy, 0), Vector3(s.x * 0.5, yy, 0)]), 0.04, 8), paint_m)


# =====================================================================================
# Markers (editor helpers; goals and wave gates are also shown in matches as cosmetic set pieces)
# =====================================================================================

static func marker_color(name_: String, team: int) -> Color:
	if team >= 0 and team < TEAM_COLORS.size():
		return TEAM_COLORS[team]
	match name_:
		"spawn": return Color("#F2F2EC")
		"boss": return Color("#B06BFF")
		"spotlight_anchor": return Color("#FFD27A")
		"ball_spawn": return Color("#FF9F43")
		"wave_gate": return Color("#8BD426")
		"unit_spawn": return Color("#8BD426")
		"respawn": return Color("#35C1C9")
		"goal": return Color("#F2F2EC")
	return Color.WHITE


static func _marker(root: Node3D, def: Dictionary, item: Dictionary) -> void:
	var name_ := str(def["marker"]["name"])
	var team := int(item.get("team", -1))
	var c := marker_color(name_, team)
	var g := glow(c, 1.2)
	match name_:
		"goal":
			var sz: Vector3 = def["marker"]["size"]
			var frame := paint(c.lerp(Color.WHITE, 0.2), 0.4, 0.4)
			for sx in [-1.0, 1.0]:
				ArenaMeshKit.cyl(root, 0.06, sz.y, frame, Vector3(sx * sz.x * 0.5, sz.y * 0.5, 0), Vector3.ZERO, 10, 0.02)
			ArenaMeshKit.add(root, ArenaMeshKit.tube(PackedVector3Array([Vector3(-sz.x * 0.5, sz.y, 0), Vector3(sz.x * 0.5, sz.y, 0)]), 0.06, 10), frame)
			var q := QuadMesh.new()
			q.size = Vector2(sz.x, sz.y)
			ArenaMeshKit.add(root, q, fence_mat(c.lerp(Color.WHITE, 0.5)), Vector3(0, sz.y * 0.5, -0.25))
			var dm := decal(c, 0, Vector2(sz.x, 0.6), 0, {"base_alpha": 0.6})
			decal_quad(root, dm, Vector2(sz.x, 0.6), Vector3(0, 0, 0.3))
		"wave_gate":
			# a minion door: striped steel jambs, a chain-link door panel, a lit GATE sign
			var sz2: Vector3 = def["marker"]["size"]
			var frame2 := paint(Color("#5B6168"), 0.45, 0.6)
			var stripes := surface(10, Color.WHITE, Color.WHITE, Color.WHITE, {"seam_a": Color("#F7E04A"), "seam_b": Color("#1E1E24")})
			for sx2 in [-1.0, 1.0]:
				ArenaMeshKit.box(root, Vector3(0.14, sz2.y, 0.22), stripes, Vector3(sx2 * (sz2.x * 0.5 + 0.07), sz2.y * 0.5, 0), Vector3.ZERO, 0.03)
			ArenaMeshKit.box(root, Vector3(sz2.x + 0.28, 0.16, 0.22), frame2, Vector3(0, sz2.y + 0.08, 0), Vector3.ZERO, 0.03)
			var door := QuadMesh.new()
			door.size = Vector2(sz2.x, sz2.y - 0.05)
			ArenaMeshKit.add(root, door, fence_mat(Color("#C9CED6")), Vector3(0, sz2.y * 0.5, 0.02))
			for yy in [0.12, sz2.y * 0.5, sz2.y - 0.12]:
				ArenaMeshKit.add(root, ArenaMeshKit.tube(PackedVector3Array([Vector3(-sz2.x * 0.5, yy, 0.02), Vector3(sz2.x * 0.5, yy, 0.02)]), 0.03, 6), frame2)
			ArenaMeshKit.box(root, Vector3(0.7, 0.22, 0.05), g, Vector3(0, sz2.y + 0.3, 0.06), Vector3.ZERO, 0.01)
			ArenaMeshKit.label(root, "GATE", 64, Color("#10140A"), Vector3(0, sz2.y + 0.3, 0.09), Vector3.ZERO, Color(0, 0, 0, 0), "res://assets/fonts/BarlowCondensed-900.woff2", 0.003)
		_:
			var ring := TorusMesh.new()
			ring.inner_radius = 0.34
			ring.outer_radius = 0.42
			ArenaMeshKit.add(root, ring, g, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.3, 1), false)
			var dm2 := decal(c, 1, Vector2(1.0, 1.0), 0, {"base_alpha": 0.25, "hatch_period": 0.2})
			decal_quad(root, dm2, Vector2(1.0, 1.0))
			match name_:
				"spawn":
					ArenaMeshKit.add(root, ArenaMeshKit.cylinder(0.0, 0.16, 0.34, 3, 0.0), g, Vector3(0, 0.06, 0.48), Vector3(PI * 0.5, 0, 0), Vector3(1, 1, 0.35), false)
					ArenaMeshKit.add(root, ArenaMeshKit.cylinder(0.05, 0.12, 0.9, 10, 0.02), toon(c.darkened(0.15), 0.5), Vector3(0, 0.45, 0), Vector3.ZERO, Vector3.ONE, false)
					ArenaMeshKit.add(root, SphereMesh.new(), toon(c, 0.4), Vector3(0, 1.0, 0), Vector3.ZERO, Vector3(0.24, 0.24, 0.24), false)
				"boss":
					var crown := Node3D.new()
					crown.position = Vector3(0, 1.1, 0)
					root.add_child(crown)
					ArenaMeshKit.add(crown, ArenaMeshKit.cylinder(0.28, 0.25, 0.16, 16, 0.02, false), toon(c, 0.35, 0.5), Vector3.ZERO)
					for k in 5:
						var a := TAU * k / 5.0
						ArenaMeshKit.add(crown, ArenaMeshKit.cylinder(0.0, 0.06, 0.2, 6, 0.0), toon(c, 0.35, 0.5), Vector3(cos(a) * 0.26, 0.17, sin(a) * 0.26))
					ArenaMeshKit.add(root, ArenaMeshKit.cylinder(0.04, 0.06, 1.0, 8, 0.01), toon(Color("#2B2F3A"), 0.5), Vector3(0, 0.5, 0))
				"spotlight_anchor":
					for k2 in 8:
						var a2 := TAU * k2 / 8.0
						ArenaMeshKit.box(root, Vector3(0.05, 0.02, 0.3), g, Vector3(cos(a2) * 0.6, 0.02, sin(a2) * 0.6), Vector3(0, -a2 + PI * 0.5, 0), 0.005)
					ArenaMeshKit.add(root, ArenaMeshKit.cylinder(0.12, 0.22, 0.22, 14, 0.02), toon(Color("#2B2F3A"), 0.4, 0.5), Vector3(0, 0.11, 0))
					ArenaMeshKit.add(root, ArenaMeshKit.floor_disc(0.12, 14), g, Vector3(0, 0.225, 0))
				"ball_spawn":
					ArenaMeshKit.add(root, SphereMesh.new(), toon(Color("#C9B39A"), 0.8), Vector3(0, 0.5, 0), Vector3(0.3, 0.6, 0.1), Vector3(0.9, 0.9, 0.9))
					var tape := TorusMesh.new()
					tape.inner_radius = 0.43
					tape.outer_radius = 0.47
					ArenaMeshKit.add(root, tape, toon(Color("#9FA6AD"), 0.5), Vector3(0, 0.5, 0), Vector3(0.2, 0, 0.4))
				"unit_spawn":
					ArenaMeshKit.add(root, ArenaMeshKit.cylinder(0.15, 0.15, 0.32, 16, 0.02), toon(Color("#8BD426"), 0.3), Vector3(0, 0.2, 0))
					for k3 in 5:
						var a3 := TAU * k3 / 5.0
						ArenaMeshKit.add(root, ArenaMeshKit.cylinder(0.0, 0.05, 0.16, 6, 0.0), toon(Color("#C9A227"), 0.3, 0.6), Vector3(cos(a3) * 0.13, 0.44, sin(a3) * 0.13))
				"respawn":
					for k4 in 3:
						var a4 := TAU * k4 / 3.0
						ArenaMeshKit.add(root, ArenaMeshKit.cylinder(0.0, 0.1, 0.22, 3, 0.0), g, Vector3(cos(a4) * 0.38, 0.05, sin(a4) * 0.38), Vector3(PI * 0.5, -a4, 0), Vector3(1, 1, 0.3), false)
	var lbl := Label3D.new()
	lbl.text = _marker_text(name_, team)
	lbl.font_size = 40
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate = c
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.05, 0.05, 0.08)
	lbl.position = Vector3(0, 1.45 if name_ != "goal" else 2.4, 0)
	lbl.font = load("res://assets/fonts/BarlowCondensed-900.woff2")
	root.add_child(lbl)
	root.set_meta("label", lbl)


static func _marker_text(name_: String, team: int) -> String:
	var t := ""
	if team >= 0:
		t = " " + ["A", "B", "C", "D"][clampi(team, 0, 3)]
	match name_:
		"spawn": return "SPAWN" + t
		"boss": return "BOSS"
		"spotlight_anchor": return "SPOTLIGHT"
		"goal": return "GOAL" + t
		"ball_spawn": return "BALL"
		"wave_gate": return "WAVE GATE"
		"unit_spawn": return "UNIT"
		"respawn": return "RESPAWN"
	return name_.to_upper()
