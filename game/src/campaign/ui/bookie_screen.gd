extends Screen
## The Bookie's Table: Teddy Two-Tooth's autobattler.
##   Setup  — fighter (or random), variant, difficulty, Teddy's dice (the bots' skill), who
##            decides (Teddy = unattended, or you), watch fights or fast-forward, keep dealing.
##   Live   — the run's status and a running log, with PAUSE/RESUME, SPEED 1x-4x, TAKE OVER /
##            HAND BACK, WATCH/FAST-FORWARD and STOP. While you have taken over, decisions open
##            the normal campaign screens (BookieFlow) and come back here for each fight.
##   Overlay (params.overlay) — a slim control bar over a presented fight.
## The BookieTable node lives under App (not under this screen) so it survives screen changes.

const TABLE_NAME := "BookieTable"
const SPEEDS := [1.0, 2.0, 3.0, 4.0]

var overlay := false
var table: BookieTable
var bflow: BookieFlow
var catalog: CampaignCatalog
var stand_ins := false
var fighter := ""
var variant := "off_the_street"
var difficulty := "amateur"
var tier := "contender"
var attended := false
var watch := true
var keep_going := true
var _focusables: Array = []
var _live_box: Control
var _msg: Label
var _dirty := false


static func get_table() -> BookieTable:
	return App.get_node_or_null(TABLE_NAME) as BookieTable


func on_enter(p: Dictionary) -> void:
	overlay = bool(p.get("overlay", false))
	table = get_table()
	if table:
		bflow = table.get_meta("bookie_flow") if table.has_meta("bookie_flow") else null
		catalog = table.catalog
		_connect_table()
	else:
		stand_ins = bool(p.get("stand_ins", false)) or OS.get_cmdline_user_args().has("--campaign-stand-ins")
		catalog = CampaignFlow.make_catalog(stand_ins)
		var fs := catalog.available_fighters()
		fighter = "" if fs.is_empty() else "random"
		var d = Settings.get_value("gameplay.difficulty")
		difficulty = str(d) if d != null and catalog.difficulties.has(str(d)) else "amateur"
	_build()


func _connect_table() -> void:
	table.changed.connect(_on_table_event)
	table.run_over.connect(_on_table_event_run)
	table.stopped.connect(_on_table_stopped)


func _disconnect_table(t: BookieTable) -> void:
	if t == null or not is_instance_valid(t):
		return
	if t.changed.is_connected(_on_table_event):
		t.changed.disconnect(_on_table_event)
	if t.run_over.is_connected(_on_table_event_run):
		t.run_over.disconnect(_on_table_event_run)
	if t.stopped.is_connected(_on_table_stopped):
		t.stopped.disconnect(_on_table_stopped)


func on_exit() -> void:
	_disconnect_table(table)


func _on_table_stopped() -> void:
	_dirty = true


func _on_table_event(_what: String) -> void:
	_dirty = true


func _on_table_event_run(_s: Dictionary) -> void:
	_dirty = true


func _process(_dt: float) -> void:
	if _dirty and is_inside_tree():
		_dirty = false
		_refresh()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_focusables.clear()
	if overlay:
		_build_overlay()
	elif table == null:
		_build_setup()
	else:
		_build_live()


func _refresh() -> void:
	var f: Control = get_viewport().gui_get_focus_owner() if get_viewport() else null
	var focus_text := (f as Button).text if f is Button else ""
	_build()
	if focus_text != "":
		for c in _focusables:
			if c is Button and (c as Button).text == focus_text and not (c as Button).disabled:
				(c as Button).call_deferred("grab_focus")
				return


# ---------------------------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------------------------

