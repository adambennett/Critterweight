class_name NetPlaylist
extends RefCounted
## Server playlist: a weighted rotation of {rules preset, arena, optional player/bot limits,
## optional rules overrides} entries (schema: content/schemas/playlist.schema.json; examples in
## content/core/playlists/). Rules (docs/SERVER.md#playlists):
##
## * Weight = relative chance of an entry being drawn (as a vote candidate, or as the next match
##   when voting is off). 0 disables an entry; negative weights are invalid.
## * Candidates: up to `voting.candidates` entries are drawn by weight WITHOUT replacement from
##   the entries that can start with the current number of human players, excluding the last
##   `repeat_avoidance` played entries. If that leaves nothing, the exclusion is relaxed.
## * Vote: most votes wins. Tie -> the tied candidate with the higher weight, then the one drawn
##   first. No votes at all -> the highest-weight candidate (then the one drawn first).
## * Minimum players: an entry needs `min_players` fighters (default: the rules format minimum).
##   Bots fill missing fighters if allowed (entry `bots` > 0, or the server's `bots = true` when
##   the entry does not say); otherwise the server waits for players.
## * `max_players` caps human fighters; extra humans spectate that match (they get priority next).
## * Invalid entries (unknown rules/arena/mode, bad limits) are reported with the entry number
##   and skipped; content missing at match time is re-checked and skipped too.
## * State (history, match count) persists across restarts in <user>/server/.

const MAX_ENTRIES := 64
const HISTORY_KEEP := 32
const STATE_VERSION := 1

var id := ""
var display_name := ""
var source := ""
var entries: Array = []                ## normalized entries (valid and invalid)
var candidates_count := 3
var voting := true
var repeat_avoidance := 2
var errors: Array[String] = []
var history: Array[String] = []        ## played entry keys, oldest first
var matches_played := 0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


## ref: a content playlist id ("fight_night", "mymod:x") or a JSON file path.
static func load_ref(ref: String) -> NetPlaylist:
	if ref.ends_with(".json") or ref.contains("/") or ref.contains("\\"):
		return load_file(ref)
	var d := Content.get_entry("playlists", ref)
	if d.is_empty():
		var p := NetPlaylist.new()
		p.id = ref
		p.display_name = ref
		p.source = "content:" + ref
		p.errors.append("playlist '%s' was not found in the loaded content packages (available: %s)" % [ref, ", ".join(PackedStringArray(Content.ids("playlists")))])
		return p
	return from_dict(d, "content:" + ref)


static func load_file(path: String) -> NetPlaylist:
	var p := NetPlaylist.new()
	p.source = path
	p.id = path.get_file().get_basename()
	p.display_name = p.id
	if not FileAccess.file_exists(path):
		p.errors.append("playlist file not found: %s" % path)
		return p
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 512 * 1024:
		p.errors.append("playlist file %s cannot be read or is larger than 512 KB" % path)
		return p
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		p.errors.append("%s: JSON error at line %d: %s" % [path.get_file(), json.get_error_line(), json.get_error_message()])
		return p
	if typeof(json.data) != TYPE_DICTIONARY:
		p.errors.append("%s: a playlist must be a JSON object" % path.get_file())
		return p
	var d: Dictionary = json.data
	var schema_errs := Schema.validate_named(d, "playlist", path.get_file())
	var out := from_dict(d, path)
	for e in schema_errs:
		out.errors.append("schema: " + e)
	return out


static func from_dict(d: Dictionary, src: String) -> NetPlaylist:
	var p := NetPlaylist.new()
	p.source = src
	p.id = str(d.get("id", src.get_file().get_basename()))
	p.display_name = str(d.get("name", p.id))
	var v = d.get("voting", {})
	if typeof(v) == TYPE_DICTIONARY:
		var vd: Dictionary = v
		p.candidates_count = clampi(int(vd.get("candidates", 3)), 1, 5)
		p.voting = bool(vd.get("enabled", true))
	p.repeat_avoidance = clampi(int(d.get("repeat_avoidance", 2)), 0, 16)
	var raw = d.get("entries", [])
	if typeof(raw) != TYPE_ARRAY:
		p.errors.append("'entries' must be a list")
		return p
	var arr: Array = raw
	if arr.size() > MAX_ENTRIES:
		p.errors.append("only the first %d entries are used (%d given)" % [MAX_ENTRIES, arr.size()])
	for i in mini(arr.size(), MAX_ENTRIES):
		p.entries.append(_normalize(arr[i], i))
	return p


