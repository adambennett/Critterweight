extends HubTestCase
## CMP-03 / UI-01 / UI-10 for THE CANNERY with the real HubScene (view, HUD, camera, player input)
## entered through Cannery.enter(): every hub board opens as an overlay with focus inside it, moves
## focus with the D-pad, and B closes it back to walking (without the fighter also grabbing); every
## board and the HUD fit and read at >= 18 px at 1280x800 (Steam Deck); the interact button —
## keyboard Enter or pad A, which is also Dodge — next to an NPC opens the conversation instead of
## dodging; the first secret found unlocks "ach_confidant". Input goes through the engine's input
## pipeline (Input.parse_input_event); user data is redirected to a temporary root.

var _root := ""
var _profile := {}
var _old_size := Vector2i.ZERO


func before_each() -> void:
	App.clear_screens()
	_root = Paths.root
	Paths.root = temp_dir("hub_ui_%d" % Time.get_ticks_usec())
	_profile = Profiles.current
	Profiles.current = Profiles.default_profile("hub_ui", "Hub Tester")
	CampaignProgression.ensure_fields(Profiles.current)
	_old_size = get_tree().root.size


func after_each() -> void:
	App.clear_screens()
	if App.current_scene != null:
		App.set_scene(null)
	get_tree().root.size = _old_size
	Paths.root = _root
	Profiles.current = _profile


# --- helpers -------------------------------------------------------------------------------------

## Input lands at the start of a physics step (like the OS events the engine flushes before it
## steps physics), so the sim's input poll in that step sees it as "just pressed".
func _send(ev: InputEvent) -> void:
	await get_tree().physics_frame
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func pad(button: JoyButton, settle := 3) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = true
	ev.pressure = 1.0
	await _send(ev)
	await wait_physics(2)
	var up := InputEventJoypadButton.new()
	up.device = 0
	up.button_index = button
	up.pressed = false
	await _send(up)
	await wait_frames(settle)


func key(code: Key, settle := 3) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	await _send(ev)
	await wait_physics(2)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	await _send(up)
	await wait_frames(settle)


func seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true, true).timeout


func top_name() -> String:
	var t := App.top_screen()
	return t.screen_name if t != null else "none"


func board() -> HubBoard:
	return App.top_screen() as HubBoard


func expect_focus(step: String) -> bool:
	var top := App.top_screen()
	var f := get_viewport().gui_get_focus_owner()
	var ok := top != null and f != null and is_instance_valid(f) and top.is_ancestor_of(f) and f.is_visible_in_tree()
	return check(ok, "focus inside the board after '%s' (top=%s, focus=%s)" % [step, top_name(), str(f.get_path()) if f != null else "none"])


func enter_hub(params := {}) -> HubScene:
	Cannery.enter(params)
	await wait_physics(8)
	await wait_frames(4)
	var sc := App.current_scene as HubScene
	check(sc != null and sc.sim != null, "Cannery.enter() puts the hub on screen")
	return sc


## Every board kind the hub opens (all six stations, a conversation with every NPC).
func board_specs() -> Array:
	var specs := [["pause", {}], ["map", {}], ["lockers", {}], ["records", {}], ["booth", {}], ["run", {}],
		["spar", {"opponent": "kid_lamprey"}], ["lessons", {}], ["shop", {}], ["rest", {}]]
	for st in HubServices.STATION_NAMES:
		specs.append(["station", {"station": str(st)}])
	for npc in HubLayout.NPC_SPOTS:
		specs.append(["talk", {"npc": str(npc)}])
	return specs


func _audit(tag: String, root: Node, vr: Rect2, px_per_du: float, needs_prompts := true) -> void:
	var bars := 0
	for b in root.find_children("*", "PromptBar", true, false):
		var bar := b as Control
		if not bar.is_visible_in_tree():
			continue
		bars += 1
		var r := bar.get_global_rect()
		check(r.end.y <= vr.end.y + 1.0 and r.position.y >= vr.position.y - 1.0 and r.end.x <= vr.end.x + 1.0 and r.position.x >= vr.position.x - 1.0,
			"%s: footer prompts on screen (bar %s, view %s)" % [tag, str(r), str(vr.size)])
	if needs_prompts:
		check(bars > 0, "%s: has a prompt bar" % tag)
	var smallest := 999.0
	var smallest_text := ""
	for n in root.find_children("*", "", true, false):
		var size_du := 0
		var text := ""
		if n is Label and (n as Label).is_visible_in_tree():
			text = (n as Label).text
			size_du = (n as Label).get_theme_font_size("font_size")
		elif n is Button and (n as Button).is_visible_in_tree():
			text = (n as Button).text
			size_du = (n as Button).get_theme_font_size("font_size")
		elif n is RichTextLabel and (n as RichTextLabel).is_visible_in_tree():
			text = (n as RichTextLabel).get_parsed_text()
			size_du = (n as RichTextLabel).get_theme_font_size("normal_font_size")
		if text.strip_edges() == "":
			continue
		var px := size_du * px_per_du
		if px < smallest:
			smallest = px
			smallest_text = text
	check(smallest < 999.0, "%s: has text to read" % tag)
	check(smallest >= 18.0 - 0.01, "%s: smallest text '%s' is %.1f px (< 18 px)" % [tag, smallest_text.substr(0, 40), smallest])


