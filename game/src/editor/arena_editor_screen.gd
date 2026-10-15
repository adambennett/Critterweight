extends Screen
## Arena editor (ARN-01..05). Choose a base and variant, place/select/move/rotate/delete/duplicate
## props, hazards, pickups and mode markers on a grid (or freely), adjust the playable boundary
## within the base's range, toggle base hazards and built-ins, declare supported modes, see live
## validation (budget, counts, clear floor, spawn safety, team clusters, mode markers — click an
## issue to select the culprit), undo/redo everything, save/load, export/import packages, and
## test-play the layout in a real match, returning here afterwards with history intact.
##
## Controls — mouse/keyboard: LMB place/select/drag (Alt = no snap), RMB click cancel / drag orbit,
## MMB pan, wheel zoom, R / Shift+R rotate, Del delete, Ctrl+D duplicate, Ctrl+Z / Ctrl+Y undo/redo,
## Ctrl+S save, [ / ] palette tab, 1-9 palette item, T marker team, G grid snap, F5 test play,
## Esc cancel, H help. Controller: left stick cursor, right stick orbit (Y = pitch), LT/RT zoom,
## A place/select (A on the selection carries it), B back/cancel, X delete, Y rotate, LB/RB palette
## tab, D-pad nudge (or palette item when nothing is selected), Start menu, View panels, L3 snap.
## Self-contained: plain Godot controls with a local theme (the shared UI theme can replace it).

const TABS := ["obstacles", "walls", "hazards", "pickups", "markers"]
const COL_BG := Color("#1A1D24")
const COL_TEXT := Color("#F2F2EC")
const COL_MUTED := Color("#9AA0AB")
const COL_GOLD := Color("#C9A227")
const COL_DANGER := Color("#FF5A5A")
const COL_OK := Color("#8BD426")
const COL_WARN := Color("#FFC43D")
const STICK_DEAD := 0.22

static var _session := {}

var model: ArenaEditModel
var stack: ArenaEditCommands.Stack
var path := ""
var vp: ArenaEditorViewport
var cursor := Vector3.ZERO
var tab := 0
var armed := ""
var armed_yaw := 0.0
var armed_team := -1
var selected := -1
var carrying := false
var snap_on := true
var grid_step := 0.5
var validation := {}
var _drag := {}
var _dirty_view := false
var _dirty_static := false
var _need_validate := true
var _overlay: Control = null
var _overlay_focus: Control = null
var _status_until := 0.0
var _joy_prev := {}
var _ui_lock := false
var _leaving := false
# UI
var _root_box: HBoxContainer
var _name_edit: LineEdit
var _base_opt: OptionButton
var _variant_opt: OptionButton
var _tab_buttons: Array[Button] = []
var _palette: ItemList
var _palette_desc: Label
var _meters := {}
var _inspector: VBoxContainer
var _layout_box: VBoxContainer
var _issues_box: VBoxContainer
var _status: Label
var _hints: Label
var _undo_btn: Button
var _redo_btn: Button
var _right_scroll: ScrollContainer
var _first_panel_control: Control


# =====================================================================================
# Lifecycle
# =====================================================================================

func on_enter(p: Dictionary) -> void:
	theme = _make_theme()
	_build_ui()
	if bool(p.get("resume", false)) and not _session.is_empty():
		_restore_session()
	elif p.has("example"):
		_open_content(str(p["example"]), false)
	elif p.has("path"):
		_open_file(str(p["path"]), false)
	elif p.has("layout"):
		_bind(ArenaEditModel.from_dict(p["layout"]), "")
	elif not _session.is_empty():
		_restore_session()
	else:
		_bind(ArenaEditModel.new_from_base("gullet"), "")
	set_process(true)
	set_process_input(true)


func on_exit() -> void:
	if not _leaving:
		_save_session()


func default_focus() -> Control:
	return vp


func _save_session() -> void:
	if model == null:
		return
	_session = {"model": model, "stack": stack, "path": path, "selected": selected, "tab": tab,
		"cam": [vp.yaw, vp.pitch, vp.dist, vp.focus] if vp else []}


func _restore_session() -> void:
	var m: ArenaEditModel = _session["model"]
	var st: ArenaEditCommands.Stack = _session["stack"]
	_bind(m, str(_session.get("path", "")), st)
	tab = int(_session.get("tab", 0))
	_refresh_palette()
	var cam: Array = _session.get("cam", [])
	if cam.size() == 4:
		vp.yaw = float(cam[0])
		vp.pitch = float(cam[1])
		vp.dist = float(cam[2])
		vp.set_focus(cam[3], true)
	_select(int(_session.get("selected", -1)))
	_status_msg("Back from test play.")


func _bind(m: ArenaEditModel, file_path: String, st: ArenaEditCommands.Stack = null) -> void:
	if model and model.changed.is_connected(_on_model_changed):
		model.changed.disconnect(_on_model_changed)
	model = m
	stack = st if st != null else ArenaEditCommands.Stack.new(m)
	if not stack.changed.is_connected(_refresh_history):
		stack.changed.connect(_refresh_history)
	model.changed.connect(_on_model_changed)
	path = file_path
	selected = -1
	carrying = false
	vp.show_arena(model.to_arena())
	vp.reset_camera()
	cursor = Vector3.ZERO
	_dirty_static = false
	_dirty_view = false
	_need_validate = true
	_refresh_all()


func _on_model_changed(what: String) -> void:
	if what in ["size", "base", "variant", "restore", "load"]:
		_dirty_static = true
	else:
		_dirty_view = true
	_need_validate = true
	if what in ["name", "id"]:
		_name_edit.text = model.name


# =====================================================================================
# UI construction
# =====================================================================================

