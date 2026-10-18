class_name UiNav
extends Node
## Global UI runtime. Installed under the App autoload by the first Screen that enters the tree
## (UiNav.ensure()), so no project setting is needed. Responsibilities:
##  - UI-only input actions: ui_tab_prev / ui_tab_next (LB/RB, Q/E, PgUp/PgDn), ui_alt (Y, R),
##    ui_extra (X, Delete, Backspace). Gameplay actions stay in Controls.
##  - Analog stick -> discrete ui_up/down/left/right with hysteresis and hold-repeat. (Godot treats
##    every stick motion event past the dead zone as a fresh press, which skips several items per
##    flick.) Held D-pad directions repeat too. Raw stick events are swallowed only while a menu
##    control has focus, so gameplay polling through Controls is unaffected.
##  - Focus guardian: if the top screen ends up without focus (freed control, click on empty space,
##    rebuilt list) focus returns to that screen's remembered/default control. Focus is never lost.
##  - Binding capture for KeybindRow: swallows ALL input until a key/button of the requested class
##    arrives (Esc cancels, timeout cancels).
##  - Toasts above every screen; device hot-plug notices.
##  - Match hooks (offline): the pause action, controller disconnect and window focus loss open the
##    pause menu (see MatchFlow). Online matches never pause.
##  - Live text-size changes (UiTheme.refresh()).

const STICK_PRESS := 0.6
const STICK_RELEASE := 0.35
const REPEAT_DELAY := 0.38
const REPEAT_RATE := 0.11
const REPEAT_RATE_FAST := 0.06
const DPAD := {JOY_BUTTON_DPAD_UP: "ui_up", JOY_BUTTON_DPAD_DOWN: "ui_down", JOY_BUTTON_DPAD_LEFT: "ui_left", JOY_BUTTON_DPAD_RIGHT: "ui_right"}

static var instance: UiNav

var toasts: ToastLayer
var stick_events_swallowed := 0          ## diagnostics/tests
var _stick := Vector2.ZERO
var _stick_dir := Vector2i.ZERO
var _held_action := ""
var _held_source := ""
var _held_button := -1
var _repeat_t := 0.0
var _repeats := 0
var _last_input_ms := -100000
var _capture := {}
var fps_label: Label


## Returns the installed instance, creating it under /root/App when needed.
static func ensure() -> UiNav:
	if instance != null and is_instance_valid(instance) and instance.is_inside_tree():
		return instance
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var app := tree.root.get_node_or_null("App")
	if app == null:
		return null
	var n := app.get_node_or_null("UiNav") as UiNav
	if n == null:
		n = UiNav.new()
		n.name = "UiNav"
		app.add_child(n)
	instance = n
	return n


static func toast(text: String, kind := "info", seconds := 3.5) -> void:
	var n := ensure()
	if n != null and n.toasts != null:
		n.toasts.show_toast(text, kind, seconds)
	else:
		Log.i("toast", text)


## True right after a key/button/mouse input: lets widgets play ui_move only for user-driven focus.
static func user_initiated() -> bool:
	return instance != null and is_instance_valid(instance) and Time.get_ticks_msec() - instance._last_input_ms < 300


static func begin_capture(pad: bool, seconds: float, cb: Callable) -> void:
	var n := ensure()
	if n == null:
		cb.call(null)
		return
	n._held_action = ""
	n._capture = {"pad": pad, "until": Time.get_ticks_msec() + int(seconds * 1000.0), "cb": cb, "start": Time.get_ticks_msec()}


static func capture_active() -> bool:
	return instance != null and is_instance_valid(instance) and not instance._capture.is_empty()


static func capture_seconds_left() -> float:
	if not capture_active():
		return 0.0
	return maxf(0.0, float(int(instance._capture["until"]) - Time.get_ticks_msec()) / 1000.0)


static func cancel_capture() -> void:
	if capture_active():
		instance._finish_capture(null)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_actions()
	toasts = ToastLayer.new()
	add_child(toasts)
	Controls.joy_connection.connect(_on_joy_connection)
	Settings.changed.connect(_on_setting_changed)
	get_window().focus_exited.connect(_on_window_focus_lost)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	fps_label = UiTheme.label("", "CaptionStrong")
	fps_label.name = "FPS"
	fps_label.position = Vector2(16, 8)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.add_theme_color_override("font_color", Color.WHITE)
	fps_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	fps_label.add_theme_constant_override("shadow_offset_x", 2)
	fps_label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(fps_label)


