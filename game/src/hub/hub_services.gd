class_name HubServices
extends RefCounted
## THE ONE adapter between the hub and the campaign module (FightCamp, CampaignFlow,
## CampaignCatalog, RunRng — owned by the campaign team, docs/HUB_SYSTEMS.md §9). Every station
## board, Snappington's desk, the Bookie's Table, the AI Lab terminal and the shop/rest previews go
## through here and nowhere else.
##
## The campaign classes are looked up by name in the global class list and called dynamically,
## so this branch compiles and runs without them: when they are absent `available()` is false and
## `unavailable_reason()` is the in-world explanation the boards show. Tests can inject a backend
## object with the same calls (stations, list_upgrades, buy_upgrade, run_options, start_run).
##
## FightCamp API used (campaign branch): stations(); list_upgrades(catalog, profile, station);
## buy_upgrade(catalog, profile, id); run_options(catalog, profile, variant); run_config(profile,
## choices); services(). CampaignFlow.make_catalog(stand_ins), CampaignFlow.start(catalog, cfg)
## .show_current(), CampaignFlow.custom_reasons(stand_ins). RunRng.text_to_seed(text).

const STATION_NAMES := {"gym_floor": ["Gym Floor", "Granny's clipboard"], "med_bay": ["Med Bay", "Doc's chart"],
	"juice_bar": ["Juice Bar", "Needles' menu"], "office": ["Office", "Snappington's ledger"],
	"loading_dock": ["Loading Dock", "Ludlow's workbench"], "boiler_room": ["Boiler Room", "Teddy's ledger"]}

var state: HubState
var backend: Object = null
var _catalog = null
static var _scripts := {}


func _init(s: HubState, test_backend: Object = null) -> void:
	state = s
	backend = test_backend


static func script_of(cls: String) -> GDScript:
	if _scripts.has(cls):
		return _scripts[cls]
	var found: GDScript = null
	for e in ProjectSettings.get_global_class_list():
		if str(e.get("class", "")) == cls:
			var p := str(e.get("path", ""))
			if ResourceLoader.exists(p):
				found = load(p)
			break
	_scripts[cls] = found
	return found


## Whether the campaign services exist in this build (or a test backend is injected).
func available() -> bool:
	return backend != null or (script_of("FightCamp") != null and script_of("CampaignFlow") != null)


func unavailable_reason() -> String:
	return "The Commission's paperwork hasn't arrived: this build has no campaign module, so upgrades, fight cards and the Bookie's Table are closed for now."


func catalog():
	if _catalog == null and backend == null:
		var flow := script_of("CampaignFlow")
		if flow:
			_catalog = flow.call("make_catalog", false)
	return _catalog


func stations() -> Array:
	if backend:
		return backend.call("stations")
	var fc := script_of("FightCamp")
	if fc:
		return fc.call("stations")
	var out := []
	for id in STATION_NAMES:
		out.append({"id": id, "name": STATION_NAMES[id][0], "prop": STATION_NAMES[id][1]})
	return out


static func station_name(id: String) -> String:
	return str(STATION_NAMES.get(id, [id.capitalize()])[0])


static func station_prop(id: String) -> String:
	return str(STATION_NAMES.get(id, ["", id.capitalize()])[1])


## Rows for a station board: {id, name, effect, level, max_level, next_cost, maxed, locked, lock_reason, affordable}
func list_upgrades(station: String) -> Array:
	if backend:
		return backend.call("list_upgrades", state.profile, station)
	var fc := script_of("FightCamp")
	if fc == null or catalog() == null:
		return []
	return fc.call("list_upgrades", catalog(), state.profile, station)


## Spends Clout on the next level. {ok, error, level, clout}. The caller saves the profile.
func buy_upgrade(id: String) -> Dictionary:
	var r: Dictionary = {}
	if backend:
		r = backend.call("buy_upgrade", state.profile, id)
	else:
		var fc := script_of("FightCamp")
		if fc == null or catalog() == null:
			return {"ok": false, "error": unavailable_reason()}
		r = fc.call("buy_upgrade", catalog(), state.profile, id)
	if bool(r.get("ok", false)):
		state.dirty = true
		state.changed.emit("upgrade", {"id": id, "level": int(r.get("level", 0))})
	return r


