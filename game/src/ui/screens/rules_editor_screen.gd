extends Screen
## Rules editor ("rules_editor", MCH-05/06). Two views:
##  - Presets: every rules preset (built-in, mod, yours) with its summary; open / duplicate / new
##    (pick a mode) / rename / delete / export (shareable .rules.json) / import (Downloads folder).
##  - Editor: tabs generated from RulesValidator.GROUPS, one row per field with a plain-language
##    explanation, live validation (errors block saving, warnings explain), Save and Test-play.
## Built-in and mod presets are read-only: editing one starts a copy. Controller: LB/RB tabs,
## up/down rows, left/right adjust, A select, Y save, X test-play, B back. Mouse/keyboard work too.

const VALUE_LABELS := {"standard": "Standard", "spotlight_hog": "Spotlight Hog", "chumball": "Chumball",
	"absolute_unit": "Absolute Unit", "chum_rush": "Chum Rush", "tag_team": "Tag Team", "practice": "Practice",
	"duel": "Duel (1v1)", "ffa": "Free-for-all", "teams": "Teams", "tag": "Tag team", "coop": "Co-op",
	"ko": "Last standing (KO)", "score": "Score", "survive": "Survive", "strict": "Strict", "split": "Split",
	"punching_bag": "Punching Bag", "journeyman": "Journeyman", "contender": "Contender",
	"headliner": "Headliner", "hall_of_famer": "Hall-of-Famer"}

var _view := "list"
var _frame := {}
var _body: VBoxContainer
var _bar: PromptBar
var _list: FocusScroll
var _help: HelpPanel
var _tabs: TabStrip
var _problems_label: Label
var _rules := {}                 ## working copy in the editor
var _editing_id := ""            ## user preset id being edited ("" = new)
var _dirty := false
var _selected_id := ""
var _rows: Array[UiRow] = []


func on_enter(p: Dictionary) -> void:
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.75)
	_frame = build_frame("Create", "Rules")
	_body = _frame["body"]
	_bar = _frame["prompts"]
	if p.has("edit"):
		_open_editor(str(p["edit"]))
	else:
		_show_list()
	play_intro()


func default_focus() -> Control:
	if _view == "editor" and not _rows.is_empty():
		return _rows[0]
	var fs := _list.focusables() if _list else ([] as Array[Control])
	return fs[0] if not fs.is_empty() else null


func on_back() -> bool:
	if _view == "editor":
		if _dirty:
			App.dialog("Leave without saving?", "Your changes to these rules will be lost.",
				[{"label": "Keep editing", "id": "stay", "cancel": true}, {"label": "Discard changes", "id": "discard", "danger": true}],
				_on_leave_choice)
		else:
			_show_list()
		return true
	return false


func _on_leave_choice(choice: String) -> void:
	if choice == "discard":
		_dirty = false
		_show_list()


func _clear_body() -> void:
	for c in _body.get_children():
		c.queue_free()
	_rows.clear()
	_list = null
	_tabs = null


# --- presets list ------------------------------------------------------------------------------

func _origin_text(id: String) -> String:
	var pid := Content.origin_of("rules", id)
	if pid == "user":
		return "Yours"
	if pid == "core" or pid == "":
		return "Built-in"
	return "Mod: %s" % pid


func _show_list() -> void:
	_view = "list"
	_clear_body()
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(cols)
	var board := ClipboardPanel.new()
	board.size_flags_stretch_ratio = 1.6
	cols.add_child(board)
	_list = FocusScroll.new(8)
	board.add_child(_list)
	_help = HelpPanel.new(_list, "Preset")
	_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help.custom_minimum_size = Vector2(520, 0)
	cols.add_child(_help)
	var ids := Content.ids("rules")
	# your presets first, then built-in/mod presets, each alphabetical
	ids.sort_custom(func(a, b) -> bool:
		var ua := RulePresets.is_user(str(a))
		var ub := RulePresets.is_user(str(b))
		if ua != ub:
			return ua
		return str(Content.get_entry("rules", str(a)).get("name", a)).naturalnocasecmp_to(str(Content.get_entry("rules", str(b)).get("name", b))) < 0)
	var new_b := UiButton.new("New rules…", "PrimaryButton", "create")
	new_b.set_help("New rules", "Start from a mode's defaults.")
	new_b.pressed.connect(_ask_new)
	_list.content.add_child(new_b)
	var imp := UiButton.new("Import from Downloads…", "", "folder")
	imp.set_help("Import", "Imports a shared .rules.json from your Downloads or packages folder:\n%s" % Paths.dir("downloads"))
	imp.pressed.connect(_ask_import)
	_list.content.add_child(imp)
	for id in ids:
		var r := Content.get_entry("rules", str(id))
		if str(r.get("mode", "")) == "tutorial":
			continue
		var b := UiButton.new("%s   ·   %s" % [str(r.get("name", id)), _origin_text(str(id))], "SubItem")
		var desc := str(r.get("description", ""))
		b.set_help(str(r.get("name", id)), "%s\n\n%s\n\n%s" % [RulesValidator.describe(RulesValidator.normalize(r)), desc, _origin_text(str(id)) + (" — editing makes your own copy" if not RulePresets.is_user(str(id)) else "")])
		var pid := str(id)
		b.pressed.connect(func(): _preset_actions(pid))
		b.focus_entered.connect(func(): _selected_id = pid)
		_list.content.add_child(b)
	_bar.set_prompts([
		{"actions": ["ui_accept"], "text": "Open"},
		{"actions": ["ui_alt"], "text": "New", "call": _ask_new},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back},
	])
	restore_focus()


