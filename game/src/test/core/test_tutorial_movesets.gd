extends TestCase
## v0.9.18 Movesets tutorial course (docs/design/MOVESET_COMBAT.md §9; UI-12): Granny teaches the
## equipped moves. The course and who takes it (Movesets for every fighter but Varga; Classic keeps
## the v0.9.17 course, tested by test_tutorial.gd), lines that name the equipped moves and their
## live inputs (a custom loadout reads right), lessons the loadout can't do skipped with a note,
## and every lesson passed by a scripted player pressing the inputs it teaches. The checks read the
## pool move each event carries: hits from other moves never count.
## Run fast with --fixed-fps 120. TUTORIAL_TRACE=1 prints each exercise's events.

const FURNACE := ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"]
const BRAWLER := ["ember_jab", "furnace_haymaker", "flare_rush", "cinder_shot"]
const COURSE := ["tut_footwork", "tut_m_string", "tut_m_charge", "tut_m_sustain", "tut_m_special", "tut_guard",
	"tut_m_dodge", "tut_m_grapple", "tut_parry", "tut_m_ultimate", "tut_freestyle"]
## The lines Granny speaks (subtitled): kept to 90 characters.
const SPOKEN := ["intro", "hint", "success", "rush", "stage"]


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


func before_each() -> void:
	Controls.last_device = "keyboard"


func after_each() -> void:
	Controls.last_device = "keyboard"


func _stoke() -> CreatureDef:
	return Content.creature("f_stoke")


## A tutorial match at exercise `index` of the fighter's course, with `lo` equipped.
func _sim(index: int, lo: Array, c: CreatureDef = null, combat := "moves") -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var mode := TutorialMode.new()
	mode.start_index = index
	if c == null:
		c = _stoke()
	sim.setup({"arena": Tutorial.practice_cage(), "seed": 4, "mode": mode,
		"rules": {"id": "tutorial", "name": "Tutorial", "mode": "tutorial", "combat": combat, "round_time": 0.0, "intro_time": 0.0},
		"fighters": [{"creature": c, "team": 0, "source": null, "kind": "player", "loadout": lo},
			{"creature": Content.creature(Tutorial.partner_for(c.id)), "team": 1, "source": null, "kind": "scripted"}]})
	return sim


var _rb := BotBrain.new("regular", 1)    ## only for its cached move-reach estimates


func _in_reach(f: Fighter, kid: Fighter, slot: String, mem: Dictionary, ability := false) -> bool:
	var d := _dist(f, kid)
	var stalled := _stalled(d, mem)
	return d <= _rb.reach_of(f.creature, slot, ability) + 0.05 or stalled


static func _stalled(d: float, mem: Dictionary) -> bool:
	var prev := float(mem.get("_pd", -1.0))
	var stuck := float(mem.get("_st", 0.0))
	if prev >= 0.0 and prev - d < 0.004:
		stuck += 1.0 / Engine.physics_ticks_per_second
	else:
		stuck = 0.0
	mem["_pd"] = d
	mem["_st"] = stuck
	return stuck > 0.35


static func _toward(f: Fighter, target: Vector3) -> Vector3:
	var d := Vector3(target.x - f.pos().x, 0.0, target.z - f.pos().z)
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


static func _dist(a: Fighter, b: Fighter) -> float:
	return Vector2(b.pos().x - a.pos().x, b.pos().z - a.pos().z).length()


## The FighterInput button of the move a lesson teaches ("basic", "charge", "sustain", "special").
static func _button(sim, which: String) -> int:
	var mode := sim.mode as TutorialMode
	return int((mode.kit.get(which, {}) as Dictionary).get("button", FighterInput.LIGHT))


