class_name LabTaskEval
extends LabTask
## Stand-alone evaluation of a saved policy against fixed baseline opponents on test seeds,
## optionally side by side with a comparison (another policy file, or a randomly initialised
## network of the same shape = "what an untrained policy does") and a scripted reference, all on
## the same episodes. Writes report.json with a paired test per comparison.
## The policy plays exactly as saved: its own action mode, temperature, perception lag, decision
## rate and button mask (a comparison file keeps its own; the random network borrows the
## target's). The episodes are played in short batches, so the job's limits (time, episodes)
## and a stop request end it after the current batch with an honest partial report.

var target: PolicyData
var compare: PolicyData
var conds: Array = []
var results: Array = []
var _next := 0
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
	play = LabTask.play_of(target)
	var cmp := str(tj.get("compare", ""))
	if cmp == "random_init":
		compare = PolicyData.create_new(target.creature, target.net.hidden, target.net.activation, int(job["seed"]) * 7 + 3)
		compare.act_mode = target.act_mode
		compare.temperature = target.temperature
		compare.target_lag = target.target_lag
		compare.decision_hz = target.decision_hz
		compare.button_mask = target.button_mask.duplicate()
	elif cmp != "":
		var r2 := PolicyIO.read_file(cmp, target.creature)
		if r2["ok"]:
			compare = r2["policy"]
		else:
			note("comparison policy rejected: %s" % "; ".join(r2["errors"]))
	if compare != null and (compare.net.hidden != target.net.hidden or compare.net.activation != target.net.activation):
		note("comparison policy has another network shape; it is not evaluated")
		compare = null
	var ev: Dictionary = job["eval"]
	conds = LabEval.conditions(job, "test", ev["opponents"], int(ev["episodes"]), bool(ev.get("standard_spawns", true)))
	phase = "eval"


## The batch payload: the target (and comparison) parameters, each with its own play settings.
func make_payload() -> Dictionary:
	var params := {"target": target.net.params}
	var by_key := {"target": policy_meta(target.act_mode, LabTask.play_of(target))}
	if compare != null:
		params["compare"] = compare.net.params
		by_key["compare"] = policy_meta(compare.act_mode, LabTask.play_of(compare))
	return payload(target.net.hidden, target.net.activation, target.act_mode, params, by_key)


## Items for episode conditions [a, b): every compared group plays the same episodes.
func items_for_range(a: int, b: int) -> Array:
	var part := conds.slice(a, b)
	var items := LabEval.items_for(part, "target", "target", 0, target.act_mode)
	if compare != null:
		items.append_array(LabEval.items_for(part, "compare", "compare", items.size(), compare.act_mode))
	items.append_array(LabEval.reference_items_for(job, part, items.size()))
	return items


func _limit_reason() -> String:
	if stop_requested != "":
		return stop_requested
	var lim: Dictionary = job["limits"]
	if int(lim["max_episodes"]) > 0 and episodes >= int(lim["max_episodes"]):
		return "episode limit (%d)" % int(lim["max_episodes"])
	return ""


func frame(_dt: float) -> void:
	if phase != "eval":
		return
	if not _submitted:
		var why := _limit_reason()
		if _next >= conds.size() or why != "":
			_finish(why)
			return
		var groups := 1 + (1 if compare != null else 0) + (1 if LabOpponents.BASELINES.has(str(job["eval"].get("reference", ""))) else 0)
		var b := mini(_next + maxi(1, chunk_size() / groups), conds.size())
		batch.submit(items_for_range(_next, b), make_payload())
		_next = b
		_submitted = true
		progress["step"] = "evaluating (episodes %d of %d per policy)" % [_next, conds.size()]
	elif batch.poll():
		_submitted = false
		var res := batch.ordered_results()
		count_results(res)
		results.append_array(res)


func _finish(stop_reason: String) -> void:
	var res := results
	var w := weights()
	var rep := {"policy": target.summary(), "target": LabEval.summarize(res, w, "target"), "objective": job["objective"],
		"opponents": job["eval"]["opponents"], "episodes_per_opponent": job["eval"]["episodes"],
		"planned_episodes": conds.size(), "played_episodes": _next, "complete": _next >= conds.size(),
		"play": play_settings(), "decision_us_mean": LabStats.mean(_decision_us(res)), "act_hist": LabEval.act_hist(res, "act_hist", "target")}
	if stop_reason != "":
		rep["stop_reason"] = stop_reason
	if compare != null:
		rep["compare_label"] = str(job["target"]["compare"])
		rep["compare"] = LabEval.summarize(res, w, "compare")
		rep["paired_compare"] = LabEval.compare(res, w, "target", "compare")
	var s_ref := LabEval.summarize(res, w, "reference")
	if int(s_ref["n"]) > 0:
		rep["reference_kind"] = str(job["eval"].get("reference", ""))
		rep["reference"] = s_ref
		rep["paired_reference"] = LabEval.compare(res, w, "target", "reference")
	write_report(rep)
	note("evaluation: %s" % LabEval.one_line(rep["target"]))
	if rep.has("paired_compare"):
		note("policy − %s, %s" % [str(rep["compare_label"]), LabEval.paired_line(rep["paired_compare"])])
	if rep.has("paired_reference"):
		note("policy − %s, %s" % [str(rep["reference_kind"]), LabEval.paired_line(rep["paired_reference"])])
	var part := "" if bool(rep["complete"]) else " (stopped early: %s; %d of %d planned episodes)" % [stop_reason, _next, conds.size()]
	message = "evaluated%s: %s" % [part, LabEval.one_line(rep["target"])]
	finished = true
	final_state = "completed"
	phase = "done"


static func _decision_us(res: Array) -> Array:
	var out := []
	for r: Dictionary in res:
		if float(r.get("decision_us", 0.0)) > 0.0:
			out.append(float(r["decision_us"]))
	return out
