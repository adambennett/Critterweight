class_name TutorialMode
extends MatchMode
## Granny Haymaker's tutorial (UI-12): ten staged exercises against Kid Lamprey, each with a
## data-defined success check (content/core/tutorial/exercises.json), live binding prompts,
## hints after failure or 20 s without progress, retry / skip / replay, and a real 60 s round
## at the end. Fighter 0 is the player, fighter 1 the Kid driven by KidScript.
##
## Presentation reads `coach` (current line), `objective()` and `progress_text()`; every line is
## also emitted as a "tutorial_line" event and spoken through Audio (subtitles always).
##
## Every check reads the player's real kit and every drill works for every body: see
## docs/design/ANNOUNCER_AND_TUTORIAL.md §2.3 (partner choice, how the Kid drills, adaptations).

const SUCCESS_PAUSE := 3.2
const HINT_IDLE := 20.0
const HOLD_MARGIN := 0.15     ## m the Kid may still give ground during a Light string drill
const CHARGED_FRACTION := 0.35  ## a held Heavy counts as charged from here (Fighter switches to heavy_charged at it)
const RUSH_SLACK := 0.03      ## s of a strike's active part a cancel may cut before it counts as rushed

var start_index := 0
var on_exit: Callable = Callable()
var list: Array = []                 ## exercise dictionaries in order
var index := 0
var state := "active"                ## active | success | failed | done_single | complete
var state_t := 0.0
var ex_t := 0.0                      ## time in the current exercise
var progress_t := 0.0                ## last time progress was made (idle hints)
var hinted := false
var coach := {"kind": "", "text": ""}
var stage := 0
var data := {}                       ## per-exercise tracking
var completed: Array = []
var single := false                  ## replaying one exercise from the list: stop after it
var kid: KidScript
var _cursor := 0


func id() -> String:
	return "tutorial"


func setup(match_sim) -> void:
	match_sim.rules["round_time"] = 0.0
	match_sim.rules["rounds"] = 1
	match_sim.rules["intro_time"] = 0.0
	super.setup(match_sim)
	if rules.has("tutorial_start"):
		start_index = int(rules["tutorial_start"])
	list = Tutorial.exercises()
	completed = Tutorial.completed_ids().duplicate()
	kid = KidScript.new(self)
	if sim.fighters.size() > 1:
		sim.set_input_source(1, kid)
	_cursor = sim.event_seq
	start_exercise(clampi(start_index, 0, maxi(0, list.size() - 1)), start_index > 0)


func player() -> Fighter:
	return sim.fighters[0]


func partner() -> Fighter:
	return sim.fighters[1]


func current() -> Dictionary:
	return list[index] if index < list.size() else {}


## (Re)starts exercise `i`: both fighters back to their marks with full vitals.
func start_exercise(i: int, only_this := false) -> void:
	index = clampi(i, 0, list.size() - 1)
	single = only_this
	state = "active"
	state_t = 0.0
	ex_t = 0.0
	progress_t = 0.0
	hinted = false
	stage = 0
	data = {}
	sim.reset_round()
	phase = Phase.FIGHT
	sim.input_enabled = true
	for f in sim.fighters:
		f.mods["hype_gain"] = 1.0
		f.mods.erase("move_speed")
	var ex := current()
	var p := player()
	if str(ex.get("check", "")) == "finisher_juice":
		p.mods["hype_gain"] = 2.0      # the tutorial fills Hype faster so the lesson stays short
	if str(ex.get("check", "")) == "win_round":
		round_timer = float((ex.get("params", {}) as Dictionary).get("time", 60.0))
	kid.set_behavior(str(ex.get("dummy", "idle")))
	data["adapt"] = _adaptation(ex, p.creature)
	var intro := exercise_text("intro")
	if index == 0 and not only_this:
		var jab := Tutorial.jab_for(p.creature.id)
		if jab != "":
			intro = jab + " " + intro
	_say("intro", intro)
	sim.emit_event({"type": "tutorial_exercise", "index": index, "id": str(ex.get("id", ""))})


func retry() -> void:
	start_exercise(index, single)


func skip() -> void:
	if index + 1 < list.size():
		start_exercise(index + 1)
	else:
		_finish_all()


