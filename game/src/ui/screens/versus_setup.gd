class_name VersusSetup
extends Screen
## Local match setup for Versus, Practice and Spectate (spectate_setup.gd sets the mode).
## One vertical list (predictable controller focus): match rows (rules preset, arena), then a group
## per fighter (fighter pick, controller kind, team, bot skill tier, remove), then Add / Start. A
## "fight card" poster on the right summarises the line-up and shows validation errors.
## Up to 8 fighters. Bot skill tiers come from BotTiers (the single tier -> BotBrain mapping).
## params: {mode: versus|practice|spectate, setup: Dictionary (restore), fighters: int (initial count)}
## Launches through MatchFlow.launch(); the config carries ui.setup so Results can come back here.

const MAX_FIGHTERS := 8
const PRACTICE_RULES := {"id": "practice", "name": "Practice", "mode": "standard", "rounds": 1, "round_time": 0,
	"lives": -1, "respawn": true, "respawn_delay": 2.0,
	"description": "No clock and endless respawns: knocked-out fighters come back after two seconds."}

var mode := "versus"
var setup := {}
var _scroll: FocusScroll
var _poster: VBoxContainer
var _error: Label
var _help: HelpPanel
var _start: UiButton
var _add: UiButton
var _pick_rows: Array[PickRow] = []
var _bar: PromptBar


func on_enter(p: Dictionary) -> void:
	mode = str(p.get("mode", "versus"))
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.75)
	var restored: Dictionary = p.get("setup", {})
	setup = restored.duplicate(true) if not restored.is_empty() else _default_setup(int(p.get("fighters", 2)))
	_sanitize()
	var titles := {"versus": ["Local", "Versus"], "practice": ["Training", "Practice"], "spectate": ["Bot fights", "Spectate"]}
	var tt: Array = titles.get(mode, titles["versus"])
	var f := build_frame(str(tt[0]), str(tt[1]))
	var body: VBoxContainer = f["body"]
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
	right.custom_minimum_size = Vector2(520, 0)
	cols.add_child(right)
	var poster := UiTheme.panel("PanelPoster")
	poster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(poster)
	# the card scrolls (mouse wheel) so 8 fighters never push the footer off screen
	var ps := ScrollContainer.new()
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	poster.add_child(ps)
	_poster = UiTheme.vbox(UiTheme.GAP_S)
	_poster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ps.add_child(_poster)
	_help = HelpPanel.new(_scroll)
	_help.size_flags_vertical = Control.SIZE_SHRINK_END
	_help.custom_minimum_size = Vector2(0, 190)
	right.add_child(_help)
	_bar = f["prompts"]
	_bar.set_prompts([{"actions": ["ui_accept"], "text": "Select"}, {"actions": ["ui_left", "ui_right"], "text": "Change"},
		{"actions": ["ui_alt"], "text": "Start fight" if mode != "spectate" else "Start watching", "call": _try_start},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back}])
	_rebuild()
	play_intro()


func default_focus() -> Control:
	var fs := _scroll.focusables()
	return fs[0] if not fs.is_empty() else null


# --- data --------------------------------------------------------------------------------------

func _playable() -> Array:
	var ids := Content.playable_creatures()
	return ids if not ids.is_empty() else ["dev_biped"]


func _default_setup(count: int) -> Dictionary:
	var ids := _playable()
	var slots := []
	var n := clampi(count, 2, MAX_FIGHTERS)
	for i in n:
		var cid := str(ids[i % ids.size()])
		match mode:
			"spectate":
				slots.append({"kind": "bot", "creature": cid, "team": i % 2, "tier": "contender" if i == 0 else BotTiers.DEFAULT})
			"practice":
				slots.append({"kind": "player" if i == 0 else "dummy", "creature": cid, "team": i % 2, "tier": "punching_bag"})
			_:
				slots.append({"kind": "player" if i == 0 else "bot", "creature": cid, "team": i % 2, "tier": BotTiers.default_tier()})
	var rules := "duel" if Content.get_entry("rules", "duel").size() > 0 else (str(Content.ids("rules")[0]) if not Content.ids("rules").is_empty() else "duel")
	if n > 2 and Content.get_entry("rules", "free_for_all").size() > 0:
		rules = "free_for_all"
	var arenas := Content.ids("arenas")
	return {"rules": rules, "arena": "the_gullet" if arenas.has("the_gullet") or arenas.is_empty() else str(arenas[0]), "slots": slots}


