class_name HubView
extends Node3D
## Visual side of The Cannery (docs/HUB_SYSTEMS.md §6). Builds everything you see from HubLayout
## and HubState: environment + sun/moon by time of day, walls/floors/furniture batched into one
## mesh per space with the hub_surface shader, glass, water, lights, set dressing (HubDressing),
## NPCs (HubNpcView), props mirroring the physics bodies (HubPropsView), the purchase-driven
## world changes (HubUpgradeProps) and ambient life (HubAmbient). Reads sim state; never changes it.
##
## Occlusion: no ceilings are drawn (roofs are shadow-only) and the shader's see-through cylinder
## dithers away walls/furniture between the camera and the player, so every space reads from the
## follow camera without hiding your fighter.

const STYLE := {
	"brick": [Color("#86614f"), HubMeshKit.BRICK], "brick_dark": [Color("#5d4339"), HubMeshKit.BRICK],
	"plaster_green": [Color("#7f9a73"), HubMeshKit.PLASTER], "tile_white": [Color("#dedbd1"), HubMeshKit.TILE_WHITE],
	"tile_blue": [Color("#8fa8b9"), HubMeshKit.TILE_BLUE], "plaster_dark": [Color("#463e4b"), HubMeshKit.PLASTER],
	"wood_panel": [Color("#6e4c34"), HubMeshKit.PLANK], "plank": [Color("#6a5442"), HubMeshKit.PLANK],
	"parapet": [Color("#7d7a74"), HubMeshKit.CONCRETE], "steel": [Color("#5b6168"), HubMeshKit.PLAIN],
	"steel_light": [Color("#9fa6ad"), HubMeshKit.PLAIN], "counter": [Color("#2f3a2d"), HubMeshKit.PLANK],
	"vending": [Color("#8bd426"), HubMeshKit.PLAIN], "table": [Color("#5e4a3a"), HubMeshKit.PLANK],
	"cot": [Color("#b9c3c7"), HubMeshKit.PLAIN], "dumpster": [Color("#3e6b4f"), HubMeshKit.CORRUGATED],
	"dumpster_in": [Color("#a9c9d6"), HubMeshKit.PLAIN], "lockers": [Color("#55708a"), HubMeshKit.CORRUGATED],
	"bench": [Color("#8a6a48"), HubMeshKit.PLANK], "case": [Color("#3a2c22"), HubMeshKit.PLANK],
	"cabinet": [Color("#6b7177"), HubMeshKit.PLAIN], "desk": [Color("#4b3a30"), HubMeshKit.PLANK],
	"bleacher": [Color("#6d6a64"), HubMeshKit.PLANK], "chair": [Color("#8c3b2b"), HubMeshKit.PLAIN],
	"cooler": [Color("#2e9be0"), HubMeshKit.PLAIN], "container_red": [Color("#8c3b2b"), HubMeshKit.CORRUGATED],
	"container_blue": [Color("#355d7f"), HubMeshKit.CORRUGATED], "workbench": [Color("#6a5236"), HubMeshKit.PLANK],
	"curb": [Color("#c9a227"), HubMeshKit.HAZARD], "terminal": [Color("#3a4038"), HubMeshKit.PLAIN],
	"trunk": [Color("#6b3f2a"), HubMeshKit.PLANK], "crate": [Color("#a8743a"), HubMeshKit.PLANK],
}
const FLOOR_STYLE := {
	"main_floor": [Color("#8f8b82"), HubMeshKit.CONCRETE], "juice_bar": [Color("#cdc7b4"), HubMeshKit.MAT],
	"med_bay": [Color("#d4d2c9"), HubMeshKit.TILE_WHITE], "loading_dock": [Color("#8b877e"), HubMeshKit.CONCRETE],
	"locker_room": [Color("#7f98a8"), HubMeshKit.TILE_BLUE], "office": [Color("#7a5a3e"), HubMeshKit.WOOD_FLOOR],
	"booth": [Color("#5c3f61"), HubMeshKit.PLAIN], "boiler_room": [Color("#5f5b55"), HubMeshKit.CONCRETE],
	"roof": [Color("#4d4c52"), HubMeshKit.CONCRETE], "pier": [Color("#6a5442"), HubMeshKit.PLANK],
	"crawlspace": [Color("#4a3c30"), HubMeshKit.PLANK],
}
## Time of day (HUB.md §6): [sun elevation deg, sun yaw deg, sun colour, sun energy, background,
## ambient colour, ambient energy, interior light multiplier, neon multiplier]
const TOD := {
	"morning": [-38.0, 120.0, Color("#ffe0b5"), 1.15, Color("#9cb6c8"), Color("#a7b4c0"), 0.5, 0.85, 0.7],
	"evening": [-14.0, -60.0, Color("#ff9a58"), 0.95, Color("#c9805e"), Color("#8f6e72"), 0.5, 1.1, 1.0],
	"night": [-52.0, 30.0, Color("#8fb2ff"), 0.32, Color("#0f1322"), Color("#2c3248"), 0.55, 1.25, 1.6],
}

