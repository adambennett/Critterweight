extends Screen
## Career hub ("career_hub", CMP-08): the Cage Rules station panel as one screen.
##   Header: name "nick", fighter, standing (tier + popularity label, contender #, Champion),
##   streak, record W-L-D with TKO/DEC, bank, Year/Week, popularity number + label + a bar with
##   the promotion gates marked, difficulty.
##   Tabs (TabStrip, LB/RB): CAMP (TRAINING while unbooked, FIGHT WEEK! when due) · OFFERS · GYM ·
##   HISTORY. Side: the six stats with the overall rating, and condition (head/body/legs).
## CAMP unbooked: the train grid (each stat with the exact model gain for this week, its gym room
## and level; Rest with its healing and the "you are healthy" hint). Booked: the fight card
## (promotion, tier, title, purse + bonus, rounds, weeks to go, the opponent with fighter,
## record, rating, bot tier, danger tag, the six-row stat comparison, the camp so far), then the
## train grid — or, on fight week, FIGHT with the condition line. PULL OUT is a withdrawal
## (danger confirmation, popularity -4). OFFERS: every offer as a card (A accepts) with the
## next-promotion / title-shot / tier-cap hints. GYM: the eight facilities with level pips, effect
## and next cost (A buys). HISTORY: the fights, newest first, then the news log.
## Every action goes through the CareerController (which autosaves); Back returns to the slot list.
## params: {flow: CareerFlow, tab?: "camp"|"offers"|"gym"|"history"}. Without a flow it loads
## params.slot (or the first career of the active profile that loads), so a dev capture can open
## it directly: --screen career_hub --screen-arg tab=gym.

const TABS := ["camp", "offers", "gym", "history"]

var flow: CareerFlow
var ctrl: CareerController
var _tabs: TabStrip
var _scroll: FocusScroll
var _header: PanelContainer
var _side: VBoxContainer
var _status: Label
var _help: Label
var _built := false


func on_enter(p: Dictionary) -> void:
	var f = p.get("flow", null)
	flow = f if f is CareerFlow else _load_from(p)
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.9)
	if flow == null or flow.ctrl == null:
		var fr := build_frame("Career", "No career")
		(fr["prompts"] as PromptBar).set_prompts(std_prompts())
		(fr["body"] as VBoxContainer).add_child(UiTheme.label("There is no career to show. Start one from Campaign › Career.", "Body", true))
		var b := UiButton.new("CAREER SLOTS", "", "back")
		b.route = "slots"
		b.pressed.connect(func() -> void: App.goto("career"))
		(fr["body"] as VBoxContainer).add_child(b)
		return
	ctrl = flow.ctrl
	var fr2 := build_frame("", "")
	(fr2["prompts"] as PromptBar).set_prompts([{"actions": ["ui_accept"], "text": "Select"},
		{"actions": ["ui_tab_prev", "ui_tab_next"], "text": "Tabs", "call": func() -> void: _tabs.step(1)},
		{"actions": ["ui_cancel"], "text": "Career slots", "call": App.back}])
	var body: VBoxContainer = fr2["body"]
	_header = UiTheme.panel("PanelPoster", 20.0)
	body.add_child(_header)
	_tabs = TabStrip.new()
	var start := maxi(0, TABS.find(str(p.get("tab", "camp"))))
	_tabs.setup(_tab_titles(), TABS, start)
	_tabs.tab_changed.connect(func(_i: int) -> void: _show_tab())
	body.add_child(_tabs)
	var row := UiTheme.hbox(UiTheme.GAP_L)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var main := UiTheme.panel("PanelSolid", 16.0)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(main)
	var mv := UiTheme.vbox(UiTheme.GAP_S)
	main.add_child(mv)
	_status = UiTheme.label("", "Warning", true)
	_status.visible = false
	mv.add_child(_status)
	_scroll = FocusScroll.new(12)
	mv.add_child(_scroll)
	# what the focused card does (stat descriptions, offer terms, facility blurbs): one line under
	# the list instead of a help panel, so the fight card and the first actions share the screen
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.GOLD, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mv.add_child(rule)
	_help = UiTheme.label("", "Caption", true)
	_help.custom_minimum_size = Vector2(0, 66)
	mv.add_child(_help)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	var side_panel := UiTheme.panel("PanelSolid", 22.0)
	side_panel.custom_minimum_size = Vector2(600, 0)
	row.add_child(side_panel)
	# the side never pushes the footer off screen (large text sizes scroll it instead)
	var ss := ScrollContainer.new()
	ss.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ss.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panel.add_child(ss)
	_side = UiTheme.vbox(UiTheme.GAP_M)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ss.add_child(_side)
	if flow.notice != "":
		_set_status(flow.notice)
		flow.notice = ""
	_built = true
	_refresh()
	play_intro()


