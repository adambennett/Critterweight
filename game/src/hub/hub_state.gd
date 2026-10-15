class_name HubState
extends RefCounted
## Fight Camp hub state stored in a profile dictionary (Profiles.current at runtime, a plain dict in
## tests). Owns the keys the hub adds; never saves by itself (`dirty` tells the scene to call
## Profiles.save()). Layout inside the profile:
##   camp.clout / clout_total / upgrades{id: level} / secrets[ids] / flags{} / hub_spot   (shared with FightCamp)
##   camp.hub = {discovered[], tour_done, visits, rewards{key: tier}, best{key: score}, bag_tiers{fighter: {bag: tier}},
##               spar{kid_contender, headliner[]}, parts[], hints[], loadout{fighter, cosmetics{slot: id}},
##               last_result, last_seen_run, boiler_hits, packs{}}
##   unlocks.cosmetics[]  (shared cosmetics list; hub cosmetics are prefixed "hub_")
## Time of day (HUB.md §6) follows the most recent Fight Camp run in profile.history:
## morning after a loss, evening after a win (a run that beat at least one boss), night after a title.

signal changed(kind: String, data: Dictionary)

const SECRETS := ["sec_loose_panel", "sec_crawlspace_tooth", "sec_sleeping_scrapling", "sec_belt_case_combo", "sec_booth_tape",
	"sec_freight_elevator", "sec_roof_sign", "sec_pier_ladder", "sec_boiler_face", "sec_doc_dumpster"]
const ELEVATOR_PARTS := ["fuse", "cable_spool", "button"]

var profile: Dictionary
var dirty := false


func _init(p: Dictionary = {}) -> void:
	profile = p
	ensure()


func ensure() -> void:
	if not profile.has("camp"):
		profile["camp"] = {}
	var c: Dictionary = profile["camp"]
	for k in ["clout", "clout_total"]:
		if not c.has(k):
			c[k] = 0
	for k2 in ["upgrades", "flags"]:
		if not c.has(k2) or typeof(c[k2]) != TYPE_DICTIONARY:
			c[k2] = {}
	if not c.has("secrets") or typeof(c["secrets"]) != TYPE_ARRAY:
		c["secrets"] = []
	if not c.has("hub_spot"):
		c["hub_spot"] = "main_floor"
	if not c.has("hub") or typeof(c["hub"]) != TYPE_DICTIONARY:
		c["hub"] = {}
	var h: Dictionary = c["hub"]
	var defaults := {"discovered": [], "tour_done": false, "visits": 0, "rewards": {}, "best": {}, "bag_tiers": {},
		"spar": {"kid_contender": false, "headliner": []}, "parts": [], "hints": [], "loadout": {"fighter": "", "cosmetics": {}},
		"last_result": "", "last_seen_run": "", "boiler_hits": 0, "packs": {}, "frames": []}
	for k3 in defaults:
		if not h.has(k3):
			h[k3] = defaults[k3].duplicate(true) if typeof(defaults[k3]) in [TYPE_DICTIONARY, TYPE_ARRAY] else defaults[k3]
	if not profile.has("unlocks") or typeof(profile["unlocks"]) != TYPE_DICTIONARY:
		profile["unlocks"] = {}
	if not (profile["unlocks"] as Dictionary).has("cosmetics"):
		profile["unlocks"]["cosmetics"] = []
	if not profile.has("history"):
		profile["history"] = []


func camp() -> Dictionary:
	return profile["camp"]


func hub() -> Dictionary:
	return profile["camp"]["hub"]


func _touch(kind: String, data := {}) -> void:
	dirty = true
	changed.emit(kind, data)


# ---- Clout --------------------------------------------------------------------------------

func clout() -> int:
	return int(camp().get("clout", 0))


func add_clout(n: int, reason := "") -> void:
	if n <= 0:
		return
	camp()["clout"] = clout() + n
	camp()["clout_total"] = int(camp().get("clout_total", 0)) + n
	_touch("clout", {"amount": n, "reason": reason, "total": clout()})


## Grants the Clout of every tier newly reached for `key` (tiers count from 1). Returns the Clout
## granted. `thresholds` and `rewards` are parallel arrays (e.g. [300, 600, 1000] / [10, 25, 50]).
func reward_tiers(key: String, score: float, thresholds: Array, rewards: Array, reason := "") -> Dictionary:
	var r: Dictionary = hub()["rewards"]
	var had := int(r.get(key, 0))
	var reached := 0
	for i in thresholds.size():
		if score >= float(thresholds[i]):
			reached = i + 1
	var gain := 0
	for t in range(had, reached):
		gain += int(rewards[t])
	if reached > had:
		r[key] = reached
	var best: Dictionary = hub()["best"]
	if score > float(best.get(key, 0.0)):
		best[key] = score
		dirty = true
	if gain > 0:
		add_clout(gain, reason)
	return {"tier": reached, "previous": had, "clout": gain}


func tier_of(key: String) -> int:
	return int((hub()["rewards"] as Dictionary).get(key, 0))


func best_of(key: String) -> float:
	return float((hub()["best"] as Dictionary).get(key, 0.0))


# ---- secrets, cosmetics, flags ----------------------------------------------------------------

func has_secret(id: String) -> bool:
	return (camp()["secrets"] as Array).has(id)


## Returns true when the secret was newly found.
func find_secret(id: String) -> bool:
	if has_secret(id):
		return false
	(camp()["secrets"] as Array).append(id)
	_touch("secret", {"id": id, "count": secrets_found()})
	return true


func secrets_found() -> int:
	return (camp()["secrets"] as Array).size()


func has_cosmetic(id: String) -> bool:
	return (profile["unlocks"]["cosmetics"] as Array).has(id)


