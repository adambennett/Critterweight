class_name HubUpgradeProps
extends Node3D
## Every Cannery upgrade is visible in the world (HUB.md §4): bags appear, bikes line up, the ice
## bath gains a lid, the Office gets a second filing cabinet, the Loading Dock gets a sound system...
## At 12+ owned upgrades the Main Floor's dead fluorescents are replaced with working ones; with all
## 24 the Glandco banner over the practice cage becomes one with the player's fighter on it.
## Purely visual: reads levels from HubState (written by FightCamp.buy_upgrade via HubServices).

const LIGHTS_FIXED_AT := 12
const ALL_UPGRADES := ["meta_heavy_bag", "meta_speed_bag", "meta_squat_rack", "meta_cardio_bikes", "meta_grappling_dummy", "meta_mat_room",
	"meta_ice_bath", "meta_cut_corner", "meta_sutures", "meta_juice_bar_tab", "meta_needles_connect", "meta_label_reader", "meta_antidote_stash",
	"meta_sponsorship", "meta_scouting_report", "meta_reroll_token", "meta_cornermans_eye", "meta_film_room", "meta_title_contender",
	"meta_crowd_connection", "meta_walkout", "meta_second_skin", "meta_bookies_favor", "meta_boiler_room_key"]

var v: HubView
var state: HubState
var nodes := {}                    ## "<id>:<level>" -> Node3D (shown when the owned level >= level)
var player_banner: Node3D
var _built_fighter := ""


func build(view: HubView) -> void:
	v = view
	state = view.state
	name = "HubUpgrades"
	_gym()
	_med_bay()
	_juice_bar()
	_office()
	_dock()
	_boiler()
	refresh()


func _node(id: String, level: int, k: HubMeshKit) -> Node3D:
	var n := Node3D.new()
	n.name = "%s_%d" % [id, level]
	n.add_child(k.commit("Mesh", v.surface_mat))
	add_child(n)
	nodes["%s:%d" % [id, level]] = n
	return n


## Which visuals are shown, the fluorescents, the banner. Call after any purchase.
func refresh() -> void:
	for key in nodes:
		var parts := str(key).split(":")
		(nodes[key] as Node3D).visible = state.upgrade_level(parts[0]) >= int(parts[1])
	var owned := owned_count()
	var fixed := owned >= LIGHTS_FIXED_AT
	var dress := v.dressing
	if dress:
		for i in dress.fluorescents.size():
			var tube: MeshInstance3D = dress.fluorescents[i]
			if fixed:
				tube.set_instance_shader_parameter("lit", 1.0)
				tube.set_instance_shader_parameter("flicker", 0.0)
			else:
				tube.set_instance_shader_parameter("lit", 0.0 if i in [1, 4] else 1.0)
				tube.set_instance_shader_parameter("flicker", 0.8 if i in [2, 5] else 0.0)
		for l in v.interior_lights:
			if l.has_meta("gym"):
				v._light_base[l] = 1.7 if fixed else 1.1
		v.apply_time_of_day(v.tod)
		var all := owned >= ALL_UPGRADES.size()
		if dress.cage_banner:
			dress.cage_banner.visible = not all
		_player_banner(all)
	v.surface_mat.set_shader_parameter("wear", 0.45 if fixed else 1.0)


func owned_count() -> int:
	var n := 0
	for id in ALL_UPGRADES:
		if state.upgrade_level(id) > 0:
			n += 1
	return n


func lights_fixed() -> bool:
	return owned_count() >= LIGHTS_FIXED_AT