## Without a flow: params.slot, else the first slot of the active profile that loads.
func _load_from(p: Dictionary) -> CareerFlow:
	var cat := CareerFlow.default_catalog()
	var st := CareerStore.new()
	var slots := [int(p.get("slot", 0))] if CareerStore.valid_slot(int(p.get("slot", 0))) else [1, 2, 3]
	for n in slots:
		var r := CareerFlow.open_slot(cat, st, int(n))
		if bool(r["ok"]):
			return r["flow"]
	return null


func current_tab() -> String:
	return _tabs.current_id() if _tabs != null else ""


func select_tab(id: String) -> void:
	var i := TABS.find(id)
	if i >= 0 and _tabs != null and i != _tabs.current:
		_tabs.select(i)


func _tab_titles() -> Array:
	var camp := "Training"
	if ctrl.fight_ready():
		camp = "Fight week!"
	elif ctrl.is_booked():
		camp = "Camp"
	var n := (ctrl.state.get("offers", []) as Array).size()
	return [camp, "Offers (%d)" % n if not ctrl.is_booked() else "Offers", "Gym", "History"]


## Rebuilds everything (after an action) and puts focus back on `focus_route` when it still exists.
func _refresh(focus_route := "") -> void:
	if not _built:
		return
	_tabs.setup(_tab_titles(), TABS, _tabs.current)
	_build_header()
	_build_side()
	_show_tab(focus_route)


func _on_focus_changed(c: Control) -> void:
	if _help == null or c == null or not is_instance_valid(c) or _scroll == null or not _scroll.is_ancestor_of(c):
		return
	var title := str(c.get("help_title")) if "help_title" in c else ""
	var body := str(c.get("help_text")) if "help_text" in c else ""
	_help.text = ("%s: %s" % [title, body]) if title != "" and body != "" else (title + body)


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


# --- header ------------------------------------------------------------------------------------

func _build_header() -> void:
	for c in _header.get_children():
		_header.remove_child(c)
		c.queue_free()
	var h := ctrl.header()
	var row := UiTheme.hbox(UiTheme.GAP_L)
	_header.add_child(row)
	var who := UiTheme.vbox(2)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(who)
	who.add_child(UiTheme.label("CAREER · SLOT %d · %s · %s" % [ctrl.slot, str(h["fighter_name"]).to_upper(), str(h["difficulty_name"]).to_upper()], "Eyebrow"))
	var nm := UiTheme.label(str(h["billed"]).to_upper(), "H2")
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(300, 0)
	who.add_child(nm)
	var line := UiTheme.hbox(UiTheme.GAP_S)
	if bool(h["champion"]):
		line.add_child(UiIcons.rect("trophy", 34, UiTheme.GOLD_HI))
		line.add_child(UiTheme.label(str(h["standing"]).to_upper(), "ValueGold"))
	else:
		line.add_child(UiTheme.label(str(h["standing"]), "BodyStrong"))
	if str(h["streak_text"]) != "":
		line.add_child(UiTheme.label("·  %s" % str(h["streak_text"]), "Body"))
	who.add_child(line)
	var rec := "%d-%d-%d" % [int(h["record"].get("w", 0)), int(h["record"].get("l", 0)), int(h["record"].get("d", 0))]
	row.add_child(CareerUi.kpi("Record", rec, "%d TKO · %d DEC" % [int(h["tko"]), int(h["dec"])]))
	row.add_child(CareerUi.kpi("Bank", str(h["money_text"]), "", "ValueGold"))
	var w := int(h["week"])
	row.add_child(CareerUi.kpi("Date", "Week %d" % (((w - 1) % 52) + 1), "Year %d" % (int((w - 1) / 52.0) + 1)))
	var pop := UiTheme.vbox(0)
	pop.custom_minimum_size = Vector2(300, 0)
	pop.add_child(UiTheme.label("POPULARITY", "Eyebrow"))
	var pr := UiTheme.hbox(UiTheme.GAP_S)
	pr.add_child(UiTheme.label(CareerUi.num(float(h["pop"])), "Value"))
	var bar := CareerUi.PopBar.new(float(h["pop"]), h["pop_marks"])
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(bar)
	pop.add_child(pr)
	pop.add_child(UiTheme.label(str(h["pop_label"]), "Caption"))
	row.add_child(pop)


