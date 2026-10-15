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
##
## Mod package rules enforced here, at load (docs/MODDING.md, D-016, D-027):
## - Only files the mod manager validated are read (`files` in the package dictionary): folder and
##   file names are exact and lowercase on every platform, links are never followed.
## - Overrides: a bare id with "override": true may replace an existing CORE entry only, and only
##   when the package declares `replaces_core` and the player consented (`consent`). A mod can
##   never replace another mod's or the player's entries; two mods replacing the same core entry
##   is a conflict. Root singletons (tuning.json, elements.json) change core values, so they need
##   the same capability and consent.
## - client_only (presentation) packages load only PRESENTATION_KINDS; gameplay folders and root
##   singletons are reported and skipped, whatever their letter case.
## - Every string in a mod entry's art/audio blocks that names a file must be a relative path to a
##   validated package file with an asset extension; it becomes an absolute package path that
##   is_package_asset() vouches for. Nothing else from a mod is ever handed to a loader.

signal reloaded()

const KINDS := ["creatures", "arenas", "rules", "modes", "supplements", "techniques", "meta_upgrades",
	"events", "encounters", "bosses", "boss_fights", "minions", "playlists", "announcer", "hub", "props", "ladder", "tutorial", "policies",
	"achievements"]
## Kinds that change simulation outcomes and therefore the multiplayer content hash.
const GAMEPLAY_KINDS := ["creatures", "rules", "modes", "supplements", "techniques", "events", "encounters",
	"bosses", "boss_fights", "minions", "props", "ladder", "arenas"]
## The only kinds a presentation-only (client_only) package may contain.
const PRESENTATION_KINDS := ["announcer"]
## Package-root files that merge into global tables.
const SINGLETONS := ["elements.json", "tuning.json"]
const SCHEMA_FOR := {"creatures": "creature", "minions": "creature", "bosses": "creature", "arenas": "arena", "rules": "rules", "playlists": "playlist"}
const CREATURE_KINDS := ["creatures", "minions", "bosses"]
const ASSET_EXTS := ["png", "jpg", "jpeg", "webp", "glb", "ogg", "wav"]
## art/audio keys whose value is always a file, whatever it looks like.
const ASSET_KEYS := ["model"]

var packages: Array = []          ## [{id, version, path, source:"core"|"mod", manifest, files?, consent?}]
var tables := {}                  ## kind -> {id -> Dictionary}
var origins := {}                 ## "kind/id" -> package id
var creatures := {}               ## id -> CreatureDef (parsed lazily)
var arenas := {}                  ## id -> ArenaDef
var errors: PackedStringArray = PackedStringArray()
var _hash := ""
var _gameplay_bytes := PackedByteArray()
var _replaced := {}               ## "kind/id" -> the core entry a mod override replaced (restored if the override fails)
var _assets := {}                 ## absolute path of every validated mod asset -> package id


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
	_replaced.clear()
	_assets.clear()
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
	_run_post_load_validators()
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
	var ctx := _package_context(p)
	for kind in KINDS:
		if bool(ctx["client_only"]) and not kind in PRESENTATION_KINDS:
			if _has_folder(ctx, kind):
				errors.append("%s: presentation-only (client_only) package contains '%s/', which was not loaded" % [pid, kind])
			continue
		var dir := base.path_join(kind)
		for f in _json_files(ctx, kind):
			var full := dir.path_join(f)
			if kind == "policies":
				# trained policies are size-capped before anything is read (same rule as PolicyIO)
				var size := _file_size(full)
				if size > PolicyData.MAX_FILE_BYTES:
					errors.append("%s/%s/%s: policy file is too large (%d KB > %d KB limit); not loaded" % [pid, kind, f, size / 1024, PolicyData.MAX_FILE_BYTES / 1024])
					continue
			var text := FileAccess.get_file_as_string(full)
			var json := JSON.new()
			if json.parse(text) != OK:
				errors.append("%s/%s/%s: JSON error at line %d: %s" % [pid, kind, f, json.get_error_line(), json.get_error_message()])
				continue
			var items: Array = []
			if typeof(json.data) == TYPE_DICTIONARY and json.data.has("items"):
				if typeof(json.data["items"]) != TYPE_ARRAY:
					errors.append("%s/%s/%s: \"items\" must be a list" % [pid, kind, f])
					continue
				items = json.data["items"]
			elif typeof(json.data) == TYPE_DICTIONARY:
				items = [json.data]
			else:
				errors.append("%s/%s/%s: expected an object or {\"items\": [...]}" % [pid, kind, f])
				continue
			for it in items:
				_add(kind, it, ctx, "%s/%s/%s" % [pid, kind, f])
			if kind in GAMEPLAY_KINDS:
				_gameplay_bytes.append_array(("%s|%s|" % [pid, f]).to_utf8_buffer())
				_gameplay_bytes.append_array(text.sha256_buffer())
	for single in SINGLETONS:
		if not _has_singleton(ctx, single):
			continue
		if bool(ctx["client_only"]):
			errors.append("%s: presentation-only (client_only) package contains %s, which was not loaded" % [pid, single])
			continue
		if pid != "core" and not _may_replace_core(ctx):
			errors.append("%s/%s: changes core values, so the package must declare the 'replaces_core' capability and the player must allow it; it was not loaded" % [pid, single])
			continue
		var sp := base.path_join(single)
		var t2 := FileAccess.get_file_as_string(sp)
		var parsed = JSON.parse_string(t2)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s/%s: invalid JSON" % [pid, single])
			continue
		tables["_" + single.get_basename()] = parsed if pid == "core" else _merge(tables.get("_" + single.get_basename(), {}), parsed)
		_gameplay_bytes.append_array(t2.sha256_buffer())