func _player_banner(want: bool) -> void:
	var fid := state.loadout_fighter()
	if want and player_banner and _built_fighter == fid:
		player_banner.visible = true
		return
	if player_banner:
		player_banner.queue_free()
		player_banner = null
	if not want:
		return
	_built_fighter = fid
	var d := Content.get_entry("creatures", fid)
	var pal: Dictionary = d.get("art", {}).get("palette", {})
	var prim := Color.from_string(str(pal.get("primary", "#c9a227")), Color("#c9a227"))
	var sec := Color.from_string(str(pal.get("secondary", "#2b2f3a")), Color("#2b2f3a"))
	player_banner = Node3D.new()
	player_banner.name = "PlayerBanner"
	add_child(player_banner)
	var c := HubLayout.CAGE_CENTER
	player_banner.position = Vector3(4.3, 5.0, -7.74)
	var k := HubMeshKit.new()
	k.box(Vector3.ZERO, Vector3(4.2, 1.5, 0.05), sec)
	k.box(Vector3(0, 0, 0.03), Vector3(3.9, 1.25, 0.01), prim.darkened(0.2), HubMeshKit.PAINT)
	k.sphere(Vector3(-1.4, 0.05, 0.05), 0.42, prim, 5, 10, HubMeshKit.PLAIN, true, Vector3(1, 1, 0.2))
	k.cyl(Vector3(-2.2, 0.78, 0), Vector3(2.2, 0.78, 0), 0.04, Color("#5b6168"), 6)
	player_banner.add_child(k.commit("Banner", v.surface_mat))
	var l := Label3D.new()
	l.text = str(d.get("name", "CHAMP")).to_upper()
	l.font = load(HubDressing.F_BUNGEE)
	l.font_size = 100
	l.pixel_size = 0.006
	l.modulate = Color("#f2f2ec")
	l.position = Vector3(0.6, 0.12, 0.05)
	player_banner.add_child(l)
	var l2 := Label3D.new()
	l2.text = "%s  ·  THE CANNERY'S OWN" % str(state.profile.get("name", "")).to_upper()
	l2.font = load(HubDressing.F_COND)
	l2.font_size = 38
	l2.pixel_size = 0.006
	l2.modulate = Color("#c9a227")
	l2.position = Vector3(0.6, -0.45, 0.05)
	player_banner.add_child(l2)


func update(_dt: float) -> void:
	pass


# ---- Gym Floor -------------------------------------------------------------------------------

