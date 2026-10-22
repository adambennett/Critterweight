extends TestCase
## v0.9.18 Movesets in the player-facing UI (docs/design/MOVESET_COMBAT.md §9): the Compendium's
## pool, loadouts and Combat basics; the character select sheet per combat style; the loadout
## screen's validation and confirm; versus setup's Moves row; practice's Change moves (live, through
## the pause menu) and its shortcuts that never collide with Varga's pad layout; the HUD move cards
## (hold tag, charges, stamina-short, denied flash) locally and on a network mirror; the rebinding
## labels and the Controls reference. Real screens, driven through their own controls.
## Run: godot --headless --path game --fixed-fps 120 -- --test movesets_ui

const FURNACE := ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"]
const BRAWLER := ["ember_jab", "furnace_haymaker", "flare_rush", "cinder_shot"]

var _saved_profile := {}
var _saved_root := ""
var _saved_window := Vector2i.ZERO
var _saved_bindings := {}
var _saved_settings := {}


func before_each() -> void:
	_saved_window = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)
	_saved_settings = Settings.values.duplicate(true)
	Settings.values["gameplay.tutorial_prompts"] = true
	Settings.values["access.reduce_motion"] = true
	Settings.values["gameplay.pause_on_focus_loss"] = false
	_saved_root = Paths.root
	Paths.root = temp_dir("movesets_ui_%d" % Time.get_ticks_usec())
	_saved_profile = Profiles.current
	Profiles.current = Profiles.default_profile("movesets_ui", "Rookie")
	_saved_bindings = Controls.current_bindings()
	Controls.last_device = "keyboard"
	MatchFlow.set_paused(false)
	App.clear_screens()


func after_each() -> void:
	MatchFlow.set_paused(false)
	App.clear_screens()
	if App.current_scene != null:
		App.set_scene(null)
	Controls.apply_bindings(_saved_bindings)
	Controls.last_device = "keyboard"
	Settings.values = _saved_settings
	Profiles.current = _saved_profile
	Paths.root = _saved_root
	get_tree().root.size = _saved_window
	Engine.time_scale = 1.0


# --- helpers ------------------------------------------------------------------------------------

