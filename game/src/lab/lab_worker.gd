class_name LabWorker
extends Node
## AI Lab training worker: a separate, headless game process, so the game UI never stalls.
##   <game> --headless --fixed-fps 120 -- --lab-worker <job.json> [--lab-out <run dir>]
##          [--lab-rank k --lab-parent-pid pid] [--user-root <dir>]
## Rank 0 (the coordinator) owns the job: it spawns `limits.workers - 1` helper processes
## (ranks 1..n, same binary), runs the task (ES / BC / evaluation / recording), distributes
## episodes through LabBatch, writes progress/metrics/checkpoints, and obeys the control file
## (pause / resume / cancel / snapshot). Helpers only run episodes they are handed and exit when
## the coordinator is gone. Every rank steps its episodes in its own physics worlds with the
## real combat rules; --fixed-fps 120 makes each frame exactly one 120 Hz tick, as fast as the
## CPU allows.
## Exit codes: 0 completed/cancelled/interrupted, 1 failed, 2 bad job.

const CONTROL_EVERY_MS := 200
const PROGRESS_EVERY_MS := 500
const PARENT_CHECK_MS := 5000

var args := PackedStringArray()
var job := {}
var run_dir := ""
var rank := 0
var parent_pid := 0
var runner: LabRunner
var batch: LabBatch
var task: LabTask
var state := "starting"
var helper_pids := {}

var _t_start := 0
var _paused_total := 0
var _pause_started := 0
var _elapsed_base := 0.0
var _last_control := 0
var _last_progress := 0
var _busy_us := 0
var _wall_mark_us := 0
var _util := 0.0
var _mem_peak := 0.0
var _snapshot_seq := 0
var _log: FileAccess
var _finished := false
var _last_parent_check := 0


func _arg(flag: String, fallback := "") -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


func run_from_cli(a: PackedStringArray) -> void:
	args = a
	set_physics_process(false)
	rank = int(_arg("--lab-rank", "0"))
	parent_pid = int(_arg("--lab-parent-pid", "0"))
	if args.has("--lab-bench"):
		var bench := LabBench.new()
		add_child(bench)
		bench.run(_arg("--lab-bench", "inference"), _arg("--lab-out", ""))
		return
	if args.has("--lab-publish"):
		get_tree().quit(publish(_arg("--lab-publish", ""), _arg("--id", ""), _arg("--name", ""), _arg("--description", ""), _arg("--lab-out", "")))
		return
	var job_path := _arg("--lab-worker", "")
	var loaded := LabJob.load_file(job_path)
	job = loaded["job"]
	var errors: PackedStringArray = loaded["errors"]
	run_dir = _resolve_run_dir(job_path)
	if run_dir == "":
		printerr("lab worker: cannot determine a run folder for %s" % job_path)
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(run_dir)
	_open_log()
	if not errors.is_empty():
		_note("invalid job: " + "; ".join(errors))
		if rank == 0:
			_write_status("failed", "invalid job: " + "; ".join(errors))
		get_tree().quit(2)
		return
	(job["paths"] as Dictionary)["run_dir"] = run_dir
	if str(job.get("id", "")) == "":
		job["id"] = run_dir.get_file()
	_apply_paths()
	if rank == 0:
		LabIO.write_json(run_dir.path_join("job_effective.json"), job)
		_write_status("starting", "")
	if bool(job["limits"]["low_priority"]):
		_lower_priority()
	runner = LabRunner.new()
	runner.name = "Runner"
	runner.max_worlds = int(job["limits"]["worlds"])
	add_child(runner)
	batch = LabBatch.new()
	batch.setup(run_dir.path_join("gen"), rank, runner)
	if rank == 0:
		DirAccess.remove_absolute(run_dir.path_join("gen").path_join("stop"))
		task = _make_task(str(job["kind"]))
		task.job = job
		task.run_dir = run_dir
		task.batch = batch
		task.runner = runner
		task.log_cb = _note
		task.begin()
		_elapsed_base = task.restored_elapsed
		task.elapsed_s = _elapsed_base
		if task.finished:
			_finish()
			return
		_spawn_helpers()
		state = "running"
		_write_status("running", "")
		_note("run %s: %s, creature %s, %d worker process(es) x %d world(s)" % [str(job["id"]), str(job["kind"]), str(job["creature"]),
			int(job["limits"]["workers"]), int(job["limits"]["worlds"])])
	else:
		state = "running"
		_note("helper rank %d ready (coordinator pid %d)" % [rank, parent_pid])
	_t_start = Time.get_ticks_msec()
	_wall_mark_us = Time.get_ticks_usec()
	set_physics_process(true)


