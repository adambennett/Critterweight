extends Screen
## Pause ("pause"). Offline: freezes the match (simulation + physics, MatchFlow.set_paused) until
## it closes. Online: nothing pauses — the menu says so and the fight keeps running behind it.
## Resume · Restart fight (offline) · Settings · Controls · Quit to main menu (confirmed).
## In a career bout (the match scene carries meta "career_flow", design contract D4) there is no
## Restart, and quitting is pulling out of the fight: the confirmation says so ("No purse,
## popularity -4.") and the career's withdrawal is applied before returning to the main menu.
## A quick reference shows the core actions with the CURRENT bindings for the active device, for
## the local fighter's kit: Movesets names the four equipped moves on their inputs and the
## Ultimate, Classic the Classic actions, a martial fighter the Cage Rules layout.
## Practice (the match carries a PracticeOverlay): a PRACTICE group with the dummy's behaviour,
## record / stop, reset positions and, in Movesets, Change moves (the loadout screen over the paused
## match; the new moves apply live). These are the controller route to the practice tools whenever
## the overlay's shortcuts collide with the fighter's layout (Varga's Cage Rules pad layout uses
## every button but Start).
## Start / Esc / B close it. params: {notice: String} (e.g. "Controller disconnected ...").

const QUICK_REF := [["move_up", "Move", "left_stick"], ["light", "Light attack", ""], ["heavy", "Heavy (hold to charge)", ""],
	["guard", "Guard (tap to parry)", ""], ["dodge", "Dodge", ""], ["grab", "Grab / throw", ""], ["ability1", "Ability 1", ""],
	["ability2", "Ability 2", ""], ["juice", "JUICE", ""], ["taunt", "Taunt", ""], ["target", "Switch target", ""]]
const MARTIAL_REF := [["move_up", "Move", "left_stick"], ["mma_lh", "Left hand", ""], ["mma_rh", "Right hand", ""], ["mma_ll", "Left leg", ""],
	["mma_rl", "Right leg", ""], ["mma_mod1", "Hooks / body kicks", ""], ["mma_mod2", "Straights / head kicks", ""], ["mma_mod3", "Overhands / low kicks", ""],
	["mma_guard", "Guard", ""], ["mma_dodge", "Slip", ""], ["mma_grab", "Takedown / throw", ""], ["mma_juice", "JUICE", ""]]

var _online := false
var _career: CareerFlow = null       ## the career bout's flow (null outside career bouts)
var _resume: UiButton
var _ref_box: VBoxContainer
var _practice: Node = null           ## the match's PracticeOverlay (practice tools), null otherwise
var _record_btn: UiButton = null


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
	_practice = _practice_overlay() if not _online else null
	var holder: Container = lv
	if _practice != null:
		# practice adds a group of tools: the list scrolls (focus keeps the focused entry in view)
		left.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var fs := FocusScroll.new(UiTheme.GAP_S)
		fs.name = "PauseList"
		fs.custom_minimum_size = Vector2(600, 0)
		lv.add_child(fs)
		holder = fs.content
	_resume = _button(holder, "Resume", "fight", "resume", _resume_match)
	if _practice != null:
		_practice_rows(holder)
	if party_fight:
		var pv: Dictionary = OnlineFlow.coop.session.pause_view()
		if bool(pv.get("paused", false)) and str(pv.get("by", "")) == OnlineFlow.coop.me:
			_button(holder, "End my ref timeout", "fight", "timeout", _end_timeout)
		elif not bool(pv.get("paused", false)):
			var tb := _button(holder, "Call a ref timeout", "info", "timeout", _call_timeout)
			tb.disabled = OnlineFlow.coop.session.my_pause_budget() <= 0.0
		if OnlineFlow.coop.is_host():
			_button(holder, "Forfeit this fight", "close", "forfeit", _ask_forfeit)
	if not _online and not MatchFlow.last_config.is_empty() and _career == null:
		_button(holder, "Restart fight", "restart", "restart", _ask_restart)
	_button(holder, "Settings", "settings", "settings", func() -> void: App.push("settings", {"in_game": true}))
	_button(holder, "Controls", "gamepad", "controls", func() -> void: App.push("controls", {"in_game": true}))
	_button(holder, "Quit to main menu", "quit", "quit", _ask_quit)
	var buttons: Array[Control] = []
	for c in holder.get_children():
		if c is UiButton or c is UiRow:
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


