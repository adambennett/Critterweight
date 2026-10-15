extends TestCase
## MCH-04: the four bonus modes run end-to-end with bots and behave per docs/design/MODES.md.
## Run fast with: godot --headless --path game --fixed-fps 120 -- --test test_modes


func _bots(n: int, ffa := true, team_split := 2) -> Array:
	var out := []
	for i in n:
		var b := BotBrain.new("regular", 1000 + i)
		out.append({"creature": "dev_biped", "team": i if ffa else i % team_split, "source": b, "kind": "bot", "name": "Bot%d" % i})
	return out


func _mode_sim(mode_id: String, rules: Dictionary, fighters: Array, seed_value := 5) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var entries := []
	for f in fighters:
		var e: Dictionary = f.duplicate()
		e["creature"] = Content.creature(str(e["creature"]))
		entries.append(e)
	var r := rules.duplicate()
	r["mode"] = mode_id
	sim.setup({"arena": Content.arena("the_gullet"), "rules": r, "seed": seed_value, "fighters": entries, "mode": ModeRegistry.create(mode_id)})
	return sim


func _events(sim: MatchSim, type: String) -> Array:
	return sim.events.filter(func(e): return e["type"] == type)


func test_spotlight_hog_scores_and_swings() -> void:
	var sim := _mode_sim("spotlight_hog", {"score_target": 12, "dwell": 6.0, "round_time": 90.0}, _bots(4))
	var seen_swing := false
	var t := 0.0
	while t < 90.0 and not sim.is_finished:
		await step_sim(sim, 1.0)
		t += 1.0
		if not _events(sim, "spotlight_swing").is_empty():
			seen_swing = true
	var best := 0.0
	for k in sim.mode.scores:
		best = maxf(best, float(sim.mode.scores[k]))
	check(seen_swing, "the light moved between anchors")
	check(best > 1.0, "someone hogged the light (best %.1f)" % best)
	check(sim.is_finished, "match finished by target or time")
	check(not sim.result.is_empty() and sim.result["mode"] == "spotlight_hog", "result recorded")


func test_chumball_ball_moves_and_scores_or_times_out() -> void:
	var sim := _mode_sim("chumball", {"score_target": 1, "round_time": 120.0}, _bots(4, false))
	var mode := sim.mode as ChumballMode
	var start := mode.ball.global_position
	var moved := false
	var t := 0.0
	while t < 125.0 and not sim.is_finished:
		await step_sim(sim, 1.0)
		t += 1.0
		if mode.ball.global_position.distance_to(start) > 1.5:
			moved = true
	check(moved, "players moved the ball")
	check(not _events(sim, "object_hit").is_empty() or not _events(sim, "ball_pickup").is_empty(), "ball was struck or carried")
	check(sim.is_finished, "goal or timeout ended the match")


func test_absolute_unit_is_crowned_scaled_and_scores() -> void:
	var sim := _mode_sim("absolute_unit", {"score_target": 15, "round_time": 80.0}, _bots(4))
	var mode := sim.mode as AbsoluteUnitMode
	await step_sim(sim, 4.0)
	check(mode.unit != null, "a Unit is crowned at the start")
	if mode.unit:
		check_near(mode.unit.creature.body.scale, 1.6, 0.001, "Unit body scale")
		check(mode.unit.rig.total_mass > 150.0, "Unit is heavy (%.0f kg)" % mode.unit.rig.total_mass)
		check(mode.unit.statuses.flag("no_dodge"), "Unit cannot dodge")
	var t := 4.0
	while t < 82.0 and not sim.is_finished:
		await step_sim(sim, 1.0)
		t += 1.0
	var best := 0.0
	for k in mode.scores:
		best = maxf(best, float(mode.scores[k]))
	check(best >= 5.0, "the Unit earned points (best %.1f)" % best)
	check(sim.is_finished, "finished")


func test_chum_rush_waves_spawn_and_slots_are_reused() -> void:
	var allies := _bots(2, false, 1)
	for a in allies:
		a["team"] = 0
	var sim := _mode_sim("chum_rush", {"wave_size_mult": 0.5, "picks": false, "round_time": 0.0, "enemy_health_mult": 0.3}, allies)
	var mode := sim.mode as ChumRushMode
	var t := 0.0
	while t < 300.0 and not sim.is_finished and mode.wave < 3:
		await step_sim(sim, 1.0)
		t += 1.0
	check(mode.wave >= 2, "multiple waves started (wave %d)" % mode.wave)
	check(mode.kills >= 3, "minions were defeated (%d)" % mode.kills)
	check(sim.fighters.size() <= MatchSim.MAX_FIGHTERS, "fighter slots bounded (%d)" % sim.fighters.size())
	check(not _events(sim, "fighter_despawned").is_empty(), "dead minions despawned")
