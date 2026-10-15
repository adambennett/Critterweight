extends HubTestCase
## The Cannery as one scene among the game's others (docs/HUB_SYSTEMS.md §1, §9), with the real
## HubScene entered through Cannery.enter():
##   * match audio survives every hub <-> match swap (spar, lesson, rooftop practice, the tape, a
##     match started over the hub) in both directions
##   * a lesson from Granny's corner returns by a plain route (never a lambda kept in a static) that
##     quitting to the menu forgets
##   * boards stop the hub's clocks (the PAUSED board above all)
##   * "Restart fight" in a spar restarts that spar and still walks back in; the tape offers none
##   * rooftop practice returns to the roof; the campaign menu opened at the desk goes back to it
##   * the hub is not an online match; the pet's "None" hides it; a fighter switch calls off a
##     challenge; dev stand-ins apply to one sign-up only
## User data is redirected to a temporary root.

var _root := ""
var _profile := {}


func before_each() -> void:
	App.clear_screens()
	_root = Paths.root
	Paths.root = temp_dir("hub_flow_%d" % Time.get_ticks_usec())
	_profile = Profiles.current
	Profiles.current = Profiles.default_profile("hub_flow", "Flow Tester")
	CampaignProgression.ensure_fields(Profiles.current)
	CampaignFlow.force_dev_tools = false


func after_each() -> void:
	MatchFlow.set_paused(false)
	App.clear_screens()
	if App.current_scene != null:
		App.set_scene(null)
	Tutorial.clear_exit_route()
	MatchFlow.last_config = {}
	CampaignFlow.force_dev_tools = false
	await wait_frames(2)
	Paths.root = _root
	Profiles.current = _profile


# --- helpers -------------------------------------------------------------------------------------

func enter_hub(params := {}) -> HubScene:
	Cannery.enter(params)
	await settle()
	var sc := App.current_scene as HubScene
	check(sc != null and sc.sim != null, "the Cannery is on screen")
	return sc


func settle(physics := 8, frames := 4) -> void:
	await wait_physics(physics)
	await wait_frames(frames)


func seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true, true).timeout


## The audio bridge (Audio's per-match event reader) belongs to the scene on screen.
func expect_audio(tag: String) -> void:
	var b = Audio.get("_bridge")
	var live = b.get("sim") if b != null and is_instance_valid(b) else null
	var cs = App.current_scene
	var want = cs.get("sim") if cs != null and is_instance_valid(cs) else null
	check(want != null and live == want, "%s: the match audio follows the scene on screen (bridge %s)" % [tag, "attached" if live != null else "missing"])
	check(not Audio.match_context().is_empty(), "%s: with its match context" % tag)


func hub_scene() -> HubScene:
	return App.current_scene as HubScene


func rules_id(cfg: Dictionary) -> String:
	var r = cfg.get("rules", {})
	return str((r as Dictionary).get("id", "")) if typeof(r) == TYPE_DICTIONARY else str(r)


# --- review #1 -------------------------------------------------------------------------------------

func test_match_audio_survives_every_hub_scene_swap() -> void:
	HubState.new(Profiles.current).find_secret("sec_freight_elevator")      # the roof is open
	var hub := await enter_hub({"spot": "main_floor"})
	expect_audio("the hub")
	var ms := HubSparring.launch(hub, {"opponent": "kid_lamprey", "tier": "journeyman", "format": "spar"})
	await settle()
	expect_audio("a spar started from the hub")
	HubSparring.finished(ms.config.get("hub_spar", {}), {"winner_team": -2, "left": true})
	await settle()
	expect_audio("back in the hub after the spar")
	HubSparring.play_tape(hub_scene())
	await settle()
	expect_audio("the 1973 tape")
	Cannery.enter({"spot": "booth", "from": "tape"})
	await settle()
	expect_audio("back in the booth after the tape")
	App.push("hub_board", {"kind": "lessons", "scene": hub_scene()})
	await wait_frames(2)
	(App.top_screen() as HubBoard).call("_start_lesson", 0)
	await settle()
	expect_audio("a lesson from Granny's corner")
	Tutorial.exit_tutorial()
	await settle(10, 6)
	expect_audio("back from the lesson")
	Cannery.enter({"spot": "roof"})
	await settle()
	hub_scene().call("_service", "rooftop_practice")
	await settle()
	expect_audio("rooftop practice")
	MatchFlow.quit_to_menu()
	await settle()
	# any match started over the hub (a resumed campaign fight is one) keeps its audio too
	var hub2 := await enter_hub({"spot": "office"})
	var cfg := HubSparring.config(hub2.player().creature.id, "Flow", {"opponent": "f_dredge", "tier": "journeyman"})
	cfg.erase("hub_spar")
	cfg.erase("overlay_script")
	App.start_match(cfg)
	await settle()
	expect_audio("a match started over the hub")


