class_name KeybindRow
extends PanelContainer
## "Action label | [keyboard & mouse glyphs] | [controller glyphs]" — two focus stops (BindSlots).
## Left/right moves between the columns, up/down between actions (same column). Capturing, conflict
## handling and persistence happen in `capture()` so screens only lay rows out.

signal rebound(action: String, stolen_from: String, pad: bool)
signal reset_done(action: String, conflicts: Array)

var action := ""
var kb_slot: BindSlot
var pad_slot: BindSlot
var _label: Label
var _note: Label


func _init(action_ := "") -> void:
	action = action_
	theme_type_variation = "PanelRow"
	add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.SURFACE, 0.55), UiTheme.RADIUS, 24.0, 6.0))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := UiTheme.hbox(UiTheme.GAP_M)
	add_child(row)
	var col := UiTheme.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label = UiTheme.label(BindingsFlow.label_of(action_), "BodyStrong")
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_label)
	_note = UiTheme.label("", "Caption")
	_note.visible = false
	col.add_child(_note)
	row.add_child(col)
	kb_slot = BindSlot.new(action_, false)
	pad_slot = BindSlot.new(action_, true)
	for s in [kb_slot, pad_slot]:
		var slot: BindSlot = s
		slot.capture_requested.connect(capture)
		slot.reset_requested.connect(func(_s: BindSlot) -> void: reset())
		row.add_child(slot)


func refresh() -> void:
	kb_slot.refresh()
	pad_slot.refresh()


## Shows a short note under the action name (conflict explanations).
func set_note(text: String, variation := "Warning") -> void:
	_note.text = text
	_note.theme_type_variation = variation
	_note.visible = text != ""


func capture(slot: BindSlot) -> void:
	if UiNav.capture_active():
		return
	set_note("")
	slot.set_capturing(true)
	UiNav.begin_capture(slot.pad, BindingsFlow.CAPTURE_SECONDS, func(ev: InputEvent) -> void:
		slot.set_capturing(false)
		if ev == null:
			Audio.sfx("ui_back")
			set_note("Unchanged.", "Caption")
			return
		var stolen := BindingsFlow.rebind(action, ev)
		Audio.sfx("ui_accept")
		rebound.emit(action, stolen, slot.pad))


func reset() -> void:
	var conflicts := BindingsFlow.reset_action(action)
	Audio.sfx("ui_accept")
	set_note("Defaults restored.", "Success")
	reset_done.emit(action, conflicts)
