class_name NetEventCodec
## Compact, loss-free encoding of simulation events (the dictionaries MatchSim.emit_event()
## produces) for the reliable events channel, plus the generic tagged value codec also used for
## mode view/HUD state in snapshots.
##
## Batch: [u32 base_tick][u8 count] then per event:
##   [type: u8 index into TYPES | 0xFF + string][svarint tick - base_tick][u8 field count]
##   per field: [key: u8 index into KEYS | 0xFF + string][tagged value]
## Tagged values: null, bool, int (zig-zag varint), float (f32), string (u8 len) or common string
## (u8 index), Vector2, Vector3 (quantized 1 mm, or 3 x f32 outside +-32 m / non-finite), Color,
## Array (<= 256), Dictionary (<= 128, String or int keys). Depth <= 8, <= 4096 values per decode.
## Unknown event types and keys still travel (as strings), so new events added by other systems
## replicate without protocol changes; known ones cost one byte. "seq" is implicit; "seed" and
## the other PRIVATE_KEYS never leave the server (randomness stays server-owned).

const TYPES := ["hit", "glance", "grab_tech", "effect", "reflect", "reaction", "juice_end", "ability",
	"taunt", "move_start", "dodge", "knockdown", "getup", "ko", "downed", "revived", "juice", "grab",
	"throw", "grab_escape", "parry", "guard_break", "burst", "match_start", "ringout", "slam",
	"round_reset", "round_intro", "round_start", "match_end", "elimination", "respawn", "timeout",
	"round_end", "status", "fighter_spawned", "fighter_despawned", "fighter_rebuilt", "goal",
	"unit_crowned", "unit_toppled", "unit_transforming", "wave_start", "wave_cleared", "pick_offered",
	"pick_taken", "tag", "reaction_zone", "carry", "throw_ball"]
const KEYS := ["fighter", "target", "victim", "attacker", "damage", "point", "normal", "pos", "blocked",
	"parried", "counter", "part", "element", "quality", "move", "slot", "knockdown", "otg", "effect",
	"vfx", "reaction", "name", "a", "b", "id", "reason", "arena", "mode", "speed", "round", "winner",
	"by", "status", "creature", "team", "scale", "wave", "upgrade", "score", "kind", "amount", "dir"]
const COMMON := ["", "core", "head", "arm", "leg", "tail", "wing", "shell", "horn", "fin", "l1", "l2",
	"l3", "heavy", "finisher", "dash_attack", "grab", "taunt", "juice", "ability1", "ability2", "effect",
	"zone", "pummel", "throw", "slam", "reaction", "projectile", "area", "buff", "debuff", "heal",
	"shield", "dash", "leap", "pull", "push", "blink", "prop", "self_damage", "cleanse", "hype", "orb",
	"burst", "hit", "move", "poise", "standard", "dodge", "spark", "label", "value", "rows", "mode",
	"downed", "left", "revive", "fighter", "team", "pos"]
const PRIVATE_KEYS := ["seed"]
const IMPLICIT_KEYS := ["type", "seq", "tick"]

const T_NULL := 0
const T_FALSE := 1
const T_TRUE := 2
const T_INT := 3
const T_FLOAT := 4
const T_STR := 5
const T_VEC3 := 6
const T_COMMON := 7
const T_VEC3F := 8
const T_ARRAY := 9
const T_DICT := 10
const T_VEC2 := 11
const T_COLOR := 12

const MAX_FIELDS := 32
const MAX_STR := 120
const MAX_KEY := 32
const MAX_PER_BATCH := 200
const MAX_DEPTH := 8
const MAX_ARRAY := 256
const MAX_DICT := 128
const MAX_VALUES := 4096

static var _type_idx := {}
static var _key_idx := {}
static var _common_idx := {}


static func _tables() -> void:
	if not _type_idx.is_empty():
		return
	for i in TYPES.size():
		_type_idx[TYPES[i]] = i
	for i in KEYS.size():
		_key_idx[KEYS[i]] = i
	for i in COMMON.size():
		_common_idx[COMMON[i]] = i


## Writes events (already filtered by the caller) as one batch. Returns the number encoded.
static func encode_batch(w: NetWriter, events: Array, base_tick: int) -> int:
	_tables()
	var n := mini(events.size(), MAX_PER_BATCH)
	w.u32(base_tick)
	w.u8(n)
	for i in n:
		_encode_event(w, events[i], base_tick)
	return n


