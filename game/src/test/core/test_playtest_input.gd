extends TestCase

func after_each() -> void:
	Input.action_release("ability2")
	Input.action_release("move_up")
	Input.action_release("dodge")
	App.clear_screens()
	App.set_scene(null)
	SimSpeed.restore()

func test_right_bumper_starts_ability_two_for_every_roster_fighter() -> void:
	App.clear_screens()
	for id in ["f_stoke", "f_dredge", "f_dozer", "f_gusto", "f_slurry", "f_jitters"]:
		var source := LocalPlayerInput.new()
		var sim := make_sim("", {"mode": "practice", "round_time": 0, "intro_time": 0}, [{"creature": id, "team": 0, "source": source}, {"creature": "dev_biped", "team": 1}])
		await step_sim(sim, 0.2)
		var f: Fighter = sim.fighters[0]
		var event := InputEventJoypadButton.new()
		event.button_index = JOY_BUTTON_RIGHT_SHOULDER
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		source.poll(f, sim, 1.0 / 120)
		check(f.input.is_held(FighterInput.AB2), "%s maps RB to ability 2" % id)
		await step_sim(sim, 0.1)
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		check(float(f.cooldown_left.get("ability2", 0)) > 0, "%s actually spends ability 2's charge" % id)
		var uses := sim.events_since(0).filter(func(e): return e.get("type") == "ability" and e.get("slot") == "ability2")
		check(not uses.is_empty(), "%s emits an ability activation" % id)
		sim.get_parent().queue_free()
		await wait_frames(2)

func test_spectator_has_follow_locked_and_free_flight() -> void:
	var scene := MatchFlow.launch({"arena": Content.arena("the_gullet"), "rules": {"mode": "practice", "round_time": 0}, "spectate": true, "fighters": [{"creature": "f_dozer", "team": 0, "kind": "bot"}, {"creature": "f_stoke", "team": 1, "kind": "bot"}]})
	await wait_frames(3)
	var overlay := scene.find_child("SpectatorOverlay", true, false) as SpectatorOverlay
	check(overlay != null, "spectator overlay created")
	if overlay == null:
		return
	overlay.toggle_camera()
	check(scene.director.locked >= 0, "first press locks a fighter")
	overlay.toggle_camera()
	check_eq(scene.camera.mode, FightCamera.Mode.FREE, "second press enters free flight")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(Paths.dir("captures").path_join("v0912-spectator-free.png"))
	var start := scene.camera.free_pos
	Input.action_press("move_up")
	Input.action_press("dodge")
	scene.camera._free_cam(0.2)
	Input.action_release("move_up")
	Input.action_release("dodge")
	check(scene.camera.free_pos.y > start.y, "free camera can rise")
	check(Vector2(scene.camera.free_pos.x - start.x, scene.camera.free_pos.z - start.z).length() > 0.5, "free camera translates around arena")
	overlay.toggle_camera()
	check_eq(scene.camera.mode, FightCamera.Mode.SPECTATE, "third press returns to director")
	check_eq(scene.director.locked, -1, "follow releases fighter lock")
	var mode_ref: WeakRef = weakref(scene.sim.mode)
	App.set_scene(null)
	await wait_frames(3)
	check(mode_ref.get_ref() == null, "leaving practice releases its dummy source and mode")

func test_small_team_hud_leaves_no_orphan_containers() -> void:
	await wait_frames(3)
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for count in [3, 4]:
		var fighters := []
		for i in count:
			fighters.append({"creature": "f_dozer", "team": i, "kind": "bot"})
		App.start_match({"arena": "the_gullet", "rules": {"round_time": 30}, "fighters": fighters})
		await wait_frames(3)
		App.set_scene(null)
		await wait_frames(3)
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= before, "three/four-fighter HUDs release even the unused top rows")

func test_legacy_you_name_is_a_rookie_until_renamed() -> void:
	check_eq(Profiles.player_name({"name": "You"}), "Rookie", "legacy default is addressed by a name")
	check_eq(Profiles.player_name({"name": "  Skipper  "}), "Skipper", "custom profile names appear in dialogue")
