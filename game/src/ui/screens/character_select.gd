extends Screen
## Character select. Cards for every playable creature (Content.playable_creatures(), so mods add
## fighters automatically) plus a Random card; the poster on the right shows the focused fighter:
## name, epithet, element icon + name + status, weight class, stat bars, playstyle and kit.
## params: {mode: "quick" | "pick", title, current, allow_random, on_pick: Callable(id)}
##  - quick: picking starts a 1v1 against a random opponent at the default bot tier (Quick Fight).
##  - pick:  returns the id to on_pick (versus/spectate setup) and closes.
## Creature JSON fields used for presentation (all optional): name, title (epithet), element,
## stats {health, walk_speed, stamina, poise, power}, blurb (playstyle), tags, abilities.*.name, juice.name.

## Ranges for stat bars (ROSTER.md weight-class table spans these).
const STAT_RANGES := {"health": [60.0, 150.0], "walk_speed": [2.2, 4.6], "stamina": [80.0, 115.0], "poise": [30.0, 100.0], "power": [0.7, 1.3]}
const STAT_LABELS := {"health": "Health", "walk_speed": "Speed", "stamina": "Stamina", "poise": "Poise", "power": "Power"}
const CLASSES := [[65.0, "Pipsqueak"], [110.0, "Scrapper"], [145.0, "Lunker"], [9999.0, "Absolute Unit"]]

var mode := "quick"
var _cards: Array[CreatureCard] = []
var _grid: GridContainer
var _scroll: FocusScroll
var _detail: VBoxContainer
var _on_pick: Callable
var _current := ""


func on_enter(p: Dictionary) -> void:
	mode = str(p.get("mode", "quick"))
	_on_pick = p.get("on_pick", Callable())
	_current = str(p.get("current", ""))
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.8)
	var eyebrow := "Quick fight" if mode == "quick" else str(p.get("title", "Fighter"))
	var f := build_frame(eyebrow, "Choose your critter")
	(f["prompts"] as PromptBar).set_prompts([{"actions": ["ui_accept"], "text": "Choose"},
		{"actions": ["ui_alt"], "text": "Random", "call": func() -> void: _choose("random")},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back}])
	var body: VBoxContainer = f["body"]
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	_scroll = FocusScroll.new(14)
	_scroll.size_flags_stretch_ratio = 1.25
	cols.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 22)
	_grid.add_theme_constant_override("v_separation", 22)
	_scroll.content.add_child(_grid)
	var ids := Content.playable_creatures()
	for id in ids:
		_add_card(str(id))
	if not ids.is_empty() and (bool(p.get("allow_random", true)) or mode == "quick"):
		_add_card("random")
	var poster := UiTheme.panel("PanelPoster")
	poster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	poster.custom_minimum_size = Vector2(600, 0)
	cols.add_child(poster)
	# the tale of the tape scrolls inside the poster so long kits never push the footer off screen
	var ds := ScrollContainer.new()
	ds.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ds.size_flags_vertical = Control.SIZE_EXPAND_FILL
	poster.add_child(ds)
	_detail = UiTheme.vbox(UiTheme.GAP_S)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.add_child(_detail)
	if ids.is_empty():
		_detail.add_child(UiTheme.label("No playable fighters were found in the loaded content.", "Danger", true))
	play_intro()


func _add_card(id: String) -> void:
	var c := CreatureCard.new(id)
	c.chosen.connect(_choose)
	c.focus_entered.connect(_show_detail.bind(id))
	if id == _current:
		c.set_selected(true)
	_grid.add_child(c)
	_cards.append(c)


func default_focus() -> Control:
	for c in _cards:
		if c.creature_id == _current:
			return c
	return _cards[0] if not _cards.is_empty() else null


func cards() -> Array[CreatureCard]:
	return _cards


static func weight_class(d: Dictionary) -> String:
	var body = d.get("body", {})
	var mass := 0.0
	if typeof(body) == TYPE_DICTIONARY:
		for s in (body as Dictionary).get("segments", []):
			mass += float((s as Dictionary).get("mass", 0.0))
	if mass <= 0.0:
		return ""
	for c in CLASSES:
		if mass <= float(c[0]):
			return "%s · %d kg" % [str(c[1]), roundi(mass)]
	return ""