static func _encode_event(w: NetWriter, ev: Dictionary, base_tick: int) -> void:
	var t := str(ev.get("type", ""))
	if _type_idx.has(t):
		w.u8(int(_type_idx[t]))
	else:
		w.u8(0xFF)
		w.text(t, MAX_KEY)
	w.svarint(int(ev.get("tick", base_tick)) - base_tick)
	var keys: Array = []
	for k in ev.keys():
		var ks := str(k)
		if ks in IMPLICIT_KEYS or ks in PRIVATE_KEYS:
			continue
		keys.append(ks)
		if keys.size() >= MAX_FIELDS:
			break
	w.u8(keys.size())
	for ks: String in keys:
		if _key_idx.has(ks):
			w.u8(int(_key_idx[ks]))
		else:
			w.u8(0xFF)
			w.text(ks, MAX_KEY)
		encode_value(w, ev[ks])


## Generic tagged value (see class comment). Objects are written as their text.
static func encode_value(w: NetWriter, v, depth := 0) -> void:
	_tables()
	match typeof(v):
		TYPE_NIL:
			w.u8(T_NULL)
		TYPE_BOOL:
			w.u8(T_TRUE if v else T_FALSE)
		TYPE_INT:
			var iv: int = v
			if iv >= -2147483648 and iv <= 2147483647:
				w.u8(T_INT)
				w.svarint(iv)
			else:
				w.u8(T_FLOAT)
				w.buf.put_float(float(iv))
		TYPE_FLOAT:
			w.u8(T_FLOAT)
			w.buf.put_float(float(v))
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(v)
			if _common_idx.has(s):
				w.u8(T_COMMON)
				w.u8(int(_common_idx[s]))
			else:
				w.u8(T_STR)
				w.text(s, MAX_STR)
		TYPE_VECTOR3, TYPE_VECTOR3I:
			var p := Vector3(v)
			if p.is_finite() and absf(p.x) < 31.9 and absf(p.y) < 31.9 and absf(p.z) < 31.9:
				w.u8(T_VEC3)
				w.vec3q(p)
			else:
				w.u8(T_VEC3F)
				w.buf.put_float(p.x)
				w.buf.put_float(p.y)
				w.buf.put_float(p.z)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			var q := Vector2(v)
			w.u8(T_VEC2)
			w.buf.put_float(q.x)
			w.buf.put_float(q.y)
		TYPE_COLOR:
			var c: Color = v
			w.u8(T_COLOR)
			w.u8(clampi(roundi(c.r * 255.0), 0, 255))
			w.u8(clampi(roundi(c.g * 255.0), 0, 255))
			w.u8(clampi(roundi(c.b * 255.0), 0, 255))
			w.u8(clampi(roundi(c.a * 255.0), 0, 255))
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			if depth >= MAX_DEPTH:
				w.u8(T_NULL)
				return
			var arr: Array = Array(v)
			var n := mini(arr.size(), MAX_ARRAY)
			w.u8(T_ARRAY)
			w.u16(n)
			for i in n:
				encode_value(w, arr[i], depth + 1)
		TYPE_DICTIONARY:
			if depth >= MAX_DEPTH:
				w.u8(T_NULL)
				return
			var d: Dictionary = v
			var keys: Array = []
			for k in d.keys():
				if typeof(k) == TYPE_STRING or typeof(k) == TYPE_STRING_NAME or typeof(k) == TYPE_INT:
					keys.append(k)
				if keys.size() >= MAX_DICT:
					break
			w.u8(T_DICT)
			w.u8(keys.size())
			for k in keys:
				encode_value(w, k if typeof(k) == TYPE_INT else str(k), depth + 1)
				encode_value(w, d[k], depth + 1)
		_:
			w.u8(T_STR)
			w.text(str(v), MAX_STR)


