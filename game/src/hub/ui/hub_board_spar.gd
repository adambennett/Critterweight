class_name HubBoardSpar
extends RefCounted
## Boards for the cage gate (Ring Sparring setup), your locker (fighter + cosmetics), the Wall of
## Fame / Shame (runs and records) and the Broadcast Booth desk (announcer settings, line packs,
## the replay booth).


static func build(b: HubBoard, p: Dictionary) -> void:
	b.frame("The practice cage", "Ring sparring", 1080.0)
	var st := b.hub_state()
	var ids := ["kid_lamprey"]
	var names := ["Kid Lamprey"]
	for c in Content.playable_creatures():
		if str(c).begins_with("f_"):
			ids.append(str(c))
			names.append(str(Content.get_entry("creatures", str(c)).get("name", c)))
	var opp := OptionRow.new("Opponent").setup(ids, names, str(p.get("opponent", "kid_lamprey")))
	opp.set_help("Opponent", "Kid Lamprey (the Cannery's sparring partner) or any fighter on the roster.")
	b.list.content.add_child(opp)
	var tier := OptionRow.new("Bot tier").setup(BotTiers.ids(), BotTiers.names(), "journeyman")
	tier.set_help("Bot tier", "Punching Bag to Hall-of-Famer. First win over Kid Lamprey at Contender: 25 Clout. Beating a Headliner earns that fighter a badge.")
	b.list.content.add_child(tier)
	var fmt := OptionRow.new("Format").setup(["spar", "practice"], ["Spar: one round", "Practice: no KO, telemetry"], "spar")
	fmt.set_help("Format", "Spar is a real one-round fight. Practice never ends: hit speed, quality, clean hits and poise on the HUD.")
	b.list.content.add_child(fmt)
	var grav := ToggleRow.new("Low gravity").setup(false)
	grav.set_help("Low gravity", "Half gravity in the cage. Throws fly, so do you.")
	b.list.content.add_child(grav)
	var haz := ToggleRow.new("Hazards").setup(false)
	haz.set_help("Hazards", "A puddle and a fire grate on the canvas.")
	b.list.content.add_child(haz)
	var go := UiButton.new("STEP INTO THE CAGE", "PrimaryButton", "fight")
	go.custom_minimum_size = Vector2(0, 76)
	go.set_help("Step into the cage", "No stakes: sparring never changes your record. Leave any time with the Scoreboard button.")
	go.pressed.connect(func() -> void:
		var choices := {"opponent": str(opp.get_value()), "tier": str(tier.get_value()), "format": str(fmt.get_value()),
			"low_gravity": grav.get_value(), "hazards": haz.get_value()}
		App.clear_screens()
		HubSparring.launch(b.scene, choices))
	b.list.content.add_child(go)
	var sp: Dictionary = st.hub()["spar"]
	b.set_status("Kid Lamprey at Contender: %s  ·  Headliner badges: %d" % ["beaten" if bool(sp.get("kid_contender", false)) else "not yet",
		(sp.get("headliner", []) as Array).size()])
	b.focus_first()


# ---- your locker --------------------------------------------------------------------------------

const SLOTS := [["piece", "Gag piece"], ["idle_prop", "Idle prop"], ["back", "Walkout back-piece"], ["frame", "Profile frame"],
	["juice", "JUICE colour"], ["pet", "Hub pet"], ["neck", "Neckwear"], ["can", "Supplement can"]]


static func build_lockers(b: HubBoard, _p: Dictionary) -> void:
	b.frame("Locker 23", "Your locker", 1080.0)
	_fill_lockers(b)


static func _fill_lockers(b: HubBoard) -> void:
	b.clear_list()
	var st := b.hub_state()
	var cur := st.loadout_fighter()
	b.section("Walk the Cannery as")
	for c in Content.playable_creatures():
		var cid := str(c)
		if not cid.begins_with("f_"):
			continue
		var d := Content.get_entry("creatures", cid)
		var label := "%s   ·   %s%s" % [str(d.get("name", cid)).to_upper(), Elements.display_name(str(d.get("element", ""))), "   ·   IN USE" if cid == cur else ""]
		var pick := func() -> void:
			if b.scene != null:
				b.scene.call("switch_fighter", cid)
			_fill_lockers(b)
		var btn := b.button(label, pick, str(d.get("name", cid)), str(d.get("blurb", d.get("title", ""))))
		btn.route = cid
	b.section("Cosmetics")
	var any := false
	for s in SLOTS:
		var slot := str(s[0])
		var owned := HubContent.cosmetics_in_slot(slot).filter(func(x): return st.has_cosmetic(str(x)))
		if slot == "frame":
			owned.append_array(st.profile.get("unlocks", {}).get("cosmetics", []).filter(func(x): return str(x).begins_with("hub_badge_")))
		if owned.is_empty():
			continue
		any = true
		var vals: Array = ["none"] + owned
		var lbls: Array = ["None"] + owned.map(func(x): return HubContent.cosmetic_name(str(x)))
		var row := OptionRow.new(str(s[1])).setup(vals, lbls, st.cosmetic_in(slot) if st.cosmetic_in(slot) != "" else "none")
		row.set_help(str(s[1]), "Cosmetic only: nothing here changes how a fighter fights.")
		row.value_changed.connect(func(v) -> void: st.equip(slot, "" if str(v) == "none" else str(v)))
		b.list.content.add_child(row)
	if not any:
		b.text_line("Nothing yet. The Cannery hides plenty: ask Ludlow.", "BodyMuted")
	b.set_status("Your fighter here is just for walking around; the fight card's fighter is picked at Snappington's desk.")
	b.focus_first()