func _gym() -> void:
	var steel := Color("#5b6168")
	# Heavy Bag: up to three more bags on a frame near the north wall
	for lv in range(1, 4):
		var k := HubMeshKit.new()
		var x := -8.4 + lv * 1.3
		k.box(Vector3(x, 2.4, -6.75), Vector3(0.12, 0.12, 0.9), steel)
		k.box(Vector3(x, 1.2, -7.15), Vector3(0.1, 2.4, 0.1), steel)
		k.cyl(Vector3(x, 0.55, -6.45), Vector3(x, 1.85, -6.45), 0.3, [Color("#3a3a42"), Color("#8c3b2b"), Color("#355d7f")][lv - 1], 14)
		k.cyl(Vector3(x, 1.85, -6.45), Vector3(x, 2.4, -6.45), 0.015, Color("#9fa6ad"), 4)
		_node("meta_heavy_bag", lv, k)
	# Speed Bag: wall platforms with teardrop bags
	for lv2 in range(1, 4):
		var k2 := HubMeshKit.new()
		var z := -0.9 + (lv2 - 1) * 0.55
		k2.box(Vector3(-11.6, 2.1, z), Vector3(0.5, 0.06, 0.5), Color("#6a5236"), HubMeshKit.PLANK)
		k2.box(Vector3(-11.8, 1.95, z), Vector3(0.1, 0.3, 0.1), steel)
		k2.sphere(Vector3(-11.55, 1.88, z), 0.12, Color("#d9532b"), 4, 8, HubMeshKit.PLAIN, true, Vector3(1, 1.3, 1))
		_node("meta_speed_bag", lv2, k2)
	# Squat Rack: the rack, then more plates
	for lv3 in range(1, 4):
		var k3 := HubMeshKit.new()
		var rp := Vector3(-4.8, 0, 4.7)
		if lv3 == 1:
			for xo in [-0.6, 0.6]:
				k3.box(rp + Vector3(xo, 1.0, 0), Vector3(0.08, 2.0, 0.08), steel)
			k3.box(rp + Vector3(0, 2.0, 0), Vector3(1.3, 0.08, 0.08), steel)
			k3.box(rp + Vector3(0, 0.02, 0), Vector3(1.6, 0.04, 1.0), Color("#2b2f3a"), HubMeshKit.PLAIN, false)
			k3.cyl(rp + Vector3(-0.95, 1.45, 0), rp + Vector3(0.95, 1.45, 0), 0.025, Color("#9fa6ad"), 6)
		for side in [-1.0, 1.0]:
			var px: float = side * (0.7 + lv3 * 0.06)
			k3.cyl(rp + Vector3(px - 0.03, 1.45, 0), rp + Vector3(px + 0.03, 1.45, 0), 0.22 - lv3 * 0.03, Color("#2b2f3a").lightened(0.1 * lv3), 12)
		_node("meta_squat_rack", lv3, k3)
	# Cardio Bikes: two, then four
	for lv4 in range(1, 3):
		var k4 := HubMeshKit.new()
		for j in 2:
			var bx := -3.6 + ((lv4 - 1) * 2 + j) * 1.2
			var bp := Vector3(bx, 0, 3.0)
			k4.box(bp + Vector3(0, 0.05, 0), Vector3(0.4, 0.1, 1.0), Color("#2b2f3a"))
			k4.cyl(bp + Vector3(0, 0.1, 0.3), bp + Vector3(0, 0.75, 0.05), 0.04, Color("#9fa6ad"), 6)
			k4.box(bp + Vector3(0, 0.8, 0.05), Vector3(0.2, 0.06, 0.32), Color("#2b2f3a"))
			k4.cyl(bp + Vector3(0, 0.1, -0.35), bp + Vector3(0, 1.05, -0.45), 0.04, Color("#9fa6ad"), 6)
			k4.box(bp + Vector3(0, 1.05, -0.45), Vector3(0.5, 0.05, 0.08), Color("#8bd426"))
			k4.cyl(bp + Vector3(-0.06, 0.45, -0.2), bp + Vector3(0.06, 0.45, -0.2), 0.24, Color("#c23a2b"), 14)
		_node("meta_cardio_bikes", lv4, k4)
	# Grappling Dummy
	for lv5 in range(1, 3):
		var k5 := HubMeshKit.new()
		var dp := Vector3(-5.6, 0, 2.5 + (lv5 - 1) * 1.4)
		k5.cyl(dp + Vector3(0, 0.0, 0), dp + Vector3(0, 0.9, 0), 0.22, Color("#6b5a48"), 10)
		k5.cyl(dp + Vector3(0, 0.9, 0), dp + Vector3(0, 1.45, 0), 0.26, Color("#6b5a48"), 10)
		k5.sphere(dp + Vector3(0, 1.62, 0), 0.16, Color("#6b5a48"), 4, 8)
		k5.cyl(dp + Vector3(-0.55, 1.3, 0.05), dp + Vector3(0.55, 1.3, 0.05), 0.07, Color("#5a4636"), 8)
		_node("meta_grappling_dummy", lv5, k5)
	# Mat Room: a second mat zone and its sign
	var k6 := HubMeshKit.new()
	k6.floor_rect(Rect2(4.0, 2.9, 4.0, 2.3), 0.014, Color("#355d7f"), HubMeshKit.MAT)
	var sz := HubLayout.STAIRS_Z - HubLayout.STAIRS_W * 0.5 - 0.2
	k6.box(Vector3(6.0, 1.6, sz), Vector3(1.6, 0.4, 0.05), Color("#2b2f3a"))
	var n6 := _node("meta_mat_room", 1, k6)
	_sign(n6, "MAT ROOM", Vector3(6.0, 1.6, sz - 0.03), PI, Color("#e8e6dc"))


func _sign(parent: Node3D, text: String, pos: Vector3, rot_y: float, col: Color, px := 36) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = load(HubDressing.F_COND)
	l.font_size = px
	l.pixel_size = 0.004
	l.modulate = col
	l.position = pos
	l.rotation = Vector3(0, rot_y, 0)
	l.shaded = true
	parent.add_child(l)
	return l


# ---- Med Bay -------------------------------------------------------------------------------------

