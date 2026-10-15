extends TestCase
## LAB-09: inference budget. Eight policy-controlled fighters play a live free-for-all; the
## measured policy cost (observation + network + action choice, decisions staggered at 15 Hz)
## must stay within the budget documented in docs/AI_LAB.md:
##   mean cost per 120 Hz physics tick for 8 policy fighters <= 0.2 ms (dev PC)
## A tolerance factor absorbs a busy machine; real measurements are printed for the record.

const BUDGET_TICK_US := 200.0
const TOLERANCE := 1.5


func test_eight_policy_fighters_fit_the_budget() -> void:
	var c := Content.creature("dev_biped")
	var sources: Array = []
	var fighters := []
	for k in 8:
		var p := PolicyData.create_new("dev_biped", PackedInt32Array([32, 32]), "tanh", 200 + k)
		var src := PolicyInputSource.create(p, k + 1, k)
		sources.append(src)
		fighters.append({"creature": c, "team": k, "source": src})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": ArenaDef.from_dict({"id": "bench", "base": "octagon", "radius": 6.0}), "rules": {"rounds": 1, "round_time": 0},
		"seed": 5, "fighters": fighters})
	sim.mode.phase = MatchMode.Phase.FIGHT
	sim.input_enabled = true
	var ticks := 360
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in ticks:
		sim.step(dt)
		await get_tree().physics_frame
	var total := 0
	var decisions := 0
	var worst := 0
	for s: PolicyInputSource in sources:
		total += s.total_usec
		decisions += s.decisions
		worst = maxi(worst, s.max_usec)
	var per_tick := float(total) / float(ticks)
	var per_decision := float(total) / float(maxi(decisions, 1))
	print("    inference: %d decisions, %.1f us per decision (worst %d us), %.1f us per tick for 8 fighters" % [decisions, per_decision, worst, per_tick])
	check(decisions >= 8 * ticks / 8 - 8, "decisions at ~15 Hz per fighter (%d)" % decisions)
	check(per_tick <= BUDGET_TICK_US * TOLERANCE, "per-tick cost %.1f us within budget %.0f us (x%.1f tolerance)" % [per_tick, BUDGET_TICK_US, TOLERANCE])
