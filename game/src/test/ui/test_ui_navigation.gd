extends TestCase
## End-to-end UI navigation tests (UI-01, UI-02, UI-03, UI-04, UI-06, UI-07, CMB-12).
## They drive the REAL screens through Input.parse_input_event with controller (joypad buttons and
## stick motion), keyboard and mouse events — widgets are never poked directly — and assert after
## every step that a visible control inside the top screen owns focus ("focus is never lost").
## Settings and bindings changed by a test are restored in after_each; still, prefer running with an
## isolated user folder:  godot --headless --path game -- --test ui --user-root <tmp dir>

var _saved_values := {}
var _saved_bindings := {}
var _steps := 0


func before_each() -> void:
	_saved_values = Settings.values.duplicate(true)
	_saved_bindings = Controls.current_bindings()
	MatchFlow.set_paused(false)
	App.clear_screens()


func after_each() -> void:
	UiNav.cancel_capture()
	MatchFlow.set_paused(false)
	App.clear_screens()
	if App.current_scene != null:
		App.set_scene(null)
	for k in _saved_values:
		Settings.values[k] = _saved_values[k]
	Settings.apply_all()
	Settings.save_settings()
	Controls.apply_bindings(_saved_bindings)
	Controls.last_device = "keyboard"


# --- input helpers (everything goes through the engine's input pipeline) ---------------------------

