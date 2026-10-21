class_name FxKit
extends RefCounted
## Shared building blocks of the v0.9.17 ability VFX (docs/art/VFX.md): the effect shaders,
## procedural meshes for thrown pieces, and the particle presets every fighter's effects are made
## from. View-only; nothing here reads or changes the simulation.
##
## Element language (docs/design/ART_DIRECTION.md §6): Scorch rises in pointed tongues and sparks,
## Brine falls in rounded drops and ripples outward, Static snaps in zigzags, Sludge sags in lumpy
## blobs and pops bubbles, Grit tumbles in hexagonal chunks and settles as dust, Gale swirls in
## spirals and streaks. v0.9.17 adds Scrap (crisp four-point bursts, struck-metal sparks) and
## Spectral (lantern wisps and tolling rings).

const SHADER_DIR := "res://src/view/shaders/"

## area/zone floor pattern per element (fx_area.gdshader `style`)
const AREA_STYLE := {"scorch": 1, "brine": 2, "gale": 3, "grit": 4, "sludge": 5, "static": 6, "spectral": 7, "scrap": 8}
## covering (mix) instead of glowing (add) floor patterns
const AREA_COVERS := {"brine": true, "grit": true, "sludge": true}
## How each element is painted so it reads on the bright cage canvas as well as on dark floors:
## a saturated paint colour, an HDR glow colour (bloomed by the arena's glow pass) and the stain
## its footprint leaves (scorch marks, wet floor, goo, dust).
const PAINT := {"scorch": Color(0.95, 0.36, 0.08), "brine": Color(0.13, 0.48, 0.88), "static": Color(0.98, 0.78, 0.1),
	"sludge": Color(0.36, 0.62, 0.08), "grit": Color(0.58, 0.42, 0.26), "gale": Color(0.27, 0.68, 0.72),
	"scrap": Color(0.88, 0.48, 0.22), "spectral": Color(0.52, 0.32, 0.95)}
const GLOW := {"scorch": Color(1.0, 0.72, 0.28), "brine": Color(0.62, 0.88, 1.0), "static": Color(1.0, 0.95, 0.5),
	"sludge": Color(0.68, 0.95, 0.22), "grit": Color(0.9, 0.78, 0.55), "gale": Color(0.82, 1.0, 1.0),
	"scrap": Color(1.0, 0.84, 0.55), "spectral": Color(0.82, 0.72, 1.0)}
const STAIN := {"scorch": Color(0.18, 0.07, 0.03), "brine": Color(0.08, 0.25, 0.45), "static": Color(0.3, 0.25, 0.05),
	"sludge": Color(0.16, 0.26, 0.03), "grit": Color(0.32, 0.23, 0.14), "gale": Color(0.25, 0.5, 0.52),
	"scrap": Color(0.28, 0.16, 0.08), "spectral": Color(0.22, 0.12, 0.42)}

static var _shaders := {}
static var _meshes := {}
static var _draw_mats := {}


static func shader(name_: String) -> Shader:
	if not _shaders.has(name_):
		_shaders[name_] = load(SHADER_DIR + name_ + ".gdshader")
	return _shaders[name_]


## Element colours (ELEMENTS.md), with a light "hot" partner for cores and crests.
static func el_color(el: String) -> Color:
	if el == "":
		return Color(1.0, 0.9, 0.6)
	return Elements.color(el)


static func el_paint(el: String) -> Color:
	return PAINT.get(el, el_color(el))


static func el_glow(el: String) -> Color:
	return GLOW.get(el, el_hot(el))


static func el_hot(el: String) -> Color:
	match el:
		"scorch":
			return Color(1.0, 0.9, 0.55)
		"brine":
			return Color(0.85, 0.97, 1.0)
		"static":
			return Color(1.0, 1.0, 0.85)
		"sludge":
			return Color(0.85, 1.0, 0.45)
		"grit":
			return Color(0.95, 0.85, 0.65)
		"gale":
			return Color(1.0, 1.0, 1.0)
		"scrap":
			return Color(1.0, 0.93, 0.7)
		"spectral":
			return Color(0.95, 0.9, 1.0)
	return Color(1, 1, 1)


# ---- materials ---------------------------------------------------------------------------

