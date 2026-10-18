class_name HubBoardTalk
extends RefCounted
## A conversation (HubBoard kind "talk"): the NPC's line in a dialogue box at the bottom of the
## screen (the 3D hub stays visible) and what you can ask them — their services, their station,
## "How did I do?" (a reaction to your last run), Ludlow's hint about the nearest unfound secret,
## handing Ludlow an elevator part, Barnaby re-calling your last fight, the 1973 tape.

const STATION_OF := {"granny": "gym_floor", "doc": "med_bay", "needles": "juice_bar", "snappington": "office", "ludlow": "loading_dock", "teddy": "boiler_room"}


static func build(b: HubBoard, p: Dictionary) -> void:
	var npc := str(p.get("npc", "granny"))
	var d := HubContent.npc(npc)
	b.extra["npc"] = npc
	b.frame(str(d.get("role", "")), str(d.get("name", npc)), 1500.0, false, "bottom")
	b.eyebrow_label.add_theme_color_override("font_color", HubContent.npc_color(npc))
	var st := b.hub_state()
	var salt := int(Time.get_ticks_msec() / 997.0) + st.secrets_found()
	var line := HubContent.line(npc, "talk", salt)
	b.extra["line"] = UiTheme.label(HubContent.fill(line, HubContent.run_context(st)), "H3", true)
	(b.extra["line"] as Label).custom_minimum_size = Vector2(1300, 0)
	b.list.content.add_child(b.extra["line"])
	Audio.stop_announcer() # An explicit conversation replaces an incidental bark.
	Audio.say(str(d.get("speaker", npc)), HubContent.fill(line, HubContent.run_context(st)), 45)
	_options(b, npc, d)
	b.prompts.set_prompts([{"actions": ["ui_accept"], "text": "Choose"}, {"actions": ["ui_cancel"], "text": "Bye", "call": b.close}])


static func say(b: HubBoard, text: String) -> void:
	(b.extra["line"] as Label).text = text
	var npc := str(b.extra.get("npc", ""))
	Audio.stop_announcer() # A newly selected response must not be dropped behind the greeting.
	Audio.say(str(HubContent.npc(npc).get("speaker", npc)), text, 45)


static func _options(b: HubBoard, npc: String, d: Dictionary) -> void:
	var st := b.hub_state()
	var mode := b.hub_mode()
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	b.list.content.add_child(grid)
	for opt in d.get("options", []):
		var o := str(opt)
		if o.begins_with("station:"):
			var sid := o.substr(8)
			_btn(b, grid, "%s (upgrades)" % HubServices.station_prop(sid), func() -> void: b.open_child("station", {"station": sid}), "station")
			continue
		match o:
			"bag_challenge":
				for bag in ["light", "heavy", "body"]:
					var bname := str((HubContent.activity("bags").get("bags", {}) as Dictionary).get(bag, {}).get("name", bag))
					_btn(b, grid, "%s challenge" % bname, func() -> void: _start_bag(b, bag), "fight")
			"tutorial":
				_btn(b, grid, "Lessons in the cage", func() -> void: b.open_child("lessons"), "tutorial")
			"last_run":
				_btn(b, grid, "How did I do?", func() -> void: say(b, _run_reaction(npc, st)), "info")
			"start_run":
				_btn(b, grid, "Sign up for a fight card", func() -> void: b.open_child("run"), "campaign")
			"shop_preview":
				_btn(b, grid, "Tonight's menu", func() -> void: b.open_child("shop"), "can")
			"rest_preview":
				_btn(b, grid, "Ask about patch-ups", func() -> void: b.open_child("rest"), "plus")
			"sparring":
				_btn(b, grid, "Spar with me", func() -> void: b.open_child("spar", {"opponent": "kid_lamprey"}), "versus")
			"hint":
				_btn(b, grid, "Know any secrets?", func() -> void: _hint(b, st, mode), "info")
			"give_part":
				_btn(b, grid, "About the freight elevator...", func() -> void: _elevator(b, st, mode), "forward")
			"bookie":
				_btn(b, grid, "Take a seat at the table", func() -> void: _bookie(b), "random")
			"ai_lab":
				_btn(b, grid, "The AI Lab terminal", func() -> void: _lab(b), "lab")
			"booth":
				_btn(b, grid, "Announcer settings", func() -> void: b.open_child("booth"), "settings")
			"recall":
				_btn(b, grid, "Re-call my last fight", func() -> void: say(b, " ".join(PackedStringArray(recall_lines(st)))), "spectate")
			"tape":
				if st.has_secret("sec_booth_tape"):
					_btn(b, grid, "Play the 1973 tape", func() -> void: _tape(b), "spectate")
	_btn(b, grid, "Bye", b.close, "back")


