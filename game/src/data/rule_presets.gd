class_name RulePresets
## The player's own rules presets (MCH-06): saved atomically with versions and checksums in the
## user "presets/rules" folder, registered into Content (ids "user:<slug>") so every menu, host
## screen and playlist sees them next to core and mod presets, plus duplicate / rename / delete
## (moved aside, never destroyed) / export (a plain shareable .rules.json) / import.

const KIND := "rules_preset"
const VERSION := 1
const PREFIX := "user:"
const MAX_IMPORT_BYTES := 256 * 1024


static func dir() -> String:
	return Paths.dir("presets").path_join("rules")


static func _path(id: String) -> String:
	return dir().path_join(id.trim_prefix(PREFIX) + ".json")


static func list() -> Array:
	var out := []
	var d := DirAccess.open(dir())
	if d == null:
		return out
	var files := d.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var r := Saves.read_json(dir().path_join(f), KIND, VERSION, Callable(RulePresets, "_migrate"))
		if r["ok"] and typeof(r["data"]) == TYPE_DICTIONARY:
			var rules: Dictionary = r["data"]
			rules["id"] = PREFIX + f.get_basename()
			out.append(rules)
		elif r["exists"]:
			Log.w("presets", "%s could not be read (%s); it was left untouched" % [f, r["error"]])
	return out


static func _migrate(data, _from_version: int):
	return data


## Registers every user preset into Content (call after each Content.reload()).
static func register_all() -> void:
	for r in list():
		Content.register_runtime("rules", r, "user")


static func is_user(id: String) -> bool:
	return id.begins_with(PREFIX)


static func _unique_id(name_: String) -> String:
	var base := Paths.slug(name_).to_lower().replace(" ", "_").replace(":", "_")
	if base == "" or base == "unnamed":
		base = "rules"
	var id := PREFIX + base
	var n := 2
	while FileAccess.file_exists(_path(id)) or not Content.get_entry("rules", id).is_empty():
		id = "%s%s_%d" % [PREFIX, base, n]
		n += 1
	return id


## Saves (creating or overwriting) a user preset. Returns {ok, id, problems}.
static func save(rules: Dictionary, id := "") -> Dictionary:
	var r := RulesValidator.normalize(rules)
	var problems := RulesValidator.validate(r)
	if RulesValidator.has_errors(problems):
		return {"ok": false, "id": id, "problems": problems}
	if id == "" or not is_user(id):
		id = _unique_id(str(r.get("name", "rules")))
	r["id"] = id
	r["version"] = int(r.get("version", 0)) + 1
	r.erase("_package")
	r.erase("_file")
	var data := r.duplicate(true)
	data.erase("id")
	if Saves.write_json(_path(id), KIND, VERSION, data) != OK:
		return {"ok": false, "id": id, "problems": [{"field": "", "severity": "error", "text": "Could not write the preset file."}]}
	Content.register_runtime("rules", r, "user")
	return {"ok": true, "id": id, "problems": problems}


static func duplicate_preset(id: String) -> Dictionary:
	var src := Content.get_entry("rules", id)
	if src.is_empty():
		return {"ok": false, "id": "", "problems": [{"field": "", "severity": "error", "text": "Unknown preset '%s'." % id}]}
	var copy := src.duplicate(true)
	copy["name"] = ("Copy of %s" % str(src.get("name", id))).substr(0, 40)
	copy.erase("override")
	copy["version"] = 0
	return save(copy, "")


static func rename(id: String, new_name: String) -> Dictionary:
	if not is_user(id):
		return {"ok": false, "id": id, "problems": [{"field": "name", "severity": "error", "text": "Built-in and mod presets can't be renamed; duplicate it first."}]}
	var r := Content.get_entry("rules", id).duplicate(true)
	r["name"] = new_name
	return save(r, id)


## Moves the preset file to presets/rules/.removed (nothing is destroyed).
static func delete(id: String) -> bool:
	if not is_user(id) or not FileAccess.file_exists(_path(id)):
		return false
	var bin := dir().path_join(".removed")
	DirAccess.make_dir_recursive_absolute(bin)
	var dst := bin.path_join("%d_%s" % [int(Time.get_unix_time_from_system()), _path(id).get_file()])
	DirAccess.rename_absolute(_path(id), dst)
	for ext in [".bak", ".tmp"]:
		if FileAccess.file_exists(_path(id) + ext):
			DirAccess.remove_absolute(_path(id) + ext)
	Content.unregister_runtime("rules", id)
	return true


## Writes a shareable plain-JSON copy into `dst_dir` (default: user "packages"). Returns the path.
static func export_preset(id: String, dst_dir := "") -> String:
	var r := Content.get_entry("rules", id).duplicate(true)
	if r.is_empty():
		return ""
	for k in ["_package", "_file", "override"]:
		r.erase(k)
	r["id"] = id.trim_prefix(PREFIX)
	r["format"] = r.get("format", "duel")
	r["critterweight_rules"] = VERSION
	if dst_dir == "":
		dst_dir = Paths.dir("packages")
	DirAccess.make_dir_recursive_absolute(dst_dir)
	var out := dst_dir.path_join("%s.rules.json" % Paths.slug(str(r.get("name", "rules"))).replace(" ", "_"))
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(r, "  "))
	f.close()
	return out


## Reads a text file of at most `max_bytes`, checking the size BEFORE reading anything (a huge
## file is never loaded into memory). Returns {ok, text, error}.
static func read_limited(path: String, max_bytes: int) -> Dictionary:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return {"ok": false, "text": "", "error": "unreadable"}
	var n := fa.get_length()
	if n == 0:
		return {"ok": false, "text": "", "error": "empty"}
	if n > max_bytes:
		return {"ok": false, "text": "", "error": "too large (%d KB, at most %d KB)" % [ceili(n / 1024.0), int(max_bytes / 1024.0)]}
	return {"ok": true, "text": fa.get_buffer(n).get_string_from_utf8(), "error": ""}


## Imports a shared .rules.json (or a saved preset file). Returns {ok, id, problems}.
static func import_preset(path: String) -> Dictionary:
	var rd := read_limited(path, MAX_IMPORT_BYTES)
	if not rd["ok"]:
		return {"ok": false, "id": "", "problems": [{"field": "", "severity": "error", "text": "%s is %s." % [path.get_file(), rd["error"]]}]}
	var text := str(rd["text"])
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "id": "", "problems": [{"field": "", "severity": "error", "text": "%s is not a rules file (invalid JSON)." % path.get_file()}]}
	var d: Dictionary = parsed
	if d.has("data") and d.has("kind"):
		d = d["data"] if typeof(d["data"]) == TYPE_DICTIONARY else {}
	if not d.has("mode"):
		return {"ok": false, "id": "", "problems": [{"field": "mode", "severity": "error", "text": "%s has no 'mode'; it is not a rules preset." % path.get_file()}]}
	d.erase("id")
	d.erase("critterweight_rules")
	d["version"] = 0
	return save(d, "")
