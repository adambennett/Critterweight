extends TestCase
## v0.9.18 engine additions raised while the move pools were built (docs/design/MOVESET_COMBAT.md
## §3.3, docs/MODDING.md): grounded areas skip airborne and hovering fighters, the blow that knocks a
## fighter down still applies its build-up, `repeats` caps a repeating effect, a counter stance's
## answer and a move's zone damage are credited to the move.


func _duel(style := "moves") -> MatchSim:
	var sim := make_sim("", {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": style},
		[{"creature": "f_dozer", "team": 0}, {"creature": "f_dredge", "team": 1}])
	return sim


func _place(sim: MatchSim, gap: float) -> void:
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	a.rig.place(Vector3(0, a.rig.ground_y, -gap * 0.5), 0.0)
	b.rig.place(Vector3(0, b.rig.ground_y, gap * 0.5), PI)


func test_grounded_areas_skip_hovering_fighters() -> void:
	var sim := _duel()
	await step_sim(sim, 0.4)
	_place(sim, 1.5)
	await step_sim(sim, 0.1)
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	var quake := {"type": "area", "shape": "circle", "radius": 2.5, "damage": 5.0, "knockdown": true, "grounded": true}
	b.set_flag("hovering", 1.0)
	var hp := b.health
	sim.effects.fire(a, quake.duplicate())
	await step_sim(sim, 0.1)
	check(is_equal_approx(b.health, hp) and not b.is_down(), "a hovering fighter is not tripped by a quake")
	b.flags.erase("hovering")
	await step_sim(sim, 0.3)
	sim.effects.fire(a, quake.duplicate())
	await step_sim(sim, 0.1)
	check(b.health < hp, "one standing on the floor is (%.1f -> %.1f)" % [hp, b.health])


func test_the_knockdown_blow_builds_its_status() -> void:
	var sim := _duel()
	await step_sim(sim, 0.4)
	_place(sim, 1.2)
	await step_sim(sim, 0.1)
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	sim.effects.fire(a, {"type": "area", "shape": "circle", "radius": 2.5, "damage": 4.0, "knockdown": true, "unblockable": true,
		"element": "grit", "buildup": 40})
	await step_sim(sim, 0.05)
	check(b.is_down(), "the blow knocks Dredge down")
	check(float(b.statuses.buildup.get("grit", 0.0)) > 0.0 or b.statuses.has_element("grit"), "and its grit build-up applies (%s)" % str(b.statuses.buildup))
	var before := float(b.statuses.buildup.get("grit", 0.0))
	sim.effects.fire(a, {"type": "area", "shape": "circle", "radius": 2.5, "damage": 1.0, "element": "grit", "buildup": 40})
	await step_sim(sim, 0.05)
	check(float(b.statuses.buildup.get("grit", 0.0)) <= before + 0.001, "a later hit on the downed fighter builds nothing")


func test_repeats_caps_a_repeating_effect() -> void:
	check_eq(EffectsSystem._repeat_cap({"type": "area", "repeats": 3}), 3, "repeats caps the firings")
	check_eq(EffectsSystem._repeat_cap({"type": "area", "count": 4}), 4, "count on an area is the cap (older content)")
	check_eq(EffectsSystem._repeat_cap({"type": "projectile", "count": 5}), -1, "a projectile's count is how many fly")
	check_eq(EffectsSystem._repeat_cap({"type": "projectile", "count": 5, "repeats": 2}), 2, "repeats wins")


func test_counters_and_zones_are_credited_to_their_moves() -> void:
	var sim := _duel()
	await step_sim(sim, 0.4)
	_place(sim, 1.0)
	await step_sim(sim, 0.1)
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	# Dredge sets a counter stance from a pool move: Dozer strikes into it
	b.move_pool_id = "anchor_drop"
	sim.effects.fire(b, {"type": "counter_stance", "duration": 1.5, "counter": {"damage": 6, "poise": 10}})
	b.move_pool_id = ""
	var seq0 := sim.event_seq
	a.input.press(FighterInput.LIGHT)        # Dozer's Snout Jab into the stance
	await step_sim(sim, 0.6)
	a.input.set_held(FighterInput.LIGHT, false)
	var answers := sim.events.filter(func(e: Dictionary) -> bool:
		return int(e["seq"]) > seq0 and str(e["type"]) == "hit" and int(e.get("fighter", -1)) == 1 and int(e.get("target", -1)) == 0)
	check(not answers.is_empty() and str(answers[0].get("pool", "")) == "anchor_drop", "the counter's answer is Anchor Drop's (%s)" % str(answers))
	# a zone fired by a pool move ticks as that move, a repeat
	a.move_pool_id = "rock_slide"
	sim.effects.fire(a, {"type": "zone", "radius": 2.5, "duration": 1.2, "tick": 0.3, "tick_damage": 2.0, "element": "grit", "at": "self"})
	a.move_pool_id = ""
	_place(sim, 0.8)
	var seq1 := sim.event_seq
	await step_sim(sim, 1.0)
	var ticks := sim.events.filter(func(e: Dictionary) -> bool:
		return int(e["seq"]) > seq1 and str(e["type"]) == "hit" and str(e.get("slot", "")) == "zone" and int(e.get("target", -1)) == 1)
	check(not ticks.is_empty(), "the zone ticks on Dredge")
	check(ticks.all(func(e: Dictionary) -> bool: return str(e.get("pool", "")) == "rock_slide" and bool(e.get("repeat", false))),
		"credited to the move and marked as repeats (%s)" % str(ticks.slice(0, 2)))
