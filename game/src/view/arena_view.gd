class_name ArenaView
extends Node3D
## Visual side of an ArenaDef (never changes gameplay): environment and lighting per base
## variant, the floor (with real pit holes), the base's set dressing (ArenaSetDressing), every
## prop and marker (ArenaPropVisuals), hazard footprints with ~1 s telegraphs, and the live
## animation of hazards/props read from the authoritative runtime (ArenaHazards.view_state() +
## "arena_*" sim events). Audio cues go through Audio.sfx (ids listed in docs/ARENAS_AND_EDITOR.md).
##
## Usage: build(arena) then either bind_sim(sim) (local matches; also auto-discovered from a
## parent exposing `sim`), or apply_state(state) each frame with a networked snapshot.
## MatchScene's legacy set_prop_transform(i, xf) contract is kept: index i matches
## sim.arena_nodes["props"][i] (ArenaBuilder body order).

## Audio.sfx ids (assets/audio/bank.json) per hazard / timed-prop transition. Ring-outs, wall
## slams and KOs are voiced by Audio's own match bridge, so they are not repeated here.
const AUDIO := {
	"tidal_gutter": {"telegraph": "hazard_gutter_telegraph", "active": "hazard_gutter_flood", "end": ""},
	"crane_hook": {"telegraph": "hazard_crane_telegraph", "active": "hazard_crane_drop", "end": ""},
	"plate_grid": {"telegraph": "hazard_plate_telegraph", "active": "hazard_plate_live", "end": ""},
	"crane_magnet": {"telegraph": "hazard_magnet_telegraph", "active": "hazard_magnet_pull", "end": "prop_break_metal"},
	"wind_gust": {"telegraph": "hazard_wind_telegraph", "active": "hazard_wind_gust", "end": ""},
	"steam_vent": {"telegraph": "zone_steam", "active": "react_steam_burst", "end": ""},
	"electric_plate": {"telegraph": "hazard_plate_telegraph", "active": "hazard_plate_live", "end": ""},
}
## Kept for older callers that pick a theme by name (legacy sandbox --theme).
const THEMES := {"can": "gullet", "rooftop": "rooftop", "scrapyard": "crusher", "sewer": "drydock"}

var arena: ArenaDef
var variant := {}
var editor_mode := false
var env: WorldEnvironment
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var rim_light: DirectionalLight3D
var spots: Array[SpotLight3D] = []
var prop_nodes: Array[Node3D] = []        ## by ArenaBuilder body index (legacy set_prop_transform contract)
var hazard_nodes: Array[Node3D] = []      ## legacy hazard zones (format-1 arenas)
var all_prop_nodes: Array[Node3D] = []    ## by ArenaDef.all_props() index
var marker_nodes: Array[Node3D] = []
var _static_root: Node3D
var _layout_root: Node3D
var _hazard_root: Node3D
var _crowd: MultiMeshInstance3D
var _logo_vp: SubViewport
var _out := {}
var _sim: MatchSim = null
var _remote := {}
var _auto_bind := true
var _cursor := 0
var _t := 0.0
var _crowd_energy := 0.3
var _crowd_boost := 0.0
var _rim_flash := 0.0
var _hz_decals := {}                      ## hazard id -> {kind: ..., mats/nodes}
var _last_phase := {}                     ## "h:<id>" / "p:<i>" -> phase
var _spawned := {}                        ## runtime prop index -> node (magnet bundles)
var _destroyed := {}
var _bag_chains: Array = []
var _debris: Array = []
var _shown_markers: Array = ["wave_gate"]
var _quality := {}


func build(a: ArenaDef) -> void:
	arena = a
	name = "ArenaView"
	variant = a.variant_def()
	if variant.is_empty():
		variant = {"key": "#FFD9A0", "rim": "#35C1C9", "bg": "#0A0D14", "fog": "#18202E", "fog_density": 0.02}
	_out = {"confetti": [], "pyro": [], "hooks": [], "gulls": [], "flags": [], "neon": [], "pigeons": []}
	_static_root = Node3D.new()
	_static_root.name = "Static"
	add_child(_static_root)
	_hazard_root = Node3D.new()
	_hazard_root.name = "Hazards"
	add_child(_hazard_root)
	_layout_root = Node3D.new()
	_layout_root.name = "Layout"
	add_child(_layout_root)
	_build_environment()
	_build_lights()
	_build_floor()
	match a.style:
		"drydock":
			ArenaSetDressing.build_drydock(_static_root, a, variant, _out)
		"crusher":
			ArenaSetDressing.build_crusher(_static_root, a, variant, _out)
		"rooftop":
			ArenaSetDressing.build_rooftop(_static_root, a, variant, _out)
		_:
			ArenaSetDressing.build_gullet(_static_root, a, variant, _out)
	_crowd = _out.get("crowd")
	if editor_mode:
		_hide_overhead(_static_root)
	_crowd_energy = float(variant.get("crowd_energy", 0.3))
	set_crowd_energy(_crowd_energy)
	_build_base_hazards()
	_build_layout()
	for h in a.hazards:
		hazard_nodes.append(_build_legacy_hazard(h))


func _c(key: String, fallback: String) -> Color:
	return Color.from_string(str(variant.get(key, fallback)), Color(fallback))


# =====================================================================================
# Environment & lights
# =====================================================================================

