extends TestCase
## v0.9.18 Movesets effects (src/view/fx/move_vfx.gd, moves/<creature>.gd): the kits are found, a
## kit draws the events and entities it names (and only those), sustained moves get a living
## effect that follows the fighter and ends with the move (or when it is cut off), and entity
## looks are cleaned up.

var _state := {}         ## fighter -> Fighter.State the info callable reports


func _fx(views: Array) -> AbilityVfx:
	var fx := AbilityVfx.new()
	fx.view_of = func(i: int): return views[i] if i >= 0 and i < views.size() else null
	fx.info_of = func(i: int) -> Dictionary:
		if i < 0 or i >= views.size():
			return {}
		return {"ground": Vector3(i * 2.0, 0, 0), "yaw": 0.0, "state": int(_state.get(i, Fighter.State.ABILITY)), "juiced": false,
			"hidden": false, "charge": -1.0, "out": false}
	fx.fighter_count = func() -> int: return views.size()
	add_child(fx)
	return fx


func _views(ids: Array) -> Array:
	var out := []
	for id in ids:
		var v := CreatureView.new()
		add_child(v)
		v.setup(Content.creature(str(id)))
		out.append(v)
	return out


func _free(fx: AbilityVfx, views: Array) -> void:
	fx.queue_free()
	for v in views:
		(v as Node).queue_free()


func test_kits_are_registered_by_creature_and_vfx_name() -> void:
	var views := _views(["f_stoke"])
	var fx := _fx(views)
	check(fx.moves != null and fx.moves.kits.has("f_stoke"), "Stoke's kit is loaded")
	for v in ["flamethrower", "cinder_shot", "cinder_burst", "flare_burst", "fire_spin", "fire_spin_burst"]:
		check(fx.moves.by_vfx.has(v), "the kit draws '%s'" % v)
	check(not fx.moves.by_vfx.has("steam_vent"), "v0.9.17 recipes are not taken over")
	_free(fx, views)


func test_flamethrower_lives_while_sustained_and_dies_when_cut_off() -> void:
	var views := _views(["f_stoke"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_stoke"]
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "start", "pool": "flamethrower", "slot": "m2"})
	check((kit._jets as Dictionary).has(0), "a sustain start lights the jet")
	for k in 4:
		fx.on_event({"type": "effect", "fighter": 0, "effect": "area", "vfx": "flamethrower", "pool": "flamethrower", "tick": true,
			"pos": Vector3(0, 0, 0), "origin": Vector3.ZERO, "radius": 3.2, "cone_deg": 40.0, "shape": "cone", "yaw": 0.0, "element": "scorch"})
		await wait_frames(6)
	var jet: Dictionary = kit._jets.get(0, {})
	check(not jet.is_empty() and float(jet["len"]) > 1.0, "the jet surges out toward its reach (%s)" % str(jet.get("len", 0)))
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "end", "pool": "flamethrower", "slot": "m2"})
	await wait_frames(30)
	check(not (kit._jets as Dictionary).has(0), "releasing ends it")
	# cut off: a hit stuns Stoke mid-stream (no end event reaches the effects first)
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "start", "pool": "flamethrower", "slot": "m2"})
	await wait_frames(4)
	_state[0] = Fighter.State.HITSTUN
	await wait_frames(30)
	check(not (kit._jets as Dictionary).has(0), "an interrupted stream dies with the move")
	_state.erase(0)
	_free(fx, views)


func test_coal_and_ring_entities_draw_and_clean_up() -> void:
	var views := _views(["f_stoke"])
	var fx := _fx(views)
	fx.sync_entities([{"id": 1, "kind": "projectile", "vfx": "cinder_shot", "pos": Vector3(0, 1, 1), "radius": 0.26, "element": "scorch", "team": 0},
		{"id": 2, "kind": "zone", "vfx": "fire_spin", "pos": Vector3(0, 0, 0), "radius": 1.8, "element": "scorch", "team": 0}])
	check(fx._ents.has(1) and fx._ents.has(2), "both entities are drawn")
	var coal: Node3D = (fx._ents[1] as Dictionary)["node"]
	var ring: Node3D = (fx._ents[2] as Dictionary)["node"]
	fx.sync_entities([{"id": 1, "kind": "projectile", "vfx": "cinder_shot", "pos": Vector3(0, 1.2, 2), "radius": 0.26, "element": "scorch", "team": 0},
		{"id": 2, "kind": "zone", "vfx": "fire_spin", "pos": Vector3(1, 0, 0), "radius": 1.8, "element": "scorch", "team": 0}])
	check(coal.global_position.is_equal_approx(Vector3(0, 1.2, 2)), "the coal flies with its projectile")
	check(is_equal_approx(ring.global_position.x, 1.0), "the ring follows Stoke")
	fx.sync_entities([])
	await wait_frames(40)
	check(not is_instance_valid(coal), "the coal is cleaned up")
	check(not is_instance_valid(ring), "the ring is cleaned up")
	_free(fx, views)


