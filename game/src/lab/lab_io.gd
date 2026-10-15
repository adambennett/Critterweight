class_name LabIO
extends RefCounted
## File plumbing between the game (Lab UI) and training worker processes. Small JSON files are
## written atomically (temp file + rename) so a reader never sees half a file; a reader that
## races a rename simply gets {} and tries again on its next poll. Larger durable state
## (checkpoints, policies) goes through Saves / PolicyIO instead.
##
## Run folder layout (docs/AI_LAB.md "Run folder"):
##   job.json            the job (input; plain JSON so it can be written by hand)
##   status.json         {state, pid, message, ...}         written by the coordinator (rank 0)
##   progress.json       live counters and metrics          written by rank 0 (~2 Hz)
##   metrics.jsonl       one line per generation / epoch    appended by rank 0
##   control.json        {desired: run|pause|cancel, snapshot_seq}   written by the game
##   checkpoints/        ckpt_<n>.json (Saves envelopes, newest valid one is resumed)
##   gen/                task/result/heartbeat files between ranks
##   eval_*.json, report.json, best.policy.json, final.policy.json, worker_r<k>.log, home_r<k>/


static func write_json(path: String, data) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := "%s.%d.tmp" % [path, OS.get_process_id()]
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "", false, true))
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		# Windows cannot rename over a file another process holds open; retry once
		OS.delay_msec(5)
		err = DirAccess.rename_absolute(tmp, path)
		if err != OK:
			DirAccess.remove_absolute(tmp)
	return err


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


static func append_line(path: String, data: Dictionary) -> void:
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(JSON.stringify(data, "", false, true))
	f.flush()
	f.close()


static func read_lines(path: String, max_lines := 5000) -> Array:
	var out := []
	if not FileAccess.file_exists(path):
		return out
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n", false):
		var json := JSON.new()
		if json.parse(line) == OK and typeof(json.data) == TYPE_DICTIONARY:
			out.append(json.data)
	if out.size() > max_lines:
		out = out.slice(out.size() - max_lines)
	return out


## Keeps only metric lines whose `key` value is <= limit (used when resuming from a checkpoint
## older than the last written metrics line, so the curve has no duplicates).
static func truncate_lines(path: String, key: String, limit: int) -> void:
	var lines := read_lines(path, 1000000)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	for l: Dictionary in lines:
		if int(l.get(key, -1)) <= limit:
			f.store_line(JSON.stringify(l, "", false, true))
	f.close()


static func b64_floats(a: PackedFloat32Array) -> String:
	return Marshalls.raw_to_base64(a.to_byte_array())


static func floats_b64(s: String) -> PackedFloat32Array:
	if s == "" or s.length() % 4 != 0:
		return PackedFloat32Array()
	return Marshalls.base64_to_raw(s).to_float32_array()


static func remove_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		remove_tree(dir.path_join(str(sub)))
	for fn in d.get_files():
		DirAccess.remove_absolute(dir.path_join(str(fn)))
	DirAccess.remove_absolute(dir)


static func now_ms() -> int:
	return Time.get_ticks_msec()
