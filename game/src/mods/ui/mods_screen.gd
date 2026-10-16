extends Screen
## Mods screen (MOD-03/04/05): browse installed and bundled mods, enable/disable them per mod
## set, see validation problems with actionable text, grant consent for core overrides, import
## (file dialog, drag & drop, or the Downloads folder for controller users), export/share,
## uninstall, and manage named mod sets. Fully operable with a controller or mouse/keyboard.
## Invariant: every mod-supplied string (name, author, description, ids, versions, file names,
## errors, warnings, load reports) goes through esc() before it reaches the BBCode details panel,
## so a package can never hide or fake the screen's own warnings.

var _list: VBoxContainer
var _details: RichTextLabel
var _set_pick: OptionButton
var _notice: Label
var _rows := {}                  ## mod id -> {row, toggle}
var _selected := ""
var _overlay: PanelContainer
var _overlay_body: Label
var _overlay_buttons: HBoxContainer
var _file_dialog: FileDialog
var _first_button: Control


func on_enter(_p: Dictionary) -> void:
	_build()
	Mods.mods_changed.connect(_on_mods_changed)
	get_window().files_dropped.connect(_on_files_dropped)
	_rebuild_list()


func on_exit() -> void:
	if Mods.mods_changed.is_connected(_on_mods_changed):
		Mods.mods_changed.disconnect(_on_mods_changed)
	if get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)


func default_focus() -> Control:
	if not _rows.is_empty():
		var id: String = _selected if _rows.has(_selected) else str(_rows.keys()[0])
		return _rows[id]["toggle"]
	return _first_button


func on_back() -> bool:
	if _overlay.visible:
		_close_overlay()
		return true
	return false


# ---------------------------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.08, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48 if side in ["left", "right"] else 32)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	var title := Label.new()
	title.text = "MODS"
	title.add_theme_font_size_override("font_size", 44)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var set_l := Label.new()
	set_l.text = "Mod set"
	head.add_child(set_l)
	_set_pick = OptionButton.new()
	_set_pick.custom_minimum_size = Vector2(220, 0)
	_set_pick.item_selected.connect(_on_set_picked)
	head.add_child(_set_pick)
	head.add_child(_button("New set", _new_set))
	head.add_child(_button("Rename", _rename_set))
	head.add_child(_button("Delete set", _delete_set))

	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.text = "Mods are data-only packages: they never run code. Changes apply to new matches and runs right away. Online games need the same gameplay mods as the host; presentation-only mods never block joining."
	_notice.modulate = Color(1, 1, 1, 0.75)
	if Mods.sets_error != "":
		_notice.text = Mods.sets_error
		_notice.modulate = Color(1.0, 0.9, 0.6)
	root.add_child(_notice)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.fit_content = false
	_details.scroll_active = true
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.focus_mode = Control.FOCUS_NONE
	panel.add_child(_details)

	# a flow, not a row: at 1280x800 the seven buttons are wider than the window and a row pushed
	# the whole screen past its right edge; here they wrap to a second line instead
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 10)
	bar.add_theme_constant_override("v_separation", 10)
	root.add_child(bar)
	_first_button = _button("Import package…", _import_dialog)
	bar.add_child(_first_button)
	bar.add_child(_button("Import from Downloads", _import_from_downloads))
	bar.add_child(_button("Export / share", _export_selected))
	bar.add_child(_button("Uninstall", _uninstall_selected))
	bar.add_child(_button("Open mods folder", func(): Paths.open_in_os("mods")))
	bar.add_child(_button("Rescan", func():
		Mods.refresh()
		Mods.apply()))
	bar.add_child(_button("Back", func(): App.back()))

	_overlay = PanelContainer.new()
	_overlay.visible = false
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_overlay.custom_minimum_size = Vector2(720, 0)
	add_child(_overlay)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 16)
	_overlay.add_child(ov)
	_overlay_body = Label.new()
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_body.custom_minimum_size = Vector2(680, 0)
	ov.add_child(_overlay_body)
	_overlay_buttons = HBoxContainer.new()
	_overlay_buttons.alignment = BoxContainer.ALIGNMENT_END
	_overlay_buttons.add_theme_constant_override("separation", 10)
	ov.add_child(_overlay_buttons)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.critmod, *.zip ; Mod packages"])
	_file_dialog.title = "Import a mod package"
	_file_dialog.use_native_dialog = false
	_file_dialog.file_selected.connect(_import_file)
	add_child(_file_dialog)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): b.grab_focus())
	return b


