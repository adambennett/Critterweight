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
## Each slot is a row that cycles through the moves (left/right); the help panel describes the
## focused move. The loadout must hold a basic strike and no move twice.

const SLOT_INPUTS := ["light", "heavy", "ability1", "ability2"]

var _c: CreatureDef
var _ids: Array = []              ## equippable pool ids, in pool order
var _slots: Array = []            ## chosen ids per slot ("" = empty)
var _styles := {}
var _on_done := Callable()
var _scroll: FocusScroll
var _help: HelpPanel
var _error: Label
var _rows: Array = []


func on_enter(p: Dictionary) -> void:
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
	c.add_child(UiTheme.label("EQUIPPED", "Eyebrow"))
	var names2: Array[String] = []
	var values: Array = []
	for id in _ids:
		values.append(id)
		names2.append(_move_label(id))
	for i in 4:
		var row := OptionRow.new("Move %d  (%s)" % [i + 1, Controls.prompt_for(str(SLOT_INPUTS[i]))])
		row.setup(values, names2, _slots[i] if _slots[i] != "" else values[0])
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
	done.set_help("Done", "Fight with these four moves.")
	done.pressed.connect(_confirm)
	c.add_child(done)
	_validate()
	_scroll.wrap_focus.call_deferred()
	play_intro()


func default_focus() -> Control:
	return _rows[0] if not _rows.is_empty() else null


func _move_label(id: String) -> String:
	var pm: PoolMove = _c.pool.get(id)
	if pm == null:
		return id
	var tag := "basic" if pm.role == "basic" else pm.category
	var style := str(_styles.get(id, ""))
	if style != "" and pm.styles.has(style):
		return "%s · %s (%s)" % [pm.display_name, str((pm.styles[style] as Dictionary).get("name", style)), tag]
	return "%s (%s)" % [pm.display_name, tag]


## The help text for a move: what it does, how to use it, what it costs.
static func describe(pm: PoolMove) -> String:
	var lines := PackedStringArray()
	lines.append(pm.desc if pm.desc != "" else pm.short)
	var how := "Tap"
	match pm.hold:
		"charge":
			how = "Hold to charge, release to fire"
		"sustain":
			how = "Hold to keep it going (up to %.1f s)%s" % [pm.max_hold, ", aim with the stick" if pm.aim_turn > 0.0 else ""]
	if pm.role == "basic":
		how = "Press again to continue the string; the last press is the finisher; out of a dodge it is a dash strike"
	lines.append(how + ".")
	var facts := PackedStringArray()
	facts.append(pm.category.capitalize())
	if pm.element != "":
		facts.append(pm.element.capitalize())
	if pm.cooldown > 0.0:
		facts.append("cooldown %.0f s" % pm.cooldown)
	if pm.charges > 1:
		facts.append("%d charges" % pm.charges)
	if pm.stamina_cost() > 0.0:
		facts.append("%d stamina" % roundi(pm.stamina_cost()))
	if pm.drain > 0.0:
		facts.append("+%d stamina/s held" % roundi(pm.drain))
	lines.append(" · ".join(facts))
	return "\n".join(lines)


func _describe_row(row: OptionRow, id: String) -> void:
	var pm: PoolMove = _c.pool.get(id)
	if pm:
		row.set_help(pm.display_name, describe(pm))


func _on_slot_changed(v, i: int, row: OptionRow) -> void:
	_slots[i] = str(v)
	_describe_row(row, str(v))
	_help.show_help(row.help_title, row.help_text)
	_validate()


func _apply_preset(key: String) -> void:
	var lo: Array = (_c.loadouts[key] as Dictionary)["moves"]
	for i in 4:
		_slots[i] = str(lo[i]) if i < lo.size() else ""
		if i < _rows.size() and _slots[i] != "":
			(_rows[i] as OptionRow).set_value(_slots[i])
			_describe_row(_rows[i], _slots[i])
	_validate()
	Audio.sfx("ui_confirm")


func _chosen() -> Array:
	return _slots.filter(func(x) -> bool: return str(x) != "")


func _validate() -> bool:
	var problem := _c.loadout_problem(_chosen())
	_error.text = "" if problem == "" else problem.capitalize() + "."
	_error.visible = problem != ""
	return problem == ""


func _confirm() -> void:
	if not _validate():
		Audio.sfx("ui_error")
		return
	if _on_done.is_valid():
		_on_done.call(_chosen())
	App.pop()
