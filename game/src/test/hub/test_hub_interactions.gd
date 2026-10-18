extends HubTestCase
## CMP-03/CMP-04 hub interactions: every interactable in the Cannery offers its prompt and fires
## its event, the A press (Dodge) near an interactable becomes an interaction instead of a dodge
## (MatchMode.intercept_actions) while A in open space still dodges, Grab picks things up and
## throws them (Heavy hold = heave), and the hub never deals damage or knocks anyone down.


## Stands the fighter on an interactable's spot and returns the focused entry.
func _stand_at(id: String) -> Dictionary:
	var d := HubLayout.interact_def(id)
	var p: Vector3 = d.get("pos", Vector3.ZERO)
	if d.is_empty():
		var t: Dictionary = HubLayout.TRANSITIONS.get(id, {})
		p = t.get("from", Vector3.ZERO)
	await teleport(p, 0.0)
	await run_until(func(): return false, 0.25)
	return mode.focus_of(player())


func test_every_interactable_fires() -> void:
	make_hub("f_stoke")
	# open everything that is gated so each interaction can be offered
	state.find_secret("sec_loose_panel")
	state.find_secret("sec_freight_elevator")
	state.find_secret("sec_pier_ladder")
	state.camp()["upgrades"]["meta_scouting_report"] = 1
	mode.remove_panel()
	mode.fix_elevator()
	var expect_kind := {"npc": "hub_interact", "station": "hub_interact", "service": "hub_interact", "object": "hub_interact"}
	var skip := ["elevator_gate", "booth_chair", "ice_bath", "crawl_jar", "filing_cabinet_2", "fishing_rod", "roof_trunk", "belt_case"]
	for d in HubLayout.INTERACTS:
		var id := str(d["id"])
		if id in skip or str(d["kind"]) == "activity":
			continue
		var f := await _stand_at(id)
		check_eq(str(f.get("id", "")), id, "%s is the focused interactable" % id)
		check(str(f.get("prompt", "")) != "", "%s has a prompt" % id)
		var s0 := last_seq()
		mode.request_interact(player())
		await run_until(func(): return false, 0.15)
		var evs := events_of(str(expect_kind.get(str(d["kind"]), "hub_interact")), s0)
		check(not evs.is_empty(), "%s fires an interaction event" % id)
		if not evs.is_empty():
			var ev: Dictionary = evs[0]
			match str(d["kind"]):
				"npc":
					check_eq(str(ev.get("npc", "")), str(d["npc"]), "%s talks to the right NPC" % id)
				"station":
					check_eq(str(ev.get("station", "")), str(d["station"]), "%s opens its station" % id)
				"service":
					check_eq(str(ev.get("service", "")), str(d["service"]), "%s opens its service" % id)
	# activities start their activity
	for act in [["bag_heavy", "bag"], ["crate_pile", "crates"], ["chum_cannon", "drill"]]:
		await _stand_at(str(act[0]))
		var start_seq := last_seq()
		mode.request_interact(player())
		if act[1] == "drill":
			await run_until(func(): return not events_of("hub_interact", start_seq).is_empty(), 0.5)
			var choices := events_of("hub_interact", start_seq)
			check(not choices.is_empty() and choices[0].get("kind") == "drill", "cannon opens its difficulty choice before firing")
			check_eq(mode.activity_running(), "", "cannon waits for a difficulty selection")
			mode.start_activity("drill", "", "standard")
		await run_until(func(): return mode.activity_running() != "", 0.5)
		check_eq(mode.activity_running(), str(act[1]), "%s starts the %s activity" % [act[0], act[1]])
		mode.cancel_activity()
		await run_until(func(): return false, 0.1)


