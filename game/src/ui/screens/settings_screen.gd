extends Screen
## Settings ("the clipboard"). Tabs are generated from the categories of Settings.SCHEMA (so a new
## option appears automatically); every row is built by SettingRows. The Controls tab adds the full
## rebinding table for Controls.GAME_ACTIONS (keyboard & mouse and controller columns). Each tab has
## "reset to defaults" with confirmation; display changes use the 15 s keep/revert countdown.
## Works from the main menu and in-game (params.in_game, or automatically when a match is running):
## in-game it dims the paused match instead of showing the menu backdrop.
## Input: LB/RB (Q/E) tabs · up/down rows · left/right adjust · A select · X default · Y reset tab · B back.

const CAT_TITLES := {"display": "Display", "graphics": "Graphics", "audio": "Audio", "input": "Controls",
	"accessibility": "Accessibility", "gameplay": "Gameplay", "network": "Network", "diagnostics": "Diagnostics"}

var _tabs: TabStrip
var _list: FocusScroll
var _help: HelpPanel
var _rows: Array[UiRow] = []
var _bind_rows: Array[KeybindRow] = []
var _cats: Array[String] = []
var _focus_memory := {}
var _in_game := false
var _bar: PromptBar
var _reset_button: UiButton


func on_enter(p: Dictionary) -> void:
	_in_game = bool(p.get("in_game", false)) or MatchFlow.match_running()
	if _in_game:
		add_dimmer(0.93)          # the fight HUD behind must not compete with the header
	else:
		MenuBackdrop.ensure()
		add_backdrop_gradient(0.97, 0.7)
	for s in Settings.SCHEMA:
		var cat := str(s["cat"])
		if not _cats.has(cat) and not Settings.keys_in(cat).is_empty():
			_cats.append(cat)
	var f := build_frame("The clipboard", "Settings")
	var header: VBoxContainer = f["header"]
	if _in_game:
		var chip := UiTheme.panel("PanelChip")
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		# (opened over the Cannery hub: a local world whose clocks stop while a board is open)
		var notice := "ONLINE MATCH — STILL RUNNING" if MatchFlow.is_online() else ("MATCH PAUSED" if MatchFlow.current_match() != null else "PAUSED")
		chip.add_child(UiTheme.label(notice, "Value"))
		header.add_child(chip)
	var body: VBoxContainer = f["body"]
	_tabs = TabStrip.new()
	var titles: Array[String] = []
	for c in _cats:
		titles.append(str(CAT_TITLES.get(c, c.capitalize())))
	var start := maxi(0, _cats.find(str(p.get("tab", "display"))))
	_tabs.setup(titles, _cats, start)
	_tabs.tab_changed.connect(_on_tab_changed)
	body.add_child(_tabs)
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var board := ClipboardPanel.new()
	board.size_flags_stretch_ratio = 1.9
	cols.add_child(board)
	_list = FocusScroll.new(10)
	board.add_child(_list)
	_help = HelpPanel.new(_list, "About this option")
	_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help.custom_minimum_size = Vector2(460, 0)
	cols.add_child(_help)
	_bar = f["prompts"]
	_bar.set_prompts([
		{"actions": ["ui_left", "ui_right"], "text": "Adjust"},
		{"actions": ["ui_extra"], "text": "Default"},
		{"actions": ["ui_alt"], "text": "Reset tab", "call": _ask_reset},
		{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Tabs"},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back},
	])
	Settings.changed.connect(_on_setting_changed)
	Controls.bindings_changed.connect(_refresh_bindings)
	_build_tab()
	play_intro()


func default_focus() -> Control:
	var fs := _list.focusables()
	return fs[0] if not fs.is_empty() else null


func current_tab() -> String:
	return _tabs.current_id()


func rows() -> Array[UiRow]:
	return _rows


func bind_rows() -> Array[KeybindRow]:
	return _bind_rows


func row_for(key: String) -> UiRow:
	for r in _rows:
		if r.key == key:
			return r
	return null


func bind_row_for(action: String) -> KeybindRow:
	for r in _bind_rows:
		if r.action == action:
			return r
	return null


func select_tab(id: String) -> void:
	var i := _cats.find(id)
	if i >= 0 and i != _tabs.current:
		_tabs.select(i)


# --- tab content -------------------------------------------------------------------------------

func _on_tab_changed(_i: int) -> void:
	_build_tab()
	var target := _remembered_focus()
	if target:
		target.grab_focus()


func _remember_tab_focus() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not _list.is_ancestor_of(f):
		return
	var idx := _list.focusables().find(f)
	if idx >= 0:
		_focus_memory[_tabs.current_id()] = idx


func _remembered_focus() -> Control:
	var fs := _list.focusables()
	if fs.is_empty():
		return null
	var idx := int(_focus_memory.get(_tabs.current_id(), 0))
	return fs[clampi(idx, 0, fs.size() - 1)]


func _build_tab() -> void:
	_list.clear()
	_rows.clear()
	_bind_rows.clear()
	var cat := _tabs.current_id()
	for key in Settings.keys_in(cat):
		var row := SettingRows.make(str(key))
		row.focus_entered.connect(_remember_tab_focus)
		_list.content.add_child(row)
		_rows.append(row)
	match cat:
		"audio":
			var jukebox := UiButton.new("Jukebox", "", "settings")
			jukebox.pressed.connect(func(): App.push("jukebox"))
			_list.content.add_child(jukebox)
		"input":
			_build_input_extras()
		"gameplay":
			_build_gameplay_extras()
		"diagnostics":
			_build_diagnostics()
	_list.content.add_child(UiTheme.spacer(false, 8))
	_reset_button = UiButton.new("Reset %s to defaults" % str(CAT_TITLES.get(cat, cat)), "", "restart")
	_reset_button.route = "reset_tab"
	_reset_button.set_help("Reset %s" % str(CAT_TITLES.get(cat, cat)), "Restores every option on this tab to its default value. You will be asked to confirm.")
	_reset_button.pressed.connect(_ask_reset)
	_reset_button.focus_entered.connect(_remember_tab_focus)
	_list.content.add_child(_reset_button)
	_list.scroll_to_top()
	_list.wrap_focus.call_deferred()
	_help.show_help(str(CAT_TITLES.get(cat, cat)), "Select an option to see what it does.")


func _section(title: String) -> void:
	_list.content.add_child(UiTheme.spacer(false, 10))
	_list.content.add_child(UiTheme.label(title.to_upper(), "Eyebrow"))


func _build_input_extras() -> void:
	var vib := UiButton.new("Test vibration", "", "gamepad")
	vib.set_help("Test vibration", "Rumbles every connected controller at the current Vibration strength.")
	vib.pressed.connect(func() -> void:
		if Input.get_connected_joypads().is_empty():
			UiNav.toast("No controller connected.", "warning")
		elif float(Settings.get_value("input.vibration")) <= 0.0:
			UiNav.toast("Vibration is set to 0%.", "info")
		else:
			Controls.rumble(0.6, 0.8, 0.45))
	vib.focus_entered.connect(_remember_tab_focus)
	_list.content.add_child(vib)
	_section("Button mapping")
	var head := UiTheme.hbox(UiTheme.GAP_M)
	var a := UiTheme.label("ACTION", "Caption")
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.custom_minimum_size = Vector2(0, 0)
	head.add_child(UiTheme.spacer(false, 24))
	head.add_child(a)
	for t in ["KEYBOARD & MOUSE", "CONTROLLER"]:
		var l := UiTheme.label(str(t), "Caption")
		l.custom_minimum_size = Vector2(320, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(l)
	head.add_child(UiTheme.spacer(false, 24))
	_list.content.add_child(head)
	for action in Controls.GAME_ACTIONS:
		var kr := KeybindRow.new(str(action))
		kr.rebound.connect(_on_rebound)
		kr.reset_done.connect(_on_binding_reset)
		kr.kb_slot.focus_entered.connect(_remember_tab_focus)
		kr.pad_slot.focus_entered.connect(_remember_tab_focus)
		_list.content.add_child(kr)
		_bind_rows.append(kr)
	var all := UiButton.new("Reset all bindings", "", "restart")
	all.set_help("Reset all bindings", "Restores the default keyboard, mouse and controller bindings for every action. You will be asked to confirm.")
	all.pressed.connect(func() -> void:
		App.dialog("Reset all bindings?", "Every action goes back to its default keyboard, mouse and controller inputs.",
			[{"label": "Reset bindings", "id": "reset", "danger": true}, {"label": "Cancel", "id": "cancel", "cancel": true, "default": true}],
			func(id: String) -> void:
				if id == "reset":
					BindingsFlow.reset_all()
					UiNav.toast("All bindings restored to defaults.", "success")))
	all.focus_entered.connect(_remember_tab_focus)
	_list.content.add_child(all)


func _build_gameplay_extras() -> void:
	if _in_game:
		return
	var any := false
	if App.has_screen("tutorial_menu"):
		if not any:
			_section("Shortcuts")
			any = true
		var t := UiButton.new("Open the tutorial", "", "tutorial")
		t.set_help("Tutorial", "Granny Haymaker's short lessons, taught with your own moves (or the Classic ones). You can replay or skip any of them.")
		t.pressed.connect(func() -> void: App.push("tutorial_menu"))
		_list.content.add_child(t)
	if App.has_screen("profile"):
		if not any:
			_section("Shortcuts")
			any = true
		var pbtn := UiButton.new("Manage profiles", "", "profile")
		pbtn.set_help("Profiles", "Create, rename, switch or delete profiles. Settings are shared; records and progress are per profile.")
		pbtn.pressed.connect(func() -> void: App.push("profile"))
		_list.content.add_child(pbtn)


func diagnostics_report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("CRITTERWEIGHT %s" % str(ProjectSettings.get_setting("application/config/version", "")))
	lines.append("Engine: Godot %s" % str(Engine.get_version_info().get("string", "")))
	lines.append("Renderer: %s on %s (%s)" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	lines.append("OS: %s %s · CPU: %s × %d" % [OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count()])
	var win := get_window().size
	lines.append("Window: %d × %d · UI scale factor %.2f" % [win.x, win.y, get_tree().root.content_scale_factor])
	lines.append("User data: %s" % Paths.root)
	lines.append("Log file: %s" % Log.log_path())
	lines.append("Content: %d package(s), hash %s, %d problem(s)" % [Content.packages.size(), Content.content_hash().substr(0, 12), Content.errors.size()])
	for i in mini(Content.errors.size(), 5):
		lines.append("  - %s" % Content.errors[i])
	lines.append("Profile: %s" % Profiles.id())
	if Settings.load_error != "":
		lines.append("Settings: %s" % Settings.load_error)
	if Profiles.last_error != "":
		lines.append("Profiles: %s" % Profiles.last_error)
	return "\n".join(lines)


func _build_diagnostics() -> void:
	_section("System report")
	var info := UiTheme.panel("PanelHelp")
	var l := UiTheme.label(diagnostics_report(), "Caption", true)
	info.add_child(l)
	_list.content.add_child(info)
	var row := UiTheme.hbox(UiTheme.GAP_M)
	var open := UiButton.new("Open logs folder", "", "folder")
	open.set_help("Open logs folder", "Opens the folder with the game's log files in your file manager.")
	open.pressed.connect(func() -> void: Paths.open_in_os("logs"))
	open.focus_entered.connect(_remember_tab_focus)
	row.add_child(open)
	var copy := UiButton.new("Copy report", "", "copy")
	copy.set_help("Copy report", "Copies the system report above to the clipboard, ready to paste into a bug report.")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(diagnostics_report())
		UiNav.toast("System report copied to the clipboard.", "success"))
	copy.focus_entered.connect(_remember_tab_focus)
	row.add_child(copy)
	_list.content.add_child(row)


# --- updates -----------------------------------------------------------------------------------

func _on_setting_changed(key: String, value) -> void:
	for r in _rows:
		if r.key == key:
			SettingRows.refresh_row(r, value)


func _refresh_all_rows() -> void:
	for r in _rows:
		SettingRows.refresh_row(r, Settings.get_value(r.key))
	_refresh_bindings()


func _refresh_bindings() -> void:
	for kr in _bind_rows:
		if is_instance_valid(kr):
			kr.refresh()


func _on_rebound(action: String, stolen: String, pad: bool) -> void:
	_refresh_bindings()
	var row := bind_row_for(action)
	var ev := PromptGlyph.events_for(action, pad)
	var input_name := Controls.event_label(ev[0]) if not ev.is_empty() else "?"
	if stolen == "":
		if row:
			row.set_note("Now: %s" % input_name, "Success")
		return
	var other := bind_row_for(stolen)
	var left_unbound := not BindingsFlow.has_binding(stolen, pad)
	if other:
		var note := "%s moved to %s" % [input_name, BindingsFlow.label_of(action)]
		if left_unbound:
			note += " — no %s binding left" % ("controller" if pad else "keyboard")
		other.set_note(note, "Warning")
	if row:
		row.set_note("Now: %s (taken from %s)" % [input_name, BindingsFlow.label_of(stolen)], "Warning")
	UiNav.toast("%s was taken from %s.%s" % [input_name, BindingsFlow.label_of(stolen),
		(" %s now has no %s binding." % [BindingsFlow.label_of(stolen), "controller" if pad else "keyboard"]) if left_unbound else ""], "warning", 5.0)


func _on_binding_reset(action: String, conflicts: Array) -> void:
	_refresh_bindings()
	if conflicts.is_empty():
		UiNav.toast("%s: default bindings restored." % BindingsFlow.label_of(action), "success")
		return
	var names: PackedStringArray = PackedStringArray()
	for c in conflicts:
		names.append(BindingsFlow.label_of(str(c)))
		var r := bind_row_for(str(c))
		if r:
			r.set_note("Gave a default input back to %s" % BindingsFlow.label_of(action), "Warning")
	UiNav.toast("%s defaults restored; taken back from: %s." % [BindingsFlow.label_of(action), ", ".join(names)], "warning", 5.0)


# --- reset -------------------------------------------------------------------------------------

func _ask_reset() -> void:
	var cat := _tabs.current_id()
	var title := str(CAT_TITLES.get(cat, cat))
	var body := "Every %s option returns to its default value. Your other settings are not touched." % title
	if cat == "input":
		body = "Every Controls option and every button binding returns to its default."
	elif cat == "display":
		body += " Window changes are confirmed with a 15-second countdown."
	App.dialog("Reset %s settings?" % title, body,
		[{"label": "Reset", "id": "reset", "danger": true}, {"label": "Cancel", "id": "cancel", "cancel": true, "default": true}],
		func(id: String) -> void:
			if id == "reset":
				_reset_category(cat))


func _reset_category(cat: String) -> void:
	match cat:
		"display":
			var changes := {}
			for key in Settings.keys_in("display"):
				var s := Settings.schema(str(key))
				if bool(s.get("rollback", false)):
					if str(Settings.get_value(str(key))) != str(s["def"]):
						changes[str(key)] = s["def"]
				else:
					Settings.set_value(str(key), s["def"])
			if not changes.is_empty():
				_confirm_display_changes(changes)
		"input":
			Settings.reset("input")
			BindingsFlow.reset_all()
		_:
			Settings.reset(cat)
	_refresh_all_rows()
	UiNav.toast("%s settings reset to defaults." % str(CAT_TITLES.get(cat, cat)), "success")


func _confirm_display_changes(changes: Dictionary) -> void:
	var prev := Settings.apply_display_tentative(changes)
	App.push("dialog", {"title": "Keep these display settings?", "body": "The window settings were reset.\nReverting automatically in {s} seconds.",
		"buttons": [{"label": "Keep", "id": "keep", "default": true}, {"label": "Revert", "id": "revert", "cancel": true}],
		"countdown": SettingRows.ROLLBACK_SECONDS, "timeout_choice": "revert", "kind": "warning",
		"callback": func(id: String) -> void:
			if id == "keep":
				Settings.confirm_display()
			else:
				Settings.revert_display(prev)
			_refresh_all_rows()})


# --- input -------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_top():
		return
	if event.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		_remember_tab_focus()
		_tabs.step(-1)
		return
	if event.is_action_pressed("ui_tab_next"):
		get_viewport().set_input_as_handled()
		_remember_tab_focus()
		_tabs.step(1)
		return
	if event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		_ask_reset()
		return
	super(event)


func on_exit() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	if Controls.bindings_changed.is_connected(_refresh_bindings):
		Controls.bindings_changed.disconnect(_refresh_bindings)
	UiNav.cancel_capture()
