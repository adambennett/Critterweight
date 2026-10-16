extends TestCase
## NET-03 / PERF-04 measurements (LOOPBACK, one machine): bandwidth per client and server cost
## per tick for a 2-fighter duel and an 8-fighter free-for-all (bots fill), with one human client
## connected through the conditioner relay at 1 ms (its byte counters see every UDP datagram, so
## the numbers are exact UDP payload; add 28 B per packet for IPv4+UDP headers on the wire).
## Writes captures/tests/net/measure_<name>/report.json and prints a summary line per scenario.

const U := preload("res://src/test/net/net_test_util.gd")
const SOAK := preload("res://src/test/net/test_net_soak.gd")

var u = null


func after_each() -> void:
	if u:
		u.kill_all()
	u = null


func _measure(name_: String, rules: String, fighters: int, seconds: float) -> Dictionary:
	u = U.new(self, "measure_" + name_)
	var port: int = u.base_port
	var entry := {"id": name_, "rules": rules, "arena": "the_gullet", "weight": 1, "rules_override": {"rounds": 1, "round_time": 300}}
	if fighters > 2:
		entry["min_players"] = fighters
	var pl: String = u.playlist("m.json", [entry], {"voting": {"enabled": false, "candidates": 1}})
	var cfg: String = u.write_cfg("srv.cfg", u.server_sections(port, {"server": {"stats_interval": 5},
		"match": {"playlist": pl, "lobby_time": 3, "bots": "true", "bot_difficulty": "pro"}}))
	# packaged: measure the dedicated server package itself (its own engine settings), not the game
	var srv_exe: String = U.server_package_exe()
	var srv: int = u.spawn("srv", ["--server", "--config", cfg], false, srv_exe)
	check(await u.wait_until(func() -> bool: return u.out(srv).contains("ready:"), U.SERVER_READY_S), "server ready")
	var cli: int = u.spawn("probe", u.client_args(port, "Probe", "wander", ["--ready", "--present", "--net-latency", "1",
		"--quit-after", str(int(seconds + 40))]))
	var status_path: String = u.path("srv").path_join("server").path_join("status.json")
	# wait for the fight phase, then measure a window
	check(await u.wait_until(func() -> bool: return int(U.read_json(status_path).get("tick", 0)) > 400, 30.0), "match running")
	# the probe replaces its result file every second: poll, never trust one read
	var has_counters := func(d: Dictionary) -> bool: return d.get("stats", {}).has("conditioner")
	var r0: Dictionary = await u.wait_json(u.result_path("Probe"), has_counters, 5.0)
	var c0: Dictionary = r0.get("stats", {}).get("conditioner", {})
	var p0 := SOAK.proc_usage(srv)
	var st0: Dictionary = U.read_json(status_path)
	var t0 := Time.get_ticks_msec()
	var sim_samples: Array = []
	var phys_samples: Array = []
	while (Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await u.sleep(1.0)
		var st: Dictionary = U.read_json(status_path)
		if float(st.get("tick_ms_avg_1s", 0.0)) > 0.0:
			sim_samples.append(float(st.get("tick_ms_avg_1s", 0.0)))
			phys_samples.append(float(st.get("physics_frame_max_ms", 0.0)))
	var span := (Time.get_ticks_msec() - t0) / 1000.0
	var r1: Dictionary = await u.wait_json(u.result_path("Probe"), has_counters, 5.0)
	var c1: Dictionary = r1.get("stats", {}).get("conditioner", {})
	var p1 := SOAK.proc_usage(srv)
	var st1: Dictionary = U.read_json(status_path)
	var down_b := float(int(c1.get("down_bytes", 0)) - int(c0.get("down_bytes", 0)))
	var up_b := float(int(c1.get("up_bytes", 0)) - int(c0.get("up_bytes", 0)))
	var down_p := float(int(c1.get("down", 0)) - int(c0.get("down", 0)))
	var up_p := float(int(c1.get("up", 0)) - int(c0.get("up", 0)))
	var sim_avg := 0.0
	for s in sim_samples:
		sim_avg += float(s)
	sim_avg /= maxf(1.0, sim_samples.size())
	var phys_avg := 0.0
	for s in phys_samples:
		phys_avg += float(s)
	phys_avg /= maxf(1.0, phys_samples.size())
	var cpu := 0.0
	if not p0.is_empty() and not p1.is_empty():
		cpu = (float(p1["cpu_s"]) - float(p0["cpu_s"])) / span * 100.0
	# the server's main-thread load from its own frame pacing (exact for short bursts of work,
	# which sampled OS CPU accounting under-counts); the status file is rewritten every 5 s
	var busy := -1.0
	var dwall := float(st1.get("paced_wall_us", 0)) - float(st0.get("paced_wall_us", 0))
	if dwall >= 5e6:
		busy = 100.0 * (1.0 - (float(st1.get("paced_sleep_us", 0)) - float(st0.get("paced_sleep_us", 0))) / dwall)
	var rep := {"label": "LOOPBACK on one machine (i7-7700K, Windows 10), one human client + bots", "scenario": name_,
		"server_binary": srv_exe.get_file() if srv_exe != "" else "game executable with --server",
		"rules": rules, "fighters": int(st1.get("fighters", 0)), "window_s": span,
		"down_kBps_payload": down_b / span / 1024.0, "up_kBps_payload": up_b / span / 1024.0,
		"down_kBps_wire_ipv4": (down_b + 28.0 * down_p) / span / 1024.0, "up_kBps_wire_ipv4": (up_b + 28.0 * up_p) / span / 1024.0,
		"down_packets_per_s": down_p / span, "up_packets_per_s": up_p / span,
		"snapshot_bytes_avg": float(st1.get("snapshot_bytes_avg", 0.0)), "last_snapshot_size": int(st1.get("last_snapshot_size", 0)),
		"server_sim_ms_per_tick_avg": sim_avg, "server_physics_frame_max_ms_avg": phys_avg,
		"server_net_ms_per_tick_avg": float(st1.get("net_ms_avg", 0.0)), "server_net_ms_per_tick_max": float(st1.get("net_ms_max", 0.0)),
		"server_cpu_percent_one_core": cpu, "server_main_thread_busy_percent": busy, "server_mem_static_mb": float(st1.get("mem_static_mb", 0.0)),
		"client_snapshot_rate": float(r1.get("stats", {}).get("snapshot_rate", 0.0)),
		"client_interp_ms": float(r1.get("stats", {}).get("interp_delay_ms", 0.0))}
	u.write_json("report.json", rep)
	print("    MEASURE %s (LOOPBACK, %d fighters, %.0f s): per client down %.1f KB/s (wire %.1f), up %.1f KB/s (wire %.1f), %.0f/%.0f pkt/s; snapshot %d B; server sim %.2f ms/tick, net %.3f ms/tick, longest physics frame %.2f ms (avg of 1 s maxima), main thread busy %.1f%%, process CPU %.1f%% of one core (%s)" % [
		name_, int(rep["fighters"]), span, rep["down_kBps_payload"], rep["down_kBps_wire_ipv4"], rep["up_kBps_payload"], rep["up_kBps_wire_ipv4"],
		rep["down_packets_per_s"], rep["up_packets_per_s"], int(rep["last_snapshot_size"]), sim_avg, float(rep["server_net_ms_per_tick_avg"]), phys_avg, busy, cpu,
		rep["server_binary"]])
	var errs: Array = u.errors(srv) + u.errors(cli)
	check(errs.is_empty(), "no errors: %s" % str(errs.slice(0, 5)))
	return rep


func test_measure_duel_and_ffa8() -> void:
	var duel := await _measure("duel", "duel", 2, 20.0)
	check_eq(int(duel.get("fighters", 0)), 2, "duel has 2 fighters")
	check(float(duel["down_kBps_wire_ipv4"]) < 20.0, "duel downstream under 20 KB/s per client")
	check(float(duel["up_kBps_wire_ipv4"]) < 8.0, "duel upstream under 8 KB/s per client")
	u.kill_all()
	var ffa := await _measure("ffa8", "free_for_all", 8, 20.0)
	check_eq(int(ffa.get("fighters", 0)), 8, "8 fighters")
	check(float(ffa["down_kBps_wire_ipv4"]) < 60.0, "8-fighter downstream under 60 KB/s per client")
	# hard limit: the server keeps real time (simulation + networking inside one 120 Hz tick). The
	# quiet-machine figure (2.9-3.7 ms simulation, docs/NETWORKING.md §15) is a reference, not a
	# pass mark: other processes on a shared test machine inflate wall-clock tick times (4.4 ms was
	# seen with the CPU at 100 % from parallel jobs), so it is reported instead of asserted.
	var tick_ms := float(ffa["server_sim_ms_per_tick_avg"]) + float(ffa["server_net_ms_per_tick_avg"])
	check(tick_ms < 1000.0 / 120.0, "8-fighter server keeps real time (%.2f ms of the 8.33 ms tick)" % tick_ms)
	if float(ffa["server_sim_ms_per_tick_avg"]) > 4.0:
		print("    NOTE: 8-fighter simulation %.2f ms/tick is above the 4 ms quiet-machine reference (machine busy?)" % float(ffa["server_sim_ms_per_tick_avg"]))
