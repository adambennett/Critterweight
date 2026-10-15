extends Screen
## The fight card map: the current act's rows left-to-right (row 1 -> boss), edges between
## nodes, node types as icon + text (unrevealed rows show ???), the current position and the
## reachable next nodes as focusable buttons. Controller: up/down cycles the reachable nodes,
## left/right jumps between the map and the side panel, A/Enter enters, B/Esc offers to suspend.
## Mouse: click. Side panel: fighter, HP, Scrip, Hype carry, build, consumables, suspend/abandon.

var flow: CampaignFlow
var ctrl: RunController
var _map_view: Control
var _node_buttons := {}          ## node id -> Button
var _reachable: Array = []       ## Buttons of reachable nodes (focus order)
var _side_buttons: Array = []
var _first: Control = null
var _msg: Label


func on_enter(p: Dictionary) -> void:
	flow = p.get("flow")
	ctrl = flow.ctrl
	_build()
	if str(p.get("fight_error", "")) != "" and ctrl.phase() == "fight":
		_show_fight_error(str(p["fight_error"]))
	else:
		_maybe_act_intro()


func _show_fight_error(errors: String) -> void:
	CampaignUI.confirm(self, "Fight unavailable", "This fight could not be built:\n%s\n\nYour run is saved. Install the missing content (or enable development stand-ins) and resume, or forfeit the fight (it counts as a loss)." % errors,
		[{"label": "SUSPEND RUN", "id": "suspend"}, {"label": "FORFEIT FIGHT", "id": "forfeit", "danger": true}], _on_fight_error)


func _on_fight_error(id: String) -> void:
	match id:
		"forfeit":
			flow.forfeit_fight()
		"suspend":
			flow.suspend()
		_:
			_after_modal(id)


func _build() -> void:
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
	_map_view = MapView.new()
	_map_view.screen = self
	map_panel.add_child(_map_view)
	_place_nodes()
	cols.add_child(_side_panel())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)
	for t in ["fight", "elite", "event", "shop", "rest", "mystery", "treasure", "boss"]:
		var hb := HBoxContainer.new()
		var ic := CampaignUI.NodeIcon.new(t)
		ic.custom_minimum_size = Vector2(30, 30)
		ic.lit = true
		hb.add_child(ic)
		hb.add_child(CampaignUI.label(str(CampaignUI.NODE_NAMES[t]) if t != "mystery" else "? MYSTERY", 18, CampaignUI.MUTED))
		foot.add_child(hb)
	v.add_child(foot)
	_msg = CampaignUI.label("\n".join(flow.notices) if not flow.notices.is_empty() else "", 20, CampaignUI.DANGER)
	flow.notices.clear()
	v.add_child(_msg)
	_wire_focus()
	var f := default_focus()
	if f:
		f.call_deferred("grab_focus")


func _node_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var sb := CampaignUI.style(bg, border, width)
	sb.content_margin_left = 54
	sb.content_margin_right = 8
	return sb


func _place_nodes() -> void:
	var m := RunState.current_map(ctrl.state)
	var avail := ctrl.available_nodes() if ctrl.phase() == "map" else []
	var pos := str(ctrl.state.get("position", ""))
	var path: Array = ctrl.state.get("path", [])
	var rows: Array = m.get("rows", [])
	for r in rows.size():
		for id in rows[r]:
			var n: Dictionary = m["nodes"][id]
			var t := ctrl.visible_type(str(id))
			var on := avail.has(id)
			var here := str(id) == pos
			var done := path.has(id)
			var b := Button.new()
			b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
			b.disabled = not on
			b.custom_minimum_size = Vector2(168, 76)
			b.size = b.custom_minimum_size
			var txt := str(CampaignUI.NODE_NAMES.get(t, t)) if t != "mystery" else "? MYSTERY"
			var lbl := ctrl.node_label(str(id))
			if lbl != "":
				txt += "\n" + lbl
			if here:
				txt += "\nYOU ARE HERE"
			elif done:
				txt += "\ncleared"
			elif on:
				txt += "\nreachable"
			b.text = txt
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.add_theme_font_size_override("font_size", 16)
			var fnt := CampaignUI.font("700")
			if fnt:
				b.add_theme_font_override("font", fnt)
			var col: Color = CampaignUI.NODE_COLORS.get(t, Color.WHITE)
			b.add_theme_stylebox_override("normal", _node_style(CampaignUI.PANEL_HI, col, 3))
			b.add_theme_stylebox_override("hover", _node_style(col.darkened(0.15), Color.WHITE, 3))
			b.add_theme_stylebox_override("focus", _node_style(col, Color.WHITE, 5))
			b.add_theme_stylebox_override("pressed", _node_style(col.darkened(0.3), Color.WHITE, 5))
			var dis_bg := CampaignUI.PANEL_HI.darkened(0.25) if (done or here) else CampaignUI.PANEL.darkened(0.2)
			var dis_border := CampaignUI.ACCENT if here else (col.darkened(0.35) if done else col.darkened(0.65))
			b.add_theme_stylebox_override("disabled", _node_style(dis_bg, dis_border, 4 if here else 1))
			b.add_theme_color_override("font_color", CampaignUI.INK)
			b.add_theme_color_override("font_disabled_color", CampaignUI.INK if (here or done) else CampaignUI.MUTED.darkened(0.2))
			b.add_theme_color_override("font_focus_color", CampaignUI.BG)
			b.add_theme_color_override("font_hover_color", CampaignUI.BG)
			b.add_theme_color_override("font_pressed_color", CampaignUI.BG)
			var icon := CampaignUI.NodeIcon.new(t)
			icon.lit = on or here or done
			icon.anchor_top = 0.5
			icon.anchor_bottom = 0.5
			icon.offset_top = -22
			icon.offset_bottom = 22
			icon.offset_left = 8
			icon.offset_right = 52
			b.add_child(icon)
			b.set_meta("row", r)
			b.set_meta("x", float(n.get("x", 0.5)))
			if on:
				b.pressed.connect(_enter.bind(str(id)))
				b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				_reachable.append(b)
			b.tooltip_text = txt.replace("\n", " · ")
			_map_view.add_child(b)
			_node_buttons[str(id)] = b
	_reachable.sort_custom(func(a, c): return float(a.get_meta("x", 0.0)) < float(c.get_meta("x", 0.0)))
	if not _reachable.is_empty():
		_first = _reachable[0]


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
		build.add_child(CampaignUI.label("Nothing yet. Win fights to pick supplements.", 17, CampaignUI.MUTED))
	box.add_child(CampaignUI.scroll(build))
	var cons: Dictionary = p.get("consumables", {})
	for cid in cons:
		var ub := CampaignUI.button("USE %s (x%d)" % [ctrl.catalog.item_name(str(cid)).to_upper(), int(cons[cid])], _use.bind(str(cid)), 20)
		ub.tooltip_text = str(ctrl.catalog.item(str(cid)).get("effect", ""))
		box.add_child(ub)
		_side_buttons.append(ub)
	var sus := CampaignUI.button("HAND BACK TO TEDDY" if flow.is_bookie() else "SUSPEND RUN (save & quit)", _confirm_suspend, 20)
	box.add_child(sus)
	_side_buttons.append(sus)
	var ab := CampaignUI.button("ABANDON RUN", _confirm_abandon, 20, CampaignUI.DANGER)
	box.add_child(ab)
	_side_buttons.append(ab)
	return box


