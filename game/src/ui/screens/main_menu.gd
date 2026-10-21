extends Screen
## Main menu as a fight-night poster: categories on the left, a sub-menu column that slides in for
## categories with children, and a poster card on the right describing the focused entry.
## Entries whose screen does not exist yet (App.has_screen) are HIDDEN — a development-time rule;
## the lead verifies every entry exists before release. Hidden entries are logged once.
## Controller: up/down move, A or right opens a category, left/B closes it, B at the top asks to quit.

const ENTRIES := [
	{"id": "fight", "label": "Fight", "icon": "fight", "desc": "Step into the cage: quick fights, local versus with bots, practice and spectating.",
		"children": [
			{"id": "quick_fight", "label": "Quick Fight", "icon": "quick", "screen": "character_select", "params": {"mode": "quick"},
				"desc": "Pick a critter and go. Your opponent, the rules and the cage are chosen for you."},
			{"id": "versus", "label": "Versus", "icon": "versus", "screen": "versus_setup", "params": {"mode": "versus"},
				"desc": "Set up a local card: up to 8 fighters, bots at any skill tier, teams, rules presets and arenas."},
			{"id": "practice", "label": "Practice", "icon": "practice", "screen": "versus_setup", "params": {"mode": "practice"},
				"desc": "No clock, endless respawns. Work on your timing against a standing dummy or a bot."},
			{"id": "spectate", "label": "Spectate", "icon": "spectate", "screen": "spectate", "params": {},
				"desc": "Book a fight between bots, pick their skill tiers and watch from the director's chair."},
			{"id": "tutorial", "label": "Tutorial", "icon": "tutorial", "screen": "tutorial_menu", "params": {},
				"desc": "Granny Haymaker's corner: short lessons from footwork to your Ultimate, taught with your own moves."},
		]},
	{"id": "campaign", "label": "Campaign", "icon": "campaign", "desc": "A persistent fighter career, or a seeded fight card from the Undercard to the Title Card.",
		"children": [
			{"id": "career", "label": "Career", "icon": "star", "screen": "career", "params": {},
				"desc": "Build one fighter's career: take fights, train between bouts and chase the belt."},
			{"id": "off_the_street", "label": "Off the Street", "icon": "campaign", "screen": "campaign_menu", "params": {"variant": "off_the_street"},
				"desc": "A fresh run with nothing carried over. Climb The Dosage on skill alone."},
			{"id": "fight_camp", "label": "Fight Camp", "icon": "trophy", "screen": "hub", "params": {"from": "menu"},
				"desc": "Train between runs at The Cannery and keep your permanent upgrades."},
			{"id": "bookie", "label": "Bookie's Table", "icon": "random", "screen": "bookie", "params": {},
				"desc": "Teddy Two-Tooth's autobattler: build the fighter, pick the route, let the bots throw the punches."},
		]},
	{"id": "online", "label": "Online", "icon": "online", "screen": "online", "params": {},
		"desc": "Host or join matches and co-op runs over the internet or your local network."},
	{"id": "create", "label": "Create", "icon": "create", "desc": "Write your own rules and build your own cages.",
		"children": [
			{"id": "rules_editor", "label": "Rules Editor", "icon": "rules", "screen": "rules_editor", "params": {},
				"desc": "Rounds, timers, health, damage, respawns, hazards and mode options — saved as shareable presets."},
			{"id": "arena_editor", "label": "Arena Editor", "icon": "arena", "screen": "arena_editor", "params": {},
				"desc": "Place props, hazards and spawns, test-play the layout and share it."},
			{"id": "lab", "label": "AI Lab", "icon": "lab", "screen": "lab", "params": {},
				"desc": "Train bots on your own machine and pit them against the house fighters."},
			{"id": "mods", "label": "Mods", "icon": "mods", "screen": "mods", "params": {},
				"desc": "Enable, disable and arrange content packages and mod sets."},
		]},
	{"id": "compendium", "label": "Compendium", "icon": "info", "screen": "compendium", "params": {},
		"desc": "Meet every fighter, inspect their models and abilities, and learn the arenas, elements and rules."},
	{"id": "profile", "label": "Profile", "icon": "profile", "screen": "profile", "params": {},
		"desc": "Switch, create or rename profiles and check your record."},
	{"id": "settings", "label": "Settings", "icon": "settings", "desc": "Settings, controls, credits and patch notes.", "children": [
		{"id": "settings", "label": "Settings", "icon": "settings", "screen": "settings", "desc": "Display, sound, controls and accessibility."},
		{"id": "controls", "label": "Controls", "icon": "info", "screen": "controls", "desc": "Every keyboard and controller action."},
		{"id": "credits", "label": "Credits", "icon": "credits", "screen": "credits", "desc": "Who made this, and the licences of everything we built it with."},
		{"id": "patch_notes", "label": "Patch Notes", "icon": "info", "screen": "patch_notes", "desc": "Read every published release note, available offline."}]},
	{"id": "quit", "label": "Quit", "icon": "quit", "action": "quit", "desc": "Hang up the gloves for tonight."},
]