## What the loader needs to know about one package. Core reads its folder directly; a mod reads
## only the files the mod manager validated (`files`), so a link, a file added after the check or
## a differently-cased folder never loads.
func _package_context(p: Dictionary) -> Dictionary:
	var pid := str(p["id"])
	var man: Dictionary = p.get("manifest", {}) if typeof(p.get("manifest")) == TYPE_DICTIONARY else {}
	var ctx := {"pid": pid, "base": str(p["path"]), "core": pid == "core", "files": {},
		"client_only": pid != "core" and bool(man.get("client_only", false)),
		"caps": man.get("capabilities", []) if typeof(man.get("capabilities")) == TYPE_ARRAY else [],
		"consented": p.get("consent", []) if typeof(p.get("consent")) == TYPE_ARRAY else []}
	if pid != "core":
		var raw = p.get("files", [])
		var listed: Array = []
		if typeof(raw) == TYPE_ARRAY or typeof(raw) == TYPE_PACKED_STRING_ARRAY:
			for f in raw:
				listed.append(str(f))
		if listed.is_empty():
			errors.append("%s: the package has no validated file list; nothing was loaded from it" % pid)
		for f in listed:
			ctx["files"][f] = true
		# folders that only differ from a content kind by letter case load nowhere (portable hashes)
		var warned := {}
		for f in ctx["files"]:
			var top := str(f).get_slice("/", 0)
			var k := kind_alias(top)
			if str(f).contains("/") and k != "" and k != top and not warned.has(top) and not bool(ctx["client_only"]):
				warned[top] = true
				errors.append("%s: '%s/' was not loaded; content folders are lowercase ('%s/')" % [pid, top, k])
	return ctx


## JSON files directly inside `kind/` (sorted names).
func _json_files(ctx: Dictionary, kind: String) -> PackedStringArray:
	if bool(ctx["core"]):
		return _list_json(str(ctx["base"]).path_join(kind))
	var out := PackedStringArray()
	for f in ctx["files"]:
		var rel := str(f)
		if rel.get_base_dir() == kind and rel.ends_with(".json"):
			out.append(rel.get_file())
	out.sort()
	return out


## Whether the package has anything that stands for folder `kind`: a validated file under any
## letter-case variant of it, or JSON the file system resolves under that name (Windows aliases).
func _has_folder(ctx: Dictionary, kind: String) -> bool:
	for f in ctx["files"]:
		if str(f).contains("/") and kind_alias(str(f).get_slice("/", 0)) == kind:
			return true
	return not _list_json(str(ctx["base"]).path_join(kind)).is_empty()


## Whether a root singleton is present. A mod's must be validated and named exactly; a case
## variant is reported (and, in a client_only package, counts as present so it is refused).
func _has_singleton(ctx: Dictionary, single: String) -> bool:
	if bool(ctx["core"]):
		return FileAccess.file_exists(str(ctx["base"]).path_join(single))
	if ctx["files"].has(single):
		return true
	for f in ctx["files"]:
		if not str(f).contains("/") and singleton_alias(str(f)) == single:
			if bool(ctx["client_only"]):
				return true
			errors.append("%s: '%s' was not loaded; the file must be named '%s'" % [ctx["pid"], f, single])
			return false
	return bool(ctx["client_only"]) and FileAccess.file_exists(str(ctx["base"]).path_join(single))


func _may_replace_core(ctx: Dictionary) -> bool:
	return "replaces_core" in ctx["caps"] and "replaces_core" in ctx["consented"]


## Case-insensitive form used for name comparisons (also folds Unicode look-alikes such as the
## dotless i or the long s that Windows treats as the same letter).
static func fold(s: String) -> String:
	return s.to_upper().to_lower()


