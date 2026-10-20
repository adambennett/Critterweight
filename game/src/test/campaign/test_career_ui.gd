extends CareerTestCase
## CMP-08 / UI-01 / UI-02 / UI-10: the Career screens through App with REAL ui_* input (the same
## InputEventActions a controller or keyboard produces): the Campaign menu lists Career first, every
## career screen builds with focus and Back, the layout fits at 1280x800 and 1920x1080 with text
## >= 18 px, a career is created, weeks are trained / rested / booked / upgraded (each autosaved),
## a bout is launched through CareerFlow and settled with a synthetic 10-point result (design
## contract B1 shape) onto career_result and back to the hub, the pause menu's quit in a career bout
## is a withdrawal (D4), an interrupted bout is offered again (D4) and retiring frees the slot (D3).
## User data is redirected to a temporary root and a test profile; no real save is touched.

var _root := ""
var _profile := {}
var _speed = 1.0
var _motion = false


## A CareerFlow whose bouts are settled by the test (no presented MatchScene). Static members are
## plain data (never Callables) and are cleared after every test.
class TestCareerFlow:
	extends CareerFlow

	static var launches: Array = []      ## one {cfg, in_fight, fight_id} per launched bout
	static var next_result := {}          ## when set, the bout ends with this result at once

	func launch_match(cfg: Dictionary) -> void:
		TestCareerFlow.launches.append({"cfg": cfg, "in_fight": ctrl.interrupted(), "fight_id": ctrl.booked_id()})
		if not TestCareerFlow.next_result.is_empty():
			finish_fight(TestCareerFlow.next_result)


func before_each() -> void:
	_speed = Settings.get_value("access.game_speed")
	_motion = Settings.get_value("access.reduce_motion")
	# screens slide in over 0.24 s otherwise; the layout audit measures them where they rest
	Settings.set_value("access.reduce_motion", true, false, false)
	_root = Paths.root
	Paths.root = temp_dir("career_ui_%d" % Time.get_ticks_usec())
	_profile = Profiles.current
	Profiles.current = Profiles.default_profile("ui_test", "UI Test")
	store = null
	TestCareerFlow.launches.clear()
	TestCareerFlow.next_result = {}
	MatchFlow.set_paused(false)


func after_each() -> void:
	App.clear_screens()
	App.set_scene(null)
	MatchFlow.set_paused(false)
	MatchFlow.last_config = {}
	TestCareerFlow.launches.clear()
	TestCareerFlow.next_result = {}
	Settings.set_value("access.game_speed", _speed, false, false)
	Settings.set_value("access.reduce_motion", _motion, false, false)
	Paths.root = _root
	Profiles.current = _profile
	store = null
	super.after_each()


# --- helpers ---------------------------------------------------------------------------------------

func top() -> Screen:
	return App.top_screen()


func top_name() -> String:
	return top().screen_name if top() != null else "none"


func focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()


func route_of(c: Control) -> String:
	if c is CareerUi.ActionCard:
		return (c as CareerUi.ActionCard).route
	if c is UiButton:
		return (c as UiButton).route
	if c != null and c.has_meta("focus_key"):
		return "key:" + str(c.get_meta("focus_key"))
	return ""


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


## Focus is inside the top screen and visible (the UI-02 invariant).
func expect_focus(step: String) -> bool:
	var t := top()
	var f := focus_owner()
	var ok := t != null and f != null and is_instance_valid(f) and t.is_ancestor_of(f) and f.is_visible_in_tree()
	return check(ok, "focus lost after '%s' (top=%s, focus=%s)" % [step, top_name(), str(f.get_path()) if f != null else "none"])


## Presses `dir` until the focused control has `route` (checking focus after every step).
func nav_to(route: String, dir := "ui_down", max_steps := 40) -> bool:
	for i in max_steps:
		if route_of(focus_owner()) == route:
			return true
		await action(dir)
		expect_focus("towards %s" % route)
	return check(route_of(focus_owner()) == route, "reached %s (focus is on '%s')" % [route, route_of(focus_owner())])


func find_label(root: Node, text: String) -> Label:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text.contains(text) and (l as Label).is_visible_in_tree():
			return l as Label
	return null


## The screens' own store (Paths.dir("careers") under the temporary root).
func ui_store() -> CareerStore:
	if store == null:
		store = CareerStore.new()
	return store


