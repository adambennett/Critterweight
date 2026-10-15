class_name RunStore
extends RefCounted
## Suspended runs and co-op party tickets on disk (SAV-01/02/03).
##   <runs dir>/<profile id>/<slot>.json   kind "campaign_run", version RunState.VERSION
## Slots: off_the_street, fight_camp, bookie (one suspended run each per profile) and
## party_<run id> (co-op: the host's run, or a member's replica checkpoint).
## Writes go through Saves (temp -> verify -> .bak rotate -> rename, checksummed), so a crash at
## any point leaves a recoverable copy. Loading never deletes or rewrites anything; a damaged,
## newer-format or content-incompatible save produces a clear error and stays on disk.

const KIND := "campaign_run"
const TICKET_KIND := "party_ticket"

var base_dir := ""


func _init(dir := "") -> void:
	base_dir = dir if dir != "" else Paths.dir("runs")


func slot_path(profile_id: String, slot: String) -> String:
	return base_dir.path_join(Paths.slug(profile_id if profile_id != "" else "default")).path_join(Paths.slug(slot) + ".json")


static func slot_for(state: Dictionary) -> String:
	if (state.get("players", []) as Array).size() > 1:
		return "party_%s" % str(state.get("run_id", "run"))
	if str(state.get("mode", "")) == "bookie":
		return "bookie"
	return str(state.get("variant", "off_the_street"))


func save(state: Dictionary, profile_id: String, slot := "") -> Error:
	var s := slot if slot != "" else slot_for(state)
	return Saves.write_json(slot_path(profile_id, s), KIND, RunState.VERSION, json_stable(state))


## Godot's JSON reader does not read every 17-digit float back exactly, and it misreads a large
## whole number written as "N.0" by one (which changed 53-bit run seeds on save). Saves.stabilize
## returns the JSON fixed point with whole numbers kept as integers, so the data survives the
## file or a network hop bit-exactly and checksums computed now still verify after loading.
static func json_stable(data):
	return Saves.stabilize(data)


## One float that survives a JSON round trip exactly (for values written into profiles).
static func stable_float(x: float) -> float:
	var cur := x
	for i in 24:
		var nx := float(JSON.parse_string(JSON.stringify([cur], "", false, true))[0])
		if nx == cur:
			return cur
		cur = nx
	return cur


## Loads and validates a suspended run. Returns {ok, state, error, problems, recovered_from,
## migrated, exists}. `ok` is false for missing, damaged, newer-format or inconsistent runs and
## for runs that reference content which is no longer installed (problems lists every id).
func load_slot(profile_id: String, slot: String, catalog: CampaignCatalog) -> Dictionary:
	var path := slot_path(profile_id, slot)
	var r := Saves.read_json(path, KIND, RunState.VERSION, migrate)
	var out := {"ok": false, "state": {}, "error": "", "problems": [], "recovered_from": str(r.get("recovered_from", "")),
		"migrated": bool(r.get("migrated", false)), "exists": bool(r.get("exists", false)), "path": path}
	if not bool(r["ok"]):
		if not bool(r.get("exists", false)):
			out["error"] = "No suspended run in this slot."
		elif bool(r.get("newer", false)):
			out["error"] = str(r["error"])
		else:
			out["error"] = "This run save is damaged and could not be recovered (%s). The file was left untouched." % r["error"]
		return out
	var st = r["data"]
	if typeof(st) != TYPE_DICTIONARY:
		out["error"] = "This run save does not contain a run."
		return out
	var probs := RunState.check(catalog, st)
	if not probs.is_empty():
		out["problems"] = probs
		var missing := []
		for p in probs:
			if str(p).begins_with("missing "):
				missing.append(str(p).substr(8))
		if not missing.is_empty():
			out["error"] = "This run uses content that is no longer installed: %s. Re-enable the mod that provided it to continue, or abandon the run." % ", ".join(missing)
		else:
			out["error"] = "This run cannot be resumed safely: %s. The save was left untouched." % "; ".join(probs)
		out["state"] = st
		return out
	out["ok"] = true
	out["state"] = st
	return out


## Suspended runs of a profile: [{slot, path, ok, error, summary}].
func list(profile_id: String, catalog: CampaignCatalog) -> Array:
	var out := []
	var dir := base_dir.path_join(Paths.slug(profile_id if profile_id != "" else "default"))
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files := d.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var slot := f.get_basename()
		var res := load_slot(profile_id, slot, catalog)
		var st: Dictionary = res.get("state", {})
		out.append({"slot": slot, "path": res["path"], "ok": res["ok"], "error": res["error"], "summary": summarize(st)})
	return out


static func summarize(st: Dictionary) -> Dictionary:
	if st.is_empty():
		return {}
	var fighters := []
	for p in st.get("players", []):
		fighters.append(str(p.get("fighter", "")))
	return {"run_id": str(st.get("run_id", "")), "variant": str(st.get("variant", "")), "mode": str(st.get("mode", "")),
		"difficulty": str(st.get("difficulty", "")), "dose": int(st.get("dose", 0)), "act": int(st.get("act", 1)),
		"phase": str(st.get("phase", "")), "fighters": fighters, "players": (st.get("players", []) as Array).size(),
		"seed_text": str(st.get("seed_text", "")), "elapsed": float(st.get("elapsed", 0.0)), "custom": bool(st.get("custom", false))}


## Removes a finished run's suspend slot (its summary lives on in the profile history).
func clear(profile_id: String, slot: String) -> void:
	Saves.delete_save(slot_path(profile_id, slot))


## Moves an unusable save aside instead of deleting it (abandoning a broken run).
func quarantine(profile_id: String, slot: String) -> String:
	return Saves.quarantine(slot_path(profile_id, slot))


## Save-format migrations. v0 (pre-release prototype) lacked claims/flags/log; future versions
## chain here. Returning null rejects the file (it stays on disk).
static func migrate(data, from_version: int):
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = data
	if from_version == 0:
		if not d.has("claims"):
			d["claims"] = {}
		if not d.has("flags"):
			d["flags"] = {"boss_mods": {}, "film_study": {}, "revealed": {}}
		if not d.has("log"):
			d["log"] = []
		d["version"] = 1
		return d
	return d if from_version == RunState.VERSION else null


# ---------------------------------------------------------------------------------------------
# Co-op party tickets: every member keeps the last node-boundary checkpoint of the shared run so
# any member can resume as the new host (CAMPAIGN.md §11 "Run ownership").
# ---------------------------------------------------------------------------------------------

static func make_ticket(state: Dictionary, host: String) -> Dictionary:
	var st: Dictionary = json_stable(state)
	return {"run_id": str(state.get("run_id", "")), "host": host, "log_size": (state.get("log", []) as Array).size(),
		"checksum": Saves.checksum(st), "state": st}


static func ticket_valid(t: Dictionary) -> bool:
	return t.has("state") and typeof(t["state"]) == TYPE_DICTIONARY and Saves.checksum(t["state"]) == str(t.get("checksum", ""))


func save_ticket(profile_id: String, ticket: Dictionary) -> Error:
	return Saves.write_json(slot_path(profile_id, "party_%s" % ticket.get("run_id", "run")), KIND, RunState.VERSION, json_stable(ticket["state"]))
