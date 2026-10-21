extends TestCase
## UI-12: every tutorial exercise can be completed with the inputs it teaches (driven by a
## scripted player standing in for a competent human), failures give hints, retry/skip work,
## exercises adapt honestly to kits that lack a slot, and completion is saved.
## This file is the Classic course (the v0.9.17 lessons, run under the Classic rule, unchanged);
## the Movesets course is test_tutorial_movesets.gd.
## Run fast with --fixed-fps 120. TUTORIAL_TRACE=1 prints each exercise's events.

## The fighter taking the course: TUTORIAL_CREATURE=<id> runs the whole course with another
## fighter (tools/verify/tutorial_matrix.ps1 runs it for every fighter; ANNOUNCER_AND_TUTORIAL.md §2.3).
static func _player_id() -> String:
	var e := OS.get_environment("TUTORIAL_CREATURE")
	return e if e != "" and Content.creature(e) != null else "dev_biped"


## Kid Lamprey's creature: the one the game launches for this player (Tutorial.partner_for);
## TUTORIAL_PARTNER=<id> overrides it to check the drills against other bodies.
static func _partner_id(player_id := "") -> String:
	var e := OS.get_environment("TUTORIAL_PARTNER")
	if e != "" and Content.creature(e) != null:
		return e
	return Tutorial.partner_for(player_id if player_id != "" else _player_id())


## A misspelt TUTORIAL_CREATURE must not quietly run the course with the Test Dummy.
func before_each() -> void:
	var e := OS.get_environment("TUTORIAL_CREATURE")
	check(e == "" or Content.creature(e) != null, "TUTORIAL_CREATURE=%s names no creature" % e)


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


## A tutorial match at exercise `index` with `c` (default: the configured fighter) against the
## Kid the game would pick for it.
func _sim(index: int, c: CreatureDef = null) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var mode := TutorialMode.new()
	mode.start_index = index
	if c == null:
		c = Content.creature(_player_id())
	sim.setup({"arena": Tutorial.practice_cage(), "seed": 4, "mode": mode,
		"rules": {"id": "tutorial", "name": "Tutorial", "mode": "tutorial", "combat": "classic", "round_time": 0.0, "intro_time": 0.0},
		"fighters": [{"creature": c, "team": 0, "source": null, "kind": "player"},
			{"creature": Content.creature(_partner_id(c.id)), "team": 1, "source": null, "kind": "scripted"}]})
	return sim


var _rb := BotBrain.new("regular", 1)    ## only for its cached move-reach estimates


## Close enough to use `slot` on the Kid: the move's reach covers the gap, or we are pressed
## against him and can't get closer (bodies of every size).
func _in_reach(f: Fighter, kid: Fighter, slot: String, mem: Dictionary, ability := false) -> bool:
	var d := _dist(f, kid)
	var stalled := _stalled(d, mem)
	return d <= _rb.reach_of(f.creature, slot, ability) + 0.05 or stalled


## Call every tick of an approach: true once the gap has stopped shrinking for 0.35 s (pressed
## against a big body).
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


## Runs exercise `index` with `plan` until success (or `limit` sim seconds).
func _run(index: int, plan: Callable, limit := 40.0, c: CreatureDef = null) -> TutorialMode:
	var sim := _sim(index, c)
	var mode := sim.mode as TutorialMode
	check_eq(mode.index, index, "exercise %d started" % index)
	sim.set_input_source(0, Driver.new(plan))
	var t := 0.0
	var trace := OS.get_environment("TUTORIAL_TRACE") != ""
	var cursor := sim.event_seq
	while t < limit and not mode.state in ["success", "complete", "done_single"]:
		await step_sim(sim, 0.25)
		t += 0.25
		if trace:
			cursor = _trace(sim, cursor)
	print("    %s with %s vs %s: %s after %.2f s" % [mode.current().get("id", "?"), sim.fighters[0].creature.id, sim.fighters[1].creature.id, mode.state, t])
	check(mode.state in ["success", "complete", "done_single"], "exercise %d (%s) completed within %.0f s (state %s, progress '%s')" % [index + 1, mode.current().get("id", "?"), limit, mode.state, mode.progress_text()])
	return mode