func _on_mods_changed() -> void:
	if is_inside_tree():
		_rebuild_list.call_deferred()


func _rebuild_list() -> void:
	var had_focus := get_viewport().gui_get_focus_owner() != null and is_ancestor_of(get_viewport().gui_get_focus_owner())
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	_set_pick.clear()
	var names: Array = Mods.sets.keys()
	names.sort()
	for i in names.size():
		_set_pick.add_item(str(names[i]))
		if str(names[i]) == Mods.active_set:
			_set_pick.select(i)
	var shown := []
	for info in Mods.available:
		shown.append(str(info["id"]))
		_add_row(info)
	for id in Mods.missing_in_active():
		if not id in shown:
			_add_row({"id": id, "name": id, "version": "?", "kind": "missing", "errors": ["not installed: reinstall it (or remove it from this set) — nothing else was changed"], "warnings": []})
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "No mods installed. Use Import, or copy .critmod files into the mods folder."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	_wire_focus()
	if _selected == "" or not _rows.has(_selected):
		_selected = str(_rows.keys()[0]) if not _rows.is_empty() else ""
	_show_details(_selected)
	if had_focus or get_viewport().gui_get_focus_owner() == null:
		restore_focus()


func _status_of(info: Dictionary) -> Array:
	var id := str(info["id"])
	if str(info.get("kind", "")) == "missing":
		return ["MISSING", Color(1.0, 0.45, 0.4)]
	if not (info["errors"] as Array).is_empty():
		return ["ERROR", Color(1.0, 0.4, 0.35)]
	if not Mods.consent_needed(id).is_empty():
		return ["NEEDS CONSENT", Color(1.0, 0.75, 0.3)]
	if Mods.is_enabled(id):
		if Mods.load_report.has(id) and not (Mods.load_report[id] as Array).is_empty():
			return ["PROBLEMS" if id in Mods.load_order else "NOT LOADED", Color(1.0, 0.7, 0.3)]
		return ["ON", Color(0.45, 0.95, 0.55)]
	return ["OFF", Color(0.7, 0.7, 0.75)]