## What Snappington's desk offers: {fighters, difficulties: [{id, name, desc}], max_dose, doses: [{level, name}], clout}
func run_options() -> Dictionary:
	if backend:
		return backend.call("run_options", state.profile)
	var fc := script_of("FightCamp")
	var cat = catalog()
	if fc == null or cat == null:
		return {}
	var o: Dictionary = fc.call("run_options", cat, state.profile, "fight_camp")
	var diffs := []
	for did in o.get("difficulties", []):
		var d: Dictionary = cat.call("difficulty", str(did))
		diffs.append({"id": str(did), "name": str(d.get("name", did)), "desc": str(d.get("desc", ""))})
	o["difficulties"] = diffs
	var doses := [{"level": 0, "name": "Base card"}]
	for lv in range(1, int(o.get("max_dose", 0)) + 1):
		var dd: Dictionary = cat.call("dose", lv)
		doses.append({"level": lv, "name": "Dose %d: %s" % [lv, str(dd.get("name", ""))]})
	o["doses"] = doses
	return o


## Starts a Fight Camp run from Snappington's desk. choices: {fighter, difficulty, dose, seed_text, coop_format}.
## Leaves the hub (the campaign flow takes over the screen). Returns {ok, error}.
func start_run(choices: Dictionary) -> Dictionary:
	if backend:
		return backend.call("start_run", state.profile, choices)
	var fc := script_of("FightCamp")
	var flow := script_of("CampaignFlow")
	if fc == null or flow == null or catalog() == null:
		return {"ok": false, "error": unavailable_reason()}
	var seed_value := 0
	var st := str(choices.get("seed_text", "")).strip_edges()
	if st != "":
		var rng := script_of("RunRng")
		seed_value = int(rng.call("text_to_seed", st)) if rng else hash(st)
	var cfg: Dictionary = fc.call("run_config", state.profile, {"variant": "fight_camp", "fighter": str(choices.get("fighter", "")),
		"difficulty": str(choices.get("difficulty", "amateur")), "dose": int(choices.get("dose", 0)), "seed": seed_value,
		"coop_format": str(choices.get("coop_format", "simultaneous")), "custom_reasons": flow.call("custom_reasons", false)})
	cfg["content_hash"] = Content.content_hash()
	cfg["from_hub"] = true
	Profiles.save()
	App.set_scene(null)
	var f = flow.call("start", catalog(), cfg)
	f.call("show_current")
	return {"ok": true, "error": ""}


## Needles' shop preview: a few supplements with their run prices (read-only outside a run).
func shop_preview() -> Array:
	var out := []
	var cat = catalog()
	if cat == null:
		return out
	for rarity in ["otc", "prescription", "black_market"]:
		var ids: Array = cat.call("supplement_ids_of_rarity", rarity)
		for i in mini(2, ids.size()):
			var id := str(ids[i])
			var it: Dictionary = cat.call("item", id)
			out.append({"id": id, "name": str(it.get("name", id)), "rarity": rarity, "price": int(cat.call("price_of", id)),
				"desc": str(it.get("desc", it.get("description", it.get("effect", ""))))})
	return out


func has_screen(nm: String) -> bool:
	return App.has_screen(nm)


## The Bookie's Table (the campaign's autobattler screen). Leaves the hub. false when absent.
func open_bookie() -> bool:
	if not App.has_screen("bookie"):
		return false
	Profiles.save()
	App.set_scene(null)
	App.goto("bookie", {"from_hub": true})
	return true


## The AI Lab terminal (the Lab owner's screen). Leaves the hub. false when absent.
func open_lab() -> bool:
	if not App.has_screen("lab"):
		return false
	Profiles.save()
	App.set_scene(null)
	App.goto("lab", {"from_hub": true, "boiler_room_key": state.upgrade_level("meta_boiler_room_key") > 0})
	return true
