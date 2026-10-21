class_name RunMoves
extends RefCounted
## Moves in runs (v0.9.18; docs/CAMPAIGN_SYSTEMS.md "Moves in runs", MOVESET_COMBAT.md §5): what a
## run player has learned, equipped and drilled, where new moves come from, and the texts and
## offer weights that tie v0.9.17 upgrades to moves. Pure functions of the catalog and the run
## state (random choices draw from the run's own streams), shared by RunState, RunController,
## the shop, AutoPilot, EncounterBuilder, BuildApplier and the campaign screens.
##   player["moves"] = {learned: [pool ids], equipped: [pool ids], drilled: {move id: style id}}
##   state["combat"] = "moves" (every run today) | "classic" (a future start option)
## A new run learns the fighter's recommended loadouts combined and equips its default loadout;
## Fight Camp's Sparring Partner / Film Study add a learned / drilled move at the start. A move
## id the installed pool no longer has is ignored (a pool may still change while it is authored).
## Pool data is parsed once per catalog and fighter (CampaignCatalog.moves_cache).


# =============================================================================================
# Pool data
# =============================================================================================

## The fighter's move pool as plain data: {fighter, ok, order: [ids], moves: {id: {id, name, short,
## desc, role, category, hold, element, use, charged, string, dash, inline, slots, styles: {style
## id: {name, desc, patch}}, cooldown, charges, classes}}, loadouts: {id: {name, moves}},
## loadout_order, default, martial, raw (the unpatched creature dict; read only), def (CreatureDef)}.
static func info(catalog: CampaignCatalog, fighter: String) -> Dictionary:
	if catalog == null:
		return _empty_info(fighter)
	var key := "info|" + fighter
	if not catalog.moves_cache.has(key):
		catalog.moves_cache[key] = _build_info(catalog, fighter)
	return catalog.moves_cache[key]


static func _empty_info(fighter: String) -> Dictionary:
	return {"fighter": fighter, "ok": false, "order": [], "moves": {}, "loadouts": {}, "loadout_order": [], "default": "",
		"martial": false, "raw": {}, "def": null}


static func _build_info(catalog: CampaignCatalog, fighter: String) -> Dictionary:
	var out := _empty_info(fighter)
	var d := catalog.resolver.creature_dict(fighter)
	if d.is_empty():
		return out
	var errs := PackedStringArray()
	var c := CreatureResolver.parse(d, errs)
	if c == null:
		return out
	out["ok"] = true
	out["raw"] = d
	out["def"] = c
	out["martial"] = c.tags.has("martial")
	var mp: Dictionary = d.get("movepool", {}) if typeof(d.get("movepool")) == TYPE_DICTIONARY else {}
	var moves := {}
	for id in c.pool:
		var pm: PoolMove = c.pool[id]
		var styles := {}
		for sid in pm.styles:
			var sd = pm.styles[sid]
			if typeof(sd) != TYPE_DICTIONARY:
				continue
			var patch = (sd as Dictionary).get("patch", [])
			styles[str(sid)] = {"name": str((sd as Dictionary).get("name", str(sid).capitalize())), "desc": str((sd as Dictionary).get("desc", "")),
				"patch": patch if typeof(patch) == TYPE_ARRAY else []}
		var inline := UpgradeTranslation._is_inline(mp.get(str(id)))
		moves[str(id)] = {"id": str(id), "name": pm.display_name, "short": pm.short, "desc": pm.desc, "role": pm.role,
			"category": pm.category, "hold": pm.hold, "element": pm.element, "use": pm.use, "charged": pm.charged_use,
			"string": pm.string.duplicate(), "dash": pm.dash, "inline": inline, "slots": Array(pm.classic_slots),
			"styles": styles, "cooldown": pm.cooldown, "charges": pm.charges, "classes": _classes(d, pm, inline),
			"martial": not pm.martial.is_empty()}
		(out["order"] as Array).append(str(id))
	out["moves"] = moves
	for lk in c.loadouts:
		var lo: Dictionary = c.loadouts[lk]
		var ids := []
		for mid in lo.get("moves", []):
			ids.append(str(mid))
		(out["loadouts"] as Dictionary)[str(lk)] = {"name": str(lo.get("name", str(lk).capitalize())), "moves": ids}
		(out["loadout_order"] as Array).append(str(lk))
	out["default"] = c.default_loadout
	return out