var mode: HubMode
var state: HubState
var tod := "morning"
var surface_mat: ShaderMaterial
var glass_mat: StandardMaterial3D
var env: WorldEnvironment
var sun: DirectionalLight3D
var interior_lights: Array[Light3D] = []
var _light_base := {}               ## Light3D -> base energy
var neon: Array[GeometryInstance3D] = []
var batches := {}                   ## space id -> HubMeshKit (during build) / MeshInstance3D
var npc_views := {}                 ## npc key -> HubNpcView
var props: HubPropsView
var upgrades: HubUpgradeProps
var ambient: HubAmbient
var dressing: HubDressing
var water: MeshInstance3D
var _water_mat: ShaderMaterial
var _time := 0.0
var quality := {}


func build(m: HubMode, s: HubState) -> void:
	mode = m
	state = s
	name = "HubView"
	tod = state.time_of_day()
	surface_mat = ShaderMaterial.new()
	surface_mat.shader = load("res://src/hub/view/hub_surface.gdshader")
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.7, 0.85, 0.9, 0.22)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.08
	glass_mat.metallic_specular = 0.9
	glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var t0 := Time.get_ticks_usec()
	_build_environment()
	_build_structure()
	var t1 := Time.get_ticks_usec()
	dressing = HubDressing.new()
	dressing.build(self)
	var t2 := Time.get_ticks_usec()
	_commit_batches()
	var t3 := Time.get_ticks_usec()
	_build_water()
	_build_npcs()
	var t4 := Time.get_ticks_usec()
	props = HubPropsView.new()
	add_child(props)
	props.build(self)
	upgrades = HubUpgradeProps.new()
	add_child(upgrades)
	upgrades.build(self)
	var t5 := Time.get_ticks_usec()
	ambient = HubAmbient.new()
	add_child(ambient)
	ambient.build(self)
	apply_time_of_day(tod)
	var t6 := Time.get_ticks_usec()
	var verts := 0
	for k in batches:
		var mi := batches[k] as MeshInstance3D
		if mi and mi.mesh:
			verts += mi.mesh.surface_get_array_len(0)
	Log.i("hub", "view build ms: structure %.0f dressing %.0f commit %.0f water+npcs %.0f props+upgrades %.0f ambient %.0f; batch verts %d" % [
		(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0, (t5 - t4) / 1000.0, (t6 - t5) / 1000.0, verts])


## A batch (HubMeshKit) for a space; everything added to it becomes one mesh.
func kit(space_id: String) -> HubMeshKit:
	if not batches.has(space_id):
		batches[space_id] = HubMeshKit.new()
	return batches[space_id]


func _commit_batches() -> void:
	for sid in batches.keys():
		var k: HubMeshKit = batches[sid]
		var mi := k.commit("Batch_" + str(sid), surface_mat)
		add_child(mi)
		batches[sid] = mi


# =====================================================================================
# Environment and time of day
# =====================================================================================

func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.05
	e.ssao_enabled = true
	e.ssao_radius = 0.8
	e.ssao_intensity = 1.4
	e.fog_enabled = true
	e.fog_density = 0.006
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.05
	e.adjustment_saturation = 1.05
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.light_angular_distance = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.04
	add_child(sun)


func apply_time_of_day(t: String) -> void:
	tod = t if TOD.has(t) else "morning"
	var d: Array = TOD[tod]
	sun.rotation_degrees = Vector3(float(d[0]), float(d[1]), 0.0)
	sun.light_color = d[2]
	sun.light_energy = float(d[3])
	var e := env.environment
	e.background_color = d[4]
	e.ambient_light_color = d[5]
	e.ambient_light_energy = float(d[6])
	e.fog_light_color = (d[4] as Color).lerp(Color("#2b2f3a"), 0.4)
	for l in interior_lights:
		l.light_energy = float(_light_base.get(l, 1.0)) * float(d[7])
	for n in neon:
		n.set_instance_shader_parameter("neon", float(d[8]))
	if ambient:
		ambient.on_time_of_day(tod)


func add_light(l: Light3D, base_energy: float, interior := true) -> Light3D:
	l.light_energy = base_energy
	_light_base[l] = base_energy
	if interior:
		interior_lights.append(l)
	add_child(l)
	return l


func omni(pos: Vector3, col: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = col
	o.omni_range = rng
	o.omni_attenuation = 1.2
	o.shadow_enabled = shadow
	add_light(o, energy)
	return o


func spot(pos: Vector3, at: Vector3, col: Color, energy: float, rng: float, angle: float, shadow := false) -> SpotLight3D:
	var s := SpotLight3D.new()
	add_light(s, energy)
	s.look_at_from_position(pos, at, Vector3.UP if absf((at - pos).normalized().y) < 0.99 else Vector3.FORWARD)
	s.light_color = col
	s.spot_range = rng
	s.spot_angle = angle
	s.spot_angle_attenuation = 0.7
	s.shadow_enabled = shadow
	return s


func apply_quality(q: Dictionary) -> void:
	quality = q
	var e := env.environment
	e.ssao_enabled = int(q.get("ao", 2)) > 0
	e.glow_enabled = int(q.get("effects", 2)) > 0
	e.fog_enabled = int(q.get("effects", 2)) > 0
	e.adjustment_brightness = float(q.get("brightness", 1.0))
	sun.shadow_enabled = int(q.get("shadows", 2)) > 0
	var shadow_lights := int(q.get("shadows", 2)) >= 2
	for l in interior_lights:
		if l.has_meta("wants_shadow"):
			l.shadow_enabled = shadow_lights


# =====================================================================================
# Structure: floors, walls (split around openings), solids, stairs, roofs (shadow-only)
# =====================================================================================

func _build_structure() -> void:
	# yard around the building and the void under the separate regions
	var yard := kit("_yard")
	# (the yard stops short of the basement: the Boiler Room sits in darkness, not in a parking lot)
	yard.floor_rect(Rect2(-60, -18.6, 90, 90), -0.02, Color("#3b3b40"), HubMeshKit.CONCRETE)
	yard.floor_rect(Rect2(30, -14, 34, 28), -0.03, Color("#0b0a0d"), HubMeshKit.PLAIN)
	yard.floor_rect(Rect2(36, -40, 24, 20), -0.04, Color("#2c2c33"), HubMeshKit.PLAIN)
	for sid in HubLayout.SPACES:
		var s: Dictionary = HubLayout.SPACES[sid]
		var r: Rect2 = s["rect"]
		var fs: Array = FLOOR_STYLE.get(sid, [Color("#8f8b82"), HubMeshKit.CONCRETE])
		kit(sid).floor_rect(r, float(s["floor"]) + 0.004, fs[0], int(fs[1]))
	for w in HubLayout.walls():
		_wall_visual(w)
	for so in HubLayout.solids():
		if not bool(so.get("visible", true)):
			continue
		var b: AABB = so["box"]
		var st: Array = STYLE.get(str(so["style"]), [Color("#777777"), HubMeshKit.PLAIN])
		var sid2 := HubLayout.space_at(b.get_center() + Vector3.UP * 0.2)
		if str(so["name"]) in ["booth_block", "office_block"]:
			sid2 = "main_floor"
		kit(sid2 if sid2 != "" else "_yard").box_aabb(b, st[0], int(st[1]), b.size.y > 0.7)
	_stairs()
	_roofs()


func _wall_visual(w: Dictionary) -> void:
	var st: Array = STYLE.get(str(w["style"]), [Color("#888888"), HubMeshKit.PLAIN])
	var col: Color = st[0]
	var pat := int(st[1])
	var k := kit(str(w.get("space", "_yard")))
	var y0 := float(w["y0"])
	var y1 := float(w["y1"])
	var ops: Array = (w["openings"] as Array).duplicate()
	ops.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var cursor := float(w["from"])
	var t := HubLayout.WALL_T
	for o in ops:
		var a := float(o[0])
		var b := float(o[1])
		var oy0 := float(o[2])
		var oy1 := float(o[3])
		if a > cursor:
			_wall_piece(k, w, cursor, a, y0, y1, col, pat)
		if oy0 > y0 + 0.01:
			_wall_piece(k, w, a, b, y0, oy0, col, pat)
		if oy1 < y1 - 0.01:
			_wall_piece(k, w, a, b, oy1, y1, col, pat)
		var kind := str(o[4])
		if kind == "glass" or kind == "window":
			_glass(w, a, b, oy0, oy1)
			_wall_piece(k, w, a, b, oy0 - 0.05, oy0, Color("#2b2f3a"), HubMeshKit.PLAIN)    # sill
		cursor = maxf(cursor, b)
	if cursor < float(w["to"]):
		_wall_piece(k, w, cursor, float(w["to"]), y0, y1, col, pat)
	# a dark cap on top of the wall so cut-away rooms read like a doll's house
	var c := float(w["c"])
	if str(w["axis"]) == "x":
		k.box(Vector3((float(w["from"]) + float(w["to"])) * 0.5, y1 + 0.03, c), Vector3(float(w["to"]) - float(w["from"]) + t, 0.06, t + 0.04), Color("#23262e"), HubMeshKit.PLAIN, true)
	else:
		k.box(Vector3(c, y1 + 0.03, (float(w["from"]) + float(w["to"])) * 0.5), Vector3(t + 0.04, 0.06, float(w["to"]) - float(w["from"]) + t), Color("#23262e"), HubMeshKit.PLAIN, true)


func _wall_piece(k: HubMeshKit, w: Dictionary, a: float, b: float, y0: float, y1: float, col: Color, pat: int) -> void:
	if b - a < 0.01 or y1 - y0 < 0.01:
		return
	var c := float(w["c"])
	var t := HubLayout.WALL_T
	if str(w["axis"]) == "x":
		k.box(Vector3((a + b) * 0.5, (y0 + y1) * 0.5, c), Vector3(b - a, y1 - y0, t), col, pat, true)
	else:
		k.box(Vector3(c, (y0 + y1) * 0.5, (a + b) * 0.5), Vector3(t, y1 - y0, b - a), col, pat, true)


func _glass(w: Dictionary, a: float, b: float, y0: float, y1: float) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(b - a, y1 - y0)
	mi.mesh = qm
	mi.material_override = glass_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := float(w["c"])
	if str(w["axis"]) == "x":
		mi.position = Vector3((a + b) * 0.5, (y0 + y1) * 0.5, c)
	else:
		mi.position = Vector3(c, (y0 + y1) * 0.5, (a + b) * 0.5)
		mi.rotation = Vector3(0, PI * 0.5, 0)
	add_child(mi)


## Visual stairs on the ramp collider: 20 steps of 0.2 m with stringers and a handrail.
func _stairs() -> void:
	var k := kit("main_floor")
	var steps := 20
	var x0 := -2.0
	var x1 := 8.0
	var run := (x1 - x0) / steps
	for i in steps:
		var top := 4.0 * float(i + 1) / steps
		var xa := x0 + run * i
		if xa < 4.4:
			k.box(Vector3(xa + run * 0.5, top * 0.5, HubLayout.STAIRS_Z), Vector3(run, top, HubLayout.STAIRS_W), Color("#6b6f75"), HubMeshKit.PLAIN, true)
		else:
			k.box(Vector3(xa + run * 0.5, top - 0.18, HubLayout.STAIRS_Z), Vector3(run, 0.36, HubLayout.STAIRS_W), Color("#6b6f75"), HubMeshKit.PLAIN, true)
		k.box(Vector3(xa + run * 0.5, top + 0.005, HubLayout.STAIRS_Z), Vector3(run * 0.92, 0.02, HubLayout.STAIRS_W - 0.15), Color("#c9a227"), HubMeshKit.PAINT, true)
	# landing slab and its edge
	var north := HubLayout.STAIRS_Z - HubLayout.STAIRS_W * 0.5
	k.box(Vector3(10.0, 3.82, (north + 8.0) * 0.5), Vector3(4.0, 0.36, 8.0 - north), Color("#6b6f75"), HubMeshKit.PLAIN, true)
	k.floor_rect(Rect2(8.0, north, 4.0, 8.0 - north), 4.004, Color("#80848a"), HubMeshKit.PLAIN)
	# handrails along the open side of the stairs and the landing
	for i in 11:
		var x := x0 + i * 1.0
		var y := clampf((x - x0) / (x1 - x0) * 4.0, 0.0, 4.0)
		k.cyl(Vector3(x, y, north - 0.08), Vector3(x, y + 1.05, north - 0.08), 0.035, Color("#c9a227"), 6)
	k.cyl(Vector3(x0, 1.05, north - 0.08), Vector3(x1, 5.05, north - 0.08), 0.045, Color("#c9a227"), 6)
	for j in 5:
		var xl := 8.0 + j * 1.0
		k.cyl(Vector3(xl, 4.0, north - 0.15), Vector3(xl, 5.05, north - 0.15), 0.035, Color("#c9a227"), 6)
	k.cyl(Vector3(8.0, 5.05, north - 0.15), Vector3(12.0, 5.05, north - 0.15), 0.045, Color("#c9a227"), 6)


## Roofs block the sun (shadows) but are never drawn, so rooms read from the camera.
func _roofs() -> void:
	var k := HubMeshKit.new()
	for sid in HubLayout.SPACES:
		var s: Dictionary = HubLayout.SPACES[sid]
		if bool(s.get("exterior", false)):
			continue
		var r: Rect2 = s["rect"]
		var top := float(s["floor"]) + float(s["height"]) + 0.15
		k.box(Vector3(r.get_center().x, top, r.get_center().y), Vector3(r.size.x + 0.4, 0.3, r.size.y + 0.4), Color.BLACK, HubMeshKit.PLAIN, false, Basis.IDENTITY, false)
	var mi := k.commit("Roofs", surface_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(mi)


func _build_water() -> void:
	water = MeshInstance3D.new()
	water.name = "Harbor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 80)
	pm.subdivide_width = 1
	water.mesh = pm
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://src/hub/view/hub_water.gdshader")
	water.material_override = _water_mat
	water.position = Vector3(0, HubLayout.WATER_Y, -58.6)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# the pier's own patch of harbor (the pier region sits away from the dock)
	var w2 := MeshInstance3D.new()
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(30, 20)
	w2.mesh = pm2
	w2.material_override = _water_mat
	w2.position = Vector3(24.0, HubLayout.WATER_Y, -42.0)
	add_child(w2)


func _build_npcs() -> void:
	for key in HubLayout.NPC_SPOTS:
		var spot: Dictionary = HubLayout.NPC_SPOTS[key]
		var d := HubContent.npc(str(key))
		var v := HubNpcView.new()
		add_child(v)
		v.setup(str(key), str(d.get("model", "")), spot["pos"], deg_to_rad(float(spot["yaw"])), float(d.get("height", 1.3)), bool(d.get("static", false)))
		npc_views[str(key)] = v


# =====================================================================================
# Per frame
# =====================================================================================

func update(dt: float, cam: Camera3D, player_pos: Vector3) -> void:
	_time += dt
	surface_mat.set_shader_parameter("cut_camera", cam.global_position)
	surface_mat.set_shader_parameter("cut_player", player_pos + Vector3.UP * 0.55)
	if _water_mat:
		_water_mat.set_shader_parameter("time_offset", _time)
	for key in npc_views:
		var v: HubNpcView = npc_views[key]
		if key == "ludlow":
			var l: Dictionary = mode.ludlow
			v.walk_to(l["pos"], float(l["yaw"]), bool(l["moving"]))
		v.update(dt, player_pos)
	props.update(dt)
	ambient.update(dt, player_pos)
	upgrades.update(dt)


func npc(key: String) -> HubNpcView:
	return npc_views.get(key)
