extends TestCase
## v0.9.18 Movesets sounds (docs/design/MOVESET_COMBAT.md §9): a held stream runs one loop from the
## start of the pour to its end instead of a burst per damage tick, a target touched by ticks gets a
## quiet hit now and then, a move of its own gets its kind's cast sound, and the commentary still
## sees every tick (a stream that connects is called as landed).


func after_each() -> void:
	Audio.end_match()


## on_sim_event returns both sound IDs and "line:" commentary actions. Commentary still receives
## every tick; count the impact/effect sounds separately rather than treating speech as hit spam.
func _sounds(actions: Array) -> Array:
	return actions.filter(func(id) -> bool: return not str(id).begins_with("line:"))


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
		sounds += _sounds(Audio.on_sim_event({"type": "effect", "fighter": 0, "effect": "area", "element": "scorch", "pos": Vector3.ZERO,
			"pool": "flamethrower", "repeat": true}, Vector3.ZERO, at)).size()
		sounds += _sounds(Audio.on_sim_event({"type": "hit", "fighter": 0, "target": 1, "damage": 1.6, "slot": "mv.flamethrower",
			"pool": "flamethrower", "cat": "stream", "repeat": true, "element": "scorch"}, Vector3.ZERO, at)).size()
	check_eq(sounds, 1, "eight ticks make exactly one quiet impact, with no repeated area sound")
	var loops: Dictionary = Audio._state().get("sustain_loops", {})
	check(loops.has(0), "the loop runs while the stream pours")
	Audio.on_sim_event({"type": "sustain", "phase": "end", "fighter": 0, "pool": "flamethrower", "slot": "m2", "held": 1.2}, Vector3.ZERO, at)
	check(not (Audio._state().get("sustain_loops", {}) as Dictionary).has(0), "and stops when it ends")
	# a darts volley's repeated launches still sound, quietly
	var darts := Audio.on_sim_event({"type": "effect", "fighter": 0, "effect": "projectile", "element": "sludge", "pos": Vector3.ZERO,
		"pool": "poison_darts", "repeat": true}, Vector3.ZERO, at)
	check(darts.has("proj_launch_sludge"), "a repeated launch sounds (%s)" % str(darts))


func test_stream_impact_cooldown_is_per_target_and_recovers() -> void:
	Audio.attach_match_dummy()
	var hit := {"type": "hit", "fighter": 0, "target": 1, "damage": 1.6, "slot": "mv.flamethrower",
		"pool": "flamethrower", "cat": "stream", "repeat": true, "element": "scorch"}
	check_eq(_sounds(Audio.on_sim_event(hit)), ["hit_light"], "first contact makes one quiet impact")
	check(_sounds(Audio.on_sim_event(hit)).is_empty(), "the next tick does not stack another impact")
	var other := hit.duplicate(true)
	other["fighter"] = 1
	other["target"] = 0
	other["blocked"] = true
	check_eq(_sounds(Audio.on_sim_event(other)), ["hit_guard"], "another target has an independent blocked impact")
	# Advance the target's recorded last-sound time without a wall-clock sleep in this unit check.
	Audio._state()["tick_sound"][1] = Audio._now() - Audio.TICK_SOUND_GAP - 0.01
	check_eq(_sounds(Audio.on_sim_event(hit)), ["hit_light"], "contact becomes audible again after the interval")
	check(_sounds(Audio.on_sim_event(other)).is_empty(), "that does not reset the other target's interval")
