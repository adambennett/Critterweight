class_name LabTaskEval
extends LabTask
## Stand-alone evaluation of a saved policy against fixed baseline opponents on test seeds,
## optionally side by side with a comparison (another policy file, or a randomly initialised
## network of the same shape = "what an untrained policy does"). Writes report.json.

var target: PolicyData
var compare: PolicyData
var _submitted := false


func begin() -> void:
	var tj: Dictionary = job["target"]
	var ref := str(tj["policy"])
	if not ref.is_absolute_path() and not ref.ends_with(PolicyIO.EXT):
		# a library / built-in policy id
		target = PolicyLibrary.get_policy(ref)
		if target == null:
			finished = true
			final_state = "failed"
			message = "policy '%s' unavailable: %s" % [ref, PolicyLibrary.last_error(ref)]
			return
	else:
		var r := PolicyIO.read_file(ref)
		if not r["ok"]:
			finished = true
			final_state = "failed"
			message = "policy rejected: %s" % "; ".join(r["errors"])
			return
		target = r["policy"]
	job["creature"] = target.creature
	if str(job["opponent_creature"]) == "":
		job["opponent_creature"] = target.creature
	var cmp := str(tj.get("compare", ""))
	if cmp == "random_init":
		compare = PolicyData.create_new(target.creature, target.net.hidden, target.net.activation, int(job["seed"]) * 7 + 3)
		compare.act_mode = target.act_mode
	elif cmp != "":
		var r2 := PolicyIO.read_file(cmp, target.creature)
		if r2["ok"]:
			compare = r2["policy"]
		else:
			note("comparison policy rejected: %s" % "; ".join(r2["errors"]))
	phase = "eval"


func _payload_for(p: PolicyData, key: String, extra: Dictionary) -> Dictionary:
	var pl := payload(p.net.hidden, p.net.activation, p.act_mode, {key: p.net.params})
	for k in extra:
		pl["params"][k] = LabIO.b64_floats(extra[k])
	return pl


func frame(_dt: float) -> void:
	if phase != "eval":
		return
	if not _submitted:
		var ev: Dictionary = job["eval"]
		var opps: Array = ev["opponents"]
		var n := int(ev["episodes"])
		var std := bool(ev.get("standard_spawns", true))
		var items := LabEval.items(job, "target", "test", opps, n, std, "target", 0, target.act_mode)
		var extra := {}
		if compare != null and compare.net.hidden == target.net.hidden and compare.net.activation == target.net.activation:
			items.append_array(LabEval.items(job, "compare", "test", opps, n, std, "compare", items.size(), compare.act_mode))
			extra["compare"] = compare.net.params
		items.append_array(LabEval.reference_items(job, opps, n, std, items.size()))
		batch.submit(items, _payload_for(target, "target", extra))
		_submitted = true
		progress["step"] = "evaluating (%d episodes)" % items.size()
	elif batch.poll():
		var res := batch.ordered_results()
		count_results(res)
		var w := weights()
		var rep := {"policy": target.summary(), "target": LabEval.summarize(res, w, "target"), "objective": job["objective"],
			"opponents": job["eval"]["opponents"], "episodes_per_opponent": job["eval"]["episodes"],
			"decision_us_mean": LabStats.mean(_decision_us(res)), "act_hist": LabEval.act_hist(res, "act_hist", "target")}
		if compare != null:
			rep["compare_label"] = str(job["target"]["compare"])
			rep["compare"] = LabEval.summarize(res, w, "compare")
		var s_ref := LabEval.summarize(res, w, "reference")
		if int(s_ref["n"]) > 0:
			rep["reference_kind"] = str(job["eval"].get("reference", ""))
			rep["reference"] = s_ref
		write_report(rep)
		note("evaluation: %s" % LabEval.one_line(rep["target"]))
		message = "evaluated: " + LabEval.one_line(rep["target"])
		finished = true
		final_state = "completed"
		phase = "done"


static func _decision_us(res: Array) -> Array:
	var out := []
	for r: Dictionary in res:
		if float(r.get("decision_us", 0.0)) > 0.0:
			out.append(float(r["decision_us"]))
	return out
