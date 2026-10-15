class_name ModeView
extends Node3D
## Draws bonus-mode objectives from MatchMode.view_state() (plain data, so local and networked
## matches render identically): the spotlight, the chum ball and goals, the Absolute Unit crown,
## Chum Rush gates, and downed-ally bleed/revive rings.

var head_of: Callable            ## (fighter_index) -> Vector3 world head position
var team_of: Callable            ## (fighter_index) -> int team
var _light: SpotLight3D
var _disc: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _ball: MeshInstance3D
var _ball_mat: StandardMaterial3D
var _goals: Array = []
var _crown: Node3D
var _gates: Array = []
var _downed: Dictionary = {}     ## fighter index -> Node3D
var _mode := ""
var _t := 0.0


func update_state(v: Dictionary, dt: float) -> void:
	_t += dt
	var m := str(v.get("mode", ""))
	if m != _mode:
		_build(m, v)
	match m:
		"spotlight_hog":
			_update_spotlight(v)
		"chumball":
			_update_ball(v)
		"absolute_unit":
			_update_unit(v)
		"chum_rush":
			_update_gates(v)
		"tutorial":
			_update_rings(v.get("rings", []))
	_update_downed(v.get("downed", []))


func _build(m: String, v: Dictionary) -> void:
	_mode = m
	for c in get_children():
		c.queue_free()
	_goals.clear()
	_gates.clear()
	_downed.clear()
	_light = null
	_beam = null
	_ball = null
	_crown = null
	match m:
		"spotlight_hog":
			_light = SpotLight3D.new()
			_light.spot_angle = 18.0
			_light.spot_range = 12.0
			_light.light_energy = 9.0
			_light.shadow_enabled = true
			add_child(_light)
			_disc = MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 1.0
			cm.height = 0.02
			cm.radial_segments = 48
			_disc.mesh = cm
			_disc_mat = Materials.unshaded(Color(1, 0.95, 0.75, 0.35), true)
			_disc.material_override = _disc_mat
			add_child(_disc)
			# faint additive beam so the light reads from any camera angle
			_beam = MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.12
			bm.bottom_radius = 1.0
			bm.height = 1.0
			bm.radial_segments = 32
			bm.cap_top = false
			bm.cap_bottom = false
			_beam.mesh = bm
			_beam_mat = Materials.unshaded(Color(1, 0.95, 0.75, 0.07), true)
			_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			_beam.material_override = _beam_mat
			_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_beam)
			_ring = MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.94
			tm.outer_radius = 1.0
			tm.rings = 48
			_ring.mesh = tm
			_ring_mat = Materials.unshaded(Color(1, 1, 1, 0.8), true)
			_ring.material_override = _ring_mat
			add_child(_ring)
		"chumball":
			_ball = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = ChumballMode.BALL_RADIUS
			sm.height = ChumballMode.BALL_RADIUS * 2.0
			sm.radial_segments = 24
			sm.rings = 12
			_ball.mesh = sm
			_ball_mat = StandardMaterial3D.new()
			_ball_mat.albedo_color = Color("#d9c6a1")
			_ball_mat.roughness = 0.75
			_ball_mat.rim_enabled = true
			_ball_mat.rim = 0.4
			_ball.material_override = _ball_mat
			add_child(_ball)
			var tape := MeshInstance3D.new()
			var tt := TorusMesh.new()
			tt.inner_radius = ChumballMode.BALL_RADIUS * 0.98
			tt.outer_radius = ChumballMode.BALL_RADIUS * 1.04
			tape.mesh = tt
			tape.rotation = Vector3(PI * 0.5, 0, 0)
			tape.material_override = Materials.toon(Color("#8c8c8c"), 0.5, 0.0, 0.2)
			_ball.add_child(tape)
			for g in v.get("goals", []):
				_goals.append(_make_goal(g))
		"absolute_unit":
			_crown = Node3D.new()
			add_child(_crown)
			for i in 5:
				var can := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.07
				cyl.bottom_radius = 0.07
				cyl.height = 0.22
				can.mesh = cyl
				can.material_override = Materials.toon(Color("#8BD426"), 0.3, 0.6, 0.4, Color("#8BD426") * 0.6)
				var a := TAU * i / 5.0
				can.position = Vector3(cos(a) * 0.22, 0.0, sin(a) * 0.22)
				_crown.add_child(can)
			var halo := MeshInstance3D.new()
			var ht := TorusMesh.new()
			ht.inner_radius = 0.9
			ht.outer_radius = 1.0
			halo.mesh = ht
			halo.material_override = Materials.unshaded(Color(0.55, 0.85, 0.15, 0.6), true)
			halo.name = "Halo"
			add_child(halo)
		"chum_rush":
			var gs: Array = v.get("gates", [])
			var walls: Array = v.get("gate_walls", gs)
			for k in gs.size():
				var gate := _make_gate(walls[k] if k < walls.size() else gs[k], gs[k])
				_gates.append(gate)