func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	var outdoor := arena.style in ["drydock", "rooftop", "crusher"]
	if outdoor:
		var sky := Sky.new()
		var sm := ShaderMaterial.new()
		sm.shader = load("res://src/view/shaders/arena_sky.gdshader")
		match arena.style:
			"drydock":
				sm.set_shader_parameter("top", _c("sky_top", "#8FA2AE"))
				sm.set_shader_parameter("horizon", _c("sky_horizon", "#DCE3E6"))
				sm.set_shader_parameter("bottom", Color("#6E7C84"))
				sm.set_shader_parameter("clouds", 0.8)
				sm.set_shader_parameter("cloud_color", Color("#E6EBEE"))
			"rooftop":
				sm.set_shader_parameter("top", Color("#070B16"))
				sm.set_shader_parameter("horizon", Color("#2A2342"))
				sm.set_shader_parameter("bottom", Color("#05070C"))
				sm.set_shader_parameter("stars", 1.0)
				sm.set_shader_parameter("moon", 1.0)
			_:
				sm.set_shader_parameter("top", Color("#08070C"))
				sm.set_shader_parameter("horizon", Color("#2A1A26"))
				sm.set_shader_parameter("bottom", Color("#050407"))
				sm.set_shader_parameter("stars", 0.5)
		sky.sky_material = sm
		e.background_mode = Environment.BG_SKY
		e.sky = sky
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	else:
		e.background_mode = Environment.BG_COLOR
		e.background_color = _c("bg", "#0A0D14")
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _c("ambient", "#2B2F3A")
	e.ambient_light_energy = float(variant.get("ambient_energy", 0.6))
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.0
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 0.9
	e.ssao_intensity = 1.6
	e.fog_enabled = true
	e.fog_light_color = _c("fog", "#18202E")
	e.fog_density = float(variant.get("fog_density", 0.02))
	e.fog_sky_affect = 0.15 if outdoor else 0.0
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.06
	env.environment = e
	add_child(env)


func _build_lights() -> void:
	key_light = DirectionalLight3D.new()
	key_light.light_color = _c("key", "#FFD9A0")
	key_light.light_energy = float(variant.get("key_energy", 1.15))
	key_light.shadow_enabled = true
	key_light.light_angular_distance = 1.5
	key_light.directional_shadow_max_distance = 32.0
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key_light.rotation_degrees = Vector3(-58, 28, 0)
	add_child(key_light)
	fill_light = DirectionalLight3D.new()
	fill_light.light_color = _c("ambient", "#2B2F3A").lightened(0.4)
	fill_light.light_energy = 0.3
	fill_light.rotation_degrees = Vector3(-25, 210, 0)
	add_child(fill_light)
	rim_light = DirectionalLight3D.new()
	rim_light.light_color = _c("rim", "#35C1C9")
	rim_light.light_energy = 0.75
	rim_light.rotation_degrees = Vector3(-12, 120, 0)
	add_child(rim_light)
	var ext := arena.extent()
	var r := maxf(ext.size.x, ext.size.y) * 0.5
	var spot_col := _c("spot", "#FFF1DA")
	var n := 4
	for i in n:
		var s := SpotLight3D.new()
		var a := TAU * i / float(n) + PI * 0.25
		s.position = Vector3(cos(a) * r * 0.7, 7.6, sin(a) * r * 0.7)
		s.look_at_from_position(s.position, Vector3(cos(a) * r * 0.1, 0, sin(a) * r * 0.1))
		s.light_color = spot_col if arena.style != "crusher" else _c("key", "#FFB347")
		s.light_energy = 4.5 if arena.style == "gullet" else (2.5 if arena.style == "rooftop" else 3.2)
		s.spot_range = 16.0
		s.spot_angle = 38.0
		s.spot_angle_attenuation = 0.6
		s.shadow_enabled = i < 2
		add_child(s)
		spots.append(s)


# =====================================================================================
# Floor
# =====================================================================================

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
	sb.border_color = Color("#8BD426")
	sb.set_border_width_all(22)
	sb.set_corner_radius_all(512)
	ring.add_theme_stylebox_override("panel", sb)
	ring.position = Vector2(70, 70)
	ring.size = Vector2(884, 884)
	root.add_child(ring)
	# the giant JUICE can
	var can := Panel.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color("#8BD426")
	cs.set_corner_radius_all(70)
	cs.border_color = Color("#C9A227")
	cs.set_border_width_all(18)
	can.add_theme_stylebox_override("panel", cs)
	can.position = Vector2(352, 210)
	can.size = Vector2(320, 560)
	root.add_child(can)
	for yy in [240, 700]:
		var rim := Panel.new()
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color("#C9A227")
		rs.set_corner_radius_all(30)
		rim.add_theme_stylebox_override("panel", rs)
		rim.position = Vector2(372, yy)
		rim.size = Vector2(280, 46)
		root.add_child(rim)
	var juice := Label.new()
	juice.text = "JUICE"
	juice.add_theme_font_override("font", load("res://assets/fonts/BarlowCondensed-900.woff2"))
	juice.add_theme_font_size_override("font_size", 150)
	juice.add_theme_color_override("font_color", Color("#1A1D24"))
	juice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	juice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	juice.size = Vector2(560, 200)
	juice.position = Vector2(232, 390)
	juice.rotation = -PI * 0.5
	juice.pivot_offset = Vector2(280, 100)
	root.add_child(juice)
	var brand := Label.new()
	brand.text = "GLANDCO"
	brand.add_theme_font_override("font", load("res://assets/fonts/BarlowCondensed-900.woff2"))
	brand.add_theme_font_size_override("font_size", 96)
	brand.add_theme_color_override("font_color", Color("#1D2140"))
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.size = Vector2(1024, 120)
	brand.position = Vector2(0, 800)
	root.add_child(brand)
	var top := Label.new()
	top.text = "CRITTERWEIGHT"
	top.add_theme_font_override("font", load("res://assets/fonts/BarlowCondensed-700.woff2"))
	top.add_theme_font_size_override("font_size", 72)
	top.add_theme_color_override("font_color", Color("#8C3B2B"))
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.size = Vector2(1024, 100)
	top.position = Vector2(0, 110)
	root.add_child(top)
	return _logo_vp.get_texture()


func _pit_rects() -> Array:
	var out := []
	for p in arena.all_props():
		var def := ArenaCatalog.prop(str(p["type"]))
		if not def.is_empty() and str(def["behaviour"]) == "pit":
			out.append(ArenaCatalog.footprint_aabb(p, def))
	return out


