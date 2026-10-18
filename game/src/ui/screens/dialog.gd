extends Screen
## Generic modal ("dialog"), used by App.dialog() and by flows needing a confirmation. Focus stays
## inside the dialog (screens below are focus/mouse-disabled); left/right moves between buttons and
## wraps; B/Esc picks the cancel button. Optional countdown auto-picks `timeout_choice` (display
## changes use 15 s with "revert").
## params: {title, body, buttons: [{label, id, danger?, cancel?, default?}], callback(id),
##          kind: info|warning|error|danger, countdown: seconds, timeout_choice: id}
## The body may contain "{s}" which is replaced by the seconds left.

var _callback: Callable
var _buttons: Array[UiButton] = []
var _ids: Array[String] = []
var _cancel_id := ""
var _default_index := 0
var _remaining := 0.0
var _countdown := 0.0
var _timeout_choice := ""
var _body: Label
var _body_template := ""
var _bar: ProgressBar
var _chosen := false
var _panel: PanelContainer


func on_enter(p: Dictionary) -> void:
	is_overlay = true
	add_dimmer()
	_callback = p.get("callback", Callable())
	_countdown = float(p.get("countdown", 0.0))
	_remaining = _countdown
	_timeout_choice = str(p.get("timeout_choice", ""))
	var kind := str(p.get("kind", "info"))
	_cancel_id = str(p.get("cancel_id", ""))
	var buttons: Array = p.get("buttons", [])
	if buttons.is_empty():
		buttons = [{"label": "OK", "id": "ok"}]
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	var danger := kind == "danger" or kind == "error"
	for b in buttons:
		if bool((b as Dictionary).get("danger", false)):
			danger = true
	_panel.theme_type_variation = "PanelDialogDanger" if danger else "PanelDialog"
	_panel.custom_minimum_size = Vector2(1040 if buttons.size() > 3 else 860, 0)
	center.add_child(_panel)
	var col := UiTheme.vbox(UiTheme.GAP_M)
	_panel.add_child(col)
	var head := UiTheme.hbox(UiTheme.GAP_M)
	var icon := {"info": "info", "warning": "warning", "error": "error", "danger": "warning"}.get(kind, "info") as String
	var icon_col: Color = UiTheme.DANGER if danger else (UiTheme.WARNING if kind == "warning" else UiTheme.RIM)
	head.add_child(UiIcons.rect(icon, 52, icon_col))
	var title := UiTheme.label(str(p.get("title", "")), "H2", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	col.add_child(head)
	_body_template = str(p.get("body", ""))
	_body = UiTheme.label("", "Body", true)
	_body.custom_minimum_size = Vector2(760, 0)
	col.add_child(_body)
	if _countdown > 0.0:
		_bar = ProgressBar.new()
		_bar.show_percentage = false
		_bar.custom_minimum_size = Vector2(0, 14)
		_bar.max_value = _countdown
		_bar.value = _countdown
		col.add_child(_bar)
	_update_body()
	col.add_child(UiTheme.spacer(false, 6))
	# Choice lists use a bounded grid; a horizontal button row grows off screen.
	var row := GridContainer.new()
	row.columns = mini(3, buttons.size())
	row.add_theme_constant_override("h_separation", UiTheme.GAP_S)
	row.add_theme_constant_override("v_separation", UiTheme.GAP_S)
	col.add_child(row)
	for i in buttons.size():
		var bd: Dictionary = buttons[i]
		var id := str(bd.get("id", str(i)))
		var b := UiButton.new(str(bd.get("label", id)), "DangerButton" if bool(bd.get("danger", false)) else ("PrimaryButton" if bool(bd.get("primary", false)) else ""))
		b.custom_minimum_size = Vector2(220, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.route = id
		b.pressed.connect(_choose.bind(id))
		row.add_child(b)
		_buttons.append(b)
		_ids.append(id)
		if bool(bd.get("cancel", false)):
			_cancel_id = id
		if bool(bd.get("default", false)):
			_default_index = i
	if _cancel_id == "":
		_cancel_id = _ids[_ids.size() - 1]
	# keep focus inside the button row (wrap left/right, block up/down)
	for i in _buttons.size():
		var b := _buttons[i]
		b.focus_neighbor_left = b.get_path_to(_buttons[posmod(i - 1, _buttons.size())])
		b.focus_neighbor_right = b.get_path_to(_buttons[posmod(i + 1, _buttons.size())])
		b.focus_neighbor_top = b.get_path_to(_buttons[maxi(0, i - row.columns)] if i >= row.columns else b)
		b.focus_neighbor_bottom = b.get_path_to(_buttons[mini(i + row.columns, _buttons.size() - 1)] if i + row.columns < _buttons.size() else b)
	var prompts := PromptBar.new()
	prompts.set_prompts([{"actions": ["ui_accept"], "text": "Choose"},
		{"actions": ["ui_cancel"], "text": _label_for(_cancel_id), "call": func() -> void: _choose(_cancel_id)}])
	col.add_child(prompts)
	play_intro()
	if not UiTheme.reduce_motion():
		_panel.pivot_offset = Vector2(430, 120)
		_panel.scale = Vector2.ONE * 0.96
		create_tween().tween_property(_panel, "scale", Vector2.ONE, UiTheme.ANIM).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.sfx("ui_error" if danger else "ui_accept")


func _label_for(id: String) -> String:
	var i := _ids.find(id)
	return _buttons[i].text if i >= 0 else "Cancel"


func default_focus() -> Control:
	return _buttons[_default_index] if _default_index < _buttons.size() else null


func button_ids() -> Array[String]:
	return _ids.duplicate()


func seconds_left() -> float:
	return _remaining


func _update_body() -> void:
	_body.text = _body_template.replace("{s}", str(ceili(_remaining)))
	_body.visible = _body.text != ""


func _process(dt: float) -> void:
	if _countdown <= 0.0 or _chosen:
		return
	_remaining = maxf(0.0, _remaining - dt)
	if _bar:
		_bar.value = _remaining
	_update_body()
	if _remaining <= 0.0:
		_choose(_timeout_choice if _timeout_choice != "" else _cancel_id)


## Picks a button: closes the dialog first, then reports the id (the callback may open new screens).
func choose(id: String) -> void:
	_choose(id)


func _choose(id: String) -> void:
	if _chosen:
		return
	_chosen = true
	var cb := _callback
	if App.top_screen() == self:
		App.pop()
	if cb.is_valid():
		cb.call(id)


func on_back() -> bool:
	_choose(_cancel_id)
	return true