## `--lab-worker --lab-publish <trained.policy.json> --id <id> --name <name> --lab-out <file>`:
## re-labels a trained policy (new id/name/description, re-signed, validated) — used to ship
## sample policies as content. Returns a process exit code.
static func publish(src: String, id: String, display_name: String, description: String, dest: String) -> int:
	var r := PolicyIO.read_file(src)
	if not r["ok"]:
		printerr("cannot publish %s: %s" % [src, "; ".join(r["errors"])])
		return 2
	var p: PolicyData = r["policy"]
	if id != "":
		p.id = id
	if display_name != "":
		p.name = display_name
	if description != "":
		p.description = description
	p.updated = PolicyData.now_iso()
	var err := PolicyIO.write_file(dest, p)
	if err != OK:
		printerr("cannot write %s: %s" % [dest, error_string(err)])
		return 1
	PolicyIO.delete_file(dest + ".bak")
	print("published %s as %s -> %s" % [src.get_file(), p.id, dest])
	return 0


func _resolve_run_dir(job_path: String) -> String:
	var out := _arg("--lab-out", "")
	if out != "":
		return out.replace("\\", "/")
	var rd := str((job.get("paths", {}) as Dictionary).get("run_dir", "")) if not job.is_empty() else ""
	if rd != "":
		return rd.replace("\\", "/")
	if job_path.get_file() == "job.json" or job_path.get_file() == "job_effective.json":
		return job_path.get_base_dir().replace("\\", "/")
	var rid := LabJob.new_run_id(str(job.get("kind", "job")), str(job.get("creature", "x")))
	var d := Paths.dir("lab").path_join("runs").path_join(rid)
	DirAccess.make_dir_recursive_absolute(d)
	if FileAccess.file_exists(job_path):
		DirAccess.copy_absolute(job_path, d.path_join("job.json"))
	return d


func _apply_paths() -> void:
	var p: Dictionary = job["paths"]
	if str(p.get("library_dir", "")) != "":
		PolicyLibrary.user_dir_override = str(p["library_dir"])
	if str(p.get("datasets_dir", "")) != "":
		PolicyDataset.root_override = str(p["datasets_dir"])


func _make_task(kind: String) -> LabTask:
	match kind:
		"bc":
			return LabTaskBC.new()
		"eval":
			return LabTaskEval.new()
		"record":
			return LabTaskRecord.new()
	return LabTaskES.new()


func _open_log() -> void:
	_log = FileAccess.open(run_dir.path_join("worker_r%d.log" % rank), FileAccess.READ_WRITE if FileAccess.file_exists(run_dir.path_join("worker_r%d.log" % rank)) else FileAccess.WRITE)
	if _log != null:
		_log.seek_end()


func _note(msg: String) -> void:
	var line := "%s r%d %s" % [Time.get_datetime_string_from_system(false, true), rank, msg]
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()


# =====================================================================================
# Processes
# =====================================================================================

static func spawn_args(job_path: String, run_dir_path: String, user_args: Array) -> PackedStringArray:
	var a := PackedStringArray()
	if not OS.has_feature("template"):
		a.append_array(["--path", ProjectSettings.globalize_path("res://")])
	a.append_array(["--headless", "--fixed-fps", "120", "--", "--lab-worker", job_path, "--lab-out", run_dir_path])
	for x in user_args:
		a.append(str(x))
	return a


func _spawn_helpers() -> void:
	var n := int(job["limits"]["workers"])
	var exe := OS.get_executable_path()
	for k in range(1, n):
		var home := run_dir.path_join("home_r%d" % k)
		DirAccess.make_dir_recursive_absolute(home)
		var a := spawn_args(run_dir.path_join("job_effective.json"), run_dir, ["--lab-rank", k, "--lab-parent-pid", OS.get_process_id(), "--user-root", home])
		var pid := OS.create_process(exe, a)
		if pid <= 0:
			_note("could not start helper rank %d" % k)
			continue
		helper_pids[k] = pid
		batch.helpers[k] = {"pid": pid, "alive": true, "started_ms": Time.get_ticks_msec()}
		_note("helper rank %d started (pid %d)" % [k, pid])


func _stop_helpers() -> void:
	LabIO.write_json(run_dir.path_join("gen").path_join("stop"), {"by": OS.get_process_id()})


