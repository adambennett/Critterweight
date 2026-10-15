extends HubTestCase
## CMP-04 robustness: two minutes of scripted wandering through the Cannery (random nav goals that
## favour the least-visited spaces; hatches, ladders, the elevator and the pier ladder taken on the
## way) with the fight controls mashed along the way (Light, Heavy, Grab, Taunt, Dodge, Guard,
## throwing whatever gets picked up; a Dodge next to something interacts, so activities start and
## transitions fire mid-walk) — the fighter never falls through the world, never ends up outside
## every space, keeps making progress, takes no damage and is never left knocked down.

const SEED := 20261015
const DURATION := 120.0

var _nav_space := {}           ## nav point -> space id


func _space_of_nav(n: String) -> String:
	if not _nav_space.has(n):
		_nav_space[n] = HubLayout.space_at((HubLayout.NAV[n] as Vector3) + Vector3.UP * 0.5)
	return str(_nav_space[n])


## Picks the next leg: {target, points}. Mostly heads for the least-visited place it can reach (a
## space on foot, or a hatch/ladder/elevator ride), sometimes just strolls inside the current space.
func _plan(rng: RandomNumberGenerator, visits: Dictionary) -> Dictionary:
	var from := HubLayout.nearest_nav(player().pos())
	var here := mode.current_space
	var by_space := {}
	for n in HubLayout.NAV:
		if HubLayout.nav_path(from, str(n)).is_empty():
			continue
		var sp := _space_of_nav(str(n))
		if not by_space.has(sp):
			by_space[sp] = []
		(by_space[sp] as Array).append(str(n))
	var options := []
	for sp2 in by_space:
		if str(sp2) != here:
			options.append({"walk": str(sp2), "visits": int(visits.get(sp2, 0))})
	for tid in HubLayout.TRANSITIONS:
		var tr: Dictionary = HubLayout.TRANSITIONS[tid]
		if tr.has("needs") and not mode.condition(str(tr["needs"])):
			continue
		if by_space.has(_space_of_nav(HubLayout.nearest_nav(tr["from"]))) and not HubLayout.nav_path(from, HubLayout.nearest_nav(tr["from"])).is_empty():
			options.append({"ride": str(tid), "visits": int(visits.get(str(tr["dest"]), 0))})
	if options.is_empty() or (by_space.has(here) and rng.randf() < 0.2):
		var inside: Array = by_space.get(here, by_space.values()[0])
		var stroll := str(inside[rng.randi() % inside.size()])
		return {"target": stroll, "points": HubLayout.nav_path(from, stroll).map(func(n): return HubLayout.NAV[n])}
	var least := 1 << 30
	for o in options:
		least = mini(least, int(o["visits"]))
	var fresh := options.filter(func(o): return int(o["visits"]) == least)
	var pick: Dictionary = fresh[rng.randi() % fresh.size()]
	if pick.has("ride"):
		var tid2 := str(pick["ride"])
		var t2: Dictionary = HubLayout.TRANSITIONS[tid2]
		var pts := HubLayout.nav_path(from, HubLayout.nearest_nav(t2["from"])).map(func(n): return HubLayout.NAV[n])
		pts.append(t2["from"])
		return {"target": "@" + tid2, "points": pts}
	var spots: Array = by_space[pick["walk"]]
	var goal := str(spots[rng.randi() % spots.size()])
	return {"target": goal, "points": HubLayout.nav_path(from, goal).map(func(n): return HubLayout.NAV[n])}


