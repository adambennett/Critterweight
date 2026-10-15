class_name HubAmbient
extends Node3D
## Ambient life (HUB.md §2/§6, view only): two dock gulls that steal from the chum cannon (and
## sit on the pier ladder until a big splash scares them off), the referee goat on a smoke break by
## the roller door, three crowd regulars in the practice-cage bleachers who react to what you do,
## the sleeping Scrapling under the stairs (secret #3: it runs for the dock when woken) and the
## frozen Blister pet that follows you once found (secret #10). Time of day changes who is around.

var v: HubView
var mode: HubMode
var gulls: Array[Node3D] = []
var _gull_state := []              ## per gull: {home, t, mode}
var goat: Node3D
var _smoke: MeshInstance3D
var regulars: Array[Node3D] = []
var _cheer := 0.0
var scrapling: Node3D
var _zzz: Label3D
var pet: Node3D
var _pet_pos := Vector3.ZERO
var _t := 0.0
var _scared_t := -1.0


func build(view: HubView) -> void:
	v = view
	mode = view.mode
	name = "HubAmbient"
	for i in 2:
		gulls.append(_gull())
		_gull_state.append({"home": HubLayout.PIER_LADDER + Vector3(-0.25 + i * 0.5, 0.75, 0.0), "t": float(i) * 1.7, "fly": 0.0})
	goat = _goat()
	goat.position = Vector3(3.4, 0, -9.2)
	goat.rotation.y = -2.4
	var fan_paths := ["res://assets/models/crowd/fan_a.glb", "res://assets/models/crowd/fan_b.glb"]
	for j in 3:
		var fp := str(fan_paths[j % 2])
		var f := _model(fp, Color.from_string(["#e04fb0", "#ffc43d", "#35c1c9"][j], Color.WHITE))
		f.position = Vector3(9.0 + j * 0.9, 0.45 + j * 0.45, 0.4 + j * 0.8)
		f.rotation.y = -PI * 0.5 - 0.3
		f.scale = Vector3.ONE * 1.05
		regulars.append(f)
	scrapling = _model("res://assets/models/creatures/npc_scrapling.glb", Color.WHITE)
	_zzz = Label3D.new()
	_zzz.text = "z Z z"
	_zzz.font = load(HubDressing.F_COND)
	_zzz.font_size = 48
	_zzz.pixel_size = 0.005
	_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_zzz.modulate = Color("#e8e6dc")
	_zzz.position = Vector3(0, 0.9, 0)
	scrapling.add_child(_zzz)
	pet = _model("res://assets/models/creatures/npc_blister.glb", Color("#bfe9ff"))
	pet.scale = Vector3.ONE * 0.75
	pet.visible = false
	on_time_of_day(v.tod)


func _model(path: String, tint: Color) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	if not ResourceLoader.exists(path):
		return holder
	var ps: PackedScene = load(path)
	var inst := ps.instantiate()
	holder.add_child(inst)
	_restyle(inst, tint)
	return holder


func _restyle(n: Node, tint: Color) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		if mi.name == "gore_piece":
			mi.visible = false
			return
		for si in mi.mesh.get_surface_count():
			var m := Materials.creature_material()
			m.set_shader_parameter("tint", tint)
			m.next_pass = Materials.outline_material(0.01)
			mi.set_surface_override_material(si, m)
	for c in n.get_children():
		_restyle(c, tint)


func _gull() -> Node3D:
	var k := HubMeshKit.new()
	k.sphere(Vector3(0, 0.18, 0), 0.16, Color("#f2f2ec"), 4, 8, HubMeshKit.PLAIN, true, Vector3(0.8, 0.8, 1.3))
	k.sphere(Vector3(0, 0.33, 0.16), 0.09, Color("#f2f2ec"), 4, 8)
	k.cyl(Vector3(0, 0.32, 0.24), Vector3(0, 0.3, 0.36), 0.025, Color("#ffc43d"), 6, HubMeshKit.PLAIN, true, true, 0.005)
	k.box(Vector3(0.12, 0.22, -0.02), Vector3(0.04, 0.1, 0.3), Color("#9fa6ad"))
	k.box(Vector3(-0.12, 0.22, -0.02), Vector3(0.04, 0.1, 0.3), Color("#9fa6ad"))
	k.cyl(Vector3(0.04, 0.0, 0), Vector3(0.04, 0.08, 0), 0.01, Color("#ffc43d"), 4)
	k.cyl(Vector3(-0.04, 0.0, 0), Vector3(-0.04, 0.08, 0), 0.01, Color("#ffc43d"), 4)
	var n := Node3D.new()
	n.add_child(k.commit("Gull", v.surface_mat))
	add_child(n)
	return n