func _show_detail(id: String) -> void:
	for ch in _detail.get_children():
		ch.queue_free()
	if id == "random":
		_detail.add_child(UiTheme.label("THE FIGHTER IS", "Eyebrow"))
		_detail.add_child(UiTheme.label("RANDOM", "H1"))
		_detail.add_child(UiTheme.label("Anyone on the roster could step through the door. You'll find out at the bell.", "Body", true))
		return
	var d := Content.get_entry("creatures", id)
	var defs := CreatureDef.new()
	_detail.add_child(UiTheme.label("TALE OF THE TAPE", "Eyebrow"))
	_detail.add_child(UiTheme.label(str(d.get("name", id)).to_upper(), "H1"))
	var title := str(d.get("title", ""))
	if title != "":
		var t := UiTheme.label(title, "H3")
		t.add_theme_color_override("font_color", UiTheme.WARM)
		_detail.add_child(t)
	var el := str(d.get("element", ""))
	_detail.add_child(UiIcons.element_badge(el, 46, true))
	var wc := weight_class(d)
	if wc != "":
		var wl := UiTheme.label(wc.to_upper(), "Eyebrow")
		wl.add_theme_color_override("font_color", UiTheme.MUTED)
		_detail.add_child(wl)
	_detail.add_child(UiTheme.spacer(false, 6))
	var st: Dictionary = d.get("stats", {})
	for k in ["health", "walk_speed", "stamina", "poise", "power"]:
		var v := float(st.get(k, defs.stats.get(k, 1.0)))
		var rg: Array = STAT_RANGES[k]
		var frac := (v - float(rg[0])) / (float(rg[1]) - float(rg[0]))
		var txt := ("%.1f m/s" % v) if k == "walk_speed" else (("%d%%" % roundi(v * 100.0)) if k == "power" else "%d" % roundi(v))
		_detail.add_child(StatBar.new(str(STAT_LABELS[k]), frac, txt, UiTheme.element_color(el) if el != "" else UiTheme.GOLD))
	_detail.add_child(UiTheme.spacer(false, 6))
	var blurb := str(d.get("blurb", d.get("playstyle", d.get("description", ""))))
	if blurb == "":
		var tags: Array = d.get("tags", [])
		blurb = "Engine test fighter: a plain biped used to tune the physics and the combat." if tags.has("dev") else "No scouting report on this one yet."
	_detail.add_child(UiTheme.label("PLAYSTYLE", "Eyebrow"))
	_detail.add_child(UiTheme.label(blurb, "Body", true))
	var kit := _kit_text(d)
	if kit != "":
		_detail.add_child(UiTheme.label("KIT", "Eyebrow"))
		_detail.add_child(UiTheme.label(kit, "Caption", true))


func _kit_text(d: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var ab: Dictionary = d.get("abilities", {})
	for slot in ["ability1", "ability2"]:
		if ab.has(slot) and typeof(ab[slot]) == TYPE_DICTIONARY:
			parts.append("%s: %s" % ["LB" if slot == "ability1" else "RB", str((ab[slot] as Dictionary).get("name", slot))])
	var j = d.get("juice", {})
	if typeof(j) == TYPE_DICTIONARY and (j as Dictionary).has("name"):
		parts.append("JUICE: %s" % str((j as Dictionary)["name"]))
	return "   ·   ".join(parts)


func _choose(id: String) -> void:
	var ids := Content.playable_creatures()
	if ids.is_empty():
		Audio.sfx("ui_error")
		return
	if mode == "pick":
		var cb := _on_pick
		App.pop()
		if cb.is_valid():
			cb.call(id)
		return
	# quick fight: you vs a random opponent at the default tier, standard duel in a random arena
	var mine := FighterSelection.resolve(id, ids)
	var foe := str(ids[randi() % ids.size()])
	var arenas := Content.ids("arenas")
	var arena := str(arenas[randi() % arenas.size()]) if not arenas.is_empty() else "the_gullet"
	var foe_name := str(Content.get_entry("creatures", foe).get("name", foe))
	if foe_name == Profiles.player_name():
		foe_name += " II"
	var tier := BotTiers.default_tier()
	MatchFlow.launch({"arena": arena, "rules": "duel",
		"fighters": [{"creature": mine, "team": 0, "kind": "player", "name": Profiles.player_name()},
			{"creature": foe, "team": 1, "kind": "bot", "difficulty": BotTiers.brain_tier(tier), "name": foe_name}],
		"ui": {"mode": "quick", "tier": tier}})


func _unhandled_input(event: InputEvent) -> void:
	if is_top() and event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		_choose("random")
		return
	super(event)
