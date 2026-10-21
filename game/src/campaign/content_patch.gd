class_name ContentPatch
extends RefCounted
## Data-driven patches on creature JSON (and any nested Dictionary/Array data). Techniques,
## supplements, side effects, meta upgrades, minion loadouts and event outcomes change a
## fighter's kit ONLY through these ops, so every build is a reproducible transformation of the
## creature's authored JSON (docs/CAMPAIGN_SYSTEMS.md#patches).
##
## Patch: {"op": OP, "path": PATH, "value": V, ...}
##   ops: set | add | mul | min | max | append | remove | merge | time_scale
##   time_scale: value = factor; "phase": "all" (default) or "startup" (only the wind-up before
##               the first hit window / effect is scaled; later times shift accordingly).
##   add/mul on a missing numeric field use "default" when given, otherwise the target is skipped.
##   set/append/merge create missing leaf fields (never missing parents unless "create": true).
## Path: dot separated keys; a key may be "*" (every key of a Dictionary) and may carry selectors:
##   name[3]          array index        name[*]       every array element
##   name[type=zone]  array elements (Dictionaries) whose field equals the value (string compare)
##   e.g. "moves.heavy.damage", "moves.*.buildup", "abilities.ability2.effects[type=prop].max_active",
##        "abilities.ability1.effects[type=projectile].on_expire.radius", "moves.heavy_charged.lunge[*][2]"
## Missing paths are not errors at apply time (kits differ); apply() reports how many targets matched
## so validators/tests can flag patches that never hit anything on the intended fighter.

const OPS := ["set", "add", "mul", "min", "max", "append", "remove", "merge", "time_scale"]
## Fields of a move/ability that are times in seconds (scaled by time_scale).
const TIME_FIELDS := ["duration", "cancel"]
const TIME_RANGE_FIELDS := ["lunge", "armor", "invuln"]   ## arrays of [t0, t1, ...]


## Validates a patch's shape (not whether it matches anything). Returns an error or "".
static func validate(p) -> String:
	if typeof(p) != TYPE_DICTIONARY:
		return "patch is not an object"
	var op := str(p.get("op", ""))
	if not OPS.has(op):
		return "unknown patch op '%s'" % op
	var path := str(p.get("path", ""))
	if path == "":
		return "patch without a path"
	if parse_path(path).is_empty():
		return "malformed patch path '%s'" % path
	if op in ["add", "mul", "min", "max", "time_scale"]:
		var v = p.get("value")
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return "patch '%s' on %s needs a numeric value" % [op, path]
	if op in ["set", "append", "merge"] and not p.has("value"):
		return "patch '%s' on %s needs a value" % [op, path]
	if op == "merge" and typeof(p.get("value")) != TYPE_DICTIONARY:
		return "merge patch on %s needs an object value" % path
	if op == "time_scale" and float(p.get("value", 1.0)) <= 0.05:
		return "time_scale on %s must be > 0.05" % path
	return ""


## Parses "a.b[type=x].c[*]" into [{key, sels:[{kind, ...}]}]. Empty array if malformed.
static func parse_path(path: String) -> Array:
	var out := []
	for raw in path.split("."):
		var seg := str(raw)
		if seg == "":
			return []
		var key := seg
		var sels := []
		var b := seg.find("[")
		if b >= 0:
			key = seg.substr(0, b)
			var rest := seg.substr(b)
			while rest != "":
				if not rest.begins_with("["):
					return []
				var e := rest.find("]")
				if e < 0:
					return []
				var inner := rest.substr(1, e - 1)
				rest = rest.substr(e + 1)
				if inner == "*":
					sels.append({"kind": "all"})
				elif inner.is_valid_int():
					sels.append({"kind": "index", "i": int(inner)})
				elif "=" in inner:
					var kv := inner.split("=", true, 1)
					sels.append({"kind": "match", "field": kv[0], "value": kv[1]})
				else:
					return []
		out.append({"key": key, "sels": sels})
	return out


