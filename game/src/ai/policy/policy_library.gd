class_name PolicyLibrary
extends RefCounted
## Registry of saved AI policies (static API, no autoload needed):
##  * built-in / mod policies: content packages' `policies/*.json` (read-only, via Content)
##  * user policies: `<user data>/policies/*.policy.json` (save, rename, export, import, delete)
##
## Lookup API for match setup, hosts and dedicated servers (docs/AI_LAB.md "Using policies"):
##   var p := PolicyLibrary.get_policy(id)            # PolicyData or null (see last_error(id))
##   var why := PolicyLibrary.compatibility(p, creature_id)   # "" when usable for that fighter
##   var src := PolicyInputSource.create(p, seed)    # an InputSource for MatchSim
## (`get` itself is reserved by Godot's Object, hence `get_policy`.)
## Loading a policy never executes code: files are JSON + base64 floats, strictly validated.

const MAX_USER_POLICIES := 500

static var user_dir_override := ""
static var _cache := {}          ## id -> {"policy": PolicyData, "mtime": int, "path": String}
static var _errors := {}         ## id -> last load error


static func user_dir() -> String:
	if user_dir_override != "":
		if not DirAccess.dir_exists_absolute(user_dir_override):
			DirAccess.make_dir_recursive_absolute(user_dir_override)
		return user_dir_override
	var paths := _autoload("Paths")
	if paths != null:
		return str(paths.call("dir", "policies"))
	return OS.get_user_data_dir().path_join("policies")


