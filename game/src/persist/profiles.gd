extends Node
## Autoload "Profiles": local player profiles (no login). Each profile stores statistics, records,
## The Dosage ladder progress per campaign variant, cosmetic unlocks, Fight Camp meta progression
## (Clout, permanent upgrades, hub secrets/flags), tutorial state and recent run history.
## Persistent campaign power lives ONLY in `camp` and is never read by PvP/versus code (COOP-06).

signal profile_changed()

const VERSION := 1
const MAX_HISTORY := 60

var current := {}
var _index := {"profiles": [], "active": ""}
var last_error := ""


func _ready() -> void:
	_load_index()
	if _index["profiles"].is_empty():
		create("Rookie")
	else:
		switch_to(str(_index["active"]) if _index["active"] != "" else str(_index["profiles"][0]["id"]))


static func default_profile(id: String, name_: String) -> Dictionary:
	return {
		"id": id, "name": name_, "created": int(Time.get_unix_time_from_system()),
		"stats": {"matches": 0, "wins": 0, "losses": 0, "draws": 0, "kos": 0, "knockdowns": 0, "damage_dealt": 0.0,
			"time_played": 0.0, "per_fighter": {}},
		"records": {"best_win_streak": 0, "win_streak": 0, "fastest_ko": 0.0,
			"runs": {"off_the_street": {"attempts": 0, "clears": 0, "best_dose": 0}, "fight_camp": {"attempts": 0, "clears": 0, "best_dose": 0}}},
		"ladder": {"off_the_street": {"unlocked": 1, "cleared": 0}, "fight_camp": {"unlocked": 1, "cleared": 0}},
		"unlocks": {"cosmetics": [], "titles": [], "bookie_seats": 1},
		"camp": {"clout": 0, "clout_total": 0, "upgrades": {}, "secrets": [], "flags": {}, "hub_spot": "locker_room"},
		"tutorial": {"completed": false, "times_offered": 0, "skipped": false},
		"history": [],
	}


func _index_path() -> String:
	return Paths.file("profiles", "index.json")


func _profile_path(id: String) -> String:
	return Paths.dir("profiles").path_join(id).path_join("profile.json")


func _load_index() -> void:
	var r := Saves.read_json(_index_path(), "profile_index", 1)
	if r["ok"]:
		_index = r["data"]
	elif r["exists"]:
		last_error = "Profile list unreadable (%s); rebuilding from profile folders." % r["error"]
		_rebuild_index()


func _rebuild_index() -> void:
	_index = {"profiles": [], "active": ""}
	var d := DirAccess.open(Paths.dir("profiles"))
	if d == null:
		return
	for sub in d.get_directories():
		var r := Saves.read_json(_profile_path(sub), "profile", VERSION, _migrate)
		if r["ok"]:
			_index["profiles"].append({"id": sub, "name": r["data"].get("name", sub)})
	_save_index()


func _save_index() -> void:
	Saves.write_json(_index_path(), "profile_index", 1, _index)


func list_profiles() -> Array:
	return _index["profiles"].duplicate(true)


func create(name_: String) -> String:
	var base := Paths.slug(name_).to_lower().replace(" ", "_")
	var id := base
	var n := 2
	while _has(id):
		id = "%s_%d" % [base, n]
		n += 1
	var p := default_profile(id, name_.strip_edges().substr(0, 24))
	Saves.write_json(_profile_path(id), "profile", VERSION, p)
	_index["profiles"].append({"id": id, "name": p["name"]})
	_save_index()
	switch_to(id)
	return id


func _has(id: String) -> bool:
	for e in _index["profiles"]:
		if e["id"] == id:
			return true
	return false