## Which parts of an exercise this fighter's kit cannot do (a fighter may lack a slot): flag ->
## true, only for the flags that apply. Those parts are skipped, and the exercise's "adapt" block
## (exercises.json) says so: its intro / goal / hint / success replace the normal lines (see
## exercise_text()). "skip": nothing of the exercise is possible; its success line is the explanation.
func _adaptation(ex: Dictionary, c: CreatureDef) -> Dictionary:
	var a := {}
	match str(ex.get("check", "")):
		"heavy_then_charged":
			if c.tags.has("martial") or (not c.moves.has("heavy_charged") and (not c.moves.has("heavy") or (c.moves["heavy"] as MoveDef).charge_time <= 0.0)):
				a["no_charge"] = true
		"dodge_then_dash":
			if c.tags.has("martial") or not c.moves.has("dash_attack"):
				a["no_dash"] = true
		"ability_connect":
			if not c.abilities.has(str((ex.get("params", {}) as Dictionary).get("slot", "ability1"))):
				a["skip"] = true
		"finisher_juice":
			if c.tags.has("martial") or not c.moves.has("finisher"):
				a["no_finisher"] = true
			if not c.abilities.has("juice"):
				a["no_juice"] = true
			if a.size() == 2:
				a = {"skip": true}
		"grab_throw":
			if not c.moves.has("grab"):
				a["skip"] = true
	return a


## The current exercise's line `key` (intro, goal, hint, success): the "adapt" block's version
## for the first adaptation flag that has one, else the exercise's own.
func exercise_text(key: String) -> String:
	var ex := current()
	if player().creature.tags.has("martial"):
		var guest := _martial_text(str(ex.get("check", "")), key)
		if guest != "":
			return guest
	var blocks: Dictionary = ex.get("adapt", {})
	for flag in (data.get("adapt", {}) as Dictionary):
		var b: Dictionary = blocks.get(flag, {})
		if b.has(key):
			return str(b[key])
	return str(ex.get(key, ""))


func adapted(flag: String) -> bool:
	return bool((data.get("adapt", {}) as Dictionary).get(flag, false))


func _say(kind: String, raw: String) -> void:
	var line := Tutorial.fill(raw, player().creature)
	coach = {"kind": kind, "text": line}
	sim.emit_event({"type": "tutorial_line", "kind": kind, "text": line, "index": index})
	if kind != "hint":
		Audio.stop_announcer() # Advancing a lesson replaces instructions for the previous state.
	Audio.say("granny", line, 80 if kind != "hint" else 60)


func objective() -> String:
	return Tutorial.fill(exercise_text("goal"), player().creature)


func tick_fight(dt: float) -> void:
	state_t += dt
	ex_t += dt
	var evs := sim.events_since(_cursor)
	if not evs.is_empty():
		_cursor = int(evs[-1]["seq"])
	match state:
		"active":
			_check(dt, evs)
			if not hinted and ex_t - progress_t > HINT_IDLE:
				_hint()
		"success":
			if state_t >= SUCCESS_PAUSE:
				if single:
					state = "done_single"
					state_t = 0.0
					if _all_completed():
						_save_progress(true)
				elif index + 1 >= list.size():
					_finish_all()
				else:
					start_exercise(index + 1)
		"failed":
			if state_t >= 3.0:
				retry()


func _progress() -> void:
	progress_t = ex_t


func _hint() -> void:
	hinted = true
	_say("hint", exercise_text("hint"))


func _fail() -> void:
	state = "failed"
	state_t = 0.0
	_say("hint", exercise_text("hint"))


func _succeed() -> void:
	state = "success"
	state_t = 0.0
	var ex := current()
	var id_ := str(ex.get("id", ""))
	if not id_ in completed:
		completed.append(id_)
	_save_progress(false)
	_say("success", exercise_text("success"))
	sim.emit_event({"type": "tutorial_success", "index": index, "id": id_})
	if not adapted("skip"):
		Audio.announce_trigger("tutorial", {"kind": _barnaby_kind(str(ex.get("check", "")))})
	kid.set_behavior("idle")


func _barnaby_kind(check: String) -> String:
	return {"footwork": "start", "light_string": "string", "heavy_then_charged": "heavy", "guard_string": "guard",
		"dodge_then_dash": "dodge", "ability_connect": "ability", "grab_throw": "string", "parries": "parry",
		"finisher_juice": "ability", "win_round": "complete"}.get(check, "start")


func _finish_all() -> void:
	state = "complete"
	state_t = 0.0
	_save_progress(_all_completed())
	sim.emit_event({"type": "tutorial_complete", "all": _all_completed()})


func _all_completed() -> bool:
	for ex in list:
		if not str(ex.get("id", "")) in completed:
			return false
	return true


func _save_progress(all_done: bool) -> void:
	var t: Dictionary = Profiles.current.get("tutorial", {})
	t["exercises"] = completed.duplicate()
	if all_done and _all_completed():
		t["completed"] = true
		Platform.unlock_achievement("ach_tutorial")
	Profiles.current["tutorial"] = t
	Profiles.save()


func leave() -> void:
	sim.paused = true
	if on_exit.is_valid():
		on_exit.call()
	else:
		Tutorial.exit_tutorial()


# ---------------------------------------------------------------------------------------------
# success checks (one per exercise "check" kind)

