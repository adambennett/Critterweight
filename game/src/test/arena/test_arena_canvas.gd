extends TestCase
## P15-12: editor-only rooftop canvas; rectangular geometry, saved packages, controller
## sizing, large-stage cameras and authoritative ledge falls. No graphical launch required.

var _camera_points: Array = []

func after_each() -> void:
	App.clear_screens()
	App.set_scene(null)

func _model() -> ArenaEditModel:
	return ArenaEditModel.new_from_base("rooftop_canvas")

func _points() -> Array:
	return _camera_points

func _joy(button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.device = 0
		ev.pressed = pressed
		Input.parse_input_event(ev)
	await wait_frames(2)

func test_template_is_editor_only_and_valid_at_supported_sizes() -> void:
	check(ArenaCatalog.base_ids().has("rooftop_canvas"), "offered as an editor base")
	check_eq(ArenaCatalog.base_arena_id("rooftop_canvas"), "", "no built-in playable arena")
	check(not Content.ids("arenas").has("editor_rooftop_canvas"), "no blank entry in Content")
	for entry in ArenaLibrary.base_arenas():
		check(str(entry["base"]) != "rooftop_canvas", "not a built-in match choice")
	for entry in ArenaLibrary.playable_arenas():
		check(str(entry["id"]) != "editor_rooftop_canvas", "blank template never in setup menus")
	var m := _model()
	check_eq(m.size, Vector2(32, 32), "large square default")
	for sz in [Vector2(12, 12), Vector2(64, 12), Vector2(12, 64), Vector2(64, 64)]:
		m.size = sz
		var a := m.to_arena()
		check_eq(a.size, sz, "independent dimensions survive resolution")
		check_eq(a.style, "rooftop", "rooftop environment")
		check_eq(a.shape, "rect", "no original rooftop notches")
		check(a.all_props().is_empty(), "blank floor; no built-in props")
		check(a.base_hazards_all().is_empty(), "no automatic wind or hazards")
		check_eq(a.boundary_edges().size(), 4, "four ledges")
		for edge in a.boundary_edges():
			check(not bool(edge["wall"]), "every edge is open")
		var validation := ArenaValidator.validate(a)
		check(bool(validation["ok"]), "%s: default markers remain valid: %s" % [sz, validation["errors"]])
		check(Schema.validate_named(m.to_dict(), "arena").is_empty(), "export schema accepts canvas size")
	check_eq(ArenaDef.clamp_size(m.base_def(), Vector2(100, 1)), Vector2(64, 12), "dimensions have independent safety bounds")
	check_eq(ArenaDef.clamp_size(m.base_def(), Vector2(30.24, 18.26)), Vector2(30, 18.5), "half-metre sizing")

func test_saved_canvas_and_exported_package_are_playable() -> void:
	var m := _model()
	m.id = "user:canvas_roundtrip"
	m.name = "Canvas Roundtrip"
	m.size = Vector2(64, 24)
	m.insert_item(m.make_item("prop_crate", Vector3(29, 0, 7)))
	check(bool(ArenaValidator.validate(m.to_arena())["ok"]), "normal editor props usable near outer boundary")
	var dir := temp_dir("canvas_saved")
	var saved := ArenaLibrary.save_layout(m.to_dict(), "", dir)
	if not check(bool(saved["ok"]), "saved: %s" % saved):
		return
	var a := ArenaLibrary.resolve(m.id, dir)
	check(a != null, "saved canvas resolves for normal matches")
	check_eq(a.size, m.size, "rectangle preserved")
	check_eq(a.props.size(), 1, "placed object preserved")
	var found := false
	for entry in ArenaLibrary.playable_arenas(dir):
		if str(entry["id"]) == m.id:
			found = true
	check(found, "only the saved custom variant becomes playable")
	var zip := dir.path_join("canvas.zip")
	var ex := ArenaPackage.export_package([m.to_dict()], zip, {"id": "canvas_pack", "name": "Canvas Pack"})
	if not check(bool(ex["ok"]), "export: %s" % ex.get("error", "")):
		return
	var im := ArenaPackage.import_package(zip, temp_dir("canvas_imported"))
	if not check(bool(im["ok"]), "import: %s" % str(im.get("errors", []))):
		return
	var imported := ArenaDef.from_dict(im["arenas"][0])
	check_eq(imported.content_hash(), a.content_hash(), "geometry, markers and props survive package round trip")
	ArenaCatalog.reload()
	check_eq(ArenaLibrary.resolve(m.id, dir).size, m.size, "template base resolves after catalog reload")

func test_resize_undo_preserves_props_and_reports_outside_items() -> void:
	var m := _model()
	m.size = Vector2(64, 24)
	m.insert_item(m.make_item("prop_crate", Vector3(28, 0, 7)))
	var stack := ArenaEditCommands.Stack.new(m)
	stack.execute(ArenaEditCommands.SetField.new("size", m.size, Vector2(12, 24), "Width"))
	var count := m.items.size()
	check(not bool(ArenaValidator.validate(m.to_arena())["ok"]), "shrinking reports the outside prop")
	stack.undo()
	check_eq(m.size, Vector2(64, 24), "undo restores only changed dimension")
	check_eq(m.items.size(), count, "resizing never destroys placed objects")
	check(bool(ArenaValidator.validate(m.to_arena())["ok"]), "undo restores valid layout")
	stack.redo()
	check_eq(m.size, Vector2(12, 24), "redo rectangle")

func test_floor_collision_and_ringout_switch() -> void:
	var m := _model()
	m.size = Vector2(64, 18)
	for enabled in [true, false]:
		var sim := MatchSim.new()
		sim.running = false
		fresh_world().add_child(sim)
		sim.setup({"arena": m.to_arena(), "rules": {"ringouts": enabled, "rounds": 1}, "fighters": [], "seed": 1})
		var nodes: Dictionary = sim.arena_nodes
		check_eq((nodes["walls"] as Array).size(), 0 if enabled else 4, "ringout switch preserves existing rule behavior")
		var floor_body: Node = nodes["floor"]
		check_eq(floor_body.get_child_count(), 1, "one flat rectangle, no extra hidden floor")
		var cs := floor_body.get_child(0) as CollisionShape3D
		check_eq((cs.shape as BoxShape3D).size, Vector3(64, 1, 18), "collision ends exactly at visible ledges")

func test_all_four_canvas_ledges_trigger_real_ringouts() -> void:
	for pos in [Vector3(0, 0, 10), Vector3(0, 0, -10), Vector3(17, 0, 0), Vector3(-17, 0, 0)]:
		var m := _model()
		m.size = Vector2(32, 18)
		var sim := MatchSim.new()
		sim.running = false
		fresh_world().add_child(sim)
		sim.setup({"arena": m.to_arena(), "rules": {"rounds": 1, "round_time": 0}, "seed": 8,
			"fighters": [{"creature": Content.creature("dev_biped"), "team": 0}, {"creature": Content.creature("dev_biped"), "team": 1}]})
		sim.mode.phase = MatchMode.Phase.FIGHT
		sim.input_enabled = true
		var f := sim.fighters[0]
		f.rig.place(pos, 0.0)
		await step_sim(sim, 1.5)
		check(f.state == Fighter.State.INACTIVE, "%s: actual falling fighter rings out" % pos)
		check_near(f.health, f.max_health * 0.92, 0.6, "existing ringout damage retained")
		await step_sim(sim, 2.7)
		check(f.state != Fighter.State.INACTIVE and m.to_arena().on_floor(f.pos(), 0), "returns safely to a canvas respawn marker")
		sim.queue_free()
		await wait_frames(1)

func test_editor_controls_resize_rectangle_and_reach_outer_coordinates() -> void:
	App.goto("arena_editor", {"layout": _model().to_dict()})
	await wait_frames(4)
	var scr = App.top_screen()
	var bases: Array = []
	for index in scr._base_opt.item_count:
		bases.append(scr._base_opt.get_item_metadata(index))
	check(bases.has("rooftop_canvas"), "canvas available in editor base selector")
	await _joy(JOY_BUTTON_BACK)
	check(not scr._canvas_active(), "Share switches to menu controls")
	var sliders := (scr._layout_box as Control).find_children("*", "HSlider", true, false)
	if not check_eq(sliders.size(), 2, "width and depth both exposed"):
		return
	var width := sliders[0] as HSlider
	width.grab_focus()
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	(sliders[1] as HSlider).grab_focus()
	await wait_frames(3)
	check_eq(scr.model.size, Vector2(32.5, 32), "controller changes width without changing depth")
	scr._on_size_changed(0, 64)
	scr._on_size_changed(1, 24)
	await wait_frames(4)
	var it: Dictionary = scr.model.make_item("prop_crate", Vector3(29, 0, 7))
	scr.stack.execute(ArenaEditCommands.AddItems.new([it]))
	scr._select(int(it["uid"]))
	await wait_frames(3)
	var spins := (scr._inspector as Control).find_children("*", "SpinBox", true, false)
	check((spins[0] as SpinBox).max_value >= 32.0, "inspector permits positions beyond old 20m limit")
	scr.vp.reset_camera()
	await wait_frames(3)
	check(float(scr.vp.dist) > 80.0, "large editor overview is not clamped to 40m")
	scr.vp.set_focus(Vector3(29, 0, 7), true)
	check_eq(scr.vp.focus, Vector3(29, 0, 7), "outer stage remains accessible")
	scr._test_play("watch")
	await wait_frames(4)
	if check(App.current_scene is MatchScene, "canvas can start a real test match"):
		var scene := App.current_scene as MatchScene
		check_eq(scene.sim.arena.size, Vector2(64, 24), "test play uses the resized rectangle")
		check(scene.camera.open_stage, "real match enables unrestricted canvas framing")
		ArenaTestPlay.return_to_editor()
		await wait_frames(4)
		check_eq(App.top_screen().model.size, Vector2(64, 24), "test-play return preserves canvas")


func test_large_canvas_fight_camera_frames_separated_fighters() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.own_world_3d = true
	add_child(sv)
	var cam := FightCamera.new()
	cam.arena_radius = 32.0
	cam.open_stage = true
	cam.shake_scale = 0.0
	cam.points_provider = _points
	sv.add_child(cam)
	for half in [5.0, 12.0, 14.5, 29.0]:
		_camera_points = [Vector3(-half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half), Vector3(half, 0, -half)]
		for angle in [0.0, PI * 0.25, PI * 0.5]:
			cam.yaw = angle
			cam.snap()
			for p: Vector3 in _camera_points:
				check(not cam.is_position_behind(p), "fighter in front of broadcast camera")
				var pixel := cam.unproject_position(p + Vector3.UP)
				check(Rect2(30, 30, 1220, 660).has_point(pixel), "fighters fit at size %s, angle %s: %s" % [half * 2, angle, pixel])

func test_canvas_dressing_keeps_the_platform_clear() -> void:
	var view := ArenaView.new()
	add_child(view)
	view.build(_model().to_arena())
	check(view.find_children("NeonSign", "", true, false).is_empty(), "canvas has no elevated sign blocking a ledge")
	check((view._out["flags"] as Array).is_empty(), "no wind poles on blank edges")
	check((view._out["pigeons"] as Array).is_empty(), "no floating pigeons where HVAC used to be")
	check_eq(view.arena.style, "rooftop", "existing city, bay, sky and rooftop finish retained")

func test_canvas_uses_rooftop_audio_and_rectangular_policy_boundary() -> void:
	var audio: Node = Audio.get_script().new()
	add_child(audio)
	# Headless startup deliberately omits players; supply the two ambience players
	# before exercising the real set_arena path with the silent headless driver.
	audio.enabled = true
	audio._ambience = audio._make_2d("Ambience")
	audio._ambience_next = audio._make_2d("Ambience")
	audio.set_arena("user:totally_unrelated_name", "rooftop_canvas")
	var bus := AudioServer.get_bus_index("Crowd")
	var reverb := AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
	check_near(reverb.room_size, 0.2, 0.001, "saved canvas uses the outdoor rooftop acoustic profile")
	var m := _model()
	m.size = Vector2(64, 12)
	var a := m.to_arena()
	check_near(PolicyObs._ray_to_boundary(a, Vector3.ZERO, Vector3.FORWARD), 6.0, 0.001, "policy senses short edge rather than a 32m circle")
	check_near(PolicyObs._ray_to_boundary(a, Vector3.ZERO, Vector3.RIGHT), 32.0, 0.001, "policy senses long edge")
	check_near(PolicyObs._boundary_dist(a, Vector3(0, 0, 5)), 1.0, 0.001, "policy can recognise the nearby ledge")
	audio.set_arena("arena_gullet", "gullet")
	audio.queue_free()