func _preset_actions(id: String) -> void:
	_selected_id = id
	var mine := RulePresets.is_user(id)
	var buttons := [{"label": "Edit" if mine else "Edit a copy", "id": "edit"}, {"label": "Duplicate", "id": "dup"},
		{"label": "Export to share", "id": "export"}]
	if mine:
		buttons.append({"label": "Rename", "id": "rename"})
		buttons.append({"label": "Delete", "id": "delete", "danger": true})
	buttons.append({"label": "Cancel", "id": "cancel", "cancel": true})
	var r := Content.get_entry("rules", id)
	App.dialog(str(r.get("name", id)), RulesValidator.describe(RulesValidator.normalize(r)), buttons, _on_preset_action.bind(id))


func _on_preset_action(choice: String, id: String) -> void:
	var r := Content.get_entry("rules", id)
	match choice:
		"edit":
			_open_editor(id)
		"dup":
			var res := RulePresets.duplicate_preset(id)
			if res["ok"]:
				UiNav.toast("Saved a copy: %s" % str(Content.get_entry("rules", str(res["id"])).get("name", "")), "success")
			else:
				UiNav.toast("Could not copy: %s" % _first_problem(res), "error")
			_show_list()
		"export":
			var out := RulePresets.export_preset(id)
			UiNav.toast(("Exported to %s" % out) if out != "" else "Export failed", "success" if out != "" else "error")
		"rename":
			_ask_rename(id)
		"delete":
			App.dialog("Delete these rules?", "\"%s\" will be moved to the presets/.removed folder." % str(r.get("name", id)),
				[{"label": "Keep", "id": "keep", "cancel": true}, {"label": "Delete", "id": "del", "danger": true}],
				_on_delete_choice.bind(id))


func _on_delete_choice(choice: String, id: String) -> void:
	if choice == "del":
		RulePresets.delete(id)
		_show_list()


func _first_problem(res: Dictionary) -> String:
	var probs: Array = res.get("problems", [])
	for pr in probs:
		if str(pr["severity"]) == "error":
			return str(pr["text"])
	return "unknown error"


func _ask_new() -> void:
	var buttons := []
	for m in RulesValidator.EDITABLE_MODES:
		buttons.append({"label": str(VALUE_LABELS.get(m, m)), "id": m})
	buttons.append({"label": "Cancel", "id": "cancel", "cancel": true})
	App.dialog("New rules", "Pick a mode to start from. You can change everything afterwards.", buttons, _on_new_choice)


func _on_new_choice(choice: String) -> void:
	if choice in RulesValidator.EDITABLE_MODES:
		var r := RulesValidator.defaults_for(choice)
		r["name"] = "My %s" % str(VALUE_LABELS.get(choice, choice))
		_edit_dict(r, "")


func _ask_rename(id: String) -> void:
	if not App.has_screen("text_entry"):
		return
	App.push("text_entry", {"title": "Rename rules", "value": str(Content.get_entry("rules", id).get("name", "")), "max_len": 40, "allow_empty": false,
		"callback": _on_renamed.bind(id)})


func _on_renamed(ok: bool, text: String, id: String) -> void:
	if ok and text.strip_edges() != "":
		var res := RulePresets.rename(id, text)
		if not res["ok"]:
			UiNav.toast(_first_problem(res), "error")
		_show_list()


func _ask_import() -> void:
	var found := []
	for kind in ["downloads", "packages"]:
		var d := DirAccess.open(Paths.dir(kind))
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".rules.json") or (f.ends_with(".json") and kind == "downloads"):
				found.append(Paths.dir(kind).path_join(f))
	if found.is_empty():
		App.dialog("Nothing to import", "Put a shared .rules.json file in\n%s\nand try again." % Paths.dir("downloads"), [{"label": "OK", "id": "ok", "cancel": true}])
		return
	var buttons := []
	for i in mini(found.size(), 8):
		buttons.append({"label": str(found[i]).get_file(), "id": str(i)})
	buttons.append({"label": "Cancel", "id": "cancel", "cancel": true})
	App.dialog("Import rules", "Choose a file:", buttons, _on_import_choice.bind(found))


