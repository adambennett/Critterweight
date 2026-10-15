extends Node
## Performance captures (PERF-01..05, VER-05). Writes a JSON report and prints a summary.
##
##   -- --bench busy   [--n 8] [--duration 30] [--warmup 5] [--preset high] [--out file.json]
##        rendered match with N pro bots (FFA, lives) in the primary cage: frame-time
##        distribution, physics/process time, draw calls, memory, match load time
##   -- --bench duel   same with 2 fighters
##   -- --bench sim    [--n 8] [--duration 60]: headless authoritative simulation cost per tick
##        (dedicated-server capacity), no rendering
##   -- --bench soak   [--matches 20]: back-to-back headless matches; memory/object trend
##   -- --bench roster [--bouts 4] [--tier pro] [--round 60]: bot round robin between the
##        playable fighters (win rates, hits/min, damage per hit) for balance and size checks
##
## Rendered benches disable VSync and the frame cap so the numbers show real headroom; the
## "frames over 16.7 ms" figure is what matters for the 60 fps target.

var args: PackedStringArray
var report := {}


func run(scene: String, a: PackedStringArray) -> void:
	args = a
	report = {"bench": scene, "date": Time.get_datetime_string_from_system(), "game_version": Saves.game_version(),
		"engine": Engine.get_version_info()["string"], "os": OS.get_name(), "cpu": OS.get_processor_name(),
		"cores": OS.get_processor_count(), "renderer": RenderingServer.get_video_adapter_name(),
		"headless": DisplayServer.get_name() == "headless", "boot_ms": Time.get_ticks_msec()}
	match scene:
		"busy":
			await _rendered(int(_arg("--n", "8")))
		"duel":
			await _rendered(2)
		"sim":
			await _sim_cost(int(_arg("--n", "8")))
		"soak":
			await _soak(int(_arg("--matches", "20")))
		"roster":
			await _roster(int(_arg("--bouts", "4")), _arg("--tier", "pro"), float(_arg("--round", "60")))
		_:
			print("unknown bench '%s' (busy, duel, sim, soak)" % scene)
			get_tree().quit(2)
			return
	_finish()


