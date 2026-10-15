extends TestCase
## LAB-05/06/08 robustness of the REAL worker processes (review findings 3, 5, 6, 8, 9, 10):
## a long pause keeps the helpers, a live helper that never delivers cannot hang a run,
## evaluation and recording jobs stop at their limits, ES validates the last generations before
## its final selection, evaluation plays a policy exactly as saved and with the policy's own
## objective, helpers start only when episodes are handed out and back off when idle, helpers
## still leave when the coordinator dies, and the CPU share holds over the long run.


func _job(run: String, raw: Dictionary) -> void:
	var job := raw.duplicate(true)
	job["paths"] = {"run_dir": run, "library_dir": run.path_join("lib"), "datasets_dir": run.path_join("ds")}
	LabIO.write_json(run.path_join("job.json"), job)


func _es_job(run: String, extra: Dictionary) -> void:
	var job := {"kind": "es", "name": "faults", "creature": "dev_biped", "seed": 31,
		"objective": {"preset": "drill"}, "scenario": {"preset": "drill_dummy", "round_time": 4.0},
		"eval": {"val_episodes": 1, "episodes": 1, "every": 1000, "standard_spawns": false},
		"es": {"pairs": 3, "episodes_per_candidate": 1},
		"limits": {"max_generations": 500, "workers": 1, "worlds": 2, "low_priority": false, "max_wall_s": 600}}
	for k in extra:
		if typeof(job.get(k)) == TYPE_DICTIONARY and typeof(extra[k]) == TYPE_DICTIONARY:
			for k2 in extra[k]:
				job[k][k2] = extra[k][k2]
		else:
			job[k] = extra[k]
	_job(run, job)