## TUTORIAL_TRACE=1: prints the exercise's combat events and both fighters' states (debugging).
func _trace(sim: MatchSim, cursor: int) -> int:
	for ev in sim.events_since(cursor):
		cursor = int(ev["seq"])
		var ty := str(ev["type"])
		if ty in ["move_start", "hit", "glance", "dodge", "parry", "ability", "grab", "throw", "tutorial_line", "knockdown", "grab_tech", "effect"]:
			var keep := {}
			for k in ["fighter", "target", "slot", "id", "blocked", "parried", "charged", "move_class", "damage", "kind", "text", "effect", "move"]:
				if ev.has(k):
					keep[k] = ev[k]
			print("  [%6.2f] %s %s" % [sim.time, ty, str(keep)])
	var a: Fighter = sim.fighters[0]
	var b: Fighter = sim.fighters[1]
	var mode := sim.mode as TutorialMode
	print("  [%6.2f] P %s %s  K %s %s (%s)  d=%.2f  mode=%s %s" % [sim.time, a.state_name(), a.move_slot, b.state_name(), b.move_slot,
		mode.kid.debug_text(), _dist(a, b), mode.state, mode.progress_text()])
	return cursor


func test_exercises_load_with_live_prompts() -> void:
	var list := Tutorial.exercises("classic")
	check_eq(list.size(), 10, "ten exercises")
	var ids: Array = list.map(func(e): return str(e["id"]))
	check_eq(ids, ["tut_footwork", "tut_hands", "tut_heavy", "tut_guard", "tut_dodge", "tut_ability", "tut_grab", "tut_parry", "tut_finish", "tut_freestyle"],
		"the Classic course is the v0.9.17 course, in its order")
	var c := Content.creature(_player_id())
	for ex in list:
		for key in ["title", "goal", "intro", "success", "hint", "check", "dummy"]:
			check(str(ex.get(key, "")) != "", "%s has %s" % [ex.get("id", "?"), key])
		var texts := str(ex["intro"]) + str(ex["goal"]) + str(ex["hint"]) + str(ex.get("rush", ""))
		var blocks: Dictionary = ex.get("adapt", {})
		for flag in blocks:
			for key in (blocks[flag] as Dictionary):
				check(key in ["intro", "goal", "hint", "success"], "%s adapt.%s: known line '%s'" % [ex["id"], flag, key])
				texts += str(blocks[flag][key])
		var filled := Tutorial.fill(texts, c)
		check(not filled.contains("{"), "%s: every token replaced (%s)" % [ex["id"], filled.substr(0, 80)])
	check(Tutorial.fill("{light}", c).begins_with("["), "binding prompt in brackets")
	# the Hands goal names the very string the drill checks, in the kit's own move names
	var names: Array = []
	for slot in TutorialMode.string_slots(c):
		names.append((c.moves[slot] as MoveDef).display_name)
	check(Tutorial.fill("{l_names}", c) == " – ".join(names), "Hands names %s's string: %s" % [c.id, " – ".join(names)])


## The stand-in Kid can reach every fighter: never the player's own fighter when another stand-in
## exists, and never one more than MAX_HEIGHT_RATIO times the player's height when one fits.
func test_partner_fits_every_fighter() -> void:
	for id in Content.playable_creatures():
		var me := Content.creature(str(id))
		var kid_id := Tutorial.partner_for(str(id))
		var kid := Content.creature(kid_id)
		check(kid != null, "%s gets a sparring partner" % id)
		if kid_id == Tutorial.PARTNER or kid == null:
			continue
		check(kid_id != str(id), "%s spars with someone else (%s)" % [id, kid_id])
		var fits := false
		for s in Tutorial.STAND_INS:
			var sc := Content.creature(s)
			if s != str(id) and sc and sc.body.height <= me.body.height * Tutorial.MAX_HEIGHT_RATIO:
				fits = true
		if fits:
			check(kid.body.height <= me.body.height * Tutorial.MAX_HEIGHT_RATIO, "%s (%.2f m) spars with %s (%.2f m), within %.1fx its height" % [id, me.body.height, kid_id, kid.body.height, Tutorial.MAX_HEIGHT_RATIO])


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


## The Hands driver's attempts: (fraction of the first Light's estimated reach to start from, how
## hard the stick pushes toward the Kid during the string). A player whose string doesn't finish
## tries again from another spacing, closer or further out, pushing in more or less. The estimate
## can be well off either way: Slurry's Head Butt drives the head ~1.3 m forward (estimate 0.97 m)
## and its whole string lands from 1.5-1.7 m.
const HANDS_TRIES := [[0.85, 0.3], [0.7, 0.3], [1.0, 0.0], [0.95, 0.3], [1.6, 0.3], [0.55, 0.3], [1.3, 0.0], [1.7, 0.0], [0.45, 0.3], [1.15, 0.3]]


