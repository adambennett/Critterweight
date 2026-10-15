extends TestCase
## LAB-04 / VER-01: the obs_v1 / act_v1 contracts — shape, bounds, determinism, perception
## (no hidden state), fighter-space frame, and that the recorder's inverse action mapping
## reproduces exactly what a policy did (same contract in training, recording and matches).


func _duel(gap := 3.0, seed_value := 3) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 5.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var c := Content.creature("dev_biped")
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 30}, "seed": seed_value,
		"fighters": [{"creature": c, "team": 0, "source": null}, {"creature": c, "team": 1, "source": null}]})
	return sim


func test_feature_names_match_size() -> void:
	check_eq(PolicyObs.NAMES.size(), PolicyObs.SIZE, "one name per feature")
	check_eq(PolicyObs.TARGET_START + PolicyObs.TARGET_SIZE, PolicyObs.ENV_START, "target block layout")
	check_eq(PolicyObs.ENV_START + PolicyObs.ENV_SIZE, PolicyObs.HIST_START, "env block layout")
	check_eq(PolicyObs.HIST_START + PolicyActions.OUTPUTS + 2, PolicyObs.SIZE, "history block layout")
	check_eq(PolicyObs.NAMES[PolicyObs.TARGET_START], "tgt_present")
	check_eq(PolicyObs.NAMES[PolicyObs.ENV_START], "wall_fwd")
	check_eq(PolicyObs.NAMES[PolicyObs.HIST_START], "prev_move_none")
	check_eq(PolicyActions.MOVE_NAMES.size(), PolicyActions.MOVE_COUNT)
	check_eq(PolicyActions.BUTTON_NAMES.size(), PolicyActions.BUTTON_COUNT)
	check_eq(PolicyActions.PRESS.size(), PolicyActions.BUTTON_COUNT)
	check_eq(PolicyActions.HOLD.size(), PolicyActions.BUTTON_COUNT)


func test_observation_shape_bounds_and_determinism() -> void:
	var sim := _duel()
	await step_sim(sim, 1.0)
	var f := sim.fighters[0]
	var a := PolicyObs.new(0).encode(f, sim, 3, 5)
	var b := PolicyObs.new(0).encode(f, sim, 3, 5)
	check_eq(a.size(), PolicyObs.SIZE, "observation size")
	var bad := 0
	for x in a:
		if not is_finite(x) or absf(x) > 2.0:
			bad += 1
	check_eq(bad, 0, "all features finite and within [-2, 2]")
	check(a == b, "same state -> identical observation")
	check_eq(a[PolicyObs.HIST_START + 3], 1.0, "previous move one-hot")
	check_eq(a[PolicyObs.HIST_START + PolicyActions.MOVE_COUNT + 5], 1.0, "previous button one-hot")
	check_near(a[0], 1.0, 1e-6, "full health")
	check_eq(a[PolicyObs.TARGET_START], 1.0, "target present")


func test_target_seen_in_fighter_space() -> void:
	var sim := _duel(3.0)
	await step_sim(sim, 0.5)
	var f := sim.fighters[0]
	var o := PolicyObs.new(0).encode(f, sim, 0, 0)
	var t := PolicyObs.TARGET_START
	# fighter 0 faces +Z toward fighter 1, 3 m away: straight ahead, facing us
	check(o[t + 2] > 0.3, "target ahead (rel_fwd %.2f)" % o[t + 2])
	check(absf(o[t + 1]) < 0.1, "target not to the side (rel_left %.2f)" % o[t + 1])
	check_near(o[t + 3] * PolicyObs.POS_SCALE, f.pos().distance_to(sim.fighters[1].pos()), 0.15, "distance")
	check(o[t + 5] > 0.95, "bearing cos ~1")
	check(o[t + 7] > 0.8, "target faces us")
	# turn our fighter 90° left: the target must now appear on our right (negative left axis)
	f.facing_yaw = MathX.wrap_angle(f.facing_yaw + PI * 0.5)
	var o2 := PolicyObs.new(0).encode(f, sim, 0, 0)
	check(o2[t + 1] < -0.3, "after turning left the target is on the right (rel_left %.2f)" % o2[t + 1])


