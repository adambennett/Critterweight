class_name OptionRow
extends UiRow
## Enum selector: "Label ......  ◀  Value  ▶". Left/right (D-pad, stick, arrows) cycle; A/Enter
## and a click on the value advance; the arrows are clickable. LB/RB are deliberately NOT used here
## (they switch tabs on tabbed screens). Position pips under the value show where you are in the list.

var options: Array = []
var labels: Array[String] = []
var index := 0
var wrap := true
var _value_label: Label
var _pips: OptionPips


func _init(label_ := "") -> void:
	super(label_)
	var left := ArrowButton.new(-1)
	left.pressed.connect(func() -> void: _step_from_mouse(-1))
	_value_box.add_child(left)
	var mid := UiTheme.vbox(2)
	mid.custom_minimum_size = Vector2(240, 0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_value_label = UiTheme.label("", "Value")
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(_value_label)
	_pips = OptionPips.new()
	mid.add_child(_pips)
	_value_box.add_child(mid)
	var right := ArrowButton.new(1)
	right.pressed.connect(func() -> void: _step_from_mouse(1))
	_value_box.add_child(right)


## opts: values; lbls: display strings (same length) or empty to use str(value).
func setup(opts: Array, lbls: Array, current) -> OptionRow:
	options = opts.duplicate()
	labels.clear()
	for i in options.size():
		labels.append(str(lbls[i]) if i < lbls.size() else str(options[i]))
	index = _find(current)
	_refresh()
	return self


func _find(v) -> int:
	for i in options.size():
		if str(options[i]) == str(v):
			return i
	return 0


func get_value():
	return options[index] if index >= 0 and index < options.size() else null


## Updates the shown value without emitting (e.g. Settings changed elsewhere).
func set_value(v) -> void:
	index = _find(v)
	_refresh()


func value_text() -> String:
	return labels[index] if index >= 0 and index < labels.size() else ""


func _refresh() -> void:
	_value_label.text = value_text()
	_pips.count = options.size()
	_pips.current = index
	_pips.visible = options.size() > 1 and options.size() <= 12
	_pips.queue_redraw()


func _step_from_mouse(dir: int) -> void:
	if not has_focus():
		grab_focus()
	_on_step(dir)


func _on_step(dir: int) -> bool:
	if options.size() <= 1:
		Audio.sfx("ui_error")
		return true
	var n := index + dir
	if wrap:
		n = posmod(n, options.size())
	else:
		n = clampi(n, 0, options.size() - 1)
	if n == index:
		Audio.sfx("ui_error")
		return true
	index = n
	_refresh()
	Audio.sfx("ui_move")
	_bump(dir)
	value_changed.emit(get_value())
	return true


func _on_accept() -> void:
	_on_step(1)


func _on_click(_ev: InputEventMouseButton) -> void:
	# the arrows handle their own clicks; a click anywhere else on the row advances
	_on_step(1)


## Brief gold flash of the value (container-safe feedback that the value changed).
func _bump(_dir: int) -> void:
	_value_label.modulate = UiTheme.GOLD_HI
	var tw := create_tween()
	tw.tween_property(_value_label, "modulate", Color.WHITE, UiTheme.ANIM_SLOW)