## A career saved in `slot` of the test profile (what the slot list reads).
func make_career(slot_n := 1, opts := {}) -> CareerController:
	var o := {"name": "Tester", "nick": "The Test", "fighter": "f_stoke", "difficulty": "normal", "seed": 4242, "created_at": 1}
	for k in opts:
		o[k] = opts[k]
	var r := CareerController.create(cat(), o, ui_store(), CareerFlow.profile_key(), slot_n)
	check(bool(r["ok"]), "career created: %s" % r["error"])
	return r["ctrl"]


func career_flow_for(ctrl: CareerController) -> TestCareerFlow:
	return CareerFlow.make(cat(), ctrl, TestCareerFlow) as TestCareerFlow


func reload(slot_n := 1) -> Dictionary:
	var r := CareerStore.new().load_slot(CareerFlow.profile_key(), slot_n, cat())
	check(bool(r["ok"]), "the slot reloads from disk: %s" % r["error"])
	return r["state"]


## A career with one fight behind it (history, news), unbooked and with fresh offers.
func veteran(slot_n := 1) -> CareerController:
	var ctrl := make_career(slot_n)
	book(ctrl)
	var s := ctrl.apply_result(scoring_result(0, "Unanimous Decision"), ctrl.booked_id())
	check(bool(s["ok"]), "the first fight settles: %s" % s.get("error", ""))
	return ctrl


# --- tests -----------------------------------------------------------------------------------------

## D8: the Campaign category lists Career first (default focus) and A opens the slot list.
func test_campaign_menu_lists_career_first() -> void:
	var mm := App.goto("main_menu")
	await wait_frames(4)
	check(bool(mm.call("open_category", "campaign")), "the Campaign category opens")
	await wait_frames(3)
	var routes := []
	for b in mm.get("_sub_items"):
		routes.append((b as UiButton).route)
	check_eq(routes, ["career", "off_the_street", "fight_camp", "bookie"], "Campaign children in order")
	check_eq(route_of(focus_owner()), "career", "Career has the focus")
	var cat_desc := ""
	for d in mm.get("_item_defs"):
		if str((d as Dictionary).get("id", "")) == "campaign":
			cat_desc = str((d as Dictionary).get("desc", ""))
	check(cat_desc.contains("career"), "the Campaign description mentions the career (%s)" % cat_desc)
	await action("ui_accept")
	await wait_frames(3)
	check_eq(top_name(), "career", "A opens the career slots")
	expect_focus("open career")
	check_eq(route_of(focus_owner()), "new:1", "an empty profile focuses NEW CAREER in slot 1")
	await action("ui_cancel")
	await wait_frames(3)
	check_eq(top_name(), "main_menu", "Back returns to the main menu")
	expect_focus("back to the main menu")


## UI-01/02: every career screen builds through App with a focused control, D-pad moves keep it,
## and Back goes where it should (slots -> menu, new -> slots, hub -> slots, result -> hub).
func test_every_career_screen_has_focus_and_back() -> void:
	App.goto("main_menu")
	await wait_frames(3)
	App.push("career", {"catalog": cat()})
	await wait_frames(4)
	check_eq(top_name(), "career", "career opens")
	expect_focus("career")
	await action("ui_down")
	expect_focus("down in career")
	await action("ui_accept")
	await wait_frames(3)
	check_eq(top_name(), "career_new", "NEW CAREER opens the new-career screen")
	expect_focus("career_new")
	check_eq(route_of(focus_owner()), "start", "START CAREER has the focus")
	await action("ui_up")
	expect_focus("up in career_new")
	await action("ui_cancel")
	await wait_frames(3)
	check_eq(top_name(), "career", "Back from a new career returns to the slots")
	expect_focus("back to career")
	await action("ui_cancel")
	await wait_frames(3)
	check_eq(top_name(), "main_menu", "Back from the slots returns to the main menu")
	var ctrl := veteran()
	var f := career_flow_for(ctrl)
	f.show_hub()
	await wait_frames(4)
	check_eq(top_name(), "career_hub", "the hub opens")
	expect_focus("career_hub")
	for t in ["offers", "gym", "history", "camp"]:
		await action("ui_tab_next")
		expect_focus("tab %s" % t)
		await action("ui_down")
		expect_focus("down in %s" % t)
	await action("ui_cancel")
	await wait_frames(3)
	check_eq(top_name(), "career", "Back from the hub returns to the slots")
	expect_focus("hub -> slots")
	check_eq(route_of(focus_owner()), "continue:1", "the slots focus CONTINUE")
	App.goto("career_result", {"flow": f, "summary": ctrl.state["last_fight"]})
	await wait_frames(4)
	check_eq(top_name(), "career_result", "the result screen opens")
	expect_focus("career_result")
	check_eq(route_of(focus_owner()), "continue", "CONTINUE has the focus")
	await action("ui_cancel")
	await wait_frames(3)
	check_eq(top_name(), "career_hub", "Back from the result returns to the hub")
	expect_focus("result -> hub")