## Floor top mesh: the boundary polygon, split around pit holes when there are any.
func _floor_mesh(holes: Array) -> ArrayMesh:
	var poly := arena.boundary_polygon()
	if holes.is_empty():
		return ArenaMeshKit.slab(poly, 0.0, -0.06)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box in ArenaBuilder.subtract_rects(arena.extent(), holes):
		var b: Rect2 = box
		var bp := PackedVector2Array([b.position, Vector2(b.end.x, b.position.y), b.end, Vector2(b.position.x, b.end.y)])
		for piece in Geometry2D.intersect_polygons(bp, poly):
			var tri := Geometry2D.triangulate_polygon(piece)
			for k in range(0, tri.size(), 3):
				var p0: Vector2 = piece[tri[k]]
				var p1: Vector2 = piece[tri[k + 1]]
				var p2: Vector2 = piece[tri[k + 2]]
				ArenaMeshKit._tri(st, Vector3(p0.x, 0, p0.y), Vector3(p1.x, 0, p1.y), Vector3(p2.x, 0, p2.y), Vector3.UP)
	return st.commit()


func _build_floor() -> void:
	var logo: Texture2D = _make_logo_texture() if arena.style == "gullet" else null
	var fm := ArenaSetDressing.floor_material(arena, logo)
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	mi.mesh = _floor_mesh(_pit_rects())
	mi.material_override = fm
	_static_root.add_child(mi)
	if arena.style != "rooftop" and arena.style != "gullet":
		var under := MeshInstance3D.new()
		under.mesh = ArenaMeshKit.floor_quad(arena.extent().size + Vector2(6, 6))
		under.material_override = Materials.toon(Color("#121316"), 1.0)
		under.position = Vector3(arena.extent().get_center().x, -0.08, arena.extent().get_center().y)
		_static_root.add_child(under)


# =====================================================================================
# Base hazards (static footprints + animated parts)
# =====================================================================================

func _build_base_hazards() -> void:
	for h in arena.hazard_defs():
		var id := str(h.get("id", ""))
		match str(h.get("type", "")):
			"tidal_gutter":
				var r := arena.strip_rect(h)
				var m := ArenaPropVisuals.decal(ArenaPropVisuals.element_color("brine"), 0, r.size, ArenaPropVisuals.ICONS["brine"], {"icon_spacing": 2.0, "base_alpha": 0.38})
				ArenaPropVisuals.decal_quad(_hazard_root, m, r.size, Vector3(r.get_center().x, 0.0, r.get_center().y))
				_hz_decals[id] = {"mats": [m]}
			"crane_hook":
				var mats := []
				for s in h.get("spots", []):
					var sp: Vector2 = s
					var d := float(h.get("radius", 0.75)) * 2.0
					var m2 := ArenaPropVisuals.decal(Color("#F2D27A"), 1, Vector2(d, d), ArenaPropVisuals.ICONS["hook"], {"icon_spacing": 10.0, "icon_size": 0.6, "base_alpha": 0.45})
					ArenaPropVisuals.decal_quad(_hazard_root, m2, Vector2(d, d), Vector3(sp.x, 0.0, sp.y))
					mats.append(m2)
				_hz_decals[id] = {"mats": mats}
			"plate_grid":
				var cells := arena.grid_cells(h)
				var mats2 := []
				var arcs := []
				for c in cells:
					var cr: Rect2 = c
					var m3 := ArenaPropVisuals.decal(ArenaPropVisuals.element_color("static"), 0, cr.size - Vector2(0.3, 0.3), ArenaPropVisuals.ICONS["static"], {"icon_spacing": 1.9, "base_alpha": 0.12, "outline_w": 0.1})
					ArenaPropVisuals.decal_quad(_hazard_root, m3, cr.size - Vector2(0.3, 0.3), Vector3(cr.get_center().x, 0.0, cr.get_center().y))
					mats2.append(m3)
				for k in 6:
					var arc := MeshInstance3D.new()
					arc.mesh = ArenaMeshKit.chamfer_box(Vector3(0.7, 0.04, 0.04), 0.0)
					arc.material_override = ArenaPropVisuals.glow(Color("#F7E04A"), 5.0)
					arc.visible = false
					arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_hazard_root.add_child(arc)
					arcs.append(arc)
				_hz_decals[id] = {"mats": mats2, "arcs": arcs, "cells": cells}
			"crane_magnet":
				var dia := float(h.get("radius", 3.0)) * 2.0
				var m4 := ArenaPropVisuals.decal(Color("#E04FB0"), 3, Vector2(dia, dia), ArenaPropVisuals.ICONS["magnet"], {"icon_spacing": 1.3, "base_alpha": 0.0})
				m4.render_priority = 2     # over the plate-grid decals it crosses
				var node := ArenaPropVisuals.decal_quad(_hazard_root, m4, Vector2(dia, dia))
				node.visible = false
				_hz_decals[id] = {"mats": [m4], "node": node}
			"wind_gust":
				# floor-shaped (never overhangs notches or edges); arrows rotate with the gust
				var ext := arena.extent()
				var m5 := ArenaPropVisuals.decal(Color("#CFF4F2"), 0, ext.size, ArenaPropVisuals.ICONS["arrow"], {"icon_spacing": 2.6, "base_alpha": 0.0, "outline_w": 0.0, "hatch_period": 100.0})
				var node2 := MeshInstance3D.new()
				node2.mesh = _floor_uv_mesh(arena.boundary_polygon(), ext, 0.014)
				node2.material_override = m5
				node2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node2.visible = false
				_hazard_root.add_child(node2)
				_hz_decals[id] = {"mats": [m5], "node": node2}