func test_light_string() -> void:
	# step in, set the feet, then tap the three Lights in rhythm with the hits (pushing toward the
	# Kid or not, depending on the attempt)
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
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
			# arrived: a beat to stand still, so the string starts from the spacing, not from a run
			if not mem.has("arrived"):
				mem["arrived"] = t
			var v := f.rig.com_velocity()
			if Vector2(v.x, v.z).length() > 0.4 and t - float(mem["arrived"]) < 0.6:
				return
		if presses < 3:
			# taps in rhythm with the hits (Granny: "let it land, tap again")
			if TutorialMode.swing_over(f) and t - float(mem.get("last", -9.0)) > 0.08:
				mem["last"] = t
				mem["presses"] = presses + 1
				f.input.press(FighterInput.LIGHT)
			f.input.move = _toward(f, kid.pos()) * push
		elif f.state == Fighter.State.NEUTRAL:
			mem["presses"] = 0
			mem["tries"] = int(mem.get("tries", 0)) + 1
			mem["set_t"] = t
			mem.erase("arrived")
		else:
			f.input.move = _toward(f, kid.pos()) * push
	await _run(1, plan)


## Taps the Hands string faster than it can land (a button masher, from out of reach so nothing
## connects): Granny tells them the rhythm, if the kit's string cancels before it lands at all.
func test_rushed_string_gets_rhythm_advice() -> void:
	var sim := _sim(1)
	var mode := sim.mode as TutorialMode
	var c: CreatureDef = sim.fighters[0].creature
	var rushable := false
	for slot in TutorialMode.string_slots(c).slice(0, 2):
		rushable = rushable or TutorialMode.rushable(c.moves[slot])
	var plan := func(f: Fighter, _s, t: float, mem: Dictionary) -> void:
		if t - float(mem.get("last", -9.0)) > 0.1:
			mem["last"] = t
			f.input.press(FighterInput.LIGHT)
	sim.set_input_source(0, Driver.new(plan))
	var said := false
	var cursor := sim.event_seq
	var rush := Tutorial.fill(str(mode.current().get("rush", "")), c)
	for i in 16:
		await step_sim(sim, 0.25)
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			if ev["type"] == "tutorial_line" and str(ev["text"]) == rush:
				said = true
	check_eq(said, rushable, "%s: rhythm advice when mashing (its string can be rushed: %s)" % [c.id, rushable])


## A Heavy from the edge of its reach; then the held one from where the charged move has room to
## travel (a ram released against his body only shoves him): a little further or closer after a
## release that didn't land, as a player would.
func _heavy_plan() -> Callable:
	return func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		var mode := sim.mode as TutorialMode
		if mode.stage == 0:
			if f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, "heavy", mem):
				f.input.move = _toward(f, kid.pos())
			elif f.state == Fighter.State.NEUTRAL and t - float(mem.get("last", -9.0)) > 1.2:
				mem["last"] = t
				f.input.press(FighterInput.HEAVY)
			return
		if not mem.has("set_t"):
			mem["set_t"] = t
		if mem.has("hold_from"):
			if t - float(mem["hold_from"]) < 0.7:
				f.input.set_held(FighterInput.HEAVY, true)
			elif t - float(mem["hold_from"]) > 2.2:
				mem.erase("hold_from")
				mem["tries"] = int(mem.get("tries", 0)) + 1
				mem["set_t"] = t
			return
		if f.state != Fighter.State.NEUTRAL:
			return
		var slot := "heavy_charged" if f.creature.moves.has("heavy_charged") else "heavy"
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
			f.input.press(FighterInput.HEAVY)
			f.input.set_held(FighterInput.HEAVY, true)


func test_heavy_then_charged() -> void:
	await _run(2, _heavy_plan())


func test_guard_string() -> void:
	var plan := func(f: Fighter, _sim, _t: float, _mem: Dictionary) -> void:
		f.input.set_held(FighterInput.GUARD, true)
	await _run(3, plan, 45.0)