func _add_row(info: Dictionary) -> void:
	var id := str(info["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_list.add_child(row)
	var toggle := CheckButton.new()
	toggle.text = "%s  %s" % [str(info.get("name", id)), str(info.get("version", ""))]
	toggle.button_pressed = Mods.is_enabled(id)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.toggled.connect(func(on: bool): _toggle(id, on, toggle))
	toggle.focus_entered.connect(func():
		_selected = id
		_show_details(id))
	toggle.mouse_entered.connect(func(): toggle.grab_focus())
	row.add_child(toggle)
	var st := _status_of(info)
	var badge := Label.new()
	badge.text = st[0]
	badge.add_theme_color_override("font_color", st[1])
	badge.custom_minimum_size = Vector2(150, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(badge)
	if str(info.get("kind", "")) == "example":
		var ex := Label.new()
		ex.text = "bundled"
		ex.modulate = Color(1, 1, 1, 0.55)
		row.add_child(ex)
	_rows[id] = {"row": row, "toggle": toggle}


func _wire_focus() -> void:
	var toggles: Array = _rows.values().map(func(r): return r["toggle"])
	for i in toggles.size():
		var t: Control = toggles[i]
		t.focus_neighbor_top = t.get_path_to(toggles[i - 1]) if i > 0 else t.get_path_to(_set_pick)
		t.focus_neighbor_bottom = t.get_path_to(toggles[i + 1]) if i + 1 < toggles.size() else t.get_path_to(_first_button)


## Makes mod-supplied text inert in BBCode: "[" becomes the "[lb]" tag, so "[font_size=1]" or
## "[color=#0000]" in a package's description is shown literally instead of being applied.
static func esc(v) -> String:
	return str(v).replace("[", "[lb]")


func _show_details(id: String) -> void:
	var info := Mods.info_of(id)
	if info.is_empty():
		_details.text = "[b]%s[/b]\n\nThis mod is part of the set \"%s\" but is not installed. Reinstall it to restore the set, or disable it here to remove it from the set. Nothing else was changed." % [esc(id), esc(Mods.active_set)] if id != "" else ""
		return
	var t := "[font_size=28][b]%s[/b][/font_size]  %s\n" % [esc(info["name"]), esc(info["version"])]
	t += "[color=#aab]id[/color] %s   [color=#aab]by[/color] %s   [color=#aab]source[/color] %s\n\n" % [esc(id), esc(info["author"]) if str(info["author"]) != "" else "unknown", esc({"example": "bundled example", "archive": str(info["path"]).get_file(), "folder": "folder " + str(info["path"]).get_file()}.get(str(info["kind"]), "?"))]
	if str(info["description"]) != "":
		t += "%s\n\n" % esc(info["description"])
	t += "[color=#aab]Changes:[/color] %s\n" % (esc(", ".join(info["kinds"])) if not (info["kinds"] as Array).is_empty() else "nothing recognised")
	t += "[color=#aab]Multiplayer:[/color] %s\n" % ("presentation only — never blocks joining" if bool(info["client_only"]) else "gameplay — everyone in a match needs the same version")
	var reqs: Array = (info["requires"] as Array).map(func(r): return "%s %s" % [r.get("id", "?"), r.get("version", "")] if typeof(r) == TYPE_DICTIONARY else str(r))
	if not reqs.is_empty():
		t += "[color=#aab]Requires:[/color] %s\n" % esc(", ".join(reqs))
	if not (info["capabilities"] as Array).is_empty():
		t += "[color=#aab]Capabilities:[/color] %s\n" % esc(", ".join(info["capabilities"]))
	t += "[color=#aab]Size:[/color] %.1f KB in %d files   [color=#aab]hash[/color] %s\n" % [float(info["size"]) / 1024.0, int(info["files"]), esc(str(info["hash"]).substr(0, 12))]
	if "replaces_core" in info["capabilities"]:
		t += "\n[color=#ffbf4d]Replaces core content.[/color] Matches and runs using it are marked Modded; you are asked before it is enabled.\n"
	for e in info["errors"]:
		t += "\n[color=#ff6b5e]Problem:[/color] %s" % esc(e)
	for w in info["warnings"]:
		t += "\n[color=#ffbf4d]Note:[/color] %s" % esc(w)
	for e2 in Mods.load_report.get(id, []):
		t += "\n[color=#ffbf4d]While loading:[/color] %s" % esc(e2)
	_details.text = t


## The details text currently shown (tests and accessibility read-outs).
func details_text() -> String:
	return _details.text if _details else ""


func _toggle(id: String, on: bool, toggle: CheckButton) -> void:
	var r := Mods.set_enabled(id, on)
	if not r["ok"] and not (r["needs_consent"] as Array).is_empty():
		toggle.set_pressed_no_signal(false)
		var info := Mods.info_of(id)
		_ask("%s %s replaces core game content (balance, rules or fighters).\n\nWith it enabled, matches and runs are marked Modded, records stay separate, and online players need the same mod. It cannot run code. Allow it?" % [info["name"], info["version"]],
			[["Allow and enable", func():
				Mods.grant_consent(id, r["needs_consent"])
				Mods.set_enabled(id, true)
				Mods.apply()], ["Cancel", func(): pass]])
		return
	if not r["ok"]:
		toggle.set_pressed_no_signal(not on)
		_toast(str(r["message"]))
		return
	Mods.apply()
	if str(r["message"]) != "":
		_toast(str(r["message"]))


func _ask(text: String, choices: Array) -> void:
	remember_focus()
	_overlay_body.text = text
	for c in _overlay_buttons.get_children():
		c.queue_free()
	var first: Button = null
	for ch in choices:
		var cb: Callable = ch[1]
		var b := _button(str(ch[0]), func():
			_close_overlay()
			cb.call())
		_overlay_buttons.add_child(b)
		if first == null:
			first = b
	_overlay.visible = true
	_overlay.reset_size()
	_overlay.position = (size - _overlay.size) * 0.5
	if first:
		first.grab_focus.call_deferred()


func _close_overlay() -> void:
	_overlay.visible = false
	restore_focus()


func _toast(msg: String) -> void:
	_notice.text = msg
	_notice.modulate = Color(1.0, 0.9, 0.6)
	Log.i("mods", msg)


func _on_set_picked(i: int) -> void:
	Mods.use_set(_set_pick.get_item_text(i))


func _new_set() -> void:
	var n := Mods.save_set_as("Set %d" % (Mods.sets.size() + 1), [])
	Mods.sets[n] = []
	Mods.use_set(n)
	_toast("Created mod set \"%s\" (empty). Enable mods to fill it." % n)


func _rename_set() -> void:
	var line := LineEdit.new()
	line.text = Mods.active_set
	line.max_length = 40
	remember_focus()
	_overlay_body.text = "Rename mod set \"%s\" to:" % Mods.active_set
	for c in _overlay_buttons.get_children():
		c.queue_free()
	_overlay_buttons.add_child(line)
	line.custom_minimum_size = Vector2(320, 0)
	var ok := _button("Rename", func():
		var old := Mods.active_set
		_close_overlay()
		if not Mods.rename_set(old, line.text):
			_toast("That name is empty or already used.")
		else:
			_rebuild_list())
	line.text_submitted.connect(func(_t): ok.pressed.emit())
	_overlay_buttons.add_child(ok)
	_overlay_buttons.add_child(_button("Cancel", _close_overlay))
	_overlay.visible = true
	_overlay.reset_size()
	_overlay.position = (size - _overlay.size) * 0.5
	line.grab_focus.call_deferred()


func _delete_set() -> void:
	if Mods.sets.size() <= 1:
		_toast("You need at least one mod set.")
		return
	var name_ := Mods.active_set
	_ask("Delete the mod set \"%s\"? The mods themselves stay installed." % name_, [["Delete set", func(): Mods.delete_set(name_)], ["Cancel", func(): pass]])


func _import_dialog() -> void:
	_file_dialog.current_dir = Paths.dir("downloads")
	_file_dialog.popup_centered_ratio(0.7)


func _import_file(path: String, downgrade := false) -> void:
	var r := Mods.import_package(path, downgrade)
	if not r["ok"] and bool(r.get("downgrade", false)):
		_ask(str(r["message"]), [["Downgrade", func(): _import_file(path, true)], ["Cancel", func(): pass]])
		return
	if not r["ok"]:
		var errs: Array = r.get("errors", [])
		_ask("%s%s" % [r["message"], ("\n\n• " + "\n• ".join(errs.slice(0, 6))) if errs.size() > 1 else ""], [["OK", func(): pass]])
		return
	_selected = str(r["id"])
	_toast("%s. It is %s in the set \"%s\"." % [r["message"], "enabled" if Mods.is_enabled(_selected) else "not enabled yet", Mods.active_set])
	_rebuild_list()


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		_import_file(f)


## Controller-friendly import: lists packages sitting in the user Downloads/packages folders.
func _import_from_downloads() -> void:
	var found := []
	for kind in ["downloads", "packages"]:
		var d := DirAccess.open(Paths.dir(kind))
		if d == null:
			continue
		for f in d.get_files():
			if f.get_extension().to_lower() in Mods.ARCHIVE_EXT:
				found.append(Paths.dir(kind).path_join(f))
	if found.is_empty():
		_ask("No .critmod or .zip packages in:\n%s\n%s\n\nPut downloaded mod packages there, or use Import package… to browse." % [Paths.dir("downloads"), Paths.dir("packages")], [["OK", func(): pass]])
		return
	var choices := []
	for p in found.slice(0, 8):
		var pp: String = p
		choices.append([pp.get_file(), func(): _import_file(pp)])
	choices.append(["Cancel", func(): pass])
	_ask("Import which package?", choices)


func _export_selected() -> void:
	if _selected == "" or Mods.info_of(_selected).is_empty():
		_toast("Select an installed mod first.")
		return
	var out := Mods.export_package(_selected)
	if out == "":
		_toast("This mod cannot be exported (it has errors).")
		return
	_ask("Saved a shareable copy:\n%s\n\nSend that file to a friend; they import it from their Mods screen." % out, [["Open folder", func(): Paths.open_in_os("packages")], ["OK", func(): pass]])


func _uninstall_selected() -> void:
	var info := Mods.info_of(_selected)
	if info.is_empty():
		_toast("Select an installed mod first.")
		return
	if str(info["kind"]) == "example":
		_toast("Bundled examples cannot be uninstalled; just turn them off.")
		return
	var id := _selected
	_ask("Uninstall %s %s? The package is moved to the mods/.removed folder, and it stays listed as missing in sets that use it until you reinstall it or turn it off." % [info["name"], info["version"]],
		[["Uninstall", func():
			Mods.uninstall(id)
			_toast("Uninstalled %s." % info["name"])], ["Cancel", func(): pass]])
