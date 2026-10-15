extends Screen
## Living style guide (development/QA only; open with `-- --ui-screen gallery`): every widget,
## icon and glyph family on one scrollable page so art and focus states can be reviewed and
## captured. Not reachable from the player menus.

var _scroll: FocusScroll


func on_enter(_p: Dictionary) -> void:
	add_backdrop_gradient(0.97, 0.9)
	var f := build_frame("Development", "UI gallery", std_prompts([{"actions": ["ui_left", "ui_right"], "text": "Adjust"}]))
	var body: VBoxContainer = f["body"]
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	_scroll = FocusScroll.new(14)
	_scroll.size_flags_stretch_ratio = 1.3
	cols.add_child(_scroll)
	var right := UiTheme.vbox(UiTheme.GAP_M)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_build_widgets(_scroll.content)
	_build_art(right)
	play_intro()


func default_focus() -> Control:
	return _scroll.focusables()[0] if not _scroll.focusables().is_empty() else null


func _build_widgets(c: VBoxContainer) -> void:
	c.add_child(UiTheme.label("BUTTONS", "Eyebrow"))
	var brow := UiTheme.hbox(UiTheme.GAP_M)
	brow.add_child(UiButton.new("Default"))
	brow.add_child(UiButton.new("Start fight", "PrimaryButton"))
	brow.add_child(UiButton.new("Delete", "DangerButton"))
	var dis := UiButton.new("Disabled")
	dis.disabled = true
	brow.add_child(dis)
	c.add_child(brow)
	var mi := UiButton.new("Fight", "MenuItem", "fight")
	c.add_child(mi)
	c.add_child(UiButton.new("Quick Fight", "SubItem", "quick"))
	c.add_child(UiTheme.label("ROWS", "Eyebrow"))
	c.add_child(OptionRow.new("Option row").setup(["windowed", "borderless", "fullscreen"], ["Windowed", "Borderless", "Fullscreen"], "borderless").set_help("Option row", "Left/right cycles; the arrows are clickable."))
	var s := SliderRow.new("Slider row")
	s.setup(0, 100, 5, 65, SliderRow.Fmt.PERCENT)
	c.add_child(s)
	c.add_child(ToggleRow.new("Toggle row").setup(true))
	c.add_child(TextFieldRow.new("Text field row").setup("Rookie", 20))
	var kb := KeybindRow.new("light")
	c.add_child(kb)
	var toast_btn := UiButton.new("Show a toast of each kind")
	toast_btn.pressed.connect(func() -> void:
		UiNav.toast("Info: settings saved.", "info")
		UiNav.toast("Success: profile created.", "success")
		UiNav.toast("Warning: controller disconnected.", "warning")
		UiNav.toast("Error: could not write the file.", "error"))
	c.add_child(toast_btn)
	var dlg := UiButton.new("Open a dialog")
	dlg.pressed.connect(func() -> void:
		App.dialog("Example dialog", "Dialogs keep controller focus inside until they close.", [{"label": "OK", "id": "ok"}, {"label": "Cancel", "id": "cancel", "cancel": true}]))
	c.add_child(dlg)
	_scroll.wrap_focus.call_deferred()


func _build_art(c: VBoxContainer) -> void:
	c.add_child(UiTheme.label("ELEMENTS", "Eyebrow"))
	var er := HFlowContainer.new()
	er.add_theme_constant_override("h_separation", 26)
	er.add_theme_constant_override("v_separation", 10)
	for e in ["scorch", "brine", "static", "sludge", "grit", "gale"]:
		er.add_child(UiIcons.element_badge(e, 48))
	c.add_child(er)
	c.add_child(UiTheme.label("ICONS", "Eyebrow"))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var names := ["fight", "campaign", "online", "tutorial", "create", "lab", "mods", "profile", "settings", "credits", "quit",
		"back", "forward", "lock", "warning", "check", "info", "error", "star", "random", "gamepad", "keyboard", "spectate",
		"practice", "versus", "quick", "bot", "trophy", "can", "restart", "plus", "close", "edit", "folder", "copy", "arena", "rules", "team"]
	for n in names:
		var r := UiIcons.rect(n, 44)
		r.tooltip_text = n
		grid.add_child(r)
	c.add_child(grid)
	c.add_child(UiTheme.label("GLYPHS: XBOX / PLAYSTATION / KEYBOARD & MOUSE", "Eyebrow"))
	var pad_events: Array[InputEvent] = []
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
			JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_START, JOY_BUTTON_BACK]:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		pad_events.append(jb)
	for a in [[JOY_AXIS_TRIGGER_LEFT, 1.0], [JOY_AXIS_TRIGGER_RIGHT, 1.0], [JOY_AXIS_LEFT_X, -1.0], [JOY_AXIS_RIGHT_Y, 1.0]]:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		pad_events.append(jm)
	for st in ["xbox", "playstation"]:
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 10)
		for ev in pad_events:
			row.add_child(PromptGlyph.new(ev, st, 44.0))
		c.add_child(row)
	var krow := HFlowContainer.new()
	krow.add_theme_constant_override("h_separation", 10)
	for k in [KEY_ENTER, KEY_ESCAPE, KEY_SPACE, KEY_SHIFT, KEY_J, KEY_Q, KEY_E, KEY_TAB, KEY_LEFT, KEY_UP, KEY_DELETE]:
		var ke := InputEventKey.new()
		ke.keycode = k
		krow.add_child(PromptGlyph.new(ke, "keyboard", 44.0))
	for mbi in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var me := InputEventMouseButton.new()
		me.button_index = mbi
		krow.add_child(PromptGlyph.new(me, "keyboard", 44.0))
	c.add_child(krow)
	c.add_child(UiTheme.label("TEAMS & STATS", "Eyebrow"))
	var tr := UiTheme.hbox(UiTheme.GAP_S)
	for t in 4:
		tr.add_child(TeamChip.new(t, 44))
	tr.add_child(TeamChip.new(-1, 44))
	c.add_child(tr)
	c.add_child(StatBar.new("Health", 0.7, "110"))
	c.add_child(StatBar.new("Speed", 0.45, "3.4"))
	var wm := Wordmark.new(64.0)
	wm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.add_child(wm)