func _build_side() -> void:
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()
	_side.add_child(CareerUi.stats_box(ctrl))
	_side.add_child(CareerUi.condition_box(ctrl))


# --- tabs --------------------------------------------------------------------------------------

func _show_tab(focus_route := "") -> void:
	_scroll.clear()
	match current_tab():
		"offers":
			_build_offers()
		"gym":
			_build_gym()
		"history":
			_build_history()
		_:
			_build_camp()
	_scroll.wrap_focus.call_deferred()
	_focus_route.call_deferred(focus_route)
	_scroll.scroll_to_top()


func _focus_route(route: String) -> void:
	if not is_inside_tree() or App.top_screen() != self:
		return
	var t := find_route(route) if route != "" else null
	if t == null:
		t = default_focus()
	if t != null and t.is_visible_in_tree():
		t.grab_focus()
		_settle_scroll(t)


## The list was rebuilt this frame, so follow_focus measured stale positions: once the containers
## have sorted, scroll from the top just far enough to show the focused control (the fight card
## above the first action stays visible whenever it fits).
func _settle_scroll(t: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(t) or not t.is_inside_tree() or _scroll == null:
		return
	_scroll.scroll_vertical = 0
	_scroll.ensure_control_visible(t)


## The focusable control with this route (cards and buttons), or null.
func find_route(route: String) -> Control:
	if _scroll == null:
		return null
	for c in _scroll.focusables():
		if (c is CareerUi.ActionCard and (c as CareerUi.ActionCard).route == route) or (c is UiButton and (c as UiButton).route == route):
			return c
	return null


## Every route in the current tab, in focus order (tests, tooling).
func routes() -> Array[String]:
	var out: Array[String] = []
	if _scroll == null:
		return out
	for c in _scroll.focusables():
		if c is CareerUi.ActionCard:
			out.append((c as CareerUi.ActionCard).route)
		elif c is UiButton:
			out.append((c as UiButton).route)
	return out


func default_focus() -> Control:
	if _scroll == null:
		return first_focusable(self)
	for r in ["fight", "refight"]:
		var t := find_route(r)
		if t != null:
			return t
	var fs := _scroll.focusables()
	return fs[0] if not fs.is_empty() else null


func right_stick_scroll_target() -> Control:
	return _scroll


func _section(text: String) -> void:
	_scroll.content.add_child(UiTheme.label(text.to_upper(), "Eyebrow"))


func _caption(text: String, variation := "Caption") -> void:
	_scroll.content.add_child(UiTheme.label(text, variation, true))


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 14)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.content.add_child(g)
	return g


# CAMP / TRAINING / FIGHT WEEK --------------------------------------------------------------------

