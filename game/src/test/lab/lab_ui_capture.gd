extends SceneTree
## Windowed runtime verification of the AI Lab screen (not part of the headless test run):
##   godot --path game --resolution 1600x900 -s res://src/test/lab/lab_ui_capture.gd -- \
##         --user-root <fresh dir> --out <capture dir> [--train-seconds 25] [--baseline-seconds 20] [--static]
## Opens the Lab, measures the game's frame times without training (baseline), starts a real
## training run from the Train tab (1 worker process at normal priority), measures the frame
## times again while the worker trains, exercises pause / resume / cancel through the UI, and
## writes captures + ui_report.json into --out. --static only captures every tab; --runs captures
## the Runs tab once per run folder found under <user root>/lab/runs.

var out_dir := ""
var train_seconds := 25.0
var baseline_seconds := 20.0
var screen: Node
var report := {}
var frame_ms: Array = []
var _last_us := 0
var _measuring := false
## loaded at run time: this script is compiled before the autoloads that LabManager uses exist
var lm = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else OS.get_user_data_dir().path_join("captures")
	var j := args.find("--train-seconds")
	if j >= 0 and j + 1 < args.size():
		train_seconds = float(args[j + 1])
	var b := args.find("--baseline-seconds")
	if b >= 0 and b + 1 < args.size():
		baseline_seconds = float(args[b + 1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if _measuring:
		var now := Time.get_ticks_usec()
		if _last_us > 0:
			frame_ms.append(float(now - _last_us) / 1000.0)
		_last_us = now
	return false


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frame_stats(prefix: String, samples: Array) -> void:
	var sorted := samples.duplicate()
	sorted.sort()
	var n := sorted.size()
	report[prefix + "_frames"] = n
	report[prefix + "_frame_ms_median"] = sorted[n / 2] if n > 0 else 0.0
	report[prefix + "_frame_ms_p95"] = sorted[int(n * 0.95)] if n > 0 else 0.0
	report[prefix + "_frame_ms_p99"] = sorted[int(n * 0.99)] if n > 0 else 0.0
	report[prefix + "_frame_ms_max"] = sorted.back() if n > 0 else 0.0
	var slow := 0
	for v in sorted:
		if float(v) > 33.4:
			slow += 1
	report[prefix + "_frames_over_33ms_pct"] = 100.0 * float(slow) / float(maxi(n, 1))


func _shot(name_: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("lab_%s.png" % name_)
	img.save_png(path)
	print("CAPTURED ", path)


func _run() -> void:
	lm = load("res://src/lab/lab_manager.gd")
	var app := root.get_node("App")
	await _wait(0.5)
	screen = app.call("goto", "lab")
	await _wait(1.0)
	await _shot("train")
	if OS.get_cmdline_user_args().has("--runs"):
		# the Runs tab (state, numbers, learning curve, checkpoints, report) for every run folder
		# under <user root>/lab/runs, e.g. evidence runs copied there
		screen.call("_select_tab", 1)
		await _wait(0.8)
		var runs: Array = screen.get("_runs")
		var list: ItemList = screen.get("_runs_list")
		for i in runs.size():
			list.select(i)
			list.item_selected.emit(i)
			await _wait(0.8)
			await _shot("run_%s" % str((runs[i] as Dictionary)["run_id"]))
		quit(0)
		return
	if OS.get_cmdline_user_args().has("--static"):
		# layout check only: every tab, no training
		for t in [1, 2, 3]:
			screen.call("_select_tab", t)
			await _wait(0.8)
			await _shot("tab%d" % t)
		quit(0)
		return
	# baseline: the same screen without a worker, under whatever else the PC is running
	_measuring = true
	await _wait(baseline_seconds)
	_measuring = false
	_last_us = 0
	_frame_stats("ui_baseline", frame_ms)
	frame_ms = []
	# start a real (short) training run from the UI with one worker process
	var workers_box: Control = screen.get("_workers")
	(workers_box.get_node("Slider") as HSlider).value = 1
	var steps_box: Control = screen.get("_lim_steps")
	(steps_box.get_node("Slider") as HSlider).value = 200
	# normal priority: the worst case for the game's frame rate, and the worker makes progress
	# even when other programs keep every core busy (a low-priority worker would wait for CPU)
	(screen.get("_low_prio") as CheckBox).button_pressed = false
	report["worker_low_priority"] = false
	report["processor_count"] = OS.get_processor_count()
	screen.call("_start_training")
	var run_dir: String = screen.get("_run_dir")
	report["run_dir"] = run_dir
	_measuring = true
	await _wait(train_seconds)
	_measuring = false
	await _shot("runs_training")
	var pr: Dictionary = lm.progress(run_dir)
	report["progress_while_training"] = pr
	_frame_stats("ui_training", frame_ms)
	# the screen's own polling work (reading the run's small files), timed directly
	var costs := []
	for k in 20:
		var t0 := Time.get_ticks_usec()
		screen.call("_refresh_run_detail", true)
		costs.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		await process_frame
	costs.sort()
	report["ui_refresh_full_ms_median"] = costs[costs.size() / 2]
	report["ui_refresh_full_ms_max"] = costs.back()
	# pause / resume / cancel through the screen's buttons
	screen.call("_control", "pause")
	await _wait(2.0)
	report["state_after_pause"] = lm.effective_state(run_dir)
	var ep_paused := int(lm.progress(run_dir).get("episodes", 0))
	await _wait(2.0)
	report["episodes_frozen_while_paused"] = int(lm.progress(run_dir).get("episodes", 0)) == ep_paused
	screen.call("_refresh_run_detail", true)
	await _shot("runs_paused")
	screen.call("_control", "run")
	await _wait(4.0)
	report["state_after_resume"] = lm.effective_state(run_dir)
	screen.call("_control", "cancel")
	await _wait(4.0)
	report["state_after_cancel"] = lm.effective_state(run_dir)
	screen.call("_refresh_run_detail", true)
	await _shot("runs_cancelled")
	screen.call("_select_tab", 2)
	await _wait(0.8)
	await _shot("policies")
	screen.call("_select_tab", 3)
	await _wait(0.8)
	await _shot("recording")
	var f := FileAccess.open(out_dir.path_join("ui_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("UI_REPORT ", JSON.stringify(report))
	quit(0)