## Runs exercise `index` with `plan` until success (or `limit` sim seconds) on `sim`.
func _drive(sim: MatchSim, plan: Callable, limit := 40.0) -> TutorialMode:
	var mode := sim.mode as TutorialMode
	sim.set_input_source(0, Driver.new(plan))
	var t := 0.0
	var trace := OS.get_environment("TUTORIAL_TRACE") != ""
	var cursor := sim.event_seq
	while t < limit and not mode.state in ["success", "complete", "done_single"]:
		await step_sim(sim, 0.25)
		t += 0.25
		if trace:
			for ev in sim.events_since(cursor):
				cursor = int(ev["seq"])
				if str(ev["type"]) in ["move_start", "hit", "sustain", "ability", "dodge", "grab", "throw", "juice", "tutorial_line", "move_denied"]:
					print("  [%6.2f] %s %s" % [sim.time, ev["type"], str(ev)])
	print("    %s with %s %s: %s after %.2f s" % [mode.current().get("id", "?"), sim.fighters[0].creature.id, str(sim.fighters[0].loadout), mode.state, t])
	check(mode.state in ["success", "complete", "done_single"], "exercise %s completed within %.0f s (state %s, progress '%s')" % [mode.current().get("id", "?"), limit, mode.state, mode.progress_text()])
	return mode


func _run(index: int, plan: Callable, lo: Array, limit := 40.0, c: CreatureDef = null) -> TutorialMode:
	var sim := _sim(index, lo, c)
	var mode := sim.mode as TutorialMode
	check_eq(mode.course, "moves", "the Movesets course")
	check_eq(str(mode.current().get("id", "")), COURSE[index], "exercise %d" % index)
	return await _drive(sim, plan, limit)


## Whether a Movesets lesson is skipped for this kit (the move it teaches isn't equipped).
static func _lacks(ex: Dictionary, c: CreatureDef, kit: Dictionary) -> bool:
	match str(ex.get("check", "")):
		"basic_string":
			return not kit.has("basic")
		"charge_move":
			return not kit.has("charge")
		"sustain_aim":
			return not kit.has("sustain")
		"special_connect":
			return not kit.has("special")
		"ultimate":
			return not c.abilities.has("juice")
		"grab_throw":
			return not c.moves.has("grab")
	return false


## Every line of an exercise: [key, text, spoken].
static func _lines(ex: Dictionary) -> Array:
	var out: Array = []
	for k in ["intro", "goal", "hint", "success", "rush", "stage"]:
		if ex.has(k):
			out.append([k, str(ex[k]), k in SPOKEN])
	var blocks: Dictionary = ex.get("adapt", {})
	for flag in blocks:
		for k in (blocks[flag] as Dictionary):
			out.append(["%s.%s" % [flag, k], str(blocks[flag][k]), k in SPOKEN])
	return out


# --- the course ---------------------------------------------------------------------------------

func test_courses_and_who_takes_them() -> void:
	var ids: Array = Tutorial.exercises("moves").map(func(e): return str(e["id"]))
	check_eq(ids, COURSE, "the Movesets course, in order")
	check_eq(TutorialHook.lessons("moves").map(func(e): return str(e["id"])), COURSE, "the tutorial menu lists the same lessons")
	check_eq(TutorialHook.lessons("classic").size(), 10, "the Classic course keeps its ten")
	var varga := Content.creature("f_varga")
	check_eq(Tutorial.course_for(_stoke(), "moves"), "moves", "Movesets: the Movesets course")
	check_eq(Tutorial.course_for(_stoke(), "classic"), "classic", "the Classic rule: the Classic course")
	if varga:
		check_eq(Tutorial.course_for(varga, "moves"), "classic", "Varga keeps his Cage Rules lessons")
	var sim := _sim(0, FURNACE)
	var mode := sim.mode as TutorialMode
	check_eq(mode.course, "moves", "a Movesets tutorial runs the Movesets course")
	check_eq(mode.list.size(), 11, "eleven lessons")
	check_eq(sim.fighters[0].loadout, FURNACE, "with the player's loadout")
	check_eq(sim.fighters[1].combat_style, "classic", "the Kid drills with his Classic kit")
	var sc := _sim(0, [], _stoke(), "classic")
	check_eq((sc.mode as TutorialMode).course, "classic", "the Classic rule runs the Classic course")
	check_eq((sc.mode as TutorialMode).list.size(), 10, "its ten lessons")
	if varga:
		var sv := _sim(0, [], varga)
		check_eq((sv.mode as TutorialMode).course, "classic", "Varga in Movesets: his own lessons")
	for ex in Tutorial.exercises("moves"):
		for key in ["title", "goal", "intro", "success", "hint", "check", "dummy"]:
			check(str(ex.get(key, "")) != "", "%s has %s" % [ex.get("id", "?"), key])
		var blocks: Dictionary = ex.get("adapt", {})
		for flag in blocks:
			for key in (blocks[flag] as Dictionary):
				check(key in ["intro", "goal", "hint", "success"], "%s adapt.%s: known line '%s'" % [ex["id"], flag, key])


