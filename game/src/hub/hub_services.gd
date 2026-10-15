class_name HubServices
extends RefCounted
## THE ONE adapter between the hub and the campaign module (FightCamp, CampaignFlow,
## CampaignCatalog, CampaignProgression, RunRng — owned by the campaign team; docs/CAMPAIGN_SYSTEMS.md,
## docs/HUB_SYSTEMS.md §9). Every station board, Snappington's desk, the Bookie's Table, the AI Lab
## terminal and the shop/rest previews go through here and nowhere else.
##
## Calls go straight to the campaign API (merged into main). Tests may inject a `backend` object
## with the same calls (stations, list_upgrades(profile, station), buy_upgrade(profile, id),
## run_options(profile), start_run(profile, choices)) to exercise the hub's purchase flow in
## isolation; without one, the real FightCamp/CampaignCatalog are used.

const STATION_NAMES := {"gym_floor": ["Gym Floor", "Granny's clipboard"], "med_bay": ["Med Bay", "Doc's chart"],
	"juice_bar": ["Juice Bar", "Needles' menu"], "office": ["Office", "Snappington's ledger"],
	"loading_dock": ["Loading Dock", "Ludlow's workbench"], "boiler_room": ["Boiler Room", "Teddy's ledger"]}

var state: HubState
var backend: Object = null
## Development stand-ins (CampaignFlow.make_catalog(true)): while fighter kits are still being
## authored the campaign treats them as unusable; stand-ins let a run start anyway (marked custom),
## exactly like the campaign menu's "ENABLE DEV STAND-INS".
var stand_ins := false
var _standin_catalog: CampaignCatalog = null


func _init(s: HubState, test_backend: Object = null) -> void:
	state = s
	backend = test_backend


## Whether the campaign services exist (always true since the campaign is part of the game; kept
## so the boards can still explain themselves if a stripped build ships without it).
func available() -> bool:
	return backend != null or catalog() != null


func unavailable_reason() -> String:
	return "The Commission's paperwork hasn't arrived: this build has no campaign content, so upgrades, fight cards and the Bookie's Table are closed for now."


func catalog() -> CampaignCatalog:
	if stand_ins:
		if _standin_catalog == null:
			_standin_catalog = CampaignFlow.make_catalog(true)
		return _standin_catalog
	return CampaignCatalog.shared()


func stations() -> Array:
	if backend:
		return backend.call("stations")
	return FightCamp.stations()


static func station_name(id: String) -> String:
	return str(STATION_NAMES.get(id, [id.capitalize()])[0])


static func station_prop(id: String) -> String:
	return str(STATION_NAMES.get(id, ["", id.capitalize()])[1])


## Rows for a station board: {id, name, effect, level, max_level, next_cost, maxed, locked, lock_reason, affordable}
func list_upgrades(station: String) -> Array:
	if backend:
		return backend.call("list_upgrades", state.profile, station)
	return FightCamp.list_upgrades(catalog(), state.profile, station)


## Spends Clout on the next level. {ok, error, level, clout}. The caller saves the profile.
func buy_upgrade(id: String) -> Dictionary:
	var r: Dictionary
	if backend:
		r = backend.call("buy_upgrade", state.profile, id)
	else:
		r = FightCamp.buy_upgrade(catalog(), state.profile, id)
	if bool(r.get("ok", false)):
		state.dirty = true
		state.changed.emit("upgrade", {"id": id, "level": int(r.get("level", 0))})
	return r


## What Snappington's desk offers: {fighters, difficulties: [{id, name, desc, dose_allowed}],
## max_dose, doses: [{level, name}], clout}. Doses are only offered on difficulties that take
## them (never Sparring) — the sign-up sheet filters by `dose_allowed`.
func run_options() -> Dictionary:
	if backend:
		return backend.call("run_options", state.profile)
	var cat := catalog()
	var o := FightCamp.run_options(cat, state.profile, "fight_camp")
	var diffs := []
	for did in o.get("difficulties", []):
		var d := cat.difficulty(str(did))
		diffs.append({"id": str(did), "name": str(d.get("name", did)), "desc": str(d.get("desc", "")),
			"dose_allowed": bool(d.get("dose_allowed", true))})
	o["difficulties"] = diffs
	var doses := [{"level": 0, "name": "Base card"}]
	for lv in range(1, int(o.get("max_dose", 0)) + 1):
		doses.append({"level": lv, "name": "Dose %d: %s" % [lv, str(cat.dose(lv).get("name", ""))]})
	o["doses"] = doses
	return o