static var _reported_hidden := false
static var _reported_errors := false

var _items: Array[UiButton] = []
var _item_defs: Array[Dictionary] = []
var _sub_panel: PanelContainer
var _sub_box: VBoxContainer
var _sub_title: Label
var _sub_items: Array[UiButton] = []
var _open_index := -1
var _poster_title: Label
var _poster_body: Label
var _poster_eyebrow: Label
var _record: Label
var _bar: PromptBar


func on_enter(_p: Dictionary) -> void:
	MatchFlow.set_paused(false)
	MenuBackdrop.ensure()
	add_backdrop_gradient(0.95, 0.05)
	_build()
	_report_once()
	play_intro()
	Profiles.profile_changed.connect(_update_record)
	Audio.music(menu_track(), 1.0)


## Menu music (docs/AUDIO.md): the fight-night poster theme; Title Night once the profile has
## cleared a run.
static func menu_track() -> String:
	var records: Dictionary = Profiles.current.get("records", {})
	var runs: Dictionary = records.get("runs", {})
	for v in runs.values():
		if v is Dictionary and int((v as Dictionary).get("clears", 0)) > 0:
			return "title_night"
	return "fight_night_poster"


func _build() -> void:
	var m := UiTheme.margin(UiTheme.SCREEN_MARGIN, 52, 40)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	var outer := UiTheme.vbox(UiTheme.GAP_M)
	m.add_child(outer)
	var cols := UiTheme.hbox(UiTheme.GAP_L)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)
	# --- left: wordmark + categories
	var left := UiTheme.vbox(UiTheme.GAP_S)
	left.custom_minimum_size = Vector2(640, 0)
	cols.add_child(left)
	var wm := Wordmark.new(66.0)
	wm.arch = 0.12
	wm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(wm)
	var sub := UiTheme.label("THE CRITTERWEIGHT CIRCUIT  ·  GULLET BAY", "Eyebrow")
	left.add_child(sub)
	left.add_child(UiTheme.spacer(false, 18))
	var list := UiTheme.vbox(4)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(list)
	var hidden: Array[String] = []
	for e in ENTRIES:
		var d: Dictionary = e
		if not _entry_available(d, hidden):
			continue
		var b := UiButton.new(str(d["label"]).to_upper(), "MenuItem", str(d["icon"]))
		b.route = str(d["id"])
		b.help_title = str(d["label"])
		b.help_text = str(d.get("desc", ""))
		b.custom_minimum_size = Vector2(560, 62)
		b.add_theme_font_size_override("font_size", UiTheme.size("h3"))
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var idx := _items.size()
		b.pressed.connect(_activate.bind(idx))
		b.focus_entered.connect(_on_item_focus.bind(idx))
		if d.has("children"):
			# right opens the category (handled before Godot's focus navigation sees the event)
			b.gui_input.connect(func(ev: InputEvent) -> void:
				if ev.is_action_pressed("ui_right", false, true):
					b.accept_event()
					_open_sub(idx))
		list.add_child(b)
		_items.append(b)
		_item_defs.append(d)
	if not _reported_hidden and not hidden.is_empty():
		_reported_hidden = true
		Log.i("ui", "main menu: hidden entries (screens not available yet): %s" % ", ".join(hidden))
	for i in _items.size():
		var b := _items[i]
		b.focus_neighbor_top = b.get_path_to(_items[posmod(i - 1, _items.size())])
		b.focus_neighbor_bottom = b.get_path_to(_items[posmod(i + 1, _items.size())])
		b.focus_neighbor_right = b.get_path_to(b)
		b.focus_neighbor_left = b.get_path_to(b)
	# --- middle: sub-menu column (hidden until a category opens)
	_sub_panel = UiTheme.panel("PanelSolid")
	_sub_panel.custom_minimum_size = Vector2(480, 0)
	_sub_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sub_panel.visible = false
	cols.add_child(_sub_panel)
	_sub_box = UiTheme.vbox(UiTheme.GAP_S)
	_sub_panel.add_child(_sub_box)
	_sub_title = UiTheme.label("", "Eyebrow")
	_sub_box.add_child(_sub_title)
	cols.add_child(UiTheme.spacer())
	# --- right: poster card
	var poster := UiTheme.panel("PanelPoster")
	poster.custom_minimum_size = Vector2(560, 0)
	poster.size_flags_vertical = Control.SIZE_SHRINK_END
	cols.add_child(poster)
	var pv := UiTheme.vbox(UiTheme.GAP_S)
	poster.add_child(pv)
	_poster_eyebrow = UiTheme.label("TONIGHT AT THE GULLET", "Eyebrow")
	pv.add_child(_poster_eyebrow)
	_poster_title = UiTheme.label("", "H1", true)
	pv.add_child(_poster_title)
	_poster_body = UiTheme.label("", "Body", true)
	_poster_body.custom_minimum_size = Vector2(480, 120)
	pv.add_child(_poster_body)
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.GOLD, 0.5)
	rule.custom_minimum_size = Vector2(0, 3)
	pv.add_child(rule)
	var prof := UiTheme.hbox(UiTheme.GAP_S)
	prof.add_child(UiIcons.rect("profile", 34, UiTheme.MUTED))
	_record = UiTheme.label("", "BodyStrong", true)
	_record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof.add_child(_record)
	pv.add_child(prof)
	_update_record()
	# --- footer
	var foot := UiTheme.hbox(UiTheme.GAP_L)
	outer.add_child(foot)
	foot.add_child(UiTheme.label("v%s" % BuildInfo.label(), "Caption"))     # version + commit for bug reports
	_bar = PromptBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_bar)
	_set_prompts(false)


