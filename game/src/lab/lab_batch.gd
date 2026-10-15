class_name LabBatch
extends RefCounted
## Distributes a batch of episodes over the job's worker processes ("ranks") through files in
## `<run>/gen/`, and resolves each episode's learner policy from a compact payload.
##
## Coordinator (rank 0): `submit(items, payload)` splits items round-robin over itself and the
## live helpers, writes `task_<id>.json` (payload + per-rank items), runs its own share in its
## LabRunner and `poll()`s `result_<id>_r<k>.json`. A helper that dies or stops heart-beating
## has its share re-queued locally, so a crashed helper costs time, never correctness.
## Helper (rank k>0): `helper_poll()` picks up the newest task, runs its share, writes results.
##
## Payload: {arch: {hidden, activation}, meta: {mode, temperature, target_lag, decision_hz, mask,
##   creature}, params: {key: base64 f32}}; item.policy: {key, noise_seed?, sign?, sigma?}.
## Candidates are rebuilt from θ + noise seed on every rank (LabES.perturbed), so only θ travels.

const HEARTBEAT_TIMEOUT_S := 20
const STARTUP_TIMEOUT_MS := 60000

var gen_dir := ""
var rank := 0
var runner: LabRunner
var helpers := {}            ## rank -> {pid, alive, started_ms}
var seq := 0
var id := ""
var items: Array = []
var results := {}            ## item index -> result
var pending := {}            ## helper rank -> Array of items
var payload := {}
var helper_stats := {}       ## rank -> {util, mem_mb, episodes}
var reassigned := 0
var sink: LabRecordSink      ## set while a recording batch runs on this rank

var _task_id := ""
var _task_results: Array = []
var _last_done := ""
var _last_hb_ms := -100000


func setup(p_gen_dir: String, p_rank: int, p_runner: LabRunner) -> void:
	gen_dir = p_gen_dir
	rank = p_rank
	runner = p_runner
	DirAccess.make_dir_recursive_absolute(gen_dir)


## Builds the resolver for a payload: item -> PolicyData (cached per base parameter key).
static func resolver_for(p: Dictionary) -> Callable:
	var cache := {}
	var arch: Dictionary = p.get("arch", {})
	var meta: Dictionary = p.get("meta", {})
	var params: Dictionary = p.get("params", {})
	var hidden := PackedInt32Array(arch.get("hidden", [32, 32]))
	var act := str(arch.get("activation", "tanh"))
	return func(item: Dictionary) -> PolicyData:
		var learner: Dictionary = item.get("learner", {"type": "policy"})
		if str(learner.get("type", "policy")) != "policy":
			return null
		var pol: Dictionary = item.get("policy", {})
		var key := str(pol.get("key", "theta"))
		if not cache.has(key):
			cache[key] = LabIO.floats_b64(str(params.get(key, "")))
		var base: PackedFloat32Array = cache[key]
		if base.size() != PolicyMLP.count_params(PolicyObs.SIZE, hidden, PolicyActions.OUTPUTS):
			return null
		var w := base
		if pol.has("noise_seed"):
			w = LabES.perturbed(base, int(pol["noise_seed"]), float(pol.get("sign", 1.0)), float(pol.get("sigma", 0.05)))
		var pd := PolicyData.new()
		pd.creature = str(meta.get("creature", ""))
		pd.name = "candidate"
		pd.net = PolicyMLP.new()
		pd.net.configure(PolicyObs.SIZE, hidden, PolicyActions.OUTPUTS, act)
		pd.net.params = w
		pd.act_mode = str(pol.get("mode", meta.get("mode", "argmax")))
		pd.temperature = float(meta.get("temperature", 1.0))
		pd.target_lag = int(meta.get("target_lag", 1))
		pd.decision_hz = int(meta.get("decision_hz", PolicyActions.DEFAULT_DECISION_HZ))
		var mask: Array = meta.get("mask", [])
		pd.button_mask = PackedByteArray(mask) if mask.size() == PolicyActions.BUTTON_COUNT else PolicyActions.button_mask(null)
		return pd


func alive_helpers() -> Array:
	var out := []
	for r in helpers:
		var was := bool(helpers[r]["alive"])
		var now_alive := _helper_alive(int(r))
		if now_alive:
			out.append(int(r))
			if not was:
				helpers[r]["alive"] = true
				Log.i("lab", "helper rank %d is heart-beating again; it gets work from the next batch" % int(r))
		elif was:
			helpers[r]["alive"] = false
			Log.w("lab", "helper rank %d is gone; its work moves to the coordinator" % int(r))
	out.sort()
	return out


## A helper is alive while its process runs and its heartbeat file is fresh. The newest heartbeat
## time seen is remembered: the helper replaces the file atomically (remove + rename on Windows),
## so a stat can momentarily fail; that must not count as a missed heartbeat.
func _helper_alive(r: int) -> bool:
	var h: Dictionary = helpers[r]
	var now_ms := Time.get_ticks_msec()
	if h.has("checked_ms") and now_ms - int(h["checked_ms"]) < 250:
		return bool(h["last_ok"])   # poll() asks every frame; the file system is asked 4x a second
	h["checked_ms"] = now_ms
	var ok := OS.is_process_running(int(h["pid"]))
	if ok:
		var hb := gen_dir.path_join("hb_r%d.json" % r)
		var mt := int(FileAccess.get_modified_time(hb)) if FileAccess.file_exists(hb) else 0
		ok = heartbeat_ok(h, mt, int(Time.get_unix_time_from_system()), now_ms)
	h["last_ok"] = ok
	return ok


