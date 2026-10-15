class_name HubDressing
extends RefCounted
## Static set dressing of The Cannery (view only): what makes each space recognisable from its
## entrance (HUB.md §1 landmarks: the bags, the neon can, the belt case, the desk, the boiler),
## signage, neon, lights and harbor surroundings. Geometry goes into HubView's per-space batches
## (one draw call per space); only neon, signs and fences are separate nodes.

const F_BUNGEE := "res://assets/fonts/Bungee-Regular.ttf"
const F_COND := "res://assets/fonts/BarlowCondensed-900.woff2"
const F_COND7 := "res://assets/fonts/BarlowCondensed-700.woff2"
const GREEN := Color("#8bd426")
const GOLD := Color("#c9a227")
const RUST := Color("#8c3b2b")
const STEEL := Color("#5b6168")
const STEEL_L := Color("#9fa6ad")
const CANVAS := Color("#e9e2cf")
const INK := Color("#23262e")

var v: HubView
var _neon_cache := {}
var sign_letters := {}               ## roof sign letter -> MeshInstance3D
var fluorescents: Array[MeshInstance3D] = []
var cage_banner: Node3D
var elevator_sign: Label3D


func build(view: HubView) -> void:
	v = view
	_main_floor()
	_cage()
	_juice_bar()
	_med_bay()
	_locker_room()
	_office()
	_booth()
	_dock()
	_boiler_room()
	_roof()
	_pier()
	_crawlspace()
	_surroundings()


# ---- helpers ---------------------------------------------------------------------------------

func neon_mat(col: Color, energy := 2.5) -> ShaderMaterial:
	var key := "%s|%.2f" % [col.to_html(), energy]
	if _neon_cache.has(key):
		return _neon_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://src/hub/view/hub_neon.gdshader")
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	_neon_cache[key] = m
	return m


