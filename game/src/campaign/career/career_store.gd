class_name CareerStore
extends RefCounted
## Career saves on disk (CMP-08, SAV-02): three slots per profile, never under runs/ (RunStore.list
## would list them) nor inside profiles/<id>/ (Profiles.delete_profile removes that folder):
##   <careers dir>/<slug(profile id)>/slot_<n>.json      kind "career", version CareerState.VERSION
##   <careers dir>/<slug(profile id)>/retired/slot_<n>-<unix>.json[.tmp|.bak]   retired careers
## Writes go through Saves (temp -> verify -> .bak rotate -> rename, checksummed). Loading never
## deletes or rewrites anything; a damaged, newer-format or content-incompatible save is reported
## and stays where it is. A slot is OCCUPIED while any copy (.json, .json.tmp, .json.bak) exists.
## retire()/move_aside() move ALL copies out of the slot namespace (design contract D3), so a
## recoverable leftover can never bring a retired career back or leak into the next career saved
## in that slot. A slot holding a newer-format copy is never moved or written.

const KIND := "career"
const SLOTS := 3

var base_dir := ""


func _init(dir := "") -> void:
	base_dir = dir if dir != "" else Paths.dir("careers")


func profile_dir(profile_id: String) -> String:
	return base_dir.path_join(Paths.slug(profile_id if profile_id != "" else "default"))


func slot_path(profile_id: String, slot: int) -> String:
	return profile_dir(profile_id).path_join("slot_%d.json" % slot)


static func valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOTS


## Any copy of the slot on disk (main, verified temp or backup).
func occupied(profile_id: String, slot: int) -> bool:
	var p := slot_path(profile_id, slot)
	return FileAccess.file_exists(p) or FileAccess.file_exists(p + ".tmp") or FileAccess.file_exists(p + ".bak")


## The first free slot (1..SLOTS), or -1 when all three hold a career (or an unreadable save).
func free_slot(profile_id: String) -> int:
	for n in range(1, SLOTS + 1):
		if not occupied(profile_id, n):
			return n
	return -1


func save(state: Dictionary, profile_id: String, slot: int) -> Error:
	if not valid_slot(slot):
		return ERR_INVALID_PARAMETER
	# the slot list shows when a career was last played: stamped into the state itself, so the
	# in-memory career stays identical to what is on disk
	state["saved_at"] = int(Time.get_unix_time_from_system())
	return Saves.write_json(slot_path(profile_id, slot), KIND, CareerState.VERSION, Saves.stabilize(state))


## Loads and validates a career. Returns {ok, state, error, problems, blocking, missing,
## recovered_from, migrated, exists, newer, path}. `ok` is false for missing, damaged, newer-format
## or inconsistent saves and for a career whose own fighter is no longer installed; stale offers
## and a booked fight with missing content load (CareerController repairs / offers to cancel).
func load_slot(profile_id: String, slot: int, catalog: CampaignCatalog) -> Dictionary:
	var path := slot_path(profile_id, slot)
	var out := {"ok": false, "state": {}, "error": "", "problems": [], "blocking": [], "missing": {},
		"recovered_from": "", "migrated": false, "exists": false, "newer": false, "path": path}
	if not valid_slot(slot):
		out["error"] = "There is no career slot %d." % slot
		return out
	var r := Saves.read_json(path, KIND, CareerState.VERSION, Callable(CareerState, "migrate"))
	out["recovered_from"] = str(r.get("recovered_from", ""))
	out["migrated"] = bool(r.get("migrated", false))
	out["exists"] = bool(r.get("exists", false))
	out["newer"] = bool(r.get("newer", false))
	if not bool(r["ok"]):
		if not bool(r.get("exists", false)):
			out["error"] = "This slot is empty."
		elif bool(r.get("newer", false)):
			out["error"] = str(r["error"])
		else:
			out["error"] = "This career save is damaged and could not be recovered (%s). The file was left untouched." % r["error"]
		return out
	var st = r["data"]
	if typeof(st) != TYPE_DICTIONARY:
		out["error"] = "This career save does not contain a career."
		return out
	var probs := CareerState.check(catalog, st)
	out["problems"] = probs
	out["missing"] = CareerState.missing_content(catalog, st)
	out["state"] = st
	var block := CareerState.blocking(probs)
	out["blocking"] = block
	if not block.is_empty():
		var missing: Array = out["missing"].get("fighter", [])
		if not missing.is_empty():
			out["error"] = "This career's fighter is no longer installed: %s. Re-enable the mod that provided it to continue. The save was left untouched." % ", ".join(PackedStringArray(missing))
		else:
			out["error"] = "This career cannot be continued safely: %s. The save was left untouched." % "; ".join(PackedStringArray(block))
		return out
	out["ok"] = true
	return out


