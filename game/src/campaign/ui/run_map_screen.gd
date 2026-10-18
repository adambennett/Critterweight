extends Screen
## The fight card chart: climb from the first row to the boss, with curved routes between
## nodes, node types as icon + text (unrevealed rows show ???), the current position and the
## reachable next nodes as focusable buttons. Controller: up/down cycles the reachable nodes,
## left/right jumps between the map and the side panel, A/Enter enters, B/Esc offers to suspend.
## Mouse: click. Side panel: fighter, HP, Scrip, Hype carry, build, consumables, suspend/abandon.
## Online party runs: pressing a reachable stop is this player's VOTE (each stop shows its votes;
## the majority decides, the Captain breaks ties, the timer resolves it); the side panel offers
## the Captain's "move on" for absent players and suspend (host: for everyone) / leave (member);
## at a fight the map says the fight is being set up while the host starts it on the session.

var flow: CampaignFlow
var ctrl: RunController
var _map_view: Control
var _map_scroll: ScrollContainer
var _node_buttons := {}          ## node id -> Button
var _reachable: Array = []       ## Buttons of reachable nodes (focus order)
var _side_buttons: Array = []
var _first: Control = null
var _msg: Label
var _fight_pending := false


func on_enter(p: Dictionary) -> void:
	flow = p.get("flow")
	ctrl = flow.ctrl
	_fight_pending = bool(p.get("fight_pending", false))
	_build()
	if str(p.get("fight_error", "")) != "" and ctrl.phase() == "fight":
		_show_fight_error(str(p["fight_error"]))



func _show_fight_error(errors: String) -> void:
	if flow.is_party():
		CampaignUI.confirm(self, "Fight unavailable", "%s\n\nThe party run is saved at the last stop. Try again, forfeit the fight (it counts as a loss for the party) or suspend the run for everyone." % errors,
			[{"label": "TRY AGAIN", "id": "retry"}, {"label": "SUSPEND PARTY RUN", "id": "suspend"}, {"label": "FORFEIT FIGHT", "id": "forfeit", "danger": true}], _on_fight_error)
		return
	CampaignUI.confirm(self, "Fight unavailable", "This fight could not be built:\n%s\n\nYour run is saved. Install the missing content (or enable development stand-ins) and resume, or forfeit the fight (it counts as a loss)." % errors,
		[{"label": "SUSPEND RUN", "id": "suspend"}, {"label": "FORFEIT FIGHT", "id": "forfeit", "danger": true}], _on_fight_error)


func _on_fight_error(id: String) -> void:
	match id:
		"forfeit":
			flow.forfeit_fight()
		"suspend":
			flow.suspend()
		"retry":
			if flow.has_method("retry_fight"):
				flow.call("retry_fight")
		_:
			_after_modal(id)


func _build() -> void:
	ctrl = flow.ctrl
	for c in get_children():
		c.queue_free()
	_node_buttons.clear()
	_reachable.clear()
	_side_buttons.clear()
	_first = null
	var act := int(ctrl.state.get("act", 1))
	var act_def: Dictionary = ctrl.catalog.acts.get(act, {})
	var v := CampaignUI.scaffold(self, "ACT %d — %s" % [act, str(act_def.get("name", "")).to_upper()], str(act_def.get("blurb", "")))
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	var map_panel := CampaignUI.panel()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(map_panel)
	_map_scroll = ScrollContainer.new()
	_map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_map_scroll.follow_focus = true
	_map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.add_child(_map_scroll)
	_map_view = MapView.new()
	_map_view.screen = self
	_map_scroll.add_child(_map_view)
	_place_nodes()
	cols.add_child(_side_panel())
	var foot := HFlowContainer.new()
	foot.add_theme_constant_override("h_separation", 18)
	foot.add_theme_constant_override("v_separation", 4)
	for t in ["fight", "elite", "event", "shop", "rest", "mystery", "treasure", "boss"]:
		var hb := HBoxContainer.new()
		var ic := CampaignUI.NodeIcon.new(t)
		ic.custom_minimum_size = Vector2(30, 30)
		ic.lit = true
		hb.add_child(ic)
		hb.add_child(CampaignUI.inline_label(str(CampaignUI.NODE_NAMES[t]) if t != "mystery" else "? MYSTERY", 18, CampaignUI.MUTED))
		foot.add_child(hb)
	v.add_child(foot)
	v.add_child(CampaignUI.label("Drag the chart / mouse wheel / right stick to explore · Select a pulsing stop to continue", 18, CampaignUI.MUTED))
	_msg = CampaignUI.label("\n".join(flow.notices) if not flow.notices.is_empty() else "", 20, CampaignUI.DANGER)
	flow.notices.clear()
	v.add_child(_msg)
	if flow.is_party() and _msg.text == "":
		_msg.text = _party_status()
		_msg.add_theme_color_override("font_color", CampaignUI.ACCENT)
	_wire_focus()
	refresh_party()
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