func _sleep(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await get_tree().process_frame
		OS.delay_msec(5)


func _wait(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		if cond.call():
			return true
		await _sleep(0.25)
	return cond.call()


func _pr(run: String) -> Dictionary:
	return LabManager.progress(run)


func _state(run: String) -> String:
	return str(LabManager.status(run).get("state", ""))


func _finished(run: String) -> bool:
	return _state(run) in ["completed", "failed", "cancelled"]


func _stop(run: String, pid: int) -> void:
	LabManager.control(run, "cancel")
	await _wait(func() -> bool: return not OS.is_process_running(pid), 60.0)


func _helper_pids(run: String) -> Array:
	var out := []
	for h: Dictionary in _pr(run).get("helpers", []):
		out.append(int(h.get("pid", -1)))
	return out


## Every helper process this run started has exited (they are not children of the test).
func _helpers_gone(pids: Array, seconds: float) -> bool:
	var image := OS.get_executable_path().get_file()
	var gone := func() -> bool:
		for p in pids:
			if int(p) > 0 and LabWorker.process_alive(int(p), image):
				return false
		return true
	return await _wait(gone, seconds)


# ---------------------------------------------------------------------------------------------
# unit-level rules
# ---------------------------------------------------------------------------------------------

## Finding 3: after a pause every helper gets a fresh grace period, whatever its last heartbeat.
func test_resume_grants_a_heartbeat_grace_period() -> void:
	var h := {"pid": 1, "alive": true, "started_ms": 0, "hb_s": 1000}
	check(not LabBatch.heartbeat_ok(h, 0, 1100, 50000), "100 s without a heartbeat: gone")
	h["grace_until_ms"] = 60000
	check(LabBatch.heartbeat_ok(h, 0, 1100, 50000), "within the grace period after a resume: alive")
	check(not LabBatch.heartbeat_ok(h, 0, 1100, 61000), "after it: the heartbeat rule applies again")
	check(LabBatch.heartbeat_ok(h, 1095, 1100, 61000), "a heartbeat written after the resume counts")


## Finding 5: the straggler deadline follows the coordinator's own pace, never below the minimum.
func test_straggler_deadline_rule() -> void:
	check_eq(LabBatch.deadline_s(-1, 4, 4, 30.0), -1.0, "no deadline before the coordinator finished its own share")
	check_near(LabBatch.deadline_s(2000, 4, 4, 30.0), 30.0, 1e-6, "fast batches: the minimum")
	check_near(LabBatch.deadline_s(40000, 4, 4, 30.0), 120.0, 1e-6, "3x the coordinator's time for an equal share")
	check_near(LabBatch.deadline_s(40000, 4, 8, 30.0), 240.0, 1e-6, "scaled by the share size")


## Finding 9: an idle helper looks for new tasks with a growing interval, not every frame.
func test_idle_helper_scans_back_off() -> void:
	var gen := temp_dir("lab_idle_%d" % Time.get_ticks_usec())
	var runner := LabRunner.new()
	add_child(runner)
	var b := LabBatch.new()
	b.setup(gen, 1, runner)
	var t0 := Time.get_ticks_msec()
	var scans := 0
	var last_next := -1
	while Time.get_ticks_msec() - t0 < 1500:
		b.helper_poll({})
		if b._next_task_scan != last_next:
			scans += 1
			last_next = b._next_task_scan
		OS.delay_msec(2)
	check(b.loops > 200, "the helper loop ran (%d frames)" % b.loops)
	check(scans <= 14, "but looked for tasks only %d times in 1.5 s (it used to every frame)" % scans)
	check(b.helper_idle(), "idle")
	# a new task is picked up promptly after the back-off resets on work
	LabIO.write_json(gen.path_join("task_000001.json"), {"id": "000001", "payload": {}, "assign": {"1": []}})
	var t1 := Time.get_ticks_msec()
	while b.helper_idle() and Time.get_ticks_msec() - t1 < 1000:
		b.helper_poll({})
		OS.delay_msec(2)
	check(Time.get_ticks_msec() - t1 < 600, "a task is noticed within the longest back-off step")
	runner.queue_free()


## Finding 10: the CPU share holds over the long run although the OS sleeps in coarse steps.
func test_cpu_throttle_keeps_the_long_run_share() -> void:
	for share in [0.25, 0.5, 0.75]:
		var th := LabWorker.CpuThrottle.new(share)
		var r := RandomNumberGenerator.new()
		r.seed = 3
		var work := 0.0
		var idle := 0.0
		for f in 20000:
			var w := int(r.randf_range(600.0, 2600.0))       # work per frame incl. physics, µs
			work += float(w)
			var ms := th.plan(w)
			if ms > 0:
				# Windows-like sleep: at least 1 ms, often up to ~1 ms longer than asked
				var actual := ms * 1000 + int(r.randf_range(100.0, 1100.0))
				idle += float(actual)
				th.slept(actual)
		var got := work / (work + idle)
		check_near(got, share, 0.02, "share %.2f over 20000 frames" % share)
	var full := LabWorker.CpuThrottle.new(1.0)
	check_eq(full.plan(5000), 0, "100%: never sleeps")


## Finding 8: an evaluation job plays the policy with its own saved settings (not the job's
## defaults), the random comparison borrows them, and "Evaluate vs baselines" keeps the policy's
## custom reward weights.
func test_evaluation_plays_the_policy_as_saved() -> void:
	var dir := temp_dir("lab_eval_play_%d" % Time.get_ticks_usec())
	var p := PolicyData.create_new("dev_biped", PackedInt32Array([16]), "tanh", 4)
	p.id = "eval_play_test"
	p.name = "Play settings"
	p.act_mode = "sample"
	p.temperature = 0.5
	p.decision_hz = 10
	p.target_lag = 0
	var mask := p.button_mask.duplicate()
	mask[PolicyActions.B_DODGE] = 0
	p.button_mask = mask
	p.training = {"approach": "es", "objective": {"preset": "drill", "weights": LabRewards.weights_for("drill", {"hits": 7.5, "taunts": 2.0})}}
	var path := dir.path_join("play.policy.json")
	check_eq(PolicyIO.write_file(path, p), OK)
	var task := LabTaskEval.new()
	task.job = LabJob.normalize({"kind": "eval", "creature": "dev_biped", "seed": 4, "model": {"temperature": 2.0},
		"target": {"policy": path, "compare": "random_init"}, "eval": {"opponents": ["idle"], "episodes": 1, "standard_spawns": false}})["job"]
	task.run_dir = dir
	task.begin()
	check(not task.finished, "evaluation set up: %s" % task.message)
	var resolve := LabBatch.resolver_for(task.make_payload())
	var groups := {}
	for it: Dictionary in task.items_for_range(0, 1):
		var pd: PolicyData = resolve.call(it)
		check(pd != null, "item resolves")
		if pd == null:
			continue
		groups[str(it["group"])] = true
		check_eq(pd.act_mode, "sample", "%s: action mode as saved" % it["group"])
		check_near(pd.temperature, 0.5, 1e-6, "%s: temperature as saved (the job default was 2.0)" % it["group"])
		check_eq(pd.decision_hz, 10, "%s: decision rate as saved" % it["group"])
		check_eq(pd.target_lag, 0, "%s: perception lag as saved" % it["group"])
		check_eq(int(pd.button_mask[PolicyActions.B_DODGE]), 0, "%s: button mask as saved" % it["group"])
	check(groups.has("target") and groups.has("compare"), "target and comparison both resolved: %s" % str(groups.keys()))
	var ej: Dictionary = LabJob.normalize(LabManager.eval_job_for(p, "eval_play_test", ["idle"], 2, 1))["job"]
	var w: Dictionary = ej["objective"]["weights"]
	check_eq(str(ej["objective"]["preset"]), "drill", "the policy's objective preset")
	check_near(float(w["hits"]), 7.5, 1e-6, "its edited weight (hits)")
	check_near(float(w["taunts"]), 2.0, 1e-6, "its edited weight (taunts)")
	check_near(float(w["damage_dealt"]), 1.0, 1e-6, "and the preset's other weights")


# ---------------------------------------------------------------------------------------------
# real worker processes
# ---------------------------------------------------------------------------------------------

## Finding 3: pausing longer than the heartbeat timeout with helper work in flight used to drop
## the helpers on resume (their share was re-run). Helpers now heart-beat while paused.
func test_long_pause_keeps_the_helpers() -> void:
	var run := temp_dir("lab_pause_long_%d" % Time.get_ticks_usec())
	_es_job(run, {"scenario": {"preset": "drill_dummy", "round_time": 30.0}, "es": {"pairs": 4},
		"limits": {"workers": 2, "heartbeat_s": 4}})
	var pid := LabManager.start(run)
	check(pid > 0, "worker started")
	var in_flight := await _wait(func() -> bool:
		var pr := _pr(run)
		return str(pr.get("phase", "")) == "gen" and int(pr.get("generation", 0)) >= 1 and int(pr.get("helpers_alive", 0)) >= 1 \
			and int(pr.get("batch_size", 0)) > 0 and int(pr.get("batch_done", 0)) < int(pr.get("batch_size", 0)), 240.0)
	check(in_flight, "a generation with helper work is in flight")
	var gen0 := int(_pr(run).get("generation", 0))
	LabManager.control(run, "pause")
	check(await _wait(func() -> bool: return _state(run) == "paused", 30.0), "paused")
	await _sleep(10.0)    # 2.5x the heartbeat timeout
	LabManager.control(run, "run")
	check(await _wait(func() -> bool: return int(_pr(run).get("generation", 0)) > gen0, 180.0), "the generation finished after the resume")
	var pr2 := _pr(run)
	check_eq(int(pr2.get("reassigned", -1)), 0, "no helper share was re-run after the pause")
	check_eq(int(pr2.get("late", -1)), 0, "and none was late")
	var log_text := FileAccess.get_file_as_string(run.path_join("worker_r0.log"))
	check(not log_text.contains("stopped responding"), "no helper was declared gone")
	await _stop(run, pid)


## Finding 5: a live helper whose result write fails (here: a directory occupies the result file
## name) used to hang the run forever; its share is now re-run after the straggler deadline.
func test_a_helper_that_never_delivers_cannot_hang_the_run() -> void:
	var run := temp_dir("lab_lost_result_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(run.path_join("gen").path_join("result_000001_r1.json"))
	_job(run, {"kind": "eval", "name": "lost result", "creature": "dev_biped", "seed": 77,
		"target": {"policy": "dev_biped_es_drill", "compare": ""}, "objective": {"preset": "drill"},
		"scenario": {"preset": "drill_dummy", "round_time": 4.0}, "eval": {"opponents": ["idle"], "episodes": 2, "standard_spawns": false},
		"limits": {"workers": 2, "worlds": 2, "low_priority": false, "max_wall_s": 300, "straggler_s": 3}})
	var pid := LabManager.start(run)
	check(await _wait(func() -> bool: return _finished(run), 120.0), "the evaluation finished (state %s)" % _state(run))
	check_eq(_state(run), "completed")
	var helpers := _helper_pids(run)
	var pr := _pr(run)
	check(int(pr.get("late", 0)) + int(pr.get("reassigned", 0)) >= 1, "the undelivered share was re-run by the coordinator (late %d)" % int(pr.get("late", 0)))
	var rep := LabManager.report(run)
	check_eq(int((rep.get("target", {}) as Dictionary).get("n", 0)), 2, "every planned episode counted once")
	await _wait(func() -> bool: return not OS.is_process_running(pid), 30.0)
	check(await _helpers_gone(helpers, 30.0), "the helper exited too")


## Finding 5: evaluation and recording jobs used to ignore their limits (one batch for the whole
## job). They now run in short batches and stop at the time limit with an honest partial report.
func test_evaluation_and_recording_stop_at_the_time_limit() -> void:
	var ev := temp_dir("lab_eval_limit_%d" % Time.get_ticks_usec())
	_job(ev, {"kind": "eval", "name": "eval limit", "creature": "dev_biped", "seed": 5,
		"target": {"policy": "dev_biped_es_drill", "compare": "random_init"}, "objective": {"preset": "drill"},
		"scenario": {"preset": "drill_dummy", "round_time": 4.0}, "eval": {"opponents": ["idle"], "episodes": 300, "standard_spawns": false},
		"limits": {"workers": 1, "worlds": 2, "low_priority": false, "max_wall_s": 10}})
	var rec := temp_dir("lab_rec_limit_%d" % Time.get_ticks_usec())
	_job(rec, {"kind": "record", "name": "record limit", "creature": "dev_biped", "seed": 5,
		"scenario": {"preset": "spar_jabber", "opponents": ["idle"], "round_time": 4.0},
		"record": {"teacher": "jabber", "episodes": 500, "dataset_id": "limit_test"},
		"limits": {"workers": 1, "worlds": 2, "low_priority": false, "max_wall_s": 10}})
	var p1 := LabManager.start(ev)
	var p2 := LabManager.start(rec)
	check(p1 > 0 and p2 > 0, "workers started")
	check(await _wait(func() -> bool: return _finished(ev) and _finished(rec), 120.0), "both stopped (eval %s, record %s)" % [_state(ev), _state(rec)])
	var r1 := LabManager.report(ev)
	check_eq(_state(ev), "completed", "evaluation completed gracefully")
	check(not bool(r1.get("complete", true)), "the evaluation report says it is partial")
	check(str(r1.get("stop_reason", "")).contains("time limit"), "and why: %s" % str(r1.get("stop_reason", "")))
	var played := int(r1.get("played_episodes", 0))
	check(played > 0 and played < 300, "it played %d of 300 planned episodes" % played)
	check_eq(int((r1.get("target", {}) as Dictionary).get("n", -1)), played, "n counts exactly the played episodes")
	check_eq(int((r1.get("paired_compare", {}) as Dictionary).get("n", -1)), played, "comparison paired on the same episodes")
	var r2 := LabManager.report(rec)
	check_eq(_state(rec), "completed", "recording completed gracefully")
	check(not bool(r2.get("complete", true)) and str(r2.get("stop_reason", "")).contains("time limit"), "partial recording reported")
	var d := PolicyDataset.load_all(str(r2.get("dataset", "")))
	check(int(d["episodes"]) > 0 and int(d["episodes"]) == int(r2.get("episodes", -1)), "the dataset holds exactly the recorded episodes (%d)" % int(d["episodes"]))
	await _wait(func() -> bool: return not OS.is_process_running(p1) and not OS.is_process_running(p2), 30.0)


## Finding 6: generations after the last validation step used to be ignored by the final
## selection (with `every` larger than the run, the untrained network was always "best").
func test_es_validates_the_last_generations_before_selecting() -> void:
	var run := temp_dir("lab_es_select_%d" % Time.get_ticks_usec())
	_es_job(run, {"seed": 12, "limits": {"max_generations": 3}, "eval": {"val_episodes": 2, "every": 1000}})
	var pid := LabManager.start(run)
	check(await _wait(func() -> bool: return _finished(run), 300.0), "run finished (%s)" % _state(run))
	var vals := []
	for l: Dictionary in LabManager.metrics(run):
		if l.has("eval_reward"):
			vals.append(int(l["gen"]))
	check(vals.has(0) and vals.has(3), "validated at generation 0 and again at the stop (generation 3): %s" % str(vals))
	var rep := LabManager.report(run)
	var best_gen := int(rep.get("best_gen", -1))
	check(best_gen == 3 or bool(rep.get("selected_initial", false)), "selection considered generation 3 (best_gen %d)" % best_gen)
	if bool(rep.get("selected_initial", false)):
		check(str(LabManager.status(run).get("message", "")).contains("starting network"), "keeping the starting network is said, not silent")
	check(rep.has("paired"), "the final test is a paired comparison")
	await _wait(func() -> bool: return not OS.is_process_running(pid), 30.0)


## Finding 9: a behaviour-cloning job no longer starts its helpers before the rollouts (they
## used to idle through every training epoch, polling the file system every frame).
func test_bc_starts_helpers_only_for_the_rollouts() -> void:
	var run := temp_dir("lab_bc_lazy_%d" % Time.get_ticks_usec())
	var ds := run.path_join("ds")
	PolicyDataset.root_override = ds
	var r := RandomNumberGenerator.new()
	r.seed = 4
	var obs := PackedFloat32Array()
	var moves := PackedByteArray()
	var buttons := PackedByteArray()
	var eps := PackedInt32Array()
	for k in 480:
		var row := PackedFloat32Array()
		row.resize(PolicyObs.SIZE)
		var a := r.randf_range(-1.0, 1.0)
		row[1] = a
		obs.append_array(row)
		moves.append(1 if a > 0.0 else 2)
		buttons.append(PolicyActions.B_LIGHT if a > 0.5 else PolicyActions.B_NONE)
		eps.append(k / 40)
	var ddir := PolicyDataset.ensure("lazy", "Lazy", "dev_biped", "test")
	PolicyDataset.write_shard(ddir, obs, moves, buttons, eps, "t")
	PolicyDataset.root_override = ""
	_job(run, {"kind": "bc", "name": "lazy helpers", "creature": "dev_biped", "seed": 3, "model": {"hidden": [16]},
		"scenario": {"preset": "drill_dummy", "round_time": 4.0},
		"bc": {"datasets": [ddir], "rollouts": 2, "patience": 2}, "limits": {"max_epochs": 4, "workers": 2, "low_priority": false}})
	var pid := LabManager.start(run)
	var max_workers_training := 0
	var t0 := Time.get_ticks_msec()
	while not _finished(run) and Time.get_ticks_msec() - t0 < 180000:
		var pr := _pr(run)
		if str(pr.get("phase", "")) == "train":
			max_workers_training = maxi(max_workers_training, int(pr.get("workers", 0)))
		await _sleep(0.2)
	check_eq(_state(run), "completed", "BC job completed")
	check_eq(max_workers_training, 1, "no helper process while the network trains")
	var log_text := FileAccess.get_file_as_string(run.path_join("worker_r0.log"))
	var started := log_text.find("helper rank 1 started")
	check(started > log_text.rfind("epoch "), "the helper started after the last epoch, for the rollouts")
	check_eq(int((LabManager.report(run).get("clone_rollouts", {}) as Dictionary).get("n", 0)), 2, "the rollouts ran")
	await _wait(func() -> bool: return not OS.is_process_running(pid), 30.0)


## Finding 9: a helper with nothing to do sleeps between frames (it used to spin at ~300 frames
## per second, 15-34% of a core). With one ES pair and 3 workers, rank 2 never gets work.
func test_an_idle_helper_backs_off() -> void:
	var run := temp_dir("lab_idle_helper_%d" % Time.get_ticks_usec())
	_es_job(run, {"es": {"pairs": 1}, "limits": {"workers": 3}})
	var pid := LabManager.start(run)
	var hb := run.path_join("gen").path_join("hb_r2.json")
	check(await _wait(func() -> bool: return int(LabIO.read_json(hb).get("loops", 0)) > 0 and int(_pr(run).get("generation", 0)) >= 1, 120.0), "helper rank 2 is running")
	await _sleep(1.5)
	var a := LabIO.read_json(hb)
	var ta := Time.get_ticks_msec()
	await _sleep(4.0)
	var b := LabIO.read_json(hb)
	var tb := Time.get_ticks_msec()
	var rate := float(int(b.get("loops", 0)) - int(a.get("loops", 0))) / (float(tb - ta) / 1000.0)
	check(rate > 0.0 and rate < 100.0, "the idle helper runs %.0f frames per second" % rate)
	var helpers := _helper_pids(run)
	await _stop(run, pid)
	check(await _helpers_gone(helpers, 30.0), "helpers exited")


## The cheaper liveness check must still notice a dead coordinator: helpers trust its progress
## heartbeat and only ask the OS once it is stale.
func test_helpers_exit_when_the_coordinator_dies() -> void:
	var run := temp_dir("lab_coord_dies_%d" % Time.get_ticks_usec())
	_es_job(run, {"scenario": {"preset": "drill_dummy", "round_time": 20.0}, "limits": {"workers": 2}})
	var pid := LabManager.start(run)
	check(await _wait(func() -> bool: return int(_pr(run).get("helpers_alive", 0)) >= 1, 120.0), "a helper is working")
	var helpers := _helper_pids(run)
	OS.kill(pid)
	check(await _wait(func() -> bool: return not OS.is_process_running(pid), 20.0), "coordinator killed")
	check(await _helpers_gone(helpers, 60.0), "the helper noticed and exited within a minute")
