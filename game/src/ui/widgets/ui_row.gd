class_name UiRow
extends PanelContainer
## Base for focusable list rows (option/slider/toggle/text/action rows): [chevron] Label ...... value.
## The whole row is ONE focus stop; left/right/accept are routed to the subclass, so a controller
## user never has to "enter" a row. Focus = gold border + 4% scale + chevron. Mouse hover focuses
## the row; clicks go to the subclass (`_on_click`). Up/down stay with Godot focus navigation.
## `help_title`/`help_text`/`help_extra` feed HelpPanel; `key` names the setting/action it edits.

signal value_changed(value)
signal activated

var label_text := ""
var help_title := ""
var help_text := ""
var help_extra := ""
var key := ""
var badge_text := ""                ## small right-side note ("Restart required", "Unbound")
var focus_scale := 1.02
var on_extra: Callable              ## X / Delete handler (settings: restore this option's default)
var _label: Label
var _value_box: HBoxContainer
var _badge: Label
var _row: HBoxContainer
var _tween: Tween
var _focused_style := "row_focus"
var _normal_style := "row"


func _init(label_ := "") -> void:
	label_text = label_
	help_title = label_
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, UiTheme.ROW_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", UiTheme.style(_normal_style))
	_row = UiTheme.hbox(UiTheme.GAP_M)
	add_child(_row)
	_label = UiTheme.label(label_, "BodyStrong")
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_stretch_ratio = 1.0
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_row.add_child(_label)
	_badge = UiTheme.label("", "Caption")
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.visible = false
	_row.add_child(_badge)
	_value_box = UiTheme.hbox(UiTheme.GAP_S)
	_value_box.alignment = BoxContainer.ALIGNMENT_END
	_value_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_box.size_flags_stretch_ratio = 0.9
	_row.add_child(_value_box)


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	pivot_offset = size * 0.5


func set_label(t: String) -> void:
	label_text = t
	_label.text = t


func set_badge(t: String, variation := "Caption") -> void:
	badge_text = t
	_badge.text = t
	_badge.theme_type_variation = variation
	_badge.visible = t != ""


func set_help(title: String, body: String, extra := "") -> UiRow:
	help_title = title
	help_text = body
	help_extra = extra
	return self


func value_box() -> HBoxContainer:
	return _value_box


func _on_mouse_entered() -> void:
	if focus_mode != Control.FOCUS_NONE and not has_focus() and is_visible_in_tree():
		grab_focus()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_FOCUS_ENTER:
			add_theme_stylebox_override("panel", UiTheme.style(_focused_style))
			if UiNav.user_initiated():
				Audio.sfx("ui_move")
			_animate_scale(focus_scale)
			queue_redraw()
			_on_focus_changed(true)
		NOTIFICATION_FOCUS_EXIT:
			add_theme_stylebox_override("panel", UiTheme.style(_normal_style))
			_animate_scale(1.0)
			queue_redraw()
			_on_focus_changed(false)


## Swap the style pair (e.g. capture mode in KeybindRow).
func set_styles(normal: String, focused: String) -> void:
	_normal_style = normal
	_focused_style = focused
	add_theme_stylebox_override("panel", UiTheme.style(focused if has_focus() else normal))


func _animate_scale(target: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if UiTheme.reduce_motion() or not is_inside_tree():
		scale = Vector2.ONE * target
		return
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * target, UiTheme.ANIM_FAST).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if not has_focus():
		return
	var h := size.y
	var s := clampf(h * 0.14, 7.0, 12.0)
	var cx := 18.0
	var cy := h * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(cx - s * 0.55, cy - s), Vector2(cx + s * 0.75, cy), Vector2(cx - s * 0.55, cy + s)]), UiTheme.GOLD_HI)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not has_focus():
				grab_focus()
			_on_click(mb)
			accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.shift_pressed:
			if _on_step(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1):
				accept_event()
		return
	if event.is_action_pressed("ui_accept", false, true):
		_on_accept()
		accept_event()
	elif event.is_action_pressed("ui_left", true, true):
		if _on_step(-1):
			accept_event()
	elif event.is_action_pressed("ui_right", true, true):
		if _on_step(1):
			accept_event()
	elif event.is_action_pressed("ui_extra", false, true):
		if _on_extra():
			accept_event()


# --- virtuals ----------------------------------------------------------------------------------

## A/Enter on the row.
func _on_accept() -> void:
	activated.emit()


## Left (-1) / right (+1). Return true when handled (prevents focus from moving sideways).
func _on_step(_dir: int) -> bool:
	return false


## X / Delete on the row ("restore default" in settings). Return true when handled.
func _on_extra() -> bool:
	if on_extra.is_valid():
		on_extra.call()
		return true
	return false


func _on_click(_ev: InputEventMouseButton) -> void:
	_on_accept()


func _on_focus_changed(_focused: bool) -> void:
	pass