func _make_theme() -> Theme:
	var t := Theme.new()
	var body := load("res://assets/fonts/Barlow-400.woff2")
	var bold := load("res://assets/fonts/Barlow-600.woff2")
	t.default_font = body
	t.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(COL_BG, 0.94)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("#2B2F3A")
	btn.set_corner_radius_all(5)
	btn.set_content_margin_all(7)
	var btn_hover := btn.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color("#3A3F4C")
	var btn_press := btn.duplicate() as StyleBoxFlat
	btn_press.bg_color = Color("#4A3F1C")
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = COL_GOLD
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(6)
	focus.set_expand_margin_all(2)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, btn_hover)
		t.set_stylebox("pressed", cls, btn_press)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, COL_TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_font("font", cls, bold)
	for cls2 in ["LineEdit", "SpinBox", "ItemList", "HSlider"]:
		t.set_stylebox("focus", cls2, focus)
	var field := StyleBoxFlat.new()
	field.bg_color = Color("#12141A")
	field.set_corner_radius_all(4)
	field.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("panel", "ItemList", field)
	t.set_color("font_color", "LineEdit", COL_TEXT)
	t.set_color("font_color", "ItemList", COL_TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color("#4A3F1C")
	sel.set_corner_radius_all(4)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_stylebox("cursor", "ItemList", focus)
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_color("font_color", "CheckBox", COL_TEXT)
	return t


func _header(text: String, size := 26) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", load("res://assets/fonts/BarlowCondensed-900.woff2"))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", COL_GOLD)
	return l


func _label(text: String, col := COL_TEXT, size := 19) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_ALL
	return b


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0B0D12")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_root_box = HBoxContainer.new()
	_root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_box.add_theme_constant_override("separation", 8)
	_root_box.offset_left = 8
	_root_box.offset_top = 8
	_root_box.offset_right = -8
	_root_box.offset_bottom = -8
	add_child(_root_box)
	_build_palette_panel()
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	_root_box.add_child(center)
	_build_top_bar(center)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color.BLACK
	fs.set_border_width_all(2)
	fs.border_color = Color("#2B2F3A")
	frame.add_theme_stylebox_override("panel", fs)
	center.add_child(frame)
	vp = ArenaEditorViewport.new()
	vp.name = "Viewport3D"
	frame.add_child(vp)
	vp.pointer_moved.connect(_on_pointer_moved)
	vp.pointer_pressed.connect(_on_pointer_pressed)
	vp.pointer_released.connect(_on_pointer_released)
	vp.focus_entered.connect(func(): _refresh_hints())
	var bottom := PanelContainer.new()
	center.add_child(bottom)
	var bb := VBoxContainer.new()
	bottom.add_child(bb)
	_status = _label("", COL_TEXT, 19)
	bb.add_child(_status)
	_hints = _label("", COL_MUTED, 17)
	bb.add_child(_hints)
	_build_right_panel()


func _build_top_bar(parent: Control) -> void:
	var bar := PanelContainer.new()
	parent.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(200, 0)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = "Layout name"
	_name_edit.max_length = 40
	_name_edit.text_submitted.connect(func(_t): _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	row.add_child(_name_edit)
	_base_opt = OptionButton.new()
	_base_opt.tooltip_text = "Arena base (starts a new layout)"
	row.add_child(_base_opt)
	for b in ArenaCatalog.base_ids():
		_base_opt.add_item(str(ArenaCatalog.base(b).get("name", b)))
		_base_opt.set_item_metadata(_base_opt.item_count - 1, b)
	_base_opt.item_selected.connect(_on_base_selected)
	_variant_opt = OptionButton.new()
	_variant_opt.tooltip_text = "Theme variant"
	_variant_opt.item_selected.connect(_on_variant_selected)
	row.add_child(_variant_opt)
	_undo_btn = _button("Undo", _undo, "Ctrl+Z")
	_redo_btn = _button("Redo", _redo, "Ctrl+Y")
	row.add_child(_undo_btn)
	row.add_child(_redo_btn)
	row.add_child(_button("Save", _save, "Ctrl+S"))
	row.add_child(_button("Load", _open_load_dialog))
	row.add_child(_button("Test Play", _open_test_dialog, "F5"))
	row.add_child(_button("Menu", _open_menu, "Start / Esc"))


func _build_palette_panel() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	_root_box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(_header("ARENA EDITOR", 34))
	v.add_child(_header("PALETTE", 24))
	var tabs := HFlowContainer.new()
	v.add_child(tabs)
	for i in TABS.size():
		var tb := _button(str(ArenaCatalog.TAB_LABELS[TABS[i]]), _set_tab.bind(i), "LB / RB  ·  [ / ]")
		tb.toggle_mode = true
		tabs.add_child(tb)
		_tab_buttons.append(tb)
	_palette = ItemList.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.custom_minimum_size = Vector2(0, 420)
	_palette.item_selected.connect(_on_palette_selected)
	_palette.item_activated.connect(func(i): _on_palette_selected(i); vp.grab_focus())
	v.add_child(_palette)
	_palette_desc = _label("", COL_MUTED, 17)
	_palette_desc.custom_minimum_size = Vector2(0, 110)
	v.add_child(_palette_desc)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_button("Grid snap", func(): _toggle_snap(), "G / L3"))
	row.add_child(_button("Team", func(): _cycle_team(), "T: spawn/goal team"))
	row.add_child(_button("Help", _open_help, "H"))


func _build_right_panel() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	_root_box.add_child(panel)
	_right_scroll = ScrollContainer.new()
	_right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_right_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	_right_scroll.add_child(v)
	v.add_child(_header("BUDGET"))
	for key in ["budget", "props", "hazards", "pickups", "clear_floor"]:
		var row := HBoxContainer.new()
		var name_l := _label({"budget": "Points", "props": "Props", "hazards": "Hazards", "pickups": "Pickups", "clear_floor": "Clear floor"}[key], COL_MUTED, 18)
		name_l.custom_minimum_size = Vector2(110, 0)
		row.add_child(name_l)
		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(0, 22)
		bar.show_percentage = false
		row.add_child(bar)
		var val := _label("", COL_TEXT, 18)
		val.custom_minimum_size = Vector2(90, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val)
		v.add_child(row)
		_meters[key] = [bar, val]
	v.add_child(_header("SELECTION"))
	_inspector = VBoxContainer.new()
	v.add_child(_inspector)
	v.add_child(_header("LAYOUT"))
	_layout_box = VBoxContainer.new()
	v.add_child(_layout_box)
	v.add_child(_header("VALIDATION"))
	_issues_box = VBoxContainer.new()
	v.add_child(_issues_box)


# =====================================================================================
# Refresh
# =====================================================================================

func _refresh_all() -> void:
	_name_edit.text = model.name
	for i in _base_opt.item_count:
		if str(_base_opt.get_item_metadata(i)) == model.base:
			_base_opt.select(i)
	_variant_opt.clear()
	var vs: Dictionary = model.base_def().get("variants", {})
	var k := 0
	for vid in vs:
		_variant_opt.add_item(str(vs[vid].get("label", str(vid).capitalize())))
		_variant_opt.set_item_metadata(k, vid)
		if str(vid) == model.variant or (model.variant == "" and str(vid) == str(model.base_def().get("default_variant", ""))):
			_variant_opt.select(k)
		k += 1
	_refresh_palette()
	_refresh_layout_panel()
	_refresh_inspector()
	_refresh_history()
	_refresh_hints()


func _refresh_history() -> void:
	if _undo_btn:
		_undo_btn.disabled = not stack.can_undo()
		_redo_btn.disabled = not stack.can_redo()


func _refresh_palette() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == tab
	_palette.clear()
	var entries := ArenaCatalog.palette(TABS[tab])
	for e in entries:
		var cost := int(e["cost"])
		var label := "%s   %s" % [str(e["name"]), ("%d pt" % cost) if cost > 0 else "free"]
		var idx := _palette.add_item(label)
		_palette.set_item_metadata(idx, e["id"])
		if not _placement_allowed(str(e["id"])).is_empty():
			_palette.set_item_custom_fg_color(idx, COL_MUTED)
		if str(e["id"]) == armed:
			_palette.select(idx)
	_update_palette_desc()


func _update_palette_desc() -> void:
	if armed == "":
		_palette_desc.text = "Pick an item, then click (or press A) on the floor to place it. Nothing armed: click (A) selects."
		return
	var d := ArenaCatalog.prop(armed)
	var extra := ""
	if bool(d.get("is_marker", false)) and bool(d["marker"]["teams"]):
		extra = "  ·  Team: %s (T)" % ["none", "A", "B"][armed_team + 1]
	_palette_desc.text = "%s — %s%s" % [str(d.get("name", armed)), str(d.get("description", "")), extra]


func _refresh_layout_panel() -> void:
	for c in _layout_box.get_children():
		c.queue_free()
	var bd := model.base_def()
	var lo: Vector2 = bd.get("size_min", model.size)
	var hi: Vector2 = bd.get("size_max", model.size)
	var uniform := bool(bd.get("uniform", false))
	_layout_box.add_child(_label("Boundary (metres): %s %.1f – %.1f" % ["size" if uniform else "width", lo.x, hi.x], COL_MUTED, 17))
	_layout_box.add_child(_size_slider(0, lo.x, hi.x, model.size.x, float(bd.get("size_step", 0.5))))
	if not uniform and hi.y > lo.y:
		_layout_box.add_child(_label("Depth %.1f – %.1f" % [lo.y, hi.y], COL_MUTED, 17))
		_layout_box.add_child(_size_slider(1, lo.y, hi.y, model.size.y, float(bd.get("size_step", 0.5))))
	_layout_box.add_child(_label("Supported modes", COL_MUTED, 17))
	var modes_flow := HFlowContainer.new()
	_layout_box.add_child(modes_flow)
	for m in ArenaValidator.MODE_REQUIREMENTS:
		if str(m) == "practice":
			continue
		var cb := CheckBox.new()
		cb.text = str(ArenaValidator.MODE_LABELS.get(m, m))
		cb.button_pressed = model.modes.has(m)
		cb.toggled.connect(_on_mode_toggled.bind(str(m)))
		modes_flow.add_child(cb)
	var hz: Array = bd.get("hazards", [])
	if not hz.is_empty():
		_layout_box.add_child(_label("Base hazards", COL_MUTED, 17))
		for h in hz:
			var fl := str(h.get("flag", ""))
			if fl == "":
				continue
			var cb2 := CheckBox.new()
			cb2.text = str(h.get("label", fl.capitalize()))
			cb2.button_pressed = bool(model.flags.get(fl, true))
			cb2.toggled.connect(_on_flag_toggled.bind(fl))
			_layout_box.add_child(cb2)
	if not bool(bd.get("allow_pits", false)):
		var cb3 := CheckBox.new()
		cb3.text = "Allow pits on this base"
		cb3.button_pressed = bool(model.flags.get("allow_pits", false))
		cb3.toggled.connect(_on_flag_toggled.bind("allow_pits"))
		_layout_box.add_child(cb3)
	var bis: Array = bd.get("builtins", [])
	if not bis.is_empty():
		_layout_box.add_child(_label("Built-in props (kept)", COL_MUTED, 17))
		var flow := HFlowContainer.new()
		_layout_box.add_child(flow)
		for b in bis:
			var bid := str(b.get("id", ""))
			var cb4 := CheckBox.new()
			cb4.text = bid.replace("_", " ")
			cb4.button_pressed = not model.removed_builtins.has(bid)
			cb4.disabled = not bool(b.get("removable", true))
			cb4.toggled.connect(_on_builtin_toggled.bind(bid))
			flow.add_child(cb4)


func _size_slider(axis: int, lo: float, hi: float, cur: float, step: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = cur
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_ALL
	var val := _label("%.1f m" % cur, COL_TEXT, 18)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(x): val.text = "%.1f m" % x)
	s.drag_ended.connect(func(_c): _on_size_changed(axis, s.value))
	s.focus_exited.connect(func(): _on_size_changed(axis, s.value))
	row.add_child(s)
	row.add_child(val)
	return row


func _refresh_inspector() -> void:
	for c in _inspector.get_children():
		c.queue_free()
	var it := model.get_item(selected) if selected >= 0 else {}
	if it.is_empty():
		_inspector.add_child(_label("Nothing selected. Click an item (A) to select it; drag it (or A again with a controller) to move it.", COL_MUTED, 17))
		return
	var d := ArenaCatalog.prop(str(it["type"]))
	_inspector.add_child(_label("%s  ·  %s" % [str(d.get("name", it["type"])), ("%d pt" % int(d.get("cost", 0))) if int(d.get("cost", 0)) > 0 else "free"], COL_TEXT, 20))
	var pos: Vector3 = it["pos"]
	_inspector.add_child(_spin_row("X", pos.x, -20.0, 20.0, 0.05, func(v): _set_item_value("x", v)))
	_inspector.add_child(_spin_row("Z", pos.z, -20.0, 20.0, 0.05, func(v): _set_item_value("z", v)))
	_inspector.add_child(_spin_row("Yaw", snappedf(rad_to_deg(float(it["yaw"])), 0.1), -360.0, 360.0, float(d.get("rotation_step", 15.0)), func(v): _set_item_value("yaw", v)))
	if it.has("pos2"):
		var p2: Vector3 = it["pos2"]
		_inspector.add_child(_spin_row("End X", p2.x, -20.0, 20.0, 0.05, func(v): _set_item_value("x2", v)))
		_inspector.add_child(_spin_row("End Z", p2.z, -20.0, 20.0, 0.05, func(v): _set_item_value("z2", v)))
	if bool(d.get("is_marker", false)) and bool(d["marker"]["teams"]):
		var opt := OptionButton.new()
		for t in ["No team", "Team A", "Team B"]:
			opt.add_item(t)
		opt.select(int(it.get("team", -1)) + 1)
		opt.item_selected.connect(func(i): _set_item_value("team", float(i - 1)))
		_inspector.add_child(opt)
	var row := HBoxContainer.new()
	row.add_child(_button("Duplicate", _duplicate, "Ctrl+D"))
	row.add_child(_button("Rotate", func(): _rotate(1), "R / Y"))
	row.add_child(_button("Delete", _delete, "Del / X"))
	_inspector.add_child(row)


func _spin_row(label: String, value: float, lo: float, hi: float, step: float, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _label(label, COL_MUTED, 18)
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = value
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(cb)
	row.add_child(sb)
	return row


func _refresh_validation() -> void:
	validation = ArenaValidator.validate(model.to_arena(true))
	var st: Dictionary = validation["stats"]
	_meter("budget", float(st["budget"]), 100.0, "%d / 100" % int(st["budget"]))
	_meter("props", float(st["props"]), 24.0, "%d / 24" % int(st["props"]))
	_meter("hazards", float(st["hazards"]), 8.0, "%d / 8" % int(st["hazards"]))
	_meter("pickups", float(st["pickups"]), 4.0, "%d / 4" % int(st["pickups"]))
	var cf := float(st["clear_floor"])
	_meter("clear_floor", cf, 1.0, "%d%%" % roundi(cf * 100.0), cf < ArenaValidator.MIN_CLEAR)
	for c in _issues_box.get_children():
		c.queue_free()
	var issues: Array = validation["errors"] + validation["warnings"]
	if issues.is_empty():
		_issues_box.add_child(_label("✔ Layout is valid for every declared mode.", COL_OK, 19))
	for it in issues:
		var err := str(it["severity"]) == "error"
		var b := Button.new()
		b.text = ("✖ " if err else "▲ ") + str(it["message"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_color_override("font_color", COL_DANGER if err else COL_WARN)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_on_issue_pressed.bind(it))
		_issues_box.add_child(b)
	vp.set_pins(issues)
	_palette_colors()


func _meter(key: String, v: float, mx: float, text: String, bad := false) -> void:
	var bar: ProgressBar = _meters[key][0]
	var lbl: Label = _meters[key][1]
	bar.max_value = mx
	bar.value = minf(v, mx)
	var over := bad or (key != "clear_floor" and v > mx)
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_DANGER if over else (COL_GOLD if key != "clear_floor" else COL_OK)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	lbl.text = text
	lbl.add_theme_color_override("font_color", COL_DANGER if over else COL_TEXT)


func _palette_colors() -> void:
	for i in _palette.item_count:
		var id := str(_palette.get_item_metadata(i))
		_palette.set_item_custom_fg_color(i, COL_TEXT if _placement_allowed(id).is_empty() else COL_MUTED)


func _refresh_hints() -> void:
	if _hints == null:
		return
	if Controls.last_device == "gamepad":
		_hints.text = "LS cursor · RS orbit · LT/RT zoom · A place/select (A on selection = carry) · B cancel · X delete · Y rotate · LB/RB tabs · D-pad nudge/item · View panels · Menu: Start"
	else:
		_hints.text = "LMB place/select/drag (Alt: free) · RMB orbit/cancel · MMB pan · Wheel zoom · R rotate · Del delete · Ctrl+D dup · Ctrl+Z/Y undo/redo · Ctrl+S save · [ ] tabs · T team · G snap · F5 test · Esc menu"


func _status_msg(text: String, col := COL_TEXT, seconds := 4.0) -> void:
	if _status:
		_status.text = text
		_status.add_theme_color_override("font_color", col)
		_status_until = Time.get_ticks_msec() / 1000.0 + seconds


# =====================================================================================
# Per-frame: deferred rebuilds, controller polling, ghost/cursor
# =====================================================================================

func _process(dt: float) -> void:
	if model == null:
		return
	if _dirty_static:
		_dirty_static = false
		_dirty_view = false
		vp.show_arena(model.to_arena())
		_refresh_all()
		_refresh_selection_visual()
	elif _dirty_view:
		_dirty_view = false
		vp.show_layout(model.to_arena(true))
		_refresh_selection_visual()
	if _need_validate:
		_need_validate = false
		_refresh_validation()
	if _status and _status.text != "" and Time.get_ticks_msec() / 1000.0 > _status_until:
		_status.text = ""
	if _overlay == null and _canvas_active():
		_poll_sticks(dt)
	_update_ghost()


func _canvas_active() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f == null or f == vp


func _poll_sticks(dt: float) -> void:
	var lx := 0.0
	var ly := 0.0
	var rx := 0.0
	var ry := 0.0
	var lt := 0.0
	var rt := 0.0
	for dev in Input.get_connected_joypads():
		lx = _strongest(lx, Input.get_joy_axis(dev, JOY_AXIS_LEFT_X))
		ly = _strongest(ly, Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		rx = _strongest(rx, Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X))
		ry = _strongest(ry, Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		lt = maxf(lt, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT))
		rt = maxf(rt, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT))
	var lstick := Vector2(lx, ly)
	if lstick.length() > STICK_DEAD:
		var ax: Array = vp.ground_axes()
		var right: Vector3 = ax[0]
		var fwd: Vector3 = ax[1]
		var spd := 4.0 + vp.dist * 0.35
		var dv := (right * lstick.x - fwd * lstick.y) * spd * dt * clampf((lstick.length() - STICK_DEAD) / (1.0 - STICK_DEAD), 0.0, 1.0)
		_move_cursor(cursor + dv, true)
	if absf(rx) > STICK_DEAD:
		vp.orbit(-rx * dt * 2.4, 0.0)
	if absf(ry) > STICK_DEAD:
		vp.orbit(0.0, ry * dt * 1.6)
	if lt > 0.2:
		vp.zoom(1.0 + lt * dt * 1.6)
	if rt > 0.2:
		vp.zoom(1.0 - rt * dt * 1.4)


static func _strongest(a: float, b: float) -> float:
	return b if absf(b) > absf(a) else a


func _move_cursor(p: Vector3, follow_cam: bool) -> void:
	var lim := model_extent().grow(1.0) if model else Rect2(-10, -10, 20, 20)
	cursor = Vector3(clampf(p.x, lim.position.x, lim.end.x), 0.0, clampf(p.z, lim.position.y, lim.end.y))
	vp.set_cursor(cursor, true)
	if follow_cam:
		vp.set_focus(cursor)
	if carrying and selected >= 0:
		_drag_to(cursor, false)


func model_extent() -> Rect2:
	return vp.arena.extent() if vp.arena else Rect2(-6, -6, 12, 12)


func _snap(p: Vector3, free := false) -> Vector3:
	if free or not snap_on:
		return Vector3(snappedf(p.x, 0.05), 0.0, snappedf(p.z, 0.05))
	return Vector3(snappedf(p.x, grid_step), 0.0, snappedf(p.z, grid_step))


func _update_ghost() -> void:
	if armed == "" or not vp:
		vp.clear_ghost()
		return
	var def := ArenaCatalog.prop(armed)
	var item := {"type": armed, "pos": _snap(cursor), "yaw": armed_yaw, "team": armed_team, "params": {}, "scale": 1.0}
	if ArenaCatalog.footprint_shape(def) == "pair":
		var sep := float(def["params"].get("separation", 4.0))
		item["pos2"] = item["pos"] + Vector3(cos(armed_yaw) * sep, 0, -sin(armed_yaw) * sep)
	vp.set_ghost(def, item, _placement_valid(def, item))


func _placement_valid(def: Dictionary, item: Dictionary) -> bool:
	if not vp.arena:
		return true
	for v in ArenaCatalog.footprint_outline(item, def):
		if not vp.arena.on_floor(Vector3(v.x, 0, v.y), -0.02):
			return false
	return _placement_allowed(str(def["id"])).is_empty()


## "" when one more of this type may be placed, else the reason.
func _placement_allowed(type_id: String) -> String:
	var d := ArenaCatalog.prop(type_id)
	if d.is_empty():
		return "unknown"
	if bool(d["is_marker"]):
		var mname := str(d["marker"]["name"])
		if mname == "spawn":
			var cap := 8 if armed_team < 0 else int(d["marker"]["team_max"])
			if model.count_markers("spawn", armed_team) >= cap:
				return "That spawn group is full."
		elif model.count_markers(mname) >= int(d["marker"]["max"]):
			return "At most %d %s markers." % [int(d["marker"]["max"]), str(d["name"])]
		return ""
	var n := 0
	for it in model.items:
		if str(it["type"]) == type_id:
			n += 1
	if int(d["max_per_layout"]) > 0 and n >= int(d["max_per_layout"]):
		return "At most %d %s per layout." % [int(d["max_per_layout"]), str(d["name"])]
	if str(d["behaviour"]) == "pit" and vp.arena and not vp.arena.allows_pits():
		return "Pits need an open-edge base (or 'Allow pits')."
	return ""


# =====================================================================================
# Pointer & editing actions
# =====================================================================================

func _on_pointer_moved(world: Vector3) -> void:
	if _overlay:
		return
	cursor = world
	vp.set_cursor(world, true)
	if not _drag.is_empty():
		_drag_to(world, Input.is_key_pressed(KEY_ALT))


func _on_pointer_pressed(world: Vector3, button: int, _shift: bool, alt: bool) -> void:
	if _overlay:
		return
	cursor = world
	if button == MOUSE_BUTTON_RIGHT:
		_cancel()
		return
	if armed != "":
		_place_at(world, alt)
		return
	var hit := _pick(world)
	if hit.is_empty():
		_select(-1)
		return
	_select(int(hit["uid"]))
	_begin_drag(int(hit["uid"]), world, str(hit["end"]))


func _on_pointer_released(_world: Vector3, _button: int) -> void:
	_end_drag()


## Topmost item under p: markers first, then smallest footprint. {uid, end: "pos"|"pos2"}.
func _pick(p: Vector3) -> Dictionary:
	var best := {}
	var best_area := INF
	var p2 := Vector2(p.x, p.z)
	for it in model.items:
		var d := ArenaCatalog.prop(str(it["type"]))
		if bool(d.get("is_marker", false)):
			var c: Vector3 = it["pos"]
			if p2.distance_to(Vector2(c.x, c.z)) <= 0.6:
				return {"uid": int(it["uid"]), "end": "pos"}
			continue
		var end := "pos"
		if it.has("pos2"):
			var c2: Vector3 = it["pos2"]
			if p2.distance_to(Vector2(c2.x, c2.z)) <= 0.6:
				end = "pos2"
		var dd := ArenaCatalog.footprint_distance(it, d, p2)
		if dd <= 0.08 or end == "pos2":
			var area := ArenaCatalog.footprint_area(it, d)
			if area < best_area:
				best_area = area
				best = {"uid": int(it["uid"]), "end": end}
	return best


func _place_at(world: Vector3, free: bool) -> void:
	var why := _placement_allowed(armed)
	if why != "":
		_status_msg(why, COL_WARN)
		return
	var it := model.make_item(armed, _snap(world, free), armed_yaw)
	it["team"] = armed_team if str(it["kind"]) == "marker" else -1
	if it.has("pos2"):
		var sep := float(ArenaCatalog.prop(armed)["params"].get("separation", 4.0))
		it["pos2"] = (it["pos"] as Vector3) + Vector3(cos(armed_yaw) * sep, 0, -sin(armed_yaw) * sep)
	stack.execute(ArenaEditCommands.AddItems.new([it], "Place %s" % str(ArenaCatalog.prop(armed)["name"])))
	_status_msg("Placed %s." % str(ArenaCatalog.prop(armed)["name"]))
	_select(int(it["uid"]), false)


func _begin_drag(uid: int, world: Vector3, end := "pos") -> void:
	var it := model.get_item(uid)
	if it.is_empty():
		return
	var anchor: Vector3 = it[end]
	_drag = {"uid": uid, "before": it.duplicate(true), "offset": anchor - world, "end": end, "moved": false}


func _drag_to(world: Vector3, free: bool) -> void:
	var uid := int(_drag.get("uid", selected))
	var it := model.get_item(uid)
	if it.is_empty():
		return
	var end := str(_drag.get("end", "pos"))
	var offset: Vector3 = _drag.get("offset", Vector3.ZERO)
	var target := _snap(world + offset, free)
	var cur: Vector3 = it[end]
	if target.distance_to(cur) < 0.001:
		return
	var moved := it.duplicate(true)
	if end == "pos" and moved.has("pos2"):
		moved["pos2"] = (moved["pos2"] as Vector3) + (target - cur)
	moved[end] = target
	model.replace_item(uid, moved)
	if not _drag.is_empty():
		_drag["moved"] = true


func _end_drag() -> void:
	if _drag.is_empty():
		return
	var uid := int(_drag["uid"])
	if bool(_drag.get("moved", false)):
		stack.push_applied(ArenaEditCommands.ModifyItems.new([[uid, _drag["before"], model.get_item(uid)]], "Move"))
		_refresh_inspector()
	_drag = {}


func _select(uid: int, refresh := true) -> void:
	if not carrying:
		_end_drag()
	selected = uid if model.index_of(uid) >= 0 else -1
	if selected < 0:
		carrying = false
	_refresh_selection_visual()
	if refresh:
		_refresh_inspector()
	else:
		_refresh_inspector.call_deferred()


func _refresh_selection_visual() -> void:
	var it := model.get_item(selected) if selected >= 0 else {}
	if it.is_empty():
		vp.clear_selection()
	else:
		vp.set_selection(it, ArenaCatalog.prop(str(it["type"])))


func _cancel() -> bool:
	if carrying:
		_end_drag()
		carrying = false
		_status_msg("Dropped.")
		return true
	if armed != "":
		armed = ""
		_palette.deselect_all()
		_update_palette_desc()
		return true
	if selected >= 0:
		_select(-1)
		return true
	return false


func _modify_selected(fn: Callable, label: String) -> void:
	if selected < 0:
		return
	var before := model.get_item(selected).duplicate(true)
	var after := before.duplicate(true)
	fn.call(after)
	if after == before:
		return
	stack.execute(ArenaEditCommands.ModifyItems.new([[selected, before, after]], label))
	_refresh_inspector()


func _rotate(dir: int) -> void:
	if selected < 0 and armed != "":
		var step := deg_to_rad(float(ArenaCatalog.prop(armed).get("rotation_step", 15.0)))
		armed_yaw = wrapf(armed_yaw + step * dir, -PI, PI)
		return
	if selected < 0:
		return
	var step2 := deg_to_rad(float(ArenaCatalog.prop(str(model.get_item(selected)["type"])).get("rotation_step", 15.0)))
	var turn := func(it: Dictionary) -> void:
		var c: Vector3 = it["pos"]
		it["yaw"] = wrapf(float(it["yaw"]) + step2 * dir, -PI, PI)
		if it.has("pos2"):
			var off: Vector3 = (it["pos2"] as Vector3) - c
			it["pos2"] = c + off.rotated(Vector3.UP, step2 * dir)
	_modify_selected(turn, "Rotate")


func _nudge(dir: Vector2) -> void:
	if selected < 0:
		return
	var ax: Array = vp.ground_axes()
	var right: Vector3 = ax[0]
	var fwd: Vector3 = ax[1]
	var dv := right * dir.x + fwd * dir.y
	var step := grid_step if snap_on else 0.1
	var snapped := Vector3(signf(dv.x) * step if absf(dv.x) > 0.5 else 0.0, 0.0, signf(dv.z) * step if absf(dv.z) > 0.5 else 0.0)
	var move := func(it: Dictionary) -> void:
		it["pos"] = (it["pos"] as Vector3) + snapped
		if it.has("pos2"):
			it["pos2"] = (it["pos2"] as Vector3) + snapped
	_modify_selected(move, "Nudge")
	_refresh_selection_visual()


func _delete() -> void:
	if selected < 0:
		return
	var name_ := str(ArenaCatalog.prop(str(model.get_item(selected)["type"])).get("name", "item"))
	stack.execute(ArenaEditCommands.RemoveItems.new(model, [selected], "Delete %s" % name_))
	_status_msg("Deleted %s." % name_)
	_select(-1)


func _duplicate() -> void:
	if selected < 0:
		return
	var src := model.get_item(selected)
	var type_id := str(src["type"])
	var why := ""
	var save_team := armed_team
	armed_team = int(src.get("team", -1))
	why = _placement_allowed(type_id)
	armed_team = save_team
	if why != "":
		_status_msg(why, COL_WARN)
		return
	var copy := src.duplicate(true)
	copy["uid"] = model.new_uid()
	var off := Vector3(1.0, 0, 1.0)
	copy["pos"] = (copy["pos"] as Vector3) + off
	if copy.has("pos2"):
		copy["pos2"] = (copy["pos2"] as Vector3) + off
	stack.execute(ArenaEditCommands.AddItems.new([copy], "Duplicate"))
	_select(int(copy["uid"]))


func _cycle_team() -> void:
	if selected >= 0:
		var d := ArenaCatalog.prop(str(model.get_item(selected)["type"]))
		if bool(d.get("is_marker", false)) and bool(d["marker"]["teams"]):
			_modify_selected(func(it: Dictionary): it["team"] = (int(it.get("team", -1)) + 2) % 3 - 1, "Team")
			return
	armed_team = (armed_team + 2) % 3 - 1
	_update_palette_desc()
	_status_msg("Markers will be placed for %s." % ["no team", "team A", "team B"][armed_team + 1])


func _toggle_snap() -> void:
	snap_on = not snap_on
	vp.set_grid_visible(snap_on)
	_status_msg("Grid snap %s (%.1f m)." % ["on" if snap_on else "off", grid_step])


func _set_item_value(key: String, v: float) -> void:
	if _ui_lock:
		return
	var edit := func(it: Dictionary) -> void:
		match key:
			"x":
				it["pos"] = Vector3(v, 0, (it["pos"] as Vector3).z)
			"z":
				it["pos"] = Vector3((it["pos"] as Vector3).x, 0, v)
			"x2":
				it["pos2"] = Vector3(v, 0, (it["pos2"] as Vector3).z)
			"z2":
				it["pos2"] = Vector3((it["pos2"] as Vector3).x, 0, v)
			"yaw":
				it["yaw"] = deg_to_rad(v)
			"team":
				it["team"] = int(v)
	_modify_selected(edit, "Edit")
	_refresh_selection_visual()


func _set_tab(i: int) -> void:
	tab = posmod(i, TABS.size())
	_refresh_palette()


func _on_palette_selected(i: int) -> void:
	armed = str(_palette.get_item_metadata(i))
	armed_yaw = 0.0
	var d := ArenaCatalog.prop(armed)
	if not bool(d.get("is_marker", false)) or not bool(d["marker"]["teams"]):
		armed_team = -1
	_select(-1)
	_update_palette_desc()
	var why := _placement_allowed(armed)
	if why != "":
		_status_msg(why, COL_WARN)


func _palette_step(dir: int) -> void:
	if _palette.item_count == 0:
		return
	var cur := -1
	for i in _palette.item_count:
		if str(_palette.get_item_metadata(i)) == armed:
			cur = i
	var nxt := posmod(cur + dir, _palette.item_count) if cur >= 0 else (0 if dir > 0 else _palette.item_count - 1)
	_palette.select(nxt)
	_palette.ensure_current_is_visible()
	_on_palette_selected(nxt)


func _on_issue_pressed(issue: Dictionary) -> void:
	var ref: Dictionary = issue.get("ref", {})
	var uid := int(ref.get("uid", -1))
	if uid >= 0 and model.index_of(uid) >= 0:
		armed = ""
		_select(uid)
		var it := model.get_item(uid)
		vp.set_focus(it["pos"])
		cursor = it["pos"]
		vp.set_cursor(cursor, true)
		vp.grab_focus()
		_status_msg(str(issue["message"]), COL_DANGER if str(issue["severity"]) == "error" else COL_WARN, 6.0)
	elif str(ref.get("kind", "")) == "builtin":
		_status_msg("Built-in '%s': %s (toggle it under Layout)." % [str(ref.get("id", "")), str(issue["message"])], COL_WARN, 6.0)
	else:
		_right_scroll.ensure_control_visible(_layout_box)
		_status_msg(str(issue["message"]), COL_WARN, 6.0)


# =====================================================================================
# Layout-level changes
# =====================================================================================

func _commit_name() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "" or n == model.name:
		_name_edit.text = model.name
		return
	stack.execute(ArenaEditCommands.SetField.new("name", model.name, n, "Rename"))


func _on_base_selected(i: int) -> void:
	var b := str(_base_opt.get_item_metadata(i))
	if b == model.base:
		return
	var fresh := ArenaEditModel.new_from_base(b)
	stack.execute(ArenaEditCommands.SetState.new(model.snapshot(), fresh.snapshot(), "Change base"))
	selected = -1
	vp.reset_camera()
	_status_msg("New %s layout (undo to go back)." % str(ArenaCatalog.base(b).get("name", b)))


func _on_variant_selected(i: int) -> void:
	var v := str(_variant_opt.get_item_metadata(i))
	if v != model.variant:
		stack.execute(ArenaEditCommands.SetField.new("variant", model.variant, v, "Variant"))


func _on_size_changed(axis: int, value: float) -> void:
	var s := model.size
	if axis == 0:
		s.x = value
		if bool(model.base_def().get("uniform", false)):
			s.y = value
	else:
		s.y = value
	s = ArenaDef.clamp_size(model.base_def(), s)
	if s != model.size:
		stack.execute(ArenaEditCommands.SetField.new("size", model.size, s, "Boundary"))


func _on_mode_toggled(on: bool, m: String) -> void:
	var modes := model.modes.duplicate()
	if on and not modes.has(m):
		modes.append(m)
	elif not on:
		modes.erase(m)
	stack.execute(ArenaEditCommands.SetField.new("modes", model.modes, modes, "Modes"))


func _on_flag_toggled(on: bool, fl: String) -> void:
	var f := model.flags.duplicate(true)
	f[fl] = on
	stack.execute(ArenaEditCommands.SetField.new("flags", model.flags, f, "Hazards"))


func _on_builtin_toggled(on: bool, bid: String) -> void:
	var r := model.removed_builtins.duplicate()
	if on:
		r.erase(bid)
	elif not r.has(bid):
		r.append(bid)
	stack.execute(ArenaEditCommands.SetField.new("removed_builtins", model.removed_builtins, r, "Built-ins"))


func _undo() -> void:
	_end_drag()
	var l := stack.undo()
	if l != "":
		_status_msg("Undo: %s" % l)
		_after_history()


func _redo() -> void:
	var l := stack.redo()
	if l != "":
		_status_msg("Redo: %s" % l)
		_after_history()


func _after_history() -> void:
	if model.index_of(selected) < 0:
		selected = -1
	_refresh_inspector()
	_refresh_layout_panel()
	_name_edit.text = model.name


# =====================================================================================
# Files, packages, test play
# =====================================================================================

func _save() -> void:
	_commit_name()
	var want := "user:" + ArenaEditModel.slug_id(model.name)
	if model.id != want:
		model.id = want
	var r := ArenaLibrary.save_layout(model.to_dict(), path if path != "" and path.get_file() == ArenaLibrary.path_for(model.id).get_file() else "")
	if bool(r["ok"]):
		path = str(r["path"])
		stack.mark_clean()
		var errs: int = (validation.get("errors", []) as Array).size()
		_status_msg("Saved %s%s" % [path, "" if errs == 0 else "  (%d validation errors remain)" % errs], COL_OK if errs == 0 else COL_WARN, 6.0)
	else:
		_status_msg("Save failed: %s" % r["error"], COL_DANGER, 8.0)


func _open_file(p: String, undoable := true) -> void:
	var r := ArenaLibrary.load_layout(p)
	if not bool(r["ok"]):
		_status_msg("Could not load %s: %s" % [p.get_file(), r["error"]], COL_DANGER, 8.0)
		return
	_load_dict(r["data"], p, undoable)
	if bool(r.get("migrated", false)):
		_status_msg("Loaded and upgraded an older layout.", COL_WARN)


func _open_content(id: String, undoable := true) -> void:
	var d := Content.get_entry("arenas", id).duplicate(true)
	if d.is_empty():
		_status_msg("Unknown layout %s" % id, COL_DANGER)
		_bind(ArenaEditModel.new_from_base("gullet"), "")
		return
	d.erase("_package")
	d.erase("_file")
	d.erase("base_def")
	d.erase("example")
	_load_dict(d, "", undoable)


func _load_dict(d: Dictionary, p: String, undoable: bool) -> void:
	var m := ArenaEditModel.from_dict(d)
	if model == null or not undoable:
		_bind(m, p)
		return
	stack.execute(ArenaEditCommands.SetState.new(model.snapshot(), m.snapshot(), "Load %s" % m.name))
	path = p
	selected = -1
	vp.reset_camera()
	_status_msg("Loaded %s." % m.name)


func _export() -> void:
	var zip := ArenaPackage.packages_dir().path_join(ArenaEditModel.slug_id(model.name) + ".zip")
	var r := ArenaPackage.export_package([model.to_dict()], zip, {"name": model.name})
	if bool(r["ok"]):
		_status_msg("Exported %s  (hash %s)" % [zip, str(r["hash"]).substr(0, 12)], COL_OK, 8.0)
	else:
		_status_msg("Export failed: %s" % r["error"], COL_DANGER, 8.0)


func _import(zip: String) -> void:
	var r := ArenaPackage.import_package(zip)
	if not bool(r["ok"]):
		_dialog("Import rejected", "\n".join(r["errors"]))
		return
	var arenas: Array = r["arenas"]
	_load_dict(arenas[0], (r["installed"] as Array)[0] if not (r["installed"] as Array).is_empty() else "", true)
	var w: Array = r["warnings"]
	_status_msg("Imported %d arena(s)%s." % [arenas.size(), "" if w.is_empty() else " with %d warnings" % w.size()], COL_OK if w.is_empty() else COL_WARN, 8.0)


func _test_play(format: String) -> void:
	_close_overlay()
	_end_drag()
	var errs: Array = validation.get("errors", [])
	var a := model.to_arena(false)
	var creature := "dev_biped"
	var pc := Content.playable_creatures()
	if not pc.is_empty():
		creature = str(pc[0])
	var fighters := []
	var rules := {"mode": "standard", "rounds": 1, "round_time": 99, "win": "ko", "lives": 1}
	match format:
		"ffa":
			for i in 4:
				fighters.append({"creature": creature, "team": i, "kind": "player" if i == 0 else "bot", "difficulty": "regular", "name": "You" if i == 0 else "Bot %d" % i})
			rules["round_time"] = 120
		"teams":
			for i2 in 4:
				fighters.append({"creature": creature, "team": i2 % 2, "kind": "player" if i2 == 0 else "bot", "difficulty": "regular", "name": "You" if i2 == 0 else "Bot %d" % i2})
		"watch":
			for i3 in 4:
				fighters.append({"creature": creature, "team": i3, "kind": "bot", "difficulty": "pro", "name": "Bot %d" % (i3 + 1)})
		_:
			fighters = [{"creature": creature, "team": 0, "kind": "player", "name": "You"}, {"creature": creature, "team": 1, "kind": "bot", "difficulty": "regular", "name": "Sparring Bot"}]
	_save_session()
	var cfg := {"arena": a, "rules": rules, "seed": randi() % 100000, "fighters": fighters, "context": "arena_test"}
	var scene := App.start_match(cfg, func(_res): ArenaTestPlay.return_to_editor())
	scene.add_child(ArenaTestPlay.new())
	if not errs.is_empty():
		Log.w("arena_editor", "test play with %d validation errors" % errs.size())


# =====================================================================================
# Overlays (menu, load, test play, help, dialogs) — keyboard/controller navigable
# =====================================================================================

func _make_overlay(title: String, width := 620) -> VBoxContainer:
	_close_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(_header(title, 32))
	_overlay = dim
	return v


func _close_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if is_inside_tree():
		vp.grab_focus.call_deferred()


func _focus_first(v: Control) -> void:
	for c in v.find_children("*", "BaseButton", true, false):
		if (c as Control).visible and not (c as BaseButton).disabled:
			(c as Control).grab_focus.call_deferred()
			return


func _open_menu() -> void:
	var v := _make_overlay("EDITOR MENU", 520)
	for entry in [["Save  (Ctrl+S)", _save], ["Load layout / example", _open_load_dialog], ["New layout on a base", _open_new_dialog],
			["Test play  (F5)", _open_test_dialog], ["Export package", func(): _close_overlay(); _export()],
			["Import package", _open_import_dialog], ["Controls", _open_help], ["Exit editor", _exit], ["Back to editing", _close_overlay]]:
		var b := _button(str(entry[0]), entry[1])
		v.add_child(b)
	_focus_first(v)


func _open_new_dialog() -> void:
	var v := _make_overlay("NEW LAYOUT", 620)
	v.add_child(_label("Pick a base. The current layout can be restored with Undo.", COL_MUTED))
	for b in ArenaCatalog.base_ids():
		var bd := ArenaCatalog.base(b)
		var btn := _button("%s — %s" % [str(bd.get("name", b)), str(bd.get("description", "")).substr(0, 90)], _new_layout_on.bind(str(b)))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(btn)
	v.add_child(_button("Cancel", _close_overlay))
	_focus_first(v)


func _new_layout_on(b: String) -> void:
	_close_overlay()
	var fresh := ArenaEditModel.new_from_base(b)
	stack.execute(ArenaEditCommands.SetState.new(model.snapshot(), fresh.snapshot(), "New layout"))
	path = ""
	vp.reset_camera()


func _open_load_dialog() -> void:
	var v := _make_overlay("LOAD LAYOUT", 760)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 560)
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	list.add_child(_label("Examples", COL_GOLD))
	for e in ArenaLibrary.examples():
		var id := str(e["id"])
		list.add_child(_button("%s  ·  %s" % [str(e["name"]), str(ArenaCatalog.base(str(e["base"])).get("name", e["base"]))], func(): _close_overlay(); _open_content(id)))
	list.add_child(_label("Bases", COL_GOLD))
	for e2 in ArenaLibrary.base_arenas():
		var id2 := str(e2["id"])
		list.add_child(_button(str(e2["name"]), func(): _close_overlay(); _open_content(id2)))
	list.add_child(_label("Your layouts  (%s)" % ArenaLibrary.dir(), COL_GOLD))
	var saved := ArenaLibrary.list_saved()
	if saved.is_empty():
		list.add_child(_label("Nothing saved yet.", COL_MUTED))
	for s in saved:
		var p := str(s["path"])
		var txt := "%s  ·  %s" % [str(s["name"]), str(s["base"])] if not s.has("error") else "%s  (damaged: %s)" % [p.get_file(), str(s["error"]).substr(0, 60)]
		var b := _button(txt, func(): _close_overlay(); _open_file(p))
		b.disabled = s.has("error")
		list.add_child(b)
	v.add_child(_button("Cancel", _close_overlay))
	_focus_first(v)


func _open_import_dialog() -> void:
	var v := _make_overlay("IMPORT PACKAGE", 760)
	v.add_child(_label("Packages found in %s and the downloads folder:" % ArenaPackage.packages_dir(), COL_MUTED))
	var found := ArenaPackage.list_local()
	if found.is_empty():
		v.add_child(_label("No .zip packages yet. Put arena packages there and reopen this list.", COL_MUTED))
	for f in found:
		var p := str(f["path"])
		v.add_child(_button("%s  (%d KB)" % [str(f["name"]), int(int(f["size"]) / 1024.0)], func(): _close_overlay(); _import(p)))
	v.add_child(_button("Open packages folder", func(): OS.shell_open("file://" + ArenaPackage.packages_dir())))
	v.add_child(_button("Cancel", _close_overlay))
	_focus_first(v)


func _open_test_dialog() -> void:
	var v := _make_overlay("TEST PLAY", 560)
	var errs: Array = validation.get("errors", [])
	if not errs.is_empty():
		v.add_child(_label("%d validation error(s): the match will run, but fix them before sharing." % errs.size(), COL_WARN))
	v.add_child(_button("1v1 against a bot", _test_play.bind("duel")))
	v.add_child(_button("Free-for-all (you + 3 bots)", _test_play.bind("ffa")))
	v.add_child(_button("2v2 teams (spawn clusters)", _test_play.bind("teams")))
	v.add_child(_button("Watch 4 bots", _test_play.bind("watch")))
	v.add_child(_label("Return to the editor any time with F5 or the View button.", COL_MUTED, 17))
	v.add_child(_button("Cancel", _close_overlay))
	_focus_first(v)


func _open_help() -> void:
	var v := _make_overlay("ARENA EDITOR CONTROLS", 900)
	v.add_child(_label("MOUSE / KEYBOARD", COL_GOLD))
	v.add_child(_label("Left click: place the armed item / select / drag (hold Alt for free placement)\nRight click: cancel · right drag: orbit · middle drag: pan · wheel: zoom\nR / Shift+R rotate 15° · Del delete · Ctrl+D duplicate · arrows nudge\nCtrl+Z undo · Ctrl+Y (or Ctrl+Shift+Z) redo · Ctrl+S save · F5 test play\n[ and ] palette tab · 1–9 palette item · T marker team · G grid snap · Esc cancel/menu", COL_TEXT, 18))
	v.add_child(_label("CONTROLLER", COL_GOLD))
	v.add_child(_label("Left stick: cursor · Right stick: orbit (up/down = tilt) · LT / RT: zoom\nA: place / select (A again on the selection carries it, A drops it)\nB: back / cancel · X: delete · Y: rotate 15° · LB / RB: palette tab\nD-pad: nudge the selection, or browse palette items when nothing is selected\nView: jump to the side panels (B returns) · Menu: editor menu · L3: grid snap · R3: reset camera", COL_TEXT, 18))
	v.add_child(_button("Close", _close_overlay))
	_focus_first(v)


func _dialog(title: String, body: String) -> void:
	var v := _make_overlay(title, 760)
	var l := _label(body, COL_TEXT, 18)
	v.add_child(l)
	v.add_child(_button("OK", _close_overlay))
	_focus_first(v)


func _exit() -> void:
	if stack.is_dirty():
		var v := _make_overlay("UNSAVED CHANGES", 560)
		v.add_child(_label("Leave the editor without saving?", COL_TEXT))
		v.add_child(_button("Save and exit", func(): _save(); _leave()))
		v.add_child(_button("Discard and exit", _leave))
		v.add_child(_button("Keep editing", _close_overlay))
		_focus_first(v)
		return
	_leave()


func _leave() -> void:
	_close_overlay()
	_leaving = true
	_session = {}
	if App.stack.size() > 1:
		App.pop()
	elif App.has_screen("main_menu"):
		App.goto("main_menu")
	elif App.has_screen("title"):
		App.goto("title")
	else:
		get_tree().quit()


# =====================================================================================
# Input
# =====================================================================================

func on_back() -> bool:
	if _overlay:
		_close_overlay()
		return true
	if not _canvas_active():
		vp.grab_focus()
		return true
	if _cancel():
		return true
	_open_menu()
	return true


func _input(ev: InputEvent) -> void:
	if App.top_screen() != self or not is_visible_in_tree():
		return
	if ev is InputEventJoypadButton:
		_on_joy_button(ev as InputEventJoypadButton)
	elif ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		_on_key(ev as InputEventKey)
	elif ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).echo:
		var k := (ev as InputEventKey).keycode
		if k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] and _canvas_active() and _overlay == null and selected >= 0:
			_on_key(ev as InputEventKey)


