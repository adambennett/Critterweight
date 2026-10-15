class_name LabTaskES
extends LabTask
## Evolution-strategies training job (approach "es"; also "bc→es" when started from a cloned
## policy via model.init_policy). Each generation evaluates 2·pairs mirrored candidates on the
## same training episodes (common random numbers), shapes fitness by rank and takes one Adam
## step on the mean θ.
## Model selection: ES improves the noise-smoothed objective, so early on the mean θ can play
## worse than its best perturbations. Every `eval.every` generations both θ and the generation's
## best candidate ("elite") are evaluated on VALIDATION seeds; the best validated network is
## kept. At the end the initial and the selected network are evaluated on separate TEST seeds
## (and, if configured, a scripted reference on the same episodes), so the reported improvement
## is measured on episodes neither training nor selection ever saw.

var es := LabES.new()
var gen := 0
var hidden := PackedInt32Array()
var activation := "tanh"
var act_mode := "argmax"
var theta0 := PackedFloat32Array()
var best_theta := PackedFloat32Array()
var best_val := -INF
var best_gen := 0
var best_source := "initial"
var elite := PackedFloat32Array()
var elite_fit := -INF
var last_val := {}
var last_fit := {}
var _submitted := false
var _gen_t0 := 0


func begin() -> void:
	var model: Dictionary = job["model"]
	var init := load_init_policy(str(model.get("init_policy", "")))
	if init != null:
		hidden = init.net.hidden.duplicate()
		activation = init.net.activation
		theta0 = init.net.params.duplicate()
		act_mode = init.act_mode
		note("starting from policy '%s' (%s, %d params)" % [init.name, str(init.training.get("approach", "?")), theta0.size()])
	else:
		hidden = PackedInt32Array(model["hidden"])
		activation = str(model["activation"])
		var seed_init := int(model.get("init_seed", 0))
		var mlp := PolicyMLP.create(PolicyObs.SIZE, hidden, PolicyActions.OUTPUTS, activation, seed_init if seed_init != 0 else int(job["seed"]) * 7 + 3,
			float(model.get("out_scale", 0.01)))
		theta0 = mlp.params
	if str(model.get("mode", "")) != "":
		act_mode = str(model["mode"])
	var esj: Dictionary = job["es"]
	es.setup(theta0, int(esj["pairs"]), float(esj["sigma"]), float(esj["lr"]), float(esj["l2"]), int(job["seed"]))
	var ck := load_checkpoint()
	if not ck.is_empty() and es.from_dict(ck.get("es", {})):
		gen = int(ck.get("gen", 0))
		theta0 = LabIO.floats_b64(str(ck.get("theta0", "")))
		best_theta = LabIO.floats_b64(str(ck.get("best_theta", "")))
		best_val = float(ck.get("best_val", -1e30))
		best_gen = int(ck.get("best_gen", 0))
		best_source = str(ck.get("best_source", "theta"))
		elite = LabIO.floats_b64(str(ck.get("elite", "")))
		elite_fit = float(ck.get("elite_fit", -1e30))
		phase = str(ck.get("phase", "gen"))
		if phase not in ["gen", "val", "final"]:
			phase = "gen"
		if best_theta.size() != es.theta.size():
			best_theta = es.theta.duplicate()
		if elite.size() != es.theta.size():
			elite = PackedFloat32Array()
		LabIO.truncate_lines(run_dir.path_join("metrics.jsonl"), "gen", gen)
		note("resumed at generation %d (best validation reward %.2f at gen %d)" % [gen, best_val, best_gen])
	else:
		best_theta = es.theta.duplicate()
		phase = "baseline"
		note("ES: %d params, %d candidates x %d episodes per generation, sigma %.3f, lr %.3f" % [es.theta.size(), es.population(),
			int(esj["episodes_per_candidate"]), es.sigma, es.lr])


func _check_limits() -> void:
	var lim: Dictionary = job["limits"]
	if gen >= int(lim["max_generations"]):
		request_stop("generation limit (%d)" % int(lim["max_generations"]))
	elif int(lim["max_episodes"]) > 0 and episodes >= int(lim["max_episodes"]):
		request_stop("episode limit (%d)" % int(lim["max_episodes"]))


func _train_items() -> Array:
	var items := []
	var scn: Dictionary = job["scenario"]
	var opps: Array = scn["opponents"]
	var per := int(job["es"]["episodes_per_candidate"])
	var eps := []
	for e in per:
		var s := LabScenarios.seed_for("train", int(job["seed"]), gen, e)
		var opp := str(opps[(gen * per + e) % opps.size()])
		eps.append(LabScenarios.episode(scn, opp, s, str(job["creature"]), str(job["opponent_creature"])))
	var i := 0
	for k in es.population():
		var spec := es.candidate_spec(gen, k)
		for e in per:
			items.append({"i": i, "policy": {"key": "theta", "noise_seed": spec["noise_seed"], "sign": spec["sign"], "sigma": spec["sigma"]},
				"episode": eps[e], "cand": k, "group": "train"})
			i += 1
	return items