## Party runs: what the map is waiting for (the vote, a fight being set up, the others).
func _party_status() -> String:
	var ph := ctrl.phase()
	if ph == "fight":
		var plan := ctrl.current_plan()
		return "FIGHT: %s - the host is starting it for the whole party..." % str(plan.get("name", "next fight"))
	if ph == "map":
		var vv := flow.vote_view()
		if vv.is_empty():
			return "The route vote opens in a moment."
		var mine := str((vv.get("votes", {}) as Dictionary).get(flow.me, ""))
		if mine != "":
			return "You voted for %s. %d s left - the most votes win, the Captain breaks ties." % [_stop_name(mine), ceili(float(vv.get("left", 0.0)))]
		return "Vote for the next stop: %d s left. The most votes win, the Captain breaks ties." % ceili(float(vv.get("left", 0.0)))
	if ctrl.is_over():
		return ""
	return "Your part here is done - waiting for the rest of the party."


func _stop_name(id: String) -> String:
	var t := ctrl.visible_type(id)
	return str(CampaignUI.NODE_NAMES.get(t, t)) if t != "mystery" else "? MYSTERY"


## CoopFlow: votes and timers change without rebuilding the map (focus stays put).
func refresh_party() -> void:
	if not flow.is_party() or _msg == null or not is_instance_valid(_msg):
		return
	var vv := flow.vote_view()
	var votes: Dictionary = vv.get("votes", {})
	for id in _node_buttons:
		var b: Button = _node_buttons[id]
		if not is_instance_valid(b):
			continue
		var n := 0
		for voter in votes:
			if str(votes[voter]) == str(id):
				n += 1
		var t := _stop_name(str(id))
		if not vv.is_empty() and not b.disabled:
			t += "\nVOTES %d%s" % [n, "  (yours)" if str(votes.get(flow.me, "")) == str(id) else ""]
		b.tooltip_text = t
	if flow.notices.is_empty():
		_msg.text = _party_status()


func _place_nodes() -> void:
	var map := RunState.current_map(ctrl.state)
	var available := ctrl.available_nodes() if ctrl.phase() == "map" else []
	var position := str(ctrl.state.get("position", ""))
	var path: Array = ctrl.state.get("path", [])
	var rows: Array = map.get("rows", [])
	_map_view.custom_minimum_size = Vector2(860, maxf(700, rows.size() * 170 + 80))
	for row in rows.size():
		for id in rows[row]:
			var node: Dictionary = map["nodes"][id]
			var kind := ctrl.visible_type(str(id))
			var available_now := available.has(id)
			var here := str(id) == position
			var done := path.has(id)
			var button := Button.new()
			button.name = "Stop_" + str(id).replace(":", "_")
			button.disabled = not available_now
			button.focus_mode = Control.FOCUS_ALL if available_now else Control.FOCUS_NONE
			button.size = Vector2(100, 108)
			button.custom_minimum_size = button.size
			button.pivot_offset = button.size * 0.5
			var color: Color = CampaignUI.NODE_COLORS.get(kind, Color.WHITE)
			for state in ["normal", "hover", "pressed", "disabled"]:
				button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			button.add_theme_stylebox_override("focus", CampaignUI.style(Color(color, 0.16), color, 2, 16))
			var icon := CampaignUI.NodeIcon.new(kind)
			icon.position = Vector2(14, 0)
			icon.size = Vector2(72, 72)
			icon.lit = available_now or here or done
			button.add_child(icon)
			var caption := CampaignUI.label(str(CampaignUI.NODE_NAMES.get(kind, kind)), 18, color if available_now or here else CampaignUI.MUTED, "900")
			caption.position = Vector2(0, 75)
			caption.size = Vector2(100, 28)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(caption)
			if here or done:
				var mark := CampaignUI.label("HERE" if here else "CLEARED", 14, CampaignUI.ACCENT if here else CampaignUI.MUTED, "700")
				mark.position = Vector2(0, -23)
				mark.size.x = 100
				mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.add_child(mark)
			button.set_meta("row", row)
			button.set_meta("x", float(node.get("x", 0.5)))
			button.tooltip_text = "%s%s" % [CampaignUI.NODE_NAMES.get(kind, kind), " · " + ctrl.node_label(str(id)) if ctrl.node_label(str(id)) != "" else ""]
			if available_now:
				button.pressed.connect(_enter.bind(str(id)))
				button.focus_entered.connect(_reveal_node.bind(button))
				button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				_reachable.append(button)
			_map_view.add_child(button)
			_node_buttons[str(id)] = button
	_reachable.sort_custom(func(a, b): return float(a.get_meta("x")) < float(b.get_meta("x")))
	if not _reachable.is_empty():
		_first = _reachable[0]