func _use(cid: String) -> void:
	if ctrl.use_consumable(flow.me, cid):
		_build()
	else:
		_msg.text = ctrl.last_error


func _maybe_act_intro() -> void:
	var act := int(ctrl.state.get("act", 1))
	if str(ctrl.state.get("position", "")) != "" or flow.intro_seen.has(act):
		return
	flow.intro_seen[act] = true
	var act_def: Dictionary = ctrl.catalog.acts.get(act, {})
	var boss_enc: Dictionary = ctrl.catalog.encounters.get(str(act_def.get("boss", "")), {})
	var body := str(act_def.get("blurb", ""))
	if not boss_enc.is_empty():
		body += "\n\nTonight's headliner: %s." % str(boss_enc.get("name", "")).replace("Boss: ", "")
	CampaignUI.confirm(self, "ACT %d — %s" % [act, str(act_def.get("name", "")).to_upper()], body, [{"label": "LET'S GO", "id": "ok"}], _after_modal)


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

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(900, 520)
		resized.connect(_layout)

	func _ready() -> void:
		_layout.call_deferred()

	func _rows() -> int:
		return (RunState.current_map(screen.ctrl.state).get("rows", []) as Array).size()

	func _cell(row: int, x: float, rows: int) -> Vector2:
		var w := size.x - 180.0
		var h := size.y - 100.0
		return Vector2(10.0 + w * (float(row) / maxf(1.0, float(rows - 1))), 10.0 + h * x)

	func _layout() -> void:
		var rows := _rows()
		for c in get_children():
			if c is Button:
				var b: Button = c
				b.position = _cell(int(b.get_meta("row", 0)), float(b.get_meta("x", 0.5)), rows)
		queue_redraw()

	func _draw() -> void:
		var m := RunState.current_map(screen.ctrl.state)
		var path: Array = screen.ctrl.state.get("path", [])
		var pos := str(screen.ctrl.state.get("position", ""))
		var avail: Array = screen.ctrl.available_nodes()
		var buttons: Dictionary = screen._node_buttons
		for id in m.get("nodes", {}):
			var ba: Control = buttons.get(str(id))
			if ba == null:
				continue
			var a := ba.position + Vector2(ba.size.x, ba.size.y * 0.5)
			for e in m["nodes"][id].get("edges", []):
				var bb: Control = buttons.get(str(e))
				if bb == null:
					continue
				var b := bb.position + Vector2(0.0, bb.size.y * 0.5)
				var walked := path.has(id) and path.has(e)
				var next := str(id) == pos and avail.has(e)
				var col := CampaignUI.ACCENT if walked else (Color(1, 1, 1, 0.75) if next else Color(1, 1, 1, 0.16))
				draw_line(a, b, col, 5.0 if walked else (3.0 if next else 2.0), true)
		if pos == "":
			# act start: draw stubs into the first row so the entry choice reads as a route
			for e2 in avail:
				var bs: Control = buttons.get(str(e2))
				if bs:
					var tip := bs.position + Vector2(0.0, bs.size.y * 0.5)
					draw_line(tip - Vector2(28, 0), tip, Color(1, 1, 1, 0.75), 3.0, true)