func test_a_press_interacts_instead_of_dodging() -> void:
	make_hub("f_stoke")
	var f := await _stand_at("npc_granny")
	check_eq(str(f.get("id", "")), "npc_granny", "standing by Granny")
	var s0 := last_seq()
	var dodged := [false]
	press("dodge")
	for i in 30:
		await run_until(func(): return false, 1.0 / 120.0)
		if player().state == Fighter.State.DODGE:
			dodged[0] = true
	check(not bool(dodged[0]), "the A (Dodge) press next to Granny did not dodge")
	var evs := events_of("hub_interact", s0)
	check(not evs.is_empty() and str(evs[0].get("npc", "")) == "granny", "it opened the conversation instead")
	check(events_of("dodge", s0).is_empty(), "no dodge event")
	# in the open, A still dodges
	await teleport(Vector3(-4.0, 0, 0.0), 0.0)
	await run_until(func(): return false, 0.5)
	check(mode.focus_of(player()).is_empty(), "nothing to interact with on the mats")
	var s1 := last_seq()
	press("dodge")
	await run_until(func(): return player().state == Fighter.State.DODGE, 0.5)
	check(not events_of("dodge", s1).is_empty(), "A dodges when there is nothing to interact with")


func test_grab_carry_and_heave_a_crate() -> void:
	make_hub("f_dredge")
	var crate: RigidBody3D = mode.world["crates"][0]
	await teleport(crate.global_position + Vector3(0.0, 0.0, -0.9) * 1.0 - Vector3(0, crate.global_position.y, 0), 0.0)
	# face the crate
	var to := crate.global_position - player().pos()
	player().facing_yaw = atan2(to.x, to.z)
	press("grab")
	await run_until(func(): return not mode.carried_by(player()).is_empty(), 1.0)
	check(not mode.carried_by(player()).is_empty(), "Grab picked the crate up")
	check(crate.global_position.y > player().pos().y + 0.3, "the crate is carried overhead")
	# walk to the throw line, face north, hold Heavy for a full heave
	driver.set_path([Vector3(HubLayout.CRATE_LANE_X, 0, HubLayout.CRATE_LINE_Z + 0.3)])
	await run_until(func(): return driver.done(), 6.0)
	player().facing_yaw = PI
	var s0 := last_seq()
	press("heavy")
	driver.hold = ["heavy"]
	await run_until(func(): return false, 1.0)
	driver.hold = []
	await run_until(func(): return not events_of("hub_land", s0).is_empty() or not events_of("hub_splash", s0).is_empty(), 4.0)
	var throws := events_of("hub_throw", s0)
	check(not throws.is_empty(), "the heave threw the crate")
	if not throws.is_empty():
		check(float(throws[0]["charge"]) > 0.8, "a held Heavy charges the throw (%.2f)" % float(throws[0]["charge"]))
		check(float(throws[0]["dist"]) > 9.0, "Dredge heaves a crate far (%.1f m)" % float(throws[0]["dist"]))
	var landed := events_of("hub_land", s0) + events_of("hub_splash", s0)
	check(not landed.is_empty(), "the crate came down somewhere")
	if not landed.is_empty():
		check(float(landed[0]["dist"]) > 7.0, "it flew more than 7 m (%.1f)" % float(landed[0]["dist"]))
	check(mode.carried_by(player()).is_empty(), "hands are free again")


