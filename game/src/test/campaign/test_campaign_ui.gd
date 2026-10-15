extends CampaignTestCase
## UI-01/UI-02 smoke tests for the campaign screens: every screen builds through App, offers a
## focused control (controller), and drives the run through the same RunController calls a
## player makes — including real ui_accept / ui_down input events on the map. Fights are
## settled with synthetic results (the fight presentation is MatchScene's job). User data is
## redirected to a temporary root so no real profile or save is touched.

var _root := ""
var _profile := {}


## A CampaignFlow whose fights are settled by the test (no presented MatchScene).
class TestFlow:
	extends CampaignFlow
	var fights_requested := 0

	func launch_fight() -> void:
		fights_requested += 1


func make_flow(cfg: Dictionary) -> TestFlow:
	var f := TestFlow.new()
	f.catalog = cat()
	f.store = RunStore.new()
	f.ctrl = RunController.start_run(cat(), cfg)
	f._hook()
	f.save()
	return f


func before_each() -> void:
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
		t.queue_free()
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
	# act intro modal first; Back closes it
	check(CampaignUI.has_modal(top()), "act intro card shown at the start of Act 1")
	App.back()
	await wait_frames(2)
	check(not CampaignUI.has_modal(top()), "Back closes the modal")
	check_eq(top().screen_name, "run_map", "and stays on the map")


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