## Sidesteps the Kid's Heavy as it arrives ("wait for his big wind-up, then dodge"): the first
## guess is its active frame, after that when his Heavies actually landed. Then dodges toward
## him and presses Light during the dodge.
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
			# "it closes distance": dash in from a few steps out (part of the dodge's travel plus
			# the dash attack's reach), from a little further or closer after a miss
			var d := _dist(f, kid)
			var tries := int(mem.get("dash_tries", 0))
			var want: float = (f.creature.stat("dodge_distance") * 0.5 + _rb.reach_of(f.creature, "dash_attack") * 0.6) * float([1.0, 0.7, 1.3][tries % 3])
			if f.state == Fighter.State.NEUTRAL:
				var backing := float(mem.get("back_t", 0.0))
				if d < want - 0.3 and backing < 1.5:          # (not forever: a wall may be behind)
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
				f.input.press(FighterInput.LIGHT)


func test_dodge_then_dash_attack() -> void:
	await _run(4, _dodge_plan(), 60.0)


## The dodge drill is honest: the Kid's Heavy lands on a player who doesn't dodge it (so a dodged
## one was a real evasion, not a whiff), and taking it doesn't count as the dodge.
func test_dodge_drill_heavy_is_a_real_threat() -> void:
	var sim := _sim(4)
	var mode := sim.mode as TutorialMode
	sim.set_input_source(0, Driver.new(func(_f: Fighter, _s, _t: float, _m: Dictionary) -> void: pass))
	var hit := false
	var cursor := sim.event_seq
	var t := 0.0
	while t < 20.0 and not hit:
		await step_sim(sim, 0.25)
		t += 0.25
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			if ev["type"] == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0 and str(ev["slot"]).begins_with("heavy"):
				hit = true
	await step_sim(sim, 1.5)
	check(hit, "the Kid's Heavy lands on %s when it stands still (Kid: %s)" % [sim.fighters[0].creature.id, sim.fighters[1].creature.id])
	check_eq(mode.stage, 0, "taking the Heavy doesn't count as dodging it")


func test_ability_connects() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		if f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, "ability1", mem, true):
			f.input.move = _toward(f, kid.pos())
		elif t - float(mem.get("last", -9.0)) > 0.5:
			mem["last"] = t
			f.input.move = _toward(f, kid.pos())
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
		elif f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, "grab", mem):
			f.input.move = _toward(f, kid.pos())
		elif t - float(mem.get("grab", -9.0)) > 0.8:
			mem["grab"] = t
			f.input.press(FighterInput.GRAB)
	await _run(6, plan)


func test_parries() -> void:
	# a player reading the Kid's rhythm ("early is a block, late is a bruise"): the first guess for
	# when a strike lands is its active frame, after that when that move's strikes actually
	# arrived; tap Guard just before. A tap still lasts a few frames: Guard stays down briefly.
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		var arrive: Dictionary = mem.get("arrive", {})     # Kid's slot -> s from his move start to contact
		mem["arrive"] = arrive
		var pace := maxf(0.1, float(kid.mods.get("move_speed", 1.0)))
		if kid.state == Fighter.State.ATTACK and kid.move:
			if not mem.has("start") or str(mem.get("slot", "")) != kid.move_slot:
				mem["start"] = sim.time - kid.state_time / pace
				mem["slot"] = kid.move_slot
				mem["pressed"] = false
				mem["seen"] = false
		else:
			mem.erase("start")
		for ev in sim.events_since(int(mem.get("cur", 0))):
			mem["cur"] = int(ev["seq"])
			if ev["type"] == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0 and mem.has("start") and not bool(mem["seen"]):
				mem["seen"] = true
				var took: float = float(sim.time) - float(mem["start"])
				var s := str(mem["slot"])
				arrive[s] = lerpf(float(arrive[s]), took, 0.5) if arrive.has(s) else took
		if mem.has("start") and not bool(mem["pressed"]):
			var expect := float(arrive.get(str(mem["slot"]), kid.move.first_active() / pace))
			if sim.time - float(mem["start"]) >= expect - 0.06:
				mem["pressed"] = true
				mem["hold_until"] = t + 0.3
				f.input.press(FighterInput.GUARD)
		if t < float(mem.get("hold_until", -1.0)):
			f.input.set_held(FighterInput.GUARD, true)
	await _run(7, plan, 60.0)


