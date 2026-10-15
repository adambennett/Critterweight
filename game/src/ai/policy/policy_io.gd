class_name PolicyIO
extends RefCounted
## `.policy.json` file access. Size is checked before reading, content is validated strictly by
## PolicyData.from_dict, writes are atomic (temp file -> flush -> re-read + validate -> rotate the
## old file to .bak -> rename), and reads recover from a verified .tmp/.bak copy when the main
## file is damaged — never silently overwriting a recoverable file (same rules as Saves, D-015).

const EXT := ".policy.json"


static func to_text(p: PolicyData) -> String:
	return JSON.stringify(p.to_dict(), "\t", true, true)


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "policy": null, "errors": PackedStringArray([msg]), "warnings": PackedStringArray()}


## Parses and validates one file. {ok, policy, errors, warnings}
static func read_one(path: String, expect_creature := "") -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("file not found: %s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _fail("cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
	var size := f.get_length()
	if size > PolicyData.MAX_FILE_BYTES:
		return _fail("file is too large (%d KB > %d KB limit)" % [size / 1024, PolicyData.MAX_FILE_BYTES / 1024])
	if size == 0:
		return _fail("file is empty")
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	var r := PolicyData.from_dict(json.data, expect_creature)
	if r["ok"]:
		(r["policy"] as PolicyData).path = path
	return r


## Reads a policy, falling back to a verified .tmp (interrupted write) or .bak copy.
static func read_file(path: String, expect_creature := "") -> Dictionary:
	var main := read_one(path, expect_creature)
	if main["ok"]:
		return main
	for alt in [path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(alt):
			var r := read_one(alt, expect_creature)
			if r["ok"]:
				var warns: PackedStringArray = r["warnings"]
				warns.append("recovered from %s (%s)" % [str(alt).get_file(), "; ".join(main["errors"])])
				r["warnings"] = warns
				(r["policy"] as PolicyData).path = path
				Log.w("policy", "recovered %s from %s" % [path.get_file(), str(alt).get_file()])
				return r
	return main


static func write_file(path: String, p: PolicyData) -> Error:
	var text := to_text(p)
	if text.length() > PolicyData.MAX_FILE_BYTES:
		Log.e("policy", "refusing to write %s: %d bytes exceeds the policy size limit" % [path, text.length()])
		return ERR_OUT_OF_MEMORY
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		Log.e("policy", "cannot write %s: %s" % [tmp, error_string(err)])
		return err
	f.store_string(text)
	f.flush()
	f.close()
	var check := read_one(tmp)
	if not check["ok"]:
		Log.e("policy", "verification of %s failed: %s" % [tmp, "; ".join(check["errors"])])
		return ERR_FILE_CORRUPT
	var bak := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var e1 := DirAccess.rename_absolute(path, bak)
		if e1 != OK:
			return e1
	return DirAccess.rename_absolute(tmp, path)


static func delete_file(path: String) -> void:
	for x in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(x):
			DirAccess.remove_absolute(x)