static func _normalize(raw, i: int) -> Dictionary:
	var e := {"index": i, "key": "", "name": "", "rules": "", "arena": "", "weight": 1.0, "min_players": 0,
		"max_players": 0, "bots": -1, "rules_override": {}, "valid": true, "errors": [], "notes": []}
	if typeof(raw) != TYPE_DICTIONARY:
		e["valid"] = false
		(e["errors"] as Array).append("entry is not an object")
		e["key"] = "#%d" % i
		return e
	var d: Dictionary = raw
	e["rules"] = str(d.get("rules", ""))
	e["arena"] = str(d.get("arena", ""))
	e["key"] = str(d.get("id", "%s@%s" % [e["rules"], e["arena"]]))
	e["name"] = str(d.get("name", ""))
	var w = d.get("weight", 1.0)
	if typeof(w) != TYPE_FLOAT and typeof(w) != TYPE_INT:
		(e["errors"] as Array).append("weight must be a number")
	else:
		e["weight"] = float(w)
	e["min_players"] = int(d.get("min_players", 0))
	e["max_players"] = int(d.get("max_players", 0))
	e["bots"] = int(d.get("bots", -1))
	var ov = d.get("rules_override", {})
	if typeof(ov) == TYPE_DICTIONARY:
		e["rules_override"] = (ov as Dictionary).duplicate(true)
	else:
		(e["errors"] as Array).append("rules_override must be an object")
	if str(e["rules"]) == "":
		(e["errors"] as Array).append("missing 'rules'")
	if str(e["arena"]) == "":
		(e["errors"] as Array).append("missing 'arena'")
	return e


## Fighter count limits of a rules dictionary: Vector2i(min, max).
static func format_limits(rules: Dictionary) -> Vector2i:
	var fmt := str(rules.get("format", ""))
	var teams := int(rules.get("teams", 0))
	match fmt:
		"duel":
			return Vector2i(2, 2)
		"ffa":
			return Vector2i(2, NetProtocol.MAX_FIGHTERS)
		"teams":
			var t := maxi(2, teams)
			var size := clampi(int(rules.get("team_size", 2)), 1, floori(float(NetProtocol.MAX_FIGHTERS) / float(t)))
			return Vector2i(t * size, t * size)
	if teams >= 2:
		return Vector2i(teams, NetProtocol.MAX_FIGHTERS)
	return Vector2i(2, NetProtocol.MAX_FIGHTERS)


static func resolve_rules(rules_id: String, override: Dictionary) -> Dictionary:
	var base := Content.get_entry("rules", rules_id)
	if base.is_empty():
		return {}
	var r: Dictionary = base.duplicate(true)
	for k in override:
		r[k] = override[k]
	return r


func rules_for(e: Dictionary) -> Dictionary:
	return resolve_rules(str(e["rules"]), e["rules_override"])


## Effective fighter range for an entry: Vector2i(fighters needed, max human fighters).
func limits_for(e: Dictionary) -> Vector2i:
	var lim := format_limits(rules_for(e))
	var lo := lim.x
	var hi := lim.y
	if int(e["min_players"]) > 0:
		lo = clampi(int(e["min_players"]), lim.x, lim.y)
	if int(e["max_players"]) > 0:
		hi = clampi(int(e["max_players"]), 1, lim.y)
	return Vector2i(lo, hi)