func _on_import_choice(choice: String, found: Array) -> void:
	if not choice.is_valid_int():
		return
	var res := RulePresets.import_preset(str(found[int(choice)]))
	if res["ok"]:
		UiNav.toast("Imported %s" % str(Content.get_entry("rules", str(res["id"])).get("name", "")), "success")
	else:
		UiNav.toast("Not imported: %s" % _first_problem(res), "error")
	_show_list()


# --- editor ------------------------------------------------------------------------------------

func _open_editor(id: String) -> void:
	var r := Content.get_entry("rules", id).duplicate(true)
	if r.is_empty():
		_show_list()
		return
	for k in ["_package", "_file", "override"]:
		r.erase(k)
	if not RulePresets.is_user(id):
		r["name"] = ("%s (custom)" % str(r.get("name", id))).substr(0, 40)
		_edit_dict(r, "")
	else:
		_edit_dict(r, id)


func _edit_dict(r: Dictionary, id: String) -> void:
	_view = "editor"
	_rules = RulesValidator.normalize(r)
	_editing_id = id
	_dirty = id == ""
	_clear_body()
	_tabs = TabStrip.new()
	var titles: Array[String] = []
	var ids: Array[String] = []
	for g in RulesValidator.GROUPS:
		titles.append(g)
		ids.append(g)
	_tabs.setup(titles, ids, 0)
	_tabs.tab_changed.connect(func(_i: int): _build_rows())
	_body.add_child(_tabs)
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(cols)
	var board := ClipboardPanel.new()
	board.size_flags_stretch_ratio = 1.8
	cols.add_child(board)
	_list = FocusScroll.new(10)
	board.add_child(_list)
	var right := UiTheme.vbox(UiTheme.GAP_M)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(500, 0)
	cols.add_child(right)
	_help = HelpPanel.new(_list, "About this rule")
	_help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_help)
	var probs := UiTheme.panel("PanelHelp")
	right.add_child(probs)
	_problems_label = UiTheme.label("", "Caption", true)
	_problems_label.custom_minimum_size = Vector2(460, 0)
	probs.add_child(_problems_label)
	_bar.set_prompts([
		{"actions": ["ui_left", "ui_right"], "text": "Adjust"},
		{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Tabs"},
		{"actions": ["ui_alt"], "text": "Save", "call": _save},
		{"actions": ["ui_extra"], "text": "Test-play", "call": _test_play},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back},
	])
	_build_rows()
	_validate()


func _build_rows() -> void:
	for c in _list.content.get_children():
		c.queue_free()
	_rows.clear()
	var group := _tabs.current_id()
	var mode := str(_rules.get("mode", "standard"))
	for key in RulesValidator.fields_for(mode):
		var f: Dictionary = RulesValidator.FIELDS[key]
		if str(f["group"]) != group:
			continue
		var row := _row_for(key, f)
		row.key = key
		row.set_help(str(f["label"]), str(f["help"]))
		_list.content.add_child(row)
		_rows.append(row)
	if _rows.is_empty():
		var none := UiTheme.label("This mode has no extra options.", "BodyMuted", true)
		_list.content.add_child(none)
	_list.wrap_focus()
	if not _rows.is_empty():
		_rows[0].grab_focus.call_deferred()


func _labels_for(opts: Array) -> Array:
	return opts.map(func(o): return str(VALUE_LABELS.get(str(o), str(o).capitalize())))


func _row_for(key: String, f: Dictionary) -> UiRow:
	var v = RulesValidator.get_value(_rules, key)
	match str(f["type"]):
		"bool":
			var t := ToggleRow.new(str(f["label"])).setup(bool(v))
			t.value_changed.connect(func(nv): _changed(key, nv))
			return t
		"enum":
			var opts: Array = f.get("options", [])
			var o := OptionRow.new(str(f["label"])).setup(opts, _labels_for(opts), v)
			o.value_changed.connect(func(nv): _changed(key, nv))
			return o
		"text":
			var tf := TextFieldRow.new(str(f["label"])).setup(str(v), int(f.get("max", 40)))
			tf.value_changed.connect(func(nv): _changed(key, nv))
			return tf
		_:
			var is_int := str(f["type"]) == "int"
			var mn := float(f.get("min", 0.0))
			var mx := float(f.get("max", 100.0))
			var st := float(f.get("step", 1.0 if is_int else 0.05))
			var fmt := SliderRow.Fmt.INT
			if not is_int:
				fmt = SliderRow.Fmt.MULT if (mn >= 0.0 and mx <= 5.0 and key.ends_with("_mult")) else (SliderRow.Fmt.SECONDS if str(f["label"]).ends_with("(s)") else SliderRow.Fmt.DECIMAL2)
			var s := SliderRow.new(str(f["label"])).setup(mn, mx, st, float(v), fmt)
			if key == "round_time":
				s.zero_text = "No timer"
			s.value_changed.connect(func(nv): _changed(key, int(nv) if is_int else float(nv)))
			return s


