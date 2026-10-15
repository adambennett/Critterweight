extends Node
## Autoload "Content": the registry of all game content, loaded from content packages in a
## deterministic order (core first, then enabled mods sorted by dependencies/load_after/id).
## Every JSON file in a package's kind folder is an object with "id" or an {"items": [...]} list.
##
## Kinds (folder names): creatures, arenas, rules, modes, supplements, techniques, meta_upgrades,
## events, encounters, bosses, minions, playlists, announcer, hub, props, ladder, tutorial.
## Singletons (package root): elements.json, tuning.json.
## Ids: core uses bare ids; mod ids must be "<modid>:<name>" unless "override": true (MOD-02).
## Creature-bearing entries may `"extends": "<creature id>"` and give only what changes: objects
## merge recursively, arrays and scalars replace, and `null` removes a key (e.g. a move slot).
## Mod asset paths (art.model, textures, sounds) are relative to the package folder.

signal reloaded()

const KINDS := ["creatures", "arenas", "rules", "modes", "supplements", "techniques", "meta_upgrades",
	"events", "encounters", "bosses", "boss_fights", "minions", "playlists", "announcer", "hub", "props", "ladder", "tutorial", "policies",
	"achievements"]
## Kinds that change simulation outcomes and therefore the multiplayer content hash.
const GAMEPLAY_KINDS := ["creatures", "rules", "modes", "supplements", "techniques", "events", "encounters",
	"bosses", "boss_fights", "minions", "props", "ladder", "arenas"]
const SCHEMA_FOR := {"creatures": "creature", "minions": "creature", "bosses": "creature", "arenas": "arena", "rules": "rules", "playlists": "playlist"}
const CREATURE_KINDS := ["creatures", "minions", "bosses"]

var packages: Array = []          ## [{id, version, path, source:"core"|"mod", manifest}]
var tables := {}                  ## kind -> {id -> Dictionary}
var origins := {}                 ## "kind/id" -> package id
var creatures := {}               ## id -> CreatureDef (parsed lazily)
var arenas := {}                  ## id -> ArenaDef
var errors: PackedStringArray = PackedStringArray()
var _hash := ""
var _gameplay_bytes := PackedByteArray()


func _ready() -> void:
	reload([])


## mod_packages: [{id, version, path, manifest}] in load order (from Mods). Core is always first.
func reload(mod_packages: Array) -> void:
	packages.clear()
	tables.clear()
	origins.clear()
	creatures.clear()
	arenas.clear()
	errors.clear()
	_gameplay_bytes = PackedByteArray()
	for k in KINDS:
		tables[k] = {}
	var core_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/manifest.json"))
	packages.append({"id": "core", "version": str(core_manifest.get("version", "1.0.0")) if typeof(core_manifest) == TYPE_DICTIONARY else "1.0.0",
		"path": "res://content/core", "source": "core", "manifest": core_manifest if typeof(core_manifest) == TYPE_DICTIONARY else {}})
	for m in mod_packages:
		var e: Dictionary = m.duplicate()
		e["source"] = "mod"
		packages.append(e)
	for p in packages:
		_load_package(p)
	_resolve_extends()
	_apply_singletons()
	_hash = _gameplay_bytes.hex_encode().sha256_text() if not _gameplay_bytes.is_empty() else "empty"
	_gameplay_bytes = PackedByteArray()
	if not errors.is_empty():
		for e2 in errors:
			Log.w("content", e2)
	# the player's own presets sit on top of packages (never part of the content hash)
	RulePresets.register_all()
	ArenaLibrary.register_all()     # saved/imported arena layouts, ids "user:<slug>"
	reloaded.emit()


func _load_package(p: Dictionary) -> void:
	var base: String = p["path"]
	var pid: String = p["id"]
	for kind in KINDS:
		var dir := base.path_join(kind)
		for f in _list_json(dir):
			var full := dir.path_join(f)
			var text := FileAccess.get_file_as_string(full)
			var json := JSON.new()
			if json.parse(text) != OK:
				errors.append("%s/%s/%s: JSON error at line %d: %s" % [pid, kind, f, json.get_error_line(), json.get_error_message()])
				continue
			var items: Array = []
			if typeof(json.data) == TYPE_DICTIONARY and json.data.has("items"):
				items = json.data["items"]
			elif typeof(json.data) == TYPE_DICTIONARY:
				items = [json.data]
			else:
				errors.append("%s/%s/%s: expected an object or {\"items\": [...]}" % [pid, kind, f])
				continue
			for it in items:
				_add(kind, it, pid, "%s/%s/%s" % [pid, kind, f], base)
			if kind in GAMEPLAY_KINDS:
				_gameplay_bytes.append_array(("%s|%s|" % [pid, f]).to_utf8_buffer())
				_gameplay_bytes.append_array(text.sha256_buffer())
	for single in ["elements.json", "tuning.json"]:
		var sp := base.path_join(single)
		if FileAccess.file_exists(sp):
			var t2 := FileAccess.get_file_as_string(sp)
			var parsed = JSON.parse_string(t2)
			if typeof(parsed) != TYPE_DICTIONARY:
				errors.append("%s/%s: invalid JSON" % [pid, single])
				continue
			tables["_" + single.get_basename()] = parsed if pid == "core" else _merge(tables.get("_" + single.get_basename(), {}), parsed)
			_gameplay_bytes.append_array(t2.sha256_buffer())


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if typeof(out.get(k)) == TYPE_ARRAY and typeof(b[k]) == TYPE_ARRAY:
			out[k] = out[k] + b[k]
		else:
			out[k] = b[k]
	return out


