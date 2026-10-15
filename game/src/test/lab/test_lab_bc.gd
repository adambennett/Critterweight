extends TestCase
## LAB-02 (imitation): datasets round-trip and reject damage; behaviour cloning drives the loss
## down and can overfit a tiny dataset (the optimiser and gradients really learn).

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
