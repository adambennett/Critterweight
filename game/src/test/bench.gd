extends Node
## Performance captures (PERF-01..05, VER-05). Writes a JSON report and prints a summary.
##
##   -- --bench busy   [--n 8] [--duration 30] [--warmup 5] [--preset high] [--out file.json]
##        rendered match with N pro bots (FFA, lives) in the primary cage: frame-time
##        distribution, physics/process time, draw calls, memory, match load time
##        [--abilities-every s]: every s seconds all fighters use an ability at once (cycling
##        ability 1, ability 2, JUICE; cooldowns and hype refilled) for crowded-effects captures
##   -- --bench duel   same with 2 fighters
##   -- --bench sim    [--n 8] [--duration 60]: headless authoritative simulation cost per tick
##        (dedicated-server capacity), no rendering
##   -- --bench soak   [--matches 20]: back-to-back headless matches; memory/object trend
##   -- --bench client_soak [--matches 16] [--match-seconds 40] [--speed 4]: presented matches
##        back to back (rendering, HUD, VFX, audio, arenas) left the way the app leaves them;
##        memory, objects, nodes, orphan nodes and video memory after each (run windowed)
##   -- --bench roster [--bouts 4] [--tier pro] [--round 60]: bot round robin between the
##        playable fighters (win rates, hits/min, damage per hit) for balance and size checks
##   -- --bench commentary --out <json> [--label x] [--sequence 1|0] [--start-bout k] [--bouts n]:
##        the commentary audit (src/test/audio/commentary_audit.gd); headless, real time
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
		"client_soak":
			await _client_soak(int(_arg("--matches", "16")), float(_arg("--match-seconds", "40")))
		"roster":
			await _roster(int(_arg("--bouts", "4")), _arg("--tier", "pro"), float(_arg("--round", "60")))
		"tiers":
			await _tiers(int(_arg("--bouts", "12")), float(_arg("--round", "60")))
		"commentary":
			# the commentary audit (docs/audio/COMMENTARY.md) writes its own log and quits
			var audit = load("res://src/test/audio/commentary_audit.gd").new()
			add_child(audit)
			await audit.run(args)
			return
		_:
			print("unknown bench '%s' (busy, duel, sim, soak, client_soak, roster, tiers)" % scene)
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
	var every := float(_arg("--abilities-every", "0"))
	report["abilities_every_s"] = every
	var next_burst := Time.get_ticks_msec()
	var burst_k := 0
	var bursts := 0
	while Time.get_ticks_msec() < t_end:
		if every > 0.0 and Time.get_ticks_msec() >= next_burst:
			next_burst += int(every * 1000.0)
			_all_use_ability(scene.sim, burst_k)
			burst_k += 1
			bursts += 1
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
	report["ability_bursts"] = bursts
	report["hits"] = scene.sim.events.filter(func(e): return e["type"] == "hit").size()


