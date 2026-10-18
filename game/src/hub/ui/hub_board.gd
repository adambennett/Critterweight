class_name HubBoard
extends Screen
## Every menu in The Cannery is a diegetic board (HUB.md §6: "menus open as diegetic
## boards/ledgers"): Granny's clipboard, Needles' menu, Snappington's ledger and sign-up sheet, the
## corkboard map, your locker, the Wall of Fame, the booth desk, a conversation with an NPC.
## One Screen ("hub_board" in App.SCREENS) with params {kind, scene, ...}; each kind's content is
## built by a HubBoard* builder. Built from the UI widget library, so every board is fully operable
## with a controller (focus moves between rows, A selects, B closes) and with mouse/keyboard.
## The 3D hub stays visible behind (overlay); your fighter gets no input while a board is open.

const KIND_STYLE := {
	"station": ["#c9a227", "ClipboardPanel"], "run": ["#c9a227", "PanelPoster"], "spar": ["#ff5a5a", "PanelPoster"],
	"lockers": ["#8fa8b9", "PanelPoster"], "records": ["#c9a227", "PanelPoster"], "booth": ["#ffc43d", "PanelPoster"],
	"map": ["#b0844f", "PanelPoster"], "pause": ["#c9a227", "PanelSolid"], "lessons": ["#b06bff", "PanelPoster"],
	"shop": ["#8bd426", "PanelPoster"], "rest": ["#35c1c9", "PanelPoster"], "talk": ["#c9a227", "PanelSolid"], "info": ["#c9a227", "PanelSolid"],
}

var scene = null                 ## HubScene (null in some tests)
var kind := ""
var panel: PanelContainer
var header: VBoxContainer
var eyebrow_label: Label
var title_label: Label
var clout_label: Label
var list: FocusScroll
var help: HelpPanel
var status: Label
var prompts: PromptBar
var body_row: HBoxContainer
var extra := {}                  ## builder-owned state
var align := ""                  ## where frame() put the panel (HubScene frames your fighter beside it)


func on_enter(p: Dictionary) -> void:
	is_overlay = true
	scene = p.get("scene")
	kind = str(p.get("kind", "info"))
	match kind:
		"talk":
			HubBoardTalk.build(self, p)
		"station":
			HubBoardStation.build(self, p)
		"run":
			HubBoardStation.build_run(self, p)
		"spar":
			HubBoardSpar.build(self, p)
		"lockers":
			HubBoardSpar.build_lockers(self, p)
		"records":
			HubBoardSpar.build_records(self, p)
		"booth":
			HubBoardSpar.build_booth(self, p)
		"map":
			HubBoardMap.build(self, p)
		"pause":
			_build_pause()
		"lessons":
			_build_lessons()
		"shop":
			_build_shop()
		"drill":
			_build_drill()
		"rest":
			_build_rest()
		_:
			_build_info(p)
	# a board with nothing to select (an empty Wall of Fame, the map before Fast walk) still gets
	# a focused Close, so a controller always has somewhere to be
	if list != null and is_instance_valid(list) and not list.is_queued_for_deletion() and list.focusables().is_empty():
		button("Close", close, "Close", "Back to the Cannery.")
		focus_first()
	play_intro()


func hub_state() -> HubState:
	if scene != null:
		return scene.get("state")
	return HubState.new(Profiles.current)


func hub_mode() -> HubMode:
	return scene.get("mode") if scene != null else null


func services() -> HubServices:
	if scene != null:
		return scene.get("services")
	return HubServices.new(hub_state())