func _med_bay() -> void:
	# Ice Bath: the dumpster gains a lid (propped open), then a thermometer and an ice machine
	var k := HubMeshKit.new()
	k.box(Vector3(17.0, 1.75, -0.62), Vector3(3.2, 1.5, 0.08), Color("#3e6b4f"), HubMeshKit.CORRUGATED, true, Basis(Vector3.RIGHT, -0.12))
	_node("meta_ice_bath", 1, k)
	var k2 := HubMeshKit.new()
	k2.box(Vector3(19.5, 0.9, -1.2), Vector3(0.7, 1.8, 0.8), Color("#cfe3ea"))
	k2.box(Vector3(19.14, 1.2, -1.2), Vector3(0.02, 0.5, 0.5), Color("#8bd426"), HubMeshKit.PAINT)
	_node("meta_ice_bath", 2, k2)
	# Cut Corner: stool, bucket, towel, the cut-woman's kit
	var k3 := HubMeshKit.new()
	k3.cyl(Vector3(13.3, 0, -1.1), Vector3(13.3, 0.55, -1.1), 0.2, Color("#c23a2b"), 10)
	k3.cyl(Vector3(13.9, 0, -0.9), Vector3(13.9, 0.4, -0.9), 0.17, Color("#9fa6ad"), 10, HubMeshKit.PLAIN, true, true, 0.2)
	k3.box(Vector3(13.3, 0.6, -1.1), Vector3(0.4, 0.05, 0.4), Color("#e8e6dc"))
	_node("meta_cut_corner", 1, k3)
	# Sutures: a tray on the exam table, then a whole rig
	var k4 := HubMeshKit.new()
	k4.box(Vector3(17.2, 0.98, -5.5), Vector3(0.5, 0.04, 0.35), Color("#9fa6ad"))
	k4.cyl(Vector3(17.1, 1.0, -5.5), Vector3(17.3, 1.0, -5.5), 0.02, Color("#35c1c9"), 6)
	_node("meta_sutures", 1, k4)
	var k5 := HubMeshKit.new()
	k5.box(Vector3(15.2, 0.6, -7.6), Vector3(0.8, 1.2, 0.5), Color("#cfe3ea"))
	k5.cyl(Vector3(15.2, 1.2, -7.6), Vector3(15.2, 1.7, -7.45), 0.03, Color("#9fa6ad"), 6)
	_node("meta_sutures", 2, k5)


# ---- Juice Bar ------------------------------------------------------------------------------------

func _juice_bar() -> void:
	var k := HubMeshKit.new()
	k.box(Vector3(-15.0, 2.0, -7.83), Vector3(1.4, 1.0, 0.04), Color("#22261f"))
	var n := _node("meta_juice_bar_tab", 1, k)
	_sign(n, "HOUSE TAB", Vector3(-15.0, 2.3, -7.8), 0.0, Color("#8bd426"))
	_sign(n, "-8% for regulars", Vector3(-15.0, 1.95, -7.8), 0.0, Color("#e8e6dc"), 26)
	var k1 := HubMeshKit.new()
	k1.box(Vector3(-13.6, 2.0, -7.83), Vector3(1.0, 1.0, 0.04), Color("#22261f"))
	var n1 := _node("meta_juice_bar_tab", 2, k1)
	_sign(n1, "-16%", Vector3(-13.6, 2.0, -7.8), 0.0, Color("#ffc43d"), 44)
	var k2 := HubMeshKit.new()
	k2.box(Vector3(-19.9, 0.3, -0.9), Vector3(0.6, 0.6, 0.6), Color("#2b2f3a"), HubMeshKit.PLANK)
	var n2 := _node("meta_needles_connect", 1, k2)
	_sign(n2, "DO NOT OPEN", Vector3(-19.59, 0.35, -0.9), PI * 0.5, Color("#ff5a5a"), 24)
	var k3 := HubMeshKit.new()
	k3.cyl(Vector3(-19.8, 1.12, -6.6), Vector3(-19.8, 1.3, -6.5), 0.015, Color("#c9a227"), 6)
	k3.cyl(Vector3(-19.8, 1.33, -6.48), Vector3(-19.8, 1.36, -6.46), 0.09, Color("#cfe3ea"), 12)
	_node("meta_label_reader", 1, k3)
	var k4 := HubMeshKit.new()
	k4.cyl(Vector3(-19.8, 1.12, -5.0), Vector3(-19.8, 1.4, -5.0), 0.11, Color("#cfe3ea"), 12)
	k4.cyl(Vector3(-19.8, 1.4, -5.0), Vector3(-19.8, 1.45, -5.0), 0.12, Color("#c23a2b"), 12)
	for i in 6:
		k4.sphere(Vector3(-19.8 + (i % 2) * 0.05 - 0.025, 1.17 + floorf(i / 2.0) * 0.06, -5.0 + ((i + 1) % 3) * 0.04 - 0.04), 0.03, Color("#8bd426"), 3, 5)
	_node("meta_antidote_stash", 1, k4)


# ---- Office ----------------------------------------------------------------------------------------