func _on_joy_button(jb: InputEventJoypadButton) -> void:
	if not jb.pressed:
		return
	var canvas := _canvas_active() and _overlay == null
	if jb.button_index == JOY_BUTTON_START:
		get_viewport().set_input_as_handled()
		if _overlay:
			_close_overlay()
		else:
			_open_menu()
		return
	if jb.button_index == JOY_BUTTON_BACK and _overlay == null:
		get_viewport().set_input_as_handled()
		if canvas:
			_focus_panels()
		else:
			vp.grab_focus()
		return
	if not canvas:
		if jb.button_index == JOY_BUTTON_B and _overlay == null:
			get_viewport().set_input_as_handled()
			vp.grab_focus()
		return
	get_viewport().set_input_as_handled()
	match jb.button_index:
		JOY_BUTTON_A:
			_primary_at_cursor()
		JOY_BUTTON_B:
			if not _cancel():
				_open_menu()
		JOY_BUTTON_X:
			_delete()
		JOY_BUTTON_Y:
			_rotate(1)
		JOY_BUTTON_LEFT_SHOULDER:
			_set_tab(tab - 1)
		JOY_BUTTON_RIGHT_SHOULDER:
			_set_tab(tab + 1)
		JOY_BUTTON_DPAD_UP:
			_dpad(Vector2(0, 1))
		JOY_BUTTON_DPAD_DOWN:
			_dpad(Vector2(0, -1))
		JOY_BUTTON_DPAD_LEFT:
			_dpad(Vector2(-1, 0))
		JOY_BUTTON_DPAD_RIGHT:
			_dpad(Vector2(1, 0))
		JOY_BUTTON_LEFT_STICK:
			_toggle_snap()
		JOY_BUTTON_RIGHT_STICK:
			vp.reset_camera()


