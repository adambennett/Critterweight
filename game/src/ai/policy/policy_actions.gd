class_name PolicyActions
extends RefCounted
## act_v1 — the discrete, factorized action contract shared by AI Lab training, recording and
## live matches (docs/AI_LAB.md "Action contract").
##
## A policy decides at `decision_hz` (default 15 Hz = every 8 physics ticks at 120 Hz) and picks
## one MOVE class and one BUTTON class; the choice is repeated (held) until the next decision.
##  * MOVE (9): direction relative to the TARGET (the fighter's current soft-lock target, or its
##    own facing when it has none), expressed in fighter space (+Z toward the target, +X = the
##    fighter's LEFT). Converted to the world-space FighterInput.move at decision time.
##  * BUTTON (12): what happens to the buttons during the window. Taps press on the first tick
##    and release on the next; holds keep the button down for the whole window. A hold that
##    continues the previous decision's hold does not re-press (so charging/guarding continues).
##    `guard_tap` releases guard for one tick and then presses + holds it, which is what opens the
##    parry window in Fighter (a guard press while already guarding does not parry).
## The network emits 21 logits: [0..8] move head, [9..20] button head.
## Invariant (tested): classify_* (the inverse map used to label recorded play) returns the same
## classes that `apply` produced.

const VERSION := "act_v1"
const MOVE_COUNT := 9
const BUTTON_COUNT := 12
const OUTPUTS := MOVE_COUNT + BUTTON_COUNT
const DEFAULT_DECISION_HZ := 15

const MOVE_NAMES: PackedStringArray = ["none", "toward", "away", "left", "right", "toward_left", "toward_right", "away_left", "away_right"]
const BUTTON_NAMES: PackedStringArray = ["none", "light", "heavy", "heavy_hold", "guard_hold", "guard_tap", "dodge", "grab", "ability1", "ability2", "juice", "taunt"]

const B_NONE := 0
const B_LIGHT := 1
const B_HEAVY := 2
const B_HEAVY_HOLD := 3
const B_GUARD_HOLD := 4
const B_GUARD_TAP := 5
const B_DODGE := 6
const B_GRAB := 7
const B_AB1 := 8
const B_AB2 := 9
const B_JUICE := 10
const B_TAUNT := 11

## Fighter-relative unit direction per move class: x = toward the fighter's LEFT, y = toward target.
const MOVE_DIRS: Array[Vector2] = [Vector2(0, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0),
	Vector2(0.70710678, 0.70710678), Vector2(-0.70710678, 0.70710678), Vector2(0.70710678, -0.70710678), Vector2(-0.70710678, -0.70710678)]

## FighterInput button pressed on the window's press tick (-1 = none).
const PRESS: PackedInt32Array = [-1, FighterInput.LIGHT, FighterInput.HEAVY, FighterInput.HEAVY, -1, FighterInput.GUARD,
	FighterInput.DODGE, FighterInput.GRAB, FighterInput.AB1, FighterInput.AB2, FighterInput.JUICE, FighterInput.TAUNT]
## FighterInput button held for the whole window (-1 = none).
const HOLD: PackedInt32Array = [-1, -1, -1, FighterInput.HEAVY, FighterInput.GUARD, FighterInput.GUARD, -1, -1, -1, -1, -1, -1]

## Stick magnitude below which a recorded move counts as "none".
const MOVE_DEADZONE := 0.3


static func decision_ticks(decision_hz: int) -> int:
	var tps := Engine.physics_ticks_per_second
	return maxi(1, int(round(float(tps) / float(clampi(decision_hz, 1, tps)))))


## Horizontal reference frame for a fighter's relative actions: [toward, left] unit vectors.
## `toward` points at the target's position (as given) or along the fighter's facing.
static func frame(f: Fighter, target_pos = null) -> Array:
	var fwd := f.forward()
	if target_pos != null:
		var to: Vector3 = (target_pos as Vector3) - f.pos()
		to.y = 0.0
		if to.length_squared() > 1e-4:
			fwd = to.normalized()
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-8 else Vector3.BACK
	# fighter space: +X is the creature's left; for a facing vector (fx, 0, fz) that is (fz, 0, -fx)
	var left := Vector3(fwd.z, 0.0, -fwd.x)
	return [fwd, left]


## World-space stick vector (length 0 or 1) for a move class in the given frame.
static func move_world(move_class: int, fwd: Vector3, left: Vector3) -> Vector3:
	if move_class <= 0 or move_class >= MOVE_COUNT:
		return Vector3.ZERO
	var d: Vector2 = MOVE_DIRS[move_class]
	return (left * d.x + fwd * d.y).normalized()


## Inverse of move_world: the move class whose direction is closest to a world stick vector.
static func classify_move(world_move: Vector3, fwd: Vector3, left: Vector3) -> int:
	var flat := Vector3(world_move.x, 0.0, world_move.z)
	if flat.length() < MOVE_DEADZONE:
		return 0
	var lx := flat.dot(left)
	var lz := flat.dot(fwd)
	var v := Vector2(lx, lz).normalized()
	var best := 1
	var best_dot := -INF
	for k in range(1, MOVE_COUNT):
		var d := v.dot(MOVE_DIRS[k])
		if d > best_dot + 1e-6:
			best_dot = d
			best = k
	return best


