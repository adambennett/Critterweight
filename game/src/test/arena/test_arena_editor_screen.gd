extends TestCase
## ARN-02/03: the arena editor screen is fully operable with a controller (simulated joypad
## events through Input.parse_input_event: palette tabs/items, A place/select/carry, Y rotate,
## X delete, B cancel/back, Start menu, D-pad nudge) and with mouse/keyboard (click-select,
## drag-move with undo, Ctrl+Z/Ctrl+Y, Del, R); the test-play loop starts a real match and
## returns to the editor with the layout and undo history intact.
## (Physical controller hardware is not available here; events are injected at the engine level.)


func _open(params := {}) -> Control:
	App.goto("arena_editor", params)
	await wait_frames(3)
	return App.top_screen()


func _joy(button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventJoypadButton.new()
	up.device = 0
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await wait_frames(2)


func _key(code: int, ctrl := false, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await wait_frames(2)


func after_each() -> void:
	App.clear_screens()
	App.set_scene(null)


func test_controller_place_rotate_delete_undo() -> void:
	var scr = await _open({"example": "layout_gullet_classic"})
	check(scr != null and scr.screen_name == "arena_editor", "editor screen open")
	if scr == null:
		return
	scr.vp.grab_focus()
	await wait_frames(1)
	var n0: int = scr.model.items.size()
	await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	check_eq(int(scr.tab), 1, "RB -> next palette tab")
	await _joy(JOY_BUTTON_LEFT_SHOULDER)
	await _joy(JOY_BUTTON_LEFT_SHOULDER)
	check_eq(int(scr.tab), 4, "LB wraps to the markers tab")
	await _joy(JOY_BUTTON_RIGHT_SHOULDER)
	check_eq(int(scr.tab), 0, "RB wraps back to obstacles")
	await _joy(JOY_BUTTON_DPAD_DOWN)
	check(str(scr.armed) != "", "D-pad with nothing selected arms a palette item (%s)" % scr.armed)
	scr._move_cursor(Vector3(2.0, 0, 1.0), true)
	await _joy(JOY_BUTTON_A)
	check_eq(scr.model.items.size(), n0 + 1, "A places the armed item at the cursor")
	var uid: int = scr.selected
	check(uid >= 0, "the new item is selected")
	var yaw0 := float(scr.model.get_item(uid)["yaw"])
	await _joy(JOY_BUTTON_Y)
	check_near(float(scr.model.get_item(uid)["yaw"]) - yaw0, deg_to_rad(15.0), 0.001, "Y rotates 15 degrees")
	var p0: Vector3 = scr.model.get_item(uid)["pos"]
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	var p1: Vector3 = scr.model.get_item(uid)["pos"]
	check(p0.distance_to(p1) > 0.4, "D-pad nudges the selection one grid step")
	await _joy(JOY_BUTTON_X)
	check_eq(scr.model.items.size(), n0, "X deletes the selection")
	await _key(KEY_Z, true)
	check_eq(scr.model.items.size(), n0 + 1, "Ctrl+Z restores it")
	await _key(KEY_Y, true)
	check_eq(scr.model.items.size(), n0, "Ctrl+Y deletes it again")
	# B peels back state: disarm, then the menu
	await _joy(JOY_BUTTON_B)
	check_eq(str(scr.armed), "", "B disarms the palette tool")
	await _joy(JOY_BUTTON_B)
	check(scr._overlay != null, "B with nothing to cancel opens the editor menu (never exits silently)")
	await _joy(JOY_BUTTON_START)
	check(scr._overlay == null, "Start closes the menu")
	await _joy(JOY_BUTTON_START)
	check(scr._overlay != null, "Start opens the menu")
	await _joy(JOY_BUTTON_B)
	check(scr._overlay == null, "B closes the menu")


func test_controller_carry_moves_items() -> void:
	var scr = await _open({"example": "layout_crusher_king"})
	scr.vp.grab_focus()
	await wait_frames(1)
	var bat := -1
	for it in scr.model.items:
		if str(it["type"]) == "prop_battery":
			bat = int(it["uid"])
			break
	var start: Vector3 = scr.model.get_item(bat)["pos"]
	scr._move_cursor(start, false)
	await _joy(JOY_BUTTON_A)
	check_eq(int(scr.selected), bat, "A on an item selects it")
	await _joy(JOY_BUTTON_A)
	check(bool(scr.carrying), "A on the selection picks it up")
	scr._move_cursor(start + Vector3(1.5, 0, -1.0), false)
	await _joy(JOY_BUTTON_A)
	check(not bool(scr.carrying), "A drops it")
	var moved: Vector3 = scr.model.get_item(bat)["pos"]
	check(moved.distance_to(start + Vector3(1.5, 0, -1.0)) < 0.3, "item followed the cursor (%s)" % moved)
	await _key(KEY_Z, true)
	check(Vector3(scr.model.get_item(bat)["pos"]).distance_to(start) < 0.01, "carry is one undo step")


func test_mouse_select_drag_and_keyboard() -> void:
	var scr = await _open({"example": "layout_rooftop_gauntlet"})
	var crate := -1
	for it in scr.model.items:
		if str(it["type"]) == "prop_heavy_crate":
			crate = int(it["uid"])
	var start: Vector3 = scr.model.get_item(crate)["pos"]
	scr.vp.pointer_pressed.emit(start + Vector3(0.2, 0, 0.1), MOUSE_BUTTON_LEFT, false, false)
	check_eq(int(scr.selected), crate, "click selects")
	scr.vp.pointer_moved.emit(start + Vector3(-1.0, 0, 1.1))
	scr.vp.pointer_moved.emit(start + Vector3(-2.0, 0, 2.1))
	scr.vp.pointer_released.emit(start + Vector3(-2.0, 0, 2.1), MOUSE_BUTTON_LEFT)
	var moved: Vector3 = scr.model.get_item(crate)["pos"]
	var target := start + Vector3(-2.2, 0, 2.0)   # pointer target + grab offset (-0.2, -0.1)
	check(moved.distance_to(target) <= 0.36, "drag follows the pointer (%s vs %s)" % [moved, target])
	check(is_zero_approx(fmod(absf(moved.x), 0.5)) and is_zero_approx(fmod(absf(moved.z), 0.5)), "and lands on the 0.5 m grid (%s)" % moved)
	await _key(KEY_R)
	check_near(float(scr.model.get_item(crate)["yaw"]), deg_to_rad(15.0), 0.001, "R rotates")
	await _key(KEY_Z, true)
	await _key(KEY_Z, true)
	check(Vector3(scr.model.get_item(crate)["pos"]).distance_to(start) < 0.01, "drag undone in one step")
	scr.vp.grab_focus()
	await _key(KEY_DELETE)
	check_eq(scr.model.index_of(crate), -1, "Del deletes")
	# clicking an issue selects the offending item
	var it2: Dictionary = scr.model.make_item("prop_heavy_crate", Vector3(40, 0, 0))
	scr.stack.execute(ArenaEditCommands.AddItems.new([it2]))
	await wait_frames(3)
	var issue := {}
	for e in scr.validation["errors"]:
		if int(e["ref"].get("uid", -1)) == int(it2["uid"]):
			issue = e
	check(not issue.is_empty(), "live validation reports the stray crate")
	scr._on_issue_pressed(issue)
	check_eq(int(scr.selected), int(it2["uid"]), "clicking the error selects the culprit")


func test_test_play_round_trip_restores_session() -> void:
	var scr = await _open({"example": "layout_drydock_pitch"})
	var it: Dictionary = scr.model.make_item("prop_bollard", Vector3(0, 0, -3))
	scr.stack.execute(ArenaEditCommands.AddItems.new([it]))
	var count: int = scr.model.items.size()
	scr._test_play("watch")
	await wait_frames(3)
	check(App.current_scene is MatchScene, "test play runs a real match")
	var ms: MatchScene = App.current_scene
	check_eq(ms.sim.arena.props.size(), 9, "the match uses the edited layout (8 example props + the new bollard)")
	check(ms.find_children("*", "ArenaTestPlay", true, false).size() == 1, "return overlay present")
	ArenaTestPlay.return_to_editor()
	await wait_frames(4)
	var back = App.top_screen()
	check(back != null and back.screen_name == "arena_editor", "back in the editor")
	check_eq(back.model.items.size(), count, "layout restored")
	check(back.stack.can_undo(), "undo history survived test play")
	back.stack.undo()
	check_eq(back.model.items.size(), count - 1, "and still works")


## docs/UI.md layout rules for the editor (UI-10): at 1280x800 (Steam Deck) and 1920x1080 the
## footer prompt bar stays on screen, the 3D canvas keeps a usable size, and every visible label,
## button and the palette list render at >= 18 px. The headless root window is resized, so this
## measures real layout.
func test_layout_fits_and_text_is_readable() -> void:
	var scr = await _open({"example": "layout_glandco_showcase"})
	var root := get_tree().root
	var old := root.size
	for res in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = res
		await wait_frames(4)
		var vr := get_viewport().get_visible_rect()
		var px_per_du := get_viewport().get_final_transform().get_scale().y
		var tag := "%dx%d" % [res.x, res.y]
		var bars: Array = scr.find_children("*", "PromptBar", true, false)
		bars.append_array(scr.find_children("*", "FlowPromptBar", true, false))
		check(bars.size() >= 1, "%s: the editor has a prompt bar" % tag)
		for b in bars:
			var r := (b as Control).get_global_rect()
			check(r.end.y <= vr.end.y + 1.0 and r.end.x <= vr.end.x + 1.0, "%s: prompts on screen (%s in %s)" % [tag, str(r), str(vr.size)])
		var vpr: Rect2 = (scr.vp as Control).get_global_rect()
		check(vpr.size.x * px_per_du >= 500.0 and vpr.size.y * px_per_du >= 300.0, "%s: canvas stays usable (%s px)" % [tag, str(vpr.size * px_per_du)])
		var smallest := 999.0
		var which := ""
		for n in scr.find_children("*", "", true, false):
			var size_du := 0
			var text := ""
			if n is Label and (n as Label).is_visible_in_tree():
				text = (n as Label).text
				size_du = (n as Label).get_theme_font_size("font_size")
			elif n is Button and (n as Button).is_visible_in_tree():
				text = (n as Button).text
				size_du = (n as Button).get_theme_font_size("font_size")
			elif n is ItemList and (n as ItemList).is_visible_in_tree():
				text = "palette"
				size_du = (n as ItemList).get_theme_font_size("font_size")
			if text.strip_edges() == "":
				continue
			if size_du * px_per_du < smallest:
				smallest = size_du * px_per_du
				which = text
		check(smallest >= 18.0 - 0.01, "%s: smallest text '%s' is %.1f px (>= 18)" % [tag, which.substr(0, 30), smallest])
	root.size = old
	await wait_frames(2)