func _texts(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in root.find_children("*", "Label", true, false):
		if (n as Label).text != "":
			out.append((n as Label).text)
	return out


func _has_text(root: Node, text: String) -> bool:
	for t in _texts(root):
		if t.contains(text):
			return true
	return false


func _prompts(root: Node) -> Array:
	return root.find_children("*", "ButtonPrompt", true, false)


func _prompt_with(root: Node, text: String) -> ButtonPrompt:
	for p in _prompts(root):
		if (p as ButtonPrompt).text == text:
			return p
	return null


func _hud(sim: MatchSim, player := 0) -> FightHud:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := FightHud.new()
	layer.add_child(hud)
	hud.setup(sim, player)
	return hud


func _focusable(s: Screen, key: String) -> Control:
	for c in s.find_children("*", "Control", true, false):
		if (c as Control).has_meta("focus_key") and str((c as Control).get_meta("focus_key")) == key and (c as Control).is_visible_in_tree():
			return c
	return null


func _press_joy(button: JoyButton, settle := 3) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = true
	ev.pressure = 1.0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await wait_frames(1)
	var up := InputEventJoypadButton.new()
	up.device = 0
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await wait_frames(settle)


func _practice(creature: String, loadout: Array = []) -> MatchScene:
	var rules: Dictionary = Content.get_entry("rules", "practice").duplicate(true)
	var cfg := {"arena": "the_gullet", "rules": rules, "seed": 3, "no_record": true, "overlay_script": "res://src/ui/practice_overlay.gd",
		"fighters": [{"creature": creature, "team": 0, "kind": "player", "name": "Rookie", "loadout": loadout},
			{"creature": "dev_biped", "team": 1, "kind": "dummy", "name": "Dummy"}]}
	return MatchFlow.launch(cfg)


# --- Compendium ---------------------------------------------------------------------------------

func test_compendium_lists_the_pool_loadouts_and_combat_basics() -> void:
	var c := Content.creature("f_stoke")
	check(c != null and c.pool.size() == 8, "Stoke's finished pool loads (%d moves)" % (c.pool.size() if c else 0))
	var text := CompendiumData.fighter_text(c)
	for id in c.pool:
		var pm: PoolMove = c.pool[id]
		check(text.contains(pm.display_name), "the page text lists %s" % pm.display_name)
		check(text.contains(MovesUi.facts(pm)), "%s: category, cooldown and cost" % pm.display_name)
		for sid in pm.styles:
			check(text.contains(str((pm.styles[sid] as Dictionary)["name"])), "%s: style %s" % [pm.display_name, sid])
	for lk in c.loadouts:
		check(text.contains(str((c.loadouts[lk] as Dictionary)["name"])), "the page text names loadout %s" % lk)
	check(text.contains("Classic kit") and text.contains(str(CompendiumData.ABILITIES["f_stoke"][0])), "the Classic ability texts stay, for Classic")
	var s = App.goto("compendium")
	await wait_frames(4)
	var idx := -1
	for i in s.rows.size():
		if str(s.rows[i]["id"]) == "f_stoke":
			idx = i
	check(idx >= 0, "Stoke has a Compendium page")
	if idx < 0:
		return
	s._select_entry(idx)
	await wait_frames(3)
	var info: FighterInfo = s.fighter_info
	check(info.full, "the Compendium shows the full page")
	for id in c.pool:
		var pm: PoolMove = c.pool[id]
		var head := info.content.find_child("Move_" + str(id), true, false)
		check(head != null, "%s has its own entry" % pm.display_name)
		if head:
			check(_has_text(head, pm.display_name), "%s: its name" % pm.display_name)
			check(head.find_child("Category_" + pm.category, true, false) != null, "%s: its category chip (%s)" % [pm.display_name, pm.category])
		check(_has_text(info.content, MovesUi.how_to_use(pm, c)), "%s: how to use it" % pm.display_name)
		check(_has_text(info.content, MovesUi.facts(pm)), "%s: cooldown and cost" % pm.display_name)
		for line in MovesUi.style_lines(pm):
			check(_has_text(info.content, line), "%s: style '%s'" % [pm.display_name, line.substr(0, 20)])
	check(_has_text(info.content, "Hold to keep it going (up to 2.4 s), steer it with the stick"), "Flamethrower: hold to sustain and aim")
	check(_has_text(info.content, "Hold to charge, release to strike (a full charge becomes Furnace Haymaker)"), "Furnace Haymaker: hold to charge")
	check(info.content.find_child("Move_flamethrower", true, false) != null and _has_text(info.content.find_child("Move_flamethrower", true, false), "HOLD+AIM"), "the HOLD+AIM tag")
	for lk in c.loadouts:
		var l := info.content.find_child("Loadout_" + str(lk), true, false) as Label
		check(l != null and l.text.begins_with(str((c.loadouts[lk] as Dictionary)["name"])), "loadout %s listed" % lk)
	check(_has_text(info.content, "Furnace  (default)"), "the default loadout is marked")
	var vent := _prompt_with(info.content, "Steam Vent")
	check(vent != null, "loadout moves carry their input prompts")
	check(_has_text(info.content, "CLASSIC KIT"), "the Classic kit follows")
	# Combat basics: Movesets and Classic, with live bindings
	var guide := CompendiumData.entries("guide")
	check_eq(str(guide[0]["name"]), "Combat basics", "Combat basics opens the guide")
	var basics := str(guide[0]["text"])
	for w in ["Movesets", "Move 1", "Move 4", "Basic strike", "finisher", "HOLD+AIM", "stamina", "cooldown", "parry", "Dodge", "Grapple", "Ultimate", "element", "Classic", "Rules Editor", "Combat style"]:
		check(basics.contains(w), "Combat basics explains '%s'" % w)
	check(basics.contains("(%s)" % Controls.prompt_for("light")) and basics.contains("(%s)" % Controls.prompt_for("ability2")), "with the live bindings")


# --- Character select sheet ---------------------------------------------------------------------

func test_character_select_sheet_follows_the_combat_style() -> void:
	var s = App.goto("character_select", {"mode": "pick", "current": "f_stoke", "allow_random": true, "combat": "moves"})
	await wait_frames(6)
	var info: FighterInfo = s.get("_fighter_info")
	info.show_fighter("f_stoke")
	await wait_frames(2)
	check(_has_text(info.content, "MOVES · FURNACE"), "Movesets: the default loadout's moves")
	var c := Content.creature("f_stoke")
	for i in FURNACE.size():
		var p := info.content.find_child("MovePrompt_" + str(FURNACE[i]), true, false) as ButtonPrompt
		check(p != null, "%s on the sheet" % FURNACE[i])
		if p:
			check_eq(p.text, (c.pool[FURNACE[i]] as PoolMove).display_name, "named")
			check_eq(Array(p.actions), [MovesUi.slot_action(i)], "%s on its own input" % FURNACE[i])
			check(p.find_child("Category_" + (c.pool[FURNACE[i]] as PoolMove).category, true, false) != null, "with its category chip")
	check(_has_text(info.content, "ULTIMATE") and _prompt_with(info.content, "Meltdown") != null, "the Ultimate")
	check(not _has_text(info.content, "Cooldown 7.0 s"), "no Classic ability block in Movesets")
	# Classic: the v0.9.17 sheet
	s = App.goto("character_select", {"mode": "pick", "current": "f_stoke", "allow_random": true, "combat": "classic"})
	await wait_frames(6)
	info = s.get("_fighter_info")
	info.show_fighter("f_stoke")
	await wait_frames(2)
	check(not _has_text(info.content, "MOVES ·"), "Classic: no Movesets list")
	var vent := _prompt_with(info.content, "Steam Vent")
	check(vent != null and Array(vent.actions) == ["ability1"], "Classic: the abilities on their inputs")
	check(_has_text(info.content, str(CompendiumData.ABILITIES["f_stoke"][0])), "Classic: the v0.9.17 ability text")
	# the player's own saved loadout
	MovesUi.remember_loadout("f_stoke", BRAWLER)
	s = App.goto("character_select", {"mode": "pick", "current": "f_stoke", "allow_random": true, "combat": "moves", "player": true})
	await wait_frames(6)
	info = s.get("_fighter_info")
	info.show_fighter("f_stoke")
	await wait_frames(2)
	check(_has_text(info.content, "MOVES · BRAWLER"), "the player's saved loadout")
	check(info.content.find_child("MovePrompt_furnace_haymaker", true, false) != null, "with its moves")


# --- Loadout screen -----------------------------------------------------------------------------

func test_loadout_screen_validates_and_applies() -> void:
	var got: Array = []
	var s = App.push("loadout", {"creature": "f_stoke", "loadout": FURNACE, "title": "Fighter 1 moves",
		"on_done": func(lo: Array) -> void: got.append(lo.duplicate())})
	await wait_frames(4)
	check_eq(s.chosen(), FURNACE, "the rows start on the current loadout")
	check_eq(s.problem_shown(), "", "a valid loadout shows no problem")
	await capture_ui_evidence("moves-ordinary-loadout")
	var first: OptionRow = s.default_focus()
	check_eq(first.label_text, "Move 1  (%s)" % Controls.prompt_for("light"), "each row names its input")
	Controls.last_device = "gamepad"
	Controls.device_changed.emit("gamepad")
	check_eq(first.label_text, "Move 1  (X)", "and follows the device")
	Controls.last_device = "keyboard"
	Controls.device_changed.emit("keyboard")
	# the controller changes a row in place
	var row: OptionRow = s.default_focus()
	row.grab_focus()
	await wait_frames(1)
	var before = row.get_value()
	await _press_joy(JOY_BUTTON_DPAD_RIGHT)
	check(row.get_value() != before, "D-pad right cycles Move 1")
	s.set_slot(0, "flamethrower")
	check(s.problem_shown().contains("Flamethrower") and s.problem_shown().contains("twice"), "a move equipped twice is refused by name: '%s'" % s.problem_shown())
	s.set_slot(1, "cinder_shot")
	check(s.problem_shown().contains("basic"), "a loadout without a basic strike is refused: '%s'" % s.problem_shown())
	await capture_ui_evidence("moves-loadout-validation")
	s.confirm()
	await wait_frames(2)
	check(got.is_empty() and App.top_screen() == s, "an invalid loadout is not applied")
	s.set_slot(0, "ember_jab")
	s.set_slot(3, "")
	check_eq(s.problem_shown(), "", "three moves with a basic strike are fine")
	s.confirm()
	await wait_frames(2)
	check_eq(got, [["ember_jab", "cinder_shot", "steam_vent"]], "Done applies the loadout (empty slots dropped)")
	check(App.top_screen() == null, "and closes")
	# a recommended loadout in one press
	got.clear()
	s = App.push("loadout", {"creature": "f_stoke", "loadout": FURNACE, "on_done": func(lo: Array) -> void: got.append(lo.duplicate())})
	await wait_frames(4)
	var preset: UiButton = null
	for b in s.find_children("*", "UiButton", true, false):
		if (b as UiButton).route == "preset_brawler":
			preset = b
	check(preset != null, "the recommended loadouts are buttons")
	if preset:
		preset.pressed.emit()
	check_eq(s.chosen(), BRAWLER, "Brawler fills the rows")
	s.confirm()
	await wait_frames(2)
	check_eq(got, [BRAWLER], "and applies")


# --- Versus setup -------------------------------------------------------------------------------

func test_varga_loadout_names_techniques_without_claiming_generic_move_buttons() -> void:
	var s = App.push("loadout", {"creature": "f_varga"})
	await wait_frames(4)
	var first: OptionRow = s.default_focus()
	check_eq(first.label_text, "Technique 1", "Varga equips techniques, not an attack on a generic move button")
	check(_has_text(s, "limb and modifier strikes"), "the panel explains how the techniques are used")
	check_eq(s.problem_shown(), "", "the initial martial build is valid")
	Controls.last_device = "gamepad"
	Controls.device_changed.emit("gamepad")
	check_eq(first.label_text, "Technique 1", "switching device preserves the martial explanation")
	s.set_slot(0, "spiral_hook")
	check_eq(s.problem_shown(), "", "a technique can be replaced within its group")
	check(s.chosen().has("spiral_hook"), "the replacement is equipped")
	await capture_ui_evidence("moves-varga-techniques")


func test_versus_setup_moves_row_opens_the_loadout_and_keeps_the_pick() -> void:
	var vs = App.goto("versus_setup", {"mode": "versus"})
	await wait_frames(4)
	vs.slots()[0]["creature"] = "f_stoke"
	vs._rebuild("moves0")
	await wait_frames(3)
	var row := _focusable(vs, "moves0") as PickRow
	check(row != null, "Movesets rules: each fighter has a Moves row")
	if row == null:
		return
	check_eq(row.value_text(), "Furnace", "the recommended default")
	row.grab_focus()
	await wait_frames(1)
	await _press_joy(JOY_BUTTON_A, 4)
	check_eq(App.top_screen().screen_name, "loadout", "A on Moves opens the loadout screen")
	var ls = App.top_screen()
	ls._apply_preset("brawler")
	ls.confirm()
	await wait_frames(4)
	check_eq(App.top_screen(), vs, "back on the setup")
	check_eq(vs.slots()[0]["loadout"], BRAWLER, "the slot keeps the pick")
	check_eq(MovesUi.saved_loadout("f_stoke"), BRAWLER, "the player's pick is remembered for the fighter")
	row = _focusable(vs, "moves0") as PickRow
	check(row != null and row.value_text() == "Brawler", "the row names it")
	check_eq(vs.build_config()["fighters"][0]["loadout"], BRAWLER, "and the match gets it")
	# Classic rules: no Moves row, no loadout sent
	Content.register_runtime("rules", {"id": "t_classic_duel", "name": "Classic duel", "mode": "standard", "format": "duel", "teams": 2,
		"players": [2, 2], "rounds": 1, "round_time": 60, "lives": 1, "combat": "classic"}, "user")
	vs.setup["rules"] = "t_classic_duel"
	vs._rebuild("rules")
	await wait_frames(3)
	check(_focusable(vs, "moves0") == null, "Classic rules: no Moves row")
	check(not (vs.build_config()["fighters"][0] as Dictionary).has("loadout"), "Classic: no loadout")
	Content.unregister_runtime("rules", "t_classic_duel")


# --- Practice -----------------------------------------------------------------------------------

func test_practice_change_moves_applies_live_through_the_pause_menu() -> void:
	var ms := _practice("f_stoke", FURNACE)
	await wait_physics(10)
	var f: Fighter = ms.sim.fighters[0]
	var ov := ms.hud_layer.get_node_or_null("PracticeOverlay")
	check(ov != null, "the practice overlay is up")
	check_eq(f.loadout, FURNACE, "practice starts with the chosen loadout")
	check(ms.hud.move_card("m2") != null and ms.hud.move_card("m2").pool_id == "flamethrower", "HUD card for Move 2")
	f.charges_left["m3"] = 0
	f.cooldown_left["m3"] = 5.0
	f.stamina = 10.0
	MatchFlow.open_pause()
	await wait_frames(3)
	check_eq(App.top_screen().screen_name, "pause", "Start opens the pause menu")
	var pause = App.top_screen()
	var mv: UiButton = null
	for b in pause.find_children("*", "UiButton", true, false):
		if (b as UiButton).route == "change_moves":
			mv = b
	check(mv != null, "the pause menu has Change moves in practice")
	if mv == null:
		return
	mv.grab_focus()
	await wait_frames(1)
	await _press_joy(JOY_BUTTON_A, 4)
	check_eq(App.top_screen().screen_name, "loadout", "it opens the loadout screen")
	var ls = App.top_screen()
	check(ls.get("_in_game") == true, "over the paused match (never the menu backdrop)")
	check(App.current_scene == ms and get_tree().paused, "the match stays, paused")
	check_eq(ls.chosen(), FURNACE, "on the current loadout")
	ls._apply_preset("brawler")
	ls.confirm()
	await wait_frames(4)
	check_eq(App.top_screen().screen_name, "pause", "Done returns to the pause menu")
	check_eq(f.loadout, BRAWLER, "the new loadout is equipped live")
	check_eq(f.slot_move("m2").id, "furnace_haymaker", "Move 2 is the new move")
	check_eq(int(f.charges_left.get("m3", -1)), 1, "charges restored")
	check_near(float(f.cooldown_left.get("m3", 0.0)), 0.0, 0.001, "cooldowns cleared")
	check_near(f.stamina, f.max_stamina, 0.01, "stamina refilled")
	var card := ms.hud.move_card("m2")
	check(card != null and card.pool_id == "furnace_haymaker" and card.hold_text() == "HOLD", "the HUD's cards follow (Move 2: HOLD)")
	check(ms.hud.move_card("m3") != null and ms.hud.move_card("m3").pool_id == "flare_rush", "Move 3 card")
	check_eq(MovesUi.saved_loadout("f_stoke"), BRAWLER, "remembered for the fighter")
	check_eq((MatchFlow.last_config["fighters"][0] as Dictionary).get("loadout", []), BRAWLER, "Restart fight keeps the new moves")
	await _press_joy(JOY_BUTTON_START, 4)
	check(App.top_screen() == null and not get_tree().paused, "Start resumes the fight")
	await capture_ui_evidence("moves-practice-live-brawler")
	MatchFlow.quit_to_menu()
	await wait_frames(2)


func test_practice_shortcuts_never_collide_with_the_fighter_layout() -> void:
	# ordinary layout: D-pad left/right, View and LS are free, the shortcuts work
	var ms := _practice("f_stoke", FURNACE)
	await wait_physics(6)
	var ov = ms.hud_layer.get_node("PracticeOverlay")
	var pad_next := InputEventJoypadButton.new()
	pad_next.button_index = JOY_BUTTON_DPAD_RIGHT
	pad_next.pressed = true
	check(not ov.collides(pad_next), "D-right is free in the ordinary layout")
	var b0: String = ov.current_behavior()
	ov._unhandled_input(pad_next)
	check(ov.current_behavior() != b0, "D-right cycles the dummy")
	Controls.last_device = "gamepad"
	ov._rebuild_prompts()
	var bar: PromptBar = ov.get("_bar")
	check(bar.find_prompt("Dummy") != null and bar.find_prompt("Record") != null and bar.find_prompt("Reset") != null, "pad shortcuts shown")
	check(bar.find_prompt("Practice menu") != null, "Change moves on a pad: the practice menu (Start)")
	MatchFlow.quit_to_menu()
	await wait_frames(2)
	# Varga's Cage Rules layout uses every one of those inputs: the shortcuts stand down
	Controls.last_device = "keyboard"
	ms = _practice("f_varga")
	await wait_physics(6)
	ov = ms.hud_layer.get_node("PracticeOverlay")
	for jb in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_BACK, JOY_BUTTON_LEFT_STICK]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = jb
		ev.pressed = true
		check(ov.collides(ev), "button %d is one of Varga's fight inputs" % jb)
	var b1: String = ov.current_behavior()
	ov._unhandled_input(pad_next)
	check_eq(ov.current_behavior(), b1, "D-right (Varga's ability 2) does not cycle the dummy")
	var f5 := InputEventKey.new()
	f5.physical_keycode = KEY_F5
	f5.pressed = true
	check(not ov.collides(f5), "F5 is free in both layouts")
	Controls.last_device = "gamepad"
	ov._rebuild_prompts()
	bar = ov.get("_bar")
	check(bar.find_prompt("Dummy") == null and bar.find_prompt("Record") == null and bar.find_prompt("Reset") == null, "no colliding pad shortcut is offered")
	check(bar.find_prompt("Practice menu") != null, "Start's practice menu is")
	Controls.last_device = "keyboard"
	ov._rebuild_prompts()
	bar = ov.get("_bar")
	check(bar.find_prompt("Record") != null and bar.find_prompt("Reset") != null, "keyboard shortcuts stay")
	# the pause menu carries the tools for him
	MatchFlow.open_pause()
	await wait_frames(3)
	var pause = App.top_screen()
	var routes := []
	for b in pause.find_children("*", "UiButton", true, false):
		routes.append((b as UiButton).route)
	check(routes.has("practice_record") and routes.has("practice_reset"), "pause menu: record and reset")
	var dummy: OptionRow = null
	for r in pause.find_children("*", "OptionRow", true, false):
		if (r as OptionRow).key == "practice_dummy":
			dummy = r
	check(dummy != null, "pause menu: the dummy row")
	if dummy:
		dummy.grab_focus()
		await wait_frames(1)
		var b2: String = ov.current_behavior()
		await _press_joy(JOY_BUTTON_DPAD_RIGHT)
		check(ov.current_behavior() != b2, "the row changes the dummy with the controller")
	check(routes.has("change_moves"), "Varga can change his equipped techniques from the practice menu")
	var change: UiButton = null
	for b in pause.find_children("*", "UiButton", true, false):
		if (b as UiButton).route == "change_moves":
			change = b
	if not check(change != null, "the martial Change moves control is reachable"):
		return
	change.grab_focus()
	await _press_joy(JOY_BUTTON_A, 4)
	check_eq(App.top_screen().screen_name, "loadout", "Varga's practice menu opens his technique loadout")
	var ls = App.top_screen()
	var f: Fighter = ms.sim.fighters[0]
	var alternate := str(f.creature.loadouts.keys()[1])
	var expected: Array = f.creature.loadouts[alternate]["moves"]
	ls._apply_preset(alternate)
	var help: HelpPanel = ls.get("_help")
	check_eq((help.get("_title") as Label).text, (f.creature.pool[expected[0]] as PoolMove).display_name,
		"the focused technique description follows the alternate preset")
	await capture_ui_evidence("moves-practice-varga-techniques")
	ls.confirm()
	await wait_frames(4)
	check_eq(f.loadout, expected, "the alternate martial build applies live")
	check(not f.move_overrides.is_empty(), "its limb techniques are rebuilt")
	check_eq(MovesUi.saved_loadout("f_varga"), expected, "the practice selection is saved for Varga")
	check_eq((MatchFlow.last_config["fighters"][0] as Dictionary).get("loadout", []), expected, "Restart fight retains the martial build")
	check_eq(App.top_screen().screen_name, "pause", "Done returns to the paused practice match")
	App.pop()
	await wait_frames(2)
	MatchFlow.quit_to_menu()
	await wait_frames(2)


