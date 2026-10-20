extends Screen
## Pause ("pause"). Offline: freezes the match (simulation + physics, MatchFlow.set_paused) until
## it closes. Online: nothing pauses — the menu says so and the fight keeps running behind it.
## Resume · Restart fight (offline) · Settings · Controls · Quit to main menu (confirmed).
## In a career bout (the match scene carries meta "career_flow", design contract D4) there is no
## Restart, and quitting is pulling out of the fight: the confirmation says so ("No purse,
## popularity -4.") and the career's withdrawal is applied before returning to the main menu.
## A quick reference shows the core actions with the CURRENT bindings for the active device.
## Start / Esc / B close it. params: {notice: String} (e.g. "Controller disconnected ...").

const QUICK_REF := [["move_up", "Move", "left_stick"], ["light", "Light attack", ""], ["heavy", "Heavy (hold to charge)", ""],
	["guard", "Guard (tap to parry)", ""], ["dodge", "Dodge", ""], ["grab", "Grab / throw", ""], ["ability1", "Ability 1", ""],
	["ability2", "Ability 2", ""], ["juice", "JUICE", ""], ["taunt", "Taunt", ""], ["target", "Switch target", ""]]

var _online := false
var _career: CareerFlow = null       ## the career bout's flow (null outside career bouts)
var _resume: UiButton
var _ref_box: VBoxContainer


func on_enter(p: Dictionary) -> void:
	is_overlay = true
	_online = MatchFlow.is_online()
	_career = CareerFlow.of_scene(MatchFlow.current_match()) if not _online else null
	if not _online:
		MatchFlow.set_paused(true)
	add_dimmer(0.66)
	var m := UiTheme.margin(UiTheme.SCREEN_MARGIN, 64, 40)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var outer := UiTheme.vbox(UiTheme.GAP_M)
	m.add_child(outer)
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)
	var left := UiTheme.panel("PanelSolid")
	left.custom_minimum_size = Vector2(640, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(left)
	var lv := UiTheme.vbox(UiTheme.GAP_S)
	left.add_child(lv)
	lv.add_child(UiTheme.label("ONLINE MATCH" if _online else "MATCH PAUSED", "Eyebrow"))
	lv.add_child(UiTheme.label("MENU" if _online else "PAUSED", "H1"))
	var notice := str(p.get("notice", ""))
	var party_fight := _online and OnlineFlow.coop != null and OnlineFlow.coop.in_fight()
	if party_fight:
		notice = ("%s\n" % notice if notice != "" else "") + "Co-op fight: the menu does not pause it. A ref timeout freezes the fight for everyone (%d s of yours left this run)." % int(OnlineFlow.coop.session.my_pause_budget())
	elif _online:
		notice = ("%s\n" % notice if notice != "" else "") + "Online matches can't be paused — the fight keeps going while this menu is open."
	if notice != "":
		var banner := UiTheme.panel("PanelBanner")
		var br := UiTheme.hbox(UiTheme.GAP_S)
		br.add_child(UiIcons.rect("warning", 36, UiTheme.WARNING))
		var nl := UiTheme.label(notice, "BodyStrong", true)
		nl.custom_minimum_size = Vector2(500, 0)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		br.add_child(nl)
		banner.add_child(br)
		lv.add_child(banner)
	lv.add_child(UiTheme.spacer(false, 8))
	_resume = _button(lv, "Resume", "fight", "resume", _resume_match)
	if party_fight:
		var pv: Dictionary = OnlineFlow.coop.session.pause_view()
		if bool(pv.get("paused", false)) and str(pv.get("by", "")) == OnlineFlow.coop.me:
			_button(lv, "End my ref timeout", "fight", "timeout", _end_timeout)
		elif not bool(pv.get("paused", false)):
			var tb := _button(lv, "Call a ref timeout", "info", "timeout", _call_timeout)
			tb.disabled = OnlineFlow.coop.session.my_pause_budget() <= 0.0
		if OnlineFlow.coop.is_host():
			_button(lv, "Forfeit this fight", "close", "forfeit", _ask_forfeit)
	if not _online and not MatchFlow.last_config.is_empty() and _career == null:
		_button(lv, "Restart fight", "restart", "restart", _ask_restart)
	_button(lv, "Settings", "settings", "settings", func() -> void: App.push("settings", {"in_game": true}))
	_button(lv, "Controls", "gamepad", "controls", func() -> void: App.push("controls", {"in_game": true}))
	_button(lv, "Quit to main menu", "quit", "quit", _ask_quit)
	var buttons: Array[Control] = []
	for c in lv.get_children():
		if c is UiButton:
			buttons.append(c)
	for i in buttons.size():
		var b := buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[posmod(i - 1, buttons.size())])
		b.focus_neighbor_bottom = b.get_path_to(buttons[posmod(i + 1, buttons.size())])
	cols.add_child(UiTheme.spacer())
	var ref := UiTheme.panel("PanelHelp")
	ref.custom_minimum_size = Vector2(560, 0)
	ref.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(ref)
	_ref_box = UiTheme.vbox(UiTheme.GAP_S)
	ref.add_child(_ref_box)
	_build_reference()
	Controls.device_changed.connect(_on_device_changed)
	var bar := PromptBar.new()
	bar.set_prompts([{"actions": ["ui_accept"], "text": "Select"}, {"actions": ["ui_cancel"], "text": "Resume", "call": _resume_match}])
	outer.add_child(bar)
	play_intro()