func _goat() -> Node3D:
	var k := HubMeshKit.new()
	k.cyl(Vector3(0.1, 0, 0), Vector3(0.1, 0.55, 0), 0.07, Color("#23262e"), 6)
	k.cyl(Vector3(-0.1, 0, 0), Vector3(-0.1, 0.55, 0), 0.07, Color("#23262e"), 6)
	k.cyl(Vector3(0, 0.55, 0), Vector3(0, 1.15, 0), 0.24, Color("#f2f2ec"), 10)
	for s in 4:
		k.cyl(Vector3(0, 0.62 + s * 0.15, 0), Vector3(0, 0.68 + s * 0.15, 0), 0.245, Color("#23262e"), 10)
	k.sphere(Vector3(0, 1.36, 0.06), 0.17, Color("#d8d2bd"), 4, 8, HubMeshKit.PLAIN, true, Vector3(0.85, 1.0, 1.25))
	k.cyl(Vector3(0.08, 1.5, 0.0), Vector3(0.16, 1.66, -0.12), 0.03, Color("#6b5a48"), 5, HubMeshKit.PLAIN, true, true, 0.01)
	k.cyl(Vector3(-0.08, 1.5, 0.0), Vector3(-0.16, 1.66, -0.12), 0.03, Color("#6b5a48"), 5, HubMeshKit.PLAIN, true, true, 0.01)
	k.cyl(Vector3(0, 1.2, 0.22), Vector3(0, 1.08, 0.26), 0.035, Color("#d8d2bd"), 5, HubMeshKit.PLAIN, true, true, 0.01)
	k.sphere(Vector3(0.06, 1.4, 0.2), 0.025, Color("#23262e"), 3, 5)
	k.sphere(Vector3(-0.06, 1.4, 0.2), 0.025, Color("#23262e"), 3, 5)
	k.cyl(Vector3(0.18, 0.95, 0.08), Vector3(0.3, 1.25, 0.2), 0.04, Color("#d8d2bd"), 5)
	k.cyl(Vector3(0.05, 1.3, 0.24), Vector3(0.12, 1.3, 0.34), 0.008, Color("#f2f2ec"), 4)
	var n := Node3D.new()
	n.name = "RefereeGoat"
	n.add_child(k.commit("Goat", v.surface_mat))
	add_child(n)
	_smoke = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	_smoke.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.88, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke.material_override = mat
	n.add_child(_smoke)
	if v.dressing:
		var tip := MeshInstance3D.new()
		var tm := SphereMesh.new()
		tm.radius = 0.012
		tm.height = 0.024
		tip.mesh = tm
		tip.material_override = v.dressing.neon_mat(Color("#ff6b2b"), 4.0)
		tip.position = Vector3(0.12, 1.3, 0.34)
		n.add_child(tip)
	return n


## Time of day: who is around (gulls sleep at night, the regulars come in the evening).
func on_time_of_day(tod: String) -> void:
	for i in regulars.size():
		regulars[i].visible = tod != "morning" or i == 0
	goat.visible = tod != "night"


func cheer(amount := 1.0) -> void:
	_cheer = maxf(_cheer, amount)


func scare_gulls() -> void:
	_scared_t = _t


