extends Screen
## Campaign menu: variant (Off the Street / Fight Camp), fighter, difficulty, Dose, party
## (solo / co-op format), seed, suspended runs (resume / abandon), The Bookie's Table and the
## Cannery Ledger. Fully operable with a controller (focus moves between rows by geometry,
## ui_accept presses, ui_cancel goes back) and with mouse/keyboard.
## One suspended run per variant: START RUN over an occupied slot asks first (abandon it and
## start, resume it, or cancel); abandoning credits it as a defeat. Party runs are listed but
## resume only through the co-op host path (CoopSession.host_resume), never as a solo run.

const PARTY_RESUME_TEXT := "A co-op party's run: its host resumes it from the co-op lobby so the party can rejoin (it never continues as a solo run)."

var catalog: CampaignCatalog
var stand_ins := false
var variant := "off_the_street"
var fighter := ""
var difficulty := "amateur"
var dose := 0
var coop_format := "simultaneous"
var seed_edit: LineEdit
var _status: Label
var _rows: VBoxContainer
var _start: Button
var _runs_box: VBoxContainer
var _diff_desc: Label
var _dose_label: Label


func on_enter(p: Dictionary) -> void:
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
	var v := CampaignUI.scaffold(self, "THE FIGHT CARD", "Three acts. Branching routes. Shady supplements. One belt.")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(CampaignUI.scroll(_rows))
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(520, 0)
	right.add_theme_constant_override("separation", 10)
	cols.add_child(right)
	_build_rows()
	right.add_child(CampaignUI.label("SUSPENDED RUNS", 26, CampaignUI.ACCENT, "900"))
	_runs_box = VBoxContainer.new()
	_runs_box.add_theme_constant_override("separation", 8)
	right.add_child(_runs_box)
	_refresh_runs()
	right.add_child(CampaignUI.button("THE BOOKIE'S TABLE (autobattler)", func(): App.goto("bookie", {"stand_ins": stand_ins})))
	right.add_child(CampaignUI.button("CANNERY LEDGER (Fight Camp upgrades)", func(): App.push("camp_ledger", {"station": ""})))
	right.add_child(CampaignUI.button("BACK", CampaignUI.leave_campaign, 24, CampaignUI.MUTED))
	_status = CampaignUI.label("", 20, CampaignUI.MUTED)
	v.add_child(_status)
	_update_status()


func _build_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
	_row("VARIANT", [["Off the Street", "off_the_street"], ["Fight Camp", "fight_camp"]], variant, _pick_variant)
	var fs := []
	for fid in catalog.available_fighters():
		var info := catalog.fighter_info(str(fid))
		fs.append(["%s  ·  %s" % [info.get("name", fid), Elements.display_name(str(info.get("element", "")))], str(fid)])
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
		_rows.add_child(CampaignUI.label(why + " Enable development stand-ins to try the campaign (runs are marked custom).", 20, CampaignUI.DANGER))
		_rows.add_child(CampaignUI.button("ENABLE DEV STAND-INS", func(): App.goto("campaign_menu", {"stand_ins": true})))
	else:
		_row("FIGHTER", fs, fighter, _pick_fighter)
	var ds := []
	for did in catalog.difficulty_ids():
		ds.append([str(catalog.difficulties[did].get("name", did)), str(did)])
	_row("DIFFICULTY", ds, difficulty, _pick_difficulty)
	_diff_desc = CampaignUI.label(str(catalog.difficulty(difficulty).get("desc", "")), 18, CampaignUI.MUTED)
	_rows.add_child(_diff_desc)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 10)
	dh.add_child(CampaignUI.label("THE DOSAGE", 22, CampaignUI.INK, "900"))
	var minus := CampaignUI.button("  -  ", _change_dose.bind(-1))
	var plus := CampaignUI.button("  +  ", _change_dose.bind(1))
	minus.disabled = dose <= 0
	plus.disabled = dose >= _max_dose()
	dh.add_child(minus)
	var dname := "Base card" if dose == 0 else "Dose %d: %s" % [dose, catalog.dose(dose).get("name", "")]
	_dose_label = CampaignUI.label(dname, 22)
	dh.add_child(_dose_label)
	dh.add_child(plus)
	_rows.add_child(dh)
	if dose > 0:
		_rows.add_child(CampaignUI.label("Active: " + "; ".join(_dose_lines()), 18, CampaignUI.MUTED))
	elif _max_dose() == 0:
		_rows.add_child(CampaignUI.label("Clear a run on Amateur or harder to open The Dosage.", 18, CampaignUI.MUTED))
	_row("CO-OP FORMAT", [["Simultaneous (default)", "simultaneous"], ["Tag-team", "tag"]], coop_format, _pick_format)
	_rows.add_child(CampaignUI.label(_coop_note(), 18, CampaignUI.MUTED))
	var sh := HBoxContainer.new()
	sh.add_child(CampaignUI.label("SEED", 22, CampaignUI.INK, "900"))
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "random (or type a seed / any words)"
	seed_edit.custom_minimum_size = Vector2(420, 44)
	seed_edit.focus_mode = Control.FOCUS_ALL
	sh.add_child(seed_edit)
	_rows.add_child(sh)
	if variant == "fight_camp":
		CampaignProgression.ensure_fields(Profiles.current)
		_rows.add_child(CampaignUI.label("Clout: %d  ·  Cannery upgrades owned: %d (apply ONLY in Fight Camp runs)" % [
			int(Profiles.current["camp"].get("clout", 0)), (Profiles.current["camp"].get("upgrades", {}) as Dictionary).size()], 18, CampaignUI.MUTED))
	_start = CampaignUI.button("START RUN", _start_run, 30)
	_start.disabled = fighter == ""
	_rows.add_child(_start)
	_start.call_deferred("grab_focus")


