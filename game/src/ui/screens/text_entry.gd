extends Screen
## Text entry modal ("text_entry") usable with any device: a text box for physical keyboards plus
## an on-screen keyboard for controllers (A types, X deletes, Y adds a space, LB/RB move the caret,
## Start confirms, B cancels). Explicit Confirm/Cancel buttons for everyone.
## params: {title, value, max_len, secret, numeric, min, max, help, allow_empty (default true),
##          validate: Callable(text) -> String error ("" = ok), callback(confirmed: bool, text: String)}

const ROWS := ["1234567890", "QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM-_.", ]
const NUM_ROWS := ["123", "456", "789", "0"]

var _edit: LineEdit
var _error: Label
var _cb: Callable
var _validate: Callable
var _numeric := false
var _allow_empty := true
var _min := 0
var _max := 0
var _shift := true
var _letter_keys: Array[UiButton] = []
var _first_key: UiButton
var _confirm: UiButton
var _done := false


func on_enter(p: Dictionary) -> void:
	is_overlay = true
	add_dimmer()
	_cb = p.get("callback", Callable())
	_validate = p.get("validate", Callable())
	_numeric = bool(p.get("numeric", false))
	_allow_empty = bool(p.get("allow_empty", true))
	_min = int(p.get("min", 0))
	_max = int(p.get("max", 65535))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UiTheme.panel("PanelDialog")
	panel.custom_minimum_size = Vector2(980, 0)
	center.add_child(panel)
	var col := UiTheme.vbox(UiTheme.GAP_M)
	panel.add_child(col)
	col.add_child(UiTheme.label(str(p.get("title", "Enter text")).to_upper(), "H2"))
	var help := str(p.get("help", ""))
	if help != "":
		col.add_child(UiTheme.label(help, "Caption", true))
	_edit = LineEdit.new()
	_edit.text = str(p.get("value", ""))
	_edit.max_length = int(p.get("max_len", 32))
	_edit.secret = bool(p.get("secret", false))
	_edit.custom_minimum_size = Vector2(0, 72)
	_edit.caret_blink = true
	_edit.select_all_on_focus = false
	_edit.context_menu_enabled = false
	_edit.placeholder_text = "Type here"
	_edit.text_submitted.connect(func(_t: String) -> void: _confirm_entry())
	_edit.text_changed.connect(func(_t: String) -> void: _error.text = "")
	col.add_child(_edit)
	_error = UiTheme.label("", "Danger", true)
	col.add_child(_error)
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var rows := NUM_ROWS if _numeric else ROWS
	grid.columns = 3 if _numeric else 10
	for r in rows:
		for ch in str(r):
			var k := _key(ch)
			grid.add_child(k)
			if _first_key == null:
				_first_key = k
			if ch.to_upper() != ch.to_lower():
				_letter_keys.append(k)
	var keyrow := HBoxContainer.new()
	keyrow.alignment = BoxContainer.ALIGNMENT_CENTER
	keyrow.add_child(grid)
	col.add_child(keyrow)
	var special := UiTheme.hbox(UiTheme.GAP_S)
	special.alignment = BoxContainer.ALIGNMENT_CENTER
	if not _numeric:
		var shift := _special("Shift", func() -> void: _toggle_shift())
		special.add_child(shift)
		special.add_child(_special("Space", func() -> void: _type(" ")))
	special.add_child(_special("Delete", func() -> void: _backspace()))
	special.add_child(_special("Clear", func() -> void:
		_edit.text = ""
		_edit.caret_column = 0))
	col.add_child(special)
	var actions := UiTheme.hbox(UiTheme.GAP_M)
	actions.alignment = BoxContainer.ALIGNMENT_END
	var cancel := UiButton.new("Cancel")
	cancel.custom_minimum_size = Vector2(220, 64)
	cancel.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel.pressed.connect(_cancel)
	actions.add_child(cancel)
	_confirm = UiButton.new("Confirm", "PrimaryButton")
	_confirm.custom_minimum_size = Vector2(240, 64)
	_confirm.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.pressed.connect(_confirm_entry)
	actions.add_child(_confirm)
	col.add_child(actions)
	var bar := PromptBar.new()
	bar.set_prompts([{"actions": ["ui_accept"], "text": "Type"}, {"actions": ["ui_extra"], "text": "Delete", "call": _backspace},
		{"actions": ["ui_alt"], "text": "Space", "call": func() -> void: _type(" ")},
		{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Move cursor"},
		{"actions": ["ui_cancel"], "text": "Cancel", "call": _cancel}])
	col.add_child(bar)
	_edit.caret_column = _edit.text.length()
	_refresh_case()
	play_intro()


func default_focus() -> Control:
	if PromptGlyph.wants_pad() or Controls.last_device == "gamepad":
		return _first_key
	return _edit


func _key(ch: String) -> UiButton:
	var b := UiButton.new(ch, "FlatButton")
	b.custom_minimum_size = Vector2(76, 68)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.show_chevron = false
	b.focus_scale = 1.12
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(UiTheme.SURFACE, 0.95), 6, 6.0, 4.0))
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.SURFACE_HI, 6, 6.0, 4.0))
	b.add_theme_stylebox_override("focus", UiTheme.focus_ring())
	b.add_theme_font_override("font", UiTheme.font("label"))
	b.pressed.connect(func() -> void: _type(b.text))
	return b