## Lowers this process's scheduling priority (best effort; never fatal).
func _lower_priority() -> void:
	var pid := OS.get_process_id()
	var out := []
	var code := -1
	if OS.get_name() == "Windows":
		code = OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command", "(Get-Process -Id %d).PriorityClass = 'BelowNormal'" % pid], out, true)
	elif OS.get_name() in ["Linux", "macOS", "FreeBSD"]:
		code = OS.execute("renice", ["-n", "10", "-p", str(pid)], out, true)
	_note("process priority lowered: %s" % ("yes" if code == 0 else "no (exit %d)" % code))


# =====================================================================================
# Frame loop
# =====================================================================================

func _physics_process(dt: float) -> void:
	if _finished:
		return
	var t0 := Time.get_ticks_usec()
	var now := Time.get_ticks_msec()
	if now - _last_control >= CONTROL_EVERY_MS:
		_last_control = now
		_check_control()
		if _finished:
			return
	if state == "paused":
		runner.set_frozen(true)
		if rank == 0 and now - _last_progress >= PROGRESS_EVERY_MS:
			_last_progress = now
			_write_progress()
		OS.delay_msec(40)
		return
	runner.set_frozen(false)
	if rank == 0:
		task.elapsed_s = elapsed_s()
		_check_limits()
		task.frame(dt)
		if task.finished:
			_finish()
			return
	else:
		batch.helper_poll(_stats())
	runner.step(dt)
	var work := Time.get_ticks_usec() - t0
	_busy_us += work
	if rank == 0 and now - _last_progress >= PROGRESS_EVERY_MS:
		_last_progress = now
		_write_progress()
	var share := float(job["limits"]["cpu_share"])
	if share < 0.999:
		OS.delay_usec(int(float(work) * (1.0 / share - 1.0)))
	elif not runner.busy():
		OS.delay_msec(3)


func elapsed_s() -> float:
	var paused := _paused_total
	if state == "paused":
		paused += Time.get_ticks_msec() - _pause_started
	return _elapsed_base + float(Time.get_ticks_msec() - _t_start - paused) / 1000.0


func _check_limits() -> void:
	var lim: Dictionary = job["limits"]
	if elapsed_s() >= float(lim["max_wall_s"]):
		task.request_stop("time limit (%d s)" % int(float(lim["max_wall_s"])))
	var mem := float(OS.get_static_memory_usage()) / 1048576.0
	if mem > float(lim["max_memory_mb"]):
		task.request_stop("memory limit (%d MB)" % int(lim["max_memory_mb"]))


## True if a process with this pid exists. OS.is_process_running only knows a process's own
## children (on Windows and Unix), so the parent is checked through the OS (best effort; an
## unknown answer counts as alive so a worker never stops by mistake).
static func process_alive(pid: int) -> bool:
	if pid <= 0:
		return false
	if OS.is_process_running(pid):
		return true
	var out := []
	if OS.get_name() == "Windows":
		var code := OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/NH", "/FO", "CSV"], out, true)
		if code != 0 or out.is_empty():
			return true
		return str(out[0]).contains("\"%d\"" % pid)
	var c2 := OS.execute("kill", ["-0", str(pid)], out, true)
	return c2 == 0


func _check_control() -> void:
	var now := Time.get_ticks_msec()
	if parent_pid > 0 and now - _last_parent_check >= PARENT_CHECK_MS:
		_last_parent_check = now
		if not process_alive(parent_pid):
			if rank == 0:
				_note("the game process exited; stopping (resume from the Lab later)")
				_finish_interrupted("interrupted: the game was closed (resumable)")
			else:
				_note("coordinator gone; helper exiting")
				_quit(0)
			return
	if rank > 0 and FileAccess.file_exists(run_dir.path_join("gen").path_join("stop")):
		_quit(0)
		return
	var c := LabIO.read_json(run_dir.path_join("control.json"))
	var desired := str(c.get("desired", "run"))
	if desired == "cancel":
		if rank == 0:
			_note("cancel requested")
			task.cancel_now()
			_finish()
		else:
			_quit(0)
		return
	if desired == "pause" and state == "running":
		state = "paused"
		_pause_started = Time.get_ticks_msec()
		runner.set_frozen(true)
		if rank == 0:
			_note("paused")
			_write_status("paused", "")
			_write_progress()
	elif desired != "pause" and state == "paused":
		state = "running"
		_paused_total += Time.get_ticks_msec() - _pause_started
		runner.set_frozen(false)
		if rank == 0:
			_note("resumed")
			_write_status("running", "")
	var snap := int(c.get("snapshot_seq", 0))
	if rank == 0 and snap > _snapshot_seq:
		_snapshot_seq = snap
		_snapshot()