func _changed(key: String, v) -> void:
	RulesValidator.set_value(_rules, key, v)
	_dirty = true
	if key == "mode":
		# a new mode brings its own format/defaults; keep the name and description
		var keep := {"name": _rules.get("name", ""), "description": _rules.get("description", "")}
		_rules = RulesValidator.defaults_for(str(v))
		_rules.merge(keep, true)
		_build_rows()
	elif key == "format":
		var t := {"duel": 2, "ffa": 0, "teams": 2, "tag": 2, "coop": 1}
		_rules["teams"] = t.get(str(v), 2)
		if str(v) == "duel":
			_rules["players"] = [2, 2]
		_build_rows()
	_validate()


func _validate() -> Array:
	var probs := RulesValidator.validate(_rules)
	var lines := []
	for pr in probs:
		var f := RulesValidator.field(str(pr["field"]))
		lines.append("%s %s%s" % ["✖" if pr["severity"] == "error" else "!", (str(f.get("label", "")) + ": ") if not f.is_empty() else "", pr["text"]])
	_problems_label.text = "Rules check: OK — ready to save." if lines.is_empty() else "\n".join(lines)
	_problems_label.theme_type_variation = "Danger" if RulesValidator.has_errors(probs) else ("Warning" if not probs.is_empty() else "Success")
	for row in _rows:
		var msgs := probs.filter(func(pr): return str(pr["field"]) == row.key)
		row.set_badge(("✖ " if msgs.any(func(pr): return pr["severity"] == "error") else "! ") + str(msgs[0]["text"]).substr(0, 48) if not msgs.is_empty() else "", "Danger" if msgs.any(func(pr): return pr["severity"] == "error") else "Warning")
	return probs


func _save() -> void:
	if _view != "editor":
		return
	var res := RulePresets.save(_rules, _editing_id)
	if not res["ok"]:
		UiNav.toast("Can't save yet: %s" % _first_problem(res), "error")
		Audio.ui("ui_error")
		return
	_editing_id = str(res["id"])
	_rules = Content.get_entry("rules", _editing_id).duplicate(true)
	_dirty = false
	UiNav.toast("Saved \"%s\" — it's in every rules list now." % _rules.get("name", ""), "success")


func _test_play() -> void:
	if _view != "editor":
		return
	var probs := _validate()
	if RulesValidator.has_errors(probs):
		UiNav.toast("Fix the errors first: %s" % _first_problem({"problems": probs}), "error")
		return
	var r := RulesValidator.normalize(_rules)
	var pl: Array = r.get("players", [2, 2])
	var n := clampi(int(pl[0]), 2, 8)
	var teams := int(r.get("teams", 2))
	var ids := Content.playable_creatures().filter(func(c): return not str(c).begins_with("dev_"))
	if ids.is_empty():
		ids = Content.playable_creatures()
	var fighters := []
	for i in n:
		var team := 0 if str(r.get("format", "")) == "coop" else (i % teams if teams > 0 else i)
		fighters.append({"creature": ids[i % ids.size()], "team": team, "kind": "player" if i == 0 else "bot",
			"difficulty": BotTiers.brain_tier(str(r.get("bot_tier", "journeyman"))), "name": Profiles.player_name() if i == 0 else "Bot %d" % i})
	MatchFlow.launch({"arena": "the_gullet", "rules": r, "seed": randi() % 100000, "fighters": fighters, "custom": true,
		"ui": {"mode": "rules_test"}})


func _unhandled_input(event: InputEvent) -> void:
	if not is_top():
		return
	if _view == "editor" and _tabs:
		if event.is_action_pressed("ui_tab_prev") or event.is_action_pressed("ui_tab_next"):
			get_viewport().set_input_as_handled()
			_tabs.step(1 if event.is_action_pressed("ui_tab_next") else -1)
			return
		if event.is_action_pressed("ui_alt"):
			get_viewport().set_input_as_handled()
			_save()
			return
		if event.is_action_pressed("ui_extra"):
			get_viewport().set_input_as_handled()
			_test_play()
			return
	elif _view == "list" and event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		_ask_new()
		return
	super._unhandled_input(event)
