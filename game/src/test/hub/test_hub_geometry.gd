extends HubTestCase
## CMP-03/CMP-04: The Cannery is a connected, walkable place. Layout data is consistent, every
## space is reachable ON FOOT with the real fighter body (doors, the stairs to the Office, the
## hatch/ladders/elevator transitions), walls and fighter-only blockers hold, props fly over the
## dock-edge blocker, and nothing ever sends a fighter below the floor.


func test_layout_data_is_consistent() -> void:
	for a in HubLayout.NAV_LINKS:
		check(HubLayout.NAV.has(a[0]) and HubLayout.NAV.has(a[1]), "nav link %s-%s names exist" % [a[0], a[1]])
	for sid in HubLayout.SPACES:
		var arr := HubLayout.arrive_of(sid)
		var p: Vector3 = arr[0]
		check_eq(HubLayout.space_at(p + Vector3.UP * 0.6), str(sid), "arrival point of %s lies inside it" % sid)
	for d in HubLayout.INTERACTS:
		var ip: Vector3 = d["pos"]
		check(HubLayout.space_at(ip + Vector3.UP * 0.5) != "", "interactable %s sits inside a space" % d["id"])
	for tid in HubLayout.TRANSITIONS:
		var t: Dictionary = HubLayout.TRANSITIONS[tid]
		check_eq(HubLayout.space_at((t["from"] as Vector3) + Vector3.UP * 0.5), str(t["space"]), "%s starts in %s" % [tid, t["space"]])
		check_eq(HubLayout.space_at((t["to"] as Vector3) + Vector3.UP * 0.5), str(t["dest"]), "%s lands in %s" % [tid, t["dest"]])
	for k in HubLayout.NAV:
		var np: Vector3 = HubLayout.NAV[k]
		check(HubLayout.space_at(np + Vector3.UP * 0.5) != "", "nav point %s is inside a space" % k)
	# HUB.md: at least 5 connected spaces (we have 8 public + 3 secret), 8 NPCs, 6 stations
	check(HubLayout.TOUR.size() >= 5, "five or more public spaces")
	check_eq(HubLayout.NPC_SPOTS.size(), 8, "eight NPCs placed")
	var stations := HubLayout.INTERACTS.filter(func(d): return str(d["kind"]) == "station")
	check_eq(stations.size(), 6, "six upgrade stations")
	check_eq(HubContent.secret_ids().size(), 10, "ten secrets in content")
	# the practice cage gate faces west, toward the mats
	var pts := HubLayout.cage_points()
	var g := HubLayout.CAGE_GATE_SIDE
	var mid := (pts[g] + pts[(g + 1) % 8]) * 0.5
	check(mid.x < HubLayout.CAGE_CENTER.x - 2.5, "cage gate is the west side (%.2f)" % mid.x)