# --- tests ---------------------------------------------------------------------------------------

func test_every_board_has_focus_and_b_returns_to_walking() -> void:
	var sc := await enter_hub({"spot": "main_floor"})
	if sc == null:
		return
	check(App.top_screen() == null, "walking around: no menu on top (top=%s)" % top_name())
	var s0 := sc.sim.event_seq
	var grabbed := []
	for s in board_specs():
		var kind := str(s[0])
		var tag := "%s%s" % [kind, (":" + str((s[1] as Dictionary).values()[0])) if not (s[1] as Dictionary).is_empty() else ""]
		sc.open_board(kind, (s[1] as Dictionary).duplicate())
		await wait_frames(4)
		var b := board()
		check(b != null and b.kind == kind, "%s opens as a hub board (top=%s)" % [tag, top_name()])
		check(b != null and b.is_overlay, "%s is an overlay (the Cannery stays visible behind)" % tag)
		expect_focus("open %s" % tag)
		await pad(JOY_BUTTON_DPAD_DOWN)
		expect_focus("D-pad in %s" % tag)
		await pad(JOY_BUTTON_B, 4)
		check(App.top_screen() == null, "B closes %s back to walking (top=%s)" % [tag, top_name()])
		for i in 40:
			await wait_physics(1)
			if sc.player().state in [Fighter.State.GRABBING, Fighter.State.ATTACK]:
				grabbed.append(tag)
				break
	check(grabbed.is_empty(), "the B (Grab) that closed a board never reached the fighter (%s)" % str(grabbed))
	var dodges := sc.sim.events_since(s0).filter(func(ev): return str(ev["type"]) == "dodge")
	check(dodges.is_empty(), "nor did the D-pad/A presses inside the boards")


func test_boards_and_hud_fit_and_read_at_1280x800() -> void:
	var sc := await enter_hub({"spot": "main_floor"})
	if sc == null:
		return
	get_tree().root.size = Vector2i(1280, 800)
	await wait_frames(4)
	var vr := get_viewport().get_visible_rect()
	var px_per_du := get_viewport().get_final_transform().get_scale().y
	check(absf(px_per_du * vr.size.y - 800.0) < 2.0, "the viewport maps to 1280x800 (%.3f px/du)" % px_per_du)
	# stand by Granny so the HUD shows its interaction prompt too
	sc.mode.teleport(sc.player(), HubLayout.NAV["mf_granny"], deg_to_rad(228.0))
	await wait_physics(30)
	await wait_frames(2)
	check(sc.mode.interaction_available(sc.player()), "standing by Granny: an interaction prompt is offered")
	_audit("hud@1280x800", sc.hud, vr, px_per_du, false)
	for s in board_specs():
		var kind := str(s[0])
		var tag := "%s%s@1280x800" % [kind, (":" + str((s[1] as Dictionary).values()[0])) if not (s[1] as Dictionary).is_empty() else ""]
		sc.open_board(kind, (s[1] as Dictionary).duplicate())
		await wait_frames(5)
		var b := board()
		if not check(b != null, "%s opens" % tag):
			continue
		_audit(tag, b, vr, px_per_du)
		check(vr.grow(1.0).encloses(b.panel.get_global_rect()), "%s: the board fits on screen (%s in %s)" % [tag, str(b.panel.get_global_rect()), str(vr)])
		App.pop()
		await wait_frames(2)