func test_lines_name_the_equipped_moves_and_their_inputs() -> void:
	var c := _stoke()
	var k := func(a: String) -> String: return "[%s]" % Controls.prompt_for(a)
	check_eq(Tutorial.fill("{basic}", c, FURNACE), k.call("light"), "the basic strike's input")
	check_eq(Tutorial.fill("{basic_name}", c, FURNACE), "Ember Jab", "its name")
	check_eq(Tutorial.fill("{string_names}", c, FURNACE), "Jab – Cross – Lead Hook – Gut Furnace", "its string")
	check_eq(Tutorial.fill("{finisher_name}", c, FURNACE), "Gut Furnace", "its finisher")
	check_eq(Tutorial.fill("{dash_name}", c, FURNACE), "Stoke Step", "its dash strike")
	check_eq(Tutorial.fill("{sustain} {sustain_name} {sustain_max}", c, FURNACE), "%s Flamethrower 2.4" % k.call("heavy"), "the sustained move")
	check_eq(Tutorial.fill("{special} {special_name} {special_cat}", c, FURNACE), "%s Steam Vent blast" % k.call("ability1"), "the special to land")
	check_eq(Tutorial.fill("{ultimate} {ultimate_name}", c, FURNACE), "%s Meltdown" % k.call("juice"), "the Ultimate")
	check_eq(Tutorial.fill("{charge} {charge_name} {charge_full}", c, BRAWLER), "%s Furnace Haymaker Furnace Haymaker" % k.call("heavy"), "the charge move")
	check_eq(Tutorial.fill("{special_name}", c, BRAWLER), "Flare Rush", "Brawler's special")
	# a custom loadout: the basic on Move 2, the stream on Move 1
	var mine := ["flamethrower", "ember_jab", "cinder_shot", "fire_spin"]
	check_eq(Tutorial.fill("{basic}", c, mine), k.call("heavy"), "the basic's real input")
	check_eq(Tutorial.fill("{sustain}", c, mine), k.call("light"), "the stream's real input")
	check_eq(Tutorial.fill("{special_name}", c, mine), "Cinder Shot", "the special")
	# controller glyph names
	Controls.last_device = "gamepad"
	check_eq(Tutorial.fill("{basic} {sustain} {special}", c, FURNACE), "[X] [Y] [LB]", "controller inputs")
	Controls.last_device = "keyboard"
	# what the mode says is filled from the player's own loadout
	var sim := _sim(1, mine)
	var mode := sim.mode as TutorialMode
	check_eq(mode.objective(), Tutorial.fill(str(mode.current()["goal"]), c, mine), "the goal names the equipped moves")
	check(mode.objective().contains(k.call("heavy")) and mode.objective().contains("Ember Jab"), "goal: '%s'" % mode.objective())
	# no token survives for any fighter and loadout; Granny's new spoken lines stay short (subtitles):
	# the lines a lesson speaks with that loadout (a lesson it can't do speaks only its note)
	for id in Content.playable_creatures():
		var cr := Content.creature(str(id))
		if cr == null or cr.tags.has("martial"):
			continue
		var los: Array = [cr.resolve_loadout([])]
		for lk in cr.loadouts:
			los.append((cr.loadouts[lk] as Dictionary)["moves"])
		for lo in los:
			var kit := Tutorial.moves_kit(cr, lo)
			for ex in Tutorial.exercises("moves"):
				var skipped := _lacks(ex, cr, kit)
				for line in _lines(ex):
					var filled := Tutorial.fill(str(line[1]), cr, lo)
					check(not filled.contains("{"), "%s %s %s.%s: every token replaced (%s)" % [id, str(lo), ex["id"], line[0], filled.substr(0, 60)])
					var key := str(line[0])
					var spoken_here := bool(line[2]) and (key.begins_with("skip.") if skipped else not key.begins_with("skip."))
					if spoken_here and str(ex.get("style", "")) == "moves" and str(id) == "f_stoke":
						check(filled.length() <= 90, "%s.%s spoken line within 90 characters (%d): %s" % [ex["id"], key, filled.length(), filled])


