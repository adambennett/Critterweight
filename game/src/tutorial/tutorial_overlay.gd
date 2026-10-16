extends Control
## On-screen coach for the tutorial: Granny Haymaker's lines (subtitled, with live binding
## prompts), the current exercise's goal and progress, and the tutorial menu (Resume, Retry,
## Skip, exercise list for replays, Leave). The menu pauses the match. Works with a controller
## (focus + ui_accept/ui_cancel, the Pause button opens/closes it) and mouse/keyboard.

var scene: MatchScene
var mode: TutorialMode
var _coach_name: Label
var _coach_text: Label
var _title: Label
var _goal: Label
var _progress: Label
var _prompt: Label
var _menu: PanelContainer
var _menu_box: VBoxContainer
var _done_shown := false
var _font: Font
var _font_heavy: Font
var _last_line := ""
var _type_t := 0.0


func bind(s: MatchScene) -> void:
	scene = s
	mode = s.sim.mode as TutorialMode
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/BarlowCondensed-700.woff2")
	_font_heavy = load("res://assets/fonts/BarlowCondensed-900.woff2")
	_build()
	# Granny's lines go to the coach box; everything else (Barnaby) keeps the HUD subtitle
	if Audio.subtitle.is_connected(s.hud.subtitle):
		Audio.subtitle.disconnect(s.hud.subtitle)
	Audio.subtitle.connect(_on_subtitle)
	Controls.device_changed.connect(func(_k): _refresh_static())


func _exit_tree() -> void:
	if Audio.subtitle.is_connected(_on_subtitle):
		Audio.subtitle.disconnect(_on_subtitle)


func _on_subtitle(speaker: String, text: String, seconds: float) -> void:
	if speaker == "granny":
		return
	if is_instance_valid(scene) and scene.hud:
		scene.hud.subtitle(speaker, text, seconds)


func _panel(bg: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	sb.border_color = Color(1.0, 0.75, 0.3, 0.6)
	sb.set_border_width_all(2)
	pc.add_theme_stylebox_override("panel", sb)
	return pc


func _lbl(size: int, heavy := false, color := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font_heavy if heavy else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	# coach box (bottom left), above the fight HUD's control-prompt strip (16-78 px from the bottom),
	# which it used to cover (Light / Heavy / Guard hidden under the box)
	var coach := _panel(Color(0.07, 0.05, 0.09, 0.88))
	coach.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	coach.offset_left = 32
	coach.offset_bottom = -92
	coach.offset_top = -310
	coach.offset_right = 820
	coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(coach)
	var cb := VBoxContainer.new()
	cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coach.add_child(cb)
	_coach_name = _lbl(26, true, Color(1.0, 0.78, 0.35))
	_coach_name.text = "GRANNY HAYMAKER"
	cb.add_child(_coach_name)
	_coach_text = _lbl(28)
	_coach_text.custom_minimum_size = Vector2(760, 0)
	cb.add_child(_coach_text)
	# objective (top centre, under the timer)
	var obj := _panel(Color(0.07, 0.05, 0.09, 0.78))
	obj.set_anchors_preset(Control.PRESET_CENTER_TOP)
	obj.offset_left = -430
	obj.offset_right = 430
	obj.offset_top = 150
	obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(obj)
	var ob := VBoxContainer.new()
	ob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj.add_child(ob)
	_title = _lbl(34, true, Color(1.0, 0.85, 0.4))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ob.add_child(_title)
	_goal = _lbl(26)
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.custom_minimum_size = Vector2(820, 0)
	ob.add_child(_goal)
	_progress = _lbl(26, true, Color(0.6, 1.0, 0.65))
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ob.add_child(_progress)
	# prompt (bottom right), above the HUD's control-prompt strip as well
	_prompt = _lbl(22, false, Color(1, 1, 1, 0.85))
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_prompt.offset_left = -520
	_prompt.offset_right = -32
	_prompt.offset_top = -128
	_prompt.offset_bottom = -92
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_prompt)
	# menu
	_menu = _panel(Color(0.06, 0.04, 0.08, 0.95))
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.custom_minimum_size = Vector2(560, 0)
	_menu.visible = false
	add_child(_menu)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 8)
	_menu.add_child(_menu_box)
	_refresh_static()


