class_name SpeechLibrary
extends RefCounted
## Offline recorded speech. Authored subtitles retain names/bindings; audio uses recorded
## roster names, Player 1-8 fallbacks and device-independent action names. No network access.
const PATH := "res://assets/audio/speech/catalog.json"
const EXPANSION_PATH := "res://assets/audio/speech/announcer_expansion/catalog.json"
var catalog: Dictionary = {}
var _ids: Dictionary = {}
var _exact: Dictionary = {}
var _patterns: Array = []

func _init() -> void:
	for path in [PATH, EXPANSION_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary):
			continue
		for key in ["clips", "tokens", "fixed_tokens", "voices", "cast"]:
			var incoming = data.get(key, {})
			if incoming is Dictionary:
				var merged: Dictionary = catalog.get(key, {})
				merged.merge(incoming, true)
				catalog[key] = merged
		var incoming_lines = data.get("lines", [])
		if incoming_lines is Array:
			var merged_lines: Array = catalog.get("lines", [])
			merged_lines.append_array(incoming_lines)
			catalog["lines"] = merged_lines
	for item in catalog.get("lines", []):
		var line: Dictionary = item
		_ids[str(line["id"])] = line
		var source := str(line["template"])
		var speaker := str(line["speaker"])
		_exact[speaker + "\n" + source] = line
		var tokens: Array = []
		var expression := "^"
		var cursor := 0
		var token_re := RegEx.create_from_string("\\{([a-z0-9_]+)\\}")
		for found in token_re.search_all(source):
			var token := found.get_string(1)
			var capture := "([0-9]+)" if token in ["n", "act", "kos", "parts", "dose"] else "([^\\n.!?]{1,160}?)"
			if token in ["p", "o", "player"]:
				capture = "([^\\n]{1,160}?)" # Custom profile names can contain punctuation.
			expression += _escape(source.substr(cursor, found.get_start() - cursor)) + capture
			tokens.append(found.get_string(1))
			cursor = found.get_end()
		expression += _escape(source.substr(cursor))
		_patterns.append({"line": line, "tokens": tokens, "full": RegEx.create_from_string(expression + "$"), "prefix": RegEx.create_from_string(expression)})

	_patterns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["line"]["template"]).length() > str(b["line"]["template"]).length())

static func _escape(value: String) -> String:
	var out := ""
	for c in value:
		out += ("\\" if c in "\\.^$|?*+()[]{}" else "") + c
	return out

func resolve(id: String, speaker: String, source: String, text: String, vars: Dictionary, context: Dictionary) -> Dictionary:
	var parts: Array = []
	if _ids.has(id) and str(_ids[id]["template"]) == source and str(_ids[id]["speaker"]) == speaker:
		parts = _expand(_ids[id], vars, context)
	else:
		var remaining := text.strip_edges()
		for _segment in 8:
			if remaining.is_empty():
				break
			var matched := _find(speaker, remaining)
			if matched.is_empty():
				return {}
			parts.append_array(_expand(matched["line"], matched["vars"], context))
			remaining = remaining.substr(int(matched["length"])).strip_edges()
		if not remaining.is_empty():
			return {}
	if parts.is_empty():
		return {}
	var seconds := 0.0
	var paths: Array = []
	for clip in parts:
		var metadata: Dictionary = catalog.get("clips", {}).get(clip, {})
		if metadata.is_empty():
			return {}
		paths.append(str(metadata["path"]))
		seconds += float(metadata["seconds"])
	return {"clips": paths, "seconds": seconds, "ids": parts}

func _find(speaker: String, text: String) -> Dictionary:
	var exact_key := speaker + "\n" + text
	if _exact.has(exact_key):
		return {"line": _exact[exact_key], "vars": {}, "length": text.length()}
	var best: Dictionary = {}
	for full in [true, false]:
		for pattern in _patterns:
			var line: Dictionary = pattern["line"]
			if str(line["speaker"]) != speaker:
				continue
			var regex: RegEx = pattern["full"] if full else pattern["prefix"]
			var found := regex.search(text)
			if found == null or found.get_end() <= int(best.get("length", 0)):
				continue
			var vars: Dictionary = {}
			var tokens: Array = pattern["tokens"]
			for i in tokens.size():
				vars[tokens[i]] = found.get_string(i + 1)
			best = {"line": line, "vars": vars, "length": found.get_end()}
		if not best.is_empty():
			return best
	return best

func _expand(line: Dictionary, vars: Dictionary, context: Dictionary) -> Array:
	var out: Array = []
	var voice := str(line["voice"])
	for part in line["parts"]:
		if part.has("clip"):
			out.append(str(part["clip"]))
		else:
			out.append_array(_token(voice, str(part["token"]), str(vars.get(part["token"], "")), context))
	return out

func _token(voice: String, token: String, value: String, context: Dictionary) -> Array:
	var vocabulary: Dictionary = catalog.get("tokens", {}).get(voice, {})
	var normalized := value.strip_edges().to_lower()
	var words: Array = []
	if token in ["p", "o", "player"]:
		if vocabulary.has(normalized):
			words = [normalized]
		else:
			var index := int(context.get("player_index", 0)) if token != "o" else 1
			for fighter in context.get("fighters", []):
				if str(fighter.get("name", "")).to_lower() == normalized:
					index = int(fighter.get("index", index))
					break
			words = ["player %d" % clampi(index + 1, 1, 8)]
	elif token in ["n", "act", "kos", "parts", "dose"]:
		words = _number(int(value)) if value.is_valid_int() else ["many"]
	elif token in ["variant", "difficulty"]:
		words = [normalized if vocabulary.has(normalized) else "standard"]
	elif token in ["fighter", "boss"]:
		words = [normalized if vocabulary.has(normalized) else ("your fighter" if token == "fighter" else "the boss")]
	else:
		words = [str(catalog.get("fixed_tokens", {}).get(token, "your ultimate")).to_lower()]
	var out: Array = []
	for word in words:
		if vocabulary.has(word):
			out.append(vocabulary[word])
	return out

static func _number(value: int) -> Array:
	var small := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
	var tens := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
	if value < 0 or value >= 1000:
		return ["many"]
	if value < 20:
		return [small[value]]
	if value >= 100:
		return [small[int(value / 100.0)], "hundred"] + (_number(value % 100) if value % 100 != 0 else [])
	return [tens[int(value / 10.0)]] + ([small[value % 10]] if value % 10 != 0 else [])