func test_lessons_the_loadout_lacks_are_skipped_with_a_note() -> void:
	var c := _stoke()
	for item in [[2, FURNACE, "charge"], [3, BRAWLER, "sustain"]]:
		var lo: Array = item[1]
		var sim := _sim(int(item[0]), lo)
		var mode := sim.mode as TutorialMode
		check(mode.adapted("skip"), "%s: no %s move in %s" % [mode.current()["id"], item[2], str(lo)])
		var block: Dictionary = (mode.current()["adapt"] as Dictionary)["skip"]
		check_eq(mode.objective(), Tutorial.fill(str(block["goal"]), c, lo), "the goal says so")
		await step_sim(sim, 0.1)
		check_eq(mode.state, "success", "and moves on")
		check_eq(str(mode.coach["text"]), Tutorial.fill(str(block["success"]), c, lo), "with its short note")
		check_eq(mode.progress_text(), "Not in your kit", "progress says why")


# --- the lessons, played --------------------------------------------------------------------------

const HANDS_TRIES := [[0.85, 0.3], [0.7, 0.3], [1.0, 0.0], [0.95, 0.3], [1.6, 0.3], [0.55, 0.3], [1.3, 0.0], [1.7, 0.0], [0.45, 0.3], [1.15, 0.3]]


## The basic string on the basic's own input, one press per landed (or finished) strike, all the
## way to the finisher; from another spacing after a string that didn't finish.
func _string_plan() -> Callable:
	return func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var mode := sim.mode as TutorialMode
		var kid: Fighter = sim.fighters[1]
		var button := _button(sim, "basic")
		var steps := mode.kit_move("basic").string.size()
		var attempt: Array = HANDS_TRIES[int(mem.get("tries", 0)) % HANDS_TRIES.size()]
		var want := _rb.reach_of(f.creature, "l1") * float(attempt[0])
		var push := float(attempt[1])
		var presses := int(mem.get("presses", 0))
		if presses == 0:
			if f.state != Fighter.State.NEUTRAL:
				return
			var d := _dist(f, kid)
			if d < want - 0.15 and t - float(mem.get("set_t", 0.0)) < 1.5:
				f.input.move = -_toward(f, kid.pos())
				mem["_pd"] = -1.0
				mem.erase("arrived")
				return
			if d > want + 0.1 and not _stalled(d, mem):
				f.input.move = _toward(f, kid.pos())
				mem.erase("arrived")
				return
			mem["_pd"] = -1.0
			if not mem.has("arrived"):
				mem["arrived"] = t
			var v := f.rig.com_velocity()
			if Vector2(v.x, v.z).length() > 0.4 and t - float(mem["arrived"]) < 0.6:
				return
		if presses < steps:
			if TutorialMode.swing_over(f) and t - float(mem.get("last", -9.0)) > 0.08:
				mem["last"] = t
				mem["presses"] = presses + 1
				f.input.press(button)
			f.input.move = _toward(f, kid.pos()) * push
		elif f.state == Fighter.State.NEUTRAL:
			mem["presses"] = 0
			mem["tries"] = int(mem.get("tries", 0)) + 1
			mem["set_t"] = t
			mem.erase("arrived")
		else:
			f.input.move = _toward(f, kid.pos()) * push


