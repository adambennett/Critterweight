class_name ArenaEditModel
extends RefCounted
## Editable arena layout (the arena editor's document). Props and markers are one ordered list of
## items with stable uids so selection, undo/redo and validation errors can point at them:
##   item = {uid, kind: "prop"|"marker", type: catalog id, pos: Vector3, yaw: radians,
##           team: int (markers, -1 = none), pos2: Vector3 (drain pairs), params: {}, scale: 1.0}
## Layout fields mirror the format-2 arena JSON (docs/ARENAS_AND_EDITOR.md). Mutate only through
## the command stack (ArenaEditCommands) so every change is undoable.

signal changed(what: String)

const FIELDS := ["id", "name", "author", "description", "base", "variant", "size", "modes", "flags", "removed_builtins", "version"]

var id := "user:new_layout"
var name := "New Layout"
var author := ""
var description := ""
var base := "gullet"
var variant := ""
var size := Vector2(12, 12)
var modes: Array = ["duel", "ffa", "teams"]
var flags := {}
var removed_builtins: Array = []
var version := 1
var items: Array = []
var _next_uid := 1


static func slug_id(s: String) -> String:
	var out := ""
	for ch in s.to_lower().strip_edges():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif out != "" and not out.ends_with("_"):
			out += "_"
	out = out.trim_suffix("_").substr(0, 40)
	return out if out != "" else "layout"


## A fresh layout on a base, starting from the base arena's markers (spawns, clusters, boss...).
static func new_from_base(base_id: String, variant_id := "") -> ArenaEditModel:
	var src := ArenaCatalog.editor_template(base_id)
	var aid := ArenaCatalog.base_arena_id(base_id)
	if aid != "":
		src = Content.get_entry("arenas", aid).duplicate(true)
	if src.is_empty():
		src = {"base": base_id, "markers": {}}
	src.erase("base_def")
	src.erase("_package")
	src.erase("_file")
	src["props"] = []
	src["id"] = "user:new_" + base_id
	src["name"] = "New %s Layout" % str(ArenaCatalog.base(base_id).get("name", base_id.capitalize())).trim_prefix("The ")
	src["author"] = ""
	src["removed_builtins"] = []
	src["flags"] = {}
	if variant_id != "":
		src["variant"] = variant_id
	return from_dict(src)


static func from_dict(d: Dictionary) -> ArenaEditModel:
	var m := ArenaEditModel.new()
	m.load_dict(d)
	return m


func load_dict(d: Dictionary) -> void:
	var a := ArenaDef.from_dict(d)
	id = str(d.get("id", "user:layout"))
	name = str(d.get("name", id))
	author = str(d.get("author", ""))
	description = str(d.get("description", ""))
	base = a.base
	variant = a.variant
	size = a.size
	modes = a.modes.duplicate()
	flags = a.flags.duplicate(true)
	removed_builtins = a.removed_builtins.duplicate()
	version = int(d.get("version", 1))
	items.clear()
	_next_uid = 1
	for p in a.props:
		var it := {"kind": "prop", "type": str(p["type"]), "pos": p["pos"], "yaw": float(p["yaw"]), "team": -1,
			"params": (p.get("params", {}) as Dictionary).duplicate(true), "scale": float(p.get("scale", 1.0))}
		if p.has("pos2"):
			it["pos2"] = p["pos2"]
		_add_raw(it)
	for name_ in a.marker_entries:
		for me in a.marker_entries[name_]:
			_add_raw({"kind": "marker", "type": ArenaCatalog.marker_type(str(name_)), "pos": me["pos"], "yaw": float(me["yaw"]),
				"team": int(me["team"]), "params": {}, "scale": 1.0, "size": me.get("size", Vector3.ZERO)})
	changed.emit("load")


func _add_raw(it: Dictionary) -> int:
	it["uid"] = _next_uid
	_next_uid += 1
	items.append(it)
	return int(it["uid"])


func new_uid() -> int:
	_next_uid += 1
	return _next_uid - 1