func _sanitize() -> void:
	var slots: Array = setup.get("slots", [])
	if slots.size() < 2:
		setup = _default_setup(2)
	var known := _playable()
	for s in setup["slots"]:
		var d: Dictionary = s
		if str(d.get("creature", "")) != "random" and not known.has(str(d.get("creature", ""))):
			d["creature"] = str(known[0])
		if not d.has("tier"):
			d["tier"] = BotTiers.DEFAULT
		if mode == "spectate":
			d["kind"] = "bot"


func rules_dict() -> Dictionary:
	if mode == "practice":
		return PRACTICE_RULES
	return Content.get_entry("rules", str(setup.get("rules", "duel")))


func is_ffa() -> bool:
	var r := rules_dict()
	return str(r.get("format", "")) == "ffa" or int(r.get("teams", 2)) == 0


func team_count() -> int:
	return clampi(maxi(2, int(rules_dict().get("teams", 2))), 2, 4)


func slots() -> Array:
	return setup["slots"]


func _creature_name(id: String) -> String:
	if id == "random":
		return "Random"
	return str(Content.get_entry("creatures", id).get("name", id)).to_upper()


func _creature_sub(id: String) -> String:
	if id == "random":
		return "Picked when the fight starts"
	var d := Content.get_entry("creatures", id)
	var el := str(d.get("element", ""))
	var t := str(d.get("title", ""))
	return ("%s · %s" % [t, Elements.display_name(el)]) if el != "" and t != "" else (t if t != "" else Elements.display_name(el))


func _creature_icon(id: String) -> Texture2D:
	if id == "random":
		return UiIcons.tex("random")
	var el := str(Content.get_entry("creatures", id).get("element", ""))
	return UiIcons.element_tex(el) if el != "" else UiIcons.tex("fight")


# --- list --------------------------------------------------------------------------------------