func _snapshot() -> void:
	var params := PackedFloat32Array()
	var hidden := PackedInt32Array()
	var act := "tanh"
	var mode := "argmax"
	if task is LabTaskES:
		var t := task as LabTaskES
		params = t.best_theta if not t.best_theta.is_empty() else t.es.theta
		hidden = t.hidden
		act = t.activation
		mode = t.act_mode
	elif task is LabTaskBC:
		var b := task as LabTaskBC
		params = b.bc.best_params
		hidden = b.hidden
		act = b.activation
		mode = "sample"
	if params.is_empty():
		return
	var p := task.make_policy(hidden, act, params, mode, str(job["kind"]), {"snapshot": true, "note": "saved during training"})
	p.name = (p.name + " (snapshot)").substr(0, 64)
	var pid := task.publish_policy(p, "snapshot.policy.json", true)
	_note("snapshot saved as %s" % pid)


func _stats() -> Dictionary:
	var now_us := Time.get_ticks_usec()
	var wall := now_us - _wall_mark_us
	if wall > 1000000:
		_util = clampf(float(_busy_us) / float(wall), 0.0, 1.0)
		_busy_us = 0
		_wall_mark_us = now_us
	var mem := float(OS.get_static_memory_usage()) / 1048576.0
	_mem_peak = maxf(_mem_peak, mem)
	return {"util": _util, "mem_mb": mem, "mem_peak_mb": _mem_peak, "episodes": runner.episodes_done, "sim_ticks": runner.sim_ticks, "pid": OS.get_process_id()}


func _write_progress() -> void:
	var st := _stats()
	var el := elapsed_s()
	var sim_s := task.sim_seconds()
	var helpers := []
	var alive := 0
	for r in batch.helpers:
		var h: Dictionary = batch.helpers[r]
		var hs: Dictionary = batch.helper_stats.get(r, {})
		if bool(h["alive"]):
			alive += 1
		helpers.append({"rank": r, "pid": h["pid"], "alive": h["alive"], "util": hs.get("util", 0.0), "mem_mb": hs.get("mem_mb", 0.0)})
	var p := {"run_id": str(job["id"]), "kind": str(job["kind"]), "name": str(job.get("name", "")), "creature": str(job["creature"]),
		"state": state, "phase": task.phase, "pid": OS.get_process_id(), "elapsed_s": el, "max_wall_s": float(job["limits"]["max_wall_s"]),
		"episodes": task.episodes, "sim_s": sim_s, "sim_speed": sim_s / maxf(el, 0.001), "eps_per_hour": float(task.episodes) / maxf(el / 3600.0, 1e-6),
		"util": st["util"], "mem_mb": st["mem_mb"], "mem_peak_mb": st["mem_peak_mb"], "workers": 1 + helpers.size(), "helpers_alive": alive,
		"helpers": helpers, "reassigned": batch.reassigned, "batch_done": batch.done_count(), "batch_size": batch.items.size(),
		"limits": job["limits"], "updated": Time.get_unix_time_from_system(), "message": task.message}
	for k in task.progress:
		p[k] = task.progress[k]
	LabIO.write_json(run_dir.path_join("progress.json"), p)


func _write_status(st: String, msg: String, extra := {}) -> void:
	var d := {"state": st, "message": msg, "pid": OS.get_process_id(), "kind": str(job.get("kind", "")), "run_id": str(job.get("id", "")),
		"updated": Time.get_unix_time_from_system()}
	for k in extra:
		d[k] = extra[k]
	LabIO.write_json(run_dir.path_join("status.json"), d)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	task.elapsed_s = elapsed_s()
	state = task.final_state
	_stop_helpers()
	_write_progress()
	_write_status(task.final_state, task.message, {"report": task.report_path, "policy_id": task.policy_id, "final": true})
	_note("finished: %s — %s" % [task.final_state, task.message])
	_quit(1 if task.final_state == "failed" else 0)


func _finish_interrupted(msg: String) -> void:
	_finished = true
	state = "interrupted"
	_stop_helpers()
	_write_progress()
	_write_status("interrupted", msg, {"final": false})
	_quit(0)


func _quit(code: int) -> void:
	_finished = true
	set_physics_process(false)
	if runner != null:
		runner.clear()
	if _log != null:
		_log.flush()
	get_tree().quit(code)