## Format-2 arena dictionary. include_uids keeps editor uids on props/markers (for validation refs).
func to_dict(include_uids := false) -> Dictionary:
	var props := []
	var mk := {}
	for it in items:
		if str(it["kind"]) == "marker":
			var mname := ArenaCatalog.marker_name(str(it["type"]))
			var me := {"pos": it["pos"], "yaw": float(it["yaw"]), "team": int(it.get("team", -1)), "size": it.get("size", Vector3.ZERO)}
			var mj := ArenaDef.marker_to_json(me)
			if include_uids:
				mj["uid"] = int(it["uid"])
			if not mk.has(mname):
				mk[mname] = []
			mk[mname].append(mj)
		else:
			var pj := ArenaDef.prop_to_json(it)
			if include_uids:
				pj["uid"] = int(it["uid"])
			props.append(pj)
	var out := {"id": id, "name": name, "base": base, "variant": variant, "format": ArenaDef.FORMAT, "version": version,
		"author": author, "size": [ArenaDef.r2(size.x), ArenaDef.r2(size.y)], "modes": modes.duplicate(),
		"flags": flags.duplicate(true), "removed_builtins": removed_builtins.duplicate(), "props": props, "markers": mk}
	if description != "":
		out["description"] = description
	return out


func to_arena(include_uids := true) -> ArenaDef:
	return ArenaDef.from_dict(to_dict(include_uids))


func index_of(uid: int) -> int:
	for i in items.size():
		if int(items[i]["uid"]) == uid:
			return i
	return -1


func get_item(uid: int) -> Dictionary:
	var i := index_of(uid)
	return items[i] if i >= 0 else {}


## Low-level mutators (used by commands; they do not record undo history).
func insert_item(it: Dictionary, at := -1) -> void:
	if at < 0 or at > items.size():
		items.append(it)
	else:
		items.insert(at, it)
	_next_uid = maxi(_next_uid, int(it["uid"]) + 1)
	changed.emit("items")


func remove_item(uid: int) -> Dictionary:
	var i := index_of(uid)
	if i < 0:
		return {}
	var it: Dictionary = items[i]
	items.remove_at(i)
	changed.emit("items")
	return it


func replace_item(uid: int, it: Dictionary) -> void:
	var i := index_of(uid)
	if i >= 0:
		var copy := it.duplicate(true)
		copy["uid"] = uid
		items[i] = copy
		changed.emit("items")


func get_field(key: String):
	return get(key)


func set_field(key: String, value) -> void:
	if not FIELDS.has(key):
		return
	match key:
		"size":
			size = value
		"modes", "removed_builtins":
			set(key, (value as Array).duplicate())
		"flags":
			flags = (value as Dictionary).duplicate(true)
		_:
			set(key, value)
	changed.emit(key)


func snapshot() -> Dictionary:
	var its := []
	for it in items:
		its.append(it.duplicate(true))
	var s := {"items": its, "next_uid": _next_uid}
	for k in FIELDS:
		var v = get(k)
		s[k] = v.duplicate(true) if v is Array or v is Dictionary else v
	return s


func restore(s: Dictionary) -> void:
	for k in FIELDS:
		var v = s.get(k)
		set(k, v.duplicate(true) if v is Array or v is Dictionary else v)
	items.clear()
	for it in s.get("items", []):
		items.append((it as Dictionary).duplicate(true))
	_next_uid = int(s.get("next_uid", items.size() + 1))
	changed.emit("restore")


# =====================================================================================
# Helpers for the editor UI
# =====================================================================================

func base_def() -> Dictionary:
	return ArenaCatalog.base(base)


func count_markers(name_: String, team := -2) -> int:
	var n := 0
	for it in items:
		if str(it["kind"]) == "marker" and ArenaCatalog.marker_name(str(it["type"])) == name_:
			if team == -2 or int(it.get("team", -1)) == team:
				n += 1
	return n


## A placeable default item of catalog type `type_id` at `pos`.
func make_item(type_id: String, pos: Vector3, yaw := 0.0) -> Dictionary:
	var def := ArenaCatalog.prop(type_id)
	var it := {"uid": new_uid(), "kind": "marker" if bool(def.get("is_marker", false)) else "prop", "type": type_id,
		"pos": Vector3(pos.x, 0.0, pos.z), "yaw": yaw, "team": -1, "params": {}, "scale": 1.0}
	if ArenaCatalog.footprint_shape(def) == "pair":
		var sep := float(def["params"].get("separation", 4.0))
		it["pos2"] = Vector3(pos.x + cos(yaw) * sep, 0.0, pos.z - sin(yaw) * sep)
	if bool(def.get("is_marker", false)):
		var ms: Vector3 = def["marker"]["size"]
		if ms.y > 0.0 and str(def["marker"]["name"]) in ["goal", "wave_gate"]:
			it["size"] = Vector3(ms.x, ms.y, ms.z)
	return it