func _check(dt: float, evs: Array) -> void:
	var ex := current()
	var prm: Dictionary = ex.get("params", {})
	var p := player()
	var k := partner()
	if adapted("skip"):
		_succeed()       # the kit can't do any of it: the adapted success line says so
		return
	match str(ex.get("check", "")):
		"footwork":
			var rings: Array = prm.get("rings", [])
			var done: Array = data.get("rings", [])
			var pp := p.pos()
			for i in rings.size():
				var r: Array = rings[i]
				if not i in done and Vector2(pp.x - float(r[0]), pp.z - float(r[1])).length() < float(prm.get("ring_radius", 0.6)):
					done.append(i)
					data["rings"] = done
					_progress()
					sim.emit_event({"type": "tutorial_ring", "ring": i})
			if done.size() >= rings.size():
				var kp := k.pos()
				var ang := atan2(pp.x - kp.x, pp.z - kp.z)
				var to_kid := Vector3(kp.x - pp.x, 0.0, kp.z - pp.z)
				var facing := to_kid.length() > 0.1 and p.forward().dot(to_kid.normalized()) > 0.6
				if data.has("ang") and facing and to_kid.length() < 4.5:
					var d := wrapf(ang - float(data["ang"]), -PI, PI)
					data["circle"] = float(data.get("circle", 0.0)) + absf(d)
					if absf(d) > 0.0005:
						_progress()
				data["ang"] = ang
				if rad_to_deg(float(data.get("circle", 0.0))) >= float(prm.get("circle_degrees", 330.0)):
					_succeed()
		"light_string":
			var string := string_slots(p.creature)
			var gap := float(prm.get("gap", 1.2))
			if int(data.get("step", 0)) > 0 and sim.time - float(data.get("t", 0.0)) > gap:
				data["step"] = 0           # the chain went cold: start over
				kid.hold_dist = -1.0
			for i in evs.size():
				var ev: Dictionary = evs[i]
				if ev["type"] == "move_start" and int(ev["fighter"]) == 0:
					_note_swing(_tutorial_slot(str(ev.get("slot", "")), p.creature), string)
					continue
				if ev["type"] != "hit" or int(ev["fighter"]) != 0 or int(ev["target"]) != 1 or bool(ev["blocked"]):
					continue
				var slot := _hit_slot(evs, i, p)
				var swing: Dictionary = data.get("swing", {})
				if slot == str(swing.get("slot", "")):
					swing["landed"] = true
				var step := int(data.get("step", 0))
				if step < string.size() and slot == str(string[step]):
					step += 1
					data["t"] = sim.time
					_progress()
				elif slot == str(string[0]):
					step = 1
					data["t"] = sim.time
				else:
					continue
				data["step"] = step
				if step == 1:
					# the Kid holds his ground for the rest of the string: he can't be knocked
					# further away than he stood when the first hit landed (see KidScript)
					kid.hold_dist = Vector2(k.pos().x - p.pos().x, k.pos().z - p.pos().z).length() + HOLD_MARGIN
				if step >= string.size():
					_succeed()
					return
		"heavy_then_charged":
			for i in evs.size():
				var ev: Dictionary = evs[i]
				if ev["type"] != "hit" or int(ev["fighter"]) != 0 or int(ev["target"]) != 1:
					continue
				var slot2 := _hit_slot(evs, i, p)
				if not slot2 in ["heavy", "heavy_charged"]:
					continue
				# charged: the kit's dedicated charged heavy, or a Heavy held past the point where
				# Fighter would switch to one (CHARGED_FRACTION of its charge time)
				var charged := slot2 == "heavy_charged" or (bool(ev.get("charged", false)) and
					(p.move_slot.split("@")[0] != "heavy" or p.move_charge >= CHARGED_FRACTION))
				if stage == 0:
					stage = 1
					_progress()
					if adapted("no_charge"):
						_succeed()
						return
					_say("hint", "Good. Now hold {heavy} for {charged_name}, and let it go with him in range.")
				elif charged:
					_succeed()
					return
		"guard_string":
			_check_guard_string(prm, evs)
		"dodge_then_dash":
			for i in evs.size():
				var ev: Dictionary = evs[i]
				var t := str(ev["type"])
				if stage == 0:
					if t == "move_start" and int(ev["fighter"]) == 1 and str(ev.get("slot", "")).split("@")[0] in ["heavy", "heavy_charged"]:
						data["kid_heavy"] = true
						data["dodged"] = false
						data["hit"] = false
					elif t == "dodge" and int(ev["fighter"]) == 0 and bool(data.get("kid_heavy", false)):
						data["dodged"] = true
					elif t == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0:
						data["hit"] = true
				elif t == "hit" and int(ev["fighter"]) == 0 and int(ev["target"]) == 1 and _hit_slot(evs, i, p) == "dash_attack":
					_succeed()
					return
			if stage == 0 and bool(data.get("kid_heavy", false)) and k.state != Fighter.State.ATTACK:
				data["kid_heavy"] = false
				if bool(data.get("dodged", false)) and not bool(data.get("hit", false)):
					stage = 1
					_progress()
					if adapted("no_dash"):
						_succeed()
						return
					_say("hint", "Nothing hits what isn't there. Now press {light} while you're dodging — dash attack.")
				elif bool(data.get("hit", false)):
					_hint()
		"ability_connect":
			var slot3 := str(prm.get("slot", "ability1"))
			for ev in evs:
				if ev["type"] == "ability" and int(ev["fighter"]) == 0 and str(ev.get("slot", "")) == slot3:
					data["used_at"] = sim.time
					data["kid_hp"] = k.health
					data["kid_bu"] = _buildup_total(k)
					_progress()
				elif ev["type"] == "hit" and int(ev["fighter"]) == 0 and int(ev["target"]) == 1 and data.has("used_at"):
					if str(ev.get("move_class", "")) == "ability" or str(ev.get("slot", "")).begins_with(slot3):
						_succeed()
						return
			if data.has("used_at") and sim.time - float(data["used_at"]) <= float(prm.get("window", 3.0)):
				if k.health < float(data["kid_hp"]) - 0.5 or _buildup_total(k) > float(data["kid_bu"]) + 1.0 or _in_own_zone(k, 0):
					_succeed()
		"grab_throw":
			for ev in evs:
				if ev["type"] == "grab" and int(ev["fighter"]) == 0:
					_progress()
				if ev["type"] == "throw" and int(ev["fighter"]) == 0 and int(ev.get("victim", -1)) == 1:
					_succeed()
					return
		"parries":
			for ev in evs:
				if ev["type"] == "parry" and int(ev["fighter"]) == 0:
					data["parries"] = int(data.get("parries", 0)) + 1
					_progress()
					if int(data["parries"]) >= int(prm.get("count", 2)):
						_succeed()
						return
		"finisher_juice":
			if stage == 0 and adapted("no_finisher"):
				stage = 1
			if stage == 1 and adapted("no_juice"):
				_succeed()
				return
			for i in evs.size():
				var ev: Dictionary = evs[i]
				if stage == 0 and ev["type"] == "hit" and int(ev["fighter"]) == 0 and int(ev["target"]) == 1 and _hit_slot(evs, i, p) == "finisher":
					stage = 1
					_progress()
					if adapted("no_juice"):
						_succeed()
						return
					_say("hint", "That's your finisher. Now fill the Hype meter — hits, or {taunt} — then {juice}.")
				elif stage == 1 and ev["type"] == "juice" and int(ev["fighter"]) == 0:
					_succeed()
					return
			if stage == 1 and p.hype > float(data.get("hype_seen", 0.0)) + 5.0:
				data["hype_seen"] = p.hype
				_progress()
		"win_round":
			if not hinted and ex_t >= 30.0 and p.health_frac() < k.health_frac():
				_hint()
			round_timer = maxf(0.0, round_timer - dt)
			if round_timer <= 0.0:
				if p.health_frac() > k.health_frac():
					_succeed()
				else:
					_fail()