## Standard board chrome: a light dimmer, a diegetic panel (right side by default) with eyebrow,
## title and the Clout chip, a scrolling list, an optional help panel and the prompt bar.
func frame(eyebrow: String, title: String, width := 1020.0, with_help := true, align_ := "right") -> void:
	align = align_
	add_dimmer(0.38)
	var st: Array = KIND_STYLE.get(kind, ["#c9a227", "PanelPoster"])
	var m := UiTheme.margin(64, 52, 44)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var outer: BoxContainer = UiTheme.vbox(UiTheme.GAP_L) if align_ == "bottom" else UiTheme.hbox(UiTheme.GAP_L)
	m.add_child(outer)
	if align_ != "left":
		outer.add_child(UiTheme.spacer())
	if str(st[1]) == "ClipboardPanel":
		panel = ClipboardPanel.new()
	else:
		panel = UiTheme.panel(str(st[1]), 26.0)
	panel.custom_minimum_size = Vector2(width, 0)
	if align_ == "bottom":
		panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		panel.size_flags_vertical = Control.SIZE_SHRINK_END
		panel.custom_minimum_size = Vector2(width, 560)     # the line + three rows of options
	else:
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(panel)
	if align_ == "center":
		outer.add_child(UiTheme.spacer())
	var col := UiTheme.vbox(UiTheme.GAP_S)
	panel.add_child(col)
	var top := UiTheme.hbox(UiTheme.GAP_M)
	col.add_child(top)
	header = UiTheme.vbox(0)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eyebrow_label = UiTheme.label(eyebrow.to_upper(), "Eyebrow")
	eyebrow_label.add_theme_color_override("font_color", Color.from_string(str(st[0]), UiTheme.GOLD))
	title_label = UiTheme.label(title.to_upper(), "H2")
	header.add_child(eyebrow_label)
	header.add_child(title_label)
	top.add_child(header)
	var chip := UiTheme.panel("PanelChip", 10.0)
	var cv := UiTheme.vbox(0)
	var ct := UiTheme.label("CLOUT", "Caption")
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clout_label = UiTheme.label(str(hub_state().clout()), "ValueGold")
	clout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(ct)
	cv.add_child(clout_label)
	chip.add_child(cv)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(chip)
	body_row = UiTheme.hbox(UiTheme.GAP_M)
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body_row)
	list = FocusScroll.new(8)
	list.size_flags_stretch_ratio = 1.6
	body_row.add_child(list)
	if with_help:
		help = HelpPanel.new(list, "Details")
		help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# A scrollable details panel needs allocated height: shrink-to-content
		# would collapse its ScrollContainer to an empty strip.
		help.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# long rows must not squeeze the details into a one-word column (it would grow off screen)
		help.custom_minimum_size = Vector2(340, 0)
		body_row.add_child(help)
	status = UiTheme.label("", "Caption", true)
	status.custom_minimum_size = Vector2(400, 0)
	col.add_child(status)
	prompts = PromptBar.new()
	col.add_child(prompts)
	prompts.set_prompts([{"actions": ["ui_accept"], "text": "Select"}, {"actions": ["ui_cancel"], "text": "Close", "call": close}])


func refresh_clout() -> void:
	if clout_label:
		clout_label.text = str(hub_state().clout())


func set_status(text: String, variation := "Caption") -> void:
	if status:
		status.text = text
		status.theme_type_variation = variation


func button(text: String, cb: Callable, help_title := "", help_text := "", variation := "", icon := "") -> UiButton:
	var b := UiButton.new(text, variation, icon)
	b.set_help(help_title if help_title != "" else text, help_text)
	b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(0, 66)
	list.content.add_child(b)
	return b


func section(text: String) -> Label:
	var l := UiTheme.label(text.to_upper(), "Eyebrow")
	list.content.add_child(l)
	return l


func text_line(text: String, variation := "Body") -> Label:
	var l := UiTheme.label(text, variation, true)
	l.custom_minimum_size = Vector2(560, 0)
	list.content.add_child(l)
	return l


func clear_list() -> void:
	list.clear()


func focus_first() -> void:
	var fs := list.focusables()
	if not fs.is_empty():
		fs[0].call_deferred("grab_focus")


func default_focus() -> Control:
	if list == null:
		return null
	var fs := list.focusables()
	return fs[0] if not fs.is_empty() else null


func close() -> void:
	if not is_top():
		return
	Audio.ui("ui_close")
	App.pop()


## B closes the board (the hub has no other screen below it, and App.back() never pops the last one).
func on_back() -> bool:
	if App.stack.size() > 1:
		return false
	close()
	return true


func open_child(child_kind: String, p := {}) -> void:
	var q: Dictionary = p.duplicate()
	q["kind"] = child_kind
	q["scene"] = scene
	App.push("hub_board", q)


# ---- small boards ------------------------------------------------------------------------------

func _build_pause() -> void:
	frame("The Cannery", "Paused", 760.0, true, "center")
	var st := hub_state()
	button("Resume", close, "Resume", "Back to the Cannery.", "", "fight")
	button("Corkboard map", func() -> void: open_child("map"), "Corkboard map", "Where everything is, the secrets you've found and Fast walk.", "", "arena")
	button("Your locker", func() -> void: open_child("lockers"), "Your locker", "Change the fighter you walk around with and your cosmetics.", "", "profile")
	button("Settings", func() -> void: App.push("settings", {"in_game": true}), "Settings", "Display, audio, controls, accessibility.", "", "settings")
	button("Controls", func() -> void: App.push("controls", {"in_game": true}), "Controls", "Every action with your current bindings.", "", "gamepad")
	button("Leave the Cannery", _ask_leave, "Leave the Cannery", "Back to the main menu. Your Clout and progress are saved.", "DangerButton", "quit")
	set_status("Clout %d  ·  secrets %d / 10  ·  upgrades %d / 24" % [st.clout(), st.secrets_found(), st.upgrades_owned()])
	list.wrap_focus.call_deferred()


