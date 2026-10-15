class_name Elements
## Element registry: names, statuses, mild resist/weak multipliers and pair reactions.
## Data comes from content (content/core/elements.json); this class holds the loaded tables.

static var defs := {}            ## element id -> Dictionary (name, color, icon, status, ...)
static var matchups := {}        ## "attacker>defender" -> multiplier
static var reactions := {}       ## "a+b" (sorted ids) -> Dictionary


static func load_from(d: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	defs.clear()
	matchups.clear()
	reactions.clear()
	for e in d.get("elements", []):
		if typeof(e) != TYPE_DICTIONARY or str(e.get("id", "")) == "":
			errs.append("element entry without id")
			continue
		defs[str(e["id"])] = e
	for m in d.get("matchups", []):
		matchups["%s>%s" % [m.get("attacker", ""), m.get("defender", "")]] = float(m.get("mult", 1.0))
	for r in d.get("reactions", []):
		var a := str(r.get("a", ""))
		var b := str(r.get("b", ""))
		if not defs.has(a) or not defs.has(b):
			errs.append("reaction %s+%s references an unknown element" % [a, b])
			continue
		reactions[pair_key(a, b)] = r
	return errs


static func pair_key(a: String, b: String) -> String:
	return "%s+%s" % [a, b] if a < b else "%s+%s" % [b, a]


static func damage_mult(attack_el: String, defender_el: String) -> float:
	if attack_el == "" or defender_el == "":
		return 1.0
	return float(matchups.get("%s>%s" % [attack_el, defender_el], 1.0))


static func reaction(a: String, b: String) -> Dictionary:
	return reactions.get(pair_key(a, b), {})


static func display_name(id: String) -> String:
	return str(defs.get(id, {}).get("name", id.capitalize()))


static func color(id: String) -> Color:
	var c = defs.get(id, {}).get("color", "#ffffff")
	return Color.from_string(str(c), Color.WHITE)
