class_name LabManager
extends RefCounted
## Game-side control of AI Lab runs. The game never trains in its own process: it writes a job
## into a run folder, launches a worker process (`OS.create_process` on the game's own
## executable, headless, fixed 120 Hz steps) and then only reads small progress files and
## writes the control file, so menus stay responsive whatever the worker is doing.
## Runs survive the game closing: workers notice the game is gone, keep their last checkpoint
## and stop as "interrupted"; `start(run_dir)` later resumes from that checkpoint.

const LIVE_STATES: PackedStringArray = ["starting", "running", "paused"]
## A live worker rewrites progress.json every 0.5 s (also while paused). After this much silence
## the worker's process is checked: a low-priority worker on a saturated PC can be starved of CPU
## for a while without being gone (and must never be resumed twice). File heartbeats and pid
## checks both work across game restarts.
const STALE_PROGRESS_S := 20.0
const STARTUP_GRACE_S := 60.0
const PROCESS_RECHECK_MS := 5000

static var _seen_updated := {}   ## run dir -> newest progress/status "updated" time read
static var _spawned := {}        ## pids of workers this game session launched (children)
static var _proc_cache := {}     ## pid -> {alive, ms}: OS process checks of other sessions' workers
static var _job_info := {}       ## run dir -> {kind, name, creature} (a run's job never changes)
static var _final_progress := {} ## run dir -> {key, progress} for runs that are not live


static func runs_dir() -> String:
	var d := Paths.dir("lab").path_join("runs")
	LabIO.ensure_dir(d)
	return d


static func datasets_dir() -> String:
	return PolicyDataset.root()


## Normalizes and writes a new job; returns {ok, run_dir, run_id, errors}.
static func create_run(raw_job: Dictionary) -> Dictionary:
	var n := LabJob.normalize(raw_job)
	var job: Dictionary = n["job"]
	var errors: PackedStringArray = n["errors"]
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "run_dir": "", "run_id": ""}
	var rid := LabJob.new_run_id(str(job["kind"]), str(job["creature"]))
	var dir := runs_dir().path_join(rid)
	DirAccess.make_dir_recursive_absolute(dir)
	job["id"] = rid
	job["paths"] = {"run_dir": dir, "library_dir": PolicyLibrary.user_dir(), "datasets_dir": datasets_dir()}
	job["created"] = PolicyData.now_iso()
	LabIO.write_json(dir.path_join("job.json"), job)
	return {"ok": true, "errors": errors, "run_dir": dir, "run_id": rid}


## Launches (or resumes) the coordinator worker of a run. Returns the pid (> 0) or -1.
static func start(run_dir: String) -> int:
	if is_alive(run_dir):
		return int(status(run_dir).get("pid", -1))
	LabIO.write_json(run_dir.path_join("control.json"), {"desired": "run", "snapshot_seq": 0})
	var home := run_dir.path_join("home_r0")
	DirAccess.make_dir_recursive_absolute(home)
	var a := LabWorker.spawn_args(run_dir.path_join("job.json"), run_dir, ["--lab-rank", 0, "--lab-parent-pid", OS.get_process_id(), "--user-root", home])
	var pid := OS.create_process(OS.get_executable_path(), a)
	if pid > 0:
		_spawned[pid] = true
		LabIO.write_json(run_dir.path_join("status.json"), {"state": "starting", "pid": pid, "message": "launching worker", "updated": Time.get_unix_time_from_system()})
	return pid


static func control(run_dir: String, desired: String) -> void:
	var c := LabIO.read_json(run_dir.path_join("control.json"))
	c["desired"] = desired
	LabIO.write_json(run_dir.path_join("control.json"), c)


static func request_snapshot(run_dir: String) -> void:
	var c := LabIO.read_json(run_dir.path_join("control.json"))
	c["snapshot_seq"] = int(c.get("snapshot_seq", 0)) + 1
	if not c.has("desired"):
		c["desired"] = "run"
	LabIO.write_json(run_dir.path_join("control.json"), c)