func test_finisher_then_juice() -> void:
	var plan := func(f: Fighter, sim, t: float, mem: Dictionary) -> void:
		var kid: Fighter = sim.fighters[1]
		var mode := sim.mode as TutorialMode
		if mode.stage == 1 and f.hype >= 100.0:
			f.input.press(FighterInput.JUICE)
			return
		if f.state == Fighter.State.NEUTRAL and not _in_reach(f, kid, "l1", mem):
			f.input.move = _toward(f, kid.pos())
			mem["step"] = 0
			return
		# Light, Light, then Heavy while the second Light can still chain (each press once the
		# last strike landed or finished its swing, as in Hands)
		var step := int(mem.get("step", 0))
		if step < 3 and TutorialMode.swing_over(f) and t - float(mem.get("last", -9.0)) > 0.08:
			mem["last"] = t
			f.input.press(FighterInput.HEAVY if step == 2 else FighterInput.LIGHT)
			mem["step"] = step + 1
		elif step >= 3 and f.state == Fighter.State.NEUTRAL:
			mem["step"] = 0
	await _run(8, plan, 60.0)


func test_freestyle_round_can_be_won() -> void:
	var brain := BotBrain.new("champion", 99)
	brain.set_personality(Content.creature(_player_id()).ai)   # plays the kit as every match bot does
	var plan := func(f: Fighter, sim, _t: float, _mem: Dictionary) -> void:
		brain.poll(f, sim, 1.0 / Engine.physics_ticks_per_second)
	var mode := await _run(9, plan, 130.0)
	check(mode.state in ["success", "complete"], "freestyle won by KO or on health (two attempts allowed)")


## A kit without a charge, a dash attack, a finisher, the JUICE or a first ability (a mod
## fighter may lack any of them): each exercise says so in its own words (the "adapt" blocks in
## exercises.json) and skips that part, never passes silently with the normal lines.
func test_exercises_adapt_to_missing_slots() -> void:
	var d: Dictionary = Content.get_entry("creatures", "dev_biped").duplicate(true)
	d["id"] = "test_kitless_biped"
	for slot in ["dash_attack", "finisher"]:
		(d["moves"] as Dictionary).erase(slot)
	(d["moves"]["heavy"] as Dictionary)["charge_time"] = 0.0
	for slot in ["ability1", "juice"]:
		(d["abilities"] as Dictionary).erase(slot)
	var c := CreatureDef.from_dict(d)
	check(c.is_valid(), "the stripped kit is valid (%s)" % str(c.errors))
	var flags := {2: "no_charge", 4: "no_dash", 5: "skip", 8: "skip"}
	for i in flags:
		var sim := _sim(int(i), c)
		var mode := sim.mode as TutorialMode
		var flag := str(flags[i])
		var block: Dictionary = (mode.current().get("adapt", {}) as Dictionary).get(flag, {})
		check(mode.adapted(flag), "%s adapts (%s)" % [mode.current()["id"], flag])
		check(block.has("goal") and block.has("success"), "%s has adapted goal and success lines for %s" % [mode.current()["id"], flag])
		check_eq(mode.objective(), Tutorial.fill(str(block.get("goal", "")), c), "%s: adapted goal" % mode.current()["id"])
		if block.has("intro"):
			check_eq(str(mode.coach["text"]), Tutorial.fill(str(block["intro"]), c), "%s: adapted intro" % mode.current()["id"])
		if flag == "skip":
			await step_sim(sim, 0.1)
			check_eq(mode.state, "success", "%s: nothing to do, moves on" % mode.current()["id"])
			check_eq(str(mode.coach["text"]), Tutorial.fill(str(block["success"]), c), "%s: the move-on line says why" % mode.current()["id"])
			check_eq(mode.progress_text(), "Not in your kit", "%s: progress says why" % mode.current()["id"])
	# the doable part still has to be done, and the success line is the adapted one
	var heavy := await _run(2, _heavy_plan(), 40.0, c)
	check(not heavy.progress_text().contains("Charged"), "no charged step shown for a Heavy that doesn't charge")
	check_eq(str(heavy.coach["text"]), Tutorial.fill(str(heavy.current()["adapt"]["no_charge"]["success"]), c), "Heavy: adapted success line")
	var dodge := await _run(4, _dodge_plan(), 60.0, c)
	check(not dodge.progress_text().contains("Dash"), "no dash step shown without a dash attack")
	check_eq(str(dodge.coach["text"]), Tutorial.fill(str(dodge.current()["adapt"]["no_dash"]["success"]), c), "Dodge: adapted success line")


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
