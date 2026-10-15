extends HubTestCase
## CMP-03/CMP-04 hub activities score and pay Clout: the Heavy Bag Score Challenge (combat damage
## formula, Heavy x1.5, Finisher x2, combo, Body bag zones, tiers once per fighter), the Chum Cannon
## Dodge Drill (dodge / parry / guard / hit, streak tiers), the Crate Toss (rings, foul line, tiers,
## the Jitters 100 hint) and Ring Sparring's match config (Kid Lamprey, tiers, no stakes).


func test_bag_points_formula() -> void:
	make_hub("f_stoke")
	var b := mode.bags
	var base := {"q": 1.0, "clean": 1.0, "damage": 10.0, "charge": 0.0, "charge_damage": 0.4, "class": "light", "slot": "l1"}
	var light := b.points_for("heavy", base, 1.0)
	var heavy_info := base.duplicate()
	heavy_info["class"] = "heavy"
	heavy_info["slot"] = "heavy"
	check_near(b.points_for("heavy", heavy_info, 1.0), light * 1.5, 0.01, "a Heavy scores x1.5")
	var fin := base.duplicate()
	fin["slot"] = "finisher"
	fin["class"] = "heavy"
	check_near(b.points_for("heavy", fin, 1.0), light * 2.0, 0.01, "a Finisher scores x2")
	var weak := base.duplicate()
	weak["q"] = 0.0
	weak["clean"] = 0.4
	check(b.points_for("heavy", weak, 1.0) < light * 0.6, "slow, glancing contact scores much less (same formula as combat)")
	var charged := heavy_info.duplicate()
	charged["charge"] = 1.0
	check(b.points_for("heavy", charged, 1.0) > b.points_for("heavy", heavy_info, 1.0) * 1.3, "charge adds its damage bonus")
	# the Body bag only counts head and shell hits
	check_eq(b.points_for("body", base, 0.3), 0.0, "legs of the Body bag don't count")
	check(b.points_for("body", base, 0.9) > 0.0, "the shell counts")
	check(b.points_for("body", base, 1.5) > b.points_for("body", base, 0.9), "the head counts more")
	# the Light bag rewards any hit (flat bonus)
	check(b.points_for("light", weak, 1.0) > b.points_for("heavy", weak, 1.0), "the Light bag pays for speed, not power")


func test_bag_challenge_scores_real_hits_and_pays_clout() -> void:
	make_hub("dev_biped")
	var bag: RigidBody3D = mode.bag_body("heavy")
	await teleport(Vector3(-9.15, 0, 1.0), 270.0)
	mode.start_activity("bag", "heavy")
	await run_until(func(): return mode.bags.phase == "running", 4.0)
	check_eq(mode.bags.phase, "running", "the countdown ends and the challenge runs")
	var s0 := last_seq()
	# jab, jab, heavy... for the whole 30 s, always facing the bag
	var t := 0.0
	var i := 0
	while mode.bags.running() and t < 34.0:
		var to := bag.global_position - player().pos()
		to.y = 0.0
		player().facing_yaw = atan2(to.x, to.z)
		if to.length() > 1.05:
			driver.set_path([Vector3(bag.global_position.x + 0.9, 0, bag.global_position.z)])
		else:
			driver.set_path([])
		press(["light", "light", "heavy", "light"][i % 4])
		i += 1
		await run_until(func(): return false, 0.35)
		t += 0.35
	var ends := events_of("hub_activity", s0).filter(func(e): return str(e["phase"]) == "end")
	check(not ends.is_empty(), "the challenge ended after 30 s")
	var hits := events_of("hub_score", s0).filter(func(e): return int(e.get("points", 0)) > 0)
	check(hits.size() >= 10, "real weapon hits on the bag scored (%d)" % hits.size())
	if not ends.is_empty():
		var r: Dictionary = ends[0]["result"]
		check(int(r["score"]) > 0, "a score (%d)" % int(r["score"]))
		var tier := int(r["tier"])
		var expected: int = [0, 10, 35, 85][tier]
		check_eq(state.clout(), expected, "tier %d paid its Clout once" % tier)
		# the same tier does not pay twice
		mode.bags.start("heavy")
		mode.bags.score = float(r["score"])
		mode.bags.phase = "running"
		mode.bags.finish()
		check_eq(state.clout(), expected, "no second payment for the same tier")
		print("bag challenge (dev_biped jab-jab-heavy): score %d, hits %d, best combo %d, tier %d" % [int(r["score"]), int(r["hits"]), int(r["best_combo"]), tier])