## The content kind a folder name stands for when letter case and trailing dots/spaces are ignored
## (how Windows resolves names), or "".
static func kind_alias(name_: String) -> String:
	var n := fold(name_.rstrip(". "))
	for k in KINDS:
		if fold(k) == n:
			return k
	return ""


## Same for root singleton files ("Tuning.JSON" -> "tuning.json"), or "".
static func singleton_alias(name_: String) -> String:
	var n := fold(name_.rstrip(". "))
	for s in SINGLETONS:
		if fold(s) == n:
			return s
	return ""


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		if typeof(out.get(k)) == TYPE_ARRAY and typeof(b[k]) == TYPE_ARRAY:
			out[k] = out[k] + b[k]
		else:
			out[k] = b[k]
	return out


func _add(kind: String, it, ctx: Dictionary, where: String) -> void:
	if typeof(it) != TYPE_DICTIONARY or str(it.get("id", "")) == "":
		errors.append("%s: entry without an 'id'" % where)
		return
	var pid := str(ctx["pid"])
	var id := str(it["id"])
	var key := "%s/%s" % [kind, id]
	if pid != "core":
		var problem := _id_problem(kind, id, it, ctx)
		if problem != "":
			errors.append("%s: %s" % [where, problem])
			return
		var bad := _confine_assets(it, ctx)
		if bad != "":
			errors.append("%s#%s: %s" % [where, id, bad])
			return
	# entries that extend another are validated after the merge (_resolve_extends)
	if SCHEMA_FOR.has(kind) and not (kind in CREATURE_KINDS and it.has("extends")):
		var errs := Schema.validate_named(it, SCHEMA_FOR[kind], "%s#%s" % [where, id])
		if not errs.is_empty():
			for e in errs:
				errors.append(e)
			return
	if tables[kind].has(id):
		var owner := str(origins.get(key, "?"))
		# a package may re-define its own entry with "override"; a mod may replace a core entry
		# only after _id_problem() checked the capability and the player's consent
		if not bool(it.get("override", false)) or (owner != pid and not (owner == "core" and pid != "core")):
			errors.append("%s: duplicate id '%s' (already defined by %s)" % [where, id, owner])
			return
		if owner == "core" and pid != "core":
			_replaced[key] = tables[kind][id]
	var copy: Dictionary = it.duplicate(true)
	copy["_package"] = pid
	copy["_file"] = where
	tables[kind][id] = copy
	origins[key] = pid


## Why a mod entry id is not allowed ("" when it is): mods add "<modid>:<name>" entries; a bare id
## with "override": true replaces an existing core entry, which needs the `replaces_core`
## capability AND the player's consent; nobody can replace another mod's (or the player's "user:")
## entries, and only one mod may replace a given core entry (D-027).
func _id_problem(kind: String, id: String, it: Dictionary, ctx: Dictionary) -> String:
	var pid := str(ctx["pid"])
	if id.begins_with(pid + ":"):
		return ""
	if id.contains(":"):
		return "'%s' belongs to '%s'; a mod can only add its own '%s:' entries and never replaces another mod's or the player's entries" % [id, id.get_slice(":", 0), pid]
	if not bool(it.get("override", false)):
		return "mod ids must start with '%s:' (got '%s'); to replace a core entry deliberately set \"override\": true and declare the 'replaces_core' capability" % [pid, id]
	var key := "%s/%s" % [kind, id]
	var owner := str(origins.get(key, ""))
	if owner == "":
		return "\"override\": there is no core %s entry '%s' to replace" % [kind, id]
	if owner != "core":
		return "'%s' is already replaced by '%s'; two mods cannot replace the same core entry (disable one of them)" % [id, owner]
	if not "replaces_core" in ctx["caps"]:
		return "replaces the core entry '%s', so the manifest must declare the 'replaces_core' capability (players are asked before such a mod loads); it was not loaded" % id
	if not "replaces_core" in ctx["consented"]:
		return "replaces the core entry '%s' but the player has not allowed it; it was not loaded" % id
	return ""


## Confines a mod entry's art/audio blocks (recursively, lists included). A string names a file
## when its key is in ASSET_KEYS or it looks like a path (a separator, a colon, a leading dot or
## '~', or a file extension); it must then be a relative path to a file the package validated,
## with an asset extension, and is rewritten to the absolute package path. Other strings (colours
## like "#2B6FD9", words like "head") stay as they are. Returns "" or the problem.
func _confine_assets(it: Dictionary, ctx: Dictionary) -> String:
	for key in ["art", "audio"]:
		if not it.has(key):
			continue
		if typeof(it[key]) != TYPE_DICTIONARY:
			return "'%s' must be an object" % key
		var bad := _confine_block(it[key], key, ctx, 0)
		if bad != "":
			return bad
	return ""


