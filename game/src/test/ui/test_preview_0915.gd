extends CampaignTestCase
## v0.9.15 preview regression coverage. Hardware/audio taste remains a manual playtest.
var saved_settings := {}
var saved_root := ""
var saved_profile := {}
var saved_window := Vector2i.ZERO

class QuietFlow:
	extends CampaignFlow
	var fights := 0
	func launch_fight() -> void:
		fights += 1

func before_each() -> void:
	saved_window = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)
	saved_settings = Settings.values.duplicate(true)
	Settings.values["access.reduce_motion"] = true
	Settings.values["gameplay.pause_on_focus_loss"] = false
	saved_root = Paths.root
	Paths.root = temp_dir("preview_0915_%d" % Time.get_ticks_usec())
	saved_profile = Profiles.current
	Profiles.current = Profiles.default_profile("preview", "Rookie")
	CampaignProgression.ensure_fields(Profiles.current)

func after_each() -> void:
	App.clear_screens()
	App.set_scene(null)
	var table := App.get_node_or_null("BookieTable")
	if table:
		table.queue_free()
	get_tree().root.size = saved_window
	Settings.values = saved_settings
	Paths.root = saved_root
	Profiles.current = saved_profile
	Controls.last_device = "keyboard"
	super.after_each()

func joy(button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_frames(1)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await wait_frames(3)

func action(key: String) -> void:
	var ev := InputEventAction.new()
	ev.action = key
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_frames(1)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await wait_frames(3)

func button(root: Node, text: String) -> Button:
	for child in root.find_children("*", "Button", true, false):
		if (child as Button).text == text and (child as Control).is_visible_in_tree():
			return child
	return null

func flow() -> QuietFlow:
	var f := QuietFlow.new()
	f.catalog = cat()
	f.store = RunStore.new()
	f.ctrl = new_run()
	f._hook()
	return f

func test_editor_popup_keeps_controller_focus_and_share_toggles_all_controls() -> void:
	var s = App.goto("arena_editor")
	await wait_frames(8)
	s.vp.grab_focus()
	await joy(JOY_BUTTON_B)
	check(s._overlay != null, "B opens editor menu")
	var first := get_viewport().gui_get_focus_owner()
	check(first != s.vp and s._overlay.is_ancestor_of(first), "overlay receives focus after all deferred restores")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() != first, "D-pad navigates the actual popup")
	await joy(JOY_BUTTON_B)
	await joy(JOY_BUTTON_BACK)
	check(s._toolbar.is_ancestor_of(get_viewport().gui_get_focus_owner()), "Share enters toolbar controls")
	var controls: Array = s._panel_controls(s._palette_panel)
	check(controls.has(button(s, "Grid snap")), "grid snap belongs to menu navigation")
	check(controls.has(button(s, "Team")), "team belongs to menu navigation")
	var total: int = s.model.items.size()
	await joy(JOY_BUTTON_X)
	await joy(JOY_BUTTON_Y)
	check_eq(s.model.items.size(), total, "menu buttons do not edit the canvas")
	var before := get_viewport().gui_get_focus_owner()
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() != before, "menu focus moves through toolbar")
	s._toggle_panel(s._palette_panel)
	await wait_frames(2)
	check(not s._canvas_active(), "minimizing a sidebar keeps menu mode active")
	await joy(JOY_BUTTON_BACK)
	check(s.vp.has_focus(), "Share returns exclusively to canvas")