## Hands drill feedback for mashing: a string Light that starts while the previous one was still
## in its active part and hadn't landed cancelled it (a buffered Light is consumed at the cancel
## time, which for some kits is the very tick the active window opens). The second time,
## Granny says the exercise's "rush" line, once per attempt.
func _note_swing(slot: String, string: Array) -> void:
	var prev: Dictionary = data.get("swing", {})
	if slot in string and prev.has("slot") and not bool(prev.get("landed", false)):
		var m: MoveDef = player().creature.moves.get(str(prev["slot"]))
		if m and sim.time - float(prev["t"]) < active_end(m) - RUSH_SLACK:
			data["rushed"] = int(data.get("rushed", 0)) + 1
			if int(data["rushed"]) >= 2 and not data.has("rush_said") and exercise_text("rush") != "":
				data["rush_said"] = true
				_say("hint", exercise_text("rush"))
	data["swing"] = {"slot": slot if slot in string else "", "t": sim.time, "landed": false}


func _check_guard_string(prm: Dictionary, evs: Array) -> void:
	var p := player()
	for ev in evs:
		if ev["type"] == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0 and kid.string_active:
			if bool(ev["blocked"]):
				data["blocked"] = int(data.get("blocked", 0)) + 1
				_progress()
			else:
				data["clean"] = int(data.get("clean", 0)) + 1
	if kid.string_active and not data.has("hp0"):
		data["hp0"] = p.health
		data["blocked"] = 0
		data["clean"] = 0
	if not kid.string_active and data.has("hp0"):
		var lost := (float(data["hp0"]) - p.health) / maxf(1.0, p.max_health)
		var blocked := int(data.get("blocked", 0))
		data.erase("hp0")
		if blocked >= int(prm.get("min_blocked", 2)) and lost <= float(prm.get("max_loss", 0.1)):
			_succeed()
		elif blocked + int(data.get("clean", 0)) > 0:
			_hint()


