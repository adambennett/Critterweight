class_name LabJob
extends RefCounted
## A training/evaluation job: what to learn, from what, against whom, and within which limits.
## Jobs are plain JSON (hand-writable for reproducible command-line runs, docs/AI_LAB.md);
## `normalize` fills defaults, clamps every number to a safe range and reports problems.
##
## kinds: "es" (evolution strategies, reward-driven), "bc" (behaviour cloning from a dataset),
## "eval" (evaluate a saved policy against fixed baselines), "record" (record a scripted
## teacher into an imitation dataset).

const VERSION := 1
const KINDS: PackedStringArray = ["es", "bc", "eval", "record"]
const KIND_NAMES := {"es": "Evolution strategies (reward)", "bc": "Behaviour cloning (imitation)", "eval": "Evaluation", "record": "Record teacher dataset"}


static func defaults() -> Dictionary:
	return {
		"version": VERSION, "id": "", "kind": "es", "name": "", "creature": "dev_biped", "opponent_creature": "",
		"seed": 1,
		"objective": {"preset": "aggressive", "weights": {}},
		"scenario": {"preset": "drill_dummy"},
		"eval": {"opponents": [], "episodes": 6, "val_episodes": 6, "every": 5, "standard_spawns": true},
		"model": {"hidden": [32, 32], "activation": "tanh", "init_policy": "", "mode": "", "temperature": 1.0, "init_seed": 0, "out_scale": 0.1},
		"es": {"pairs": 12, "sigma": 0.05, "lr": 0.03, "l2": 0.005, "episodes_per_candidate": 1},
		"bc": {"datasets": [], "epochs": 60, "batch": 128, "lr": 0.003, "val_frac": 0.2, "patience": 8, "l2": 0.0001,
			"rollouts": 6, "balance": false},
		"record": {"teacher": "bot_regular", "episodes": 40, "dataset_id": "", "dataset_name": ""},
		"target": {"policy": "", "compare": "random_init"},
		"limits": {"max_wall_s": 1800.0, "max_generations": 60, "max_epochs": 60, "max_episodes": 0, "workers": 1,
			"worlds": 2, "low_priority": true, "cpu_share": 1.0, "max_memory_mb": 3072},
		"paths": {"run_dir": "", "library_dir": "", "datasets_dir": ""},
		"output": {"save_to_library": true, "policy_name": ""},
	}


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if typeof(out.get(k)) == TYPE_DICTIONARY and typeof(over[k]) == TYPE_DICTIONARY:
			out[k] = _merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out


static func _num(d: Dictionary, key: String, lo: float, hi: float) -> void:
	var v = d.get(key)
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(v)):
		return
	d[key] = clampf(float(v), lo, hi)


static func _int(d: Dictionary, key: String, lo: int, hi: int) -> void:
	var v = d.get(key)
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(v)):
		return
	d[key] = clampi(int(v), lo, hi)