func _payload(params: Dictionary) -> Dictionary:
	return payload(hidden, activation, act_mode, params)


func _val_items() -> Array:
	var ev: Dictionary = job["eval"]
	var opps: Array = job["scenario"]["opponents"]
	var n := int(ev["val_episodes"])
	var items := LabEval.items(job, "theta", "val", opps, n, false, "val", 0)
	if not elite.is_empty():
		items.append_array(LabEval.items(job, "elite", "val", opps, n, false, "val_elite", items.size()))
	return items


func frame(_dt: float) -> void:
	match phase:
		"baseline":
			if not _submitted:
				var ev: Dictionary = job["eval"]
				batch.submit(LabEval.items(job, "theta", "val", job["scenario"]["opponents"], int(ev["val_episodes"]), false, "val", 0), _payload({"theta": es.theta}))
				_submitted = true
				progress["step"] = "baseline evaluation"
			elif batch.poll():
				_submitted = false
				var res := batch.ordered_results()
				count_results(res)
				_record_val(res)
				phase = "gen"
				save_checkpoint(gen, _ck())
		"gen":
			if not _submitted:
				_check_limits()
				if stop_requested != "":
					phase = "final"
					return
				_gen_t0 = Time.get_ticks_msec()
				batch.submit(_train_items(), _payload({"theta": es.theta}))
				_submitted = true
				progress["step"] = "generation %d" % (gen + 1)
			elif batch.poll():
				_submitted = false
				_finish_generation(batch.ordered_results())
		"val":
			if not _submitted:
				var params := {"theta": es.theta}
				if not elite.is_empty():
					params["elite"] = elite
				batch.submit(_val_items(), _payload(params))
				_submitted = true
				progress["step"] = "validation after generation %d" % gen
			elif batch.poll():
				_submitted = false
				var res2 := batch.ordered_results()
				count_results(res2)
				_record_val(res2)
				phase = "gen"
				save_checkpoint(gen, _ck())
		"final":
			if not _submitted:
				var ev3: Dictionary = job["eval"]
				var opps: Array = ev3["opponents"]
				var n := int(ev3["episodes"])
				var std := bool(ev3.get("standard_spawns", true))
				var items := LabEval.items(job, "init", "test", opps, n, std, "init", 0)
				items.append_array(LabEval.items(job, "best", "test", opps, n, std, "best", items.size()))
				items.append_array(LabEval.reference_items(job, opps, n, std, items.size()))
				batch.submit(items, _payload({"init": theta0, "best": best_theta}))
				_submitted = true
				progress["step"] = "final test evaluation (%d episodes)" % items.size()
				save_checkpoint(gen, _ck())
			elif batch.poll():
				_submitted = false
				var res3 := batch.ordered_results()
				count_results(res3)
				_finish(res3)


func _finish_generation(res: Array) -> void:
	count_results(res)
	var pop := es.population()
	var per := int(job["es"]["episodes_per_candidate"])
	var fit := PackedFloat32Array()
	fit.resize(pop)
	var w := weights()
	var counts := PackedInt32Array()
	counts.resize(pop)
	var dealt := 0.0
	var wins := 0
	var errs := 0
	for r: Dictionary in res:
		if r.has("error"):
			errs += 1
			continue
		var k := int(r.get("i", 0)) / per
		fit[k] += LabRewards.score(r.get("raw", {}), w)
		counts[k] += 1
		dealt += float((r.get("raw", {}) as Dictionary).get("damage_dealt", 0.0))
		if str(r.get("outcome", "")) == "win":
			wins += 1
	var top := 0
	for k in pop:
		fit[k] = fit[k] / float(maxi(counts[k], 1))
		if fit[k] > fit[top]:
			top = k
	# the generation's best candidate, rebuilt from the pre-update mean (validated later)
	var spec := es.candidate_spec(gen, top)
	elite = LabES.perturbed(es.theta, int(spec["noise_seed"]), float(spec["sign"]), float(spec["sigma"]))
	elite_fit = fit[top]
	var ups := es.update(gen, fit)
	gen += 1
	var fl := Array(fit)
	var stats := LabStats.describe(fl)
	var n_ok := maxi(res.size() - errs, 1)
	last_fit = {"gen": gen, "fit_mean": stats["mean"], "fit_std": stats["std"], "fit_max": fl.max(), "fit_min": fl.min(),
		"pop_damage": dealt / float(n_ok), "pop_win_rate": float(wins) / float(n_ok), "grad_norm": ups["grad_norm"],
		"step_norm": ups["step_norm"], "theta_norm": ups["theta_norm"], "gen_wall_s": (Time.get_ticks_msec() - _gen_t0) / 1000.0,
		"errors": errs}
	metrics(last_fit.duplicate())
	progress["generation"] = gen
	progress["fitness_mean"] = stats["mean"]
	progress["fitness_max"] = fl.max()
	note("gen %d: fitness %.2f ± %.2f (max %.2f), pop damage %.1f, |step| %.4f" % [gen, float(stats["mean"]), float(stats["std"]), float(fl.max()), dealt / float(n_ok), float(ups["step_norm"])])
	if gen % int(job["eval"]["every"]) == 0:
		phase = "val"
	save_checkpoint(gen, _ck())