## The move classes a pool move reports while it runs (hooks' move_class; the heavy fallback).
static func _classes(d: Dictionary, pm: PoolMove, inline: bool) -> Array:
	var out := []
	if inline:
		var md: Dictionary = (d["movepool"][pm.id] as Dictionary).get("move", {})
		out.append(str(md.get("class", "light" if pm.role == "basic" else ("heavy" if pm.role == "heavy" else "ability"))))
		return out
	for slot in pm.classic_slots:
		var c := UpgradeTranslation._slot_class(d, str(slot))
		if not out.has(c):
			out.append(c)
	return out


static func move_info(catalog: CampaignCatalog, fighter: String, id: String) -> Dictionary:
	return (info(catalog, fighter).get("moves", {}) as Dictionary).get(id, {})


static func move_name(catalog: CampaignCatalog, fighter: String, id: String) -> String:
	return str(move_info(catalog, fighter, id).get("name", id.capitalize()))


static func style_name(catalog: CampaignCatalog, fighter: String, id: String, style: String) -> String:
	return str((move_info(catalog, fighter, id).get("styles", {}) as Dictionary).get(style, {}).get("name", style.capitalize()))


## One line for cards: "Stream · Scorch · cooldown 6 s · hold to keep it going".
static func move_facts(catalog: CampaignCatalog, fighter: String, id: String) -> String:
	var mv := move_info(catalog, fighter, id)
	if mv.is_empty():
		return ""
	var facts := PackedStringArray()
	facts.append("Basic strike" if str(mv.get("role", "")) == "basic" else str(mv.get("category", "")).capitalize())
	if str(mv.get("element", "")) != "":
		facts.append(str(mv["element"]).capitalize())
	if float(mv.get("cooldown", 0.0)) > 0.0:
		facts.append("cooldown %.0f s" % float(mv["cooldown"]))
	match str(mv.get("hold", "")):
		"charge":
			facts.append("hold to charge")
		"sustain":
			facts.append("hold to keep it going")
	return " · ".join(facts)


# =============================================================================================
# A player's moves
# =============================================================================================

## The starting moves of a new run: the recommended loadouts combined, the default one equipped.
static func start_moves(catalog: CampaignCatalog, fighter: String) -> Dictionary:
	var inf := info(catalog, fighter)
	var learned := []
	for lk in inf.get("loadout_order", []):
		for id in (inf["loadouts"][lk] as Dictionary).get("moves", []):
			if not learned.has(str(id)) and (inf["moves"] as Dictionary).has(str(id)):
				learned.append(str(id))
	var equipped := []
	var lo: Dictionary = (inf.get("loadouts", {}) as Dictionary).get(str(inf.get("default", "")), {})
	for id2 in lo.get("moves", []):
		if (inf["moves"] as Dictionary).has(str(id2)):
			equipped.append(str(id2))
	return {"learned": learned, "equipped": equipped, "drilled": {}}


## The player's moves block (a normalized copy: empty lists when absent).
static func moves_of(player: Dictionary) -> Dictionary:
	var m = player.get("moves", {})
	var md: Dictionary = m if typeof(m) == TYPE_DICTIONARY else {}
	var learned: Array = md.get("learned", []) if typeof(md.get("learned")) == TYPE_ARRAY else []
	var equipped: Array = md.get("equipped", []) if typeof(md.get("equipped")) == TYPE_ARRAY else []
	var drilled: Dictionary = md.get("drilled", {}) if typeof(md.get("drilled")) == TYPE_DICTIONARY else {}
	return {"learned": learned, "equipped": equipped, "drilled": drilled}


## The run's moves block of a player, created when missing (older runs get theirs by migration).
static func block(player: Dictionary) -> Dictionary:
	if typeof(player.get("moves")) != TYPE_DICTIONARY:
		player["moves"] = {"learned": [], "equipped": [], "drilled": {}}
	var m: Dictionary = player["moves"]
	for k in ["learned", "equipped"]:
		if typeof(m.get(k)) != TYPE_ARRAY:
			m[k] = []
	if typeof(m.get("drilled")) != TYPE_DICTIONARY:
		m["drilled"] = {}
	return m


static func is_movesets(state: Dictionary) -> bool:
	return str(state.get("combat", "moves")) != "classic"


## Pool moves the player has not learned yet (pool order).
static func learnable(catalog: CampaignCatalog, player: Dictionary) -> Array:
	var inf := info(catalog, str(player.get("fighter", "")))
	var learned: Array = moves_of(player)["learned"]
	var out := []
	for id in inf.get("order", []):
		if not learned.has(str(id)):
			out.append(str(id))
	return out


