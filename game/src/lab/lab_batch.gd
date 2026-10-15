class_name LabBatch
extends RefCounted
## Distributes a batch of episodes over the job's worker processes ("ranks") through files in
## `<run>/gen/`, and resolves each episode's learner policy from a compact payload.
##
## Coordinator (rank 0): `submit(items, payload)` splits items round-robin over itself and the
## live helpers, writes `task_<id>.json` (payload + per-rank items), runs its own share in its
## LabRunner and `poll()`s `result_<id>_r<k>.json`. A helper share is re-run by the coordinator
## when the helper dies, stops heart-beating, or does not deliver in time (a straggler deadline
## scaled from the coordinator's own share), so neither a crashed nor a live-but-stuck helper can
## hang a run: it costs time, never results. Helpers are started lazily (`spawner`) before the
## first batch, so a job that trains for a long time on the coordinator alone (behaviour cloning)
## does not keep idle helper processes around.
## Helper (rank k>0): `helper_poll()` picks up the newest task, runs its share, writes results
## (retrying a failed write; the coordinator's deadline covers a write that never succeeds) and
## heart-beats every second — also while the run is paused (`heartbeat()`). An idle helper looks
## for new tasks with a growing interval (20 → 250 ms) instead of every frame.
## Recording batches: helpers write their shards into `gen/stage_<task>_r<k>/` and list them in
## their result; the coordinator moves them into the dataset only when it accepts that result
## for the current task. A helper whose share was re-run elsewhere therefore never adds a second
## copy of those episodes.
##
## Payload: {arch: {hidden, activation}, meta: {mode, temperature, target_lag, decision_hz, mask,
##   creature}, meta_by_key?: {key: meta}, params: {key: base64 f32}, record_dir?}; item.policy:
##   {key, noise_seed?, sign?, sigma?, mode?}. Candidates are rebuilt from θ + noise seed on every
##   rank (LabES.perturbed), so only θ travels. meta_by_key lets parameters with their own play
##   settings (e.g. an evaluated policy file) keep them.

const HEARTBEAT_TIMEOUT_S := 20
const STARTUP_TIMEOUT_MS := 60000
## A helper share still missing STRAGGLER_FACTOR × (the coordinator's own share time, scaled to
## the share size) after submission — never sooner than straggler_min_s — is re-run locally.
const STRAGGLER_FACTOR := 3.0
const STRAGGLER_MIN_S := 30.0
## A helper that missed this many deadlines in a row gets no work for BENCH_BATCHES batches.
const MAX_MISSES := 2
const BENCH_BATCHES := 5
const RESULT_CHECK_MS := 50
const IDLE_POLL_MIN_MS := 20
const IDLE_POLL_MAX_MS := 250
const RESULT_RETRY_MS := 250
const RESULT_GIVE_UP_MS := 60000

var gen_dir := ""
var rank := 0
var runner: LabRunner
var helpers := {}            ## rank -> {pid, alive, started_ms, hb_s, misses, bench_until, ...}
var seq := 0
var id := ""
var items: Array = []
var results := {}            ## item index -> result
var pending := {}            ## helper rank -> Array of items
var payload := {}
var helper_stats := {}       ## rank -> {util, mem_mb, episodes}
var reassigned := 0          ## episodes re-run here because their helper died or went silent
var late := 0                ## episodes re-run here because their helper missed the deadline
var committed_shards := 0    ## staged helper shards moved into the dataset
var sink: LabRecordSink      ## set while a recording batch runs on this rank
## coordinator: starts the helper processes; called once, before the first batch
var spawner: Callable = Callable()
var heartbeat_timeout_s := HEARTBEAT_TIMEOUT_S
var straggler_min_s := STRAGGLER_MIN_S
## helper: frames run since start (reported in the heartbeat; shows idle back-off)
var loops := 0

