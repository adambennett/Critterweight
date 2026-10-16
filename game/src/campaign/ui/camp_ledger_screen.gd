extends Screen
## The Cannery Ledger: the menu face of the Fight Camp hub boards (FightCamp API). Station
## filter (Gym Floor, Med Bay, Juice Bar, Office, Loading Dock, Boiler Room), one row per
## upgrade (level, effect, next cost, lock reason) with BUY. Purchases spend Clout from the
## active profile and save it. Upgrades are tagged meta_bonus: they only ever apply inside
## Fight Camp runs (or custom matches that visibly enable Gym Bonuses).

var catalog: CampaignCatalog
var station := ""
var _rows: VBoxContainer
var _focusables: Array = []
var _msg: Label
var _note := ""
var _focus_id := ""


func on_enter(p: Dictionary) -> void:
	station = str(p.get("station", ""))
	catalog = CampaignFlow.make_catalog(false)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_focusables.clear()
	CampaignProgression.ensure_fields(Profiles.current)
	var clout := int(Profiles.current["camp"].get("clout", 0))
	var v := CampaignUI.scaffold(self, "THE CANNERY LEDGER", "Clout buys Fight Camp upgrades. They apply only in Fight Camp runs — never in Off the Street, versus or online.")
	v.add_child(CampaignUI.label("CLOUT %d   ·   earned in total %d" % [clout, int(Profiles.current["camp"].get("clout_total", 0))], 30, CampaignUI.ACCENT, "900"))
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 8)
	filters.add_theme_constant_override("v_separation", 8)
	var tabs := [{"id": "", "name": "All stations", "npc": ""}]
	tabs.append_array(FightCamp.stations())
	for st in tabs:
		var sid := str(st["id"])
		var label := str(st["name"]) + ((" · " + str(st["npc"])) if str(st.get("npc", "")) != "" else "")
		# the chosen station is the green chip (no text marker)
		var b := CampaignUI.button(label, _pick_station.bind(sid), 20,
			CampaignUI.GOOD if sid == station else CampaignUI.ACCENT)
		filters.add_child(b)
		_focusables.append(b)
	v.add_child(filters)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	var focus_target: Control = null
	for u in FightCamp.list_upgrades(catalog, Profiles.current, station):
		var row := _upgrade_row(u)
		_rows.add_child(row[0])
		if row[1] != null:
			_focusables.append(row[1])
			if str(u["id"]) == _focus_id:
				focus_target = row[1]
	v.add_child(CampaignUI.scroll(_rows))
	_msg = CampaignUI.label(_note.trim_prefix("!"), 20, CampaignUI.DANGER if _note.begins_with("!") else CampaignUI.GOOD)
	_note = ""
	v.add_child(_msg)
	var back := CampaignUI.button("BACK", _leave, 22, CampaignUI.MUTED)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size = Vector2(260, 48)
	v.add_child(back)
	_focusables.append(back)
	var f: Control = focus_target if focus_target else default_focus()
	if f:
		f.call_deferred("grab_focus")


func _upgrade_row(u: Dictionary) -> Array:
	var pnl := CampaignUI.panel()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	pnl.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st_name := ""
	for st in FightCamp.stations():
		if str(st["id"]) == str(u.get("station", "")):
			st_name = "%s · %s" % [st["name"], st["npc"]]
	info.add_child(CampaignUI.label("%s   Lv %d / %d" % [str(u["name"]).to_upper(), int(u["level"]), int(u["max_level"])], 26, CampaignUI.INK, "900"))
	info.add_child(CampaignUI.label(str(u.get("effect", "")), 20))
	var meta_line := st_name
	if bool(u.get("locked", false)):
		meta_line += ("   ·   " if meta_line != "" else "") + "LOCKED: " + str(u.get("lock_reason", ""))
	info.add_child(CampaignUI.label(meta_line, 17, CampaignUI.DANGER if bool(u.get("locked", false)) else CampaignUI.MUTED))
	h.add_child(info)
	var pips := HBoxContainer.new()
	for i in int(u["max_level"]):
		var pip := CampaignUI.ShapeIcon.new("square" if i < int(u["level"]) else "circle", CampaignUI.ACCENT if i < int(u["level"]) else CampaignUI.PANEL_HI.lightened(0.2))
		pips.add_child(pip)
	h.add_child(pips)
	var btn: Button = null
	if bool(u.get("maxed", false)):
		h.add_child(CampaignUI.label("MAXED", 24, CampaignUI.GOOD, "900"))
	else:
		btn = CampaignUI.button("BUY · %d CLOUT" % int(u["next_cost"]), _buy.bind(str(u["id"])), 22)
		btn.custom_minimum_size = Vector2(240, 48)
		btn.disabled = not bool(u.get("affordable", false))
		btn.tooltip_text = str(u.get("lock_reason", "")) if bool(u.get("locked", false)) else ("Not enough Clout" if btn.disabled else "")
		h.add_child(btn)
	return [pnl, btn]


func _pick_station(id: String) -> void:
	station = id
	_build()


func _buy(id: String) -> void:
	var r := FightCamp.buy_upgrade(catalog, Profiles.current, id)
	if bool(r.get("ok", false)):
		Profiles.save()
		_note = "%s is now level %d." % [catalog.meta.get(id, {}).get("name", id), int(r["level"])]
	else:
		_note = "!" + str(r.get("error", "could not buy"))
	_focus_id = id
	_build()


func _leave() -> void:
	if App.stack.size() > 1:
		App.back()
	else:
		App.goto("campaign_menu")


func on_back() -> bool:
	if App.stack.size() > 1:
		return false
	App.goto("campaign_menu")
	return true


func default_focus() -> Control:
	for c in _focusables:
		if c is Button and not (c as Button).disabled and (c as Button).text.begins_with("BUY"):
			return c
	return CampaignUI.first_enabled(_focusables)