static func status(run_dir: String) -> Dictionary:
	return LabIO.read_json(run_dir.path_join("status.json"))


static func progress(run_dir: String) -> Dictionary:
	return LabIO.read_json(run_dir.path_join("progress.json"))


static func job_of(run_dir: String) -> Dictionary:
	var j := LabIO.read_json(run_dir.path_join("job_effective.json"))
	return j if not j.is_empty() else LabIO.read_json(run_dir.path_join("job.json"))


## How the UI should see a run, from its status (and, for live runs, progress) dictionaries:
## {state, alive, silent_s}. `state` is the stored state, except that a live run whose worker
## is gone reads "interrupted". A live run's coordinator is alive while it reports (heartbeat
## through progress.json) or, when silent for longer than the heartbeat gap, while its process
## still exists (`silent_s` > 0: waiting for CPU rather than gone). Pass dictionaries already
## read to avoid reading the files again; empty ones are read here when needed.
static func run_state(run_dir: String, st := {}, pr := {}) -> Dictionary:
	if st.is_empty():
		st = status(run_dir)
	var raw := str(st.get("state", "new"))
	if not LIVE_STATES.has(raw):
		return {"state": raw, "alive": false, "silent_s": 0.0}
	if pr.is_empty():
		pr = progress(run_dir)
	var updated := maxf(float(pr.get("updated", 0.0)), float(st.get("updated", 0.0)))
	# a read that races the worker's atomic rewrite returns {}: remember the newest time seen
	updated = maxf(updated, float(_seen_updated.get(run_dir, 0.0)))
	_seen_updated[run_dir] = updated
	var age := Time.get_unix_time_from_system() - updated
	var limit := STARTUP_GRACE_S if raw == "starting" else STALE_PROGRESS_S
	var silent := age if age >= limit else 0.0
	var alive := silent <= 0.0 or worker_process_running(int(st.get("pid", -1)))
	return {"state": raw if alive else "interrupted", "alive": alive, "silent_s": silent}


## True while the run's coordinator is working (see run_state).
static func is_alive(run_dir: String) -> bool:
	return bool(run_state(run_dir)["alive"])


## Seconds a live run's coordinator has been silent beyond the allowed heartbeat gap (0 = it
## reports normally). With a running process this means "waiting for CPU", not "gone".
static func silent_for(run_dir: String) -> float:
	return float(run_state(run_dir)["silent_s"])


## Whether a worker process with this pid still exists. Workers this session launched are
## children (cheap, exact check); others (launched before the game restarted) are looked up
## through the OS by pid and executable name, at most every PROCESS_RECHECK_MS, and a process
## once seen gone stays gone.
static func worker_process_running(pid: int) -> bool:
	if pid <= 0:
		return false
	if OS.is_process_running(pid):
		return true
	if _spawned.has(pid):
		return false
	var c: Dictionary = _proc_cache.get(pid, {})
	var now := Time.get_ticks_msec()
	if not c.is_empty() and (not bool(c["alive"]) or now - int(c["ms"]) < PROCESS_RECHECK_MS):
		return bool(c["alive"])
	var alive := LabWorker.process_alive(pid, OS.get_executable_path().get_file())
	_proc_cache[pid] = {"alive": alive, "ms": now}
	return alive


## Status as the UI should show it: a "running" run whose process vanished is "interrupted".
static func effective_state(run_dir: String) -> String:
	return str(run_state(run_dir)["state"])


static func has_checkpoint(run_dir: String) -> bool:
	if not DirAccess.dir_exists_absolute(run_dir.path_join("checkpoints")):
		return false
	for fn in DirAccess.get_files_at(run_dir.path_join("checkpoints")):
		if str(fn).begins_with("ckpt_") and str(fn).ends_with(".json"):
			return true
	return false


static func can_resume(run_dir: String) -> bool:
	return resumable(run_state(run_dir))


## Whether a run in this run_state can be (re)started.
static func resumable(rs: Dictionary) -> bool:
	return str(rs["state"]) in ["interrupted", "cancelled", "failed", "new"] and not bool(rs["alive"])


