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