var _spawned := false
var _task_id := ""
var _task_results: Array = []
var _last_done := ""
var _last_hb_ms := -100000
var _submit_ms := 0
var _own_count := 0
var _own_done_ms := -1
var _booting := {}           ## helper rank -> true while it has not heart-beat since it started
var _start_ms := {}          ## helper rank -> when its deadline starts (submission, or when it came up)
var _last_result_check := -100000
var _next_task_scan := 0
var _idle_poll_ms := IDLE_POLL_MIN_MS
var _unsent := {}
var _unsent_since := 0
var _next_send := 0


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
	var meta_by_key: Dictionary = p.get("meta_by_key", {})
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
		var m: Dictionary = meta_by_key.get(key, meta)
		var pd := PolicyData.new()
		pd.creature = str(m.get("creature", meta.get("creature", "")))
		pd.name = "candidate"
		pd.net = PolicyMLP.new()
		pd.net.configure(PolicyObs.SIZE, hidden, PolicyActions.OUTPUTS, act)
		pd.net.params = w
		pd.act_mode = str(pol.get("mode", m.get("mode", "argmax")))
		pd.temperature = float(m.get("temperature", 1.0))
		pd.target_lag = int(m.get("target_lag", 1))
		pd.decision_hz = int(m.get("decision_hz", PolicyActions.DEFAULT_DECISION_HZ))
		var mask: Array = m.get("mask", [])
		pd.button_mask = PackedByteArray(mask) if mask.size() == PolicyActions.BUTTON_COUNT else PolicyActions.button_mask(null)
		return pd


## Coordinator: the helpers that get work in the next batch (alive and not benched).
func alive_helpers() -> Array:
	var out := []
	for r in helpers:
		var h: Dictionary = helpers[r]
		var was := bool(h["alive"])
		var now_alive := _helper_alive(int(r))
		if now_alive:
			if not was:
				h["alive"] = true
				Log.i("lab", "helper rank %d is heart-beating again; it gets work from the next batch" % int(r))
			if seq < int(h.get("bench_until", 0)):
				continue
			out.append(int(r))
		elif was:
			h["alive"] = false
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
		return bool(h["last_ok"])   # poll() asks often; the file system is asked 4x a second
	h["checked_ms"] = now_ms
	var ok := OS.is_process_running(int(h["pid"]))
	if ok:
		var hb := gen_dir.path_join("hb_r%d.json" % r)
		var mt := int(FileAccess.get_modified_time(hb)) if FileAccess.file_exists(hb) else 0
		ok = heartbeat_ok(h, mt, int(Time.get_unix_time_from_system()), now_ms, heartbeat_timeout_s)
	h["last_ok"] = ok
	return ok


## The heartbeat rule on its own (tested directly): keeps the newest heartbeat file time in
## h["hb_s"], so a failed stat (0) never replaces a good one. Fresh = at most `timeout_s` old;
## before its first heartbeat a helper has STARTUP_TIMEOUT_MS; after a pause every helper gets a
## fresh grace period (h["grace_until_ms"], see on_resume).
static func heartbeat_ok(h: Dictionary, mtime: int, now_s: int, now_ms: int, timeout_s := HEARTBEAT_TIMEOUT_S) -> bool:
	if mtime > int(h.get("hb_s", 0)):
		h["hb_s"] = mtime
	if now_ms < int(h.get("grace_until_ms", 0)):
		return true
	var last := int(h.get("hb_s", 0))
	if last <= 0:
		return now_ms - int(h.get("started_ms", 0)) < STARTUP_TIMEOUT_MS
	return now_s - last <= timeout_s


## Coordinator, after the run was paused for `paused_ms`: batch deadlines do not count the pause
## and every helper gets a fresh heartbeat grace period (a helper may have been frozen too).
func on_resume(paused_ms: int) -> void:
	_submit_ms += paused_ms
	if _own_done_ms >= 0:
		_own_done_ms += paused_ms
	for r in _start_ms:
		_start_ms[r] = int(_start_ms[r]) + paused_ms
	var now := Time.get_ticks_msec()
	for r in helpers:
		var h: Dictionary = helpers[r]
		h["grace_until_ms"] = now + heartbeat_timeout_s * 1000
		h.erase("checked_ms")


func _ensure_helpers() -> void:
	if _spawned or rank != 0:
		return
	_spawned = true
	if spawner.is_valid():
		spawner.call()


