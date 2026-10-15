class_name LabTaskBC
extends LabTask
## Behaviour-cloning job (approach "bc"): loads imitation datasets, trains the act_v1 heads with
## minibatch Adam + early stopping on a held-out split (whole episodes), then measures how close
## the clone is to its teacher:
##  * offline: accuracy of the clone's argmax actions vs the teacher's labels on held-out data,
##    next to the majority-class baseline and the untrained network;
##  * online (when the dataset's teacher is a scripted bot): the clone and the teacher each play
##    the same test-seed episodes against the same opponents; outcome statistics and action
##    distributions (total variation distance) are compared.

var bc := LabBC.new()
var hidden := PackedInt32Array()
var activation := "tanh"
var data := {}
var teacher := {}
var init_val := {}
var baseline := {}
var _submitted := false
var _epoch_t0 := 0


func begin() -> void:
	var bcj: Dictionary = job["bc"]
	var obs := PackedFloat32Array()
	var moves := PackedByteArray()
	var buttons := PackedByteArray()
	var units := PackedInt32Array()
	var count := 0
	var unit_base := 0
	for dpath in bcj["datasets"]:
		var r := PolicyDataset.load_all(str(dpath))
		for e in r["errors"]:
			note("dataset %s: %s" % [str(dpath).get_file(), str(e)])
		if not r["ok"]:
			continue
		var meta: Dictionary = r["meta"]
		if str(meta.get("creature", job["creature"])) != str(job["creature"]):
			note("warning: dataset %s was recorded with '%s', training '%s'" % [str(dpath).get_file(), str(meta.get("creature", "")), str(job["creature"])])
		if teacher.is_empty() and typeof(meta.get("teacher")) == TYPE_DICTIONARY:
			teacher = meta["teacher"]
		obs.append_array(r["obs"])
		moves.append_array(r["moves"])
		buttons.append_array(r["buttons"])
		var u: PackedInt32Array = r["units"]
		var mx := 0
		for k in u.size():
			units.append(unit_base + u[k])
			mx = maxi(mx, u[k])
		unit_base += mx + 1
		count += int(r["count"])
	data = {"obs": obs, "moves": moves, "buttons": buttons, "units": units, "count": count}
	if int(data["count"]) < 20:
		finished = true
		final_state = "failed"
		message = "not enough recorded samples (%d) — record some matches first" % int(data["count"])
		return
	var model: Dictionary = job["model"]
	var init := load_init_policy(str(model.get("init_policy", "")))
	var net: PolicyMLP
	if init != null:
		net = init.net.clone()
	else:
		hidden = PackedInt32Array(model["hidden"])
		activation = str(model["activation"])
		var seed_init := int(model.get("init_seed", 0))
		net = PolicyMLP.create(PolicyObs.SIZE, hidden, PolicyActions.OUTPUTS, activation, seed_init if seed_init != 0 else int(job["seed"]) * 7 + 3)
	hidden = net.hidden.duplicate()
	activation = net.activation
	var c: CreatureDef = Content.creature(str(job["creature"]))
	bc.setup(data, net, PolicyActions.button_mask(c), {"lr": bcj["lr"], "l2": bcj["l2"], "batch": bcj["batch"], "seed": job["seed"],
		"val_frac": bcj["val_frac"], "balance": bcj["balance"]})
	note("BC: %d samples (%d train / %d validation), %d params" % [bc.sample_count(), bc.train_idx.size(), bc.val_idx.size(), net.params.size()])
	init_val = bc.evaluate(bc.val_idx)
	baseline = bc.majority_baseline(bc.val_idx)
	var ck := load_checkpoint()
	if not ck.is_empty() and bc.from_dict(ck.get("bc", {})):
		init_val = ck.get("init_val", init_val)
		phase = str(ck.get("phase", "train"))
		if phase not in ["train", "rollout", "final"]:
			phase = "train"
		LabIO.truncate_lines(run_dir.path_join("metrics.jsonl"), "epoch", bc.epoch)
		note("resumed at epoch %d (best validation loss %.4f at epoch %d)" % [bc.epoch, bc.best_val, bc.best_epoch])
	else:
		metrics({"epoch": 0, "val_loss": init_val["loss"], "val_acc_move": init_val["acc_move"], "val_acc_button": init_val["acc_button"],
			"val_acc_joint": init_val["acc_joint"], "base_acc_move": baseline["acc_move"], "base_acc_button": baseline["acc_button"],
			"base_acc_joint": baseline["acc_joint"]})
		phase = "train"
	bc.start_epoch()
	_epoch_t0 = Time.get_ticks_msec()