## True when `f` may throw the next strike of a string and still land the current one: it is
## free, or its current move connected or has finished its active part (windows and timed
## effects). A Light pressed earlier is consumed at the move's cancel time, which for some kits
## is the very tick its active window opens, so the strike would never land.
static func swing_over(f: Fighter) -> bool:
	if f.state == Fighter.State.NEUTRAL:
		return true
	if f.state != Fighter.State.ATTACK or f.move == null:
		return false
	return f.move_hit_any or f.state_time >= active_end(f.move)


## True when a buffered Light cancels `m` before it could land: its cancel time comes more than
## RUSH_SLACK before the end of its active part (Stoke's Jab cancels as its window opens).
static func rushable(m: MoveDef) -> bool:
	return m.cancel_t0 < active_end(m) - RUSH_SLACK


## When a move's active part is over (move time): its last hit window or timed effect, at least
## its cancel time, and a little before it ends so a string can still chain from it.
static func active_end(m: MoveDef) -> float:
	var t_done := m.cancel_t0
	for w in m.windows:
		t_done = maxf(t_done, float(w["t1"]))
	for e in m.effects:
		t_done = maxf(t_done, float(e.get("t", 0.0)))
	return minf(t_done, m.duration - 0.05)


## The Light string the Hands drill asks for: the kit's first three string slots (a slot the kit
## lacks falls back to l1, as Fighter does when it presses Light).
static func string_slots(c: CreatureDef) -> Array:
	var out: Array = []
	for slot in c.light_string.slice(0, 3):
		out.append(slot if c.moves.has(slot) else "l1")
	return out


## The move slot (variant suffix dropped) behind hit event `evs[i]` of fighter `f`. Effect hits
## (slot "effect") belong to the move whose own timeline fired them:
##  * an effect with an "id" reports it as the hit's "move" (Slurry's finisher spits the
##    projectile "venom_spit", which lands after the move has ended), so it maps to the move
##    that declares it;
##  * an unnamed one is paired with its "effect" event: EffectsSystem emits an effect's hits
##    first (Combat.deliver emits each hit after its hooks ran) and then that effect's event
##    with the move's id, in the same tick (Dozer's Hoof Stomp, an area at the hoof).
## Hook-fired and delayed effects carry no move id and give "".
static func _hit_slot(evs: Array, i: int, f: Fighter) -> String:
	var ev: Dictionary = evs[i]
	var slot := str(ev.get("slot", ""))
	if slot != "effect":
		return _tutorial_slot(slot, f.creature)
	var eid := str(ev.get("move", ""))
	for s in f.creature.moves:
		for e in (f.creature.moves[s] as MoveDef).effects:
			if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("id", "")) == eid and eid != "":
				return str(s).split("@")[0]
	for j in range(i + 1, evs.size()):
		var e2: Dictionary = evs[j]
		if int(e2.get("tick", -1)) != int(ev.get("tick", -2)):
			break
		if e2["type"] == "effect" and int(e2.get("fighter", -1)) == int(ev["fighter"]):
			var mid := str(e2.get("move", ""))
			for s in f.creature.moves:
				if mid != "" and (f.creature.moves[s] as MoveDef).id == mid:
					return str(s).split("@")[0]
			return ""
	return ""


func _buildup_total(f: Fighter) -> float:
	var t := 0.0
	for el in f.statuses.buildup:
		t += float(f.statuses.buildup[el])
	return t + f.statuses.active.size() * 100.0


func _in_own_zone(f: Fighter, owner: int) -> bool:
	for e in sim.effects.entities:
		if str(e.get("kind", "")) == "zone" and int(e.get("owner", -1)) == owner:
			var ep: Vector3 = e["pos"]
			if Vector2(ep.x - f.pos().x, ep.z - f.pos().z).length() < float(e.get("radius", 1.0)):
				return true
	return false


# ---------------------------------------------------------------------------------------------
# no KOs except in the freestyle round

func on_depleted(f: Fighter, attacker: Fighter, hit: Dictionary) -> void:
	if str(current().get("check", "")) == "win_round" and state == "active":
		if f.index == 1:
			super.on_depleted(f, attacker, hit)
			_succeed()
		else:
			f.health = 1.0
			_fail()
		return
	f.health = f.max_health
	sim.emit_event({"type": "practice_refill", "fighter": f.index})


func check_round_over() -> void:
	pass


func on_timeout() -> void:
	pass


func hud_status() -> String:
	return ""      # the tutorial overlay shows the exercise title, goal and progress


