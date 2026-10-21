class_name CreatureDef
extends RefCounted
## A playable (or NPC) creature: its body, base stats, moveset slots, abilities, element and
## presentation references. Loaded from content JSON (schema: content/schemas/creature.schema.json).

const MOVE_SLOTS := ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "pummel", "taunt"]
const ABILITY_SLOTS := ["ability1", "ability2", "juice"]

var id := ""
var display_name := ""
var title := ""                 ## short epithet shown in menus
var element := ""
var body: BodyDef
var stats := {
	"health": 100.0, "walk_speed": 3.4, "side_speed": 0.0, "accel": 26.0, "turn_rate": 9.0,
	"stamina": 100.0, "stamina_regen": 12.0, "poise": 60.0, "poise_regen": 15.0,
	"dodge_distance": 2.8, "dodge_time": 0.3, "power": 1.0, "defense": 1.0, "weight": 1.0,
	"dodge_side_distance": 0.0,   ## > 0: dash length of a sideways dodge (crabs); see Fighter.dodge_distance_now
	# kit traits (multipliers; run/rules mods of the same name multiply on top, see Fighter.getup_speed_mult)
	"getup_speed": 1.0,           ## knockdown recovery speed (1.3 = 30% faster)
	"held_time": 1.0,             ## how long grabs can hold this fighter (0.7 = 30% shorter)
}
var moves := {}                 ## slot -> MoveDef (plus any extra ids used by abilities)
var abilities := {}             ## slot -> MoveDef (kind "ability") with cooldown
var cooldowns := {}             ## slot -> seconds
var juice := {}                 ## JUICE ultimate parameters (duration, buffs, move)
var light_string: Array = ["l1", "l2", "l3"]   ## Light presses walk this list (techniques may lengthen it)
var ability_charges := {}       ## slot -> max charges (default 1)
var passives: Array = []        ## always-on Hooks (kit traits, techniques)
var throws := {}                ## throw_fwd / throw_side / throw_back -> {distance, damage, up, knockdown, buildup}
var art := {}                   ## model path, palette, gore piece
var audio := {}                 ## voice/impact palette
var ai := {}                    ## bot personality weights
var tags: PackedStringArray = PackedStringArray()
var pool := {}                  ## Movesets: move id -> PoolMove (docs/design/MOVESET_COMBAT.md)
var loadouts := {}              ## loadout id -> {name, moves: [4 pool ids]}
var default_loadout := ""       ## the loadout a fighter gets when nothing else is chosen
var npc_only := false
var source := ""                ## content package id that defined this creature
var errors: PackedStringArray = PackedStringArray()


static func from_dict(d: Dictionary, body_lookup: Callable = Callable(), src := "") -> CreatureDef:
	var c := CreatureDef.new()
	c.source = src
	c.id = str(d.get("id", ""))
	c.display_name = str(d.get("name", c.id))
	c.title = str(d.get("title", ""))
	c.element = str(d.get("element", ""))
	c.npc_only = bool(d.get("npc_only", false))
	c.tags = PackedStringArray(d.get("tags", []))
	if c.id == "":
		c.errors.append("creature without id")
	var bd = d.get("body", null)
	if typeof(bd) == TYPE_DICTIONARY:
		c.body = BodyDef.from_dict(bd, c.id)
	elif typeof(bd) == TYPE_STRING and body_lookup.is_valid():
		c.body = body_lookup.call(bd)
	if c.body == null:
		c.errors.append("%s: body missing or unknown" % c.id)
		return c
	c.errors.append_array(c.body.errors)
	var st: Dictionary = d.get("stats", {})
	for k in st:
		if c.stats.has(k):
			c.stats[k] = float(st[k])
		else:
			c.errors.append("%s: unknown stat '%s'" % [c.id, k])
	var md: Dictionary = d.get("moves", {})
	for slot in md:
		var mv = md[slot]
		if typeof(mv) != TYPE_DICTIONARY:
			c.errors.append("%s: move '%s' is not an object" % [c.id, slot])
			continue
		var mdict: Dictionary = mv.duplicate()
		if not mdict.has("id"):
			mdict["id"] = "%s.%s" % [c.id, slot]
		c.moves[str(slot)] = MoveDef.parse(mdict, c.body, c.errors)
	for slot in ["l1", "heavy", "grab"]:
		if not c.moves.has(slot):
			c.errors.append("%s: required move slot '%s' missing" % [c.id, slot])
	var ad: Dictionary = d.get("abilities", {})
	for slot in ad:
		var av = ad[slot]
		if typeof(av) != TYPE_DICTIONARY:
			continue
		var adict: Dictionary = av.duplicate()
		if not adict.has("id"):
			adict["id"] = "%s.%s" % [c.id, slot]
		adict["kind"] = "ability"
		c.abilities[str(slot)] = MoveDef.parse(adict, c.body, c.errors)
		c.cooldowns[str(slot)] = float(av.get("cooldown", 6.0))
	c.juice = d.get("juice", {})
	if d.has("string"):
		c.light_string = d["string"]
	for slot2 in c.light_string:
		if not c.moves.has(str(slot2)):
			c.errors.append("%s: light string references missing move '%s'" % [c.id, slot2])
	for slot3 in ad:
		if typeof(ad[slot3]) == TYPE_DICTIONARY:
			c.ability_charges[str(slot3)] = int(ad[slot3].get("charges", 1))
	c.passives = d.get("passives", [])
	for ph in c.passives:
		for e in Hooks.validate(ph):
			c.errors.append("%s: %s" % [c.id, e])
	c.throws = d.get("throws", {})
	c.art = d.get("art", {})
	c.audio = d.get("audio", {})
	c.ai = d.get("ai", {})
	var mp = d.get("movepool", null)
	if typeof(mp) == TYPE_DICTIONARY and not (mp as Dictionary).is_empty():
		for key in mp:
			if typeof(mp[key]) == TYPE_DICTIONARY:
				c.pool[str(key)] = PoolMove.parse(c, str(key), mp[key], c.errors)
		var lo = d.get("loadouts", {})
		if typeof(lo) == TYPE_DICTIONARY:
			for lk in lo:
				var entry = lo[lk]
				var ids: Array = entry.get("moves", []) if typeof(entry) == TYPE_DICTIONARY else []
				var problem := c.loadout_problem(ids)
				if problem != "":
					c.errors.append("%s: loadout '%s': %s" % [c.id, lk, problem])
				c.loadouts[str(lk)] = {"name": str(entry.get("name", str(lk).capitalize())) if typeof(entry) == TYPE_DICTIONARY else str(lk), "moves": ids.duplicate()}
		c.default_loadout = str(d.get("default_loadout", c.loadouts.keys()[0] if not c.loadouts.is_empty() else ""))
		if c.default_loadout != "" and not c.loadouts.has(c.default_loadout):
			c.errors.append("%s: default_loadout '%s' is not a loadout" % [c.id, c.default_loadout])
	else:
		c.derive_pool()
	return c


