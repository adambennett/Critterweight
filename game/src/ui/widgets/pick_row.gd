class_name PickRow
extends UiRow
## Row that opens a picker (e.g. character select): "Fighter ......  [icon] STOKE  the Boiler Newt  >".
## A/Enter/click emits `activated`; the owner opens the picker and calls set_choice() afterwards.

var _icon: TextureRect
var _name: Label
var _sub: Label


func _init(label_ := "") -> void:
	super(label_)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(44, 44)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_value_box.add_child(_icon)
	var col := UiTheme.vbox(0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# trimming labels report ~0 minimum width, so the column must expand to give them room
	_name = UiTheme.label("", "Value")
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_name)
	_sub = UiTheme.label("", "Caption")
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_sub)
	_value_box.add_child(col)
	_value_box.add_child(UiIcons.rect("forward", 26, UiTheme.MUTED))


func set_choice(title: String, subtitle := "", icon: Texture2D = null) -> PickRow:
	_name.text = title
	_sub.text = subtitle
	_sub.visible = subtitle != ""
	_icon.texture = icon
	_icon.visible = icon != null
	return self


func value_text() -> String:
	return _name.text


func _on_accept() -> void:
	Audio.sfx("ui_accept")
	activated.emit()