## The heartbeat rule on its own (tested directly): keeps the newest heartbeat file time in
## h["hb_s"], so a failed stat (0) never replaces a good one. Fresh = at most
## HEARTBEAT_TIMEOUT_S old; before its first heartbeat a helper has STARTUP_TIMEOUT_MS.
static func heartbeat_ok(h: Dictionary, mtime: int, now_s: int, now_ms: int) -> bool:
	if mtime > int(h.get("hb_s", 0)):
		h["hb_s"] = mtime
	var last := int(h.get("hb_s", 0))
	if last <= 0:
		return now_ms - int(h.get("started_ms", 0)) < STARTUP_TIMEOUT_MS
	return now_s - last <= HEARTBEAT_TIMEOUT_S


func submit(p_items: Array, p_payload: Dictionary) -> void:
	seq += 1
	id = "%06d" % seq
	items = p_items
	payload = p_payload
	results.clear()
	pending.clear()
	for fn in DirAccess.get_files_at(gen_dir):
		if str(fn).begins_with("task_") or str(fn).begins_with("result_"):
			DirAccess.remove_absolute(gen_dir.path_join(str(fn)))
	var live := alive_helpers()
	var ranks := [0]
	ranks.append_array(live)
	var groups := {}
	for r in ranks:
		groups[r] = []
	for j in items.size():
		(groups[ranks[j % ranks.size()]] as Array).append(items[j])
	if not live.is_empty():
		var assign := {}
		for r in live:
			assign[str(r)] = groups[r]
			pending[r] = groups[r]
		LabIO.write_json(gen_dir.path_join("task_%s.json" % id), {"id": id, "payload": payload, "assign": assign})
	_prepare_runner(payload)
	runner.add_items(groups[0])


func _prepare_runner(p: Dictionary) -> void:
	runner.resolver = resolver_for(p)
	if str(p.get("record_dir", "")) != "":
		sink = LabRecordSink.new(str(p["record_dir"]), "r%d" % rank)
		runner.on_finished = sink.on_episode
	else:
		sink = null
		runner.on_finished = Callable()


func done_count() -> int:
	return results.size()


## Coordinator: gathers results; returns true when every item has a result.
func poll() -> bool:
	for res: Dictionary in runner.take_results():
		results[int(res.get("i", -1))] = res
	if sink != null and not runner.busy():
		sink.flush()
	for r in pending.keys():
		var path := gen_dir.path_join("result_%s_r%d.json" % [id, int(r)])
		var d := LabIO.read_json(path)
		if not d.is_empty() and str(d.get("id", "")) == id:
			for res: Dictionary in d.get("results", []):
				var i := int(res.get("i", -1))
				if not results.has(i):
					results[i] = res
			helper_stats[r] = d.get("stats", {})
			pending.erase(r)
			continue
		if not _helper_alive(int(r)):
			helpers[r]["alive"] = false
			Log.w("lab", "helper rank %d stopped responding; re-running its %d episodes here" % [int(r), (pending[r] as Array).size()])
			reassigned += (pending[r] as Array).size()
			runner.add_items(pending[r])
			pending.erase(r)
	return results.size() >= items.size()


func ordered_results() -> Array:
	var out := []
	for it: Dictionary in items:
		out.append(results.get(int(it["i"]), {"i": int(it["i"]), "error": "missing"}))
	return out


## Helper rank: picks up work, reports results and heart-beats. Call once per frame.
func helper_poll(stats: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hb_ms > 1000:
		_last_hb_ms = now
		LabIO.write_json(gen_dir.path_join("hb_r%d.json" % rank), {"rank": rank, "pid": OS.get_process_id(), "task": _task_id})
	if _task_id == "":
		var newest := ""
		for fn in DirAccess.get_files_at(gen_dir):
			var f := str(fn)
			if f.begins_with("task_") and f.ends_with(".json"):
				var tid := f.trim_prefix("task_").trim_suffix(".json")
				if tid > _last_done and tid > newest:
					newest = tid
		if newest == "":
			return
		var d := LabIO.read_json(gen_dir.path_join("task_%s.json" % newest))
		if d.is_empty():
			return
		_task_id = newest
		_task_results = []
		var mine: Array = (d.get("assign", {}) as Dictionary).get(str(rank), [])
		_prepare_runner(d.get("payload", {}))
		runner.add_items(mine)
		return
	_task_results.append_array(runner.take_results())
	if now - _last_hb_ms < 20 and not FileAccess.file_exists(gen_dir.path_join("task_%s.json" % _task_id)):
		# the coordinator moved on (it re-ran our share itself): drop the stale work
		runner.clear()
		_last_done = _task_id
		_task_id = ""
		_task_results = []
		return
	if not runner.busy():
		if sink != null:
			sink.flush()
		LabIO.write_json(gen_dir.path_join("result_%s_r%d.json" % [_task_id, rank]), {"id": _task_id, "rank": rank, "results": _task_results, "stats": stats})
		_last_done = _task_id
		_task_id = ""
		_task_results = []
