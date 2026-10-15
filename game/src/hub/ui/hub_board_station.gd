class_name HubBoardStation
extends RefCounted
## Upgrade station boards (HUB.md §4: Granny's clipboard, Doc's chart, Needles' menu,
## Snappington's ledger, Ludlow's workbench, Teddy's ledger) and Snappington's fight-card sign-up
## sheet (run start). Data and purchases go through HubServices (FightCamp). A purchase saves the
## profile, plays the NPC's thanks and changes the Cannery at once (HubUpgradeProps).

const NPC_OF := {"gym_floor": "granny", "med_bay": "doc", "juice_bar": "needles", "office": "snappington", "loading_dock": "ludlow", "boiler_room": "teddy"}
## What each purchase changes in the world (shown on the board).
const VISIBLE := {
	"meta_heavy_bag": "Another heavy bag goes up by the north wall.", "meta_speed_bag": "A speed bag platform on the west wall.",
	"meta_squat_rack": "A squat rack, then more plates.", "meta_cardio_bikes": "Bikes line up by the mats.",
	"meta_grappling_dummy": "A grappling dummy by the mats.", "meta_mat_room": "A blue mat zone under the stairs.",
	"meta_ice_bath": "The ice bath gains a lid (then an ice machine).", "meta_cut_corner": "A cut-man's stool and bucket.",
	"meta_sutures": "A suture tray on Doc's table.", "meta_juice_bar_tab": "A house tab chalkboard.",
	"meta_needles_connect": "A DO NOT OPEN crate under the counter.", "meta_label_reader": "A magnifier on the counter.",
	"meta_antidote_stash": "A jar of lozenges on the counter.", "meta_sponsorship": "Sponsor posters in the Office.",
	"meta_scouting_report": "A second filing cabinet in the Office.", "meta_reroll_token": "Tokens stacked on the desk.",
	"meta_cornermans_eye": "A fight monitor in the Office.", "meta_film_room": "A projector screen in the Office.",
	"meta_title_contender": "A title plaque behind the desk.", "meta_crowd_connection": "String lights over the dock, then a fan barricade.",
	"meta_walkout": "A sound system on the dock that plays your walkout.", "meta_second_skin": "A ring jacket on a tailor's dummy.",
	"meta_bookies_favor": "Today's odds board in the Boiler Room.", "meta_boiler_room_key": "A key on the hook by the AI Lab terminal.",
}


static func build(b: HubBoard, p: Dictionary) -> void:
	var station := str(p.get("station", "gym_floor"))
	b.extra["station"] = station
	b.frame(HubServices.station_prop(station), "%s upgrades" % HubServices.station_name(station), 1080.0)
	_fill(b, str(p.get("focus", "")))


static func _fill(b: HubBoard, focus_id: String) -> void:
	b.clear_list()
	var station := str(b.extra["station"])
	var sv := b.services()
	b.refresh_clout()
	if not sv.available():
		b.text_line(sv.unavailable_reason(), "Warning")
		b.set_status("The station opens when the campaign module is installed.")
		b.button("Close", b.close)
		return
	var rows := sv.list_upgrades(station)
	var focus_btn: UiButton = null
	for r in rows:
		var u: Dictionary = r
		var id := str(u["id"])
		var lv := int(u.get("level", 0))
		var mx := int(u.get("max_level", 1))
		var right := ""
		if bool(u.get("maxed", false)):
			right = "MAXED"
		elif bool(u.get("locked", false)):
			right = "LOCKED"
		else:
			right = "%d CLOUT" % int(u.get("next_cost", 0))
		var pips := ""
		for i in mx:
			pips += "■" if i < lv else "□"
		var help := "%s\n\nLevel %d of %d.  %s" % [str(u.get("effect", "")), lv, mx, str(VISIBLE.get(id, ""))]
		if bool(u.get("locked", false)):
			help += "\n\nLocked: %s" % str(u.get("lock_reason", ""))
		var btn := b.button("%s   %s   ·   %s" % [str(u.get("name", id)).to_upper(), pips, right], _buy.bind(b, u), str(u.get("name", id)), help)
		btn.route = id
		if bool(u.get("locked", false)) or bool(u.get("maxed", false)) or not bool(u.get("affordable", false)):
			btn.add_theme_color_override("font_color", UiTheme.MUTED)
		if id == focus_id:
			focus_btn = btn
	if rows.is_empty():
		b.text_line("Nothing for sale at this station.", "BodyMuted")
	b.set_status("Upgrades apply in Fight Camp runs only (never in versus or online). Clout comes from runs, activities and secrets.")
	if focus_btn:
		focus_btn.call_deferred("grab_focus")
	else:
		b.focus_first()


static func _buy(b: HubBoard, u: Dictionary) -> void:
	var id := str(u["id"])
	if bool(u.get("maxed", false)):
		Audio.ui("ui_error")
		b.set_status("%s is already at its top level." % str(u.get("name", id)), "Warning")
		return
	if bool(u.get("locked", false)):
		Audio.ui("ui_error")
		b.set_status("Locked: %s" % str(u.get("lock_reason", "")), "Warning")
		return
	if not bool(u.get("affordable", false)):
		Audio.ui("ui_error")
		b.set_status("Not enough Clout: %d of %d." % [b.hub_state().clout(), int(u.get("next_cost", 0))], "Danger")
		return
	App.dialog("Buy %s?" % str(u.get("name", id)), "Level %d for %d Clout. %s" % [int(u.get("level", 0)) + 1, int(u.get("next_cost", 0)), str(u.get("effect", ""))],
		[{"label": "Buy", "id": "buy"}, {"label": "Not yet", "id": "no", "cancel": true}],
		func(choice: String) -> void:
			if choice == "buy":
				confirm_buy(b, id))


