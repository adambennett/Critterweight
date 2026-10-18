extends Screen
## Campaign menu ("The Fight Card"): variant (Off the Street / Fight Camp), fighter, difficulty,
## Dose, co-op format, seed, suspended runs (resume / abandon), The Bookie's Table and the Cannery
## Ledger. Built from the shared menu kit (frame, option rows, help panel, prompt bar) like the
## versus setup, so it reads as part of the same game; fully operable with a controller and with
## mouse/keyboard.
## One suspended run per variant: START RUN over an occupied slot asks first (abandon it and
## start, resume it, or cancel); abandoning credits it as a defeat. Party runs are listed but
## resume only through the co-op host path (CoopSession.host_resume), never as a solo run.

const PARTY_RESUME_TEXT := "A co-op party's run: its host resumes it from the co-op lobby so the party can rejoin (it never continues as a solo run)."

var catalog: CampaignCatalog
var stand_ins := false
## Opened from the Cannery's sign-up sheet (params.from_hub): Back walks back to Snappington's desk.
var return_to_hub := false
var variant := "off_the_street"
var fighter := ""
var difficulty := "amateur"
var dose := 0
var coop_format := "simultaneous"
var seed_text := ""                ## typed seed (or any words); empty = a random card
var _scroll: FocusScroll
var _help: HelpPanel
var _status: Label
var _start: Button
var _runs_box: VBoxContainer
var _right_buttons: Array[Control] = []


