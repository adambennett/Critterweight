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
	while t < 100.0 and not sim.is_finished:
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


## Review regression: score modes respawn knocked-out fighters (the shipped presets have no
## "lives" key, which once meant one life and no respawn).
func test_score_mode_presets_respawn_knocked_out_fighters() -> void:
	for preset in ["spotlight_hog", "chumball", "absolute_unit"]:
		var rules: Dictionary = Content.get_entry("rules", preset).duplicate(true)
		var sim := MatchSim.new()
		sim.running = false
		fresh_world().add_child(sim)
		var entries := []
		for i in 4:
			entries.append({"creature": Content.creature("dev_biped"), "team": i % 2 if preset == "chumball" else i, "source": null, "kind": "bot"})
		sim.setup({"arena": Content.arena("the_gullet"), "rules": rules, "seed": 5, "fighters": entries, "mode": ModeRegistry.create(str(rules["mode"]))})
		await step_sim(sim, 3.0)
		var victim: Fighter = sim.fighters[3]
		if preset == "absolute_unit" and sim.mode.get("unit") == victim:
			victim = sim.fighters[2]
		sim.on_fighter_depleted(victim, sim.fighters[1], {})
		check(victim.is_out(), "%s: knocked out" % preset)
		await step_sim(sim, float(sim.rules.get("respawn_delay", 5.0)) + 1.5)
		check(not victim.is_out(), "%s: respawned after the delay" % preset)
		check(not sim.is_finished, "%s: one KO does not end the match" % preset)


## Review regression (2026-10-16): Chum Rush picks once read top-level mods/hooks that no
## supplement has (effects live under "apply"), so every pick did nothing. A stat, a hook and a
## move patch must each change the fighter, and a supplement stops being offered at its stack cap.
func test_chum_rush_supplements_change_the_fighter() -> void:
	var sim := _mode_sim("chum_rush", {"round_time": 0.0}, [{"creature": "f_stoke", "team": 0, "source": null, "kind": "bot"}])
	await step_sim(sim, 0.5)
	var mode: ChumRushMode = sim.mode
	var f: Fighter = sim.fighters[0]
	var take := func(sid: String) -> void:
		mode.pending_pick[f.index] = [sid]
		mode.choose_pick(f.index, 0)
	# stat: Marrow Shake, max HP +12 (granted at once), walk speed x0.97
	var hp0 := f.max_health
	var cur0 := f.health
	var spd0 := float(f.mods["speed"])
	take.call("sup_marrow_shake")
	check(is_equal_approx(f.max_health, hp0 + 12.0), "Marrow Shake: max HP %.1f -> %.1f" % [hp0, f.max_health])
	check(is_equal_approx(f.health, cur0 + 12.0), "Marrow Shake: the 12 HP are granted now")
	check(is_equal_approx(float(f.mods["speed"]), spd0 * 0.97), "Marrow Shake: speed x0.97")
	check(not _events(sim, "pick_taken").is_empty(), "the pick is reported")
	# hook: Adrenal Drip, a round-start buff hook and max stamina -10
	var st0 := f.max_stamina
	take.call("sup_adrenal_drip")
	check(f.hooks.list.any(func(h): return str(h.get("source", "")) == "supplement:sup_adrenal_drip"), "Adrenal Drip: its hook is installed")
	check(is_equal_approx(f.max_stamina, st0 - 10.0), "Adrenal Drip: max stamina -10")
	# move patch: Tusk Dust, heavy damage x1.12 (and stamina regen x0.9)
	var dmg0 := float((f.creature.moves["heavy"] as MoveDef).damage)
	var regen0 := float(f.mods["stamina_regen"])
	take.call("sup_tusk_dust")
	check(is_equal_approx(float((f.creature.moves["heavy"] as MoveDef).damage), dmg0 * 1.12), "Tusk Dust: heavy damage %.2f -> %.2f" % [dmg0, (f.creature.moves["heavy"] as MoveDef).damage])
	check(is_equal_approx(float(f.mods["stamina_regen"]), regen0 * 0.9), "Tusk Dust: stamina regen x0.9")
	check(f.max_health > hp0, "earlier picks survive a later patch")
	# stacking: Marrow Shake stacks twice, then it is no longer offered
	take.call("sup_marrow_shake")
	check(is_equal_approx(f.max_health, hp0 + 24.0), "Marrow Shake stacks: +24")
	check(not mode._can_take(f, "sup_marrow_shake"), "Marrow Shake at its stack cap is not offered again")
	# offers: three different OTC / Prescription supplements, nothing capped
	f.controller_kind = "player"
	mode.wave = 5
	mode._offer_picks()
	var offer: Array = mode.pending_pick.get(f.index, [])
	check_eq(offer.size(), 3, "three supplements offered")
	var distinct := {}
	for sid in offer:
		distinct[sid] = true
	check_eq(distinct.size(), offer.size(), "all different")
	for sid in offer:
		var u := Content.get_entry("supplements", str(sid))
		check(str(u.get("type", "")) == "supplement" and str(u.get("rarity", "")) in ["otc", "prescription"], "%s is an OTC/Prescription supplement" % sid)
		check(str(sid) != "sup_marrow_shake", "a capped supplement is not offered")


## Review regression (2026-10-16): Chumball KOs once scored like goals (MatchMode's default
## ko_points on a preset that wins on "score"). KOs give nothing; four KOs then a goal make 1-0.
func test_chumball_knockouts_never_score() -> void:
	var rules: Dictionary = Content.get_entry("rules", "chumball").duplicate(true)
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var entries := []
	for i in 4:
		entries.append({"creature": Content.creature("dev_biped"), "team": i % 2, "source": null, "kind": "bot"})
	sim.setup({"arena": Content.arena("the_gullet"), "rules": rules, "seed": 5, "fighters": entries, "mode": ModeRegistry.create("chumball")})
	await step_sim(sim, 1.0)
	var mode: ChumballMode = sim.mode
	var kos := 0
	for round_i in 2:
		for vi in [1, 3]:
			var victim: Fighter = sim.fighters[vi]
			sim.on_fighter_depleted(victim, sim.fighters[0], {})
			if victim.is_out():
				kos += 1
		await step_sim(sim, float(sim.rules.get("respawn_delay", 6.0)) + 1.5)
	check_eq(kos, 4, "four KOs by team 0")
	check_eq(float(mode.scores.get(0, 0.0)), 0.0, "KOs give team 0 nothing")
	check_eq(float(mode.scores.get(1, 0.0)), 0.0, "and team 1 nothing")
	# a real goal: the ball in team 1's goal mouth, last touched by team 0
	var g: Dictionary = mode.goals[1]
	mode.ball.linear_velocity = Vector3.ZERO
	mode.ball.global_position = (g["pos"] as Vector3) + Vector3.UP * 0.5
	mode.last_touch = sim.fighters[0]
	await step_sim(sim, 0.2)
	check_eq(float(mode.scores.get(0, 0.0)), 1.0, "four KOs and one goal make 1 for team 0")
	check_eq(float(mode.scores.get(1, 0.0)), 0.0, "team 1 still 0")
	check(not sim.is_finished, "first to 5: the match goes on")