## Flat mesh of a polygon at height y whose UVs span `ext` (0..1), for floor-shaped decals.
static func _floor_uv_mesh(poly: PackedVector2Array, ext: Rect2, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := Geometry2D.triangulate_polygon(poly)
	for k in range(0, tri.size(), 3):
		var pts := [poly[tri[k]], poly[tri[k + 1]], poly[tri[k + 2]]]
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var c: Vector2 = pts[2]
		if (Vector3(b.x, 0, b.y) - Vector3(a.x, 0, a.y)).cross(Vector3(c.x, 0, c.y) - Vector3(a.x, 0, a.y)).y > 0.0:
			pts = [a, c, b]
		for p in pts:
			var v: Vector2 = p
			st.set_normal(Vector3.UP)
			st.set_uv((v - ext.position) / ext.size)
			st.add_vertex(Vector3(v.x, y, v.y))
	return st.commit()


func _build_legacy_hazard(h: Dictionary) -> Node3D:
	var n := Node3D.new()
	_hazard_root.add_child(n)
	var p: Vector3 = h["pos"]
	n.position = Vector3(p.x, 0.0, p.z)
	var d := float(h["radius"]) * 2.0
	var m := ArenaPropVisuals.decal(Color("#FF6B2B"), 1, Vector2(d, d), 0, {"base_alpha": 0.5})
	ArenaPropVisuals.decal_quad(n, m, Vector2(d, d))
	return n


# =====================================================================================
# Layout (props + markers) — rebuilt by the editor after each command
# =====================================================================================

func _build_layout() -> void:
	prop_nodes.clear()
	all_prop_nodes.clear()
	marker_nodes.clear()
	_bag_chains.clear()
	var all := arena.all_props()
	for i in all.size():
		var p: Dictionary = all[i]
		var def := ArenaCatalog.prop(ArenaBuilder.catalog_type(str(p["type"])))
		var node := ArenaPropVisuals.build(def, p, {"index": i, "editor": editor_mode})
		_layout_root.add_child(node)
		if def.is_empty():
			all_prop_nodes.append(node)
			continue
		if str(def["body"]) != "none":
			node.transform = ArenaBuilder.prop_body_transform(p, def)
			prop_nodes.append(node)
			if str(def["body"]) == "bag":
				_make_bag_chain(node, p, def)
		else:
			var pos: Vector3 = p["pos"]
			node.transform = Transform3D(Basis(Vector3.UP, float(p.get("yaw", 0.0))), Vector3(pos.x, pos.y, pos.z))
		node.set_meta("uid", int(p.get("uid", -1)))
		node.set_meta("all_index", i)
		all_prop_nodes.append(node)
	if editor_mode:
		for b in arena.builtins:
			if arena.builtin_removed(str(b["id"])):
				var def2 := ArenaCatalog.prop(str(b["type"]))
				var ghost := ArenaPropVisuals.build(def2, b, {"index": 99})
				_layout_root.add_child(ghost)
				ghost.transform = ArenaBuilder.prop_body_transform(b, def2) if str(def2.get("body", "none")) != "none" else Transform3D(Basis(Vector3.UP, float(b.get("yaw", 0.0))), b["pos"])
				_set_transparency(ghost, 0.8)
				ghost.set_meta("ghost_builtin", str(b["id"]))
	for name_ in arena.marker_entries:
		var show := editor_mode or _shown_markers.has(str(name_))
		var entries: Array = arena.marker_entries[name_]
		var mdef := ArenaCatalog.prop(ArenaCatalog.marker_type(str(name_)))
		for k in entries.size():
			var me: Dictionary = entries[k]
			if not show:
				continue
			var item := {"type": mdef.get("id", "marker_" + str(name_)), "pos": me["pos"], "yaw": me["yaw"], "team": me["team"]}
			var mn := ArenaPropVisuals.build(mdef, item, {"index": k, "editor": editor_mode})
			_layout_root.add_child(mn)
			var mp: Vector3 = me["pos"]
			mn.transform = Transform3D(Basis(Vector3.UP, float(me["yaw"])), Vector3(mp.x, 0.0, mp.z))
			mn.set_meta("uid", int(me.get("uid", -1)))
			mn.set_meta("marker", str(name_))
			mn.set_meta("marker_index", k)
			if not editor_mode and mn.has_meta("label"):
				(mn.get_meta("label") as Node3D).visible = false
			marker_nodes.append(mn)


## Editor: rebuild only props and markers for a changed layout (static set is kept).
func rebuild_layout(a: ArenaDef) -> void:
	arena = a
	for c in _layout_root.get_children():
		_layout_root.remove_child(c)
		c.queue_free()
	_build_layout()


## Shows mode markers in matches (e.g. ["goal", "ball_spawn"] for Chumball). Wave gates always show.
func show_markers(names: Array) -> void:
	_shown_markers = names.duplicate()
	if not _shown_markers.has("wave_gate"):
		_shown_markers.append("wave_gate")
	rebuild_layout(arena)


func set_editor_mode(on: bool) -> void:
	editor_mode = on
	_auto_bind = not on


## Editor: hides set dressing that sits entirely above head height (trusses, light banks, hooks,
## gantries) so the top-down editing view stays clear.
func _hide_overhead(n: Node) -> void:
	for c in n.get_children():
		if c is VisualInstance3D and c is Node3D:
			var vi := c as VisualInstance3D
			var box := (c as Node3D).global_transform * vi.get_aabb()
			if box.position.y > 4.6:
				(c as Node3D).visible = false
				continue
		if c is Node3D and not (c is VisualInstance3D) and (c as Node3D).global_position.y > 6.0:
			(c as Node3D).visible = false
			continue
		_hide_overhead(c)


static func _set_transparency(n: Node, t: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).transparency = t
	for c in n.get_children():
		_set_transparency(c, t)


func _make_bag_chain(node: Node3D, p: Dictionary, def: Dictionary) -> void:
	var pos: Vector3 = p["pos"]
	var hang := float(def["params"].get("hang", 2.3))
	var anchor := Vector3(pos.x, pos.y + hang, pos.z)
	var bracket := MeshInstance3D.new()
	bracket.mesh = ArenaMeshKit.chamfer_box(Vector3(0.9, 0.16, 0.16), 0.03)
	bracket.material_override = Materials.toon(Color("#2B2F3A"), 0.5, 0.6)
	bracket.position = anchor + Vector3(0, 0.08, 0)
	_layout_root.add_child(bracket)
	var chain := MeshInstance3D.new()
	chain.mesh = ArenaMeshKit.cylinder(0.025, 0.025, 1.0, 6, 0.0, false)
	chain.material_override = Materials.toon(Color("#9FA6AD"), 0.35, 0.8)
	_layout_root.add_child(chain)
	_bag_chains.append([node, chain, anchor, float(def["height"]) * 0.5 + 0.15])


func layout_node_for_uid(uid: int) -> Node3D:
	for n in all_prop_nodes + marker_nodes:
		if is_instance_valid(n) and int(n.get_meta("uid", -2)) == uid:
			return n
	return null


func set_prop_transform(i: int, xf: Transform3D) -> void:
	if i >= 0 and i < prop_nodes.size() and is_instance_valid(prop_nodes[i]):
		prop_nodes[i].global_transform = xf


## Excitement 0..1 drives the crowd's bounce (from announcer/hype events).
func set_crowd_energy(v: float) -> void:
	if _crowd:
		(_crowd.material_override as ShaderMaterial).set_shader_parameter("energy", clampf(v, 0.0, 1.0))


# =====================================================================================
# Live state
# =====================================================================================

func bind_sim(sim: MatchSim) -> void:
	_sim = sim
	_cursor = 0


## Networked clients: feed ArenaHazards.view_state() snapshots here instead of binding a sim.
func apply_state(state: Dictionary) -> void:
	_remote = state


func _try_bind() -> void:
	var p := get_parent()
	if p == null:
		return
	var s = p.get("sim")
	if s is MatchSim:
		bind_sim(s)


func _process(dt: float) -> void:
	_t += dt
	if arena == null:
		return
	if _sim == null and _auto_bind:
		_try_bind()
	var st: Dictionary = _remote
	if _sim != null and is_instance_valid(_sim):
		var hz = _sim.arena_nodes.get("hazards") if typeof(_sim.arena_nodes) == TYPE_DICTIONARY else null
		if hz is ArenaHazards:
			st = (hz as ArenaHazards).view_state()
		_consume_events()
	_apply_hazards(st, dt)
	_apply_props(st, dt)
	_animate_ambient(dt)


func _sfx(id: String, pos = null, vol_db := 0.0) -> void:
	if id != "" and not editor_mode:
		Audio.sfx(id, pos, vol_db)


func _transition(key: String, phase: String) -> String:
	var last := str(_last_phase.get(key, "idle"))
	_last_phase[key] = phase
	if last == phase:
		return ""
	return phase if phase != "idle" else "end"


func _apply_hazards(st: Dictionary, dt: float) -> void:
	for hz in st.get("hazards", []):
		var id := str(hz["id"])
		var type := str(hz["type"])
		var phase := str(hz["phase"])
		var t := float(hz["t"])
		var tr := _transition("h:" + id, phase)
		if tr != "":
			var pos = null
			if hz.has("spot"):
				pos = Vector3((hz["spot"] as Vector2).x, 0.5, (hz["spot"] as Vector2).y)
			elif hz.has("pos"):
				pos = Vector3((hz["pos"] as Vector2).x, 0.5, (hz["pos"] as Vector2).y)
			_sfx(str(AUDIO.get(type, {}).get(tr, "")), pos)
		var deco: Dictionary = _hz_decals.get(id, {})
		var mats: Array = deco.get("mats", [])
		var glow := 1.0 if phase == "telegraph" else 0.0
		var act := 1.0 if phase == "active" else 0.0
		match type:
			"tidal_gutter":
				for m in mats:
					(m as ShaderMaterial).set_shader_parameter("glow", glow)
					(m as ShaderMaterial).set_shader_parameter("active", act * 0.4)
				_gutter_water(phase, t, float(hz["len"]), dt)
			"crane_hook":
				for m in mats:
					(m as ShaderMaterial).set_shader_parameter("glow", glow)
					(m as ShaderMaterial).set_shader_parameter("active", act)
				_crane_anim(hz, phase, t, dt)
			"plate_grid":
				var cell := int(hz.get("cell", -1))
				for k in mats.size():
					var on := k == cell
					(mats[k] as ShaderMaterial).set_shader_parameter("glow", glow if on else 0.0)
					(mats[k] as ShaderMaterial).set_shader_parameter("active", act if on else 0.0)
				_plate_arcs(deco, cell, phase == "active")
			"crane_magnet":
				_magnet_anim(hz, deco, phase, t, dt)
			"wind_gust":
				_wind_anim(hz, deco, phase, dt)


func _gutter_water(phase: String, t: float, len: float, dt: float) -> void:
	var w: MeshInstance3D = _out.get("gutter_water")
	if w == null:
		return
	var m: ShaderMaterial = _out.get("gutter_mat")
	var target_y := -0.2
	var opacity := 0.0
	var foam := 0.0
	match phase:
		"telegraph":
			target_y = 0.008
			opacity = 0.45
			foam = 0.6 + 0.4 * sin(_t * 10.0)
		"active":
			target_y = 0.035 if t < len - 1.0 else lerpf(0.035, -0.2, clampf((t - (len - 1.0)) / 1.0, 0.0, 1.0))
			opacity = 0.85
			foam = 0.25
	w.position.y = move_toward(w.position.y, target_y, dt * 0.6)
	w.visible = w.position.y > -0.15
	var cur := lerpf(float(_out.get("gutter_opacity", 0.0)), opacity, clampf(dt * 4.0, 0.0, 1.0))
	_out["gutter_opacity"] = cur
	m.set_shader_parameter("opacity", cur)
	m.set_shader_parameter("foam_band", foam)


func _crane_anim(hz: Dictionary, phase: String, t: float, dt: float) -> void:
	var c: Dictionary = _out.get("crane", {})
	if c.is_empty():
		return
	var hook: Node3D = c["hook"]
	var tip: Vector3 = c["tip"]
	var spot: Vector2 = hz.get("spot", Vector2(tip.x, tip.z))
	var target := Vector3(spot.x, float(c["rest_y"]), spot.y)
	var spot_light: SpotLight3D = c["spot"]
	match phase:
		"telegraph":
			target.y = lerpf(float(c["rest_y"]), 2.6, clampf(t / 1.2, 0.0, 1.0))
			spot_light.light_energy = 6.0
		"active":
			var lift := clampf(t / 0.45, 0.0, 1.0)
			target.y = 2.3 + 2.0 * lift
			spot_light.light_energy = 3.0
			var hooked: Array = hz.get("hooked", [])
			if _sim and not hooked.is_empty():
				var f: Fighter = _sim.fighters[int(hooked[0])]
				target = f.head_pos() + Vector3(0, 0.55, 0)
		_:
			spot_light.light_energy = move_toward(spot_light.light_energy, 0.0, dt * 8.0)
	hook.position = hook.position.lerp(target, clampf(dt * 6.0, 0.0, 1.0))
	spot_light.position = Vector3(spot.x, tip.y - 0.3, spot.y)
	var cable: MeshInstance3D = c["cable"]
	var top := Vector3(hook.position.x, tip.y, hook.position.z)
	var bottom := hook.position + Vector3(0, 0.62, 0)
	cable.position = (top + bottom) * 0.5
	cable.scale = Vector3(1, maxf(0.05, top.y - bottom.y), 1)


func _plate_arcs(deco: Dictionary, cell: int, live: bool) -> void:
	var arcs: Array = deco.get("arcs", [])
	var cells: Array = deco.get("cells", [])
	for k in arcs.size():
		var arc: MeshInstance3D = arcs[k]
		arc.visible = live and cell >= 0 and randf() < 0.75
		if arc.visible:
			var r: Rect2 = cells[cell]
			arc.position = Vector3(randf_range(r.position.x + 0.4, r.end.x - 0.4), 0.06 + randf() * 0.1, randf_range(r.position.y + 0.4, r.end.y - 0.4))
			arc.rotation = Vector3(0, randf() * TAU, randf_range(-0.3, 0.3))
			arc.scale = Vector3(randf_range(0.6, 1.6), 1, 1)


func _magnet_anim(hz: Dictionary, deco: Dictionary, phase: String, t: float, dt: float) -> void:
	var mg: Dictionary = _out.get("magnet", {})
	var node: MeshInstance3D = deco.get("node")
	var mats: Array = deco.get("mats", [])
	var target := Vector2.ZERO
	if hz.has("pos"):
		target = hz["pos"]
	var drop_y := -3.4
	var glow_e := 0.2
	match phase:
		"telegraph":
			drop_y = -4.6
			glow_e = 1.2 + sin(_t * 12.0) * 0.6
		"active":
			drop_y = -6.2
			glow_e = 3.5
		_:
			target = mg.get("rest", Vector2.ZERO) if not mg.is_empty() else Vector2.ZERO
	if node:
		node.visible = phase != "idle"
		# just above the plate-grid decals (a y of 0 sank the ring into the floor)
		node.position = Vector3(target.x, 0.02, target.y)
		for m in mats:
			(m as ShaderMaterial).set_shader_parameter("base_alpha", 0.4 if phase != "idle" else 0.0)
			(m as ShaderMaterial).set_shader_parameter("glow", 1.0 if phase == "telegraph" else 0.0)
			(m as ShaderMaterial).set_shader_parameter("active", 1.0 if phase == "active" else 0.0)
	if mg.is_empty():
		return
	var bridge: Node3D = mg["bridge"]
	var trolley: Node3D = mg["trolley"]
	var magnet: Node3D = mg["magnet"]
	bridge.position.x = move_toward(bridge.position.x, target.x, dt * 6.0)
	trolley.position.z = move_toward(trolley.position.z, target.y, dt * 6.0)
	magnet.position.y = move_toward(magnet.position.y, drop_y, dt * 3.0)
	var chains: MeshInstance3D = mg["chains"]
	chains.position = Vector3(0, magnet.position.y * 0.5, 0)
	chains.scale = Vector3(1, absf(magnet.position.y), 1)
	(mg["glow"] as StandardMaterial3D).emission_energy_multiplier = glow_e
	(mg["light"] as OmniLight3D).light_energy = 0.0 if phase == "idle" else glow_e * 1.2
	if phase == "active" and randf() < dt * 20.0:
		_sparks(Vector3(target.x, 0.3, target.y) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), Color("#E04FB0"))


