class_name PolicyDataset
extends RefCounted
## Imitation datasets: (obs_v1, act_v1) samples recorded from human play or scripted teachers,
## stored under `<user data>/lab/datasets/<id>/`:
##   meta.json            Saves envelope (kind "lab_dataset"): id, name, creature, contracts,
##                        source description, optional teacher statistics
##   shard_*.bin          one recording session each (self-describing binary, see below)
## Shards are discovered by scanning, so several writers (worker ranks, the game) never contend
## on one index file.
##
## Shard layout (little endian): "CWDS" | u16 format | u16 obs_size | u32 count | u32 flags |
##   f32[count * obs_size] observations | u8[count] move | u8[count] button | u32[count] episode
## Reading validates the header, exact file length, finite values and label ranges; the
## content is numbers only — nothing is executed.

const MAGIC := "CWDS"
const SHARD_VERSION := 1
const META_VERSION := 1
const HEADER_BYTES := 16
const MAX_SHARD_SAMPLES := 250000
const MAX_TOTAL_SAMPLES := 2000000

static var root_override := ""


static func root() -> String:
	if root_override != "":
		if not DirAccess.dir_exists_absolute(root_override):
			DirAccess.make_dir_recursive_absolute(root_override)
		return root_override
	var tree := Engine.get_main_loop() as SceneTree
	var paths: Node = tree.root.get_node_or_null("Paths") if tree != null else null
	var base: String = str(paths.call("dir", "lab")) if paths != null else OS.get_user_data_dir().path_join("lab")
	var d := base.path_join("datasets")
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d


static func dir_for(id: String) -> String:
	return root().path_join(PolicyLibrary.file_stem(id))


static func _saves() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Saves") if tree != null else null


## Meta is stored as one JSON string inside the Saves envelope so the envelope checksum covers
## exact text (float values do not survive Godot's JSON round trip bit-exactly).
static func read_meta(dir: String) -> Dictionary:
	var saves := _saves()
	if saves == null:
		return {}
	var r: Dictionary = saves.call("read_json", dir.path_join("meta.json"), "lab_dataset", META_VERSION)
	if not r["ok"] or typeof(r["data"]) != TYPE_DICTIONARY:
		return {}
	var parsed = JSON.parse_string(str((r["data"] as Dictionary).get("json", "")))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func write_meta(dir: String, meta: Dictionary) -> Error:
	var saves := _saves()
	if saves == null:
		return ERR_UNAVAILABLE
	DirAccess.make_dir_recursive_absolute(dir)
	return saves.call("write_json", dir.path_join("meta.json"), "lab_dataset", META_VERSION, {"json": JSON.stringify(meta, "", false, true)})


## Creates the dataset folder + meta if missing; returns the folder.
static func ensure(id: String, display_name: String, creature: String, source: String) -> String:
	var dir := dir_for(id)
	if read_meta(dir).is_empty():
		var now := PolicyData.now_iso()
		write_meta(dir, {"id": id, "name": display_name, "creature": creature, "obs_version": PolicyObs.VERSION,
			"obs_size": PolicyObs.SIZE, "act_version": PolicyActions.VERSION, "source": source, "created": now, "updated": now})
	return dir


static func write_shard(dir: String, obs: PackedFloat32Array, moves: PackedByteArray, buttons: PackedByteArray, episodes: PackedInt32Array, tag := "rec") -> Dictionary:
	var n := moves.size()
	if n == 0 or buttons.size() != n or episodes.size() != n or obs.size() != n * PolicyObs.SIZE:
		return {"ok": false, "error": "inconsistent sample buffers", "file": ""}
	if n > MAX_SHARD_SAMPLES:
		return {"ok": false, "error": "too many samples for one shard", "file": ""}
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := "%s_%d_%04d" % [Time.get_datetime_string_from_system(true, false).replace(":", "").replace("-", ""), OS.get_process_id(), randi() % 10000]
	var path := dir.path_join("shard_%s_%s.bin" % [PolicyLibrary.file_stem(tag), stamp])
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": error_string(FileAccess.get_open_error()), "file": ""}
	f.big_endian = false
	f.store_buffer(MAGIC.to_ascii_buffer())
	f.store_16(SHARD_VERSION)
	f.store_16(PolicyObs.SIZE)
	f.store_32(n)
	f.store_32(0)
	f.store_buffer(obs.to_byte_array())
	f.store_buffer(moves)
	f.store_buffer(buttons)
	f.store_buffer(episodes.to_byte_array())
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return {"ok": false, "error": error_string(err), "file": ""}
	var meta := read_meta(dir)
	if not meta.is_empty():
		meta["updated"] = PolicyData.now_iso()
		write_meta(dir, meta)
	return {"ok": true, "error": "", "file": path}