## UI-10: at 1280x800 and 1920x1080 the career screens keep their prompt bar on screen and every
## visible text is >= 18 px: slots (a career + an empty slot + a damaged one), new career, every
## hub tab unbooked, booked mid-camp and on fight week, and the result with its scorecards.
func test_layout_fits_and_text_is_readable() -> void:
	var ctrl := veteran(1)
	var pid := CareerFlow.profile_key()
	DirAccess.make_dir_recursive_absolute(ui_store().profile_dir(pid))
	var bad := FileAccess.open(ui_store().slot_path(pid, 3), FileAccess.WRITE)
	bad.store_string("{\"kind\": \"career\", broken")
	bad.close()
	var f := career_flow_for(ctrl)
	var summary: Dictionary = ctrl.state["last_fight"]
	var root := get_tree().root
	var old := root.size
	for res in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = res
		await wait_frames(3)
		var vr := get_viewport().get_visible_rect()
		var px_per_du := get_viewport().get_final_transform().get_scale().y
		App.goto("career", {"catalog": cat()})
		await wait_frames(4)
		_audit(top(), "career@%dx%d" % [res.x, res.y], vr, px_per_du)
		check(top().call("find_route", "aside:3") != null, "the damaged slot offers MOVE ASIDE")
		App.push("career_new", {"catalog": cat(), "slot": 2})
		await wait_frames(4)
		_audit(top(), "career_new@%dx%d" % [res.x, res.y], vr, px_per_du)
		if ctrl.is_booked():
			ctrl.withdraw()
		for phase in ["unbooked", "booked", "fight_week"]:
			if phase == "booked":
				check(ctrl.accept(str(ctrl.state["offers"][0]["id"])), "booked: %s" % ctrl.last_error)
			elif phase == "fight_week":
				ctrl.state["booked"]["weeks_left"] = 0
			for tab in ["camp", "offers", "gym", "history"]:
				if phase != "unbooked" and tab in ["gym", "history"]:
					continue
				f.show_hub(tab)
				await wait_frames(4)
				check_eq(str(top().call("current_tab")), tab, "hub opens on %s" % tab)
				_audit(top(), "career_hub/%s/%s@%dx%d" % [phase, tab, res.x, res.y], vr, px_per_du)
		App.goto("career_result", {"flow": f, "summary": summary})
		await wait_frames(4)
		_audit(top(), "career_result@%dx%d" % [res.x, res.y], vr, px_per_du)
		check(not top().find_children("*", "ScorecardPanel", true, false).is_empty(), "the result shows the judges' cards")
	root.size = old
	await wait_frames(2)


func _audit(s: Screen, tag: String, vr: Rect2, px_per_du: float) -> void:
	if not check(s != null, "%s: screen open" % tag):
		return
	var bars := 0
	for b in s.find_children("*", "PromptBar", true, false):
		var bar := b as Control
		if not bar.is_visible_in_tree():
			continue
		bars += 1
		var r := bar.get_global_rect()
		check(r.end.y <= vr.end.y + 1.0 and r.position.y >= vr.position.y - 1.0 and r.end.x <= vr.end.x + 1.0,
			"%s: footer prompts on screen (bar %s, view %s)" % [tag, str(r), str(vr.size)])
	check(bars > 0, "%s: has a prompt bar" % tag)
	var smallest := 999.0
	var smallest_text := ""
	for n in s.find_children("*", "", true, false):
		var size_du := 0
		var text := ""
		if n is Label and (n as Label).is_visible_in_tree():
			text = (n as Label).text
			size_du = (n as Label).get_theme_font_size("font_size")
		elif n is Button and (n as Button).is_visible_in_tree():
			text = (n as Button).text
			size_du = (n as Button).get_theme_font_size("font_size")
		if text.strip_edges() == "":
			continue
		var px := size_du * px_per_du
		if px < smallest:
			smallest = px
			smallest_text = text
	check(smallest >= 18.0 - 0.01, "%s: smallest text '%s' is %.1f px (< 18 px)" % [tag, smallest_text.substr(0, 30), smallest])
	# the screen content stays inside the viewport horizontally (no clipped columns)
	for n2 in s.find_children("*", "PanelContainer", true, false):
		var pc := n2 as Control
		if pc.is_visible_in_tree() and not _inside_scroll(pc, s):
			check(pc.get_global_rect().end.x <= vr.end.x + 2.0, "%s: %s fits the width (%s)" % [tag, pc.name, str(pc.get_global_rect())])