func wait_seconds(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func press_joy(button: JoyButton, settle := 2) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = true
	ev.pressure = 1.0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await wait_frames(1)
	var up := InputEventJoypadButton.new()
	up.device = 0
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await wait_frames(settle)


func press_key(code: Key, settle := 2) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await wait_frames(1)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await wait_frames(settle)


func stick(x: float, y: float) -> void:
	for a in [[JOY_AXIS_LEFT_X, x], [JOY_AXIS_LEFT_Y, y]]:
		var ev := InputEventJoypadMotion.new()
		ev.device = 0
		ev.axis = a[0]
		ev.axis_value = a[1]
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func top_name() -> String:
	var t := App.top_screen()
	return t.screen_name if t != null else "none"


## The core invariant: a visible control inside the top screen has focus.
func expect_focus(step: String) -> bool:
	_steps += 1
	var top := App.top_screen()
	var f := focus()
	var ok := top != null and f != null and is_instance_valid(f) and top.is_ancestor_of(f) and f.is_visible_in_tree()
	return check(ok, "focus lost after '%s' (top=%s, focus=%s)" % [step, top_name(), str(f.get_path()) if f != null else "none"])


## Presses `button` until pred(focus) holds, checking focus after every press.
func nav_until(pred: Callable, button: JoyButton = JOY_BUTTON_DPAD_DOWN, max_steps := 50) -> bool:
	for i in max_steps:
		var f := focus()
		if f != null and bool(pred.call(f)):
			return true
		await press_joy(button)
		expect_focus("navigate step %d" % i)
	var f2 := focus()
	return check(f2 != null and bool(pred.call(f2)), "navigation never reached its target")


func nav_to_slot(action: String, pad: bool) -> bool:
	var ok: bool = await nav_until(func(c: Control) -> bool: return c is BindSlot and (c as BindSlot).action == action)
	if not ok:
		return false
	var f := focus() as BindSlot
	if f.pad != pad:
		await press_joy(JOY_BUTTON_DPAD_RIGHT if pad else JOY_BUTTON_DPAD_LEFT)
	f = focus() as BindSlot
	return check(f != null and f.action == action and f.pad == pad, "reached the %s %s slot" % [action, "controller" if pad else "keyboard"])


func route_of(c: Control) -> String:
	return (c as UiButton).route if c is UiButton else ""


func kb_has(action: String, key: Key) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and ((ev as InputEventKey).physical_keycode == key or (ev as InputEventKey).keycode == key):
			return true
	return false


func kb_first(action: String) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		if ev is InputEventMouseButton:
			return -1
	return 0


func pad_has(action: String, button: JoyButton) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return true
	return false


func toast_contains(text: String) -> bool:
	if UiNav.instance == null:
		return false
	for e in UiNav.instance.toasts.history:
		if str((e as Dictionary)["text"]).contains(text):
			return true
	return false


func find_label_containing(root: Node, text: String) -> Label:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text.contains(text) and (l as Label).is_visible_in_tree():
			return l as Label
	return null


func open_main_menu() -> Screen:
	App.goto("main_menu")
	await wait_frames(4)
	return App.top_screen()


# --- tests -----------------------------------------------------------------------------------------

## Main menu -> settings: tab switching, change a value (persisted), restore default, rebind on
## keyboard and controller with a conflict, cancel a capture, reset one action, reset the tab via
## the confirmation dialog, display change with keep/revert countdown, back to the main menu and the
## quit dialog — all with the controller/keyboard, checking focus after every step.
func test_menu_settings_round_trip() -> void:
	await wait_frames(2)
	print("    viewport %s, window %s" % [get_viewport().get_visible_rect().size, get_tree().root.size])
	var mm: Screen = await open_main_menu()
	check_eq(top_name(), "main_menu", "main menu opens")
	expect_focus("open main menu")
	check_eq(route_of(focus()), "fight", "first entry focused")
	var ok: bool = await nav_until(func(c: Control) -> bool: return route_of(c) == "settings")
	check(ok, "Settings entry reachable with the D-pad")
	await press_joy(JOY_BUTTON_A, 4)
	check(mm.submenu_open(), "A opens the Settings category")
	check_eq(route_of(focus()), "settings", "Settings is the first category option")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "settings", "A opens Settings")
	expect_focus("open settings")
	check(not mm.visible, "the main menu is hidden under a full screen")
	var ss = App.top_screen()
	check_eq(str(ss.current_tab()), "display", "Settings start on Display")
	# LB/RB tabs
	await press_joy(JOY_BUTTON_RIGHT_SHOULDER)
	await press_joy(JOY_BUTTON_RIGHT_SHOULDER)
	check_eq(str(ss.current_tab()), "audio", "RB twice reaches Audio")
	expect_focus("RB to Audio")
	# change a value with the D-pad; it applies at once and persists after the debounce
	ok = await nav_until(func(c: Control) -> bool: return c is UiRow and (c as UiRow).key == "audio.music")
	check(ok, "Music row reachable")
	var before := int(Settings.get_value("audio.music"))
	var expected := mini(before + 5, 100)
	await press_joy(JOY_BUTTON_DPAD_RIGHT)
	check_eq(int(Settings.get_value("audio.music")), expected, "D-pad right raises Music by one step")
	expect_focus("adjust Music")
	await wait_seconds(0.7)
	var saved := Saves.read_json(Paths.file("profiles", Settings.FILE), "settings", Settings.VERSION)
	check(bool(saved["ok"]) and int((saved["data"] as Dictionary).get("audio.music", -1)) == expected, "the new value is saved to disk")
	await press_joy(JOY_BUTTON_X)
	check_eq(int(Settings.get_value("audio.music")), int(Settings.schema("audio.music")["def"]), "X restores the default")
	expect_focus("restore default")
	# keyboard rebinding: Light <- H, then Heavy <- H steals it (conflict notice)
	await press_joy(JOY_BUTTON_RIGHT_SHOULDER)
	check_eq(str(ss.current_tab()), "input", "RB reaches Controls")
	ok = await nav_to_slot("light", false)
	check(ok, "Light keyboard slot reachable")
	await press_key(KEY_ENTER)
	check(UiNav.capture_active(), "Enter starts a keyboard capture")
	await press_key(KEY_H)
	check(not UiNav.capture_active(), "a key press ends the capture")
	check(kb_has("light", KEY_H), "Light is bound to H")
	check_eq(kb_first("light"), int(KEY_H), "H became Light's primary key")
	expect_focus("rebind Light")
	ok = await nav_to_slot("heavy", false)
	await press_key(KEY_ENTER)
	await press_key(KEY_H)
	check(kb_has("heavy", KEY_H), "Heavy is bound to H")
	check(not kb_has("light", KEY_H), "H was removed from Light (one input, one action)")
	check(toast_contains("taken from"), "a conflict notice is shown")
	var light_row = ss.bind_row_for("light")
	check(light_row != null and str(light_row.note_text()) != "", "the Light row explains what happened")
	expect_focus("rebind Heavy (conflict)")
	# controller rebinding: Taunt <- Y, taken from Heavy
	ok = await nav_to_slot("taunt", true)
	check(ok, "Taunt controller slot reachable (left/right switches columns)")
	await press_joy(JOY_BUTTON_A)
	check(UiNav.capture_active(), "A starts a controller capture")
	await press_joy(JOY_BUTTON_Y)
	check(pad_has("taunt", JOY_BUTTON_Y), "Taunt is bound to Y")
	check(not pad_has("heavy", JOY_BUTTON_Y), "Y was taken from Heavy")
	check(not BindingsFlow.has_binding("heavy", true), "Heavy is now unbound on the controller (shown as Unbound)")
	expect_focus("rebind Taunt (controller)")
	# Esc cancels a capture and changes nothing
	await press_joy(JOY_BUTTON_DPAD_LEFT)
	await press_key(KEY_ENTER)
	await press_key(KEY_ESCAPE)
	check(not UiNav.capture_active(), "Esc cancels the capture")
	check(kb_has("taunt", KEY_T), "a cancelled capture keeps the old key")
	check_eq(top_name(), "settings", "Esc during a capture does not leave Settings")
	expect_focus("cancel capture")
	# X on a binding restores that action's defaults
	await press_joy(JOY_BUTTON_DPAD_RIGHT)
	await press_joy(JOY_BUTTON_X)
	check(pad_has("taunt", JOY_BUTTON_DPAD_UP), "X restores Taunt's default controller button")
	expect_focus("reset Taunt")
	# Y: reset the whole tab through the confirmation dialog
	await press_joy(JOY_BUTTON_Y, 4)
	check_eq(top_name(), "dialog", "Y asks before resetting the tab")
	expect_focus("reset dialog")
	check(ss.visible, "Settings stay visible (dimmed) under the dialog")
	var dlg := App.top_screen()
	check_eq(route_of(focus()), "cancel", "the dialog focuses the safe choice")
	await press_joy(JOY_BUTTON_DPAD_LEFT)
	check_eq(route_of(focus()), "reset", "left moves to Reset")
	await press_joy(JOY_BUTTON_DPAD_UP)
	check(App.top_screen() == dlg and dlg.is_ancestor_of(focus()), "up cannot leave the dialog")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "settings", "the dialog closes")
	check(BindingsFlow.is_default(), "every binding is back to its default")
	check(pad_has("heavy", JOY_BUTTON_Y), "Heavy has Y again")
	expect_focus("after tab reset")
	# Display: window mode change -> 15 s keep/revert countdown; B reverts
	for i in 3:
		await press_joy(JOY_BUTTON_LEFT_SHOULDER)
	check_eq(str(ss.current_tab()), "display", "LB returns to Display")
	ok = await nav_until(func(c: Control) -> bool: return c is UiRow and (c as UiRow).key == "display.window_mode", JOY_BUTTON_DPAD_UP)
	check(ok, "Window mode row reachable")
	var mode_before := str(Settings.get_value("display.window_mode"))
	await press_joy(JOY_BUTTON_DPAD_RIGHT, 4)
	check_eq(top_name(), "dialog", "a display change asks for confirmation")
	var cd = App.top_screen()
	check(float(cd.seconds_left()) > 13.0 and float(cd.seconds_left()) <= 15.0, "a 15 s countdown is running")
	check(str(Settings.get_value("display.window_mode")) != mode_before, "the new mode is applied tentatively")
	expect_focus("countdown dialog")
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(str(Settings.get_value("display.window_mode")), mode_before, "B reverts the display change")
	check_eq(top_name(), "settings", "back in Settings")
	var wm := focus()
	check(wm is UiRow and (wm as UiRow).key == "display.window_mode", "focus returns to the Window mode row")
	check_eq(str((ss.row_for("display.window_mode") as OptionRow).get_value()), mode_before, "the row shows the reverted value")
	# back to the main menu: focus returns to the entry we left from
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "main_menu", "B returns to the main menu")
	check_eq(route_of(focus()), "settings", "focus returns to the Settings entry")
	check(mm.visible, "the main menu is visible again")
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "main_menu", "B closes the Settings category")
	check(not mm.submenu_open(), "the category is closed")
	# B on the main menu asks before quitting; B again keeps playing
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "dialog", "B on the main menu asks to quit")
	check_eq(route_of(focus()), "stay", "the quit dialog focuses Stay")
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "main_menu", "B on the quit dialog stays in the game")
	check(not App.quitting, "the game did not quit")
	check_eq(route_of(focus()), "settings", "focus is back on Settings after the dialog")
	check(_steps >= 30, "walked %d focus checkpoints" % _steps)


