extends TestCase
## COOP-02 / MCH-01: Tag Team swaps, resting regen, auto-tag on KO; Practice refills and dummy
## behaviours. Run fast with --fixed-fps 120.


func _sim(mode_id: String, rules: Dictionary, entries: Array) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var r := rules.duplicate()
	r["mode"] = mode_id
	var es := []
	for e in entries:
		var d: Dictionary = e.duplicate()
		d["creature"] = Content.creature("dev_biped")
		es.append(d)
	sim.setup({"arena": Content.arena("the_gullet"), "rules": r, "seed": 3, "fighters": es, "mode": ModeRegistry.create(mode_id)})
	return sim


func test_tag_team_swaps_and_resting_partner_regenerates() -> void:
	var p0 := InputSource.Scripted.new([{"t0": 3.0, "t1": 3.05, "press": ["tag"]}])
	var sim := _sim("tag_team", {"rounds": 1, "round_time": 0.0}, [
		{"team": 0, "source": p0}, {"team": 0, "source": null}, {"team": 1, "source": null}, {"team": 1, "source": null}])
	var mode := sim.mode as TagTeamMode
	await step_sim(sim, 2.5)
	check_eq((mode.active[0] as Fighter).index, 0, "fighter 0 starts active")
	check(mode.is_resting(sim.fighters[1]), "partner rests on the apron")
	sim.fighters[1].health = 40.0
	await step_sim(sim, 1.5)
	check_eq((mode.active[0] as Fighter).index, 1, "tag brought the partner in")
	check(mode.is_resting(sim.fighters[0]), "tagged-out fighter rests")
	var hp_before := sim.fighters[0].health
	sim.fighters[0].health = 30.0
	await step_sim(sim, 2.0)
	check(sim.fighters[0].health > 30.0 + 5.0, "resting fighter regenerates")
	# KO the active fighter: the resting partner is tagged in automatically
	var a: Fighter = mode.active[0]
	sim.on_fighter_depleted(a, null, {})
	check(mode.active[0] != a, "auto-tag on KO")
	check(not sim.is_finished, "team still alive")


func test_practice_refills_and_dummy_guards() -> void:
	var p0 := InputSource.Scripted.new([{"t0": 2.4, "t1": 9.0, "move": "to_target", "press": ["light"], "every": 0.4}])
	var sim := _sim("practice", {}, [{"team": 0, "source": p0}, {"team": 1, "source": null}])
	var mode := sim.mode as PracticeMode
	mode.set_behavior("guard")
	sim.fighters[1].health = 1.0
	sim.on_fighter_depleted(sim.fighters[1], sim.fighters[0], {})
	check_near(sim.fighters[1].health, sim.fighters[1].max_health, 0.01, "practice refills instead of KO")
	await step_sim(sim, 9.0)
	var blocked := sim.events.filter(func(e): return e["type"] == "hit" and bool(e["blocked"]))
	check(not blocked.is_empty(), "guard dummy blocks")
	check(not sim.is_finished, "practice never ends on its own")
	check(mode.hud_status().contains("Dummy"), "telemetry text available")