# --- HUD ----------------------------------------------------------------------------------------

func test_hud_move_cards_hold_charges_stamina_and_denied_flash() -> void:
	var d: Dictionary = Content.creature_entry("f_stoke").duplicate(true)
	d["id"] = "t_stoke_two_shots"
	(d["movepool"]["cinder_shot"] as Dictionary)["charges"] = 2
	var c := CreatureDef.from_dict(d, Callable(), "test")
	check(c.is_valid(), "test kit: %s" % str(c.errors))
	var sim := make_sim("the_gullet", {"rounds": 1, "round_time": 0, "combat": "moves"},
		[{"creature": c, "team": 0, "source": null, "loadout": ["ember_jab", "flamethrower", "cinder_shot", "steam_vent"]},
		{"creature": "f_dredge", "team": 1, "source": null}])
	var f: Fighter = sim.fighters[0]
	f.controller_kind = "player"
	var hud := _hud(sim)
	await wait_frames(4)
	var ids := ["ember_jab", "flamethrower", "cinder_shot", "steam_vent"]
	for i in 4:
		var card := hud.move_card(Fighter.MOVE_SLOTS[i])
		check(card != null and card.pool_id == ids[i], "card %d is %s" % [i + 1, ids[i]])
		if card:
			check_eq(Array(card.actions), [FightHud.MOVE_ACTIONS[i]], "card %d on its input" % [i + 1])
			check_eq(card.binding_text(), Controls.prompt_for(str(FightHud.MOVE_ACTIONS[i])), "card %d shows the live binding" % [i + 1])
	check(not hud._ability_prompts.has("ability1"), "no Classic ability card in Movesets")
	check(hud._ability_prompts.has("juice"), "the Ultimate card")
	check_eq(hud.move_card("m2").hold_text(), "HOLD+AIM", "Flamethrower: HOLD+AIM")
	check_eq(hud.move_card("m1").hold_text(), "", "a tap move has no tag")
	var shot := hud.move_card("m3")
	hud._process(0.0)
	var charges := shot.find_child("Charges", true, false) as Label
	check(charges != null and charges.visible and charges.text == "×2", "two charges: ×2")
	f.charges_left["m3"] = 1
	f.cooldown_left["m3"] = 3.0
	hud._process(0.0)
	check(charges.text == "×1" and shot.available, "one charge left, still usable")
	f.charges_left["m3"] = 0
	hud._process(0.0)
	check(not shot.available and shot.find_child("CooldownSeconds", true, false).text == "3", "no charge: the cooldown veil and seconds")
	f.charges_left["m3"] = 2
	f.cooldown_left["m3"] = 0.0
	# stamina short: the move can't start below half its cost (Fighter._try_moves)
	f.stamina = 1.0
	hud._process(0.0)
	var state := hud.move_card("m2").find_child("MoveState", true, false) as Label
	check(not hud.move_card("m2").affordable and state.visible and state.text == "TIRED", "stamina-short: tinted and says TIRED")
	check(hud.move_card("m1").affordable, "a basic strike always starts")
	f.stamina = f.max_stamina
	hud._process(0.0)
	check(hud.move_card("m2").affordable and not state.visible, "affordable again")
	# the "Abilities" rule off: specials are off (said on the card), basics and heavies stay
	sim.rules["abilities"] = false
	hud._process(0.0)
	var off := hud.move_card("m3").find_child("MoveState", true, false) as Label
	check(hud.move_card("m3").locked and not hud.move_card("m3").available and off.visible and off.text == "OFF", "abilities off: the special says OFF")
	check(not hud.move_card("m1").locked and hud.move_card("m1").available, "the basic strike stays")
	sim.rules["abilities"] = true
	hud._process(0.0)
	# a denied press flashes the card (its own flash: the tutorial highlight can't clear it)
	hud.move_denied("m2", "stamina")
	check(hud.move_card("m2").is_flashing(), "denied: the card flashes")
	await get_tree().create_timer(0.5).timeout
	check(not hud.move_card("m2").is_flashing(), "the flash fades")
	# the strip fits both rows above the bottom, the subtitles above it
	await wait_frames(2)
	var strip := hud._hints
	var view := hud.get_global_rect()
	check(strip.get_global_rect().end.y <= view.end.y + 1.0, "strip on screen")
	check(hud._sub.get_global_rect().end.y <= strip.get_global_rect().position.y + 1.0, "subtitles above the move strip")
	check(strip.find_child("BasicHints", true, false) != null, "guard / dodge / grapple hints on the second row")
	# a live loadout change rebuilds the cards
	f.set_combat("moves", ["ember_jab", "steam_vent"])
	hud._process(0.0)
	check(hud.move_card("m2") != null and hud.move_card("m2").pool_id == "steam_vent" and hud.move_card("m3") == null, "cards follow the loadout")
	hud.get_parent().queue_free()
	# Classic: the v0.9.17 strip, unchanged
	var s2 := make_sim("the_gullet", {"rounds": 1, "round_time": 0}, [{"creature": "f_stoke", "team": 0, "source": null}, {"creature": "f_dredge", "team": 1, "source": null}])
	s2.fighters[0].controller_kind = "player"
	var h2 := _hud(s2)
	await wait_frames(3)
	check(h2._ability_prompts.has("ability1") and h2.move_card("m1") == null, "Classic: ability cards, no move cards")
	h2.get_parent().queue_free()