func _ask_leave() -> void:
	App.dialog("Leave the Cannery?", "Your Clout, upgrades and secrets are saved.",
		[{"label": "Leave", "id": "leave", "danger": true}, {"label": "Stay", "id": "stay", "cancel": true, "default": true}],
		func(id: String) -> void:
			if id == "leave":
				Cannery.leave())


func _build_lessons() -> void:
	frame("Granny's corner", "Lessons", 980.0)
	var list_ex := Tutorial.exercises()
	var done: Array = Tutorial.completed_ids()
	if list_ex.is_empty():
		text_line("No lessons are installed.")
	for i in list_ex.size():
		var ex: Dictionary = list_ex[i]
		var tick := "  ✓" if done.has(str(ex.get("id", ""))) else ""
		button("%d.  %s%s" % [i + 1, str(ex.get("title", ex.get("id", ""))), tick], _start_lesson.bind(i), str(ex.get("title", "")), str(ex.get("goal", "")))
	set_status("Lessons run in the practice cage with your current fighter. You come back here when you leave.")


func _start_lesson(i: int) -> void:
	var fid := "f_stoke"
	if scene != null:
		fid = scene.call("player").creature.id
	Profiles.save()
	# a plain route back (App screen "hub"), never a lambda: the tutorial keeps it in a static
	Tutorial.start(i, fid, {"screen": "hub", "params": {"spot": "main_floor", "from": "tutorial"}})


func _build_shop() -> void:
	frame("Needles' price board", "Tonight's menu", 1000.0)
	text_line("CATALOG PREVIEW · Visit a Shop node on your campaign map to buy items and services with Scrip. Nothing is sold in the Cannery.", "BodyStrong")
	var sv := services()
	var items := sv.shop_preview()
	if items.is_empty():
		text_line(sv.unavailable_reason() if not sv.available() else "Nothing on the board tonight.", "BodyMuted")
	var rarity_names := {"otc": "Over-the-Counter", "prescription": "Prescription", "black_market": "Black Market", "banned": "Banned"}
	for it in items:
		var d: Dictionary = it
		var b := button("%s   ·   %d Scrip" % [str(d["name"]), int(d["price"])], func() -> void: pass, str(d["name"]),
			"%s. %s" % [str(rarity_names.get(str(d["rarity"]), d["rarity"])), str(d.get("desc", ""))])
		b.sfx_accept = "ui_denied"
	section("Campaign shop services")
	text_line("Each campaign stall offers one service, alongside its stock. Rub-down (35 Scrip) removes side effects now. Antidote (30) gives a consumable to clear them later. Restock (25) rerolls that stall once. You can also sell supplements for half price.", "Caption")
	set_status("Preview only: Needles sells on the fight card, not in the Cannery.")


func _build_drill() -> void:
	frame("Ludlow's cannon", "Pick your pressure", 1000.0)
	text_line("45 seconds. Dodge, block or parry buckets. Parrying earns +5 streak. Leave the square to stop. Clout milestones are shared across difficulties.", "Caption")
	var descriptions := ["The original drill. Slow lobs with forgiving spread.", "More shots, shorter flight times and stronger movement prediction.", "Rapid fire with homing buckets. They stop steering just before impact: time your dodge!"]
	var i := 0
	for id: String in HubChumDrill.DIFFICULTIES:
		var level := id
		button(str(HubChumDrill.DIFFICULTIES[id]["name"]), func():
			var m := hub_mode()
			close()
			if m:
				m.start_activity("drill", "", level), str(HubChumDrill.DIFFICULTIES[id]["name"]), descriptions[i])
		i += 1
	focus_first()


func _build_rest() -> void:
	frame("Doc Sutura's table", "Patch-ups", 1000.0)
	var st := hub_state()
	var heal := 30 + 8 * st.upgrade_level("meta_ice_bath")
	var rows := [["Patch up", "Heal %d%% of your max HP%s." % [heal, " (Ice Bath upgrade included)" if st.upgrade_level("meta_ice_bath") > 0 else ""]],
		["Train", "Learn one technique (one of two offered)."], ["Rub-down", "Remove all side effects and heal 10%."],
		["Film study", "See the next act's elite and boss modifiers; +15 Hype carry."]]
	for r in rows:
		var b := button(str(r[0]), func() -> void: pass, str(r[0]), str(r[1]))
		b.sfx_accept = "ui_denied"
	if st.upgrade_level("meta_sutures") > 0:
		text_line("Sutures: you heal %d%% after every fight." % (4 * st.upgrade_level("meta_sutures")), "Success")
	set_status("Preview: on the fight card you pick ONE of these at each Rest stop.")


func _build_info(p: Dictionary) -> void:
	frame(str(p.get("eyebrow", "The Cannery")), str(p.get("title", "")), 900.0, false, "center")
	text_line(str(p.get("text", "")))
	button("OK", close)
