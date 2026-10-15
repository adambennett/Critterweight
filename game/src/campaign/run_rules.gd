class_name RunRules
extends RefCounted
## Resolves the effective run-level rules ("run" modifiers) for a run and optionally one player:
##   difficulty preset (enemy HP/damage, bot tier, reward multipliers, Sparring rest heal)
##   x every Dose level <= the run's Dose (cumulative, CAMPAIGN.md §9)
##   x the player's own build packages that carry "run" entries (supplements, techniques,
##     side effects, Fight Camp upgrades, event outcomes) — economy is per player in co-op.
## Keys and identity values: CampaignCatalog.RUN_DEFAULTS. Pure function of (catalog, state).


static func compute(catalog: CampaignCatalog, state: Dictionary, player: Dictionary = {}) -> Dictionary:
	var r: Dictionary = CampaignCatalog.RUN_DEFAULTS.duplicate(true)
	var diff := catalog.difficulty(str(state.get("difficulty", "amateur")))
	r["enemy_hp_mult"] = float(diff.get("enemy_hp", 1.0))
	r["enemy_damage_mult"] = float(diff.get("enemy_damage", 1.0))
	r["bot_tier"] = str(diff.get("bot_tier", "journeyman"))
	r["scrip_mult"] = float(diff.get("scrip_mult", 1.0))
	r["clout_mult"] = float(diff.get("clout_mult", 1.0))
	r["rest_heal_override"] = float(diff.get("rest_heal", 0.0))
	var dose_level := int(state.get("dose", 0))
	for l in range(1, dose_level + 1):
		apply_entries(r, catalog.dose(l).get("run", []))
	if not player.is_empty():
		for pkg in BuildApplier.packages(catalog, state, player, false):
			apply_entries(r, pkg.get("apply", {}).get("run", []), int(pkg.get("level", 1)))
	return r


## Applies [{key, mul|add|set}] entries. `level` scales mul/add linearly (meta upgrade levels).
static func apply_entries(r: Dictionary, entries: Array, level := 1) -> void:
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var key := str(e.get("key", ""))
		if key == "":
			continue
		if e.has("set"):
			r[key] = e["set"]
		elif e.has("mul"):
			var m := 1.0 + (float(e["mul"]) - 1.0) * level
			r[key] = float(r.get(key, 1.0)) * m
		elif e.has("add"):
			r[key] = float(r.get(key, 0.0)) + float(e["add"]) * level


## Bot tier id for enemies of this run ("" falls back to the difficulty's tier).
static func bot_tier(catalog: CampaignCatalog, state: Dictionary) -> String:
	var r := compute(catalog, state)
	var t := str(r.get("bot_tier", ""))
	return t if t != "" else "journeyman"