func submit(p_items: Array, p_payload: Dictionary) -> void:
	_ensure_helpers()
	seq += 1
	id = "%06d" % seq
	items = p_items
	payload = p_payload
	results.clear()
	pending.clear()
	_clear_gen_files()
	var live := alive_helpers()
	var ranks := [0]
	ranks.append_array(live)
	var groups := {}
	for r in ranks:
		groups[r] = []
	for j in items.size():
		(groups[ranks[j % ranks.size()]] as Array).append(items[j])
	var mine: Array = groups[0]
	if not live.is_empty():
		var assign := {}
		for r in live:
			assign[str(r)] = groups[r]
		var err := LabIO.write_json(gen_dir.path_join("task_%s.json" % id), {"id": id, "payload": payload, "assign": assign}, 6)
		if err == OK:
			_booting.clear()
			_start_ms.clear()
			for r in live:
				pending[r] = groups[r]
				# a helper that has not heart-beat yet is still starting its process: its delivery
				# deadline counts from when it comes up (the startup timeout covers the boot)
				_booting[r] = int((helpers[r] as Dictionary).get("hb_s", 0)) <= 0
		else:
			# the helpers can never see this batch: run all of it here
			Log.w("lab", "could not hand batch %s to the helpers (%s); running it on the coordinator" % [id, error_string(err)])
			mine = items.duplicate()
	_submit_ms = Time.get_ticks_msec()
	_own_count = mine.size()
	_own_done_ms = -1
	_last_result_check = -100000
	_prepare_runner(payload, "")
	runner.add_items(mine)


## Removes the previous batch's task/result files and helper staging folders.
func _clear_gen_files() -> void:
	for fn in DirAccess.get_files_at(gen_dir):
		if str(fn).begins_with("task_") or str(fn).begins_with("result_"):
			DirAccess.remove_absolute(gen_dir.path_join(str(fn)))
	for dn in DirAccess.get_directories_at(gen_dir):
		if str(dn).begins_with("stage_"):
			LabIO.remove_tree(gen_dir.path_join(str(dn)))


## Coordinator: removes leftovers of the last batch (end of the run).
func cleanup() -> void:
	if rank == 0 and gen_dir != "" and DirAccess.dir_exists_absolute(gen_dir):
		_clear_gen_files()


## `stage_dir`: where this rank's recorded shards go ("" = the payload's dataset folder).
func _prepare_runner(p: Dictionary, stage_dir: String) -> void:
	runner.resolver = resolver_for(p)
	if str(p.get("record_dir", "")) != "":
		sink = LabRecordSink.new(stage_dir if stage_dir != "" else str(p["record_dir"]), "r%d" % rank)
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
	var now := Time.get_ticks_msec()
	if not runner.busy():
		if sink != null:
			sink.flush()
		if _own_done_ms < 0:
			_own_done_ms = now
	if pending.is_empty() or now - _last_result_check < RESULT_CHECK_MS:
		return results.size() >= items.size()
	_last_result_check = now
	for r in pending.keys():
		var share: Array = pending[r]
		var d := LabIO.read_json(gen_dir.path_join("result_%s_r%d.json" % [id, int(r)]))
		if not d.is_empty() and str(d.get("id", "")) == id:
			for res: Dictionary in d.get("results", []):
				var i := int(res.get("i", -1))
				if not results.has(i):
					results[i] = res
			_commit_shards(d.get("shards", []), int(r))
			helper_stats[r] = d.get("stats", {})
			helpers[r]["misses"] = 0
			pending.erase(r)
			continue
		if not _helper_alive(int(r)):
			helpers[r]["alive"] = false
			Log.w("lab", "helper rank %d stopped responding; re-running its %d episodes here" % [int(r), share.size()])
			reassigned += share.size()
			_requeue(int(r))
			continue
		if bool(_booting.get(r, false)):
			if int((helpers[r] as Dictionary).get("hb_s", 0)) <= 0:
				continue
			_booting[r] = false
			_start_ms[r] = now
		var limit := deadline_s(_own_done_ms - _submit_ms if _own_done_ms >= 0 else -1, _own_count, share.size(), straggler_min_s)
		if limit > 0.0 and float(now - int(_start_ms.get(r, _submit_ms))) / 1000.0 > limit:
			var h: Dictionary = helpers[r]
			h["misses"] = int(h.get("misses", 0)) + 1
			Log.w("lab", "helper rank %d did not deliver batch %s within %.0f s; re-running its %d episodes here" % [int(r), id, limit, share.size()])
			if int(h["misses"]) >= MAX_MISSES:
				h["bench_until"] = seq + 1 + BENCH_BATCHES
				h["misses"] = 0
				Log.w("lab", "helper rank %d missed %d deadlines in a row; it gets no work for %d batches" % [int(r), MAX_MISSES, BENCH_BATCHES])
			late += share.size()
			_requeue(int(r))
	return results.size() >= items.size()


