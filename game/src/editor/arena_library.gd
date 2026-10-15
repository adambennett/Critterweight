class_name ArenaLibrary
## Where arena layouts live and how a match finds them:
##   * shipped content  — Content arenas (base arenas, examples "layout_*", mod arenas)
##   * saved layouts    — <user>/arenas/<slug>.arena.json (Saves envelope, kind "arena_layout")
##   * imported packages — same folder after ArenaPackage.import_package installs them
## Saved and imported layouts are also registered into Content as runtime entries (ids always
## "user:<slug>", package "user"), so every match setup screen lists them next to core and mod
## arenas; Content.reload() re-registers them (register_all) like the user's rules presets.
## resolve(id) is how App/match setup turns an arena id into an ArenaDef (content first, then the
## user's layouts on disk), so authored arenas are playable in normal matches. Versioned with
## migration from format 1 (legacy shape layouts).

const KIND := "arena_layout"
const VERSION := 2
const EXT := ".arena.json"
const PREFIX := "user:"
const LEGACY_BASE := {"octagon": "gullet", "square": "crusher", "circle": "gullet", "platform": "rooftop"}


static func dir() -> String:
	return Paths.dir("arenas")


## Content id of a saved/imported layout: always "user:"-namespaced, so a user file can never
## replace a core or mod arena.
static func content_id(id: String) -> String:
	if id.begins_with(PREFIX):
		return id
	return PREFIX + ArenaEditModel.slug_id(id.replace(":", "_"))


## Registers every saved layout in the user arenas folder into Content (called by
## Content.reload() after packages and rules presets).
static func register_all() -> void:
	var d := dir()
	var da := DirAccess.open(d)
	if da == null:
		return
	for f in da.get_files():
		if f.ends_with(EXT):
			var r := load_layout(d.path_join(f))
			if bool(r["ok"]):
				_register(r["data"])


static func _register(data: Dictionary) -> void:
	var e := data.duplicate(true)
	e["id"] = content_id(str(e.get("id", "layout")))
	Content.register_runtime("arenas", e, "user")


## Moves a saved layout to arenas/.removed (nothing is destroyed) and unregisters it.
static func delete_layout(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var r := load_layout(path)
	var bin := path.get_base_dir().path_join(".removed")
	DirAccess.make_dir_recursive_absolute(bin)
	var dst := bin.path_join("%d_%s" % [int(Time.get_unix_time_from_system()), path.get_file()])
	if DirAccess.rename_absolute(path, dst) != OK:
		return false
	for ext in [".bak", ".tmp"]:
		if FileAccess.file_exists(path + ext):
			DirAccess.remove_absolute(path + ext)
	if bool(r["ok"]):
		var cid := content_id(str((r["data"] as Dictionary).get("id", "")))
		if Content.origin_of("arenas", cid) == "user":
			Content.unregister_runtime("arenas", cid)
	return true


static func path_for(id: String, in_dir := "") -> String:
	var d := in_dir if in_dir != "" else dir()
	return d.path_join(ArenaEditModel.slug_id(id.trim_prefix("user:")) + EXT)


## Saves a format-2 layout dictionary (schema-checked first). Returns {ok, path, error}.
static func save_layout(data: Dictionary, path := "", in_dir := "") -> Dictionary:
	var clean := data.duplicate(true)
	_strip_uids(clean)
	var errs := Schema.validate_named(clean, "arena")
	if not errs.is_empty():
		return {"ok": false, "path": "", "error": "; ".join(errs)}
	var p := path if path != "" else path_for(str(clean.get("id", "layout")), in_dir)
	var err := Saves.write_json(p, KIND, VERSION, clean)
	if err != OK:
		return {"ok": false, "path": p, "error": error_string(err)}
	if p.get_base_dir().simplify_path() == dir().simplify_path():
		_register(clean)     # the user's own folder: offer it in match setup right away
	return {"ok": true, "path": p, "error": ""}


static func _strip_uids(d: Dictionary) -> void:
	for p in d.get("props", []):
		if typeof(p) == TYPE_DICTIONARY:
			(p as Dictionary).erase("uid")
	var mk = d.get("markers", {})
	if typeof(mk) == TYPE_DICTIONARY:
		for k in mk:
			for me in mk[k]:
				if typeof(me) == TYPE_DICTIONARY:
					(me as Dictionary).erase("uid")


## Loads a saved layout. Returns {ok, data, error, migrated, recovered_from}.
static func load_layout(path: String) -> Dictionary:
	var r := Saves.read_json(path, KIND, VERSION, ArenaLibrary.migrate)
	if not bool(r["ok"]):
		return {"ok": false, "data": {}, "error": str(r["error"]), "migrated": false}
	var data = r["data"]
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "error": "layout is not an object", "migrated": false}
	var errs := Schema.validate_named(data, "arena")
	if not errs.is_empty():
		return {"ok": false, "data": {}, "error": "; ".join(errs), "migrated": bool(r["migrated"])}
	return {"ok": true, "data": data, "error": "", "migrated": bool(r["migrated"]), "recovered_from": r.get("recovered_from", "")}