func _build_setup() -> void:
	var v := CampaignUI.scaffold(self, "THE BOOKIE'S TABLE", "Teddy Two-Tooth deals a fight card and rolls the dice. The AI fights every bout; you can watch, bet on your build, or take over the decisions.")
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	v.add_child(CampaignUI.scroll(rows))
	var fs := [["Random", "random"]]
	for fid in catalog.available_fighters():
		fs.append([CampaignUI.fighter_name(catalog, str(fid)), str(fid)])
	if fs.size() == 1:
		rows.add_child(CampaignUI.label("No roster fighters are installed yet. Enable development stand-ins to deal a card (runs are marked custom).", 20, CampaignUI.DANGER))
		var en := CampaignUI.button("ENABLE DEV STAND-INS", _enable_stand_ins, 22)
		rows.add_child(en)
		_focusables.append(en)
	else:
		_row(rows, "FIGHTER", fs, fighter, _set_fighter)
	_row(rows, "CARD", [["Off the Street", "off_the_street"], ["Fight Camp (Clout to the Cannery)", "fight_camp"]], variant, _set_variant)
	var ds := []
	for did in catalog.difficulty_ids():
		ds.append([str(catalog.difficulties[did].get("name", did)), str(did)])
	_row(rows, "DIFFICULTY", ds, difficulty, _set_difficulty)
	var ts := []
	var tids := catalog.bot_tiers.keys()
	tids.sort_custom(func(a, b): return int(catalog.bot_tiers[a].get("order", 0)) < int(catalog.bot_tiers[b].get("order", 0)))
	for tid in tids:
		ts.append([str(catalog.bot_tiers[tid].get("name", tid)), str(tid)])
	_row(rows, "TEDDY'S DICE (how well the AI fights for you)", ts, tier, _set_tier)
	_row(rows, "DECISIONS", [["Teddy decides (unattended)", "teddy"], ["I decide", "me"]], "me" if attended else "teddy", _set_decisions)
	_row(rows, "FIGHTS", [["Watch them", "watch"], ["Fast-forward", "ff"]], "watch" if watch else "ff", _set_watch)
	_row(rows, "WHEN A RUN ENDS", [["Deal another card", "yes"], ["Stop", "no"]], "yes" if keep_going else "no", _set_keep)
	rows.add_child(CampaignUI.label("The table keeps its own record board. Clout is paid at 50% and The Dosage never unlocks here.", 18, CampaignUI.MUTED))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var start := CampaignUI.button("DEAL THE CARD", _start_table, 30)
	start.disabled = fs.size() == 1
	hb.add_child(start)
	var back := CampaignUI.button("BACK", _leave, 24, CampaignUI.MUTED)
	hb.add_child(back)
	v.add_child(hb)
	_focusables.append(start)
	_focusables.append(back)
	_msg = CampaignUI.label("", 20, CampaignUI.DANGER)
	v.add_child(_msg)
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


func _row(parent: Control, title: String, opts: Array, current: String, on_pick: Callable) -> void:
	parent.add_child(CampaignUI.label(title, 22, CampaignUI.INK, "900"))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 8)
	fl.add_theme_constant_override("v_separation", 8)
	for o in opts:
		var id := str(o[1])
		var b := CampaignUI.button(("> %s" % o[0]) if id == current else str(o[0]), on_pick.bind(id), 22, CampaignUI.GOOD if id == current else CampaignUI.ACCENT)
		fl.add_child(b)
		_focusables.append(b)
	parent.add_child(fl)


func _set_fighter(id: String) -> void:
	fighter = id
	_refresh()


func _set_variant(id: String) -> void:
	variant = id
	_refresh()


func _set_difficulty(id: String) -> void:
	difficulty = id
	_refresh()


func _set_tier(id: String) -> void:
	tier = id
	_refresh()


func _set_decisions(id: String) -> void:
	attended = id == "me"
	_refresh()


func _set_watch(id: String) -> void:
	watch = id == "watch"
	_refresh()


func _set_keep(id: String) -> void:
	keep_going = id == "yes"
	_refresh()


func _enable_stand_ins() -> void:
	App.goto("bookie", {"stand_ins": true})


func _start_table() -> void:
	var fs := catalog.available_fighters()
	if fs.is_empty():
		return
	var fid := fighter
	if fid == "random" or fid == "":
		fid = str(fs[randi() % fs.size()])
	var t := BookieTable.new()
	t.name = TABLE_NAME
	App.add_child(t)
	var cfg := FightCamp.run_config(Profiles.current, {"variant": variant, "fighter": fid, "difficulty": difficulty, "dose": 0, "seed": 0,
		"mode": "bookie", "custom_reasons": CampaignFlow.custom_reasons(stand_ins)})
	cfg["content_hash"] = Content.content_hash()
	t.setup(catalog, cfg, Profiles.current)
	t.fighter_tier = tier
	t.unattended = not attended
	t.keep_going = keep_going
	t.think_delay = 0.8
	t.speed = 1.0
	var f := BookieFlow.for_table(t)
	f.watching = watch
	f.note("Teddy deals a card: %s, %s." % [CampaignUI.fighter_name(catalog, fid), str(catalog.difficulty(difficulty).get("name", difficulty))])
	table = t
	bflow = f
	_connect_table()
	t.play()     # coroutine: sets `running` before its first await, so build the live view after
	_build()


# ---------------------------------------------------------------------------------------------
# Live view
# ---------------------------------------------------------------------------------------------

