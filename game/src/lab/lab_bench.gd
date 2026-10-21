class_name LabBench
extends Node
## Reproducible AI Lab measurements (docs/AI_LAB.md "Measurements"):
##   <game> --headless --fixed-fps 120 -- --lab-worker --lab-bench inference [--lab-out file.json]
##     8 policy-controlled fighters in one real match for 4 simulated seconds: per-decision cost
##     (observation + network + action choice) and the amortised cost per physics tick.
##   <game> --headless --fixed-fps 120 -- --lab-worker --lab-bench throughput [--lab-out file.json]
##     policy-vs-bot training episodes through LabRunner for 30 wall seconds: simulated seconds
##     per wall second and episodes per hour for ONE worker process.

var mode := ""
var out_path := ""
var sim: MatchSim
var sources: Array = []
var ticks := 0
var max_ticks := 480
var runner: LabRunner
var t0_ms := 0
var hidden := PackedInt32Array([32, 32])


func run(p_mode: String, p_out: String) -> void:
	mode = p_mode
	out_path = p_out
	if mode == "throughput":
		_start_throughput()
	else:
		_start_inference()


func _start_inference() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--hidden")
	if i >= 0 and i + 1 < args.size():
		hidden = PackedInt32Array()
		for h in args[i + 1].split(","):
			hidden.append(int(h))
	var c := Content.creature("dev_biped")
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sv)
	sim = MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	var fighters := []
	for k in 8:
		var p := PolicyData.create_new("dev_biped", hidden, "tanh", 100 + k)
		var src := PolicyInputSource.create(p, k + 1, k)
		sources.append(src)
		fighters.append({"creature": c, "team": k, "source": src})
	sim.setup({"arena": ArenaDef.from_dict({"id": "bench", "base": "octagon", "radius": 6.0}), "rules": {"rounds": 1, "round_time": 0, "combat": "classic"}, "seed": 5, "fighters": fighters})
	sim.mode.phase = MatchMode.Phase.FIGHT
	sim.input_enabled = true
	set_physics_process(true)


func _start_throughput() -> void:
	runner = LabRunner.new()
	runner.max_worlds = int(_arg("--worlds", "2"))
	add_child(runner)
	var p := PolicyData.create_new("dev_biped", hidden, "tanh", 7)
	var payload := {"arch": {"hidden": Array(hidden), "activation": "tanh"}, "meta": {"creature": "dev_biped", "mode": "argmax"},
		"params": {"theta": LabIO.b64_floats(p.net.params)}}
	runner.resolver = LabBatch.resolver_for(payload)
	var scn: Dictionary = LabScenarios.PRESETS["spar_jabber"].duplicate(true)
	scn["round_time"] = 10.0
	var items := []
	for k in 400:
		items.append({"i": k, "policy": {"key": "theta"}, "episode": LabScenarios.episode(scn, "bot_regular" if k % 2 == 0 else "jabber", 1000 + k, "dev_biped", "dev_biped")})
	runner.add_items(items)
	t0_ms = Time.get_ticks_msec()
	set_physics_process(true)


func _arg(flag: String, fallback: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else fallback


func _physics_process(dt: float) -> void:
	if mode == "throughput":
		runner.step(dt)
		var wall := float(Time.get_ticks_msec() - t0_ms) / 1000.0
		if wall >= 30.0 or not runner.busy():
			var sim_s := float(runner.sim_ticks) / float(Engine.physics_ticks_per_second)
			_report({"bench": "throughput", "worlds": runner.max_worlds, "wall_s": wall, "episodes": runner.episodes_done,
				"world_sim_seconds": sim_s, "sim_speed_total": sim_s / wall, "episodes_per_hour": float(runner.episodes_done) / wall * 3600.0,
				"processor_count": OS.get_processor_count(), "note": "one worker process; total throughput scales with worker processes"})
		return
	sim.step(dt)
	ticks += 1
	if ticks >= max_ticks:
		var total := 0
		var decisions := 0
		var mx := 0
		var enc := 0
		var fwd := 0
		for s: PolicyInputSource in sources:
			total += s.total_usec
			decisions += s.decisions
			mx = maxi(mx, s.max_usec)
			enc += s.encode_usec
			fwd += s.forward_usec
		var nd := float(maxi(decisions, 1))
		_report({"bench": "inference", "fighters": sources.size(), "hidden": Array(hidden), "params": (sources[0] as PolicyInputSource).net.params.size(),
			"ticks": ticks, "decisions": decisions, "mean_decision_us": float(total) / nd, "mean_encode_us": float(enc) / nd,
			"mean_forward_us": float(fwd) / nd, "max_decision_us": mx,
			"per_tick_us_8_fighters": float(total) / float(ticks), "decision_hz": PolicyActions.DEFAULT_DECISION_HZ})


func _report(d: Dictionary) -> void:
	set_physics_process(false)
	var text := JSON.stringify(d, "  ")
	print("LAB_BENCH ", text)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	get_tree().quit(0)
