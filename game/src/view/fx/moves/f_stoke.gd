extends MoveFxKit
## Stoke's Movesets effects (v0.9.18): the Flamethrower's living jet of fire, the Cinder Shot coal and
## its burst, the Flare Rush ignition and explosion, and the Fire Spin ring. Furnace identity: fire
## that comes out under pressure (a roaring core, licking tongues, cinders and smoke), never a flat
## orange glow.

const FLAME_CORE := Color(1.0, 0.86, 0.45)
const FLAME_BODY := Color(1.0, 0.42, 0.08)
const FLAME_EDGE := Color(0.78, 0.16, 0.04)
const SMOKE := Color(0.24, 0.2, 0.18, 0.5)

var _jets := {}          ## fighter -> {node, mat, inner_mat, len, full, cone_deg, age, ending, end_t}


func vfx_names() -> Array:
	return ["flamethrower", "flamethrower_patch", "cinder_shot", "cinder_burst", "flare_rush", "flare_burst", "fire_spin", "fire_spin_burst"]


## The stovepipe mouth (Stoke's head weapon point, a little forward).
func mouth(fi: int) -> Vector3:
	return fx.anchor(fi, "head", Vector3(0, -0.03, 0.12))


func on_sustain(fi: int, ev: Dictionary) -> bool:
	if str(ev.get("pool", "")) != "flamethrower":
		return false
	if str(ev.get("phase", "")) == "start":
		_start_jet(fi)
	else:
		_end_jet(fi)
	return true


func on_effect(fi: int, ev: Dictionary) -> bool:
	match str(ev.get("vfx", "")):
		"flamethrower":
			_flame_tick(fi, ev)
		"flamethrower_patch":
			pass        # the scorch patch itself is drawn as a zone
		"cinder_burst":
			_cinder_burst(Vector3(ev["pos"]), float(ev.get("radius", 1.3)))
		"flare_rush":
			_flare_ignite(fi)
		"flare_burst":
			_flare_burst(fi, Vector3(ev["pos"]), float(ev.get("radius", 1.1)))
		"fire_spin_burst":
			_spin_burst(fi, Vector3(ev["pos"]), float(ev.get("radius", 1.9)))
		_:
			return false
	return true


func on_move_start(fi: int, ev: Dictionary) -> bool:
	match str(ev.get("pool", "")):
		"flamethrower":
			# the stovepipe draws breath: embers suck into the mouth, the stacks puff
			fx._converge(fi, "head", Vector3(0, -0.03, 0.12), 0.25, FLAME_BODY, FLAME_CORE, 0.6, "cinders")
			fx._stacks_puff(fi, "smoke", 0.3, 0.7)
		"cinder_shot":
			fx._glow_at(fi, "fist_r", Vector3.ZERO, 0.22, 0.4, FLAME_BODY, 0.22, true)
		"fire_spin":
			fx._stacks_puff(fi, "flames", 0.4, 0.8)
	return false        # the generic move-start build-up still runs


## ---- Flamethrower --------------------------------------------------------------------------------