func _fd(stamina: float, cds: Dictionary, charges: Dictionary) -> Dictionary:
	return {"gen": 1, "state": Fighter.State.NEUTRAL, "flags": NetSnapshot.F_GROUNDED, "root": Vector3(0, 0.9, 0), "health": 100.0,
		"max_health": 110.0, "stamina": stamina, "max_stamina": 100.0, "poise": 60.0, "max_poise": 60.0, "hype": 10.0,
		"lives": 1, "target": -1, "cooldowns": cds, "charges": charges, "statuses": []}


func test_online_mirror_renders_the_same_cards() -> void:
	var rep := NetReplica.new()
	rep.reset({"tick_rate": 120, "snapshot_rate": 30, "match_id": 1, "fighters": [
		{"slot": 0, "gen": 1, "creature": "f_stoke", "scale": 1.0, "team": 0, "name": "Alice", "kind": "net", "despawned": false, "combat": "moves", "loadout": BRAWLER},
		{"slot": 1, "gen": 1, "creature": "f_dredge", "scale": 1.0, "team": 1, "name": "Bob", "kind": "bot", "despawned": false, "combat": "moves", "loadout": []}]})
	check_eq(str(rep.roster[0].get("combat", "")), "moves", "the replica keeps the combat style")
	check_eq(rep.roster[0].get("loadout", []), BRAWLER, "and the loadout")
	var mirror := NetHudMirror.new()
	mirror.build({"rules": {"rounds": 1, "round_time": 0, "mode": "standard", "combat": "moves"}, "mode": "standard", "you": 0}, rep)
	var sample := {"fighters": [_fd(80.0, {"m3": 2.5}, {"m1": 1, "m2": 1, "m3": 0, "m4": 1}), _fd(100.0, {}, {})], "entities": [],
		"mode": {"phase": MatchMode.Phase.FIGHT, "round": 0, "timer": 50.0, "flags": 1, "winner": -2, "round_winner": -2,
		"teams": [{"team": 0, "wins": 0, "score": 0}, {"team": 1, "wins": 0, "score": 0}], "status": "", "hud": {"rows": []}, "view": {}}}
	mirror.update(sample, 1.0 / 60.0)
	var hud := _hud(mirror.sim, 0)
	await wait_frames(3)
	hud._process(0.0)
	for i in 4:
		var card := hud.move_card(Fighter.MOVE_SLOTS[i])
		check(card != null and card.pool_id == BRAWLER[i], "mirror card %d is %s" % [i + 1, BRAWLER[i]])
	check_eq(hud.move_card("m2").hold_text(), "HOLD", "Furnace Haymaker: HOLD")
	var m3 := hud.move_card("m3")
	check(m3 != null and not m3.available and is_equal_approx(m3.remaining, 2.5), "cooldown and charges from the snapshot")
	# the host changes the loadout (a roster update): the cards follow
	rep.apply_roster_entry({"slot": 0, "gen": 1, "creature": "f_stoke", "scale": 1.0, "team": 0, "name": "Alice", "kind": "net", "despawned": false, "combat": "moves", "loadout": FURNACE})
	mirror.sync_roster(rep)
	hud._process(0.0)
	check(hud.move_card("m2") != null and hud.move_card("m2").pool_id == "flamethrower" and hud.move_card("m2").hold_text() == "HOLD+AIM", "the cards follow the roster")
	hud.move_denied("m2", "cooldown")
	check(hud.move_card("m2").is_flashing(), "a replicated denied press flashes the card")
	hud.get_parent().queue_free()
	await wait_frames(1)
	mirror.free_all()