func _refresh_static() -> void:
	_prompt.text = "[%s] Tutorial menu: retry, skip, pick an exercise" % Controls.prompt_for("pause")


func _process(delta: float) -> void:
	if mode == null:
		return
	if _menu.visible:
		scene.sim.paused = true
	var ex := mode.current()
	_title.text = "EXERCISE %d/%d · %s" % [mode.index + 1, mode.list.size(), str(ex.get("title", "")).to_upper()]
	_goal.text = mode.objective()
	var pt := mode.progress_text()
	match mode.state:
		"success":
			pt = "✓  DONE"
		"failed":
			pt = "Not quite — again in a moment"
		"complete":
			pt = "TUTORIAL COMPLETE"
		"done_single":
			pt = "✓  EXERCISE COMPLETE"
	_progress.text = pt
	var line := str(mode.coach.get("text", ""))
	if line != _last_line:
		_last_line = line
		_type_t = 0.0
	_type_t += delta
	var shown := mini(line.length(), int(_type_t * 55.0))
	_coach_text.text = line.substr(0, shown)
	_coach_name.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if str(mode.coach.get("kind", "")) == "success" else Color(1.0, 0.78, 0.35))
	if mode.state in ["complete", "done_single"] and not _done_shown:
		_done_shown = true
		_open_menu(mode.state == "complete")
	elif mode.state == "active":
		_done_shown = false


func _input(event: InputEvent) -> void:
	if mode == null:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _menu.visible:
			_close_menu()
		else:
			_open_menu(false)
	elif _menu.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_menu()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 28)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): b.grab_focus())
	_menu_box.add_child(b)
	return b


func _open_menu(finished: bool) -> void:
	scene.sim.paused = true
	for c in _menu_box.get_children():
		c.queue_free()
	var head := _lbl(36, true, Color(1.0, 0.85, 0.4))
	head.text = "TUTORIAL COMPLETE" if finished else "TUTORIAL"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_box.add_child(head)
	var first: Button = null
	if finished:
		var note := _lbl(24)
		note.text = "That's the whole kit. Everything after this is timing. Your photo is on the Wall of Fame."
		_menu_box.add_child(note)
		first = _button("Freestyle again", func():
			_close_menu()
			mode.start_exercise(mode.list.size() - 1, true))
	elif mode.state == "done_single":
		head.text = "EXERCISE COMPLETE"
		if mode.index + 1 < mode.list.size():
			first = _button("Next exercise", func():
				_close_menu()
				mode.start_exercise(mode.index + 1, true))
		var again := _button("Do it again", func():
			_close_menu()
			mode.retry())
		if first == null:
			first = again
	else:
		first = _button("Resume", _close_menu)
		_button("Retry this exercise", func():
			_close_menu()
			mode.retry())
		if mode.index + 1 < mode.list.size():
			_button("Skip to the next exercise", func():
				_close_menu()
				mode.skip())
			if mode.index < 7:
				_button("Skip to Freestyle", func():
					_close_menu()
					mode.start_exercise(mode.list.size() - 1))
	var sub := _lbl(22, false, Color(1, 1, 1, 0.7))
	sub.text = "Replay an exercise:"
	_menu_box.add_child(sub)
	for i in mode.list.size():
		var ex: Dictionary = mode.list[i]
		var mark := "✓ " if str(ex.get("id", "")) in mode.completed else "   "
		var ii := i
		_button("%s%d. %s" % [mark, i + 1, str(ex.get("title", ""))], func():
			_close_menu()
			mode.start_exercise(ii, true))
	_button("Leave the tutorial", func():
		_close_menu()
		mode.leave())
	_menu.visible = true
	_menu.reset_size()
	_menu.position = (size - _menu.size) * 0.5
	if first:
		first.grab_focus.call_deferred()


func _close_menu() -> void:
	_menu.visible = false
	if mode and mode.state != "complete":
		scene.sim.paused = false
	elif mode:
		scene.sim.paused = false