func test_editor_unique_default_and_overwrite_confirmation() -> void:
	var s = App.goto("arena_editor")
	await wait_frames(5)
	# Other UI tests may leave a different base in the editor's restored session.
	s._new_layout_on("gullet")
	await wait_frames(3)
	var original: String = s.model.name
	s._save()
	await wait_frames(3)
	var path := ArenaLibrary.path_for(s.model.id)
	check(FileAccess.file_exists(path), "first new layout saved")
	var before := FileAccess.get_file_as_string(path)
	s.model.description = "edited description"
	s._save()
	await wait_frames(3)
	check(s._overlay != null, "existing layout requires overwrite confirmation")
	check_eq(FileAccess.get_file_as_string(path), before, "file unchanged before approval")
	var accept := button(s, "Overwrite")
	check(accept != null, "overwrite action exists")
	if accept:
		accept.pressed.emit()
	await wait_frames(3)
	check(FileAccess.get_file_as_string(path) != before, "approved overwrite persists edits")
	s._new_layout_on("gullet")
	await wait_frames(5)
	check_eq(s.model.name, original + " 1", "new default does not reuse an existing name")

func test_compendium_custom_arena_actions_require_confirmation() -> void:
	var model := ArenaEditModel.new_from_base("gullet")
	var result := ArenaLibrary.save_layout(model.to_dict())
	check(bool(result["ok"]), "custom arena fixture saved")
	var s = App.goto("compendium")
	await wait_frames(4)
	s._select_section(2)
	await wait_frames(4)
	var index := -1
	for i in s.rows.size():
		if str(s.rows[i]["id"]) == ArenaLibrary.content_id(model.id):
			index = i
	check(index >= 0, "custom arena appears")
	if index < 0:
		return
	s._arena_action(index, "edit")
	await wait_frames(2)
	check_eq(App.top_screen().screen_name, "dialog", "edit asks before leaving compendium")
	await action("ui_cancel")
	check_eq(App.top_screen(), s, "cancelling edit stays in compendium")
	s._arena_action(index, "trash")
	await wait_frames(2)
	check(FileAccess.file_exists(result["path"]), "delete confirmation has not removed map")
	var yes := button(App.top_screen(), "Delete arena")
	check(yes != null, "delete confirm action")
	if yes:
		yes.pressed.emit()
	await wait_frames(4)
	check(not FileAccess.file_exists(result["path"]), "confirmed delete removes map from library")

func test_character_panel_scroll_and_shared_stats_glyphs() -> void:
	var s = App.goto("character_select", {"mode": "pick", "current": "f_jitters", "allow_random": true})
	await wait_frames(8)
	var info: FighterInfo = s.get("_fighter_info")
	s.default_focus().grab_focus()
	UiNav.ensure().scroll_focused(650)
	check(info.scroll_vertical > 0, "right stick scrolls fighter details from roster focus: size=%s content=%s max=%s page=%s focus=%s" % [info.size, info.content.size, info.get_v_scroll_bar().max_value, info.get_v_scroll_bar().page, get_viewport().gui_get_focus_owner()])
	var bars := 0
	var prompts := 0
	for child in info.content.get_children():
		if child is StatBar:
			bars += 1
		if child is ButtonPrompt:
			prompts += 1
	check_eq(bars, 5, "five segmented fighter stats")
	check(prompts >= 2, "abilities use live input glyphs")
	var c = App.goto("compendium")
	await wait_frames(6)
	check(c.get("fighter_info") is FighterInfo, "compendium uses the identical stat widget")

func test_rules_picker_has_hidden_cancel_and_patch_notes_archive() -> void:
	var s = App.goto("rules_editor")
	s._ask_new()
	await wait_frames(3)
	check(button(App.top_screen(), "Cancel") == null, "Cancel is not a duplicate mode option")
	await action("ui_cancel")
	check_eq(App.top_screen(), s, "B still dismisses the picker")
	var notes = App.goto("patch_notes")
	await wait_frames(4)
	check(notes.default_focus() != null, "offline patch notes have controller focus")
	var archive = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/patch_notes.json"))
	check(archive.size() >= 15, "archive contains every published version")