func _build_camp() -> void:
	if not ctrl.is_booked():
		_section("No fight booked")
		_caption("Train one stat this week, or rest. A week without a fight booked costs %s popularity and brings new offers (see OFFERS)." % CareerUi.num(float(ctrl.rules.get("idle_week_pop", 0.6))))
		_train_grid()
		return
	var card := ctrl.fight_card()
	if bool(card["interrupted"]):
		_banner("This bout was interrupted before it was scored. It is fought again: the same opponent, arena and seed, no penalty.")
	var missing: Array = card["missing"]
	if not missing.is_empty():
		_banner("This fight can't be made: %s is not installed. Call it off without a penalty, or re-enable the mod." % ", ".join(PackedStringArray(missing)))
	_scroll.content.add_child(_fight_card(card))
	if not missing.is_empty():
		var cb := UiButton.new("CALL THE FIGHT OFF (no penalty)", "", "close")
		cb.route = "call_off"
		cb.set_help("Call the fight off", "The fight cannot be made with the installed content, so it is called off without a penalty. New offers come in.")
		cb.pressed.connect(_call_off)
		_scroll.content.add_child(cb)
	elif bool(card["fight_week"]):
		var fb := UiButton.new("FIGHT  ·  vs %s" % str(card["opp"]["name"]).to_upper(), "PrimaryButton", "fight")
		fb.route = "fight"
		fb.custom_minimum_size = Vector2(0, 96)
		fb.set_help("It's fight night", "Step into the cage: %s rounds under Cage Rules, three judges and a referee." % str(card["rounds_label"]))
		fb.pressed.connect(_fight)
		_scroll.content.add_child(fb)
		_caption(str(card["condition_line"]), "BodyStrong")
	else:
		_train_grid()
	var plan: Array = card["plan"]
	if not plan.is_empty():
		_caption("Camp so far: %s" % " › ".join(PackedStringArray(plan)))
	if missing.is_empty():
		var pb := UiButton.new("PULL OUT OF THE FIGHT…", "DangerButton", "close")
		pb.route = "pull_out"
		pb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		pb.custom_minimum_size = Vector2(560, 0)
		pb.set_help("Pull out", "Withdraw from this fight: %s The week moves on and new offers come in." % flow.withdraw_terms())
		pb.pressed.connect(_ask_pull_out)
		_scroll.content.add_child(pb)


