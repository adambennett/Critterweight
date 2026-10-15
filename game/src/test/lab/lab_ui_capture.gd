extends SceneTree
## Windowed runtime verification of the AI Lab screen (not part of the headless test run):
##   godot --path game --resolution 1600x900 -s res://src/test/lab/lab_ui_capture.gd -- \
##         --user-root <fresh dir> --out <capture dir> [--train-seconds 25]
## Opens the Lab, captures every tab, starts a real training run from the Train tab (1 worker
## process), measures the game's frame times while the worker trains, exercises pause /
## resume / cancel through the UI, and writes captures + ui_report.json into --out.

var out_dir := ""
var train_seconds := 25.0
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
	if OS.get_cmdline_user_args().has("--static"):
		# layout check only: every tab, no training
		for t in [1, 2, 3]:
			screen.call("_select_tab", t)
			await _wait(0.8)
			await _shot("tab%d" % t)
		quit(0)
		return
	# start a real (short) training run from the UI with one worker process
	var workers_box: Control = screen.get("_workers")
	(workers_box.get_node("Slider") as HSlider).value = 1
	var steps_box: Control = screen.get("_lim_steps")
	(steps_box.get_node("Slider") as HSlider).value = 200
	screen.call("_start_training")
	var run_dir: String = screen.get("_run_dir")
	report["run_dir"] = run_dir
	_measuring = true
	await _wait(train_seconds)
	_measuring = false
	await _shot("runs_training")
	var pr: Dictionary = lm.progress(run_dir)
	report["progress_while_training"] = pr
	var sorted := frame_ms.duplicate()
	sorted.sort()
	report["ui_frames"] = sorted.size()
	report["ui_frame_ms_median"] = sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
	report["ui_frame_ms_p99"] = sorted[int(sorted.size() * 0.99)] if not sorted.is_empty() else 0.0
	report["ui_frame_ms_max"] = sorted.back() if not sorted.is_empty() else 0.0
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