func _row(title: String, opts: Array, current: String, on_pick: Callable) -> void:
	_rows.add_child(CampaignUI.label(title, 22, CampaignUI.INK, "900"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for o in opts:
		var id := str(o[1])
		var b := CampaignUI.button(("> %s" % o[0]) if id == current else str(o[0]), on_pick.bind(id), 22, CampaignUI.GOOD if id == current else CampaignUI.ACCENT)
		flow.add_child(b)
	_rows.add_child(flow)


func _pick_variant(id: String) -> void:
	variant = id
	dose = mini(dose, _max_dose())
	_build_rows()


func _pick_fighter(id: String) -> void:
	fighter = id
	_build_rows()


func _pick_difficulty(id: String) -> void:
	difficulty = id
	dose = mini(dose, _max_dose())
	_build_rows()


func _pick_format(id: String) -> void:
	coop_format = id
	_build_rows()


func _change_dose(delta: int) -> void:
	dose = clampi(dose + delta, 0, _max_dose())
	_build_rows()


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


func _refresh_runs() -> void:
	for c in _runs_box.get_children():
		c.queue_free()
	var runs := RunStore.new().list(Profiles.id() if Profiles.id() != "" else "default", catalog)
	if runs.is_empty():
		_runs_box.add_child(CampaignUI.label("No suspended runs.", 18, CampaignUI.MUTED))
		return
	for r in runs:
		var s: Dictionary = r["summary"]
		var party := RunStore.is_party_slot(str(r["slot"]), s)
		var box := CampaignUI.panel()
		var col := VBoxContainer.new()
		box.add_child(col)
		var head := CampaignFlow.describe_suspended(catalog, s)
		if party:
			head = "PARTY RUN (%d players) · %s" % [int(s.get("players", 2)), head]
		col.add_child(CampaignUI.label(head if not s.is_empty() else str(r["slot"]), 20))
		if not bool(r["ok"]):
			col.add_child(CampaignUI.label(str(r["error"]), 16, CampaignUI.DANGER))
		elif party:
			col.add_child(CampaignUI.label(PARTY_RESUME_TEXT, 16, CampaignUI.MUTED))
		var hb := HBoxContainer.new()
		var resume := CampaignUI.button("RESUME", _resume.bind(str(r["slot"])), 20)
		resume.disabled = not bool(r["ok"]) or party
		hb.add_child(resume)
		hb.add_child(CampaignUI.button("ABANDON", _abandon.bind(str(r["slot"])), 20, CampaignUI.DANGER))
		col.add_child(hb)
		_runs_box.add_child(box)


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
	CampaignUI.leave_campaign()
	return true


func _start_run() -> void:
	if fighter == "":
		return
	var seed_value := RunRng.text_to_seed(seed_edit.text) if seed_edit and seed_edit.text.strip_edges() != "" else 0
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
