extends CampaignTestCase
## UI-01/UI-02 smoke tests for the campaign screens: every screen builds through App, offers a
## focused control (controller), and drives the run through the same RunController calls a
## player makes — including real ui_accept / ui_down input events on the map. Fights are
## settled with synthetic results (the fight presentation is MatchScene's job). User data is
## redirected to a temporary root so no real profile or save is touched.

var _root := ""
var _profile := {}
var _speed = 1.0               ## the accessibility game speed setting, restored after each test


## A CampaignFlow whose fights are settled by the test (no presented MatchScene).
class TestFlow:
	extends CampaignFlow
	var fights_requested := 0

	func launch_fight() -> void:
		fights_requested += 1


## A real CampaignFlow (presented fights) whose catalog's stand-ins do not count as a custom
## reason, so a test can watch the game-speed reason on its own.
class NoStandInFlow:
	extends CampaignFlow

	func uses_stand_ins() -> bool:
		return false


func make_flow(cfg: Dictionary) -> TestFlow:
	var f := TestFlow.new()
	f.catalog = cat()
	f.store = RunStore.new()
	f.ctrl = RunController.start_run(cat(), cfg)
	f._hook()
	f.save()
	return f


func before_each() -> void:
	_speed = Settings.get_value("access.game_speed")
	_root = Paths.root
	Paths.root = temp_dir("ui_root_%d" % Time.get_ticks_usec())
	_profile = Profiles.current
	Profiles.current = Profiles.default_profile("ui_test", "UI Test")
	CampaignProgression.ensure_fields(Profiles.current)


func after_each() -> void:
	App.clear_screens()
	App.set_scene(null)
	var t := App.get_node_or_null("BookieTable")
	if t:
		t.name = "BookieTable_done"
		t.queue_free()
	Settings.set_value("access.game_speed", _speed, false, false)
	Paths.root = _root
	Profiles.current = _profile
	super.after_each()


func top() -> Screen:
	return App.top_screen()


func focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()


func press(b: Control) -> void:
	check(b is BaseButton, "pressing a button (%s)" % str(b))
	if b is BaseButton:
		(b as BaseButton).pressed.emit()
	await wait_frames(2)


func action(name_: String) -> void:
	var ev := InputEventAction.new()
	ev.action = name_
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_frames(1)
	var up := InputEventAction.new()
	up.action = name_
	up.pressed = false
	Input.parse_input_event(up)
	await wait_frames(2)


