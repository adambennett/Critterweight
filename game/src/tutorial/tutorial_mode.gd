class_name TutorialMode
extends MatchMode
## Granny Haymaker's tutorial (UI-12): ten staged exercises against Kid Lamprey, each with a
## data-defined success check (content/core/tutorial/exercises.json), live binding prompts,
## hints after failure or 20 s without progress, retry / skip / replay, and a real 60 s round
## at the end. Fighter 0 is the player, fighter 1 the Kid driven by KidScript.
##
## Presentation reads `coach` (current line), `objective()` and `progress_text()`; every line is
## also emitted as a "tutorial_line" event and spoken through Audio (subtitles always).

const SUCCESS_PAUSE := 3.2
const HINT_IDLE := 20.0

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
	var intro := str(ex.get("intro", ""))
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


func _say(kind: String, text: String) -> void:
	var line := Tutorial.fill(text, player().creature)
	coach = {"kind": kind, "text": line}
	sim.emit_event({"type": "tutorial_line", "kind": kind, "text": line, "index": index})
	Audio.say("granny", line, 80 if kind != "hint" else 60)


func objective() -> String:
	return Tutorial.fill(str(current().get("goal", "")), player().creature)


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
				if index + 1 >= list.size():
					_finish_all()
				elif single:
					state = "done_single"
					state_t = 0.0
				else:
					start_exercise(index + 1)
		"failed":
			if state_t >= 3.0:
				retry()


func _progress() -> void:
	progress_t = ex_t


func _hint() -> void:
	hinted = true
	_say("hint", str(current().get("hint", "")))


func _fail() -> void:
	state = "failed"
	state_t = 0.0
	_say("hint", str(current().get("hint", "")))


func _succeed() -> void:
	state = "success"
	state_t = 0.0
	var ex := current()
	var id_ := str(ex.get("id", ""))
	if not id_ in completed:
		completed.append(id_)
	_save_progress(false)
	_say("success", str(ex.get("success", "")))
	sim.emit_event({"type": "tutorial_success", "index": index, "id": id_})
	Audio.announce_trigger("tutorial", {"kind": _barnaby_kind(str(ex.get("check", "")))})
	kid.set_behavior("idle")


func _barnaby_kind(check: String) -> String:
	return {"footwork": "start", "light_string": "string", "heavy_then_charged": "heavy", "guard_string": "guard",
		"dodge_then_dash": "dodge", "ability_connect": "ability", "grab_throw": "string", "parries": "parry",
		"finisher_juice": "ability", "win_round": "complete"}.get(check, "start")


func _finish_all() -> void:
	state = "complete"
	state_t = 0.0
	_save_progress(true)
	sim.emit_event({"type": "tutorial_complete"})


func _save_progress(all_done: bool) -> void:
	var t: Dictionary = Profiles.current.get("tutorial", {})
	t["exercises"] = completed.duplicate()
	if all_done or completed.size() >= list.size():
		t["completed"] = true
	Profiles.current["tutorial"] = t
	Profiles.save()


func leave() -> void:
	sim.paused = true
	if on_exit.is_valid():
		on_exit.call()


# ---------------------------------------------------------------------------------------------
# success checks (one per exercise "check" kind)

