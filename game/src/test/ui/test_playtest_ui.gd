extends TestCase
var saved := {}

func before_each() -> void:
	saved = Settings.values.duplicate(true)
	Settings.values["access.reduce_motion"] = true
	Settings.values["gameplay.pause_on_focus_loss"] = false
	if OS.get_cmdline_user_args().has("--playtest-720") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))

func after_each() -> void:
	App.clear_screens()
	App.set_scene(null)
	Settings.values = saved
	Controls.last_device = "keyboard"
	MatchFlow.set_paused(false)

func capture(label_: String) -> void:
	await wait_frames(10)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(Paths.dir("captures").path_join("v0912-" + label_ + ".png"))

func fits(control: Control, label_: String) -> void:
	var screen := get_viewport().get_visible_rect().grow(2)
	check(screen.encloses(control.get_global_rect()), "%s fits screen: %s within %s" % [label_, control.get_global_rect(), screen])

func test_main_menu_has_no_scroll_and_keeps_submenu() -> void:
	var s := App.goto("main_menu")
	await wait_frames(4)
	check_eq(s.find_children("*", "ScrollContainer", true, false).size(), 0, "main navigation needs no scrollbar")
	s.call("_open_sub", 1)
	await wait_frames(4)
	var items: Array = s.get("_items")
	items[3].grab_focus()
	await wait_frames(4)
	var sub: Control = s.get("_sub_panel")
	check(sub.visible, "mouse/focus passing another category keeps submenu open")
	fits(sub, "submenu")
	for b: Control in items:
		fits(b, "main option")
	await capture("main-menu")

func test_dialog_options_fit_and_are_reachable() -> void:
	App.goto("main_menu")
	var choices := []
	for mode in ["Standard", "Spotlight Hog", "Chumball", "Absolute Unit", "Chum Rush", "Tag Team", "Practice", "Cancel"]:
		choices.append({"label": mode, "id": mode})
	App.dialog("New rules", "Pick a mode to start from. You can change everything afterwards.", choices)
	await wait_frames(4)
	var s := App.top_screen()
	for b: Control in s.get("_buttons"):
		fits(b, "dialog option")
		b.grab_focus()
		check(b.has_focus(), "every mode is focusable")
	await capture("new-rules")

func test_compendium_roster_models_and_all_sections() -> void:
	var s := App.goto("compendium")
	await wait_frames(5)
	check(s != null, "compendium registered")
	if s == null:
		return
	var rows: Array = s.get("rows")
	check(rows.size() >= Content.playable_creatures().size(), "every playable fighter plus NPCs")
	for i in rows.size():
		s.call("_select_entry", i)
		await wait_frames(1)
		var preview: FighterPreview = s.get("preview")
		check(preview.model != null and preview.creature_id == str(rows[i]["id"]), "loaded model for %s" % rows[i]["id"])
	s.call("_select_entry", 0)
	await capture("compendium-fighter")
	for i in range(1, 6):
		s.call("_select_section", i)
		await wait_frames(3)
		check(not (s.get("rows") as Array).is_empty(), "section %d has documentation" % i)
		fits(s.get("details"), "compendium details")
		if i == 1:
			await capture("compendium-elements")
	var back := InputEventAction.new()
	back.action = "ui_cancel"
	back.pressed = true
	Input.parse_input_event(back)
	Input.flush_buffered_events()
	await wait_frames(3)
	check_eq(App.top_screen().screen_name, "main_menu", "Back leaves the Compendium")
	back.pressed = false
	Input.parse_input_event(back)

func test_editor_lock_and_device_layout() -> void:
	var s := App.goto("arena_editor")
	await wait_frames(12)
	var vp: Control = s.get("vp")
	vp.grab_focus()
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_LEFT_X
	ev.axis_value = 0.9
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await wait_frames(4)
	check(vp.has_focus(), "left stick stays locked to canvas")
	ev.axis_value = 0
	Input.parse_input_event(ev)
	for device in ["gamepad", "keyboard", "gamepad"]:
		Controls.last_device = device
		Controls.device_changed.emit(device)
		await wait_frames(5)
		fits(s.get("_details_panel"), "editor details after device switch")
		fits(s.get("_prompts"), "editor hints")
	s.call("_toggle_panel", s.get("_palette_panel"))
	s.call("_toggle_panel", s.get("_details_panel"))
	await wait_frames(4)
	check(vp.has_focus(), "hiding panels keeps focus in map")
	await capture("editor-map")
	s.call("_toggle_panel", s.get("_palette_panel"))
	s.call("_toggle_panel", s.get("_details_panel"))
	await capture("editor-panels")