static func _register_actions() -> void:
	var spec := {
		"ui_tab_prev": [JOY_BUTTON_LEFT_SHOULDER, KEY_Q, KEY_PAGEUP],
		"ui_tab_next": [JOY_BUTTON_RIGHT_SHOULDER, KEY_E, KEY_PAGEDOWN],
		"ui_alt": [JOY_BUTTON_Y, KEY_R],
		"ui_extra": [JOY_BUTTON_X, KEY_DELETE, KEY_BACKSPACE],
	}
	for action in spec:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		var list: Array = spec[action]
		for i in list.size():
			if i == 0:
				var jb := InputEventJoypadButton.new()
				jb.button_index = list[i]
				jb.device = -1
				InputMap.action_add_event(action, jb)
			else:
				var k := InputEventKey.new()
				k.keycode = list[i]
				InputMap.action_add_event(action, k)


func _menu_active() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and not bool(f.get_meta("owns_sticks", false))


func _input(event: InputEvent) -> void:
	if event is InputEventAction:
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		_last_input_ms = Time.get_ticks_msec()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0:
		_last_input_ms = Time.get_ticks_msec()
	if not _capture.is_empty():
		get_viewport().set_input_as_handled()
		_capture_input(event)
		return
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_LEFT_X or jm.axis == JOY_AXIS_LEFT_Y:
			if jm.axis == JOY_AXIS_LEFT_X:
				_stick.x = jm.axis_value
			else:
				_stick.y = jm.axis_value
			if absf(jm.axis_value) > STICK_RELEASE:
				_last_input_ms = Time.get_ticks_msec()
			if _menu_active():
				get_viewport().set_input_as_handled()
				stick_events_swallowed += 1
				# UiNav runs before Controls._input (reverse tree order), so mirror its device switch
				# here or stick-only menu users would keep seeing keyboard prompts
				if absf(jm.axis_value) > 0.5 and Controls.last_device != "gamepad":
					Controls.last_device = "gamepad"
					Controls.device_changed.emit("gamepad")
				_update_stick()
			else:
				_stick_dir = Vector2i.ZERO
				_clear_hold("stick")
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if DPAD.has(jb.button_index):
			if jb.pressed:
				_hold(str(DPAD[jb.button_index]), "dpad")
				_held_button = jb.button_index
			elif _held_button == jb.button_index:
				_clear_hold("dpad")


func _update_stick() -> void:
	var ax := absf(_stick.x)
	var ay := absf(_stick.y)
	var dir := Vector2i.ZERO
	if _stick_dir != Vector2i.ZERO:
		var cur := ax if _stick_dir.x != 0 else ay
		var other := ay if _stick_dir.x != 0 else ax
		if cur >= STICK_RELEASE and not (other >= STICK_PRESS and other > cur):
			dir = _stick_dir
	if dir == Vector2i.ZERO and maxf(ax, ay) >= STICK_PRESS:
		dir = Vector2i(int(signf(_stick.x)), 0) if ax >= ay else Vector2i(0, int(signf(_stick.y)))
	if dir == _stick_dir:
		return
	_stick_dir = dir
	if dir == Vector2i.ZERO:
		_clear_hold("stick")
		return
	var action := _dir_action(dir)
	emit_nav(action)
	_hold(action, "stick")


static func _dir_action(d: Vector2i) -> String:
	if d.x < 0:
		return "ui_left"
	if d.x > 0:
		return "ui_right"
	if d.y < 0:
		return "ui_up"
	return "ui_down"


func _hold(action: String, source: String) -> void:
	_held_action = action
	_held_source = source
	_repeat_t = REPEAT_DELAY
	_repeats = 0


func _clear_hold(source: String) -> void:
	if _held_source == source:
		_held_action = ""
		_held_source = ""
		_held_button = -1


