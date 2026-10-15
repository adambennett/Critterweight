extends Node
## Autoload "Saves": versioned, checksummed, atomic JSON persistence (D-015, SAV-02).
##
## Envelope: {"format":"critterweight","kind":K,"version":N,"game_version":V,"saved_at":unix,
##            "seq":S,"checksum":sha256(canonical data json),"data":{...}}
## `seq` counts writes of one file (one more than the highest valid copy on disk). Recovery orders
## copies by it, never by the wall clock, which can jump backwards or forwards.
## Write: refuse when any copy on disk (main, .tmp, .bak) was written by a NEWER format, so a newer
##        game's data is never overwritten -> serialize -> <path>.tmp (flush, re-read and verify) ->
##        a valid main file rotates to <path>.bak; a damaged one is quarantined instead (moved
##        aside), so the last valid .bak is never deleted -> rename tmp to <path>.
##        A crash at any point leaves the old file, the .bak, or a verified .tmp — read_json()
##        recovers from whichever is valid.
## Read: a valid main file wins; a verified .tmp wins over it only when its seq is higher (a write
##       interrupted after verification); otherwise .tmp/.bak by seq (legacy files without seq:
##       by saved_at). Any newer-format copy makes the result {newer: true}: callers then keep
##       that path read-only. Reading never deletes or overwrites anything.

const FORMAT := "critterweight"
const PRIORITY := {"": 0, "tmp": 1, "bak": 2}

## Test hook: when set, write_json() stops after writing the temp file (simulated crash).
var simulate_crash_after_tmp := false
## Test hook: when >= 0, the "saved_at" time written into envelopes (simulates a clock jump).
var clock_override := -1.0


func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


const MAX_EXACT_INT := 9007199254740991.0   ## 2^53 - 1: every whole number up to here is an exact double


## Canonical form for hashing: JSON parsing turns every number into a float, so integral floats
## are normalized to ints (recursively) and keys are sorted before hashing.
static func canonical(v):
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and floorf(f) == f and absf(f) <= MAX_EXACT_INT:
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


## Data exactly as it will read back: Godot's JSON text round trip is not exact for every double
## (small numbers lose trailing digits), so saves store and hash the round-trip fixed point. A
## checksum computed on the in-memory values would otherwise flag good files as damaged.
## Whole numbers are kept as integer text: the parser reads "N" exactly but misreads a large
## "N.0" by one, which would silently change 53-bit run seeds.
static func stabilize(data):
	var d = canonical(data)
	for i in 4:
		var t1 := JSON.stringify(d, "", true, true)
		var d2 = canonical(JSON.parse_string(t1))
		if JSON.stringify(d2, "", true, true) == t1:
			return d2
		d = d2
	return d


func _now() -> float:
	return clock_override if clock_override >= 0.0 else Time.get_unix_time_from_system()


func envelope(kind: String, version: int, data, seq := 1) -> Dictionary:
	var stable = stabilize(data)
	return {"format": FORMAT, "kind": kind, "version": version, "game_version": game_version(),
		"saved_at": _now(), "seq": seq, "checksum": checksum(stable), "data": stable}


## Everything on disk for `path`: {exists, copies: [[path, tag, env]] (valid, any version),
## main_valid, max_seq, newer: [path, version] or [] (the first copy of a newer format), errors}.
## A copy counts as newer when its header (format + kind) is ours and its version is higher,
## whatever its checksum says: a newer format may hash differently.
func _scan(path: String, kind: String, version: int) -> Dictionary:
	var out := {"exists": false, "copies": [], "main_valid": false, "max_seq": 0, "newer": [], "errors": []}
	for c in [[path, ""], [path + ".tmp", "tmp"], [path + ".bak", "bak"]]:
		if not FileAccess.file_exists(c[0]):
			continue
		out["exists"] = true
		var parsed := _parse_envelope(FileAccess.get_file_as_string(c[0]), kind)
		if bool(parsed["header_ok"]) and int(parsed["version"]) > version and (out["newer"] as Array).is_empty():
			out["newer"] = [c[0], int(parsed["version"])]
		if not parsed["ok"]:
			out["errors"].append("%s: %s" % [str(c[0]).get_file(), parsed["error"]])
			continue
		var env: Dictionary = parsed["env"]
		out["copies"].append([c[0], c[1], env])
		out["max_seq"] = maxi(int(out["max_seq"]), _seq_of(env))
		if c[1] == "":
			out["main_valid"] = true
	return out


static func _seq_of(env: Dictionary) -> int:
	var s = env.get("seq")
	return int(s) if typeof(s) == TYPE_FLOAT or typeof(s) == TYPE_INT else 0


## True when a copy of `path` was written by a newer format than `version` (never write it then).
func is_newer(path: String, kind: String, version: int) -> bool:
	return not (_scan(path, kind, version)["newer"] as Array).is_empty()