## Summaries of all runs, newest first. Cheap enough to poll: a run's job is read once, and a
## finished run's progress only again when its status changes (one small read per run).
static func list_runs() -> Array:
	var out := []
	var root := runs_dir()
	var dirs := Array(DirAccess.get_directories_at(root))
	dirs.sort()
	dirs.reverse()
	for d in dirs:
		var dir := root.path_join(str(d))
		var info: Dictionary = _job_info.get(dir, {})
		if info.is_empty():
			var job := job_of(dir)
			if job.is_empty():
				continue
			info = {"kind": str(job.get("kind", "")), "name": str(job.get("name", "")), "creature": str(job.get("creature", ""))}
			_job_info[dir] = info
		var st := status(dir)
		var raw := str(st.get("state", "new"))
		var key := "%s|%s" % [raw, str(st.get("updated", ""))]
		var cached: Dictionary = _final_progress.get(dir, {})
		var pr: Dictionary
		if not LIVE_STATES.has(raw) and str(cached.get("key", "")) == key:
			pr = cached["progress"]
		else:
			pr = progress(dir)
			if not LIVE_STATES.has(raw):
				_final_progress[dir] = {"key": key, "progress": pr}
		var rs := run_state(dir, st, pr)
		out.append({"run_id": str(d), "dir": dir, "kind": info["kind"], "name": info["name"], "creature": info["creature"],
			"state": rs["state"], "episodes": int(pr.get("episodes", 0)), "elapsed_s": float(pr.get("elapsed_s", 0.0)),
			"message": str(st.get("message", ""))})
	return out


static func checkpoints(run_dir: String) -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(run_dir.path_join("checkpoints")):
		return out
	for fn in DirAccess.get_files_at(run_dir.path_join("checkpoints")):
		var f := str(fn)
		if f.begins_with("ckpt_") and f.ends_with(".json"):
			var path := run_dir.path_join("checkpoints").path_join(f)
			var fa := FileAccess.open(path, FileAccess.READ)
			out.append({"file": f, "n": int(f.trim_prefix("ckpt_").trim_suffix(".json")), "time": FileAccess.get_modified_time(path),
				"size_kb": (fa.get_length() / 1024) if fa != null else 0})
	out.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	return out


static func metrics(run_dir: String) -> Array:
	return LabIO.read_lines(run_dir.path_join("metrics.jsonl"))


static func report(run_dir: String) -> Dictionary:
	return LabIO.read_json(run_dir.path_join("report.json"))


static func delete_run(run_dir: String) -> Error:
	if is_alive(run_dir):
		return ERR_BUSY
	if not run_dir.begins_with(runs_dir()):
		return ERR_INVALID_PARAMETER
	LabIO.remove_tree(run_dir)
	_job_info.erase(run_dir)
	_final_progress.erase(run_dir)
	_seen_updated.erase(run_dir)
	return OK


## Starts an evaluation run for a saved policy against the fixed baselines.
static func evaluate_policy(policy_id: String, opponents: Array, episodes: int, workers: int) -> Dictionary:
	var p := PolicyLibrary.get_policy(policy_id)
	if p == null:
		return {"ok": false, "errors": PackedStringArray([PolicyLibrary.last_error(policy_id)]), "run_dir": ""}
	var r := create_run({"kind": "eval", "name": "Evaluate %s" % p.name, "creature": p.creature, "seed": 1000,
		"target": {"policy": policy_id, "compare": "random_init"}, "objective": {"preset": str((p.training.get("objective", {}) as Dictionary).get("preset", "aggressive")) if typeof(p.training.get("objective")) == TYPE_DICTIONARY else "aggressive"},
		"eval": {"opponents": opponents, "episodes": episodes, "standard_spawns": true}, "scenario": {"preset": "bots_low"},
		"limits": {"workers": workers}})
	if r["ok"]:
		start(str(r["run_dir"]))
	return r