## Reads and validates one shard. {ok, error, count, obs, moves, buttons, episodes}
static func read_shard(path: String) -> Dictionary:
	var res := {"ok": false, "error": "", "count": 0}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		res["error"] = "cannot open %s" % path.get_file()
		return res
	f.big_endian = false
	var length := f.get_length()
	if length < HEADER_BYTES:
		res["error"] = "%s: truncated header" % path.get_file()
		return res
	if f.get_buffer(4).get_string_from_ascii() != MAGIC:
		res["error"] = "%s: not a dataset shard" % path.get_file()
		return res
	var ver := f.get_16()
	var obs_size := f.get_16()
	var n := f.get_32()
	f.get_32()
	if ver != SHARD_VERSION:
		res["error"] = "%s: unsupported shard version %d" % [path.get_file(), ver]
		return res
	if obs_size != PolicyObs.SIZE:
		res["error"] = "%s: observation size %d does not match %s (%d)" % [path.get_file(), obs_size, PolicyObs.VERSION, PolicyObs.SIZE]
		return res
	if n <= 0 or n > MAX_SHARD_SAMPLES:
		res["error"] = "%s: invalid sample count %d" % [path.get_file(), n]
		return res
	var expected := HEADER_BYTES + n * obs_size * 4 + n * 2 + n * 4
	if length != expected:
		res["error"] = "%s: wrong length %d (expected %d) — damaged file" % [path.get_file(), length, expected]
		return res
	var obs := f.get_buffer(n * obs_size * 4).to_float32_array()
	var moves := f.get_buffer(n)
	var buttons := f.get_buffer(n)
	var episodes := f.get_buffer(n * 4).to_int32_array()
	f.close()
	for x in obs:
		if not is_finite(x) or absf(x) > 100.0:
			res["error"] = "%s: invalid observation value" % path.get_file()
			return res
	for k in n:
		if moves[k] >= PolicyActions.MOVE_COUNT or buttons[k] >= PolicyActions.BUTTON_COUNT:
			res["error"] = "%s: invalid action label" % path.get_file()
			return res
	res["ok"] = true
	res["count"] = n
	res["obs"] = obs
	res["moves"] = moves
	res["buttons"] = buttons
	res["episodes"] = episodes
	return res


static func shard_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for fn in d.get_files():
		if str(fn).begins_with("shard_") and str(fn).ends_with(".bin"):
			out.append(dir.path_join(str(fn)))
	out.sort()
	return out


## Loads every valid shard. Damaged shards are skipped and reported (non-destructive).
## {ok, count, obs, moves, buttons, units (unique id per (shard, episode)), errors, meta}
static func load_all(dir: String, max_samples := MAX_TOTAL_SAMPLES) -> Dictionary:
	var obs := PackedFloat32Array()
	var moves := PackedByteArray()
	var buttons := PackedByteArray()
	var units := PackedInt32Array()
	var errors := PackedStringArray()
	var count := 0
	var unit_base := 0
	for path in shard_files(dir):
		var r := read_shard(path)
		if not r["ok"]:
			errors.append(str(r["error"]))
			continue
		var n := int(r["count"])
		if count + n > max_samples:
			errors.append("sample limit reached; remaining shards skipped")
			break
		obs.append_array(r["obs"])
		moves.append_array(r["moves"])
		buttons.append_array(r["buttons"])
		var eps: PackedInt32Array = r["episodes"]
		var max_ep := 0
		for k in n:
			units.append(unit_base + eps[k])
			max_ep = maxi(max_ep, eps[k])
		unit_base += max_ep + 1
		count += n
	return {"ok": count > 0, "count": count, "obs": obs, "moves": moves, "buttons": buttons, "units": units,
		"errors": errors, "meta": read_meta(dir)}


## Summaries for the UI: [{id, name, creature, source, samples, shards, updated, path, errors}]
static func list(creature_id := "") -> Array:
	var out := []
	var d := DirAccess.open(root())
	if d == null:
		return out
	var dirs := Array(d.get_directories())
	dirs.sort()
	for sub in dirs:
		var dir := root().path_join(str(sub))
		var meta := read_meta(dir)
		if meta.is_empty():
			continue
		if creature_id != "" and str(meta.get("creature", "")) != creature_id:
			continue
		var samples := 0
		var errors := PackedStringArray()
		var files := shard_files(dir)
		for path in files:
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null or f.get_length() < HEADER_BYTES:
				errors.append(path.get_file())
				continue
			f.get_buffer(8)
			samples += f.get_32()
			f.close()
		out.append({"id": str(meta.get("id", sub)), "name": str(meta.get("name", sub)), "creature": str(meta.get("creature", "")),
			"source": str(meta.get("source", "")), "samples": samples, "shards": files.size(), "updated": str(meta.get("updated", "")),
			"path": dir, "errors": errors, "teacher": meta.get("teacher", {})})
	return out


static func rename(id: String, new_name: String) -> Error:
	var dir := dir_for(id)
	var meta := read_meta(dir)
	if meta.is_empty():
		return ERR_DOES_NOT_EXIST
	meta["name"] = new_name.strip_edges().strip_escapes().substr(0, 64)
	meta["updated"] = PolicyData.now_iso()
	return write_meta(dir, meta)


## Deletes a dataset folder (its shards and meta files).
static func delete(id: String) -> Error:
	var dir := dir_for(id)
	var d := DirAccess.open(dir)
	if d == null:
		return ERR_DOES_NOT_EXIST
	for fn in d.get_files():
		DirAccess.remove_absolute(dir.path_join(str(fn)))
	return DirAccess.remove_absolute(dir)