func test_basic_string_to_its_finisher() -> void:
	var mode := await _run(1, _string_plan(), FURNACE, 45.0)
	check_eq(int(mode.data.get("step", 0)), 4, "all four steps, the Gut Furnace finisher last")


func test_basic_string_on_a_custom_input() -> void:
	# the basic on Move 2 (Heavy's input): the lesson and its check follow the loadout
	var mine := ["flamethrower", "ember_jab", "cinder_shot", "fire_spin"]
	var sim := _sim(1, mine)
	var mode := sim.mode as TutorialMode
	check_eq(_button(sim, "basic"), FighterInput.HEAVY, "the basic strike sits on Move 2")
	check(str(mode.coach["text"]).begins_with("[%s]" % Controls.prompt_for("heavy")), "Granny names its input: %s" % mode.coach["text"])
	await _drive(sim, _string_plan(), 45.0)


## Basic strikes on the Kid first (they never count), then the charge move: a tap within its reach,
## then held to the full charge from where the charged follow-up has room.
func _charge_plan(basics_first := 0.0) -> Callable:
	return func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var mode := sim.mode as TutorialMode
		var kid: Fighter = sim.fighters[1]
		var cpm := mode.kit_move("charge")
		var button := _button(sim, "charge")
		if t < basics_first:
			if f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, "l1", mem):
				f.input.move = _toward(f, kid.pos())
			elif t - float(mem.get("jab", -9.0)) > 0.35:
				mem["jab"] = t
				f.input.press(_button(sim, "basic"))
			return
		if mode.stage == 0:
			if f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, cpm.use if cpm.use != "" else "heavy", mem):
				f.input.move = _toward(f, kid.pos())
			elif f.state == Fighter.State.NEUTRAL and t - float(mem.get("last", -9.0)) > 1.2:
				mem["last"] = t
				f.input.press(button)
			return
		if not mem.has("set_t"):
			mem["set_t"] = t
		if mem.has("hold_from"):
			if t - float(mem["hold_from"]) < 0.7:
				f.input.set_held(button, true)
			elif t - float(mem["hold_from"]) > 2.2:
				mem.erase("hold_from")
				mem["tries"] = int(mem.get("tries", 0)) + 1
				mem["set_t"] = t
			return
		if f.state != Fighter.State.NEUTRAL:
			return
		var slot := cpm.charged_use if cpm.charged_use != "" else (cpm.use if cpm.use != "" else "heavy")
		var want: float = _rb.reach_of(f.creature, slot) * float([0.75, 0.55, 0.95, 0.4][int(mem.get("tries", 0)) % 4])
		var d := _dist(f, kid)
		var spacing_t := t - float(mem.get("set_t", 0.0))
		if d < want - 0.25 and spacing_t < 1.5:
			f.input.move = -_toward(f, kid.pos())
			mem["_pd"] = -1.0
		elif d > want + 0.15 and spacing_t < 4.0 and not _stalled(d, mem):
			f.input.move = _toward(f, kid.pos())
		else:
			mem["hold_from"] = t
			mem["_pd"] = -1.0
			f.input.press(button)
			f.input.set_held(button, true)


func test_charge_move_tapped_then_charged() -> void:
	var sim := _sim(2, BRAWLER)
	var mode := sim.mode as TutorialMode
	check_eq(mode.kit_id("charge"), "furnace_haymaker", "Brawler's hold-to-charge move")
	sim.set_input_source(0, Driver.new(_charge_plan(4.0)))
	await step_sim(sim, 4.0)
	var basic_hits := 0
	for ev in sim.events:
		if str(ev["type"]) == "hit" and int(ev["fighter"]) == 0 and str(ev.get("pool", "")) == "ember_jab":
			basic_hits += 1
	check(basic_hits > 0, "the basic strikes landed (%d)" % basic_hits)
	check_eq(mode.stage, 0, "...and don't count for the charge lesson")
	var f: Fighter = sim.fighters[0]
	sim.set_input_source(0, Driver.new(_charge_plan()))
	var t := 0.0
	while t < 45.0 and mode.state == "active":
		await step_sim(sim, 0.25)
		t += 0.25
	check(mode.state in ["success", "complete", "done_single"], "the charge lesson completed (state %s, progress '%s')" % [mode.state, mode.progress_text()])
	# a move without a cooldown stays usable (a regression: it once spent a charge that never came back)
	check_eq(int(f.charges_left.get("m2", 1)), 1, "the Furnace Haymaker spends no charge")