## Learned moves that have styles and are not drilled yet: equipped ones first (slot order), then
## the others (pool order).
static func drillable(catalog: CampaignCatalog, player: Dictionary) -> Array:
	var inf := info(catalog, str(player.get("fighter", "")))
	var m := moves_of(player)
	var out := []
	var ordered: Array = (m["equipped"] as Array).duplicate()
	for id in inf.get("order", []):
		if not ordered.has(str(id)):
			ordered.append(str(id))
	for id2 in ordered:
		var mv: Dictionary = (inf.get("moves", {}) as Dictionary).get(str(id2), {})
		if (m["learned"] as Array).has(str(id2)) and not (m["drilled"] as Dictionary).has(str(id2)) and not (mv.get("styles", {}) as Dictionary).is_empty():
			out.append(str(id2))
	return out


static func has_role(inf: Dictionary, ids: Array, role: String) -> bool:
	for id in ids:
		if str((inf.get("moves", {}) as Dictionary).get(str(id), {}).get("role", "")) == role:
			return true
	return false


## Why `ids` cannot be equipped ("" when it can): learned moves only, and a valid loadout for the
## fighter (CreatureDef.loadout_problem; a recommended loadout always is).
static func loadout_problem(catalog: CampaignCatalog, player: Dictionary, ids: Array) -> String:
	var fighter := str(player.get("fighter", ""))
	var inf := info(catalog, fighter)
	if inf.get("def") == null:
		return "your fighter is not installed"
	var learned: Array = moves_of(player)["learned"]
	for id in ids:
		if typeof(id) != TYPE_STRING and typeof(id) != TYPE_STRING_NAME:
			return "a loadout lists move ids"
		if not learned.has(str(id)):
			return "%s is not learned" % move_name(catalog, fighter, str(id))
	for lk in inf.get("loadouts", {}):
		if (inf["loadouts"][lk] as Dictionary).get("moves", []) == ids:
			return ""
	return (inf["def"] as CreatureDef).loadout_problem(ids)


## The loadout a player fights with: the equipped moves the pool still has ([] = the fighter's
## default, as MatchSim resolves it).
static func fight_loadout(catalog: CampaignCatalog, player: Dictionary) -> Array:
	var inf := info(catalog, str(player.get("fighter", "")))
	var out := []
	for id in moves_of(player)["equipped"]:
		if (inf.get("moves", {}) as Dictionary).has(str(id)):
			out.append(str(id))
	if out.is_empty() or (inf.get("def") != null and loadout_problem(catalog, player, out) != ""):
		var lo: Dictionary = (inf.get("loadouts", {}) as Dictionary).get(str(inf.get("default", "")), {})
		return (lo.get("moves", []) as Array).duplicate()
	return out


## The drilled styles as build packages (applied before every upgrade: a style shapes the move,
## upgrades then improve it): [{source, patches}].
static func drill_packages(catalog: CampaignCatalog, player: Dictionary) -> Array:
	var inf := info(catalog, str(player.get("fighter", "")))
	var out := []
	var drilled: Dictionary = moves_of(player)["drilled"]
	for id in drilled:
		var st: Dictionary = ((inf.get("moves", {}) as Dictionary).get(str(id), {}).get("styles", {}) as Dictionary).get(str(drilled[id]), {})
		if not st.is_empty():
			out.append({"source": "drill:%s:%s" % [id, drilled[id]], "patches": st.get("patch", [])})
	return out


# =============================================================================================
# Offers (deterministic per run seed + stream key)
# =============================================================================================

## A move tutor / training / event pick: `n` distinct moves the player has not learned.
static func tutor_offer(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, key: String, n: int) -> Array:
	var rng := RunRng.stream(int(state.get("seed", 1)), key)
	return rng.pick_distinct(learnable(catalog, player), n)


## A drill pick: up to `n_moves` learned moves (equipped ones first), each with all its styles, as
## "move:style" option ids.
static func drill_offer(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, key: String, n_moves: int) -> Array:
	var rng := RunRng.stream(int(state.get("seed", 1)), key)
	var equipped: Array = moves_of(player)["equipped"]
	var mine := []
	var others := []
	for id in drillable(catalog, player):
		if equipped.has(id):
			mine.append(id)
		else:
			others.append(id)
	var picked := rng.pick_distinct(mine, n_moves)
	if picked.size() < n_moves:
		picked.append_array(rng.pick_distinct(others, n_moves - picked.size()))
	var inf := info(catalog, str(player.get("fighter", "")))
	var out := []
	for id2 in picked:
		for sid in ((inf["moves"] as Dictionary).get(str(id2), {}).get("styles", {}) as Dictionary):
			out.append("%s:%s" % [id2, sid])
	return out


