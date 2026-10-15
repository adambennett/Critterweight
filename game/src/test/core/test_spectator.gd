extends TestCase
## AI-02: the spectator auto-director cuts to big moments, varies shots, mixes in wide shots,
## and lets the viewer lock onto a fighter and hand control back. Run with --fixed-fps 120.


func _sim(n: int) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var c := Content.creature("dev_biped")
	var entries := []
	for i in n:
		entries.append({"creature": c, "team": i, "source": BotBrain.new("pro", 50 + i), "kind": "bot"})
	sim.setup({"arena": Content.arena("the_gullet"), "rules": {"mode": "standard", "round_time": 0.0}, "seed": 21,
		"fighters": entries, "mode": ModeRegistry.create("standard")})
	return sim


func test_director_cuts_to_big_moments_and_varies_shots() -> void:
	var sim := _sim(4)
	var d := SpectatorDirector.new(sim)
	d.on_event({"type": "knockdown", "fighter": 2})
	check_eq(d.focus_index, 2, "cut to the knockdown")
	check_eq(d.shot, "close")
	check_eq((d.focus() as Array).size(), 2, "focus pair for the camera")
	var shots := {}
	var focused := {}
	for k in 400:
		d.update(0.1)
		sim.time += 0.1
		shots[d.shot] = true
		focused[d.focus_index] = true
	check(shots.has("wide"), "wide shots with 3+ fighters standing")
	check(focused.size() >= 3, "the director visits several fighters (%d)" % focused.size())
	check(d.points().is_empty() == (d.shot == "wide"), "wide shot frames everyone")


func test_viewer_lock_cycles_and_returns_to_auto() -> void:
	var sim := _sim(3)
	var d := SpectatorDirector.new(sim)
	d.cycle_lock(1)
	check_eq(d.locked, 0, "first fighter")
	d.update(0.1)
	check_eq(d.focus_index, 0, "camera follows the lock")
	d.on_event({"type": "ko", "fighter": 2})
	check_eq(d.focus_index, 0, "a lock is never overridden by cuts")
	d.cycle_lock(1)
	d.cycle_lock(1)
	check_eq(d.locked, 2)
	d.cycle_lock(1)
	check_eq(d.locked, -1, "past the end -> auto director")
	check(d.label().begins_with("Auto"), "label says auto")
	await step_sim(sim, 0.5)
