extends TestCase
## LAB-08 (honest evaluation statistics), review finding 2: small-sample intervals use Student-t
## quantiles (no zero-width interval from one episode), conditions played on the same episodes
## are compared with a paired test, and evaluation episodes never repeat — standard spawns are
## jittered per seed, "swapped" really swaps, random spawns honour the requested distance — so
## a deterministic policy against a static dummy does not replay one episode n times.


func test_student_t_intervals_for_small_samples() -> void:
	check_near(LabStats.t975(1), 12.7062, 1e-4, "t(0.975, 1)")
	check_near(LabStats.t975(5), 2.5706, 1e-4, "t(0.975, 5)")
	check_near(LabStats.t975(30), 2.0423, 1e-4, "t(0.975, 30)")
	check_near(LabStats.t975(31), 2.0395, 2e-4, "t(0.975, 31) from the expansion")
	check_near(LabStats.t975(60), 2.0003, 2e-4, "t(0.975, 60)")
	check_near(LabStats.t975(120), 1.9799, 2e-4, "t(0.975, 120)")
	check_near(LabStats.t975(100000), 1.96, 1e-3, "large df -> normal quantile")
	var one := LabStats.describe([5.0])
	check_eq(int(one["n"]), 1)
	check((one["ci95"] as Array).is_empty(), "one episode has no interval (not a zero-width one): %s" % str(one["ci95"]))
	check(LabEval.one_line({"n": 1, "reward": one}).contains("CI n/a"), "the report says so")
	var three := LabStats.describe([1.0, 2.0, 3.0])
	var sem := 1.0 / sqrt(3.0)
	var ci: Array = three["ci95"]
	check_near(float(ci[0]), 2.0 - 4.3027 * sem, 1e-3, "n=3 interval uses t(2), not 1.96 (lower)")
	check_near(float(ci[1]), 2.0 + 4.3027 * sem, 1e-3, "n=3 interval uses t(2) (upper)")
	var big := []
	for k in 200:
		big.append(float(k % 7))
	var bd := LabStats.describe(big)
	var bci: Array = bd["ci95"]
	check_near((float(bci[1]) - float(bci[0])) / 2.0 / float(bd["sem"]), LabStats.t975(199), 1e-6, "large n half-width = t * sem")


func test_paired_test_uses_episode_pairs() -> void:
	# a consistent +1 improvement on episodes whose difficulty varies a lot: Welch (unpaired)
	# cannot see it, the paired test can
	var init := []
	var trained := []
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for k in 12:
		var difficulty := r.randf_range(0.0, 40.0)
		init.append(difficulty)
		trained.append(difficulty + 1.0 + r.randf_range(-0.2, 0.2))
	var p := LabStats.paired(trained, init)
	check_eq(int(p["n"]), 12, "n counts episode pairs")
	check_eq(int(p["df"]), 11)
	check_near(float(p["mean"]), 1.0, 0.15, "mean difference")
	check(bool(p["significant"]), "a consistent paired improvement is significant (CI %s)" % LabStats.ci_text(p["ci95"]))
	check(absf(LabStats.welch_t(trained, init)) < 1.0, "the unpaired test cannot see it (Welch t %.2f)" % LabStats.welch_t(trained, init))
	var noise := LabStats.paired([1.0, 3.0, 2.0, 5.0], [2.0, 2.0, 3.0, 4.0])
	check(not bool(noise["significant"]), "differences of both signs are not significant")
	var single := LabStats.paired([3.0], [1.0])
	check(not bool(single["significant"]) and (single["ci95"] as Array).is_empty(), "one pair proves nothing")
	# pairing by episode identity, ignoring failed episodes
	var res := []
	for k in 4:
		res.append({"group": "a", "opponent": "idle", "seed": k, "spawn": "random", "raw": {"hits": float(k + 1)}})
		res.append({"group": "b", "opponent": "idle", "seed": k, "spawn": "random", "raw": {"hits": float(k)}})
	res.append({"group": "a", "opponent": "idle", "seed": 9, "spawn": "random", "raw": {"hits": 50.0}})
	res.append({"group": "b", "opponent": "idle", "seed": 9, "error": "missing"})
	var cmp := LabEval.compare(res, {"hits": 1.0}, "a", "b")
	check_eq(int(cmp["n"]), 4, "only episodes both groups completed are paired")
	check_near(float(cmp["mean"]), 1.0, 1e-9, "paired by episode")


