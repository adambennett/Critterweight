class_name HubBench
extends Node
## Frame-time capture for THE CANNERY (docs/HUB_SYSTEMS.md §11). Walks the player through every
## space — placed at each arrival point, then walking that space's nav points in a loop while
## frames are sampled — with VSync and the frame cap off, so the numbers show real headroom.
##   godot --path game -- --hub --hub-bench [--bench-seconds 6] [--preset high] [--out file.json]
##         [--windowed --size 1920x1080]
## Prints "HUB_BENCH {json}", writes the report (default user://captures/bench_hub.json) and quits.
## The "frames over 16.7 ms" figure is what matters for the 60 fps target.

var scene: HubScene
var walker: Walker
var report := {}


## Walks the fighter around a loop of points (a stand-in for a player strolling through a room).
class Walker:
	extends InputSource
	var points: Array = []
	var index := 0
	var _best := INF
	var _since := 0.0

	func set_points(pts: Array) -> void:
		points = pts
		index = 0
		_best = INF
		_since = 0.0

	func poll(f: Fighter, _sim, dt: float) -> void:
		f.input.move = Vector3.ZERO
		f.input.held = 0
		if points.is_empty():
			return
		var target: Vector3 = points[index % points.size()]
		var to := Vector3(target.x - f.pos().x, 0.0, target.z - f.pos().z)
		if to.length() < 0.45 or _since > 4.0:
			index += 1
			_best = INF
			_since = 0.0
			return
		if to.length() < _best - 0.05:
			_best = to.length()
			_since = 0.0
		else:
			_since += dt
		f.input.move = to.normalized()


func run() -> void:
	var preset := Cannery.cli("--preset")
	if preset != "":
		Settings.set_value("graphics.preset", preset, true, false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var per_space := float(Cannery.cli("--bench-seconds", "6"))
	report = {"bench": "hub", "date": Time.get_datetime_string_from_system(), "engine": Engine.get_version_info()["string"],
		"os": OS.get_name(), "cpu": OS.get_processor_name(), "cores": OS.get_processor_count(),
		"renderer": RenderingServer.get_video_adapter_name(), "preset": str(Settings.values.get("graphics.preset", "?")),
		"window": [get_window().size.x, get_window().size.y], "seconds_per_space": per_space}
	walker = Walker.new()
	scene.sim.set_input_source(0, walker)
	await get_tree().create_timer(2.5).timeout          # fade-in and first-frame shader warm-up
	var all := PackedFloat32Array()
	var draws := PackedFloat32Array()
	var prims := PackedFloat32Array()
	var proc := PackedFloat32Array()
	var phys := PackedFloat32Array()
	var spaces := {}
	for sid in HubLayout.SPACES:
		var space_id := str(sid)
		var arrive := HubLayout.arrive_of(space_id)
		scene.mode.teleport(scene.player(), arrive[0], float(arrive[1]))
		var loop := []
		for n in HubLayout.NAV:
			var q: Vector3 = HubLayout.NAV[n]
			if HubLayout.space_at(q + Vector3.UP * 0.5) == space_id:
				loop.append(q)
		walker.set_points(loop)
		await get_tree().create_timer(0.6).timeout      # let the camera settle on the new room
		var frames := PackedFloat32Array()
		var t_end := Time.get_ticks_msec() + int(per_space * 1000.0)
		var last := Time.get_ticks_usec()
		while Time.get_ticks_msec() < t_end:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var ms := (now - last) / 1000.0
			last = now
			frames.append(ms)
			all.append(ms)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var st := stats(frames)
		st["over_16_7ms"] = frames.size() - Array(frames).filter(func(v): return float(v) <= 16.7).size()
		spaces[space_id] = st
	report["spaces"] = spaces
	report["frame_ms"] = stats(all)
	report["fps_avg"] = snappedf(1000.0 / maxf(0.001, float(report["frame_ms"].get("mean", 1.0))), 0.1)
	var over := 0
	for v in all:
		if v > 16.7:
			over += 1
	report["frames"] = all.size()
	report["frames_over_16_7ms"] = over
	report["frames_over_16_7ms_pct"] = snappedf(100.0 * over / maxf(1.0, all.size()), 0.01)
	report["draw_calls"] = stats(draws)
	report["primitives"] = stats(prims)
	report["process_ms"] = stats(proc)
	report["physics_ms"] = stats(phys)
	report["video_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	report["memory_static_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	var out := Cannery.cli("--out", Paths.dir("captures").path_join("bench_hub.json"))
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("HUB_BENCH ", JSON.stringify(report))
	print("HUB_BENCH_REPORT ", out)
	get_tree().quit(0)


static func stats(a: PackedFloat32Array) -> Dictionary:
	if a.is_empty():
		return {"n": 0}
	var s := Array(a)
	s.sort()
	var sum := 0.0
	for v in s:
		sum += float(v)
	var pick := func(q: float) -> float: return float(s[clampi(int(round(q * (s.size() - 1))), 0, s.size() - 1)])
	return {"n": s.size(), "mean": snappedf(sum / s.size(), 0.001), "p50": snappedf(pick.call(0.5), 0.001),
		"p95": snappedf(pick.call(0.95), 0.001), "p99": snappedf(pick.call(0.99), 0.001), "max": snappedf(float(s[-1]), 0.001)}