## Merges `raw` over the defaults and validates. {job: Dictionary, errors: PackedStringArray}
static func normalize(raw: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var job := _merge(defaults(), raw)
	if not KINDS.has(str(job["kind"])):
		errors.append("unknown job kind '%s'" % str(job["kind"]))
	job["seed"] = int(job.get("seed", 1)) if typeof(job.get("seed")) in [TYPE_INT, TYPE_FLOAT] else 1
	job["name"] = str(job.get("name", "")).strip_escapes().substr(0, 64)
	var lim: Dictionary = job["limits"]
	_num(lim, "max_wall_s", 10.0, 7.0 * 24.0 * 3600.0)
	_int(lim, "max_generations", 1, 100000)
	_int(lim, "max_epochs", 1, 10000)
	_int(lim, "max_episodes", 0, 100000000)
	_int(lim, "workers", 1, maxi(1, OS.get_processor_count()))
	_int(lim, "worlds", 1, 8)
	_num(lim, "cpu_share", 0.1, 1.0)
	_int(lim, "max_memory_mb", 256, 65536)
	lim["low_priority"] = bool(lim.get("low_priority", true))
	var es: Dictionary = job["es"]
	_int(es, "pairs", 1, 256)
	_num(es, "sigma", 0.001, 1.0)
	_num(es, "lr", 0.0001, 1.0)
	_num(es, "l2", 0.0, 0.1)
	_int(es, "episodes_per_candidate", 1, 16)
	var bc: Dictionary = job["bc"]
	_int(bc, "epochs", 1, 10000)
	_int(bc, "batch", 8, 4096)
	_num(bc, "lr", 0.00001, 0.1)
	_num(bc, "val_frac", 0.05, 0.5)
	_int(bc, "patience", 1, 1000)
	_num(bc, "l2", 0.0, 0.1)
	_int(bc, "rollouts", 0, 1000)
	var ev: Dictionary = job["eval"]
	_int(ev, "episodes", 1, 1000)
	_int(ev, "val_episodes", 1, 1000)
	_int(ev, "every", 1, 1000)
	var rec: Dictionary = job["record"]
	_int(rec, "episodes", 1, 100000)
	var model: Dictionary = job["model"]
	var hid := []
	if typeof(model.get("hidden")) == TYPE_ARRAY:
		for h in model["hidden"]:
			if typeof(h) in [TYPE_INT, TYPE_FLOAT]:
				hid.append(clampi(int(h), 1, PolicyMLP.MAX_WIDTH))
	model["hidden"] = hid.slice(0, PolicyMLP.MAX_HIDDEN_LAYERS)
	if not PolicyMLP.ACTIVATIONS.has(str(model.get("activation", "tanh"))):
		errors.append("unknown activation '%s'" % str(model.get("activation", "")))
	_num(model, "temperature", 0.05, 5.0)
	_num(model, "out_scale", 0.01, 3.0)
	# objective
	var obj: Dictionary = job["objective"]
	if not LabRewards.PRESETS.has(str(obj.get("preset", ""))):
		errors.append("unknown objective preset '%s'" % str(obj.get("preset", "")))
		obj["preset"] = "aggressive"
	obj["weights"] = LabRewards.weights_for(str(obj["preset"]), obj.get("weights", {}) if typeof(obj.get("weights")) == TYPE_DICTIONARY else {})
	# scenario: preset values, then explicit overrides
	var scn: Dictionary = job["scenario"]
	var preset := str(scn.get("preset", "drill_dummy"))
	var base: Dictionary = LabScenarios.PRESETS.get(preset, LabScenarios.PRESETS["drill_dummy"]).duplicate(true)
	for k in scn:
		base[k] = scn[k]
	base["preset"] = preset
	var opps := []
	for o in base.get("opponents", []):
		if LabOpponents.is_valid(str(o)):
			opps.append(str(o))
		else:
			errors.append("unknown opponent '%s'" % str(o))
	if opps.is_empty():
		opps = ["idle"]
	base["opponents"] = opps
	_num(base, "round_time", 3.0, 300.0)
	job["scenario"] = base
	var eops := []
	for o in ev.get("opponents", []):
		if LabOpponents.is_valid(str(o)):
			eops.append(str(o))
	ev["opponents"] = eops if not eops.is_empty() else opps.duplicate()
	if str(job["opponent_creature"]) == "":
		job["opponent_creature"] = job["creature"]
	if str(job["kind"]) == "bc" and (job["bc"]["datasets"] as Array).is_empty():
		errors.append("behaviour cloning needs at least one dataset")
	if str(job["kind"]) == "eval" and str(job["target"]["policy"]) == "":
		errors.append("evaluation needs a policy file")
	return {"job": job, "errors": errors}


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"job": {}, "errors": PackedStringArray(["job file not found: %s" % path])}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 1024 * 1024:
		return {"job": {}, "errors": PackedStringArray(["job file unreadable or too large"])}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"job": {}, "errors": PackedStringArray(["job file is not a JSON object"])}
	return normalize(json.data)


static func new_run_id(kind: String, creature: String) -> String:
	var t := Time.get_datetime_dict_from_system()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%04d%02d%02d-%02d%02d%02d_%s_%s_%03d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"],
		kind, PolicyLibrary.file_stem(creature), rng.randi_range(0, 999)]
