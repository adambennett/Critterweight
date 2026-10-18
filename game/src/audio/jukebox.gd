class_name Jukebox
extends RefCounted
## User playlists contain stable bank IDs, never file paths. Stings are not playlist tracks.
const CONTEXTS := ["menu", "fight", "boss", "hub"]
const LABELS := ["Main menu", "Fights", "Boss fights", "Cannery radio"]
const MODES := ["game", "ordered", "shuffle", "repeat"]
const MODE_LABELS := ["Game soundtrack", "Play in order", "Shuffle", "Repeat first track"]

static func tracks() -> Array:
	var ids: Array = []
	var files := {}
	for id in Audio.music_ids():
		var entry: Dictionary = Audio.bank["music"][id]
		var file := str(entry.get("file", ""))
		if not bool(entry.get("stinger", false)) and not files.has(file):
			files[file] = true
			ids.append(id)
	return ids

static func config(context: String) -> Dictionary:
	var all: Dictionary = Settings.get_value("audio.jukebox")
	var value: Dictionary = all.get(context, {})
	return {"mode": str(value.get("mode", "game")), "tracks": value.get("tracks", [])}

static func save(context: String, value: Dictionary) -> void:
	var all: Dictionary = (Settings.get_value("audio.jukebox") as Dictionary).duplicate(true)
	all[context] = value.duplicate(true)
	Settings.set_value("audio.jukebox", all)

static func context_for(track: String) -> String:
	if track.begins_with("combat"):
		return "fight"
	if track.begins_with("boss"):
		return "boss"
	if track == "cannery_radio":
		return "hub"
	return "menu"

static func choose(context: String, fallback: String, current := "", advance := false) -> String:
	var cfg := config(context)
	var mode := str(cfg["mode"])
	if mode == "game" or not mode in MODES:
		return fallback
	var valid := tracks()
	var choices: Array = []
	for id in cfg["tracks"]:
		if valid.has(id) and not choices.has(id):
			choices.append(id)
	if choices.is_empty():
		return "" # an explicitly empty playlist means silence
	if not advance and choices.has(current):
		return current
	if mode == "shuffle":
		var pool := choices.duplicate()
		if pool.size() > 1:
			pool.erase(current)
		return str(pool[randi() % pool.size()])
	if mode == "ordered" and advance:
		return str(choices[posmod(choices.find(current) + 1, choices.size())])
	return str(choices[0])