# --- review #2 -------------------------------------------------------------------------------------

func test_lessons_return_by_a_route_not_a_stored_lambda() -> void:
	var hub := await enter_hub({"spot": "main_floor"})
	App.push("hub_board", {"kind": "lessons", "scene": hub})
	await wait_frames(2)
	(App.top_screen() as HubBoard).call("_start_lesson", 0)
	await settle()
	check(App.current_scene is MatchScene, "the lesson runs in the practice cage")
	var route: Dictionary = Tutorial._exit_route
	check_eq(str(route.get("screen", "")), "hub", "the way back is a plain route to the hub screen (no lambda kept in a static)")
	check_eq(str((route.get("params", {}) as Dictionary).get("spot", "")), "main_floor", "...to Granny's corner")
	Tutorial.exit_tutorial()
	await settle(10, 6)
	check(hub_scene() != null and hub_scene().mode.current_space == "main_floor", "leaving the lesson walks back onto the Main Floor")
	check(Tutorial._exit_route.is_empty(), "and the route is used up")
	# quitting the lesson to the main menu forgets the way back to the hub
	App.push("hub_board", {"kind": "lessons", "scene": hub_scene()})
	await wait_frames(2)
	(App.top_screen() as HubBoard).call("_start_lesson", 0)
	await settle()
	MatchFlow.quit_to_menu()
	await settle()
	check(Tutorial._exit_route.is_empty(), "quit to the main menu: no route left behind (a later lesson exits normally)")


# --- review #5 -------------------------------------------------------------------------------------

func test_boards_freeze_the_hubs_clocks() -> void:
	var hub := await enter_hub({"spot": "loading_dock"})
	var mode := hub.mode
	check(mode.start_activity("drill"), "the chum drill starts")
	await seconds(4.0)
	check(mode.drill.phase == "running", "the drill is running (%s)" % mode.drill.phase)
	var t0 := mode.drill.t
	var hits0 := mode.drill.hits_taken
	var fired0 := mode.drill.fired
	hub.open_board("pause")
	await wait_frames(2)
	await seconds(6.0)
	check(mode.frozen, "the PAUSED board stops the hub's clocks")
	check_near(mode.drill.t, t0, 0.05, "the drill's clock waits")
	check_eq(mode.drill.hits_taken, hits0, "nothing hits the fighter standing at the board")
	check_eq(mode.drill.fired, fired0, "the cannon holds fire")
	App.clear_screens()
	await seconds(1.0)
	check(not mode.frozen and mode.drill.t > t0 + 0.5, "closing the board starts the clock again")
	mode.cancel_activity()
	# a bag challenge does not run out behind a board either
	var hub2 := await enter_hub({"spot": "main_floor"})
	var m2 := hub2.mode
	m2.start_activity("bag", "heavy")
	await seconds(3.5)
	var left := m2.bags.time_left()
	hub2.open_board("talk", {"npc": "granny"})
	await seconds(32.0)
	check(m2.bags.running(), "the bag challenge is still on after 32 s behind a board")
	check_near(m2.bags.time_left(), left, 0.05, "with the same time left")
	App.clear_screens()


# --- review #6 -------------------------------------------------------------------------------------

