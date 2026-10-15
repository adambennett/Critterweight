class_name PolicyData
extends RefCounted
## A trained policy artifact: metadata + contract versions + network weights. This is the
## in-memory form of the `.policy.json` format (docs/AI_LAB.md "Policy file format").
##
## Safety: a policy is pure data. Loading only parses JSON and decodes base64 float32 weights;
## nothing is ever instantiated, evaluated or executed (no str_to_var/bytes_to_var/load). Every
## field is validated strictly (types, shapes, version/contract compatibility, finite numbers,
## size limits, checksum); invalid files are rejected with readable errors and never "repaired".

const FORMAT := "critterweight.policy"
const FORMAT_VERSION := 1
const MAX_FILE_BYTES := 4 * 1024 * 1024
const MAX_META_BYTES := 256 * 1024
const MAX_ABS_WEIGHT := 1.0e4
const ID_REGEX := "^[A-Za-z0-9_.:\\-]{1,96}$"
const B64_REGEX := "^[A-Za-z0-9+/]*={0,2}$"
const WEIGHT_ENCODING := "f32le_base64"
const MODES: PackedStringArray = ["argmax", "sample"]

var id := ""
var name := ""
var version := 1
var creature := ""
var created := ""
var updated := ""
var description := ""
var target_lag := 1
var decision_hz := PolicyActions.DEFAULT_DECISION_HZ
var act_mode := "argmax"
var temperature := 1.0
var button_mask := PackedByteArray()
var net: PolicyMLP
var training := {}
var creature_signature := ""
## Not serialized: where it came from ("user", "core" or a mod id) and its file.
var source := "user"
var path := ""


static func now_iso() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"


## A fresh, randomly initialised policy for a creature (deterministic for a given seed).
static func create_new(creature_id: String, hidden: PackedInt32Array, activation: String, seed_value: int) -> PolicyData:
	var p := PolicyData.new()
	p.creature = creature_id
	p.net = PolicyMLP.create(PolicyObs.SIZE, hidden, PolicyActions.OUTPUTS, activation, seed_value)
	p.created = now_iso()
	p.updated = p.created
	p.button_mask = PolicyActions.button_mask(_creature_or_null(creature_id))
	p.creature_signature = creature_signature_of(creature_id)
	return p


## Content lookup that also works without autoloads (unit tests, tools).
static func _creature_or_null(creature_id: String) -> CreatureDef:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Content") == null:
		return null
	return tree.root.get_node("Content").call("creature", creature_id) as CreatureDef


