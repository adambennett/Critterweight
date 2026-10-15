class_name Elements
## Element registry: names, statuses, mild resist/weak multipliers, pair reactions, zones and
## zone-on-zone reactions. Data comes from content packages' elements.json (core + mods).

static var defs := {}            ## element id -> Dictionary (name, color, icon, status, ...)
static var rules := {}           ## build-up thresholds, caps, immunity windows ...
static var matchups := {}        ## "attacker>defender" -> multiplier
static var reactions := {}       ## "a+b" (sorted ids) -> Dictionary
static var zones := {}           ## zone kind -> Dictionary (incl. derived zones)
static var zone_reactions := {}  ## "existing|incoming" -> Dictionary


static func load_from(d: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	defs.clear()
	matchups.clear()
	reactions.clear()
	zones.clear()
	zone_reactions.clear()
	rules = d.get("rules", {})
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
	var zd: Dictionary = d.get("zones", {})
	for k in zd:
		zones[str(k)] = zd[k]
	var dz: Dictionary = d.get("derived_zones", {})
	for k in dz:
		zones[str(k)] = dz[k]
	for zr in d.get("zone_reactions", []):
		zone_reactions["%s|%s" % [zr.get("existing", ""), zr.get("incoming", "")]] = zr
		var res := str(zr.get("result", ""))
		if not res in ["grow", "rubble_prop", "smear", "slide"] and not zones.has(res):
			errs.append("zone reaction result '%s' is not a defined zone" % res)
	return errs


static func pair_key(a: String, b: String) -> String:
	return "%s+%s" % [a, b] if a < b else "%s+%s" % [b, a]


static func damage_mult(attack_el: String, defender_el: String) -> float:
	if attack_el == "" or defender_el == "":
		return 1.0
	return float(matchups.get("%s>%s" % [attack_el, defender_el], 1.0))


static func reaction(a: String, b: String) -> Dictionary:
	return reactions.get(pair_key(a, b), {})


static func zone_def(kind: String) -> Dictionary:
	return zones.get(kind, {})


static func zone_reaction(existing_kind: String, incoming_el: String) -> Dictionary:
	return zone_reactions.get("%s|%s" % [existing_kind, incoming_el], {})


static func display_name(id: String) -> String:
	return str(defs.get(id, {}).get("name", id.capitalize()))


static func status_name(id: String) -> String:
	return str(defs.get(id, {}).get("status_name", ""))


static func color(id: String) -> Color:
	var c = defs.get(id, {}).get("color", "#ffffff")
	return Color.from_string(str(c), Color.WHITE)