func _button(parent: Container, text: String, icon: String, route: String, cb: Callable) -> UiButton:
	var b := UiButton.new(text, "SubItem", icon)
	b.route = route
	b.custom_minimum_size = Vector2(560, 70)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _on_device_changed(_kind: String) -> void:
	_build_reference()


func _build_reference() -> void:
	for c in _ref_box.get_children():
		c.queue_free()
	_ref_box.add_child(UiTheme.label("CONTROLS", "Eyebrow"))
	for e in QUICK_REF:
		var row := UiTheme.hbox(UiTheme.GAP_M)
		var l := UiTheme.label(str(e[1]), "Body")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var ev := PromptGlyph.event_for(str(e[0]))
		if str(e[2]) == "left_stick" and PromptGlyph.wants_pad():
			var jm := InputEventJoypadMotion.new()
			jm.axis = JOY_AXIS_LEFT_X
			jm.axis_value = 0.0
			ev = jm
		var g := PromptGlyph.new(ev, "", 38.0)
		g.tooltip_text = Controls.prompt_for(str(e[0]))
		row.add_child(g)
		_ref_box.add_child(row)


func default_focus() -> Control:
	return _resume


func _resume_match() -> void:
	if is_top():
		App.pop()


## Co-op party fight: freezes the fight for everyone from this player's ref timeout budget.
func _call_timeout() -> void:
	if OnlineFlow.coop == null or not OnlineFlow.coop.call_timeout():
		UiNav.toast("No ref timeout: %s" % (OnlineFlow.coop.error_text() if OnlineFlow.coop else "not in a party fight"), "error")
		return
	_resume_match()


func _end_timeout() -> void:
	if OnlineFlow.coop != null:
		OnlineFlow.coop.end_timeout()
	_resume_match()


## Co-op party fight, host only: the party gives the fight up (a lost fight ends the run).
func _ask_forfeit() -> void:
	App.dialog("Forfeit this fight?", "The fight ends now for everyone and counts as lost: the party run is over.",
		[{"label": "Forfeit", "id": "forfeit", "danger": true}, {"label": "Keep fighting", "id": "stay", "cancel": true, "default": true}],
		func(id: String) -> void:
			if id == "forfeit" and OnlineFlow.coop != null:
				OnlineFlow.coop.forfeit_fight())


func _ask_restart() -> void:
	App.dialog("Restart this fight?", "The current fight is abandoned and starts again from round one with the same fighters.",
		[{"label": "Restart", "id": "restart", "danger": true}, {"label": "Cancel", "id": "cancel", "cancel": true, "default": true}],
		func(id: String) -> void:
			if id == "restart":
				MatchFlow.restart())


func _ask_quit() -> void:
	if _career != null:
		# a bout the judges or the referee already decided is settled, not withdrawn from
		var decided := CareerFlow.bout_decided()
		App.dialog("Leave the fight?" if decided else "Pull out of this fight?",
			"The decision stands and is booked." if decided else _career.withdraw_terms(),
			[{"label": "Leave" if decided else "Pull out", "id": "pull", "danger": true}, {"label": "Keep fighting", "id": "stay", "cancel": true, "default": true}],
			_on_pull_out_choice)
		return
	App.dialog("Quit to the main menu?", "The current fight ends without a result." if not _online else "You will leave the online match.",
		[{"label": "Quit fight", "id": "quit", "danger": true}, {"label": "Keep fighting", "id": "stay", "cancel": true, "default": true}],
		func(id: String) -> void:
			if id == "quit":
				MatchFlow.quit_to_menu())


## Career bout: "Pull out" withdraws (popularity -4, week +1, no purse) and returns to the menu; after
## the judges' decision or a stoppage, "Leave" books that result (CareerFlow.pull_out).
func _on_pull_out_choice(id: String) -> void:
	if id == "pull" and _career != null:
		_career.pull_out()


func on_exit() -> void:
	if not _online:
		MatchFlow.set_paused(false)


## B / Esc resume. (Handled here: during a fight the pause menu is the only screen on the stack,
## and App.back() never pops the last screen.)
func on_back() -> bool:
	_resume_match()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if is_top() and event.is_action_pressed("pause") and not event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_resume_match()
		return
	super(event)
