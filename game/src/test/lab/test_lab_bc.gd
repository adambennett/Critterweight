extends TestCase
## LAB-02 (imitation): datasets round-trip and reject damage; behaviour cloning drives the loss
## down and can overfit a tiny dataset (the optimiser and gradients really learn). Review
## findings 4 and 12: the split is by whole episodes into train / validation (early stopping) /
## test (reported), a dataset too small for that is refused with a clear message (no fallback
## that trains on held-out data), and the job reports test-episode accuracy and its split.

var dir := ""


func before_each() -> void:
	dir = temp_dir("lab_bc_%d" % Time.get_ticks_usec())
	PolicyDataset.root_override = dir.path_join("datasets")


func after_each() -> void:
	PolicyDataset.root_override = ""


## Synthetic labelled data: the move label depends on the sign of feature 1 and 2, the button
## label on feature 3 (a learnable rule over obs_v1-sized vectors).
func _data(n: int, seed_value: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var obs := PackedFloat32Array()
	var moves := PackedByteArray()
	var buttons := PackedByteArray()
	var eps := PackedInt32Array()
	for k in n:
		var row := PackedFloat32Array()
		row.resize(PolicyObs.SIZE)
		for i in PolicyObs.SIZE:
			row[i] = r.randf_range(-1.0, 1.0) if r.randf() < 0.3 else 0.0
		var a := r.randf_range(-1.0, 1.0)
		var b := r.randf_range(-1.0, 1.0)
		var c := r.randf_range(-1.0, 1.0)
		row[1] = a
		row[2] = b
		row[3] = c
		obs.append_array(row)
		moves.append(1 if a > 0.0 else (2 if b > 0.0 else 0))
		buttons.append(PolicyActions.B_LIGHT if c > 0.3 else (PolicyActions.B_GUARD_HOLD if c < -0.3 else PolicyActions.B_NONE))
		eps.append(k / 8)
	return {"obs": obs, "moves": moves, "buttons": buttons, "units": eps, "count": n, "episodes": eps}


func test_dataset_shards_round_trip_and_validation() -> void:
	var d := _data(50, 1)
	var ddir := PolicyDataset.ensure("unit_ds", "Unit dataset", "dev_biped", "test")
	var w := PolicyDataset.write_shard(ddir, d["obs"], d["moves"], d["buttons"], d["episodes"], "t")
	check(w["ok"], "shard written: %s" % str(w["error"]))
	var meta := PolicyDataset.read_meta(ddir)
	check_eq(str(meta.get("creature", "")), "dev_biped", "meta stored")
	var all := PolicyDataset.load_all(ddir)
	check(all["ok"], "loaded")
	check_eq(int(all["count"]), 50)
	check(all["obs"] == d["obs"], "observations exact")
	check(all["moves"] == d["moves"] and all["buttons"] == d["buttons"], "labels exact")
	var listed := PolicyDataset.list("dev_biped")
	check(listed.size() == 1 and int(listed[0]["samples"]) == 50, "listed with its sample count")
	# a damaged shard is skipped with a reason; the good one still loads
	var bad := ddir.path_join("shard_bad.bin")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_buffer("CWDS".to_ascii_buffer())
	f.store_16(1)
	f.store_16(PolicyObs.SIZE)
	f.store_32(1000)
	f.store_32(0)
	f.store_buffer(PackedByteArray([1, 2, 3]))
	f.close()
	var all2 := PolicyDataset.load_all(ddir)
	check_eq(int(all2["count"]), 50, "good shard still loads")
	check(("; ".join(all2["errors"])).contains("wrong length"), "damaged shard reported")
	check_eq(PolicyDataset.rename("unit_ds", "Renamed"), OK)
	check_eq(str(PolicyDataset.read_meta(ddir).get("name", "")), "Renamed")
	check_eq(PolicyDataset.delete("unit_ds"), OK)
	check(not DirAccess.dir_exists_absolute(ddir), "deleted")


func test_bc_overfits_a_tiny_dataset() -> void:
	var d := _data(64, 2)
	var net := PolicyMLP.create(PolicyObs.SIZE, PackedInt32Array([32]), PolicyActions.OUTPUTS, "tanh", 4)
	var bc := LabBC.new()
	bc.setup(d, net, PolicyActions.button_mask(Content.creature("dev_biped")), {"lr": 0.01, "l2": 0.0, "batch": 16, "seed": 1, "val_frac": 0.2})
	# overfitting test: train on everything
	bc.train_idx = PackedInt32Array(range(64))
	var all_idx := PackedInt32Array(range(64))
	var start := bc.evaluate(all_idx)
	for epoch in 120:
		bc.start_epoch()
		while not bc.train_steps(1000.0):
			pass
	var end := bc.evaluate(all_idx)
	check(float(end["loss"]) < float(start["loss"]) * 0.2, "loss fell from %.3f to %.3f" % [float(start["loss"]), float(end["loss"])])
	check(float(end["acc_joint"]) >= 0.95, "memorised the tiny dataset (joint accuracy %.2f)" % float(end["acc_joint"]))


func test_bc_generalises_on_held_out_episodes() -> void:
	var d := _data(400, 3)
	var net := PolicyMLP.create(PolicyObs.SIZE, PackedInt32Array([32]), PolicyActions.OUTPUTS, "tanh", 6)
	var bc := LabBC.new()
	bc.setup(d, net, PolicyActions.button_mask(Content.creature("dev_biped")), {"lr": 0.005, "l2": 0.0001, "batch": 32, "seed": 2, "val_frac": 0.25})
	check(bc.val_idx.size() > 50 and bc.train_idx.size() > 200, "episode split %d / %d" % [bc.train_idx.size(), bc.val_idx.size()])
	# validation units never appear in training
	var train_units := {}
	for k in bc.train_idx:
		train_units[d["units"][k]] = true
	var leak := 0
	for k in bc.val_idx:
		if train_units.has(d["units"][k]):
			leak += 1
	check_eq(leak, 0, "no episode is split between train and validation")
	var base := bc.majority_baseline(bc.val_idx)
	var v0 := bc.evaluate(bc.val_idx)
	var stopped := false
	for epoch in 40:
		bc.start_epoch()
		while not bc.train_steps(1000.0):
			pass
		if bc.end_epoch(bc.evaluate(bc.val_idx), 6):
			stopped = true
			break
	var v1 := bc.evaluate(bc.val_idx)
	check(float(v1["loss"]) < float(v0["loss"]), "validation loss decreased (%.3f -> %.3f)" % [float(v0["loss"]), float(v1["loss"])])
	check(float(v1["acc_joint"]) > float(base["acc_joint"]) + 0.15, "beats the majority baseline (%.2f vs %.2f)" % [float(v1["acc_joint"]), float(base["acc_joint"])])
	check(bc.best_epoch >= 1 and not bc.best_params.is_empty(), "best weights tracked (epoch %d, early stop %s)" % [bc.best_epoch, str(stopped)])


func test_bc_refuses_datasets_with_too_few_episodes() -> void:
	var d := _data(5 * 30, 4)
	var units := PackedInt32Array()
	for k in 5 * 30:
		units.append(k / 30)          # 5 recorded episodes of 30 decisions
	d["units"] = units
	var net := PolicyMLP.create(PolicyObs.SIZE, PackedInt32Array([8]), PolicyActions.OUTPUTS, "tanh", 1)
	var bc := LabBC.new()
	var why := bc.setup(d, net, PolicyActions.button_mask(null), {"seed": 1, "val_frac": 0.2})
	check(why.contains("episode"), "refused with a reason: %s" % why)
	check(bc.train_idx.is_empty() and bc.val_idx.is_empty(), "no fallback split (the old one cut episodes into blocks and could train on validation)")
	# the job fails with that message instead of training
	var ddir := PolicyDataset.ensure("few", "Few episodes", "dev_biped", "test")
	PolicyDataset.write_shard(ddir, d["obs"], d["moves"], d["buttons"], units, "t")
	var run := dir.path_join("run_few")
	var task := LabTaskBC.new()
	task.job = LabJob.normalize({"kind": "bc", "creature": "dev_biped", "bc": {"datasets": [ddir], "rollouts": 0},
		"output": {"save_to_library": false}})["job"]
	task.run_dir = run
	task.begin()
	check(task.finished and task.final_state == "failed", "the BC job refuses the dataset")
	check(task.message.contains("at least %d" % LabBC.MIN_EPISODES), "and says how many episodes are needed: %s" % task.message)


func test_bc_split_is_by_whole_episodes_three_ways() -> void:
	var d := _data(400, 5)
	var net := PolicyMLP.create(PolicyObs.SIZE, PackedInt32Array([8]), PolicyActions.OUTPUTS, "tanh", 1)
	var bc := LabBC.new()
	check_eq(bc.setup(d, net, PolicyActions.button_mask(null), {"seed": 9, "val_frac": 0.2, "test_frac": 0.2}), "", "50 episodes split")
	var part := {}
	var mixed := 0
	for pair in [[bc.train_idx, "train"], [bc.val_idx, "val"], [bc.test_idx, "test"]]:
		for k in (pair[0] as PackedInt32Array):
			var u := int(d["units"][k])
			if part.has(u) and str(part[u]) != str(pair[1]):
				mixed += 1
			part[u] = pair[1]
	check_eq(mixed, 0, "no episode is in two splits")
	check_eq(bc.train_idx.size() + bc.val_idx.size() + bc.test_idx.size(), 400, "every sample in exactly one split")
	var si := bc.split_info
	check_eq(str(si["mode"]), "episodes")
	check_eq(int(si["val_episodes"]), 10, "20% of 50 episodes validate")
	check_eq(int(si["test_episodes"]), 10, "20% test")
	check_eq(int(si["train_episodes"]), 30, "the rest train")
	# the smallest accepted dataset still holds out one validation and one test episode
	var small := _data(6 * 20, 6)
	var su := PackedInt32Array()
	for k in 6 * 20:
		su.append(k / 20)
	small["units"] = su
	var bc2 := LabBC.new()
	check_eq(bc2.setup(small, PolicyMLP.create(PolicyObs.SIZE, PackedInt32Array([8]), PolicyActions.OUTPUTS, "tanh", 1), PolicyActions.button_mask(null), {"seed": 1}), "")
	check(bc2.val_idx.size() == 20 and bc2.test_idx.size() == 20 and bc2.train_idx.size() == 80, "6 episodes: 4 train / 1 validation / 1 test")


## The BC job end to end (in-process, no rollouts): early stopping on validation episodes, test
## accuracy reported on other episodes, split shown in the report and the policy metadata.
func test_bc_job_reports_test_episode_accuracy() -> void:
	var d := _data(400, 7)
	var ddir := PolicyDataset.ensure("bcjob", "BC job", "dev_biped", "test")
	PolicyDataset.write_shard(ddir, d["obs"], d["moves"], d["buttons"], d["episodes"], "t")
	var run := dir.path_join("run_bc")
	DirAccess.make_dir_recursive_absolute(run)
	var task := LabTaskBC.new()
	task.job = LabJob.normalize({"kind": "bc", "creature": "dev_biped", "seed": 2, "model": {"hidden": [16]},
		"bc": {"datasets": [ddir], "rollouts": 0, "patience": 3, "lr": 0.01, "batch": 32}, "limits": {"max_epochs": 6},
		"output": {"save_to_library": false}})["job"]
	task.run_dir = run
	task.begin()
	check(not task.finished, "training starts: %s" % task.message)
	var guard := 0
	while not task.finished and guard < 2000:
		task.frame(1.0 / 120.0)
		guard += 1
	check_eq(task.final_state, "completed", "job completed: %s" % task.message)
	var rep := LabIO.read_json(run.path_join("report.json"))
	check(rep.has("test") and rep.has("final_val"), "report has test and validation accuracy")
	var sp: Dictionary = rep.get("split", {})
	check_eq(str(sp.get("mode", "")), "episodes", "split mode reported")
	check(int(sp.get("test_episodes", 0)) >= 1 and int(rep.get("test_samples", 0)) > 0, "test episodes held out")
	check(task.message.contains("test-episode accuracy"), "the run's message names the metric honestly: %s" % task.message)
	var pol := PolicyIO.read_file(run.path_join("best.policy.json"))
	check(pol["ok"], "clone saved")
	if pol["ok"]:
		var tr: Dictionary = (pol["policy"] as PolicyData).training
		check(tr.has("test_accuracy") and tr.has("split"), "policy metadata carries the test accuracy and the split")
