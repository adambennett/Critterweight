class_name LabRecordSink
extends RefCounted
## Collects recorded teacher samples from finished episodes of one worker rank and writes them
## as dataset shards (several thousand samples per shard). Every sample keeps its episode's
## recording index (item.rec_index: unique within the dataset) and scenario seed, so the
## behaviour-cloning split stays episode-disjoint and copies of an episode can be recognised.
## Helpers write into a staging folder of their task (LabBatch commits those shards only when it
## accepts the helper's result, so a helper whose share was re-run never adds a second copy);
## the coordinator writes into the dataset folder directly.

const FLUSH_AT := 6000

var dir := ""
var tag := "rec"
var obs := PackedFloat32Array()
var moves := PackedByteArray()
var buttons := PackedByteArray()
var episodes := PackedInt32Array()
var seeds := PackedInt32Array()
var written := 0
## shard files written so far (helpers report them with their results)
var files := PackedStringArray()
var _local := 0


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
	var it: Dictionary = ep.item
	var index := int(it.get("rec_index", -1))
	if index < 0:
		index = _local
		_local += 1
	var sd := int((it.get("episode", {}) as Dictionary).get("seed", 0))
	obs.append_array(r.obs_rows)
	moves.append_array(r.moves)
	buttons.append_array(r.buttons)
	for k in r.moves.size():
		episodes.append(index)
		seeds.append(sd)
	r.obs_rows = PackedFloat32Array()
	r.moves = PackedByteArray()
	r.buttons = PackedByteArray()
	r.episodes = PackedInt32Array()
	if moves.size() >= FLUSH_AT:
		flush()


func flush() -> void:
	if moves.is_empty() or dir == "":
		return
	var res := PolicyDataset.write_shard(dir, obs, moves, buttons, episodes, tag, seeds)
	if res["ok"]:
		written += moves.size()
		files.append(str(res["file"]))
	else:
		Log.w("lab", "could not write dataset shard: %s" % str(res["error"]))
	obs = PackedFloat32Array()
	moves = PackedByteArray()
	buttons = PackedByteArray()
	episodes = PackedInt32Array()
	seeds = PackedInt32Array()