## Crowded-effects load: every fighter presses the same ability at once (cycle k: ability 1,
## ability 2, JUICE), with cooldowns, charges, stamina and hype refilled so the press fires.
static func _all_use_ability(sim: MatchSim, k: int) -> void:
	var button: int = [FighterInput.AB1, FighterInput.AB2, FighterInput.JUICE][k % 3]
	for f in sim.fighters:
		if f.is_out():
			continue
		f.cooldown_left.clear()
		for slot in f.creature.abilities:
			f.charges_left[slot] = int(f.creature.ability_charges.get(slot, 1))
		f.stamina = f.max_stamina
		if button == FighterInput.JUICE:
			f.hype = 100.0
		f.input.press(button)


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
	var cpu0 := process_cpu_ms()
	var wall0 := Time.get_ticks_usec()
	for k in ticks:
		var a := Time.get_ticks_usec()
		sim.step(dt)
		var b := Time.get_ticks_usec()
		step_ms.append((b - a) / 1000.0)
		await get_tree().physics_frame
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var wall := (Time.get_ticks_usec() - wall0) / 1e6
	var cpu1 := process_cpu_ms()
	report["sim_seconds"] = dur
	report["wall_seconds"] = wall
	report["realtime_factor"] = dur / maxf(wall, 1e-6)
	report["sim_logic_ms_per_tick"] = _stats(step_ms)
	# TIME_PHYSICS_PROCESS is the engine's worst physics frame of each second (and includes the
	# sim step, which runs inside the physics frame): informative only, never added to the cost
	report["physics_frame_max_ms"] = _stats(phys_ms)
	report["hits"] = sim.events.filter(func(e): return e["type"] == "hit").size()
	report["memory_static_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	# the loop runs flat out (--fixed-fps), so wall time per tick is everything one tick costs on
	# the main thread; process CPU time also counts the physics worker threads
	report["wall_ms_per_tick"] = wall * 1000.0 / maxf(1.0, ticks)
	report["wall_core_share_at_120hz_pct"] = float(report["wall_ms_per_tick"]) * 120.0 / 10.0
	if cpu0 >= 0.0 and cpu1 >= cpu0:
		report["cpu_ms_per_tick"] = (cpu1 - cpu0) / maxf(1.0, ticks)
		report["cpu_core_share_at_120hz_pct"] = float(report["cpu_ms_per_tick"]) * 120.0 / 10.0
	report["core_share_at_120hz_pct"] = report.get("cpu_core_share_at_120hz_pct", report["wall_core_share_at_120hz_pct"])
	report["core_share_target_pct"] = 35.0
	report["state_hash"] = state_hash(sim)
	var sections := {}
	var nt := maxf(1.0, float(sim.prof.get("ticks", 1.0)))
	for k in sim.prof:
		if k != "ticks":
			sections[k] = snappedf(float(sim.prof[k]) / nt / 1000.0, 0.001)
	report["section_ms_per_tick"] = sections
	sv.queue_free()


## Client soak (VER-05): presented matches back to back through App.start_match, as a player sees
## them (rendering, HUD, VFX, audio, camera, arena dressing), rotating arenas and duel/FFA rules,
## each left the way the app leaves a match. A leak shows as a steady climb in the per-match series;
## the slope is taken over the second half, after caches and pools have warmed up.
func _client_soak(matches: int, seconds: float) -> void:
	var arenas := ["the_gullet", "arena_crusher", "arena_drydock", "arena_rooftop"]
	var series := {"memory_mb": [], "objects": [], "nodes": [], "orphan_nodes": [], "video_mb": []}
	var speed := float(_arg("--speed", "4"))
	var t0 := Time.get_ticks_msec()
	for m in matches:
		var n := 2 if m % 2 == 0 else 4
		SimSpeed.set_scale(speed)
		var scene := App.start_match({"arena": arenas[m % arenas.size()], "rules": "duel" if n == 2 else "free_for_all_lives",
			"seed": 100 + m, "fighters": _fighters(n)})
		await get_tree().create_timer(seconds / speed, true, false, true).timeout
		if is_instance_valid(scene):
			App.set_scene(null)
		App.goto("main_menu", {})
		for i in 8:
			await get_tree().process_frame
		series["memory_mb"].append(snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.01))
		series["objects"].append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
		series["nodes"].append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		series["orphan_nodes"].append(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
		series["video_mb"].append(snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.01))
		print("client soak %d/%d: %s" % [m + 1, matches, JSON.stringify(series.keys().map(func(k): return "%s=%s" % [k, series[k][-1]]))])
	SimSpeed.set_scale(1.0)
	report["matches"] = matches
	report["match_seconds"] = seconds
	report["speed"] = speed
	report["series"] = series
	var half := matches / 2
	for k in series:
		var arr: Array = series[k]
		report["%s_growth_first_to_last" % k] = float(arr[-1]) - float(arr[0])
		report["%s_per_match_second_half" % k] = (float(arr[-1]) - float(arr[half])) / maxf(1.0, float(arr.size() - 1 - half))
	report["wall_seconds"] = (Time.get_ticks_msec() - t0) / 1000.0


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
	# --pair a,b plays one pairing only (e.g. --pair f_dredge,f_slurry)
	var only := _arg("--pair", "").split(",", false)
	for a_i in ids.size():
		for b_i in range(a_i, ids.size()):
			var a := str(ids[a_i])
			var b := str(ids[b_i])
			if only.size() == 2 and not ((a == only[0] and b == only[1]) or (a == only[1] and b == only[0])):
				continue
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