func _record_val(res: Array) -> void:
	var w := weights()
	var s := LabEval.summarize(res, w, "val")
	var v := float((s["reward"] as Dictionary)["mean"])
	last_val = {"gen": gen, "eval_reward": v, "eval_reward_std": (s["reward"] as Dictionary)["std"], "eval_n": s["n"],
		"eval_damage": LabEval.mean_term(res, "damage_dealt", "val"), "eval_taken": LabEval.mean_term(res, "damage_taken", "val"),
		"eval_win_rate": s["win_rate"]}
	var cand := v
	var cand_params := es.theta
	var cand_src := "theta"
	var se := LabEval.summarize(res, w, "val_elite")
	if int(se["n"]) > 0:
		var ve := float((se["reward"] as Dictionary)["mean"])
		last_val["eval_elite_reward"] = ve
		if ve > cand:
			cand = ve
			cand_params = elite
			cand_src = "elite"
	if cand > best_val:
		best_val = cand
		best_gen = gen
		best_theta = cand_params.duplicate()
		best_source = cand_src if gen > 0 else "initial"
		last_val["new_best"] = true
	last_val["best_eval_reward"] = best_val
	metrics(last_val.duplicate())
	progress["eval_reward"] = v
	progress["best_eval_reward"] = best_val
	progress["best_gen"] = best_gen
	note("validation at gen %d: %s%s%s" % [gen, LabEval.one_line(s), (" | elite %.2f" % float(last_val["eval_elite_reward"])) if last_val.has("eval_elite_reward") else "",
		" (new best: %s)" % best_source if gen == best_gen else ""])


func _ck() -> Dictionary:
	return {"gen": gen, "es": es.to_dict(), "theta0": LabIO.b64_floats(theta0), "best_theta": LabIO.b64_floats(best_theta),
		"best_val": best_val if is_finite(best_val) else -1e30, "best_gen": best_gen, "best_source": best_source,
		"elite": LabIO.b64_floats(elite), "elite_fit": elite_fit if is_finite(elite_fit) else -1e30}


func _finish(res: Array) -> void:
	var w := weights()
	var s_init := LabEval.summarize(res, w, "init")
	var s_best := LabEval.summarize(res, w, "best")
	var r_init := []
	var r_best := []
	for r: Dictionary in res:
		if r.has("error"):
			continue
		var rw := LabRewards.score(r.get("raw", {}), w)
		match str(r.get("group", "")):
			"init":
				r_init.append(rw)
			"best":
				r_best.append(rw)
	var t := LabStats.welch_t(r_best, r_init)
	note("test: initial %s" % LabEval.one_line(s_init))
	note("test: trained %s (Welch t = %.2f)" % [LabEval.one_line(s_best), t])
	var s_ref := LabEval.summarize(res, w, "reference")
	if int(s_ref["n"]) > 0:
		note("test: scripted reference (%s) %s" % [str(job["eval"].get("reference", "")), LabEval.one_line(s_ref)])
	var approach := "es" if str(job["model"].get("init_policy", "")) == "" else "bc_es"
	var extra := {"generations": gen, "best_gen": best_gen, "best_source": best_source, "es": job["es"],
		"selection": "best validation reward among the mean and each validation step's elite",
		"test_eval": {"initial": s_init, "trained": s_best, "welch_t": t}, "val_best_reward": best_val}
	if int(s_ref["n"]) > 0:
		extra["test_eval"]["reference"] = s_ref
		extra["test_eval"]["reference_kind"] = str(job["eval"].get("reference", ""))
	var best_pol := make_policy(hidden, activation, best_theta, act_mode, approach, extra)
	policy_id = publish_policy(best_pol, "best.policy.json", true)
	var final_pol := make_policy(hidden, activation, es.theta, act_mode, approach, {"generations": gen, "note": "mean after the last generation (not selected)"})
	final_pol.id = best_pol.id + "_last"
	publish_policy(final_pol, "final.policy.json", false)
	write_report({"approach": approach, "generations": gen, "best_gen": best_gen, "best_source": best_source, "episodes": episodes,
		"sim_seconds": sim_seconds(), "wall_s": elapsed_s, "initial": s_init, "trained": s_best, "welch_t": t,
		"reference": s_ref if int(s_ref["n"]) > 0 else {}, "reference_kind": str(job["eval"].get("reference", "")),
		"policy_id": policy_id, "stop_reason": stop_requested, "seeds": {"job": int(job["seed"]), "train": "train:<seed>:<gen>:<k>",
			"validation": "val:<seed>:<i>", "test": "test:<seed>:<i>"}})
	message = "completed (%s): trained policy %s" % [stop_requested if stop_requested != "" else "done", LabEval.one_line(s_best)]
	finished = true
	final_state = "completed"
	phase = "done"
