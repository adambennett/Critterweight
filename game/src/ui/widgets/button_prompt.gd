class_name ButtonPrompt
extends HBoxContainer
## "[glyph] Label" prompt for one or more input actions (e.g. ui_accept -> "Select",
## ui_tab_prev + ui_tab_next -> "Tabs"). Shows the CURRENT binding on the CURRENT device: it reads
## Controls.prompt_for()/the InputMap and refreshes instantly on Controls.device_changed,
## Controls.bindings_changed and the "Button prompts" setting. Clickable: mouse users can press a
## footer prompt ("Back") instead of the key, so every prompt is also a working control.

signal pressed

var actions: Array[String] = []
var text := ""
var glyph_size := 40.0
var clickable := true
var _label: Label
var _glyph_box: HBoxContainer
var _hover := false


func _init(actions_: Array = [], text_ := "", size_du := 40.0) -> void:
	for a in actions_:
		actions.append(str(a))
	text = text_
	glyph_size = size_du
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_glyph_box = HBoxContainer.new()
	_glyph_box.add_theme_constant_override("separation", 4)
	_glyph_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph_box)
	_label = UiTheme.label(text, "CaptionStrong")
	add_child(_label)


func _ready() -> void:
	Controls.device_changed.connect(_on_device_changed)
	Controls.bindings_changed.connect(refresh)
	Settings.changed.connect(_on_setting)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	refresh()


func set_text(t: String) -> void:
	text = t
	if _label:
		_label.text = t


func set_actions(a: Array) -> void:
	actions.clear()
	for x in a:
		actions.append(str(x))
	refresh()


## The binding names currently shown (e.g. "A", "Enter"), from Controls.prompt_for().
func binding_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for a in actions:
		parts.append(Controls.prompt_for(a))
	return "/".join(parts)


func current_style() -> String:
	return PromptGlyph.style_now()


func refresh() -> void:
	if _glyph_box == null:
		return
	for c in _glyph_box.get_children():
		c.queue_free()
	var st := PromptGlyph.style_now()
	for a in actions:
		var ev := PromptGlyph.event_for(a)
		var g := PromptGlyph.new(ev, st if ev != null and PromptGlyph.is_pad_event(ev) == PromptGlyph.wants_pad() else "", glyph_size)
		_glyph_box.add_child(g)
	tooltip_text = "%s: %s" % [binding_text(), text]


func _on_device_changed(_kind: String) -> void:
	refresh()


func _on_setting(key: String, _v) -> void:
	if key == "input.prompts":
		refresh()


func _gui_input(event: InputEvent) -> void:
	if not clickable:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()


func _draw() -> void:
	if _hover and clickable and pressed.get_connections().size() > 0:
		var sb := UiTheme.box(Color(UiTheme.SURFACE_HI, 0.8), 6)
		draw_style_box(sb, Rect2(Vector2(-8, -4), size + Vector2(16, 8)))