func progress_text() -> String:
	var ex := current()
	var prm: Dictionary = ex.get("params", {})
	if adapted("skip"):
		return "Not in your kit"
	match str(ex.get("check", "")):
		"footwork":
			var n := (data.get("rings", []) as Array).size()
			var total := (prm.get("rings", []) as Array).size()
			if n < total:
				return "Rings %d / %d" % [n, total]
			return "Circle him: %d° / %d°" % [int(rad_to_deg(float(data.get("circle", 0.0)))), int(prm.get("circle_degrees", 330))]
		"light_string":
			return "String %d / %d" % [int(data.get("step", 0)), string_slots(player().creature).size()]
		"heavy_then_charged":
			var heavy := "Heavy %s" % ("✓" if stage >= 1 else "–")
			return heavy if adapted("no_charge") else heavy + "   Charged Heavy –"
		"guard_string":
			return "Blocked %d of his string" % int(data.get("blocked", 0)) if data.has("hp0") else "Wait for his string…"
		"dodge_then_dash":
			var dodge := "Dodge his Heavy %s" % ("✓" if stage >= 1 else "–")
			return dodge if adapted("no_dash") else dodge + "   Dash Attack –"
		"parries":
			return "Parries %d / %d" % [int(data.get("parries", 0)), int(prm.get("count", 2))]
		"finisher_juice":
			var parts: Array = []
			if not adapted("no_finisher"):
				parts.append("Finisher %s" % ("✓" if stage >= 1 else "–"))
			if not adapted("no_juice"):
				parts.append("Hype %d / 100   JUICE –" % int(player().hype))
			return "   ".join(parts)
		"win_round":
			return "%d s   You %d%%  Kid %d%%" % [ceili(round_timer), int(player().health_frac() * 100.0), int(partner().health_frac() * 100.0)]
	return ""


func hud_state() -> Dictionary:
	return {"rows": [], "status": hud_status(), "highlight": str(current().get("highlight", ""))}


func view_state() -> Dictionary:
	var v := super.view_state()
	v["mode"] = "tutorial"
	var ex := current()
	if str(ex.get("check", "")) == "footwork":
		var rings := []
		var prm: Dictionary = ex.get("params", {})
		var done: Array = data.get("rings", [])
		var all_rings: Array = prm.get("rings", [])
		for i in all_rings.size():
			var r: Array = all_rings[i]
			rings.append({"pos": Vector3(float(r[0]), 0.0, float(r[1])), "radius": float(prm.get("ring_radius", 0.6)), "done": i in done})
		v["rings"] = rings
	return v


