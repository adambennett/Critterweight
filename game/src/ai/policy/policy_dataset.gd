class_name PolicyDataset
extends RefCounted
## Imitation datasets: (obs_v1, act_v1) samples recorded from human play or scripted teachers,
## stored under `<user data>/lab/datasets/<id>/`:
##   meta.json            Saves envelope (kind "lab_dataset"): id, name, creature, contracts,
##                        source description, optional teacher statistics, next_episode (the
##                        next free recording index, so a new recording run never reuses seeds)
##   shard_*.bin          one recording session each (self-describing binary, see below)
## Shards are discovered by scanning, so several writers (worker ranks, the game) never contend
## on one index file.
##
## Shard layout (little endian): "CWDS" | u16 format | u16 obs_size | u32 count | u32 flags |
##   f32[count * obs_size] observations | u8[count] move | u8[count] button | u32[count] episode
##   | (format 2) u32[count] seed
## `episode` identifies the sample's episode (teacher recordings: the dataset-wide recording
## index; human play: the round within the session). `seed` is the episode's scenario seed
## (0 = unknown, e.g. human play). Format 1 shards (no seed column) still load.
## Reading validates the header, exact file length, finite values and label ranges; the
## content is numbers only — nothing is executed.
##
## Loading (load_all / load_many) drops exact copies of an episode (same samples, e.g. a teacher
## recorded twice with the same seeds) and gives every remaining episode a split unit: its seed
## when known (so even non-identical copies of a seeded episode share one unit), else its content
## hash. Behaviour cloning splits by these units, so copies of an episode always land in the
## same split.

const MAGIC := "CWDS"
const SHARD_VERSION := 2
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


## Writes one shard (format 2). `seeds` (per sample) may be empty = unknown (0).
static func write_shard(dir: String, obs: PackedFloat32Array, moves: PackedByteArray, buttons: PackedByteArray, episodes: PackedInt32Array, tag := "rec", seeds := PackedInt32Array()) -> Dictionary:
	var n := moves.size()
	if n == 0 or buttons.size() != n or episodes.size() != n or obs.size() != n * PolicyObs.SIZE or (not seeds.is_empty() and seeds.size() != n):
		return {"ok": false, "error": "inconsistent sample buffers", "file": ""}
	if n > MAX_SHARD_SAMPLES:
		return {"ok": false, "error": "too many samples for one shard", "file": ""}
	var sd := seeds
	if sd.is_empty():
		sd = PackedInt32Array()
		sd.resize(n)
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
	f.store_buffer(sd.to_byte_array())
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


static func _expected_length(ver: int, n: int, obs_size: int) -> int:
	return HEADER_BYTES + n * obs_size * 4 + n * 2 + n * 4 + (n * 4 if ver >= 2 else 0)


## Reads and validates one shard. {ok, error, count, obs, moves, buttons, episodes, seeds}
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
	if ver < 1 or ver > SHARD_VERSION:
		res["error"] = "%s: unsupported shard version %d" % [path.get_file(), ver]
		return res
	if obs_size != PolicyObs.SIZE:
		res["error"] = "%s: observation size %d does not match %s (%d)" % [path.get_file(), obs_size, PolicyObs.VERSION, PolicyObs.SIZE]
		return res
	if n <= 0 or n > MAX_SHARD_SAMPLES:
		res["error"] = "%s: invalid sample count %d" % [path.get_file(), n]
		return res
	var expected := _expected_length(ver, n, obs_size)
	if length != expected:
		res["error"] = "%s: wrong length %d (expected %d) — damaged file" % [path.get_file(), length, expected]
		return res
	var obs := f.get_buffer(n * obs_size * 4).to_float32_array()
	var moves := f.get_buffer(n)
	var buttons := f.get_buffer(n)
	var episodes := f.get_buffer(n * 4).to_int32_array()
	var seeds := PackedInt32Array()
	if ver >= 2:
		seeds = f.get_buffer(n * 4).to_int32_array()
	else:
		seeds.resize(n)
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
	res["version"] = ver
	res["obs"] = obs
	res["moves"] = moves
	res["buttons"] = buttons
	res["episodes"] = episodes
	res["seeds"] = seeds
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


## Loads every valid shard of one folder (see load_many).
static func load_all(dir: String, max_samples := MAX_TOTAL_SAMPLES) -> Dictionary:
	return load_many([dir], max_samples)