func find_button(root: Node, prefix: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		var b: Button = c
		if b.text.begins_with(prefix) and b.is_visible_in_tree():
			return b
	return null


func find_exact(root: Node, text: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		var b: Button = c
		if b.text == text and b.is_visible_in_tree():
			return b
	return null


func test_menu_starts_a_run_and_shows_the_map() -> void:
	var s := App.goto("campaign_menu", {"stand_ins": true})
	check(s != null, "campaign menu screen exists")
	await wait_frames(3)
	var start := s.default_focus()
	check(start is Button and (start as Button).text == "START RUN", "START RUN has the default focus")
	check(focus_owner() == start, "focus actually landed on START RUN (controller-ready)")
	check(find_button(s, "THE BOOKIE'S TABLE") != null, "Bookie's Table entry")
	check(find_button(s, "CANNERY LEDGER") != null, "Cannery Ledger entry")
	await action("ui_accept")
	await wait_frames(2)
	check_eq(top().screen_name, "run_map", "START RUN opens the run map")
	await wait_frames(2)
	check(not CampaignUI.has_modal(top()), "new run starts on the map without an act-intro popup")
	check_eq(top().screen_name, "run_map", "new run is ready for an intentional route choice")


func test_controller_walks_the_map_and_screens_to_the_summary() -> void:
	var f := make_flow(run_cfg("f_stoke", {"seed": 4242, "difficulty": "sparring"}))
	f.intro_seen = {1: true, 2: true, 3: true}
	f.show_current()
	await wait_frames(3)
	check_eq(top().screen_name, "run_map", "map first")
	var avail := f.ctrl.available_nodes()
	check(avail.size() >= 2, "several reachable nodes in row 1")
	var first := focus_owner()
	check(first is Button, "a reachable node has focus")
	await action("ui_down")
	var second := focus_owner()
	check(second is Button and second != first, "ui_down moves to another reachable node")
	await action("ui_accept")
	await wait_frames(2)
	check_eq(int((f.ctrl.state["path"] as Array).size()), 1, "ui_accept entered a node")
	var seen := {}
	var guard := 0
	while not f.ctrl.is_over() and guard < 220:
		guard += 1
		var s := top()
		if f.ctrl.phase() == "fight":
			f.ctrl.complete_fight(fake_result(f.ctrl, true, 0.9))
			f.show_current()
			await wait_frames(2)
			continue
		if s == null:
			fail("no screen in phase %s" % f.ctrl.phase())
			break
		seen[s.screen_name] = true
		var df := s.default_focus()
		if not check(df != null, "%s offers a default focus" % s.screen_name):
			break
		match s.screen_name:
			"run_map":
				if CampaignUI.has_modal(s):
					App.back()
					await wait_frames(2)
					continue
				await press(df)
			"shop":
				await press(find_button(s, "LEAVE"))
			_:
				await press(df)
	check(f.ctrl.is_over(), "the run reached its end through the screens")
	check(f.fights_requested >= 12, "the screens asked for every fight (%d)" % f.fights_requested)
	check_eq(f.ctrl.phase(), "victory", "won with synthetic fights")
	await wait_frames(2)
	check_eq(top().screen_name, "run_summary", "summary screen at the end")
	check(find_button(top(), "RUN IT BACK") != null, "Run it back offered")
	check(find_button(top(), "NEW CARD") != null, "New card offered")
	for k in ["run_map", "reward"]:
		check(seen.has(k), "visited the %s screen" % k)
	print("ui walk visited: %s" % str(seen.keys()))
	var rec: Dictionary = Profiles.current["records"]["runs"]["off_the_street"]
	check_eq(int(rec["attempts"]), 1, "the run was credited once to the (temporary) profile")
	await press(find_button(top(), "CAMPAIGN MENU"))
	check_eq(top().screen_name, "campaign_menu", "back to the campaign menu")


func test_every_decision_screen_builds_with_focus() -> void:
	var f := make_flow(run_cfg("f_dredge", {"seed": 99}))
	var ctrl := f.ctrl
	# reward
	ctrl.state["phase"] = "reward"
	ctrl.state["node"] = {"id": "ui", "type": "fight", "pending": {"p0": []}, "fights": 1}
	ctrl.add_pending("p0", "supplement", {"n": 3, "source": "fight"})
	App.goto("reward", {"flow": f})
	await wait_frames(3)
	check(top().default_focus() != null and focus_owner() == top().default_focus(), "reward: first card focused")
	check(find_button(top(), "REROLL") != null and find_button(top(), "SKIP") != null, "reward: reroll and skip")
	# event (first event of the catalog)
	var ev_id := str(ctrl.catalog.events.keys()[0])
	ctrl.state["phase"] = "event"
	ctrl.state["position"] = "ui_evt"
	ctrl.state["node"] = {"id": "ui_evt", "type": "event", "pending": {"p0": []}, "fights": 0, "event": EventRunner.begin(ctrl, "ui_evt", ev_id)}
	App.goto("event", {"flow": f})
	await wait_frames(3)
	check(top().default_focus() != null, "event: a choice is focusable")
	# shop
	ctrl.state["phase"] = "shop"
	ctrl.state["node"] = {"id": "ui_shop", "type": "shop", "pending": {"p0": []}, "fights": 0, "shop": {"p0": CampaignShop.stock(ctrl, "p0")}}
	ctrl.player("p0")["scrip"] = 500
	App.goto("shop", {"flow": f})
	await wait_frames(3)
	check(top().default_focus() != null, "shop: an item is focusable")
	var scrip0 := int(ctrl.player("p0")["scrip"])
	await press(top().default_focus())
	check(int(ctrl.player("p0")["scrip"]) < scrip0, "shop: buying through the card spends Scrip")
	# rest
	ctrl.state["phase"] = "rest"
	ctrl.state["node"] = {"id": "ui_rest", "type": "rest", "pending": {"p0": []}, "fights": 0, "rest": {"p0": {"done": false, "choice": ""}}}
	App.goto("rest", {"flow": f})
	await wait_frames(3)
	check(top().default_focus() != null, "rest: an option is focusable")
	check(find_button(top(), "") != null, "rest: cards present")


func test_run_map_modal_traps_focus_and_back_closes_it() -> void:
	var f := make_flow(run_cfg("f_gusto", {"seed": 7}))
	f.intro_seen = {1: true}
	f.show_current()
	await wait_frames(3)
	var s := top()
	await press(find_button(s, "ABANDON"))
	check(CampaignUI.has_modal(s), "abandon asks first")
	await wait_frames(1)
	var fo := focus_owner()
	var in_modal := fo is Button and (fo as Button).text.begins_with("ABANDON")
	check(in_modal, "focus moved into the modal")
	await action("ui_up")
	check(focus_owner() == fo, "ui_up cannot leave the modal")
	App.back()
	await wait_frames(2)
	check(not CampaignUI.has_modal(s), "Back closed the modal")
	check(not f.ctrl.is_over(), "nothing was abandoned")


func test_unbuildable_fight_offers_forfeit() -> void:
	var bare := CampaignCatalog.new(Content, "")   # no stand-ins: roster creatures are missing here
	if not bare.available_fighters().is_empty():
		return   # real roster installed: nothing to test
	var f := CampaignFlow.start(bare, run_cfg("f_stoke", {"seed": 5}))
	f.intro_seen = {1: true}
	var fight_id := ""
	for id in f.ctrl.available_nodes():
		if str(RunState.node(f.ctrl.state, str(id)).get("type", "")) == "fight":
			fight_id = str(id)
	if fight_id == "":
		return
	f.choose_node(fight_id)
	await wait_frames(3)
	check_eq(top().screen_name, "run_map", "an unbuildable fight returns to the map")
	check(CampaignUI.has_modal(top()), "with an explanation")
	await press(find_button(top(), "FORFEIT"))
	await wait_frames(2)
	check_eq(f.ctrl.phase(), "defeat", "forfeit counts as a lost fight")
	check_eq(top().screen_name, "run_summary", "summary shown")


func test_camp_ledger_buys_with_clout() -> void:
	Profiles.current["camp"]["clout"] = 400
	App.goto("camp_ledger", {"station": "gym_floor"})
	await wait_frames(3)
	var b := top().default_focus()
	check(b is Button and (b as Button).text.begins_with("BUY"), "a BUY button has focus")
	await press(b)
	check(int(Profiles.current["camp"]["clout"]) < 400, "Clout spent")
	var owned: Dictionary = Profiles.current["camp"]["upgrades"]
	check_eq(owned.size(), 1, "one upgrade level bought")


func test_bookie_screen_setup_live_and_stop() -> void:
	var s := App.goto("bookie", {"stand_ins": true})
	await wait_frames(3)
	check(s.default_focus() != null, "setup is focusable")
	s.call("_set_watch", "ff")
	await wait_frames(1)
	await press(find_button(top(), "DEAL THE CARD"))
	var table := App.get_node_or_null("BookieTable") as BookieTable
	check(table != null, "the table lives under App")
	if table == null:
		return
	await press(find_button(top(), "PAUSE"))
	check(table.paused, "PAUSE pauses the table")
	await wait_frames(5)
	check(table.transitions.is_empty(), "nothing happens while paused")
	await press(find_button(top(), "TAKE OVER"))
	check(not table.unattended, "TAKE OVER hands decisions to the player")
	await press(find_button(top(), "2x"))
	check_near(table.speed, 2.0, 0.001, "speed 2x")
	await press(find_button(top(), "STOP THE TABLE"))
	check(CampaignUI.has_modal(top()), "stop asks first")
	await press(find_exact(top(), "STOP"))
	var budget := 0
	while table.running and budget < 300:
		budget += 1
		await wait_frames(1)
	check(not table.running, "the table stopped")
	await wait_frames(3)
	await press(find_button(top(), "LEAVE THE TABLE"))
	await wait_frames(2)
	check_eq(top().screen_name, "campaign_menu", "left to the campaign menu")
	check(App.get_node_or_null("BookieTable") == null, "the table was released")
	check_near(Engine.time_scale, 1.0, 0.001, "game speed restored")


# --- review regressions ----------------------------------------------------------------------------

## Turns the first reachable node into a rest stop.
func _rest_node(ctrl: RunController) -> String:
	var nid := str(ctrl.available_nodes()[0])
	var n := RunState.node(ctrl.state, nid)
	n["type"] = "rest"
	n["encounter"] = ""
	n.erase("hidden")
	return nid


## Counts screen changes; past `limit` it breaks a screen loop from outside (so a regression
## fails this test instead of freezing the suite) by settling the node by force.
func _loop_guard(ctrl: RunController, limit := 40) -> Array:
	var changes := [0]
	var on_screen := func(_s: String) -> void:
		changes[0] += 1
		if changes[0] == limit:
			ctrl.state["phase"] = "map"
			ctrl.state["node"] = {}
	App.screen_changed.connect(on_screen)
	return [changes, on_screen]


func _end_guard(guard: Array) -> int:
	App.screen_changed.disconnect(guard[1])
	return int(guard[0][0])


## Review #1: Rest -> Train opens the technique pick (no screen loop), and the pick completes
## the rest stop.
func test_rest_train_opens_the_pick_without_a_loop() -> void:
	var f := make_flow(run_cfg("f_stoke", {"seed": 4242}))
	f.intro_seen = {1: true, 2: true, 3: true}
	var nid := _rest_node(f.ctrl)
	f.choose_node(nid)
	await wait_frames(2)
	check_eq(top().screen_name, "rest", "the rest stop")
	var guard := _loop_guard(f.ctrl)
	var cards: Array = top().get("_cards")
	await press(cards[1])                     # TRAIN
	await wait_frames(3)
	var changes := _end_guard(guard)
	check(changes <= 3, "Train moved on once, no screen loop (%d screen changes)" % changes)
	check_eq(top().screen_name, "reward", "Train opens the technique pick")
	check_eq(str(f.ctrl.pending_for("p0")[0]["kind"]) if not f.ctrl.pending_for("p0").is_empty() else "", "technique", "a technique pick")
	await press(top().default_focus())
	await wait_frames(2)
	check_eq(f.ctrl.phase(), "map", "the pick completed the rest stop")
	check_eq(top().screen_name, "run_map", "back on the map")


func test_run_moves_screens_equip_learn_and_drill() -> void:
	for variant in ["off_the_street", "fight_camp"]:
		for choice in ["learn", "drill"]:
			var f := make_flow(run_cfg("f_stoke", {"seed": 4343, "variant": variant}))
			f.intro_seen = {1: true, 2: true, 3: true}
			f.show_current()
			await wait_frames(4)
			var button := find_exact(top(), "CHANGE MOVES")
			if not check(button != null, "%s exposes the run loadout" % variant):
				return
			button.grab_focus()
			await action("ui_accept")
			check_eq(top().screen_name, "loadout", "the map opens the learned-move loadout")
			var screen = top()
			var before: Array = RunMoves.moves_of(f.ctrl.player("p0"))["equipped"].duplicate()
			screen.set_slot(1, "cinder_shot")
			await capture_ui_evidence(variant + "-equipped-moves")
			screen.confirm()
			await wait_frames(4)
			var equipped: Array = RunMoves.moves_of(f.ctrl.player("p0"))["equipped"]
			check(equipped != before and equipped[1] == "cinder_shot", "the UI equips Cinder Shot in this run")
			check_eq(top().screen_name, "run_map", "Done returns to the map")
			if not check(_walk_into_rest(f.ctrl), "reached a real rest stop"):
				return
			f.show_current()
			await wait_frames(4)
			check_eq(top().screen_name, "rest", "the actual rest screen")
			var cards: Array = top().get("_cards")
			var options := f.ctrl.rest_options("p0")
			var index := -1
			for i in options.size():
				if str(options[i]["id"]) == choice:
					index = i
			if not check(index >= 0 and not (cards[index] as Button).disabled, "%s is available" % choice):
				return
			(cards[index] as Control).grab_focus()
			await capture_ui_evidence(variant + "-rest-" + choice)
			await action("ui_accept")
			await wait_frames(3)
			check_eq(top().screen_name, "reward", "rest opens the move choice")
			var pending := f.ctrl.pending_for("p0")
			if not check(not pending.is_empty(), "a move pick is pending"):
				return
			var picked := str(pending[0]["options"][0])
			await capture_ui_evidence(variant + "-" + choice + "-picker")
			top().default_focus().grab_focus()
			await action("ui_accept")
			await wait_frames(3)
			var moves := RunMoves.moves_of(f.ctrl.player("p0"))
			if choice == "learn":
				check((moves["learned"] as Array).has(picked), "the UI learned its selected move")
			else:
				var parts := RunMoves.split_drill(picked)
				check_eq(str((moves["drilled"] as Dictionary).get(str(parts[0]), "")), str(parts[1]), "the UI drilled its selected style")
			check_eq(f.ctrl.phase(), "map", "the choice completes the rest")
			check(bool(RunController.verify(cat(), RunStore.json_stable(f.ctrl.state))["ok"]), "the run's equip and training choices replay")
			App.clear_screens()
			await wait_frames(2)


## Walks a run (synthetic results) until a real rest stop is reachable and enters it.
func _walk_into_rest(ctrl: RunController) -> bool:
	for i in 40:
		if ctrl.is_over():
			return false
		var av := ctrl.available_nodes()
		for id in av:
			if str(RunState.node(ctrl.state, str(id)).get("type", "")) == "rest":
				return ctrl.choose_node(str(id), "p0")
		ctrl.choose_node(str(av[0]), "p0")
		settle_node(ctrl)
	return false


## Review #1: a run saved in the stuck state (Train taken, its pick pending, phase still
## "rest") resumes straight into the pick.
func test_stuck_rest_save_resumes_into_the_pick() -> void:
	var ctrl := RunController.start_run(cat(), run_cfg("f_stoke", {"seed": 4343}))
	check(_walk_into_rest(ctrl), "reached a rest stop on the card")
	check(ctrl.rest_choose("p0", "train"), "Train: %s" % ctrl.last_error)
	check_eq(ctrl.phase(), "rest", "precondition: the state older builds froze on")
	var rs := RunStore.new()
	rs.save(ctrl.state, CampaignFlow.profile_key())
	var res := rs.load_slot(CampaignFlow.profile_key(), "off_the_street", cat())
	check(bool(res["ok"]), "the stuck save loads: %s" % res["error"])
	var f := CampaignFlow.resume(cat(), res["state"])
	f.intro_seen = {1: true, 2: true, 3: true}
	var guard := _loop_guard(f.ctrl)
	f.show_current()
	await wait_frames(3)
	var changes := _end_guard(guard)
	check(changes <= 2, "resume shows one screen (%d screen changes)" % changes)
	check_eq(top().screen_name, "reward", "RESUME opens the pending technique pick")
	await press(top().default_focus())
	await wait_frames(2)
	check_eq(f.ctrl.phase(), "map", "and the run goes on")


## Review #1: the same at The Bookie's Table when the player has taken over.
func test_bookie_attended_rest_train_opens_the_pick() -> void:
	var t := BookieTable.new()
	t.name = "BookieTable"
	App.add_child(t)
	t.setup(cat(), run_cfg("f_stoke", {"seed": 4444}), {})
	t.unattended = false
	var bf := BookieFlow.for_table(t)
	t.ctrl.choose_node(_rest_node(t.ctrl), "p0")
	bf.show_current()
	await wait_frames(2)
	check_eq(top().screen_name, "rest", "the player decides the rest stop")
	var guard := _loop_guard(t.ctrl)
	var cards: Array = top().get("_cards")
	await press(cards[1])
	await wait_frames(3)
	var changes := _end_guard(guard)
	check(changes <= 3, "no screen loop at the table (%d screen changes)" % changes)
	check_eq(top().screen_name, "reward", "Train opens the pick at the table too")


## Review #2: START RUN over a suspended run of the same variant asks first; CANCEL keeps it,
## ABANDON IT & START credits it as an abandoned defeat and deals the new card.
func test_menu_asks_before_replacing_a_suspended_run() -> void:
	var old := CampaignFlow.start(cat(), run_cfg("f_stoke", {"seed": 111}))
	var old_id := str(old.ctrl.state["run_id"])
	App.goto("campaign_menu", {"stand_ins": true})
	await wait_frames(3)
	await press(find_exact(top(), "START RUN"))
	check(CampaignUI.has_modal(top()), "START RUN asks before replacing the suspended run")
	await press(find_exact(top(), "CANCEL"))
	var held := CampaignFlow.suspended_run(cat(), "off_the_street")
	check_eq(str(held.get("summary", {}).get("run_id", "")), old_id, "CANCEL keeps the suspended run")
	check((Profiles.current["history"] as Array).is_empty(), "and credits nothing")
	await press(find_exact(top(), "START RUN"))
	await press(find_button(top(), "ABANDON IT"))
	await wait_frames(3)
	check_eq(top().screen_name, "run_map", "the new card is dealt")
	var now := CampaignFlow.suspended_run(cat(), "off_the_street")
	var new_id := str(now.get("summary", {}).get("run_id", ""))
	check(new_id != "" and new_id != old_id, "the slot holds the new run")
	var hist: Array = Profiles.current["history"]
	check(not hist.is_empty() and str(hist[0]["run_id"]) == old_id and not bool(hist[0]["victory"]), "the old run is in the history as a defeat")
	check_eq(int(Profiles.current["records"]["runs"]["off_the_street"]["attempts"]), 1, "counted as an attempt")


## Review #2 with the newer-version rule: a run saved by a newer game version is never replaced
## (nor moved or deleted), so START RUN over it explains instead of dealing a card.
func test_menu_never_deals_over_a_newer_versions_run() -> void:
	var rs := RunStore.new()
	var path := rs.slot_path(CampaignFlow.profile_key(), "off_the_street")
	Saves.write_json(path, RunStore.KIND, RunState.VERSION + 1, {"future": true})
	var before := FileAccess.get_file_as_string(path)
	App.goto("campaign_menu", {"stand_ins": true})
	await wait_frames(3)
	await press(find_exact(top(), "START RUN"))
	check(CampaignUI.has_modal(top()), "START RUN explains")
	check(find_button(top(), "ABANDON IT") == null, "and offers no way to replace it")
	check_eq(top().screen_name, "campaign_menu", "no card dealt")
	check_eq(FileAccess.get_file_as_string(path), before, "the newer run is untouched")
	var sv := HubServices.new(HubState.new(Profiles.current))
	sv.stand_ins = true
	var held := CampaignFlow.suspended_run(sv.catalog(), "off_the_street")
	check(bool(held.get("newer", false)), "reported as a newer version's run")


## Review #2: the hub's sign-up sheet asks the same (dialog: abandon it / resume it / keep it),
## and the services never replace a suspended Fight Camp run without that answer.
func test_hub_sign_up_asks_before_replacing_a_suspended_run() -> void:
	var old := CampaignFlow.start(cat(), run_cfg("f_stoke", {"seed": 222, "variant": "fight_camp"}))
	var old_id := str(old.ctrl.state["run_id"])
	var sv := HubServices.new(HubState.new(Profiles.current))
	sv.stand_ins = true
	var r := sv.start_run({"fighter": "f_stoke", "difficulty": "amateur", "dose": 0})
	check(not bool(r.get("ok", true)) and bool(r.get("needs_confirm", false)), "the services ask instead of replacing")
	check_eq(str(CampaignFlow.suspended_run(cat(), "fight_camp").get("summary", {}).get("run_id", "")), old_id, "nothing replaced")
	App.goto("hub_board", {"kind": "run", "stand_ins": true})
	await wait_frames(3)
	await press(find_button(top(), "SIGN THE WAIVER"))
	await wait_frames(2)
	check_eq(top().screen_name, "dialog", "signing asks first")
	top().call("choose", "keep")
	await wait_frames(2)
	check_eq(top().screen_name, "hub_board", "KEEP IT returns to the sheet")
	check_eq(str(CampaignFlow.suspended_run(cat(), "fight_camp").get("summary", {}).get("run_id", "")), old_id, "the run is kept")
	await press(find_button(top(), "SIGN THE WAIVER"))
	await wait_frames(2)
	top().call("choose", "replace")
	await wait_frames(3)
	check_eq(top().screen_name, "run_map", "the new card is dealt")
	var new_id := str(CampaignFlow.suspended_run(cat(), "fight_camp").get("summary", {}).get("run_id", ""))
	check(new_id != "" and new_id != old_id, "the slot holds the new run")
	var hist: Array = Profiles.current["history"]
	check(not hist.is_empty() and str(hist[0]["run_id"]) == old_id, "the old run was credited as abandoned")


## Review #4: the hub's sign-up sheet offers Doses only on difficulties that take them.
func test_hub_sign_up_offers_no_dose_on_sparring() -> void:
	Profiles.current["ladder"]["fight_camp"] = {"unlocked": 3, "cleared": 2, "open": true}
	App.goto("hub_board", {"kind": "run", "stand_ins": true})
	await wait_frames(3)
	var diff_row: OptionRow = null
	var dose_row: OptionRow = null
	for c in top().find_children("*", "OptionRow", true, false):
		var row := c as OptionRow
		if row.label_text == "Difficulty":
			diff_row = row
		elif row.label_text == "The Dosage":
			dose_row = row
	check(diff_row != null and dose_row != null, "the sheet has Difficulty and Dosage rows")
	if diff_row == null or dose_row == null:
		return
	for i in diff_row.options.size():
		if str(diff_row.get_value()) == "amateur":
			break
		diff_row._on_step(1)
	check_eq(dose_row.options, [0, 1, 2, 3], "Amateur: the base card and Doses 1-3")
	dose_row.set_value(2)
	for i in diff_row.options.size():
		if str(diff_row.get_value()) == "sparring":
			break
		diff_row._on_step(1)
	check_eq(str(diff_row.get_value()), "sparring", "Sparring picked")
	check_eq(dose_row.options, [0], "Sparring: no Dose on offer")
	check_eq(int(dose_row.get_value()), 0, "the Dose fell back to the base card")


## Review #4: whatever a caller asks for, a run is created only at a Dose the active profile may
## play (menu, hub sheet and "Raise the Dose" all start through CampaignFlow.start).
func test_run_creation_clamps_the_dose() -> void:
	Profiles.current["ladder"]["off_the_street"] = {"unlocked": 3, "cleared": 2, "open": true}
	var f := CampaignFlow.start(cat(), run_cfg("f_stoke", {"seed": 556, "dose": 7}))
	check_eq(int(f.ctrl.state["dose"]), 3, "Dose 7 asked, Dose 3 unlocked: Dose 3")
	f.abandon()
	var f2 := CampaignFlow.start(cat(), run_cfg("f_stoke", {"seed": 557, "dose": 2, "difficulty": "sparring"}))
	check_eq(int(f2.ctrl.state["dose"]), 0, "no Dose on Sparring")
	f2.abandon()
	Profiles.current["ladder"]["off_the_street"] = {"unlocked": 1, "cleared": 0, "open": false}
	var f3 := CampaignFlow.start(cat(), run_cfg("f_stoke", {"seed": 558, "dose": 1}))
	check_eq(int(f3.ctrl.state["dose"]), 0, "The Dosage closed: the base card")


## Review #11: a party's slot is listed but never resumed as a solo run (only the co-op host
## path resumes it); abandoning credits the local member.
func test_menu_never_resumes_a_party_run_solo() -> void:
	var cfg := run_cfg("f_stoke", {"seed": 333})
	cfg["players"].append({"id": "p1", "name": "Two", "profile_id": "someone_else", "fighter": "f_dozer"})
	var party := RunController.start_run(cat(), cfg)
	var slot := RunStore.slot_for(party.state)
	RunStore.new().save(party.state, CampaignFlow.profile_key(), slot)
	var s := App.goto("campaign_menu", {"stand_ins": true})
	await wait_frames(3)
	var resume := find_exact(s, "RESUME")
	check(resume != null and resume.disabled, "a party run cannot be resumed solo from the menu")
	s.call("_resume", slot)
	await wait_frames(2)
	check_eq(top().screen_name, "campaign_menu", "no solo run was started")
	check(CampaignUI.has_modal(top()), "the menu explains how party runs resume")
	App.back()
	await wait_frames(1)
	s.call("_on_abandon", "yes", slot)
	await wait_frames(1)
	check(CampaignFlow.suspended_run(cat(), slot).is_empty(), "abandoning clears the party slot")
	check_eq(int(Profiles.current["records"]["runs"]["off_the_street"]["attempts"]), 1, "credited as an attempt")


## Review #6: "custom" is re-checked before every fight (the game speed may have been lowered
## since the run started); once custom, a run stays custom.
func test_custom_rechecked_at_each_fight() -> void:
	var f := NoStandInFlow.new()
	f.catalog = cat()
	f.store = RunStore.new()
	f.ctrl = RunController.start_run(cat(), run_cfg("f_stoke", {"seed": 4545}))
	f._hook()
	check(not bool(f.ctrl.state["custom"]), "a standard run")
	f.ctrl.choose_node(str(f.ctrl.available_nodes()[0]), "p0")
	Settings.set_value("access.game_speed", 0.8, false, false)
	f.launch_fight()
	await wait_frames(2)
	check(bool(f.ctrl.state["custom"]), "slowed down before the fight: the run is custom now")
	check((f.ctrl.state["custom_reasons"] as Array).has(CampaignFlow.REASON_GAME_SPEED), "for reduced game speed")
	App.set_scene(null)
	Settings.set_value("access.game_speed", 1.0, false, false)
	f.ctrl.complete_fight(fake_result(f.ctrl))
	settle_node(f.ctrl)
	f.ctrl.choose_node(str(f.ctrl.available_nodes()[0]), "p0")
	if f.ctrl.phase() == "fight":
		f.launch_fight()
		await wait_frames(2)
		App.set_scene(null)
	check(bool(f.ctrl.state["custom"]), "back at full speed, the run stays custom")


## Review #6: "Run it back" decides custom afresh from the reasons that apply now.
func test_run_it_back_rechecks_custom() -> void:
	var f := NoStandInFlow.new()
	f.catalog = cat()
	f.store = RunStore.new()
	f.ctrl = RunController.start_run(cat(), run_cfg("f_stoke", {"seed": 4646, "custom": true, "custom_reasons": [CampaignFlow.REASON_GAME_SPEED]}))
	f._hook()
	f.abandon()
	await wait_frames(2)
	Settings.set_value("access.game_speed", 1.0, false, false)
	f.restart(true)
	await wait_frames(2)
	var nf: CampaignFlow = top().get("flow")
	check(nf != null and nf != f, "a new card")
	if nf == null:
		return
	check(not bool(nf.ctrl.state["custom"]), "full speed now: the run back is a standard run")
	nf.abandon()
	await wait_frames(2)
	Settings.set_value("access.game_speed", 0.7, false, false)
	var nf2 := NoStandInFlow.new()
	nf2.catalog = cat()
	nf2.store = RunStore.new()
	nf2.ctrl = nf.ctrl
	nf2.restart(true)
	await wait_frames(2)
	var nf3: CampaignFlow = top().get("flow")
	check(nf3 != null and bool(nf3.ctrl.state["custom"]), "slowed down now: the run back is custom")
	check(nf3 != null and (nf3.ctrl.state["custom_reasons"] as Array).has(CampaignFlow.REASON_GAME_SPEED), "for reduced game speed")


## Review #7: a presented fight counts once — its simulated time — not also its wall-clock time.
func test_fight_time_counts_once() -> void:
	var f := CampaignFlow.start(cat(), run_cfg("f_stoke", {"seed": 4747}))
	var fight_id := ""
	for id in f.ctrl.available_nodes():
		if str(RunState.node(f.ctrl.state, str(id)).get("type", "")) == "fight":
			fight_id = str(id)
	check(fight_id != "", "a fight on row 1")
	f.ctrl.choose_node(fight_id, "p0")
	var before := float(f.ctrl.state["elapsed"])
	f.launch_fight()
	check(App.current_scene is MatchScene, "a presented fight")
	var until := Time.get_ticks_msec() + 1300
	while Time.get_ticks_msec() < until:
		await wait_frames(1)               # the fight takes 1.3 s of real time...
	var res := fake_result(f.ctrl)
	res["campaign"]["time"] = 0.5          # ...and reports 0.5 s of fight time
	f._on_match_finished(res)
	await wait_frames(2)
	var added := float(f.ctrl.state["elapsed"]) - before
	check(added >= 0.5 - 0.001, "the fight's own time counts (%.2f s)" % added)
	check(added < 0.5 + 0.4, "the fight's wall-clock time is not counted on top (%.2f s added)" % added)


## Review #8: the Bookie's speed applies to every presented fight, not just the first: a
## finished MatchScene resets Engine.time_scale, so each fight re-applies k x at the fixed
## 1/120 s step.
func test_bookie_speed_holds_for_every_presented_fight() -> void:
	var t := BookieTable.new()
	t.name = "BookieTable"
	App.add_child(t)
	t.setup(cat(), run_cfg("f_stoke", {"seed": 99}), {})
	t.speed = 4.0
	var bf := BookieFlow.for_table(t)
	bf.watching = true
	t.running = true
	SimSpeed.set_scale(t.speed)
	t.ctrl.choose_node(str(t.ctrl.available_nodes()[0]), "p0")
	var built := t.ctrl.match_config({"bot_tier_players": "contender", "player_kinds": {"p0": "bot"}})
	check((built["errors"] as PackedStringArray).is_empty(), "the fight builds")
	for i in 2:
		var done := [false]
		var run := func() -> void:
			await bf.run_fight(t, built["config"])
			done[0] = true
		run.call()
		await wait_physics(8)
		check_near(Engine.time_scale, 4.0, 0.001, "fight %d runs at the table's 4x" % (i + 1))
		check_near(get_physics_process_delta_time(), 1.0 / 120.0, 0.00001, "fight %d steps the fixed 1/120 s" % (i + 1))
		bf.abort_fight()
		var budget := 0
		while not done[0] and budget < 120:
			budget += 1
			await wait_frames(1)
		await wait_frames(2)               # the finished MatchScene leaves the tree (and resets time_scale)
	t.running = false


## AI-04 "speed/camera": the table's camera preset (broadcast / director / free) applies to every
## presented fight, and changing it mid-fight moves the live camera.
func test_bookie_camera_preset_holds_for_every_presented_fight() -> void:
	var t := BookieTable.new()
	t.name = "BookieTable"
	App.add_child(t)
	t.setup(cat(), run_cfg("f_stoke", {"seed": 99}), {})
	t.set_camera("director")
	var bf := BookieFlow.for_table(t)
	bf.watching = true
	t.running = true
	SimSpeed.set_scale(t.speed)
	t.ctrl.choose_node(str(t.ctrl.available_nodes()[0]), "p0")
	var built := t.ctrl.match_config({"bot_tier_players": "contender", "player_kinds": {"p0": "bot"}})
	check((built["errors"] as PackedStringArray).is_empty(), "the fight builds")
	var expect := [FightCamera.Mode.SPECTATE, FightCamera.Mode.FREE]
	for i in 2:
		var done := [false]
		var run := func() -> void:
			await bf.run_fight(t, built["config"])
			done[0] = true
		run.call()
		await wait_physics(8)
		var scene: MatchScene = bf._scene
		check(scene != null, "fight %d is presented" % (i + 1))
		if scene == null:
			break
		check_eq(scene.camera.mode, expect[i], "fight %d opens on the table's camera preset" % (i + 1))
		if i == 0:
			check(scene.director != null, "the director camera has its director")
			t.set_camera("free")
			check_eq(scene.camera.mode, FightCamera.Mode.FREE, "switching mid-fight moves the live camera")
		else:
			t.set_camera("broadcast")
			check_eq(scene.camera.mode, FightCamera.Mode.FIGHT, "back to the broadcast framing")
		bf.abort_fight()
		var budget := 0
		while not done[0] and budget < 120:
			budget += 1
			await wait_frames(1)
		await wait_frames(2)
	t.running = false