## Applies one patch to `root` in place. Returns the number of targets modified.
static func apply(root: Dictionary, p: Dictionary) -> int:
	var segs := parse_path(str(p.get("path", "")))
	if segs.is_empty():
		return 0
	var op := str(p.get("op", ""))
	# resolve every container that holds the final key
	var parents: Array = [root]
	for i in segs.size() - 1:
		parents = _descend(parents, segs[i], bool(p.get("create", false)))
		if parents.is_empty():
			return 0
	var last: Dictionary = segs[segs.size() - 1]
	var hits := 0
	var compact := []          ## arrays that had elements removed (compacted after all refs ran)
	for parent in parents:
		if typeof(parent) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = parent
		var keys := []
		if str(last["key"]) == "*":
			keys = pd.keys()
		else:
			keys = [str(last["key"])]
		for k in keys:
			var sels: Array = last["sels"]
			if sels.is_empty():
				hits += _apply_leaf(pd, k, op, p)
			else:
				# selectors on the last segment address array elements: operate on each element
				if not pd.has(k):
					continue
				for ref in _select(pd[k], sels):
					if op == "remove" and typeof(ref["container"]) == TYPE_ARRAY:
						(ref["container"] as Array)[int(ref["key"])] = null
						compact.append(ref["container"])   # compaction is idempotent; duplicates are harmless
						hits += 1
					else:
						hits += _apply_leaf(ref["container"], ref["key"], op, p)
	for arr in compact:
		var a: Array = arr
		var i := a.size() - 1
		while i >= 0:
			if a[i] == null:
				a.remove_at(i)
			i -= 1
	return hits


## The leaves a path addresses in `root`: [[container, key], ...] (what apply() would modify; for
## a missing leaf of an existing parent the reference is returned too, so callers can apply ops
## that create it). UpgradeTranslation uses it to treat each leaf on its own.
static func targets(root: Dictionary, path: String, create := false) -> Array:
	var segs := parse_path(path)
	if segs.is_empty():
		return []
	var parents: Array = [root]
	for i in segs.size() - 1:
		parents = _descend(parents, segs[i], create)
		if parents.is_empty():
			return []
	var last: Dictionary = segs[segs.size() - 1]
	var refs := []
	for parent in parents:
		if typeof(parent) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = parent
		var keys: Array = pd.keys() if str(last["key"]) == "*" else [str(last["key"])]
		for k in keys:
			var sels: Array = last["sels"]
			if sels.is_empty():
				refs.append([pd, k])
			elif pd.has(k):
				for ref in _select(pd[k], sels):
					refs.append([ref["container"], ref["key"]])
	return refs


## Applies one patch's op to a single leaf (container[key]); the patch's path is not read.
## Returns 1 when the leaf changed (see apply()).
static func apply_at(container, key, p: Dictionary) -> int:
	return _apply_leaf(container, key, str(p.get("op", "")), p)


## Applies a list of patches; returns {"hits": total, "unmatched": [paths with 0 hits]}.
static func apply_all(root: Dictionary, patches: Array) -> Dictionary:
	var total := 0
	var unmatched := []
	for p in patches:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var n := apply(root, p)
		total += n
		if n == 0:
			unmatched.append(str(p.get("path", "")))
	return {"hits": total, "unmatched": unmatched}


static func _descend(parents: Array, seg: Dictionary, create: bool) -> Array:
	var out := []
	for parent in parents:
		if typeof(parent) != TYPE_DICTIONARY:
			continue
		var pd: Dictionary = parent
		var keys := []
		if str(seg["key"]) == "*":
			keys = pd.keys()
		else:
			keys = [str(seg["key"])]
		for k in keys:
			if not pd.has(k):
				if create and (seg["sels"] as Array).is_empty():
					pd[k] = {}
				else:
					continue
			var v = pd[k]
			var sels: Array = seg["sels"]
			if sels.is_empty():
				out.append(v)
			else:
				for ref in _select(v, sels):
					out.append(ref["container"][ref["key"]])
	return out


## Resolves selectors on a value into [{container, key}] references (container[key] = element).
static func _select(v, sels: Array) -> Array:
	var refs := [{"container": {"_": v}, "key": "_"}]
	for s in sels:
		var next := []
		for ref in refs:
			var cur = ref["container"][ref["key"]]
			if typeof(cur) != TYPE_ARRAY:
				continue
			var arr: Array = cur
			match str(s["kind"]):
				"all":
					for i in arr.size():
						next.append({"container": arr, "key": i})
				"index":
					var idx := int(s["i"])
					if idx < 0:
						idx += arr.size()
					if idx >= 0 and idx < arr.size():
						next.append({"container": arr, "key": idx})
				"match":
					for i in arr.size():
						var el = arr[i]
						if typeof(el) == TYPE_DICTIONARY and (el as Dictionary).has(str(s["field"])) and str(el[str(s["field"])]) == str(s["value"]):
							next.append({"container": arr, "key": i})
		refs = next
	return refs


