class_name ArenaTestPlay
extends CanvasLayer
## Overlay added to a MatchScene started by the arena editor's "Test play": shows how to get back
## and returns to the editor (F5, or the controller View button) — the editor session (layout,
## undo history, camera, selection) is restored. The match ending normally also returns.

var _label: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.85)
	sb.border_color = Color("#C9A227")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-330, 112)
	panel.custom_minimum_size = Vector2(660, 0)
	add_child(panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", load("res://assets/fonts/BarlowCondensed-700.woff2"))
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color("#F2F2EC"))
	panel.add_child(_label)
	_refresh()
	Controls.device_changed.connect(func(_k): _refresh())


func _refresh() -> void:
	var back := "View button" if Controls.last_device == "gamepad" else "F5"
	_label.text = "ARENA TEST PLAY  ·  press %s to return to the editor" % back


func _input(ev: InputEvent) -> void:
	var go := false
	if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_F5:
		go = true
	elif ev is InputEventJoypadButton and (ev as InputEventJoypadButton).pressed and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_BACK:
		go = true
	if go:
		get_viewport().set_input_as_handled()
		return_to_editor()


static func return_to_editor() -> void:
	var app := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("App")
	if app == null:
		return
	app.call_deferred("set_scene", null)
	app.call_deferred("goto", "arena_editor", {"resume": true})