func _rebuild(focus_key := "") -> void:
	_scroll.clear()
	_pick_rows.clear()
	var c := _scroll.content
	c.add_child(UiTheme.label("MATCH", "Eyebrow"))
	if mode != "practice":
		var rule_ids := Content.ids("rules")
		var rule_names: Array[String] = []
		for id in rule_ids:
			rule_names.append(str(Content.get_entry("rules", str(id)).get("name", id)))
		var rr := OptionRow.new("Rules")
		rr.setup(rule_ids, rule_names, setup["rules"])
		rr.set_help("Rules preset", str(rules_dict().get("description", "")), "Presets come from the content packages (and enabled mods).")
		rr.set_meta("focus_key", "rules")
		rr.value_changed.connect(func(v) -> void:
			setup["rules"] = str(v)
			_rebuild("rules"))
		c.add_child(rr)
	var arena_ids := Content.ids("arenas")
	if arena_ids.is_empty():
		arena_ids = ["the_gullet"]
	var arena_names: Array[String] = []
	for id in arena_ids:
		arena_names.append(str(Content.get_entry("arenas", str(id)).get("name", str(id).capitalize())))
	var ar := OptionRow.new("Arena")
	ar.setup(arena_ids, arena_names, setup["arena"])
	ar.set_help("Arena", "Where the fight happens. Custom arenas from the arena editor and mods appear here too.")
	ar.set_meta("focus_key", "arena")
	ar.value_changed.connect(func(v) -> void:
		var had := not _looks().is_empty()
		setup["arena"] = str(v)
		setup["look"] = ""
		if had or not _looks().is_empty():
			_rebuild("arena")
		else:
			_update_poster())
	c.add_child(ar)
	# hidden arena looks the profile unlocked (the Cannery's Pier Night for Chum Rush): only shown
	# when the chosen arena and rules have one
	var looks := _looks()
	if not looks.is_empty():
		var look_ids: Array = [""]
		var look_names: Array[String] = ["Standard"]
		for lk in looks:
			look_ids.append(str(lk["id"]))
			look_names.append(str(lk["label"]))
		var lr := OptionRow.new("Look")
		lr.setup(look_ids, look_names, str(setup.get("look", "")) if look_ids.has(str(setup.get("look", ""))) else "")
		lr.set_help("Look", "An arena look you unlocked in the Cannery. Lighting and dressing only.")
		lr.set_meta("focus_key", "look")
		lr.value_changed.connect(func(v) -> void: setup["look"] = str(v))
		c.add_child(lr)
	var sl := slots()
	for i in sl.size():
		_add_slot_rows(c, i)
	c.add_child(UiTheme.spacer(false, 6))
	if sl.size() < MAX_FIGHTERS:
		_add = UiButton.new("Add a bot" if mode != "practice" else "Add a sparring partner", "", "plus")
		_add.set_help("Add a fighter", "Adds another fighter (up to %d). Free-for-all and team rules suit 3+ fighters." % MAX_FIGHTERS)
		_add.set_meta("focus_key", "add")
		_add.pressed.connect(_add_slot)
		c.add_child(_add)
	else:
		_add = null
	_start = UiButton.new("Start watching" if mode == "spectate" else "Start fight", "PrimaryButton", "fight")
	_start.custom_minimum_size = Vector2(0, 76)
	_start.set_help("Start", "Checks the line-up and starts the fight. Shortcut: Y / R.")
	_start.set_meta("focus_key", "start")
	_start.pressed.connect(_try_start)
	c.add_child(_start)
	_scroll.wrap_focus.call_deferred()
	_update_poster()
	if focus_key != "":
		_focus_key.call_deferred(focus_key)


func _focus_key(key: String) -> void:
	for f in _scroll.focusables():
		if f.has_meta("focus_key") and str(f.get_meta("focus_key")) == key:
			f.grab_focus()
			return
	ensure_focus()


func _slot_title(i: int) -> String:
	var s: Dictionary = slots()[i]
	match str(s["kind"]):
		"player":
			return "FIGHTER %d  ·  YOU (%s)" % [i + 1, Profiles.player_name().to_upper()]
		"dummy":
			return "FIGHTER %d  ·  TRAINING DUMMY" % (i + 1)
	return "FIGHTER %d  ·  BOT" % (i + 1)