func _reveal_node(button: Control) -> void:
	_map_scroll.ensure_control_visible.call_deferred(button)


func right_stick_scroll_target() -> Control:
	var focus := get_viewport().gui_get_focus_owner()
	return _map_scroll if focus != null and _map_view.is_ancestor_of(focus) else null


func _process(_dt: float) -> void:
	for button: Control in _reachable:
		var pulse := 1.0 if UiTheme.reduce_motion() else 1.0 + 0.045 * sin(Time.get_ticks_msec() / 650.0)
		button.scale = Vector2.ONE * pulse


func _wire_focus() -> void:
	CampaignUI.chain_focus(_reachable, true)
	var side_first := CampaignUI.first_enabled(_side_buttons)
	for b in _reachable:
		var bt: Button = b
		if side_first:
			bt.focus_neighbor_right = bt.get_path_to(side_first)
			bt.focus_neighbor_left = bt.get_path_to(side_first)
	if _first:
		for s in _side_buttons:
			var sb: Control = s
			sb.focus_neighbor_left = sb.get_path_to(_first)
			sb.focus_neighbor_right = sb.get_path_to(_first)
	CampaignUI.chain_focus(_side_buttons, true)


func _enter(id: String) -> void:
	if flow.is_party():
		if flow.choose_node(id):
			_msg.text = "Voted for %s." % _stop_name(id)
			_msg.add_theme_color_override("font_color", CampaignUI.GOOD)
		else:
			_msg.text = "Can't vote for that: %s" % flow.error_text()
			_msg.add_theme_color_override("font_color", CampaignUI.DANGER)
		return
	if not flow.choose_node(id):
		_msg.text = "Can't go there: %s" % ctrl.last_error