func unlock_cosmetic(id: String) -> bool:
	if has_cosmetic(id):
		return false
	(profile["unlocks"]["cosmetics"] as Array).append(id)
	_touch("cosmetic", {"id": id})
	return true


func flag(k: String, fallback = false):
	return hub().get("f_" + k, fallback)


func set_flag(k: String, v) -> void:
	if hub().get("f_" + k) == v:
		return
	hub()["f_" + k] = v
	_touch("flag", {"key": k, "value": v})


# ---- upgrades (levels written by FightCamp.buy_upgrade through HubServices) -------------------

func upgrade_level(id: String) -> int:
	return int((camp()["upgrades"] as Dictionary).get(id, 0))


func upgrades_owned() -> int:
	var n := 0
	for k in camp()["upgrades"]:
		if int(camp()["upgrades"][k]) > 0:
			n += 1
	return n


func upgrade_levels_total() -> int:
	var n := 0
	for k in camp()["upgrades"]:
		n += int(camp()["upgrades"][k])
	return n


# ---- spaces / tour -------------------------------------------------------------------------

func discover(space_id: String) -> bool:
	var d: Array = hub()["discovered"]
	if d.has(space_id):
		return false
	d.append(space_id)
	var done := true
	for s in HubLayout.TOUR:
		if not d.has(s):
			done = false
	if done and not bool(hub()["tour_done"]):
		hub()["tour_done"] = true
	_touch("discover", {"space": space_id})
	return true


func discovered() -> Array:
	return hub()["discovered"]


func tour_done() -> bool:
	return bool(hub()["tour_done"])


func set_spot(space_id: String) -> void:
	if str(camp().get("hub_spot", "")) != space_id:
		camp()["hub_spot"] = space_id
		dirty = true


func spot() -> String:
	var s := str(camp().get("hub_spot", "main_floor"))
	return s if HubLayout.SPACES.has(s) else "main_floor"


# ---- elevator parts, hints, loadout ----------------------------------------------------------

func parts() -> Array:
	return hub()["parts"]


func give_part(id: String) -> bool:
	if parts().has(id):
		return false
	parts().append(id)
	_touch("part", {"id": id, "count": parts().size()})
	return true


func elevator_fixed() -> bool:
	return has_secret("sec_freight_elevator")


func hint_given(secret_id: String) -> bool:
	return (hub()["hints"] as Array).has(secret_id)


func mark_hint(secret_id: String) -> void:
	if not hint_given(secret_id):
		(hub()["hints"] as Array).append(secret_id)
		dirty = true


func loadout_fighter() -> String:
	return str((hub()["loadout"] as Dictionary).get("fighter", ""))


func set_loadout_fighter(id: String) -> void:
	hub()["loadout"]["fighter"] = id
	_touch("loadout", {"fighter": id})


func cosmetic_in(slot: String) -> String:
	return str(((hub()["loadout"] as Dictionary).get("cosmetics", {}) as Dictionary).get(slot, ""))


func equip(slot: String, id: String) -> void:
	var c: Dictionary = hub()["loadout"]["cosmetics"]
	if id == "":
		c.erase(slot)
	else:
		c[slot] = id
	_touch("loadout", {"slot": slot, "id": id})


func pack_on(id: String) -> bool:
	return bool((hub()["packs"] as Dictionary).get(id, false))


func set_pack(id: String, on: bool) -> void:
	hub()["packs"][id] = on
	_touch("pack", {"id": id, "on": on})


# ---- runs: last result, time of day, Wall of Fame ---------------------------------------------

## Fight Camp (and Off the Street) runs from the profile history, newest first (Bookie runs excluded).
func runs() -> Array:
	var out := []
	for e in profile.get("history", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		if str(d.get("kind", "")) == "campaign" and str(d.get("mode", "")) != "bookie":
			out.append(d)
	return out


## "title" (won the belt) | "win" (beat at least one boss) | "loss"
static func classify(run: Dictionary) -> String:
	if bool(run.get("victory", false)):
		return "title"
	if int(run.get("act", 1)) >= 2:
		return "win"
	return "loss"


func last_run() -> Dictionary:
	var r := runs()
	return r[0] if not r.is_empty() else {}


func last_result() -> String:
	var lr := last_run()
	if lr.is_empty():
		return "none"
	return classify(lr)


func time_of_day() -> String:
	match last_result():
		"title":
			return "night"
		"win":
			return "evening"
	return "morning"


## The Wall of Fame/Shame: one photo per run (newest first), at most 24.
func wall_photos() -> Array:
	var out := []
	for r in runs():
		if out.size() >= 24:
			break
		out.append({"result": classify(r), "fighter": str(r.get("fighter", "")), "act": int(r.get("act", 1)), "dose": int(r.get("dose", 0)),
			"variant": str(r.get("variant", "")), "kos": int(r.get("kos", 0)), "time": float(r.get("time", 0.0))})
	return out


## Spars (no stakes) still earn the documented one-time rewards.
func spar_record(opponent: String, tier: String, won: bool, fighter: String) -> Dictionary:
	var out := {"clout": 0, "badge": ""}
	if not won:
		return out
	var sp: Dictionary = hub()["spar"]
	if opponent == "kid_lamprey" and tier in ["contender", "headliner", "hall_of_famer"] and not bool(sp.get("kid_contender", false)):
		sp["kid_contender"] = true
		add_clout(25, "First win over Kid Lamprey at Contender")
		out["clout"] = 25
	if tier in ["headliner", "hall_of_famer"]:
		var badges: Array = sp["headliner"]
		if not badges.has(fighter):
			badges.append(fighter)
			out["badge"] = fighter
			unlock_cosmetic("hub_badge_headliner_%s" % fighter)
	dirty = true
	return out
