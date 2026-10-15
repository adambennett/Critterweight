class_name FighterInput
extends RefCounted
## One tick of intent for one fighter. This is THE input contract shared by local players,
## bots, network clients, replays and AI Lab policies (see docs/DESIGN.md "Input contract").
##
## `move` is a WORLD-space horizontal direction (y ignored), length 0..1. Camera-relative
## conversion happens in the input source, never in the simulation.
## Presses are counted per button (wrapping 0..255) so redundant network packets and bursts of
## taps between ticks are never lost or double counted.

const LIGHT := 0
const HEAVY := 1
const GUARD := 2
const DODGE := 3
const GRAB := 4
const AB1 := 5
const AB2 := 6
const JUICE := 7
const TAUNT := 8
const TARGET := 9
const BUTTON_COUNT := 10
const BUTTON_NAMES := ["light", "heavy", "guard", "dodge", "grab", "ability1", "ability2", "juice", "taunt", "target"]

var move := Vector3.ZERO
var held := 0
var press_count := PackedByteArray()


func _init() -> void:
	press_count.resize(BUTTON_COUNT)


func is_held(button: int) -> bool:
	return (held >> button) & 1 == 1


func set_held(button: int, on: bool) -> void:
	if on:
		held |= 1 << button
	else:
		held &= ~(1 << button)


## Registers a press (also sets held).
func press(button: int) -> void:
	press_count[button] = (press_count[button] + 1) & 0xFF
	set_held(button, true)


func copy_from(o: FighterInput) -> void:
	move = o.move
	held = o.held
	press_count = o.press_count.duplicate()


func duplicate_input() -> FighterInput:
	var n := FighterInput.new()
	n.copy_from(self)
	return n


## Compact serialization (network / replays): 3 floats quantized + bitmask + counters.
func encode(buf: StreamPeerBuffer) -> void:
	buf.put_8(int(clampf(move.x, -1.0, 1.0) * 127.0))
	buf.put_8(int(clampf(move.z, -1.0, 1.0) * 127.0))
	buf.put_u16(held)
	buf.put_data(press_count)


static func decode(buf: StreamPeerBuffer) -> FighterInput:
	var i := FighterInput.new()
	i.move = Vector3(buf.get_8() / 127.0, 0.0, buf.get_8() / 127.0)
	if i.move.length() > 1.0:
		i.move = i.move.normalized()
	i.held = buf.get_u16() & ((1 << BUTTON_COUNT) - 1)
	var res: Array = buf.get_data(BUTTON_COUNT)
	if res[0] == OK:
		i.press_count = res[1]
	return i


## Tracks press counters on the consuming side and yields fresh presses each tick.
class PressTracker:
	var last := PackedByteArray()
	var primed := false

	func _init() -> void:
		last.resize(FighterInput.BUTTON_COUNT)

	## Returns a bitmask of buttons pressed since the previous call.
	func consume(inp: FighterInput) -> int:
		var mask := 0
		if not primed:
			last = inp.press_count.duplicate()
			primed = true
			return 0
		for b in FighterInput.BUTTON_COUNT:
			if inp.press_count[b] != last[b]:
				mask |= 1 << b
		last = inp.press_count.duplicate()
		return mask