func _side_panel() -> Control:
	var p := ctrl.player(flow.me)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 6)
	box.add_child(CampaignUI.label(CampaignUI.fighter_name(ctrl.catalog, str(p.get("fighter", ""))), 34, CampaignUI.ACCENT, "900"))
	var mh := ctrl.max_hp(p)
	box.add_child(CampaignUI.label("HP %d / %d" % [int(ceil(float(p.get("hp", 0)))), int(mh)], 24, CampaignUI.INK, "700"))
	var bar := ProgressBar.new()
	bar.max_value = mh
	bar.value = float(p.get("hp", 0))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	var fill := StyleBoxFlat.new()
	var frac := float(p.get("hp", 0)) / maxf(1.0, mh)
	fill.bg_color = CampaignUI.GOOD if frac > 0.5 else (CampaignUI.ACCENT if frac > 0.25 else CampaignUI.DANGER)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	box.add_child(CampaignUI.label("Scrip %d   ·   Hype carry %d" % [int(p.get("scrip", 0)), int(p.get("hype_carry", 0))], 22))
	var diff := str(ctrl.catalog.difficulty(str(ctrl.state.get("difficulty", ""))).get("name", ""))
	var dose := int(ctrl.state.get("dose", 0))
	var mode := "The Bookie's Table" if str(ctrl.state.get("mode", "")) == "bookie" else str(ctrl.state.get("variant", "")).replace("_", " ").capitalize()
	box.add_child(CampaignUI.label("%s · %s%s · seed %s%s" % [mode, diff, (" · Dose %d" % dose) if dose > 0 else "",
		ctrl.state.get("seed_text", ""), " · CUSTOM RUN" if bool(ctrl.state.get("custom", false)) else ""], 18, CampaignUI.MUTED))
	var build := VBoxContainer.new()
	build.add_theme_constant_override("separation", 4)
	build.add_child(CampaignUI.label("BUILD", 22, CampaignUI.INK, "900"))
	for t in p.get("techniques", []):
		build.add_child(CampaignUI.label("Technique: %s — %s" % [ctrl.catalog.item_name(str(t)), ctrl.catalog.item(str(t)).get("effect", "")], 17, CampaignUI.GOOD))
	for s in p.get("supplements", []):
		var d: Dictionary = ctrl.catalog.supplements.get(str(s["id"]), {})
		var stacks := int(s.get("stacks", 1))
		var r := str(d.get("rarity", "otc"))
		build.add_child(CampaignUI.label("%s%s (%s) — %s" % [d.get("name", s["id"]), (" x%d" % stacks) if stacks > 1 else "",
			CampaignUI.rarity_text(r).capitalize(), d.get("effect", "")], 17, CampaignUI.RARITY_COLORS.get(r, CampaignUI.INK)))
	for se in p.get("side_effects", []):
		build.add_child(CampaignUI.label("Side effect: %s — %s" % [ctrl.catalog.item_name(str(se)), ctrl.catalog.item(str(se)).get("effect", "")], 17, CampaignUI.DANGER))
	if (p.get("supplements", []) as Array).is_empty() and (p.get("techniques", []) as Array).is_empty():
		build.add_child(CampaignUI.label("Nothing yet. Win fights to pick supplements.", 20, CampaignUI.MUTED))
	box.add_child(CampaignUI.scroll(build))
	var cons: Dictionary = p.get("consumables", {})
	for cid in cons:
		var ub := CampaignUI.button("USE %s (x%d)" % [ctrl.catalog.item_name(str(cid)).to_upper(), int(cons[cid])], _use.bind(str(cid)), 20)
		ub.tooltip_text = str(ctrl.catalog.item(str(cid)).get("effect", ""))
		box.add_child(ub)
		_side_buttons.append(ub)
	if flow.is_party():
		_party_buttons(box)
		return box
	var sus := CampaignUI.button("HAND BACK TO TEDDY" if flow.is_bookie() else "SUSPEND RUN (save & quit)", _confirm_suspend, 20)
	box.add_child(sus)
	_side_buttons.append(sus)
	var ab := CampaignUI.button("ABANDON RUN", _confirm_abandon, 20, CampaignUI.DANGER)
	box.add_child(ab)
	_side_buttons.append(ab)
	return box


## Party runs: the Captain may move on for absent players; the host suspends the run for everyone
## (it stays in every party save), a member leaves it (a bot takes over until they rejoin).
func _party_buttons(box: VBoxContainer) -> void:
	if ctrl.captain() == flow.me and ctrl.phase() != "map" and ctrl.phase() != "fight" and not ctrl.is_over():
		var mo := CampaignUI.button("MOVE ON FOR ABSENT PLAYERS", _move_on, 20)
		mo.tooltip_text = "Captain: decide for players who are away (after %d s idle)." % int(ctrl.catalog.rules.get("coop", {}).get("absent_time", 60.0))
		box.add_child(mo)
		_side_buttons.append(mo)
	var host: bool = flow.has_method("is_host") and bool(flow.call("is_host"))
	var sus := CampaignUI.button("SUSPEND PARTY RUN (everyone)" if host else "LEAVE THE PARTY RUN", _confirm_suspend, 20,
		CampaignUI.ACCENT if host else CampaignUI.DANGER)
	box.add_child(sus)
	_side_buttons.append(sus)


func _move_on() -> void:
	if flow.has_method("move_on") and bool(flow.call("move_on")):
		_msg.text = "Moving on for the absent players..."
		_msg.add_theme_color_override("font_color", CampaignUI.GOOD)
	else:
		_msg.text = flow.error_text()
		_msg.add_theme_color_override("font_color", CampaignUI.DANGER)


func _use(cid: String) -> void:
	if not flow.do_consume(cid):
		_msg.text = flow.error_text()
		return
	if flow.is_party():
		CampaignUI.wait_for_party(self, _msg)
	else:
		_build()


