class_name NetReader
extends RefCounted
## Bounds-checked little-endian reader for protocol messages (pairs with NetWriter).
## Never reads past the end: the first failure sets `ok = false` (with `error`), and every
## later read returns a zero value, so decoders can read a whole layout and check `ok` once.
## Strings, blobs and counts are validated against caller-supplied maxima.

var data := PackedByteArray()
var pos := 0
var ok := true
var error := ""


func _init(d: PackedByteArray = PackedByteArray(), start := 0) -> void:
	data = d
	pos = start


func remaining() -> int:
	return data.size() - pos


func fail(msg: String) -> void:
	if ok:
		ok = false
		error = "%s at byte %d" % [msg, pos]


func _need(n: int) -> bool:
	if not ok:
		return false
	if n < 0 or pos + n > data.size():
		fail("truncated (need %d, have %d)" % [n, data.size() - pos])
		return false
	return true


func at_end() -> bool:
	return pos >= data.size()


## Fails if unread bytes remain (strict layouts).
func expect_end() -> bool:
	if ok and pos != data.size():
		fail("%d trailing bytes" % (data.size() - pos))
	return ok


func u8() -> int:
	if not _need(1):
		return 0
	var v := data.decode_u8(pos)
	pos += 1
	return v


func i8() -> int:
	if not _need(1):
		return 0
	var v := data.decode_s8(pos)
	pos += 1
	return v


func u16() -> int:
	if not _need(2):
		return 0
	var v := data.decode_u16(pos)
	pos += 2
	return v


func i16() -> int:
	if not _need(2):
		return 0
	var v := data.decode_s16(pos)
	pos += 2
	return v


func u32() -> int:
	if not _need(4):
		return 0
	var v := data.decode_u32(pos)
	pos += 4
	return v


func i32() -> int:
	if not _need(4):
		return 0
	var v := data.decode_s32(pos)
	pos += 4
	return v


func u64() -> int:
	if not _need(8):
		return 0
	var v := data.decode_u64(pos)
	pos += 8
	return v


## 32-bit float; non-finite values are a decode failure.
func f32() -> float:
	if not _need(4):
		return 0.0
	var v := data.decode_float(pos)
	pos += 4
	if not is_finite(v):
		fail("non-finite float")
		return 0.0
	return v


## 32-bit float that may be non-finite (presentation data such as Vector3.INF markers).
func f32_any() -> float:
	if not _need(4):
		return 0.0
	var v := data.decode_float(pos)
	pos += 4
	return v


func boolean() -> bool:
	var v := u8()
	if v > 1:
		fail("invalid bool %d" % v)
	return v == 1


func varint() -> int:
	var result := 0
	var shift := 0
	for i in 5:
		var b := u8()
		if not ok:
			return 0
		result |= (b & 0x7F) << shift
		if b & 0x80 == 0:
			return result & 0xFFFFFFFF
		shift += 7
	fail("varint too long")
	return 0


func svarint() -> int:
	var z := varint()
	var v := (z >> 1) ^ -(z & 1)
	return v


## Length-prefixed UTF-8 string; fails if longer than max_bytes.
func text(max_bytes := 255, wide := false) -> String:
	var n := u16() if wide else u8()
	if not ok:
		return ""
	if n > max_bytes:
		fail("string of %d bytes exceeds %d" % [n, max_bytes])
		return ""
	if not _need(n):
		return ""
	var s := data.slice(pos, pos + n).get_string_from_utf8()
	pos += n
	return s


## Length-prefixed bytes; fails if longer than max_len.
func blob(max_len: int, wide := false) -> PackedByteArray:
	var n := u32() if wide else u16()
	if not ok:
		return PackedByteArray()
	if n > max_len:
		fail("blob of %d bytes exceeds %d" % [n, max_len])
		return PackedByteArray()
	if not _need(n):
		return PackedByteArray()
	var b := data.slice(pos, pos + n)
	pos += n
	return b


## Exactly n raw bytes.
func raw(n: int) -> PackedByteArray:
	if not _need(n):
		return PackedByteArray()
	var b := data.slice(pos, pos + n)
	pos += n
	return b


## Count prefix (u8) validated against a maximum.
func count(max_count: int) -> int:
	var n := u8()
	if n > max_count:
		fail("count %d exceeds %d" % [n, max_count])
		return 0
	return n


func vec3q() -> Vector3:
	if not _need(6):
		return Vector3.ZERO
	var x := data.decode_s16(pos)
	var y := data.decode_s16(pos + 2)
	var z := data.decode_s16(pos + 4)
	pos += 6
	return Vector3(x, y, z) / NetWriter.POS_SCALE


func quat32() -> Quaternion:
	if not _need(4):
		return Quaternion.IDENTITY
	var p := data.decode_u32(pos)
	pos += 4
	return NetWriter.unpack_quat(p)
