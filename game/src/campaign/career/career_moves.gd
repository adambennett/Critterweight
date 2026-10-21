class_name CareerMoves
extends RefCounted
## The career fighter's moves (v0.9.18 Movesets, docs/design/MOVESET_COMBAT.md §5 and §8): which
## pool moves it has learned, the loadout it equips and the style drilled into each move. Pure
## functions over the "moves" block of a CareerState (CareerController is the only writer):
##   {"learned": [pool ids], "equipped": [1-4 pool ids], "drilled": {pool id: style id}}
## Rules:
##   * a new career (and a v1 save, CareerState.migrate) starts with every move of the creature's
##     recommended loadouts learned, its default loadout equipped and nothing drilled (starting());
##   * learning and drilling are training weeks (CareerController.learn_move / drill_move). Learn:
##     one of a few unlearned pool moves offered that week (learn_options, at most
##     career.moves.learn_choices, drawn per career seed and week so the choice is stable all week).
##     Drill: one of the two styles of a learned move that is not drilled yet; a drill is permanent;
##   * equipped is a subset of learned and a valid loadout for the creature (its default loadout
##     always is: CreatureDef.resolve_loadout falls back to it);
##   * a drilled style reaches the bout as ContentPatch ops on the creature JSON (drill_effects ->
##     CareerBuild.compose, the BuildApplier path the career stats use), never as a fighter entry key.
## normalize() repairs a block against the installed creature: ids a content update renamed or
## removed are dropped, a fighter whose derived Classic pool was replaced by an authored pool starts
## over with its starting moves, and an invalid loadout falls back to the default one (whose moves
## are then learned). It returns its input unchanged (equal) for a valid block.


static func empty() -> Dictionary:
	return {"learned": [], "equipped": [], "drilled": {}}


## The career fighter's base kit (no career stats, no drills): the creature its moves refer to.
## Null when the fighter is not installed (or not resolvable through the catalog's stand-in).
static func creature(catalog: CampaignCatalog, fighter: String) -> CreatureDef:
	if catalog == null or catalog.resolver == null or fighter == "":
		return null
	var d := catalog.resolver.creature_dict(fighter)
	if d.is_empty():
		return null
	var errs := PackedStringArray()
	return CreatureResolver.parse(d, errs)


## Strings only (ids read back from JSON or passed by a screen).
static func strings(ids) -> Array:
	var out: Array = []
	if typeof(ids) != TYPE_ARRAY:
		return out
	for id in ids:
		if typeof(id) == TYPE_STRING or typeof(id) == TYPE_STRING_NAME:
			out.append(str(id))
	return out


## The creature's default loadout (what a fighter gets when nothing else is chosen).
static func default_loadout(c: CreatureDef) -> Array:
	if c == null:
		return []
	return strings(c.resolve_loadout([]))


## A new career's moves: the moves of the creature's recommended loadouts learned (pool order), the
## default loadout equipped, nothing drilled.
static func starting(c: CreatureDef) -> Dictionary:
	var out := empty()
	if c == null or c.pool.is_empty():
		return out
	var known := {}
	for lk in c.loadouts:
		var lo = c.loadouts[lk]
		if typeof(lo) == TYPE_DICTIONARY:
			for id in strings((lo as Dictionary).get("moves", [])):
				known[id] = true
	var eq := default_loadout(c)
	for id2 in eq:
		known[id2] = true
	var learned: Array = []
	for id3 in c.pool:
		if known.has(str(id3)):
			learned.append(str(id3))
	out["learned"] = learned
	out["equipped"] = eq
	return out


## A moves block with the right shape whatever was stored (lists of strings without repeats, a
## string -> string map).
static func well_formed(moves) -> Dictionary:
	var out := empty()
	if typeof(moves) != TYPE_DICTIONARY:
		return out
	var m: Dictionary = moves
	var learned: Array = []
	for id in strings(m.get("learned", [])):
		if not learned.has(id):
			learned.append(id)
	out["learned"] = learned
	out["equipped"] = strings(m.get("equipped", []))
	var drilled := {}
	var dr = m.get("drilled", {})
	if typeof(dr) == TYPE_DICTIONARY:
		for k in dr:
			if typeof(dr[k]) == TYPE_STRING:
				drilled[str(k)] = str(dr[k])
	out["drilled"] = drilled
	return out


## Why `ids` cannot be equipped ("" when they can): every move learned, and a valid loadout for
## the creature (or exactly its default loadout).
static func loadout_problem(c: CreatureDef, moves: Dictionary, ids: Array) -> String:
	if c == null:
		return "the fighter is not installed"
	var lo := strings(ids)
	if lo.size() != ids.size() or lo.is_empty():
		return "a loadout is a list of moves"
	var learned: Array = moves.get("learned", [])
	for id in lo:
		if not learned.has(id):
			return "%s is not learned yet" % move_name(c, id)
	if lo == default_loadout(c):
		return ""
	return c.loadout_problem(lo)