func switch_to(id: String) -> bool:
	var r := Saves.read_json(_profile_path(id), "profile", VERSION, _migrate)
	if not r["ok"]:
		last_error = "Profile '%s' could not be loaded: %s" % [id, r["error"]]
		Log.e("profiles", last_error)
		if not r["exists"] or r.get("newer", false):
			return false
		# damaged and unrecoverable: keep the damaged file, start a fresh profile in its place
		Saves.quarantine(_profile_path(id))
		current = default_profile(id, id)
		save()
	else:
		current = r["data"]
		if r["migrated"] or r["recovered_from"] != "":
			save()
	_index["active"] = id
	_save_index()
	profile_changed.emit()
	return true


func rename(new_name: String) -> void:
	current["name"] = new_name.strip_edges().substr(0, 24)
	for e in _index["profiles"]:
		if e["id"] == current["id"]:
			e["name"] = current["name"]
	_save_index()
	save()


func delete_profile(id: String) -> void:
	if _index["profiles"].size() <= 1:
		return
	Saves.delete_save(_profile_path(id))
	DirAccess.remove_absolute(Paths.dir("profiles").path_join(id))
	_index["profiles"] = _index["profiles"].filter(func(e): return e["id"] != id)
	if current.get("id", "") == id:
		switch_to(str(_index["profiles"][0]["id"]))
	_save_index()


func save() -> void:
	if current.is_empty():
		return
	var err := Saves.write_json(_profile_path(str(current["id"])), "profile", VERSION, current)
	if err != OK:
		last_error = "Could not save profile: %s" % error_string(err)
		Log.e("profiles", last_error)


func _migrate(data, from_version: int):
	# v1 is the first format; future migrations chain here.
	return data if from_version == VERSION else null


func id() -> String:
	return str(current.get("id", ""))


func player_name() -> String:
	return str(current.get("name", "Rookie"))


## Records a finished match for statistics/records. `context`: versus | campaign | tutorial | lab...
## Custom-rule or reduced-speed matches still count for statistics but not for records.
func record_match(won: bool, draw: bool, fighter_id: String, stats: Dictionary, duration: float, custom := false) -> void:
	var s: Dictionary = current["stats"]
	s["matches"] = int(s["matches"]) + 1
	if draw:
		s["draws"] = int(s["draws"]) + 1
	elif won:
		s["wins"] = int(s["wins"]) + 1
	else:
		s["losses"] = int(s["losses"]) + 1
	s["kos"] = int(s["kos"]) + int(stats.get("kos", 0))
	s["knockdowns"] = int(s["knockdowns"]) + int(stats.get("knockdowns", 0))
	s["damage_dealt"] = float(s["damage_dealt"]) + float(stats.get("damage_dealt", 0.0))
	s["time_played"] = float(s["time_played"]) + duration
	var pf: Dictionary = s["per_fighter"]
	var e: Dictionary = pf.get(fighter_id, {"matches": 0, "wins": 0})
	e["matches"] = int(e["matches"]) + 1
	e["wins"] = int(e["wins"]) + (1 if won else 0)
	pf[fighter_id] = e
	if not custom:
		var rec: Dictionary = current["records"]
		if won:
			rec["win_streak"] = int(rec["win_streak"]) + 1
			rec["best_win_streak"] = maxi(int(rec["best_win_streak"]), int(rec["win_streak"]))
		elif not draw:
			rec["win_streak"] = 0
	save()


## The Dosage: clearing the highest unlocked dose unlocks the next (max 10). Returns true if a
## new dose was unlocked.
func clear_dose(variant: String, dose: int) -> bool:
	var l: Dictionary = current["ladder"][variant]
	l["cleared"] = maxi(int(l["cleared"]), dose)
	var unlocked := false
	if dose >= int(l["unlocked"]) and int(l["unlocked"]) < 10:
		l["unlocked"] = mini(10, dose + 1)
		unlocked = true
	var runs: Dictionary = current["records"]["runs"][variant]
	runs["best_dose"] = maxi(int(runs["best_dose"]), dose)
	save()
	return unlocked


func add_history(entry: Dictionary) -> void:
	var h: Array = current["history"]
	h.push_front(entry)
	while h.size() > MAX_HISTORY:
		h.pop_back()
	save()
