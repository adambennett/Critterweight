extends CampaignTestCase
var old_profile := {}
var old_root := ""

func before_each() -> void:
	old_profile = Profiles.current
	old_root = Paths.root
	Paths.root = temp_dir("playtest_%d" % Time.get_ticks_usec())
	Profiles.current = Profiles.default_profile("playtest", "Rookie")
	if OS.get_cmdline_user_args().has("--playtest-720") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))

func after_each() -> void:
	App.clear_screens()
	App.set_scene(null)
	Profiles.current = old_profile
	Paths.root = old_root
	super.after_each()

func test_campaign_flow_survives_its_map_and_resumes_reward() -> void:
	var flow := CampaignFlow.start(cat(), run_cfg())
	flow.ctrl.choose_node(str(flow.ctrl.available_nodes()[0]), "p0")
	var result := fake_result(flow.ctrl)
	flow.launch_fight()
	var ref: WeakRef = weakref(flow)
	flow = null
	await wait_frames(4)
	check(ref.get_ref() != null, "presented match owns the flow after the map is freed")
	var scene: MatchScene = App.current_scene
	scene.match_finished.emit(result)
	await wait_frames(4)
	check(App.top_screen() != null and App.top_screen().screen_name == "reward", "winning opens the reward instead of generic results")
	var saved := RunStore.new().load_slot(CampaignFlow.profile_key(), "off_the_street", cat())
	check(bool(saved.get("ok", false)), "completed fight is saved")
	if saved.get("ok", false):
		var resumed := CampaignFlow.resume(cat(), saved["state"])
		check_eq(resumed.current_screen(), "reward", "resume preserves the pending reward")

func test_campaign_lobby_back_pops_without_recursing() -> void:
	App.goto("main_menu")
	App.push("campaign_menu")
	await wait_frames(3)
	App.back()
	await wait_frames(2)
	check_eq(App.top_screen().screen_name, "main_menu", "ESC leaves the campaign lobby")

func test_suspended_run_is_reachable_from_bookie_with_dpad() -> void:
	var flow := CampaignFlow.start(cat(), run_cfg())
	flow.save()
	var screen := App.goto("campaign_menu")
	await wait_frames(6)
	var right: Array = screen.get("_right_buttons")
	var bookie: Control = right[0]
	bookie.grab_focus()
	var up := InputEventAction.new()
	up.action = "ui_up"
	up.pressed = true
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await wait_frames(2)
	var focused := get_viewport().gui_get_focus_owner()
	check(focused != null and (screen.get("_runs_box") as Control).is_ancestor_of(focused), "Up from Bookie enters suspended run controls")
	up.pressed = false
	Input.parse_input_event(up)
	var start: Control = screen.get("_start")
	check(start.get_node(start.focus_neighbor_right) is Button, "Start bridges to the suspended run buttons")

func test_bookie_default_setup_reaches_a_visible_live_fight() -> void:
	var screen := App.goto("bookie")
	await wait_frames(3)
	screen.call("_start_table")
	var table := App.get_node("BookieTable") as BookieTable
	table.think_delay = 0.0
	var flow: BookieFlow = table.get_meta("bookie_flow")
	var deadline := Time.get_ticks_msec() + 5000
	while not table.in_fight and Time.get_ticks_msec() < deadline:
		await wait_frames(1)
	await wait_frames(5)
	check(table.in_fight, "default table starts a fight")
	check(App.current_scene is MatchScene, "actual 3D match remains installed")
	check(bool(App.top_screen().get("overlay")), "only the slim controls cover the fight")
	if App.current_scene is MatchScene:
		var scene: MatchScene = App.current_scene
		var before := scene.sim.time
		await wait_physics(20)
		check(scene.sim.time > before, "AI bout keeps advancing while its overlay is open")
		flow.set_watching(false)
		await wait_frames(4)
		check(App.current_scene == scene and not scene.visible, "skipping retains the same fight")
		check(Engine.time_scale >= 8.0, "skip advances at 8x")
		flow.set_watching(true)
		await wait_frames(4)
		check(App.current_scene == scene and scene.visible, "watch returns immediately to that same fight")
		check_near(Engine.time_scale, table.speed, 0.01, "watch restores selected speed")
		table.set_camera("free")
		await wait_frames(4)
		var overlay := App.top_screen()
		var focus := get_viewport().gui_get_focus_owner()
		check(focus != null and bool(focus.get_meta("owns_sticks", false)), "free view owns navigation input")
		var camera_pos := scene.camera.free_pos
		Input.action_press("move_up")
		Input.action_press("dodge")
		scene.camera._free_cam(0.2)
		Input.action_release("move_up")
		Input.action_release("dodge")
		check(scene.camera.free_pos.distance_to(camera_pos) > 0.5, "Bookie free camera flies while the AI keeps fighting")
		var view := InputEventJoypadButton.new()
		view.button_index = JOY_BUTTON_BACK
		view.pressed = true
		Input.parse_input_event(view)
		Input.flush_buffered_events()
		await wait_frames(3)
		check(not bool(overlay.get_meta("free_camera_input", true)), "View gives the stick back to the table controls")
		check(get_viewport().gui_get_focus_owner() is Button, "table controls are reachable while in free camera mode")
		view.pressed = false
		Input.parse_input_event(view)
		table.set_camera("broadcast")
		await wait_frames(4)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(Paths.dir("captures").path_join("v0912-bookie.png"))
	table.stop()
	flow.abort_fight()
	var frames := 0
	while table.running and frames < 240:
		frames += 1
		await wait_frames(1)
	table.name = "BookieDone"
	table.queue_free()
