extends HubTestCase
## CMP-03/CMP-04: all ten Cannery secrets trigger as specified (HUB.md §5), pay their rewards once
## and change the world for good (docs/HUB_SYSTEMS.md §7 lists each trigger).


func _found(id: String, since: int) -> bool:
	return not events_of("hub_secret", since).filter(func(e): return str(e["id"]) == id).is_empty() and state.has_secret(id)


func _face(p: Vector3) -> void:
	var to := p - player().pos()
	player().facing_yaw = atan2(to.x, to.z)


func test_01_02_loose_panel_and_crawlspace_tooth() -> void:
	make_hub("dev_biped")
	var bag: RigidBody3D = mode.bag_body("body")
	await teleport(Vector3(bag.global_position.x + 1.0, 0, bag.global_position.z), 270.0)
	var s0 := last_seq()
	# a plain jab does not loosen anything
	_face(bag.global_position)
	press("light")
	await run_until(func(): return false, 0.8)
	check(not mode.secrets.panel_revealed(), "a jab on bag 3 reveals nothing")
	# a Charged Heavy swings it wide and the panel behind it comes loose
	for attempt in 4:
		if mode.secrets.panel_revealed():
			break
		await teleport(Vector3(bag.global_position.x + 1.0, 0, bag.global_position.z), 270.0)
		_face(bag.global_position)
		press("heavy")
		driver.hold = ["heavy"]
		await run_until(func(): return false, 0.85)
		driver.hold = []
		await run_until(func(): return mode.secrets.panel_revealed(), 1.0)
	check(mode.secrets.panel_revealed(), "a Charged Heavy on bag 3 reveals the loose panel")
	check(not events_of("hub_reveal", s0).filter(func(e): return str(e["what"]) == "panel").is_empty(), "the reveal is announced")
	# Grab pulls it off: secret #1, 50 Clout, the crawlspace opens
	await teleport(Vector3(-11.2, 0, 4.9), 270.0)
	var clout0 := state.clout()
	press("grab")
	await run_until(func(): return state.has_secret("sec_loose_panel"), 1.0)
	check(_found("sec_loose_panel", s0), "Grab pulls the panel off (secret #1)")
	check_eq(state.clout() - clout0, 50, "50 Clout")
	check(bool(state.flag("panel_pal")), "Ludlow's Panel Pal dialogue is unlocked")
	var ok := await walk_nav(["cs_in", "cs_end"], 10.0)
	check(ok and mode.current_space == "crawlspace", "the 3 m crawlspace is walkable now")
	# secret #2: the jar on the shelf
	await run_until(func(): return false, 0.3)
	check_eq(str(mode.focus_of(player()).get("id", "")), "crawl_jar", "the jar is offered")
	mode.request_interact(player())
	await run_until(func(): return state.has_secret("sec_crawlspace_tooth"), 1.0)
	check(_found("sec_crawlspace_tooth", s0), "Granny's old tooth (secret #2)")
	check(state.has_cosmetic("hub_gold_tooth"), "Gold Tooth cosmetic unlocked")


func test_03_sleeping_scrapling_wakes_and_is_caught() -> void:
	make_hub("f_stoke")
	check_eq(mode.secrets.scrapling_state(), "asleep", "a Scrapling sleeps under the stairs")
	mode.bags.start("heavy")
	mode.bags.phase = "running"
	mode.bags.score = 640.0
	mode.bags.finish()
	check_eq(mode.secrets.scrapling_state(), "running", "600+ on the Heavy bag wakes it")
	check(mode.item_visible("trash_lid"), "it drops its lid")
	var s0 := last_seq()
	# cut it off on its way to the roller door and Grab it there
	var clout0 := state.clout()
	driver.set_path([Vector3(3.5, 0, -6.3)])
	var t := 0.0
	while t < 12.0 and mode.secrets.scrapling_state() == "running":
		var sp := mode.secrets.scrapling_pos()
		if player().pos().distance_to(sp) < 2.2:
			driver.set_path([sp])
		if player().pos().distance_to(sp) < 1.5:
			_face(sp)
			press("grab")
		await run_until(func(): return false, 0.1)
		t += 0.1
	check_eq(mode.secrets.scrapling_state(), "caught", "caught it")
	check(_found("sec_sleeping_scrapling", s0), "secret #3 found")
	check_eq(state.clout() - clout0, 25, "+25 Clout for catching it before the roller door")
	# the lid is still lying there: Grab picks it up (the cosmetic)
	var lid: RigidBody3D = mode.world["items"]["trash_lid"]
	await teleport(lid.global_position + Vector3(0, 0, -0.7) - Vector3(0, lid.global_position.y, 0), 0.0)
	_face(lid.global_position)
	press("grab")
	await run_until(func(): return state.has_cosmetic("hub_trash_lid"), 1.0)
	check(state.has_cosmetic("hub_trash_lid"), "the trash-can lid shield is yours")