func _wind_anim(hz: Dictionary, deco: Dictionary, phase: String, dt: float) -> void:
	var dir: Vector2 = hz.get("dir", Vector2(1, 0))
	var node: MeshInstance3D = deco.get("node")
	var mats: Array = deco.get("mats", [])
	if node:
		node.visible = phase != "idle"
		for m in mats:
			# decal local +Y is world +Z; the arrow icon points along local +Y
			(m as ShaderMaterial).set_shader_parameter("icon_rot", atan2(dir.x, dir.y))
			(m as ShaderMaterial).set_shader_parameter("base_alpha", 0.0)
			(m as ShaderMaterial).set_shader_parameter("glow", 0.6 if phase == "telegraph" else 0.0)
			(m as ShaderMaterial).set_shader_parameter("active", 0.35 if phase == "active" else 0.0)
	var gust := phase != "idle"
	var yaw_target := atan2(dir.x, dir.y) - PI * 0.5
	for f in _out.get("flags", []):
		var flag: Node3D = f
		var want := yaw_target if gust else 0.6 + sin(_t * 0.4) * 0.3
		flag.rotation.y = lerp_angle(flag.rotation.y, want, clampf(dt * (8.0 if gust else 1.0), 0.0, 1.0))
		flag.rotation.x = sin(_t * (18.0 if phase == "active" else 4.0)) * (0.25 if gust else 0.08)