## Stick flicks move exactly one entry (Godot alone would step once per motion event), holding
## repeats, arrows work, prompts switch glyph family instantly with the device, mouse hover focuses.
func test_stick_keyboard_mouse_and_prompts() -> void:
	await wait_frames(2)
	var mm = await open_main_menu()
	var items: Array[UiButton] = mm.items()
	var n := items.size()
	check(n >= 3, "main menu has entries")
	check(focus() == items[0], "first entry focused")
	var swallowed: int = UiNav.instance.stick_events_swallowed
	stick(0.0, 0.3)
	stick(0.0, 0.72)
	stick(0.0, 0.97)
	await wait_frames(3)
	stick(0.0, 0.0)
	await wait_frames(3)
	check(focus() == items[1], "one stick flick = one step")
	check(UiNav.instance.stick_events_swallowed > swallowed, "raw stick motion is kept away from GUI navigation")
	check_eq(Controls.last_device, "gamepad", "stick use switches the prompt device to the controller")
	expect_focus("stick flick")
	stick(0.0, 0.97)
	await wait_seconds(0.6)
	stick(0.0, 0.0)
	await wait_frames(3)
	var moved := posmod(items.find(focus()) - 1, n)
	check(moved >= 2, "holding the stick repeats (moved %d)" % moved)
	expect_focus("stick hold")
	# keyboard arrows; prompts follow the device instantly
	var prompts: Array = []
	for p in mm.find_children("*", "ButtonPrompt", true, false):
		if (p as ButtonPrompt).actions.has("ui_accept"):
			prompts.append(p)
	check(not prompts.is_empty(), "the menu shows an accept prompt")
	var bp := prompts[0] as ButtonPrompt
	check_eq(bp.current_style(), "xbox", "controller glyphs while using the stick")
	var at := items.find(focus())
	await press_key(KEY_DOWN)
	check_eq(items.find(focus()), posmod(at + 1, n), "Down arrow moves one entry")
	check_eq(Controls.last_device, "keyboard", "a key press switches to keyboard prompts")
	check_eq(bp.current_style(), "keyboard", "prompt glyphs switched to keyboard")
	await press_joy(JOY_BUTTON_DPAD_UP)
	check_eq(bp.current_style(), "xbox", "prompt glyphs switched back to the controller")
	var glyph: PromptGlyph = null
	for g in bp.find_children("*", "PromptGlyph", true, false):
		if not g.is_queued_for_deletion():
			glyph = g
	check(glyph != null and glyph.event is InputEventJoypadButton, "the accept prompt now shows a controller button")
	check_eq(bp.binding_text(), Controls.prompt_for("ui_accept"), "prompt text comes from Controls.prompt_for")
	Settings.set_value("input.prompts", "playstation", true, false)
	await wait_frames(2)
	check_eq(bp.current_style(), "playstation", "the Button prompts setting selects PlayStation glyphs")
	Settings.set_value("input.prompts", "auto", true, false)
	# mouse hover moves focus to the hovered entry
	var target := items[posmod(items.find(focus()) + 2, n)]
	var vp := get_tree().root
	vp.notification(Window.NOTIFICATION_WM_MOUSE_ENTER)
	var mev := InputEventMouseMotion.new()
	mev.position = vp.get_final_transform() * target.get_global_rect().get_center()
	mev.global_position = mev.position
	mev.relative = Vector2(12, 0)
	Input.parse_input_event(mev)
	Input.flush_buffered_events()
	await wait_frames(3)
	check(focus() == target, "hovering an entry focuses it")
	check_eq(Controls.last_device, "keyboard", "mouse movement switches to keyboard & mouse prompts")
	expect_focus("mouse hover")