## Kid Lamprey's scripted behaviours (attack toggles controlled by the exercise).
class KidScript:
	extends InputSource
	var _mode: WeakRef
	var mode: TutorialMode:
		get: return _mode.get_ref() as TutorialMode
	var behavior := "idle"
	var string_active := false
	var _t := 0.0
	var _phase := "rest"
	var _phase_t := 0.0
	var _left := 0
	var _last_press := -1.0
	var _alt := false
	var _bot: BotBrain = null
	var _reach := BotBrain.new("regular", 1)   ## only for its cached move-reach estimates
	var _prev_dist := -1.0
	var _stuck_t := 0.0
	## > 0: the Kid holds his ground (a Light string drill in progress): knockback can't carry
	## him further than this from the player, so a string that started landing can finish.
	## Kits whose strings push the target out of the next hit's reach (Stoke's jab and cross on
	## the 55 kg Gusto stand-in, Dozer's stomp before the Scoop) would otherwise make the Hands
	## drill a matter of luck; inside that distance he still reacts to every hit normally.
	var hold_dist := -1.0
	var _spacing := {}           ## "light" | "heavy" -> index into SPACINGS (fractions of the reach)
	var _want := 0.0             ## the spacing (m) of the attack being set up
	var _record := {}            ## "<kind><spacing index>" -> Vector2i(attacks that landed, attacks)
	var _seen_hit_at := 0.0
	var _landed := {}            ## slots of the current attack that touched the player
	var _evaded := false         ## the player dodged the current attack

	func _init(m) -> void:
		_mode = weakref(m)

	func label() -> String:
		return "Kid Lamprey (%s)" % behavior

	## Drill state for traces and debugging.
	func debug_text() -> String:
		return "%s %s spacing %s hold %.2f" % [behavior, _phase, str(_spacing), hold_dist]

	func set_behavior(b: String) -> void:
		behavior = b
		_phase = "rest"
		_phase_t = 0.0
		_left = 0
		string_active = false
		hold_dist = -1.0
		_bot = BotBrain.new(BotTiers.brain_tier("punching_bag"), 777) if b == "fight" else null
		var k: Fighter = mode.partner()
		k.mods.erase("move_speed")
		if b in ["parry_drill", "heavy"]:
			k.mods["move_speed"] = 0.75     # telegraphed: longer, readable wind-ups
		# fighting back he is a Punching Bag-tier bot with the handicaps the game's easiest
		# difficulty gives every opponent (Sparring, content/core/ladder/difficulty.json). The
		# freestyle closes a beginner's tutorial: without them even his deliberately weak kit
		# splits 60 s rounds with a slow fighter (Dredge: a strong player needed two rounds),
		# and a roster stand-in is a full-strength fighter (a rookie Stoke's overhand on Dredge)
		var spar: Dictionary = Content.get_entry("ladder", "sparring") if b == "fight" else {}
		k.mods["damage"] = float(spar.get("enemy_damage", 1.0))
		var hp := float(spar.get("enemy_hp", 1.0))
		if not is_equal_approx(float(k.mods.get("max_health", 1.0)), hp):
			k.mods["max_health"] = hp
			k.max_health = k.creature.stat("health") * hp + float(k.mods.get("max_health_add", 0.0))
			k.health = k.max_health

	func poll(f: Fighter, sim, dt: float) -> void:
		_t += dt
		_phase_t += dt
		f.input.move = Vector3.ZERO
		f.input.held = 0
		if mode.state != "active" and behavior != "fight":
			string_active = false
			return
		var p: Fighter = sim.fighters[0]
		var to := Vector3(p.pos().x - f.pos().x, 0.0, p.pos().z - f.pos().z)
		var dist := to.length()
		if hold_dist > 0.0 and dist > hold_dist and dist > 0.01:
			var away := -to / dist
			var out := f.rig.com_velocity().dot(away)
			if out > 0.0:
				f.rig.apply_body_impulse(-away * out * f.rig.total_mass)
		match behavior:
			"guard":
				f.input.set_held(FighterInput.GUARD, true)
			"fight":
				if _bot:
					_bot.poll(f, sim, dt)
			"string", "heavy", "parry_drill":
				_attacker(f, p, to, dist, dt)

	## The drills' attacks: rest, take up his spacing (walk in, or step back when he's crowding
	## the player), throw it, rest again. Two rules keep every drill fair for every body:
	##  * a string goes in one strike at a time: the next Light only once the last one connected
	##    or finished its swing (pressed earlier, a buffered Light cancels a strike on the very
	##    tick its active window opens and it never lands);
	##  * spacing adapts: each attack kind keeps a record per spacing in SPACINGS (fractions of
	##    the move's estimated reach); when the attacks thrown from one land on the player (two
	##    strikes of a string, else the strike; blocked and parried count, dodged ones don't
	##    count either way) less than half the time, the next spacing is tried. The estimate is
	##    generous; strikes authored against a tall body pass over a short one from its edge
	##    (Jitters), and from too close they are smothered by a raised guard before they get
	##    going (Dredge's claws stand 0.9 m out in front of him).
	## The estimate (BotBrain.reach_of: furthest strike point + 70% of the lunge + weapon radius)
	## overshoots where strikes really land: the Kid's jab estimates 1.16 m and lands at
	## 0.9–1.0 m (docs/kits/npc_kid_lamprey.md), so he starts at 0.8 of it, where a fist meets
	## the body early in its active window (a parry is timed to that), then tries closer, the
	## edge, and closer still.
	const SPACINGS := [0.8, 0.65, 0.95, 0.5, 0.4]
	const BAND := 0.2            ## m inside his spacing that still counts as "at" it

	func _attacker(f: Fighter, p: Fighter, to: Vector3, dist: float, dt: float) -> void:
		var light := behavior == "string" or (behavior == "parry_drill" and not _alt)
		var kind := "light" if light else "heavy"
		match _phase:
			"rest":
				string_active = false
				if _phase_t > 2.2:
					_phase = "approach"
					_phase_t = 0.0
					_prev_dist = -1.0
					_stuck_t = 0.0
			"approach":
				var reach := _reach.reach_of(f.creature, "l1" if light else "heavy")
				var want := reach * float(SPACINGS[int(_spacing.get(kind, 0)) % SPACINGS.size()]) + 0.05
				if _prev_dist >= 0.0 and _prev_dist - dist < 0.004:
					_stuck_t += dt
				else:
					_stuck_t = 0.0
				_prev_dist = dist
				_want = want
				var close_enough := dist <= want or (_phase_t > 0.5 and _stuck_t > 0.35) or _phase_t > 3.0
				if dist < want - BAND and _phase_t < 1.5:
					f.input.move = -to.normalized()       # crowding him: step back to his spacing
				elif not close_enough:
					# eases off as he arrives, so he stops at his spacing instead of sliding past it
					f.input.move = to.normalized() * clampf((dist - want) / 0.6, 0.25, 1.0)
				else:
					_phase = "set"
					_phase_t = 0.0
				if _phase_t > 4.0:
					_phase = "rest"
					_phase_t = 0.0
			"set":
				# plants his feet before he throws: every drill strike starts from rest at his
				# spacing (walking momentum would carry him into a raised guard), and the beat
				# before it is the cue Granny tells you to watch for
				if dist < _want - BAND and _phase_t < 1.0 and _stuck_t <= 0.35:
					f.input.move = -to.normalized()       # slid in too close: back to his spacing
					return
				var v := f.rig.com_velocity()
				var settled := Vector2(v.x, v.z).length() < 0.4 and _phase_t >= 0.25
				if (settled or _phase_t > 1.2) and f.state == Fighter.State.NEUTRAL:
					_phase = "attack"
					_phase_t = 0.0
					_last_press = -1.0
					_seen_hit_at = mode.sim.time
					_landed = {}
					_evaded = false
					_left = (3 if behavior == "string" else 1) if light else 0
					if not light:
						f.input.press(FighterInput.HEAVY)
					string_active = true
				elif _phase_t > 2.0:
					_phase = "rest"
					_phase_t = 0.0
			"attack":
				if p.last_attacker_index == f.index and p.last_attacked_at > _seen_hit_at:
					_seen_hit_at = p.last_attacked_at      # a new hit on the player (clean, blocked or parried)
					_landed[f.move_slot if f.move_slot != "" else "?"] = true
				_evaded = _evaded or p.state == Fighter.State.DODGE or p.is_evading()
				if _left > 0 and _phase_t - _last_press > 0.1 and TutorialMode.swing_over(f):
					f.input.press(FighterInput.LIGHT)
					_left -= 1
					_last_press = _phase_t
				var done := _left <= 0 and _phase_t > 0.3 and f.state != Fighter.State.ATTACK
				if done or _phase_t > 3.0:
					# a string should land at least two of its three strikes (the guard drill counts
					# them), a single attack should land; a spacing that misses more often than not
					# gives way to the next one
					if not _evaded:
						var key := "%s%d" % [kind, int(_spacing.get(kind, 0)) % SPACINGS.size()]
						var rec: Vector2i = _record.get(key, Vector2i.ZERO) + Vector2i(1 if _landed.size() >= (2 if behavior == "string" else 1) else 0, 1)
						_record[key] = rec
						if rec.x * 2 < rec.y:
							_spacing[kind] = int(_spacing.get(kind, 0)) + 1
					if done:
						_alt = not _alt
					_phase = "rest"
					_phase_t = 0.0
					string_active = false