# ---- Wall of Fame / Shame --------------------------------------------------------------------------

static func build_records(b: HubBoard, _p: Dictionary) -> void:
	b.frame("Locker room", "Wall of Fame & Shame", 1080.0)
	var st := b.hub_state()
	var photos := st.wall_photos()
	b.section("The wall (newest first, 24 photos)")
	if photos.is_empty():
		b.text_line("No photos yet. Ludlow keeps the nails ready.", "BodyMuted")
	var tags := {"title": ["TITLE", "Success"], "win": ["BEAT A BOSS", "Success"], "loss": ["LOSS", "Danger"]}
	for ph in photos:
		var d: Dictionary = ph
		var t: Array = tags.get(str(d["result"]), ["?", "Body"])
		var fname := str(Content.get_entry("creatures", str(d["fighter"])).get("name", d["fighter"]))
		var line := "%s   %s · Act %d%s · %d KOs" % [str(t[0]), fname, int(d["act"]), (" · Dose %d" % int(d["dose"])) if int(d["dose"]) > 0 else "", int(d["kos"])]
		var btn := b.button(line, func() -> void: pass, str(t[0]), "%s run with %s, ended in Act %d." % ["Fight Camp" if str(d["variant"]) == "fight_camp" else "Off the Street", fname, int(d["act"])])
		btn.sfx_accept = "ui_move"
		btn.add_theme_color_override("font_color", UiTheme.SUCCESS if str(d["result"]) != "loss" else UiTheme.DANGER)
	b.section("Records")
	var runs: Dictionary = st.profile.get("records", {}).get("runs", {})
	for v in ["fight_camp", "off_the_street", "bookie"]:
		var r: Dictionary = runs.get(v, {})
		b.text_line("%s: %d attempts · %d clears · best Dose %d" % [{"fight_camp": "Fight Camp", "off_the_street": "Off the Street", "bookie": "Bookie's Table"}[v],
			int(r.get("attempts", 0)), int(r.get("clears", 0)), int(r.get("best_dose", 0))], "Body")
	var stats: Dictionary = st.profile.get("stats", {})
	b.text_line("All matches: %d wins · %d losses · %d KOs" % [int(stats.get("wins", 0)), int(stats.get("losses", 0)), int(stats.get("kos", 0))], "Body")
	b.section("Cannery bests")
	for k in [["bag_light", "Light bag"], ["bag_heavy", "Heavy bag"], ["bag_body", "Body bag"], ["drill", "Chum drill streak"], ["crates", "Crate Toss"]]:
		b.text_line("%s: %d" % [str(k[1]), int(st.best_of(str(k[0])))], "Caption")
	b.focus_first()


# ---- Broadcast Booth desk --------------------------------------------------------------------------

static func build_booth(b: HubBoard, _p: Dictionary) -> void:
	b.frame("Barnaby's desk", "Broadcast booth", 1080.0)
	var st := b.hub_state()
	b.section("Announcer")
	for key in ["audio.voice", "gameplay.announcer", "access.subtitles"]:
		var row := SettingRows.make(key)
		if row:
			b.list.content.add_child(row)
	b.section("Line packs")
	if st.has_secret("sec_booth_tape"):
		var vt := ToggleRow.new("Vintage Bellows ('73)").setup(st.pack_on("vintage_bellows"))
		vt.set_help("Vintage Bellows", "Barnaby, 1973 edition: plays in the booth and on the tape. More hair, more reverb.")
		vt.value_changed.connect(func(v) -> void: st.set_pack("vintage_bellows", bool(v)))
		b.list.content.add_child(vt)
	else:
		b.text_line("Standard Bellows (more packs are... somewhere around here).", "BodyMuted")
	b.section("Replay booth")
	var recall := func() -> void:
		var lines := HubBoardTalk.recall_lines(st)
		b.set_status(" ".join(PackedStringArray(lines)), "Body")
		Audio.say("barnaby", str(lines[lines.size() - 1]), 55)
	b.button("Re-call my last fight", recall, "Re-call my last fight", "Barnaby calls it again. Louder.")
	if st.has_secret("sec_booth_tape"):
		var tape := func() -> void:
			App.clear_screens()
			HubSparring.play_tape(b.scene)
		b.button("Play the 1973 tape", tape, "The 1973 tape", "The Commissioner's title fight, 40 seconds of history.")
	b.focus_first()