func test_04_belt_case_taunts() -> void:
	make_hub("f_stoke")
	await teleport(HubLayout.BELT_CASE_POS + Vector3(0, 0, 1.3), 180.0)
	var s0 := last_seq()
	for i in 3:
		press("taunt")
		await run_until(func(): return false, 2.3)
	var kid := events_of("hub_say", s0).filter(func(e): return str(e["npc"]) == "kid" and str(e["key"]) == "line:belt_case")
	check(not kid.is_empty(), "after three taunts Kid Lamprey says \"...it's not even locked\"")
	check_eq(HubContent.keyed_line("kid", "belt_case"), "...it's not even locked.", "the line from HUB.md")
	await run_until(func(): return false, 0.2)
	check_eq(str(mode.focus_of(player()).get("id", "")), "belt_case", "the case is the interaction")
	mode.request_interact(player())
	await run_until(func(): return state.has_secret("sec_belt_case_combo"), 1.0)
	check(_found("sec_belt_case_combo", s0), "secret #4 found")
	check(state.has_cosmetic("hub_replica_belt"), "replica belt cosmetic")


func test_05_booth_tape_while_crouched() -> void:
	make_hub("f_stoke", "booth")
	await teleport(Vector3(1.4, 3.0, 9.6), 180.0)
	await run_until(func(): return false, 0.3)
	check(str(mode.focus_of(player()).get("id", "")) != "booth_chair", "standing up, there is nothing to reach")
	var s0 := last_seq()
	driver.hold = ["guard"]
	await run_until(func(): return player().state == Fighter.State.GUARD, 1.0)
	await run_until(func(): return false, 0.2)
	check_eq(str(mode.focus_of(player()).get("id", "")), "booth_chair", "crouched (guard) under the desk, the tape is in reach")
	mode.request_interact(player())
	await run_until(func(): return state.has_secret("sec_booth_tape"), 1.0)
	driver.hold = []
	check(_found("sec_booth_tape", s0), "secret #5: the 1973 tape")
	check(state.pack_on("vintage_bellows"), "the Vintage Bellows line pack is on")
	check(state.has_cosmetic("hub_pack_vintage_bellows"), "and unlocked")
	var tape := HubSparring.play_tape.bind(null)
	check(tape.is_valid(), "the replay can be launched")


func test_06_freight_elevator_parts() -> void:
	make_hub("f_stoke")
	var s0 := last_seq()
	check(not mode.condition("elevator_fixed"), "the elevator starts broken")
	# the button needs the Scouting Report (second filing cabinet)
	check(not mode.secrets.button_available(), "no second cabinet without the Scouting Report")
	state.camp()["upgrades"]["meta_scouting_report"] = 1
	check(mode.secrets.button_available(), "Scouting Report bought: the cabinet holds a button")
	await teleport(Vector3(7.3, 4.0, 10.5), 270.0)
	await run_until(func(): return false, 0.2)
	check_eq(str(mode.focus_of(player()).get("id", "")), "filing_cabinet_2", "the second filing cabinet")
	mode.request_interact(player())
	await run_until(func(): return not mode.carried_by(player()).is_empty(), 0.5)
	check_eq(str(mode.carried_by(player()).get("id", "")), "button", "you come away holding the button")
	# hand each part to Ludlow (he walks his rounds: catch him where he is)
	for part in ["button", "fuse", "cable_spool"]:
		if mode.carried_by(player()).is_empty():
			var body: RigidBody3D = mode.world["items"][part]
			await teleport(Vector3(body.global_position.x, 0.0, body.global_position.z) + Vector3(-0.7, 0, 0), 90.0)
			_face(body.global_position)
			press("grab")
			await run_until(func(): return not mode.carried_by(player()).is_empty(), 1.0)
			check_eq(str(mode.carried_by(player()).get("id", "")), part, "picked up %s" % part)
		var lp: Vector3 = mode.ludlow["pos"]
		await teleport(lp + Vector3(0.9, 0, 0), 270.0)
		await run_until(func(): return false, 0.2)
		var f := mode.focus_of(player())
		check(str(f.get("prompt", "")).begins_with("Give Ludlow"), "Ludlow's prompt offers to take the part (%s)" % str(f.get("prompt", "")))
		mode.request_interact(player())
		await run_until(func(): return state.parts().has(part), 1.0)
		check(state.parts().has(part), "Ludlow has the %s" % part)
	check(_found("sec_freight_elevator", s0), "secret #6: the elevator runs")
	check(mode.condition("elevator_fixed"), "the roof is open")
	check(mode.world["gate"].is_empty(), "the chain gate is gone")


