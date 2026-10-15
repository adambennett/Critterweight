extends TestCase
## UI-12: every tutorial exercise can be completed with the inputs it teaches (driven by a
## scripted player), failures give hints, retry/skip work, and completion is saved.
## Run fast with --fixed-fps 120.

## The fighter taking the course: TUTORIAL_CREATURE=<id> runs the whole course with another
## fighter (tools/verify runs it for every roster fighter).
static func _player_id() -> String:
	var e := OS.get_environment("TUTORIAL_CREATURE")
	return e if e != "" and Content.creature(e) != null else "dev_biped"


class Driver:
	extends InputSource
	var plan: Callable
	var t := 0.0
	var mem := {}

	func _init(p: Callable) -> void:
		plan = p

	func poll(f: Fighter, sim, dt: float) -> void:
		t += dt
		f.input.move = Vector3.ZERO
		f.input.held = 0
		plan.call(f, sim, t, mem)


func _sim(index: int) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var mode := TutorialMode.new()
	mode.start_index = index
	var c := Content.creature(_player_id())
	sim.setup({"arena": Tutorial.practice_cage(), "seed": 4, "mode": mode,
		"rules": {"id": "tutorial", "name": "Tutorial", "mode": "tutorial", "round_time": 0.0, "intro_time": 0.0},
		"fighters": [{"creature": c, "team": 0, "source": null, "kind": "player"}, {"creature": c, "team": 1, "source": null, "kind": "scripted"}]})
	return sim


static func _toward(f: Fighter, target: Vector3) -> Vector3:
	var d := Vector3(target.x - f.pos().x, 0.0, target.z - f.pos().z)
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


## Runs exercise `index` with `plan` until success (or `limit` sim seconds).
func _run(index: int, plan: Callable, limit := 40.0) -> TutorialMode:
	var sim := _sim(index)
	var mode := sim.mode as TutorialMode
	check_eq(mode.index, index, "exercise %d started" % index)
	sim.set_input_source(0, Driver.new(plan))
	var t := 0.0
	while t < limit and not mode.state in ["success", "complete", "done_single"]:
		await step_sim(sim, 0.25)
		t += 0.25
	check(mode.state in ["success", "complete", "done_single"], "exercise %d (%s) completed within %.0f s (state %s, progress '%s')" % [index + 1, mode.current().get("id", "?"), limit, mode.state, mode.progress_text()])
	return mode


func test_exercises_load_with_live_prompts() -> void:
	var list := Tutorial.exercises()
	check_eq(list.size(), 10, "ten exercises")
	var c := Content.creature(_player_id())
	for ex in list:
		for key in ["title", "goal", "intro", "success", "hint", "check", "dummy"]:
			check(str(ex.get(key, "")) != "", "%s has %s" % [ex.get("id", "?"), key])
		var filled := Tutorial.fill(str(ex["intro"]) + str(ex["goal"]) + str(ex["hint"]), c)
		check(not filled.contains("{"), "%s: every token replaced (%s)" % [ex["id"], filled.substr(0, 80)])
	check(Tutorial.fill("{light}", c).begins_with("["), "binding prompt in brackets")


func test_footwork() -> void:
	var plan := func(f: Fighter, sim, _t: float, mem: Dictionary) -> void:
		var mode := sim.mode as TutorialMode
		var rings: Array = mode.current()["params"]["rings"]
		var done: Array = mode.data.get("rings", [])
		for i in rings.size():
			if not i in done:
				f.input.move = _toward(f, Vector3(float(rings[i][0]), 0, float(rings[i][1])))
				return
		var kid: Fighter = sim.fighters[1]
		var to := Vector3(kid.pos().x - f.pos().x, 0, kid.pos().z - f.pos().z)
		var tangent := Vector3(-to.z, 0, to.x).normalized()
		var radial := to.normalized() * clampf((to.length() - 1.6) * 0.8, -0.5, 0.5)
		f.input.move = (tangent + radial).normalized() * 0.8
	await _run(0, plan)


func test_light_string() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		if f.pos().distance_to(kid.pos()) > 1.0 and f.state == Fighter.State.NEUTRAL:
			f.input.move = _toward(f, kid.pos())
		elif t - float(mem.get("last", -9.0)) > 0.22:
			mem["last"] = t
			f.input.press(FighterInput.LIGHT)
	await _run(1, plan)


func test_heavy_then_charged() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		var mode := sim.mode as TutorialMode
		if f.pos().distance_to(kid.pos()) > 1.05 and f.state == Fighter.State.NEUTRAL and not mem.has("hold_from"):
			f.input.move = _toward(f, kid.pos())
			return
		if mode.stage == 0:
			if f.state == Fighter.State.NEUTRAL and t - float(mem.get("last", -9.0)) > 1.2:
				mem["last"] = t
				f.input.press(FighterInput.HEAVY)
		else:
			if not mem.has("hold_from") and f.state == Fighter.State.NEUTRAL:
				mem["hold_from"] = t
				f.input.press(FighterInput.HEAVY)
			if mem.has("hold_from"):
				if t - float(mem["hold_from"]) < 0.7:
					f.input.set_held(FighterInput.HEAVY, true)
				elif t - float(mem["hold_from"]) > 2.0:
					mem.erase("hold_from")
	await _run(2, plan)