func _apply_props(st: Dictionary, dt: float) -> void:
	var list: Array = st.get("props", [])
	for e in list:
		var i := int(e["i"])
		var node: Node3D = null
		if bool(e.get("spawned", false)):
			node = _spawned_node(e)
		elif i < all_prop_nodes.size():
			node = all_prop_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		var destroyed := bool(e["destroyed"])
		var key := "d:%d:%s" % [i, "s" if bool(e.get("spawned", false)) else ""]
		if destroyed and not _destroyed.has(key):
			_destroyed[key] = true
			node.visible = false
			_debris_burst(node.global_position, str(e["type"]))
		elif not destroyed and _destroyed.has(key):
			_destroyed.erase(key)
			node.visible = true
		if destroyed:
			continue
		if e.has("xform"):
			node.global_transform = e["xform"]
		var phase := str(e.get("phase", "idle"))
		var tr := _transition("p:%d" % i, phase)
		var def := ArenaCatalog.prop(str(e["type"]))
		var beh := str(def.get("behaviour", ""))
		if tr != "" and AUDIO.has(beh):
			_sfx(str(AUDIO[beh].get(tr, "")), node.global_position)
		for m in node.get_meta("glow_mats", []):
			if m is ShaderMaterial:
				(m as ShaderMaterial).set_shader_parameter("glow", 1.0 if phase == "telegraph" else 0.0)
				(m as ShaderMaterial).set_shader_parameter("active", 1.0 if phase == "active" else 0.0)
		if node.has_meta("plume"):
			(node.get_meta("plume") as Node3D).visible = phase == "active"
			var heat: StandardMaterial3D = node.get_meta("heat")
			heat.albedo_color.a = 0.65 if phase == "telegraph" else (0.35 if phase == "active" else 0.0)
		if node.has_meta("live_mat"):
			var lm: StandardMaterial3D = node.get_meta("live_mat")
			lm.emission_energy_multiplier = 6.0 if phase == "active" else (2.0 + sin(_t * 14.0) * 1.5 if phase == "telegraph" else 0.0)
		if node.has_meta("bob"):
			var bob: Node3D = node.get_meta("bob")
			var avail := bool(e.get("available", true))
			bob.visible = avail
			if node.has_meta("ring_mat"):
				var rm: ShaderMaterial = node.get_meta("ring_mat")
				rm.set_shader_parameter("base_alpha", 0.55 if avail else 0.18)
				rm.set_shader_parameter("glow", 0.0 if avail else (1.0 if float(e.get("respawn_in", 99.0)) < 3.0 else 0.0))