## Sends a synthetic UI navigation action through the normal input pipeline (focus navigation and
## the focused control's _gui_input both see it).
static func emit_nav(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _process(dt: float) -> void:
	if fps_label != null:
		fps_label.visible = bool(Settings.get_value("diag.show_fps"))
		if fps_label.visible:
			fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if not _capture.is_empty():
		if Time.get_ticks_msec() >= int(_capture["until"]):
			_finish_capture(null)
		return
	if _held_action != "":
		if not _menu_active():
			_held_action = ""
		else:
			_repeat_t -= dt
			if _repeat_t <= 0.0:
				_repeats += 1
				_repeat_t = REPEAT_RATE_FAST if _repeats > 8 else REPEAT_RATE
				emit_nav(_held_action)
	_guard_focus()
	if App.top_screen() != null:
		var ry := 0.0
		for device in Input.get_connected_joypads():
			var value := Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
			if absf(value) > absf(ry):
				ry = value
		if absf(ry) > 0.25:
			scroll_focused(ry * 1400.0 * dt)


## One right-stick path for lists, information panels, and rich text (including
## embedded text scrollbars). It never scrolls a covered screen or an editor canvas.
func scroll_focused(amount: float) -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f == null or bool(f.get_meta("owns_sticks", false)):
		return
	var bar := scroll_bar_for(f)
	if bar != null:
		bar.value += amount


static func scroll_bar_for(f: Control) -> Range:
	if f is ScrollText:
		return (f as ScrollText).scroll.get_v_scroll_bar()
	if f is RichTextLabel and (f as RichTextLabel).scroll_active:
		return (f as RichTextLabel).get_v_scroll_bar()
	if f is ItemList:
		return (f as ItemList).get_v_scroll_bar()
	var n: Node = f
	while n != null:
		if n is ScrollContainer:
			return (n as ScrollContainer).get_v_scroll_bar()
		n = n.get_parent()
	# A focusable information panel owns a scroll region below it.
	for child in f.find_children("*", "ScrollContainer", true, false):
		if (child as Control).is_visible_in_tree():
			return (child as ScrollContainer).get_v_scroll_bar()
	return null


func _on_focus_changed(f: Control) -> void:
	reveal_focus.call_deferred(f)


static func reveal_focus(f: Control) -> void:
	if not is_instance_valid(f) or not f.is_inside_tree() or not f.has_focus():
		return
	var n := f.get_parent()
	while n != null:
		if n is ScrollContainer:
			var sc := n as ScrollContainer
			sc.ensure_control_visible(f)
			# Godot only reveals the unscaled rectangle. Reserve room for the
			# gold focus ring and scale tween, including the final row's padding.
			var top := f.global_position.y - sc.global_position.y - 16.0
			var bottom := f.global_position.y + f.size.y - sc.global_position.y + 16.0
			if bottom > sc.size.y:
				sc.scroll_vertical += ceili(bottom - sc.size.y)
			elif top < 0.0:
				sc.scroll_vertical += floori(top)
		n = n.get_parent()


## Focus guardian (UI-02): the top screen always owns a visible focused control when it has any.
func _guard_focus() -> void:
	if not is_instance_valid(App) or App.stack.is_empty():
		return
	var top := App.top_screen()
	if top == null or not is_instance_valid(top) or top.is_queued_for_deletion() or not top.is_visible_in_tree():
		return
	var f := get_viewport().gui_get_focus_owner()
	if f != null and is_instance_valid(f) and top.is_ancestor_of(f) and f.is_visible_in_tree():
		return
	top.ensure_focus()


func _capture_input(event: InputEvent) -> void:
	var pad: bool = _capture["pad"]
	var since := Time.get_ticks_msec() - int(_capture["start"])
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE or k.physical_keycode == KEY_ESCAPE or pad:
			_finish_capture(null)
		else:
			_finish_capture(k)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or since < 200:
			return
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return
		_finish_capture(null if pad else mb)
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		_finish_capture(jb if pad else null)
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if pad and absf(jm.axis_value) >= 0.6 and since > 150:
			_finish_capture(jm)


func _finish_capture(ev: InputEvent) -> void:
	if _capture.is_empty():
		return
	var cb: Callable = _capture["cb"]
	_capture = {}
	_stick_dir = Vector2i.ZERO
	if cb.is_valid():
		cb.call(ev)


func _on_joy_connection(device: int, connected: bool) -> void:
	var nm := Input.get_joy_name(device)
	if nm == "":
		nm = "Controller"
	if connected:
		toast("%s connected." % nm, "success")
		return
	toast("%s disconnected." % nm, "warning", 5.0)
	if MatchFlow.match_running() and not MatchFlow.is_online() and App.top_screen() == null:
		MatchFlow.open_pause("Controller disconnected. Reconnect it, or carry on with keyboard and mouse.")


func _on_window_focus_lost() -> void:
	if not bool(Settings.get_value("gameplay.pause_on_focus_loss")):
		return
	if MatchFlow.match_running() and not MatchFlow.is_online() and App.top_screen() == null:
		MatchFlow.open_pause("Paused because the game window lost focus.")


func _on_setting_changed(key: String, _value) -> void:
	if key == "access.text_scale":
		UiTheme.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and App.top_screen() == null and MatchFlow.match_running():
		get_viewport().set_input_as_handled()
		MatchFlow.open_pause()
