class_name CreatureResolver
extends RefCounted
## Resolves creature ids used by the campaign to raw creature dictionaries (deep copies that the
## caller may patch freely):
##   1. a creature entry with that id in the creatures / minions / bosses tables
##      (the creature owner's files; same lookup order as Content.creature_entry on main);
##   2. a campaign minion loadout recipe (encounters/*.json, "type": "minion_loadout"): the base
##      minion (e.g. npc_scrapling) with the loadout's patches applied;
##   3. ONLY when `stand_in` is set (tests / --campaign-stand-ins dev runs): a copy of the stand-in
##      creature renamed to the requested id, with roster/boss stats applied so numbers stay
##      realistic. Production runs never fall back silently: unresolved ids are reported by the
##      campaign validator and such encounters are excluded from generation.

const CREATURE_KINDS := ["creatures", "minions", "bosses"]

var content                       ## Content autoload (or any object with get_entry(kind, id))
var loadouts := {}                ## loadout id -> recipe dict
var roster_info := {}             ## fighter id -> {element, class, name} (campaign rules)
var standin_stats := {}           ## creature id -> stats overrides used for stand-ins (bosses)
var stand_in := ""                ## stand-in creature id; "" disables stand-ins
var stand_ins_used := {}          ## id -> true (diagnostics)
var _checked := {}                ## id -> PackedStringArray of parse problems ([] = usable)


func _init(content_src = null) -> void:
	content = content_src


## The installed creature entry for `id` (any of the creature tables), usable or not.
func raw_entry(id: String) -> Dictionary:
	if content == null:
		return {}
	for k in CREATURE_KINDS:
		var d: Dictionary = content.get_entry(k, id)
		if not d.is_empty() and d.has("body"):
			return d
	return {}


## The installed entry only if it also parses into a valid CreatureDef: a creature whose kit is
## still being authored (missing moves, newer stat names) is installed but not usable yet, and
## is treated like a missing one (stand-ins in tests/dev runs; excluded from generation).
func usable_entry(id: String) -> Dictionary:
	var d := raw_entry(id)
	if d.is_empty():
		return {}
	if not _checked.has(id):
		var errs := PackedStringArray()
		parse(_clean(d), errs)
		_checked[id] = errs
	return d if (_checked[id] as PackedStringArray).is_empty() else {}


## Why an installed creature is not usable ([] when it is, or when it is not installed).
func problems(id: String) -> PackedStringArray:
	usable_entry(id)
	return _checked.get(id, PackedStringArray())


## True when `id` resolves from real, valid content (no stand-in).
func exists(id: String) -> bool:
	if not usable_entry(id).is_empty():
		return true
	if loadouts.has(id):
		return not usable_entry(str(loadouts[id].get("base", ""))).is_empty()
	return false


## True when `id` resolves, counting stand-ins.
func resolvable(id: String) -> bool:
	return exists(id) or stand_in != ""


## Deep copy of the creature dictionary for `id` ({} if unresolvable).
func creature_dict(id: String) -> Dictionary:
	var d := usable_entry(id)
	if not d.is_empty():
		return _clean(d)
	if loadouts.has(id):
		var rec: Dictionary = loadouts[id]
		var base := creature_dict(str(rec.get("base", "")))
		if base.is_empty():
			return {}
		base["id"] = id
		if rec.has("name"):
			base["name"] = str(rec["name"])
		ContentPatch.apply_all(base, rec.get("patches", []))
		var ai: Dictionary = base.get("ai", {})
		for k in rec.get("ai", {}):
			ai[k] = rec["ai"][k]
		base["ai"] = ai
		var tags: Array = base.get("tags", [])
		for t in rec.get("tags", []):
			if not tags.has(t):
				tags.append(t)
		base["tags"] = tags
		return base
	if stand_in != "" and stand_in != id:
		var s := usable_entry(stand_in)
		if s.is_empty():
			return {}
		stand_ins_used[id] = true
		var c := _clean(s)
		c["id"] = id
		c["npc_only"] = false
		var info: Dictionary = roster_info.get(id, {})
		c["name"] = str(info.get("name", id.capitalize()))
		c["title"] = "stand-in"
		if info.has("element"):
			c["element"] = str(info["element"])
		var st: Dictionary = c.get("stats", {})
		for k in standin_stats.get(id, {}):
			st[k] = standin_stats[id][k]
		c["stats"] = st
		return c
	return {}


## Parses a (possibly patched) creature dictionary. Returns null and fills `errors` when invalid.
static func parse(d: Dictionary, errors: PackedStringArray) -> CreatureDef:
	if d.is_empty():
		errors.append("empty creature definition")
		return null
	var c := CreatureDef.from_dict(d, Callable(), str(d.get("_package", "campaign")))
	if not c.is_valid():
		errors.append_array(c.errors)
	return c


static func _clean(d: Dictionary) -> Dictionary:
	var c: Dictionary = d.duplicate(true)
	c.erase("_file")
	return c