func write_json(path: String, kind: String, version: int, data) -> Error:
	var disk := _scan(path, kind, version)
	if not (disk["newer"] as Array).is_empty():
		Log.w("saves", "not writing %s: %s was saved by a newer version of the game (format v%d > v%d) and stays untouched" % [path.get_file(), str(disk["newer"][0]).get_file(), int(disk["newer"][1]), version])
		return ERR_FILE_CANT_WRITE
	var env := envelope(kind, version, data, int(disk["max_seq"]) + 1)
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
	if FileAccess.file_exists(path):
		if bool(disk["main_valid"]):
			# the main file is a valid copy, so the older .bak it replaces is not the last one
			var e1 := DirAccess.rename_absolute(path, path + ".bak")
			if e1 != OK:
				Log.e("saves", "cannot rotate %s -> .bak: %s" % [path, error_string(e1)])
				return e1
		elif quarantine(path) == "":
			# damaged: keep it for inspection and leave the .bak (maybe the only valid copy) alone
			Log.e("saves", "cannot move the damaged %s aside" % path)
			return ERR_FILE_CANT_WRITE
	var e2 := DirAccess.rename_absolute(tmp, path)
	if e2 != OK:
		Log.e("saves", "cannot move %s into place: %s" % [tmp, error_string(e2)])
		return e2
	return OK


## {ok, env, error, header_ok, version}: header_ok = format and kind are ours (version is then
## meaningful even when the checksum does not match).
func _parse_envelope(text: String, kind: String) -> Dictionary:
	var res := {"ok": false, "env": {}, "error": "", "header_ok": false, "version": 0}
	if text == "":
		res["error"] = "empty file"
		return res
	var json := JSON.new()
	if json.parse(text) != OK:
		res["error"] = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return res
	var env = json.data
	if typeof(env) != TYPE_DICTIONARY or env.get("format", "") != FORMAT:
		res["error"] = "not a %s save file" % FORMAT
		return res
	if kind != "" and env.get("kind", "") != kind:
		res["error"] = "wrong kind '%s' (expected '%s')" % [env.get("kind", ""), kind]
		return res
	res["header_ok"] = true
	var v = env.get("version", 0)
	res["version"] = int(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else 0
	if not env.has("data") or checksum(env["data"]) != str(env.get("checksum", "")):
		res["error"] = "checksum mismatch (file damaged or edited)"
		return res
	res["ok"] = true
	res["env"] = env
	return res


## Reads and validates a save. `current_version` is what this build writes; `migrate` is
## Callable(data, from_version) -> data (or null if unsupported) applied for older files.
## Returns {ok, data, version, error, recovered_from ("", "tmp", "bak"), migrated (bool), newer (bool), exists}.
func read_json(path: String, kind: String, current_version: int, migrate: Callable = Callable()) -> Dictionary:
	var res := {"ok": false, "data": null, "version": 0, "error": "", "recovered_from": "", "migrated": false, "newer": false, "exists": false}
	var disk := _scan(path, kind, current_version)
	res["exists"] = disk["exists"]
	if not (disk["newer"] as Array).is_empty():
		res["newer"] = true
		res["error"] = "%s was saved by a newer version of the game (format v%d > v%d). It was left untouched." % [str(disk["newer"][0]).get_file(), int(disk["newer"][1]), current_version]
		return res
	var errors: Array = (disk["errors"] as Array).duplicate()
	for c in _ordered(disk["copies"]):
		var env: Dictionary = c[2]
		var v := int(env.get("version", 0))
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


## Valid copies ([path, tag, env]) best first. A valid main file comes first, except that a .tmp
## written later (higher seq: a write interrupted after verification) goes before it; a .bak never
## does. The remaining copies follow by seq, then (copies written before seq existed) saved_at,
## then main > tmp > bak.
static func _ordered(copies: Array) -> Array:
	var rest := copies.duplicate()
	rest.sort_custom(_by_seq)
	var main_copy: Array = []
	for c in rest:
		if c[1] == "":
			main_copy = c
	if main_copy.is_empty():
		return rest
	rest.erase(main_copy)
	var out := []
	for c2 in rest:
		if c2[1] == "tmp" and _later(c2[2], main_copy[2]):
			out.append(c2)
	out.append(main_copy)
	for c3 in rest:
		if not c3 in out:
			out.append(c3)
	return out


## Whether envelope `a` was written after `b`: by seq, or by saved_at when neither has one.
static func _later(a: Dictionary, b: Dictionary) -> bool:
	var sa := _seq_of(a)
	var sb := _seq_of(b)
	if sa != sb:
		return sa > sb
	return sa == 0 and float(a.get("saved_at", 0)) > float(b.get("saved_at", 0))


## Total order for sort_custom: seq, then saved_at for copies without seq, then main > tmp > bak.
static func _by_seq(a: Array, b: Array) -> bool:
	if _later(a[2], b[2]):
		return true
	if _later(b[2], a[2]):
		return false
	return int(PRIORITY[a[1]]) < int(PRIORITY[b[1]])


## Moves a damaged file aside (never deletes, never replaces an earlier quarantined copy) so a
## fresh one can be created; returns the new path ("" if it could not be moved).
func quarantine(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var stem := "%s.damaged-%d" % [path, int(Time.get_unix_time_from_system())]
	var dst := stem
	var n := 2
	while FileAccess.file_exists(dst):
		dst = "%s-%d" % [stem, n]
		n += 1
	if DirAccess.rename_absolute(path, dst) != OK:
		return ""
	Log.w("saves", "quarantined %s -> %s" % [path.get_file(), dst.get_file()])
	return dst


func delete_save(path: String) -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