static func _autoload(n: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(n)


static func path_for(id: String) -> String:
	return user_dir().path_join(file_stem(id) + PolicyIO.EXT)


## File-system-safe stem for an id (anything but letters, digits, '_', '-', '.' becomes '_').
static func file_stem(id: String) -> String:
	var out := ""
	for ch in id.substr(0, 96):
		var ok := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in ["_", "-", "."]
		out += ch if ok else "_"
	return out if out != "" and out != "." and out != ".." else "policy"


## A new unique id for a user policy of `creature`.
static func new_id(creature_id: String) -> String:
	var base := "u_%s_%s" % [creature_id.replace(":", "_"), String.num_int64(int(Time.get_unix_time_from_system()), 36)]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var id := "%s%03d" % [base, rng.randi_range(0, 999)]
	while FileAccess.file_exists(path_for(id)) or _builtin_entry(id).size() > 0:
		id = "%s%03d" % [base, rng.randi_range(0, 999)]
	return id


static func _builtin_entry(id: String) -> Dictionary:
	var content := _autoload("Content")
	if content == null:
		return {}
	return content.call("get_entry", "policies", id)


static func _builtin_ids() -> Array:
	var content := _autoload("Content")
	if content == null:
		return []
	return content.call("ids", "policies")


## Summaries of every known policy (optionally only one creature's), built-ins first.
## Invalid files are listed too, with `valid = false` and the reason, so the UI can show them.
static func list(creature_id := "") -> Array:
	var out := []
	for id in _builtin_ids():
		var p := get_policy(str(id))
		if p == null:
			out.append({"id": id, "name": id, "valid": false, "error": last_error(str(id)), "source": "core", "creature": ""})
			continue
		if creature_id != "" and p.creature != creature_id:
			continue
		var s := p.summary()
		s["valid"] = true
		s["error"] = ""
		out.append(s)
	var d := DirAccess.open(user_dir())
	if d != null:
		var files := Array(d.get_files())
		files.sort()
		for fn in files:
			var fname := str(fn)
			if not fname.ends_with(PolicyIO.EXT):
				continue
			var path := user_dir().path_join(fname)
			var r := _load_path(path)
			if not r["ok"]:
				out.append({"id": fname.trim_suffix(PolicyIO.EXT), "name": fname, "valid": false, "error": "; ".join(r["errors"]),
					"source": "user", "path": path, "creature": ""})
				continue
			var pol: PolicyData = r["policy"]
			if creature_id != "" and pol.creature != creature_id:
				continue
			var s2 := pol.summary()
			s2["valid"] = true
			s2["error"] = ""
			s2["warnings"] = "; ".join(r["warnings"])
			out.append(s2)
	return out


static func _load_path(path: String) -> Dictionary:
	var mtime := FileAccess.get_modified_time(path)
	for id in _cache:
		var c: Dictionary = _cache[id]
		if str(c["path"]) == path and int(c["mtime"]) == mtime:
			return {"ok": true, "policy": c["policy"], "errors": PackedStringArray(), "warnings": c.get("warnings", PackedStringArray())}
	var r := PolicyIO.read_file(path)
	if r["ok"]:
		var p: PolicyData = r["policy"]
		p.source = "user"
		_cache[p.id] = {"policy": p, "mtime": mtime, "path": path, "warnings": r["warnings"]}
	return r


## The policy with this id (built-in, mod or user), validated; null if missing or invalid.
static func get_policy(id: String) -> PolicyData:
	if id == "":
		_errors[id] = "no policy id given"
		return null
	if _cache.has(id):
		var c: Dictionary = _cache[id]
		if str(c["path"]) == "" or (FileAccess.file_exists(str(c["path"])) and FileAccess.get_modified_time(str(c["path"])) == int(c["mtime"])):
			return c["policy"]
		_cache.erase(id)
	var entry := _builtin_entry(id)
	if not entry.is_empty():
		var r := PolicyData.from_dict(entry)
		if not r["ok"]:
			_errors[id] = "; ".join(r["errors"])
			return null
		var p: PolicyData = r["policy"]
		p.source = str(entry.get("_package", "core"))
		p.path = str(entry.get("_file", ""))
		_cache[id] = {"policy": p, "mtime": 0, "path": ""}
		return p
	var path := path_for(id)
	if not FileAccess.file_exists(path):
		# ids are slugged into file names; fall back to scanning in case a file was renamed
		var d := DirAccess.open(user_dir())
		if d != null:
			for fn in d.get_files():
				if str(fn).ends_with(PolicyIO.EXT):
					var r2 := _load_path(user_dir().path_join(str(fn)))
					if r2["ok"] and (r2["policy"] as PolicyData).id == id:
						return r2["policy"]
		_errors[id] = "no policy with id '%s'" % id
		return null
	var r3 := _load_path(path)
	if not r3["ok"]:
		_errors[id] = "; ".join(r3["errors"])
		return null
	var pol: PolicyData = r3["policy"]
	if pol.id != id:
		_errors[id] = "file %s holds policy '%s', not '%s'" % [path.get_file(), pol.id, id]
		return null
	return pol


static func last_error(id: String) -> String:
	return str(_errors.get(id, ""))


## "" if `p` can drive `creature_id` in this build, else the reason.
static func compatibility(p: PolicyData, creature_id: String) -> String:
	if p == null:
		return "policy missing"
	if creature_id != "" and p.creature != creature_id:
		return "trained for '%s', not '%s'" % [p.creature, creature_id]
	var content := _autoload("Content")
	if content != null and content.call("creature", p.creature) == null:
		return "unknown creature '%s' (missing content or mod)" % p.creature
	return ""


## Non-fatal notes (e.g. the fighter's definition changed since training).
static func warnings_for(p: PolicyData) -> PackedStringArray:
	var w := PackedStringArray()
	if p == null:
		return w
	var sig := PolicyData.creature_signature_of(p.creature)
	if p.creature_signature != "" and sig != "" and sig != p.creature_signature:
		w.append("%s has changed since this policy was trained; it still works but may play worse" % p.creature)
	return w


static func is_builtin(id: String) -> bool:
	return not _builtin_entry(id).is_empty()


## Saves (creates or replaces) a user policy. Built-in ids cannot be overwritten.
static func save(p: PolicyData) -> Error:
	if p.id == "":
		p.id = new_id(p.creature)
	if is_builtin(p.id):
		return ERR_ALREADY_EXISTS
	var count := 0
	var d := DirAccess.open(user_dir())
	if d != null:
		for fn in d.get_files():
			if str(fn).ends_with(PolicyIO.EXT):
				count += 1
	var path := path_for(p.id)
	if count >= MAX_USER_POLICIES and not FileAccess.file_exists(path):
		return ERR_OUT_OF_MEMORY
	if p.created == "":
		p.created = PolicyData.now_iso()
	p.updated = PolicyData.now_iso()
	var err := PolicyIO.write_file(path, p)
	if err == OK:
		p.source = "user"
		p.path = path
		_cache[p.id] = {"policy": p, "mtime": FileAccess.get_modified_time(path), "path": path}
		_errors.erase(p.id)
	return err


static func rename(id: String, new_name: String) -> Error:
	var p := get_policy(id)
	if p == null or p.source != "user":
		return ERR_UNAVAILABLE
	var n := new_name.strip_edges().strip_escapes().substr(0, 64)
	if n == "":
		return ERR_INVALID_PARAMETER
	p.name = n
	return save(p)


## Removes a user policy (and its backups). Built-in policies cannot be deleted.
static func delete(id: String) -> Error:
	var p := get_policy(id)
	if p == null or p.source != "user":
		return ERR_UNAVAILABLE
	PolicyIO.delete_file(p.path)
	_cache.erase(id)
	return OK


## Writes a copy to any path (".policy.json" appended when missing).
static func export_to(id: String, dest: String) -> Error:
	var p := get_policy(id)
	if p == null:
		return ERR_DOES_NOT_EXIST
	var path := dest.strip_edges()
	if path == "":
		return ERR_INVALID_PARAMETER
	if not path.ends_with(PolicyIO.EXT):
		path += PolicyIO.EXT
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(PolicyIO.to_text(p))
	f.close()
	return OK


## Validates and copies an external policy file into the user library.
## {ok, id, errors: PackedStringArray, warnings: PackedStringArray}
static func import_from(src: String) -> Dictionary:
	var r := PolicyIO.read_one(src.strip_edges())
	var errors: PackedStringArray = PackedStringArray(r["errors"])
	var warnings: PackedStringArray = PackedStringArray(r["warnings"])
	var out := {"ok": false, "id": "", "errors": errors, "warnings": warnings}
	if not r["ok"]:
		return out
	var p: PolicyData = r["policy"]
	var why := compatibility(p, "")
	if why != "":
		errors.append(why)
		out["errors"] = errors
		return out
	if is_builtin(p.id) or FileAccess.file_exists(path_for(p.id)):
		var old := p.id
		p.id = new_id(p.creature)
		warnings.append("id '%s' already exists; imported as '%s'" % [old, p.id])
	warnings.append_array(warnings_for(p))
	out["warnings"] = warnings
	var err := save(p)
	if err != OK:
		errors.append("could not save into the library: %s" % error_string(err))
		out["errors"] = errors
		return out
	out["ok"] = true
	out["id"] = p.id
	return out


static func clear_cache() -> void:
	_cache.clear()
	_errors.clear()