## Short hash of a creature's gameplay definition, used to warn when a policy was trained on a
## different version of its fighter (still loadable: the contracts are unchanged).
static func creature_signature_of(creature_id: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.get_node_or_null("Content") == null:
		return ""
	var d: Dictionary = tree.root.get_node("Content").call("get_entry", "creatures", creature_id)
	if d.is_empty():
		return ""
	var clean := {}
	for k in d:
		if not str(k).begins_with("_"):
			clean[k] = d[k]
	return canonical_hash(clean).substr(0, 16)


func param_count() -> int:
	return net.params.size() if net else 0


func summary() -> Dictionary:
	return {"id": id, "name": name, "version": version, "creature": creature, "created": created, "updated": updated,
		"approach": str(training.get("approach", "")), "source": source, "path": path, "params": param_count(),
		"hidden": Array(net.hidden) if net else [], "mode": act_mode, "objective": str((training.get("objective", {}) as Dictionary).get("preset", "")) if typeof(training.get("objective", {})) == TYPE_DICTIONARY else ""}


# =====================================================================================
# Serialization
# =====================================================================================

func to_dict() -> Dictionary:
	var d := {
		"format": FORMAT, "format_version": FORMAT_VERSION,
		"id": id, "name": name, "version": version, "creature": creature,
		"created": created, "updated": updated, "description": description,
		"creature_signature": creature_signature,
		"obs": {"version": PolicyObs.VERSION, "size": PolicyObs.SIZE, "target_lag": target_lag},
		"act": {"version": PolicyActions.VERSION, "heads": [PolicyActions.MOVE_COUNT, PolicyActions.BUTTON_COUNT],
			"decision_hz": decision_hz, "mode": act_mode, "temperature": temperature, "mask": Array(button_mask)},
		"arch": {"type": "mlp", "inputs": net.inputs, "hidden": Array(net.hidden), "activation": net.activation, "outputs": net.outputs},
		"weights": {"encoding": WEIGHT_ENCODING, "count": net.params.size(), "data": Marshalls.raw_to_base64(net.params.to_byte_array())},
		"training": training,
	}
	d["checksum"] = canonical_hash(d)
	return d


## Canonical form for hashing. Floats are hashed as 9-significant-digit text: Godot 4.5's JSON
## number parser is not correctly rounded (0.03 -> 0.029999999999999988 -> ...982 over repeated
## round trips), so full-precision hashes of parsed floats are not stable. Weights are exact
## (base64), so this only coarsens the integrity check of display metadata.
static func canonical(v):
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and floorf(f) == f and absf(f) < 9.0e15:
				return int(f)
			return sig_text(f)
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[str(k)] = canonical(v[k])
			return out
		TYPE_ARRAY:
			var arr := []
			for e in v:
				arr.append(canonical(e))
			return arr
	return v


## A float as "<integer mantissa>e<exponent>" with 9 significant digits ("nan"/"inf" if not finite).
static func sig_text(f: float) -> String:
	if is_nan(f):
		return "nan"
	if is_inf(f):
		return "inf" if f > 0.0 else "-inf"
	if f == 0.0:
		return "0"
	var e := floori(log(absf(f)) / log(10.0))
	var shift := 8 - e
	var m := roundf(f * pow(10.0, shift))
	return "%de%d" % [int(m), -shift]


## sha256 over the canonical JSON of every top-level field except "checksum" and "_*" keys.
static func canonical_hash(d: Dictionary) -> String:
	var clean := {}
	for k in d:
		var ks := str(k)
		if ks == "checksum" or ks.begins_with("_"):
			continue
		clean[ks] = d[k]
	return JSON.stringify(canonical(clean), "", true, true).sha256_text()


static func _is_int(v) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(float(v)) and floorf(float(v)) == float(v))


static func _str_field(d: Dictionary, key: String, max_len: int, errors: PackedStringArray, required := true) -> String:
	if not d.has(key):
		if required:
			errors.append("missing field '%s'" % key)
		return ""
	if typeof(d[key]) != TYPE_STRING:
		errors.append("field '%s' must be a string" % key)
		return ""
	var s: String = d[key]
	if s.length() > max_len:
		errors.append("field '%s' is too long (%d > %d characters)" % [key, s.length(), max_len])
		return ""
	return s