func test_scroll_reveals_last_button_and_text_panel_scrolls() -> void:
	var s := App.goto("main_menu")
	var scroll := FocusScroll.new()
	s.add_child(scroll)
	scroll.position = Vector2(800, 200)
	scroll.size = Vector2(500, 300)
	var last: Button
	for i in 12:
		last = UiButton.new("Row %d" % i)
		scroll.content.add_child(last)
	await wait_frames(4)
	last.grab_focus()
	await wait_frames(8)
	check(last.get_global_rect().end.y + 8 <= scroll.get_global_rect().end.y, "focus outline has bottom clearance")
	var text := ScrollText.new()
	s.add_child(text)
	text.position = Vector2(800, 520)
	text.size = Vector2(500, 200)
	text.set_bbcode("Long text line\n".repeat(80))
	await wait_frames(4)
	text.grab_focus()
	UiNav.ensure().scroll_focused(300)
	check(text.scroll.scroll_vertical > 0, "shared right-stick scrolling reaches text")

func test_cannery_boards_fit_and_lessons_reveal_the_final_button() -> void:
	App.goto("main_menu")
	for kind in ["drill", "shop", "lessons"]:
		var board := App.push("hub_board", {"kind": kind}) as HubBoard
		await wait_frames(6)
		fits(board.panel, "%s board" % kind)
		check(board.help.size.y > 120, "%s details have room for readable text" % kind)
		var description: Label = board.help.get("_body")
		check(description.visible and description.text != "", "%s focused choice has a description" % kind)
		var buttons := board.list.focusables()
		if kind == "drill":
			check_eq(buttons.size(), 3, "all three cannon difficulties are offered")
		if kind == "lessons":
			var last := buttons.back() as Control
			last.grab_focus()
			await wait_frames(8)
			check(last.get_global_rect().end.y + 8 <= board.list.get_global_rect().end.y, "last Cannery lesson has visible bottom focus outline")
		await capture("cannery-" + kind)
		App.pop()
		await wait_frames(2)
	var tutorial := App.goto("tutorial_menu")
	await wait_frames(6)
	var lessons: FocusScroll = tutorial.get("_scroll")
	var practice := lessons.focusables().back() as UiButton
	check_eq(practice.route, "practice", "the final tutorial option is Practice instead")
	practice.grab_focus()
	await wait_frames(8)
	check(practice.get_global_rect().end.y + 8 <= lessons.get_global_rect().end.y, "Practice instead has visible bottom focus outline")
	await capture("tutorial-bottom")

func test_resolution_dropdown_and_fps_toggle() -> void:
	var s := App.goto("settings")
	await wait_frames(5)
	var dropdown: DropdownRow
	for control in s.find_children("*", "Control", true, false):
		if control is DropdownRow:
			dropdown = control
	check(dropdown != null, "resolution is a dropdown")
	if dropdown:
		check(dropdown.options.size() > 5, "resolution choices populated")
		var before = Settings.get_value("display.resolution")
		dropdown.picker.select(dropdown.options.size() - 1)
		check_eq(Settings.get_value("display.resolution"), before, "browsing does not apply modes")
	Settings.values["diag.show_fps"] = true
	await wait_frames(2)
	check(UiNav.ensure().fps_label.visible, "FPS shown globally")
	Settings.values["diag.show_fps"] = false
	await wait_frames(2)
	check(not UiNav.ensure().fps_label.visible, "FPS hides immediately")
	await capture("settings")

func test_dropdown_keeps_music_and_rapid_ambience_switches_settle() -> void:
	if not Audio.enabled:
		skip("Requires the graphical audio backend")
		return
	var s := App.goto("lab")
	await wait_frames(12)
	var pickers := s.find_children("*", "OptionButton", true, false)
	check(not pickers.is_empty(), "AI Lab has a dropdown")
	if pickers.is_empty():
		return
	# This checks transfer within a foreground application. A hidden/background test launch
	# must establish that precondition: muting while another application owns focus is correct.
	var main_window := get_window()
	main_window.grab_focus()
	var focus_deadline := Time.get_ticks_msec() + 2000
	while not DisplayServer.window_is_focused(main_window.get_window_id()) and Time.get_ticks_msec() < focus_deadline:
		await wait_frames(1)
	if not check(DisplayServer.window_is_focused(main_window.get_window_id()), "the game has native focus before opening its dropdown"):
		return
	Settings.values["audio.mute_in_background"] = true
	var picker := pickers[0] as OptionButton
	picker.show_popup()
	picker.get_popup().grab_focus()
	await wait_frames(10)
	check(picker.get_popup().visible, "the actual native popup is open")
	check(Settings.application_focused(), "a game popup counts as application focus")
	Settings._apply_focus_audio()
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "opening a dropdown does not mute the master bus")
	picker.get_popup().hide()
	Audio.ambience("amb_hub_main", 0.04)
	Audio.ambience("amb_hub_juice_bar", 0.04)
	Audio.ambience("amb_hub_office", 0.04)
	await get_tree().create_timer(0.12, true, false, true).timeout
	check(Audio._ambience.playing and not Audio._ambience_next.playing, "only the latest ambience survives rapid room changes")
	Audio.ambience("", 0.04)
	await get_tree().create_timer(0.12, true, false, true).timeout
	check(not Audio._ambience.playing and not Audio._ambience_next.playing, "stopping ambience silences both players")
