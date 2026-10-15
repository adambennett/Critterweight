class_name RunStore
extends RefCounted
## Suspended runs and co-op party tickets on disk (SAV-01/02/03).
##   <runs dir>/<profile id>/<slot>.json   kind "campaign_run", version RunState.VERSION
## Slots: off_the_street, fight_camp, bookie (one suspended run each per profile) and
## party_<run id> (co-op: the host's run, or a member's replica checkpoint). A new run never
## silently takes an occupied slot: the menus ask first and CampaignFlow credits the old run as
## abandoned (CampaignFlow.abandon_suspended) before the new one is saved.
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
		"migrated": bool(r.get("migrated", false)), "exists": bool(r.get("exists", false)), "path": path,
		"newer": bool(r.get("newer", false))}
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


## Suspended runs of a profile: [{slot, path, ok, error, summary}]. A slot is listed as soon as
## ANY copy of it exists — also when a crash left only the verified .tmp or the .bak behind,
## which load_slot recovers from.
func list(profile_id: String, catalog: CampaignCatalog) -> Array:
	var out := []
	var dir := base_dir.path_join(Paths.slug(profile_id if profile_id != "" else "default"))
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var slots := []
	for f in d.get_files():
		var s := slot_of_file(f)
		if s != "" and not slots.has(s):
			slots.append(s)
	slots.sort()
	for slot in slots:
		var res := load_slot(profile_id, str(slot), catalog)
		var st: Dictionary = res.get("state", {})
		out.append({"slot": str(slot), "path": res["path"], "ok": res["ok"], "error": res["error"], "summary": summarize(st)})
	return out


## The slot a file in a profile's runs folder belongs to: <slot>.json and the .json.tmp /
## .json.bak copies Saves writes next to it ("" for anything else, e.g. a quarantined copy).
static func slot_of_file(f: String) -> String:
	for suffix in [".json.tmp", ".json.bak", ".json"]:
		if f.ends_with(suffix) and f.length() > suffix.length():
			return f.substr(0, f.length() - suffix.length())
	return ""


## True for a co-op party's slot (party_<run id>): it resumes only through the co-op host path
## (CoopSession.host_resume), never as a solo run.
static func is_party_slot(slot: String, summary: Dictionary = {}) -> bool:
	return slot.begins_with("party_") or int(summary.get("players", 1)) > 1


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


## Removes a finished run's suspend slot (its summary lives on in the profile history). A slot
## written by a newer game version is never touched.
func clear(profile_id: String, slot: String) -> void:
	var path := slot_path(profile_id, slot)
	if Saves.is_newer(path, KIND, RunState.VERSION):
		return
	Saves.delete_save(path)
	if FileAccess.file_exists(_seat_path(path)):
		DirAccess.remove_absolute(_seat_path(path))


## Party runs: which of the run's players THIS machine is, kept next to its party save
## (party_<run id>.seat): profile ids are only unique per machine and names can change, so a
## member resuming the run elsewhere finds its seat by this first (NetPartyRuns).
func save_party_seat(profile_id: String, slot: String, seat: String) -> void:
	var p := _seat_path(slot_path(profile_id, slot))
	if FileAccess.file_exists(p) and FileAccess.get_file_as_string(p).strip_edges() == seat:
		return
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(seat)
		f.close()


## The seat save_party_seat() kept for `slot` ("" = none).
func party_seat(profile_id: String, slot: String) -> String:
	var p := _seat_path(slot_path(profile_id, slot))
	if not FileAccess.file_exists(p):
		return ""
	var s := FileAccess.get_file_as_string(p).strip_edges()
	return s if s.length() <= 16 else ""


static func _seat_path(save_path: String) -> String:
	return save_path.trim_suffix(".json") + ".seat"


## Moves an unusable save aside instead of deleting it (abandoning a broken run) — every copy of
## the slot (.json, .tmp, .bak), so a recoverable leftover cannot bring it back. Returns the new
## path of the main file ("" when it was not moved). A run saved by a newer game version stays
## where it is: nothing is moved then.
func quarantine(profile_id: String, slot: String) -> String:
	var path := slot_path(profile_id, slot)
	if Saves.is_newer(path, KIND, RunState.VERSION):
		return ""
	var main := Saves.quarantine(path)
	Saves.quarantine(path + ".tmp")
	Saves.quarantine(path + ".bak")
	return main


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
# The checksum only detects damage in transit/on disk (anyone can recompute it). Authenticity
# comes from CoopSession: a ticket is accepted only from the host's transport peer id, for the
# party's run id + seed, and only if its state follows from its own decision log
# (RunController.verify). A party slot is cleared when its run ends.
# ---------------------------------------------------------------------------------------------

static func make_ticket(state: Dictionary, host: String) -> Dictionary:
	var st: Dictionary = json_stable(state)
	return {"run_id": str(state.get("run_id", "")), "host": host, "log_size": (state.get("log", []) as Array).size(),
		"checksum": Saves.checksum(st), "state": st}


static func ticket_valid(t: Dictionary) -> bool:
	return t.has("state") and typeof(t["state"]) == TYPE_DICTIONARY and Saves.checksum(t["state"]) == str(t.get("checksum", ""))


func save_ticket(profile_id: String, ticket: Dictionary) -> Error:
	return Saves.write_json(slot_path(profile_id, "party_%s" % ticket.get("run_id", "run")), KIND, RunState.VERSION, json_stable(ticket["state"]))