## The three slots of a profile: [{slot, path, occupied, ok, error, newer, summary}].
func list(profile_id: String, catalog: CampaignCatalog) -> Array:
	var out := []
	for n in range(1, SLOTS + 1):
		var row := {"slot": n, "path": slot_path(profile_id, n), "occupied": occupied(profile_id, n), "ok": false,
			"error": "", "newer": false, "summary": {}}
		if bool(row["occupied"]):
			var r := load_slot(profile_id, n, catalog)
			row["ok"] = r["ok"]
			row["error"] = r["error"]
			row["newer"] = r["newer"]
			row["summary"] = summarize(r["state"], catalog)
		out.append(row)
	return out


## What a slot row shows (design contract D7): name, nick, fighter, record, standing, date, saved.
static func summarize(st: Dictionary, catalog: CampaignCatalog = null) -> Dictionary:
	if st.is_empty():
		return {}
	var rules := CareerDefaults.for_catalog(catalog)
	var pop := float(st.get("pop", 0.0))
	var champion := bool(st.get("champion", false))
	var fighter := str(st.get("fighter", ""))
	return {"career_id": str(st.get("career_id", "")), "name": str(st.get("name", "")), "nick": str(st.get("nick", "")),
		"fighter": fighter, "fighter_name": CareerOffers.fighter_name(catalog, fighter),
		"record": (st.get("record", {}) as Dictionary).duplicate(), "record_text": CareerState.record_text(st.get("record", {})),
		"week": int(st.get("week", 1)), "week_label": CareerState.week_label(int(st.get("week", 1))),
		"pop": pop, "champion": champion, "standing": CareerController.standing_of(rules, pop, champion)["text"],
		"difficulty": str(st.get("difficulty", "normal")), "booked": not (st.get("booked", {}) as Dictionary).is_empty(),
		"saved_at": int(st.get("saved_at", 0))}


## Moves every copy of a slot aside into <profile>/retired/ (retire a career, or clear an
## unreadable slot). Returns {ok, error, moved: [new paths]}. Nothing moves for a newer format.
func move_aside(profile_id: String, slot: int) -> Dictionary:
	var out := {"ok": false, "error": "", "moved": []}
	if not valid_slot(slot):
		out["error"] = "There is no career slot %d." % slot
		return out
	var path := slot_path(profile_id, slot)
	if Saves.is_newer(path, KIND, CareerState.VERSION):
		out["error"] = "This slot was saved by a newer version of the game and was left untouched."
		return out
	var dir := profile_dir(profile_id).path_join("retired")
	DirAccess.make_dir_recursive_absolute(dir)
	var stem := "slot_%d-%d" % [slot, int(Time.get_unix_time_from_system())]
	var n := 2
	while FileAccess.file_exists(dir.path_join(stem + ".json")) or FileAccess.file_exists(dir.path_join(stem + ".json.tmp")) \
			or FileAccess.file_exists(dir.path_join(stem + ".json.bak")):
		stem = "slot_%d-%d-%d" % [slot, int(Time.get_unix_time_from_system()), n]
		n += 1
	for suffix in ["", ".tmp", ".bak"]:
		var src: String = path + suffix
		if not FileAccess.file_exists(src):
			continue
		var dst: String = dir.path_join(stem + ".json" + suffix)
		if DirAccess.rename_absolute(src, dst) != OK:
			out["error"] = "Could not move %s aside." % src.get_file()
			return out
		out["moved"].append(dst)
	out["ok"] = true
	return out


## Retire = end the career (confirmed in the UI): the save is moved aside, never destroyed.
func retire(profile_id: String, slot: int) -> Dictionary:
	return move_aside(profile_id, slot)