static func _btn(b: HubBoard, parent: Container, text: String, cb: Callable, icon := "") -> UiButton:
	var u := UiButton.new(text, "SubItem", icon)
	u.custom_minimum_size = Vector2(420, 64)
	u.pressed.connect(cb)
	parent.add_child(u)
	return u


static func _start_bag(b: HubBoard, bag: String) -> void:
	var mode := b.hub_mode()
	b.close()
	if mode:
		mode.start_activity("bag", bag)


static func _run_reaction(npc: String, st: HubState) -> String:
	var t := HubContent.run_line(npc, st, int(Time.get_ticks_msec() / 1000.0))
	return t if t != "" else HubContent.line(npc, "talk", 1)


static func _hint(b: HubBoard, st: HubState, mode: HubMode) -> void:
	if bool(st.flag("panel_pal")) and not bool(st.flag("panel_pal_said")):
		st.set_flag("panel_pal_said", true)
		say(b, HubContent.keyed_line("ludlow", "panel_pal"))
		return
	var pos := mode.player().pos() if mode else Vector3.ZERO
	var h: Dictionary = mode.secrets.hint_for(pos) if mode else {}
	say(b, str(h.get("text", "")))


static func _elevator(b: HubBoard, st: HubState, mode: HubMode) -> void:
	if mode and mode.give_carried_to_ludlow(mode.player()):
		b.close()
		return
	if st.has_secret("sec_freight_elevator"):
		say(b, HubContent.keyed_line("ludlow", "elevator_fixed"))
		return
	var have := st.parts().map(func(x): return str(HubLayout.ITEMS[x]["name"]))
	var txt := HubContent.keyed_line("ludlow", "parts_intro")
	if not have.is_empty():
		txt += "  So far I've got %s..." % ", ".join(PackedStringArray(have))
	say(b, txt)


static func _bookie(b: HubBoard) -> void:
	if not b.services().open_bookie():
		say(b, HubContent.keyed_line("teddy", "bookie_absent"))


static func _lab(b: HubBoard) -> void:
	if not b.services().open_lab():
		say(b, HubContent.keyed_line("teddy", "lab_absent"))


static func _tape(b: HubBoard) -> void:
	App.clear_screens()
	HubSparring.play_tape(b.scene)


## Barnaby re-calls your last fight from the profile history ("Say the word and I'll re-call your
## last fight. Louder.").
static func recall_lines(st: HubState) -> Array:
	var lr := st.last_run()
	if lr.is_empty():
		return [HubContent.keyed_line("barnaby", "no_run")]
	var ctx := HubContent.run_context(st)
	var out := [HubContent.keyed_line("barnaby", "recall_intro")]
	var variant := "FIGHT CAMP" if str(lr.get("variant", "")) == "fight_camp" else "OFF THE STREET"
	out.append("%s walks out for %s, %s difficulty%s!" % [str(ctx["fighter"]).to_upper(), variant, str(lr.get("difficulty", "amateur")).capitalize(),
		(", DOSE %d" % int(lr.get("dose", 0))) if int(lr.get("dose", 0)) > 0 else ""])
	if int(lr.get("kos", 0)) > 0:
		out.append("%d KNOCKOUTS on the night! I counted every one!" % int(lr["kos"]))
	match HubState.classify(lr):
		"title":
			out.append("And they TAKE THE BELT! I'm crying! I'm ALWAYS crying!")
		"win":
			out.append("Past Act 1, a boss down, and then %s in Act %d! What a night!" % [str(ctx["boss"]), int(ctx["act"])])
		_:
			out.append("%s ends it in Act %d! A heartbreaker! A STATISTIC!" % [str(ctx["boss"]), int(ctx["act"])])
	return out