func _entry_available(d: Dictionary, hidden: Array[String]) -> bool:
	if d.has("children"):
		var any := false
		for c in d["children"]:
			var cd: Dictionary = c
			if App.has_screen(str(cd["screen"])):
				any = true
			else:
				hidden.append(str(cd["id"]))
		return any
	if d.has("screen"):
		if App.has_screen(str(d["screen"])):
			return true
		hidden.append(str(d["id"]))
		return false
	return true


func _set_prompts(in_sub: bool) -> void:
	_bar.set_prompts([{"actions": ["ui_accept"], "text": "Select"},
		{"actions": ["ui_cancel"], "text": "Close" if in_sub else "Quit", "call": App.back}])


func default_focus() -> Control:
	return _items[0] if not _items.is_empty() else null


func _on_item_focus(idx: int) -> void:
	var d := _item_defs[idx]
	_show_poster(d)
	# A clicked category stays open while the pointer crosses the poster or another
	# row. Only activating another entry or Back changes it.


func _show_poster(d: Dictionary) -> void:
	_poster_title.text = str(d["label"]).to_upper()
	_poster_body.text = str(d.get("desc", ""))


func _activate(idx: int) -> void:
	var d := _item_defs[idx]
	if d.has("children"):
		_open_sub(idx)
		return
	if str(d.get("action", "")) == "quit":
		_ask_quit()
		return
	_route(d)


func _route(d: Dictionary) -> void:
	var screen := str(d.get("screen", ""))
	if not App.has_screen(screen):
		UiNav.toast("%s is not available in this build yet." % str(d["label"]), "warning")
		return
	var p: Dictionary = d.get("params", {})
	App.push(screen, p.duplicate(true))