func test_interact_talks_instead_of_dodging() -> void:
	var sc := await enter_hub({"spot": "main_floor"})
	if sc == null:
		return
	var f := sc.player()
	sc.mode.teleport(f, HubLayout.NAV["mf_granny"], deg_to_rad(228.0))
	await wait_physics(30)
	check_eq(str(sc.mode.focus_of(f).get("id", "")), "npc_granny", "standing by Granny")
	check(str(sc.hud.find_children("*", "Label", true, false).map(func(l): return (l as Label).text if (l as Label).is_visible_in_tree() else "")).contains("Granny"),
		"the HUD prompt names her")
	# keyboard: Enter
	var s0 := sc.sim.event_seq
	await key(KEY_ENTER, 4)
	var b := board()
	check(b != null and b.kind == "talk", "Enter next to Granny opens the conversation (top=%s)" % top_name())
	expect_focus("talk via Enter")
	await pad(JOY_BUTTON_B, 4)
	check(App.top_screen() == null, "B closes the conversation")
	await seconds(0.4)
	# pad: A is Dodge AND Interact — the interaction wins and the dodge is swallowed
	await pad(JOY_BUTTON_A, 4)
	b = board()
	check(b != null and b.kind == "talk", "pad A next to Granny opens the conversation (top=%s)" % top_name())
	var dodges := 0
	for ev in sc.sim.events_since(s0):
		if str(ev["type"]) == "dodge":
			dodges += 1
	check_eq(dodges, 0, "neither Enter nor A made the fighter dodge")
	await pad(JOY_BUTTON_B, 4)
	await seconds(0.4)
	# in the open, A still dodges
	sc.mode.teleport(f, Vector3(-4.0, 0, 0.0), 0.0)
	await wait_physics(30)
	check(sc.mode.focus_of(f).is_empty(), "nothing to talk to on the mats")
	var s1 := sc.sim.event_seq
	await pad(JOY_BUTTON_A, 2)
	await wait_physics(10)
	var dodged := false
	for ev2 in sc.sim.events_since(s1):
		if str(ev2["type"]) == "dodge":
			dodged = true
	check(dodged, "A dodges when there is nothing to interact with")
	check(App.top_screen() == null, "and opens nothing")


func test_first_secret_unlocks_confidant() -> void:
	check(Platform.achievement_defs().has("ach_confidant"), "the achievement exists")
	check(not Platform.is_unlocked("ach_confidant"), "a fresh profile has not unlocked it")
	var sc := await enter_hub({"spot": "locker_room"})
	if sc == null:
		return
	var f := sc.player()
	# secret #4: taunt at the belt case three times, then try the case
	sc.mode.teleport(f, HubLayout.BELT_CASE_POS + Vector3(0, 0, 1.1), PI)
	await wait_physics(30)
	var s0 := sc.sim.event_seq
	for i in 3:
		await key(KEY_T, 2)
		# A SceneTree timer with ignore_time_scale does not measure the fighter's
		# fixed-step clock (especially after accelerated Bookie's fights). Wait for
		# the actual recovery, without bypassing it or sending extra taunt presses.
		var recovery_start := f.time
		var budget := Engine.physics_ticks_per_second * 10
		while (f._taunt_cd > 0.0 or f.state != Fighter.State.NEUTRAL) and budget > 0:
			await wait_physics(1)
			budget -= 1
		check(budget > 0, "taunt %d recovers without stalling" % (i + 1))
		check(f.time - recovery_start < 3.0, "taunt %d recovers within three simulated seconds" % (i + 1))
		var seen := sc.sim.events_since(s0).filter(func(ev): return str(ev["type"]) == "taunt")
		check_eq(seen.size(), i + 1, "each T press starts exactly one taunt")
	var taunts := sc.sim.events_since(s0).filter(func(ev): return str(ev["type"]) == "taunt")
	check_eq(taunts.size(), 3, "three taunts from the T key")
	await wait_physics(10)
	check(sc.mode.secrets.case_unlocked, "three taunts: Kid Lamprey points out it's not even locked")
	await seconds(0.3)
	check_eq(str(sc.mode.focus_of(f).get("id", "")), "belt_case", "facing the belt case")
	await key(KEY_ENTER, 6)
	check(sc.state.has_secret("sec_belt_case_combo"), "the case opens: secret found")
	check(Platform.is_unlocked("ach_confidant"), "the first secret unlocks Ludlow's Confidant")
	var shown := sc.hud.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	check(str(shown).to_upper().contains("SECRET FOUND"), "the HUD announces it")
	check(int(sc.state.secrets_found()) == 1, "one of ten")
