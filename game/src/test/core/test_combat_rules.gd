extends TestCase
## CMB-02/07: contact requirement, guard, anti-infinite protection, determinism.


func _sim(s0: InputSource, s1: InputSource, gap := 1.1, seed_value := 7) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 5.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var c := Content.creature("dev_biped")
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0}, "seed": seed_value,
		"fighters": [{"creature": c, "team": 0, "source": s0}, {"creature": c, "team": 1, "source": s1}]})
	return sim


func _count(sim: MatchSim, type: String, key := "", val = null) -> int:
	var n := 0
	for ev in sim.events:
		if ev["type"] == type and (key == "" or ev.get(key) == val):
			n += 1
	return n


func test_out_of_range_strikes_never_damage() -> void:
	var sim := _sim(InputSource.Scripted.new([{"t0": 2.4, "t1": 5.0, "press": ["light"], "every": 0.4}]), null, 3.5)
	await step_sim(sim, 5.0)
	check_eq(_count(sim, "hit"), 0, "no contact, no damage")
	check_near(sim.fighters[1].health, sim.fighters[1].max_health, 0.01)


func test_strikes_in_range_land_and_guard_reduces_damage() -> void:
	var open := _sim(InputSource.Scripted.new([{"t0": 2.4, "t1": 6.0, "move": "to_target", "press": ["light"], "every": 0.45}]), null, 0.9)
	await step_sim(open, 6.0)
	var dmg_open := open.fighters[1].max_health - open.fighters[1].health
	var guarded := _sim(InputSource.Scripted.new([{"t0": 2.4, "t1": 6.0, "move": "to_target", "press": ["light"], "every": 0.45}]), InputSource.Scripted.new([{"t0": 0.0, "t1": 7.0, "hold": ["guard"]}]), 0.9)
	await step_sim(guarded, 6.0)
	var dmg_guard := guarded.fighters[1].max_health - guarded.fighters[1].health
	check(_count(open, "hit") >= 2, "jabs connect at boxing range")
	check(dmg_open > 0.0, "open target damaged")
	check(dmg_guard < dmg_open * 0.5, "guard absorbs most damage (open %.1f, guarded %.1f)" % [dmg_open, dmg_guard])
	check(_count(guarded, "hit", "blocked", true) >= 1, "blocked hits reported")


func test_stun_budget_breaks_infinite_pressure() -> void:
	var sim := _sim(InputSource.Scripted.new([{"t0": 2.3, "t1": 14.0, "move": "to_target", "press": ["light"], "every": 0.18}]), null, 1.0)
	await step_sim(sim, 14.0)
	check(_count(sim, "burst") >= 1 or _count(sim, "knockdown") >= 1, "pressure is interrupted by burst or knockdown, never an endless lock")


## Reproducibility guarantee (docs/ARCHITECTURE.md): the same build, seed and input stream give
## identical results in a fresh process stepped at a fixed rate (--fixed-fps), which is how
## replays, AI Lab workers and headless verification run. Verified with independent processes.
func test_fixed_step_runs_are_reproducible_across_processes() -> void:
	var exe := OS.get_executable_path()
	var outs := []
	for k in 2:
		var out := []
		# an exported build carries its own game data; the editor binary needs --path
		var pre := [] if OS.has_feature("template") else ["--path", ProjectSettings.globalize_path("res://")]
		# its own user root: a test process must never touch the player's real profile
		var code := OS.execute(exe, ["--headless"] + pre + ["--fixed-fps", "120", "--", "--probe", "spar", "--user-root", temp_dir("probe_spar")], out, true)
		check_eq(code, 0, "probe process exit code")
		var lines := []
		for chunk in out:
			for line in str(chunk).split("
"):
				if line.contains("s f0") or line.contains("s f1") or line.begins_with("PROBE"):
					lines.append(line.strip_edges())
		outs.append("
".join(lines))
	check(str(outs[0]).length() > 200, "probe produced a trace")
	check_eq(outs[0], outs[1], "identical traces")