func test_wall_rays_see_the_cage() -> void:
	var sim := _duel(3.0)
	await step_sim(sim, 0.3)
	var f := sim.fighters[0]
	f.facing_yaw = 0.0          # facing +Z
	var o := PolicyObs.new(0).encode(f, sim, 0, 0)
	var e := PolicyObs.ENV_START
	# fighter 0 stands at z = -1.5 in a radius-5 octagon facing +Z: ~6.5 m ahead, ~3.5 m behind
	check(o[e + 0] > o[e + 4], "more room ahead than behind (%.2f vs %.2f)" % [o[e + 0], o[e + 4]])
	check_near(o[e + 4] * 10.0, 5.0 - 1.5, 0.35, "distance to the wall behind")
	check_eq(o[e + 8], 0.0, "caged arena (no ring-out)")


## Hidden information (the opponent's inputs, buffers, RNG) must not leak into observations.
func test_only_perceivable_state_is_observed() -> void:
	var sim := _duel(2.0)
	await step_sim(sim, 0.6)
	var f := sim.fighters[0]
	var opp := sim.fighters[1]
	var before := PolicyObs.new(0).encode(f, sim, 0, 0)
	opp.input.move = Vector3(1, 0, 0)
	opp.input.held = (1 << FighterInput.GUARD) | (1 << FighterInput.HEAVY)
	opp.input.press(FighterInput.LIGHT)
	opp.input.press(FighterInput.GRAB)
	sim.rng.seed = 987654
	var after := PolicyObs.new(0).encode(f, sim, 0, 0)
	check(before == after, "opponent intent / RNG are invisible until they change the visible state")


func test_perception_lag_uses_previous_snapshot() -> void:
	var sim := _duel(3.0)
	await step_sim(sim, 0.4)
	var f := sim.fighters[0]
	var enc := PolicyObs.new(1)
	var first := enc.encode(f, sim, 0, 0)
	var t := PolicyObs.TARGET_START
	var hp_before := first[t + 10]
	sim.fighters[1].health -= 30.0
	var lagged := enc.encode(f, sim, 0, 0)
	check_near(lagged[t + 10], hp_before, 1e-6, "lagged view still shows the old health")
	var later := enc.encode(f, sim, 0, 0)
	check(later[t + 10] < hp_before - 0.2, "next decision sees the damage")
	check(later[PolicyObs.HIST_START + 22] > 0.0 or lagged[PolicyObs.HIST_START + 22] > 0.0, "recent target damage cue")


func test_action_apply_and_classify_round_trip() -> void:
	var window := PolicyActions.decision_ticks(PolicyActions.DEFAULT_DECISION_HZ)
	check_eq(window, 8, "15 Hz at 120 Hz physics")
	var fwd := Vector3(0.6, 0, 0.8)
	var left := Vector3(fwd.z, 0, -fwd.x)
	var mismatches := []
	for prev_b in [PolicyActions.B_NONE, PolicyActions.B_HEAVY_HOLD, PolicyActions.B_GUARD_HOLD]:
		for mv in PolicyActions.MOVE_COUNT:
			for bt in PolicyActions.BUTTON_COUNT:
				var fi := FighterInput.new()
				var last := fi.press_count.duplicate()
				var presses := 0
				var held := PackedInt32Array()
				held.resize(FighterInput.BUTTON_COUNT)
				var move_sum := Vector3.ZERO
				var vec := PolicyActions.move_world(mv, fwd, left)
				for k in window:
					PolicyActions.apply_tick(fi, vec, bt, prev_b, k)
					for b in FighterInput.BUTTON_COUNT:
						if fi.press_count[b] != last[b]:
							presses |= 1 << b
						if fi.is_held(b):
							held[b] += 1
					last = fi.press_count.duplicate()
					move_sum += fi.move
				var cm := PolicyActions.classify_move(move_sum / float(window), fwd, left)
				var cb := PolicyActions.classify_button(presses, held, window, prev_b)
				if cm != mv or cb != bt:
					mismatches.append("%s+%s (prev %s) -> %s+%s" % [PolicyActions.MOVE_NAMES[mv], PolicyActions.BUTTON_NAMES[bt],
						PolicyActions.BUTTON_NAMES[prev_b], PolicyActions.MOVE_NAMES[cm], PolicyActions.BUTTON_NAMES[cb]])
	check(mismatches.is_empty(), "inverse mapping is exact: %s" % ", ".join(mismatches.slice(0, 6)))


