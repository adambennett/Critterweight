class_name LabUi
extends RefCounted
## Small widget helpers for the AI Lab screen on top of the shared UiTheme (text styles are theme
## type variations — Body, Caption, H3, Eyebrow — so the text-size setting rescales them live and
## nothing drops below the 28 du legibility floor). Every widget is focusable and works with mouse,
## keyboard and a controller (sliders and option buttons respond to the D-pad/stick; buttons to
## A / Enter / click).

const PAD := 12


## Makes text from files, mods or the player inert in BBCode ("[" -> "[lb]") before it goes into
## a rich text panel, so a policy name or description cannot restyle or hide the panel's text.
static func esc(v) -> String:
	return str(v).replace("[", "[lb]")


## Paragraph text (wraps). `style`: Body | BodyStrong | BodyMuted | Caption | CaptionStrong | H3 | Eyebrow ...
static func label(text: String, style := "Body", color := Color(0, 0, 0, 0)) -> Label:
	var l := UiTheme.label(text, style, true)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


## Single-line label that never wraps (safe inside HBoxContainers).
static func caption(text: String, style := "Body") -> Label:
	return UiTheme.label(text, style, false)


static func button(text: String, cb: Callable, min_w := 0.0, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if variation != "":
		b.theme_type_variation = variation
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
	box.add_theme_constant_override("separation", PAD)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_ALL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(220, 36)
	s.name = "Slider"
	var v := UiTheme.label(fmt % value, "Value")
	v.custom_minimum_size = Vector2(150, 0)
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


static func row(parent: Container, caption_text: String, control: Control, help := "") -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", PAD)
	var l := UiTheme.label(caption_text, "Body")
	l.custom_minimum_size = Vector2(330, 0)
	r.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(control)
	if help != "":
		r.tooltip_text = help
		control.tooltip_text = help
	parent.add_child(r)
	return r


static func header(text: String) -> Label:
	return UiTheme.label(text.to_upper(), "Eyebrow")


static func panel_box() -> PanelContainer:
	return UiTheme.panel("PanelSolid")


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
			return "#" + UiTheme.SUCCESS.to_html(false)
		"paused":
			return "#" + UiTheme.WARNING.to_html(false)
		"completed":
			return "#" + UiTheme.RIM.to_html(false)
		"failed", "interrupted":
			return "#" + UiTheme.DANGER.to_html(false)
		"cancelled":
			return "#" + UiTheme.MUTED.to_html(false)
	return "#" + UiTheme.TEXT.to_html(false)