func test_07_roof_sign_letter() -> void:
	make_hub("f_stoke")
	state.find_secret("sec_freight_elevator")
	await teleport(Vector3(51.6, 0, -26.9), 180.0)
	var letter: RigidBody3D = mode.world["items"]["letter_a"]
	_face(letter.global_position)
	press("grab")
	await run_until(func(): return not mode.carried_by(player()).is_empty(), 1.0)
	check_eq(str(mode.carried_by(player()).get("id", "")), "letter_a", "the fallen A picked up")
	# back off and heave it into the gap in GL_NDCO
	await teleport(Vector3(HubLayout.SIGN_SLOT.x, 0, -29.6), 180.0)
	player().facing_yaw = PI
	var s0 := last_seq()
	var clout0 := state.clout()
	mode.throw_carried(player(), 1.0)
	await run_until(func(): return state.has_secret("sec_roof_sign"), 3.0)
	check(_found("sec_roof_sign", s0), "secret #7: the sign is fixed")
	check_eq(state.clout() - clout0, 100, "100 Clout")
	check(state.has_cosmetic("hub_frame_sign_fixer") and state.has_cosmetic("hub_rooftop_neon"), "Sign Fixer frame and the Rooftop's full neon")


func test_08_pier_ladder_splash_and_fishing() -> void:
	make_hub("f_dredge")
	var crate: RigidBody3D = mode.world["crates"][3]
	await teleport(Vector3(crate.global_position.x, 0, crate.global_position.z + 0.85), 180.0)
	_face(crate.global_position)
	press("grab")
	await run_until(func(): return not mode.carried_by(player()).is_empty(), 1.0)
	await teleport(Vector3(-6.0, 0, -9.4), 180.0)
	player().facing_yaw = PI
	var s0 := last_seq()
	mode.throw_carried(player(), 1.0)
	await run_until(func(): return not events_of("hub_splash", s0).is_empty(), 3.0)
	var sp := events_of("hub_splash", s0)
	check(not sp.is_empty() and float(sp[0]["dist"]) >= 8.0, "an 8 m+ throw lands in the harbor")
	check(_found("sec_pier_ladder", s0), "secret #8: the gulls flee and the ladder shows")
	check(mode.condition("pier_revealed"), "the pier ladder can be climbed")
	# fishing: stay near the rod for 20 s
	mode.teleport(player(), Vector3(25.6, 0, -42.0), PI * 0.5)
	await run_until(func(): return false, 0.3)
	check_eq(str(mode.focus_of(player()).get("id", "")), "fishing_rod", "the rod")
	mode.request_interact(player())
	await run_until(func(): return state.has_cosmetic("hub_pier_night"), 22.0)
	check(state.has_cosmetic("hub_pier_night"), "the first catch is the Chum Rush arena variant Pier Night")
	mode.request_interact(player())
	await run_until(func(): return false, 0.2)
	mode.request_interact(player())
	await run_until(func(): return not events_of("hub_fish", s0).filter(func(e): return str(e["phase"]) == "catch").size() < 2, 22.0)
	var catches := events_of("hub_fish", s0).filter(func(e): return str(e["phase"]) == "catch")
	check(catches.size() >= 2 and str(catches[1].get("cosmetic", "")).begins_with("hub_fish_"), "later casts reel in OTC supplement variants")