## Format 1 (shape bases, spawns array) -> format 2 (base id, spawn markers).
static func migrate(data, from_version: int):
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = (data as Dictionary).duplicate(true)
	if from_version <= 1:
		var shape := str(d.get("base", "octagon"))
		if LEGACY_BASE.has(shape):
			var b := str(LEGACY_BASE[shape])
			d["base"] = b
			var bd := ArenaCatalog.base(b)
			var r := float(d.get("radius", 5.0))
			if not bd.is_empty():
				d["size"] = [r * 2.0, r * 2.0]
				d["variant"] = str(bd["default_variant"])
		var mk: Dictionary = d.get("markers", {}) if typeof(d.get("markers", {})) == TYPE_DICTIONARY else {}
		var sp: Array = mk.get("spawn", [])
		for s in d.get("spawns", []):
			if typeof(s) == TYPE_ARRAY and (s as Array).size() >= 2:
				sp.append({"pos": [float(s[0]), 0.0, float(s[1])], "yaw": float(s[2]) if (s as Array).size() > 2 else 0.0, "team": -1})
		if not sp.is_empty():
			mk["spawn"] = sp
		d["markers"] = mk
		d.erase("spawns")
		d.erase("radius")
		d.erase("wall_height")
		d.erase("ringout")
		d.erase("theme")
		d["format"] = 2
		if not d.has("modes"):
			d["modes"] = ["duel", "ffa"]
	return d


## Saved layouts on disk: [{path, id, name, base, modified}] newest first.
static func list_saved(in_dir := "") -> Array:
	var d := in_dir if in_dir != "" else dir()
	var out := []
	var da := DirAccess.open(d)
	if da == null:
		return out
	for f in da.get_files():
		if not f.ends_with(EXT):
			continue
		var p := d.path_join(f)
		var r := load_layout(p)
		if not bool(r["ok"]):
			out.append({"path": p, "id": "", "name": f.get_basename(), "base": "?", "modified": FileAccess.get_modified_time(p), "error": r["error"]})
			continue
		var data: Dictionary = r["data"]
		out.append({"path": p, "id": str(data.get("id", "")), "name": str(data.get("name", "")), "base": str(data.get("base", "")),
			"modified": FileAccess.get_modified_time(p)})
	out.sort_custom(func(a, b): return int(a["modified"]) > int(b["modified"]))
	return out


## Shipped example layouts (ARENAS.md §4): [{id, name, base}].
static func examples() -> Array:
	var out := []
	for id in Content.ids("arenas"):
		var e := Content.get_entry("arenas", id)
		if bool(e.get("example", false)) or str(id).begins_with("layout_"):
			out.append({"id": id, "name": str(e.get("name", id)), "base": str(e.get("base", ""))})
	return out


## The base arenas themselves: [{id, name, base}].
static func base_arenas() -> Array:
	var out := []
	for b in ArenaCatalog.base_ids():
		var aid := ArenaCatalog.base_arena_id(b)
		if aid != "":
			out.append({"id": aid, "name": str(Content.get_entry("arenas", aid).get("name", aid)), "base": b})
	return out


## Arena by id for matches: content first, then saved/imported user layouts.
static func resolve(id: String, in_dir := "") -> ArenaDef:
	var a := Content.arena(id)
	if a != null:
		return a
	var p := path_for(id, in_dir)
	if FileAccess.file_exists(p):
		var r := load_layout(p)
		if bool(r["ok"]):
			return ArenaDef.from_dict(r["data"], "user")
	for e in list_saved(in_dir):
		if str(e.get("id", "")) == id:
			var r2 := load_layout(str(e["path"]))
			if bool(r2["ok"]):
				return ArenaDef.from_dict(r2["data"], "user")
	return null


## Everything a match setup screen can offer: [{id, name, base, source: core|mod|user}].
static func playable_arenas(in_dir := "") -> Array:
	var out := []
	var seen := {}
	for id in Content.ids("arenas"):
		var e := Content.get_entry("arenas", id)
		var pk := str(e.get("_package", "core"))
		out.append({"id": id, "name": str(e.get("name", id)), "base": str(e.get("base", "")),
			"source": "core" if pk == "core" else ("user" if pk == "user" else "mod")})
		seen[id] = true
	for s in list_saved(in_dir):
		var sid := str(s.get("id", ""))
		if sid != "" and not seen.has(sid) and not seen.has(content_id(sid)):
			out.append({"id": sid, "name": s["name"], "base": s["base"], "source": "user"})
	return out
