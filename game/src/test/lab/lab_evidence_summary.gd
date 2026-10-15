extends SceneTree
## Collects AI Lab run folders into one evidence summary (not part of --test):
##   godot --headless --path game -s res://src/test/lab/lab_evidence_summary.gd -- \
##         --runs "<run dir>;<run dir>;..." --out <summary.json>
## Copies nothing; reads report.json, metrics.jsonl, job_effective.json and progress.json of
## every run and writes the numbers the evidence report quotes (per run and pooled).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--runs")
	var j := args.find("--out")
	if i < 0 or j < 0 or i + 1 >= args.size() or j + 1 >= args.size():
		printerr("usage: -- --runs \"dir;dir\" --out summary.json")
		quit(2)
		return
	var runs := []
	var pooled_gain := []
	for d in args[i + 1].split(";", false):
		var dir := d.strip_edges().replace("\\", "/")
		var rep := _json(dir.path_join("report.json"))
		var job := _json(dir.path_join("job_effective.json"))
		var pr := _json(dir.path_join("progress.json"))
		var lines := _lines(dir.path_join("metrics.jsonl"))
		var r := {"run": dir.get_file(), "kind": job.get("kind", ""), "name": job.get("name", ""), "seed": job.get("seed", 0),
			"workers": (job.get("limits", {}) as Dictionary).get("workers", 1), "episodes": pr.get("episodes", 0),
			"elapsed_s": pr.get("elapsed_s", 0.0), "sim_s": pr.get("sim_s", 0.0), "sim_speed": pr.get("sim_speed", 0.0),
			"eps_per_hour": pr.get("eps_per_hour", 0.0)}
		if rep.has("initial") and rep.has("trained"):
			r["initial"] = _brief(rep["initial"])
			r["trained"] = _brief(rep["trained"])
			r["welch_t"] = rep.get("welch_t", 0.0)
			r["generations"] = rep.get("generations", 0)
			r["best_gen"] = rep.get("best_gen", 0)
			r["best_source"] = rep.get("best_source", "")
			if typeof(rep.get("reference")) == TYPE_DICTIONARY and not (rep["reference"] as Dictionary).is_empty():
				r["reference"] = _brief(rep["reference"])
				r["reference_kind"] = rep.get("reference_kind", "")
			pooled_gain.append(float(r["trained"]["reward_mean"]) - float(r["initial"]["reward_mean"]))
			var curve := []
			for l: Dictionary in lines:
				var pt := {"gen": l.get("gen", 0)}
				for k in ["fit_mean", "fit_max", "eval_reward", "eval_elite_reward", "best_eval_reward"]:
					if l.has(k):
						pt[k] = l[k]
				curve.append(pt)
			r["curve"] = curve
		if rep.has("final_val"):
			for k in ["samples", "train_samples", "val_samples", "epochs", "best_epoch", "best_val_loss", "final_val", "untrained_val",
					"majority_baseline", "tvd_move", "tvd_button"]:
				if rep.has(k):
					r[k] = rep[k]
			if rep.has("clone_rollouts"):
				r["clone_rollouts"] = _brief(rep["clone_rollouts"])
			if rep.has("teacher_rollouts"):
				r["teacher_rollouts"] = _brief(rep["teacher_rollouts"])
			var curve2 := []
			for l: Dictionary in lines:
				curve2.append(l)
			r["curve"] = curve2
		if rep.has("samples") and rep.has("teacher") and not rep.has("final_val"):
			r["samples"] = rep["samples"]
			r["teacher_summary"] = _brief(rep.get("summary", {}))
		runs.append(r)
	var out := {"created": Time.get_datetime_string_from_system(true), "runs": runs}
	if not pooled_gain.is_empty():
		out["es_reward_gain"] = {"per_run": pooled_gain, "mean": _mean(pooled_gain), "min": pooled_gain.min(), "max": pooled_gain.max()}
	var f := FileAccess.open(args[j + 1], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("wrote ", args[j + 1])
	quit(0)


func _brief(s: Dictionary) -> Dictionary:
	var rw: Dictionary = s.get("reward", {})
	var out := {"n": s.get("n", 0), "reward_mean": rw.get("mean", 0.0), "reward_std": rw.get("std", 0.0), "reward_ci95": rw.get("ci95", []),
		"win_rate": s.get("win_rate", 0.0), "win_ci95": s.get("win_ci95", [])}
	var dd := []
	var dt := []
	var hits := []
	for o: Dictionary in s.get("per_opponent", []):
		dd.append(float((o["damage_dealt"] as Dictionary)["mean"]))
		dt.append(float((o["damage_taken"] as Dictionary)["mean"]))
		hits.append(float((o["hits"] as Dictionary)["mean"]))
	out["damage_dealt_mean"] = _mean(dd)
	out["damage_taken_mean"] = _mean(dt)
	out["hits_mean"] = _mean(hits)
	return out


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / float(a.size())


func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _lines(path: String) -> Array:
	var out := []
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var d = JSON.parse_string(line)
		if typeof(d) == TYPE_DICTIONARY:
			out.append(d)
	return out
