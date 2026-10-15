class_name LabOpponents
extends RefCounted
## Fixed opponents for AI Lab training and evaluation. Scripted drills are deterministic for a
## given seed; bot tiers are the shipped BotBrain difficulty profiles (reaction delay, mistakes);
## "policy:<file>" plays a saved policy (self-play against an earlier version or another style).

const BASELINES: PackedStringArray = ["idle", "patrol", "jabber", "turtle", "bot_rookie", "bot_regular", "bot_pro", "bot_champion"]
const NAMES := {
	"idle": "Standing dummy", "patrol": "Patrolling dummy", "jabber": "Scripted jabber", "turtle": "Scripted turtle",
	"bot_rookie": "Bot: Rookie", "bot_regular": "Bot: Regular", "bot_pro": "Bot: Pro", "bot_champion": "Bot: Champion",
}


static func display_name(kind: String) -> String:
	if kind.begins_with("policy:"):
		return "Policy " + kind.substr(7).get_file().trim_suffix(PolicyIO.EXT)
	return str(NAMES.get(kind, kind))


static func is_valid(kind: String) -> bool:
	return BASELINES.has(kind) or kind.begins_with("policy:")


## Builds the input source for an opponent kind. Returns null for an unknown kind.
static func create(kind: String, seed_value: int, c: CreatureDef) -> InputSource:
	match kind:
		"idle":
			return Idle.new()
		"patrol":
			return Patrol.new(seed_value)
		"jabber":
			return Jabber.new(seed_value)
		"turtle":
			return Turtle.new(seed_value)
		"bot_rookie", "bot_regular", "bot_pro", "bot_champion":
			var bb := BotBrain.new(kind.substr(4), maxi(1, seed_value))
			if c != null:
				bb.set_personality(c.ai)
			return bb
	if kind.begins_with("policy:"):
		var r := PolicyIO.read_file(kind.substr(7))
		if r["ok"]:
			var src := PolicyInputSource.create(r["policy"], seed_value, 1)
			src.apply_creature_mask(c)
			return src
		Log.w("lab", "opponent policy unavailable: %s" % "; ".join(r["errors"]))
	return null


static func _to_target(f: Fighter) -> Vector3:
	if f.target == null:
		return Vector3.ZERO
	var to := f.target.pos() - f.pos()
	to.y = 0.0
	return to


## Never moves or attacks (a training dummy).
class Idle:
	extends InputSource

	func label() -> String:
		return "Dummy"

	func poll(f: Fighter, _sim, _dt: float) -> void:
		f.input.move = Vector3.ZERO
		f.input.held = 0


## Walks a slow circle around the arena centre, reversing now and then; never attacks.
class Patrol:
	extends InputSource
	var rng := RandomNumberGenerator.new()
	var dir := 1.0
	var t := 0.0
	var next_flip := 3.0

	func _init(seed_value := 1) -> void:
		rng.seed = seed_value
		dir = 1.0 if rng.randf() < 0.5 else -1.0
		next_flip = rng.randf_range(2.0, 4.5)

	func label() -> String:
		return "Patrol"

	func poll(f: Fighter, _sim, dt: float) -> void:
		t += dt
		if t >= next_flip:
			dir = -dir
			next_flip = t + rng.randf_range(2.0, 4.5)
		var p := f.pos()
		var r := Vector2(p.x, p.z)
		var radial := Vector3(p.x, 0.0, p.z)
		var tangent := Vector3(-p.z, 0.0, p.x).normalized() * dir if r.length() > 0.3 else Vector3.RIGHT
		# keep near a 2.2 m circle
		var pull := radial.normalized() * clampf((2.2 - r.length()) * 0.8, -0.6, 0.6) if r.length() > 0.05 else Vector3.ZERO
		f.input.move = (tangent + pull).normalized() * 0.45
		f.input.held = 0


## Closes to jab range and jabs on a rhythm; backs off when out of stamina.
class Jabber:
	extends InputSource
	var rng := RandomNumberGenerator.new()
	var t := 0.0
	var next_jab := 0.0
	var retreat_until := -1.0

	func _init(seed_value := 1) -> void:
		rng.seed = seed_value
		next_jab = rng.randf_range(0.2, 0.6)

	func label() -> String:
		return "Jabber"

	func poll(f: Fighter, _sim, dt: float) -> void:
		t += dt
		f.input.held = 0
		var to := LabOpponents._to_target(f)
		var d := to.length()
		if d < 0.01:
			f.input.move = Vector3.ZERO
			return
		var dir := to / d
		if f.stamina < 22.0 and retreat_until < t:
			retreat_until = t + 1.0
		if t < retreat_until:
			f.input.move = -dir * 0.8
			return
		f.input.move = dir if d > 1.05 else (dir * 0.2 if d > 0.8 else -dir * 0.3)
		if d < 1.4 and t >= next_jab:
			f.input.press(FighterInput.LIGHT)
			next_jab = t + rng.randf_range(0.42, 0.62)


## Guards almost all the time, faces the target, pokes with a jab when it is close, and drops
## its guard briefly every few seconds.
class Turtle:
	extends InputSource
	var rng := RandomNumberGenerator.new()
	var t := 0.0
	var next_jab := 1.0
	var open_until := -1.0
	var next_open := 3.0
	var release_tick := false

	func _init(seed_value := 1) -> void:
		rng.seed = seed_value
		next_open = rng.randf_range(2.5, 4.5)

	func label() -> String:
		return "Turtle"

	func poll(f: Fighter, _sim, dt: float) -> void:
		t += dt
		var to := LabOpponents._to_target(f)
		var d := to.length()
		var dir := to / d if d > 0.01 else Vector3.ZERO
		f.input.move = dir * 0.4 if d > 2.5 else Vector3.ZERO
		if t >= next_open:
			open_until = t + 0.4
			next_open = t + rng.randf_range(2.5, 4.5)
		var guard := t >= open_until
		if release_tick:
			release_tick = false
			f.input.held = 0
			f.input.press(FighterInput.LIGHT)
			return
		if guard and d < 1.3 and t >= next_jab:
			next_jab = t + rng.randf_range(1.0, 1.6)
			release_tick = true
			f.input.held = 0
			return
		f.input.held = (1 << FighterInput.GUARD) if guard else 0