func _confine_block(block, where: String, ctx: Dictionary, depth: int) -> String:
	if depth > 8:
		return "'%s' is nested too deeply" % where
	var keys: Array = block.keys() if typeof(block) == TYPE_DICTIONARY else range((block as Array).size())
	for k in keys:
		var v = block[k]
		var here := "%s.%s" % [where, str(k)] if typeof(block) == TYPE_DICTIONARY else "%s[%d]" % [where, int(k)]
		if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
			var bad := _confine_block(v, here, ctx, depth + 1)
			if bad != "":
				return bad
		elif typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
			var s := str(v)
			var named_file := typeof(block) == TYPE_DICTIONARY and str(k) in ASSET_KEYS
			if not named_file and not looks_like_path(s):
				continue
			var problem := asset_path_problem(s, ctx["files"])
			if problem != "":
				return "asset path %s '%s' %s" % [here, s.c_escape(), problem]
			var full := str(ctx["base"]).path_join(s)
			block[k] = full
			_assets[full] = ctx["pid"]
	return ""


static func looks_like_path(s: String) -> bool:
	if s.contains("/") or s.contains("\\") or s.contains(":") or s.begins_with(".") or s.begins_with("~"):
		return true
	return RegEx.create_from_string("\\.[A-Za-z0-9]{1,8}$").search(s) != null


## Why `s` is not an acceptable package asset path ("" when it is). `files`: the package's
## validated relative paths (Dictionary used as a set).
static func asset_path_problem(s: String, files: Dictionary) -> String:
	if s == "" or s.contains("://") or s.is_absolute_path() or s.begins_with("/") or s.contains(":") or s.contains("\\"):
		return "must be a relative path inside the package (no res://, user://, drive or absolute paths)"
	for part in s.split("/"):
		if part == "" or part == "." or part == "..":
			return "must stay inside the package (no '..', '.' or empty folder names)"
	if not s.get_extension().to_lower() in ASSET_EXTS:
		return "must be a %s file" % "/".join(ASSET_EXTS)
	if not files.has(s):
		return "is not a file in the package (names are case-sensitive)"
	return ""


## True for files Content validated as part of a loaded mod package (absolute paths, as rewritten
## in art/audio blocks). Views call this before handing a non-core path to a loader.
func is_package_asset(path: String) -> bool:
	return _assets.has(path)


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
		var todo: Array = tables[kind].keys()
		while not todo.is_empty():
			var id := str(todo.pop_front())
			if not tables[kind].has(id):
				continue
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
				if _drop_entry(kind, id):
					todo.append(id)
				continue
			merged["_extends"] = chain.slice(1)
			var errs := Schema.validate_named(merged, SCHEMA_FOR[kind], "%s#%s" % [d.get("_file", id), id])
			if not errs.is_empty():
				for e in errs:
					errors.append(e)
				if _drop_entry(kind, id):
					todo.append(id)
				continue
			tables[kind][id] = merged


## Size of a file in bytes without reading it (-1 when it cannot be opened).
static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n


## Removes an entry that failed validation; a failed mod override gives the core entry back.
## Returns true when the restored core entry still has to be resolved (it extends another).
func _drop_entry(kind: String, id: String) -> bool:
	var key := "%s/%s" % [kind, id]
	if _replaced.has(key):
		var by := str(origins.get(key, "?"))
		var core_entry: Dictionary = _replaced[key]
		tables[kind][id] = core_entry
		origins[key] = "core"
		_replaced.erase(key)
		errors.append("%s: the override of %s '%s' was not used; the core entry stays in place" % [by, kind, id])
		return core_entry.has("extends")
	tables[kind].erase(id)
	origins.erase(key)
	return false


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
	# start from the built-in defaults every time: a disabled mod's tuning must not linger
	Tuning.reset()
	if tables.has("_tuning"):
		for problem in Tuning.apply_overrides(tables["_tuning"]):
			errors.append("tuning.json: %s" % problem)


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


## Post-load validators contributed by subsystems: scripts exposing a static
## `validate_content(content: Node) -> PackedStringArray` that schema-check and cross-check their
## kinds after every package is loaded (they may drop invalid entries from `tables`). Scripts that
## are not present in this build are skipped. Campaign: docs/CAMPAIGN_SYSTEMS.md#validation.
const POST_LOAD_VALIDATORS := ["res://src/campaign/campaign_validator.gd"]


func _run_post_load_validators() -> void:
	for path in POST_LOAD_VALIDATORS:
		if not ResourceLoader.exists(path):
			continue
		var script = load(path)
		if script == null:
			errors.append("validator %s failed to load" % path)
			continue
		var found = script.call("validate_content", self)
		if typeof(found) == TYPE_PACKED_STRING_ARRAY or typeof(found) == TYPE_ARRAY:
			for e in found:
				errors.append(str(e))