## Which button classes a creature can use (1 = allowed). Missing ability slots are masked so a
## policy never wastes decisions on them; dynamic availability (cooldowns, hype) is observed.
static func button_mask(c: CreatureDef) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(BUTTON_COUNT)
	m.fill(1)
	if c != null:
		if not c.abilities.has("ability1"):
			m[B_AB1] = 0
		if not c.abilities.has("ability2"):
			m[B_AB2] = 0
		if not c.abilities.has("juice"):
			m[B_JUICE] = 0
		if not c.moves.has("grab"):
			m[B_GRAB] = 0
	return m


## Writes one tick of a decided action into a FighterInput.
##   tick_in_window: 0 on the decision tick, then 1, 2, ...
##   prev_button: the button class of the previous window (hold continuation / guard re-tap)
static func apply_tick(fi: FighterInput, move_vec: Vector3, button: int, prev_button: int, tick_in_window: int) -> void:
	fi.move = move_vec
	var held := 0
	var hb: int = HOLD[button]
	if hb >= 0:
		held = 1 << hb
	if button == B_GUARD_TAP:
		# release on the first tick so the press re-enters guard with a fresh parry window
		if tick_in_window == 0:
			held = 0
		fi.held = held
		if tick_in_window == 1:
			fi.press(FighterInput.GUARD)
		return
	fi.held = held
	if tick_in_window == 0:
		var pb: int = PRESS[button]
		if pb >= 0:
			var continuing := button == B_HEAVY_HOLD and prev_button == B_HEAVY_HOLD
			if not continuing:
				fi.press(pb)


## Labels one decision window of observed input (used by the recorder):
##   presses: bitmask of FighterInput buttons newly pressed during the window
##   held_ticks: per FighterInput button, how many ticks of the window it was held
##   window: number of ticks in the window
##   prev_button: the label of the previous window (distinguishes continued holds)
static func classify_button(presses: int, held_ticks: PackedInt32Array, window: int, prev_button: int) -> int:
	var half := maxi(1, window / 2)
	if (presses >> FighterInput.JUICE) & 1:
		return B_JUICE
	if (presses >> FighterInput.AB1) & 1:
		return B_AB1
	if (presses >> FighterInput.AB2) & 1:
		return B_AB2
	if (presses >> FighterInput.GRAB) & 1:
		return B_GRAB
	if (presses >> FighterInput.DODGE) & 1:
		return B_DODGE
	if (presses >> FighterInput.HEAVY) & 1:
		return B_HEAVY_HOLD if held_ticks[FighterInput.HEAVY] >= half else B_HEAVY
	if (presses >> FighterInput.LIGHT) & 1:
		return B_LIGHT
	if (presses >> FighterInput.GUARD) & 1:
		return B_GUARD_TAP
	if (presses >> FighterInput.TAUNT) & 1:
		return B_TAUNT
	if held_ticks[FighterInput.HEAVY] >= half and prev_button in [B_HEAVY, B_HEAVY_HOLD]:
		return B_HEAVY_HOLD
	if held_ticks[FighterInput.GUARD] >= half:
		return B_GUARD_HOLD
	return B_NONE


## Picks a class from a logit slice. mode "argmax" (deterministic) or "sample" (softmax with
## temperature, using `rng`). Masked classes (mask[k] == 0) are never chosen.
static func choose(logits: PackedFloat32Array, offset: int, count: int, mask: PackedByteArray, mode: String, temperature: float, rng: RandomNumberGenerator) -> int:
	var best := -1
	var best_v := -INF
	for k in count:
		if not mask.is_empty() and mask[k] == 0:
			continue
		var v := logits[offset + k]
		if v > best_v:
			best_v = v
			best = k
	if best < 0:
		return 0
	if mode != "sample" or rng == null:
		return best
	var t := maxf(temperature, 0.05)
	var total := 0.0
	var probs := PackedFloat32Array()
	probs.resize(count)
	for k in count:
		if not mask.is_empty() and mask[k] == 0:
			continue
		var p := exp((logits[offset + k] - best_v) / t)
		probs[k] = p
		total += p
	var r := rng.randf() * total
	for k in count:
		r -= probs[k]
		if r <= 0.0 and probs[k] > 0.0:
			return k
	return best


## Softmax probabilities of one head (masked classes get 0).
static func head_probs(logits: PackedFloat32Array, offset: int, count: int, mask: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	var mx := -INF
	for k in count:
		if mask.is_empty() or mask[k] != 0:
			mx = maxf(mx, logits[offset + k])
	var total := 0.0
	for k in count:
		if mask.is_empty() or mask[k] != 0:
			var p := exp(logits[offset + k] - mx)
			out[k] = p
			total += p
	if total > 0.0:
		for k in count:
			out[k] /= total
	return out
