class_name ArenaTestPlay
extends CanvasLayer
## Overlay added to a MatchScene started by the arena editor's "Test play": shows how to get back
## and returns to the editor (F5, or the controller View button) — the editor session (layout,
## undo history, camera, selection) is restored. The match ending normally also returns.

var _label: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	# shared UI look (docs/UI.md): a chip under the fight HUD, never focusable
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "PanelToast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 150
	root.add_child(panel)
	_label = UiTheme.label("", "BodyStrong")
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
