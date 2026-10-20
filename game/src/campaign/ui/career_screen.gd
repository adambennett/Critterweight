extends Screen
## Career slots ("career", CMP-08): the active profile's three career saves (CareerStore.list).
## Each slot shows name "nick", fighter, W-L-D, standing or Champion, Year/Week and when it was last
## saved (design contract D7) — or its error: a damaged or inconsistent save offers MOVE ASIDE (a
## confirmation with Keep / Move aside; the files go to retired/, never deleted), a newer-format
## save is only described (it is never touched). Actions: CONTINUE (the hub), NEW CAREER (an empty
## slot), RETIRE (danger confirmation: the save is moved aside and the slot frees, D3) and, when the
## booked bout was interrupted by a crash, RE-FIGHT (D4: the identical bout, no penalty).
## params: {catalog?: CampaignCatalog, flow_script?: Script (a CareerFlow subclass, tests)}.
## Back: the main menu (it is pushed from there; reached by goto from the hub it goes there too).

var catalog: CampaignCatalog
var store: CareerStore
var flow_script: Script = null
var _scroll: FocusScroll
var _help: HelpPanel
var _rows: Array = []


func on_enter(p: Dictionary) -> void:
	var c = p.get("catalog", null)
	catalog = c if c is CampaignCatalog else CareerFlow.default_catalog()
	var fs = p.get("flow_script", null)
	flow_script = fs if fs is Script else null
	store = CareerStore.new()
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.8)
	var f := build_frame("Campaign", "Career")
	(f["prompts"] as PromptBar).set_prompts(std_prompts())
	var body: VBoxContainer = f["body"]
	body.add_child(UiTheme.label("One fighter, one career: take fights, train between bouts, climb nine promotions and chase the belt. Everything saves as you go.", "Caption", true))
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UiTheme.panel("PanelSolid", 18.0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	cols.add_child(left)
	_scroll = FocusScroll.new(14)
	left.add_child(_scroll)
	var right := UiTheme.vbox(UiTheme.GAP_M)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(560, 0)
	cols.add_child(right)
	var poster := UiTheme.panel("PanelPoster", 28.0)
	right.add_child(poster)
	var pv := UiTheme.vbox(UiTheme.GAP_S)
	poster.add_child(pv)
	pv.add_child(UiTheme.label("HOW A CAREER WORKS", "Eyebrow"))
	for line in ["Each week you train one stat or rest. Accept a fight offer and the weeks until it are your camp.",
			"Wins (and quick finishes) make you popular; popularity brings bigger promotions, bigger purses and, at the top, a title shot.",
			"Purses buy gym upgrades. Damage you take heals over the weeks and slows training while it lasts.",
			"Bouts are three rounds under Cage Rules: three judges score every round and the referee stops it after five knockdowns in one."]:
		pv.add_child(UiTheme.label(line, "Body", true))
	_help = HelpPanel.new(_scroll)
	_help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_help.custom_minimum_size = Vector2(0, 150)
	right.add_child(_help)
	_rebuild()
	play_intro()


func rows() -> Array:
	return _rows


func _rebuild(focus_route := "") -> void:
	_scroll.clear()
	_rows = store.list(CareerFlow.profile_key(), catalog)
	var c := _scroll.content
	c.add_child(UiTheme.label("CAREER SLOTS", "Eyebrow"))
	for r in _rows:
		c.add_child(_slot_panel(r))
	_scroll.wrap_focus.call_deferred()
	_focus.call_deferred(focus_route)


func _slot_panel(r: Dictionary) -> Control:
	var n := int(r["slot"])
	var box := UiTheme.panel("PanelCard")
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# the slot's details on the left, its actions stacked on the right (three slots fit at 1280x800)
	var row := UiTheme.hbox(UiTheme.GAP_M)
	box.add_child(row)
	var v := UiTheme.vbox(UiTheme.GAP_XS)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UiTheme.label("SLOT %d" % n, "Eyebrow"))
	var buttons := UiTheme.vbox(UiTheme.GAP_S)
	buttons.custom_minimum_size = Vector2(300, 0)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not bool(r["occupied"]):
		v.add_child(UiTheme.label("Empty slot", "BodyMuted"))
		var nb := _button("NEW CAREER", "PrimaryButton", "plus", "new:%d" % n, "New career",
			"Pick a fighter, a ring name and a difficulty, and start at the bottom of the regional circuit.")
		nb.pressed.connect(_new_career.bind(n))
		buttons.add_child(nb)
		row.add_child(buttons)
		return box
	var s: Dictionary = r.get("summary", {})
	if not bool(r["ok"]):
		if not s.is_empty():
			v.add_child(UiTheme.label(CareerFight.billed_name(str(s.get("name", "")), str(s.get("nick", ""))), "H3", true))
		v.add_child(UiTheme.label(str(r["error"]), "Danger", true))
		if bool(r.get("newer", false)):
			v.add_child(UiTheme.label("It stays as it is: continue it with that version of the game.", "Caption", true))
			return box
		v.add_child(UiTheme.label("Move it aside to use this slot again: the files go to the retired folder, they are never deleted.", "Caption", true))
		var ab := _button("MOVE ASIDE…", "DangerButton", "folder", "aside:%d" % n, "Move aside",
			"Moves this save (and its backup copies) into the careers' retired folder so the slot can hold a new career. Nothing is deleted.")
		ab.pressed.connect(_ask_move_aside.bind(n))
		buttons.add_child(ab)
		row.add_child(buttons)
		return box
	var st := _state_of(n)
	# a read-only view of the save (no store: nothing is repaired or written from the slot list)
	var probe: CareerController = CareerController.new(catalog, st) if not st.is_empty() else null
	var title := CareerFight.billed_name(str(s.get("name", "")), str(s.get("nick", "")))
	var head := UiTheme.hbox(UiTheme.GAP_S)
	if bool(s.get("champion", false)):
		head.add_child(UiIcons.rect("trophy", 38, UiTheme.GOLD_HI))
	var tl := UiTheme.label(title, "H3")
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	v.add_child(head)
	v.add_child(UiTheme.label("%s  ·  %s  ·  %s" % [str(s.get("fighter_name", "")), _record(s), str(s.get("standing", ""))], "Body", true))
	var when := CareerUi.saved_text(int(s.get("saved_at", 0)))
	var diff := str((CareerDefaults.for_catalog(catalog).get("difficulties", {}) as Dictionary).get(str(s.get("difficulty", "normal")), {}).get("name", str(s.get("difficulty", "")).capitalize()))
	v.add_child(UiTheme.label("%s  ·  %s%s" % [str(s.get("week_label", "")), diff, ("  ·  last saved " + when) if when != "" else ""], "Caption", true))
	var interrupted := probe != null and probe.interrupted()
	if interrupted:
		var opp := str(probe.booked().get("offer", {}).get("opp", {}).get("name", "your opponent"))
		v.add_child(UiTheme.label("Your fight against %s was interrupted. Fight it again: the same bout, no penalty." % opp, "Warning", true))
		var rb := _button("RE-FIGHT", "PrimaryButton", "fight", "refight:%d" % n, "Re-fight",
			"The bout stopped before it was scored (the game closed). It is fought again with the same opponent, arena and seed.")
		rb.pressed.connect(_refight.bind(n))
		buttons.add_child(rb)
	elif bool(s.get("booked", false)):
		var bk: Dictionary = probe.booked() if probe != null else {}
		var weeks := int(bk.get("weeks_left", 0))
		v.add_child(UiTheme.label("Booked: %s, %s." % [str(bk.get("offer", {}).get("opp", {}).get("name", "?")),
			"fight week" if weeks <= 0 else "in %d week%s" % [weeks, "" if weeks == 1 else "s"]], "BodyStrong", true))
	var cb := _button("CONTINUE", "PrimaryButton" if not interrupted else "", "forward", "continue:%d" % n, "Continue",
		"Back to the gym: train, check your offers and upgrade your gym.")
	cb.pressed.connect(_continue.bind(n))
	buttons.add_child(cb)
	var name_ := str(s.get("name", "this fighter"))
	var xb := _button("RETIRE…", "DangerButton", "close", "retire:%d" % n, "Retire",
		"Ends this career. The save is moved aside (never deleted) and the slot frees for a new career.")
	xb.pressed.connect(_ask_retire.bind(n, name_))
	buttons.add_child(xb)
	row.add_child(buttons)
	return box


