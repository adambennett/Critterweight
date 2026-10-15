class_name Vfx
extends Node3D
## Pooled combat effects driven by simulation events (never by authority): hit sparks, block
## sparks, parry flashes, impact rings, dust puffs, KO stars, element bursts, projectile and
## zone visuals. Respects the flashing-reduction and effects-quality settings.

var reduce_flashes := false
var quality := 2
var _pool := {}
var _proj_nodes := {}            ## entity id -> Node3D
var _spark_mat: StandardMaterial3D


var _puff_mat: StandardMaterial3D
var _fade_ramp: GradientTexture1D


func _ready() -> void:
	# soft round sprite: bright core falling off to transparent (no hard-edged squares)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.85))
	var soft := GradientTexture2D.new()
	soft.gradient = g
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.vertex_color_use_as_albedo = true
	_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_mat.albedo_texture = soft
	_puff_mat = _spark_mat.duplicate()
	_puff_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_puff_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	_fade_ramp = GradientTexture1D.new()
	_fade_ramp.gradient = fade


func _particles(kind: String) -> GPUParticles3D:
	var list: Array = _pool.get(kind, [])
	for pnode: GPUParticles3D in list:
		if not pnode.emitting:
			return pnode
	var gp := GPUParticles3D.new()
	gp.one_shot = true
	gp.explosiveness = 0.95
	gp.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.color_ramp = _fade_ramp
	var quad := QuadMesh.new()
	quad.material = _puff_mat if kind == "dust" else _spark_mat
	match kind:
		"spark":
			gp.amount = 14
			gp.lifetime = 0.35
			pm.direction = Vector3(0, 0, 1)
			pm.spread = 55.0
			pm.initial_velocity_min = 3.0
			pm.initial_velocity_max = 7.0
			pm.gravity = Vector3(0, -9, 0)
			pm.scale_min = 0.04
			pm.scale_max = 0.09
			quad.size = Vector2(1, 1)
		"dust":
			gp.amount = 10
			gp.lifetime = 0.7
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 80.0
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.6
			pm.gravity = Vector3(0, 0.3, 0)
			pm.scale_min = 0.2
			pm.scale_max = 0.38
			pm.damping_min = 2.0
			pm.damping_max = 3.0
			# puffs grow as they fade
			var grow := Curve.new()
			grow.add_point(Vector2(0, 0.5))
			grow.add_point(Vector2(1, 1.0))
			var gt := CurveTexture.new()
			gt.curve = grow
			pm.scale_curve = gt
		"burst":
			gp.amount = 24
			gp.lifetime = 0.6
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 180.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 5.0
			pm.gravity = Vector3(0, -2, 0)
			pm.scale_min = 0.06
			pm.scale_max = 0.16
	if pm.scale_curve == null:
		var curve := CurveTexture.new()
		var c := Curve.new()
		c.add_point(Vector2(0, 1))
		c.add_point(Vector2(1, 0))
		curve.curve = c
		pm.scale_curve = curve
	gp.process_material = pm
	gp.draw_pass_1 = quad
	add_child(gp)
	list.append(gp)
	_pool[kind] = list
	return gp


func emit(kind: String, pos: Vector3, dir: Vector3, color: Color, scale_mult := 1.0) -> void:
	if quality <= 0 and kind != "spark":
		return
	var gp := _particles(kind)
	gp.global_position = pos
	if dir.length_squared() > 1e-6:
		var up := Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		gp.global_basis = Basis.looking_at(-dir.normalized(), up)
	(gp.process_material as ParticleProcessMaterial).color = color
	gp.amount_ratio = clampf(0.5 + 0.5 * scale_mult, 0.3, 1.0)
	gp.restart()
	gp.emitting = true


## Expanding flat ring on the floor or in the air (impact, shockwave, landing).
func ring(pos: Vector3, radius: float, color: Color, duration := 0.35, flat := true) -> void:
	if reduce_flashes:
		color.a *= 0.5
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 24
	mi.mesh = tm
	var m := Materials.unshaded(color, true)
	mi.material_override = m
	add_child(mi)
	mi.global_position = pos
	if not flat:
		mi.rotation = Vector3(PI * 0.5, 0, 0)
	mi.scale = Vector3.ONE * 0.1
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.3 if flat else radius, radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)


## Big readable text pop (e.g. "COUNTER!", "PARRY!", reaction names) in the world.
func word(pos: Vector3, text: String, color: Color, size := 64) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.03, 0.08)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font = load("res://assets/fonts/BarlowCondensed-900.woff2")
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.tween_property(l, "global_position", pos + Vector3.UP * 0.6, 0.7).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.35)
	tw.tween_callback(l.queue_free)


## Mirrors simulation entities (projectiles / zones) as simple glowing visuals.
func sync_entities(entities: Array) -> void:
	var seen := {}
	for e in entities:
		var id := int(e["id"])
		seen[id] = true
		var n: Node3D = _proj_nodes.get(id)
		if n == null:
			n = _make_entity_visual(e)
			_proj_nodes[id] = n
		n.global_position = e["pos"] if e["kind"] == "projectile" else Vector3(e["pos"].x, 0.02, e["pos"].z)
	for id in _proj_nodes.keys():
		if not seen.has(id):
			(_proj_nodes[id] as Node3D).queue_free()
			_proj_nodes.erase(id)


func _make_entity_visual(e: Dictionary) -> Node3D:
	var el := str(e.get("element", ""))
	var col := Elements.color(el) if el != "" else Color(1.0, 0.85, 0.5)
	var n := Node3D.new()
	add_child(n)
	if e["kind"] == "projectile":
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = float(e["radius"])
		sm.height = float(e["radius"]) * 2.0
		mi.mesh = sm
		mi.material_override = Materials.toon(col, 0.3, 0.0, 0.5, col * 0.8)
		n.add_child(mi)
		var light := OmniLight3D.new()
		light.light_color = col
		light.light_energy = 1.2
		light.omni_range = 2.0
		n.add_child(light)
	else:
		if e["e"].has("hazard"):
			return n
		var mi2 := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = float(e["radius"])
		cm.bottom_radius = float(e["radius"])
		cm.height = 0.04
		cm.radial_segments = 32
		mi2.mesh = cm
		var zc := col
		zc.a = 0.45
		mi2.material_override = Materials.unshaded(zc, true)
		n.add_child(mi2)
	return n
