class_name SliderRow
extends UiRow
## Numeric slider: "Label ......  [=====o----]  80%". Left/right step (holding repeats via UiNav and
## accelerates after a moment); the bar is draggable/clickable with the mouse. A/Enter does nothing
## special (it is a focus stop, not a button). value_changed fires on every step; `committed` fires
## once the user stops adjusting (debounced) so callers can persist without writing every step.

signal committed(value: float)

enum Fmt { PERCENT, PERCENT_OF_ONE, DECIMAL2, MULT, INT, SECONDS }

var min_value := 0.0
var max_value := 1.0
var step := 0.1
var value := 0.0
var fmt := Fmt.PERCENT_OF_ONE
var zero_text := ""                 ## e.g. "Off" when the value is 0
var _slider: HSlider
var _value_label: Label
var _commit_timer: Timer
var _hold_steps := 0
var _last_step_ms := 0
var _syncing := false


func _init(label_ := "") -> void:
	super(label_)
	_slider = HSlider.new()
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.custom_minimum_size = Vector2(300, 34)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.mouse_filter = Control.MOUSE_FILTER_STOP
	_slider.value_changed.connect(_on_slider_changed)
	_slider.drag_ended.connect(func(_changed: bool) -> void: _commit_now())
	_value_box.add_child(_slider)
	_value_label = UiTheme.label("", "Value")
	_value_label.custom_minimum_size = Vector2(110, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_box.add_child(_value_label)
	_commit_timer = Timer.new()
	_commit_timer.one_shot = true
	_commit_timer.wait_time = 0.45
	_commit_timer.timeout.connect(_commit_now)
	add_child(_commit_timer)


func setup(min_v: float, max_v: float, step_v: float, current: float, format := Fmt.PERCENT_OF_ONE) -> SliderRow:
	min_value = min_v
	max_value = max_v
	step = step_v
	fmt = format
	_syncing = true
	_slider.min_value = min_v
	_slider.max_value = max_v
	_slider.step = step_v
	_slider.value = current
	_syncing = false
	value = _snap(current)
	_refresh()
	return self


func set_value(v: float) -> void:
	value = _snap(v)
	_syncing = true
	_slider.value = value
	_syncing = false
	_refresh()


func get_value() -> float:
	return value


func _snap(v: float) -> float:
	var s := clampf(v, min_value, max_value)
	if step > 0.0:
		s = clampf(min_value + snappedf(s - min_value, step), min_value, max_value)
	return s


func value_text() -> String:
	if zero_text != "" and is_zero_approx(value):
		return zero_text
	match fmt:
		Fmt.PERCENT:
			return "%d%%" % roundi(value)
		Fmt.PERCENT_OF_ONE:
			return "%d%%" % roundi(value * 100.0)
		Fmt.DECIMAL2:
			return "%.2f" % value
		Fmt.MULT:
			return "%.2fx" % value
		Fmt.SECONDS:
			return "%d s" % roundi(value)
	return "%d" % roundi(value)


func _refresh() -> void:
	_value_label.text = value_text()


func _on_slider_changed(v: float) -> void:
	if _syncing:
		return
	var nv := _snap(v)
	if is_equal_approx(nv, value):
		return
	value = nv
	_refresh()
	value_changed.emit(value)
	_commit_timer.start()


func _on_step(dir: int) -> bool:
	var now := Time.get_ticks_msec()
	_hold_steps = _hold_steps + 1 if now - _last_step_ms < 220 else 0
	_last_step_ms = now
	var mult := 1.0
	if _hold_steps > 12:
		mult = 4.0
	elif _hold_steps > 5:
		mult = 2.0
	var nv := _snap(value + dir * step * mult)
	if is_equal_approx(nv, value):
		Audio.sfx("ui_error")
		return true
	value = nv
	_syncing = true
	_slider.value = value
	_syncing = false
	_refresh()
	Audio.sfx("ui_move")
	value_changed.emit(value)
	_commit_timer.start()
	return true


func _on_accept() -> void:
	activated.emit()


func _on_click(_ev: InputEventMouseButton) -> void:
	pass


func _commit_now() -> void:
	_commit_timer.stop()
	committed.emit(value)