func _office() -> void:
	var y := 4.0
	var spons := [["GLANDCO", Color("#2f6b1f")], ["KRILL KOLA", Color("#8c3b2b")], ["DOCKSIDE INSURANCE", Color("#355d7f")]]
	for lv in range(1, 4):
		var k := HubMeshKit.new()
		var z := 9.0 + (lv - 1) * 1.5
		k.box(Vector3(13.83, y + 1.9, z), Vector3(0.04, 1.0, 1.2), spons[lv - 1][1])
		var n := _node("meta_sponsorship", lv, k)
		_sign(n, str(spons[lv - 1][0]), Vector3(13.8, y + 2.0, z), -PI * 0.5, Color("#f2f2ec"), 32)
		_sign(n, "OFFICIAL SPONSOR", Vector3(13.8, y + 1.7, z), -PI * 0.5, Color("#c9a227"), 22)
	var k2 := HubMeshKit.new()
	k2.box(Vector3(6.45, y + 0.7, 10.1), Vector3(0.6, 1.4, 0.7), Color("#6b7177"))
	for d in 3:
		k2.box(Vector3(6.77, y + 0.3 + d * 0.42, 10.1), Vector3(0.02, 0.02, 0.5), Color("#23262e"))
	var n2 := _node("meta_scouting_report", 1, k2)
	_sign(n2, "SCOUTING", Vector3(6.77, y + 1.25, 10.1), PI * 0.5, Color("#c9a227"), 26)
	for lv3 in range(1, 3):
		var k3 := HubMeshKit.new()
		for t in lv3 * 3:
			k3.cyl(Vector3(10.6 + (t % 3) * 0.08, y + 0.8 + floorf(t / 3.0) * 0.012, 11.7 + floorf(t / 3.0) * 0.06), Vector3(10.6 + (t % 3) * 0.08, y + 0.812 + floorf(t / 3.0) * 0.012, 11.7 + floorf(t / 3.0) * 0.06), 0.035, Color("#c9a227"), 8)
		_node("meta_reroll_token", lv3, k3)
	var k4 := HubMeshKit.new()
	k4.cyl(Vector3(13.2, y, 9.0), Vector3(13.2, y + 1.1, 9.0), 0.04, Color("#2b2f3a"), 6)
	k4.box(Vector3(13.2, y + 1.4, 9.0), Vector3(0.12, 0.55, 0.85), Color("#23262e"), HubMeshKit.PLAIN, true, Basis(Vector3.UP, 0.6))
	var n4 := _node("meta_cornermans_eye", 1, k4)
	var scr := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.01, 0.42, 0.72)
	scr.mesh = sm
	scr.material_override = v.dressing.neon_mat(Color("#35c1c9"), 1.6) if v.dressing else null
	scr.position = Vector3(13.13, y + 1.4, 9.04)
	scr.rotation = Vector3(0, 0.6, 0)
	n4.add_child(scr)
	var k5 := HubMeshKit.new()
	k5.box(Vector3(13.84, y + 1.9, 12.6), Vector3(0.02, 1.4, 1.9), Color("#e9e2cf"))
	k5.box(Vector3(10.0, y + 2.7, 9.4), Vector3(0.3, 0.2, 0.4), Color("#2b2f3a"))
	var n5 := _node("meta_film_room", 1, k5)
	_sign(n5, "FILM ROOM", Vector3(13.82, y + 2.7, 12.6), -PI * 0.5, Color("#23262e"), 30)
	var k6 := HubMeshKit.new()
	k6.box(Vector3(11.8, y + 1.7, 13.84), Vector3(1.6, 0.9, 0.04), Color("#3a2c22"), HubMeshKit.PLANK)
	k6.cyl(Vector3(11.2, y + 1.7, 13.8), Vector3(12.4, y + 1.7, 13.8), 0.07, Color("#3a2a1a"), 10)
	k6.cyl(Vector3(11.8, y + 1.7, 13.78), Vector3(11.8, y + 1.7, 13.76), 0.2, Color("#c9a227"), 14)
	var n6 := _node("meta_title_contender", 1, k6)
	_sign(n6, "TITLE CONTENDER", Vector3(11.8, y + 2.25, 13.8), PI, Color("#c9a227"), 28)


# ---- Loading Dock ----------------------------------------------------------------------------------