func test_restart_fight_restarts_the_spar_and_walks_back_in() -> void:
	var hub := await enter_hub({"spot": "main_floor"})
	var fid := hub.player().creature.id
	# a lesson first: it leaves its own config behind for "Restart fight"
	Tutorial.start(0, fid, {"screen": "hub", "params": {"spot": "main_floor", "from": "tutorial"}})
	await settle()
	Tutorial.exit_tutorial()
	await settle(10, 6)
	var ms := HubSparring.launch(hub_scene(), {"opponent": "kid_lamprey", "tier": "journeyman", "format": "spar"})
	await settle()
	check_eq(rules_id(MatchFlow.last_config), "hub_spar", "the spar is what Restart fight replays (not the lesson)")
	App.push("pause")
	await wait_frames(2)
	var labels := []
	for b in App.top_screen().find_children("*", "Button", true, false):
		labels.append((b as Button).text)
	check(labels.any(func(t): return str(t).contains("Restart")), "the pause menu offers Restart fight")
	App.pop()
	var ms2 := MatchFlow.restart()
	await settle()
	check(ms2 != null and ms2 != ms and rules_id(ms2.config) == "hub_spar", "Restart fight starts the spar again")
	check_eq(str((ms2.config.get("hub_spar", {}) as Dictionary).get("opponent", "")), "kid_lamprey", "against the same partner")
	# the restarted spar still ends in the Cannery
	ms2.match_finished.emit({"winner_team": 1, "time": 30.0})
	await settle(10, 6)
	check(hub_scene() != null and hub_scene().mode.current_space == "main_floor", "the restarted spar walks back into the Cannery")
	# a practice spar's dummy fights at the chosen tier after a restart too (it is in the config)
	var prac := HubSparring.config(fid, "Flow", {"opponent": "kid_lamprey", "tier": "contender", "format": "practice"})
	check_eq(str(prac["rules"].get("dummy_behavior", "")), "bot", "the practice dummy fights back")
	check_eq(str(prac["rules"].get("dummy_tier", "")), BotTiers.brain_tier("contender"), "at the chosen tier")
	# the tape is watched, never restarted
	HubSparring.play_tape(hub_scene())
	await settle()
	check(MatchFlow.last_config.is_empty(), "no Restart fight for the tape (nor into an earlier match)")
	App.push("pause")
	await wait_frames(2)
	var labels2 := []
	for b2 in App.top_screen().find_children("*", "Button", true, false):
		labels2.append((b2 as Button).text)
	check(not labels2.any(func(t): return str(t).contains("Restart")), "the tape's pause menu has no Restart fight")
	App.pop()


# --- review #10 ------------------------------------------------------------------------------------

func test_rooftop_practice_walks_back_onto_the_roof() -> void:
	HubState.new(Profiles.current).find_secret("sec_freight_elevator")
	var hub := await enter_hub({"spot": "roof"})
	check_eq(hub.mode.current_space, "roof", "on the roof by the chalk ring")
	hub.call("_service", "rooftop_practice")
	await settle()
	var ms := App.current_scene as MatchScene
	check(ms != null, "rooftop practice runs")
	if ms == null:
		return
	check_eq(str((ms.config.get("hub_spar", {}) as Dictionary).get("spot", "")), "roof", "the spar remembers where it started")
	HubSparring.finished(ms.config.get("hub_spar", {}), {"winner_team": -2, "left": true})
	await settle(10, 6)
	check(hub_scene() != null and hub_scene().mode.current_space == "roof", "back on the roof, not the Main Floor")
	# the cage's spars still come back to the cage
	var cage := HubSparring.config("f_stoke", "Flow", {"opponent": "kid_lamprey"})
	check_eq(str(cage["hub_spar"]["spot"]), "main_floor", "a cage spar returns to the Main Floor")


# --- review #11 ------------------------------------------------------------------------------------