## On-screen keyboard: a controller-only user edits the player name and confirms with Start;
## B cancels without changing anything; focus returns to the row each time.
func test_text_entry_with_controller() -> void:
	await wait_frames(2)
	await open_main_menu()
	App.push("settings", {"tab": "network"})
	await wait_frames(4)
	Controls.last_device = "gamepad"
	var ok: bool = await nav_until(func(c: Control) -> bool: return c is UiRow and (c as UiRow).key == "network.player_name", JOY_BUTTON_DPAD_UP)
	check(ok, "Player name row reachable")
	var original := str(Settings.get_value("network.player_name"))
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "text_entry", "A opens the text entry")
	expect_focus("open text entry")
	check((focus() as Button).text == "1", "controller users start on the on-screen keyboard")
	for i in original.length() + 2:
		await press_joy(JOY_BUTTON_X)
	await press_joy(JOY_BUTTON_A)
	await press_joy(JOY_BUTTON_DPAD_RIGHT)
	await press_joy(JOY_BUTTON_A)
	await press_joy(JOY_BUTTON_DPAD_DOWN)
	await press_joy(JOY_BUTTON_A)
	expect_focus("typing")
	var typed := str(App.top_screen().entered_text())
	check_eq(typed.length(), 3, "three characters typed (%s)" % typed)
	await press_joy(JOY_BUTTON_START, 4)
	check_eq(top_name(), "settings", "Start confirms and closes")
	check_eq(str(Settings.get_value("network.player_name")), typed, "the name was saved")
	var row := focus()
	check(row is TextFieldRow and (row as TextFieldRow).get_value() == typed, "focus returns to the row, which shows the new name")
	await press_joy(JOY_BUTTON_A, 4)
	await press_joy(JOY_BUTTON_A)
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "settings", "B cancels the text entry")
	check_eq(str(Settings.get_value("network.player_name")), typed, "cancel keeps the old name")
	expect_focus("cancel text entry")