## Semantic validation against the loaded content (rules, arenas, modes, limits).
func validate() -> void:
	var valid := 0
	for e in entries:
		var ed: Dictionary = e
		var errs: Array = ed["errors"]
		if str(ed["rules"]) != "":
			var rules := rules_for(ed)
			if rules.is_empty():
				errs.append("rules preset '%s' not found" % ed["rules"])
			else:
				var mode_id := str(rules.get("mode", "standard"))
				if not ModeRegistry.ids().has(mode_id):
					errs.append("mode '%s' (used by rules '%s') is not installed" % [mode_id, ed["rules"]])
				var lim := format_limits(rules)
				if int(ed["min_players"]) > 0 and (int(ed["min_players"]) < lim.x or int(ed["min_players"]) > lim.y):
					errs.append("min_players %d is outside what '%s' allows (%d-%d fighters)" % [int(ed["min_players"]), ed["rules"], lim.x, lim.y])
				if int(ed["max_players"]) > 0 and int(ed["max_players"]) > lim.y:
					errs.append("max_players %d exceeds what '%s' allows (%d)" % [int(ed["max_players"]), ed["rules"], lim.y])
		if str(ed["arena"]) != "":
			var a := Content.arena(str(ed["arena"]))
			if a == null:
				errs.append("arena '%s' not found" % ed["arena"])
			elif not a.errors.is_empty():
				errs.append("arena '%s' is invalid: %s" % [ed["arena"], "; ".join(a.errors)])
		if float(ed["weight"]) < 0.0:
			errs.append("weight must be 0 or more (got %s)" % str(ed["weight"]))
		if int(ed["min_players"]) < 0 or int(ed["max_players"]) < 0:
			errs.append("player limits must be positive")
		if int(ed["min_players"]) > 0 and int(ed["max_players"]) > 0 and int(ed["max_players"]) < 1:
			errs.append("max_players must be at least 1")
		if int(ed["bots"]) > NetProtocol.MAX_FIGHTERS - 1:
			errs.append("bots must be at most %d" % (NetProtocol.MAX_FIGHTERS - 1))
		if str(ed["name"]) == "" and errs.is_empty():
			var rd := Content.get_entry("rules", str(ed["rules"]))
			var ad := Content.arena(str(ed["arena"]))
			ed["name"] = "%s @ %s" % [str(rd.get("name", ed["rules"])), ad.display_name if ad else str(ed["arena"])]
		ed["valid"] = errs.is_empty()
		if ed["valid"]:
			valid += 1
			if float(ed["weight"]) == 0.0:
				(ed["notes"] as Array).append("weight 0: never drawn")
		else:
			errors.append("entry %d (%s): %s - skipped" % [int(ed["index"]) + 1, ed["key"], "; ".join(PackedStringArray(errs))])
	if valid == 0:
		errors.append("playlist '%s' has no valid entries" % id)


func valid_entries() -> Array:
	return entries.filter(func(e): return bool(e["valid"]))


## Can this entry start with `humans` human players? (bots fill if allowed)
func can_start(e: Dictionary, humans: int, server_bots: bool) -> bool:
	if not bool(e["valid"]) or float(e["weight"]) <= 0.0:
		return false
	var lim := limits_for(e)
	var playing := mini(humans, lim.y)
	if playing >= lim.x:
		return true
	return playing + bot_allowance(e, server_bots) >= lim.x


## How many bots this entry may add.
static func bot_allowance(e: Dictionary, server_bots: bool) -> int:
	var b := int(e["bots"])
	if b >= 0:
		return b
	return NetProtocol.MAX_FIGHTERS if server_bots else 0


func eligible(humans: int, server_bots: bool) -> Array:
	return entries.filter(func(e): return can_start(e, humans, server_bots))


func recent_keys() -> Array[String]:
	var out: Array[String] = []
	var n := mini(repeat_avoidance, history.size())
	for i in range(history.size() - n, history.size()):
		out.append(history[i])
	return out


## Draws up to `count` vote candidates (see class comment).
func draw_candidates(humans: int, server_bots: bool, count: int) -> Array:
	var pool := eligible(humans, server_bots)
	if pool.is_empty():
		return []
	var recent := recent_keys()
	var fresh := pool.filter(func(e): return not recent.has(str(e["key"])))
	if fresh.is_empty():
		# relax: only avoid the very last entry if possible, else allow everything
		var last: String = history[history.size() - 1] if not history.is_empty() else ""
		fresh = pool.filter(func(e): return str(e["key"]) != last)
		if fresh.is_empty():
			fresh = pool
	var n := clampi(count if voting else 1, 1, 5)
	var out: Array = []
	var left := fresh.duplicate()
	while out.size() < n and not left.is_empty():
		var total := 0.0
		for e in left:
			total += float(e["weight"])
		var r := rng.randf() * total
		var pick := left.size() - 1
		for i in left.size():
			r -= float(left[i]["weight"])
			if r < 0.0:
				pick = i
				break
		out.append(left[pick])
		left.remove_at(pick)
	return out