static func _tutorial_slot(slot: String, c: CreatureDef) -> String:
	var basic := slot.split("@")[0]
	if not c.tags.has("martial"):
		return basic
	if slot.ends_with("@southpaw") and basic.begins_with("rh_"):
		basic = "lh_" + basic.substr(3)
	elif slot.ends_with("@southpaw") and basic.begins_with("lh_"):
		basic = "rh_" + basic.substr(3)
	return "heavy" if basic.ends_with("_hkick") else basic


static func _martial_text(kind: String, key: String) -> String:
	var text := ""
	match kind:
		"footwork":
			text = "Forward moves toward your opponent; back opens distance. Left and right circle them. Visit the rings, then circle the Kid."
		"light_string":
			text = "Hold Straights {mma_mod2}: left hand {mma_lh}, then right hand {mma_rh}. Switch to Hooks {mma_mod1} and land left hand {mma_lh}. Let each hit land before the next. In Movesets each modifier carries a technique (Pressure Palm, Comet Hook), and after two strikes that connect, a hand with no modifier unleashes the Thousand-Fist Flurry."
		"heavy_then_charged":
			text = "Hold Straights {mma_mod2} and press right leg {mma_rl} for a head kick. Land one clean kick. Varga's kicks do not charge; in Movesets his Pressure Palm does: hold the hand after Straights {mma_mod2} to gather its aura blast."
		"dodge_then_dash":
			text = "Slip {mma_dodge} the Kid's big swing so it never touches you. In Movesets, switch stance {mma_stance} as you slip and the slip becomes the Afterimage Rush, a gold dash that strikes back."
		"ability_connect":
			text = "Use Cut the Angle {ability1}, then land a strike within two seconds to use the damage bonus. The step itself does not deal damage."
		"grab_throw":
			text = "Step close and press {grab} to clinch. Aim a direction and press {grab} again to throw. Limb buttons pummel while holding."
		"finisher_juice":
			text = "Fill Hype with hits or {taunt}. Tap and release {juice} for Championship Rounds. Varga has independent strikes instead of the standard combo finisher; in Movesets his finisher is the Thousand-Fist Flurry: connect with two strikes, then press a hand with no modifier."
	return text if key in ["intro", "goal", "hint"] else ""