func _open_sub(idx: int) -> void:
	if _open_index == idx and _sub_panel.visible:
		if not _sub_items.is_empty():
			_sub_items[0].grab_focus()
		return
	_close_sub(false)
	_open_index = idx
	var d := _item_defs[idx]
	_sub_title.text = str(d["label"]).to_upper()
	for c in d["children"]:
		var cd: Dictionary = c
		if not App.has_screen(str(cd["screen"])):
			continue
		var b := UiButton.new(str(cd["label"]), "SubItem", str(cd.get("icon", "")))
		b.route = str(cd["id"])
		b.help_title = str(cd["label"])
		b.help_text = str(cd.get("desc", ""))
		b.custom_minimum_size = Vector2(420, 72)
		b.pressed.connect(_route.bind(cd))
		b.focus_entered.connect(_show_poster.bind(cd))
		_sub_box.add_child(b)
		_sub_items.append(b)
	var cat := _items[idx]
	for i in _sub_items.size():
		var b := _sub_items[i]
		b.focus_neighbor_left = b.get_path_to(cat)
		b.focus_neighbor_right = b.get_path_to(b)
		b.focus_neighbor_top = b.get_path_to(_sub_items[posmod(i - 1, _sub_items.size())])
		b.focus_neighbor_bottom = b.get_path_to(_sub_items[posmod(i + 1, _sub_items.size())])
	if not _sub_items.is_empty():
		cat.focus_neighbor_right = cat.get_path_to(_sub_items[0])
	cat.add_theme_color_override("font_color", UiTheme.GOLD_HI)
	cat.add_theme_color_override("icon_normal_color", UiTheme.GOLD_HI)
	_sub_panel.visible = true
	if not UiTheme.reduce_motion():
		_sub_panel.modulate.a = 0.0
		create_tween().tween_property(_sub_panel, "modulate:a", 1.0, UiTheme.ANIM)
	_set_prompts(true)
	Audio.sfx("ui_accept")
	if not _sub_items.is_empty():
		_sub_items[0].grab_focus()


func _close_sub(refocus: bool) -> void:
	if _open_index < 0:
		return
	var cat := _items[_open_index]
	cat.focus_neighbor_right = cat.get_path_to(cat)
	cat.remove_theme_color_override("font_color")
	cat.remove_theme_color_override("icon_normal_color")
	for b in _sub_items:
		_sub_box.remove_child(b)
		b.queue_free()
	_sub_items.clear()
	_sub_panel.visible = false
	var was := _open_index
	_open_index = -1
	_set_prompts(false)
	if refocus:
		_items[was].grab_focus()


func submenu_open() -> bool:
	return _open_index >= 0


## Visible top-level entries in order (tests, tooling).
func items() -> Array[UiButton]:
	return _items


## Opens a category's sub-menu by id ("fight", "campaign", "create"); false if not available.
func open_category(id: String) -> bool:
	for i in _items.size():
		if _items[i].route == id and _item_defs[i].has("children"):
			_open_sub(i)
			return true
	return false


func _ask_quit() -> void:
	App.dialog("Leave the Circuit?", "Quit CRITTERWEIGHT and return to the desktop?",
		[{"label": "Quit game", "id": "quit", "danger": true}, {"label": "Stay", "id": "stay", "cancel": true, "default": true}],
		func(id: String) -> void:
			if id == "quit":
				App.quit())


func on_back() -> bool:
	if _open_index >= 0:
		Audio.sfx("ui_back")
		_close_sub(true)
		return true
	_ask_quit()
	return true


func _update_record() -> void:
	if _record == null:
		return
	var st: Dictionary = Profiles.current.get("stats", {})
	_record.text = "%s   ·   W %d   L %d   D %d" % [Profiles.player_name().to_upper(), int(st.get("wins", 0)), int(st.get("losses", 0)), int(st.get("draws", 0))]


func _report_once() -> void:
	if _reported_errors:
		return
	_reported_errors = true
	if Settings.load_error != "":
		UiNav.toast(Settings.load_error, "warning", 7.0)
	if Profiles.last_error != "":
		UiNav.toast(Profiles.last_error, "warning", 7.0)
	if not Content.errors.is_empty():
		UiNav.toast("%d content problem(s) were found while loading. Details: Settings › Diagnostics." % Content.errors.size(), "warning", 6.0)