func test_two_minutes_of_wandering_stays_in_the_world() -> void:
	make_hub("f_stoke")
	# open the secret spaces (their own tests cover the triggers)
	state.find_secret("sec_loose_panel")
	state.find_secret("sec_freight_elevator")
	state.find_secret("sec_pier_ladder")
	mode.remove_panel()
	mode.fix_elevator()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	driver.lenient = true
	var actions := ["light", "heavy", "grab", "taunt", "dodge", "light", "grab"]
	var dt := 1.0 / Engine.physics_ticks_per_second
	var t := 0.0
	var min_y := INF
	var low_pos := Vector3.ZERO
	var outside := 0.0
	var worst_outside := 0.0
	var down := 0.0
	var worst_down := 0.0
	var legs := 0
	var reached := 0
	var timeouts := 0
	var rides := 0
	var visits := {}
	var target := ""
	var leg_t := 0.0
	var settle := 0.0
	var prev := player().pos()
	var last_space := mode.current_space
	visits[last_space] = 1
	while t < DURATION:
		if target == "~":
			# a hatch/ladder/elevator (or a stray Dodge next to one) is fading: wait until it lands
			settle = settle + dt if mode.transition.is_empty() else 0.0
			if settle > 0.35:
				target = ""
		elif target == "" or driver.done() or leg_t > 20.0:
			if target != "":
				if driver.done():
					reached += 1
				else:
					timeouts += 1
					print("wander: leg to %s timed out at %s [%s]" % [target, str(player().pos()), mode.current_space])
					print("  state %s idx %d/%d next %s hold %s carry %s act %s ludlow %s focus %s" % [str(player().state), driver.index, driver.points.size(), str(driver.points[mini(driver.index, driver.points.size() - 1)]), str(driver.hold), str(mode.carried_by(player()).get("id", "")), mode.activity_running(), str(mode.ludlow["pos"]), str(mode.focus_of(player()).get("id", ""))])
					var near := []
					for c in mode.world["crates"]:
						if (c as RigidBody3D).global_position.distance_to(player().pos()) < 2.5:
							near.append("crate@%s" % str((c as RigidBody3D).global_position))
					for iid in mode.world["items"]:
						if (mode.world["items"][iid] as RigidBody3D).global_position.distance_to(player().pos()) < 2.5:
							near.append("%s@%s" % [iid, str((mode.world["items"][iid] as RigidBody3D).global_position)])
					print("  near %s vel %s" % [str(near), str(player().rig.root().linear_velocity)])
			if target.begins_with("@") and driver.done():
				# at the hatch/ladder/elevator spot: use it through the prompt (or directly if
				# something closer holds the focus)
				var tid := target.substr(1)
				if str(mode.focus_of(player()).get("id", "")) == tid:
					mode.request_interact(player())
				else:
					mode.begin_transition(player(), tid)
				driver.set_path([])
				target = "~"
				settle = 0.0
			else:
				var leg := _plan(rng, visits)
				driver.set_path(leg["points"])
				target = str(leg["target"])
			legs += 1
			leg_t = 0.0
		# mash the fight controls now and then
		if rng.randf() < 0.012:
			press(str(actions[rng.randi() % actions.size()]))
		if driver.hold.is_empty() and rng.randf() < 0.003:
			driver.hold = ["guard"]
		elif not driver.hold.is_empty() and rng.randf() < 0.015:
			driver.hold = []
		if not mode.carried_by(player()).is_empty() and rng.randf() < 0.01:
			press("heavy" if rng.randf() < 0.5 else "grab")
		sim.step(dt)
		await get_tree().physics_frame
		t += dt
		leg_t += dt
		var p := player().pos()
		if p.distance_to(prev) > 2.0 and target != "~":
			# teleported mid-walk (a Dodge next to a hatch interacts): re-plan once it lands
			driver.set_path([])
			target = "~"
			settle = 0.0
		prev = p
		if p.y < min_y:
			min_y = p.y
			low_pos = p
		var s := HubLayout.space_at(p)
		if s == "":
			outside += dt
			worst_outside = maxf(worst_outside, outside)
		else:
			outside = 0.0
		if mode.current_space != last_space:
			last_space = mode.current_space
			visits[last_space] = int(visits.get(last_space, 0)) + 1
			if last_space in ["boiler_room", "booth", "roof", "pier"]:
				rides += 1
		if player().is_down():
			down += dt
			worst_down = maxf(worst_down, down)
		else:
			down = 0.0
	print("wander: %d legs, %d reached, %d timed out, %d rides, visits %s, min root y %.2f at %s, longest outside %.2f s, longest down %.2f s" % [
		legs, reached, timeouts, rides, str(visits), min_y, str(low_pos), worst_outside, worst_down])
	check(min_y > -0.5, "the fighter never dropped below the floor (min root y %.2f at %s)" % [min_y, str(low_pos)])
	check(worst_outside < 2.0, "never wandered off the map (%.2f s outside every space)" % worst_outside)
	check(worst_down < 3.0, "never left lying down (%.2f s)" % worst_down)
	check(reached >= 8, "kept getting where it was going (%d legs reached)" % reached)
	check(timeouts <= 2, "rarely stuck (%d legs timed out)" % timeouts)
	check(rides >= 2, "took hatches, ladders or the elevator on the way (%d)" % rides)
	check(visits.size() >= 6, "visited most of the Cannery (%d spaces: %s)" % [visits.size(), str(visits.keys())])
	check_near(player().health, player().max_health, 0.01, "no damage taken")
	check(events_of("ringout", 0).is_empty(), "no ring-out ever fired")
