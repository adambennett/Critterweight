extends Screen
## Title: the CRITTERWEIGHT wordmark stamps in over the orbiting, spot-lit Gullet; "press any
## button" accepts any key, controller button or mouse click and opens the main menu.
## Also the boot hook for development flags (UiDevFlags: --ui-screen, --ui-seed-window, ...).

var _wordmark: Wordmark
var _press: Control
var _accepting := false
var _t := 0.0


func on_enter(_p: Dictionary) -> void:
	if UiDevFlags.handle():
		return
	MenuBackdrop.ensure()
	_build()
	_wordmark.play_intro()
	var timer := get_tree().create_timer(0.45, true, false, true)
	timer.timeout.connect(func() -> void: _accepting = true)
	Audio.music("menu_theme", 1.5)


func _build() -> void:
	# vignette: dark top and bottom bands so the wordmark and prompt read over the arena lights
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.65, 1.0])
	g.colors = PackedColorArray([Color(UiTheme.BG_DEEP, 0.85), Color(UiTheme.BG_DEEP, 0.25), Color(UiTheme.BG_DEEP, 0.3), Color(UiTheme.BG_DEEP, 0.92)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4
	gt.height = 256
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var m := UiTheme.margin(UiTheme.SCREEN_MARGIN, 64, 44)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var col := UiTheme.vbox(UiTheme.GAP_M)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(col)
	col.add_child(UiTheme.spacer())
	_wordmark = Wordmark.new(150.0)
	_wordmark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_wordmark)
	var tag := UiTheme.label("SIX OVER-JUICED CRITTERS.  ONE CAGE.  ZERO REGULATIONS.", "H3")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_color", UiTheme.WARM)
	col.add_child(tag)
	col.add_child(UiTheme.spacer())
	var press_row := UiTheme.hbox(UiTheme.GAP_M)
	press_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var prompt := ButtonPrompt.new(["ui_accept"], "", 48.0)
	prompt.clickable = false
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	press_row.add_child(prompt)
	press_row.add_child(UiTheme.label("PRESS ANY BUTTON", "H2"))
	_press = press_row
	col.add_child(press_row)
	col.add_child(UiTheme.spacer(false, 40))
	var foot := UiTheme.hbox(UiTheme.GAP_L)
	var ver := UiTheme.label("v%s  ·  local build" % str(ProjectSettings.get_setting("application/config/version", "0.0.0")), "Caption")
	foot.add_child(ver)
	foot.add_child(UiTheme.spacer())
	var device := UiTheme.label("", "Caption")
	device.name = "DeviceHint"
	foot.add_child(device)
	col.add_child(foot)
	_update_device_hint()
	Controls.device_changed.connect(func(_k: String) -> void: _update_device_hint())
	Controls.joy_connection.connect(func(_d: int, _c: bool) -> void: _update_device_hint())


func _update_device_hint() -> void:
	var l := find_child("DeviceHint", true, false) as Label
	if l == null:
		return
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		l.text = "Keyboard & mouse"
	else:
		l.text = "Controller: %s" % Input.get_joy_name(pads[0])


func _process(dt: float) -> void:
	_t += dt
	if _press and not UiTheme.reduce_motion():
		_press.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 3.2))


func _input(event: InputEvent) -> void:
	if not _accepting or not is_top():
		return
	var go := false
	if event is InputEventKey:
		go = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventJoypadButton:
		go = (event as InputEventJoypadButton).pressed
	elif event is InputEventMouseButton:
		go = (event as InputEventMouseButton).pressed
	if go:
		get_viewport().set_input_as_handled()
		_accepting = false
		Audio.sfx("ui_accept")
		App.goto("main_menu")


func on_back() -> bool:
	return true