func _special(label: String, cb: Callable) -> UiButton:
	var b := UiButton.new(label)
	b.custom_minimum_size = Vector2(170, 60)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.show_chevron = false
	b.pressed.connect(cb)
	return b


func _toggle_shift() -> void:
	_shift = not _shift
	_refresh_case()


func _refresh_case() -> void:
	for k in _letter_keys:
		k.text = k.text.to_upper() if _shift else k.text.to_lower()


func _type(s: String) -> void:
	if _edit.max_length > 0 and _edit.text.length() >= _edit.max_length:
		Audio.sfx("ui_error")
		return
	_edit.insert_text_at_caret(s)
	if _shift and s.length() == 1 and s.to_upper() != s.to_lower() and _edit.text.length() == 1:
		_shift = false
		_refresh_case()


func _backspace() -> void:
	var c := _edit.caret_column
	if c <= 0:
		Audio.sfx("ui_error")
		return
	_edit.text = _edit.text.substr(0, c - 1) + _edit.text.substr(c)
	_edit.caret_column = c - 1


func entered_text() -> String:
	return _edit.text


func _confirm_entry() -> void:
	if _done:
		return
	var t := _edit.text.strip_edges()
	var err := ""
	if t == "" and not _allow_empty:
		err = "This can't be empty."
	elif _numeric and t != "":
		if not t.is_valid_int():
			err = "Numbers only."
		elif int(t) < _min or int(t) > _max:
			err = "Enter a number from %d to %d." % [_min, _max]
	if err == "" and _validate.is_valid():
		err = str(_validate.call(t))
	if err != "":
		_error.text = err
		Audio.sfx("ui_error")
		return
	_done = true
	var cb := _cb
	App.pop()
	if cb.is_valid():
		cb.call(true, t)


func _cancel() -> void:
	if _done:
		return
	_done = true
	var cb := _cb
	App.pop()
	if cb.is_valid():
		cb.call(false, "")


func on_back() -> bool:
	_cancel()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not is_top():
		return
	var in_edit := get_viewport().gui_get_focus_owner() == _edit
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		# controller shortcuts: Start confirms, X deletes, Y space, LB/RB move the caret
		var b := (event as InputEventJoypadButton).button_index
		var handled := true
		match b:
			JOY_BUTTON_START:
				_confirm_entry()
			JOY_BUTTON_X:
				_backspace()
			JOY_BUTTON_Y:
				_type(" ")
			JOY_BUTTON_LEFT_SHOULDER:
				_edit.caret_column = maxi(0, _edit.caret_column - 1)
			JOY_BUTTON_RIGHT_SHOULDER:
				_edit.caret_column = mini(_edit.text.length(), _edit.caret_column + 1)
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventKey and (event as InputEventKey).pressed and not in_edit:
		# physical typing while an on-screen key has focus goes into the text box
		var k := event as InputEventKey
		if k.unicode >= 32 and not k.is_action("ui_cancel"):
			get_viewport().set_input_as_handled()
			_edit.grab_focus()
			_type(char(k.unicode))
			return
		if k.keycode == KEY_BACKSPACE or k.keycode == KEY_DELETE:
			get_viewport().set_input_as_handled()
			_backspace()
			return
	super(event)