func _record(s: Dictionary) -> String:
	var rec: Dictionary = s.get("record", {})
	return "%d-%d-%d" % [int(rec.get("w", 0)), int(rec.get("l", 0)), int(rec.get("d", 0))]


func _state_of(n: int) -> Dictionary:
	var r := store.load_slot(CareerFlow.profile_key(), n, catalog)
	return r["state"] if bool(r["ok"]) else {}


func _button(text: String, variation: String, icon: String, route: String, help_title: String, help_text: String) -> UiButton:
	var b := UiButton.new(text, variation, icon)
	b.route = route
	b.set_help(help_title, help_text)
	return b


func _focus(route: String) -> void:
	if not is_inside_tree() or App.top_screen() != self:
		return
	var target := find_route(route) if route != "" else null
	if target == null:
		target = default_focus()
	if target != null and target.is_visible_in_tree():
		target.grab_focus()


func find_route(route: String) -> Control:
	for b in _scroll.focusables():
		if b is UiButton and (b as UiButton).route == route:
			return b
	return null


func default_focus() -> Control:
	if _scroll == null:
		return null
	for prefix in ["refight:", "continue:", "new:"]:
		for b in _scroll.focusables():
			if b is UiButton and (b as UiButton).route.begins_with(prefix):
				return b
	var fs := _scroll.focusables()
	return fs[0] if not fs.is_empty() else null