func test_masks_and_choice() -> void:
	var c := Content.creature("dev_biped")
	var m := PolicyActions.button_mask(c)
	check_eq(m.size(), PolicyActions.BUTTON_COUNT)
	check_eq(m[PolicyActions.B_AB1], 1, "dev_biped has ability1")
	var bare := CreatureDef.new()
	var m2 := PolicyActions.button_mask(bare)
	check_eq(m2[PolicyActions.B_AB2], 0, "missing ability2 masked")
	var logits := PackedFloat32Array()
	logits.resize(PolicyActions.OUTPUTS)
	logits[PolicyActions.MOVE_COUNT + PolicyActions.B_AB2] = 50.0
	logits[PolicyActions.MOVE_COUNT + PolicyActions.B_LIGHT] = 1.0
	check_eq(PolicyActions.choose(logits, PolicyActions.MOVE_COUNT, PolicyActions.BUTTON_COUNT, m2, "argmax", 1.0, null), PolicyActions.B_LIGHT, "masked class never chosen")
	var r1 := RandomNumberGenerator.new()
	r1.seed = 5
	var r2 := RandomNumberGenerator.new()
	r2.seed = 5
	var s1 := []
	var s2 := []
	for k in 20:
		s1.append(PolicyActions.choose(logits, 0, PolicyActions.MOVE_COUNT, PackedByteArray(), "sample", 1.0, r1))
		s2.append(PolicyActions.choose(logits, 0, PolicyActions.MOVE_COUNT, PackedByteArray(), "sample", 1.0, r2))
	check(s1 == s2, "seeded sampling is reproducible")


## A policy drives a fighter while a PolicyRecorder wraps it: the recorder must label every
## window with exactly the classes the policy chose (stochastic policy -> many classes).
func test_recorder_reproduces_policy_actions() -> void:
	var p := PolicyData.create_new("dev_biped", PackedInt32Array([16]), "tanh", 42)
	p.act_mode = "sample"
	p.temperature = 2.0
	var src := PolicyInputSource.create(p, 7, 0)
	var chosen := []
	src.on_decision = func(_o: PackedFloat32Array, mv: int, bt: int) -> void: chosen.append([mv, bt])
	var rec := PolicyRecorder.new(src, "", "test")
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 5.0, "spawns": [[0, -1.5, 0], [0, 1.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var c := Content.creature("dev_biped")
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0}, "seed": 9,
		"fighters": [{"creature": c, "team": 0, "source": rec}, {"creature": c, "team": 1, "source": null}]})
	sim.mode.phase = MatchMode.Phase.FIGHT
	sim.input_enabled = true
	await step_sim(sim, 4.0)
	# only complete windows are compared (the last one is still open)
	var n := rec.moves.size()
	check(n >= 40, "recorded %d windows" % n)
	check(chosen.size() >= n, "the recorder never labels more windows than the policy decided")
	var wrong := []
	var classes := {}
	for k in n:
		var want: Array = chosen[k]
		classes["%d_%d" % [want[0], want[1]]] = true
		if int(rec.moves[k]) != int(want[0]) or int(rec.buttons[k]) != int(want[1]):
			wrong.append("#%d policy %s+%s (prev %s) recorded %s+%s" % [k, PolicyActions.MOVE_NAMES[int(want[0])], PolicyActions.BUTTON_NAMES[int(want[1])],
				PolicyActions.BUTTON_NAMES[int(chosen[k - 1][1])] if k > 0 else "-", PolicyActions.MOVE_NAMES[int(rec.moves[k])], PolicyActions.BUTTON_NAMES[int(rec.buttons[k])]])
	check(wrong.is_empty(), "labels equal the policy's own decisions (%d windows, %d distinct actions): %s" % [n, classes.size(), "; ".join(wrong)])
	check(classes.size() >= 10, "stochastic policy exercised many action classes (%d)" % classes.size())
	# observations recorded are the obs_v1 vectors
	check_eq(rec.obs_rows.size(), n * PolicyObs.SIZE)
	src.on_decision = Callable()