func _make_goal(g: Dictionary) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var p: Vector3 = g["pos"]
	var nrm: Vector3 = g["normal"]
	n.global_position = p
	n.rotation.y = atan2(nrm.x, nrm.z)
	var w := float(g["width"])
	var col := TeamColors.color(int(g["team"]))
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.08
		cm.height = 2.0
		post.mesh = cm
		post.material_override = Materials.toon(col, 0.4, 0.2, 0.4)
		post.position = Vector3(side * w * 0.5, 1.0, 0.0)
		n.add_child(post)
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.12, 0.12)
	bar.mesh = bm
	bar.material_override = Materials.toon(col, 0.4, 0.2, 0.4)
	bar.position = Vector3(0, 2.0, 0)
	n.add_child(bar)
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(w, 0.01, 0.12)
	line.mesh = lm
	line.material_override = Materials.unshaded(col.lightened(0.2), false)
	line.position = Vector3(0, 0.01, 0.55)
	n.add_child(line)
	var lbl := Label3D.new()
	lbl.text = "%s GOAL" % TeamColors.name(int(g["team"])).to_upper()
	lbl.font_size = 48
	lbl.outline_size = 10
	lbl.modulate = col
	lbl.position = Vector3(0, 2.5, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.add_child(lbl)
	return n


## A doorway set into the fence at `wall` (facing the cage centre): hazard-striped posts and
## lintel, a barred grate that rolls up while the gate spawns, a warning lamp, and a floor
## chevron at `spawn` showing where enemies step in. Open frame: never hides the fight.
func _make_gate(wall: Vector3, spawn: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = Vector3(wall.x, 0.0, wall.z)
	n.rotation.y = atan2(-wall.x, -wall.z)
	var steel := Materials.toon(Color("#2a2a30"), 0.5, 0.6, 0.3)
	var hazard := Materials.toon(Color("#E8B21F"), 0.5, 0.2, 0.3)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.16, 2.7, 0.16)
		post.mesh = pb
		post.material_override = hazard
		post.position = Vector3(side * 1.0, 1.35, 0.05)
		n.add_child(post)
	var lintel := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(2.16, 0.22, 0.2)
	lintel.mesh = lb
	lintel.material_override = steel
	lintel.position = Vector3(0, 2.75, 0.05)
	n.add_child(lintel)
	# barred grate: thin vertical bars + two rails, rolls up into the lintel when open
	var door := Node3D.new()
	door.name = "Door"
	door.position = Vector3(0, 0.0, 0.05)
	n.add_child(door)
	for k in 9:
		var bar := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 2.5
		cm.radial_segments = 6
		bar.mesh = cm
		bar.material_override = steel
		bar.position = Vector3(-0.88 + k * 0.22, 1.25, 0.0)
		door.add_child(bar)
	for y in [0.4, 2.1]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(1.86, 0.08, 0.06)
		rail.mesh = rb
		rail.material_override = steel
		rail.position = Vector3(0, y, 0.0)
		door.add_child(rail)
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.3, 0.2)
	lamp.light_energy = 0.0
	lamp.omni_range = 3.5
	lamp.position = Vector3(0, 2.95, 0.4)
	n.add_child(lamp)
	var bulb := MeshInstance3D.new()
	bulb.name = "Bulb"
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	bulb.mesh = sm
	bulb.material_override = Materials.unshaded(Color(0.45, 0.12, 0.1), false)
	bulb.position = Vector3(0, 2.98, 0.12)
	n.add_child(bulb)
	# flat arrow on the floor pointing into the cage from the spawn point
	var chevron := MeshInstance3D.new()
	chevron.name = "Chevron"
	var pm := PrismMesh.new()
	pm.size = Vector3(0.9, 0.7, 0.01)
	chevron.mesh = pm
	chevron.material_override = Materials.unshaded(Color(1.0, 0.35, 0.25, 0.0), true)
	chevron.position = n.to_local(Vector3(spawn.x, 0.03, spawn.z))
	chevron.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	n.add_child(chevron)
	return n