func _continue(n: int) -> void:
	var r := CareerFlow.open_slot(catalog, store, n, flow_script)
	if not bool(r["ok"]):
		App.dialog("Can't continue", str(r["error"]), [{"label": "OK", "id": "ok", "default": true}])
		_rebuild("continue:%d" % n)
		return
	var f: CareerFlow = r["flow"]
	f.show_hub("camp")


func _refight(n: int) -> void:
	var r := CareerFlow.open_slot(catalog, store, n, flow_script)
	if not bool(r["ok"]):
		App.dialog("Can't continue", str(r["error"]), [{"label": "OK", "id": "ok", "default": true}])
		return
	var f: CareerFlow = r["flow"]
	if not f.fight():
		f.notice = f.last_error
		f.show_hub("camp")


func _new_career(n: int) -> void:
	App.push("career_new", {"slot": n, "catalog": catalog, "flow_script": flow_script})


func _ask_retire(n: int, name_: String) -> void:
	App.dialog("Retire %s?" % name_, "The save is moved aside.",
		[{"label": "Retire", "id": "retire", "danger": true}, {"label": "Keep fighting", "id": "keep", "cancel": true, "default": true}],
		_on_retire.bind(n))


func _on_retire(id: String, n: int) -> void:
	if id != "retire":
		return
	var r := CareerController.load_career(catalog, store, CareerFlow.profile_key(), n)
	var res := {}
	if bool(r["ok"]):
		var c: CareerController = r["ctrl"]
		res = c.retire()
	else:
		res = store.retire(CareerFlow.profile_key(), n)
	if bool(res.get("ok", false)):
		UiNav.toast("Career retired. Slot %d is free." % n, "info", 3.0)
	else:
		UiNav.toast(str(res.get("error", "The career could not be retired.")), "error", 5.0)
	_rebuild("new:%d" % n)


func _ask_move_aside(n: int) -> void:
	App.dialog("Move this save aside?", "It goes to the careers' retired folder (nothing is deleted) and slot %d frees for a new career." % n,
		[{"label": "Move aside", "id": "aside", "danger": true}, {"label": "Keep it", "id": "keep", "cancel": true, "default": true}],
		_on_move_aside.bind(n))


func _on_move_aside(id: String, n: int) -> void:
	if id != "aside":
		return
	var res := store.move_aside(CareerFlow.profile_key(), n)
	if bool(res.get("ok", false)):
		UiNav.toast("The save was moved aside. Slot %d is free." % n, "info", 3.0)
	else:
		UiNav.toast(str(res.get("error", "The save could not be moved.")), "error", 5.0)
	_rebuild("new:%d" % n)


func on_back() -> bool:
	CampaignUI.leave_campaign()
	return true