func test_campaign_menu_from_the_desk_goes_back_to_the_hub() -> void:
	var hub := await enter_hub({"spot": "office"})
	hub.services.open_campaign_menu()
	await wait_frames(4)
	var top := App.top_screen()
	check(top != null and top.screen_name == "campaign_menu", "the sign-up sheet opens the campaign menu")
	if top == null:
		return
	var back: Button = null
	for b in top.find_children("*", "Button", true, false):
		if (b as Button).text.contains("CANNERY"):
			back = b
	check(back != null, "its Back button says where it goes")
	if back != null:
		back.pressed.emit()
	await settle(10, 6)
	check(hub_scene() != null and hub_scene().mode.current_space == "office", "...and walks back to Snappington's desk")
	# Esc / B does the same
	hub_scene().services.open_campaign_menu()
	await wait_frames(4)
	App.top_screen().on_back()
	await settle(10, 6)
	check(hub_scene() != null and hub_scene().mode.current_space == "office", "B also returns to the desk")
	# opened from the main menu, Back still goes to the menu
	App.set_scene(null)
	App.goto("campaign_menu", {"variant": "fight_camp"})
	await wait_frames(4)
	check(not bool(App.top_screen().get("return_to_hub")), "from the main menu it is the main menu's campaign menu")


# --- review #12 ------------------------------------------------------------------------------------

func test_the_hub_is_not_an_online_match() -> void:
	var hub := await enter_hub({"spot": "main_floor"})
	check(not MatchFlow.is_online(), "the Cannery is a local world")
	hub.open_board("pause")
	await wait_frames(2)
	App.push("settings", {"in_game": true})
	await wait_frames(3)
	var texts := []
	for l in App.top_screen().find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	check(not texts.any(func(t): return str(t).contains("ONLINE")), "Settings from the pause board say nothing about an online match")
	check(texts.has("PAUSED"), "they say the game is paused")


# --- review #7 -------------------------------------------------------------------------------------

func test_pet_none_hides_the_blister() -> void:
	var st := HubState.new(Profiles.current)
	st.unlock_cosmetic("hub_pet_blister")
	st.equip("pet", "hub_pet_blister")
	var hub := await enter_hub({"spot": "locker_room"})
	await wait_frames(3)
	check(hub.view.ambient.pet.visible, "the Frozen Blister follows you")
	hub.state.equip("pet", "")         # the locker's "None"
	await wait_frames(3)
	check(not hub.view.ambient.pet.visible, "None sends it home")
	hub.state.equip("pet", "hub_pet_blister")
	await wait_frames(3)
	check(hub.view.ambient.pet.visible, "and choosing it again brings it back")


# --- review #8 -------------------------------------------------------------------------------------

func test_switching_fighters_calls_off_the_challenge() -> void:
	var hub := await enter_hub({"spot": "main_floor", "fighter": "f_dredge"})
	var mode := hub.mode
	var st := hub.state
	var c0 := st.clout()
	mode.start_activity("bag", "heavy")
	await seconds(3.4)
	mode.bags.score = 1100.0
	hub.switch_fighter("f_jitters")
	check(not mode.bags.running(), "switching fighters at the locker calls the challenge off")
	check(bool(mode.bags.result.get("cancelled", false)), "(cancelled, not scored)")
	await seconds(1.0)
	check_eq(st.tier_of("bag_heavy_f_jitters"), 0, "Jitters gets nothing for Dredge's hits")
	check_eq(st.clout(), c0, "and no Clout changes hands")


# --- review #13 ------------------------------------------------------------------------------------

func test_dev_stand_ins_apply_to_one_sign_up_only() -> void:
	CampaignFlow.force_dev_tools = true
	var hub := await enter_hub({"spot": "office"})
	hub.open_board("run", {"stand_ins": true})
	await wait_frames(3)
	check(not hub.services.stand_ins, "the stand-in sheet does not switch the hub's services over")
	App.clear_screens()
	await wait_frames(2)
	hub.open_board("run")
	await wait_frames(3)
	check(not hub.services.stand_ins, "the next sheet of the visit is a normal one")
	check_eq(hub.services.catalog(), CampaignCatalog.shared(), "stations, the Bookie's Table and later sign-ups use the real catalog")
	App.clear_screens()