func _banner(text: String) -> void:
	var b := UiTheme.panel("PanelBanner")
	var h := UiTheme.hbox(UiTheme.GAP_S)
	h.add_child(UiIcons.rect("warning", 34, UiTheme.WARNING))
	var l := UiTheme.label(text, "BodyStrong", true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	b.add_child(h)
	_scroll.content.add_child(b)


## The booked fight in one card: promotion, tier, title and the camp week on top; the two fighters
## (the opponent with danger tag, bot tier and home town) and the terms on the left; the six-stat
## comparison on the right (YOU / THEM / GAP; the gap is written out with its sign, colour only
## reinforces it). Compact, so the card and the next action share the screen at 1920x1080.
func _fight_card(card: Dictionary) -> Control:
	var p := UiTheme.panel("PanelCard")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiTheme.vbox(UiTheme.GAP_XS)
	p.add_child(v)
	var top := UiTheme.hbox(UiTheme.GAP_S)
	var org := UiTheme.label("%s · %s" % [str(card["org_name"]).to_upper(), str(card["tier_name"]).to_upper()], "Eyebrow")
	org.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(org)
	if bool(card["title"]):
		top.add_child(UiIcons.rect("trophy", 30, UiTheme.GOLD_HI))
		top.add_child(UiTheme.label("TITLE DEFENCE" if bool(card["defence"]) else "TITLE FIGHT", "ValueGold"))
	var weeks := int(card["weeks_left"])
	var total := int(card["weeks_total"])
	var when := "IT'S FIGHT WEEK"
	if not bool(card["fight_week"]):
		when = "CAMP WEEK %d OF %d · %d TO GO" % [clampi(total - weeks + 1, 1, maxi(1, total)), total, weeks]
	top.add_child(UiTheme.label(when, "CaptionStrong"))
	v.add_child(top)
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	v.add_child(cols)
	var left := UiTheme.vbox(2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var me: Dictionary = card["me"]
	var opp: Dictionary = card["opp"]
	left.add_child(UiTheme.label(str(me["billed"]), "H3", true))
	left.add_child(UiTheme.label("%s · %s · rating %d" % [str(me["fighter_name"]), str(me["record_text"]), int(me["rating"])], "Caption", true))
	left.add_child(UiTheme.label("VS", "Eyebrow"))
	left.add_child(UiTheme.label(str(opp["billed"]), "H3", true))
	left.add_child(UiTheme.label("%s · %s · rating %d · from %s" % [str(opp["fighter_name"]), str(opp["record_text"]), int(opp["rating"]), str(opp["from"])], "Caption", true))
	var tag := UiTheme.hbox(UiTheme.GAP_S)
	tag.add_child(UiTheme.label("%s (%s)" % [str(opp["danger"]), CareerUi.signed(float(opp["danger_diff"]))], CareerUi.danger_variation(str(opp["danger"]))))
	tag.add_child(UiTheme.label("Bot: %s" % str(opp["bot_tier_name"]), "Caption"))
	left.add_child(tag)
	var terms := "Purse %s + %s win bonus · %s rounds" % [CareerController.money_text(int(card["purse"])),
		CareerController.money_text(int(card["bonus"])), str(card["rounds_label"])]
	if str(card["arena_name"]) != "":
		terms += " · at %s" % str(card["arena_name"])
	left.add_child(UiTheme.label(terms, "BodyStrong", true))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 0)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for hd in ["", "YOU", "THEM", "GAP"]:
		g.add_child(_cell(hd, "CaptionStrong", hd == ""))
	for r in card["rows"]:
		var d: Dictionary = r
		g.add_child(_cell(str(d["label"]), "Body", true))
		g.add_child(_cell(str(int(d["me"])), "Value"))
		g.add_child(_cell(str(int(d["opp"])), "Value"))
		var gap := int(d["me"]) - int(d["opp"])
		g.add_child(_cell("even" if gap == 0 else ("%+d" % gap), "Success" if gap > 0 else ("Danger" if gap < 0 else "BodyMuted")))
	cols.add_child(g)
	if str(card["note"]) != "":
		v.add_child(UiTheme.label(str(card["note"]), "Caption", true))
	return p


func _cell(text: String, variation: String, left := false) -> Label:
	var l := UiTheme.label(text, variation)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	if not left:
		l.custom_minimum_size = Vector2(62, 0)
	return l


## The seven training choices: each stat with this week's exact gain (CareerController.preview_gain)
## and its gym room level, and Rest with its healing and the "you are healthy" hint. The stat's
## description shows in the help line under the list while its card has the focus.
func _train_grid() -> void:
	var g := _grid()
	for r in ctrl.train_rows():
		var d: Dictionary = r
		var id := str(d["id"])
		var card := CareerUi.ActionCard.new("rest" if id == "rest" else "train:%s" % id)
		var head := UiTheme.hbox(UiTheme.GAP_S)
		var t := UiTheme.label(str(d["label"]).to_upper(), "H3")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		if id == "rest":
			head.add_child(UiTheme.label("heal %s" % CareerUi.num(float(d["heal"])), "ValueGold"))
		elif bool(d["capped"]):
			head.add_child(UiTheme.label("maxed", "BodyMuted"))
		else:
			head.add_child(UiTheme.label("+%s" % CareerUi.num(float(d["gain_points"])), "ValueGold"))
		card.body.add_child(head)
		if id == "rest":
			var line := "You are healthy: probably train instead." if bool(d["healthy"]) else "Injuries heal %s× as fast this week." % CareerUi.num(float(d["rest_mult"]))
			card.body.add_child(UiTheme.label(line, "Warning" if bool(d["healthy"]) else "Caption", true))
			card.help_title = "Rest & recover"
		else:
			card.body.add_child(UiTheme.label("Now %d  ·  %s L%d" % [int(d["points"]), str(d["facility"]), int(d["facility_level"])], "Caption", true))
			card.help_title = str(d["label"])
		card.help_text = str(d["desc"])
		card.activated.connect(_train.bind(id))
		g.add_child(card)


# OFFERS ------------------------------------------------------------------------------------------

func _build_offers() -> void:
	if ctrl.is_booked():
		var o: Dictionary = ctrl.booked().get("offer", {})
		_section("Booked")
		_caption("You are booked against %s. New offers come in after the fight." % str(o.get("opp", {}).get("name", "?")), "Body")
		var gb := UiButton.new("TO YOUR CAMP", "", "forward")
		gb.route = "to_camp"
		gb.pressed.connect(func() -> void: select_tab("camp"))
		_scroll.content.add_child(gb)
	else:
		var rows := ctrl.offer_rows()
		_section("This week's offers")
		if rows.is_empty():
			_caption("Nobody is calling this week. Train or rest, and new offers come in.", "Body")
		for r in rows:
			_scroll.content.add_child(_offer_card(r))
	var hints: Dictionary = ctrl.hints()
	for line in hints["lines"]:
		_caption(str(line))


func _offer_card(o: Dictionary) -> Control:
	var card := CareerUi.ActionCard.new("offer:%s" % str(o["id"]))
	var opp: Dictionary = o.get("opp", {})
	var top := UiTheme.hbox(UiTheme.GAP_S)
	var org := UiTheme.label("%s · %s" % [str(o.get("org_name", "")).to_upper(), str(o["tier_name"]).to_upper()], "Eyebrow")
	org.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(org)
	if bool(o.get("title", false)):
		top.add_child(UiIcons.rect("trophy", 30, UiTheme.GOLD_HI))
		top.add_child(UiTheme.label("TITLE DEFENCE" if bool(o.get("defence", false)) else "TITLE FIGHT", "ValueGold"))
	top.add_child(UiTheme.label("ACCEPT", "CaptionStrong"))
	top.add_child(UiIcons.rect("forward", 26, UiTheme.MUTED))
	card.body.add_child(top)
	var who := UiTheme.hbox(UiTheme.GAP_S)
	var nm := UiTheme.label("vs %s" % str(o["billed"]), "H3", true)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(nm)
	who.add_child(UiTheme.label("%s (%s)" % [str(o["danger"]), CareerUi.signed(float(o["danger_diff"]))], CareerUi.danger_variation(str(o["danger"]))))
	card.body.add_child(who)
	card.body.add_child(UiTheme.label("%s · %s · rating %d · from %s  ·  Bot: %s" % [str(opp.get("fighter_name", "")), str(o["record_text"]),
		int(o["rating"]), str(opp.get("from", "")), str(o["bot_tier_name"])], "Body", true))
	var weeks := int(o.get("weeks", 4))
	card.body.add_child(UiTheme.label("Purse %s + %s to win  ·  in %d weeks  ·  %s rounds" % [CareerController.money_text(int(o.get("purse", 0))),
		CareerController.money_text(int(o.get("bonus", 0))), weeks, str(o["rounds_label"])], "BodyStrong", true))
	if str(o.get("note", "")) != "":
		card.body.add_child(UiTheme.label(str(o["note"]), "Caption", true))
	var missing: Array = o.get("missing", [])
	if not missing.is_empty():
		card.body.add_child(UiTheme.label("Can't be made: %s is not installed." % ", ".join(PackedStringArray(missing)), "Danger", true))
		card.set_enabled(false)
	card.help_title = "Accept"
	card.help_text = "Sign to fight %s in %d weeks." % [str(opp.get("name", "")), weeks]
	card.activated.connect(_accept.bind(str(o["id"])))
	card.refused.connect(func() -> void: _set_status("That fight can't be made with the installed content."))
	return card


# GYM ---------------------------------------------------------------------------------------------

func _build_gym() -> void:
	_section("Your gym")
	var tr: Dictionary = ctrl.rules.get("training", {})
	var heal: Dictionary = ctrl.rules.get("healing", {})
	_caption("Bank %s. A stat room makes that stat's training %d%% better per level; the head coach adds %d%% to all training; the recovery tank heals %s more a week." % [
		CareerController.money_text(int(ctrl.state["money"])), int(round(float(tr.get("room_per_level", 0.3)) * 100.0)),
		int(round(float(tr.get("coach_per_level", 0.12)) * 100.0)), CareerUi.num(float(heal.get("recovery_per_level", 4.0)))], "Body")
	var g := _grid()
	for r in ctrl.upgrade_rows():
		var d: Dictionary = r
		var card := CareerUi.ActionCard.new("gym:%s" % str(d["id"]))
		var head := UiTheme.hbox(UiTheme.GAP_S)
		var t := UiTheme.label(str(d["name"]).to_upper(), "H3")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		head.add_child(t)
		head.add_child(UiTheme.label("L%d/%d" % [int(d["level"]), int(d["max_level"])], "Value"))
		card.body.add_child(head)
		card.body.add_child(CareerUi.pips(int(d["level"]), int(d["max_level"])))
		card.body.add_child(UiTheme.label(str(d["effect"]), "BodyStrong", true))
		var buy := ""
		var variation := "ValueGold"
		if bool(d["maxed"]):
			buy = "MAXED"
			variation = "BodyMuted"
		elif bool(d["affordable"]):
			buy = "UPGRADE · %s" % CareerController.money_text(int(d["next_cost"]))
		else:
			buy = "NEED %s" % CareerController.money_text(int(d["next_cost"]))
			variation = "Danger"
		card.body.add_child(UiTheme.label(buy, variation))
		card.set_enabled(not bool(d["maxed"]) and bool(d["affordable"]))
		card.help_title = str(d["name"])
		card.help_text = str(d["desc"])
		card.activated.connect(_buy.bind(str(d["id"])))
		card.refused.connect(_set_status.bind("Already at the top level." if bool(d["maxed"]) else "Not enough money for %s yet." % str(d["name"])))
		g.add_child(card)


# HISTORY -----------------------------------------------------------------------------------------

func _build_history() -> void:
	var h := ctrl.history()
	_section("Fights")
	if h.is_empty():
		_caption("No fights yet. Accept an offer to get on a card.", "Body")
	var i := 0
	for e in h:
		var d: Dictionary = e
		var card := CareerUi.ActionCard.new("history:%d" % i)
		card.inert = true
		var res := str(d.get("result", ""))
		var top := UiTheme.hbox(UiTheme.GAP_S)
		top.add_child(UiTheme.label(res.to_upper(), CareerUi.result_variation(res)))
		var vs := UiTheme.label("vs %s (%d)" % [str(d.get("opp", "?")), int(d.get("opp_rating", 0))], "H3")
		vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vs.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top.add_child(vs)
		top.add_child(UiTheme.label(CareerState.week_label(int(d.get("week", 1))), "Caption"))
		card.body.add_child(top)
		var m := str(d.get("method", ""))
		var finish := m == "TKO" or m == "KO"
		card.body.add_child(UiTheme.label("%s%s  ·  %s  ·  popularity %s (now %s)" % [m, (" · R%d" % int(d.get("round", 1))) if finish else "",
			CareerController.money_text(int(d.get("pay", 0))), CareerUi.signed(float(d.get("d_pop", 0.0))), CareerUi.num(float(d.get("pop", 0.0)))], "Body", true))
		var org := str(d.get("org_name", ""))
		if bool(d.get("title", false)):
			org += " · TITLE FIGHT"
		if str(d.get("title_note", "")) != "":
			org += " · " + str(d["title_note"])
		card.body.add_child(UiTheme.label(org, "Caption", true))
		card.help_title = "Fight %d" % (h.size() - i)
		# the judges' totals (winner first) of a decision, or round and time of a stoppage
		card.help_text = "%s · %s rounds" % [CareerUi.method_line(d), CareerFight.rounds_label({"rounds": int(d.get("rounds", 3))})]
		_scroll.content.add_child(card)
		i += 1
	_section("News")
	var news := ctrl.news()
	if news.is_empty():
		_caption("Nothing in the papers yet.", "Body")
	# the news log in focusable chunks so the D-pad can read all of it
	var chunk: CareerUi.ActionCard = null
	var k := 0
	for e2 in news:
		if chunk == null or chunk.body.get_child_count() >= 6:
			chunk = CareerUi.ActionCard.new("news:%d" % k)
			chunk.inert = true
			chunk.help_title = "News"
			chunk.help_text = "What happened in your career, newest first (the last %d items)." % int(ctrl.rules.get("news_cap", 60))
			_scroll.content.add_child(chunk)
			k += 1
		var row := UiTheme.hbox(UiTheme.GAP_S)
		var wl := UiTheme.label(str((e2 as Dictionary)["week_label"]), "Caption")
		wl.custom_minimum_size = Vector2(250, 0)
		row.add_child(wl)
		var tl := UiTheme.label(str((e2 as Dictionary)["text"]), "Body", true)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tl)
		chunk.body.add_child(row)