## Bot skill ladder (AI-01): each tier against the one below, plus Punching Bag against
## Hall-of-Famer. Mirror matches cycle through the roster (fighter strength cancels out) and the
## sides alternate; the higher tier should win clearly more often.
func _tiers(bouts: int, round_time: float) -> void:
	var ids := Content.playable_creatures().filter(func(c): return not str(c).begins_with("dev_"))
	if ids.is_empty():
		ids = ["dev_biped"]
	var tiers := BotTiers.ids()
	var pairs := []
	for i in tiers.size() - 1:
		pairs.append([tiers[i], tiers[i + 1]])
	pairs.append([tiers[0], tiers[tiers.size() - 1]])
	# --pair lower,higher measures one rung only (e.g. --pair headliner,hall_of_famer)
	var only := _arg("--pair", "").split(",", false)
	if only.size() == 2:
		pairs = [[only[0], only[1]]]
	var dt := 1.0 / Engine.physics_ticks_per_second
	var out := {}
	for pi in pairs.size():
		var lo := str(pairs[pi][0])
		var hi := str(pairs[pi][1])
		var rec := {"higher_wins": 0, "lower_wins": 0, "draws": 0}
		for k in bouts:
			var cid := str(ids[k % ids.size()])
			var c := Content.creature(cid)
			var hi_team := k % 2
			var entries := []
			for team in 2:
				var tier := hi if team == hi_team else lo
				var brain := BotBrain.new(BotTiers.brain_tier(tier), 3000 + k * 2 + team + pi * 100)
				brain.set_personality(c.ai)
				entries.append({"creature": c, "team": team, "source": brain, "kind": "bot"})
			var sv := SubViewport.new()
			sv.own_world_3d = true
			sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(sv)
			var sim := MatchSim.new()
			sim.running = false
			sv.add_child(sim)
			if not Engine.is_in_physics_frame():
				await get_tree().physics_frame
			sim.setup({"arena": Content.arena("the_gullet"), "rules": {"mode": "standard", "rounds": 1, "round_time": round_time},
				"seed": 70 + k * 13 + pi * 5, "fighters": entries, "mode": ModeRegistry.create("standard")})
			var t := 0.0
			while t < round_time + 8.0 and not sim.is_finished:
				sim.step(dt)
				t += dt
				await get_tree().physics_frame
			var wt := int(sim.result.get("winner_team", -1)) if sim.is_finished else -1
			if wt < 0:
				rec["draws"] = int(rec["draws"]) + 1
			elif wt == hi_team:
				rec["higher_wins"] = int(rec["higher_wins"]) + 1
			else:
				rec["lower_wins"] = int(rec["lower_wins"]) + 1
			sv.queue_free()
			await get_tree().process_frame
		var decided := maxi(1, int(rec["higher_wins"]) + int(rec["lower_wins"]))
		rec["higher_win_rate"] = snappedf(float(rec["higher_wins"]) / decided, 0.01)
		out["%s vs %s" % [hi, lo]] = rec
		print("tiers: %s vs %s -> %s" % [hi, lo, rec])
	report["bouts_per_pair"] = bouts
	report["round_time"] = round_time
	report["tiers"] = out


## Bit-exact fingerprint of a simulation's state (every body's transform and velocities, each
## fighter's health, state and lives, the event count): an optimisation that changes no behaviour
## leaves it unchanged for the same seed, duration and build settings.
static func state_hash(sim: MatchSim) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for f in sim.fighters:
		ctx.update(var_to_bytes([f.health, int(f.state), f.lives, f.despawned]))
		for rb in f.rig.bodies:
			ctx.update(var_to_bytes([rb.global_transform, rb.linear_velocity, rb.angular_velocity]))
	ctx.update(var_to_bytes([sim.events.size(), sim.tick_count]))
	return ctx.finish().hex_encode().substr(0, 16)


## CPU time this process has used so far, all threads, in ms (-1 when it cannot be read).
## Windows asks PowerShell (whole milliseconds, so no locale decimal separator); Linux reads
## utime + stime from /proc/self/stat (clock ticks, 100 per second).
static func process_cpu_ms() -> float:
	if OS.get_name() == "Windows":
		var out := []
		var code := OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command",
			"[int64](Get-Process -Id %d).TotalProcessorTime.TotalMilliseconds" % OS.get_process_id()], out, true)
		var s := str(out[0]).strip_edges() if not out.is_empty() else ""
		return s.to_float() if code == 0 and s.is_valid_int() else -1.0
	if FileAccess.file_exists("/proc/self/stat"):
		var stat := FileAccess.get_file_as_string("/proc/self/stat")
		var parts := stat.substr(stat.rfind(")") + 2).split(" ")
		# after "pid (comm) ": state is field 0, utime field 11, stime field 12
		if parts.size() > 12:
			return (parts[11].to_float() + parts[12].to_float()) * 10.0
	return -1.0


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
