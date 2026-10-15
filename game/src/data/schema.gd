class_name Schema
## Minimal JSON Schema (draft 2020-12 subset) validator used for content packages, mod
## manifests, presets, arenas and policies. Supported keywords: type, enum, const, required,
## properties, additionalProperties (bool or schema), items, minItems, maxItems, minimum,
## maximum, minLength, maxLength, pattern, oneOf, anyOf, $ref (to "#/$defs/<name>").
## Errors are human-readable with JSON paths so modders can act on them (MOD-02).

static var _cache := {}


static func load_schema(name_: String) -> Dictionary:
	if _cache.has(name_):
		return _cache[name_]
	var path := "res://content/schemas/%s.schema.json" % name_
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_cache[name_] = s
	return s


## Validates `data` against schema `name_` (file in content/schemas). Returns error strings.
static func validate_named(data, name_: String, label := "") -> PackedStringArray:
	var s := load_schema(name_)
	if s.is_empty():
		return PackedStringArray(["schema '%s' not found" % name_])
	var errs := PackedStringArray()
	_validate(data, s, s, label if label != "" else "$", errs)
	return errs


static func validate(data, schema: Dictionary, label := "$") -> PackedStringArray:
	var errs := PackedStringArray()
	_validate(data, schema, schema, label, errs)
	return errs


## True when `pattern` matches `s` with JSON-Schema (ECMA-262) semantics. Godot's RegEx is PCRE2,
## whose `$` also matches just before a final line break, so "1.0.0\n" would pass "^...$": a match
## of a pattern ending in `$` must end at the very end of the string. An invalid pattern never
## matches.
static func full_match(pattern: String, s: String) -> bool:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return false
	var m := re.search(s)
	if m == null:
		return false
	if pattern.ends_with("$") and not pattern.ends_with("\\$"):
		return m.get_end() == s.length()
	return true


static func _type_ok(data, t: String) -> bool:
	match t:
		"object": return typeof(data) == TYPE_DICTIONARY
		"array": return typeof(data) == TYPE_ARRAY
		"string": return typeof(data) == TYPE_STRING or typeof(data) == TYPE_STRING_NAME
		"number": return typeof(data) == TYPE_FLOAT or typeof(data) == TYPE_INT
		"integer": return typeof(data) == TYPE_INT or (typeof(data) == TYPE_FLOAT and floorf(data) == data)
		"boolean": return typeof(data) == TYPE_BOOL
		"null": return data == null
	return false


static func _validate(data, s: Dictionary, root: Dictionary, path: String, errs: PackedStringArray) -> void:
	if errs.size() > 50:
		return
	if s.has("$ref"):
		var ref := str(s["$ref"])
		if ref.begins_with("#/$defs/"):
			var target: Dictionary = root.get("$defs", {}).get(ref.substr(8), {})
			_validate(data, target, root, path, errs)
		return
	if s.has("type"):
		var types = s["type"]
		var ok := false
		if typeof(types) == TYPE_ARRAY:
			for t in types:
				ok = ok or _type_ok(data, str(t))
		else:
			ok = _type_ok(data, str(types))
		if not ok:
			errs.append("%s: expected %s, got %s" % [path, str(types), type_string(typeof(data))])
			return
	if s.has("const") and data != s["const"]:
		errs.append("%s: must be %s" % [path, str(s["const"])])
	if s.has("enum"):
		var found := false
		for e in s["enum"]:
			if str(e) == str(data):
				found = true
		if not found:
			errs.append("%s: '%s' is not one of %s" % [path, str(data), str(s["enum"])])
	if typeof(data) == TYPE_FLOAT or typeof(data) == TYPE_INT:
		if s.has("minimum") and float(data) < float(s["minimum"]):
			errs.append("%s: %s is below the minimum %s" % [path, str(data), str(s["minimum"])])
		if s.has("maximum") and float(data) > float(s["maximum"]):
			errs.append("%s: %s is above the maximum %s" % [path, str(data), str(s["maximum"])])
	if typeof(data) == TYPE_STRING:
		if s.has("minLength") and str(data).length() < int(s["minLength"]):
			errs.append("%s: shorter than %d characters" % [path, int(s["minLength"])])
		if s.has("maxLength") and str(data).length() > int(s["maxLength"]):
			errs.append("%s: longer than %d characters" % [path, int(s["maxLength"])])
		if s.has("pattern") and not full_match(str(s["pattern"]), str(data)):
			errs.append("%s: '%s' does not match %s" % [path, str(data).c_escape(), str(s["pattern"])])
	if typeof(data) == TYPE_ARRAY:
		var arr: Array = data
		if s.has("minItems") and arr.size() < int(s["minItems"]):
			errs.append("%s: needs at least %d items" % [path, int(s["minItems"])])
		if s.has("maxItems") and arr.size() > int(s["maxItems"]):
			errs.append("%s: at most %d items allowed" % [path, int(s["maxItems"])])
		if s.has("items") and typeof(s["items"]) == TYPE_DICTIONARY:
			for i in arr.size():
				_validate(arr[i], s["items"], root, "%s[%d]" % [path, i], errs)
	if typeof(data) == TYPE_DICTIONARY:
		var d: Dictionary = data
		for r in s.get("required", []):
			if not d.has(r):
				errs.append("%s: missing required '%s'" % [path, r])
		var props: Dictionary = s.get("properties", {})
		for k in d:
			if props.has(k):
				_validate(d[k], props[k], root, "%s.%s" % [path, k], errs)
			elif s.has("additionalProperties"):
				var ap = s["additionalProperties"]
				if typeof(ap) == TYPE_BOOL and not ap:
					errs.append("%s: unknown field '%s'" % [path, k])
				elif typeof(ap) == TYPE_DICTIONARY:
					_validate(d[k], ap, root, "%s.%s" % [path, k], errs)
	if s.has("oneOf") or s.has("anyOf"):
		var opts: Array = s.get("oneOf", s.get("anyOf", []))
		var matched := 0
		for o in opts:
			var sub := PackedStringArray()
			_validate(data, o, root, path, sub)
			if sub.is_empty():
				matched += 1
		if matched == 0 or (s.has("oneOf") and matched > 1):
			errs.append("%s: does not match exactly one allowed form" % path)