## The block repaired against the installed creature (see the header). Without a creature (not
## installed) the stored moves are kept as they are, so they survive until the fighter is back.
static func normalize(c: CreatureDef, moves) -> Dictionary:
	var src := well_formed(moves)
	if c == null or c.pool.is_empty():
		return src
	var learned: Array = []
	for id in src["learned"]:
		if c.pool.has(id):
			learned.append(id)
	if learned.is_empty():
		return starting(c)
	var equipped: Array = src["equipped"]
	if equipped.is_empty() or loadout_problem(c, {"learned": learned}, equipped) != "":
		equipped = default_loadout(c)
		for id2 in equipped:
			if not learned.has(id2):
				learned.append(id2)
	var drilled := {}
	for mid in src["drilled"]:
		var pm: PoolMove = c.pool.get(mid)
		var style := str(src["drilled"][mid])
		if pm != null and learned.has(mid) and pm.styles.has(style):
			drilled[mid] = style
	return {"learned": learned, "equipped": equipped, "drilled": drilled}


## Whether two blocks hold the same moves in the same order (JSON-equal).
static func same(a, b) -> bool:
	return JSON.stringify(Saves.canonical(a), "", true) == JSON.stringify(Saves.canonical(b), "", true)


## This week's "Learn a move" choices: the unlearned pool moves, at most `n` of them (drawn by the
## RunRng stream "career/learn/w<week>" of the career seed when there are more), in pool order.
static func learn_options(c: CreatureDef, moves: Dictionary, seed_value: int, week: int, n: int) -> Array:
	var open: Array = []
	if c == null:
		return open
	var learned: Array = moves.get("learned", [])
	for id in c.pool:
		if not learned.has(str(id)):
			open.append(str(id))
	if n > 0 and open.size() > n:
		var picked := RunRng.stream(seed_value, "career/learn/w%d" % week).pick_distinct(open, n)
		var keep: Array = []
		for id2 in open:
			if picked.has(id2):
				keep.append(id2)
		open = keep
	return open


## "Drill a move" choices: [{move, style}] for every learned move with styles that is not drilled
## yet (pool order, each move's styles in authored order).
static func drill_options(c: CreatureDef, moves: Dictionary) -> Array:
	var out: Array = []
	if c == null:
		return out
	var learned: Array = moves.get("learned", [])
	var drilled: Dictionary = moves.get("drilled", {})
	for id in c.pool:
		var mid := str(id)
		if not learned.has(mid) or drilled.has(mid):
			continue
		var pm: PoolMove = c.pool[id]
		for sid in pm.styles:
			out.append({"move": mid, "style": str(sid)})
	return out


## The drilled styles as BuildApplier run effects, one per drilled move in pool order: the style's
## ContentPatch ops on the creature JSON (CareerBuild.compose applies them before the stats).
static func drill_effects(c: CreatureDef, drilled: Dictionary) -> Array:
	var out: Array = []
	if c == null:
		return out
	for id in c.pool:
		var mid := str(id)
		if not drilled.has(mid):
			continue
		var pm: PoolMove = c.pool[id]
		var sid := str(drilled[mid])
		var st = pm.styles.get(sid, {})
		if typeof(st) != TYPE_DICTIONARY:
			continue
		var patch = (st as Dictionary).get("patch", [])
		if typeof(patch) != TYPE_ARRAY or (patch as Array).is_empty():
			continue
		out.append({"source": "drill:%s:%s" % [mid, sid], "apply": {"patches": (patch as Array).duplicate(true)}})
	return out


static func move_name(c: CreatureDef, id: String) -> String:
	var pm: PoolMove = c.pool.get(id) if c != null else null
	return pm.display_name if pm != null else id.capitalize()


static func style_name(c: CreatureDef, id: String, style: String) -> String:
	var pm: PoolMove = c.pool.get(id) if c != null else null
	if pm == null or not pm.styles.has(style) or typeof(pm.styles[style]) != TYPE_DICTIONARY:
		return style.capitalize()
	return str((pm.styles[style] as Dictionary).get("name", style.capitalize()))


static func style_desc(c: CreatureDef, id: String, style: String) -> String:
	var pm: PoolMove = c.pool.get(id) if c != null else null
	if pm == null or not pm.styles.has(style) or typeof(pm.styles[style]) != TYPE_DICTIONARY:
		return ""
	return str((pm.styles[style] as Dictionary).get("desc", ""))


## "Strike", "Stream"... ("Basic strike" for the basic string).
static func category_label(pm: PoolMove) -> String:
	if pm == null:
		return ""
	return "Basic strike" if pm.role == "basic" else pm.category.capitalize()


## The name of the recommended loadout `ids` matches ("" for a custom one).
static func loadout_name(c: CreatureDef, ids: Array) -> String:
	if c == null:
		return ""
	var lo := strings(ids)
	for lk in c.loadouts:
		var d = c.loadouts[lk]
		if typeof(d) == TYPE_DICTIONARY and strings((d as Dictionary).get("moves", [])) == lo:
			return str((d as Dictionary).get("name", str(lk).capitalize()))
	return ""