## "move:style" -> [move, style].
static func split_drill(option: String) -> Array:
	var i := option.find(":")
	if i <= 0:
		return [option, ""]
	return [option.substr(0, i), option.substr(i + 1)]


# =============================================================================================
# Upgrades and moves: texts and offer weights
# =============================================================================================

## The apply block of an owned-item id (supplement, side effect, technique) or Cannery upgrade.
static func apply_of(catalog: CampaignCatalog, item_id: String) -> Dictionary:
	var it := catalog.item(item_id)
	if not it.is_empty():
		return it.get("apply", {}) if typeof(it.get("apply")) == TYPE_DICTIONARY else {}
	var m: Dictionary = catalog.meta.get(item_id, {})
	return m.get("per_level", {}) if typeof(m.get("per_level")) == TYPE_DICTIONARY else {}


## UpgradeTranslation.analyze for this player's fighter, style and loadout (cached per catalog).
static func analysis(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, item_id: String, apply: Dictionary = {}) -> Dictionary:
	var fighter := str(player.get("fighter", ""))
	var combat := "moves" if is_movesets(state) else "classic"
	var lo := fight_loadout(catalog, player) if combat == "moves" else []
	var key := "an|%s|%s|%s|%s" % [fighter, item_id, combat, ",".join(PackedStringArray(lo))]
	if item_id != "" and catalog.moves_cache.has(key):
		return catalog.moves_cache[key]
	var ap := apply if not apply.is_empty() else apply_of(catalog, item_id)
	var res := UpgradeTranslation.analyze(info(catalog, fighter), ap, combat, lo)
	if item_id != "":
		catalog.moves_cache[key] = res
	return res


## The moves an upgrade improves for this player: [{id, name, equipped}] (equipped first).
## [] for an upgrade that only changes the fighter as a whole (HP, stamina, Hype...).
static func improves(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, item_id: String, apply: Dictionary = {}) -> Array:
	if not is_movesets(state):
		return []
	var a := analysis(catalog, state, player, item_id, apply)
	var fighter := str(player.get("fighter", ""))
	var equipped: Array = fight_loadout(catalog, player)
	var on := []
	var off := []
	for id in info(catalog, fighter).get("order", []):
		if not (a["moves"] as Dictionary).has(str(id)):
			continue
		var row := {"id": str(id), "name": move_name(catalog, fighter, str(id)), "equipped": equipped.has(str(id))}
		if bool(row["equipped"]):
			on.append(row)
		else:
			off.append(row)
	return on + off


## "Improves: Furnace Haymaker, Ember Jab (not equipped: Hydro Cannon)" ("" = fighter-wide only).
static func improves_text(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, item_id: String, apply: Dictionary = {}) -> String:
	var rows := improves(catalog, state, player, item_id, apply)
	if rows.is_empty():
		return ""
	var on := PackedStringArray()
	var off := PackedStringArray()
	for r in rows:
		if bool(r["equipped"]):
			on.append(str(r["name"]))
		else:
			off.append(str(r["name"]))
	if on.is_empty():
		return "Improves (not equipped): %s" % ", ".join(off)
	if off.is_empty():
		return "Improves: %s" % ", ".join(on)
	return "Improves: %s (not equipped: %s)" % [", ".join(on), ", ".join(off)]


## How strongly a reward or shop offer favours an upgrade for this player (multiplies its weight):
## Movesets - 1.4 when it improves an equipped move, 0.6 when it only improves moves that are not
## equipped (techniques only), 1 for a fighter-wide upgrade. Supplements that improve no equipped
## move and nothing fighter-wide are not offered. Classic - 1, or 0 when it changes nothing of the
## Classic kit and nothing fighter-wide.
static func offer_weight(catalog: CampaignCatalog, state: Dictionary, player: Dictionary, item_id: String) -> float:
	var a := analysis(catalog, state, player, item_id)
	if not bool(a["targeted"]):
		return 1.0
	var touched: Dictionary = a["moves"]
	if UpgradeTranslation.slot_level(info(catalog, str(player.get("fighter", ""))), "moves" if is_movesets(state) else "classic"):
		return 1.0 if not touched.is_empty() or bool(a["general"]) else 0.0
	if touched.is_empty():
		return 1.0 if bool(a["general"]) else 0.0
	for id in fight_loadout(catalog, player):
		if touched.has(str(id)):
			return 1.4
	if catalog.supplements.has(item_id):
		return 1.0 if bool(a["general"]) else 0.0
	return 0.6