func test_flame_layers_obey_quality_and_reduced_flashing() -> void:
	var views := _views(["f_stoke"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_stoke"]
	for quality in [0, 2]:
		fx.quality = quality
		fx.reduce_flashes = true
		kit._start_jet(0)
		kit.process(0.15)
		var jet: Dictionary = kit._jets[0]
		var node: MeshInstance3D = jet["node"]
		check_eq(node.get_child_count(), 0 if quality == 0 else 1, "inner fire is omitted on low effects")
		var mat: ShaderMaterial = jet["mat"]
		check_eq(mat.shader.resource_path, "res://src/view/shaders/fx_flame_jet.gdshader", "the textured furnace shader is used")
		check_near(float(mat.get_shader_parameter("alpha")), 0.85, 0.001, "reduced flashing limits the stream")
		kit._end_jet(0, true)
		await wait_frames(1)
		check(not is_instance_valid(node), "all layers are freed together")
	_free(fx, views)


func test_hydro_beam_geometry_follows_the_authoritative_direction() -> void:
	var views := _views(["f_dredge"])
	var fx := _fx(views)
	fx.quality = 2
	var kit = fx.moves.kits["f_dredge"]
	var tip: Vector3 = fx.anchor(0, "claw_crusher", Vector3(0, 0, 0.08))
	var origin := Vector3(2, 0, 1)
	var end := origin + Vector3.RIGHT * 5.0 + Vector3.UP * 0.55
	kit.on_effect(0, {"vfx": "dredge_hydro_beam", "origin": origin, "yaw": PI * 0.5,
		"shape": "line", "length": 5.0, "width": 0.9})
	fx._process(0.2)
	var jets: Array = []
	for child in fx.get_children():
		if child is MeshInstance3D and child.mesh == FxKit.wall_mesh(32, 0.06):
			jets.append(child)
	check_eq(jets.size(), 2, "water and foam columns are present")
	if jets.size() == 2:
		var outer: MeshInstance3D = jets[0]
		check(outer.global_position.is_equal_approx(end), "the wide end reaches the real beam endpoint")
		check((outer.global_transform * Vector3.UP).is_equal_approx(tip), "the narrow end begins at the crusher claw")
	_free(fx, views)


func test_flame_cone_uses_the_actual_drilled_reach_and_width() -> void:
	var views := _views(["f_stoke"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_stoke"]
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "start", "pool": "flamethrower", "slot": "m2"})
	fx.on_event({"type": "effect", "fighter": 0, "effect": "area", "vfx": "flamethrower", "pool": "flamethrower", "tick": true,
		"pos": Vector3.ZERO, "origin": Vector3.ZERO, "radius": 5.1, "cone_deg": 70.0, "shape": "cone", "yaw": 0.0, "element": "scorch"})
	# Drive the effect clock directly: independent of headless/rendered frame rates.
	kit.process(0.5)
	var jet: Dictionary = kit._jets.get(0, {})
	check(not jet.is_empty(), "the sustained flame exists")
	if not jet.is_empty():
		check_near(float(jet["len"]), 5.1, 0.001, "drilled reach controls the whole jet")
		var flutter := 1.0 + 0.08 * sin(float(jet["age"]) * 31.0) + 0.05 * sin(float(jet["age"]) * 47.0)
		var node: MeshInstance3D = jet["node"]
		check_near(node.global_basis.x.length(), 5.1 * tan(deg_to_rad(35.0)) * flutter, 0.001,
			"drilled cone angle controls its visible width")
	_free(fx, views)


func test_flame_tick_recovers_a_stream_without_its_start_event() -> void:
	var views := _views(["f_stoke"])
	var fx := _fx(views)
	var kit = fx.moves.kits["f_stoke"]
	# A late-joining spectator receives future ticks but never the earlier start event.
	fx.on_event({"type": "effect", "fighter": 0, "effect": "area", "vfx": "flamethrower", "pool": "flamethrower", "tick": true,
		"pos": Vector3.ZERO, "origin": Vector3.ZERO, "radius": 4.0, "cone_deg": 25.0, "shape": "cone", "yaw": 0.0, "element": "scorch"})
	check((kit._jets as Dictionary).has(0), "an authoritative tick reconstructs the flame")
	_state[0] = Fighter.State.HITSTUN
	kit.process(0.3)
	check(not (kit._jets as Dictionary).has(0), "a reconstructed stream also ends when interrupted")
	_state.erase(0)
	_free(fx, views)


func test_showcase_includes_every_varga_technique() -> void:
	var showcase = load("res://src/test/vfx/test_moves_showcase.gd")
	var c := Content.creature("f_varga")
	var shots: Array = showcase.shots_for(c)
	var names := []
	for shot in shots:
		names.append(str(shot["name"]))
	for id in c.pool:
		check(names.has(str(id)), "the rendered review includes Varga's %s" % id)