func _add(kind: String, it, pid: String, where: String, base := "") -> void:
	if typeof(it) != TYPE_DICTIONARY or str(it.get("id", "")) == "":
		errors.append("%s: entry without an 'id'" % where)
		return
	var id := str(it["id"])
	if pid != "core" and not id.begins_with(pid + ":") and not bool(it.get("override", false)):
		errors.append("%s: mod ids must start with '%s:' (got '%s'); set \"override\": true to replace a core entry deliberately" % [where, pid, id])
		return
	if pid != "core":
		var bad := _resolve_asset_paths(it, base)
		if bad != "":
			errors.append("%s#%s: asset path '%s' must stay inside the package (relative, no '..')" % [where, id, bad])
			return
	# entries that extend another are validated after the merge (_resolve_extends)
	if SCHEMA_FOR.has(kind) and not (kind in CREATURE_KINDS and it.has("extends")):
		var errs := Schema.validate_named(it, SCHEMA_FOR[kind], "%s#%s" % [where, id])
		if not errs.is_empty():
			for e in errs:
				errors.append(e)
			return
	var key := "%s/%s" % [kind, id]
	if tables[kind].has(id) and not bool(it.get("override", false)):
		errors.append("%s: duplicate id '%s' (already defined by %s)" % [where, id, origins.get(key, "?")])
		return
	var copy: Dictionary = it.duplicate(true)
	copy["_package"] = pid
	copy["_file"] = where
	tables[kind][id] = copy
	origins[key] = pid


const ASSET_EXTS := ["png", "jpg", "jpeg", "webp", "glb", "ogg", "wav"]


## Rewrites relative asset paths in a mod entry to absolute package paths. Returns the first
## offending path ("" when all are fine). res:// paths (core assets) are allowed as-is.
func _resolve_asset_paths(it: Dictionary, base: String) -> String:
	for key in ["art", "audio"]:
		var d = it.get(key)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		for k in d.keys():
			var v = d[k]
			if typeof(v) != TYPE_STRING or not str(v).get_extension().to_lower() in ASSET_EXTS:
				continue
			var sv := str(v)
			if sv.begins_with("res://"):
				continue
			if sv.is_absolute_path() or sv.contains("..") or sv.contains(":") or sv.begins_with("/") or sv.contains("\\"):
				return sv
			d[k] = base.path_join(sv)
	return ""


## Deep merge used by "extends": dictionaries merge, everything else replaces, null deletes.
static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		var v = over[k]
		if v == null:
			out.erase(k)
		elif typeof(v) == TYPE_DICTIONARY and typeof(out.get(k)) == TYPE_DICTIONARY:
			out[k] = deep_merge(out[k], v)
		elif typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
			out[k] = v.duplicate(true)
		else:
			out[k] = v
	return out


func _resolve_extends() -> void:
	for kind in CREATURE_KINDS:
		for id in tables[kind].keys():
			var d: Dictionary = tables[kind][id]
			if not d.has("extends"):
				continue
			var chain := [id]
			var merged := d
			var ok := true
			while merged.has("extends"):
				var parent_id := str(merged["extends"])
				if parent_id in chain or chain.size() > 4:
					errors.append("%s: 'extends' chain %s is circular or deeper than 4" % [d.get("_file", id), " -> ".join(chain + [parent_id])])
					ok = false
					break
				var parent := creature_entry(parent_id)
				if parent.is_empty():
					errors.append("%s: extends unknown creature '%s'" % [d.get("_file", id), parent_id])
					ok = false
					break
				chain.append(parent_id)
				var own := merged.duplicate(true)
				own.erase("extends")
				var p2: Dictionary = parent.duplicate(true)
				for meta in ["id", "_package", "_file", "override", "npc_only", "_extends"]:
					p2.erase(meta)
				merged = deep_merge(p2, own)
			if not ok:
				tables[kind].erase(id)
				continue
			merged["_extends"] = chain.slice(1)
			var errs := Schema.validate_named(merged, SCHEMA_FOR[kind], "%s#%s" % [d.get("_file", id), id])
			if not errs.is_empty():
				for e in errs:
					errors.append(e)
				tables[kind].erase(id)
				continue
			tables[kind][id] = merged