## The rule (HubMode.throw_strength): a fighter's crate range follows their BEST throw in the kit
## relative to the roster average, times a body factor — checked for every roster fighter with the
## kit numbers actually installed, then the design consequences on the dock's 3 / 5 / 8 m rings.
func test_throw_distance_follows_the_fighter() -> void:
	var ref := HubMode.roster_best_throw()
	var full := {}
	var tap := {}
	var cfg := HubContent.activity("crates")
	var ring8_near := 8.0 - float((HubLayout.CRATE_RINGS[2] as Dictionary)["r"])
	for fid in ["f_stoke", "f_jitters", "f_dredge", "f_dozer", "f_gusto", "f_slurry"]:
		make_hub(fid)
		var c := player().creature
		var expect := clampf(HubMode.best_throw(c) / ref * HubMode.body_factor(player().rig.total_mass), 0.6, 1.5)
		check_near(HubMode.throw_strength(player()), expect, 0.0001, "%s: best throw %.1f m / roster %.2f m x body %.2f" % [fid, HubMode.best_throw(c), ref, HubMode.body_factor(player().rig.total_mass)])
		full[fid] = mode.throw_distance(player(), 1.0, HubWorld.CRATE_MASS)
		tap[fid] = mode.throw_distance(player(), 0.0, HubWorld.CRATE_MASS)
		check_near(float(full[fid]), float(cfg.get("full_distance", 8.9)) * expect, 0.001, "%s: a full heave lands %.1f m out" % [fid, float(full[fid])])
	print("crate heave (m): ", full)
	check(full["f_dredge"] > full["f_stoke"] and full["f_dozer"] > full["f_stoke"], "the heavy grapplers out-throw Stoke (%s)" % str(full))
	check(full["f_stoke"] > full["f_jitters"], "Stoke out-throws Jitters (%.1f / %.1f)" % [full["f_stoke"], full["f_jitters"]])
	check(full["f_jitters"] < ring8_near, "Jitters cannot reach the 8 m ring at full heave (%.1f)" % full["f_jitters"])
	check(full["f_jitters"] >= 5.0, "but Jitters can still land the 5 m ring (%.1f)" % full["f_jitters"])
	check(full["f_stoke"] >= ring8_near, "Stoke's full heave reaches the 8 m ring (%.1f)" % full["f_stoke"])
	check(tap["f_stoke"] < 4.0, "a quick toss is short (%.1f)" % tap["f_stoke"])


func test_hits_on_npcs_are_shrugged_off_and_nobody_goes_down() -> void:
	make_hub("f_stoke")
	await teleport(Vector3(-8.6, 0, -4.7), 0.0)
	var granny: Vector3 = HubLayout.NPC_SPOTS["granny"]["pos"]
	var to := granny - player().pos()
	player().facing_yaw = atan2(to.x, to.z)
	var s0 := last_seq()
	for i in 6:
		press("light" if i % 2 == 0 else "heavy")
		var to2 := granny - player().pos()
		player().facing_yaw = atan2(to2.x, to2.z)
		driver.set_path([granny])
		await run_until(func(): return false, 0.7)
	driver.set_path([])
	check(not events_of("hub_npc_hit", s0).is_empty(), "punching Granny is noticed (she shrugs it off)")
	check(events_of("hit", s0).filter(func(e): return int(e.get("target", -1)) >= 0).is_empty(), "no damage event against any fighter")
	check_near(player().health, player().max_health, 0.01, "the player is at full health")
	# even a forced knockdown is undone at once (HUB.md §6: nobody goes down in the hub)
	player().knock_down("test", null)
	await run_until(func(): return not player().is_down() or player().state == Fighter.State.GETUP, 1.0)
	await run_until(func(): return player().state == Fighter.State.NEUTRAL, 2.0)
	check_eq(player().state_name(), "neutral", "back on their feet")


func test_transitions_and_fast_walk() -> void:
	make_hub("f_stoke")
	var f := await _stand_at("hatch_down")
	check_eq(str(f.get("id", "")), "hatch_down", "the hatch is offered under the stairs")
	mode.request_interact(player())
	await run_until(func(): return mode.current_space == "boiler_room", 2.0)
	check_eq(mode.current_space, "boiler_room", "the hatch leads to the Boiler Room")
	# Fast walk is locked until the first tour is done
	check(not mode.fast_walk(player(), "main_floor"), "no Fast walk before the first tour")
	for s in HubLayout.TOUR:
		state.discover(str(s))
	check(state.tour_done(), "tour complete")
	check(mode.fast_walk(player(), "juice_bar"), "Fast walk accepted")
	await run_until(func(): return mode.current_space == "juice_bar", 2.0)
	check_eq(mode.current_space, "juice_bar", "Fast walk arrives in the Juice Bar")
	check(not mode.fast_walk(player(), "roof"), "undiscovered/secret spaces are not on the list")
	# locked elevator and pier
	var e := await _stand_at("elevator_up")
	check(str(e.get("id", "")) != "elevator_up", "the broken elevator offers no ride")
	var g := await _stand_at("elevator_gate")
	check_eq(str(g.get("id", "")), "elevator_gate", "the chain gate explains itself instead")