static func _num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _apply_leaf(container, key, op: String, p: Dictionary) -> int:
	var has_it: bool = false
	if typeof(container) == TYPE_DICTIONARY:
		has_it = (container as Dictionary).has(key)
	elif typeof(container) == TYPE_ARRAY:
		has_it = int(key) >= 0 and int(key) < (container as Array).size()
	else:
		return 0
	var value = p.get("value")
	match op:
		"set":
			container[key] = _copy(value)
			return 1
		"add", "mul", "min", "max":
			var cur = container[key] if has_it else p.get("default")
			if not _num(cur):
				return 0
			var c := float(cur)
			var x := float(value)
			var r := c
			match op:
				"add": r = c + x
				"mul": r = c * x
				"min": r = minf(c, x)
				"max": r = maxf(c, x)
			container[key] = r
			return 1
		"append":
			if not has_it:
				container[key] = []
			if typeof(container[key]) != TYPE_ARRAY:
				return 0
			if typeof(value) == TYPE_ARRAY and bool(p.get("spread", false)):
				(container[key] as Array).append_array(_copy(value))
			else:
				(container[key] as Array).append(_copy(value))
			return 1
		"remove":
			if not has_it or typeof(container) != TYPE_DICTIONARY:
				return 0
			(container as Dictionary).erase(key)
			return 1
		"merge":
			if not has_it:
				container[key] = {}
			if typeof(container[key]) != TYPE_DICTIONARY or typeof(value) != TYPE_DICTIONARY:
				return 0
			var target: Dictionary = container[key]
			for k2 in value:
				target[k2] = _copy(value[k2])
			return 1
		"time_scale":
			if not has_it or typeof(container[key]) != TYPE_DICTIONARY:
				return 0
			time_scale_move(container[key], float(value), str(p.get("phase", "all")))
			return 1
	return 0


static func _copy(v):
	if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
		return v.duplicate(true)
	return v


## Scales every authored time of a move/ability dictionary by `f` (phase "all"), or only its
## startup (phase "startup": times before the first active moment scale by f, later times shift
## by the startup delta so active/recovery lengths are unchanged).
static func time_scale_move(m: Dictionary, f: float, phase := "all") -> void:
	var t0 := INF
	if phase == "startup":
		for w in m.get("hit", []):
			if typeof(w) == TYPE_DICTIONARY:
				t0 = minf(t0, float(w.get("t0", INF)))
		if t0 == INF:
			for e in m.get("effects", []):
				if typeof(e) == TYPE_DICTIONARY:
					t0 = minf(t0, float(e.get("t", INF)))
		if t0 == INF:
			t0 = float(m.get("duration", 0.5)) * 0.35
	var mapf := func(t: float) -> float:
		if phase != "startup":
			return t * f
		return t * f if t <= t0 else t + t0 * (f - 1.0)
	for k in TIME_FIELDS:
		if _num(m.get(k)):
			m[k] = mapf.call(float(m[k]))
	for w in m.get("hit", []):
		if typeof(w) == TYPE_DICTIONARY:
			for k2 in ["t0", "t1"]:
				if _num(w.get(k2)):
					w[k2] = mapf.call(float(w[k2]))
	for kf in m.get("keys", []):
		if typeof(kf) == TYPE_DICTIONARY and _num(kf.get("t")):
			kf["t"] = mapf.call(float(kf["t"]))
	for e in m.get("effects", []):
		if typeof(e) == TYPE_DICTIONARY and _num(e.get("t")):
			e["t"] = mapf.call(float(e["t"]))
	for rf in TIME_RANGE_FIELDS:
		for r in m.get(rf, []):
			if typeof(r) == TYPE_ARRAY:
				var ra: Array = r
				for i in mini(2, ra.size()):
					if _num(ra[i]):
						ra[i] = mapf.call(float(ra[i]))
	# a Movesets move's sustain window [t0, t1] (the loop of a held stream) is move time too
	var sw = m.get("sustain")
	if typeof(sw) == TYPE_ARRAY:
		var sa: Array = sw
		for j in mini(2, sa.size()):
			if _num(sa[j]):
				sa[j] = mapf.call(float(sa[j]))