func _update_spotlight(v: Dictionary) -> void:
	var p: Vector3 = v.get("light", Vector3.ZERO)
	var r := float(v.get("radius", 2.0))
	_light.global_position = Vector3(p.x, 8.5, p.z)
	_light.look_at(Vector3(p.x, 0.0, p.z), Vector3.FORWARD)
	_light.spot_angle = rad_to_deg(atan(r * 1.1 / 8.5))
	var hog := int(v.get("hog", -1))
	var col := Color(1.0, 0.95, 0.75)
	if hog >= 0:
		col = TeamColors.color(hog).lightened(0.3)
	elif hog == -2:
		col = Color(1.0, 0.35, 0.3) if fmod(_t, 0.5) < 0.25 else Color(1, 1, 1)
	_light.light_color = col
	_disc.global_position = Vector3(p.x, 0.025, p.z)
	_disc.scale = Vector3(r, 1.0, r)
	_disc_mat.albedo_color = Color(col.r, col.g, col.b, 0.35)
	_beam.global_position = Vector3(p.x, 4.25, p.z)
	_beam.scale = Vector3(r, 8.5, r)
	_beam_mat.albedo_color = Color(col.r, col.g, col.b, 0.07)
	_ring.global_position = Vector3(p.x, 0.04, p.z)
	var cd := float(v.get("countdown", 0.0))
	var pulse := 1.0 + (0.1 * sin(_t * 12.0) if cd < 3.0 and cd > 0.0 else 0.0)
	_ring.scale = Vector3(r * pulse, 0.15, r * pulse)
	_ring_mat.albedo_color = Color(col.r, col.g, col.b, 0.9 if cd < 3.0 else 0.5)


func _update_ball(v: Dictionary) -> void:
	if _ball == null:
		return
	var xf: Transform3D = v.get("ball", Transform3D())
	_ball.global_transform = xf
	var el := str(v.get("ball_element", ""))
	if el != "":
		_ball_mat.emission_enabled = true
		_ball_mat.emission = Elements.color(el)
		_ball_mat.emission_energy_multiplier = 0.8 + 0.4 * sin(_t * 10.0)
	else:
		_ball_mat.emission_enabled = false


func _update_unit(v: Dictionary) -> void:
	var u := int(v.get("unit", -1))
	var halo := get_node_or_null("Halo") as MeshInstance3D
	if u < 0 or not head_of.is_valid():
		_crown.visible = false
		if halo:
			halo.visible = false
		return
	var head: Vector3 = head_of.call(u)
	_crown.visible = true
	_crown.global_position = head + Vector3.UP * 0.55
	_crown.rotation.y = _t * 1.5
	if halo:
		halo.visible = true
		halo.global_position = Vector3(head.x, 0.05, head.z)
		halo.scale = Vector3.ONE * (1.4 + 0.08 * sin(_t * 4.0))