## Movesets for a creature without a `movepool` (NPCs, bosses, mods written before v0.9.18): its
## Classic kit as four moves (the light string with finisher and dash strike, the heavy with its
## charged follow-up, the two abilities), equipped in that order. Its fights play like Classic.
func derive_pool() -> void:
	pool.clear()
	loadouts.clear()
	var ids: Array = []
	if not light_string.is_empty() and moves.has(str(light_string[0])):
		var string: Array = light_string.duplicate()
		if moves.has("finisher"):
			string.append("finisher")
		var basic := {"name": str((moves[str(light_string[0])] as MoveDef).display_name), "category": "strike", "role": "basic", "string": string}
		if moves.has("dash_attack"):
			basic["dash"] = "dash_attack"
		pool["basic"] = PoolMove.parse(self, "basic", basic, errors)
		ids.append("basic")
	if moves.has("heavy"):
		var heavy := {"name": str((moves["heavy"] as MoveDef).display_name), "category": "strike", "role": "heavy", "use": "heavy"}
		var hm: MoveDef = moves["heavy"]
		if hm.charge_time > 0.0:
			heavy["hold"] = "charge"
		if moves.has("heavy_charged"):
			heavy["charged"] = "heavy_charged"
		pool["heavy"] = PoolMove.parse(self, "heavy", heavy, errors)
		ids.append("heavy")
	for slot in ["ability1", "ability2"]:
		if abilities.has(slot):
			pool[slot] = PoolMove.parse(self, slot, {"name": str((abilities[slot] as MoveDef).display_name), "category": "control", "role": "special", "use": slot}, errors)
			ids.append(slot)
	for pm: PoolMove in pool.values():
		pm.derived = true
	loadouts["classic"] = {"name": "Classic kit", "moves": ids}
	default_loadout = "classic"


## Why a list of pool ids is not a valid loadout ("" when it is): 1-4 known, distinct moves with at
## least one basic strike (a fighter must always have something to do). Martial creatures (Varga)
## equip techniques instead: one per modifier group, his limb strikes being always available.
func loadout_problem(ids: Array) -> String:
	if tags.has("martial") and not pool.is_empty():
		return _martial_loadout_problem(ids)
	if ids.is_empty() or ids.size() > 4:
		return "a loadout has 1 to 4 moves"
	var seen := {}
	var basic := false
	for id in ids:
		var k := str(id)
		if not pool.has(k):
			return "unknown move '%s'" % k
		if seen.has(k):
			return "'%s' is equipped twice" % k
		seen[k] = true
		basic = basic or (pool[k] as PoolMove).role == "basic"
	if not basic:
		return "a loadout needs a basic move"
	return ""


func _martial_loadout_problem(ids: Array) -> String:
	var groups := {}
	for p: PoolMove in pool.values():
		if not p.martial.is_empty():
			groups[str(p.martial.get("group", ""))] = true
	var seen := {}
	for id in ids:
		var k := str(id)
		if not pool.has(k):
			return "unknown move '%s'" % k
		var p: PoolMove = pool[k]
		var g := str(p.martial.get("group", ""))
		if g == "":
			return "'%s' is not a technique" % k
		if seen.has(g):
			return "two techniques for %s" % g
		seen[g] = true
	if seen.size() != groups.size():
		return "a technique for every group (%s)" % ", ".join(PackedStringArray(groups.keys()))
	return ""


## The loadout to fight with: `wanted` when it is valid, else the default loadout.
func resolve_loadout(wanted: Array) -> Array:
	if not wanted.is_empty() and loadout_problem(wanted) == "":
		return wanted.duplicate()
	if loadouts.has(default_loadout):
		return (loadouts[default_loadout]["moves"] as Array).duplicate()
	return []


static func load_json(path: String) -> CreatureDef:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		var bad := CreatureDef.new()
		bad.errors.append("%s: invalid JSON" % path)
		return bad
	return from_dict(parsed, Callable(), path)


func is_valid() -> bool:
	return errors.is_empty()


func stat(name_: String) -> float:
	return float(stats.get(name_, 0.0))
