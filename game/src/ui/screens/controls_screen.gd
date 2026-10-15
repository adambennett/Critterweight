extends Screen
## Controls reference ("controls"): every gameplay action with its live keyboard & mouse and
## controller bindings (glyphs + names), readable from the pause menu or the main menu, with a
## shortcut to rebinding in Settings › Controls. Rows are focus stops so the list scrolls with focus.

var _scroll: FocusScroll
var _in_game := false


func on_enter(p: Dictionary) -> void:
	_in_game = bool(p.get("in_game", false)) or MatchFlow.match_running()
	if _in_game:
		add_dimmer(0.93)
	else:
		MenuBackdrop.ensure()
		add_backdrop_gradient(0.97, 0.8)
	var f := build_frame("Reference", "Controls")
	(f["prompts"] as PromptBar).set_prompts([{"actions": ["ui_alt"], "text": "Change bindings", "call": _open_settings},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back}])
	var body: VBoxContainer = f["body"]
	var head := UiTheme.hbox(UiTheme.GAP_M)
	var a := UiTheme.label("ACTION", "Caption")
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(UiTheme.spacer(false, 40))
	head.add_child(a)
	for t in ["KEYBOARD & MOUSE", "CONTROLLER"]:
		var l := UiTheme.label(str(t), "Caption")
		l.custom_minimum_size = Vector2(380, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(l)
	head.add_child(UiTheme.spacer(false, 30))
	body.add_child(head)
	var panel := UiTheme.panel("PanelSolid", 14.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_scroll = FocusScroll.new(6)
	panel.add_child(_scroll)
	_build()
	Controls.bindings_changed.connect(_build)
	Controls.device_changed.connect(_on_device_changed)
	play_intro()


func _on_device_changed(_kind: String) -> void:
	_build()


func _build() -> void:
	var keep := -1
	var f: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f != null:
		keep = _scroll.focusables().find(f)
	_scroll.clear()
	for action in Controls.GAME_ACTIONS:
		var row := UiRow.new(BindingsFlow.label_of(str(action)))
		row.custom_minimum_size = Vector2(0, 64)
		row.key = str(action)
		for pad in [false, true]:
			var box := UiTheme.hbox(6)
			box.custom_minimum_size = Vector2(380, 0)
			box.alignment = BoxContainer.ALIGNMENT_CENTER
			var evs := BindingsFlow.events_of(str(action), pad)
			if evs.is_empty():
				box.add_child(UiTheme.label("Unbound", "Danger"))
			for i in mini(evs.size(), 3):
				box.add_child(PromptGlyph.new(evs[i], "", 38.0))
			row.value_box().add_child(box)
		var kb_txt := PackedStringArray()
		for ev in BindingsFlow.events_of(str(action), false):
			kb_txt.append(Controls.event_label(ev))
		var pad_txt := PackedStringArray()
		for ev in BindingsFlow.events_of(str(action), true):
			pad_txt.append(Controls.event_label(ev))
		row.set_help(row.label_text, "Keyboard & mouse: %s\nController: %s" % [", ".join(kb_txt) if not kb_txt.is_empty() else "unbound",
			", ".join(pad_txt) if not pad_txt.is_empty() else "unbound"])
		row.activated.connect(_open_settings)
		_scroll.content.add_child(row)
	_scroll.wrap_focus.call_deferred()
	if keep >= 0:
		var fs := _scroll.focusables()
		if keep < fs.size():
			fs[keep].grab_focus.call_deferred()


func default_focus() -> Control:
	var fs := _scroll.focusables()
	return fs[0] if not fs.is_empty() else null


func _open_settings() -> void:
	App.push("settings", {"tab": "input", "in_game": _in_game})


func _unhandled_input(event: InputEvent) -> void:
	if is_top() and event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		_open_settings()
		return
	super(event)