func test_spawns_follow_the_seed_and_the_layout() -> void:
	var scn := {"arena": "the_gullet", "round_time": 6.0, "dist": [2.0, 4.5]}
	var seen := {}
	var opp_spots := {}
	for s in [101, 102, 103, 104]:
		var std := LabScenarios.arena_for(LabScenarios.episode(scn, "idle", s, "dev_biped", "dev_biped", "standard"))
		var swp := LabScenarios.arena_for(LabScenarios.episode(scn, "idle", s, "dev_biped", "dev_biped", "swapped"))
		var rnd := LabScenarios.arena_for(LabScenarios.episode(scn, "idle", s, "dev_biped", "dev_biped", "random"))
		for a: ArenaDef in [std, swp, rnd]:
			check_eq(a.spawns.size(), 2, "exactly two spawns (the format-2 spawn ring is replaced)")
		var a0: Vector3 = std.spawn_point(0, 2)[0]
		var a1: Vector3 = std.spawn_point(1, 2)[0]
		var b0: Vector3 = swp.spawn_point(0, 2)[0]
		var b1: Vector3 = swp.spawn_point(1, 2)[0]
		check(a0.z < 0.0 and a1.z > 0.0, "standard: learner on one side, opponent on the other (%s / %s)" % [str(a0), str(a1)])
		check(b0.z > 0.0 and b1.z < 0.0, "swapped: the sides are exchanged (%s / %s)" % [str(b0), str(b1)])
		var key := "%.3f,%.3f" % [a0.x, a0.z]
		check(not seen.has(key), "standard spawn jittered by the seed (seed %d repeats %s)" % [s, key])
		seen[key] = true
		check(a0.distance_to(Vector3(0, 0, -3)) <= LabScenarios.JITTER_M + 1e-3, "jitter stays near the standard point")
		var r0: Vector3 = rnd.spawn_point(0, 2)[0]
		var r1: Vector3 = rnd.spawn_point(1, 2)[0]
		var d := r0.distance_to(r1)
		check(d >= 1.0 and d <= 4.5 + 1e-3, "random: the opponent is placed `dist` away from the learner (%.2f m)" % d)
		opp_spots["%.3f,%.3f" % [r1.x, r1.z]] = true
	check_eq(opp_spots.size(), 4, "random: the opponent's position follows the seed (it used to be one fixed ring point)")


## A deterministic (argmax) policy against a standing dummy, evaluated with standard spawns: the
## episodes differ (they used to be exact repeats that were counted as independent samples).
func test_standard_spawn_episodes_are_not_repeats() -> void:
	var p := PolicyLibrary.get_policy("dev_biped_es_drill")
	check(p != null, "drill sample available")
	if p == null:
		return
	var job := {"seed": 7, "creature": "dev_biped", "opponent_creature": "dev_biped", "scenario": {"arena": "the_gullet", "round_time": 3.0, "dist": [2.0, 4.5]}}
	var conds := LabEval.conditions(job, "test", ["idle"], 3, true)
	var std_only := []
	for c: Dictionary in conds:
		if str(c["spawn"]) != "random":
			std_only.append(c)
	check_eq(std_only.size(), 3, "three standard-layout episodes")
	var runner := LabRunner.new()
	runner.max_worlds = 3
	add_child(runner)
	runner.resolver = func(_it: Dictionary) -> PolicyData: return p
	runner.add_items(LabEval.items_for(std_only, "theta", "target", 0))
	var dt := 1.0 / Engine.physics_ticks_per_second
	# step in phase with physics (D-026), as TestCase.step_sim does
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	var guard := 0
	while runner.busy() and guard < 3000:
		runner.step(dt)
		await get_tree().physics_frame
		guard += 1
	var outcomes := {}
	for r: Dictionary in runner.take_results():
		check(not r.has("error"), "episode ran: %s" % str(r.get("error", "")))
		outcomes["%s|%.4f" % [JSON.stringify(r.get("raw", {})), float(r.get("health_left", 0.0))]] = true
	runner.queue_free()
	check_eq(outcomes.size(), 3, "three different episodes, not one episode three times")
