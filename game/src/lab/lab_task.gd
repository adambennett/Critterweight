class_name LabTask
extends RefCounted
## Base class of the coordinator-side job logic run by the worker process (rank 0): ES, BC,
## evaluation and recording. The worker owns the frame loop, control/pause/cancel, limits and
## progress files; a task drives batches through `batch` and keeps its own durable state in
## checkpoints (Saves envelopes, so a torn write is detected and the previous one is used).

const CHECKPOINT_KEEP := 3

var job := {}
var run_dir := ""
var batch: LabBatch
var runner: LabRunner
var log_cb: Callable = Callable()
## training wall time in seconds, excluding pauses (maintained by the worker)
var elapsed_s := 0.0
var phase := "init"
var finished := false
var final_state := "completed"
var message := ""
var episodes := 0
var fight_ticks := 0
var stop_requested := ""
var progress := {}
var report_path := ""
var policy_id := ""
var restored_elapsed := 0.0


func begin() -> void:
	pass


func frame(_dt: float) -> void:
	pass


## Graceful stop (limits reached): finish the current step, evaluate, save, complete.
func request_stop(reason: String) -> void:
	if stop_requested == "":
		stop_requested = reason
		note("stopping: %s" % reason)


## Immediate stop (user cancel): keep the last checkpoint, no final evaluation.
func cancel_now() -> void:
	finished = true
	final_state = "cancelled"
	message = "cancelled by the user (resumable from the last checkpoint)"


func note(msg: String) -> void:
	if log_cb.is_valid():
		log_cb.call(msg)


func weights() -> Dictionary:
	return (job["objective"] as Dictionary)["weights"]


func metrics(line: Dictionary) -> void:
	line["t"] = snappedf(elapsed_s, 0.01)
	line["episodes"] = episodes
	LabIO.append_line(run_dir.path_join("metrics.jsonl"), line)


func count_results(results: Array) -> void:
	for r: Dictionary in results:
		if not r.has("error"):
			episodes += 1
			fight_ticks += int(r.get("ticks", 0))


func sim_seconds() -> float:
	return float(fight_ticks) / float(Engine.physics_ticks_per_second)


func checkpoint_dir() -> String:
	return run_dir.path_join("checkpoints")


func save_checkpoint(n: int, data: Dictionary) -> void:
	data["n"] = n
	data["episodes"] = episodes
	data["fight_ticks"] = fight_ticks
	data["elapsed_s"] = elapsed_s
	data["phase"] = phase
	var dir := checkpoint_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	# stored as one JSON string inside the Saves envelope: the envelope checksum then covers
	# exact text (see PolicyData.canonical about float round trips)
	var err: Error = Saves.write_json(dir.path_join("ckpt_%06d.json" % n), "lab_checkpoint", 1, {"json": JSON.stringify(data, "", false, true)})
	if err != OK:
		note("checkpoint %d failed: %s" % [n, error_string(err)])
		return
	var files := checkpoint_files()
	while files.size() > CHECKPOINT_KEEP:
		var old: String = files.pop_front()
		Saves.delete_save(old)


func checkpoint_files() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(checkpoint_dir()):
		return out
	for fn in DirAccess.get_files_at(checkpoint_dir()):
		var f := str(fn)
		if f.begins_with("ckpt_") and f.ends_with(".json"):
			out.append(checkpoint_dir().path_join(f))
	out.sort()
	return out


## Newest checkpoint that passes validation ({} if none). Damaged ones are skipped.
func load_checkpoint() -> Dictionary:
	var files := checkpoint_files()
	files.reverse()
	for path in files:
		var r: Dictionary = Saves.read_json(str(path), "lab_checkpoint", 1)
		var parsed = JSON.parse_string(str((r["data"] as Dictionary).get("json", ""))) if r["ok"] and typeof(r["data"]) == TYPE_DICTIONARY else null
		if r["ok"] and typeof(parsed) == TYPE_DICTIONARY:
			var d: Dictionary = parsed
			episodes = int(d.get("episodes", 0))
			fight_ticks = int(d.get("fight_ticks", 0))
			restored_elapsed = float(d.get("elapsed_s", 0.0))
			note("resuming from %s" % str(path).get_file())
			return d
		note("skipping damaged checkpoint %s: %s" % [str(path).get_file(), r["error"]])
	return {}


