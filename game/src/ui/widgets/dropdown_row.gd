class_name DropdownRow
extends UiRow
## A single focus stop with a real dropdown. Browsing never applies intermediate
## display modes; only selecting an item emits value_changed.

var options: Array = []
var labels: Array[String] = []
var picker: OptionButton


func _init(label_ := "") -> void:
	super(label_)
	picker = OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	picker.fit_to_longest_item = false
	picker.custom_minimum_size = Vector2(280, 0)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(_selected)
	_value_box.add_child(picker)


func setup(opts: Array, names: Array, value) -> void:
	options = opts.duplicate()
	picker.clear()
	labels.clear()
	for i in opts.size():
		var text := str(names[i]) if i < names.size() else str(opts[i])
		labels.append(text)
		picker.add_item(text)
	set_value(value)


func set_value(value) -> void:
	for i in options.size():
		if str(options[i]) == str(value):
			picker.select(i)
			return


func value_text() -> String:
	return picker.text


func _selected(index: int) -> void:
	if index >= 0 and index < options.size():
		value_changed.emit(options[index])


func _on_accept() -> void:
	picker.show_popup()


func _on_click(_ev: InputEventMouseButton) -> void:
	_on_accept()


func _on_step(_dir: int) -> bool:
	_on_accept()
	return true