func _inside_scroll(c: Node, s: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != s:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


## A career created with real input: NEW CAREER, a fighter changed with right, START CAREER.
func test_create_a_career_with_real_input() -> void:
	App.goto("main_menu")
	await wait_frames(3)
	App.push("career", {"catalog": cat()})
	await wait_frames(4)
	check_eq(route_of(focus_owner()), "new:1", "NEW CAREER in slot 1 has the focus")
	await action("ui_accept")
	await wait_frames(4)
	check_eq(top_name(), "career_new", "the new-career screen")
	var ok: bool = await nav_to("key:fighter", "ui_up")
	check(ok, "the Fighter row is reachable")
	var fighters := cat().available_fighters()
	check(fighters.size() >= 2, "several fighters to pick from")
	await action("ui_right")
	await wait_frames(2)
	var picked := str(fighters[1])
	check_eq(str(top().get("fighter")), picked, "right picks the next fighter")
	check(find_label(top(), CareerOffers.fighter_name(cat(), picked).to_upper()) != null, "the preview names the picked fighter")
	ok = await nav_to("start")
	check(ok, "START CAREER is reachable")
	await action("ui_accept")
	await wait_frames(4)
	check_eq(top_name(), "career_hub", "START CAREER opens the hub")
	expect_focus("new career -> hub")
	check(ui_store().occupied(CareerFlow.profile_key(), 1), "the career is saved in slot 1")
	var st := reload(1)
	check_eq(str(st.get("fighter", "")), picked, "with the picked fighter")
	check_eq(str(st.get("name", "")), "UI Test", "billed under the profile name by default")
	check_eq(str(st.get("difficulty", "")), "normal", "Normal difficulty by default")
	check_eq(int(st.get("week", 0)), 1, "week 1")
	check(not (st.get("offers", []) as Array).is_empty(), "with offers waiting")


## A few weeks with real input on the hub: train, rest, accept an offer, buy an upgrade, refuse an
## unaffordable one. Every step changes the state on screen and on disk (autosave).
func test_walk_weeks_with_real_input() -> void:
	var ctrl := make_career(1)
	var f := career_flow_for(ctrl)
	f.show_hub("camp")
	await wait_frames(4)
	check_eq(top_name(), "career_hub", "the hub")
	check_eq(route_of(focus_owner()), "train:stamina", "the train grid starts on Stamina")
	var gain := ctrl.preview_gain("stamina")
	var before := float(ctrl.state["stats"]["stamina"])
	await action("ui_accept")
	await wait_frames(2)
	check_eq(int(ctrl.state["week"]), 2, "a trained week moves the calendar")
	check_near(float(ctrl.state["stats"]["stamina"]), snappedf(before + gain, 0.0001), 0.0002, "Stamina gained exactly the previewed amount")
	check_eq(route_of(focus_owner()), "train:stamina", "focus stays on the card after the rebuild")
	check_eq(int(reload(1)["week"]), 2, "autosaved after training")
	var ok: bool = await nav_to("rest")
	check(ok, "Rest is reachable")
	await action("ui_accept")
	await wait_frames(2)
	check_eq(int(ctrl.state["week"]), 3, "a rest week")
	check_eq(int(reload(1)["week"]), 3, "autosaved after resting")
	await action("ui_tab_next")
	check_eq(str(top().call("current_tab")), "offers", "RB opens OFFERS")
	expect_focus("offers")
	var first: String = route_of(focus_owner())
	check(first.begins_with("offer:"), "an offer card has the focus (%s)" % first)
	await action("ui_accept")
	await wait_frames(2)
	check(ctrl.is_booked(), "A accepts the offer")
	check_eq("offer:" + ctrl.booked_id(), first, "the focused offer was booked")
	check_eq(str(top().call("current_tab")), "camp", "accepting returns to the camp")
	check(top().call("find_route", "pull_out") != null, "the booked camp offers PULL OUT")
	check(find_label(top(), "YOU") != null and find_label(top(), "THEM") != null, "the fight card compares the stats")
	check(not (reload(1)["booked"] as Dictionary).is_empty(), "autosaved after booking")
	await action("ui_tab_next")
	await action("ui_tab_next")
	check_eq(str(top().call("current_tab")), "gym", "RB twice more opens GYM")
	check_eq(route_of(focus_owner()), "gym:stamina", "the first facility has the focus")
	var money := int(ctrl.state["money"])
	var cost := ctrl.upgrade_cost("stamina", 0)
	await action("ui_accept")
	await wait_frames(2)
	check_eq(int(ctrl.state["gym"]["stamina"]), 1, "A buys the Cardio Loft")
	check_eq(int(ctrl.state["money"]), money - cost, "for its price")
	check_eq(int(reload(1)["gym"]["stamina"]), 1, "autosaved after the upgrade")
	ok = await nav_to("gym:chin", "ui_right")
	var left := int(ctrl.state["money"])
	await action("ui_accept")
	await wait_frames(2)
	check_eq(int(ctrl.state["gym"]["chin"]), 0, "an unaffordable upgrade is refused")
	check_eq(int(ctrl.state["money"]), left, "and costs nothing")
	check(find_label(top(), "Not enough money") != null, "the refusal is explained")
	await action("ui_tab_next")
	check_eq(str(top().call("current_tab")), "history", "HISTORY")
	check(find_label(top(), "Signed to fight") != null, "the news log shows the booking")


## A bout through CareerFlow: FIGHT marks it in progress before the launch, the synthetic B1-shaped
## 10-point result lands on career_result (method, pay, popularity, scorecards) and CONTINUE goes
## back to the hub one week later with the fight in the history.
func test_fight_through_career_flow_to_the_result_and_back() -> void:
	var ctrl := make_career(1)
	var o := book(ctrl)
	var week := int(ctrl.state["week"])
	var pop := float(ctrl.state["pop"])
	TestCareerFlow.next_result = scoring_result(0, "Unanimous Decision")
	var f := career_flow_for(ctrl)
	f.show_hub()
	await wait_frames(4)
	check_eq(str(top().call("current_tab")), "camp", "fight week opens on the camp")
	check_eq(route_of(focus_owner()), "fight", "FIGHT has the focus on fight week")
	check(top().call("find_route", "train:stamina") == null, "no training on fight week")
	await action("ui_accept")
	await wait_frames(4)
	check_eq(TestCareerFlow.launches.size(), 1, "one bout launched")
	if TestCareerFlow.launches.is_empty():
		return
	var l: Dictionary = TestCareerFlow.launches[0]
	check(bool(l["in_fight"]), "the bout was marked in progress (and saved) before the launch (D4)")
	check_eq(str(l["fight_id"]), str(o["id"]), "the booked bout")
	var cfg: Dictionary = l["cfg"]
	check(bool(cfg.get("no_record", false)) and bool(cfg.get("context", {}).get("career", false)), "no_record + career context (D9)")
	check_eq(str(cfg["fighters"][0]["kind"]), "player", "the player fights it")
	check_eq(top_name(), "career_result", "the result screen")
	expect_focus("career_result")
	check(find_label(top(), "WIN") != null, "WIN")
	check(find_label(top(), "UNANIMOUS DECISION · 30-27 · 29-28 · 29-28") != null, "the method with the judges' totals")
	check(find_label(top(), CareerController.money_text(int(o["purse"]) + int(o["bonus"]))) != null, "the pay (purse + win bonus)")
	var panels := top().find_children("*", "ScorecardPanel", true, false)
	check(not panels.is_empty(), "the judges' cards")
	if not panels.is_empty():
		var sp := panels[0] as ScorecardPanel
		check_eq(sp.team_name(0), "Tester", "the scorecard names the career fighter for team 0")
		check_eq(sp.team_name(1), str(o["opp"]["name"]), "and the opponent for team 1")
	check(float(ctrl.state["pop"]) > pop, "popularity went up")
	await action("ui_accept")
	await wait_frames(4)
	check_eq(top_name(), "career_hub", "CONTINUE returns to the hub")
	expect_focus("result -> hub")
	check_eq(int(ctrl.state["week"]), week + 1, "one week later")
	check(not ctrl.is_booked(), "the booking is over")
	var st := reload(1)
	check((st["claims"] as Array).has(str(o["id"])), "the result was claimed and saved")
	check_eq((st["history"] as Array).size(), 1, "the fight is in the history")
	# a T.K.O. reads round and time
	var t := CareerUi.method_line({"method": "TKO", "won": true, "round": 2, "time": 42.0})
	check_eq(t, "T.K.O. · ROUND 2 · 0:42", "T.K.O. method line")
	check_eq(CareerUi.method_line({"method": "Split Decision", "won": false, "totals": [[28, 29], [29, 28], [28, 29]]}),
		"SPLIT DECISION · 29-28 · 28-29 · 29-28", "a loss reads the winner's score first")


## D4: in a career bout the pause menu offers no Restart and its quit is a withdrawal
## (popularity -4, week +1, no purse); a result arriving afterwards is refused.
func test_pause_menu_quit_pulls_out_of_a_career_bout() -> void:
	var ctrl := make_career(1)
	var o := book(ctrl)
	ctrl.state["pop"] = 20.0
	var week := int(ctrl.state["week"])
	var money := int(ctrl.state["money"])
	var f := CareerFlow.make(cat(), ctrl)
	check(f.fight(), "the bout launches: %s" % f.last_error)
	await wait_frames(6)
	var ms := MatchFlow.current_match()
	check(ms != null, "a presented match is running")
	if ms == null:
		return
	check(CareerFlow.of_scene(ms) == f, "the match scene keeps the career flow (meta career_flow)")
	check(MatchFlow.last_config.is_empty(), "nothing to restart")
	check(ctrl.interrupted(), "in progress on disk until it ends (a crash would re-fight it)")
	MatchFlow.open_pause()
	await wait_frames(4)
	check_eq(top_name(), "pause", "the pause menu")
	var routes := []
	for b in top().find_children("*", "UiButton", true, false):
		routes.append((b as UiButton).route)
	check(not routes.has("restart"), "no Restart in a career bout (%s)" % str(routes))
	var ok: bool = await nav_to("quit")
	check(ok, "Quit to main menu is reachable")
	await action("ui_accept")
	await wait_frames(3)
	check_eq(top_name(), "dialog", "quitting asks first")
	check(find_label(top(), "Pull out of this fight?") != null, "it is a pull-out")
	check(find_label(top(), "No purse, popularity -4.") != null, "with the terms")
	check_eq(route_of(focus_owner()), "stay", "Keep fighting is the safe default")
	ok = await nav_to("pull", "ui_left")
	await action("ui_accept")
	await wait_frames(4)
	check_eq(top_name(), "main_menu", "back at the main menu")
	check(App.current_scene == null or not (App.current_scene is MatchScene), "the match is gone")
	check_near(float(ctrl.state["pop"]), 16.0, 0.001, "popularity -4")
	check_eq(int(ctrl.state["week"]), week + 1, "week +1")
	check_eq(int(ctrl.state["money"]), money, "no purse")
	check(not ctrl.is_booked(), "the booking is gone")
	check(not ctrl.interrupted(), "nothing to re-fight")
	var st := reload(1)
	check_near(float(st["pop"]), 16.0, 0.001, "the withdrawal was saved")
	var late := ctrl.apply_result(scoring_result(0, "Unanimous Decision"), str(o["id"]))
	check(not bool(late["ok"]) and bool(late["duplicate"]), "a late result for the bout is refused")
	check_near(float(ctrl.state["pop"]), 16.0, 0.001, "and changes nothing")


## The booked camp's PULL OUT is the same withdrawal, behind a danger confirmation.
func test_hub_pull_out_is_a_confirmed_withdrawal() -> void:
	var ctrl := make_career(1)
	var o: Dictionary = ctrl.state["offers"][0]
	check(ctrl.accept(str(o["id"])), "booked")
	ctrl.state["pop"] = 10.0
	var week := int(ctrl.state["week"])
	var f := career_flow_for(ctrl)
	f.show_hub("camp")
	await wait_frames(4)
	var ok: bool = await nav_to("pull_out")
	check(ok, "PULL OUT is reachable")
	await action("ui_accept")
	await wait_frames(3)
	check_eq(top_name(), "dialog", "pulling out asks first")
	await action("ui_accept")
	await wait_frames(3)
	check_eq(top_name(), "career_hub", "Keep the fight (the default) keeps it")
	check(ctrl.is_booked(), "still booked")
	ok = await nav_to("pull_out")
	await action("ui_accept")
	await wait_frames(3)
	ok = await nav_to("pull", "ui_left")
	await action("ui_accept")
	await wait_frames(3)
	check_eq(top_name(), "career_hub", "back on the hub")
	check(not ctrl.is_booked(), "pulled out")
	check_near(float(ctrl.state["pop"]), 6.0, 0.001, "popularity -4")
	check_eq(int(ctrl.state["week"]), week + 1, "week +1")
	check_eq(TestCareerFlow.launches.size(), 0, "no bout was fought")


## D4: a bout interrupted by a crash (in_fight saved, never settled) is offered again from the slot
## list; RE-FIGHT launches the identical bout and its result settles normally.
func test_interrupted_bout_is_offered_again() -> void:
	var ctrl := make_career(1)
	var o := book(ctrl)
	check(ctrl.begin_fight(), "launch marker saved")
	var seed_before := int(ctrl.fight_config()["seed"])
	ctrl = null      # the process "crashed": only the save is left
	TestCareerFlow.next_result = scoring_result(1, "Split Decision")
	App.goto("career", {"catalog": cat(), "flow_script": TestCareerFlow})
	await wait_frames(4)
	check(find_label(top(), "was interrupted") != null, "the slot says the bout was interrupted")
	check_eq(route_of(focus_owner()), "refight:1", "RE-FIGHT has the focus")
	await action("ui_accept")
	await wait_frames(4)
	check_eq(TestCareerFlow.launches.size(), 1, "the bout was launched again")
	if TestCareerFlow.launches.is_empty():
		return
	var l: Dictionary = TestCareerFlow.launches[0]
	check_eq(str(l["fight_id"]), str(o["id"]), "the same bout")
	check_eq(int((l["cfg"] as Dictionary)["seed"]), seed_before, "with the same seed")
	check_eq(str((l["cfg"] as Dictionary)["fighters"][1]["name"]), str(o["opp"]["name"]), "against the same opponent")
	check_eq(top_name(), "career_result", "its result is shown")
	check(find_label(top(), "LOSS") != null, "a loss")
	var st := reload(1)
	check((st["claims"] as Array).has(str(o["id"])), "settled once")
	check((st["booked"] as Dictionary).is_empty(), "and no longer booked")


## D3: RETIRE asks (danger), moves the save aside and frees the slot; a damaged slot is moved aside
## the same way, never deleted.
func test_retire_and_move_aside_free_the_slot() -> void:
	make_career(1)
	var pid := CareerFlow.profile_key()
	DirAccess.make_dir_recursive_absolute(ui_store().profile_dir(pid))
	var bad := FileAccess.open(ui_store().slot_path(pid, 2), FileAccess.WRITE)
	bad.store_string("{not json")
	bad.close()
	App.goto("career", {"catalog": cat()})
	await wait_frames(4)
	check(find_label(top(), "damaged") != null, "the damaged slot shows its error")
	var ok: bool = await nav_to("retire:1")
	check(ok, "RETIRE is reachable")
	await action("ui_accept")
	await wait_frames(3)
	check_eq(top_name(), "dialog", "retiring asks first")
	check(find_label(top(), "Retire Tester?") != null, "naming the fighter")
	check(find_label(top(), "The save is moved aside.") != null, "and what happens to the save")
	ok = await nav_to("retire", "ui_left")
	await action("ui_accept")
	await wait_frames(4)
	check_eq(top_name(), "career", "back on the slots")
	check(not ui_store().occupied(pid, 1), "slot 1 is free")
	check(top().call("find_route", "new:1") != null, "and offers NEW CAREER")
	var retired := DirAccess.get_files_at(ui_store().profile_dir(pid).path_join("retired"))
	check(retired.size() >= 1, "the retired save is kept aside (%s)" % str(retired))
	ok = await nav_to("aside:2")
	check(ok, "MOVE ASIDE on the damaged slot is reachable")
	await action("ui_accept")
	await wait_frames(3)
	check_eq(top_name(), "dialog", "moving aside asks first")
	ok = await nav_to("aside", "ui_left")
	await action("ui_accept")
	await wait_frames(4)
	check(not ui_store().occupied(pid, 2), "slot 2 is free")
	check(DirAccess.get_files_at(ui_store().profile_dir(pid).path_join("retired")).size() >= 2, "the damaged file was moved, not deleted")
