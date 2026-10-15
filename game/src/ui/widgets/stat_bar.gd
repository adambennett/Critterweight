class_name StatBar
extends HBoxContainer
## "HEALTH  ■■■■■■■□□□  110" — label, 10 segments (count readable without colour), raw value.

var _label: Label
var _bar: StatSegments
var _value: Label


func _init(label_ := "", fraction := 0.5, value_text := "", color := UiTheme.GOLD) -> void:
	add_theme_constant_override("separation", UiTheme.GAP_M)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiTheme.label(label_.to_upper(), "Eyebrow")
	_label.add_theme_color_override("font_color", UiTheme.MUTED)
	_label.custom_minimum_size = Vector2(150, 0)
	add_child(_label)
	_bar = StatSegments.new()
	_bar.fraction = clampf(fraction, 0.0, 1.0)
	_bar.color = color
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_bar)
	_value = UiTheme.label(value_text, "Value")
	_value.custom_minimum_size = Vector2(90, 0)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_value)


func set_stat(fraction: float, value_text: String) -> void:
	_bar.fraction = clampf(fraction, 0.0, 1.0)
	_bar.queue_redraw()
	_value.text = value_text