func _start_jet(fi: int) -> void:
	_end_jet(fi, true)
	var mi := MeshInstance3D.new()
	mi.mesh = FxKit.flame_mesh()                  # subdivided so the flame can curl as it travels
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/view/shaders/fx_flame_jet.gdshader")
	mat.set_shader_parameter("alpha", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	var inner_mat: ShaderMaterial = null
	if fx.quality >= 1:
		var core := MeshInstance3D.new()
		core.mesh = mi.mesh
		inner_mat = mat.duplicate() as ShaderMaterial
		inner_mat.set_shader_parameter("inner", 1.0)
		inner_mat.set_shader_parameter("seed", 3.4)
		core.material_override = inner_mat
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(core)
		core.scale = Vector3(0.46, 0.88, 0.46)
		core.position.y = 0.12                  # both cones begin at the same mouth
	_jets[fi] = {"node": mi, "mat": mat, "inner_mat": inner_mat, "len": 0.2, "full": 3.2, "cone_deg": 40.0,
		"age": 0.0, "ending": false, "end_t": 0.0}
	fx.flash_light(mouth(fi), FLAME_BODY, 2.5, 3.5, 0.25)


func _end_jet(fi: int, now := false) -> void:
	var j: Dictionary = _jets.get(fi, {})
	if j.is_empty():
		return
	if now:
		if is_instance_valid(j["node"]):
			(j["node"] as Node).queue_free()
		_jets.erase(fi)
		return
	j["ending"] = true
	# the last breath: a gout of smoke from the stovepipe
	fx.burst("smoke", mouth(fi), aim_dir(fi, 0.2), SMOKE, null, {"amount": 0.5, "speed": 0.9, "spread": 0.4})


func process(delta: float) -> void:
	for fi in _jets.keys():
		var j: Dictionary = _jets[fi]
		var mi: MeshInstance3D = j["node"]
		if not is_instance_valid(mi):
			_jets.erase(fi)
			continue
		j["age"] = float(j["age"]) + delta
		if not bool(j["ending"]) and not is_acting(fi):
			j["ending"] = true                       # interrupted (hit, knocked down): the jet dies
		var mat: ShaderMaterial = j["mat"]
		var inner_mat: ShaderMaterial = j["inner_mat"]
		var full := float(j["full"])
		if bool(j["ending"]):
			j["end_t"] = float(j["end_t"]) + delta
			var k := clampf(float(j["end_t"]) / 0.22, 0.0, 1.0)
			mat.set_shader_parameter("dissolve", k)
			mat.set_shader_parameter("alpha", 1.0 - k)
			if inner_mat != null:
				inner_mat.set_shader_parameter("dissolve", k)
				inner_mat.set_shader_parameter("alpha", 1.0 - k)
			if k >= 1.0:
				mi.queue_free()
				_jets.erase(fi)
				continue
		else:
			j["len"] = move_toward(float(j["len"]), full, delta * 14.0)      # it surges out to its reach
			mat.set_shader_parameter("alpha", clampf(float(j["age"]) / 0.08, 0.0, 1.0) * (0.85 if fx.reduce_flashes else 1.0))
			if inner_mat != null:
				inner_mat.set_shader_parameter("alpha", mat.get_shader_parameter("alpha"))
		var l: float = j["len"]
		var d := aim_dir(fi, -0.12)
		var x := d.cross(Vector3.UP).normalized()
		var y := -d
		var z := x.cross(y).normalized()
		# Follow the authoritative cone, including drills/upgrades; flutter gives the fire motion.
		var flutter := 1.0 + 0.08 * sin(float(j["age"]) * 31.0) + 0.05 * sin(float(j["age"]) * 47.0)
		var r := l * tan(deg_to_rad(float(j["cone_deg"]) * 0.5)) * flutter
		mi.global_transform = Transform3D(Basis(x * r, y * l, z * r * 0.75), mouth(fi) + d * l)


func _flame_tick(fi: int, ev: Dictionary) -> void:
	var d := aim_dir(fi, -0.12)
	var reach := float(ev.get("radius", 3.2))
	var cone := float(ev.get("cone_deg", 40.0))
	# A tap fires without a sustain-start event, and late joiners can arrive mid-stream.
	# The authoritative effect tick provides both the existence and exact footprint of the jet.
	if not _jets.has(fi):
		_start_jet(fi)
	var jet: Dictionary = _jets[fi]
	jet["full"] = reach
	jet["cone_deg"] = cone
	# tongues of flame along the jet, cinders thrown past its end, smoke rolling off the top
	fx.burst("flames", mouth(fi), d, FLAME_BODY, FLAME_EDGE, {"speed": reach * 2.2, "spread": deg_to_rad(cone) * 0.45, "amount": 0.55, "life": 0.55})
	fx.burst("cinders", mouth(fi) + d * 0.3, d, FLAME_CORE, FLAME_BODY, {"speed": reach * 2.6, "spread": 0.35, "amount": 0.3})
	if fx._rng.randf() < 0.35:
		fx.burst("smoke", mouth(fi) + d * reach * 0.7 + Vector3.UP * 0.3, Vector3.UP, SMOKE, null, {"amount": 0.25, "speed": 0.6})
	# the true footprint flickers on the floor now and then (the cone that can hit)
	if fx._rng.randf() < 0.25 and ev.has("origin"):
		fx.footprint("scorch", "cone", Vector3(ev["origin"]), float(ev.get("yaw", fx._yaw(fi))), reach,
			{"cone_deg": cone, "strength": 0.45, "front": 0.6}, 0.3, 0.05)


## ---- Cinder Shot ---------------------------------------------------------------------------------

func make_entity(e: Dictionary) -> Dictionary:
	match str(e.get("vfx", "")):
		"cinder_shot":
			return _coal(e)
		"fire_spin":
			return _ring_of_fire(e)
	return {}


func _coal(e: Dictionary) -> Dictionary:
	var r := maxf(float(e.get("radius", 0.26)), 0.1)
	var root := Node3D.new()
	fx.add_child(root)
	root.global_position = e["pos"]
	var coal := MeshInstance3D.new()
	coal.mesh = fx._sphere(r * 0.9, 12)
	coal.material_override = FxKit.flow_material(Color(0.35, 0.06, 0.02), FLAME_CORE, {"cover": 1.0, "glow_k": 1.3, "fresnel": 1.4,
		"scroll": Vector2(0.4, -0.8), "noise_scale": Vector2(5.0, 4.0), "edge_v": 0.0, "core": 0.7, "core_width": 0.5, "alpha": 1.0})
	root.add_child(coal)
	var shell := MeshInstance3D.new()
	shell.mesh = fx._sphere(r * 1.35, 12)
	shell.material_override = FxKit.flow_material(FLAME_BODY, FLAME_CORE, {"cover": 0.4, "glow_k": 1.1, "fresnel": 2.0,
		"scroll": Vector2(0.0, -2.5), "noise_scale": Vector2(6.0, 3.0), "edge_v": 0.0, "core": 0.5, "core_width": 0.5, "alpha": 0.8})
	root.add_child(shell)
	var trail := fx._attached_stream(root, "flames", FLAME_BODY, FLAME_EDGE, {"speed": 0.3, "amount": 0.7, "radius": r * 0.5})
	var embers := fx._attached_stream(root, "cinders", FLAME_CORE, FLAME_BODY, {"speed": 0.4, "amount": 0.5})
	var smoke := fx._attached_stream(root, "smoke", SMOKE, null, {"speed": 0.2, "amount": 0.35})
	var state := {"t": 0.0}
	return {"node": root, "kind": "projectile", "pos": e["pos"], "dir": Vector3.FORWARD,
		"tick": func(_e2: Dictionary) -> void:
			state["t"] = float(state["t"]) + 1.0 / 60.0
			if is_instance_valid(coal):
				coal.rotation = Vector3(float(state["t"]) * 7.0, float(state["t"]) * 5.0, 0.0),
		"end": func() -> void:
			for s in [trail, embers, smoke]:
				fx.end_stream(s)
			if is_instance_valid(root):
				root.queue_free()}


func _cinder_burst(pos: Vector3, r: float) -> void:
	var floor_p := Vector3(pos.x, 0.0, pos.z)
	fx.burst("fireball", pos + Vector3.UP * 0.1, Vector3.UP, FLAME_CORE, FLAME_BODY, {"amount": 0.8, "speed": 2.2})
	fx.burst("cinders", pos, Vector3.UP, FLAME_CORE, FLAME_BODY, {"amount": 0.7, "speed": 4.5, "spread": 1.2})
	fx.burst("smoke", pos + Vector3.UP * 0.4, Vector3.UP, SMOKE, null, {"amount": 0.6, "speed": 1.0})
	fx.ring_wall(floor_p, 0.2, r, 0.35, FLAME_BODY, FLAME_CORE, 0.35, {"bands": 3.0})
	fx.footprint("scorch", "circle", floor_p, 0.0, r, {"strength": 0.9}, 0.6, 0.08)
	fx.flash_light(pos + Vector3.UP * 0.4, FLAME_BODY, 3.0, 4.0, 0.3)


## ---- Flare Rush ----------------------------------------------------------------------------------

func _flare_ignite(fi: int) -> void:
	# both stacks fire, and the body trails flame for the length of the lunge
	fx._stacks_puff(fi, "flames", 0.35, 1.0)
	fx.flash_light(fx.anchor(fi, "core"), FLAME_BODY, 2.0, 3.0, 0.2)
	fx._stream_at(fi, "core", Vector3(0, 0, -0.1), 0.38, "flames", FLAME_BODY, FLAME_EDGE, {"dir": -aim_dir(fi), "speed": 1.2, "amount": 0.9, "radius": 0.3}, "flare")
	fx._stream_at(fi, "fist_r", Vector3.ZERO, 0.38, "cinders", FLAME_CORE, FLAME_BODY, {"speed": 0.6, "amount": 0.6}, "flare")


func _flare_burst(fi: int, pos: Vector3, r: float) -> void:
	fx.release(fi, "flare")
	var p := pos + Vector3.UP * 0.2
	fx.burst("fireball", p, aim_dir(fi), FLAME_CORE, FLAME_BODY, {"amount": 1.0, "speed": 3.0})
	fx.burst("cinders", p, aim_dir(fi), FLAME_CORE, FLAME_BODY, {"amount": 0.9, "speed": 6.0, "spread": 0.9})
	fx.burst("smoke", p + Vector3.UP * 0.3, Vector3.UP, SMOKE, null, {"amount": 0.7, "speed": 1.4})
	fx.ring_wall(Vector3(pos.x, 0.0, pos.z), 0.3, r * 1.3, 0.6, FLAME_BODY, FLAME_CORE, 0.3, {"bands": 4.0})
	fx.flash_light(p, FLAME_CORE, 4.0, 4.5, 0.3)


## ---- Fire Spin -----------------------------------------------------------------------------------

func _spin_burst(fi: int, pos: Vector3, r: float) -> void:
	var floor_p := Vector3(pos.x, 0.0, pos.z)
	fx.ring_wall(floor_p, 0.4, r, 0.9, FLAME_BODY, FLAME_CORE, 0.45, {"bands": 5.0, "scroll": Vector2(1.2, -1.4)})
	fx.burst("flames", floor_p + Vector3.UP * 0.2, Vector3.UP, FLAME_BODY, FLAME_EDGE, {"ring": true, "radius": r * 0.8, "amount": 0.9, "speed": 1.6})
	fx.flash_light(fx.anchor(fi, "core"), FLAME_BODY, 2.5, 4.0, 0.3)


func _ring_of_fire(e: Dictionary) -> Dictionary:
	var r := float(e.get("radius", 1.8))
	var root := Node3D.new()
	fx.add_child(root)
	var p: Vector3 = e["pos"]
	root.global_position = Vector3(p.x, 0.0, p.z)
	var wall := MeshInstance3D.new()
	wall.mesh = FxKit.wall_mesh(48, 1.0)
	var mat := FxKit.flow_material(FLAME_BODY, FLAME_CORE, {"cover": 0.55, "glow_k": 1.0, "scroll": Vector2(0.9, -2.2),
		"noise_scale": Vector2(14.0, 2.0), "edge_v": 0.3, "core": 0.25, "core_width": 0.25, "jag": 0.5, "alpha": 0.9})
	wall.material_override = mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.scale = Vector3(r, 0.75, r)
	root.add_child(wall)
	var floor_mi := fx.footprint("scorch", "ring", root.global_position, 0.0, r, {"inner": maxf(r - 0.45, 0.0), "strength": 0.8}, INF)
	var tongues := fx._attached_stream(root, "flames", FLAME_BODY, FLAME_EDGE, {"ring": true, "radius": r, "speed": 1.0, "amount": 0.8})
	var state := {"t": 0.0}
	return {"node": root, "kind": "zone", "pos": e["pos"],
		"tick": func(e2: Dictionary) -> void:
			state["t"] = float(state["t"]) + 1.0 / 60.0
			var q: Vector3 = e2["pos"]
			if is_instance_valid(root):
				root.global_position = Vector3(q.x, 0.0, q.z)
			if is_instance_valid(floor_mi):
				floor_mi.global_position = Vector3(q.x, 0.03, q.z)
			if is_instance_valid(wall):
				wall.scale = Vector3(r, 0.75 + 0.12 * sin(float(state["t"]) * 9.0), r)
				wall.rotation.y = float(state["t"]) * 1.4,
		"end": func() -> void:
			fx.end_stream(tongues)
			if is_instance_valid(floor_mi):
				floor_mi.queue_free()
			if is_instance_valid(root):
				var holder := root
				fx.animate(holder, 0.25, func(k: float, _t: float) -> void:
					mat.set_shader_parameter("dissolve", k)
					mat.set_shader_parameter("alpha", 0.9 * (1.0 - k)))}