## Fight > Versus with the controller: pick a fighter, refuse an invalid line-up, start a real
## match, pause/resume with Start (offline pause freezes the sim), a controller disconnect pauses
## with a notice, and Quit to main menu ends the match.
func test_versus_pause_disconnect_and_quit() -> void:
	await wait_frames(2)
	await open_main_menu()
	check_eq(route_of(focus()), "fight", "Fight focused")
	await press_joy(JOY_BUTTON_A, 3)
	check_eq(route_of(focus()), "quick_fight", "A opens the Fight sub-menu on Quick Fight")
	expect_focus("open Fight")
	await press_joy(JOY_BUTTON_DPAD_DOWN)
	check_eq(route_of(focus()), "versus", "down reaches Versus")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "versus_setup", "Versus setup opens")
	expect_focus("open versus")
	var vs = App.top_screen()
	var ok: bool = await nav_until(func(c: Control) -> bool: return c.has_meta("focus_key") and str(c.get_meta("focus_key")) == "pick1")
	check(ok, "fighter 2 pick row reachable")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "character_select", "the pick row opens character select")
	expect_focus("character select")
	check(focus() is CreatureCard, "a fighter card has focus")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "versus_setup", "picking returns to the setup")
	var f := focus()
	check(f != null and f.has_meta("focus_key") and str(f.get_meta("focus_key")) == "pick1", "focus returns to the pick row")
	# invalid line-up: both fighters on Team A
	ok = await nav_until(func(c: Control) -> bool: return c.has_meta("focus_key") and str(c.get_meta("focus_key")) == "team1")
	check(ok, "fighter 2 team row reachable")
	await press_joy(JOY_BUTTON_DPAD_LEFT)
	check_eq(int(vs.slots()[1]["team"]), 0, "fighter 2 moved to Team A")
	await press_joy(JOY_BUTTON_Y, 3)
	check_eq(top_name(), "versus_setup", "an invalid line-up does not start")
	check(not (App.current_scene is MatchScene), "no match was started")
	check(toast_contains("Team A"), "the problem is explained")
	expect_focus("invalid start")
	await press_joy(JOY_BUTTON_DPAD_RIGHT)
	await press_joy(JOY_BUTTON_Y, 4)
	check(App.current_scene is MatchScene, "Y starts the match")
	check(App.stack.is_empty(), "menus are closed during the fight")
	var ms := App.current_scene as MatchScene
	await wait_physics(30)
	# Start pauses an offline match
	await press_joy(JOY_BUTTON_START, 4)
	check_eq(top_name(), "pause", "Start opens the pause menu")
	expect_focus("pause")
	check(get_tree().paused and ms.sim.paused, "offline pause freezes the simulation and physics")
	var t0 := ms.sim.time
	await wait_frames(10)
	check_eq(ms.sim.time, t0, "no simulation time passes while paused")
	await press_joy(JOY_BUTTON_START, 4)
	check(App.top_screen() == null, "Start resumes")
	check(not get_tree().paused, "the tree is running again")
	await wait_physics(10)
	check(ms.sim.time > t0, "the fight continues after resuming")
	# keyboard Esc pauses too; controller B resumes (the pause menu is the only screen on the stack)
	await press_key(KEY_ESCAPE, 4)
	check_eq(top_name(), "pause", "Esc opens the pause menu")
	expect_focus("pause via Esc")
	await press_joy(JOY_BUTTON_B, 4)
	check(App.top_screen() == null and not get_tree().paused, "B resumes")
	# controller disconnect (same path as Input.joy_connection_changed)
	Controls._on_joy_connection(0, false)
	await wait_frames(4)
	check_eq(top_name(), "pause", "a controller disconnect pauses an offline match")
	check(get_tree().paused, "the match is paused")
	check(find_label_containing(App.top_screen(), "disconnected") != null, "the pause menu says the controller disconnected")
	check(toast_contains("disconnected"), "a disconnect notice is shown")
	expect_focus("disconnect pause")
	Controls._on_joy_connection(0, true)
	await wait_frames(2)
	check(toast_contains("Controller connected"), "a reconnect notice is shown")
	# quit to the main menu through the confirmation dialog
	ok = await nav_until(func(c: Control) -> bool: return route_of(c) == "quit")
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(top_name(), "dialog", "quitting asks first")
	check_eq(route_of(focus()), "stay", "the dialog focuses Keep fighting")
	await press_joy(JOY_BUTTON_DPAD_LEFT)
	await press_joy(JOY_BUTTON_A, 5)
	check_eq(top_name(), "main_menu", "back on the main menu")
	check(not get_tree().paused, "nothing stays paused")
	check(not (App.current_scene is MatchScene), "the match was ended")
	expect_focus("after quitting the match")