## The Fight Camp run config Snappington's desk would start (FightCamp.run_config).
func run_config(choices: Dictionary) -> Dictionary:
	var seed_value := 0
	var st := str(choices.get("seed_text", "")).strip_edges()
	if st != "":
		seed_value = RunRng.text_to_seed(st)
	var cfg := FightCamp.run_config(state.profile, {"variant": "fight_camp", "fighter": str(choices.get("fighter", "")),
		"difficulty": str(choices.get("difficulty", "amateur")), "dose": int(choices.get("dose", 0)), "seed": seed_value,
		"coop_format": str(choices.get("coop_format", "simultaneous")), "custom_reasons": CampaignFlow.custom_reasons(stand_ins)})
	cfg["content_hash"] = Content.content_hash()
	return cfg


## The Fight Camp run suspended in this profile's slot ({} if none): {slot, ok, error, summary}.
func suspended_run() -> Dictionary:
	if backend:
		return backend.call("suspended_run", state.profile) if backend.has_method("suspended_run") else {}
	return CampaignFlow.suspended_run(catalog(), "fight_camp")


## Starts a Fight Camp run from Snappington's desk. choices: {fighter, difficulty, dose,
## seed_text, coop_format, replace_suspended}. There is one suspended Fight Camp run per profile:
## while one exists this returns {ok: false, needs_confirm: true, suspended} and starts nothing;
## with replace_suspended the old run is credited as abandoned first. Leaves the hub (the
## campaign flow takes over the screen). Returns {ok, error}.
func start_run(choices: Dictionary) -> Dictionary:
	if backend:
		return backend.call("start_run", state.profile, choices)
	if str(choices.get("fighter", "")) == "":
		return {"ok": false, "error": "Pick a fighter first."}
	var held := suspended_run()
	if bool(held.get("newer", false)):
		# a newer game version's run is never replaced, moved or deleted
		return {"ok": false, "error": "Your suspended Fight Camp run was saved by a newer version of the game. It stays as it is; play it with that version."}
	if not held.is_empty() and not bool(choices.get("replace_suspended", false)):
		return {"ok": false, "needs_confirm": true, "suspended": held,
			"error": "You already have a suspended Fight Camp run. Resume it, or abandon it to sign a new card."}
	var cfg := run_config(choices)
	if not held.is_empty():
		CampaignFlow.abandon_suspended(catalog(), str(held["slot"]))
	Profiles.save()
	App.set_scene(null)
	var f := CampaignFlow.start(catalog(), cfg)
	f.show_current()
	return {"ok": true, "error": ""}


## Resumes the suspended Fight Camp run (leaves the hub). Returns {ok, error}.
func resume_run() -> Dictionary:
	if backend:
		return backend.call("resume_run", state.profile) if backend.has_method("resume_run") else {"ok": false, "error": "unavailable"}
	var res := RunStore.new().load_slot(CampaignFlow.profile_key(), "fight_camp", catalog())
	if not bool(res["ok"]):
		return {"ok": false, "error": str(res["error"])}
	Profiles.save()
	App.set_scene(null)
	CampaignFlow.resume(catalog(), res["state"]).show_current()
	return {"ok": true, "error": ""}


## The full campaign menu for Fight Camp (suspended runs, the Ledger, co-op lobby).
func open_campaign_menu() -> void:
	Profiles.save()
	App.set_scene(null)
	App.goto("campaign_menu", {"variant": "fight_camp"})


## Needles' shop preview: a few supplements with their run prices (read-only outside a run).
func shop_preview() -> Array:
	var out := []
	var cat := catalog()
	for rarity in ["otc", "prescription", "black_market"]:
		var ids := cat.supplement_ids_of_rarity(rarity)
		for i in mini(2, ids.size()):
			var id := str(ids[i])
			var it := cat.item(id)
			out.append({"id": id, "name": cat.item_name(id), "rarity": rarity, "price": cat.price_of(id),
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
	App.goto("bookie", {"from_hub": true, "stand_ins": stand_ins})
	return true


## The AI Lab terminal (the Lab owner's screen). Leaves the hub. false when absent.
func open_lab() -> bool:
	if not App.has_screen("lab"):
		return false
	Profiles.save()
	App.set_scene(null)
	App.goto("lab", {"from_hub": true, "boiler_room_key": state.upgrade_level("meta_boiler_room_key") > 0})
	return true
