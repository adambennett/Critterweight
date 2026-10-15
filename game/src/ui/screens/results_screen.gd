extends Screen
## Results ("results"), pushed by App.start_match() when a local match ends: the winner card stamps
## in over the finished fight, then per-fighter stats and the round score. Rematch replays the same
## config (MatchFlow.launch), Change fighters returns to the setup that produced the fight (from
## config.ui), Main menu leaves. params: {result: MatchMode.build_result(), config: launch config}

const COLUMNS := [["damage_dealt", "DMG DEALT"], ["damage_taken", "DMG TAKEN"], ["hits", "HITS"], ["blocks", "BLOCKS"],
	["parries", "PARRIES"], ["knockdowns", "KNOCKDOWNS"], ["kos", "KOS"]]

var result := {}
var config := {}
var _rematch: UiButton


func on_enter(p: Dictionary) -> void:
	is_overlay = true
	result = p.get("result", {})
	config = p.get("config", {})
	add_dimmer(0.6)
	var m := UiTheme.margin(UiTheme.SCREEN_MARGIN, 56, 40)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var col := UiTheme.vbox(UiTheme.GAP_M)
	m.add_child(col)
	var banner := UiTheme.panel("PanelPoster")
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner.custom_minimum_size = Vector2(1100, 0)
	col.add_child(banner)
	var bv := UiTheme.vbox(UiTheme.GAP_XS)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(bv)
	var eyebrow := UiTheme.label(_outcome_for_player(), "Eyebrow")
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(eyebrow)
	var winner := UiTheme.label(winner_text(), "Display", true)
	winner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner.add_theme_font_size_override("font_size", UiTheme.size("h1"))
	bv.add_child(winner)
	var sub := UiTheme.label(_score_text(), "H3")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UiTheme.WARM)
	bv.add_child(sub)
	# the stat table scrolls when 8 fighters do not fit (buttons and prompts always stay on screen)
	var ts := ScrollContainer.new()
	ts.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(ts)
	var tc := CenterContainer.new()
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ts.add_child(tc)
	tc.add_child(_table())
	var buttons := UiTheme.hbox(UiTheme.GAP_M)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	var spectating := bool(config.get("spectate", false))
	_rematch = _button(buttons, "Watch again" if spectating else "Rematch", "restart", "rematch", _do_rematch)
	var ui: Dictionary = config.get("ui", {})
	if ui.has("mode"):
		_button(buttons, "Change fighters", "team", "change", _change_fighters)
	_button(buttons, "Main menu", "back", "menu", func() -> void: MatchFlow.quit_to_menu())
	var bar := PromptBar.new()
	bar.set_prompts([{"actions": ["ui_accept"], "text": "Select"}, {"actions": ["ui_cancel"], "text": "Main menu", "call": MatchFlow.quit_to_menu}])
	col.add_child(bar)
	play_intro()
	# stamp once the banner has its final size (pivot = centre)
	get_tree().process_frame.connect(func() -> void: Screen.stamp(banner, 0.05), CONNECT_ONE_SHOT)
	Audio.sfx("ui_accept")


func _button(parent: Container, text: String, icon: String, route: String, cb: Callable) -> UiButton:
	var b := UiButton.new(text, "PrimaryButton" if route == "rematch" else "", icon)
	b.route = route
	b.custom_minimum_size = Vector2(320, 72)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func default_focus() -> Control:
	return _rematch


func winner_team() -> int:
	return int(result.get("winner_team", -1))


func winner_text() -> String:
	var w := winner_team()
	if w < 0:
		return "DRAW!"
	var names: PackedStringArray = PackedStringArray()
	for f in result.get("fighters", []):
		var d: Dictionary = f
		if int(d.get("team", -9)) == w:
			names.append(str(d.get("name", "?")).to_upper())
	if names.is_empty():
		return "TEAM %s WINS!" % UiTheme.team_letter(w)
	return "%s WIN%s!" % [" & ".join(names), "" if names.size() > 1 else "S"]


func _outcome_for_player() -> String:
	var mine := -99
	for f in config.get("fighters", []):
		var d: Dictionary = f
		if str(d.get("kind", "")) == "player":
			mine = int(d.get("team", 0))
	if mine == -99:
		return "RESULT"
	var w := winner_team()
	if w < 0:
		return "DRAW"
	return "VICTORY" if w == mine else "DEFEAT"


func _score_text() -> String:
	var rw: Dictionary = result.get("round_wins", {})
	var parts: PackedStringArray = PackedStringArray()
	var keys := rw.keys()
	keys.sort()
	for t in keys:
		parts.append("%s %d" % [UiTheme.team_letter(int(t)), int(rw[t])])
	var rounds := int(result.get("rounds", 1))
	var time := float(result.get("time", 0.0))
	return "Rounds  %s   ·   %d round%s   ·   %s" % ["  –  ".join(parts), rounds, "" if rounds == 1 else "s", UiTheme.duration_text(time)]


func _table() -> Control:
	var panel := UiTheme.panel("PanelSolid", 22.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var grid := GridContainer.new()
	grid.columns = 3 + COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	panel.add_child(grid)
	for h in ["", "FIGHTER", ""]:
		grid.add_child(UiTheme.label(str(h), "Caption"))
	for c in COLUMNS:
		var l := UiTheme.label(str(c[1]), "Caption")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	var w := winner_team()
	for f in result.get("fighters", []):
		var d: Dictionary = f
		var team := int(d.get("team", 0))
		grid.add_child(TeamChip.new(team, 40))
		var nc := UiTheme.vbox(0)
		var nm := UiTheme.label(str(d.get("name", "?")).to_upper(), "Value")
		nc.add_child(nm)
		var cid := str(d.get("creature", ""))
		var cname := str(Content.get_entry("creatures", cid).get("name", cid))
		var state := "KO'd" if bool(d.get("out", false)) else "%d HP left" % ceili(float(d.get("health", 0.0)))
		nc.add_child(UiTheme.label("%s  ·  %s" % [cname, state], "Caption"))
		grid.add_child(nc)
		if team == w:
			var wr := UiTheme.hbox(6)
			wr.add_child(UiIcons.rect("trophy", 30, UiTheme.GOLD_HI))
			wr.add_child(UiTheme.label("WINNER", "ValueGold"))
			grid.add_child(wr)
		else:
			grid.add_child(UiTheme.label("", "Caption"))
		var st: Dictionary = d.get("stats", {})
		for c in COLUMNS:
			var v = st.get(str(c[0]), 0)
			var l := UiTheme.label(str(roundi(float(v))), "Value")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
	return panel


func _do_rematch() -> void:
	if config.is_empty():
		MatchFlow.quit_to_menu()
		return
	MatchFlow.launch(config)


func _change_fighters() -> void:
	var ui: Dictionary = config.get("ui", {})
	var m := str(ui.get("mode", ""))
	var setup: Dictionary = ui.get("setup", {})
	MatchFlow.quit_to_menu()
	match m:
		"quick":
			App.push("character_select", {"mode": "quick"})
		"spectate":
			App.push("spectate", {"setup": setup})
		"versus", "practice":
			App.push("versus_setup", {"mode": m, "setup": setup})


func on_back() -> bool:
	MatchFlow.quit_to_menu()
	return true
