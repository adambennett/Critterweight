extends TestCase
## LAB-04/05/06 via the REAL worker process (the same `--lab-worker` path the Lab UI uses):
## pause / resume / cancel through the control file, crash (kill) + resume from the latest
## checkpoint, and evolution strategies improving on the controlled drill task within a small
## budget. Workers run headless at fixed 120 Hz steps, so these runs are reproducible.


func _job(run: String, extra: Dictionary) -> Dictionary:
	var job := {"kind": "es", "name": "test", "creature": "dev_biped", "seed": 21,
		"objective": {"preset": "drill"}, "scenario": {"preset": "drill_dummy", "round_time": 4.0},
		"eval": {"val_episodes": 1, "episodes": 1, "every": 1000, "standard_spawns": false},
		"es": {"pairs": 3, "episodes_per_candidate": 1},
		"limits": {"max_generations": 500, "workers": 1, "worlds": 2, "low_priority": false, "max_wall_s": 600},
		"paths": {"run_dir": run, "library_dir": run.path_join("lib"), "datasets_dir": run.path_join("ds")}}
	for k in extra:
		if typeof(job.get(k)) == TYPE_DICTIONARY and typeof(extra[k]) == TYPE_DICTIONARY:
			for k2 in extra[k]:
				job[k][k2] = extra[k][k2]
		else:
			job[k] = extra[k]
	LabIO.write_json(run.path_join("job.json"), job)
	return job


func _wait(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		if cond.call():
			return true
		await get_tree().create_timer(0.25).timeout
	return cond.call()


func _gen(run: String) -> int:
	return int(LabManager.progress(run).get("generation", 0))


func _episodes(run: String) -> int:
	return int(LabManager.progress(run).get("episodes", 0))


func test_pause_resume_cancel() -> void:
	var run := temp_dir("lab_worker_ctl_%d" % Time.get_ticks_usec())
	_job(run, {})
	var pid := LabManager.start(run)
	check(pid > 0, "worker process started")
	check(await _wait(func() -> bool: return _gen(run) >= 1, 120.0), "training progresses (generation %d)" % _gen(run))
	LabManager.control(run, "pause")
	check(await _wait(func() -> bool: return str(LabManager.status(run).get("state", "")) == "paused", 30.0), "worker reports paused")
	var e1 := _episodes(run)
	await get_tree().create_timer(3.0).timeout
	check_eq(_episodes(run), e1, "no episodes are run while paused")
	check(OS.is_process_running(pid) and LabManager.is_alive(run), "paused worker stays alive and keeps reporting")
	LabManager.control(run, "run")
	check(await _wait(func() -> bool: return _episodes(run) > e1, 90.0), "training continues after resume")
	check_eq(str(LabManager.status(run).get("state", "")), "running")
	LabManager.control(run, "cancel")
	check(await _wait(func() -> bool: return not OS.is_process_running(pid), 60.0), "worker exits on cancel")
	check_eq(str(LabManager.status(run).get("state", "")), "cancelled", "final state")
	check(LabManager.has_checkpoint(run), "a checkpoint was kept")


func test_crash_and_resume_from_checkpoint() -> void:
	var run := temp_dir("lab_worker_crash_%d" % Time.get_ticks_usec())
	_job(run, {})
	var pid := LabManager.start(run)
	check(await _wait(func() -> bool: return _gen(run) >= 2 and LabManager.checkpoints(run).size() >= 1, 180.0), "reached generation 2")
	var ck_before := int((LabManager.checkpoints(run)[0] as Dictionary)["n"])
	OS.kill(pid)
	check(await _wait(func() -> bool: return not OS.is_process_running(pid), 20.0), "worker killed")
	check(await _wait(func() -> bool: return LabManager.effective_state(run) == "interrupted", 90.0), "the UI sees an interrupted run")
	check(LabManager.can_resume(run), "resumable")
	var pid2 := LabManager.start(run)
	check(pid2 > 0 and pid2 != pid, "a new worker took over")
	check(await _wait(func() -> bool: return _gen(run) > ck_before, 180.0), "continued past checkpoint %d (now %d)" % [ck_before, _gen(run)])
	var log_text := FileAccess.get_file_as_string(run.path_join("worker_r0.log"))
	check(log_text.contains("resuming from ckpt_%06d" % ck_before), "resumed from the latest checkpoint")
	LabManager.control(run, "cancel")
	await _wait(func() -> bool: return not OS.is_process_running(pid2), 60.0)
	# the learning curve has no duplicate or restarted generations
	var gens := []
	for line: Dictionary in LabManager.metrics(run):
		if line.has("fit_mean"):
			gens.append(int(line["gen"]))
	var ordered := true
	for k in range(1, gens.size()):
		if gens[k] != gens[k - 1] + 1:
			ordered = false
	check(ordered and gens.size() >= 3 and gens[0] == 1, "generations 1..%d recorded exactly once: %s" % [gens.size(), str(gens)])


## Proof-of-learning in miniature (the full experiment is in docs/evidence/lab): ES must beat
## its own starting policy on held-out test episodes of the drill within a small budget.
func test_es_improves_on_the_drill_task() -> void:
	var run := temp_dir("lab_worker_es_%d" % Time.get_ticks_usec())
	_job(run, {"seed": 11, "es": {"pairs": 8, "sigma": 0.05, "lr": 0.02}, "model": {"hidden": [32, 32], "out_scale": 0.01},
		"eval": {"val_episodes": 4, "episodes": 4, "every": 4, "standard_spawns": true},
		"scenario": {"preset": "drill_dummy", "round_time": 5.0},
		"limits": {"max_generations": 12, "workers": 2}})
	var pid := LabManager.start(run)
	check(pid > 0, "worker started")
	var done := await _wait(func() -> bool: return str(LabManager.status(run).get("state", "")) in ["completed", "failed", "cancelled"], 900.0)
	check(done, "run finished in time (state %s)" % LabManager.effective_state(run))
	var rep := LabManager.report(run)
	check(not rep.is_empty(), "report written")
	if rep.is_empty():
		return
	var r0 := float((rep["initial"]["reward"] as Dictionary)["mean"])
	var r1 := float((rep["trained"]["reward"] as Dictionary)["mean"])
	check(r1 > r0 + 5.0, "trained policy beats its starting point on test seeds (%.1f -> %.1f)" % [r0, r1])
	var fits := []
	for line: Dictionary in LabManager.metrics(run):
		if line.has("fit_mean"):
			fits.append(float(line["fit_mean"]))
	check(fits.size() == 12, "12 generations recorded")
	if fits.size() >= 6:
		check(LabStats.mean(fits.slice(-3)) > LabStats.mean(fits.slice(0, 3)), "population fitness rose (%s)" % str(fits))
	var pol := PolicyIO.read_file(run.path_join("best.policy.json"))
	check(pol["ok"], "trained policy saved and valid")
	if pol["ok"]:
		check_eq(str((pol["policy"] as PolicyData).training.get("approach", "")), "es")