func _dpad(d: Vector2) -> void:
	if selected >= 0:
		_nudge(d)
	elif d.y != 0.0:
		_palette_step(-int(d.y))
	else:
		_rotate(int(d.x))


## Controller A / Enter at the cursor: place, pick up / drop (carry), or select.
func _primary_at_cursor() -> void:
	if armed != "":
		_place_at(cursor, false)
		return
	if carrying:
		_end_drag()
		carrying = false
		_status_msg("Dropped.")
		return
	var hit := _pick(cursor)
	if hit.is_empty():
		_select(-1)
		return
	if int(hit["uid"]) == selected:
		carrying = true
		_begin_drag(selected, cursor, str(hit["end"]))
		_status_msg("Carrying — move with the stick, A to drop, B to cancel.")
		return
	_select(int(hit["uid"]))


func _focus_panels() -> void:
	for c in _inspector.find_children("*", "Control", true, false) + _layout_box.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.focus_mode != Control.FOCUS_NONE and ctl.is_visible_in_tree():
			ctl.grab_focus()
			return
	_palette.grab_focus()


func _on_key(k: InputEventKey) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is SpinBox or (focus and focus.get_parent() is SpinBox):
		return
	if _overlay:
		return
	var ctrl := k.ctrl_pressed or k.meta_pressed
	var handled := true
	match k.keycode:
		KEY_Z:
			if ctrl:
				if k.shift_pressed:
					_redo()
				else:
					_undo()
			else:
				handled = false
		KEY_Y:
			if ctrl:
				_redo()
			else:
				handled = false
		KEY_S:
			if ctrl:
				_save()
			else:
				handled = false
		KEY_D:
			if ctrl:
				_duplicate()
			else:
				handled = false
		KEY_DELETE, KEY_BACKSPACE:
			_delete()
		KEY_R:
			_rotate(-1 if k.shift_pressed else 1)
		KEY_T:
			_cycle_team()
		KEY_G:
			_toggle_snap()
		KEY_H, KEY_F1:
			_open_help()
		KEY_F5:
			_open_test_dialog()
		KEY_BRACKETLEFT:
			_set_tab(tab - 1)
		KEY_BRACKETRIGHT:
			_set_tab(tab + 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _canvas_active():
				_primary_at_cursor()
			else:
				handled = false
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if _canvas_active():
				var d := {KEY_LEFT: Vector2(-1, 0), KEY_RIGHT: Vector2(1, 0), KEY_UP: Vector2(0, 1), KEY_DOWN: Vector2(0, -1)}[k.keycode] as Vector2
				if selected >= 0:
					_nudge(d)
				else:
					vp.pan(Vector2(-d.x, d.y) * 60.0)
			else:
				handled = false
		_:
			if k.keycode >= KEY_1 and k.keycode <= KEY_9:
				var idx := int(k.keycode - KEY_1)
				if idx < _palette.item_count:
					_palette.select(idx)
					_on_palette_selected(idx)
			else:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


# =====================================================================================
# Evidence / automation hook (src/test/arena/arena_shots.gd --editor)
# =====================================================================================

## Sets up a representative editing state for screenshots: a few placed items, a selection, an
## armed tool with its ghost, and validation issues on screen.
func debug_setup(_script := "") -> void:
	vp.yaw = deg_to_rad(32.0)
	vp.pitch = deg_to_rad(50.0)
	vp.dist = 15.5
	vp.set_focus(Vector3(0.3, 0, 0.6), true)
	var crate := model.make_item("prop_heavy_crate", Vector3(-2.0, 0, 1.5), deg_to_rad(15.0))
	var barrel := model.make_item("prop_fire_barrel", Vector3(2.5, 0, 2.5))
	var vent := model.make_item("prop_steam_vent", Vector3(0.5, 0, -1.5), PI)
	stack.execute(ArenaEditCommands.AddItems.new([crate, barrel, vent], "Place"))
	_select(int(crate["uid"]))
	tab = 2
	_refresh_palette()
	for i in _palette.item_count:
		if str(_palette.get_item_metadata(i)) == "prop_bumper":
			_palette.select(i)
	armed = "prop_bumper"
	_update_palette_desc()
	cursor = Vector3(1.6, 0, 0.4)
	vp.set_cursor(cursor, true)
	_status_msg("Placed Steam vent.")