func frame(_dt: float) -> void:
	match phase:
		"train":
			var lim: Dictionary = job["limits"]
			if stop_requested != "":
				_end_training()
				return
			if not bc.train_steps(25.0):
				progress["epoch_progress"] = bc.epoch_progress()
				return
			var val := bc.evaluate(bc.val_idx)
			var stop := bc.end_epoch(val, int(job["bc"]["patience"]))
			var tl := bc.train_loss()
			metrics({"epoch": bc.epoch, "train_loss": tl, "val_loss": val["loss"], "val_acc_move": val["acc_move"],
				"val_acc_button": val["acc_button"], "val_acc_joint": val["acc_joint"], "epoch_wall_s": (Time.get_ticks_msec() - _epoch_t0) / 1000.0,
				"samples_seen": bc.samples_seen})
			progress["epoch"] = bc.epoch
			progress["train_loss"] = tl
			progress["val_loss"] = val["loss"]
			progress["val_acc_joint"] = val["acc_joint"]
			progress["best_val_loss"] = bc.best_val
			note("epoch %d: train %.4f, val %.4f, acc move %.1f%% button %.1f%% joint %.1f%%" % [bc.epoch, tl, float(val["loss"]),
				100.0 * float(val["acc_move"]), 100.0 * float(val["acc_button"]), 100.0 * float(val["acc_joint"])])
			save_checkpoint(bc.epoch, _ck())
			if stop:
				request_stop("early stopping (no validation improvement for %d epochs)" % int(job["bc"]["patience"]))
			elif bc.epoch >= int(lim["max_epochs"]):
				request_stop("epoch limit (%d)" % int(lim["max_epochs"]))
			if stop_requested != "":
				_end_training()
			else:
				bc.start_epoch()
				_epoch_t0 = Time.get_ticks_msec()
		"rollout":
			if not _submitted:
				var items := _rollout_items()
				if items.is_empty():
					phase = "final"
					return
				batch.submit(items, payload(hidden, activation, "sample", {"clone": bc.net.params}))
				_submitted = true
				progress["step"] = "behaviour comparison (%d episodes)" % items.size()
			elif batch.poll():
				_submitted = false
				var res := batch.ordered_results()
				count_results(res)
				_finish(res)
		"final":
			_finish([])


func _end_training() -> void:
	bc.net.set_params(bc.best_params)
	phase = "rollout" if int(job["bc"]["rollouts"]) > 0 else "final"
	save_checkpoint(bc.epoch, _ck())


func _rollout_items() -> Array:
	var n := int(job["bc"]["rollouts"])
	var opps: Array = job["eval"]["opponents"]
	var t_opps: Array = teacher.get("opponents", []) if typeof(teacher.get("opponents")) == TYPE_ARRAY else []
	if not t_opps.is_empty():
		opps = t_opps
	var items := LabEval.items(job, "clone", "test", opps, n, false, "clone", 0, "sample")
	var tk := str(teacher.get("kind", ""))
	if tk != "" and LabOpponents.BASELINES.has(tk):
		var t_items := LabEval.items(job, "clone", "test", opps, n, false, "teacher", items.size())
		for it: Dictionary in t_items:
			it["learner"] = {"type": "scripted", "kind": tk}
			it["record"] = true
		items.append_array(t_items)
	return items


func _ck() -> Dictionary:
	return {"bc": bc.to_dict(), "init_val": init_val}


func _finish(res: Array) -> void:
	var val := bc.evaluate(bc.val_idx)
	var w := weights()
	var rep := {"approach": "bc", "samples": bc.sample_count(), "train_samples": bc.train_idx.size(), "val_samples": bc.val_idx.size(),
		"epochs": bc.epoch, "best_epoch": bc.best_epoch, "best_val_loss": bc.best_val, "final_val": val, "untrained_val": init_val,
		"majority_baseline": baseline, "teacher": teacher, "teacher_label_hist_val": bc.label_hist(bc.val_idx)}
	if not res.is_empty():
		var s_clone := LabEval.summarize(res, w, "clone")
		rep["clone_rollouts"] = s_clone
		var clone_hist := LabEval.act_hist(res, "act_hist", "clone")
		rep["clone_act_hist"] = clone_hist
		var teach_hist: Array = LabEval.act_hist(res, "label_hist", "teacher")
		var has_teacher := false
		for x in teach_hist:
			if int(x) > 0:
				has_teacher = true
				break
		if not has_teacher:
			teach_hist = bc.label_hist(bc.val_idx)
		else:
			rep["teacher_rollouts"] = LabEval.summarize(res, w, "teacher")
		rep["teacher_act_hist"] = teach_hist
		rep["tvd_move"] = LabStats.tvd(clone_hist.slice(0, PolicyActions.MOVE_COUNT), teach_hist.slice(0, PolicyActions.MOVE_COUNT))
		rep["tvd_button"] = LabStats.tvd(clone_hist.slice(PolicyActions.MOVE_COUNT), teach_hist.slice(PolicyActions.MOVE_COUNT))
		note("clone vs teacher action distribution: TVD move %.3f, button %.3f" % [float(rep["tvd_move"]), float(rep["tvd_button"])])
		note("clone rollouts: %s" % LabEval.one_line(s_clone))
		if rep.has("teacher_rollouts"):
			note("teacher rollouts: %s" % LabEval.one_line(rep["teacher_rollouts"]))
	var extra := {"epochs": bc.epoch, "best_epoch": bc.best_epoch, "datasets": job["bc"]["datasets"], "samples": bc.sample_count(),
		"val_accuracy": {"move": val["acc_move"], "button": val["acc_button"], "joint": val["acc_joint"]}, "val_loss": val["loss"],
		"majority_baseline": baseline, "bc": job["bc"], "teacher": str(teacher.get("kind", "human/unknown"))}
	if rep.has("tvd_move"):
		extra["tvd"] = {"move": rep["tvd_move"], "button": rep["tvd_button"]}
	var pol := make_policy(hidden, activation, bc.net.params, "sample", "bc", extra)
	policy_id = publish_policy(pol, "best.policy.json", true)
	rep["policy_id"] = policy_id
	rep["stop_reason"] = stop_requested
	write_report(rep)
	message = "completed: validation accuracy move %.0f%%, button %.0f%% (majority baseline %.0f%% / %.0f%%)" % [100.0 * float(val["acc_move"]),
		100.0 * float(val["acc_button"]), 100.0 * float(baseline["acc_move"]), 100.0 * float(baseline["acc_button"])]
	finished = true
	final_state = "completed"
	phase = "done"
