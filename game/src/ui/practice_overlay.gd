extends Control
## Practice controls over the fight HUD (MCH-01): choose what the dummy does (stand, guard, parry,
## counter, replay your recording, or fight back as a bot), record/stop a sequence for the replay
## dummy, and reset positions and health. The hit telemetry is the HUD's mode line (PracticeMode).
## Pad: D-pad left/right = dummy behaviour, View = record/stop, LS click = reset. Keyboard: 1-6
## behaviours, F5 record/stop, F6 reset. The pause menu works as usual.

const LABELS := {"stand": "Stand still", "guard": "Guard", "parry": "Parry", "counter": "Block and counter",
	"replay": "Replay my recording", "bot": "Fight back (bot)"}

var scene: MatchScene
var mode: PracticeMode
var _title: Label
var _bar: PromptBar


func bind(s: MatchScene) -> void:
	scene = s
	mode = s.sim.mode as PracticeMode
	name = "PracticeOverlay"
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if mode == null:
		return
	var panel := UiTheme.panel("PanelChip")
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -760
	panel.offset_right = 760
	panel.offset_top = -150
	panel.offset_bottom = -92
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var row := UiTheme.hbox(UiTheme.GAP_M)
	panel.add_child(row)
	_title = UiTheme.label("", "Value")
	row.add_child(_title)
	row.add_child(UiTheme.spacer())
	_bar = PromptBar.new()
	_bar.set_prompts([
		{"actions": ["practice_prev", "practice_next"], "text": "Dummy", "call": func() -> void: cycle(1)},
		{"actions": ["practice_record"], "text": "Record", "call": toggle_record},
		{"actions": ["practice_reset"], "text": "Reset", "call": reset_positions},
	])
	row.add_child(_bar)
	_refresh()


## Practice-only input actions (registered once; D-pad left/right and the View button are free
## in fight controls).
static func ensure_actions() -> void:
	var defs := {
		"practice_prev": [_joy(JOY_BUTTON_DPAD_LEFT)],
		"practice_next": [_joy(JOY_BUTTON_DPAD_RIGHT)],
		"practice_record": [_key(KEY_F5), _joy(JOY_BUTTON_BACK)],
		"practice_reset": [_key(KEY_F6), _joy(JOY_BUTTON_LEFT_STICK)],
	}
	for a in defs:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
			for ev in defs[a]:
				InputMap.action_add_event(a, ev)


static func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


static func _joy(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func _ready() -> void:
	ensure_actions()


func cycle(step: int) -> void:
	var list: Array = PracticeMode.BEHAVIORS
	var i := list.find(mode.behavior)
	set_behavior(str(list[posmod(i + step, list.size())]))


func set_behavior(b: String) -> void:
	mode.set_behavior(b, str(scene.sim.rules.get("dummy_tier", "regular")))
	Audio.ui("ui_toggle")
	_refresh()


func toggle_record() -> void:
	mode.toggle_recording()
	Audio.ui("ui_toggle")
	UiNav.toast("Recording your moves — press again to stop" if mode.recording else "Recording saved: set the dummy to 'Replay my recording'", "info")
	_refresh()


func reset_positions() -> void:
	scene.sim.reset_round()
	Audio.ui("ui_accept")


func _refresh() -> void:
	if _title:
		_title.text = "PRACTICE  ·  Dummy: %s%s" % [LABELS.get(mode.behavior, mode.behavior), "   ● REC" if mode.recording else ""]


func _unhandled_input(event: InputEvent) -> void:
	if mode == null or App.top_screen() != null:
		return
	if event.is_action_pressed("practice_next"):
		cycle(1)
	elif event.is_action_pressed("practice_prev"):
		cycle(-1)
	elif event.is_action_pressed("practice_record"):
		toggle_record()
	elif event.is_action_pressed("practice_reset"):
		reset_positions()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_6:
			set_behavior(str(PracticeMode.BEHAVIORS[k - KEY_1]))
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()