func _check(dt: float, evs: Array) -> void:
	var ex := current()
	var prm: Dictionary = ex.get("params", {})
	var p := player()
	var k := partner()
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
			var string: Array = p.creature.light_string.slice(0, 3)
			for ev in evs:
				if ev["type"] != "hit" or int(ev["fighter"]) != 0 or int(ev["target"]) != 1 or bool(ev["blocked"]):
					continue
				var slot := str(ev.get("slot", ""))
				var step := int(data.get("step", 0))
				var gap := float(prm.get("gap", 1.2))
				if step > 0 and sim.time - float(data.get("t", 0.0)) > gap:
					step = 0
				if step < string.size() and slot == str(string[step]):
					step += 1
					data["t"] = sim.time
					_progress()
				elif slot == str(string[0]):
					step = 1
					data["t"] = sim.time
				data["step"] = step
				if step >= string.size():
					_succeed()
					return
		"heavy_then_charged":
			for ev in evs:
				if ev["type"] != "hit" or int(ev["fighter"]) != 0 or int(ev["target"]) != 1:
					continue
				var slot2 := str(ev.get("slot", ""))
				var charged := slot2 == "heavy_charged" or (slot2 == "heavy" and bool(ev.get("charged", false)))
				if stage == 0 and slot2 == "heavy" and not charged:
					stage = 1
					_progress()
					_say("hint", "Good. Now hold {heavy} and let it go near him.")
				elif stage == 1 and charged:
					_succeed()
					return
		"guard_string":
			_check_guard_string(prm, evs)
		"dodge_then_dash":
			for ev in evs:
				var t := str(ev["type"])
				if stage == 0:
					if t == "move_start" and int(ev["fighter"]) == 1 and str(ev.get("slot", "")) in ["heavy", "heavy_charged"]:
						data["kid_heavy"] = true
						data["dodged"] = false
						data["hit"] = false
					elif t == "dodge" and int(ev["fighter"]) == 0 and bool(data.get("kid_heavy", false)):
						data["dodged"] = true
					elif t == "hit" and int(ev["fighter"]) == 1 and int(ev["target"]) == 0:
						data["hit"] = true
				elif t == "hit" and int(ev["fighter"]) == 0 and int(ev["target"]) == 1 and str(ev.get("slot", "")) == "dash_attack":
					_succeed()
					return
			if stage == 0 and bool(data.get("kid_heavy", false)) and k.state != Fighter.State.ATTACK:
				data["kid_heavy"] = false
				if bool(data.get("dodged", false)) and not bool(data.get("hit", false)):
					stage = 1
					_progress()
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
			for ev in evs:
				if stage == 0 and ev["type"] == "hit" and int(ev["fighter"]) == 0 and str(ev.get("slot", "")) == "finisher":
					stage = 1
					_progress()
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
	match str(ex.get("check", "")):
		"footwork":
			var n := (data.get("rings", []) as Array).size()
			var total := (prm.get("rings", []) as Array).size()
			if n < total:
				return "Rings %d / %d" % [n, total]
			return "Circle him: %d° / %d°" % [int(rad_to_deg(float(data.get("circle", 0.0)))), int(prm.get("circle_degrees", 330))]
		"light_string":
			return "String %d / 3" % int(data.get("step", 0))
		"heavy_then_charged":
			return "Heavy %s   Charged Heavy %s" % ["✓" if stage >= 1 else "–", "–"]
		"guard_string":
			return "Blocked %d of his string" % int(data.get("blocked", 0)) if data.has("hp0") else "Wait for his string…"
		"dodge_then_dash":
			return "Dodge his Heavy %s   Dash Attack –" % ("✓" if stage >= 1 else "–")
		"parries":
			return "Parries %d / %d" % [int(data.get("parries", 0)), int(prm.get("count", 2))]
		"finisher_juice":
			return "Finisher %s   Hype %d / 100   JUICE –" % ["✓" if stage >= 1 else "–", int(player().hype)]
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
	var mode
	var behavior := "idle"
	var string_active := false
	var _t := 0.0
	var _phase := "rest"
	var _phase_t := 0.0
	var _left := 0
	var _last_press := -1.0
	var _alt := false
	var _bot: BotBrain = null

	func _init(m) -> void:
		mode = m

	func label() -> String:
		return "Kid Lamprey (%s)" % behavior

	func set_behavior(b: String) -> void:
		behavior = b
		_phase = "rest"
		_phase_t = 0.0
		_left = 0
		string_active = false
		_bot = BotBrain.new("rookie", 777) if b == "fight" else null
		var k: Fighter = mode.partner()
		k.mods.erase("move_speed")
		if b in ["parry_drill", "heavy"]:
			k.mods["move_speed"] = 0.75     # telegraphed: longer, readable wind-ups

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
		match behavior:
			"guard":
				f.input.set_held(FighterInput.GUARD, true)
			"fight":
				if _bot:
					_bot.poll(f, sim, dt)
			"string", "heavy", "parry_drill":
				_attacker(f, to, dist, dt)

	func _attacker(f: Fighter, to: Vector3, dist: float, _dt: float) -> void:
		match _phase:
			"rest":
				string_active = false
				if _phase_t > 2.2:
					_phase = "approach"
					_phase_t = 0.0
			"approach":
				var want := 1.05 if behavior == "string" or (behavior == "parry_drill" and not _alt) else 1.25
				if dist > want:
					f.input.move = to.normalized()
				elif f.state == Fighter.State.NEUTRAL:
					_phase = "attack"
					_phase_t = 0.0
					_last_press = -1.0
					var light := behavior == "string" or (behavior == "parry_drill" and not _alt)
					_left = (3 if behavior == "string" else 1) if light else 0
					if not light:
						f.input.press(FighterInput.HEAVY)
					string_active = true
				if _phase_t > 4.0:
					_phase = "rest"
					_phase_t = 0.0
			"attack":
				if _left > 0 and _phase_t - _last_press > 0.1:
					var ready := f.state == Fighter.State.NEUTRAL or (f.state == Fighter.State.ATTACK and f.move != null and f.state_time >= f.move.cancel_t0)
					if ready:
						f.input.press(FighterInput.LIGHT)
						_left -= 1
						_last_press = _phase_t
				if _left <= 0 and _phase_t > 0.3 and f.state != Fighter.State.ATTACK:
					_phase = "rest"
					_phase_t = 0.0
					_alt = not _alt
					string_active = false
				elif _phase_t > 3.0:
					_phase = "rest"
					_phase_t = 0.0
					string_active = false