## Holds the sustained move from close range; steering (the stick on the Kid) only when `steer`.
func _sustain_plan(steer: Array) -> Callable:
	return func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		var button := _button(sim, "sustain")
		if mem.has("hold"):
			if t - float(mem["hold"]) < 2.8:
				f.input.set_held(button, true)
				if bool(steer[0]):
					f.input.move = _toward(f, kid.pos())
			else:
				mem.erase("hold")
			return
		if f.state != Fighter.State.NEUTRAL:
			return
		var d := _dist(f, kid)
		if d > 1.7 and not _stalled(d, mem):
			f.input.move = _toward(f, kid.pos())
			return
		mem["_pd"] = -1.0
		mem["hold"] = t
		f.input.press(button)
		f.input.set_held(button, true)


func test_sustained_move_held_and_steered() -> void:
	var sim := _sim(3, FURNACE)
	var mode := sim.mode as TutorialMode
	check_eq(mode.kit_id("sustain"), "flamethrower", "Furnace's stream")
	check_eq(mode.kid.behavior, "strafe", "the Kid keeps moving for it")
	var steer := [false]
	sim.set_input_source(0, Driver.new(_sustain_plan(steer)))
	var held := false
	var cursor := sim.event_seq
	var t := 0.0
	while t < 6.0:
		await step_sim(sim, 0.25)
		t += 0.25
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			if str(ev["type"]) == "sustain" and int(ev["fighter"]) == 0 and str(ev.get("pool", "")) == "flamethrower":
				held = true
	check(held, "the flame was held (a sustain started)")
	check(int(mode.data.get("hits", 0)) >= 3, "it kept on him (%d hits)" % int(mode.data.get("hits", 0)))
	check_eq(mode.state, "active", "held but not steered: not done yet (%s)" % mode.progress_text())
	steer[0] = true
	await _drive(sim, _sustain_plan(steer), 30.0)


func test_special_connects_and_only_its_own_hits_count() -> void:
	var sim := _sim(4, FURNACE)
	var mode := sim.mode as TutorialMode
	check_eq(mode.kit_id("special"), "steam_vent", "Furnace's special to land")
	check_eq(str(mode.hud_state()["highlight"]), "cooldown:m3", "the HUD highlights its card")
	# basic strikes on the Kid first: they are not the special
	sim.set_input_source(0, Driver.new(func(f: Fighter, s, t: float, mem: Dictionary) -> void:
		var kid: Fighter = s.fighters[1]
		if f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, "l1", mem):
			f.input.move = _toward(f, kid.pos())
		elif t - float(mem.get("jab", -9.0)) > 0.35:
			mem["jab"] = t
			f.input.press(FighterInput.LIGHT)))
	await step_sim(sim, 4.0)
	check_eq(mode.state, "active", "basic hits don't complete the special lesson")
	var plan := func(f: Fighter, s, t: float, mem: Dictionary) -> void:
		var kid: Fighter = s.fighters[1]
		var button := _button(s, "special")
		if f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, "ability1", mem, true):
			f.input.move = _toward(f, kid.pos())
		elif t - float(mem.get("last", -9.0)) > 0.5:
			mem["last"] = t
			f.input.move = _toward(f, kid.pos())
			f.input.press(button)
	await _drive(sim, plan, 30.0)


