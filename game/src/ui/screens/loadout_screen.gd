extends Screen
## Movesets loadout ("loadout", v0.9.18, docs/design/MOVESET_COMBAT.md §5): choose the four moves a
## fighter brings. Pushed by fighter setup (versus, practice, spectate), the Career and run prep
## screens. Params:
##   creature   creature id
##   loadout    current pool ids (empty: the creature's default)
##   allowed    pool ids that may be equipped (campaign: the learned moves); empty = the whole pool
##   styles     {move id: style id} drilled styles to show (campaign); optional
##   title      screen title ("Fighter 1 moves")
##   on_done    Callable(Array) called with the chosen loadout when the player confirms
##   in_game    opened over a running match (practice's Change moves): the match stays the 3D
##              scene under a dimmer (also detected from MatchFlow.match_running())
## Each slot is a row that cycles through the moves (left/right), "Empty" included; the help panel
## describes the focused move (MovesUi.describe). The loadout must hold a basic strike and no move
## twice.

const SLOT_INPUTS := MovesUi.SLOT_ACTIONS
const EMPTY := ""

var _c: CreatureDef
var _ids: Array = []              ## equippable pool ids, in pool order
var _slots: Array = []            ## chosen ids per slot ("" = empty)
var _styles := {}
var _on_done := Callable()
var _scroll: FocusScroll
var _help: HelpPanel
var _error: Label
var _rows: Array = []
var _in_game := false


func on_enter(p: Dictionary) -> void:
	_in_game = bool(p.get("in_game", false)) or MatchFlow.match_running()
	if _in_game:
		# over a running match: never swap the match out for the menu backdrop
		add_dimmer(0.93)
	else:
		MenuBackdrop.ensure()
		add_backdrop_gradient(0.97, 0.7)
	_c = Content.creature(str(p.get("creature", "")))
	_on_done = p.get("on_done", Callable())
	_styles = p.get("styles", {}) if typeof(p.get("styles", {})) == TYPE_DICTIONARY else {}
	var f := build_frame(str(p.get("title", "Moves")), _c.display_name.to_upper() if _c else "MOVES")
	(f["prompts"] as PromptBar).set_prompts(std_prompts())
	if _c == null:
		return
	var allowed: Array = p.get("allowed", [])
	for id in _c.pool:
		if allowed.is_empty() or allowed.has(id):
			_ids.append(str(id))
	var want: Array = p.get("loadout", [])
	_slots = _c.resolve_loadout(want)
	while _slots.size() < 4:
		_slots.append("")
	var body: VBoxContainer = f["body"]
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var lp := UiTheme.panel("PanelSolid", 18.0)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.size_flags_stretch_ratio = 1.3
	cols.add_child(lp)
	_scroll = FocusScroll.new(8)
	lp.add_child(_scroll)
	var right := UiTheme.vbox(UiTheme.GAP_M)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_help = HelpPanel.new(_scroll, "Move")
	right.add_child(_help)
	var c := _scroll.content
	if not _c.loadouts.is_empty() and allowed.is_empty():
		c.add_child(UiTheme.label("RECOMMENDED", "Eyebrow"))
		for lk in _c.loadouts:
			var lo: Dictionary = _c.loadouts[lk]
			var names := PackedStringArray()
			for mid in lo["moves"]:
				names.append(str((_c.pool[str(mid)] as PoolMove).display_name) if _c.pool.has(str(mid)) else str(mid))
			var b := UiButton.new(str(lo.get("name", lk)), "SubItem")
			b.route = "preset_" + str(lk)
			b.set_help(str(lo.get("name", lk)), ", ".join(names))
			b.pressed.connect(_apply_preset.bind(str(lk)))
			c.add_child(b)
		c.add_child(UiTheme.spacer(false, 6))
	c.add_child(UiTheme.label("EQUIPPED TECHNIQUES" if _c.tags.has("martial") else "EQUIPPED", "Eyebrow"))
	if _c.tags.has("martial"):
		c.add_child(UiTheme.label("Techniques change your limb and modifier strikes. Their position here does not change the controls.", "Caption", true))
	var names2: Array[String] = []
	var values: Array = []
	for id in _ids:
		values.append(id)
		names2.append(_move_label(id))
	values.append(EMPTY)
	names2.append("Empty")
	for i in 4:
		if not values.has(_slots[i]):
			_slots[i] = EMPTY          # not equippable here (a campaign's unlearned move)
		var row := OptionRow.new(_row_label(i))
		row.setup(values, names2, _slots[i])
		row.set_meta("focus_key", "slot%d" % i)
		_describe_row(row, str(_slots[i]))
		row.value_changed.connect(_on_slot_changed.bind(i, row))
		c.add_child(row)
		_rows.append(row)
	_error = UiTheme.label("", "Danger", true)
	_error.visible = false
	c.add_child(_error)
	c.add_child(UiTheme.spacer(false, 6))
	var done := UiButton.new("Done", "PrimaryButton", "check")
	done.route = "done"
	done.set_help("Done", "Fight with these techniques." if _c.tags.has("martial") else "Fight with these moves.")
	done.pressed.connect(_confirm)
	c.add_child(done)
	_validate()
	_scroll.wrap_focus.call_deferred()
	Controls.device_changed.connect(_on_device_changed)
	Controls.bindings_changed.connect(_relabel_rows)
	play_intro()


