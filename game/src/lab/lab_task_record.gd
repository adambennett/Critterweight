class_name LabTaskRecord
extends LabTask
## Records a scripted teacher (a bot tier or drill script) into an imitation dataset: the
## teacher plays in the learner slot wrapped by PolicyRecorder, so its observations and labels
## use exactly the obs_v1/act_v1 contracts a cloned policy will see. Every rank writes its own
## shards (see LabRecordSink); the coordinator stores the teacher's statistics (action
## distribution, outcomes) in the dataset meta for later behaviour comparisons.

var dataset_dir := ""
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
	phase = "record"
	note("recording %d episodes of %s into %s" % [int(rec["episodes"]), teacher, dataset_dir])


func frame(_dt: float) -> void:
	if phase != "record":
		return
	if not _submitted:
		var rec: Dictionary = job["record"]
		var scn: Dictionary = job["scenario"]
		var opps: Array = scn["opponents"]
		var items := []
		for k in int(rec["episodes"]):
			var s := LabScenarios.seed_for("rec", int(job["seed"]), k)
			var ep := LabScenarios.episode(scn, str(opps[k % opps.size()]), s, str(job["creature"]), str(job["opponent_creature"]))
			items.append({"i": k, "learner": {"type": "scripted", "kind": str(rec["teacher"])}, "record": true, "episode": ep, "group": "teacher"})
		batch.submit(items, {"record_dir": dataset_dir})
		_submitted = true
		progress["step"] = "recording %d episodes" % items.size()
	else:
		progress["recorded_episodes"] = batch.done_count()
		if batch.poll():
			var res := batch.ordered_results()
			count_results(res)
			var samples := 0
			for r: Dictionary in res:
				samples += int(r.get("samples", 0))
			var w := weights()
			var s := LabEval.summarize(res, w, "teacher")
			var meta := PolicyDataset.read_meta(dataset_dir)
			meta["teacher"] = {"kind": str(job["record"]["teacher"]), "opponents": job["scenario"]["opponents"], "episodes": res.size(),
				"samples": samples, "label_hist": LabEval.act_hist(res, "label_hist"), "win_rate": s["win_rate"],
				"damage_dealt": LabEval.mean_term(res, "damage_dealt"), "damage_taken": LabEval.mean_term(res, "damage_taken"),
				"hits": LabEval.mean_term(res, "hits"), "scenario": job["scenario"], "run_id": str(job.get("id", ""))}
			meta["updated"] = PolicyData.now_iso()
			PolicyDataset.write_meta(dataset_dir, meta)
			write_report({"dataset": dataset_dir, "samples": samples, "teacher": meta["teacher"], "summary": s})
			message = "recorded %d samples from %d episodes" % [samples, res.size()]
			note(message)
			finished = true
			final_state = "completed"
			phase = "done"