func test_bag_tiers_are_per_fighter() -> void:
	make_hub("f_stoke")
	mode.bags.start("light")
	mode.bags.phase = "running"
	mode.bags.score = 650.0
	mode.bags.finish()
	check_eq(state.clout(), 35, "Stoke: tiers 1 and 2 on the Light bag pay 10 + 25")
	var prof := profile
	make_hub("f_gusto", "main_floor", prof)
	mode.bags.start("light")
	mode.bags.phase = "running"
	mode.bags.score = 320.0
	mode.bags.finish()
	check_eq(state.clout(), 45, "Gusto earns its own tier 1 on the same bag")


func test_chum_drill_counts_dodges_guards_and_hits() -> void:
	make_hub("f_dredge")
	mode.start_activity("drill")
	check(HubLayout.DRILL_SQUARE.has_point(Vector2(player().pos().x, player().pos().z)), "the drill puts you in the square")
	await run_until(func(): return mode.drill.phase == "running", 4.0)
	var s0 := last_seq()
	# stand still: buckets land on you
	await run_until(func(): return mode.drill.hits_taken >= 2 or not mode.drill.running(), 12.0)
	check(mode.drill.hits_taken >= 2, "standing still gets you splattered (%d hits)" % mode.drill.hits_taken)
	check(mode.drill.drill_hp < int(HubContent.activity("drill").get("drill_hp", 30)), "drill HP drops, real health does not")
	check_near(player().health, player().max_health, 0.01, "no real damage")
	# now guard facing the cannon: buckets are blocked and the streak grows
	var streak0 := mode.drill.streak
	driver.hold = ["guard"]
	var t := 0.0
	while mode.drill.running() and t < 10.0:
		var to := HubLayout.CANNON_POS - player().pos()
		player().facing_yaw = atan2(to.x, to.z)
		await run_until(func(): return false, 0.2)
		t += 0.2
	driver.hold = []
	var blocks := events_of("hub_bucket", s0).filter(func(e): return str(e["phase"]) == "block")
	check(not blocks.is_empty(), "guarding blocks buckets (%d)" % blocks.size())
	check(mode.drill.best_streak > streak0, "the streak grows while you guard")
	# leaving the square ends the drill and pays tiers for the best streak
	mode.drill.best_streak = 32
	mode.drill.finish("test")
	check_eq(state.clout(), 35, "streak 32 pays tiers 15 and 30 (10 + 25)")


func test_chum_drill_parry_and_dodge() -> void:
	make_hub("dev_biped")
	var d := mode.drill
	d.start()
	d.phase = "running"
	var f := player()
	# a bucket arriving while the fighter is in its parry window is popped for +5
	var bucket := {"id": 99, "pos": f.pos() + f.forward() * 0.6 + Vector3.UP * 0.3, "vel": -f.forward() * 6.0, "age": 0.2, "flight": 1.0, "resolved": false}
	d.buckets.append(bucket)
	f.input.set_held(FighterInput.GUARD, true)
	f._set_state(Fighter.State.GUARD)
	f.motor.guard_blend = 1.0
	f.guard_pressed_at = f.time
	var c := sim.combat.find_contact(bucket["pos"], HubChumDrill.BUCKET_R, f)
	if c.is_empty():
		c = {"point": f.pos(), "seg": 0}
	d._resolve(bucket, f, c)
	check_eq(str(bucket.get("how", "")), "parried", "a well-timed guard pops the bucket")
	check_eq(d.streak, 5, "a parry is worth +5")
	# evading (dodge i-frames) lets a bucket through; it counts when it lands
	var b2 := {"id": 100, "pos": f.pos() + Vector3.UP * 3.0, "vel": Vector3(0, -2.0, 0), "age": 0.2, "flight": 1.0, "resolved": false}
	f.evade_until = f.time + 1.0
	d._resolve(b2, f, {"point": f.pos(), "seg": 0})
	check_eq(str(b2.get("how", "")), "evaded", "dodge i-frames let the bucket pass")