func test_map_has_scroll_room_no_intro_and_modal_blocks_nodes() -> void:
	var f := flow()
	f.show_current()
	await wait_frames(6)
	var s = App.top_screen()
	check(not CampaignUI.has_modal(s), "new campaign immediately shows the map without popup")
	check(s._map_view.size.y > s._map_scroll.size.y, "route has scroll room: map=%s scroll=%s screen=%s" % [s._map_view.size, s._map_scroll.size, s.size])
	check(s.find_child("RunStatus", true, false) != null, "map shows shared run stats")
	var first: Control = s.default_focus()
	first.grab_focus()
	CampaignUI.confirm(s, "Verify", "Modal shields the route", [{"id": "stay", "label": "STAY"}], func(_id): pass)
	await wait_frames(4)
	check(get_viewport().gui_get_focus_owner() != first, "background map yields focus to modal")
	for child in s.get_children():
		if child is Control and not child is CampaignUI.Modal:
			check(child.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED, "background descendants cannot receive focus")
	await action("ui_accept")
	check_eq((f.ctrl.state["path"] as Array).size(), 0, "confirming modal never enters a fight")

func test_bookie_abandon_targets_new_card_after_loss() -> void:
	var table := BookieTable.new()
	table.name = "BookieTable"
	App.add_child(table)
	table.setup(cat(), run_cfg())
	var f := BookieFlow.for_table(table)
	var old := table.ctrl
	old.abandon()
	table.deal(56789)
	check(f.ctrl == table.ctrl and f.ctrl != old, "flow follows freshly dealt controller")
	table.keep_going = true
	table.paused = true
	f.abandon()
	await wait_frames(3)
	check(table.ctrl.is_over(), "new card is abandoned")
	check(not table.keep_going and not table.paused, "abandon cannot loop or stay paused")
	check_eq(App.top_screen().screen_name, "bookie", "returns to accessible table controls")

func test_jukebox_order_shuffle_repeat_and_independent_contexts() -> void:
	var ids := Jukebox.tracks()
	check(ids.size() >= 2, "music library includes multiple playable tracks")
	if ids.size() < 2:
		return
	Settings.values["audio.jukebox"] = {"menu": {"mode": "ordered", "tracks": [ids[0], ids[1]]}}
	check_eq(Jukebox.choose("menu", "fallback"), ids[0], "ordered starts first")
	check_eq(Jukebox.choose("menu", "fallback", ids[0], true), ids[1], "ordered advances")
	check_eq(Jukebox.choose("menu", "fallback", ids[1], true), ids[0], "ordered loops")
	check_eq(Jukebox.choose("fight", "combat_a"), "combat_a", "menu playlist does not replace fight defaults")
	Settings.values["audio.jukebox"]["menu"]["mode"] = "shuffle"
	check_eq(Jukebox.choose("menu", "fallback", ids[0], true), ids[1], "shuffle avoids immediate repeat")
	Settings.values["audio.jukebox"]["menu"]["mode"] = "repeat"
	check_eq(Jukebox.choose("menu", "fallback", ids[0], true), ids[0], "repeat stays on first track")
	Settings.values["audio.jukebox"]["menu"]["tracks"] = []
	check_eq(Jukebox.choose("menu", "fallback"), "", "empty custom playlist is silent")

