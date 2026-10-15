class_name SpectatorOverlay
extends Control
## AI-vs-AI spectating controls drawn over the fight HUD: a "SPECTATING" banner plus prompts.
## Y / R toggles the camera between the auto director and the free camera (FightCamera FREE: stick
## or WASD moves, the Guard/Dodge bindings lower/raise, camera-nudge turns); X / Delete hides or
## shows the HUD;
## Start / Esc pauses as usual (UiNav). Input is ignored while a menu screen is open.

var scene: MatchScene
var _mode_label: Label
var _bar: PromptBar


func setup(s: MatchScene) -> void:
	scene = s
	name = "SpectatorOverlay"
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiTheme.margin(28)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var col := UiTheme.vbox(UiTheme.GAP_S)
	m.add_child(col)
	col.add_child(UiTheme.spacer())
	var row := UiTheme.hbox(UiTheme.GAP_M)
	col.add_child(row)
	var chip := UiTheme.panel("PanelChip")
	var chip_row := UiTheme.hbox(10)
	chip_row.add_child(UiIcons.rect("spectate", 30, UiTheme.RIM))
	chip_row.add_child(UiTheme.label("SPECTATING", "Value"))
	chip.add_child(chip_row)
	row.add_child(chip)
	_mode_label = UiTheme.label("", "Caption")
	row.add_child(_mode_label)
	row.add_child(UiTheme.spacer())
	_bar = PromptBar.new()
	_bar.set_prompts([
		{"actions": ["ui_alt"], "text": "Camera", "call": toggle_camera},
		{"actions": ["ui_extra"], "text": "Hide HUD", "call": toggle_hud},
		{"actions": ["pause"], "text": "Pause", "call": func() -> void: MatchFlow.open_pause()},
	])
	row.add_child(_bar)
	_update_label()


func toggle_camera() -> void:
	if scene == null or scene.camera == null:
		return
	if scene.camera.mode == FightCamera.Mode.FREE:
		scene.camera.mode = FightCamera.Mode.SPECTATE
	else:
		scene.camera.free_pos = scene.camera.global_position
		scene.camera.free_yaw = scene.camera.global_rotation.y
		scene.camera.free_pitch = clampf(scene.camera.global_rotation.x, -1.2, 0.2)
		scene.camera.mode = FightCamera.Mode.FREE
	Audio.sfx("ui_accept")
	_update_label()


func toggle_hud() -> void:
	if scene == null or scene.hud == null:
		return
	scene.hud.visible = not scene.hud.visible
	var p := _bar.find_prompt("Hide HUD") if scene.hud.visible else _bar.find_prompt("Show HUD")
	if p:
		p.set_text("Hide HUD" if scene.hud.visible else "Show HUD")
	Audio.sfx("ui_accept")


func _update_label() -> void:
	if scene == null or scene.camera == null:
		return
	_mode_label.text = "Free camera" if scene.camera.mode == FightCamera.Mode.FREE else "Director camera"


func _process(_dt: float) -> void:
	# menus (pause, results) draw their own prompts; keep the spectator bar out of their way
	visible = App.top_screen() == null


func _unhandled_input(event: InputEvent) -> void:
	if App.top_screen() != null:
		return
	if event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		toggle_camera()
	elif event.is_action_pressed("ui_extra"):
		get_viewport().set_input_as_handled()
		toggle_hud()
