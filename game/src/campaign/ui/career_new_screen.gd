extends Screen
## New career ("career_new", CMP-08; Cage Rules NEW CAREER): the base fighter (a playable
## Critterweight fighter: it shapes where the six stats start, training decides the rest), a ring
## name (required, <= 14, prefilled from the profile name), an optional nickname (<= 16) and the
## career difficulty (bot tiers one lower / as the opponent's level / one higher, design contract
## D5). The right side previews the fighter's model and starting stats. START CAREER creates the
## career in the slot (saved at once) and opens the hub.
## params: {slot?: 1..3 (default: the first free slot), catalog?, flow_script?}.
## No look editor: Critterweight fighters have fixed art (design contract §5.2).

var catalog: CampaignCatalog
var store: CareerStore
var flow_script: Script = null
var slot := 0
var rules := {}
var fighter := ""
var ring_name := ""
var nick := ""
var difficulty := "normal"
var _scroll: FocusScroll
var _help: HelpPanel
var _start: UiButton
var _preview: FighterPreview
var _preview_name: Label
var _preview_sub: Label
var _preview_stats: VBoxContainer
var _status: Label


func on_enter(p: Dictionary) -> void:
	var c = p.get("catalog", null)
	catalog = c if c is CampaignCatalog else CareerFlow.default_catalog()
	var fs = p.get("flow_script", null)
	flow_script = fs if fs is Script else null
	store = CareerStore.new()
	rules = CareerDefaults.for_catalog(catalog)
	slot = int(p.get("slot", 0))
	if not CareerStore.valid_slot(slot):
		slot = store.free_slot(CareerFlow.profile_key())
	var fighters := catalog.available_fighters()
	fighter = str(fighters[0]) if not fighters.is_empty() else ""
	ring_name = CareerState.clean_name(Profiles.player_name(), int(rules.get("name_max", 14)), "")
	difficulty = str(rules.get("difficulty_default", "normal"))
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.97, 0.75)
	var f := build_frame("Career · slot %d" % slot if slot > 0 else "Career", "New career")
	(f["prompts"] as PromptBar).set_prompts([{"actions": ["ui_accept"], "text": "Select"},
		{"actions": ["ui_left", "ui_right"], "text": "Change"},
		{"actions": ["ui_alt"], "text": "Start career", "call": _start_career},
		{"actions": ["ui_cancel"], "text": "Back", "call": App.back}])
	var body: VBoxContainer = f["body"]
	body.add_child(UiTheme.label("From the regional circuit to the big league. Your fighter only shapes where you start; training decides what you become.", "Caption", true))
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UiTheme.vbox(UiTheme.GAP_M)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	cols.add_child(left)
	var lp := UiTheme.panel("PanelSolid", 18.0)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(lp)
	_scroll = FocusScroll.new(8)
	lp.add_child(_scroll)
	_help = HelpPanel.new(_scroll)
	_help.size_flags_vertical = Control.SIZE_SHRINK_END
	_help.custom_minimum_size = Vector2(0, 250)
	left.add_child(_help)
	var poster := UiTheme.panel("PanelPoster", 24.0)
	poster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	poster.custom_minimum_size = Vector2(640, 0)
	cols.add_child(poster)
	var pv := UiTheme.vbox(UiTheme.GAP_S)
	poster.add_child(pv)
	_preview = FighterPreview.new()
	_preview.focus_mode = Control.FOCUS_NONE      # a picture here, not a focus stop
	_preview.custom_minimum_size = Vector2(440, 220)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(_preview)
	_preview_name = UiTheme.label("", "H3")
	pv.add_child(_preview_name)
	_preview_sub = UiTheme.label("", "Caption", true)
	pv.add_child(_preview_sub)
	_preview_stats = UiTheme.vbox(6)
	pv.add_child(_preview_stats)
	_status = UiTheme.label("", "Danger", true)
	_status.visible = false
	body.add_child(_status)
	_build_rows("start")
	_show_fighter()
	play_intro()