func test_09_boiler_face_scorch_hits() -> void:
	make_hub("f_stoke")
	var b := HubLayout.BOILER_POS
	await teleport(Vector3(b.x - HubLayout.BOILER_R - 0.75, 0, b.z), 90.0)
	var s0 := last_seq()
	var t := 0.0
	while t < 25.0 and not state.has_secret("sec_boiler_face"):
		await teleport(Vector3(b.x - HubLayout.BOILER_R - 0.75, 0, b.z), 90.0)
		player().facing_yaw = PI * 0.5
		press("light")
		await run_until(func(): return false, 0.6)
		t += 0.75
	var hits := events_of("hub_boiler", s0)
	check(hits.size() >= 10, "Scorch hits on the boiler are counted (%d)" % hits.size())
	check(_found("sec_boiler_face", s0), "secret #9: the face in the boiler")
	check(state.has_cosmetic("hub_juice_sizzle"), "Sizzle JUICE colour for Stoke")
	check(not events_of("hub_say", s0).filter(func(e): return str(e["npc"]) == "teddy").is_empty(), "Teddy: don't do that again")


func test_09b_non_scorch_hits_do_not_count() -> void:
	make_hub("f_dredge")
	mode.secrets.on_boiler_hit("brine")
	mode.secrets.on_boiler_hit("")
	check_eq(int(state.hub().get("boiler_hits", 0)), 0, "only Scorch counts")


func test_10_ice_bath() -> void:
	make_hub("f_stoke", "med_bay")
	var ok := await walk_to("mb_bath", 20.0)
	check(ok, "walked to the ice bath")
	driver.set_path([Vector3(17.0, 0, -2.6), Vector3(17.0, 0, -1.5)])
	await run_until(func(): return driver.done(), 6.0)
	check(HubLayout.ICE_BATH.has_point(Vector2(player().pos().x, player().pos().z)), "standing in the ice bath (%s)" % str(player().pos()))
	var s0 := last_seq()
	await run_until(func(): return mode.secrets.frost() >= 1.0, 32.0)
	check(mode.secrets.frost() >= 1.0, "30 s in the ice: the screen frosts")
	await run_until(func(): return false, 0.2)
	check_eq(str(mode.focus_of(player()).get("id", "")), "ice_bath", "something at the bottom can be reached")
	var clout0 := state.clout()
	mode.request_interact(player())
	await run_until(func(): return state.has_secret("sec_doc_dumpster"), 1.0)
	check(_found("sec_doc_dumpster", s0), "secret #10: the frozen Blister")
	check(state.has_cosmetic("hub_pet_blister"), "the Blister pet")
	check_eq(state.clout() - clout0, 50, "50 Clout")


func test_ludlow_hints_one_per_visit() -> void:
	make_hub("f_stoke")
	var h := mode.secrets.hint_for(player().pos())
	check(str(h.get("id", "")) != "", "Ludlow hints at an unfound secret")
	check(str(h.get("text", "")) != "", "with words")
	check(state.hint_given(str(h["id"])), "the hint is pinned on the corkboard")
	var h2 := mode.secrets.hint_for(player().pos())
	check_eq(str(h2.get("id", "")), "", "one hint per visit")
	# with everything found he has nothing left
	for id in HubState.SECRETS:
		state.find_secret(str(id))
	var prof := profile
	make_hub("f_stoke", "main_floor", prof)
	var h3 := mode.secrets.hint_for(player().pos())
	check_eq(str(h3.get("id", "")), "", "no hints once everything is found")
	check(str(h3.get("text", "")).contains("everything"), "and he says so")


func test_found_secrets_persist_into_the_world() -> void:
	var prof := {"id": "p", "name": "T", "camp": {"secrets": ["sec_loose_panel", "sec_freight_elevator", "sec_roof_sign", "sec_pier_ladder"], "hub": {"parts": ["fuse", "cable_spool", "button"]}}, "history": []}
	make_hub("f_stoke", "main_floor", prof)
	check(mode.world["panel"] == null, "the panel stays off the wall")
	check(mode.world["gate"].is_empty(), "the elevator stays fixed")
	check(not mode.item_visible("letter_a"), "the A stays in the sign")
	check(mode.condition("pier_revealed"), "the pier stays open")
	check(not mode.item_visible("fuse") and not mode.item_visible("cable_spool"), "delivered parts are gone from the world")