## Common policy metadata for this job (creature, act mode, mask...).
func policy_meta(mode: String) -> Dictionary:
	var c: CreatureDef = Content.creature(str(job["creature"]))
	return {"creature": str(job["creature"]), "mode": mode, "temperature": float(job["model"]["temperature"]),
		"target_lag": 1, "decision_hz": PolicyActions.DEFAULT_DECISION_HZ, "mask": Array(PolicyActions.button_mask(c))}


func payload(arch_hidden: PackedInt32Array, activation: String, mode: String, params: Dictionary) -> Dictionary:
	var enc := {}
	for k in params:
		enc[k] = LabIO.b64_floats(params[k])
	return {"arch": {"hidden": Array(arch_hidden), "activation": activation}, "meta": policy_meta(mode), "params": enc}


## A complete PolicyData from trained parameters plus training metadata.
func make_policy(arch_hidden: PackedInt32Array, activation: String, params: PackedFloat32Array, mode: String, approach: String, extra := {}) -> PolicyData:
	var p := PolicyData.create_new(str(job["creature"]), arch_hidden, activation, 1)
	p.net.params = params.duplicate()
	p.act_mode = mode
	p.temperature = float(job["model"]["temperature"])
	var nm := str(job["output"].get("policy_name", ""))
	if nm == "":
		nm = str(job.get("name", ""))
	if nm == "":
		nm = "%s %s" % [str(job["creature"]).capitalize(), approach.to_upper()]
	p.name = nm.substr(0, 64)
	var tr := {"approach": approach, "run_id": str(job.get("id", "")), "objective": job["objective"],
		"scenario": job["scenario"], "seed": int(job["seed"]), "episodes": episodes, "sim_seconds": snappedf(sim_seconds(), 0.1),
		"wall_time_s": snappedf(elapsed_s, 0.1), "game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"obs_version": PolicyObs.VERSION, "act_version": PolicyActions.VERSION, "processor_count": OS.get_processor_count(),
		"limits": job["limits"]}
	for k in extra:
		tr[k] = extra[k]
	p.training = tr
	return p


## Writes a policy into the run folder and (if configured) the user library. Returns its id.
func publish_policy(p: PolicyData, file_name: String, to_library: bool) -> String:
	var path := run_dir.path_join(file_name)
	if p.id == "":
		p.id = PolicyLibrary.new_id(p.creature)
	var err := PolicyIO.write_file(path, p)
	if err != OK:
		note("could not write %s: %s" % [file_name, error_string(err)])
	if to_library and bool(job["output"].get("save_to_library", true)):
		var e2 := PolicyLibrary.save(p)
		if e2 != OK:
			note("could not add policy to the library: %s" % error_string(e2))
		else:
			note("saved policy '%s' (%s) to the library" % [p.name, p.id])
	return p.id


## Loads an initial policy file for a job (same creature required).
func load_init_policy(path: String) -> PolicyData:
	if path == "":
		return null
	var r := PolicyIO.read_file(path, str(job["creature"]))
	if not r["ok"]:
		note("initial policy rejected: %s" % "; ".join(r["errors"]))
		return null
	return r["policy"]


func write_report(rep: Dictionary) -> void:
	rep["run_id"] = str(job.get("id", ""))
	rep["kind"] = str(job["kind"])
	rep["created"] = PolicyData.now_iso()
	rep["job"] = job
	report_path = run_dir.path_join("report.json")
	LabIO.write_json(report_path, rep)