func _after_modal(_id: String) -> void:
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


func _confirm_abandon() -> void:
	CampaignUI.confirm(self, "Abandon this run?", "It ends as a defeat (statistics and history keep it).",
		[{"label": "ABANDON", "id": "yes", "danger": true}, {"label": "KEEP FIGHTING", "id": "no"}], _on_abandon)


func _on_abandon(id: String) -> void:
	if id == "yes":
		flow.abandon()
	else:
		_after_modal(id)


func _confirm_suspend() -> void:
	if flow.is_party():
		if flow.has_method("is_host") and bool(flow.call("is_host")):
			CampaignUI.confirm(self, "Suspend the party run?", "Everyone goes back to the lobby. The run is saved at the last stop in every member's party save: offer it again from the lobby to continue (a fight in progress starts over).",
				[{"label": "SUSPEND FOR EVERYONE", "id": "yes"}, {"label": "STAY", "id": "no"}], _on_suspend)
		else:
			CampaignUI.confirm(self, "Leave the party run?", "A bot plays your fighter (and makes your choices) until you rejoin from the lobby. The run stays in your party saves.",
				[{"label": "LEAVE", "id": "yes", "danger": true}, {"label": "STAY", "id": "no"}], _on_suspend)
		return
	if flow.is_bookie():
		CampaignUI.confirm(self, "Hand back to Teddy?", "Teddy makes the decisions again from here; you can take over at any time.",
			[{"label": "HAND BACK", "id": "yes"}, {"label": "KEEP DECIDING", "id": "no"}], _on_suspend)
		return
	CampaignUI.confirm(self, "Leave the card?", "Your run is saved at this point; resume it from the campaign menu.",
		[{"label": "SUSPEND & LEAVE", "id": "yes"}, {"label": "STAY", "id": "no"}], _on_suspend)


func _on_suspend(id: String) -> void:
	if id == "yes":
		flow.suspend()
	else:
		_after_modal(id)


func on_back() -> bool:
	if CampaignUI.close_modal(self):
		return true
	_confirm_suspend()
	return true


func default_focus() -> Control:
	return _first if _first else CampaignUI.first_enabled(_side_buttons)


## Lays out node buttons by (row, lane x) and draws the edges behind them.
class MapView:
	extends Control
	var screen
	var dragging := false

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		resized.connect(_layout)

	func _ready() -> void:
		_layout.call_deferred()

	func _layout() -> void:
		var rows: Array = RunState.current_map(screen.ctrl.state).get("rows", [])
		for child in get_children():
			if child is Button:
				var row := int(child.get_meta("row", 0))
				var lane := float(child.get_meta("x", 0.5))
				child.position = Vector2(60 + lane * (size.x - 220), 45 + (rows.size() - 1 - row) * 170)
		queue_redraw()
		if screen._first:
			screen._reveal_node.call_deferred(screen._first)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			dragging = event.pressed
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			screen._map_scroll.scroll_vertical -= int(event.relative.y)
			screen._map_scroll.scroll_horizontal -= int(event.relative.x)
			accept_event()

	func _draw() -> void:
		var map := RunState.current_map(screen.ctrl.state)
		var path: Array = screen.ctrl.state.get("path", [])
		var position := str(screen.ctrl.state.get("position", ""))
		var available: Array = screen.ctrl.available_nodes()
		for id in map.get("nodes", {}):
			var source: Control = screen._node_buttons.get(str(id))
			if source == null:
				continue
			for edge in map["nodes"][id].get("edges", []):
				var destination: Control = screen._node_buttons.get(str(edge))
				if destination == null:
					continue
				var a := source.position + Vector2(50, 0)
				var b := destination.position + Vector2(50, 72)
				var walked := path.has(id) and path.has(edge)
				var next := str(id) == position and available.has(edge)
				var color := CampaignUI.ACCENT if walked else (Color("#d1c9ac") if next else Color("#49464d"))
				var curve := Curve2D.new()
				curve.add_point(a, Vector2.ZERO, Vector2(0, -48))
				curve.add_point(b, Vector2(0, 48), Vector2.ZERO)
				draw_polyline(curve.get_baked_points(), color, 3.0 if walked or next else 2.0, true)
