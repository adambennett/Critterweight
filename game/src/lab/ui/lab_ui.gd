class_name LabUi
extends RefCounted
## Small self-contained widget helpers for the AI Lab screen (plain Godot controls, minimal
## styling, so the shared UI theme can be adopted later by replacing these few functions).
## Every widget is focusable and works with mouse, keyboard and a controller (sliders and
## option buttons respond to the D-pad/stick; buttons to A / Enter / click).

const PAD := 10


static func label(text: String, size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if min_w > 0.0:
		b.custom_minimum_size = Vector2(min_w, 0)
	b.pressed.connect(cb)
	return b


static func option(items: Array, selected := 0) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_ALL
	for it in items:
		o.add_item(str(it))
	if items.size() > 0:
		o.select(clampi(selected, 0, items.size() - 1))
	o.fit_to_longest_item = false
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return o


## A slider with a live value label. `fmt` is a format string for the value ("%d", "%.2f").
static func slider(min_v: float, max_v: float, step: float, value: float, fmt: String, on_change: Callable = Callable()) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_ALL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(180, 24)
	s.name = "Slider"
	var v := Label.new()
	v.custom_minimum_size = Vector2(90, 0)
	v.text = fmt % value
	v.name = "Value"
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % x
		if on_change.is_valid():
			on_change.call(x))
	box.add_child(s)
	box.add_child(v)
	return box


static func slider_of(box: Control) -> HSlider:
	return box.get_node("Slider") as HSlider


static func row(parent: Container, caption: String, control: Control, help := "") -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", PAD)
	var l := label(caption)
	l.custom_minimum_size = Vector2(230, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(control)
	if help != "":
		r.tooltip_text = help
		control.tooltip_text = help
	parent.add_child(r)
	return r


static func header(text: String) -> Label:
	var l := label(text, 26, Color(1.0, 0.82, 0.45))
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


static func panel_box() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.085, 0.13, 0.94)
	sb.border_color = Color(0.32, 0.27, 0.38)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	return p


static func rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = false
	r.scroll_active = true
	r.focus_mode = Control.FOCUS_ALL
	r.selection_enabled = true
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


static func fmt_time(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%ds" % s


static func state_color(state: String) -> String:
	match state:
		"running":
			return "#7fe08a"
		"paused":
			return "#f0d070"
		"completed":
			return "#8fc8ff"
		"failed", "interrupted":
			return "#ff8a7a"
		"cancelled":
			return "#c0b8c8"
	return "#e0e0e0"
