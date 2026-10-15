class_name HubNpcView
extends Node3D
## One hub NPC (view only): the forged static model (assets/models/hub/*.glb, one root bone,
## facing +Z) with the creature toon shader and outline, an idle loop with per-character rhythm
## (bob, sway, Barnaby's bounce, Needles' jitter), look-at toward the player when close (whole
## body turns, limited around the home facing), a flinch when punched, Ludlow's waddle and mop
## while he walks, and a speech bubble (billboard Label3D) for barks and reactions.

const LOOK_RANGE := 6.0
const PERSONALITY := {
	"granny": {"bob": 0.012, "rate": 1.1, "sway": 1.2, "look": 70.0},
	"snappington": {"bob": 0.004, "rate": 0.5, "sway": 0.4, "look": 0.0},
	"needles": {"bob": 0.02, "rate": 2.6, "sway": 2.5, "look": 80.0},
	"doc": {"bob": 0.008, "rate": 0.9, "sway": 1.0, "look": 60.0},
	"kid": {"bob": 0.01, "rate": 1.6, "sway": 3.0, "look": 90.0},
	"ludlow": {"bob": 0.008, "rate": 0.6, "sway": 1.5, "look": 60.0},
	"teddy": {"bob": 0.014, "rate": 2.0, "sway": 1.8, "look": 75.0},
	"barnaby": {"bob": 0.03, "rate": 1.8, "sway": 2.2, "look": 70.0},
}

var key := ""
var home_pos := Vector3.ZERO
var home_yaw := 0.0
var height := 1.3
var static_body := false
var model: Node3D
var bubble: Label3D
var _yaw := 0.0
var _t := 0.0
var _phase := 0.0
var _flinch := 0.0
var _bubble_left := 0.0
var _walking := false
var _materials: Array[ShaderMaterial] = []
var _mop: MeshInstance3D


func setup(k: String, model_path: String, pos: Vector3, yaw: float, h: float, is_static: bool) -> void:
	key = k
	name = "Npc_" + k
	home_pos = pos
	home_yaw = yaw
	height = h
	static_body = is_static
	_yaw = yaw
	_phase = float(hash(k) % 1000) / 1000.0 * TAU
	position = pos
	rotation = Vector3(0, yaw, 0)
	if model_path != "" and ResourceLoader.exists(model_path):
		var ps: PackedScene = load(model_path)
		model = ps.instantiate()
		add_child(model)
		_restyle(model)
	else:
		model = Node3D.new()
		add_child(model)
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.3
		cm.height = h
		mi.mesh = cm
		mi.position = Vector3(0, h * 0.5, 0)
		mi.material_override = Materials.toon(HubContent.npc_color(k), 0.7)
		model.add_child(mi)
	if k == "ludlow":
		_mop = MeshInstance3D.new()
		var mm := CylinderMesh.new()
		mm.top_radius = 0.02
		mm.bottom_radius = 0.02
		mm.height = 1.6
		_mop.mesh = mm
		_mop.material_override = Materials.toon(Color("#8a6a48"), 0.8)
		_mop.position = Vector3(0.42, 0.75, 0.35)
		_mop.rotation = Vector3(0.35, 0, -0.25)
		add_child(_mop)
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.36, 0.1, 0.16)
		head.mesh = hm
		head.material_override = Materials.toon(Color("#d8d2bd"), 0.9)
		head.position = Vector3(0, -0.8, 0)
		_mop.add_child(head)
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.font = load("res://assets/fonts/Barlow-600.woff2")
	bubble.font_size = 40
	bubble.pixel_size = 0.0042
	bubble.outline_size = 12
	bubble.outline_modulate = Color(0.07, 0.07, 0.1, 0.95)
	bubble.modulate = Color(1, 1, 1, 0)
	bubble.visible = false
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 620
	bubble.no_depth_test = true
	bubble.render_priority = 2
	bubble.position = Vector3(0, h + 0.55, 0)
	add_child(bubble)


## Same look as the fighters: creature toon shader + outline, PBR hints from the imported materials.
func _restyle(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si)
			var m := Materials.creature_material()
			m.set_shader_parameter("tint", Color.WHITE)
			if src is BaseMaterial3D:
				var bm := src as BaseMaterial3D
				m.set_shader_parameter("roughness_v", bm.roughness)
				m.set_shader_parameter("metallic_v", bm.metallic)
				m.set_shader_parameter("vertex_glow", 1.0 if bm.emission_enabled else 0.0)
			m.next_pass = Materials.outline_material(0.012)
			mi.set_surface_override_material(si, m)
			_materials.append(m)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children():
		_restyle(c)


## Ludlow: position/facing follow the sim's patrol.
func walk_to(p: Vector3, yaw: float, moving: bool) -> void:
	home_pos = p
	position = p
	if moving:
		home_yaw = yaw
	_walking = moving


func say(text: String, seconds := 3.5) -> void:
	bubble.text = text
	_bubble_left = seconds
	_bubble_alpha(1.0)


## Fill AND outline fade together (an outline left behind reads as dark ghost text).
func _bubble_alpha(a: float) -> void:
	bubble.modulate = Color(1, 1, 1, a)
	bubble.outline_modulate = Color(0.07, 0.07, 0.1, 0.95 * a)
	bubble.visible = a > 0.0


func flinch() -> void:
	_flinch = 1.0


func update(dt: float, player_pos: Vector3) -> void:
	_t += dt
	var p: Dictionary = PERSONALITY.get(key, PERSONALITY["granny"])
	# look at the player when close (limited turn around the home facing)
	var want := home_yaw
	var to := player_pos - global_position
	to.y = 0.0
	var look_lim := deg_to_rad(float(p["look"]))
	if not static_body and to.length() < LOOK_RANGE and look_lim > 0.0 and not _walking:
		var desired := atan2(to.x, to.z)
		want = home_yaw + clampf(wrapf(desired - home_yaw, -PI, PI), -look_lim, look_lim)
	_yaw = lerp_angle(_yaw, want, clampf(dt * (2.5 if not _walking else 6.0), 0.0, 1.0))
	rotation.y = _yaw
	# idle rhythm (+ waddle when walking, + flinch)
	var ph := _t * float(p["rate"]) * TAU * 0.5 + _phase
	var bob := sin(ph) * float(p["bob"])
	var sway := sin(ph * 0.5) * deg_to_rad(float(p["sway"]))
	if _walking:
		bob += absf(sin(_t * 6.0)) * 0.04
		sway += sin(_t * 6.0) * 0.06
	_flinch = maxf(0.0, _flinch - dt * 3.0)
	if model:
		model.scale = Vector3(1.0 - bob * 0.5, 1.0 + bob, 1.0 - bob * 0.5)
		model.rotation = Vector3(-_flinch * 0.25, 0.0, sway)
	if _mop:
		_mop.rotation.z = -0.25 + sin(_t * (5.0 if _walking else 1.2)) * (0.25 if _walking else 0.08)
	if _bubble_left > 0.0:
		_bubble_left -= dt
		if _bubble_left < 0.4:
			_bubble_alpha(maxf(0.0, _bubble_left / 0.4))
