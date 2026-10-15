class_name SimSpeed
extends RefCounted
## Accelerates (or slows) the whole simulation clock WITHOUT changing the simulation step:
## Engine.time_scale = k and physics_ticks_per_second = base x k, so every physics step is still
## 1/120 s of game time (same rules, same stability) while k times as many steps run per real
## second (as many as the CPU allows). Used by The Bookie's Table speed control (1x-4x) and by
## headless tests/unattended runs (up to 32x). restore() returns the engine to its settings.

static var _saved := {}


static func scale() -> float:
	return Engine.time_scale


static func set_scale(k: float) -> void:
	k = clampf(k, 0.25, 64.0)
	if _saved.is_empty():
		_saved = {"ticks": Engine.physics_ticks_per_second, "scale": Engine.time_scale,
			"max_steps": Engine.max_physics_steps_per_frame}
	var base_ticks := int(_saved["ticks"])
	Engine.time_scale = k
	Engine.physics_ticks_per_second = maxi(30, int(round(base_ticks * k)))
	Engine.max_physics_steps_per_frame = maxi(int(_saved["max_steps"]), int(ceil(8.0 * k)))


static func restore() -> void:
	if _saved.is_empty():
		return
	Engine.time_scale = float(_saved["scale"])
	Engine.physics_ticks_per_second = int(_saved["ticks"])
	Engine.max_physics_steps_per_frame = int(_saved["max_steps"])
	_saved = {}


## Fixed simulation step (always 1/120 s of game time regardless of the speed setting).
static func step_dt() -> float:
	var base := int(_saved.get("ticks", Engine.physics_ticks_per_second))
	return 1.0 / float(base) if not _saved.is_empty() else 1.0 / float(Engine.physics_ticks_per_second) * Engine.time_scale
