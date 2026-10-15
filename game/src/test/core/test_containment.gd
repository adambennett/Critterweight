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


## Bots keep off open (ring-out) edges: near one, an outward move is bent back onto the floor,
## and with ring-outs switched off (guard walls) nothing changes.
func test_bots_steer_away_from_open_edges() -> void:
	var sim := make_sim("arena_rooftop", {"rounds": 1, "round_time": 0}, [{"creature": "dev_biped", "team": 0}, {"creature": "dev_biped", "team": 1}], 3)
	var a := sim.arena
	check(a.has_open_edges(), "the Rooftop has ring-out edges")
	var f := sim.fighters[0]
	var brain := BotBrain.new("pro", 5)
	# find a floor point 0.5 m inside an open edge
	var spot := Vector3.INF
	for e in a.boundary_edges():
		if bool(e["wall"]):
			continue
		var mid: Vector2 = ((e["a"] as Vector2) + (e["b"] as Vector2)) * 0.5
		var n: Vector2 = e["n"]
		spot = Vector3(mid.x - n.x * 0.5, 0.0, mid.y - n.y * 0.5)
		break
	check(spot != Vector3.INF, "an open edge exists")
	f.rig.shift(spot - f.ground_pos())
	var inward := a.open_edge_inward(f.pos())
	var safe := brain._edge_safe(f, sim, -inward)
	check(safe.dot(inward) > 0.0, "walking off the edge turns into stepping back in (%.2f)" % safe.dot(inward))
	var far := brain._edge_safe(f, sim, inward)
	check(far.dot(inward) > 0.9, "moving inward is kept")
	sim.rules["ringouts"] = false
	check(brain._edge_safe(f, sim, -inward).is_equal_approx(-inward), "no change when ring-outs are off")