## Online matches never pause: the menu opens over the running fight and says so.
func test_online_match_does_not_pause() -> void:
	await wait_frames(2)
	var ids := Content.playable_creatures()
	var cid := str(ids[0]) if not ids.is_empty() else "dev_biped"
	MatchFlow.launch({"arena": "the_gullet", "rules": "duel", "online": true,
		"fighters": [{"creature": cid, "team": 0, "kind": "bot", "difficulty": "rookie", "name": "A"},
			{"creature": cid, "team": 1, "kind": "bot", "difficulty": "rookie", "name": "B"}]})
	var ms := App.current_scene as MatchScene
	await wait_physics(20)
	await press_joy(JOY_BUTTON_START, 4)
	check_eq(top_name(), "pause", "the menu opens online")
	check(not get_tree().paused and not ms.sim.paused, "online matches keep running")
	check(find_label_containing(App.top_screen(), "can't be paused") != null, "the menu explains that online matches don't pause")
	var t0 := ms.sim.time
	await wait_physics(10)
	check(ms.sim.time > t0, "simulation time keeps passing")
	await press_joy(JOY_BUTTON_B, 4)
	check(App.top_screen() == null, "B closes the menu")


## Every UI-owned screen opens with focus inside it and B closes it back to the main menu.
func test_every_screen_has_focus_and_back() -> void:
	await wait_frames(2)
	await open_main_menu()
	var specs := [["settings", {}], ["profile", {}], ["credits", {}], ["tutorial_menu", {}], ["controls", {}],
		["versus_setup", {"mode": "practice"}], ["versus_setup", {"mode": "versus", "fighters": 8}], ["spectate", {}],
		["character_select", {"mode": "quick"}], ["ui_gallery", {}]]
	for s in specs:
		var name_: String = s[0]
		App.push(name_, (s[1] as Dictionary).duplicate())
		await wait_frames(4)
		check_eq(top_name(), name_, "%s opens" % name_)
		expect_focus("open %s" % name_)
		await press_joy(JOY_BUTTON_DPAD_DOWN)
		expect_focus("navigate in %s" % name_)
		await press_joy(JOY_BUTTON_B, 4)
		check_eq(top_name(), "main_menu", "B closes %s" % name_)
		expect_focus("back from %s" % name_)
	# results renders any MatchMode.build_result() dictionary
	var result := {"mode": "standard", "winner_team": 1, "round_wins": {0: 1, 1: 2}, "scores": {}, "rounds": 3, "time": 151.0,
		"fighters": [{"index": 0, "team": 0, "creature": "dev_biped", "name": "Rookie", "health": 0.0, "out": true,
			"stats": {"damage_dealt": 80.0, "damage_taken": 100.0, "hits": 14, "blocks": 3, "parries": 1, "knockdowns": 1, "kos": 0}},
			{"index": 1, "team": 1, "creature": "dev_biped", "name": "Test Dummy", "health": 22.0, "out": false,
			"stats": {"damage_dealt": 100.0, "damage_taken": 80.0, "hits": 17, "blocks": 5, "parries": 0, "knockdowns": 2, "kos": 1}}]}
	App.push("results", {"result": result, "config": {"fighters": [{"kind": "player", "team": 0}], "ui": {"mode": "quick"}}})
	await wait_frames(4)
	check_eq(top_name(), "results", "results open")
	check_eq(route_of(focus()), "rematch", "Rematch is focused first")
	check(find_label_containing(App.top_screen(), "DEFEAT") != null, "the player's outcome is shown")
	check(find_label_containing(App.top_screen(), "TEST DUMMY WINS") != null, "the winner is named")
	await press_joy(JOY_BUTTON_DPAD_RIGHT)
	check_eq(route_of(focus()), "change", "right moves to Change fighters")
	await press_joy(JOY_BUTTON_B, 4)
	check_eq(top_name(), "main_menu", "B on results returns to the main menu")
	# App.dialog reports the chosen button
	var chosen := [""]
	App.dialog("Pick one", "Body text.", [{"label": "First", "id": "first"}, {"label": "Second", "id": "second"}],
		func(id: String) -> void: chosen[0] = id)
	await wait_frames(4)
	expect_focus("App.dialog")
	await press_joy(JOY_BUTTON_DPAD_RIGHT)
	await press_joy(JOY_BUTTON_A, 4)
	check_eq(str(chosen[0]), "second", "the callback receives the chosen id")
	expect_focus("after App.dialog")
	# the title accepts any button
	App.goto("title")
	await wait_seconds(0.6)
	await press_joy(JOY_BUTTON_X, 4)
	check_eq(top_name(), "main_menu", "any button on the title opens the main menu")
	expect_focus("title -> main menu")


