class_name LabTaskRecord
extends LabTask
## Records a scripted teacher (a bot tier or drill script) into an imitation dataset: the
## teacher plays in the learner slot wrapped by PolicyRecorder, so its observations and labels
## use exactly the obs_v1/act_v1 contracts a cloned policy will see. Every rank writes its own
## shards (see LabRecordSink); the coordinator stores the teacher's statistics (action
## distribution, outcomes) in the dataset meta for later behaviour comparisons.
## Seeds: episode k of a run is recording index `first + k` of the dataset with seed
## rec(job_seed, first + k). `first` continues after everything the dataset already holds
## (meta.next_episode, and the highest index stored in its shards), so recording the same
## teacher again — same job seed or not — adds NEW episodes instead of copies. The reservation
## is kept in the run's checkpoint: "Continue run" re-uses it and skips every episode whose seed
## the dataset already has. Episodes run in short batches, so the time / episode limits and stop
## requests end a recording after the current batch (what was recorded is kept).

var dataset_dir := ""
var first := 0
var total := 0
var todo: Array = []          ## recording indices still to record
var results: Array = []
var skipped := 0
var _next := 0
var _submitted := false


func begin() -> void:
	var rec: Dictionary = job["record"]
	var teacher := str(rec["teacher"])
	if not LabOpponents.BASELINES.has(teacher):
		finished = true
		final_state = "failed"
		message = "unknown teacher '%s'" % teacher
		return
	var did := str(rec.get("dataset_id", ""))
	if did == "":
		did = "teacher_%s_%s" % [teacher, str(job["creature"])]
		rec["dataset_id"] = did
	var nm := str(rec.get("dataset_name", ""))
	if nm == "":
		nm = "%s (%s)" % [LabOpponents.display_name(teacher), str(job["creature"])]
	dataset_dir = PolicyDataset.ensure(did, nm, str(job["creature"]), "bot:" + teacher)
	total = int(rec["episodes"])
	var have := PolicyDataset.recorded_index(dataset_dir)
	var ck := load_checkpoint()
	if not ck.is_empty() and ck.has("first"):
		first = int(ck["first"])
		total = int(ck.get("total", total))
		note("continuing the recording of indices %d..%d" % [first, first + total - 1])
	else:
		var meta := PolicyDataset.read_meta(dataset_dir)
		first = maxi(int(meta.get("next_episode", 0)), int(have["next"]))
		# reserve the indices before recording, so another run continues after them
		meta["next_episode"] = first + total
		PolicyDataset.write_meta(dataset_dir, meta)
		save_checkpoint(0, {"first": first, "total": total})
	var seeds: Dictionary = have["seeds"]
	for k in total:
		if seeds.has(seed_of(first + k)):
			skipped += 1
		else:
			todo.append(first + k)
	phase = "record"
	note("recording %d episodes of %s into %s (indices %d..%d%s)" % [todo.size(), teacher, dataset_dir, first, first + total - 1,
		", %d already recorded" % skipped if skipped > 0 else ""])


## Scenario seed of the dataset's recording index `index`.
func seed_of(index: int) -> int:
	return LabScenarios.seed_for("rec", int(job["seed"]), index)


func _items(a: int, b: int) -> Array:
	var rec: Dictionary = job["record"]
	var scn: Dictionary = job["scenario"]
	var opps: Array = scn["opponents"]
	var items := []
	for j in range(a, b):
		var index: int = todo[j]
		var ep := LabScenarios.episode(scn, str(opps[index % opps.size()]), seed_of(index), str(job["creature"]), str(job["opponent_creature"]))
		items.append({"i": j - a, "learner": {"type": "scripted", "kind": str(rec["teacher"])}, "record": true, "episode": ep,
			"group": "teacher", "rec_index": index})
	return items


func _limit_reason() -> String:
	if stop_requested != "":
		return stop_requested
	var lim: Dictionary = job["limits"]
	if int(lim["max_episodes"]) > 0 and episodes >= int(lim["max_episodes"]):
		return "episode limit (%d)" % int(lim["max_episodes"])
	return ""


func frame(_dt: float) -> void:
	if phase != "record":
		return
	if not _submitted:
		var why := _limit_reason()
		if _next >= todo.size() or why != "":
			_finish(why)
			return
		var b := mini(_next + chunk_size(), todo.size())
		batch.submit(_items(_next, b), {"record_dir": dataset_dir})
		_next = b
		_submitted = true
		progress["step"] = "recording episodes %d of %d" % [_next, todo.size()]
	else:
		progress["recorded_episodes"] = results.size() + batch.done_count()
		if batch.poll():
			_submitted = false
			var res := batch.ordered_results()
			count_results(res)
			results.append_array(res)


func _finish(stop_reason: String) -> void:
	var res := results
	var samples := 0
	for r: Dictionary in res:
		samples += int(r.get("samples", 0))
	var w := weights()
	var s := LabEval.summarize(res, w, "teacher")
	var meta := PolicyDataset.read_meta(dataset_dir)
	var stats := {"kind": str(job["record"]["teacher"]), "opponents": job["scenario"]["opponents"], "episodes": res.size(),
		"samples": samples, "label_hist": LabEval.act_hist(res, "label_hist"), "win_rate": s["win_rate"],
		"damage_dealt": LabEval.mean_term(res, "damage_dealt"), "damage_taken": LabEval.mean_term(res, "damage_taken"),
		"hits": LabEval.mean_term(res, "hits"), "scenario": job["scenario"], "run_id": str(job.get("id", "")),
		"indices": [first, first + total - 1]}
	if not res.is_empty() or typeof(meta.get("teacher")) != TYPE_DICTIONARY:
		meta["teacher"] = stats   # (a continued run that recorded nothing keeps the previous statistics)
	meta["next_episode"] = maxi(int(meta.get("next_episode", 0)), first + total)
	meta["updated"] = PolicyData.now_iso()
	PolicyDataset.write_meta(dataset_dir, meta)
	var rep := {"dataset": dataset_dir, "samples": samples, "episodes": res.size(), "teacher": stats, "summary": s,
		"seeds": {"stream": "rec:<job seed>:<index>", "first_index": first, "last_index": first + total - 1}, "skipped_already_recorded": skipped,
		"planned_episodes": todo.size(), "complete": _next >= todo.size(), "helper_shards_committed": batch.committed_shards}
	if stop_reason != "":
		rep["stop_reason"] = stop_reason
	write_report(rep)
	message = "recorded %d samples from %d episodes%s" % [samples, res.size(), "" if bool(rep["complete"]) else " (stopped early: %s)" % stop_reason]
	note(message)
	finished = true
	final_state = "completed"
	phase = "done"
