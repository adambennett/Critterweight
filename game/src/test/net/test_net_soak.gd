extends TestCase
## VER-05 / NET-09 soak (LOOPBACK): a dedicated server runs a playlist with bot fill for a long
## time while one scripted fighter and one presenting spectator stay connected. Every 15 s the
## test samples the server's own status (static memory, objects, nodes, orphans, matches) and
## the OS view of the process (working set, CPU time), plus log sizes, then checks for bounded
## growth and writes a report (captures/tests/net/soak/soak_report.json).
## Duration: `--soak-minutes N` on the test command line (default 2; the requirement-level soak
## is `-- --test net_soak --soak-minutes 10`).

const U := preload("res://src/test/net/net_test_util.gd")

var u = null


func after_each() -> void:
	if u:
		u.kill_all()
	u = null


func _arg(flag: String, fallback: String) -> String:
	var a := OS.get_cmdline_user_args()
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else fallback


## OS-level memory (MB) and CPU time (s) of a process.
static func proc_usage(pid: int) -> Dictionary:
	if OS.get_name() == "Windows":
		var out: Array = []
		var code := OS.execute("powershell", ["-NoProfile", "-Command",
			"$p = Get-Process -Id %d -ErrorAction SilentlyContinue; if ($p) { '{0} {1} {2}' -f $p.WorkingSet64, $p.PrivateMemorySize64, $p.TotalProcessorTime.TotalSeconds }" % pid], out)
		if code == 0 and not out.is_empty():
			var parts := str(out[0]).strip_edges().split(" ", false)
			if parts.size() == 3:
				return {"ws_mb": float(parts[0]) / 1048576.0, "private_mb": float(parts[1]) / 1048576.0, "cpu_s": float(parts[2].replace(",", "."))}
	elif FileAccess.file_exists("/proc/%d/status" % pid):
		var st := FileAccess.get_file_as_string("/proc/%d/status" % pid)
		var rss := 0.0
		for line in st.split("\n"):
			if line.begins_with("VmRSS:"):
				rss = float(line.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
		var stat := FileAccess.get_file_as_string("/proc/%d/stat" % pid).split(" ")
		var ticks := float(stat[13]) + float(stat[14]) if stat.size() > 15 else 0.0
		return {"ws_mb": rss, "private_mb": rss, "cpu_s": ticks / 100.0}
	return {}


func _slope(xs: Array, ys: Array) -> float:
	var n := xs.size()
	if n < 2:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx += float(xs[i])
		my += float(ys[i])
	mx /= n
	my /= n
	var num := 0.0
	var den := 0.0
	for i in n:
		num += (float(xs[i]) - mx) * (float(ys[i]) - my)
		den += (float(xs[i]) - mx) * (float(xs[i]) - mx)
	return num / den if den > 0.0 else 0.0


func test_soak_server_with_bots() -> void:
	var minutes := float(_arg("--soak-minutes", "2"))
	var seconds := minutes * 60.0
	u = U.new(self, "soak")
	var port: int = u.base_port
	var pl: String = u.playlist("soak.json", [
		{"id": "s_duel", "rules": "duel", "arena": "the_gullet", "weight": 2, "rules_override": {"rounds": 1, "round_time": 30}},
		{"id": "s_ffa", "rules": "free_for_all", "arena": "the_gullet", "weight": 2, "min_players": 4, "rules_override": {"round_time": 30}},
		{"id": "s_teams", "rules": "teams_2v2", "arena": "the_gullet", "weight": 1, "rules_override": {"rounds": 1, "round_time": 30}},
		{"id": "s_hog", "rules": "spotlight_hog", "arena": "the_gullet", "weight": 1, "min_players": 4, "rules_override": {"round_time": 35}},
		{"id": "s_rush", "rules": "chum_rush", "arena": "the_gullet", "weight": 1, "bots": 0, "rules_override": {"round_time": 35}}],
		{"voting": {"enabled": true, "candidates": 3}, "repeat_avoidance": 1})
	var cfg: String = u.write_cfg("srv.cfg", u.server_sections(port, {"server": {"stats_interval": 30},
		"match": {"playlist": pl, "lobby_time": 5, "results_time": 3, "empty_behavior": "showcase"}}))
	var srv: int = u.spawn("srv", ["--server", "--config", cfg])
	check(await u.wait_until(func() -> bool: return u.out(srv).contains("ready:"), U.SERVER_READY_S), "server ready")
	var q := str(int(seconds + 60))
	var fighter: int = u.spawn("fighter", u.client_args(port, "Grinder", "wander", ["--ready", "--vote", "0", "--quit-after", q]))
	var watcher: int = u.spawn("watcher", u.client_args(port, "Watcher", "idle", ["--spectate", "--present", "--quit-after", q]))
	var status_path: String = u.path("srv").path_join("server").path_join("status.json")
	var samples: Array = []
	var t0 := Time.get_ticks_msec()
	var next := 0.0
	while true:
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if t >= seconds:
			break
		if t >= next:
			next += 15.0
			var st: Dictionary = U.read_json(status_path)
			var pu := proc_usage(srv)
			var cu := proc_usage(watcher)
			var log_size := 0
			var log_files := 0
			var ld := DirAccess.open(u.path("srv").path_join("logs"))
			if ld:
				for f in ld.get_files():
					log_files += 1
					log_size += FileAccess.get_file_as_bytes(u.path("srv").path_join("logs").path_join(f)).size()
			samples.append({"t": t, "mem_static_mb": float(st.get("mem_static_mb", 0)), "objects": int(st.get("objects", 0)),
				"nodes": int(st.get("nodes", 0)), "orphans": int(st.get("orphans", 0)), "matches": int(st.get("matches_played", 0)),
				"phase": str(st.get("phase", "")), "out_kbps": float(st.get("out_kbps", 0)), "in_kbps": float(st.get("in_kbps", 0)),
				"sim_ms_1s": float(st.get("tick_ms_avg_1s", 0)), "ws_mb": float(pu.get("ws_mb", 0)), "private_mb": float(pu.get("private_mb", 0)),
				"cpu_s": float(pu.get("cpu_s", 0)), "client_ws_mb": float(cu.get("ws_mb", 0)), "log_bytes": log_size, "log_files": log_files})
		await u.sleep(1.0)
		if not u.running(srv):
			break
	check(u.running(srv), "server survived the soak")
	check(u.running(fighter) and u.running(watcher), "clients stayed connected")
	await u.shutdown_server(port)
	var exited: bool = await u.wait_exit(srv, 15.0)
	check(exited, "graceful shutdown after the soak")
	# trends over the second half (after warm-up)
	var half := samples.filter(func(s): return float(s["t"]) >= seconds * 0.5)
	var xs := half.map(func(s): return float(s["t"]) / 60.0)
	var mem_slope := _slope(xs, half.map(func(s): return float(s["mem_static_mb"])))
	var ws_slope := _slope(xs, half.map(func(s): return float(s["ws_mb"])))
	var first: Dictionary = samples[0] if not samples.is_empty() else {}
	var last: Dictionary = samples[-1] if not samples.is_empty() else {}
	var cpu_pct := 0.0
	if samples.size() >= 2 and float(last.get("t", 0)) > float(first.get("t", 0)):
		cpu_pct = (float(last["cpu_s"]) - float(first["cpu_s"])) / (float(last["t"]) - float(first["t"])) * 100.0
	# log files after the graceful exit (on-disk sizes lag while the server runs: INFO is buffered)
	var final_log_bytes := 0
	var final_log_files := 0
	var fld := DirAccess.open(u.path("srv").path_join("logs"))
	if fld:
		for f in fld.get_files():
			final_log_files += 1
			final_log_bytes += FileAccess.get_file_as_bytes(u.path("srv").path_join("logs").path_join(f)).size()
	last["log_bytes"] = final_log_bytes
	last["log_files"] = final_log_files
	var report := {"label": "LOOPBACK soak on one machine (i7-7700K, Windows 10)", "minutes": minutes, "samples": samples,
		"server_static_mem_slope_mb_per_min": mem_slope, "server_ws_slope_mb_per_min": ws_slope,
		"server_cpu_percent_of_one_core": cpu_pct, "matches_played": int(last.get("matches", 0)),
		"server_exit_code": u.exit_code(srv) if exited else -1}
	u.write_json("soak_report.json", report)
	print("    SOAK (LOOPBACK, %.1f min): matches %d, static mem %.1f -> %.1f MB (slope %.2f MB/min, 2nd half), working set %.0f -> %.0f MB (slope %.2f MB/min), server CPU %.1f%% of one core, logs %d B in %d files" % [
		minutes, int(last.get("matches", 0)), float(first.get("mem_static_mb", 0)), float(last.get("mem_static_mb", 0)), mem_slope,
		float(first.get("ws_mb", 0)), float(last.get("ws_mb", 0)), ws_slope, cpu_pct, int(last.get("log_bytes", 0)), int(last.get("log_files", 0))])
	print("    report: %s" % u.path("soak_report.json"))
	check(int(last.get("matches", 0)) >= maxi(1, int(minutes * 1.2)), "matches kept rotating (%d)" % int(last.get("matches", 0)))
	# a leak keeps climbing; a first-time load (a new arena or kit in a later match) is one step. The short
	# default soak sees a single minute of trend, where one ~1 MB step reads as >1 MB/min, so short soaks
	# also accept a small total rise. Longer soaks (the 10-minute evidence run) keep the slope rule alone.
	var half_rise := float(half[-1]["mem_static_mb"]) - float(half[0]["mem_static_mb"]) if half.size() >= 2 else 0.0
	check(mem_slope < 1.0 or (minutes <= 3.0 and half_rise < 1.5),
		"server static memory not growing (%.2f MB/min, %.2f MB over the second half)" % [mem_slope, half_rise])
	check(int(last.get("orphans", 0)) <= int(first.get("orphans", 0)) + 5, "no orphan node build-up")
	check(int(last.get("log_bytes", 0)) <= 3 * 2 * 1024 * 1024 + 65536 and int(last.get("log_files", 0)) <= 3, "logs bounded by rotation")
	for pid in [srv, fighter, watcher]:
		var errs: Array = u.errors(pid)
		check(errs.is_empty(), "process %d printed no errors: %s" % [pid, str(errs.slice(0, 5))])
