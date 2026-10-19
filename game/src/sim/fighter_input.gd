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
const TAG := 10
const MMA_LL := 11
const MMA_RL := 12
const MMA_MOD1 := 13
const MMA_MOD2 := 14
const MMA_MOD3 := 15
const MMA_STANCE := 16
const MMA_CHECK := 17
const BUTTON_COUNT := 18
const CORE_BUTTON_COUNT := 11
const WIRE_EXTENDED := 1 << 31
const BUTTON_NAMES := ["light", "heavy", "guard", "dodge", "grab", "ability1", "ability2", "juice", "taunt", "target", "tag", "mma_ll", "mma_rl", "mma_mod1", "mma_mod2", "mma_mod3", "mma_stance", "mma_check"]

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


## Core fighters use 11 counters; guest samples append seven only when needed.
## The held word's reserved top bit marks that extension, including a released press.
func wire_counter_count() -> int:
	if held & (((1 << BUTTON_COUNT) - 1) ^ ((1 << CORE_BUTTON_COUNT) - 1)):
		return BUTTON_COUNT
	for i in range(CORE_BUTTON_COUNT, mini(press_count.size(), BUTTON_COUNT)):
		if press_count[i] != 0:
			return BUTTON_COUNT
	return CORE_BUTTON_COUNT


## Compact serialization: two movement axes + u32 held/extension word + 11 or 18 counters.
func encode(buf: StreamPeerBuffer) -> void:
	buf.put_8(int(clampf(move.x, -1.0, 1.0) * 127.0))
	buf.put_8(int(clampf(move.z, -1.0, 1.0) * 127.0))
	var count := wire_counter_count()
	buf.put_u32((held & ((1 << BUTTON_COUNT) - 1)) | (WIRE_EXTENDED if count == BUTTON_COUNT else 0))
	buf.put_data(press_count.slice(0, count))


static func decode(buf: StreamPeerBuffer) -> FighterInput:
	var i := FighterInput.new()
	i.move = Vector3(buf.get_8() / 127.0, 0.0, buf.get_8() / 127.0)
	if i.move.length() > 1.0:
		i.move = i.move.normalized()
	var word := buf.get_u32()
	i.held = word & ((1 << BUTTON_COUNT) - 1)
	var count := BUTTON_COUNT if word & WIRE_EXTENDED else CORE_BUTTON_COUNT
	var res: Array = buf.get_data(count)
	if res[0] == OK:
		for b in count:
			i.press_count[b] = res[1][b]
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