func on_enter(p: Dictionary) -> void:
	return_to_hub = bool(p.get("from_hub", false))
	stand_ins = bool(p.get("stand_ins", false)) or OS.get_cmdline_user_args().has("--campaign-stand-ins")
	catalog = CampaignFlow.make_catalog(stand_ins)
	if CampaignCatalog.VARIANTS.has(str(p.get("variant", ""))):
		variant = str(p["variant"])     # the main menu opens the menu for one variant
	var d = Settings.get_value("gameplay.difficulty")
	difficulty = str(d) if d != null and catalog.difficulties.has(str(d)) else "amateur"
	var fs := catalog.available_fighters()
	fighter = str(fs[0]) if not fs.is_empty() else ""
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	if return_to_hub:
		# over the Cannery (its scene stays loaded for the walk back): a dark screen, no backdrop swap
		var dim := ColorRect.new()
		dim.color = Color(CampaignUI.BG, 0.94)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	else:
		MenuBackdrop.ensure()
		add_backdrop_gradient(0.97, 0.75)
	var f := build_frame("Campaign", "The Fight Card")
	var body: VBoxContainer = f["body"]
	body.add_child(UiTheme.label("Three acts. Branching routes. Shady supplements. One belt.", "Caption"))
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UiTheme.panel("PanelSolid", 18.0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	cols.add_child(left)
	_scroll = FocusScroll.new(8)
	left.add_child(_scroll)
	var right := UiTheme.vbox(UiTheme.GAP_M)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(500, 0)
	cols.add_child(right)
	var runs := UiTheme.panel("PanelPoster")
	runs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(runs)
	var rs := ScrollContainer.new()
	rs.follow_focus = true
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	runs.add_child(rs)
	var rv := UiTheme.vbox(UiTheme.GAP_S)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(rv)
	rv.add_child(UiTheme.label("SUSPENDED RUNS", "Eyebrow"))
	_runs_box = UiTheme.vbox(UiTheme.GAP_S)
	_runs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rv.add_child(_runs_box)
	# the other campaign tables, beside the run form (START RUN -> right reaches them)
	right.add_child(_button("THE BOOKIE'S TABLE (autobattler)", "", func(): App.goto("bookie", {"stand_ins": stand_ins, "from_hub": return_to_hub}), "",
		"The Bookie's Table", "Teddy Two-Tooth deals a card and the AI fights it: watch, bet on your build, or take over the decisions."))
	right.add_child(_button("CANNERY LEDGER (Fight Camp upgrades)", "", func(): App.push("camp_ledger", {"station": ""}), "",
		"Cannery Ledger", "Spend Clout on Fight Camp upgrades. They apply only in Fight Camp runs."))
	for child in right.get_children():
		if child is Button:
			_right_buttons.append(child)
	# the prompt bar's Back covers the main menu; from the Cannery a button says where Back goes
	if return_to_hub:
		right.add_child(_button("BACK TO THE CANNERY", "", _leave, "back"))
	_help = HelpPanel.new(self)
	_help.size_flags_vertical = Control.SIZE_SHRINK_END
	_help.custom_minimum_size = Vector2(0, 190)
	right.add_child(_help)
	_status = UiTheme.label("", "Caption", true)
	body.add_child(_status)
	var bar: PromptBar = f["prompts"]
	bar.set_prompts([{"actions": ["ui_accept"], "text": "Select"}, {"actions": ["ui_left", "ui_right"], "text": "Change"},
		{"actions": ["ui_alt"], "text": "Start run", "call": _start_run}, {"actions": ["ui_cancel"], "text": "Back", "call": App.back}])
	_refresh_runs()
	_build_rows()
	_update_status()
	play_intro()


func _build_rows(focus_key := "") -> void:
	_scroll.clear()
	var c := _scroll.content
	c.add_child(UiTheme.label("NEW RUN", "Eyebrow"))
	_option(c, "variant", "Campaign", ["off_the_street", "fight_camp"], ["Off the Street", "Fight Camp"], variant,
		"Off the Street is the standard run. Fight Camp deals the same kind of card, and the Cannery upgrades you bought with Clout apply.",
		func(v) -> void: _pick_variant(str(v)))
	var fs := catalog.available_fighters()
	if fs.is_empty():
		var pending := 0
		var first_problem := ""
		for rid in catalog.roster():
			if not catalog.resolver.raw_entry(str(rid)).is_empty():
				pending += 1
				var probs := catalog.resolver.problems(str(rid))
				if first_problem == "" and not probs.is_empty():
					first_problem = probs[0]
		var why := "No roster fighters are installed yet."
		if pending > 0:
			why = "%d roster fighters are installed but their kits are not usable yet (%s)." % [pending, first_problem]
		# development stand-ins are a developer tool (CampaignFlow.dev_tools): hidden in normal play
		if CampaignFlow.dev_tools():
			c.add_child(UiTheme.label(why + " Enable development stand-ins to try the campaign (runs are marked custom).", "Danger", true))
			c.add_child(_button("ENABLE DEV STAND-INS", "", func(): App.goto("campaign_menu", {"stand_ins": true, "from_hub": return_to_hub})))
		else:
			c.add_child(UiTheme.label(why + " The card opens once their fight kits are cleared.", "Danger", true))
	else:
		var names: Array = []
		for fid in fs:
			var info := catalog.fighter_info(str(fid))
			names.append("%s  ·  %s" % [info.get("name", fid), Elements.display_name(str(info.get("element", "")))])
		_option(c, "fighter", "Fighter", fs, names, fighter, "Who you take through the card: the run's rewards, supplements and scars stay with this fighter.",
			func(v) -> void: _pick_fighter(str(v)))
		if not stand_ins and CampaignFlow.dev_tools() and fs.size() < catalog.roster().size():
			c.add_child(_button("ENABLE DEV STAND-INS (unfinished kits)", "", func(): App.goto("campaign_menu", {"stand_ins": true, "from_hub": return_to_hub})))
	var dids: Array = []
	var dnames: Array = []
	for did in catalog.difficulty_ids():
		dids.append(str(did))
		dnames.append(str(catalog.difficulties[did].get("name", did)))
	_option(c, "difficulty", "Difficulty", dids, dnames, difficulty, str(catalog.difficulty(difficulty).get("desc", "")),
		func(v) -> void: _pick_difficulty(str(v)))
	var cap := _max_dose()
	var dose_ids: Array = []
	var dose_names: Array = []
	for l in range(0, cap + 1):
		dose_ids.append(l)
		dose_names.append("Base card" if l == 0 else "Dose %d: %s" % [l, catalog.dose(l).get("name", "")])
	var dose_help := "Clear a run on Amateur or harder to open The Dosage."
	if cap > 0:
		dose_help = "Each Dose adds a twist to the card." if dose == 0 else "Active: " + "; ".join(_dose_lines())
	_option(c, "dose", "The Dosage", dose_ids, dose_names, dose, dose_help, func(v) -> void: _set_dose(int(v)))
	_option(c, "format", "Co-op format", ["simultaneous", "tag"], ["Simultaneous", "Tag-team"], coop_format, _coop_note(),
		func(v) -> void: _pick_format(str(v)))
	var sr := TextFieldRow.new("Seed")
	sr.placeholder = "Random"
	sr.setup(seed_text, 40)
	sr.set_help("Seed", "Type a number or any words to deal that card again (share it with a friend). Empty deals a random card.")
	sr.set_meta("focus_key", "seed")
	sr.value_changed.connect(func(v) -> void: seed_text = str(v))
	c.add_child(sr)
	if variant == "fight_camp":
		CampaignProgression.ensure_fields(Profiles.current)
		c.add_child(UiTheme.label("Clout: %d  ·  Cannery upgrades owned: %d (they apply only in Fight Camp runs)" % [
			int(Profiles.current["camp"].get("clout", 0)), (Profiles.current["camp"].get("upgrades", {}) as Dictionary).size()], "Caption", true))
	c.add_child(UiTheme.spacer(false, 2))
	_start = _button("START RUN", "PrimaryButton", _start_run, "fight", "Start run", "Deals the card and opens the route map. Shortcut: Y / R.")
	_start.custom_minimum_size = Vector2(0, 76)
	_start.set_meta("focus_key", "start")
	_start.disabled = fighter == ""
	c.add_child(_start)
	_scroll.wrap_focus.call_deferred()
	_link_columns.call_deferred()
	_focus_key.call_deferred(focus_key if focus_key != "" else "start")


## One choice row from the shared kit; picking a value rebuilds the rows (help texts follow it)
## and keeps the focus on this row.
func _option(c: Control, key: String, title: String, ids: Array, names: Array, current, help: String, on_pick: Callable) -> void:
	var lbls: Array[String] = []
	for n in names:
		lbls.append(str(n))
	var r := OptionRow.new(title)
	r.setup(ids, lbls, current)
	r.set_help(title, help)
	r.set_meta("focus_key", key)
	r.value_changed.connect(func(v) -> void:
		on_pick.call(v)
		_build_rows(key))
	c.add_child(r)


func _button(text: String, variation: String, on_press: Callable, icon := "", help_title := "", help_text := "") -> UiButton:
	var b := UiButton.new(text, variation, icon)
	if help_title != "":
		b.set_help(help_title, help_text)
	b.pressed.connect(on_press)
	return b


func _focus_key(key: String) -> void:
	for f in _scroll.focusables():
		if f.has_meta("focus_key") and str(f.get_meta("focus_key")) == key and f.is_visible_in_tree():
			f.grab_focus()
			return


func _pick_variant(id: String) -> void:
	variant = id
	dose = mini(dose, _max_dose())


func _pick_fighter(id: String) -> void:
	fighter = id


func _pick_difficulty(id: String) -> void:
	difficulty = id
	dose = mini(dose, _max_dose())


func _pick_format(id: String) -> void:
	coop_format = id


func _set_dose(v: int) -> void:
	dose = clampi(v, 0, _max_dose())


func _max_dose() -> int:
	return CampaignProgression.dose_cap(catalog, Profiles.current, variant, difficulty)


func _dose_lines() -> Array:
	var out := []
	for l in range(1, dose + 1):
		out.append(str(catalog.dose(l).get("name", l)))
	return out


func _coop_note() -> String:
	var net := NetPartyTransport.new()
	if net.available():
		return "Co-op: host a session from Online, then start the run from the lobby (2-4 players)."
	return "Co-op (2-4 players) runs over a hosted session; this build's network module does not expose party messaging yet. Solo play is unaffected."


func _update_status() -> void:
	var miss := catalog.warnings.size()
	var lines := []
	if stand_ins:
		lines.append("Development stand-ins are ON: missing creatures use a placeholder body and runs are marked custom.")
	elif miss > 0:
		lines.append("%d campaign references are waiting for creature/arena content from other packages." % miss)
	if not catalog.errors.is_empty():
		lines.append("Content errors: %s" % catalog.errors[0])
	_status.text = "\n".join(lines)
	_status.visible = not lines.is_empty()


func _refresh_runs() -> void:
	for c in _runs_box.get_children():
		_runs_box.remove_child(c)
		c.queue_free()
	var runs := RunStore.new().list(Profiles.id() if Profiles.id() != "" else "default", catalog)
	if runs.is_empty():
		_runs_box.add_child(UiTheme.label("No suspended runs. A run you suspend from the route map waits here.", "BodyMuted", true))
		return
	for r in runs:
		var s: Dictionary = r["summary"]
		var party := RunStore.is_party_slot(str(r["slot"]), s)
		var box := UiTheme.panel("PanelSolid", 12.0)
		var col := UiTheme.vbox(UiTheme.GAP_S)
		box.add_child(col)
		var head := CampaignFlow.describe_suspended(catalog, s)
		if party:
			head = "PARTY RUN (%d players) · %s" % [int(s.get("players", 2)), head]
		col.add_child(UiTheme.label(head if not s.is_empty() else str(r["slot"]), "BodyStrong", true))
		if not bool(r["ok"]):
			col.add_child(UiTheme.label(str(r["error"]), "Danger", true))
		elif party:
			col.add_child(UiTheme.label(PARTY_RESUME_TEXT, "Caption", true))
		var hb := UiTheme.hbox(UiTheme.GAP_S)
		var resume := _button("RESUME", "", _resume.bind(str(r["slot"])), "forward")
		resume.disabled = not bool(r["ok"]) or party
		hb.add_child(resume)
		hb.add_child(_button("ABANDON", "DangerButton", _abandon.bind(str(r["slot"])), "close"))
		col.add_child(hb)
		_runs_box.add_child(box)
	_link_columns.call_deferred()


func _link_columns() -> void:
	var run_buttons: Array[Control] = []
	for child in _runs_box.find_children("*", "Button", true, false):
		if not (child as Button).disabled:
			run_buttons.append(child)
	var right := run_buttons + _right_buttons
	if right.is_empty():
		return
	CampaignUI.chain_focus(right)
	var left := _scroll.focusables()
	for button in right:
		button.focus_neighbor_left = button.get_path_to(_start)
	for row in left:
		# Left/right on option rows still adjusts their value. Start and the
		# text row provide an explicit bridge to the suspended run controls.
		row.focus_neighbor_right = row.get_path_to(right[0])


func _resume(slot: String) -> void:
	var res := RunStore.new().load_slot(CampaignFlow.profile_key(), slot, catalog)
	if not bool(res["ok"]):
		CampaignUI.confirm(self, "Cannot resume", str(res["error"]), [{"label": "OK", "id": "ok"}], _after_modal)
		return
	if RunStore.is_party_slot(slot, RunStore.summarize(res["state"])):
		# a party run only continues through the co-op host path (CoopSession.host_resume)
		CampaignUI.confirm(self, "Party run", PARTY_RESUME_TEXT, [{"label": "OK", "id": "ok"}], _after_modal)
		return
	var f := CampaignFlow.resume(catalog, res["state"])
	f.show_current()


func _abandon(slot: String) -> void:
	CampaignUI.confirm(self, "Abandon run?", "The run counts as a defeat in your history. A damaged save is moved aside, never deleted.",
		[{"label": "ABANDON", "id": "yes", "danger": true}, {"label": "KEEP IT", "id": "no"}], _on_abandon.bind(slot))


func _on_abandon(id: String, slot: String) -> void:
	if id != "yes":
		_after_modal(id)
		return
	var held := CampaignFlow.suspended_run(catalog, slot)
	if bool(held.get("newer", false)):
		# a newer game version's run is never moved or deleted from here
		_newer_notice(held)
		return
	CampaignFlow.abandon_suspended(catalog, slot)
	_refresh_runs()
	_after_modal(id)


func _newer_notice(held: Dictionary) -> void:
	CampaignUI.confirm(self, "Saved by a newer version", "%s\nIt stays as it is; play it with that version." % str(held.get("error", "")),
		[{"label": "OK", "id": "ok"}], _after_modal)


func _after_modal(_id: String) -> void:
	if _start and is_instance_valid(_start):
		_start.call_deferred("grab_focus")


func on_resume() -> void:
	# back from the Cannery Ledger: Clout and upgrades may have changed
	_build_rows()


func on_back() -> bool:
	if CampaignUI.close_modal(self):
		return true
	_leave()
	return true


## Back: to the Cannery when opened from its sign-up sheet, else the game's menu.
func _leave() -> void:
	if return_to_hub and App.has_screen("hub"):
		App.goto("hub", {"spot": "office", "from": "campaign"})
		return
	CampaignUI.leave_campaign()


func _start_run() -> void:
	if fighter == "":
		return
	var seed_value := RunRng.text_to_seed(seed_text) if seed_text.strip_edges() != "" else 0
	var cfg := FightCamp.run_config(Profiles.current, {"variant": variant, "fighter": fighter, "difficulty": difficulty, "dose": dose,
		"seed": seed_value, "coop_format": coop_format, "custom_reasons": CampaignFlow.custom_reasons(stand_ins)})
	cfg["content_hash"] = Content.content_hash()
	var slot := RunStore.slot_for(cfg)
	var held := CampaignFlow.suspended_run(catalog, slot)
	if held.is_empty():
		_launch(cfg)
		return
	if bool(held.get("newer", false)):
		# a newer version's run is never replaced (or moved): the new card cannot take its slot
		_newer_notice(held)
		return
	# one suspended run per variant: never replace it without asking
	var buttons := [{"label": "ABANDON IT & START", "id": "replace", "danger": true}]
	if bool(held.get("ok", false)):
		buttons.append({"label": "RESUME IT", "id": "resume"})
	buttons.append({"label": "CANCEL", "id": "cancel"})
	CampaignUI.confirm(self, "Replace your suspended run?",
		"You already have a suspended run: %s.\nStarting a new card abandons it — it counts as a defeat in your history." % CampaignFlow.describe_suspended(catalog, held.get("summary", {})),
		buttons, _on_replace_choice.bind(cfg, slot))


func _on_replace_choice(id: String, cfg: Dictionary, slot: String) -> void:
	match id:
		"replace":
			CampaignFlow.abandon_suspended(catalog, slot)
			_launch(cfg)
		"resume":
			_resume(slot)
		_:
			_after_modal(id)


func _launch(cfg: Dictionary) -> void:
	var f := CampaignFlow.start(catalog, cfg)
	f.show_current()


func default_focus() -> Control:
	return _start
