extends TestCase
## v0.9.18 Movesets sounds (docs/design/MOVESET_COMBAT.md §9): a held stream runs one loop from the
## start of the pour to its end instead of a burst per damage tick, a target touched by ticks gets a
## quiet hit now and then, a move of its own gets its kind's cast sound, and the commentary still
## sees every tick (a stream that connects is called as landed).


func after_each() -> void:
	Audio.end_match()


func test_streams_hold_a_loop_and_ticks_stay_quiet() -> void:
	Audio.attach_match_dummy()        # STOKE (0) vs DREDGE (1)
	var at := {"time": 1.0, "pos": Vector3.ZERO}
	var cast := Audio.on_sim_event({"type": "ability", "fighter": 0, "slot": "mv.flamethrower", "id": "f_stoke.mv.flamethrower",
		"pool": "flamethrower", "cat": "stream"}, Vector3.ZERO, at)
	check(cast.has("whoosh_heavy"), "the Flamethrower's cast has its kind's sound (%s)" % str(cast))
	var start := Audio.on_sim_event({"type": "sustain", "phase": "start", "fighter": 0, "pool": "flamethrower", "slot": "m2"}, Vector3.ZERO, at)
	check(start.has("zone_scorch"), "the pour holds the scorch loop (%s)" % str(start))
	var sounds := 0
	for k in 8:
		sounds += Audio.on_sim_event({"type": "effect", "fighter": 0, "effect": "area", "element": "scorch", "pos": Vector3.ZERO,
			"pool": "flamethrower", "repeat": true}, Vector3.ZERO, at).size()
		sounds += Audio.on_sim_event({"type": "hit", "fighter": 0, "target": 1, "damage": 1.6, "slot": "mv.flamethrower",
			"pool": "flamethrower", "cat": "stream", "repeat": true, "element": "scorch"}, Vector3.ZERO, at).size()
	check(sounds <= 1, "eight ticks in a burst make at most one quiet hit sound (%d)" % sounds)
	var loops: Dictionary = Audio._state().get("sustain_loops", {})
	check(loops.has(0), "the loop runs while the stream pours")
	Audio.on_sim_event({"type": "sustain", "phase": "end", "fighter": 0, "pool": "flamethrower", "slot": "m2", "held": 1.2}, Vector3.ZERO, at)
	check(not (Audio._state().get("sustain_loops", {}) as Dictionary).has(0), "and stops when it ends")
	# a darts volley's repeated launches still sound, quietly
	var darts := Audio.on_sim_event({"type": "effect", "fighter": 0, "effect": "projectile", "element": "sludge", "pos": Vector3.ZERO,
		"pool": "poison_darts", "repeat": true}, Vector3.ZERO, at)
	check(darts.has("proj_launch_sludge"), "a repeated launch sounds (%s)" % str(darts))