# --- Rebinding and the Controls reference -------------------------------------------------------

func test_rebinding_labels_and_controls_reference_explain_both_styles() -> void:
	check_eq(BindingsFlow.label_of("light"), "Move 1 (Light in Classic)", "Move 1")
	check_eq(BindingsFlow.label_of("heavy"), "Move 2 (Heavy in Classic)", "Move 2")
	check_eq(BindingsFlow.label_of("ability1"), "Move 3 (Ability 1 in Classic)", "Move 3")
	check_eq(BindingsFlow.label_of("ability2"), "Move 4 (Ability 2 in Classic)", "Move 4")
	for a in ["light", "heavy", "ability1", "ability2"]:
		check(BindingsFlow.help_of(a).contains("Movesets") and BindingsFlow.help_of(a).contains("Classic"), "%s: help for both styles" % a)
	var ss = App.goto("settings", {"tab": "input"})
	await wait_frames(5)
	var kr: KeybindRow = ss.bind_row_for("ability1")
	check(kr != null and kr.get("_label").text == "Move 3 (Ability 1 in Classic)", "the rebinding row is labelled Move 3")
	check(kr != null and kr.kb_slot.help_extra.contains("Movesets"), "its help explains both styles")
	var cs = App.goto("controls")
	await wait_frames(4)
	var note := cs.find_child("StylesNote", true, false) as Label
	check(note != null and note.text.contains("MOVESETS") and note.text.contains("CLASSIC"), "the Controls reference explains both styles")
	# in a Movesets match the reference and the pause menu name the equipped moves
	App.clear_screens()
	var ms := MatchFlow.launch({"arena": "the_gullet", "rules": "duel", "seed": 5,
		"fighters": [{"creature": "f_stoke", "team": 0, "kind": "player", "name": "Rookie", "loadout": FURNACE},
			{"creature": "dev_biped", "team": 1, "kind": "bot", "difficulty": "rookie", "name": "Bot"}]})
	await wait_physics(6)
	var f: Fighter = ms.sim.fighters[0]
	check_eq(BindingsFlow.label_for("heavy", f), "Move 2: Flamethrower (hold, aim)", "Movesets: the equipped move")
	check_eq(BindingsFlow.label_for("juice", f), "Ultimate: Meltdown", "the Ultimate")
	App.push("controls", {"in_game": true})
	await wait_frames(4)
	var heavy_row: UiRow = null
	for r in App.top_screen().find_children("*", "UiRow", true, false):
		if (r as UiRow).key == "heavy":
			heavy_row = r
	check(heavy_row != null and heavy_row.label_text == "Move 2: Flamethrower (hold, aim)", "the in-match reference names the move")
	App.pop()
	await wait_frames(2)
	var rows: Array = load("res://src/ui/screens/pause_menu.gd").reference_rows(f)
	var labels := rows.map(func(r): return str(r[1]))
	check(labels.has("Flamethrower  (HOLD+AIM)") and labels.has("Ember Jab") and labels.has("Ultimate: Meltdown"), "the pause quick reference: %s" % str(labels))
	# glyph prompts keep working: a rebind reaches the move card
	var card := ms.hud.move_card("m2")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_H
	BindingsFlow.rebind("heavy", key)
	await wait_frames(2)
	check_eq(card.binding_text(), "H", "the Move 2 card shows the new key")
	# Classic: the Classic names
	MatchFlow.quit_to_menu()
	await wait_frames(2)
	var s2 := make_sim("the_gullet", {"rounds": 1, "round_time": 0}, [{"creature": "f_stoke", "team": 0, "source": null}, {"creature": "f_dredge", "team": 1, "source": null}])
	check_eq(BindingsFlow.label_for("heavy", s2.fighters[0]), "Heavy attack (hold to charge)", "Classic: the Classic action")
	var classic_rows: Array = load("res://src/ui/screens/pause_menu.gd").reference_rows(s2.fighters[0])
	check_eq(str(classic_rows[1][1]), "Light attack", "Classic quick reference unchanged")