func test_all_health_cards_above_subtitles_and_glyph_cooldowns() -> void:
	var fighters := []
	for i in 8:
		fighters.append({"creature": "f_stoke", "team": i % 2, "source": "player" if i == 0 else "bot"})
	var sim := make_sim("the_gullet", {"rounds": 1, "round_time": 0}, fighters)
	sim.fighters[0].controller_kind = "player"
	var hud := FightHud.new()
	App.ui_layer.add_child(hud)
	hud.setup(sim, 0)
	hud.set_bottom_inset(132)
	await wait_frames(4)
	for card in hud.cards.values():
		check((card["box"] as Control).get_global_rect().end.y < hud._sub.get_global_rect().position.y, "every card stays clear of subtitle band")
	check(hud._ability_prompts.has("ability1"), "ability controls visible")
	sim.fighters[0].charges_left["ability1"] = 0
	sim.fighters[0].cooldown_left["ability1"] = 3.4
	hud._process(0.0)
	var prompt: CombatPrompt = hud._ability_prompts["ability1"]
	check_near(prompt.remaining, 3.4, 0.01, "live cooldown reaches glyph")
	var text := prompt.find_child("CooldownSeconds", true, false) as Label
	check(text != null and text.text == "4", "remaining seconds overlay the input glyph")
	sim.fighters[0].charges_left["ability1"] = 1
	hud._process(0.0)
	check(prompt.available and text.text == "", "remaining charge stays usable while another recharges")
	sim.fighters[0].cooldown_left["ability1"] = 0.0
	hud._process(0.0)
	check(prompt.available and text.text == "", "ready glyph has no cooldown text")
	sim.fighters[7].despawned = true
	hud._process(0.0)
	check(not (hud.cards[7]["box"] as Control).visible, "inactive wave slot has no stale health card")
	sim.fighters[7].despawned = false
	sim.fighters[7].display_name = "Next Wave"
	hud._process(0.0)
	check((hud.cards[7]["box"] as Control).visible and (hud.cards[7]["name"] as Label).text == "NEXT WAVE", "reused wave slot restores current fighter name")
	hud.queue_free()

func test_crate_foul_line_and_invert_default() -> void:
	check(HubLayout.CRATE_LINE_Z < -9.6, "throw line moved toward water")
	check(HubCrateToss.legal_launch(Vector3(0, 0, HubLayout.CRATE_LINE_Z + 0.5)), "behind line is legal")
	check(not HubCrateToss.legal_launch(Vector3(0, 0, HubLayout.CRATE_LINE_Z - 0.5)), "over line is foul")
	check_eq(Settings.schema("input.invert_free_camera_y")["def"], false, "camera inversion is opt-in")

func test_every_event_has_art_visible_stats_and_accessible_choices() -> void:
	var f := flow()
	for event_id in f.catalog.events:
		f.ctrl.state["phase"] = "event"
		f.ctrl.state["position"] = "preview_evt"
		f.ctrl.state["node"] = {"id": "preview_evt", "type": "event", "pending": {"p0": []}, "fights": 0, "event": EventRunner.begin(f.ctrl, "preview_evt", event_id)}
		var s = App.goto("event", {"flow": f})
		await wait_frames(5)
		var art := s.find_child("EventArtwork", true, false) as TextureRect
		check(art != null and art.texture != null, "%s has its own imported artwork" % event_id)
		var status := s.find_child("RunStatus", true, false) as Control
		check(status != null, "%s shows player stats before a decision" % event_id)
		check(s.default_focus() != null, "%s offers an accessible choice" % event_id)
		var viewport := get_viewport().get_visible_rect()
		for b in s._buttons:
			check(b.get_global_rect().end.x <= viewport.end.x + 1.0, "%s choice fits horizontally" % event_id)
		if art and status:
			var frame: Node = status
			while frame.get_parent() != s:
				frame = frame.get_parent()
			check(art.get_index() < frame.get_index(), "%s artwork sits behind readable choices" % event_id)
		# Outcome rebuild retains the same art and refreshes the run status.
		s._show_result(["A sample outcome."])
		await wait_frames(4)
		art = s.find_child("EventArtwork", true, false) as TextureRect
		check(art != null and art.texture.resource_path.ends_with(event_id + ".png"), "%s outcome retains artwork" % event_id)
		var stats := s.find_child("RunStatus", true, false) as Control
		check(stats != null and stats.get_global_rect().end.y < s.default_focus().get_global_rect().position.y, "%s outcome stats remain above choices" % event_id)

