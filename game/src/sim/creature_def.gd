class_name CreatureDef
extends RefCounted
## A playable (or NPC) creature: its body, base stats, moveset slots, abilities, element and
## presentation references. Loaded from content JSON (schema: content/schemas/creature.schema.json).

const MOVE_SLOTS := ["l1", "l2", "l3", "heavy", "finisher", "dash_attack", "grab", "throw", "pummel", "taunt", "getup_attack"]
const ABILITY_SLOTS := ["ability1", "ability2", "juice"]

var id := ""
var display_name := ""
var title := ""                 ## short epithet shown in menus
var element := ""
var body: BodyDef
var stats := {
	"health": 100.0, "walk_speed": 3.4, "accel": 26.0, "turn_rate": 9.0,
	"stamina": 100.0, "stamina_regen": 24.0, "poise": 100.0, "poise_regen": 35.0,
	"dodge_speed": 7.5, "dodge_time": 0.26, "power": 1.0, "defense": 1.0, "weight": 1.0,
}
var moves := {}                 ## slot -> MoveDef (plus any extra ids used by abilities)
var abilities := {}             ## slot -> MoveDef (kind "ability") with cooldown
var cooldowns := {}             ## slot -> seconds
var juice := {}                 ## JUICE ultimate parameters (duration, buffs, move)
var art := {}                   ## model path, palette, gore piece
var audio := {}                 ## voice/impact palette
var ai := {}                    ## bot personality weights
var tags: PackedStringArray = PackedStringArray()
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
	c.art = d.get("art", {})
	c.audio = d.get("audio", {})
	c.ai = d.get("ai", {})
	return c


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
