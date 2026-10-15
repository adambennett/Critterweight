class_name ToggleRow
extends UiRow
## On/off switch: "Label ......  [ON  (o)]". A/Enter, left/right and clicks toggle. The switch
## shows the words ON/OFF and moves its knob, so state never depends on colour.

var on := false
var _switch: ToggleSwitch


func _init(label_ := "") -> void:
	super(label_)
	_switch = ToggleSwitch.new()
	_value_box.add_child(_switch)


func setup(current: bool) -> ToggleRow:
	on = current
	_switch.on = on
	_switch.queue_redraw()
	return self


func set_value(v: bool) -> void:
	on = v
	_switch.on = v
	_switch.queue_redraw()


func get_value() -> bool:
	return on


func value_text() -> String:
	return "On" if on else "Off"


func _toggle() -> void:
	on = not on
	_switch.on = on
	_switch.animate()
	Audio.sfx("ui_accept")
	value_changed.emit(on)


func _on_accept() -> void:
	_toggle()


func _on_step(dir: int) -> bool:
	var want := dir > 0
	if want != on:
		_toggle()
	else:
		Audio.sfx("ui_error")
	return true


func _on_click(_ev: InputEventMouseButton) -> void:
	_toggle()
