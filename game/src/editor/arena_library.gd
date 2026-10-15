class_name ArenaLibrary
## Where arena layouts live and how a match finds them:
##   * shipped content  — Content arenas (base arenas, examples "layout_*", mod arenas)
##   * saved layouts    — <user>/arenas/<slug>.arena.json (Saves envelope, kind "arena_layout")
##   * imported packages — same folder after ArenaPackage.import_package installs them
## resolve(id) is how App/match setup turns an arena id into an ArenaDef (content first, then the
## user's layouts), so authored arenas are playable in normal matches. Versioned with migration
## from format 1 (legacy shape layouts).

const KIND := "arena_layout"
const VERSION := 2
const EXT := ".arena.json"
const LEGACY_BASE := {"octagon": "gullet", "square": "crusher", "circle": "gullet", "platform": "rooftop"}


static func dir() -> String:
	return Paths.dir("arenas")


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
	for id in Content.ids("arenas"):
		var e := Content.get_entry("arenas", id)
		out.append({"id": id, "name": str(e.get("name", id)), "base": str(e.get("base", "")), "source": "core" if str(e.get("_package", "core")) == "core" else "mod"})
	for s in list_saved(in_dir):
		if str(s.get("id", "")) != "":
			out.append({"id": s["id"], "name": s["name"], "base": s["base"], "source": "user"})
	return out