func _build_rows(focus_key := "") -> void:
	_scroll.clear()
	var c := _scroll.content
	c.add_child(UiTheme.label("YOUR FIGHTER", "Eyebrow"))
	var fighters := catalog.available_fighters()
	if fighters.is_empty():
		c.add_child(UiTheme.label("No playable fighters are installed, so a career cannot start.", "Danger", true))
	else:
		var names: Array = []
		for fid in fighters:
			names.append(CareerOffers.fighter_name(catalog, str(fid)))
		_option(c, "fighter", "Fighter", fighters, names, fighter,
			"Your base style. It shapes your starting stats (and how opponents of the same fighter are built). Training decides the rest.",
			func(v) -> void:
				fighter = str(v)
				_show_fighter())
	var nr := TextFieldRow.new("Ring name")
	nr.placeholder = "Required"
	nr.setup(ring_name, int(rules.get("name_max", 14)))
	nr.set_help("Ring name", "Required, up to %d characters. Promoters bill you under it." % int(rules.get("name_max", 14)))
	nr.set_meta("focus_key", "name")
	nr.value_changed.connect(func(v) -> void: ring_name = str(v))
	c.add_child(nr)
	var kr := TextFieldRow.new("Nickname")
	kr.placeholder = "Optional"
	kr.setup(nick, int(rules.get("nick_max", 16)))
	kr.set_help("Nickname", "Optional, up to %d characters, billed between your names: Rivet \"Low Tide\" Gravelgut." % int(rules.get("nick_max", 16)))
	kr.set_meta("focus_key", "nick")
	kr.value_changed.connect(func(v) -> void: nick = str(v))
	c.add_child(kr)
	var ids: Array = []
	var dnames: Array = []
	var diffs: Dictionary = rules.get("difficulties", {})
	var order := diffs.keys()
	order.sort_custom(func(a, b) -> bool: return int(diffs[a].get("order", 0)) < int(diffs[b].get("order", 0)))
	for k in order:
		ids.append(str(k))
		dnames.append(str(diffs[k].get("name", str(k).capitalize())))
	_option(c, "difficulty", "Difficulty", ids, dnames, difficulty, _difficulty_help(), func(v) -> void: difficulty = str(v))
	c.add_child(UiTheme.spacer(false, 4))
	_start = UiButton.new("START CAREER", "PrimaryButton", "fight")
	_start.route = "start"
	_start.set_help("Start career", "Creates the career in slot %d (saved right away) and opens your gym. Shortcut: Y / R." % slot)
	_start.custom_minimum_size = Vector2(0, 76)
	_start.set_meta("focus_key", "start")
	_start.disabled = fighter == "" or slot <= 0
	_start.pressed.connect(_start_career)
	c.add_child(_start)
	if slot <= 0:
		c.add_child(UiTheme.label("All three career slots are in use. Retire a career (or move a damaged save aside) first.", "Danger", true))
	_scroll.wrap_focus.call_deferred()
	_focus_key.call_deferred(focus_key)


## Difficulty help from the career rules (WP4's bot-tier rule, design contract D5).
func _difficulty_help() -> String:
	var d: Dictionary = (rules.get("difficulties", {}) as Dictionary).get(difficulty, {})
	var base := "Opponents get a bot tier from their level: Punching Bag, Journeyman, Contender, then Headliner at the top."
	return "%s %s It is fixed for the whole career." % [base, str(d.get("desc", ""))]


func _option(c: Control, key: String, title: String, ids: Array, names: Array, current, help: String, on_pick: Callable) -> void:
	var lbls: Array[String] = []
	for n in names:
		lbls.append(str(n))
	var r := OptionRow.new(title)
	r.setup(ids, lbls, current)
	r.set_help(title, help)
	r.set_meta("focus_key", key)
	r.value_changed.connect(func(v) -> void:
		on_pick.call(v)
		_build_rows(key))
	c.add_child(r)


func _focus_key(key: String) -> void:
	if not is_inside_tree() or App.top_screen() != self:
		return
	for f in _scroll.focusables():
		if f.has_meta("focus_key") and str(f.get_meta("focus_key")) == key and f.is_visible_in_tree():
			f.grab_focus()
			return


## The fighter preview: model, starting shape, the six starting stats and their rating.
func _show_fighter() -> void:
	for ch in _preview_stats.get_children():
		ch.queue_free()
	if fighter == "":
		_preview_name.text = ""
		_preview_sub.text = ""
		return
	var cd := Content.creature(fighter)
	if cd != null:
		_preview.show_fighter(cd)
	var stats := CareerState.starting_stats(rules, fighter)
	_preview_name.text = CareerOffers.fighter_name(catalog, fighter).to_upper()
	_preview_sub.text = "Starting stats · overall rating %d" % CareerState.rating(stats)
	var info: Dictionary = rules.get("stat_info", {})
	for k in CareerDefaults.STATS:
		var v := float(stats.get(k, 0.0))
		_preview_stats.add_child(StatBar.new(str(info.get(k, {}).get("label", k)), v, str(int(round(v * 100.0))), UiTheme.GOLD))


func default_focus() -> Control:
	return _start


func _process(dt: float) -> void:
	# a slow turn on the pedestal (not with Reduce motion)
	if _preview != null and _preview.camera != null and not UiTheme.reduce_motion():
		_preview.yaw += dt * 0.35


func _start_career() -> void:
	_status.visible = false
	if slot <= 0:
		_fail("All three career slots are in use.")
		return
	if fighter == "":
		_fail("Pick a fighter first.")
		return
	if ring_name.strip_edges() == "":
		_fail("Give your fighter a ring name.")
		_focus_key("name")
		return
	var r := CareerFlow.start_career(catalog, store, {"name": ring_name, "nick": nick, "fighter": fighter, "difficulty": difficulty,
		"seed": 0, "created_at": int(Time.get_unix_time_from_system()), "content_hash": Content.content_hash()}, slot, flow_script)
	if not bool(r["ok"]):
		_fail(str(r["error"]))
		return
	var f: CareerFlow = r["flow"]
	f.show_hub("camp")
	UiNav.toast("Career started. Regional promoters are calling.", "success", 3.0)


func _fail(msg: String) -> void:
	_status.text = msg
	_status.visible = true
	Audio.sfx("ui_error")
	UiNav.toast(msg, "error", 4.0)


func _unhandled_input(event: InputEvent) -> void:
	if is_top() and event.is_action_pressed("ui_alt"):
		get_viewport().set_input_as_handled()
		_start_career()
		return
	super(event)