func _add_slot_rows(c: VBoxContainer, i: int) -> void:
	var s: Dictionary = slots()[i]
	c.add_child(UiTheme.spacer(false, 4))
	var head := UiTheme.hbox(UiTheme.GAP_S)
	head.add_child(TeamChip.new(-1 if is_ffa() else int(s["team"]), 34))
	head.add_child(UiTheme.label(_slot_title(i), "Eyebrow"))
	c.add_child(head)
	var pr := PickRow.new("Fighter")
	pr.set_choice(_creature_name(str(s["creature"])), _creature_sub(str(s["creature"])), _creature_icon(str(s["creature"])))
	pr.set_help("Fighter %d" % (i + 1), "Choose who fights in this corner. Opens the character select.")
	pr.set_meta("focus_key", "pick%d" % i)
	pr.activated.connect(_pick_creature.bind(i))
	c.add_child(pr)
	_pick_rows.append(pr)
	if i > 0 and mode == "practice":
		var kr := OptionRow.new("Controlled by")
		kr.setup(["dummy", "bot"], ["Training dummy", "Bot"], s["kind"])
		kr.set_help("Controlled by", "A training dummy stands still and never attacks. A bot fights back at the chosen skill tier.")
		kr.set_meta("focus_key", "kind%d" % i)
		kr.value_changed.connect(func(v) -> void:
			s["kind"] = str(v)
			_rebuild("kind%d" % i))
		c.add_child(kr)
	if not is_ffa():
		var tr := OptionRow.new("Team")
		var team_ids := []
		var team_names: Array[String] = []
		for t in team_count():
			team_ids.append(t)
			team_names.append("Team %s" % UiTheme.team_letter(t))
		tr.setup(team_ids, team_names, int(s["team"]) % team_count())
		tr.set_help("Team", "Fighters on the same team are allies. Teams are shown by letter and colour.")
		tr.set_meta("focus_key", "team%d" % i)
		tr.value_changed.connect(func(v) -> void:
			s["team"] = int(v)
			_rebuild("team%d" % i))
		c.add_child(tr)
	if str(s["kind"]) == "bot":
		var sr := OptionRow.new("Skill")
		sr.setup(BotTiers.ids(), BotTiers.names(), s["tier"])
		sr.set_help("Bot skill: %s" % BotTiers.display_name(str(s["tier"])), BotTiers.blurb(str(s["tier"])))
		sr.set_meta("focus_key", "tier%d" % i)
		sr.value_changed.connect(func(v) -> void:
			s["tier"] = str(v)
			sr.set_help("Bot skill: %s" % BotTiers.display_name(str(v)), BotTiers.blurb(str(v)))
			_help.show_help(sr.help_title, sr.help_text)
			_update_poster())
		c.add_child(sr)
	if slots().size() > 2 and str(s["kind"]) != "player":
		var rm := UiButton.new("Remove fighter %d" % (i + 1), "", "close")
		rm.set_help("Remove fighter", "Takes this fighter off the card.")
		rm.set_meta("focus_key", "remove%d" % i)
		rm.pressed.connect(_remove_slot.bind(i))
		c.add_child(rm)


func _pick_creature(i: int) -> void:
	var s: Dictionary = slots()[i]
	App.push("character_select", {"mode": "pick", "title": "Fighter %d" % (i + 1), "current": str(s["creature"]),
		"allow_random": true, "on_pick": func(id: String) -> void:
			s["creature"] = id
			if i < _pick_rows.size():
				_pick_rows[i].set_choice(_creature_name(id), _creature_sub(id), _creature_icon(id))
			_update_poster()})


func _add_slot() -> void:
	var sl := slots()
	if sl.size() >= MAX_FIGHTERS:
		return
	var ids := _playable()
	var teams := team_count()
	sl.append({"kind": "bot" if mode != "practice" else "dummy", "creature": str(ids[sl.size() % ids.size()]),
		"team": sl.size() % teams, "tier": BotTiers.default_tier() if mode != "spectate" else BotTiers.DEFAULT})
	_rebuild("pick%d" % (sl.size() - 1))


func _remove_slot(i: int) -> void:
	var sl := slots()
	if sl.size() <= 2 or str((sl[i] as Dictionary)["kind"]) == "player":
		Audio.sfx("ui_error")
		return
	sl.remove_at(i)
	_rebuild("pick%d" % mini(i, sl.size() - 1))


# --- poster ------------------------------------------------------------------------------------

func _update_poster() -> void:
	for ch in _poster.get_children():
		ch.queue_free()
	_poster.add_child(UiTheme.label("TONIGHT'S CARD", "Eyebrow"))
	var r := rules_dict()
	_poster.add_child(UiTheme.label(str(r.get("name", "Rules")).to_upper(), "H2", true))
	var desc := UiTheme.label(str(r.get("description", "")), "Caption", true)
	_poster.add_child(desc)
	var arena_name := str(Content.get_entry("arenas", str(setup["arena"])).get("name", str(setup["arena"]).capitalize()))
	var ar := UiTheme.hbox(UiTheme.GAP_S)
	ar.add_child(UiIcons.rect("arena", 30, UiTheme.MUTED))
	ar.add_child(UiTheme.label(arena_name, "BodyStrong"))
	_poster.add_child(ar)
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.GOLD, 0.45)
	rule.custom_minimum_size = Vector2(0, 3)
	_poster.add_child(rule)
	var sl := slots()
	for i in sl.size():
		var s: Dictionary = sl[i]
		var row := UiTheme.hbox(UiTheme.GAP_S)
		row.add_child(TeamChip.new(-1 if is_ffa() else int(s["team"]), 36))
		var ic := TextureRect.new()
		ic.texture = _creature_icon(str(s["creature"]))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(36, 36)
		row.add_child(ic)
		var nm := UiTheme.label(_creature_name(str(s["creature"])), "Value")
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(nm)
		var who := "YOU" if str(s["kind"]) == "player" else ("DUMMY" if str(s["kind"]) == "dummy" else BotTiers.display_name(str(s["tier"])).to_upper())
		row.add_child(UiTheme.label(who, "Caption"))
		_poster.add_child(row)
	_error = UiTheme.label("", "Danger", true)
	_error.visible = false
	_poster.add_child(_error)