## Loads every valid shard of several dataset folders. Damaged shards are skipped and reported
## (non-destructive). Exact copies of an episode are loaded once (`duplicate_episodes` /
## `duplicate_samples` count the dropped copies). {ok, count, obs, moves, buttons, units (split
## unit per sample: 0..episodes-1), episodes (distinct units), duplicate_episodes,
## duplicate_samples, errors, meta (first folder's), metas}
static func load_many(dirs: Array, max_samples := MAX_TOTAL_SAMPLES) -> Dictionary:
	var obs := PackedFloat32Array()
	var moves := PackedByteArray()
	var buttons := PackedByteArray()
	var units := PackedInt32Array()
	var errors := PackedStringArray()
	var metas := []
	var seen := {}          ## content hash -> true
	var unit_of := {}       ## unit key ("s<seed>" or "h<hash>") -> unit index
	var dup_eps := 0
	var dup_samples := 0
	var count := 0
	var full := false
	for dir in dirs:
		metas.append(read_meta(str(dir)))
		if full:
			continue
		for path in shard_files(str(dir)):
			var r := read_shard(path)
			if not r["ok"]:
				errors.append(str(r["error"]))
				continue
			var s_obs: PackedFloat32Array = r["obs"]
			var s_moves: PackedByteArray = r["moves"]
			var s_buttons: PackedByteArray = r["buttons"]
			var s_eps: PackedInt32Array = r["episodes"]
			var s_seeds: PackedInt32Array = r["seeds"]
			for grp: PackedInt32Array in _episode_groups(s_eps):
				var h := _episode_hash(s_obs, s_moves, s_buttons, grp)
				if seen.has(h):
					dup_eps += 1
					dup_samples += grp.size()
					continue
				if count + grp.size() > max_samples:
					errors.append("sample limit reached; remaining episodes skipped")
					full = true
					break
				seen[h] = true
				var sd := s_seeds[grp[0]]
				var key := ("s%d" % sd) if sd != 0 else ("h" + h)
				if not unit_of.has(key):
					unit_of[key] = unit_of.size()
				var unit: int = unit_of[key]
				_append_samples(grp, s_obs, s_moves, s_buttons, obs, moves, buttons)
				for k in grp.size():
					units.append(unit)
				count += grp.size()
			if full:
				break
	return {"ok": count > 0, "count": count, "obs": obs, "moves": moves, "buttons": buttons, "units": units,
		"episodes": unit_of.size(), "duplicate_episodes": dup_eps, "duplicate_samples": dup_samples,
		"errors": errors, "meta": metas[0] if not metas.is_empty() else {}, "metas": metas}


## Sample indices of each episode of a shard, in order of first appearance.
static func _episode_groups(eps: PackedInt32Array) -> Array:
	var order := []
	var by := {}
	for k in eps.size():
		var e := eps[k]
		if not by.has(e):
			by[e] = PackedInt32Array()
			order.append(e)
		var g: PackedInt32Array = by[e]
		g.append(k)
		by[e] = g
	var out := []
	for e in order:
		out.append(by[e])
	return out


static func _contiguous(grp: PackedInt32Array) -> bool:
	return grp[grp.size() - 1] - grp[0] + 1 == grp.size()


## sha256 over an episode's observations and labels (identical episodes hash identically).
static func _episode_hash(obs: PackedFloat32Array, moves: PackedByteArray, buttons: PackedByteArray, grp: PackedInt32Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var dim := PolicyObs.SIZE
	if _contiguous(grp):
		var a := grp[0]
		var b := grp[grp.size() - 1] + 1
		ctx.update(obs.slice(a * dim, b * dim).to_byte_array())
		ctx.update(moves.slice(a, b))
		ctx.update(buttons.slice(a, b))
	else:
		for k in grp:
			ctx.update(obs.slice(k * dim, (k + 1) * dim).to_byte_array())
			ctx.update(PackedByteArray([moves[k], buttons[k]]))
	return ctx.finish().hex_encode()


static func _append_samples(grp: PackedInt32Array, s_obs: PackedFloat32Array, s_moves: PackedByteArray, s_buttons: PackedByteArray,
		obs: PackedFloat32Array, moves: PackedByteArray, buttons: PackedByteArray) -> void:
	var dim := PolicyObs.SIZE
	if _contiguous(grp):
		var a := grp[0]
		var b := grp[grp.size() - 1] + 1
		obs.append_array(s_obs.slice(a * dim, b * dim))
		moves.append_array(s_moves.slice(a, b))
		buttons.append_array(s_buttons.slice(a, b))
		return
	for k in grp:
		obs.append_array(s_obs.slice(k * dim, (k + 1) * dim))
		moves.append(s_moves[k])
		buttons.append(s_buttons[k])


## What teacher recordings already hold, without reading observations: {seeds: {seed: true}
## (episodes with a known seed), next: one past the highest recording index stored with a seed}.
static func recorded_index(dir: String) -> Dictionary:
	var seeds := {}
	var next := 0
	for path in shard_files(dir):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null or f.get_length() < HEADER_BYTES:
			continue
		f.big_endian = false
		if f.get_buffer(4).get_string_from_ascii() != MAGIC:
			continue
		var ver := f.get_16()
		var obs_size := f.get_16()
		var n := f.get_32()
		f.get_32()
		if ver < 2 or ver > SHARD_VERSION or n <= 0 or n > MAX_SHARD_SAMPLES or f.get_length() != _expected_length(ver, n, obs_size):
			continue
		f.seek(HEADER_BYTES + n * obs_size * 4 + n * 2)
		var eps := f.get_buffer(n * 4).to_int32_array()
		var sds := f.get_buffer(n * 4).to_int32_array()
		for k in n:
			if sds[k] != 0:
				seeds[sds[k]] = true
				next = maxi(next, eps[k] + 1)
	return {"seeds": seeds, "next": next}


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
