extends TestCase
## Fighters must stay inside walled arenas (no tunnelling through the fence) during busy bot
## matches, including spawned wave minions. Run with --fixed-fps 120.


func test_spawned_minions_start_inside_and_stay_inside() -> void:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var entries := []
	for i in 2:
		entries.append({"creature": Content.creature("dev_biped"), "team": 0, "source": BotBrain.new("regular", 70 + i), "kind": "bot"})
	sim.setup({"arena": Content.arena("the_gullet"), "rules": {"mode": "chum_rush", "wave_size_mult": 1.0, "picks": false}, "seed": 9,
		"fighters": entries, "mode": ModeRegistry.create("chum_rush")})
	var worst := 0.0
	var worst_desc := ""
	var t := 0.0
	while t < 40.0 and not sim.is_finished:
		await step_sim(sim, 0.5)
		t += 0.5
		for f in sim.fighters:
			if f.despawned or f.state == Fighter.State.INACTIVE:
				continue
			var p := f.pos()
			var out := Vector2(p.x, p.z).length() - (sim.arena.radius / cos(PI / 8.0))
			if out > worst:
				worst = out
				worst_desc = "t=%.1f fighter %d (%s team %d) at (%.2f, %.2f, %.2f) state %s" % [t, f.index, f.creature.id, f.team, p.x, p.y, p.z, f.state_name()]
	check(worst <= 0.3, "a fighter left the cage: %s" % worst_desc)
