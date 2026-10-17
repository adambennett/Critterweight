extends TestCase
## LAB-02 (imitation data), review finding 1: recording the same teacher again must add NEW
## episodes (fresh seeds; "Continue run" skips what is already recorded), every episode carries
## its seed, exact copies already in a dataset (older builds re-recorded identical episodes) are
## loaded once, and copies of a seeded episode always land in the same behaviour-cloning split —
## no validation or test sample is a training sample.

var dir := ""


func before_each() -> void:
	dir = temp_dir("lab_ds_%d" % Time.get_ticks_usec())
	PolicyDataset.root_override = dir.path_join("datasets")


func after_each() -> void:
	PolicyDataset.root_override = ""


## One synthetic episode (deterministic per `tag`): {obs, moves, buttons}.
func _episode(tag: int, n: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = tag * 7919 + 1
	var obs := PackedFloat32Array()
	var moves := PackedByteArray()
	var buttons := PackedByteArray()
	for k in n:
		var row := PackedFloat32Array()
		row.resize(PolicyObs.SIZE)
		for i in 12:
			row[r.randi_range(0, PolicyObs.SIZE - 1)] = r.randf_range(-1.0, 1.0)
		obs.append_array(row)
		moves.append(r.randi_range(0, PolicyActions.MOVE_COUNT - 1))
		buttons.append(r.randi_range(0, 3))
	return {"obs": obs, "moves": moves, "buttons": buttons}


## Writes a shard of episodes ([{tag, index, seed}]) in format 2, or format 1 (no seed column,
## as older builds wrote it) when `v1`.
func _shard(ddir: String, name_: String, eps: Array, v1 := false) -> void:
	var obs := PackedFloat32Array()
	var moves := PackedByteArray()
	var buttons := PackedByteArray()
	var idx := PackedInt32Array()
	var seeds := PackedInt32Array()
	for e: Dictionary in eps:
		var ep := _episode(int(e["tag"]), int(e.get("n", 40)))
		var mv: PackedByteArray = ep["moves"]
		if e.has("relabel"):
			mv[0] = (int(mv[0]) + 1) % PolicyActions.MOVE_COUNT
		obs.append_array(ep["obs"])
		moves.append_array(mv)
		buttons.append_array(ep["buttons"])
		for k in mv.size():
			idx.append(int(e["index"]))
			seeds.append(int(e.get("seed", 0)))
	var n := moves.size()
	DirAccess.make_dir_recursive_absolute(ddir)
	var f := FileAccess.open(ddir.path_join("shard_%s.bin" % name_), FileAccess.WRITE)
	f.big_endian = false
	f.store_buffer("CWDS".to_ascii_buffer())
	f.store_16(1 if v1 else 2)
	f.store_16(PolicyObs.SIZE)
	f.store_32(n)
	f.store_32(0)
	f.store_buffer(obs.to_byte_array())
	f.store_buffer(moves)
	f.store_buffer(buttons)
	f.store_buffer(idx.to_byte_array())
	if not v1:
		f.store_buffer(seeds.to_byte_array())
	f.close()


func _row_key(d: Dictionary, k: int) -> String:
	var dim := PolicyObs.SIZE
	var obs: PackedFloat32Array = d["obs"]
	return "%s|%d|%d" % [obs.slice(k * dim, (k + 1) * dim).to_byte_array().hex_encode().sha256_text(), int(d["moves"][k]), int(d["buttons"][k])]


## What the reviewer measured: a dataset where a teacher was recorded twice with the same seeds
## (format 1 shards from an older build). Every copy is loaded once, so no held-out sample is
## also a training sample.
func test_identical_rerecordings_are_loaded_once() -> void:
	var ddir := PolicyDataset.ensure("twice", "Recorded twice", "dev_biped", "bot:jabber")
	var eps := []
	for t in 8:
		eps.append({"tag": t, "index": t})
	_shard(ddir, "a", eps, true)
	_shard(ddir, "b", eps, true)
	var d := PolicyDataset.load_all(ddir)
	check(d["ok"], "format 1 shards still load: %s" % str(d["errors"]))
	check_eq(int(d["episodes"]), 8, "8 distinct episodes")
	check_eq(int(d["duplicate_episodes"]), 8, "the second copy of every episode is dropped")
	check_eq(int(d["count"]), 8 * 40, "each sample once")
	var net := PolicyMLP.create(PolicyObs.SIZE, PackedInt32Array([8]), PolicyActions.OUTPUTS, "tanh", 1)
	var bc := LabBC.new()
	check_eq(bc.setup(d, net, PolicyActions.button_mask(null), {"seed": 3, "val_frac": 0.25, "test_frac": 0.25}), "", "split accepted")
	var train := {}
	for k in bc.train_idx:
		train[_row_key(d, k)] = true
	var leaked := 0
	for k in bc.val_idx + bc.test_idx:
		if train.has(_row_key(d, k)):
			leaked += 1
	check(bc.val_idx.size() > 0 and bc.test_idx.size() > 0, "held-out splits exist")
	check_eq(leaked, 0, "no validation/test sample is identical to a training sample")


## Copies of a seeded episode that are not bit-identical (e.g. recorded on another build) share
## one split unit: they always land in the same split.
func test_copies_of_a_seeded_episode_share_a_split() -> void:
	var ddir := PolicyDataset.ensure("seeded", "Seeded", "dev_biped", "bot:jabber")
	var a := []
	var b := []
	for t in 10:
		a.append({"tag": t, "index": t, "seed": 1000 + t})
		b.append({"tag": t, "index": t, "seed": 1000 + t, "relabel": true})   # same seed, one label differs
	_shard(ddir, "a", a)
	_shard(ddir, "b", b)
	var d := PolicyDataset.load_all(ddir)
	check_eq(int(d["duplicate_episodes"]), 0, "not identical, so both copies load")
	check_eq(int(d["episodes"]), 10, "but they form 10 split units (one per seed)")
	for seed_split in [1, 2, 3, 4]:
		var net := PolicyMLP.create(PolicyObs.SIZE, PackedInt32Array([8]), PolicyActions.OUTPUTS, "tanh", 1)
		var bc := LabBC.new()
		bc.setup(d, net, PolicyActions.button_mask(null), {"seed": seed_split, "val_frac": 0.2, "test_frac": 0.2})
		var where := {}
		var mixed := 0
		for pair in [[bc.train_idx, 0], [bc.val_idx, 1], [bc.test_idx, 2]]:
			for k in (pair[0] as PackedInt32Array):
				var u := int(d["units"][k])
				if where.has(u) and int(where[u]) != int(pair[1]):
					mixed += 1
				where[u] = int(pair[1])
		check_eq(mixed, 0, "split seed %d: no episode (or copy) is in two splits" % seed_split)


func _record_job(run: String, ds_root: String, episodes: int) -> void:
	LabIO.write_json(run.path_join("job.json"), {"kind": "record", "name": "rec test", "creature": "dev_biped", "seed": 3,
		"scenario": {"preset": "spar_jabber", "opponents": ["idle"], "round_time": 3.0},
		"record": {"teacher": "jabber", "episodes": episodes, "dataset_id": "rec_test"},
		"limits": {"workers": 2, "worlds": 2, "low_priority": false, "max_wall_s": 300},
		"paths": {"run_dir": run, "library_dir": run.path_join("lib"), "datasets_dir": ds_root}})


func _sleep(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await get_tree().process_frame
		OS.delay_msec(5)


func _run_to_end(run: String, seconds: float) -> String:
	var pid := LabManager.start(run)
	check(pid > 0, "worker started")
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		var st := str(LabManager.status(run).get("state", ""))
		if st in ["completed", "failed", "cancelled"] and not OS.is_process_running(pid):
			return st
		await _sleep(0.25)
	return str(LabManager.status(run).get("state", ""))


## `target` written relative to `base` ("../.." steps), as the documented commands give paths
## (they run with --path game, so ../runs/... from game/). Another drive: `target` unchanged.
static func rel_from(base: String, target: String) -> String:
	var a := base.replace("\\", "/").split("/", false)
	var b := target.replace("\\", "/").split("/", false)
	if a.is_empty() or b.is_empty() or a[0].to_lower() != b[0].to_lower():
		return target
	var i := 0
	while i < a.size() and i < b.size() and a[i] == b[i]:
		i += 1
	var parts := PackedStringArray()
	for k in range(i, a.size()):
		parts.append("..")
	for k in range(i, b.size()):
		parts.append(b[k])
	return "/".join(parts)


## The reviewer's repro: record the same teacher twice with the same job seed into the same
## dataset, then "Continue run" a finished recording. New code: the second run records new
## seeds, the continued run records nothing twice, and helper shards are committed exactly once.
## Run folders and the dataset root are given RELATIVE to the working directory (../...), as in
## the documented commands: helper shards were once dropped for such paths.
func test_recording_again_adds_new_episodes() -> void:
	# an exported build has no project folder to be relative to (globalize_path("res://") is empty
	# there): its paths stay absolute and only the relative-path part is not exercised
	var exported := OS.has_feature("template")
	var cwd := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var ds_root := rel_from(cwd, dir.path_join("datasets"))
	var run1 := rel_from(cwd, dir.path_join("rec1"))
	var run2 := rel_from(cwd, dir.path_join("rec2"))
	# a test data root on another Windows drive than the project (e.g. -UserRoot B:\... with the repo on C:)
	# cannot be reached by a relative path either: those paths stay absolute, like an export's
	var other_drive := cwd.length() >= 2 and cwd[1] == ":" and dir.length() >= 2 and dir[1] == ":" and cwd.substr(0, 1).to_upper() != dir.substr(0, 1).to_upper()
	check(exported or other_drive or run1.begins_with("..") or not OS.get_name() in ["Windows", "Linux"], "the run folder is relative (%s)" % run1)
	DirAccess.make_dir_recursive_absolute(dir.path_join("rec1"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("rec2"))
	_record_job(run1, ds_root, 4)
	check_eq(await _run_to_end(run1, 180.0), "completed", "first recording completed: %s" % str(LabManager.status(run1).get("message", "")))
	var ddir := dir.path_join("datasets").path_join("rec_test")
	var first := PolicyDataset.recorded_index(ddir)
	check_eq((first["seeds"] as Dictionary).size(), 4, "4 seeded episodes stored (the helper's share too)")
	check_eq(int(PolicyDataset.read_meta(ddir).get("next_episode", -1)), 4, "indices 0..3 reserved")
	var rep1 := LabManager.report(run1)
	check(int(rep1.get("helper_shards_committed", 0)) >= 1, "the helper's shard was committed (%s)" % str(rep1.get("helper_shards_committed", 0)))
	check_eq(int(rep1.get("helper_shards_dropped", -1)), 0, "no helper shard dropped")
	check_eq(int(rep1.get("episodes_stored", -1)), 4, "the report checks what reached the dataset")
	_record_job(run2, ds_root, 4)
	check_eq(await _run_to_end(run2, 180.0), "completed", "second recording (same job seed) completed")
	var second := PolicyDataset.recorded_index(ddir)
	check_eq((second["seeds"] as Dictionary).size(), 8, "the second run recorded 4 NEW seeds")
	var d := PolicyDataset.load_all(ddir)
	check_eq(int(d["episodes"]), 8, "8 distinct episodes")
	check_eq(int(d["duplicate_episodes"]), 0, "no copies")
	var rep2 := LabManager.report(run2)
	check_eq(int((rep2.get("seeds", {}) as Dictionary).get("first_index", -1)), 4, "numbering continued after what existed")
	# "Continue run" of the second recording: its reserved seeds are all there -> nothing again
	LabIO.write_json(run2.path_join("status.json"), {"state": "cancelled", "pid": -1, "updated": Time.get_unix_time_from_system()})
	check(LabManager.can_resume(run2), "a cancelled recording can be continued")
	check_eq(await _run_to_end(run2, 180.0), "completed", "continued recording completed")
	var rep3 := LabManager.report(run2)
	check_eq(int(rep3.get("skipped_already_recorded", -1)), 4, "the continued run skipped the 4 recorded episodes")
	check_eq(int(rep3.get("episodes", -1)), 0, "and recorded none of them again")
	var d2 := PolicyDataset.load_all(ddir)
	check_eq(int(d2["episodes"]) + int(d2["duplicate_episodes"]), 8, "the dataset still holds 8 episodes, no copies")