## Strictly validates a parsed policy dictionary.
## Returns {ok: bool, policy: PolicyData|null, errors: PackedStringArray, warnings: PackedStringArray}.
static func from_dict(d, expect_creature := "") -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var res := {"ok": false, "policy": null, "errors": errors, "warnings": warnings}
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("not a JSON object")
		return res
	var dd: Dictionary = d
	if str(dd.get("format", "")) != FORMAT:
		errors.append("not a Critterweight policy (format '%s')" % str(dd.get("format", "")))
		return res
	if not _is_int(dd.get("format_version")):
		errors.append("missing or invalid format_version")
		return res
	var fv := int(dd["format_version"])
	if fv > FORMAT_VERSION:
		errors.append("policy format v%d was made by a newer version of the game (this build reads v%d)" % [fv, FORMAT_VERSION])
		return res
	if fv < 1:
		errors.append("invalid format_version %d" % fv)
		return res
	var p := PolicyData.new()
	p.id = _str_field(dd, "id", 96, errors)
	if p.id != "" and not RegEx.create_from_string(ID_REGEX).search(p.id):
		errors.append("invalid id '%s' (letters, digits, _ . : - only)" % p.id)
	p.name = _str_field(dd, "name", 64, errors).strip_escapes()
	p.creature = _str_field(dd, "creature", 96, errors)
	if p.creature != "" and not RegEx.create_from_string(ID_REGEX).search(p.creature):
		errors.append("invalid creature id '%s'" % p.creature)
	p.created = _str_field(dd, "created", 40, errors, false)
	p.updated = _str_field(dd, "updated", 40, errors, false)
	p.description = _str_field(dd, "description", 500, errors, false)
	p.creature_signature = _str_field(dd, "creature_signature", 64, errors, false)
	if _is_int(dd.get("version")) and int(dd["version"]) >= 1 and int(dd["version"]) <= 1000000:
		p.version = int(dd["version"])
	else:
		errors.append("missing or invalid 'version'")
	# ---- contracts ----
	var obs = dd.get("obs")
	if typeof(obs) != TYPE_DICTIONARY:
		errors.append("missing 'obs' contract")
	else:
		if str(obs.get("version", "")) != PolicyObs.VERSION:
			errors.append("incompatible observation contract '%s' (this build uses %s)" % [str(obs.get("version", "")), PolicyObs.VERSION])
		if not _is_int(obs.get("size")) or int(obs["size"]) != PolicyObs.SIZE:
			errors.append("observation size %s does not match %s (%d)" % [str(obs.get("size", "?")), PolicyObs.VERSION, PolicyObs.SIZE])
		var lag = obs.get("target_lag", 1)
		if not _is_int(lag) or int(lag) < 0 or int(lag) > 1:
			errors.append("obs.target_lag must be 0 or 1")
		else:
			p.target_lag = int(lag)
	var act = dd.get("act")
	if typeof(act) != TYPE_DICTIONARY:
		errors.append("missing 'act' contract")
	else:
		if str(act.get("version", "")) != PolicyActions.VERSION:
			errors.append("incompatible action contract '%s' (this build uses %s)" % [str(act.get("version", "")), PolicyActions.VERSION])
		var heads = act.get("heads")
		if typeof(heads) != TYPE_ARRAY or heads.size() != 2 or not _is_int(heads[0]) or not _is_int(heads[1]) \
				or int(heads[0]) != PolicyActions.MOVE_COUNT or int(heads[1]) != PolicyActions.BUTTON_COUNT:
			errors.append("action heads must be [%d, %d]" % [PolicyActions.MOVE_COUNT, PolicyActions.BUTTON_COUNT])
		var hz = act.get("decision_hz", PolicyActions.DEFAULT_DECISION_HZ)
		if not _is_int(hz) or int(hz) < 5 or int(hz) > 30:
			errors.append("act.decision_hz must be an integer 5..30")
		else:
			p.decision_hz = int(hz)
		var mode := str(act.get("mode", "argmax"))
		if not MODES.has(mode):
			errors.append("act.mode must be argmax or sample")
		else:
			p.act_mode = mode
		var temp = act.get("temperature", 1.0)
		if typeof(temp) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(temp)) or float(temp) < 0.05 or float(temp) > 5.0:
			errors.append("act.temperature must be 0.05..5")
		else:
			p.temperature = float(temp)
		var mask = act.get("mask", [])
		p.button_mask.resize(PolicyActions.BUTTON_COUNT)
		p.button_mask.fill(1)
		if typeof(mask) == TYPE_ARRAY and mask.size() == PolicyActions.BUTTON_COUNT:
			for k in PolicyActions.BUTTON_COUNT:
				if not _is_int(mask[k]) or int(mask[k]) not in [0, 1]:
					errors.append("act.mask entries must be 0 or 1")
					break
				p.button_mask[k] = int(mask[k])
		elif typeof(mask) != TYPE_ARRAY or not (mask as Array).is_empty():
			errors.append("act.mask must list %d entries" % PolicyActions.BUTTON_COUNT)
	# ---- architecture + weights ----
	var arch = dd.get("arch")
	var hidden := PackedInt32Array()
	var activation := "tanh"
	var arch_ok := false
	if typeof(arch) != TYPE_DICTIONARY:
		errors.append("missing 'arch'")
	elif str(arch.get("type", "")) != "mlp":
		errors.append("unsupported architecture type '%s'" % str(arch.get("type", "")))
	else:
		var hs = arch.get("hidden", [])
		var hs_ok := typeof(hs) == TYPE_ARRAY and (hs as Array).size() <= PolicyMLP.MAX_HIDDEN_LAYERS
		if hs_ok:
			for h in hs:
				if not _is_int(h):
					hs_ok = false
					break
				hidden.append(int(h))
		if not hs_ok:
			errors.append("arch.hidden must be a list of up to %d integers" % PolicyMLP.MAX_HIDDEN_LAYERS)
		activation = str(arch.get("activation", "tanh"))
		var n_in = arch.get("inputs")
		var n_out = arch.get("outputs")
		if not _is_int(n_in) or int(n_in) != PolicyObs.SIZE:
			errors.append("arch.inputs must equal the observation size %d" % PolicyObs.SIZE)
		elif not _is_int(n_out) or int(n_out) != PolicyActions.OUTPUTS:
			errors.append("arch.outputs must equal %d" % PolicyActions.OUTPUTS)
		elif hs_ok:
			var why := PolicyMLP.validate_arch(int(n_in), hidden, int(n_out), activation)
			if why != "":
				errors.append("arch: " + why)
			else:
				arch_ok = true
	var w = dd.get("weights")
	if typeof(w) != TYPE_DICTIONARY:
		errors.append("missing 'weights'")
	elif arch_ok:
		var expected := PolicyMLP.count_params(PolicyObs.SIZE, hidden, PolicyActions.OUTPUTS)
		if str(w.get("encoding", "")) != WEIGHT_ENCODING:
			errors.append("unsupported weight encoding '%s'" % str(w.get("encoding", "")))
		elif not _is_int(w.get("count")) or int(w["count"]) != expected:
			errors.append("weight count %s does not match the architecture (%d)" % [str(w.get("count", "?")), expected])
		elif typeof(w.get("data")) != TYPE_STRING:
			errors.append("weights.data must be a base64 string")
		else:
			var s: String = w["data"]
			if s.length() != ((expected * 4 + 2) / 3) * 4 or s.length() % 4 != 0 or not RegEx.create_from_string(B64_REGEX).search(s):
				errors.append("weights.data has the wrong length or is not valid base64")
			else:
				var vals := Marshalls.base64_to_raw(s).to_float32_array()
				if vals.size() != expected:
					errors.append("weights decode to %d values, expected %d" % [vals.size(), expected])
				else:
					var bad := 0
					for x in vals:
						if not is_finite(x) or absf(x) > MAX_ABS_WEIGHT:
							bad += 1
					if bad > 0:
						errors.append("%d weights are NaN, infinite or absurdly large" % bad)
					else:
						p.net = PolicyMLP.new()
						p.net.configure(PolicyObs.SIZE, hidden, PolicyActions.OUTPUTS, activation)
						p.net.params = vals
	var tr = dd.get("training", {})
	if typeof(tr) != TYPE_DICTIONARY:
		errors.append("'training' must be an object")
	elif JSON.stringify(tr).length() > MAX_META_BYTES:
		errors.append("training metadata is too large")
	else:
		p.training = tr
	var cs = dd.get("checksum")
	if typeof(cs) != TYPE_STRING:
		errors.append("missing checksum")
	elif errors.is_empty() and canonical_hash(dd) != str(cs):
		errors.append("checksum mismatch: the file was damaged or edited by hand")
	if expect_creature != "" and p.creature != "" and p.creature != expect_creature:
		errors.append("policy is for '%s', not '%s'" % [p.creature, expect_creature])
	if not errors.is_empty():
		return res
	res["ok"] = true
	res["policy"] = p
	return res