## UI-10 layout check: at 1280x800 (Steam Deck) and 1920x1080 every UI screen keeps its footer
## prompts on screen and renders all visible text at >= 18 px (ART_DIRECTION "Deck legibility").
## The headless root window is resized, so this measures real layout, not a mock.
func test_layout_fits_and_text_is_readable() -> void:
	await wait_frames(2)
	await open_main_menu()
	var root := get_tree().root
	var old := root.size
	for res in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = res
		await wait_frames(3)
		var vr := get_viewport().get_visible_rect()
		var px_per_du := get_viewport().get_final_transform().get_scale().y
		check(absf(px_per_du * vr.size.y - float(res.y)) < 2.0, "the viewport maps to %s (%.3f px/du)" % [str(res), px_per_du])
		var eight := []
		for i in 8:
			eight.append({"index": i, "team": i, "creature": "dev_biped", "name": "Fighter %d" % (i + 1), "health": 10.0 * i, "out": i < 7,
				"stats": {"damage_dealt": 50.0 + i, "damage_taken": 40.0, "hits": 9, "blocks": 2, "parries": 1, "knockdowns": 1, "kos": i % 2}})
		var result8 := {"winner_team": 7, "round_wins": {7: 1}, "rounds": 1, "time": 180.0, "fighters": eight}
		var specs := [["main_menu", {}], ["settings", {"tab": "input"}], ["settings", {"tab": "diagnostics"}], ["profile", {}],
			["credits", {}], ["tutorial_menu", {}], ["controls", {}], ["versus_setup", {"mode": "versus", "fighters": 8}],
			["spectate", {"fighters": 8}], ["character_select", {"mode": "quick"}], ["pause", {"notice": "Controller disconnected. Reconnect it, or carry on with keyboard and mouse."}],
			["results", {"result": result8, "config": {"ui": {"mode": "versus"}}}],
			["text_entry", {"title": "Player name", "value": "Rookie"}]]
		for s in specs:
			var name_: String = s[0]
			if name_ != "main_menu":
				App.push(name_, (s[1] as Dictionary).duplicate())
			await wait_frames(4)
			_audit(App.top_screen(), "%s@%dx%d" % [name_, res.x, res.y], vr, px_per_du)
			if name_ != "main_menu":
				App.pop()
				await wait_frames(2)
		App.dialog("A dialog title that is fairly long", "Body text that wraps over more than one line to check the dialog grows correctly.",
			[{"label": "Confirm", "id": "a"}, {"label": "Cancel", "id": "b", "cancel": true}])
		await wait_frames(4)
		_audit(App.top_screen(), "dialog@%dx%d" % [res.x, res.y], vr, px_per_du)
		App.pop()
		await wait_frames(2)
	root.size = old
	await wait_frames(2)


