class_name TestCase
extends Node
## Base class for automated tests. Put files named `test_*.gd` anywhere under res://src/test/;
## every method whose name starts with `test_` runs (methods may `await`). Helpers below record
## failures without aborting the run. Run: godot --headless --path game -- --test [filter]

var _failures: Array = []
var _current := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(msg: String) -> void:
	_failures.append("%s: %s" % [_current, msg])


func check(cond: bool, msg := "expected condition to hold") -> bool:
	if not cond:
		fail(msg)
	return cond


func check_eq(a, b, msg := "") -> bool:
	if typeof(a) != typeof(b) and not ((typeof(a) == TYPE_INT and typeof(b) == TYPE_FLOAT) or (typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_INT)):
		fail("%s expected %s (%s), got %s (%s)" % [msg, str(b), type_string(typeof(b)), str(a), type_string(typeof(a))])
		return false
	if a != b:
		fail("%s expected %s, got %s" % [msg, str(b), str(a)])
		return false
	return true


func check_near(a: float, b: float, tol: float, msg := "") -> bool:
	if absf(a - b) > tol:
		fail("%s expected %.4f ± %.4f, got %.4f" % [msg, b, tol, a])
		return false
	return true


func wait_physics(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func wait_frames(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## A fresh temporary folder under the user-data root (cleaned by the runner at the end).
func temp_dir(name_: String) -> String:
	var d := Paths.dir("captures").path_join("tests").path_join(name_)
	DirAccess.make_dir_recursive_absolute(d)
	return d


## Builds a headless MatchSim (no views) with the given fighters and returns it; the caller
## steps it with `step_sim`. fighters: [{creature: CreatureDef|id, team, source}]
func make_sim(arena_id := "the_gullet", rules := {"rounds": 1, "round_time": 0}, fighters := [], seed_value := 1) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var entries := []
	for f in fighters:
		var e: Dictionary = f.duplicate()
		if not (e["creature"] is CreatureDef):
			e["creature"] = Content.creature(str(e["creature"]))
		entries.append(e)
	var arena = Content.arena(arena_id) if arena_id != "" else null
	if arena == null:
		arena = ArenaDef.from_dict({"id": "test", "base": "octagon", "radius": 5.0})
	sim.setup({"arena": arena, "rules": rules, "seed": seed_value, "fighters": entries})
	return sim


## A node whose children live in their own physics world (own Jolt space). Simulations are
## only bit-for-bit reproducible when they start in a fresh world (body ordering matters).
func fresh_world() -> Node:
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sv.size = Vector2i(2, 2)
	add_child(sv)
	return sv


## Steps a MatchSim `seconds` of simulated time, yielding to the physics server every tick.
func step_sim(sim: MatchSim, seconds: float) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	var n := int(seconds / dt)
	# step in phase with physics no matter where the caller was (idle vs physics frame)
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	for i in n:
		sim.step(dt)
		await get_tree().physics_frame
		if sim.is_finished:
			return
