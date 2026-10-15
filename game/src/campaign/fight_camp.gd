class_name FightCamp
extends RefCounted
## The data + services The Cannery hub calls (HUB.md; the 3D hub level is built elsewhere).
## Every function works on a profile Dictionary (Profiles.current at runtime) and returns plain
## data, so the hub's diegetic boards, a menu fallback (camp_ledger screen) and tests share it.
##   stations()                         -> the six upgrade stations with their NPCs
##   list_upgrades(cat, profile, station) -> rows for a station board (level, next cost, lock)
##   buy_upgrade(cat, profile, id)      -> spends Clout, raises the level, sets unlock flags
##   run_options(cat, profile)          -> what Snappington's desk offers (fighters, Doses, ...)
##   run_config(profile, choices)       -> a RunController/CampaignFlow start config
##   services()                         -> NPC services the hub exposes (shop/rest previews...)
##   gym_bonus_package(cat, profile, fighter) -> meta mods/patches for custom matches that
##                                         visibly enable "Gym Bonuses" (never PvP/standard).
## Cannery upgrades are tagged meta_bonus and only BuildApplier applies them, only for Fight
## Camp runs (or that explicit custom rule) — this API never grants power anywhere else.

const STATIONS := [
	{"id": "gym_floor", "name": "Gym Floor", "npc": "Granny Haymaker", "where": "Main Floor", "prop": "Granny's clipboard"},
	{"id": "med_bay", "name": "Med Bay", "npc": "Doc Sutura", "where": "Med Bay", "prop": "Doc's chart"},
	{"id": "juice_bar", "name": "Juice Bar", "npc": "Needles", "where": "Juice Bar", "prop": "Needles' menu"},
	{"id": "office", "name": "Office", "npc": "Commissioner Snappington", "where": "Commissioner's Office", "prop": "Snappington's ledger"},
	{"id": "loading_dock", "name": "Loading Dock", "npc": "Ludlow", "where": "Loading Dock", "prop": "Ludlow's workbench"},
	{"id": "boiler_room", "name": "Boiler Room", "npc": "Teddy Two-Tooth", "where": "Boiler Room", "prop": "Teddy's ledger"},
]


static func stations() -> Array:
	return STATIONS.duplicate(true)


static func level_of(profile: Dictionary, id: String) -> int:
	return int(profile.get("camp", {}).get("upgrades", {}).get(id, 0))


## [unlocked, reason]
static func gate_open(catalog: CampaignCatalog, profile: Dictionary, id: String) -> Array:
	var m: Dictionary = catalog.meta.get(id, {})
	var gate: Dictionary = m.get("gate", {})
	if gate.is_empty():
		return [true, ""]
	CampaignProgression.ensure_fields(profile)
	if gate.has("flag") and not bool(profile["camp"]["flags"].get(str(gate["flag"]), false)):
		return [false, str(gate.get("text", "Locked"))]
	if gate.has("dose_cleared") and int(profile["ladder"]["fight_camp"].get("cleared", 0)) < int(gate["dose_cleared"]):
		return [false, str(gate.get("text", "Locked"))]
	return [true, ""]


static func list_upgrades(catalog: CampaignCatalog, profile: Dictionary, station := "") -> Array:
	CampaignProgression.ensure_fields(profile)
	var out := []
	var clout := int(profile["camp"].get("clout", 0))
	for id in catalog.meta_ids_for_station(station):
		var m: Dictionary = catalog.meta[id]
		var costs: Array = m.get("costs", [])
		var lv := level_of(profile, id)
		var maxed := lv >= costs.size()
		var next_cost := -1 if maxed else int(costs[lv])
		var gate := gate_open(catalog, profile, id)
		out.append({"id": id, "name": str(m.get("name", id)), "station": str(m.get("station", "")), "effect": str(m.get("effect", "")),
			"level": lv, "max_level": costs.size(), "next_cost": next_cost, "maxed": maxed, "locked": not bool(gate[0]),
			"lock_reason": str(gate[1]), "affordable": not maxed and bool(gate[0]) and clout >= next_cost})
	return out