# --- actions -------------------------------------------------------------------------------------

func _train(id: String) -> void:
	var hurt := CareerState.injury_total(ctrl.state)
	var r := ctrl.train(id)
	if not bool(r["ok"]):
		_set_status(str(r["error"]))
		return
	var msg := ""
	if id == "rest":
		var healed := hurt - CareerState.injury_total(ctrl.state)
		msg = "Rested: %s damage healed." % CareerUi.num(healed) if hurt > 0.0 else "Rested a week (you were already healthy)."
	else:
		msg = "%s +%s (now %d)." % [ctrl.stat_label(id), CareerUi.num(float(r["gain"]) * 100.0), int(round(float(r["after"]) * 100.0))]
	if bool(r["fight_ready"]):
		msg += " Fight week: step in when you are ready."
	_set_status("")
	UiNav.toast(msg, "success", 2.5)
	_refresh("fight" if bool(r["fight_ready"]) else ("rest" if id == "rest" else "train:%s" % id))


func _accept(offer_id: String) -> void:
	if not ctrl.accept(offer_id):
		_set_status(ctrl.last_error)
		return
	var b: Dictionary = ctrl.booked()
	UiNav.toast("Signed: %s in %d weeks." % [str(b["offer"]["opp"].get("name", "?")), int(b.get("weeks_left", 0))], "success", 3.0)
	_set_status("")
	_tabs.select(0, false)
	_refresh()