func test_team_setup_compact_cards_fit_and_keep_slot_identity() -> void:
	for resolution in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		get_tree().root.size = resolution
		var s = App.goto("spectate", {"fighters": 4})
		await wait_frames(5)
		s.setup["rules"] = "duel"
		s._rebuild()
		await wait_frames(5)
		var columns := s.find_child("TeamColumns", true, false) as GridContainer
		check(columns != null and columns.columns == 2, "teams have separate columns")
		var bounds := get_viewport().get_visible_rect()
		check(columns.get_global_rect().end.x <= bounds.end.x, "team controls stay within screen")
		for i in 4:
			var row: PickRow = s._pick_rows[i]
			check_eq(str(row.get_meta("focus_key")), "pick%d" % i, "grouping preserves fighter slot identity")
			check(row.get_global_rect().end.x <= s._scroll.get_global_rect().end.x, "compact fighter fits its scroll panel")
			row.grab_focus()
			await wait_frames(2)
			check(row.get_global_rect().end.y <= s._scroll.get_global_rect().end.y, "controller reveals each fighter")
		check(s._pick_rows[0].global_position.x != s._pick_rows[1].global_position.x, "opponents occupy different team columns")

func test_jukebox_preview_button_stops_previous_track() -> void:
	var menu_track := "menu_mintodog_scifi_stage_select"
	var preview_track := "combat_mintodog_jazzy_battle"
	check(Audio.bank["music"].has(menu_track), "community menu track is in the bank")
	check(Audio.bank["music"].has(preview_track), "community fight track is in the bank")
	if not Audio.bank["music"].has(menu_track) or not Audio.bank["music"].has(preview_track):
		return
	var audio_was_enabled := Audio.enabled
	Audio.enabled = true
	var s = App.goto("jukebox")
	await wait_frames(4)
	var preview := s.find_child("JukeboxPreview_" + preview_track, true, false) as UiButton
	check(preview != null, "each Jukebox track has a controller-focusable preview button")
	if preview == null:
		Audio.enabled = audio_was_enabled
		return
	Audio.music(menu_track, 0.05, {"jukebox_resolved": true, "restart": true})
	await wait_frames(2)
	check(Audio._music_cur >= 0, "first track enters a music slot")
	if Audio._music_cur < 0:
		Audio.enabled = audio_was_enabled
		return
	var first_player := Audio._music_slots[Audio._music_cur]["base"] as AudioStreamPlayer
	check(first_player.playing, "first track is playing before preview")
	preview.pressed.emit()
	check_eq(Audio.music_track(), preview_track, "preview button starts its selected track")
	check(not first_player.playing, "previous track is stopped synchronously before the preview starts")
	var playing_count := 0
	for slot in Audio._music_slots:
		if slot["base"] != null and (slot["base"] as AudioStreamPlayer).playing:
			playing_count += 1
	check_eq(playing_count, 1, "only the latest preview is playing")
	Audio.stop_music(0.05)
	await wait_frames(4)
	Audio.enabled = audio_was_enabled


func test_jukebox_persists_and_menu_stops_environment() -> void:
	var ids := Jukebox.tracks()
	Jukebox.save("menu", {"mode": "ordered", "tracks": ids})
	var saved := Saves.read_json(Settings.file_path(), "settings", Settings.VERSION)
	check(bool(saved["ok"]) and saved["data"].get("audio.jukebox", {}).get("menu", {}).get("tracks", []) == ids, "jukebox track order persisted")
	var s = App.goto("jukebox")
	await wait_frames(4)
	check(s.default_focus() != null, "jukebox has controller focus")
	await action("ui_tab_next")
	check_eq(s.context, "fight", "shoulder changes playlist context")
	Audio._ambience_id = "arena_test"
	var enabled_before := Audio.enabled
	Audio.enabled = true
	Audio.crowd_start()
	await wait_frames(1)
	Audio.crowd_stop(1.5)
	Audio.enabled = enabled_before
	MenuBackdrop.ensure()
	for child in Audio.get_children():
		if child is AudioStreamPlayer and child.bus == "Crowd":
			check(not child.playing, "menu also stops a crowd loop already fading after a fight")
	check_eq(Audio._ambience_id, "", "menu clears ambience including a pending transition")
	for id in ["crowd_murmur", "crowd_cheer"]:
		check(not str(Audio.bank["sfx"][id]).contains("replacements/"), "original crowd restored: " + id)