static func confirm_buy(b: HubBoard, id: String) -> Dictionary:
	var r := b.services().buy_upgrade(id)
	if bool(r.get("ok", false)):
		Profiles.save()
		Audio.ui("ui_purchase")
		var npc := str(NPC_OF.get(str(b.extra.get("station", "")), ""))
		if npc != "" and b.scene != null:
			b.scene.call("npc_say", npc, HubContent.keyed_line(npc, "upgrade"))
		b.set_status("Bought: level %d. Look around: %s" % [int(r.get("level", 1)), str(VISIBLE.get(id, ""))], "Success")
		_fill(b, id)
		b.set_status("Bought: level %d. %s" % [int(r.get("level", 1)), str(VISIBLE.get(id, ""))], "Success")
	else:
		Audio.ui("ui_error")
		b.set_status(str(r.get("error", "Could not buy that.")), "Danger")
	return r


# ---- Snappington's sign-up sheet (run start) ------------------------------------------------------

static func build_run(b: HubBoard, p: Dictionary) -> void:
	b.frame("Commission sign-up sheet", "Fight Camp card", 1080.0)
	var sv := b.services()
	if bool(p.get("stand_ins", false)):
		sv.stand_ins = true
	var st := b.hub_state()
	if not sv.available():
		b.text_line("\"%s\"" % HubContent.keyed_line("snappington", "run_absent"), "H3")
		b.text_line(sv.unavailable_reason(), "Warning")
		b.button("Close", b.close)
		return
	var o := sv.run_options()
	var fighters: Array = o.get("fighters", [])
	var use_standins := func() -> void:
		b.close()
		b.open_child("run", {"stand_ins": true})
	if fighters.is_empty():
		b.text_line("\"The Commission has no fighters cleared for the card yet.\" (The roster's fight kits are still being finished.)", "Warning")
		# development stand-ins are a developer tool (CampaignFlow.dev_tools): hidden in normal play
		if CampaignFlow.dev_tools():
			b.button("Use development stand-ins (custom run)", use_standins, "Development stand-ins",
				"Missing kits are replaced by a placeholder body so you can try the card; the run is marked custom (no records).")
		b.button("Campaign menu (suspended runs, co-op lobby)", sv.open_campaign_menu)
		b.focus_first()
		return
	var names: Array = fighters.map(func(f): return str(Content.get_entry("creatures", str(f)).get("name", f)))
	var me := ""
	if b.scene != null:
		me = b.scene.call("player").creature.id
	var fr := OptionRow.new("Fighter").setup(fighters, names, me if fighters.has(me) else (fighters[0] if not fighters.is_empty() else ""))
	fr.set_help("Fighter", "Who walks out on the card. Your Cannery upgrades apply to whoever you pick.")
	b.list.content.add_child(fr)
	var diffs: Array = o.get("difficulties", [])
	var dids: Array = diffs.map(func(d): return str(d["id"]))
	var dnames: Array = diffs.map(func(d): return str(d["name"]))
	var dcur := str(Settings.get_value("gameplay.difficulty"))
	var dr := OptionRow.new("Difficulty").setup(dids, dnames, dcur if dids.has(dcur) else "amateur")
	dr.set_help("Difficulty", "Sparring, Amateur, Pro or Title Shot. Harder cards pay more Clout.")
	b.list.content.add_child(dr)
	var doses: Array = o.get("doses", [{"level": 0, "name": "Base card"}])
	var dose_r := OptionRow.new("The Dosage").setup(doses.map(func(d): return int(d["level"])), doses.map(func(d): return str(d["name"])), 0)
	dose_r.set_help("The Dosage", "Ten Doses of extra trouble. Clear a run on Amateur or harder to open it.")
	b.list.content.add_child(dose_r)
	var cr := OptionRow.new("Co-op format").setup(["simultaneous", "tag"], ["Simultaneous", "Tag-team"], "simultaneous")
	cr.set_help("Co-op format", "Used when you host a party from Online; solo runs ignore it.")
	b.list.content.add_child(cr)
	var seed_row := TextFieldRow.new("Seed (optional)").setup("", 32)
	seed_row.placeholder = "random"
	seed_row.set_help("Seed", "Type a seed or any words to share a card with a friend. Empty = random.")
	b.list.content.add_child(seed_row)
	var start := UiButton.new("SIGN THE WAIVER", "PrimaryButton", "fight")
	start.set_help("Sign the waiver", "\"Sign here. And here. The waiver is mostly decorative.\"")
	start.custom_minimum_size = Vector2(0, 76)
	start.pressed.connect(func() -> void:
		var r := sv.start_run({"fighter": str(fr.get_value()), "difficulty": str(dr.get_value()), "dose": int(dose_r.get_value()),
			"coop_format": str(cr.get_value()), "seed_text": seed_row.get_value()})
		if not bool(r.get("ok", false)):
			Audio.ui("ui_error")
			b.set_status(str(r.get("error", "The Commission refused.")), "Danger"))
	b.list.content.add_child(start)
	b.button("Campaign menu (suspended runs, co-op lobby)", sv.open_campaign_menu, "Campaign menu",
		"Resume a suspended Fight Camp run, host co-op, or open the Cannery Ledger.", "", "campaign")
	if CampaignFlow.dev_tools() and not sv.stand_ins and fighters.size() < CampaignCatalog.shared().roster().size():
		b.button("Use development stand-ins (unfinished kits)", use_standins, "Development stand-ins",
			"Developer tool: fighters whose kits are unfinished get a placeholder body; the run is marked custom (no records).")
	b.set_status("Clout %d  ·  Cannery upgrades owned %d / 24 (they apply to this run)." % [st.clout(), st.upgrades_owned()])
	b.focus_first()
