extends Node
## Autoload "Saves": versioned, checksummed, atomic JSON persistence (D-015, SAV-02).
##
## Envelope: {"format":"critterweight","kind":K,"version":N,"game_version":V,"saved_at":unix,
##            "checksum":sha256(canonical data json),"data":{...}}
## Write: serialize -> <path>.tmp (flush, re-read and verify) -> rotate existing to <path>.bak ->
##        rename tmp to <path>. A crash at any point leaves either the old file, the .bak, or a
##        verified .tmp — read_json() recovers from whichever is valid.
## Read never deletes or overwrites anything. Unrecoverable files can be quarantined explicitly.

const FORMAT := "critterweight"

## Test hook: when set, write_json() stops after writing the temp file (simulated crash).
var simulate_crash_after_tmp := false


func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Canonical form for hashing: JSON parsing turns every number into a float, so integral floats
## are normalized to ints (recursively) and keys are sorted before hashing.
static func canonical(v):
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and floorf(f) == f and absf(f) < 9.0e15:
				return int(f)
			return f
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[str(k)] = canonical(v[k])
			return out
		TYPE_ARRAY:
			var arr := []
			for e in v:
				arr.append(canonical(e))
			return arr
	return v


static func checksum(data) -> String:
	return JSON.stringify(canonical(data), "", true, true).sha256_text()


func envelope(kind: String, version: int, data) -> Dictionary:
	# checksum what a reader will get back: Godot's JSON parser is not exact for every 17-digit
	# float (e.g. 101.44279598486929 reads back 1 ulp off), which made verification of such saves fail
	var j := JSON.new()
	var as_read = j.data if j.parse(JSON.stringify(data, "", false, true)) == OK else data
	return {"format": FORMAT, "kind": kind, "version": version, "game_version": game_version(),
		"saved_at": Time.get_unix_time_from_system(), "checksum": checksum(as_read), "data": data}


func write_json(path: String, kind: String, version: int, data) -> Error:
	var env := envelope(kind, version, data)
	var text := JSON.stringify(env, "\t", false, true)
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		Log.e("saves", "cannot write %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()
	# verify what actually reached the disk before replacing anything
	var check := _parse_envelope(FileAccess.get_file_as_string(tmp), kind)
	if not check["ok"]:
		Log.e("saves", "verification failed for %s: %s" % [tmp, check["error"]])
		return ERR_FILE_CORRUPT
	if simulate_crash_after_tmp:
		return OK
	var bak := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var e1 := DirAccess.rename_absolute(path, bak)
		if e1 != OK:
			Log.e("saves", "cannot rotate %s -> .bak: %s" % [path, error_string(e1)])
			return e1
	var e2 := DirAccess.rename_absolute(tmp, path)
	if e2 != OK:
		Log.e("saves", "cannot move %s into place: %s" % [tmp, error_string(e2)])
		return e2
	return OK


func _parse_envelope(text: String, kind: String) -> Dictionary:
	if text == "":
		return {"ok": false, "error": "empty file"}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	var env = json.data
	if typeof(env) != TYPE_DICTIONARY or env.get("format", "") != FORMAT:
		return {"ok": false, "error": "not a %s save file" % FORMAT}
	if kind != "" and env.get("kind", "") != kind:
		return {"ok": false, "error": "wrong kind '%s' (expected '%s')" % [env.get("kind", ""), kind]}
	if not env.has("data") or checksum(env["data"]) != str(env.get("checksum", "")):
		return {"ok": false, "error": "checksum mismatch (file damaged or edited)"}
	return {"ok": true, "env": env}


## Reads and validates a save. `current_version` is what this build writes; `migrate` is
## Callable(data, from_version) -> data (or null if unsupported) applied for older files.
## Returns {ok, data, version, error, recovered_from ("", "tmp", "bak"), migrated (bool), newer (bool)}.
func read_json(path: String, kind: String, current_version: int, migrate: Callable = Callable()) -> Dictionary:
	var res := {"ok": false, "data": null, "version": 0, "error": "", "recovered_from": "", "migrated": false, "newer": false, "exists": false}
	var candidates := [[path, ""], [path + ".tmp", "tmp"], [path + ".bak", "bak"]]
	var errors := []
	# Collect every valid copy, newest first: a verified .tmp newer than the main file means a
	# write was interrupted after verification, so it holds the latest data.
	var valid := []
	for c in candidates:
		if not FileAccess.file_exists(c[0]):
			continue
		res["exists"] = true
		var parsed := _parse_envelope(FileAccess.get_file_as_string(c[0]), kind)
		if not parsed["ok"]:
			errors.append("%s: %s" % [str(c[0]).get_file(), parsed["error"]])
			continue
		valid.append([c[0], c[1], parsed["env"]])
	valid.sort_custom(func(a, b): return float(a[2].get("saved_at", 0)) > float(b[2].get("saved_at", 0)) or (float(a[2].get("saved_at", 0)) == float(b[2].get("saved_at", 0)) and a[1] == ""))
	for c in valid:
		var env: Dictionary = c[2]
		var v := int(env.get("version", 0))
		if v > current_version:
			res["newer"] = true
			res["error"] = "%s was saved by a newer version of the game (format v%d > v%d). It was left untouched." % [str(c[0]).get_file(), v, current_version]
			return res
		var data = env["data"]
		if v < current_version:
			if not migrate.is_valid():
				errors.append("%s: no migration from v%d" % [str(c[0]).get_file(), v])
				continue
			data = migrate.call(data, v)
			if data == null:
				errors.append("%s: migration from v%d failed" % [str(c[0]).get_file(), v])
				continue
			res["migrated"] = true
		res["ok"] = true
		res["data"] = data
		res["version"] = v
		res["recovered_from"] = c[1]
		if c[1] != "":
			Log.w("saves", "recovered %s from .%s (%s)" % [path.get_file(), c[1], "; ".join(errors)])
		return res
	res["error"] = "; ".join(errors) if not errors.is_empty() else "file not found"
	return res


## Moves a damaged file aside (never deletes) so a fresh one can be created; returns new path.
func quarantine(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var dst := "%s.damaged-%d" % [path, int(Time.get_unix_time_from_system())]
	DirAccess.rename_absolute(path, dst)
	Log.w("saves", "quarantined %s -> %s" % [path.get_file(), dst.get_file()])
	return dst


func delete_save(path: String) -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