func neon_box(pos: Vector3, size: Vector3, col: Color, energy := 2.5, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = neon_mat(col, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = rot
	v.add_child(mi)
	v.neon.append(mi)
	return mi


func neon_text(text: String, pos: Vector3, rot_y: float, size: float, col: Color, energy := 2.6, font := F_BUNGEE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TextMesh.new()
	tm.text = text
	tm.font = load(font)
	tm.font_size = 64
	tm.pixel_size = size / 64.0
	tm.depth = 0.03
	tm.curve_step = 1.5
	mi.mesh = tm
	mi.material_override = neon_mat(col, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = Vector3(0, rot_y, 0)
	v.add_child(mi)
	v.neon.append(mi)
	return mi


func label(text: String, pos: Vector3, rot_y: float, px: int, col: Color, font := F_COND, flat := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = load(font)
	l.font_size = px
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation = Vector3(-PI * 0.5 if flat else 0.0, rot_y, 0)
	l.double_sided = false
	l.shaded = true
	v.add_child(l)
	return l


func annulus(k: HubMeshKit, c: Vector3, r0: float, r1: float, col: Color, segs := 40) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * r0
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * r0
		var q0 := c + Vector3(cos(a0), 0, sin(a0)) * r1
		var q1 := c + Vector3(cos(a1), 0, sin(a1)) * r1
		k.quad(p0, q0, q1, p1, col, HubMeshKit.PAINT, false)


func disc(k: HubMeshKit, c: Vector3, r: float, col: Color, pattern := HubMeshKit.PAINT, segs := 24) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		k.tri(c, c + Vector3(cos(a1), 0, sin(a1)) * r, c + Vector3(cos(a0), 0, sin(a0)) * r, col, pattern, false)


func poster(k: HubMeshKit, pos: Vector3, rot_y: float, size: Vector2, col: Color, title: String, sub := "", text_col := CANVAS) -> void:
	var b := Basis(Vector3.UP, rot_y)
	k.box(pos, Vector3(size.x, size.y, 0.03), col, HubMeshKit.PLAIN, true, b)
	var fwd := b * Vector3(0, 0, 1)
	label(title, pos + fwd * 0.03 + Vector3.UP * size.y * 0.18, rot_y, 46, text_col, F_COND)
	if sub != "":
		label(sub, pos + fwd * 0.03 - Vector3.UP * size.y * 0.2, rot_y, 26, text_col.darkened(0.15), F_COND7)


func crate_stack(k: HubMeshKit, base: Vector3, n: int, s := 0.62, col := Color("#a8743a")) -> void:
	for i in n:
		var off := Vector3(0.04 * (i % 2), s * (i + 0.5), -0.03 * (i % 2))
		k.box(base + off, Vector3(s, s * 0.98, s), col.darkened(0.06 * (i % 3)), HubMeshKit.PLANK, true)


# ---- Main Floor --------------------------------------------------------------------------------

func _main_floor() -> void:
	var k := v.kit("main_floor")
	# training mats (the landmark centre of the gym) and their border
	k.floor_rect(Rect2(-8.5, -4.5, 7.0, 6.0), 0.012, Color("#8a4b41"), HubMeshKit.MAT)
	k.box(Vector3(-5.0, 0.02, -4.55), Vector3(7.1, 0.04, 0.1), INK, HubMeshKit.PLAIN, false)
	k.box(Vector3(-5.0, 0.02, 1.55), Vector3(7.1, 0.04, 0.1), INK, HubMeshKit.PLAIN, false)
	# bag gantry: beam, posts and short arms to the three chains
	k.box(Vector3(-10.4, 2.62, 1.55), Vector3(0.18, 0.18, 9.4), STEEL, HubMeshKit.PLAIN)
	for z in [-3.15, 6.25]:
		k.box(Vector3(-10.4, 1.32, z), Vector3(0.16, 2.64, 0.16), STEEL)
		k.box(Vector3(-10.4, 0.04, z), Vector3(0.5, 0.08, 0.5), INK, HubMeshKit.PLAIN, false)
	for bid in HubLayout.BAGS:
		var d: Dictionary = HubLayout.BAGS[bid]
		var h: Vector3 = d["hang"]
		k.box(Vector3((h.x - 10.4) * 0.5, 2.62, h.z), Vector3(absf(h.x + 10.4) + 0.12, 0.1, 0.1), STEEL_L)
		var name_y := 1.25
		var plate_pos := Vector3(-8.55, name_y, h.z + (0.55 if bid != "body" else -0.75))
		k.cyl(Vector3(plate_pos.x, 0.0, plate_pos.z), Vector3(plate_pos.x, 1.0, plate_pos.z), 0.03, STEEL, 6)
		k.box(plate_pos + Vector3(0, 0.08, 0), Vector3(0.05, 0.32, 0.62), INK, HubMeshKit.PLAIN, true)
		label(str(d["name"]).to_upper(), plate_pos + Vector3(0.04, 0.12, 0), PI * 0.5, 44, GOLD, F_COND)
		label("30 S CHALLENGE", plate_pos + Vector3(0.04, -0.02, 0), PI * 0.5, 24, CANVAS, F_COND7)
	# Granny's corner: folding chair back, cooler lid, towel, her old gloves, the 1973 poster
	k.box(Vector3(-11.0, 0.75, -7.25), Vector3(0.6, 0.55, 0.06), RUST)
	k.box(Vector3(-10.05, 0.53, -7.38), Vector3(0.72, 0.06, 0.47), CANVAS)
	k.box(Vector3(-11.0, 0.53, -6.9), Vector3(0.5, 0.04, 0.3), Color("#d9c27a"))
	k.box(Vector3(-11.84, 1.7, -6.2), Vector3(0.06, 0.34, 0.24), RUST.darkened(0.2))
	k.box(Vector3(-11.84, 1.7, -5.8), Vector3(0.06, 0.34, 0.24), RUST.darkened(0.2))
	poster(k, Vector3(-9.9, 2.5, -7.83), 0.0, Vector2(1.4, 1.9), Color("#5b3f8c"), "GRANNY HAYMAKER", "CANNERY CHAMP '73")
	# Granny's clipboard (Gym Floor station)
	k.cyl(Vector3(-8.0, 0.0, -7.05), Vector3(-8.0, 1.05, -7.05), 0.04, STEEL, 6)
	k.box(Vector3(-8.0, 1.25, -7.0), Vector3(0.42, 0.56, 0.04), Color("#8a6a48"), HubMeshKit.PLANK, true, Basis(Vector3.RIGHT, -0.35))
	k.box(Vector3(-8.0, 1.24, -6.98), Vector3(0.34, 0.44, 0.02), CANVAS, HubMeshKit.PAINT, true, Basis(Vector3.RIGHT, -0.35))
	# wall graphics: the gym's name, fight posters, a clock
	label("CANNERY GYM", Vector3(-11.83, 4.6, 0.0), PI * 0.5, 150, Color("#d8cfb8"), F_BUNGEE)
	poster(k, Vector3(-6.0, 2.4, -7.83), 0.0, Vector2(1.1, 1.6), Color("#8c3b2b"), "FERAL FIGHT NIGHT", "THE GULLET")
	poster(k, Vector3(6.0, 2.4, -7.83), 0.0, Vector2(1.1, 1.6), Color("#355d7f"), "THE DOSAGE", "TEN DOSES. ONE BELT.")
	poster(k, Vector3(11.83, 2.6, 3.0), -PI * 0.5, Vector2(1.2, 1.7), Color("#2f3a2d"), "GLANDCO JUICE", "NATURALLY*")
	k.cyl(Vector3(-2.6, 4.2, -7.86), Vector3(-2.6, 4.2, -7.8), 0.42, CANVAS, 16)
	k.cyl(Vector3(-2.6, 4.2, -7.79), Vector3(-2.6, 4.2, -7.77), 0.36, Color("#2b2f3a"), 16, HubMeshKit.PLAIN, true, false, 0.02)
	# the roller door: rolled-up drum, side rails, hazard threshold
	k.cyl(Vector3(-2.2, 4.55, -8.0), Vector3(2.2, 4.55, -8.0), 0.36, STEEL, 12)
	for x in [-2.08, 2.08]:
		k.box(Vector3(x, 2.1, -8.0), Vector3(0.12, 4.2, 0.4), STEEL.darkened(0.2))
	k.floor_rect(Rect2(-2.0, -8.35, 4.0, 0.7), 0.014, Color.WHITE, HubMeshKit.HAZARD)
	label("LOADING DOCK", Vector3(0, 5.05, -7.82), 0.0, 70, GOLD, F_BUNGEE)
	# corkboard map by the roller door
	_corkboard(k)
	# under the stairs: the hatch to the Boiler Room and the Scrapling's rag pile
	k.box(Vector3(6.5, 0.015, 6.9), Vector3(1.1, 0.03, 1.1), STEEL.darkened(0.25), HubMeshKit.PLAIN, false)
	k.box(Vector3(6.5, 0.035, 6.9), Vector3(0.9, 0.02, 0.9), STEEL, HubMeshKit.CORRUGATED, false)
	k.cyl(Vector3(6.5, 0.05, 6.55), Vector3(6.5, 0.12, 6.45), 0.05, GOLD, 6)
	label("BOILER ROOM", Vector3(6.5, 0.06, 7.55), 0.0, 40, GOLD, F_COND, true)
	for i in 5:
		k.box(Vector3(10.2 + (i % 3) * 0.25, 0.06 + i * 0.02, 7.0 + (i % 2) * 0.2), Vector3(0.5, 0.08, 0.4), Color("#6f6a5e").lightened(0.05 * i), HubMeshKit.PLAIN, false)
	# freight elevator: platform, cage walls, motor housing
	var er := HubLayout.ELEVATOR_RECT
	k.box(Vector3(er.get_center().x, 0.03, er.get_center().y), Vector3(er.size.x - 0.1, 0.06, er.size.y - 0.1), STEEL, HubMeshKit.CORRUGATED, false)
	k.box(Vector3(er.get_center().x, 4.6, er.get_center().y), Vector3(er.size.x, 0.6, er.size.y), STEEL.darkened(0.3))
	for c in [Vector2(er.position.x, er.end.y), Vector2(er.position.x, er.position.y)]:
		k.box(Vector3(c.x, 2.3, c.y), Vector3(0.14, 4.6, 0.14), STEEL.darkened(0.15))
	elevator_sign = label("FREIGHT  -  OUT OF ORDER", Vector3(er.get_center().x, 3.2, er.end.y + 0.06), 0.0, 44, Color("#ff5a5a"), F_COND)
	# fluorescent tubes (dead until the gym is fixed up: HubUpgradeProps lights them)
	var spots := [Vector3(-7.0, 6.3, -4.0), Vector3(-7.0, 6.3, 3.0), Vector3(0.0, 6.3, -4.0), Vector3(0.0, 6.3, 3.0), Vector3(6.5, 6.3, -4.0), Vector3(6.5, 6.3, 3.0)]
	for sp: Vector3 in spots:
		k.box(sp + Vector3.UP * 0.08, Vector3(2.4, 0.08, 0.36), STEEL.darkened(0.3))
		k.cyl(sp + Vector3(0, 0.12, 0), sp + Vector3(0, 0.7, 0), 0.012, INK, 4)
		fluorescents.append(neon_box(sp, Vector3(2.2, 0.06, 0.12), Color("#e8f4ff"), 3.0))
	# hanging lights for the gym (energies adjusted by HubUpgradeProps when the tubes are fixed)
	for sp2: Vector3 in [Vector3(-6.5, 5.6, -0.5), Vector3(0.5, 5.6, -0.5), Vector3(7.0, 5.6, 1.0)]:
		var o := v.omni(sp2, Color("#f2efe6"), 1.3, 11.0)
		o.set_meta("gym", true)
	var cage_spot := v.spot(Vector3(HubLayout.CAGE_CENTER.x, 6.6, HubLayout.CAGE_CENTER.z), HubLayout.CAGE_CENTER, Color("#ffe9cf"), 3.2, 9.0, 34.0, true)
	cage_spot.set_meta("wants_shadow", true)
	# decorative crates and barrels along the walls
	crate_stack(k, Vector3(-11.4, 0, 7.4), 3)
	crate_stack(k, Vector3(-10.7, 0, 7.5), 2)
	k.cyl(Vector3(11.4, 0, 6.6), Vector3(11.4, 0.95, 6.6), 0.36, Color("#3b6ea8"), 12)
	k.cyl(Vector3(11.4, 0, 5.8), Vector3(11.4, 0.95, 5.8), 0.36, Color("#3b6ea8").darkened(0.2), 12)
	# a water fountain and a chalk board of the day's drills
	k.box(Vector3(11.7, 0.5, 4.8), Vector3(0.4, 1.0, 0.5), STEEL_L)
	poster(k, Vector3(-11.83, 2.2, 2.4), PI * 0.5, Vector2(1.5, 1.0), Color("#2f3a2d"), "TODAY: GUARD", "chin down. hands up.", Color("#e8e6dc"))


func _corkboard(k: HubMeshKit) -> void:
	var c := Vector3(3.6, 1.7, -7.84)
	k.box(c, Vector3(2.1, 1.4, 0.05), Color("#b0844f"), HubMeshKit.PLAIN)
	k.box(c + Vector3(0, 0, -0.02), Vector3(2.25, 1.55, 0.04), Color("#5a3b22"))
	label("THE CANNERY", c + Vector3(0, 0.55, 0.035), 0.0, 40, INK, F_COND)
	# a little floor plan of pinned cards (scaled 1:30)
	for sid in HubLayout.TOUR:
		var r: Rect2 = HubLayout.SPACES[sid]["rect"]
		var center := Vector3(c.x + r.get_center().x / 30.0, c.y - 0.05 - r.get_center().y / 30.0, c.z + 0.035)
		k.box(center, Vector3(maxf(0.08, r.size.x / 30.0 - 0.02), maxf(0.06, r.size.y / 30.0 - 0.02), 0.012), CANVAS.darkened(0.05), HubMeshKit.PAINT)
		k.sphere(center + Vector3(0, 0, 0.01), 0.018, Color("#ff5a5a"), 3, 5)
	k.cyl(Vector3(c.x - 0.7, 0.0, -7.6), Vector3(c.x - 0.7, 0.9, -7.6), 0.03, STEEL, 6)


# ---- the practice cage (a 6 m mini-Gullet) ----------------------------------------------------

func _cage() -> void:
	var k := v.kit("main_floor")
	var pts := HubLayout.cage_points()
	var c := HubLayout.CAGE_CENTER
	var circ := HubLayout.CAGE_APOTHEM / cos(PI / 8.0)
	# canvas mat on a low apron
	for i in 8:
		var a := pts[i]
		var b := pts[(i + 1) % 8]
		k.tri(Vector3(c.x, 0.1, c.z), Vector3(b.x, 0.1, b.y), Vector3(a.x, 0.1, a.y), CANVAS, HubMeshKit.PLAIN, false)
		k.quad(Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y), Vector3(b.x, 0.1, b.y), Vector3(a.x, 0.1, a.y), Color("#1d2140"), HubMeshKit.PLAIN, false)
	annulus(k, Vector3(c.x, 0.105, c.z), circ * 0.55, circ * 0.58, Color("#b8322a"), 32)
	var fence_mat := ShaderMaterial.new()
	fence_mat.shader = load("res://src/view/shaders/fence.gdshader")
	fence_mat.set_shader_parameter("wire_color", Color("#9aa0aa"))
	for i in 8:
		var a := pts[i]
		var b := pts[(i + 1) % 8]
		k.cyl(Vector3(a.x, 0.0, a.y), Vector3(a.x, 2.35, a.y), 0.11, Color("#c23a2b"), 10)
		if i == HubLayout.CAGE_GATE_SIDE:
			k.cyl(Vector3(a.x, 2.2, a.y), Vector3(b.x, 2.2, b.y), 0.05, STEEL.darkened(0.3), 6)
			continue
		var mid := (a + b) * 0.5
		var len := a.distance_to(b)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(len, 2.2)
		q.mesh = qm
		q.material_override = fence_mat
		q.position = Vector3(mid.x, 1.2, mid.y)
		q.rotation = Vector3(0, -atan2(b.y - a.y, b.x - a.x), 0)
		v.add_child(q)
		k.cyl(Vector3(a.x, 2.3, a.y), Vector3(b.x, 2.3, b.y), 0.06, Color("#151219"), 6)
		k.cyl(Vector3(a.x, 0.18, a.y), Vector3(b.x, 0.18, b.y), 0.04, Color("#151219"), 6)
	label("PRACTICE CAGE", Vector3(c.x - circ - 0.05, 2.6, c.z), -PI * 0.5, 54, GOLD, F_COND)
	# the sponsor banner hanging over the cage (HubUpgradeProps swaps it at 24 upgrades)
	cage_banner = Node3D.new()
	cage_banner.name = "CageBanner"
	v.add_child(cage_banner)
	cage_banner.position = Vector3(c.x, 5.3, c.z + 3.4)
	var bk := HubMeshKit.new()
	bk.box(Vector3(0, 0, 0), Vector3(5.2, 1.5, 0.05), Color("#2f6b1f"), HubMeshKit.PLAIN, true)
	bk.cyl(Vector3(-2.7, 0.78, 0), Vector3(2.7, 0.78, 0), 0.04, STEEL, 6)
	var bm := bk.commit("BannerCloth", v.surface_mat)
	cage_banner.add_child(bm)
	var bl := Label3D.new()
	bl.text = "GLANDCO"
	bl.font = load(F_BUNGEE)
	bl.font_size = 110
	bl.pixel_size = 0.006
	bl.modulate = Color("#e8f7c8")
	bl.position = Vector3(0, 0.12, 0.04)
	cage_banner.add_child(bl)
	var bl2 := Label3D.new()
	bl2.text = "PROUD SPONSOR OF THE CIRCUIT"
	bl2.font = load(F_COND)
	bl2.font_size = 40
	bl2.pixel_size = 0.006
	bl2.modulate = Color("#c9e8a0")
	bl2.position = Vector3(0, -0.45, 0.04)
	cage_banner.add_child(bl2)


# ---- Juice Bar ---------------------------------------------------------------------------------

func _juice_bar() -> void:
	var k := v.kit("juice_bar")
	# counter top and kick plate, stools, back shelf of bottles, dispensers
	k.box(Vector3(-19.8, 1.08, -4.3), Vector3(1.0, 0.06, 6.4), Color("#d8d2bd"), HubMeshKit.PLAIN)
	k.box(Vector3(-19.38, 0.08, -4.3), Vector3(0.06, 0.16, 6.2), GREEN.darkened(0.45))
	for z in [-6.6, -5.2, -3.6, -2.1]:
		k.cyl(Vector3(-18.75, 0.0, z), Vector3(-18.75, 0.7, z), 0.04, STEEL, 6)
		k.cyl(Vector3(-18.75, 0.7, z), Vector3(-18.75, 0.78, z), 0.22, RUST, 12)
	k.box(Vector3(-21.75, 1.55, -4.0), Vector3(0.4, 0.05, 5.6), Color("#5e4a3a"), HubMeshKit.PLANK)
	k.box(Vector3(-21.75, 2.15, -4.0), Vector3(0.4, 0.05, 5.6), Color("#5e4a3a"), HubMeshKit.PLANK)
	var bottle_cols := [GREEN, Color("#e04fb0"), Color("#ffc43d"), Color("#2e9be0"), Color("#ff6b2b"), Color("#cff4f2")]
	for i in 18:
		var z2 := -6.6 + i * 0.3
		var shelf_y := 1.58 if i % 2 == 0 else 2.18
		k.cyl(Vector3(-21.75, shelf_y, z2), Vector3(-21.75, shelf_y + 0.26, z2), 0.05, bottle_cols[i % bottle_cols.size()], 6)
	for j in 3:
		var dz := -7.0 + j * 0.55
		k.cyl(Vector3(-19.9, 1.1, dz), Vector3(-19.9, 1.65, dz), 0.18, bottle_cols[j].lightened(0.2), 10)
		k.box(Vector3(-19.9, 1.72, dz), Vector3(0.4, 0.1, 0.4), STEEL)
	# the radio on the counter
	k.box(Vector3(-19.8, 1.22, -2.0), Vector3(0.24, 0.22, 0.42), Color("#6a3d2a"))
	k.cyl(Vector3(-19.66, 1.22, -2.1), Vector3(-19.66, 1.22, -2.1 + 0.001), 0.07, Color("#d8c9a0"), 10)
	# Needles' menu board (Juice Bar station) on the back wall
	k.box(Vector3(-21.84, 2.2, -6.4), Vector3(0.05, 1.1, 1.6), Color("#22261f"))
	label("NEEDLES' MENU", Vector3(-21.8, 2.6, -6.4), PI * 0.5, 40, GREEN, F_COND)
	label("ALL NATURAL*", Vector3(-21.8, 2.25, -6.4), PI * 0.5, 30, CANVAS, F_COND7)
	label("*recently", Vector3(-21.8, 1.9, -6.4), PI * 0.5, 22, Color("#9aa0ab"), F_COND7)
	# vending machine front and branding
	k.box(Vector3(-13.4, 1.15, -7.48), Vector3(0.7, 1.2, 0.04), Color("#1b2a14"), HubMeshKit.PLAIN)
	label("GLANDCO", Vector3(-13.4, 1.86, -7.45), 0.0, 40, CANVAS, F_BUNGEE)
	# tables' chairs
	for t in [Vector3(-15.1, 0, -6.5), Vector3(-15.1, 0, -1.8)]:
		for off in [Vector3(0.75, 0, 0), Vector3(-0.75, 0, 0)]:
			k.box(t + off + Vector3(0, 0.45, 0), Vector3(0.4, 0.06, 0.4), Color("#5e4a3a"), HubMeshKit.PLANK)
			k.cyl(t + off, t + off + Vector3(0, 0.45, 0), 0.03, STEEL, 6)
	# THE JUICE NEON CAN (landmark) and the door sign
	var can_pos := Vector3(-17.0, 2.55, -7.82)
	neon_box(can_pos + Vector3(-0.38, 0, 0), Vector3(0.06, 1.2, 0.05), GREEN)
	neon_box(can_pos + Vector3(0.38, 0, 0), Vector3(0.06, 1.2, 0.05), GREEN)
	neon_box(can_pos + Vector3(0, 0.6, 0), Vector3(0.8, 0.06, 0.05), GREEN)
	neon_box(can_pos + Vector3(0, -0.6, 0), Vector3(0.8, 0.06, 0.05), GREEN)
	neon_text("JUICE", can_pos + Vector3(0, 0.02, 0.02), 0.0, 0.32, GREEN)
	neon_text("JUICE BAR", Vector3(-12.17, 2.85, -4.0), PI * 0.5, 0.34, GREEN)
	v.omni(Vector3(-17.0, 2.4, -7.0), GREEN, 0.9, 4.5)
	v.omni(Vector3(-19.2, 3.1, -5.2), Color("#ffd9a0"), 1.4, 6.0)
	v.omni(Vector3(-15.0, 3.1, -2.5), Color("#ffd9a0"), 1.2, 6.5)
	for p in [Vector3(-19.2, 3.2, -5.2), Vector3(-15.0, 3.2, -2.5)]:
		k.cyl(p + Vector3.UP * 0.1, p + Vector3.UP * 0.8, 0.01, INK, 4)
		k.cyl(p - Vector3.UP * 0.1, p + Vector3.UP * 0.1, 0.25, Color("#2f3a2d"), 10, HubMeshKit.PLAIN, true, true, 0.08)
		neon_box(p - Vector3.UP * 0.12, Vector3(0.18, 0.06, 0.18), Color("#ffe6b8"), 3.0)


# ---- Med Bay -----------------------------------------------------------------------------------

func _med_bay() -> void:
	var k := v.kit("med_bay")
	# exam table pad, IV stand, cabinet with a cross, sink, Doc's chart on the wall
	k.box(Vector3(16.6, 0.9, -5.55), Vector3(1.9, 0.1, 0.8), Color("#e9e2cf"), HubMeshKit.PLAIN)
	k.cyl(Vector3(17.9, 0.0, -6.5), Vector3(17.9, 2.0, -6.5), 0.025, STEEL_L, 6)
	k.box(Vector3(17.9, 1.85, -6.5), Vector3(0.18, 0.26, 0.08), Color("#b7e0ec"))
	k.box(Vector3(19.7, 1.1, -7.2), Vector3(0.5, 2.2, 1.0), CANVAS)
	k.box(Vector3(19.44, 1.6, -7.2), Vector3(0.02, 0.4, 0.12), Color("#ff5a5a"))
	k.box(Vector3(19.44, 1.6, -7.2), Vector3(0.02, 0.12, 0.4), Color("#ff5a5a"))
	k.box(Vector3(13.4, 0.9, -7.7), Vector3(0.9, 0.12, 0.5), STEEL_L)
	k.box(Vector3(13.4, 1.6, -7.86), Vector3(0.7, 0.8, 0.03), Color("#cfe3ea"))
	k.box(Vector3(19.86, 1.5, -3.2), Vector3(0.04, 0.6, 0.45), Color("#8a6a48"), HubMeshKit.PLANK)
	k.box(Vector3(19.83, 1.48, -3.2), Vector3(0.02, 0.48, 0.36), CANVAS, HubMeshKit.PAINT)
	label("DOC'S CHART", Vector3(19.8, 1.95, -3.2), -PI * 0.5, 30, INK, F_COND)
	# cot pillow and blanket
	k.box(Vector3(12.8, 0.62, -7.15), Vector3(0.45, 0.12, 0.6), CANVAS)
	k.box(Vector3(13.8, 0.58, -7.15), Vector3(1.2, 0.06, 0.82), Color("#5d8aa8"))
	# the dumpster ice bath: lip, ice water, floating ice, hose and a stencil
	k.box(Vector3(17.0, 1.03, -1.55), Vector3(3.3, 0.06, 1.85), Color("#2c4d39"), HubMeshKit.PLAIN)
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.8, 1.4)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.72, 0.9, 0.98, 0.55)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.05
	water.material_override = wm
	water.position = Vector3(17.0, 0.86, -1.46)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(water)
	for i in 7:
		k.box(Vector3(15.9 + i * 0.37, 0.88, -1.9 + (i % 3) * 0.42), Vector3(0.18, 0.12, 0.18), Color("#f2fbff"), HubMeshKit.PLAIN, false, Basis(Vector3.UP, i * 0.7))
	k.cyl(Vector3(18.7, 0.05, -2.4), Vector3(18.7, 1.0, -1.2), 0.04, Color("#2f6b1f"), 6)
	label("ICE BATH", Vector3(17.0, 0.7, -2.36), 0.0, 40, CANVAS, F_COND)
	label("DOC'S ORDERS", Vector3(17.0, 0.5, -2.36), 0.0, 24, CANVAS, F_COND7)
	label("MED BAY", Vector3(12.17, 2.85, -2.5), -PI * 0.5, 70, Color("#e8f4ff"), F_BUNGEE)
	neon_box(Vector3(12.2, 2.85, -1.3), Vector3(0.04, 0.4, 0.12), Color("#ff5a5a"), 2.0)
	neon_box(Vector3(12.2, 2.85, -1.3), Vector3(0.04, 0.12, 0.4), Color("#ff5a5a"), 2.0)
	v.omni(Vector3(16.0, 3.4, -5.5), Color("#e8f4ff"), 1.5, 7.0)
	v.omni(Vector3(16.0, 3.4, -1.6), Color("#e8f4ff"), 1.2, 6.0)
	for p in [Vector3(16.0, 3.7, -5.5), Vector3(16.0, 3.7, -1.6)]:
		neon_box(p, Vector3(1.4, 0.05, 0.12), Color("#eaf6ff"), 2.4)


# ---- Locker Room -------------------------------------------------------------------------------

func _locker_room() -> void:
	var k := v.kit("locker_room")
	# locker doors, vents, a few numbers
	for i in 15:
		var x := -11.3 + i * 0.6
		k.box(Vector3(x, 1.0, 15.28), Vector3(0.02, 1.9, 0.02), INK, HubMeshKit.PLAIN, true)
		for j in 3:
			k.box(Vector3(x + 0.3, 1.6 + j * 0.06, 15.28), Vector3(0.3, 0.02, 0.02), INK.lightened(0.15))
	label("LOCKERS", Vector3(-7.0, 2.3, 15.26), PI, 60, CANVAS, F_BUNGEE)
	# the player's own locker (Locker station) gets a gold tag
	k.box(Vector3(-9.6, 1.3, 15.27), Vector3(0.5, 0.12, 0.02), GOLD)
	# towels on the bench, a mirror, a drain
	k.box(Vector3(-9.8, 0.48, 11.12), Vector3(0.5, 0.05, 0.4), Color("#e8e6dc"))
	k.box(Vector3(-0.17, 1.6, 14.2), Vector3(0.03, 1.1, 1.4), Color("#cfe3ea"))
	disc(k, Vector3(-6.0, 0.006, 12.6), 0.12, Color("#3b4a55"), HubMeshKit.PLAIN)
	# Wall of Fame / Shame board (photos are added by HubPropsView from the run history)
	k.box(Vector3(-11.83, 1.95, 12.0), Vector3(0.05, 1.7, 4.8), Color("#5a3b22"), HubMeshKit.PLANK)
	label("WALL OF FAME", Vector3(-11.79, 2.95, 11.0), PI * 0.5, 44, GOLD, F_COND)
	label("& SHAME", Vector3(-11.79, 2.95, 13.0), PI * 0.5, 44, Color("#ff5a5a"), F_COND)
	# the belt case: wooden base, glass box, the replica belt inside
	var bc := HubLayout.BELT_CASE_POS
	k.box(Vector3(bc.x, 1.32, bc.z), Vector3(1.24, 0.04, 0.64), GOLD)
	var glass := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(1.1, 0.6, 0.5)
	glass.mesh = gb
	glass.material_override = v.glass_mat
	glass.position = Vector3(bc.x, 1.64, bc.z)
	glass.name = "BeltCaseGlass"
	v.add_child(glass)
	k.cyl(Vector3(bc.x - 0.42, 1.55, bc.z), Vector3(bc.x + 0.42, 1.55, bc.z), 0.06, Color("#3a2a1a"), 10)
	k.cyl(Vector3(bc.x - 0.16, 1.55, bc.z + 0.05), Vector3(bc.x + 0.16, 1.55, bc.z + 0.05), 0.15, GOLD, 12)
	label("CIRCUIT TITLE BELT", Vector3(bc.x, 1.16, bc.z + 0.31), 0.0, 26, GOLD, F_COND7)
	# the ladder up to the booth
	for side in [-0.25, 0.25]:
		k.box(Vector3(-0.22, 1.85, 10.2 + side), Vector3(0.06, 3.7, 0.06), STEEL)
	for r in 12:
		k.cyl(Vector3(-0.22, 0.3 + r * 0.3, 9.95), Vector3(-0.22, 0.3 + r * 0.3, 10.45), 0.02, STEEL_L, 4)
	label("BOOTH", Vector3(-0.2, 3.2, 10.2), -PI * 0.5, 34, GOLD, F_COND)
	label("LOCKER ROOM", Vector3(-7.0, 2.85, 7.82), PI, 64, Color("#d8e6ee"), F_BUNGEE)
	v.omni(Vector3(-8.0, 3.1, 12.0), Color("#dfefff"), 1.3, 7.0)
	v.omni(Vector3(-3.0, 3.1, 12.0), Color("#dfefff"), 1.1, 6.5)
	for p in [Vector3(-8.0, 3.4, 12.0), Vector3(-3.0, 3.4, 12.0)]:
		neon_box(p, Vector3(1.6, 0.05, 0.1), Color("#e8f4ff"), 2.2)


# ---- Commissioner's Office ----------------------------------------------------------------------

func _office() -> void:
	var k := v.kit("office")
	var y := 4.0
	k.floor_rect(Rect2(8.4, 10.6, 3.2, 2.8), y + 0.008, Color("#7a2a2a"), HubMeshKit.PLAIN)
	# sign-up stand (run start) and the ledger lectern (Office station)
	k.cyl(Vector3(8.6, y, 11.25), Vector3(8.6, y + 1.0, 11.25), 0.04, GOLD, 6)
	k.box(Vector3(8.6, y + 1.1, 11.2), Vector3(0.5, 0.36, 0.05), Color("#1a1d24"), HubMeshKit.PLAIN, true, Basis(Vector3.RIGHT, -0.3))
	label("FIGHT CARD", Vector3(8.6, y + 1.2, 11.17), 0.0, 30, GOLD, F_COND)
	label("SIGN-UPS", Vector3(8.6, y + 1.06, 11.17), 0.0, 26, CANVAS, F_COND7)
	k.box(Vector3(11.4, y + 0.5, 11.35), Vector3(0.4, 1.0, 0.35), Color("#5a3b22"), HubMeshKit.PLANK)
	k.box(Vector3(11.4, y + 1.05, 11.3), Vector3(0.5, 0.08, 0.42), Color("#efe6d2"), HubMeshKit.PAINT, true, Basis(Vector3.RIGHT, -0.25))
	label("LEDGER", Vector3(11.4, y + 1.26, 11.1), 0.0, 26, GOLD, F_COND)
	# filing cabinet #1 drawer lines, the Commission's seal, a trophy shelf, a coat rack
	for d in 3:
		k.box(Vector3(6.77, y + 0.3 + d * 0.42, 8.95), Vector3(0.02, 0.02, 0.5), INK)
	k.cyl(Vector3(10.0, y + 1.9, 13.83), Vector3(10.0, y + 1.9, 13.86), 0.55, GOLD, 18)
	label("CIRCUIT COMMISSION", Vector3(10.0, y + 1.9, 13.8), PI, 30, INK, F_COND)
	k.box(Vector3(13.8, y + 1.6, 12.0), Vector3(0.3, 0.05, 2.0), Color("#5a3b22"), HubMeshKit.PLANK)
	for t in 3:
		k.cyl(Vector3(13.8, y + 1.63, 11.3 + t * 0.6), Vector3(13.8, y + 1.95, 11.3 + t * 0.6), 0.08, GOLD, 8)
	k.cyl(Vector3(13.4, y, 9.0), Vector3(13.4, y + 1.8, 9.0), 0.03, Color("#3a2a1a"), 6)
	label("OFFICE OF THE COMMISSIONER", Vector3(10.5, 6.75, 7.83), PI, 30, GOLD, F_COND)
	v.omni(Vector3(10.0, y + 2.4, 11.0), Color("#ffd9a0"), 1.2, 6.5)
	v.omni(Vector3(10.6, y + 1.2, 12.0), Color("#b8ffcf"), 0.6, 3.0)


# ---- Broadcast Booth ----------------------------------------------------------------------------

func _booth() -> void:
	var k := v.kit("booth")
	var y := 3.0
	# mixing desk knobs and faders, mics, monitors, egg-crate foam, Barnaby's empty chair
	for i in 16:
		k.cyl(Vector3(2.6 + i * 0.18, y + 0.96, 8.55), Vector3(2.6 + i * 0.18, y + 1.0, 8.55), 0.025, Color("#e8e6dc") if i % 3 else Color("#ff5a5a"), 6)
	for m in [3.3, 4.6]:
		k.cyl(Vector3(m, y + 0.95, 8.7), Vector3(m, y + 1.35, 8.75), 0.012, INK, 4)
		k.sphere(Vector3(m, y + 1.4, 8.78), 0.055, Color("#2b2f3a"), 4, 6)
	k.box(Vector3(5.2, y + 1.25, 8.4), Vector3(0.5, 0.35, 0.06), INK)
	neon_box(Vector3(5.2, y + 1.25, 8.44), Vector3(0.44, 0.28, 0.01), Color("#35c1c9"), 1.6)
	for i2 in 5:
		k.box(Vector3(0.6 + i2 * 1.2, y + 1.9, 11.84), Vector3(1.0, 1.2, 0.06), Color("#3b3540").lightened(0.06 * (i2 % 2)), HubMeshKit.PLAIN)
	k.cyl(Vector3(1.6, y, 9.6), Vector3(1.6, y + 0.45, 9.6), 0.04, STEEL, 6)
	k.cyl(Vector3(1.6, y + 0.45, 9.6), Vector3(1.6, y + 0.52, 9.6), 0.26, GOLD.darkened(0.3), 10)
	# the dusty tape under the desk (only a crouching fighter can reach it)
	k.box(Vector3(1.35, y + 0.03, 9.1), Vector3(0.12, 0.03, 0.08), Color("#3a3a3a"))
	# ON AIR sign
	k.box(Vector3(3.0, y + 2.25, 11.83), Vector3(1.1, 0.36, 0.06), INK)
	neon_text("ON AIR", Vector3(3.0, y + 2.2, 11.79), PI, 0.26, Color("#ff3b3b"), 3.0)
	v.omni(Vector3(3.0, y + 1.9, 10.6), Color("#ffd2a8"), 1.0, 5.0)
	v.omni(Vector3(3.0, y + 2.1, 11.4), Color("#ff3b3b"), 0.5, 3.0)


# ---- Loading Dock -------------------------------------------------------------------------------

func _dock() -> void:
	var k := v.kit("loading_dock")
	# crate toss: throw line, rings at 3 / 5 / 8 m, distance stencils
	k.box(Vector3(HubLayout.CRATE_LANE_X, 0.012, HubLayout.CRATE_LINE_Z), Vector3(4.2, 0.02, 0.12), CANVAS, HubMeshKit.PAINT, false)
	label("THROW LINE", Vector3(HubLayout.CRATE_LANE_X, 0.03, HubLayout.CRATE_LINE_Z + 0.35), 0.0, 40, CANVAS, F_COND, true)
	for rd in HubLayout.CRATE_RINGS:
		var cz := HubLayout.CRATE_LINE_Z - float(rd["dist"])
		var rr := float(rd["r"])
		annulus(k, Vector3(HubLayout.CRATE_LANE_X, 0.012, cz), rr - 0.07, rr, CANVAS, 36)
		annulus(k, Vector3(HubLayout.CRATE_LANE_X, 0.013, cz), rr * 0.45, rr * 0.5, Color("#ff5a5a"), 24)
		label("%d M  ·  %d" % [int(rd["dist"]), int(rd["points"])], Vector3(HubLayout.CRATE_LANE_X + rr + 0.55, 0.03, cz), 0.0, 40, CANVAS, F_COND, true)
	# chum drill square
	var sq := HubLayout.DRILL_SQUARE
	k.box(Vector3(sq.get_center().x, 0.012, sq.position.y), Vector3(sq.size.x + 0.12, 0.02, 0.12), Color("#ffc43d"), HubMeshKit.PAINT, false)
	k.box(Vector3(sq.get_center().x, 0.012, sq.end.y), Vector3(sq.size.x + 0.12, 0.02, 0.12), Color("#ffc43d"), HubMeshKit.PAINT, false)
	k.box(Vector3(sq.position.x, 0.012, sq.get_center().y), Vector3(0.12, 0.02, sq.size.y), Color("#ffc43d"), HubMeshKit.PAINT, false)
	k.box(Vector3(sq.end.x, 0.012, sq.get_center().y), Vector3(0.12, 0.02, sq.size.y), Color("#ffc43d"), HubMeshKit.PAINT, false)
	label("CHUM DRILL", Vector3(sq.get_center().x, 0.03, sq.end.y + 0.4), 0.0, 48, Color("#ffc43d"), F_COND, true)
	# the chum cannon
	var cp := HubLayout.CANNON_POS
	k.box(cp + Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 1.2), STEEL.darkened(0.2))
	k.cyl(cp + Vector3(0.2, 0.75, 0), cp + Vector3(-1.0, 1.25, 0), 0.22, STEEL_L, 12)
	k.cyl(cp + Vector3(0.35, 0.6, 0.45), cp + Vector3(0.35, 1.4, 0.45), 0.2, Color("#c23a2b"), 10)
	k.cyl(cp + Vector3(0.3, 0.6, -0.45), cp + Vector3(0.3, 1.1, -0.45), 0.28, Color("#4b6b3a"), 10, HubMeshKit.PLAIN, true, true, 0.34)
	label("CHUM CANNON", cp + Vector3(0, 1.0, 0.62), 0.0, 34, CANVAS, F_COND)
	# forklift (solid blocker in HubWorld) with the cable spool tucked behind it
	var fp := Vector3(5.4, 0, -10.6)
	k.box(fp + Vector3(0, 0.7, 0.2), Vector3(1.3, 1.0, 1.6), Color("#e0a21c"))
	k.box(fp + Vector3(0, 1.45, 0.45), Vector3(0.6, 0.5, 0.6), INK)
	for xo in [-0.5, 0.5]:
		k.box(fp + Vector3(xo, 1.6, -0.75), Vector3(0.1, 3.0, 0.12), STEEL.darkened(0.3))
		k.box(fp + Vector3(xo * 0.6, 0.08, -1.25), Vector3(0.12, 0.06, 1.0), STEEL)
		for zo in [-0.45, 0.75]:
			k.cyl(fp + Vector3(xo * 1.3, 0.28, zo), fp + Vector3(xo * 1.3 + signf(xo) * 0.2, 0.28, zo), 0.28, INK, 10)
	k.box(fp + Vector3(0, 2.2, 0.35), Vector3(1.3, 0.06, 1.4), STEEL.darkened(0.3))
	# Ludlow's workbench: vice, tool board, lamp
	k.box(Vector3(-9.5, 0.98, -14.4), Vector3(0.9, 0.06, 2.5), Color("#8a6a48"), HubMeshKit.PLANK)
	k.box(Vector3(-9.45, 1.1, -15.2), Vector3(0.25, 0.2, 0.3), STEEL)
	k.box(Vector3(-10.0, 1.75, -14.4), Vector3(0.05, 1.0, 2.2), Color("#5e4a3a"), HubMeshKit.PLANK)
	for t in 6:
		k.box(Vector3(-9.96, 1.5 + (t % 2) * 0.35, -15.2 + t * 0.3), Vector3(0.04, 0.3, 0.05), STEEL_L)
	label("LUDLOW'S BENCH", Vector3(-9.94, 2.4, -14.4), PI * 0.5, 30, GOLD, F_COND)
	# crate stacks and bollards along the edge, mooring ropes
	crate_stack(k, Vector3(-9.6, 0, -9.2), 3)
	crate_stack(k, Vector3(-8.9, 0, -9.1), 2, 0.62, Color("#9a6a34"))
	crate_stack(k, Vector3(9.4, 0, -9.2), 2)
	for x in [-9.0, -4.0, 1.0, 6.0]:
		k.cyl(Vector3(x, 0, -18.35), Vector3(x, 0.55, -18.35), 0.16, INK, 10)
		k.cyl(Vector3(x, 0.55, -18.35), Vector3(x, 0.62, -18.35), 0.22, INK, 10)
	# the pier ladder at the edge (hidden under a tarp until the gulls leave: HubPropsView)
	for side2 in [-0.25, 0.25]:
		k.box(Vector3(HubLayout.PIER_LADDER.x + side2, -0.4, -18.62), Vector3(0.06, 1.4, 0.06), STEEL)
	# flood lamps on the building wall
	for xl in [-6.0, 6.0]:
		k.box(Vector3(xl, 5.6, -8.25), Vector3(0.5, 0.3, 0.3), INK)
		var s := v.spot(Vector3(xl, 5.5, -8.4), Vector3(xl * 0.5, 0, -14.0), Color("#ffe9cf"), 2.0, 16.0, 45.0)
		s.set_meta("flood", true)
	label("LOADING DOCK", Vector3(0, 5.1, -8.18), PI, 70, GOLD, F_BUNGEE)


# ---- Boiler Room --------------------------------------------------------------------------------

func _boiler_room() -> void:
	var k := v.kit("boiler_room")
	var b := HubLayout.BOILER_POS
	# the boiler (landmark): riveted drum, firebox face, pipes, gauges
	k.cyl(b, b + Vector3(0, 3.4, 0), HubLayout.BOILER_R, Color("#5c4a3e"), 20, HubMeshKit.PLAIN)
	for ring in 4:
		k.cyl(b + Vector3(0, 0.3 + ring * 0.9, 0), b + Vector3(0, 0.38 + ring * 0.9, 0), HubLayout.BOILER_R + 0.03, Color("#3a2e27"), 20)
	var face := b + Vector3(-HubLayout.BOILER_R - 0.02, 0, 0)
	k.box(face + Vector3(0, 0.8, 0), Vector3(0.06, 0.6, 0.9), INK)
	k.cyl(face + Vector3(-0.02, 1.85, -0.35), face + Vector3(-0.08, 1.85, -0.35), 0.16, STEEL_L, 12)
	k.cyl(face + Vector3(-0.02, 1.85, 0.35), face + Vector3(-0.08, 1.85, 0.35), 0.16, STEEL_L, 12)
	neon_box(face + Vector3(-0.05, 0.8, 0), Vector3(0.02, 0.4, 0.7), Color("#ff6b2b"), 2.2)
	for pz in [-1.0, 0.0, 1.0]:
		k.cyl(b + Vector3(0.6, 3.4, pz * 0.8), b + Vector3(0.6, 4.0, pz * 0.8), 0.12, STEEL, 8)
	k.cyl(b + Vector3(0.6, 3.7, -0.8), Vector3(53.8, 3.7, -0.8), 0.1, STEEL, 8)
	k.cyl(Vector3(40.2, 3.4, -4.6), Vector3(53.8, 3.4, -4.6), 0.08, Color("#8c3b2b"), 8)
	k.cyl(Vector3(40.2, 3.0, 4.6), Vector3(53.8, 3.0, 4.6), 0.07, STEEL, 8)
	# fuse box on the boiler's side (the fuse itself is a prop: HubPropsView)
	k.box(Vector3(48.85, 0.95, -1.0), Vector3(0.14, 0.6, 0.4), STEEL.darkened(0.2))
	label("FUSE", Vector3(48.77, 1.32, -1.0), -PI * 0.5, 24, GOLD, F_COND)
	# Teddy's card table under one bulb
	var t := Vector3(45.0, 0, -2.3)
	k.cyl(t, t + Vector3(0, 0.7, 0), 0.06, INK, 6)
	k.cyl(t + Vector3(0, 0.68, 0), t + Vector3(0, 0.74, 0), 0.7, Color("#2f5b3a"), 18)
	for c in 4:
		var ca := TAU * c / 4.0 + 0.4
		k.box(t + Vector3(cos(ca) * 0.3, 0.76, sin(ca) * 0.3), Vector3(0.12, 0.01, 0.17), CANVAS, HubMeshKit.PAINT, true, Basis(Vector3.UP, ca))
	k.box(t + Vector3(0.1, 0.78, 0.0), Vector3(0.06, 0.06, 0.06), CANVAS)
	k.box(t + Vector3(0.2, 0.78, 0.1), Vector3(0.06, 0.06, 0.06), CANVAS)
	k.cyl(t + Vector3(0, 2.3, 0), t + Vector3(0, 4.0, 0), 0.008, INK, 4)
	neon_box(t + Vector3(0, 2.25, 0), Vector3(0.1, 0.14, 0.1), Color("#ffd28a"), 4.0)
	var bulb := v.omni(t + Vector3(0, 2.1, 0), Color("#ffcf85"), 2.6, 7.5, true)
	bulb.set_meta("wants_shadow", true)
	for sc in [Vector3(45.0, 0, -3.3), Vector3(45.9, 0, -1.6), Vector3(44.1, 0, -1.6)]:
		k.box(sc + Vector3(0, 0.45, 0), Vector3(0.38, 0.06, 0.38), Color("#6a5236"), HubMeshKit.PLANK)
	# Teddy's ledger desk, the AI Lab terminal
	k.box(Vector3(43.0, 0.9, -4.5), Vector3(0.6, 0.05, 0.42), Color("#efe6d2"), HubMeshKit.PAINT)
	label("TEDDY'S LEDGER", Vector3(43.0, 1.35, -4.75), 0.0, 26, GOLD, F_COND)
	k.box(Vector3(53.3, 1.65, 3.4), Vector3(0.6, 0.7, 0.8), Color("#cfc7b0"))
	neon_box(Vector3(52.98, 1.65, 3.4), Vector3(0.02, 0.5, 0.62), Color("#3fc27a"), 2.2)
	label("AI LAB", Vector3(52.95, 2.25, 3.4), -PI * 0.5, 40, Color("#3fc27a"), F_COND)
	v.omni(Vector3(52.2, 1.8, 3.4), Color("#3fc27a"), 0.8, 3.5)
	# the ladder up to the hatch, puddles, the face's glow
	for side in [-0.25, 0.25]:
		k.box(Vector3(40.25, 2.0, 4.0 + side), Vector3(0.06, 4.0, 0.06), STEEL)
	for r in 12:
		k.cyl(Vector3(40.25, 0.3 + r * 0.3, 3.75), Vector3(40.25, 0.3 + r * 0.3, 4.25), 0.02, STEEL_L, 4)
	label("UP TO THE MAIN FLOOR", Vector3(40.18, 2.6, 4.0), PI * 0.5, 30, GOLD, F_COND)
	disc(k, Vector3(47.5, 0.006, 2.5), 0.9, Color("#3b4a55"), HubMeshKit.PLAIN)
	disc(k, Vector3(42.4, 0.006, -1.0), 0.6, Color("#3b4a55"), HubMeshKit.PLAIN)
	v.omni(Vector3(48.4, 1.0, -2.0), Color("#ff7a2b"), 1.4, 4.5)


# ---- Roof ---------------------------------------------------------------------------------------

func _roof() -> void:
	var k := v.kit("roof")
	# gravel patches, the elevator housing, the sign frame and letters, the water tower
	for i in 6:
		disc(k, Vector3(42.0 + i * 2.5, 0.006, -27.0 - (i % 3) * 2.5), 0.9, Color("#5a5960"), HubMeshKit.CONCRETE, 10)
	k.box(Vector3(41.0, 1.4, -24.6), Vector3(1.8, 2.8, 1.0), Color("#5a5960"), HubMeshKit.CORRUGATED)
	label("FREIGHT", Vector3(41.0, 2.2, -25.12), PI, 34, GOLD, F_COND)
	for x in [43.0, 48.0, 53.0]:
		k.box(Vector3(x, 1.7, -35.5), Vector3(0.12, 3.4, 0.12), STEEL)
	k.box(Vector3(48.0, 2.15, -35.5), Vector3(10.6, 0.08, 0.1), STEEL)
	k.box(Vector3(48.0, 3.75, -35.5), Vector3(10.6, 0.08, 0.1), STEEL)
	var letters := ["G", "L", "A", "N", "D", "C", "O"]
	for i2 in letters.size():
		var lx := 43.7 + i2 * 1.45
		var ln := neon_text(str(letters[i2]), Vector3(lx, 2.9, -35.42), 0.0, 1.25, Color("#8bd426") if i2 != 2 else Color("#ff4fb8"), 3.2)
		sign_letters[str(letters[i2]) + str(i2)] = ln
	v.omni(Vector3(48.0, 3.0, -34.2), Color("#8bd426"), 1.6, 8.0)
	var t := Vector3(53.1, 0, -27.3)
	for lx2 in [-0.8, 0.8]:
		for lz in [-0.8, 0.8]:
			k.cyl(t + Vector3(lx2, 0.4, lz), t + Vector3(lx2 * 0.7, 3.6, lz * 0.7), 0.08, Color("#6b5a48"), 6)
	k.cyl(t + Vector3(0, 3.6, 0), t + Vector3(0, 5.6, 0), 1.35, Color("#7a5f45"), 16, HubMeshKit.PLANK)
	k.cyl(t + Vector3(0, 5.6, 0), t + Vector3(0, 6.3, 0), 1.45, Color("#4a3a2c"), 16, HubMeshKit.PLAIN, true, true, 0.05)
	# AC fans, the old trunk's lid and straps, the chalk practice ring
	for ac in [Vector3(43.8, 1.12, -30.9), Vector3(51.0, 1.12, -24.9)]:
		k.cyl(ac, ac + Vector3(0, 0.04, 0), 0.4, INK, 12)
	k.box(Vector3(54.9, 0.66, -35.1), Vector3(1.02, 0.12, 0.62), Color("#4a2c1d"))
	disc(k, Vector3(46.0, 0.008, -29.0), 0.06, CANVAS)
	annulus(k, Vector3(46.0, 0.008, -29.0), 2.6, 2.7, CANVAS, 40)
	label("ROOFTOP PRACTICE", Vector3(46.0, 0.02, -26.0), 0.0, 40, CANVAS, F_COND, true)


# ---- Pier, crawlspace, surroundings ------------------------------------------------------------

func _pier() -> void:
	var k := v.kit("pier")
	for x in range(20, 29, 2):
		for z in [-44.2, -39.8]:
			k.cyl(Vector3(float(x), -2.0, z), Vector3(float(x), 1.1, z), 0.18, Color("#4a3a2c"), 8)
	k.box(Vector3(24.0, -0.15, -42.0), Vector3(8.2, 0.3, 4.2), Color("#5a4636"), HubMeshKit.PLANK)
	for xs in [20.4, 20.8]:
		k.box(Vector3(xs, 1.4, -40.1), Vector3(0.06, 2.8, 0.06), STEEL)
	k.cyl(Vector3(27.4, 0, -40.4), Vector3(27.4, 2.2, -40.4), 0.07, Color("#4a3a2c"), 6)
	neon_box(Vector3(27.4, 2.3, -40.4), Vector3(0.18, 0.24, 0.18), Color("#ffcf85"), 3.0)
	v.omni(Vector3(27.4, 2.1, -40.6), Color("#ffcf85"), 1.8, 7.0, true).set_meta("wants_shadow", true)
	k.cyl(Vector3(26.3, 0.0, -42.9), Vector3(25.4, 2.2, -41.6), 0.02, Color("#6a5236"), 4)
	k.cyl(Vector3(26.6, 0.0, -42.6), Vector3(26.6, 0.4, -42.6), 0.2, STEEL_L, 10)
	label("THE PIER", Vector3(24.0, 0.03, -40.6), 0.0, 60, CANVAS, F_COND, true)


func _crawlspace() -> void:
	var k := v.kit("crawlspace")
	k.box(Vector3(-15.2, 1.02, 4.9), Vector3(0.4, 0.04, 1.4), Color("#5e4a3a"), HubMeshKit.PLANK)
	for i in 4:
		k.box(Vector3(-13.0 - i * 0.7, 1.9, 4.9), Vector3(0.1, 0.1, 1.6), Color("#3a2c22"))
	v.omni(Vector3(-14.0, 1.8, 4.9), Color("#ffcf85"), 0.9, 4.0)


func _surroundings() -> void:
	var k := v.kit("_yard")
	# a delivery truck and dumpsters out back, the harbor crane and a barge, a skyline far north
	k.box(Vector3(-4.0, 1.4, 21.0), Vector3(2.4, 2.8, 6.0), Color("#d8d2bd"))
	k.box(Vector3(-4.0, 1.1, 17.2), Vector3(2.3, 2.2, 1.8), Color("#8c3b2b"))
	for wz in [16.8, 20.0, 23.0]:
		for wx in [-5.25, -2.75]:
			k.cyl(Vector3(wx, 0.42, wz), Vector3(wx + signf(wx + 4.0) * 0.1, 0.42, wz), 0.42, INK, 10)
	k.box(Vector3(8.0, 0.7, 18.0), Vector3(2.0, 1.4, 1.2), Color("#3e6b4f"), HubMeshKit.CORRUGATED)
	k.box(Vector3(14.0, 4.0, -30.0), Vector3(1.2, 8.0, 1.2), Color("#e0a21c"))
	k.box(Vector3(10.0, 8.2, -30.0), Vector3(12.0, 0.8, 0.8), Color("#e0a21c"))
	k.box(Vector3(-14.0, 0.6, -34.0), Vector3(16.0, 1.6, 5.0), Color("#5a4636"))
	for i in 8:
		var h := 12.0 + float((i * 37) % 11)
		k.box(Vector3(-50.0 + i * 13.0, h * 0.5 - 1.0, -75.0), Vector3(10.0, h, 6.0), Color("#2b2f3a").lightened(0.04 * (i % 3)))