func test_every_space_reachable_on_foot() -> void:
	make_hub("f_stoke")
	# open the secret spaces the way the secrets do (their own tests cover the triggers)
	state.find_secret("sec_loose_panel")
	state.find_secret("sec_freight_elevator")
	state.find_secret("sec_pier_ladder")
	mode.remove_panel()
	mode.fix_elevator()
	await run_until(func(): return false, 0.5)
	var plan := [
		["juice_bar", ["jb_center"]], ["main_floor", ["mf_center"]], ["med_bay", ["mb_center"]], ["main_floor", ["mf_center"]],
		["loading_dock", ["dock_center"]], ["main_floor", ["mf_center"]], ["locker_room", ["lr_center"]],
		["booth", ["lr_ladder", "@ladder_up"]], ["locker_room", ["@ladder_down"]], ["main_floor", ["mf_center"]],
		["office", ["of_center"]], ["main_floor", ["mf_stairs_bottom"]], ["boiler_room", ["mf_hatch", "@hatch_down"]],
		["main_floor", ["@hatch_up"]], ["crawlspace", ["cs_end"]], ["main_floor", ["mf_center"]],
		["roof", ["mf_elevator", "@elevator_up"]], ["main_floor", ["@elevator_down"]], ["loading_dock", ["dock_edge"]],
		["pier", ["@pier_down"]], ["loading_dock", ["@pier_up"]],
	]
	var reached := {}
	for step in plan:
		var target := str(step[0])
		for leg in step[1]:
			var l := str(leg)
			if l.begins_with("@"):
				var tid := l.substr(1)
				var t: Dictionary = HubLayout.TRANSITIONS[tid]
				var ok := await walk_to(HubLayout.nearest_nav(t["from"]), 30.0)
				check(ok, "walked to the %s spot" % tid)
				driver.set_path([t["from"]])
				await run_until(func(): return driver.done(), 6.0)
				await run_until(func(): return false, 0.2)
				var f: Dictionary = mode.focus_of(player())
				check_eq(str(f.get("id", "")), tid, "the %s interaction is offered (focus %s)" % [tid, str(f.get("id", "none"))])
				mode.request_interact(player())
				await run_until(func(): return mode.current_space == str(t["dest"]), 3.0)
				await run_until(func(): return false, 0.3)
			else:
				var ok2 := await walk_to(l, 45.0)
				check(ok2, "walked to %s (stuck at %s, %s)" % [l, str(player().pos()), mode.current_space])
		await run_until(func(): return mode.current_space == target, 2.0)
		check_eq(mode.current_space, target, "arrived in %s" % target)
		reached[target] = true
		check(player().pos().y > -0.5, "never below the floor (%s)" % str(player().pos()))
	for sid in HubLayout.SPACES:
		check(reached.has(sid), "%s was reached" % sid)
	check(state.discovered().size() >= HubLayout.SPACES.size(), "every space was discovered")
	check(state.tour_done(), "the first tour is complete")


func test_walls_and_blockers_hold() -> void:
	make_hub("f_dredge")
	# push into the Main Floor's west wall where there is no door (z = 6.6)
	await teleport(Vector3(-10.0, 0, 6.8), 270.0)
	driver.set_path([Vector3(-20.0, 0, 6.8)])
	await run_until(func(): return false, 4.0)
	check(player().pos().x > -12.0, "the west wall stops the fighter (x %.2f)" % player().pos().x)
	# the dock edge: fighters are stopped before the water
	await teleport(Vector3(-4.0, 0, -16.0), 180.0)
	driver.set_path([Vector3(-4.0, 0, -30.0)])
	await run_until(func(): return false, 4.0)
	check(player().pos().z > HubLayout.WATER_EDGE_Z - 0.6, "the dock edge holds (z %.2f)" % player().pos().z)
	check(player().pos().y > 0.0, "still standing on the dock")
	# the closed elevator gate and the loose panel are solid until opened
	await teleport(Vector3(10.5, 0, -4.0), 180.0)
	driver.set_path([Vector3(10.5, 0, -7.4)])
	await run_until(func(): return false, 3.0)
	check(player().pos().z > -5.6, "the chain gate holds (z %.2f)" % player().pos().z)
	await teleport(Vector3(-11.0, 0, 4.9), 270.0)
	driver.set_path([Vector3(-14.5, 0, 4.9)])
	await run_until(func(): return false, 3.0)
	check(player().pos().x > -12.2, "the panel holds until it is pulled (x %.2f)" % player().pos().x)


func test_thrown_crate_flies_over_the_dock_edge() -> void:
	make_hub("f_dredge")
	var crate: RigidBody3D = mode.world["crates"][0]
	await teleport(Vector3(-4.0, 0, -15.5), 180.0)
	crate.global_position = Vector3(-4.0, 1.0, -17.8)
	crate.linear_velocity = Vector3(0, 0.5, -4.0)
	await run_until(func(): return crate.global_position.z < HubLayout.WATER_EDGE_Z - 1.0, 2.0)
	check(crate.global_position.z < HubLayout.WATER_EDGE_Z - 0.8, "crates pass the fighter-only blocker (z %.2f)" % crate.global_position.z)


func test_stairs_reach_the_office_and_back() -> void:
	make_hub("f_jitters")
	var ok := await walk_to("of_center", 40.0)
	check(ok, "a hopper climbs the stairs to the Office")
	check_eq(mode.current_space, "office", "in the Office")
	check(player().pos().y > 4.0, "standing on the mezzanine (y %.2f)" % player().pos().y)
	var ok2 := await walk_to("mf_center", 40.0)
	check(ok2, "and walks back down")
	check_eq(mode.current_space, "main_floor", "back on the Main Floor")