## The quick reference rows for the local fighter's kit: [action, label, special].
static func reference_rows(f: Fighter) -> Array:
	if f != null and f.creature != null and f.creature.tags.has("martial"):
		return MARTIAL_REF
	if not MovesUi.movesets(f):
		return QUICK_REF
	var rows: Array = [["move_up", "Move (steers HOLD+AIM moves)", "left_stick"]]
	for i in Fighter.MOVE_SLOTS.size():
		var pm := f.slot_move(str(Fighter.MOVE_SLOTS[i]))
		if pm != null:
			var tag := MovesUi.hold_tag(pm)
			rows.append([MovesUi.slot_action(i), pm.display_name + ("  (%s)" % tag if tag != "" else ""), ""])
	rows.append_array([["guard", "Guard (tap to parry)", ""], ["dodge", "Dodge", ""], ["grab", "Grapple / throw", ""]])
	var ult := "Ultimate"
	if f.creature.abilities.has("juice"):
		ult = "Ultimate: %s" % (f.creature.abilities["juice"] as MoveDef).display_name
	rows.append_array([["juice", ult, ""], ["taunt", "Taunt", ""], ["target", "Switch target", ""]])
	return rows


func _build_reference() -> void:
	for c in _ref_box.get_children():
		c.queue_free()
	_ref_box.add_child(UiTheme.label("CONTROLS", "Eyebrow"))
	for e in reference_rows(MovesUi.local_fighter()):
		var row := UiTheme.hbox(UiTheme.GAP_M)
		var l := UiTheme.label(str(e[1]), "Body")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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


## The running local match's practice overlay (practice_overlay.gd), or null.
static func _practice_overlay() -> Node:
	var ms := MatchFlow.current_match()
	if ms == null or ms.hud_layer == null:
		return null
	var ov := ms.hud_layer.get_node_or_null("PracticeOverlay")
	return ov if ov != null and ov.has_method("open_moves") else null


## PRACTICE: the dummy's behaviour, record / stop, reset positions and (Movesets) Change moves.
func _practice_rows(holder: Container) -> void:
	holder.add_child(UiTheme.label("PRACTICE", "Eyebrow"))
	var dummy := OptionRow.new("Dummy")
	var ids: Array = PracticeMode.BEHAVIORS.duplicate()
	var names: Array[String] = []
	for b in ids:
		names.append(str(_practice.call("behavior_label", str(b))))
	dummy.setup(ids, names, str(_practice.call("current_behavior")))
	dummy.key = "practice_dummy"
	dummy.custom_minimum_size = Vector2(560, 70)
	dummy.set_help("Dummy", "What the training dummy does: stand still, guard, parry, block and counter, replay your recording, or fight back as a bot.")
	dummy.value_changed.connect(_practice_dummy)
	holder.add_child(dummy)
	var recording := bool(_practice.call("is_recording"))
	_record_btn = _button(holder, "Stop recording" if recording else "Record a sequence", "practice", "practice_record", _practice_record)
	_button(holder, "Reset positions", "restart", "practice_reset", _practice_reset)
	if bool(_practice.call("can_change_moves")):
		var mv := _button(holder, "Change moves", "edit", "change_moves", _practice_moves)
		mv.set_help("Change moves", "Pick your four moves (a recommended loadout or your own). They apply at once and your fighter is refreshed.")


func _practice_dummy(v) -> void:
	if _practice != null and is_instance_valid(_practice):
		_practice.call("set_behavior", str(v))


func _practice_record() -> void:
	if _practice != null and is_instance_valid(_practice):
		_practice.call("toggle_record")
	_resume_match()


func _practice_reset() -> void:
	if _practice != null and is_instance_valid(_practice):
		_practice.call("reset_positions")
	_resume_match()


## Opens the loadout screen over this menu; Done applies the moves live and comes back here.
func _practice_moves() -> void:
	if _practice != null and is_instance_valid(_practice):
		_practice.call("open_moves")


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
