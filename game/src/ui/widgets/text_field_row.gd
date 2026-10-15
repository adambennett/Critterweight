class_name TextFieldRow
extends UiRow
## Text value row: "Label ......  Rookie  [edit]". A/Enter or a click opens the "text_entry" modal:
## a text box for the keyboard plus an on-screen keyboard and explicit Confirm/Cancel for controller
## users (no device needs the other). Secret values are masked; numeric fields accept digits only.

var value := ""
var max_length := 32
var secret := false
var numeric := false
var min_number := 0
var max_number := 65535
var placeholder := "(empty)"
var _value_label: Label


func _init(label_ := "") -> void:
	super(label_)
	_value_label = UiTheme.label("", "Value")
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_box.add_child(_value_label)
	_value_box.add_child(UiIcons.rect("edit", 30, UiTheme.MUTED))


func setup(current: String, max_len := 32, is_secret := false) -> TextFieldRow:
	value = current
	max_length = max_len
	secret = is_secret
	_refresh()
	return self


func set_value(v: String) -> void:
	value = v
	_refresh()


func get_value() -> String:
	return value


func value_text() -> String:
	if value == "":
		return placeholder
	return "•".repeat(mini(value.length(), 12)) if secret else value


func _refresh() -> void:
	_value_label.text = value_text()
	_value_label.theme_type_variation = "BodyMuted" if value == "" else "Value"


func _on_accept() -> void:
	Audio.sfx("ui_accept")
	App.push("text_entry", {"title": label_text, "value": value, "max_len": max_length, "secret": secret,
		"numeric": numeric, "min": min_number, "max": max_number, "help": help_text,
		"callback": _on_entered})


func _on_entered(confirmed: bool, text: String) -> void:
	if not confirmed or text == value:
		return
	value = text
	_refresh()
	value_changed.emit(value)
