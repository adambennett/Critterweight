class_name InputSource
extends RefCounted
## Something that decides a fighter's FighterInput each tick: a local player, a bot brain, a
## remote client (server side), a trained policy, a replay, or a test script.
## Implementations override `poll`. They must only write `f.input`.


func poll(_f: Fighter, _sim, _dt: float) -> void:
	pass


## Human-readable label for HUDs/spectators ("Player 1", "Bot (Brawler, Hard)", ...).
func label() -> String:
	return "Idle"


## Deterministic test/tutorial driver: a list of timed steps.
##   {"t0": s, "t1": s, "move": Vector3 (world) or "to_target"|"away", "hold": ["guard"],
##    "press": ["light"], "every": s}
## `press` fires once at t0 (or repeatedly every `every` seconds within [t0, t1)).
class Scripted:
	extends InputSource
	var steps: Array = []
	var time := 0.0
	var _fired := {}

	func _init(s: Array = []) -> void:
		steps = s

	func label() -> String:
		return "Script"

	func poll(f: Fighter, _sim, dt: float) -> void:
		time += dt
		f.input.move = Vector3.ZERO
		f.input.held = 0
		for i in steps.size():
			var st: Dictionary = steps[i]
			var t0 := float(st.get("t0", 0.0))
			var t1 := float(st.get("t1", t0 + 0.05))
			if time < t0 or time >= t1:
				continue
			var mv = st.get("move", null)
			if typeof(mv) == TYPE_VECTOR3:
				f.input.move = mv
			elif typeof(mv) == TYPE_STRING and f.target:
				var to := f.target.pos() - f.pos()
				to.y = 0.0
				f.input.move = to.normalized() * (-1.0 if mv == "away" else 1.0)
			for b in st.get("hold", []):
				f.input.set_held(FighterInput.BUTTON_NAMES.find(b), true)
			var every := float(st.get("every", 0.0))
			for b in st.get("press", []):
				var bi := FighterInput.BUTTON_NAMES.find(b)
				var key := "%d_%d" % [i, bi]
				var last := float(_fired.get(key, -1e9))
				if (every <= 0.0 and last < -1e8) or (every > 0.0 and time - last >= every):
					_fired[key] = time
					f.input.press(bi)
