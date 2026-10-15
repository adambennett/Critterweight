class_name PolicyRecorder
extends InputSource
## Imitation-learning recorder: wraps any InputSource (the local human player, a scripted bot,
## a replay) and logs (observation, action) pairs in the SAME contracts the policies use
## (obs_v1 / act_v1), at the policy decision rate. The wrapped source plays exactly as before;
## the recorder only observes FighterInput after it was written.
##
## Labels: each decision window's observed input is mapped to act_v1 classes by
## PolicyActions.classify_move / classify_button (the inverse of the policy decoder). Samples
## are only recorded during live fighting (inputs enabled, match not finished).
## Flushing: samples go to a dataset shard when the match finishes, or when `finish()` is
## called (LabRecording connects it to the match scene leaving the tree, e.g. quitting early).

var inner: InputSource
var dataset_dir := ""
var decision_ticks := 8
var min_samples := 30
var tag := "rec"
var encoder := PolicyObs.new(1)

var obs_rows := PackedFloat32Array()
var moves := PackedByteArray()
var buttons := PackedByteArray()
var episodes := PackedInt32Array()
var episode := 0
var flushed_files: PackedStringArray = PackedStringArray()
var last_error := ""

var _tick := 0
var _pending_obs := PackedFloat32Array()
var _frame: Array = []
var _move_sum := Vector3.ZERO
var _move_n := 0
var _presses := 0
var _held_ticks := PackedInt32Array()
var _last_counts := PackedByteArray()
var _prev_move := 0
var _prev_button := 0
var _done := false
var _was_live := false


func _init(wrapped: InputSource = null, dir := "", source_tag := "rec") -> void:
	inner = wrapped
	dataset_dir = dir
	tag = source_tag
	decision_ticks = PolicyActions.decision_ticks(PolicyActions.DEFAULT_DECISION_HZ)
	_held_ticks.resize(FighterInput.BUTTON_COUNT)


func label() -> String:
	return inner.label() if inner != null else "Recorder"


## Unknown properties are forwarded to the wrapped source (e.g. LocalPlayerInput.enabled /
## camera), so code that adjusts the player's input keeps working while recording.
func _get(property: StringName) -> Variant:
	if inner != null and property in inner:
		return inner.get(property)
	return null


func _set(property: StringName, value: Variant) -> bool:
	if inner != null and property in inner:
		inner.set(property, value)
		return true
	return false


func poll(f: Fighter, sim, dt: float) -> void:
	if _last_counts.size() != FighterInput.BUTTON_COUNT:
		# prime the press counters before the first poll so its presses are seen
		_last_counts = f.input.press_count.duplicate()
	if inner != null:
		inner.poll(f, sim, dt)
	var ms := sim as MatchSim
	var live := ms != null and ms.input_enabled and not ms.is_finished and not _done
	if ms != null and ms.is_finished and not _done:
		_close_window()
		flush()
		_done = true
		return
	if not live:
		if _was_live:
			# a round ended: drop the half window, start a new "episode" for the split
			_pending_obs = PackedFloat32Array()
			episode += 1
			encoder.reset()
			_prev_move = 0
			_prev_button = 0
		_was_live = false
		_last_counts = f.input.press_count.duplicate()
		return
	_was_live = true
	# window boundary first: the observation is taken before this tick's input takes effect,
	# exactly like a policy decision, and this tick's input belongs to the new window
	if _pending_obs.is_empty() or _tick >= decision_ticks:
		_close_window()
		_open_window(f, ms)
	var pc := f.input.press_count
	if _last_counts.size() == FighterInput.BUTTON_COUNT:
		for b in FighterInput.BUTTON_COUNT:
			if pc[b] != _last_counts[b]:
				_presses |= 1 << b
	_last_counts = pc.duplicate()
	for b in FighterInput.BUTTON_COUNT:
		if f.input.is_held(b):
			_held_ticks[b] += 1
	_move_sum += f.input.move
	_move_n += 1
	_tick += 1


func _open_window(f: Fighter, sim: MatchSim) -> void:
	_pending_obs = encoder.encode(f, sim, _prev_move, _prev_button)
	var tp = f.target.pos() if f.target != null and not f.target.is_out() else null
	_frame = PolicyActions.frame(f, tp)
	_tick = 0
	_move_sum = Vector3.ZERO
	_move_n = 0
	_presses = 0
	_held_ticks.fill(0)


func _close_window() -> void:
	if _pending_obs.is_empty() or _move_n == 0:
		return
	var mv := _move_sum / float(_move_n)
	var mc := PolicyActions.classify_move(mv, _frame[0], _frame[1])
	var bc := PolicyActions.classify_button(_presses, _held_ticks, _move_n, _prev_button)
	obs_rows.append_array(_pending_obs)
	moves.append(mc)
	buttons.append(bc)
	episodes.append(episode)
	_prev_move = mc
	_prev_button = bc
	_pending_obs = PackedFloat32Array()


func sample_count() -> int:
	return moves.size()


## Writes buffered samples to a new shard in `dataset_dir` (if enough were collected).
func flush() -> String:
	if moves.size() < min_samples or dataset_dir == "":
		return ""
	var r := PolicyDataset.write_shard(dataset_dir, obs_rows, moves, buttons, episodes, tag)
	if not r["ok"]:
		last_error = str(r["error"])
		Log.w("recorder", "could not save recorded samples: %s" % last_error)
		return ""
	flushed_files.append(str(r["file"]))
	Log.i("recorder", "saved %d samples to %s" % [moves.size(), str(r["file"])])
	obs_rows = PackedFloat32Array()
	moves = PackedByteArray()
	buttons = PackedByteArray()
	episodes = PackedInt32Array()
	return str(r["file"])


## Flushes once (e.g. connected to the match scene's tree_exiting when a player quits early).
func finish() -> void:
	if _done:
		return
	_close_window()
	flush()
	_done = true
