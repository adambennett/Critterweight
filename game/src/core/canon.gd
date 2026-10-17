class_name Canon
extends RefCounted
## Platform-independent hashing of JSON-like data. Godot 4.5.1's JSON.stringify writes the same double
## with 17 significant digits on Windows and 18 on Linux ("1.6000000000000001" against
## "1.60000000000000009"), so a hash over JSON text with fractional numbers differed between platforms for
## identical data: a Linux dedicated server refused Windows players' arenas at the start of a match.
## Here whole floats become ints (JSON reads every number back as a float) and every other float its exact
## IEEE-754 bytes (var_to_bytes is Godot's own little-endian encoding, the same on every platform);
## JSON.stringify then only writes ints, strings and structure, with sorted keys.

const MAX_EXACT_INT := 9007199254740991.0   ## 2^53 - 1: every whole number up to here is an exact double


## sha256 of the platform-independent form of `v`.
static func sha256(v) -> String:
	return JSON.stringify(form(v), "", true, true).sha256_text()


## `v` with every float replaced by an int (whole) or "f:<hex of its bytes>" (anything else),
## recursively through dictionaries (keys as strings), arrays, packed arrays and vectors.
static func form(v):
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and floorf(f) == f and absf(f) <= MAX_EXACT_INT:
				return int(f)
			return "f:" + var_to_bytes(f).hex_encode()
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[str(k)] = form(v[k])
			return out
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			var arr := []
			for e in v:
				arr.append(form(e))
			return arr
		TYPE_VECTOR2:
			return form([v.x, v.y])
		TYPE_VECTOR3:
			return form([v.x, v.y, v.z])
	return v