# --- start -------------------------------------------------------------------------------------

func validate() -> String:
	var sl := slots()
	if sl.size() < 2:
		return "Add at least one more fighter."
	if not is_ffa():
		var teams := {}
		for s in sl:
			teams[int((s as Dictionary)["team"])] = true
		if teams.size() < 2:
			return "Everyone is on Team %s. Put at least one fighter on another team." % UiTheme.team_letter(int((sl[0] as Dictionary)["team"]))
	if mode == "spectate":
		for s in sl:
			if str((s as Dictionary)["kind"]) != "bot":
				return "Spectate needs every fighter to be a bot."
	return ""


func build_config() -> Dictionary:
	var fighters := []
	var used := {}
	var ids := _playable()
	var ffa := is_ffa()
	for i in slots().size():
		var s: Dictionary = slots()[i]
		var cid := str(s["creature"])
		if cid == "random":
			cid = str(ids[randi() % ids.size()])
		var kind := str(s["kind"])
		var nm := Profiles.player_name() if kind == "player" else str(Content.get_entry("creatures", cid).get("name", cid))
		var base := nm
		var n := 2
		while used.has(nm):
			nm = "%s %d" % [base, n]
			n += 1
		used[nm] = true
		var fd := {"creature": cid, "team": i if ffa else int(s["team"]), "kind": kind, "name": nm}
		if kind == "bot":
			fd["difficulty"] = BotTiers.brain_tier(str(s["tier"]))
		fighters.append(fd)
	var rules = str(setup["rules"])
	var extra := {}
	if mode == "practice":
		# the real Practice mode: dummy behaviours, recording/replay, hit telemetry, no KOs
		var pr: Dictionary = Content.get_entry("rules", "practice").duplicate(true)
		if pr.is_empty():
			pr = PRACTICE_RULES.duplicate(true)
		if fighters.size() > 1 and str(fighters[1]["kind"]) == "bot":
			pr["dummy_behavior"] = "bot"
			pr["dummy_tier"] = str(fighters[1].get("difficulty", "regular"))
		rules = pr
		extra = {"overlay_script": "res://src/ui/practice_overlay.gd", "no_record": true}
	var cfg := {"arena": str(setup["arena"]), "rules": rules, "fighters": fighters, "spectate": mode == "spectate",
		"ui": {"mode": mode, "setup": setup.duplicate(true)}}
	var look := str(setup.get("look", ""))
	if look != "" and _looks().any(func(lk): return str(lk["id"]) == look):
		cfg["context"] = {"variant": look}
	cfg.merge(extra, true)
	return cfg


## Unlocked hidden looks of the chosen arena for the chosen rules' mode ([{id, label}]).
func _looks() -> Array:
	if mode == "practice":
		return []
	var a := Content.arena(str(setup.get("arena", "")))
	var m := str(rules_dict().get("mode", "standard"))
	return ArenaVariants.unlocked_extras(a, Profiles.current, m) if a != null else []


func _try_start() -> void:
	var err := validate()
	if err != "":
		Audio.sfx("ui_error")
		if _error:
			_error.text = err
			_error.visible = true
		UiNav.toast(err, "error")
		return
	Audio.sfx("ui_accept")
	MatchFlow.launch(build_config())


func _unhandled_input(event: InputEvent) -> void:
	if is_top() and event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		_try_start()
		return
	super(event)
