class_name CombatDebugDraw
extends Node3D
## Combat debug visualization (CMB-11), toggled in matches with F3 (or started with
## `-- --debug-draw`). Read-only view of the simulation: hit capsules of every segment (white),
## weapon spheres (grey idle, yellow during startup, red while their hit window is active),
## the target line per fighter, effect zones/projectile radii, each fighter's reach circle
## (1.6 m cap), and a short-lived marker at each hit (cyan = blocked) with its closing speed.
## Uses one ImmediateMesh rebuilt per frame; never affects gameplay.

const REACH_CAP := 1.6

var sim: MatchSim
var _mesh: ImmediateMesh
var _mi: MeshInstance3D
var _mat: StandardMaterial3D
var _labels: Array = []          ## [{node: Label3D, until}]
var _cursor := 0


func setup(match_sim: MatchSim) -> void:
	sim = match_sim
	_cursor = sim.event_seq
	_mesh = ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.no_depth_test = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mi.material_override = _mat
	add_child(_mi)


func _process(_dt: float) -> void:
	if sim == null or not visible:
		return
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for f in sim.fighters:
		if f.despawned:
			continue
		_draw_fighter(f)
	for e in sim.effects.entities:
		var col := Color(0.4, 0.9, 1.0, 0.8) if str(e.get("kind", "")) == "projectile" else Color(1.0, 0.5, 0.9, 0.7)
		var p: Vector3 = e["pos"]
		_circle(Vector3(p.x, maxf(p.y, 0.03), p.z), float(e.get("radius", 0.5)), col)
	_mesh.surface_end()
	_new_hits()
	var now := Time.get_ticks_msec()
	for l in _labels.duplicate():
		if now > int(l["until"]):
			(l["node"] as Label3D).queue_free()
			_labels.erase(l)


func _draw_fighter(f: Fighter) -> void:
	var body := f.creature.body
	for s: BodyDef.Seg in body.segments:
		var xf := f.rig.bodies[s.index].global_transform
		for sh: BodyDef.Shape in s.shapes:
			_capsule(xf * sh.hit_a, xf * sh.hit_b, sh.hit_r, Color(1, 1, 1, 0.35))
	var active: PackedStringArray = PackedStringArray()
	var winding := false
	if f.move and (f.state == Fighter.State.ATTACK or f.state == Fighter.State.ABILITY):
		active = f.move.window_weapons(f.state_time)
		winding = active.is_empty() and f.state_time < f.move.first_active()
	for wname in body.weapons:
		var w: BodyDef.Weapon = body.weapons[wname]
		var wp: Vector3 = f.rig.bodies[w.seg].global_transform * w.local
		var col := Color(0.6, 0.6, 0.6, 0.5)
		if wname in active:
			col = Color(1.0, 0.2, 0.15, 1.0)
		elif winding and f.move and _move_uses(f.move, wname):
			col = Color(1.0, 0.85, 0.2, 0.9)
		_sphere(wp, w.radius, col)
	var gp := f.ground_pos()
	_circle(gp + Vector3.UP * 0.02, REACH_CAP, Color(0.1, 0.8, 0.25, 0.6))
	if f.target and not f.target.despawned:
		_line(f.pos(), f.target.pos(), TeamColors.color(f.team))


func _move_uses(m: MoveDef, wname: String) -> bool:
	for w in m.windows:
		if wname in (w["weapons"] as PackedStringArray):
			return true
	return false


func _new_hits() -> void:
	for ev in sim.events_since(_cursor):
		_cursor = int(ev["seq"])
		if str(ev["type"]) != "hit" or not ev.has("point"):
			continue
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 36
		l.outline_size = 8
		l.modulate = Color(0.5, 0.9, 1.0) if bool(ev.get("blocked", false)) else Color(1.0, 0.95, 0.4)
		l.text = "%s %.1f q%.2f" % [str(ev.get("slot", "")), float(ev.get("damage", 0.0)), float(ev.get("quality", 0.0))]
		add_child(l)
		l.global_position = (ev["point"] as Vector3) + Vector3.UP * 0.15
		_labels.append({"node": l, "until": Time.get_ticks_msec() + 1600})


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)


func _circle(center: Vector3, r: float, c: Color, axis := Vector3.UP, n := 24) -> void:
	var u := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	u = (u - axis * u.dot(axis)).normalized()
	var v := axis.cross(u)
	var prev := center + u * r
	for i in range(1, n + 1):
		var a := TAU * i / n
		var p := center + (u * cos(a) + v * sin(a)) * r
		_line(prev, p, c)
		prev = p


func _sphere(c: Vector3, r: float, col: Color) -> void:
	_circle(c, r, col, Vector3.UP, 12)
	_circle(c, r, col, Vector3.RIGHT, 12)
	_circle(c, r, col, Vector3.BACK, 12)


func _capsule(a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var axis := b - a
	if axis.length() < 0.001:
		_sphere(a, r, col)
		return
	var dir := axis.normalized()
	_circle(a, r, col, dir, 10)
	_circle(b, r, col, dir, 10)
	var u := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	u = (u - dir * u.dot(dir)).normalized() * r
	var v := dir.cross(u).normalized() * r
	for off in [u, -u, v, -v]:
		_line(a + off, b + off, col)