## Hub review #3: the letter A or an elevator part thrown off the roof or the pier (or left where
## nobody can reach it) comes back where it was found, so a missed throw never costs a secret for
## the rest of the visit.
func test_lost_letter_and_parts_come_back() -> void:
	# every item's home is a reachable spot in a space (the rule never sends one somewhere it loops)
	for id in HubLayout.ITEMS:
		var home: Vector3 = (HubLayout.ITEMS[id] as Dictionary)["pos"]
		check(HubLayout.space_at(home + Vector3.UP * 0.5) != "", "%s starts inside a space" % id)
	make_hub("f_stoke", "roof")
	state.find_secret("sec_freight_elevator")
	var letter: RigidBody3D = mode.world["items"]["letter_a"]
	var home_a: Vector3 = (HubLayout.ITEMS["letter_a"] as Dictionary)["pos"]
	# heave it off the roof's south edge, away from the sign
	await teleport(Vector3(48.0, 0, -25.6), 0.0)
	mode.pick_up_item(player(), "letter_a")
	await run_until(func(): return false, 0.2)
	player().facing_yaw = 0.0
	var s0 := last_seq()
	mode.throw_carried(player(), 1.0)
	await run_until(func(): return letter.global_position.y < -1.0, 4.0)
	check(letter.global_position.y < -1.0, "the A sails off the edge of the roof (%s)" % str(letter.global_position))
	await run_until(func(): return letter.global_position.distance_to(home_a) < 0.05, 6.0)
	check(letter.global_position.distance_to(home_a) < 0.05 and letter.freeze, "it comes back by the water tower (%s)" % str(letter.global_position))
	check(not events_of("hub_item_returned", s0).is_empty(), "the hub says so")
	await teleport(Vector3(51.6, 0, -26.9), 180.0)
	_face(letter.global_position)
	check_eq(str(mode._nearest_carryable(player()).get("id", "")), "letter_a", "and it can be picked up again")
	check(not mode.secrets.sign_fixed(), "secret #7 is still on")
	# an elevator part dropped into the harbour from the pier goes back to its spot too
	var fuse: RigidBody3D = mode.world["items"]["fuse"]
	var home_f: Vector3 = (HubLayout.ITEMS["fuse"] as Dictionary)["pos"]
	mode.teleport(player(), Vector3(24.0, 0, -42.0), 0.0)
	await run_until(func(): return false, 0.2)
	mode.pick_up_item(player(), "fuse")
	await run_until(func(): return false, 0.2)
	player().facing_yaw = PI          # south, off the end of the pier
	mode.throw_carried(player(), 1.0)
	await run_until(func(): return fuse.global_position.distance_to(home_f) < 0.05, 8.0)
	check(fuse.global_position.distance_to(home_f) < 0.05, "the fuse is back by the boiler (%s)" % str(fuse.global_position))


## Hub review #9: a hidden item (the red button before the Scouting Report) is not drawn and is
## not solid either — it used to block the walk past the filing cabinets in the Office.
func test_hidden_items_are_not_solid() -> void:
	make_hub("f_stoke", "office")
	var button: RigidBody3D = mode.world["items"]["button"]
	check(not mode.item_visible("button"), "the button is hidden without the Scouting Report")
	check_eq(button.collision_layer, 0, "and has no collision while hidden")
	# walk straight through where it hangs
	await teleport(Vector3(7.0, 4.0, 11.8), 180.0)
	driver.set_path([Vector3(7.0, 4.0, 9.2)])
	await run_until(func(): return player().pos().z < 9.8, 4.0)
	driver.set_path([])
	check(player().pos().z < 9.8, "nothing invisible stops you (reached z %.2f)" % player().pos().z)
	# once revealed it is a real prop again
	mode.show_item("button")
	check(mode.item_visible("button") and button.collision_layer == Rig.LAYER_PROPS, "revealed: visible and solid")