func _arg(flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _fighters(n: int) -> Array:
	var ids := Content.playable_creatures().filter(func(c): return not str(c).begins_with("dev_"))
	if ids.is_empty():
		ids = Content.playable_creatures()
	var out := []
	for i in n:
		out.append({"creature": ids[i % ids.size()], "team": i, "kind": "bot", "difficulty": "pro", "name": "Bot %d" % i})
	return out


func _rendered(n: int) -> void:
	var preset := _arg("--preset", "")
	if preset != "":
		Settings.set_value("graphics.preset", preset, true, false)
	report["preset"] = str(Settings.values.get("graphics.preset", "?"))
	report["resolution"] = [get_window().size.x, get_window().size.y]
	report["fighters"] = n
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var t0 := Time.get_ticks_usec()
	var rules := "free_for_all_lives" if n > 2 else "duel"
	var scene := App.start_match({"arena": _arg("--arena", "the_gullet"), "rules": rules, "seed": 7, "fighters": _fighters(n)})
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	report["match_load_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	# keep everyone fighting for the whole capture
	scene.sim.rules["round_time"] = 0.0
	for f in scene.sim.fighters:
		f.lives = 99
	var warm := float(_arg("--warmup", "5"))
	var dur := float(_arg("--duration", "30"))
	await get_tree().create_timer(warm).timeout
	var frames := PackedFloat32Array()
	var phys := PackedFloat32Array()
	var proc := PackedFloat32Array()
	var draws := PackedInt32Array()
	var prims := PackedInt32Array()
	var mem_start := Performance.get_monitor(Performance.MEMORY_STATIC)
	var t_end := Time.get_ticks_msec() + int(dur * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	report["frame_ms"] = _stats(frames)
	report["fps_avg"] = 1000.0 / maxf(0.001, float(report["frame_ms"]["mean"]))
	var over := 0
	for v in frames:
		if v > 16.7:
			over += 1
	report["frames"] = frames.size()
	report["frames_over_16_7ms"] = over
	report["frames_over_16_7ms_pct"] = 100.0 * over / maxf(1.0, frames.size())
	report["physics_frame_ms"] = _stats(phys)
	report["process_frame_ms"] = _stats(proc)
	report["draw_calls"] = _stats(_to_f(draws))
	report["primitives"] = _stats(_to_f(prims))
	report["memory_static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	report["memory_growth_mb"] = (Performance.get_monitor(Performance.MEMORY_STATIC) - mem_start) / 1048576.0
	report["video_mem_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	report["objects"] = Performance.get_monitor(Performance.OBJECT_COUNT)
	report["process_rss_mb"] = OS.get_static_memory_usage() / 1048576.0
	report["alive_fighters_end"] = scene.sim.fighters.filter(func(f): return not f.is_out()).size()
	report["hits"] = scene.sim.events.filter(func(e): return e["type"] == "hit").size()


func _sim_cost(n: int) -> void:
	report["fighters"] = n
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sv.size = Vector2i(2, 2)
	add_child(sv)
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	var entries := []
	var fs := _fighters(n)
	for i in n:
		var c := Content.creature(str(fs[i]["creature"]))
		entries.append({"creature": c, "team": i, "source": BotBrain.new("pro", 100 + i), "kind": "bot"})
	var t0 := Time.get_ticks_usec()
	sim.profiling = true
	sim.setup({"arena": Content.arena("the_gullet"), "rules": {"mode": "standard", "round_time": 0.0, "lives": 99, "respawn": true, "respawn_delay": 2.0},
		"seed": 3, "fighters": entries, "mode": ModeRegistry.create("standard")})
	report["setup_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var dur := float(_arg("--duration", "60"))
	var ticks := int(dur / dt)
	var step_ms := PackedFloat32Array()
	var phys_ms := PackedFloat32Array()
	var wall0 := Time.get_ticks_usec()
	for k in ticks:
		var a := Time.get_ticks_usec()
		sim.step(dt)
		var b := Time.get_ticks_usec()
		step_ms.append((b - a) / 1000.0)
		await get_tree().physics_frame
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var wall := (Time.get_ticks_usec() - wall0) / 1e6
	report["sim_seconds"] = dur
	report["wall_seconds"] = wall
	report["realtime_factor"] = dur / maxf(wall, 1e-6)
	report["sim_logic_ms_per_tick"] = _stats(step_ms)
	report["physics_frame_ms"] = _stats(phys_ms)
	var per_tick := float(report["sim_logic_ms_per_tick"]["mean"]) + float(report["physics_frame_ms"]["mean"])
	report["estimated_core_share_at_120hz_pct"] = per_tick * 120.0 / 10.0
	report["hits"] = sim.events.filter(func(e): return e["type"] == "hit").size()
	report["memory_static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	report["wall_ms_per_tick"] = wall * 1000.0 / maxf(1.0, ticks)
	var sections := {}
	var nt := maxf(1.0, float(sim.prof.get("ticks", 1.0)))
	for k in sim.prof:
		if k != "ticks":
			sections[k] = snappedf(float(sim.prof[k]) / nt / 1000.0, 0.001)
	report["section_ms_per_tick"] = sections
	sv.queue_free()


func _soak(matches: int) -> void:
	var mem := []
	var objs := []
	var t0 := Time.get_ticks_msec()
	for m in matches:
		var sv := SubViewport.new()
		sv.own_world_3d = true
		sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(sv)
		var sim := MatchSim.new()
		sim.running = false
		sv.add_child(sim)
		var entries := []
		var fs := _fighters(4)
		for i in 4:
			entries.append({"creature": Content.creature(str(fs[i]["creature"])), "team": i, "source": BotBrain.new("regular", m * 10 + i), "kind": "bot"})
		sim.setup({"arena": Content.arena("the_gullet"), "rules": {"mode": "standard", "round_time": 45.0}, "seed": m, "fighters": entries, "mode": ModeRegistry.create("standard")})
		var dt := 1.0 / Engine.physics_ticks_per_second
		var t := 0.0
		while t < 50.0 and not sim.is_finished:
			sim.step(dt)
			t += dt
			await get_tree().physics_frame
		sv.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		mem.append(snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.01))
		objs.append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	report["matches"] = matches
	report["memory_mb_after_each"] = mem
	report["objects_after_each"] = objs
	report["memory_growth_mb_first_to_last"] = float(mem[-1]) - float(mem[0]) if mem.size() > 1 else 0.0
	report["object_growth_first_to_last"] = int(objs[-1]) - int(objs[0]) if objs.size() > 1 else 0
	report["wall_seconds"] = (Time.get_ticks_msec() - t0) / 1000.0


## Round robin between the playable fighters (bot vs bot, same tier, fixed step, headless):
## win rates, hits landed per minute, damage per hit, and how many melee moves connect —
## catches dominant/weak fighters and size mismatches where strikes whiff.
func _roster(bouts: int, tier: String, round_time: float) -> void:
	var ids := Content.playable_creatures().filter(func(c): return not str(c).begins_with("dev_"))
	var per := {}
	for id in ids:
		per[id] = {"wins": 0, "losses": 0, "draws": 0, "hits": 0, "damage": 0.0, "moves": 0, "seconds": 0.0}
	var pairs := {}
	var dt := 1.0 / Engine.physics_ticks_per_second
	for a_i in ids.size():
		for b_i in range(a_i, ids.size()):
			var a := str(ids[a_i])
			var b := str(ids[b_i])
			var pr := {"a_wins": 0, "b_wins": 0, "draws": 0}
			for k in bouts:
				var sv := SubViewport.new()
				sv.own_world_3d = true
				sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
				add_child(sv)
				var sim := MatchSim.new()
				sim.running = false
				sv.add_child(sim)
				# alternate sides so spawn position never decides a pairing
				var first := a if k % 2 == 0 else b
				var second := b if k % 2 == 0 else a
				var entries := [{"creature": Content.creature(first), "team": 0, "source": BotBrain.new(tier, 1000 + k), "kind": "bot"},
					{"creature": Content.creature(second), "team": 1, "source": BotBrain.new(tier, 2000 + k), "kind": "bot"}]
				(entries[0]["source"] as BotBrain).set_personality(Content.creature(first).ai)
				(entries[1]["source"] as BotBrain).set_personality(Content.creature(second).ai)
				sim.setup({"arena": Content.arena("the_gullet"), "rules": {"mode": "standard", "rounds": 1, "round_time": round_time},
					"seed": 50 + k * 7 + a_i * 31 + b_i, "fighters": entries, "mode": ModeRegistry.create("standard")})
				var t := 0.0
				while t < round_time + 8.0 and not sim.is_finished:
					sim.step(dt)
					t += dt
					await get_tree().physics_frame
				var wt := int(sim.result.get("winner_team", -1)) if sim.is_finished else -1
				var winner := first if wt == 0 else (second if wt == 1 else "")
				if winner == "":
					pr["draws"] += 1
				elif winner == a:
					pr["a_wins"] += 1
				else:
					pr["b_wins"] += 1
				for fi in 2:
					var f: Fighter = sim.fighters[fi]
					var rec: Dictionary = per[f.creature.id]
					rec["seconds"] = float(rec["seconds"]) + t
					rec["hits"] = int(rec["hits"]) + int(f.stats_record.get("hits", 0))
					rec["damage"] = float(rec["damage"]) + float(f.stats_record.get("damage_dealt", 0.0))
					rec["moves"] = int(rec["moves"]) + sim.events.filter(func(e): return e["type"] == "move_start" and int(e["fighter"]) == fi).size()
					if winner == "":
						rec["draws"] = int(rec["draws"]) + 1
					elif winner == f.creature.id and (a != b or wt == fi):
						rec["wins"] = int(rec["wins"]) + 1
					else:
						rec["losses"] = int(rec["losses"]) + 1
				sv.queue_free()
				await get_tree().process_frame
			pairs["%s vs %s" % [a, b]] = pr
	var summary := {}
	for id in per:
		var r: Dictionary = per[id]
		var games := maxi(1, int(r["wins"]) + int(r["losses"]) + int(r["draws"]))
		summary[id] = {"win_rate": snappedf(float(r["wins"]) / games, 0.01), "hits_per_min": snappedf(float(r["hits"]) / maxf(1.0, float(r["seconds"]) / 60.0), 0.1),
			"damage_per_hit": snappedf(float(r["damage"]) / maxf(1.0, float(r["hits"])), 0.1), "games": games}
	report["tier"] = tier
	report["bouts_per_pair"] = bouts
	report["pairs"] = pairs
	report["fighters"] = summary


static func _to_f(a: PackedInt32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in a:
		out.append(float(v))
	return out


static func _stats(a: PackedFloat32Array) -> Dictionary:
	if a.is_empty():
		return {"n": 0}
	var s := Array(a)
	s.sort()
	var sum := 0.0
	for v in s:
		sum += float(v)
	var pick := func(q: float) -> float: return float(s[clampi(int(round(q * (s.size() - 1))), 0, s.size() - 1)])
	return {"n": s.size(), "mean": snappedf(sum / s.size(), 0.001), "p50": snappedf(pick.call(0.5), 0.001),
		"p95": snappedf(pick.call(0.95), 0.001), "p99": snappedf(pick.call(0.99), 0.001),
		"min": snappedf(float(s[0]), 0.001), "max": snappedf(float(s[-1]), 0.001)}


func _finish() -> void:
	report["total_ms"] = Time.get_ticks_msec()
	var out := _arg("--out", Paths.dir("captures").path_join("bench_%s.json" % report["bench"]))
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("BENCH ", JSON.stringify(report))
	print("BENCH_REPORT ", out)
	get_tree().quit(0)