## Decodes one batch; returns [] (and sets r.ok = false) on malformed input.
static func decode_batch(r: NetReader) -> Array:
	_tables()
	var out: Array = []
	var base := r.u32()
	var n := r.count(MAX_PER_BATCH)
	var budget: Array = [MAX_VALUES * 4]
	for i in n:
		var ev := {}
		var ti := r.u8()
		if ti == 0xFF:
			ev["type"] = r.text(MAX_KEY)
		elif ti < TYPES.size():
			ev["type"] = TYPES[ti]
		else:
			r.fail("unknown event type index %d" % ti)
		ev["tick"] = base + r.svarint()
		var nf := r.count(MAX_FIELDS)
		for j in nf:
			var ki := r.u8()
			var key := ""
			if ki == 0xFF:
				key = r.text(MAX_KEY)
			elif ki < KEYS.size():
				key = KEYS[ki]
			else:
				r.fail("unknown event key index %d" % ki)
			var val = decode_value(r, 0, budget)
			if not r.ok:
				return []
			if key in IMPLICIT_KEYS:
				continue
			ev[key] = val
		if not r.ok:
			return []
		out.append(ev)
	return out


## Decodes one tagged value. `budget` is a one-element Array counting remaining values.
static func decode_value(r: NetReader, depth := 0, budget: Array = [MAX_VALUES]):
	_tables()
	budget[0] = int(budget[0]) - 1
	if int(budget[0]) < 0:
		r.fail("too many values")
		return null
	var tag := r.u8()
	match tag:
		T_NULL:
			return null
		T_FALSE:
			return false
		T_TRUE:
			return true
		T_INT:
			return r.svarint()
		T_FLOAT:
			return r.f32_any()
		T_STR:
			return r.text(MAX_STR)
		T_COMMON:
			var ci := r.u8()
			if ci >= COMMON.size():
				r.fail("unknown common string %d" % ci)
				return ""
			return COMMON[ci]
		T_VEC3:
			return r.vec3q()
		T_VEC3F:
			var x := r.f32_any()
			var y := r.f32_any()
			var z := r.f32_any()
			return Vector3(x, y, z)
		T_VEC2:
			var a := r.f32_any()
			var b := r.f32_any()
			return Vector2(a, b)
		T_COLOR:
			var cr := r.u8()
			var cg := r.u8()
			var cb := r.u8()
			var ca := r.u8()
			return Color8(cr, cg, cb, ca)
		T_ARRAY:
			if depth >= MAX_DEPTH:
				r.fail("value nested too deeply")
				return null
			var n := r.u16()
			if n > MAX_ARRAY:
				r.fail("array of %d exceeds %d" % [n, MAX_ARRAY])
				return null
			var arr: Array = []
			for i in n:
				arr.append(decode_value(r, depth + 1, budget))
				if not r.ok:
					return null
			return arr
		T_DICT:
			if depth >= MAX_DEPTH:
				r.fail("value nested too deeply")
				return null
			var nd := r.u8()
			if nd > MAX_DICT:
				r.fail("dictionary of %d exceeds %d" % [nd, MAX_DICT])
				return null
			var d := {}
			for i in nd:
				var k = decode_value(r, depth + 1, budget)
				var val = decode_value(r, depth + 1, budget)
				if not r.ok:
					return null
				if typeof(k) != TYPE_STRING and typeof(k) != TYPE_INT:
					r.fail("bad dictionary key")
					return null
				d[k] = val
			return d
	r.fail("unknown value tag %d" % tag)
	return null


## Interpolates two decoded values of the same shape (floats, vectors and colors blend;
## containers recurse; everything else switches at t = 0.5). Used for mode view state.
static func blend(a, b, t: float):
	if typeof(a) != typeof(b):
		return b if t >= 0.5 else a
	match typeof(a):
		TYPE_FLOAT:
			if is_finite(float(a)) and is_finite(float(b)):
				return lerpf(float(a), float(b), t)
		TYPE_VECTOR3:
			var va: Vector3 = a
			var vb: Vector3 = b
			if va.is_finite() and vb.is_finite() and va.distance_to(vb) < 3.0:
				return va.lerp(vb, t)
		TYPE_VECTOR2:
			var wa: Vector2 = a
			var wb: Vector2 = b
			if wa.is_finite() and wb.is_finite():
				return wa.lerp(wb, t)
		TYPE_COLOR:
			return (a as Color).lerp(b as Color, t)
		TYPE_ARRAY:
			var aa: Array = a
			var ab: Array = b
			if aa.size() == ab.size():
				var out: Array = []
				for i in aa.size():
					out.append(blend(aa[i], ab[i], t))
				return out
		TYPE_DICTIONARY:
			var da: Dictionary = a
			var db: Dictionary = b
			if da.size() == db.size():
				var out2 := {}
				for k in db:
					out2[k] = blend(da[k], db[k], t) if da.has(k) else db[k]
				return out2
	return b if t >= 0.5 else a