func _build_live() -> void:
	var ctrl := table.ctrl
	var who := "you decide" if not table.unattended else "Teddy decides"
	var v := CampaignUI.scaffold(self, "THE BOOKIE'S TABLE", "Run %d · %s · Teddy's dice: %s · %s" % [table.runs_completed + 1, who,
		str(catalog.bot_tiers.get(table.fighter_tier, {}).get("name", table.fighter_tier)), "watching fights" if (bflow and bflow.watching) else "fast-forward"])
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	cols.add_child(_status_panel(ctrl))
	cols.add_child(_log_panel())
	v.add_child(_controls())
	_msg = CampaignUI.label(_state_line(), 22, CampaignUI.ACCENT, "700")
	v.add_child(_msg)
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


func _state_line() -> String:
	if not table.running:
		if table.ctrl.is_over():
			return "The card is over. Deal another, or leave the table."
		return "The table is stopped."
	if table.paused:
		return "PAUSED"
	if table.in_fight:
		return "Fight in progress: %s%s" % [str(table.current_fight.get("name", "")), "" if (bflow and bflow.watching) else " (fast-forward)"]
	if table.waiting_for_player:
		return "Your call."
	return "Teddy is thinking..."


func _status_panel(ctrl: RunController) -> Control:
	var pnl := CampaignUI.panel()
	pnl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pnl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	pnl.add_child(box)
	var p := ctrl.player("p0")
	box.add_child(CampaignUI.label(CampaignUI.fighter_name(catalog, str(p.get("fighter", ""))), 34, CampaignUI.ACCENT, "900"))
	var act := int(ctrl.state.get("act", 1))
	var act_name := str(catalog.acts.get(act, {}).get("name", ""))
	box.add_child(CampaignUI.label("Act %d — %s · seed %s" % [act, act_name, str(ctrl.state.get("seed_text", ""))], 22))
	var mh := ctrl.max_hp(p)
	box.add_child(CampaignUI.label("HP %d / %d · Scrip %d · Hype carry %d" % [int(ceil(float(p.get("hp", 0)))), int(mh), int(p.get("scrip", 0)), int(p.get("hype_carry", 0))], 22))
	var bar := ProgressBar.new()
	bar.max_value = mh
	bar.value = float(p.get("hp", 0))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	box.add_child(bar)
	var path: Array = ctrl.state.get("path", [])
	var route := []
	for id in path:
		if int(RunState.node(ctrl.state, str(id)).get("act", 0)) == act:
			route.append(str(CampaignUI.NODE_NAMES.get(ctrl.visible_type(str(id)), "?")))
	box.add_child(CampaignUI.label("Route this act: " + (" > ".join(route) if not route.is_empty() else "(start)"), 18, CampaignUI.MUTED))
	box.add_child(CampaignUI.label("BUILD", 22, CampaignUI.INK, "900"))
	for t in p.get("techniques", []):
		box.add_child(CampaignUI.label("Technique: %s" % catalog.item_name(str(t)), 18, CampaignUI.GOOD))
	for s in p.get("supplements", []):
		var d: Dictionary = catalog.supplements.get(str(s["id"]), {})
		var stacks := int(s.get("stacks", 1))
		box.add_child(CampaignUI.label("%s%s — %s" % [d.get("name", s["id"]), (" x%d" % stacks) if stacks > 1 else "", d.get("effect", "")], 17,
			CampaignUI.RARITY_COLORS.get(str(d.get("rarity", "otc")), CampaignUI.INK)))
	for se in p.get("side_effects", []):
		box.add_child(CampaignUI.label("Side effect: %s" % catalog.item_name(str(se)), 17, CampaignUI.DANGER))
	return pnl


func _log_panel() -> Control:
	var pnl := CampaignUI.panel()
	pnl.custom_minimum_size = Vector2(620, 0)
	pnl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(CampaignUI.label("AT THE TABLE", 24, CampaignUI.ACCENT, "900"))
	var lines: Array = bflow.log_lines if bflow else []
	for i in mini(lines.size(), 22):
		box.add_child(CampaignUI.label(str(lines[i]), 18, CampaignUI.INK if i == 0 else CampaignUI.MUTED))
	if not table.results.is_empty():
		var wins := 0
		for r in table.results:
			if bool(r.get("victory", false)):
				wins += 1
		box.add_child(CampaignUI.label("Cards finished: %d · titles won: %d" % [table.results.size(), wins], 20, CampaignUI.GOOD, "700"))
	pnl.add_child(CampaignUI.scroll(box))
	return pnl