func update(dt: float, player_pos: Vector3) -> void:
	_t += dt
	_update_gulls(dt)
	# the goat smokes
	var sp := fmod(_t, 2.6) / 2.6
	_smoke.position = Vector3(0.14, 1.36 + sp * 0.6, 0.38 + sp * 0.1)
	_smoke.scale = Vector3.ONE * (0.5 + sp * 2.0)
	goat.position.y = absf(sin(_t * 0.8)) * 0.01
	# regulars bounce when something good happens
	_cheer = maxf(0.0, _cheer - dt * 0.5)
	for i in regulars.size():
		var r := regulars[i]
		r.position.y = (0.45 + i * 0.45) + absf(sin(_t * 9.0 + i)) * 0.25 * _cheer + sin(_t * 1.3 + i) * 0.01
		var to := player_pos - r.global_position
		r.rotation.y = lerp_angle(r.rotation.y, atan2(to.x, to.z), clampf(dt * 1.5, 0.0, 1.0))
	_update_scrapling(dt)
	_update_pet(dt, player_pos)


func _update_gulls(dt: float) -> void:
	var revealed := mode.secrets.pier_revealed()
	var night := v.tod == "night"
	for i in gulls.size():
		var g := gulls[i]
		var st: Dictionary = _gull_state[i]
		st["t"] = float(st["t"]) + dt
		if revealed:
			# scared off: fly up and away, then perch on the far container
			var since := _t - _scared_t if _scared_t >= 0.0 else 99.0
			var perch := Vector3(10.6, 2.62, -15.0 + i * 0.6)
			if since < 3.0:
				g.position = g.position.lerp(Vector3(g.position.x + 3.0, 6.0, g.position.z - 4.0), clampf(dt * 1.2, 0.0, 1.0))
			else:
				g.position = g.position.lerp(perch, clampf(dt * 0.8, 0.0, 1.0))
			g.rotation.z = sin(_t * 18.0) * (0.3 if since < 6.0 else 0.0)
			continue
		var home: Vector3 = st["home"]
		if night:
			g.position = home
			g.rotation = Vector3(0.2, PI * 0.5, 0)
			continue
		# hop over to the chum cannon now and then to steal, then back to the ladder
		var cycle := fmod(float(st["t"]), 14.0)
		var cannon := HubLayout.CANNON_POS + Vector3(-0.2 + i * 0.4, 1.4, 0.6)
		var target := home if cycle < 8.0 else cannon
		g.position = g.position.lerp(target, clampf(dt * 1.6, 0.0, 1.0))
		g.position.y += absf(sin(_t * 8.0 + i)) * 0.03
		var to := target - g.position
		if to.length() > 0.1:
			g.rotation.y = lerp_angle(g.rotation.y, atan2(to.x, to.z), clampf(dt * 5.0, 0.0, 1.0))
		g.rotation.x = sin(_t * 6.0 + i) * 0.15 if cycle >= 8.0 else 0.0


func _update_scrapling(dt: float) -> void:
	var st := mode.secrets.scrapling_state()
	match st:
		"asleep":
			scrapling.visible = true
			scrapling.position = Vector3(10.4, 0.25, 7.0)
			scrapling.rotation = Vector3(0, -0.6, PI * 0.5)
			_zzz.visible = true
			_zzz.position = Vector3(0, 0.9 + fmod(_t, 2.0) * 0.15, 0)
		"running":
			scrapling.visible = true
			_zzz.visible = false
			var p := mode.secrets.scrapling_pos()
			var prev := scrapling.position
			scrapling.position = Vector3(p.x, absf(sin(_t * 14.0)) * 0.12, p.z)
			var mv := scrapling.position - prev
			mv.y = 0.0
			if mv.length() > 0.001:
				scrapling.rotation = Vector3(0.2, atan2(mv.x, mv.z), 0)
		_:
			scrapling.visible = false


func _update_pet(dt: float, player_pos: Vector3) -> void:
	# follows you only while it is your pet (the locker's "None" clears the slot)
	var on := mode.state.has_cosmetic("hub_pet_blister") and mode.state.cosmetic_in("pet") == "hub_pet_blister"
	pet.visible = on
	if not on:
		_pet_pos = player_pos
		return
	var f := mode.player()
	var behind := player_pos - f.forward() * 1.1 + f.forward().cross(Vector3.UP) * 0.5
	behind.y = player_pos.y - f.rig.hover_height
	_pet_pos = _pet_pos.lerp(behind, clampf(dt * 2.2, 0.0, 1.0))
	pet.position = _pet_pos + Vector3.UP * absf(sin(_t * 5.0)) * 0.18
	var to := player_pos - pet.position
	pet.rotation.y = atan2(to.x, to.z)
