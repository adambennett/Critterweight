class_name LabRecordSink
extends RefCounted
## Collects recorded teacher samples from finished episodes of one worker rank and writes them
## as dataset shards (several thousand samples per shard; each episode keeps its own episode id
## so the behaviour-cloning validation split stays episode-disjoint).

const FLUSH_AT := 6000

var dir := ""
var tag := "rec"
var obs := PackedFloat32Array()
var moves := PackedByteArray()
var buttons := PackedByteArray()
var episodes := PackedInt32Array()
var written := 0
var _episode := 0


func _init(p_dir := "", p_tag := "rec") -> void:
	dir = p_dir
	tag = p_tag


func on_episode(ep: LabEpisode) -> void:
	var r := ep.recorder
	if r == null:
		return
	r._close_window()
	if r.moves.is_empty():
		return
	obs.append_array(r.obs_rows)
	moves.append_array(r.moves)
	buttons.append_array(r.buttons)
	for k in r.moves.size():
		episodes.append(_episode)
	_episode += 1
	r.obs_rows = PackedFloat32Array()
	r.moves = PackedByteArray()
	r.buttons = PackedByteArray()
	r.episodes = PackedInt32Array()
	if moves.size() >= FLUSH_AT:
		flush()


func flush() -> void:
	if moves.is_empty() or dir == "":
		return
	var res := PolicyDataset.write_shard(dir, obs, moves, buttons, episodes, tag)
	if res["ok"]:
		written += moves.size()
	else:
		Log.w("lab", "could not write dataset shard: %s" % str(res["error"]))
	obs = PackedFloat32Array()
	moves = PackedByteArray()
	buttons = PackedByteArray()
	episodes = PackedInt32Array()
	_episode = 0