func test_guard_string() -> void:
	var plan := func(f: Fighter, _sim, _t: float, _mem: Dictionary) -> void:
		f.input.set_held(FighterInput.GUARD, true)
	await _run(3, plan, 45.0)


func test_dodge_then_dash_attack() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		var mode := sim.mode as TutorialMode
		if mode.stage == 0:
			if kid.state == Fighter.State.ATTACK and kid.move_slot in ["heavy", "heavy_charged"] and not mem.has("dodged_at"):
				mem["dodged_at"] = t
				var to := _toward(f, kid.pos())
				f.input.move = Vector3(-to.z, 0, to.x)
				f.input.press(FighterInput.DODGE)
			elif mem.has("dodged_at") and t - float(mem["dodged_at"]) > 1.5:
				mem.erase("dodged_at")
		else:
			var d := f.pos().distance_to(kid.pos())
			if d > 2.6 and f.state == Fighter.State.NEUTRAL:
				f.input.move = _toward(f, kid.pos())
			elif f.state == Fighter.State.NEUTRAL and t - float(mem.get("dash", -9.0)) > 1.0:
				mem["dash"] = t
				f.input.move = _toward(f, kid.pos())
				f.input.press(FighterInput.DODGE)
			elif f.state == Fighter.State.DODGE:
				f.input.move = _toward(f, kid.pos())
				f.input.press(FighterInput.LIGHT)
	await _run(4, plan, 60.0)


func test_ability_connects() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		if f.pos().distance_to(kid.pos()) > 1.2 and f.state == Fighter.State.NEUTRAL:
			f.input.move = _toward(f, kid.pos())
		elif t - float(mem.get("last", -9.0)) > 0.5:
			mem["last"] = t
			f.input.press(FighterInput.AB1)
	await _run(5, plan)


func test_grab_and_throw_through_guard() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		if f.state == Fighter.State.GRABBING:
			f.input.move = _toward(f, kid.pos())
			if t - float(mem.get("throw", -9.0)) > 0.3:
				mem["throw"] = t
				f.input.press(FighterInput.GRAB)
		elif f.pos().distance_to(kid.pos()) > 0.95 and f.state == Fighter.State.NEUTRAL:
			f.input.move = _toward(f, kid.pos())
		elif t - float(mem.get("grab", -9.0)) > 0.8:
			mem["grab"] = t
			f.input.press(FighterInput.GRAB)
	await _run(6, plan)


func test_parries() -> void:
	var plan := func(f: Fighter, sim, _t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		if kid.state == Fighter.State.ATTACK and kid.move and kid.state_time < kid.move.first_active():
			var eta := (kid.move.first_active() - kid.state_time) / maxf(0.1, float(kid.mods.get("move_speed", 1.0)))
			if eta < 0.06 and not bool(mem.get("pressed", false)):
				mem["pressed"] = true
				mem["hold_until"] = _t + 0.3
				f.input.press(FighterInput.GUARD)
		elif kid.state != Fighter.State.ATTACK:
			mem["pressed"] = false
		# a "tap" still lasts a few frames: keep Guard down briefly so the hit lands on it
		if _t < float(mem.get("hold_until", -1.0)):
			f.input.set_held(FighterInput.GUARD, true)
	await _run(7, plan, 60.0)


func test_finisher_then_juice() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		var mode := sim.mode as TutorialMode
		if mode.stage == 1 and f.hype >= 100.0:
			f.input.press(FighterInput.JUICE)
			return
		if f.pos().distance_to(kid.pos()) > 1.0 and f.state == Fighter.State.NEUTRAL:
			f.input.move = _toward(f, kid.pos())
			return
		var step := int(mem.get("step", 0))
		if t - float(mem.get("last", -9.0)) > 0.24:
			mem["last"] = t
			f.input.press(FighterInput.HEAVY if step == 2 else FighterInput.LIGHT)
			mem["step"] = (step + 1) % 4
	await _run(8, plan, 60.0)


func test_freestyle_round_can_be_won() -> void:
	var brain := BotBrain.new("champion", 99)
	var plan := func(f: Fighter, sim, _t: float, _mem: Dictionary) -> void:
		brain.poll(f, sim, 1.0 / Engine.physics_ticks_per_second)
	var mode := await _run(9, plan, 130.0)
	check(mode.state in ["success", "complete"], "freestyle won by KO or on health (two attempts allowed)")


func test_retry_skip_and_progress_saved() -> void:
	var sim := _sim(0)
	var mode := sim.mode as TutorialMode
	check(str(mode.coach["text"]) != "", "intro line shown")
	mode.skip()
	check_eq(mode.index, 1, "skip advances")
	sim.fighters[0].health = 10.0
	mode.retry()
	check_eq(mode.index, 1, "retry stays")
	check_near(sim.fighters[0].health, sim.fighters[0].max_health, 0.01, "retry restores vitals")
	await step_sim(sim, 21.0)
	check_eq(str(mode.coach["kind"]), "hint", "idle hint after 20 s without progress")
	mode._succeed()
	check(str(mode.list[1]["id"]) in (Profiles.current["tutorial"] as Dictionary).get("exercises", []), "completion saved to the profile")
	# depletion never ends an exercise before the freestyle round
	sim.on_fighter_depleted(sim.fighters[0], sim.fighters[1], {})
	check(not sim.fighters[0].is_out(), "refilled instead of KO")