## The straggler deadline (seconds after submission) for a helper share of `share` episodes,
## given that the coordinator finished its own `own_count` episodes `own_ms` after submission
## (-1 = not yet: no deadline). Never less than `min_s`.
static func deadline_s(own_ms: int, own_count: int, share: int, min_s: float) -> float:
	if own_ms < 0:
		return -1.0
	var own_s := maxf(float(own_ms) / 1000.0, 0.001)
	return maxf(min_s, STRAGGLER_FACTOR * own_s * float(share) / float(maxi(own_count, 1)))


func _requeue(r: int) -> void:
	runner.add_items(pending[r])
	pending.erase(r)


## Moves a helper's staged shards (inside gen/) into the dataset.
func _commit_shards(files: Array, r: int) -> void:
	var dest := str(payload.get("record_dir", ""))
	if dest == "":
		return
	var stage_root := gen_dir.path_join("stage_")
	for f in files:
		var src := str(f).replace("\\", "/")
		if not src.begins_with(stage_root) or src.contains("..") or not FileAccess.file_exists(src):
			Log.w("lab", "ignoring shard %s reported by helper rank %d" % [src.get_file(), r])
			continue
		var err := LabIO.move_file(src, dest.path_join(src.get_file()))
		if err == OK:
			committed_shards += 1
		else:
			Log.w("lab", "could not add helper shard %s to the dataset: %s" % [src.get_file(), error_string(err)])


func ordered_results() -> Array:
	var out := []
	for it: Dictionary in items:
		out.append(results.get(int(it["i"]), {"i": int(it["i"]), "error": "missing"}))
	return out


## Helper rank: rewrites the heartbeat file (every second from helper_poll; the worker also calls
## this while the run is paused, so a long pause never looks like a dead helper).
func heartbeat(stats: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hb_ms <= 1000:
		return
	_last_hb_ms = now
	LabIO.write_json(gen_dir.path_join("hb_r%d.json" % rank), {"rank": rank, "pid": OS.get_process_id(), "task": _task_id,
		"idle": _task_id == "", "loops": loops, "stats": stats})


## True while this helper has nothing to do (the worker sleeps longer between frames then).
func helper_idle() -> bool:
	return _task_id == ""


## Helper rank: picks up work, reports results and heart-beats. Call once per frame.
func helper_poll(stats: Dictionary) -> void:
	loops += 1
	heartbeat(stats)
	var now := Time.get_ticks_msec()
	if _task_id == "":
		if now < _next_task_scan:
			return
		_next_task_scan = now + _idle_poll_ms
		_idle_poll_ms = mini(int(float(_idle_poll_ms) * 1.5), IDLE_POLL_MAX_MS)
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
		_idle_poll_ms = IDLE_POLL_MIN_MS
		_task_id = newest
		_task_results = []
		_unsent = {}
		var mine: Array = (d.get("assign", {}) as Dictionary).get(str(rank), [])
		_prepare_runner(d.get("payload", {}), gen_dir.path_join("stage_%s_r%d" % [_task_id, rank]))
		runner.add_items(mine)
		return
	_task_results.append_array(runner.take_results())
	if now - _last_hb_ms < 20 and not FileAccess.file_exists(gen_dir.path_join("task_%s.json" % _task_id)):
		# the coordinator moved on (it re-ran our share itself): drop the stale work
		_drop_task()
		return
	if runner.busy():
		return
	if _unsent.is_empty():
		if sink != null:
			sink.flush()
		_unsent = {"id": _task_id, "rank": rank, "results": _task_results, "stats": stats,
			"shards": Array(sink.files) if sink != null else []}
		_unsent_since = now
		_next_send = now
	if now < _next_send:
		return
	var err := LabIO.write_json(gen_dir.path_join("result_%s_r%d.json" % [_task_id, rank]), _unsent, 6)
	if err == OK:
		_drop_task()
	elif now - _unsent_since > RESULT_GIVE_UP_MS:
		Log.w("lab", "helper rank %d could not deliver batch %s (%s); the coordinator re-runs it" % [rank, _task_id, error_string(err)])
		_drop_task()
	else:
		_next_send = now + RESULT_RETRY_MS


func _drop_task() -> void:
	runner.clear()
	_last_done = _task_id
	_task_id = ""
	_task_results = []
	_unsent = {}
	sink = null