func _list_json(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out


func _apply_singletons() -> void:
	if tables.has("_elements"):
		for e in Elements.load_from(tables["_elements"]):
			errors.append("elements: " + e)
	if tables.has("_tuning"):
		var unknown := Tuning.apply_overrides(tables["_tuning"])
		for u in unknown:
			errors.append("tuning.json: unknown key '%s'" % u)


func get_entry(kind: String, id: String) -> Dictionary:
	return tables.get(kind, {}).get(id, {})


func ids(kind: String) -> Array:
	var out: Array = tables.get(kind, {}).keys()
	out.sort()
	return out


## Raw creature dictionary from any creature-bearing kind (fighters, minions, bosses).
func creature_entry(id: String) -> Dictionary:
	for k in CREATURE_KINDS:
		var d := get_entry(k, id)
		if not d.is_empty():
			return d
	return {}


func creature(id: String) -> CreatureDef:
	if creatures.has(id):
		return creatures[id]
	var d := creature_entry(id)
	if d.is_empty():
		return null
	var c := CreatureDef.from_dict(d, Callable(), str(d.get("_package", "")))
	if not c.is_valid():
		for e in c.errors:
			errors.append("%s: %s" % [d.get("_file", id), e])
	creatures[id] = c
	return c


## A resized variant of a creature (e.g. the Absolute Unit): every body dimension and authored
## move target is scaled by `scale`, masses by `weight_mult`. Cached per (id, scale, weight).
func scaled_creature(id: String, scale: float, weight_mult := 1.0) -> CreatureDef:
	var key := "%s@x%.2f_w%.2f" % [id, scale, weight_mult]
	if creatures.has(key):
		return creatures[key]
	var d := creature_entry(id)
	if d.is_empty():
		return null
	var c2: Dictionary = d.duplicate(true)
	var body = c2.get("body")
	if typeof(body) == TYPE_DICTIONARY:
		body["scale"] = float(body.get("scale", 1.0)) * scale
	var st: Dictionary = c2.get("stats", {})
	st["weight"] = float(st.get("weight", 1.0)) * weight_mult
	c2["stats"] = st
	var c := CreatureDef.from_dict(c2, Callable(), str(d.get("_package", "")))
	creatures[key] = c
	return c


func playable_creatures() -> Array:
	var out := []
	for id in ids("creatures"):
		var d := get_entry("creatures", id)
		if not bool(d.get("npc_only", false)):
			out.append(id)
	return out


func arena(id: String) -> ArenaDef:
	if arenas.has(id):
		return arenas[id]
	var d := get_entry("arenas", id)
	if d.is_empty():
		return null
	var a := ArenaDef.from_dict(d, str(d.get("_package", "")))
	arenas[id] = a
	return a


## Hash of all gameplay-affecting content from every loaded package (multiplayer compatibility).
func content_hash() -> String:
	return _hash


## Short manifest list for handshakes: [{id, version, hash, client_only}] of loaded packages.
func package_list() -> Array:
	var out := []
	for p in packages:
		var man: Dictionary = p.get("manifest", {}) if typeof(p.get("manifest")) == TYPE_DICTIONARY else {}
		out.append({"id": p["id"], "version": p["version"], "hash": str(p.get("hash", "")),
			"client_only": bool(man.get("client_only", false))})
	return out


## Adds an entry that does not come from a package on disk (user rules presets, user arenas).
## Runtime entries are cleared by reload(); their owners re-register on `reloaded`. They are not
## part of the gameplay content hash (multiplayer hosts send such entries in full).
func register_runtime(kind: String, entry: Dictionary, pid := "user") -> void:
	if not tables.has(kind) or str(entry.get("id", "")) == "":
		return
	var copy := entry.duplicate(true)
	copy["_package"] = pid
	copy["_file"] = "%s/%s/%s" % [pid, kind, str(entry["id"])]
	tables[kind][str(entry["id"])] = copy
	origins["%s/%s" % [kind, str(entry["id"])]] = pid
	if kind == "arenas":
		arenas.erase(str(entry["id"]))
	if kind in CREATURE_KINDS:
		creatures.erase(str(entry["id"]))


func unregister_runtime(kind: String, id: String) -> void:
	if tables.has(kind):
		tables[kind].erase(id)
	origins.erase("%s/%s" % [kind, id])
	arenas.erase(id)
	creatures.erase(id)


## Package id that defined an entry ("core" or a mod id), or "".
func origin_of(kind: String, id: String) -> String:
	return str(origins.get("%s/%s" % [kind, id], ""))
