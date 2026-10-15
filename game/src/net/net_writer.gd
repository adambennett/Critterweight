class_name NetWriter
extends RefCounted
## Little-endian binary writer for protocol messages (pairs with NetReader).
## Quantized types:
##   vec3q  : 3 x int16, 1/1024 m steps, range +-32 m (positions, normals)
##   quat32 : smallest-three quaternion in 32 bits (2-bit index + 3 x 10 bits), < 0.15 deg error
##   varint : unsigned LEB128 (1..5 bytes); svarint: zig-zag signed varint

const POS_SCALE := 1024.0
const POS_LIMIT := 32767
const QUAT_RANGE := 0.70710678
const QUAT_MAX := 1023.0

var buf := StreamPeerBuffer.new()


func _init(msg_id := -1) -> void:
	buf.big_endian = false
	if msg_id >= 0:
		buf.put_u8(msg_id)


func size() -> int:
	return buf.get_size()


func data() -> PackedByteArray:
	return buf.data_array


func u8(v: int) -> NetWriter:
	buf.put_u8(v & 0xFF)
	return self


func i8(v: int) -> NetWriter:
	buf.put_8(clampi(v, -128, 127))
	return self


func u16(v: int) -> NetWriter:
	buf.put_u16(v & 0xFFFF)
	return self


func i16(v: int) -> NetWriter:
	buf.put_16(clampi(v, -32768, 32767))
	return self


func u32(v: int) -> NetWriter:
	buf.put_u32(v & 0xFFFFFFFF)
	return self


func i32(v: int) -> NetWriter:
	buf.put_32(v)
	return self


func u64(v: int) -> NetWriter:
	buf.put_u64(v)
	return self


func f32(v: float) -> NetWriter:
	buf.put_float(v if is_finite(v) else 0.0)
	return self


func boolean(v: bool) -> NetWriter:
	buf.put_u8(1 if v else 0)
	return self


func varint(v: int) -> NetWriter:
	var x := v & 0xFFFFFFFF
	while x >= 0x80:
		buf.put_u8((x & 0x7F) | 0x80)
		x >>= 7
	buf.put_u8(x)
	return self


func svarint(v: int) -> NetWriter:
	var z := (v << 1) ^ (v >> 63)
	return varint(z & 0xFFFFFFFF)


## UTF-8 string with a u8 (or u16 when `wide`) byte-length prefix, truncated to max_bytes
## without splitting a character.
func text(s: String, max_bytes := 255, wide := false) -> NetWriter:
	var b := s.to_utf8_buffer()
	var cap := mini(max_bytes, 65535 if wide else 255)
	if b.size() > cap:
		var t := s
		while t.to_utf8_buffer().size() > cap and t.length() > 0:
			t = t.substr(0, t.length() - 1)
		b = t.to_utf8_buffer()
	if wide:
		buf.put_u16(b.size())
	else:
		buf.put_u8(b.size())
	buf.put_data(b)
	return self


## Raw bytes with a u16 (or u32 when `wide`) length prefix.
func blob(b: PackedByteArray, wide := false) -> NetWriter:
	if wide:
		buf.put_u32(b.size())
	else:
		buf.put_u16(mini(b.size(), 65535))
		if b.size() > 65535:
			b = b.slice(0, 65535)
	buf.put_data(b)
	return self


## Raw bytes without a prefix (caller knows the length).
func raw(b: PackedByteArray) -> NetWriter:
	buf.put_data(b)
	return self


func vec3q(v: Vector3) -> NetWriter:
	buf.put_16(clampi(roundi(v.x * POS_SCALE), -POS_LIMIT, POS_LIMIT))
	buf.put_16(clampi(roundi(v.y * POS_SCALE), -POS_LIMIT, POS_LIMIT))
	buf.put_16(clampi(roundi(v.z * POS_SCALE), -POS_LIMIT, POS_LIMIT))
	return self


func quat32(q: Quaternion) -> NetWriter:
	buf.put_u32(pack_quat(q))
	return self


static func pack_quat(q_in: Quaternion) -> int:
	var q := q_in.normalized() if q_in.length_squared() > 1e-12 else Quaternion.IDENTITY
	var comps := [q.x, q.y, q.z, q.w]
	var big := 0
	var big_abs := absf(q.x)
	for i in range(1, 4):
		var a := absf(float(comps[i]))
		if a > big_abs:
			big_abs = a
			big = i
	var sgn := -1.0 if float(comps[big]) < 0.0 else 1.0
	var packed := big << 30
	var shift := 20
	for i in 4:
		if i == big:
			continue
		var c := float(comps[i]) * sgn
		var qv := clampi(roundi((c + QUAT_RANGE) / (2.0 * QUAT_RANGE) * QUAT_MAX), 0, int(QUAT_MAX))
		packed |= qv << shift
		shift -= 10
	return packed


static func unpack_quat(packed: int) -> Quaternion:
	var big := (packed >> 30) & 3
	var vals := [0.0, 0.0, 0.0, 0.0]
	var shift := 20
	var sum := 0.0
	for i in 4:
		if i == big:
			continue
		var qv := (packed >> shift) & 0x3FF
		var c := float(qv) / QUAT_MAX * 2.0 * QUAT_RANGE - QUAT_RANGE
		vals[i] = c
		sum += c * c
		shift -= 10
	vals[big] = sqrt(maxf(0.0, 1.0 - sum))
	var q := Quaternion(float(vals[0]), float(vals[1]), float(vals[2]), float(vals[3]))
	return q.normalized()
