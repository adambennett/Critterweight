class_name SpectatorOverlay
extends Control
## AI-vs-AI spectating controls drawn over the fight HUD: a "SPECTATING" banner plus prompts.
## Y / R cycles the camera through follow, locked and free (FightCamera FREE: stick
## or WASD moves, the Guard/Dodge bindings lower/raise, camera-nudge turns); X / Delete hides or
## shows the HUD; LB/RB (Q/E) lock the director on a fighter (past either end = auto again);
## D-pad up/down (arrow keys) change the playback speed 0.25x-2x (offline only);
## Start / Esc pauses as usual (UiNav). Input is ignored while a menu screen is open.

var scene: MatchScene
var _mode_label: Label
var _bar: FlowPromptBar
var _free_help: Control


func setup(s: MatchScene) -> void:
	scene = s
	name = "SpectatorOverlay"
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UiTheme.margin(28)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# below the round timer (and below the big top cards in 1v1)
	m.add_theme_constant_override("margin_top", 104 if s.sim.fighters.size() > 2 else 176)
	add_child(m)
	var col := UiTheme.vbox(UiTheme.GAP_S)
	m.add_child(col)
	# top of the screen: the fighter cards own the bottom edge in 3+ fighter matches
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
	_bar = FlowPromptBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.set_prompts([
		{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Focus", "call": func() -> void: cycle_focus(1)},
		{"actions": ["ui_up", "ui_down"], "text": "Speed", "call": func() -> void: change_speed(1)},
		{"actions": ["ui_alt"], "text": "Camera", "call": toggle_camera},
		{"actions": ["ui_extra"], "text": "Hide HUD", "call": toggle_hud},
		{"actions": ["pause"], "text": "Pause", "call": func() -> void: MatchFlow.open_pause()},
	])
	row.add_child(_bar)
	_free_help = UiTheme.panel("PanelSolid", 12)
	_free_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_free_help.add_child(UiTheme.label("FREE CAMERA · WASD / left stick: move · Right drag / right stick: look · Space / A: rise · Shift / LT: descend", "Body", true))
	col.add_child(_free_help)
	col.add_child(UiTheme.spacer())
	_update_label()


func toggle_camera() -> void:
	if scene == null or scene.camera == null:
		return
	if scene.camera.mode == FightCamera.Mode.FREE:
		scene.camera.mode = FightCamera.Mode.SPECTATE
		if scene.director:
			scene.director.locked = -1
	elif scene.director and scene.director.locked < 0:
		scene.director.cycle_lock(1)
	else:
		scene.camera.enter_free()
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


const SPEEDS := [0.25, 0.5, 1.0, 1.5, 2.0]


func cycle_focus(step: int) -> void:
	if scene == null or scene.director == null:
		return
	scene.director.cycle_lock(step)
	if scene.camera.mode == FightCamera.Mode.FREE:
		scene.camera.mode = FightCamera.Mode.SPECTATE
	Audio.sfx("ui_move")
	_update_label()


func change_speed(step: int) -> void:
	if MatchFlow.is_online():
		return
	var i := SPEEDS.find(Engine.time_scale)
	if i < 0:
		i = 2
	Engine.time_scale = SPEEDS[clampi(i + step, 0, SPEEDS.size() - 1)]
	Audio.sfx("ui_move")
	_update_label()


func _update_label() -> void:
	if scene == null or scene.camera == null:
		return
	var cam := "FREE" if scene.camera.mode == FightCamera.Mode.FREE else ("LOCKED · " + scene.director.label() if scene.director and scene.director.locked >= 0 else "FOLLOW · Auto director")
	_mode_label.text = "%s   ·   %sx" % [cam, str(snappedf(Engine.time_scale, 0.01))]
	if _free_help:
		_free_help.visible = scene.camera.mode == FightCamera.Mode.FREE


func _process(_dt: float) -> void:
	# menus (pause, results) draw their own prompts; keep the spectator bar out of their way
	visible = App.top_screen() == null
	if visible:
		_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if App.top_screen() != null:
		return
	if event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		toggle_camera()
	elif event.is_action_pressed("ui_extra"):
		get_viewport().set_input_as_handled()
		toggle_hud()
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		cycle_focus(1 if event.is_action_pressed("ui_tab_next") else -1)
	elif not (event is InputEventJoypadMotion) and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")):
		get_viewport().set_input_as_handled()
		change_speed(1 if event.is_action_pressed("ui_up") else -1)
