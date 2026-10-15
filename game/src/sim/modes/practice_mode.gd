class_name PracticeMode
extends MatchMode
## PRACTICE (docs/design/MODES.md §1): no timer, no KO — health refills when depleted. The dummy
## (fighter 1) can stand, guard, parry, counter, replay a recording of the player, or be a bot of
## any tier. Telemetry for the HUD: last hit's closing speed, quality, clean %, damage, body part,
## the dummy's poise and element build-up, and the player's current move phase.

const BEHAVIORS := ["stand", "guard", "parry", "counter", "replay", "bot"]

var behavior := "stand"
var dummy_source: PracticeDummy
var last_hit := {}
var recording := false
var _rec: Array = []             ## [{t, move: Vector3, held: int, press: PackedByteArray}]
var _rec_start := 0.0


func id() -> String:
	return "practice"


func setup(match_sim) -> void:
	match_sim.rules["round_time"] = 0.0
	match_sim.rules["rounds"] = 1
	super.setup(match_sim)
	if sim.fighters.size() > 1:
		dummy_source = PracticeDummy.new(self)
		sim.set_input_source(1, dummy_source)


func set_behavior(b: String, bot_tier := "regular") -> void:
	if not BEHAVIORS.has(b):
		return
	behavior = b
	if dummy_source:
		dummy_source.reset(bot_tier)
	sim.emit_event({"type": "practice_behavior", "behavior": b})


func toggle_recording() -> void:
	recording = not recording
	if recording:
		_rec.clear()
		_rec_start = sim.time
	sim.emit_event({"type": "practice_record", "on": recording, "frames": _rec.size()})


func recording_frames() -> Array:
	return _rec


func tick_fight(_dt: float) -> void:
	if recording and sim.fighters.size() > 0:
		var p := sim.fighters[0]
		_rec.append({"t": sim.time - _rec_start, "move": p.input.move, "held": p.input.held, "press": p.input.press_count.duplicate()})
		if _rec.size() > 120 * 30:
			toggle_recording()
	for ev in sim.events_since(maxi(0, sim.event_seq - 6)):
		if ev["type"] == "hit" and int(ev.get("target", -1)) == 1 and int(ev["seq"]) > int(last_hit.get("seq", 0)):
			last_hit = ev.duplicate()


func on_depleted(f: Fighter, _attacker: Fighter, _hit: Dictionary) -> void:
	f.health = f.max_health
	sim.emit_event({"type": "practice_refill", "fighter": f.index})


func check_round_over() -> void:
	pass


func hud_status() -> String:
	var lines := ["Dummy: %s%s" % [behavior.to_upper(), "   REC ●" if recording else ""]]
	if not last_hit.is_empty():
		lines.append("Last hit: %.1f dmg  quality %d%%  %s%s%s" % [float(last_hit.get("damage", 0.0)), int(float(last_hit.get("quality", 0.0)) * 100.0),
			str(last_hit.get("part", "")), "  BLOCKED" if bool(last_hit.get("blocked", false)) else "", "  COUNTER" if bool(last_hit.get("counter", false)) else ""])
	if sim.fighters.size() > 1:
		var d := sim.fighters[1]
		var bu := []
		for el in d.statuses.buildup:
			if float(d.statuses.buildup[el]) > 1.0:
				bu.append("%s %d" % [Elements.display_name(el), int(d.statuses.buildup[el])])
		lines.append("Dummy poise %d/%d  %s" % [int(d.poise), int(d.effective_max_poise()), "  ".join(bu)])
	if sim.fighters.size() > 0:
		var p := sim.fighters[0]
		if p.move:
			var phase_name := "startup" if p.state_time < p.move.first_active() else ("ACTIVE" if p.move.window_index(p.state_time) >= 0 else "recovery")
			lines.append("%s  %.2fs / %.2fs  (%s)" % [p.move.display_name, p.state_time, p.move.duration, phase_name])
	return "\n".join(lines)


func hud_state() -> Dictionary:
	return {"rows": [], "status": hud_status(), "last_hit": last_hit}


class PracticeDummy:
	extends InputSource
	var mode
	var _t := 0.0
	var _bot: BotBrain = null
	var _replay_i := 0
	var _replay_t := 0.0
	var _countering := 0.0

	func _init(m) -> void:
		mode = m

	func reset(tier: String) -> void:
		_bot = BotBrain.new(tier, 4242) if mode.behavior == "bot" else null
		_replay_i = 0
		_replay_t = 0.0

	func label() -> String:
		return "Practice dummy (%s)" % mode.behavior

	func poll(f: Fighter, sim, dt: float) -> void:
		_t += dt
		f.input.move = Vector3.ZERO
		f.input.held = 0
		match str(mode.behavior):
			"guard":
				f.input.set_held(FighterInput.GUARD, true)
			"parry":
				var p: Fighter = sim.fighters[0]
				if p.is_winding_up():
					var eta: float = p.move.first_active() - p.state_time
					if eta < 0.1 and f.state != Fighter.State.GUARD:
						f.input.press(FighterInput.GUARD)
				f.input.set_held(FighterInput.GUARD, p.state == Fighter.State.ATTACK)
			"counter":
				f.input.set_held(FighterInput.GUARD, _countering <= 0.0)
				if f.stats_record["blocks"] > int(f.flags.get("_blocks_seen", 0)):
					f.flags["_blocks_seen"] = f.stats_record["blocks"]
					_countering = 0.5
					f.input.press(FighterInput.LIGHT)
				_countering -= dt
			"replay":
				var rec: Array = mode.recording_frames()
				if rec.is_empty() or mode.recording:
					return
				_replay_t += dt
				var last_t: float = rec[rec.size() - 1]["t"]
				if _replay_t > last_t:
					_replay_t = 0.0
					_replay_i = 0
				while _replay_i < rec.size() - 1 and float(rec[_replay_i + 1]["t"]) <= _replay_t:
					_replay_i += 1
				var fr: Dictionary = rec[_replay_i]
				# mirror the recorded movement relative to the dummy's facing toward the player
				f.input.move = -(fr["move"] as Vector3)
				f.input.held = int(fr["held"])
				var pc: PackedByteArray = fr["press"]
				for b in FighterInput.BUTTON_COUNT:
					if _replay_i > 0 and pc[b] != (rec[_replay_i - 1]["press"] as PackedByteArray)[b]:
						f.input.press(b)
			"bot":
				if _bot:
					_bot.poll(f, sim, dt)