func _buy(id: String) -> void:
	var r := ctrl.buy_upgrade(id)
	if not bool(r["ok"]):
		_set_status(str(r["error"]))
		return
	UiNav.toast("%s is now level %d." % [str(ctrl.facility(id).get("name", id)), int(r["level"])], "success", 2.5)
	_set_status("")
	_refresh("gym:%s" % id)


func _fight() -> void:
	if not flow.fight():
		_set_status(flow.last_error)
		Audio.sfx("ui_error")


func _ask_pull_out() -> void:
	var o: Dictionary = ctrl.booked().get("offer", {})
	App.dialog("Pull out of this fight?", "%s The week moves on and %s finds someone else." % [flow.withdraw_terms(), str(o.get("org_name", "the promoter"))],
		[{"label": "Pull out", "id": "pull", "danger": true}, {"label": "Keep the fight", "id": "keep", "cancel": true, "default": true}],
		_on_pull_out)


func _on_pull_out(id: String) -> void:
	if id != "pull":
		return
	if not ctrl.withdraw():
		_set_status(ctrl.last_error)
		return
	UiNav.toast("You pulled out of the fight. %s" % flow.withdraw_terms(), "warning", 4.0)
	_refresh()


func _call_off() -> void:
	if not ctrl.cancel_booked():
		_set_status(ctrl.last_error)
		return
	UiNav.toast("The fight was called off. No penalty.", "info", 3.0)
	_refresh()


func on_back() -> bool:
	if flow != null:
		flow.show_slots()
	else:
		App.goto("career")
	return true


func _unhandled_input(event: InputEvent) -> void:
	if is_top() and _tabs != null and (event.is_action_pressed("ui_tab_prev") or event.is_action_pressed("ui_tab_next")):
		get_viewport().set_input_as_handled()
		_tabs.step(-1 if event.is_action_pressed("ui_tab_prev") else 1)
		return
	super(event)