func _update_gates(v: Dictionary) -> void:
	var open_gate = v.get("open_gate", Vector3.INF)
	var spawning := str(v.get("stage", "")) == "spawning"
	for g: Node3D in _gates:
		var door := g.get_node("Door") as Node3D
		var lamp := g.get_node("Lamp") as OmniLight3D
		var bulb := g.get_node("Bulb") as MeshInstance3D
		var chevron := g.get_node("Chevron") as MeshInstance3D
		var is_open: bool = typeof(open_gate) == TYPE_VECTOR3 and open_gate != Vector3.INF and Vector2(g.global_position.x - open_gate.x, g.global_position.z - open_gate.z).length() < 2.0
		door.position.y = lerpf(door.position.y, 2.3 if is_open else 0.0, 0.15)
		door.scale.y = lerpf(door.scale.y, 0.08 if is_open else 1.0, 0.15)
		var blink := spawning and fmod(_t, 0.6) < 0.3
		lamp.light_energy = 3.0 if is_open else (1.2 if blink else 0.0)
		(bulb.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.35, 0.25) if (is_open or blink) else Color(0.45, 0.12, 0.1)
		var cmat := chevron.material_override as StandardMaterial3D
		cmat.albedo_color.a = lerpf(cmat.albedo_color.a, 0.85 if is_open else 0.0, 0.2)


## Tutorial footwork rings: white until stepped in, then green.
func _update_rings(rings: Array) -> void:
	var have := get_children().filter(func(c): return str(c.name).begins_with("TutRing"))
	if have.size() != rings.size():
		for c in have:
			c.queue_free()
		have.clear()
		for i in rings.size():
			var mi := MeshInstance3D.new()
			mi.name = "TutRing%d" % i
			var tm := TorusMesh.new()
			tm.inner_radius = 0.86
			tm.outer_radius = 1.0
			tm.rings = 32
			mi.mesh = tm
			mi.material_override = Materials.unshaded(Color(1, 1, 1, 0.85), true)
			add_child(mi)
			have.append(mi)
	for i in rings.size():
		var r: Dictionary = rings[i]
		var mi2: MeshInstance3D = have[i]
		var p: Vector3 = r["pos"]
		mi2.global_position = Vector3(p.x, 0.04, p.z)
		var rad := float(r["radius"]) * (1.0 + (0.0 if bool(r["done"]) else 0.06 * sin(_t * 5.0 + i)))
		mi2.scale = Vector3(rad, 0.2, rad)
		(mi2.material_override as StandardMaterial3D).albedo_color = Color(0.4, 1.0, 0.5, 0.9) if bool(r["done"]) else Color(1, 1, 1, 0.85)


func _update_downed(list: Array) -> void:
	var seen := {}
	for d in list:
		var idx := int(d["fighter"])
		seen[idx] = true
		var n: Node3D = _downed.get(idx)
		if n == null:
			n = Node3D.new()
			add_child(n)
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.85
			tm.outer_radius = 1.0
			ring.mesh = tm
			ring.material_override = Materials.unshaded(Color(1.0, 0.3, 0.25, 0.85), true)
			ring.name = "Ring"
			n.add_child(ring)
			var lbl := Label3D.new()
			lbl.name = "Label"
			lbl.font_size = 40
			lbl.outline_size = 10
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.position = Vector3(0, 1.4, 0)
			n.add_child(lbl)
			_downed[idx] = n
		if head_of.is_valid():
			var hp: Vector3 = head_of.call(idx)
			n.global_position = Vector3(hp.x, 0.05, hp.z)
		var rev := float(d.get("revive", 0.0))
		(n.get_node("Ring") as MeshInstance3D).scale = Vector3.ONE * (1.4 - rev * 0.6)
		(n.get_node("Label") as Label3D).text = ("REVIVING %d%%" % int(rev * 100.0)) if rev > 0.01 else ("DOWN — %ds  (hold %s nearby)" % [ceili(float(d.get("left", 0.0))), Controls.prompt_for("grab")])
	for idx in _downed.keys():
		if not seen.has(idx):
			(_downed[idx] as Node3D).queue_free()
			_downed.erase(idx)
