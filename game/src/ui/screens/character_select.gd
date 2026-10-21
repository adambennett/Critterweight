extends Screen
## Character select. Cards for every playable creature (Content.playable_creatures(), so mods add
## fighters automatically) plus a Random card; the poster on the right shows the focused fighter:
## name, epithet, element icon + name + status, weight class, stat bars, playstyle and kit.
## params: {mode: "quick" | "pick", title, current, allow_random, on_pick: Callable(id),
##          combat: "moves" | "classic" (default "moves"), player: bool (default: quick mode)}
##  - quick: picking starts a 1v1 against a random opponent at the default bot tier (Quick Fight),
##    the player bringing their saved loadout for that fighter.
##  - pick:  returns the id to on_pick (versus/spectate setup) and closes.
## The poster (FighterInfo) follows `combat`: in Movesets the fighter's moves (the player's saved
## loadout when `player`, else the recommended default), in Classic the v0.9.17 kit.
## Creature JSON fields used for presentation (all optional): name, title (epithet), element,
## stats {health, walk_speed, stamina, poise, power}, blurb (playstyle), tags, abilities.*.name, juice.name.

var mode := "quick"
var _cards: Array[CreatureCard] = []
var _grid: GridContainer
var _scroll: FocusScroll
var _detail: VBoxContainer
var _on_pick: Callable
var _current := ""
var _fighter_info: FighterInfo


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
	_fighter_info = FighterInfo.new()
	_fighter_info.combat = "classic" if str(p.get("combat", "moves")) == "classic" else "moves"
	_fighter_info.saved_loadouts = bool(p.get("player", mode == "quick"))
	poster.add_child(_fighter_info)
	_detail = _fighter_info.content
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
	return FighterInfo.weight_class(d)


func _show_detail(id: String) -> void:
	_fighter_info.show_fighter(id)


func right_stick_scroll_target() -> Control:
	return _fighter_info


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
		"fighters": [{"creature": mine, "team": 0, "kind": "player", "name": Profiles.player_name(), "loadout": MovesUi.saved_loadout(mine)},
			{"creature": foe, "team": 1, "kind": "bot", "difficulty": BotTiers.brain_tier(tier), "name": foe_name}],
		"ui": {"mode": "quick", "tier": tier}})


func _unhandled_input(event: InputEvent) -> void:
	if is_top() and event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		_choose("random")
		return
	super(event)