func _audit(s: Screen, tag: String, vr: Rect2, px_per_du: float) -> void:
	if not check(s != null, "%s: screen open" % tag):
		return
	var bars := 0
	for b in s.find_children("*", "PromptBar", true, false):
		var bar := b as Control
		if not bar.is_visible_in_tree():
			continue
		bars += 1
		var r := bar.get_global_rect()
		check(r.end.y <= vr.end.y + 1.0 and r.position.y >= vr.position.y - 1.0 and r.end.x <= vr.end.x + 1.0,
			"%s: footer prompts on screen (bar %s, view %s)" % [tag, str(r), str(vr.size)])
	check(bars > 0, "%s: has a prompt bar" % tag)
	var smallest := 999.0
	var smallest_text := ""
	for n in s.find_children("*", "", true, false):
		var size_du := 0
		var text := ""
		if n is Label and (n as Label).is_visible_in_tree():
			text = (n as Label).text
			size_du = (n as Label).get_theme_font_size("font_size")
		elif n is Button and (n as Button).is_visible_in_tree():
			text = (n as Button).text
			size_du = (n as Button).get_theme_font_size("font_size")
		if text.strip_edges() == "":
			continue
		var px := size_du * px_per_du
		if px < smallest:
			smallest = px
			smallest_text = text
	check(smallest >= 18.0 - 0.01, "%s: smallest text '%s' is %.1f px (< 18 px)" % [tag, smallest_text.substr(0, 30), smallest])


## Text size and UI scale take effect immediately (UI-07, UI-04).
func test_text_and_ui_scale_apply_live() -> void:
	await wait_frames(2)
	UiNav.ensure()
	var t := UiTheme.get_theme()
	var base := t.get_font_size(&"font_size", &"Body")
	Settings.set_value("access.text_scale", 1.4, true, false)
	await wait_frames(1)
	check(t.get_font_size(&"font_size", &"Body") > base, "text size grows live (%d -> %d)" % [base, t.get_font_size(&"font_size", &"Body")])
	check(get_tree().root.content_scale_factor > 1.0, "the canvas scales with text size")
	Settings.set_value("access.text_scale", 1.0, true, false)
	await wait_frames(1)
	check_eq(t.get_font_size(&"font_size", &"Body"), base, "text size returns to normal")
	Settings.set_value("display.ui_scale", 1.25, true, false)
	check(absf(get_tree().root.content_scale_factor - 1.25) < 0.01, "UI scale applies immediately")
	Settings.set_value("display.ui_scale", 1.0, true, false)