## Sidesteps the Kid's Heavy as it arrives, then dashes in pressing the basic's input mid-dodge.
func _dodge_plan() -> Callable:
	return func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		var mode := sim.mode as TutorialMode
		if mode.stage == 0:
			var pace := maxf(0.1, float(kid.mods.get("move_speed", 1.0)))
			var heavy := kid.state == Fighter.State.ATTACK and kid.move != null and kid.move_slot.split("@")[0] in ["heavy", "heavy_charged"]
			if heavy and not mem.has("start"):
				mem["start"] = float(sim.time) - kid.state_time / pace
			elif not heavy and kid.state != Fighter.State.HITSTUN:
				mem.erase("start")
				mem.erase("dodged")
			for ev in sim.events_since(int(mem.get("cur", 0))):
				mem["cur"] = int(ev["seq"])
				if ev["type"] == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0 and mem.has("start"):
					mem["arrive"] = float(sim.time) - float(mem["start"])
			if heavy and not mem.has("dodged"):
				var expect := float(mem.get("arrive", kid.move.first_active() / pace))
				if float(sim.time) - float(mem["start"]) >= expect - 0.12:
					mem["dodged"] = true
					var to := _toward(f, kid.pos())
					f.input.move = Vector3(-to.z, 0, to.x)
					f.input.press(FighterInput.DODGE)
		else:
			var d := _dist(f, kid)
			var tries := int(mem.get("dash_tries", 0))
			var want: float = (f.creature.stat("dodge_distance") * 0.5 + _rb.reach_of(f.creature, "dash_attack") * 0.6) * float([1.0, 0.7, 1.3][tries % 3])
			if f.state == Fighter.State.NEUTRAL:
				var backing := float(mem.get("back_t", 0.0))
				if d < want - 0.3 and backing < 1.5:
					mem["back_t"] = backing + 1.0 / Engine.physics_ticks_per_second
					f.input.move = -_toward(f, kid.pos())
				elif d > want + 0.3:
					f.input.move = _toward(f, kid.pos())
				elif t - float(mem.get("dash", -9.0)) > 1.0:
					mem["dash"] = t
					mem["dash_tries"] = tries + 1
					mem["back_t"] = 0.0
					f.input.move = _toward(f, kid.pos())
					f.input.press(FighterInput.DODGE)
			elif f.state == Fighter.State.DODGE:
				f.input.move = _toward(f, kid.pos())
				f.input.press(_button(sim, "basic"))


func test_dodge_then_the_basics_dash_strike() -> void:
	var mode := await _run(6, _dodge_plan(), FURNACE, 60.0)
	check_eq(mode._dash_slot(), "dash_attack", "Ember Jab's dash strike (Stoke Step)")


func test_grapple_and_throw_through_guard() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		if f.state == Fighter.State.GRABBING:
			f.input.move = _toward(f, kid.pos())
			if t - float(mem.get("throw", -9.0)) > 0.3:
				mem["throw"] = t
				f.input.press(FighterInput.GRAB)
		elif f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, "grab", mem):
			f.input.move = _toward(f, kid.pos())
		elif t - float(mem.get("grab", -9.0)) > 0.8:
			mem["grab"] = t
			f.input.press(FighterInput.GRAB)
	await _run(7, plan, FURNACE)


func test_ultimate_after_filling_hype() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		if f.hype >= 100.0:
			f.input.press(FighterInput.JUICE)
			return
		if f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, "l1", mem):
			f.input.move = _toward(f, kid.pos())
		elif TutorialMode.swing_over(f) and t - float(mem.get("last", -9.0)) > 0.12:
			mem["last"] = t
			f.input.press(_button(sim, "basic"))
	await _run(9, plan, FURNACE, 60.0)


func test_footwork_and_guard_in_the_moves_course() -> void:
	var walk := func(f: Fighter, sim, _t: float, _mem: Dictionary) -> void:
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
	await _run(0, walk, FURNACE)
	var guard := func(f: Fighter, _sim, _t: float, _mem: Dictionary) -> void:
		f.input.set_held(FighterInput.GUARD, true)
	await _run(5, guard, FURNACE, 45.0)