func _controls() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	if table.running:
		var pz := CampaignUI.button("RESUME" if table.paused else "PAUSE", _toggle_pause, 24)
		row.add_child(pz)
		_focusables.append(pz)
		for k in SPEEDS:
			var sb := CampaignUI.button(("> %dx" if is_equal_approx(table.speed, k) else "%dx") % int(k), _set_speed.bind(k), 22,
				CampaignUI.GOOD if is_equal_approx(table.speed, k) else CampaignUI.ACCENT)
			row.add_child(sb)
			_focusables.append(sb)
		var tk := CampaignUI.button("HAND BACK TO TEDDY" if not table.unattended else "TAKE OVER", _toggle_take_over, 24)
		row.add_child(tk)
		_focusables.append(tk)
		if table.waiting_for_player and bflow:
			var go := CampaignUI.button("MAKE YOUR CALL", _open_decision, 24, CampaignUI.GOOD)
			row.add_child(go)
			_focusables.append(go)
		var wt := CampaignUI.button("FAST-FORWARD FIGHTS" if (bflow and bflow.watching) else "WATCH FIGHTS", _toggle_watch, 22)
		row.add_child(wt)
		_focusables.append(wt)
		var st := CampaignUI.button("STOP THE TABLE", _confirm_stop, 22, CampaignUI.DANGER)
		row.add_child(st)
		_focusables.append(st)
	else:
		var deal := CampaignUI.button("DEAL ANOTHER CARD", _deal_again, 26)
		row.add_child(deal)
		_focusables.append(deal)
		var lv := CampaignUI.button("LEAVE THE TABLE", _leave, 24, CampaignUI.MUTED)
		row.add_child(lv)
		_focusables.append(lv)
	return row


func _toggle_pause() -> void:
	if table.paused:
		table.resume()
	else:
		table.pause()
	_refresh()


func _set_speed(k: float) -> void:
	table.set_speed(k)
	table.think_delay = 0.8 / k
	_refresh()


func _toggle_take_over() -> void:
	if table.unattended:
		table.take_over()
	else:
		table.hand_back()
	_refresh()


func _toggle_watch() -> void:
	if bflow:
		bflow.watching = not bflow.watching
	_refresh()


func _open_decision() -> void:
	if bflow:
		bflow.show_current()


func _confirm_stop() -> void:
	CampaignUI.confirm(self, "Stop the table?", "The card in progress ends here without credit.",
		[{"label": "STOP", "id": "yes", "danger": true}, {"label": "KEEP PLAYING", "id": "no"}], _on_stop)


func _on_stop(id: String) -> void:
	if id != "yes":
		_refresh()
		return
	table.stop()
	if bflow:
		bflow.abort_fight()
	_refresh()


func _deal_again() -> void:
	table.deal(0)
	if bflow:
		bflow.ctrl = table.ctrl
		bflow.note("Teddy deals a new card.")
	table.play()
	_build()


func _leave() -> void:
	if table and is_instance_valid(table):
		var t := table
		_disconnect_table(t)
		t.name = "%s_closing" % TABLE_NAME
		if t.running:
			# a fast-forwarded fight may still be stepping inside the table: free it afterwards
			t.stopped.connect(t.queue_free)
			t.stop()
		else:
			t.queue_free()
		table = null
	SimSpeed.restore()
	App.goto("campaign_menu")


# ---------------------------------------------------------------------------------------------
# Overlay over a presented fight
# ---------------------------------------------------------------------------------------------

func _build_overlay() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var anchor := MarginContainer.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.offset_top = -86
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	var bar := CampaignUI.panel(Color(CampaignUI.BG, 0.88))
	anchor.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var name_s := str(table.current_fight.get("name", "")) if table else ""
	var title_l := CampaignUI.label("THE BOOKIE'S TABLE · %s%s" % [name_s, " · PAUSED" if table and table.paused else ""], 22, CampaignUI.ACCENT, "900")
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(title_l)
	if table == null:
		return
	var pz := CampaignUI.button("RESUME" if table.paused else "PAUSE", _toggle_pause, 20)
	row.add_child(pz)
	_focusables.append(pz)
	for k in SPEEDS:
		var sb := CampaignUI.button(("> %dx" if is_equal_approx(table.speed, k) else "%dx") % int(k), _set_speed.bind(k), 20,
			CampaignUI.GOOD if is_equal_approx(table.speed, k) else CampaignUI.ACCENT)
		row.add_child(sb)
		_focusables.append(sb)
	var tk := CampaignUI.button("HAND BACK" if not table.unattended else "TAKE OVER", _toggle_take_over, 20)
	tk.tooltip_text = "Take over the decisions from the next decision point (the AI keeps fighting)."
	row.add_child(tk)
	_focusables.append(tk)
	var st := CampaignUI.button("STOP", _confirm_stop, 20, CampaignUI.DANGER)
	row.add_child(st)
	_focusables.append(st)


func on_back() -> bool:
	if CampaignUI.close_modal(self):
		return true
	if overlay:
		_toggle_pause()
		return true
	if table and table.running:
		_confirm_stop()
		return true
	_leave()
	return true


func default_focus() -> Control:
	return CampaignUI.first_enabled(_focusables)