func _dock() -> void:
	# Crowd Connection: string lights, then a fan barricade with banners
	var k := HubMeshKit.new()
	for i in 4:
		k.cyl(Vector3(-9.5 + i * 6.3, 3.6, -8.4), Vector3(-6.0 + i * 5.0, 3.2, -16.0), 0.01, Color("#23262e"), 3)
	var n := _node("meta_crowd_connection", 1, k)
	if v.dressing:
		for i2 in 16:
			var t := float(i2) / 15.0
			var bulb := MeshInstance3D.new()
			var bm := SphereMesh.new()
			bm.radius = 0.06
			bm.height = 0.12
			bulb.mesh = bm
			bulb.material_override = v.dressing.neon_mat([Color("#ffc43d"), Color("#ff5a5a"), Color("#8bd426"), Color("#35c1c9")][i2 % 4], 2.6)
			bulb.position = Vector3(lerpf(-9.5, 9.0, t), 3.4 - sin(t * PI * 4.0) * 0.2, lerpf(-8.6, -12.0, absf(sin(t * PI * 2.0))))
			n.add_child(bulb)
	var k2 := HubMeshKit.new()
	for j in 5:
		k2.box(Vector3(-6.0 + j * 1.25, 0.55, -18.0), Vector3(1.1, 1.1, 0.08), Color("#9fa6ad"), HubMeshKit.PLAIN)
	k2.box(Vector3(-3.5, 1.3, -18.04), Vector3(4.8, 0.45, 0.04), Color("#8bd426"))
	var n2 := _node("meta_crowd_connection", 2, k2)
	_sign(n2, "CANNERY CREW", Vector3(-3.5, 1.3, -18.08), PI, Color("#1a1d24"), 40)
	# Walkout Music: the sound system flanking the roller door (and the walkout track plays)
	var k3 := HubMeshKit.new()
	for x in [-3.0, 3.0]:
		k3.box(Vector3(x, 0.8, -8.75), Vector3(0.9, 1.6, 0.7), Color("#1a1d24"))
		k3.cyl(Vector3(x, 1.15, -9.11), Vector3(x, 1.15, -9.12), 0.3, Color("#5b6168"), 14)
		k3.cyl(Vector3(x, 0.45, -9.11), Vector3(x, 0.45, -9.12), 0.2, Color("#5b6168"), 14)
		k3.box(Vector3(x, 1.75, -8.75), Vector3(0.7, 0.3, 0.5), Color("#2b2f3a"))
	_node("meta_walkout", 1, k3)
	# Second Skin: a tailor's dummy in a ring jacket at the workbench
	var k4 := HubMeshKit.new()
	k4.cyl(Vector3(-9.3, 0.0, -16.4), Vector3(-9.3, 0.9, -16.4), 0.03, Color("#5b6168"), 6)
	k4.cyl(Vector3(-9.3, 0.9, -16.4), Vector3(-9.3, 1.55, -16.4), 0.24, Color("#8c3b2b"), 12, HubMeshKit.PLAIN, true, true, 0.3)
	k4.box(Vector3(-9.3, 1.25, -16.15), Vector3(0.1, 0.3, 0.02), Color("#c9a227"))
	_node("meta_second_skin", 1, k4)


# ---- Boiler Room -----------------------------------------------------------------------------------

func _boiler() -> void:
	var k := HubMeshKit.new()
	k.box(Vector3(46.5, 2.2, -4.84), Vector3(1.6, 1.0, 0.04), Color("#2f5b3a"))
	var n := _node("meta_bookies_favor", 1, k)
	_sign(n, "TODAY'S ODDS", Vector3(46.5, 2.45, -4.8), 0.0, Color("#ffc43d"), 30)
	_sign(n, "THE BIRD: 40-1", Vector3(46.5, 2.1, -4.8), 0.0, Color("#e8e6dc"), 26)
	var k2 := HubMeshKit.new()
	k2.box(Vector3(53.85, 1.8, 2.3), Vector3(0.04, 0.06, 0.2), Color("#5b6168"))
	k2.box(Vector3(53.8, 1.66, 2.3), Vector3(0.02, 0.2, 0.08), Color("#c9a227"))
	var n2 := _node("meta_boiler_room_key", 1, k2)
	_sign(n2, "ACCESS GRANTED", Vector3(52.94, 1.25, 3.4), -PI * 0.5, Color("#3fc27a"), 24)