func _spawned_node(e: Dictionary) -> Node3D:
	var i := int(e["i"])
	if _spawned.has(i) and is_instance_valid(_spawned[i]):
		return _spawned[i]
	if bool(e["destroyed"]):
		return null
	var def := ArenaCatalog.prop(str(e["type"]))
	var item := {"type": e["type"], "pos": e.get("pos", Vector3.ZERO), "yaw": float(e.get("yaw", 0.0)), "params": {}}
	var node := ArenaPropVisuals.build(def, item, {"index": i})
	_layout_root.add_child(node)
	var xf := ArenaBuilder.prop_body_transform(item, def)
	node.transform = xf
	node.position.y += 3.0
	var tw := create_tween()
	tw.tween_property(node, "position:y", xf.origin.y, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _debris_burst(Vector3(xf.origin.x, 0.2, xf.origin.z), "prop_scrap_bundle"))
	_spawned[i] = node
	return node


func _debris_burst(pos: Vector3, type: String) -> void:
	var col := Color("#8C6A4A")
	var sfx := "prop_break_wood"
	if type.contains("barrel") or type.contains("drum") or type.contains("fan") or type.contains("scrap") or type.contains("bundle"):
		col = Color("#6E6A66")
		sfx = "prop_break_metal"
	if type.contains("sack"):
		col = Color("#B8905E")
		sfx = "gravel_scatter"
	if type.contains("battery"):
		col = Color("#2B2F3A")
		sfx = "prop_burst_static"
	if type.contains("railing"):
		col = Color("#E0B42A")
		sfx = "prop_break_metal"
	var el := str(ArenaCatalog.prop(type).get("element", ""))
	if el != "" and Audio.has_sfx("prop_burst_" + el):
		sfx = "prop_burst_" + el      # elemental destructibles burst into their zone
	_sfx(sfx, pos)
	var gp := GPUParticles3D.new()
	gp.amount = 26
	gp.lifetime = 1.1
	gp.one_shot = true
	gp.explosiveness = 0.95
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -12, 0)
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color = col
	gp.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.08, 0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.vertex_color_use_as_albedo = false
	bm.material = mat
	gp.draw_pass_1 = bm
	add_child(gp)
	gp.global_position = pos + Vector3(0, 0.4, 0)
	gp.emitting = true
	_debris.append([gp, _t + 1.6])


func _sparks(pos: Vector3, col: Color) -> void:
	var gp := GPUParticles3D.new()
	gp.amount = 10
	gp.lifetime = 0.4
	gp.one_shot = true
	gp.explosiveness = 1.0
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -9, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color = col
	gp.process_material = pm
	# the quad itself is spark-sized: a full-size quad scaled down by the process material turned
	# into large overexposed squares when many bursts overlapped (magnet pull)
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = col.lightened(0.45)
	q.material = m
	gp.draw_pass_1 = q
	add_child(gp)
	gp.global_position = pos
	gp.emitting = true
	_debris.append([gp, _t + 0.8])