## A fresh floor-footprint material (fx_area.gdshader). shape: circle|cone|line|ring|cone_back.
static func area_material(el: String, shape: String, radius: float, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("fx_area")
	m.set_shader_parameter("shape", {"circle": 0, "cone": 1, "line": 2, "ring": 3, "cone_back": 4}.get(shape, 0))
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("half_angle", deg_to_rad(float(params.get("cone_deg", 60.0))) * 0.5)
	m.set_shader_parameter("length_m", float(params.get("length", 3.0)))
	m.set_shader_parameter("width_m", float(params.get("width", 1.0)))
	m.set_shader_parameter("inner", float(params.get("inner", 0.0)))
	m.set_shader_parameter("color", params.get("color", el_paint(el)))
	m.set_shader_parameter("color2", params.get("color2", el_glow(el)))
	m.set_shader_parameter("stain", params.get("stain", STAIN.get(el, Color(0.2, 0.18, 0.15))))
	m.set_shader_parameter("stain_a", float(params.get("stain_a", 0.22)))
	m.set_shader_parameter("style", int(params.get("style", AREA_STYLE.get(el, 0))))
	# "additive" (0 covers .. 1 glows) is kept as shorthand for cover/glow
	var add := float(params.get("additive", 0.0 if AREA_COVERS.has(el) else 0.6))
	m.set_shader_parameter("cover", float(params.get("cover", lerpf(0.95, 0.55, add))))
	m.set_shader_parameter("glow_k", float(params.get("glow_k", lerpf(0.2, 1.1, add))))
	m.set_shader_parameter("fill", float(params.get("fill", 0.35)))
	m.set_shader_parameter("speed", float(params.get("speed", 1.0)))
	m.set_shader_parameter("seed", randf() * 10.0)
	m.set_shader_parameter("progress", 0.0)
	m.set_shader_parameter("fade", 1.0)
	m.set_shader_parameter("front", float(params.get("front", 0.8)))
	return m


## A fresh animated-surface material (fx_flow.gdshader).
static func flow_material(c: Color, c2: Color, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("fx_flow")
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("color2", c2)
	# "additive" (0 covers .. 1 glows) is shorthand for cover/glow: even glowing pieces keep some
	# paint, or they would vanish on the bright canvas
	var add := float(params.get("additive", 0.5))
	m.set_shader_parameter("cover", lerpf(0.95, 0.45, add))
	m.set_shader_parameter("glow_k", lerpf(0.2, 1.2, add))
	for k in params:
		if k != "additive":
			m.set_shader_parameter(k, params[k])
	m.set_shader_parameter("seed", randf() * 10.0)
	return m


## Draw material of fx_puff particles (shared per look/blend; colours come from the particles).
static func puff_material(look: int, additive: bool, hot := 0.0) -> ShaderMaterial:
	var key := "%d|%s|%.2f" % [look, additive, hot]
	if not _draw_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = shader("fx_puff_draw")
		m.set_shader_parameter("look", look)
		m.set_shader_parameter("cover", 0.6 if additive else 1.0)
		m.set_shader_parameter("glow_k", 1.0 if additive else 0.1)
		m.set_shader_parameter("hot", hot)
		_draw_mats[key] = m
	return _draw_mats[key]


## Draw material of fx_debris pieces: lit solids (rock, shard, goo, drop, feather) or glowing
## streaks (cinders, sparks).
static func piece_material(kind: String) -> Material:
	if _draw_mats.has("piece:" + kind):
		return _draw_mats["piece:" + kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match kind:
		"glow":
			# sparks and cinders: unshaded streaks in their (HDR) particle colour, opaque enough to read
			# on the bright canvas, bright enough to bloom
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"drop":
			m.roughness = 0.08
			m.metallic_specular = 0.9
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.rim_enabled = true
			m.rim = 0.6
		"goo":
			m.roughness = 0.22
			m.metallic_specular = 0.8
			m.rim_enabled = true
			m.rim = 0.4
			m.emission_enabled = true
			m.emission = Color(0.12, 0.22, 0.02)
		"shard":
			m.roughness = 0.3
			m.metallic = 0.75
		"feather":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED     # flat cream flakes read at any light
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			m.roughness = 0.92
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_draw_mats["piece:" + kind] = m
	return m


# ---- meshes --------------------------------------------------------------------------------

## Unit-size meshes for thrown pieces (scaled by the particle).
static func piece_mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	match kind:
		"hex":
			mesh = _hex_chunk()
		"drop", "goo":
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 8
			sm.rings = 5
			mesh = sm
		"shard":
			var pm := PrismMesh.new()
			pm.size = Vector3(0.5, 1.0, 0.12)
			mesh = pm
		"streak":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.35, 1.0, 0.35)
			mesh = bm
		"feather":
			var qm := QuadMesh.new()
			qm.size = Vector2(0.35, 1.0)
			mesh = qm
		_:
			var q := QuadMesh.new()
			q.size = Vector2(1, 1)
			mesh = q
	_meshes[kind] = mesh
	return mesh


## A chunky hexagonal grain (Grit's shape), slightly irregular, flat shaded.
static func _hex_chunk() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0
		var r := 0.5 * rng.randf_range(0.82, 1.0)
		top.append(Vector3(cos(a) * r * 0.8, 0.32 + rng.randf_range(-0.06, 0.08), sin(a) * r * 0.8))
		bot.append(Vector3(cos(a) * r, -0.3, sin(a) * r))
	var ctop := Vector3(0, 0.42, 0)
	var cbot := Vector3(0, -0.34, 0)
	for i in 6:
		var j := (i + 1) % 6
		_tri(st, ctop, top[j], top[i])
		_tri(st, cbot, bot[i], bot[j])
		_tri(st, top[i], top[j], bot[j])
		_tri(st, top[i], bot[j], bot[i])
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_smooth_group(-1)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## A thin ring wall (open cylinder) of radius 1 and height 1, UV u around, v up. Scaled per use.
static func wall_mesh(segments := 48, top_scale := 1.0) -> ArrayMesh:
	var key := "wall:%d:%.2f" % [segments, top_scale]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var u0 := float(i) / segments
		var u1 := float(i + 1) / segments
		var b0 := Vector3(cos(a0), 0, sin(a0))
		var b1 := Vector3(cos(a1), 0, sin(a1))
		var t0 := Vector3(cos(a0) * top_scale, 1, sin(a0) * top_scale)
		var t1 := Vector3(cos(a1) * top_scale, 1, sin(a1) * top_scale)
		for v in [[b0, Vector2(u0, 0)], [t1, Vector2(u1, 1)], [t0, Vector2(u0, 1)], [b0, Vector2(u0, 0)], [b1, Vector2(u1, 0)], [t1, Vector2(u1, 1)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m


## A flat square of edge 1 in XZ (floor footprints), centred on the origin.
static func floor_quad() -> Mesh:
	if not _meshes.has("floor"):
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		_meshes["floor"] = pm
	return _meshes["floor"]


## A spiral ribbon (vortex) of `turns` around a funnel from radius r0 (bottom) to r1 (top), height 1.
static func spiral_mesh(turns: float, r0: float, r1: float, width := 0.18, steps := 64) -> ArrayMesh:
	var key := "spiral:%.2f:%.2f:%.2f:%.2f" % [turns, r0, r1, width]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	for i in steps + 1:
		var k := float(i) / steps
		var ang := TAU * turns * k
		var r := lerpf(r0, r1, k)
		var y := k
		var p := Vector3(cos(ang) * r, y, sin(ang) * r)
		var a := p + Vector3(0, -width * 0.5, 0)
		var b := p + Vector3(0, width * 0.5, 0)
		if i > 0:
			var u0 := float(i - 1) / steps
			var u1 := k
			for v in [[prev_a, Vector2(u0, 0)], [b, Vector2(u1, 1)], [prev_b, Vector2(u0, 1)], [prev_a, Vector2(u0, 0)], [a, Vector2(u1, 0)], [b, Vector2(u1, 1)]]:
				st.set_uv(v[1])
				st.add_vertex(v[0])
		prev_a = a
		prev_b = b
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m


## A ground-hugging crest (rolling wave / rock ridge) of length 1 along +Z, width 1, height 1:
## a half-pipe arched across X, UV u along, v across.
static func crest_mesh(steps_u := 12, steps_v := 10) -> ArrayMesh:
	if _meshes.has("crest"):
		return _meshes["crest"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps_u:
		for j in steps_v:
			var quad := []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u := float(c[0]) / steps_u
				var v := float(c[1]) / steps_v
				var ang := PI * v
				quad.append([Vector3(-cos(ang) * 0.5, sin(ang), u - 0.5), Vector2(u, v)])
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_uv(quad[idx][1])
				st.add_vertex(quad[idx][0])
	st.generate_normals()
	var m := st.commit()
	_meshes["crest"] = m
	return m