## votes: {player id: candidate index}. Returns {entry, index, tally: Array[int], reason}.
## reason: "votes" (clear winner), "tie" (resolved by weight/draw order), "no_votes".
func resolve_vote(candidates: Array, votes: Dictionary) -> Dictionary:
	if candidates.is_empty():
		return {}
	var tally: Array[int] = []
	tally.resize(candidates.size())
	tally.fill(0)
	var total := 0
	for pid in votes:
		var c := int(votes[pid])
		if c >= 0 and c < candidates.size():
			tally[c] += 1
			total += 1
	var best := 0
	var reason := "votes"
	if total == 0:
		reason = "no_votes"
		for i in candidates.size():
			if float(candidates[i]["weight"]) > float(candidates[best]["weight"]):
				best = i
	else:
		var top: int = tally.max()
		var tied: Array[int] = []
		for i in candidates.size():
			if tally[i] == top:
				tied.append(i)
		best = tied[0]
		if tied.size() > 1:
			reason = "tie"
			for i in tied:
				if float(candidates[i]["weight"]) > float(candidates[best]["weight"]):
					best = i
	return {"entry": candidates[best], "index": best, "tally": tally, "reason": reason}


func record_played(e: Dictionary) -> void:
	history.append(str(e["key"]))
	while history.size() > HISTORY_KEEP:
		history.pop_front()
	matches_played += 1


func find_entry(key: String) -> Dictionary:
	for e in entries:
		if str(e["key"]) == key:
			return e
	return {}


func summary() -> Dictionary:
	var ents: Array = []
	for e in entries:
		ents.append({"index": e["index"], "key": e["key"], "name": e["name"], "rules": e["rules"], "arena": e["arena"],
			"weight": e["weight"], "valid": e["valid"], "errors": (e["errors"] as Array).duplicate()})
	return {"id": id, "name": display_name, "source": source, "voting": voting, "candidates": candidates_count,
		"repeat_avoidance": repeat_avoidance, "entries": ents, "valid": valid_entries().size(),
		"invalid": entries.size() - valid_entries().size(), "errors": errors.duplicate(), "history": history.duplicate(),
		"matches_played": matches_played}


## Public description of a candidate for lobby/vote UIs.
func describe_entry(e: Dictionary) -> Dictionary:
	var rules := rules_for(e)
	var ad := Content.arena(str(e["arena"]))
	var lim := limits_for(e)
	return {"index": e["index"], "key": e["key"], "name": e["name"], "rules": e["rules"],
		"rules_name": str(rules.get("name", e["rules"])), "arena": e["arena"],
		"arena_name": ad.display_name if ad else str(e["arena"]), "mode": str(rules.get("mode", "standard")),
		"weight": e["weight"], "min_players": lim.x, "max_players": lim.y}


func state_path() -> String:
	return Paths.file("server", "playlist_state_%s.json" % Paths.slug(id.replace(":", "_")))


func save_state() -> Error:
	return Saves.write_json(state_path(), "playlist_state", STATE_VERSION,
		{"id": id, "source": source, "history": history.duplicate(), "matches_played": matches_played,
			"saved_unix": int(Time.get_unix_time_from_system())})


## Restores history after a restart. Returns a human-readable status line.
func load_state() -> String:
	var r := Saves.read_json(state_path(), "playlist_state", STATE_VERSION)
	if not bool(r["ok"]):
		return "no saved playlist state (%s)" % str(r["error"]) if bool(r["exists"]) else "no saved playlist state (first run)"
	var d: Dictionary = r["data"]
	history.clear()
	for k in d.get("history", []):
		history.append(str(k))
	while history.size() > HISTORY_KEEP:
		history.pop_front()
	matches_played = int(d.get("matches_played", 0))
	return "restored playlist state: %d matches played, recent: %s" % [matches_played, ", ".join(PackedStringArray(recent_keys()))]