## Spends Clout on the next level of an upgrade. Returns {ok, error, level, clout}.
static func buy_upgrade(catalog: CampaignCatalog, profile: Dictionary, id: String) -> Dictionary:
	CampaignProgression.ensure_fields(profile)
	var m: Dictionary = catalog.meta.get(id, {})
	if m.is_empty():
		return {"ok": false, "error": "unknown upgrade '%s'" % id}
	var gate := gate_open(catalog, profile, id)
	if not bool(gate[0]):
		return {"ok": false, "error": "locked: %s" % gate[1]}
	var costs: Array = m.get("costs", [])
	var lv := level_of(profile, id)
	if lv >= costs.size():
		return {"ok": false, "error": "already at max level"}
	var cost := int(costs[lv])
	var clout := int(profile["camp"].get("clout", 0))
	if clout < cost:
		return {"ok": false, "error": "not enough Clout (%d / %d)" % [clout, cost]}
	profile["camp"]["clout"] = clout - cost
	profile["camp"]["upgrades"][id] = lv + 1
	for fl in m.get("flags", []):
		profile["camp"]["flags"][str(fl)] = true
	return {"ok": true, "error": "", "level": lv + 1, "clout": clout - cost}


## The player's owned levels, as copied into a Fight Camp run at its start.
static func meta_levels(profile: Dictionary) -> Dictionary:
	return (profile.get("camp", {}).get("upgrades", {}) as Dictionary).duplicate()


static func run_options(catalog: CampaignCatalog, profile: Dictionary, variant := "fight_camp") -> Dictionary:
	CampaignProgression.ensure_fields(profile)
	return {"fighters": catalog.available_fighters(), "difficulties": catalog.difficulty_ids(),
		"max_dose": CampaignProgression.max_selectable_dose(profile, variant), "variant": variant,
		"clout": int(profile["camp"].get("clout", 0))}


## Run start config. choices: {fighter, difficulty, dose, seed, mode, coop_format, custom_reasons}
static func run_config(profile: Dictionary, choices: Dictionary) -> Dictionary:
	var variant := str(choices.get("variant", "fight_camp"))
	var cfg := {"variant": variant, "difficulty": str(choices.get("difficulty", "amateur")), "dose": int(choices.get("dose", 0)),
		"mode": str(choices.get("mode", "campaign")), "seed": int(choices.get("seed", 0)), "seeded": int(choices.get("seed", 0)) != 0,
		"coop_format": str(choices.get("coop_format", "simultaneous")), "created_at": int(Time.get_unix_time_from_system()),
		"custom": not (choices.get("custom_reasons", []) as Array).is_empty(), "custom_reasons": choices.get("custom_reasons", []),
		"players": [{"id": "p0", "name": str(profile.get("name", "Player")), "profile_id": str(profile.get("id", "")),
			"fighter": str(choices.get("fighter", "")), "meta": meta_levels(profile) if variant == "fight_camp" else {}}]}
	return cfg


static func services() -> Array:
	return [
		{"npc": "Commissioner Snappington", "station": "office", "service": "start_run", "label": "Sign up for a fight card"},
		{"npc": "Needles", "station": "juice_bar", "service": "shop_preview", "label": "Browse tonight's supplements"},
		{"npc": "Doc Sutura", "station": "med_bay", "service": "rest_preview", "label": "Ask about patch-ups"},
		{"npc": "Teddy Two-Tooth", "station": "boiler_room", "service": "bookie", "label": "Take a seat at The Bookie's Table"},
		{"npc": "Teddy Two-Tooth", "station": "boiler_room", "service": "ai_lab", "label": "AI Lab terminal"},
		{"npc": "Granny Haymaker", "station": "gym_floor", "service": "tutorial", "label": "Granny's corner"},
		{"npc": "Kid Lamprey", "station": "loading_dock", "service": "sparring", "label": "Ring sparring"},
	]


## Fight Camp upgrades as a build package for custom matches with the visible "Gym Bonuses" rule.
static func gym_bonus_package(catalog: CampaignCatalog, profile: Dictionary, fighter: String) -> Dictionary:
	var pseudo := {"id": "gym", "fighter": fighter, "meta": meta_levels(profile), "techniques": [], "supplements": [], "side_effects": []}
	var st := {"variant": "fight_camp", "dose": 0, "players": [pseudo]}
	return BuildApplier.compose(catalog, st, pseudo, {"party": "solo", "gym_bonuses": true})