func test_crate_toss_scores_rings_and_pays_tiers() -> void:
	make_hub("f_stoke")
	mode.start_activity("crates")
	check(mode.crates.running(), "the Crate Toss started")
	var line := Vector3(HubLayout.CRATE_LANE_X, 0.0, HubLayout.CRATE_LINE_Z + 0.4)
	var s0 := last_seq()
	for i in 10:
		var crate: RigidBody3D = mode.world["crates"][i]
		await teleport(Vector3(crate.global_position.x + 0.0, 0, crate.global_position.z + 0.85), 180.0)
		var to := crate.global_position - player().pos()
		player().facing_yaw = atan2(to.x, to.z)
		press("grab")
		await run_until(func(): return not mode.carried_by(player()).is_empty(), 1.0)
		await teleport(line, 180.0)
		# aim at the 5 m ring: pick the charge that lands 5 m ahead
		var want := 5.0 - 0.95 if i < 7 else 8.0 - 0.95
		var lo := mode.throw_distance(player(), 0.0, HubWorld.CRATE_MASS)
		var hi := mode.throw_distance(player(), 1.0, HubWorld.CRATE_MASS)
		var ch := clampf((want - lo) / (hi - lo), 0.0, 1.0)
		player().facing_yaw = PI
		mode.throw_carried(player(), ch)
		await run_until(func(): return mode.flying.is_empty(), 3.0)
	await run_until(func(): return not mode.crates.running(), 3.0)
	var ends := events_of("hub_activity", s0).filter(func(e): return str(e["phase"]) == "end" and str(e["activity"]) == "crates")
	check(not ends.is_empty(), "the toss ends after ten crates")
	if not ends.is_empty():
		var r: Dictionary = ends[0]["result"]
		var throws: Array = r["throws"]
		check_eq(throws.size(), 10, "ten throws recorded")
		var ringed := throws.filter(func(x): return int(x["ring"]) >= 1).size()
		check(ringed >= 6, "aimed throws land in the 5 m / 8 m rings (%d of 10)" % ringed)
		check(int(r["points"]) >= 60, "a good toss scores 60+ (%d)" % int(r["points"]))
		check(state.clout() >= 35, "tiers pay Clout (%d)" % state.clout())
		print("crate toss (Stoke, aimed): %d points, rings %s" % [int(r["points"]), str(throws.map(func(x): return int(x["ring"])))])


func test_crate_toss_foul_and_jitters_hint() -> void:
	make_hub("f_jitters")
	var ct := mode.crates
	ct.start()
	ct.on_throw(0, Vector3(HubLayout.CRATE_LANE_X, 0.8, HubLayout.CRATE_LINE_Z - 2.0))
	ct.on_land(0, Vector3(HubLayout.CRATE_LANE_X, 0.3, HubLayout.CRATE_LINE_Z - 5.0), false)
	check_eq(ct.points, 0, "a throw from past the line is a foul")
	ct.cancel()
	ct.start()
	for i in 10:
		ct.on_throw(i, Vector3(HubLayout.CRATE_LANE_X, 0.8, HubLayout.CRATE_LINE_Z + 0.2))
		ct.on_land(i, Vector3(HubLayout.CRATE_LANE_X, 0.3, HubLayout.CRATE_LINE_Z - 5.0), false)
	ct.tick(0.1)
	check_eq(ct.points, 100, "ten crates in the 5 m ring = 100")
	check(bool(state.flag("pier_hint")), "100 with Jitters earns Ludlow's pier hint")
	check_eq(state.clout(), 85, "and all three tiers (10 + 25 + 50)")


func test_ring_sparring_config() -> void:
	make_hub("f_stoke")
	var cfg := HubSparring.config("f_stoke", "Tester", {"opponent": "kid_lamprey", "tier": "contender", "format": "spar", "low_gravity": true, "hazards": true})
	check(bool(cfg["no_record"]), "sparring has no stakes (not recorded)")
	var fighters: Array = cfg["fighters"]
	check_eq(fighters.size(), 2, "you and your sparring partner")
	check_eq(str(fighters[1]["name"]), "Kid Lamprey", "the partner is Kid Lamprey")
	var kid := str(fighters[1]["creature"])
	check(Content.creature(kid) != null, "Kid Lamprey's body exists (%s)" % kid)
	check_eq(str(fighters[1]["difficulty"]), BotTiers.brain_tier("contender"), "the chosen bot tier")
	check_near(float((cfg["rules"] as Dictionary)["gravity_mult"]), 0.5, 0.001, "low gravity modifier")
	var arena: ArenaDef = cfg["arena"]
	check(arena.hazards.size() >= 2, "hazards modifier adds hazards to the cage")
	check(arena.radius < 5.0, "the practice cage is a small mini-Gullet (radius %.1f)" % arena.radius)
	var prac := HubSparring.config("f_stoke", "Tester", {"opponent": "f_dredge", "tier": "headliner", "format": "practice"})
	check_eq(str((prac["rules"] as Dictionary)["mode"]), "practice", "practice format uses PracticeMode (telemetry, no KO)")
	# rewards on return: first Contender win vs Kid pays 25 once; a Headliner win earns a badge
	var r1 := state.spar_record("kid_lamprey", "contender", true, "f_stoke")
	check_eq(int(r1["clout"]), 25, "first win over Kid at Contender: 25 Clout")
	var r2 := state.spar_record("kid_lamprey", "contender", true, "f_stoke")
	check_eq(int(r2["clout"]), 0, "only once")
	var r3 := state.spar_record("f_dredge", "headliner", true, "f_stoke")
	check_eq(str(r3["badge"]), "f_stoke", "beating a Headliner earns Stoke's badge")
	check(state.has_cosmetic("hub_badge_headliner_f_stoke"), "the badge is saved as a cosmetic")