func _consume_events() -> void:
	for ev in _sim.events_since(_cursor):
		_cursor = int(ev["seq"])
		var type := str(ev["type"])
		match type:
			"knockdown":
				_crowd_boost = maxf(_crowd_boost, 0.35)
				var conf: Array = _out.get("confetti", [])
				if not conf.is_empty():
					var gp: GPUParticles3D = conf[randi() % conf.size()]
					gp.restart()
					gp.emitting = true
			"ko":
				_crowd_boost = 0.6
				for gp2 in _out.get("confetti", []):
					(gp2 as GPUParticles3D).restart()
					(gp2 as GPUParticles3D).emitting = true
			"juice":
				_crowd_boost = maxf(_crowd_boost, 0.5)
				_rim_flash = 1.0
				for gp3 in _out.get("pyro", []):
					(gp3 as GPUParticles3D).restart()
					(gp3 as GPUParticles3D).emitting = true
			"arena_bumper":
				var i := int(ev.get("index", -1))
				if i >= 0 and i < all_prop_nodes.size() and all_prop_nodes[i].has_meta("lamp"):
					var lamp: StandardMaterial3D = all_prop_nodes[i].get_meta("lamp")
					lamp.emission_energy_multiplier = 9.0
				_sfx("bumper_ding", ev.get("pos"))
			"arena_pickup":
				_sfx("pickup_health" if str(ev.get("kind", "")) == "health" else "pickup_hype", ev.get("pos"))
			"arena_drain":
				_sfx("drain_teleport", ev.get("from"))
			"spring":
				_sfx("spring_pad", ev.get("pos"))
				_pad_squash(ev.get("pos", Vector3.ZERO))
			"ringout":
				_crowd_boost = maxf(_crowd_boost, 0.5)
			"arena_rebound":
				_sfx("wall_splat_fence", ev.get("pos"), -6.0)
			"arena_bounce":
				_sfx("land_soft", ev.get("pos"))
			"arena_zap":
				_sparks(ev.get("pos", Vector3.ZERO) + Vector3(0, 0.5, 0), Color("#F7E04A"))


func _pad_squash(pos: Vector3) -> void:
	for n in all_prop_nodes:
		if is_instance_valid(n) and n.has_meta("pad_top") and n.global_position.distance_to(pos) < 1.0:
			var top: Node3D = n.get_meta("pad_top")
			top.scale = Vector3(1.1, 0.4, 1.1)
			var tw := create_tween()
			tw.tween_property(top, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _animate_ambient(dt: float) -> void:
	for n in all_prop_nodes:
		if not is_instance_valid(n) or not n.visible:
			continue
		if n.has_meta("spin"):
			var sp: Node3D = n.get_meta("spin")
			var axis: Vector3 = n.get_meta("spin_axis", Vector3.UP)
			sp.rotate_object_local(axis, float(n.get_meta("spin_rate", 3.0)) * dt)
		if n.has_meta("bob"):
			var bob: Node3D = n.get_meta("bob")
			bob.position.y = 0.3 + sin(_t * 2.2 + n.position.x) * 0.06
		if n.has_meta("flame"):
			var fl: Node3D = n.get_meta("flame")
			fl.scale = Vector3(1.0 + sin(_t * 23.0) * 0.06, 1.0 + sin(_t * 17.0 + 1.3) * 0.14, 1.0 + cos(_t * 19.0) * 0.06)
			if n.has_meta("light"):
				(n.get_meta("light") as OmniLight3D).light_energy = 1.4 + sin(_t * 29.0) * 0.25
		if n.has_meta("lamp"):
			var lamp: StandardMaterial3D = n.get_meta("lamp")
			lamp.emission_energy_multiplier = move_toward(lamp.emission_energy_multiplier, 1.2, dt * 18.0)
	for bc in _bag_chains:
		var bag: Node3D = bc[0]
		var chain: MeshInstance3D = bc[1]
		if not is_instance_valid(bag):
			continue
		var anchor: Vector3 = bc[2]
		var top: Vector3 = bag.global_transform * Vector3(0, float(bc[3]), 0)
		chain.global_position = (anchor + top) * 0.5
		var d := top - anchor
		chain.global_basis = Basis(MathX.rotation_between(Vector3.UP, d.normalized() if d.length() > 0.01 else Vector3.UP)).scaled(Vector3(1, maxf(d.length(), 0.05), 1))
	for h in _out.get("hooks", []):
		var hook: Node3D = h
		hook.rotation.z = sin(_t * 0.5 + hook.position.x) * 0.03
		hook.rotation.x = cos(_t * 0.4 + hook.position.z) * 0.03
	for g in _out.get("gulls", []):
		var gull: Node3D = g
		var o: Array = gull.get_meta("orbit")
		var ang := _t * float(o[1]) + float(o[2])
		gull.position = Vector3(cos(ang) * float(o[0]), gull.position.y, sin(ang) * float(o[0]))
		gull.rotation.y = -ang
		gull.rotation.z = sin(_t * 6.0 + float(o[2])) * 0.25
	for p in _out.get("pigeons", []):
		var bird: Node3D = p
		bird.rotation.x = maxf(0.0, sin(_t * 1.7 + bird.position.x * 3.0)) * 0.4
	_crowd_boost = maxf(0.0, _crowd_boost - dt * 0.35)
	set_crowd_energy(_crowd_energy + _crowd_boost)
	if _rim_flash > 0.0:
		_rim_flash = maxf(0.0, _rim_flash - dt)
		rim_light.light_color = _c("rim", "#35C1C9").lerp(Color("#8BD426"), _rim_flash)
		rim_light.light_energy = 0.75 + _rim_flash * 1.5
	for d in _debris.duplicate():
		if _t > float(d[1]):
			(d[0] as Node).queue_free()
			_debris.erase(d)


## Applies graphics preset values (see Settings): shadow/AO/effects quality.
func apply_quality(q: Dictionary) -> void:
	_quality = q
	var e := env.environment
	e.ssao_enabled = int(q.get("ao", 2)) > 0
	e.glow_enabled = int(q.get("effects", 2)) > 0
	key_light.shadow_enabled = int(q.get("shadows", 2)) > 0
	for i in spots.size():
		spots[i].shadow_enabled = int(q.get("shadows", 2)) >= 2 and i < 2
	e.adjustment_brightness = float(q.get("brightness", 1.0))
	e.fog_enabled = int(q.get("effects", 2)) > 0
	if _crowd:
		_crowd.visible = int(q.get("effects", 2)) > 0 or int(q.get("crowd", 1)) > 0
