class_name CommentaryHistory
extends RefCounted
## What the booth has said recently (v0.9.17, docs/audio/COMMENTARY.md §3). A bounded ring of the
## last MAX_ENTRIES spoken lines — line id, its topic/joke families, the match it was heard in and
## its order — kept across rematches, consecutive campaign/Career bouts and game restarts
## (profiles/commentary_history.json through Saves; one file per user-data root: it describes what
## this machine's player has heard, so it is not part of any profile, save or network state).
##
## Invariants: entries are oldest-first and never exceed MAX_ENTRIES; `match_serial` only grows
## (begin_match), so "matches ago" is always serial - entry.match; recency queries are O(1) through
## the last-seen indexes rebuilt on load. Never touches gameplay; a missing or damaged file just
## starts an empty history.

const FILE := "commentary_history.json"
const KIND := "commentary_history"
const VERSION := 1
const MAX_ENTRIES := 600

var entries: Array = []          ## [{id, fam: [..], m: match serial, n: play serial}]
var match_serial := 0            ## matches begun (persisted)
var play_serial := 0             ## lines spoken (persisted)
var path := ""                   ## "" = in memory only (tests)
var _last_by_id := {}            ## id -> {m, n}
var _last_by_family := {}        ## family -> {m, n}
var _dirty := false


static func open_default() -> CommentaryHistory:
	var h := CommentaryHistory.new()
	h.path = Paths.file("profiles", FILE)
	h.load_file()
	return h


func load_file() -> void:
	entries.clear()
	match_serial = 0
	play_serial = 0
	if path != "" and FileAccess.file_exists(path):
		var r: Dictionary = Saves.read_json(path, KIND, VERSION)
		if bool(r.get("ok", false)) and typeof(r["data"]) == TYPE_DICTIONARY:
			var d: Dictionary = r["data"]
			match_serial = int(d.get("match_serial", 0))
			play_serial = int(d.get("play_serial", 0))
			for e in d.get("entries", []):
				if typeof(e) == TYPE_DICTIONARY and str(e.get("id", "")) != "":
					entries.append({"id": str(e["id"]), "fam": (e.get("fam", []) as Array).duplicate(), "m": int(e.get("m", 0)), "n": int(e.get("n", 0))})
		elif not bool(r.get("ok", false)):
			Log.w("audio", "commentary history not read (%s); starting fresh" % str(r.get("error", "")))
	_trim()
	_reindex()
	_dirty = false


func save_file() -> void:
	if path == "" or not _dirty:
		return
	var err: Error = Saves.write_json(path, KIND, VERSION, {"match_serial": match_serial, "play_serial": play_serial, "entries": entries})
	if err == OK:
		_dirty = false
	else:
		Log.w("audio", "commentary history not saved: %s" % error_string(err))


func clear() -> void:
	entries.clear()
	_last_by_id.clear()
	_last_by_family.clear()
	_dirty = true


## A new match/bout starts (rematches and campaign bouts each count once).
func begin_match() -> void:
	match_serial += 1
	_dirty = true


## A line was actually spoken.
func note_play(id: String, families: Array) -> void:
	play_serial += 1
	var e := {"id": id, "fam": families.duplicate(), "m": match_serial, "n": play_serial}
	entries.append(e)
	_last_by_id[id] = {"m": match_serial, "n": play_serial}
	for f in families:
		_last_by_family[str(f)] = {"m": match_serial, "n": play_serial}
	_trim()
	_dirty = true


## Lines spoken since `id` was last spoken (INF when never, or when it fell out of the window).
func plays_since(id: String) -> int:
	var last: Dictionary = _last_by_id.get(id, {})
	return play_serial - int(last["n"]) if not last.is_empty() else 1 << 30


## Matches begun since `id` was last spoken (0 = this match; large when never).
func matches_since(id: String) -> int:
	var last: Dictionary = _last_by_id.get(id, {})
	return match_serial - int(last["m"]) if not last.is_empty() else 1 << 30


func family_plays_since(family: String) -> int:
	var last: Dictionary = _last_by_family.get(family, {})
	return play_serial - int(last["n"]) if not last.is_empty() else 1 << 30


func family_matches_since(family: String) -> int:
	var last: Dictionary = _last_by_family.get(family, {})
	return match_serial - int(last["m"]) if not last.is_empty() else 1 << 30


## Ids heard in the current match.
func heard_this_match(id: String) -> bool:
	return matches_since(id) == 0


func _trim() -> void:
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)
		_reindex()


func _reindex() -> void:
	_last_by_id.clear()
	_last_by_family.clear()
	for e in entries:
		var at := {"m": int(e["m"]), "n": int(e["n"])}
		_last_by_id[str(e["id"])] = at
		for f in e["fam"]:
			_last_by_family[str(f)] = at