func _on_device_changed(_kind: String) -> void:
	_relabel_rows()


## "Move 2  (K)": each row names its input with the current binding on the current device.
func _relabel_rows() -> void:
	for i in _rows.size():
		(_rows[i] as UiRow).set_label(_row_label(i))


func _row_label(i: int) -> String:
	if _c != null and _c.tags.has("martial"):
		return "Technique %d" % (i + 1)
	return "Move %d  (%s)" % [i + 1, Controls.prompt_for(str(SLOT_INPUTS[i]))]


func default_focus() -> Control:
	return _rows[0] if not _rows.is_empty() else null


func _move_label(id: String) -> String:
	var pm: PoolMove = _c.pool.get(id)
	if pm == null:
		return id
	var tags := PackedStringArray(["basic" if pm.role == "basic" else MovesUi.category_name(pm.category).to_lower()])
	if MovesUi.hold_tag(pm) != "":
		tags.append(MovesUi.hold_tag(pm).to_lower())
	var style := str(_styles.get(id, ""))
	if style != "" and pm.styles.has(style):
		return "%s · %s (%s)" % [pm.display_name, str((pm.styles[style] as Dictionary).get("name", style)), ", ".join(tags)]
	return "%s (%s)" % [pm.display_name, ", ".join(tags)]


## The help text for a move: what it does, how to use it, what it costs (MovesUi.describe).
static func describe(pm: PoolMove, c: CreatureDef = null) -> String:
	return MovesUi.describe(pm, c)


func _describe_row(row: OptionRow, id: String) -> void:
	var pm: PoolMove = _c.pool.get(id)
	if pm:
		row.set_help(pm.display_name, describe(pm, _c))
	else:
		row.set_help("Empty", "Nothing on this input. A loadout needs a basic strike and up to four moves.")


## Slot `i` (0..3) set to pool move `id` ("" = empty), as if picked on its row.
func set_slot(i: int, id: String) -> void:
	if i < 0 or i >= _rows.size():
		return
	(_rows[i] as OptionRow).set_value(id)
	_on_slot_changed(id, i, _rows[i])


func _on_slot_changed(v, i: int, row: OptionRow) -> void:
	_slots[i] = str(v)
	_describe_row(row, str(v))
	_help.show_help(row.help_title, row.help_text)
	_validate()


func _apply_preset(key: String) -> void:
	var lo: Array = (_c.loadouts[key] as Dictionary)["moves"]
	for i in 4:
		_slots[i] = str(lo[i]) if i < lo.size() else EMPTY
		if i < _rows.size():
			(_rows[i] as OptionRow).set_value(_slots[i])
			_describe_row(_rows[i], _slots[i])
	var focused := get_viewport().gui_get_focus_owner()
	if focused is OptionRow and _rows.has(focused):
		var row := focused as OptionRow
		_help.show_help(row.help_title, row.help_text)
	_validate()
	Audio.sfx("ui_accept")


## The loadout the rows currently describe (empty slots dropped).
func chosen() -> Array:
	return _chosen()


## Confirms the current rows (the Done button; tests and practice drive it too).
func confirm() -> void:
	_confirm()


func _chosen() -> Array:
	return _slots.filter(func(x) -> bool: return str(x) != "")


func _validate() -> bool:
	var problem := _c.loadout_problem(_chosen())
	_error.text = problem_text(_c, problem)
	_error.visible = problem != ""
	return problem == ""


## CreatureDef.loadout_problem() for the player: move names instead of pool ids, a sentence.
static func problem_text(c: CreatureDef, problem: String) -> String:
	if problem == "":
		return ""
	var t := problem
	for id in c.pool:
		t = t.replace("'%s'" % str(id), (c.pool[id] as PoolMove).display_name)
	return t.substr(0, 1).to_upper() + t.substr(1) + "."


## The validation message shown under the rows ("" when the loadout is valid).
func problem_shown() -> String:
	return _error.text if _error.visible else ""


func _confirm() -> void:
	if not _validate():
		Audio.sfx("ui_error")
		return
	if _on_done.is_valid():
		_on_done.call(_chosen())
	App.pop()
