class_name BotBrain
extends InputSource
## Scripted NPC opponent. Plays by the same rules as a human: it only writes FighterInput,
## perceives opponents through a reaction-time delay (no omniscience), and makes deliberate,
## tunable mistakes. Difficulty profiles differ in reaction time, defence, punishing, reads,
## combo discipline, spacing, ability use and error rate (docs/BOTS.md).
##
## Perception: every tick the bot records what it can see of its target (position, body extent,
## state, the move being performed and how far into it the target is) and decides only on the
## record that is `reaction` seconds old. Beyond that it uses what a practised player knows: the
## timing of a move it has SEEN begin (its animation), its own state, blocks, parries and hits,
## the pattern of the attacks it has seen, and how its own moves connected so far this fight. It
## never reads the opponent's input or anything not yet visible.
##
## Each attack the bot sees begin gets ONE answer (block, parry tap, dodge, counter-poke, armored
## blow-through, or none), rolled once with the tier's chances; a mistake leaves it unanswered.
## Openings it has seen (a blocked, dodged or whiffed move that cannot be cancelled, a parried
## attacker) are punished with the strongest own move whose start-up fits the opening.

const PROFILES := {
	"rookie": {"reaction": 0.5, "think": 0.2, "aggression": 0.4, "block": 0.12, "parry": 0.0, "dodge": 0.04,
		"combo": 0.2, "ability": 0.2, "grab": 0.08, "mistake": 0.35, "spacing": 0.25, "juice": 0.4, "wake": 0.9, "mash_escape": 0.35,
		"punish": 0.0, "read": 0.0, "heavy": 0.2},
	"regular": {"reaction": 0.36, "think": 0.14, "aggression": 0.55, "block": 0.45, "parry": 0.05, "dodge": 0.12,
		"combo": 0.5, "ability": 0.45, "grab": 0.18, "mistake": 0.15, "spacing": 0.5, "juice": 0.75, "wake": 0.6, "mash_escape": 0.6,
		"punish": 0.25, "read": 0.5, "heavy": 0.28},
	"pro": {"reaction": 0.25, "think": 0.1, "aggression": 0.62, "block": 0.55, "parry": 0.25, "dodge": 0.22,
		"combo": 0.75, "ability": 0.65, "grab": 0.28, "mistake": 0.1, "spacing": 0.75, "juice": 0.9, "wake": 0.4, "mash_escape": 0.85,
		"punish": 0.5, "read": 0.6, "heavy": 0.28},
	"champion": {"reaction": 0.15, "think": 0.07, "aggression": 0.66, "block": 0.75, "parry": 0.4, "dodge": 0.3,
		"combo": 0.9, "ability": 0.8, "grab": 0.35, "mistake": 0.05, "spacing": 0.92, "juice": 1.0, "wake": 0.25, "mash_escape": 1.0,
		"punish": 0.75, "read": 0.9, "heavy": 0.28},
	# Hall-of-Famer (CAMPAIGN.md difficulty tiers): the quickest reads, near-flawless, reads charge-ups
	"hall_of_famer": {"reaction": 0.09, "think": 0.04, "aggression": 0.75, "block": 1.0, "parry": 0.55, "dodge": 0.36,
		"combo": 1.0, "ability": 0.85, "grab": 0.38, "mistake": 0.01, "spacing": 0.95, "juice": 1.0, "wake": 0.2, "mash_escape": 1.0,
		"punish": 1.0, "read": 1.0, "heavy": 0.28},
}
## Profile keys: reaction (s, perception delay), think (s between decisions), aggression, block /
## parry / dodge (shares of the answer to a seen attack), punish (chance to use a seen opening),
## read (spotting habits: button-mashing and its pattern, charge-ups, armored blow-throughs, which
## own moves connect from here), combo, heavy (share of Heavies in neutral offence), ability, grab,
## mistake (per decision / per seen attack), spacing, juice, wake (s of wake-up hesitation),
## mash_escape. docs/BOTS.md has the tier table and the measurements.

var difficulty := "regular"
var p := {}
var rng := RandomNumberGenerator.new()
var personality := {}            ## creature ai block: {"aggression": +0.1, "prefers": "ranged", ...}
var _t := 0.0
var _next_think := 0.0
var _history: Array = []          ## [{t, pos, state, slot, st, first, dur, bulk}]
var _move := Vector3.ZERO
var _guard := false
var _guard_from := 0.0            ## the guard hold starts here (a parry tap from neutral waits for the tap)
var _guard_until := 0.0
var _tap_at := -1.0               ## a parry tap: the guard is let go for a tick just before, then pressed
var _strafe := 1.0
var _strafe_until := 0.0
var _wake_at := -1.0
var _press_queue: Array = []      ## [{b, at}]
var _reach_cache := {}
var _last_target: Fighter = null
var objective_override := {}      ## set by modes / autobattler
var label_text := ""
var _hold_until := 0.0
var _heavy_hold_until := 0.0      ## kit hint "charge_heavy": Heavy held into the charged version
var _kit_hold_until := 0.0        ## kit hint ability "stick": the stick is committed, skip thinking
# ---- reading the opponent (all from the reaction-delayed record) ----
var _seen: Array = []             ## attacks seen begin, newest last: [{id, slot, start (bot clock), info}]
var _seen_id := 0
var _per_atk := false             ## last perceived record: attacking, its slot and move time
var _per_slot := ""
var _per_st := 0.0
var _per_t := 0.0
var _per_frozen := 0.0            ## how long the perceived move time has stood still (a held charge)
var _seen_defend_t := -99.0       ## bot clock of the last record showing the target guarding or dodging
var _answer := {}                 ## {id, kind, punished, charge} for the newest seen attack
var _busy_until := -1.0           ## a queued answer (punish, armored attack) owns the next moments
var _armor_next := 0.0
var _info_cache := {}
var _own_cache := {}
# ---- own feedback ----
var _parries_seen := -1
var _contact := {}                ## seen slot -> learned delay from its first hit frame to contact with this bot
var _contacts_pending: Array = [] ## contact times (bot clock) not yet matched to a seen attack
var _c_counts: Array = [-1, -1, -1]   ## own blocks, own parries, the target's hits at the last poll
var _blocked_at := -1.0           ## bot clock of a block just felt, until the gap after it is judged
var _last_blocked := {}           ## the attack (seen, or counted along the string) last blocked
var tally := {}                    ## decisions taken, by kind (tests and tuning read it)
var _tap_track := -1.0            ## a parry tap whose outcome is tallied (parried / blocked / hit)
var _tap_check := -1.0
var _tap_counts: Array = [0, 0, 0.0]


func _init(diff := "regular", seed_value := 0) -> void:
	difficulty = diff if PROFILES.has(diff) else "regular"
	p = PROFILES[difficulty].duplicate()
	rng.seed = seed_value if seed_value != 0 else randi()


func label() -> String:
	return label_text if label_text != "" else "Bot (%s)" % difficulty.capitalize()


func set_personality(ai: Dictionary) -> void:
	personality = ai
	for k in ["aggression", "block", "dodge", "ability", "grab"]:
		if ai.has(k):
			p[k] = clampf(float(p[k]) + float(ai[k]), 0.0, 1.0)


func _tally(k: String) -> void:
	tally[k] = int(tally.get(k, 0)) + 1


## Profile value with a default (campaign overrides may replace a profile with fewer keys).
func _pv(k: String, def := 0.0) -> float:
	return float(p.get(k, def))


func poll(f: Fighter, sim: MatchSim, dt: float) -> void:
	_t += dt
	if _kit_pre_poll(f):
		return
	var tgt := f.target
	if tgt != _last_target:
		_history.clear()
		_seen.clear()
		_last_blocked = {}
		_answer = {}
		_per_atk = false
		_gap_lost = 0
		_last_target = tgt
	if tgt:
		_history.append({"t": _t, "pos": tgt.pos(), "state": tgt.state, "slot": tgt.move_slot, "st": tgt.state_time,
			"first": tgt.move.first_active() if tgt.move else 0.0, "dur": tgt.move.duration if tgt.move else 0.0,
			"bulk": _surface_depth(f.pos(), tgt)})
		while _history.size() > 2 and _t - float(_history[1]["t"]) > float(p["reaction"]):
			_history.pop_front()
		_note_seen(tgt)
	_note_own(f)
	if _own_src != "" and (f.state != Fighter.State.ATTACK or f.move_slot != _own_slot or f.state_time < _own_st):
		var how := "hit" if (_own_hit or f.state == Fighter.State.GRABBING) else ("intr" if f.state in [Fighter.State.HITSTUN, Fighter.State.GUARD_BREAK, Fighter.State.KNOCKDOWN, Fighter.State.HELD] else "miss")
		_tally("%s_%s" % [_own_src, how])
		if _own_src.begins_with("gc_"):
			# a gap that keeps closing on it is wider in its head than on his buttons: it learns
			_gap_lost = _gap_lost + 1 if how == "intr" else (maxi(0, _gap_lost - 1) if how == "hit" else _gap_lost)
		if how != "intr" and _own_band >= 0:
			_learn_range(_own_slot.split("@")[0], _own_band, how == "hit")
		_own_src = ""
	if f.state == Fighter.State.ATTACK and (f.move_slot != _own_slot or f.state_time < _own_st):
		_own_id += 1
		_own_tgt_blocks = int(tgt.stats_record.get("blocks", 0)) if tgt else 0
		_own_src = _next_src if _t - _next_src_t < 0.3 else "other"
		_own_hit = false
		var per0 := _perceived()
		_own_band = -1
		if tgt and not per0.is_empty():
			var tp0: Vector3 = per0["pos"]
			_own_band = _band(Vector2(tp0.x - f.pos().x, tp0.z - f.pos().z).length() - _bulk)
	if f.state == Fighter.State.ATTACK and f.move_hit_any:
		_own_hit = true
	_own_slot = f.move_slot if f.state == Fighter.State.ATTACK else ""
	_own_st = f.state_time
	# pending timed presses
	for q in _press_queue.duplicate():
		if _t >= float(q["at"]):
			f.input.press(int(q["b"]))
			_press_queue.erase(q)
	if _t >= _next_think:
		_next_think = _t + float(p["think"]) * rng.randf_range(0.7, 1.3)
		_think(f, sim)
	f.input.move = _edge_safe(f, sim, _move)
	f.input.set_held(FighterInput.GUARD, _guard_held_now())
	f.input.set_held(FighterInput.GRAB, _t < _hold_until)
	f.input.set_held(FighterInput.HEAVY, _t < _heavy_hold_until)
	if f.state == Fighter.State.HELD:
		if rng.randf() < float(p["mash_escape"]) * 0.5:
			f.input.press(FighterInput.LIGHT if rng.randf() < 0.5 else FighterInput.HEAVY)


func _guard_held_now() -> bool:
	if not _guard or _t < _guard_from or _t >= _guard_until:
		return false
	return not (_tap_at > 0.0 and _t >= _tap_at - 0.012 and _t < _tap_at)


## Ring-out arenas: a ring-out costs health and time, so bots keep off open edges. Within
## EDGE_CAUTION of one, the outward part of the intended move is cancelled and an inward pull
## added (stronger closer to the edge and for better spacing). Dodges use the corrected move, so
## they never point off the roof. A bot carrying someone still walks them out to throw.
const EDGE_CAUTION := 1.7


func _edge_safe(f: Fighter, sim: MatchSim, mv: Vector3) -> Vector3:
	if sim == null or sim.arena == null or f.state == Fighter.State.GRABBING:
		return mv
	if not bool(sim.rules.get("ringouts", true)) or not sim.arena.has_open_edges():
		return mv
	var d := sim.arena.edge_distance(f.pos(), true)
	if d >= EDGE_CAUTION:
		return mv
	var inward := sim.arena.open_edge_inward(f.pos())
	if inward == Vector3.ZERO:
		return mv
	var out := mv.dot(-inward)
	if out > 0.0:
		mv += inward * out
	mv += inward * (1.0 - d / EDGE_CAUTION) * lerpf(0.5, 1.0, float(p["spacing"]))
	return mv.limit_length(1.0)


func _perceived() -> Dictionary:
	return _history[0] if not _history.is_empty() else {}


## How fast the target was coming at this bot (m/s along -`dir`, >= 0) when it last saw him: from
## the perceived position and one about 0.05 s later in what it saw (reaction-delayed, like a player).
func _closing_speed(dir: Vector3) -> float:
	if _history.size() < 2:
		return 0.0
	var a: Dictionary = _history[0]
	var b: Dictionary = _history[mini(6, _history.size() - 1)]
	var dt := float(b["t"]) - float(a["t"])
	if dt <= 0.0:
		return 0.0
	var v: Vector3 = (b["pos"] - a["pos"]) / dt
	return maxf(0.0, -Vector2(v.x, v.z).dot(Vector2(dir.x, dir.z)))


func _queue(b: int, delay: float) -> void:
	_press_queue.append({"b": b, "at": _t + delay})


## Estimated reach (metres from root) of a move: farthest animated effector target in a hit
## window plus lunge travel plus weapon radius.
func reach_of(c: CreatureDef, slot: String, abilities := false) -> float:
	var key := c.id + ":" + slot
	if _reach_cache.has(key):
		return _reach_cache[key]
	var authored: Dictionary = c.ai.get("reach", {})   # kit hint "reach" (long bodies that strike by bending)
	if authored.has(slot):
		_reach_cache[key] = float(authored[slot])
		return _reach_cache[key]
	var m: MoveDef = (c.abilities if abilities else c.moves).get(slot)
	var r := 0.0
	if m:
		for k in m.keys:
			for cname in k["chains"]:
				var v = k["chains"][cname]
				if typeof(v) == TYPE_VECTOR3:
					r = maxf(r, (v as Vector3).z)
		var lunge_d := 0.0
		for l in m.lunges:
			if l.size() >= 3:
				lunge_d += (float(l[1]) - float(l[0])) * float(l[2])
		var wr := 0.12
		for w in m.windows:
			for wn in w["weapons"]:
				var wd: BodyDef.Weapon = c.body.weapons.get(wn)
				if wd:
					wr = maxf(wr, wd.radius)
					var wseg: BodyDef.Seg = c.body.segments[wd.seg]
					var rest_z := (wd.local + wseg.pivot).z
					r = maxf(r, rest_z)
		r = r + lunge_d * 0.7 + wr
		for e in m.effects:
			match str(e.get("type", "")):
				"projectile":
					r = maxf(r, float(e.get("speed", 10.0)) * float(e.get("life", 1.0)) * 0.7)
				"area":
					r = maxf(r, float(e.get("radius", 2.0)) * 0.9)
				"leap":
					r = maxf(r, float(e.get("distance", 4.0)))
	_reach_cache[key] = maxf(r, 0.4)
	return _reach_cache[key]


func _think(f: Fighter, sim: MatchSim) -> void:
	_press_queue = _press_queue.filter(func(q): return float(q["at"]) - _t < 0.6)
	var c := f.creature
	match f.state:
		Fighter.State.DOWN:
			if _wake_at < 0.0:
				_wake_at = _t + rng.randf_range(0.0, float(p["wake"]) * 2.0)
			if _t >= _wake_at:
				f.input.press(FighterInput.LIGHT)
				_wake_at = -1.0
			return
		Fighter.State.KNOCKDOWN, Fighter.State.KO, Fighter.State.DOWNED, Fighter.State.INACTIVE:
			_move = Vector3.ZERO
			_guard = false
			return
		Fighter.State.GRABBING:
			# throw toward the nearest wall for a slam, else straight ahead
			var dir := f.forward()
			if sim.arena and rng.randf() < float(p["spacing"]):
				var out := Vector3(f.pos().x, 0, f.pos().z)
				if out.length() > 0.5:
					dir = out.normalized()
			_move = dir
			if f.state_time > rng.randf_range(0.15, 0.6):
				f.input.press(FighterInput.HEAVY if rng.randf() < 0.7 else FighterInput.LIGHT)
			return
	var obj: Dictionary = objective_override if not objective_override.is_empty() else (sim.mode.bot_objective(f) if sim.mode else {})
	if obj.has("target"):
		var ti := int(obj["target"])
		if ti >= 0 and ti < sim.fighters.size() and not sim.fighters[ti].is_out():
			f.target = sim.fighters[ti]
	if _objective_actions(f, obj):
		return
	var tgt := f.target
	if tgt == null or tgt.is_out():
		_guard = false
		if obj.has("pos"):
			_move = _toward(f.pos(), obj["pos"])
		else:
			_move = Vector3.ZERO
		return
	var per := _perceived()
	var tpos: Vector3 = per.get("pos", tgt.pos())
	var to := tpos - f.pos()
	to.y = 0.0
	var dist := to.length()
	var dir := to / maxf(dist, 0.01)
	if _t < _kit_hold_until:
		return   # kit hint "stick": an ability committed the stick (e.g. a dive away)
	# reach is judged to the body, not the root: a long body (Dozer's head, a boss) is in range
	# sooner and sticks out into the opponent's reach sooner. Kit distances were authored root to
	# root against ordinary bodies, so they only grow by what this body adds beyond one.
	_bulk = float(per.get("bulk", 0.0))
	_my_bulk = _surface_depth(tpos, f)
	var extra := maxf(_kit_target_bulk(f, tgt), _bulk - REF_BULK)
	var my_reach := float(personality.get("attack_range", reach_of(c, "l1"))) + maxf(extra, 0.0)
	var their_reach := reach_of(tgt.creature, "heavy") + _my_bulk
	var mistake := rng.randf() < float(p["mistake"])
	# ---- defence and punishes: answer each attack seen begin (perceived, reaction-delayed) ----
	var per_state := int(per.get("state", Fighter.State.NEUTRAL))
	var attacking := (per_state == Fighter.State.ATTACK or per_state == Fighter.State.ABILITY) and not _kit_opening(per, tgt)
	if _t < _busy_until:
		return   # a queued punish / armored attack is on its way
	# answers are also prepared while stunned or recovering (a guard held through hitstun is up
	# the moment it ends, like a player holding block through a combo)
	var can_answer := f.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD, Fighter.State.HITSTUN, Fighter.State.DODGE, Fighter.State.GETUP] \
			or (f.state in [Fighter.State.ATTACK, Fighter.State.ABILITY] and f.move != null and f.state_time > _kit_last_threat(f.move))
	if can_answer and _react(f, tgt, per, attacking, dist, dir):
		return
	if _t >= _guard_until:
		_guard = false
	# ---- objective modes may pull the bot elsewhere ----
	if obj.has("pos") and dist > float(obj.get("engage", 3.0)):
		_move = _toward(f.pos(), obj["pos"])
		return
	if _kit_think(f, sim, tgt, dist, dir, attacking and not mistake, my_reach, their_reach):
		return
	# ---- JUICE ----
	if f.hype >= 100.0 and rng.randf() < float(p["juice"]) * 0.5 and _kit_juice_ok(f, tgt, dist, dir, per):
		f.input.press(FighterInput.JUICE)
		return
	# ---- abilities ----
	if _kit_ability(f, tgt, dist, dir, per, false):   # kit hints from the creature "ai" block
		return
	if _kit_heavy_vs_windup(f, dist, per):   # kit hint: Heavy into a perceived long windup
		return
	for slot in ["ability1", "ability2"]:
		if _kit_hint_for(c, slot).is_empty() and c.abilities.has(slot) and float(f.cooldown_left.get(slot, 0.0)) <= 0.0 and rng.randf() < float(p["ability"]) * 0.35:
			var ar := reach_of(c, slot, true)
			if dist <= ar and dist >= minf(1.2, ar * 0.3):
				f.input.press(FighterInput.AB1 if slot == "ability1" else FighterInput.AB2)
				return
	if dist > my_reach + 0.4 and _kit_avoid_zone(f, sim, dir):
		return   # kit hint "avoid_zones": step out of an enemy puddle / patch before closing in
	# ---- offence ----
	# a Light string in progress: decided once per move, after seeing whether it landed
	if f.state == Fighter.State.ATTACK and _string_step(f, tgt, dist, dir, per):
		_move = dir * 0.4
		return
	var stamina_ok := f.stamina > 18.0 or rng.randf() < 0.2
	# a read button-masher is not traded with in neutral: his stream wins trades, so a reader waits
	# for the openings it gives (parries, his Finisher's recovery, an armored blow-through)
	if _mashing() and not f._armor_covers("light") and rng.randf() < _pv("read"):
		stamina_ok = false
	var aggression := float(p["aggression"]) * (1.25 if f.health_frac() > tgt.health_frac() else 0.9)
	# attacks start at a rate per second, so a quicker thinker is not a more aggressive one
	var p_attack := 1.0 - exp(-aggression * ATTACK_RATE * float(p["think"]) * (2.5 if f._armor_covers("light") else 1.0))
	if dist <= my_reach + 0.1 and stamina_ok and f.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD] and rng.randf() < p_attack:
		var t_guarding := per_state == Fighter.State.GUARD
		var first_light := str(c.light_string[0]) if not c.light_string.is_empty() else "l1"
		# better players pick a move that connects from here (worse ones jab regardless: visible whiffs)
		var careless := rng.randf() >= _pv("read")
		if (t_guarding or _kit_grab_target(tgt)) and rng.randf() < float(p["grab"]) * 2.0:
			f.input.press(FighterInput.GRAB)
			_tally("off_grab_guard")
		elif rng.randf() < _pv("heavy", 0.28) and _lands(f, "heavy", dist, dir):
			f.input.press(FighterInput.HEAVY)
			_tally("off_heavy")
			_kit_maybe_charge()
		elif rng.randf() < float(p["grab"]) * 0.4 and _lands(f, "grab", dist, dir):
			f.input.press(FighterInput.GRAB)
			_tally("off_grab")
		elif careless or _lands(f, first_light, dist, dir) or _second_light_lands(f, dist, dir):
			f.input.press(FighterInput.LIGHT)
			_tally("off_light")
		elif _lands(f, "heavy", dist, dir):
			f.input.press(FighterInput.HEAVY)
			_tally("off_heavy2")
		elif _lands(f, "grab", dist, dir):
			f.input.press(FighterInput.GRAB)
			_tally("off_grab2")
		elif _too_close(f, dist):
			# too close for anything it has: make room (a back-step, or a dodge out when pressed)
			_tally("off_backoff")
			_move = -dir
			if rng.randf() < float(p["spacing"]) * 0.5 and f.stamina > 30.0:
				f.input.press(FighterInput.DODGE)
			return
		else:
			# nothing it has connects from this far: step in instead of whiffing
			_tally("off_stepin")
			_move = dir
			return
		_guard_until = minf(_guard_until, _t)
		_next_src = "of"
		_next_src_t = _t
		_move = dir * 0.4
		return
	# ---- guard up inside the opponent's reach: a strike from neutral comes out faster than any
	# reaction, so a careful player keeps the guard up while he can be hit and is not attacking.
	# A read button-masher is blocked even mid-stream (his next jab is already on its way, and the
	# reader does not trade with him); his walking in is counted over the reaction it sees him by ----
	var read_mash := _mashing() and rng.randf() < _pv("read")
	if (not attacking or read_mash) and f.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD] and _t >= _guard_until \
			and dist - _closing_speed(dir) * float(p["reaction"]) < _threat_reach(tgt) + 0.2 and per_state != Fighter.State.GUARD \
			and (f.stamina > 30.0 or rng.randf() >= _pv("read")):
		if read_mash or rng.randf() < 1.0 - exp(-float(p["block"]) * GUARD_RATE * float(p["think"])):
			_hold_guard(f, _t + rng.randf_range(0.25, 0.55))
			_tally("guard_up_mash" if read_mash else "guard_up")
	if _kit_movement(f, dist, dir):   # kit hints: dash_in / dash_out
		return
	# ---- footwork ----
	var want := my_reach * lerpf(0.7, 0.95, float(p["spacing"]))
	var kit_range := _kit_range()
	if not kit_range.is_empty() and _kit_range_ready(f):
		want = lerpf(float(kit_range[1]), float(kit_range[0]), float(p["spacing"])) + maxf(extra, 0.0)
	# a spaced player stands where his own strikes can still travel into the target (a long head
	# or a held-out claw needs room), not pressed up against it
	if float(p["spacing"]) >= 0.5:
		want = maxf(want, _strike_floor(c) + _bulk + 0.15)
	if f.stamina < 15.0 and rng.randf() < float(p["spacing"]):
		want = their_reach + 0.8
	if _t >= _strafe_until:
		_strafe = -1.0 if rng.randf() < 0.5 else 1.0
		_strafe_until = _t + rng.randf_range(0.5, 1.6)
	var side2 := dir.cross(Vector3.UP) * _strafe
	if dist > want + 0.25:
		_move = (dir + side2 * 0.25).normalized()
		if dist > 4.0 and rng.randf() < float(p["aggression"]) * 0.1:
			f.input.press(FighterInput.DODGE)
	elif dist < want - 0.35:
		_move = (-dir + side2 * 0.4).normalized() * 0.8
	else:
		_move = side2 * lerpf(0.3, 0.7, float(p["spacing"]))
	if mistake:
		_move = _move.rotated(Vector3.UP, rng.randf_range(-1.0, 1.0))
	if personality.has("taunt_when"):
		if not _taunt_risky():
			_kit_taunt(f, tgt, dist, dir, per)
	elif rng.randf() < 0.01 and f.hype < 100.0 and dist > 3.0 and not _taunt_risky():
		f.input.press(FighterInput.TAUNT)


# =====================================================================================
# Own offence: strings and range
# =====================================================================================

## Attacks started per second at aggression 1.0 while in range (scaled by the profile).
const ATTACK_RATE := 3.0
## Body surface depth (m, root to front) of an ordinary roster body: kit distances assume it.
const REF_BULK := 0.45
## Guards raised per second at block 1.0 while inside the opponent's reach and not attacking.
const GUARD_RATE := 2.0
## Share of a move's animated reach (reach_of) at which it still connects with closing speed.
const EFFECTIVE_REACH := 0.78


## How far the target's quickest strike reaches toward this bot (its first Light, to my body).
func _threat_reach(tgt: Fighter) -> float:
	var c := tgt.creature
	var first_light := str(c.light_string[0]) if not c.light_string.is_empty() else "l1"
	return reach_of(c, first_light) + _my_bulk

var _bulk := 0.0                     ## target's nearest body part is this much closer than its root
var _my_bulk := 0.0                  ## and mine toward it
var _own_band := -1                  ## distance band (to the target's body) the own attack began at
var _conn := {}                      ## own connects by "slot|band": [hits, tries] (learned this fight)
var _own_src := ""                   ## what started the current own attack (tuning tally)
var _own_hit := false
var _next_src := ""
var _next_src_t := -1.0
var _own_id := 0                     ## counts own attacks begun (string decisions are per attack)
var _own_slot := ""
var _own_st := 0.0
var _own_tgt_blocks := 0             ## the target's blocks when the own attack began
var _string_done_for := -1
var _gap_lost := 0                   ## gap counters (_after_block) interrupted minus landed, this target


## Goes on with a Light string (next Light, or Heavy for the Finisher) once per own move, when
## its hit window has passed: better players continue what lands and stop a blocked or whiffed
## string; worse ones press on regardless. Returns true when it pressed.
func _string_step(f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary) -> bool:
	if f.move == null:
		return false
	var slot := f.move_slot.split("@")[0]
	var step := f.creature.light_string.find(slot)
	if step < 0:
		return false
	if _own_id == _string_done_for:
		return false
	var m := f.move
	var decide_at := minf(maxf(m.cancel_t0 - 0.1, _kit_last_threat(m) + 0.02), m.duration - 0.05)
	if f.state_time < decide_at and not f.move_hit_any:
		return false
	_string_done_for = _own_id
	var blocked := tgt != null and int(tgt.stats_record.get("blocks", 0)) > _own_tgt_blocks
	var landed := f.move_hit_any and not blocked
	# a whiffed opener is still worth following when the next hit of the string connects from
	# here (Dozer's Hoof Stomp after a Light that sails past at point blank)
	var next_lands := step + 1 < f.creature.light_string.size() and not blocked \
			and _lands(f, str(f.creature.light_string[step + 1]), dist, dir) and rng.randf() < _pv("read")
	var go := float(p["combo"])
	if not landed and not next_lands:
		go *= (1.0 - _pv("read")) * (0.6 if blocked else 0.5)
	if rng.randf() >= go:
		return false
	if _kit_commit(f, tgt, dist, dir, per):
		_tally("str_commit")
		return true
	var last := step >= f.creature.light_string.size() - 1
	if (last or (step >= 1 and rng.randf() < 0.4)) and f.creature.moves.has("finisher"):
		f.input.press(FighterInput.HEAVY)
		_tally("str_finisher")
		return true
	if last:
		return false
	f.input.press(FighterInput.LIGHT)
	_tally("str_light")
	_next_src = "st"
	_next_src_t = _t
	return true


## Closest distance (to the target's body) at which `slot` still connects: area moves and grabs
## work up close; a strike needs its weapon to travel INTO the target, so a target nearer than
## where the weapon rests (a horn on a long head, a claw held out) is too close for it.
func _min_range(c: CreatureDef, slot: String) -> float:
	var key := "min:" + c.id + ":" + slot
	if _reach_cache.has(key):
		return _reach_cache[key]
	var m: MoveDef = c.moves.get(slot)
	var r := 0.0
	if m != null and m.kind != "grab":
		var area := false
		for e in m.effects:
			if typeof(e) == TYPE_DICTIONARY and str(e.get("type", "")) == "area":
				area = true
		if not area:
			for w in m.windows:
				for wn in w["weapons"]:
					var wd: BodyDef.Weapon = c.body.weapons.get(wn)
					if wd:
						var wseg: BodyDef.Seg = c.body.segments[wd.seg]
						r = maxf(r, (wd.local + wseg.pivot).z - 0.25)
	_reach_cache[key] = maxf(r, 0.0)
	return _reach_cache[key]


## True when `slot` can connect from here: likely to connect at this distance and roughly facing
## the target (attacks snap toward a target within 70 degrees of the facing).
func _lands(f: Fighter, slot: String, dist: float, dir: Vector3) -> bool:
	if not f.creature.moves.has(slot):
		return false
	if _connect_chance(f.creature, slot, dist - _bulk) < 0.35:
		return false
	return f.forward().dot(dir) > cos(deg_to_rad(70.0))


## Distance band (0.25 m) of a distance to the target's body.
static func _band(sd: float) -> int:
	return clampi(int(floor(maxf(sd, 0.0) / 0.25)), 0, 15)


## Chance that own `slot` connects at body distance `sd`: what the bot has seen its own attacks
## do this fight (uncancelled, not interrupted), over a prior from the move's geometry - a player
## learns his ranges against this opponent as he goes.
func _connect_chance(c: CreatureDef, slot: String, sd: float) -> float:
	# a weapon at full stretch has no closing speed left: strikes connect well inside the farthest
	# point their animation reaches
	var r := reach_of(c, slot) * EFFECTIVE_REACH
	var lo := _min_range(c, slot)
	var prior := 0.1
	if sd >= lo and sd <= r:
		prior = 0.6
	elif sd >= lo - 0.1 and sd <= r + 0.2:
		prior = 0.35
	var obs: Array = _conn.get("%s|%d" % [slot, _band(sd)], [0, 0])
	return (float(obs[0]) + prior * 2.0) / (float(obs[1]) + 2.0)


## Records one own attack at `band`; it also tells about the bands next to it (a whiff at 1.0 m
## says the same move likely whiffs at 0.75 and 1.25 m), so ranges are learned in a few tries.
func _learn_range(slot: String, band: int, hit: bool) -> void:
	for b in [band - 1, band, band + 1]:
		if b < 0 or b > 15:
			continue
		var key := "%s|%d" % [slot, b]
		var obs: Array = _conn.get(key, [0, 0])
		_conn[key] = [int(obs[0]) + (1 if hit else 0), int(obs[1]) + 1]


# =====================================================================================
# Reading and answering attacks
# =====================================================================================

## Registers a target attack the moment it becomes visible in the reaction-delayed record.
func _note_seen(tgt: Fighter) -> void:
	var per := _perceived()
	var ps := int(per.get("state", Fighter.State.NEUTRAL))
	var atk := ps == Fighter.State.ATTACK or ps == Fighter.State.ABILITY
	if ps == Fighter.State.GUARD or ps == Fighter.State.DODGE:
		_seen_defend_t = float(per.get("t", _t))
	var slot := str(per.get("slot", ""))
	var pst := float(per.get("st", 0.0))
	if atk and slot != "" and (not _per_atk or slot != _per_slot or pst < _per_st - 0.001):
		_seen_id += 1
		_seen.append({"id": _seen_id, "slot": slot, "start": float(per["t"]) - pst, "info": _move_info(tgt.creature, slot)})
		if _seen.size() > 10:
			_seen.pop_front()
		# the reaction time already includes deciding: an attack seen begin is answered now, not
		# at the next scheduled think
		_next_think = minf(_next_think, _t)
		_match_contacts()
	if atk and _per_atk and slot == _per_slot and absf(pst - _per_st) < 0.0005:
		_per_frozen += float(per.get("t", 0.0)) - _per_t
	else:
		_per_frozen = 0.0
	_per_atk = atk
	_per_slot = slot
	_per_st = pst
	_per_t = float(per.get("t", 0.0))


## Contacts the bot feels (a hit blocked, parried or taken) teach it how long after an attack's
## first hit frame that attack actually reaches it (a lunge connects late in its window): taps on
## a masher's pattern aim at that. A contact belongs to the seen attack whose hit frames hold it,
## matched now or as soon as that attack has been seen (the next hit of a string often lands
## before a slow reaction has seen it begin).
func _note_contact(f: Fighter, blocks: int) -> void:
	var tgt := f.target
	var now := [blocks, int(f.stats_record.get("parries", 0)), int(tgt.stats_record.get("hits", 0)) if tgt else 0]
	var touched := int(_c_counts[0]) >= 0 and (int(now[0]) > int(_c_counts[0]) or int(now[1]) > int(_c_counts[1]) or int(now[2]) > int(_c_counts[2]))
	if int(_c_counts[0]) >= 0 and int(now[0]) > int(_c_counts[0]):
		_blocked_at = _t      # felt at once: the gap after it is judged now (_gap_counter)
		_next_think = minf(_next_think, _t)
	_c_counts = now
	if touched:
		_contacts_pending.append(_t)
	_match_contacts()


func _match_contacts() -> void:
	var keep: Array = []
	for c in _contacts_pending:
		var ct := float(c)
		var done := false
		for i in range(_seen.size() - 1, -1, -1):
			var mv: Dictionary = _seen[i]
			var after_first := ct - float(mv["start"]) - float(mv["info"]["first"])
			if after_first > _hit_span(mv["info"]):
				break   # after the newest seen attack's hit frames: an attack not seen yet
			if after_first >= -0.03:
				var k := str(mv["slot"])
				_contact[k] = lerpf(float(_contact.get(k, after_first)), clampf(after_first, 0.0, 0.3), 0.4)
				done = true
				break
		if not done and _t - ct < 1.0:
			keep.append(ct)
	_contacts_pending = keep


## How long after its first hit frame a contact belongs to a seen attack (see _move_info).
static func _hit_span(info: Dictionary) -> float:
	return float(info.get("span", float(info["last"]) - float(info["first"]) + 0.06))


## Expected delay from a seen attack's first hit frame to its contact with this bot (learned).
func _contact_after_first(slot: String) -> float:
	return float(_contact.get(slot, 0.03))


## Own parries (felt, not seen): a parry stuns the attacker and is punished. Parry taps are
## tallied by outcome (parried / blocked / hit / nothing came).
func _note_own(f: Fighter) -> void:
	var blocks := int(f.stats_record.get("blocks", 0))
	_note_contact(f, blocks)
	if _tap_track > 0.0 and _t >= _tap_track:
		_tap_track = -1.0
		_tap_counts = [blocks, int(f.stats_record.get("parries", 0)), float(f.stats_record.get("damage_taken", 0.0))]
		_tap_check = _t + 0.16
	if _tap_check > 0.0 and _t >= _tap_check:
		_tap_check = -1.0
		if int(f.stats_record.get("parries", 0)) > int(_tap_counts[1]):
			_tally("tap_parried")
		elif float(f.stats_record.get("damage_taken", 0.0)) > float(_tap_counts[2]) + 0.01 and blocks == int(_tap_counts[0]):
			_tally("tap_hit")
		elif blocks > int(_tap_counts[0]):
			_tally("tap_blocked")
		else:
			_tally("tap_nothing")
	var parries := int(f.stats_record.get("parries", 0))
	if _parries_seen < 0:
		_parries_seen = parries
	elif parries > _parries_seen:
		_parries_seen = parries
		_punish_parry(f)


## Timing facts of a move as a player learns them from its animation (cached per creature/slot).
func _move_info(c: CreatureDef, slot: String) -> Dictionary:
	var key := c.id + ":" + slot
	if _info_cache.has(key):
		return _info_cache[key]
	var base := slot.split("@")[0]
	var is_ab := c.abilities.has(slot) or (not c.moves.has(slot) and c.abilities.has(base))
	var m: MoveDef = (c.abilities if is_ab else c.moves).get(slot, (c.abilities if is_ab else c.moves).get(base))
	var info := {"first": 0.3, "last": 0.45, "dur": 0.7, "cancel": 9.0, "cls": Combat.move_class(base), "grab": false,
		"unblockable": false, "armored": false, "threat": true, "reach": reach_of(c, slot if (c.moves.has(slot) or c.abilities.has(slot)) else base, is_ab)}
	if m:
		info["first"] = _first_threat(m)
		info["last"] = maxf(_kit_last_threat(m), float(info["first"]))
		info["dur"] = m.duration
		info["cancel"] = m.cancel_t0
		if m.move_class != "":
			info["cls"] = m.move_class
		info["grab"] = m.kind == "grab"
		info["unblockable"] = m.unblockable
		info["armored"] = _armor_through(m)
		var hits := not m.windows.is_empty()
		for e in m.effects:
			if typeof(e) == TYPE_DICTIONARY and str(e.get("type", "")) in ["area", "projectile", "charge", "leap", "delayed", "push"]:
				hits = true
		info["threat"] = hits or m.kind == "grab"
	_info_cache[key] = info
	# a contact belongs to this move from its first hit frame through its hit frames (and a little
	# travel), or until the attacker's next move could strike at the earliest
	var nxt := _next_threat_after(c, {"start": 0.0, "slot": slot, "info": info}, 0.0)
	info["span"] = maxf(float(info["last"]) - float(info["first"]) + 0.06, nxt - float(info["first"]) - 0.01)
	return info


## Time of a move's first threat: its first hit window, or its first timed hit effect (a stomp's
## area, a thrown projectile) when that comes sooner or the move has no hit window.
static func _first_threat(m: MoveDef) -> float:
	var first := m.first_active() if not m.windows.is_empty() else m.duration
	for e in m.effects:
		if typeof(e) == TYPE_DICTIONARY and str(e.get("type", "")) in ["area", "projectile", "charge", "leap", "push"]:
			first = minf(first, float(e.get("t", 0.0)))
	return first


## True when the move's armor covers Lights from its first frames through its first hit window
## (it blows through a stream of Lights).
static func _armor_through(m: MoveDef) -> bool:
	if not m.armor_level in ["all", "lights", "all_but_heavy"]:
		return false
	for r in m.armor:
		if r.size() >= 2 and float(r[0]) <= 0.06 and float(r[1]) >= m.first_active() - 0.01:
			return true
	return false


## The bot's own answers: [{btn, slot, startup, reach, value, armored}], read from its kit.
func _own_options(f: Fighter) -> Array:
	var c := f.creature
	if _own_cache.has(c.id):
		return _own_cache[c.id]
	var out: Array = []
	var first_light := str(c.light_string[0]) if not c.light_string.is_empty() else "l1"
	for pair in [[FighterInput.LIGHT, first_light], [FighterInput.HEAVY, "heavy"], [FighterInput.GRAB, "grab"]]:
		var slot := str(pair[1])
		var m: MoveDef = c.moves.get(slot)
		if m == null or (m.windows.is_empty() and m.effects.is_empty()):
			continue
		var dmg := m.damage
		var stun := m.stun
		if m.kind == "grab":
			var td: Dictionary = c.throws.get("throw_fwd", {})
			dmg = float(td.get("damage", Tuning.v("throw_damage")))
			stun = 0.8   # the throw knocks down
		for e in m.effects:
			if typeof(e) == TYPE_DICTIONARY and str(e.get("type", "")) == "area":
				dmg += float(e.get("damage", 0.0))
		out.append({"btn": int(pair[0]), "slot": slot, "startup": _first_threat(m), "reach": reach_of(c, slot),
			"value": dmg * (1.0 + stun), "armored": _armor_through(m)})
	_own_cache[c.id] = out
	return out


## Strongest own move that lands within `window` seconds from now at `dist`, or {}.
func _pick_punish(f: Fighter, window: float, dist: float, dir: Vector3) -> Dictionary:
	var best := {}
	for o in _own_options(f):
		if float(o["startup"]) + 0.03 > window or not _lands(f, str(o["slot"]), dist, dir):
			continue
		if int(o["btn"]) == FighterInput.GRAB and bool(personality.get("no_punish_grab", false)):
			continue
		if best.is_empty() or float(o["value"]) > float(best["value"]):
			best = o
	return best


## Presses `o` at time `at` (letting go of the guard just before) and keeps the bot from other
## decisions until it is out.
func _commit(o: Dictionary, at: float, why := "pn") -> void:
	var delay := maxf(0.0, at - _t)
	_tally("commit_" + str(o["slot"]))
	_next_src = why + "_" + str(o["slot"])
	_next_src_t = _t + delay
	_queue(int(o["btn"]), delay)
	if int(o["btn"]) == FighterInput.HEAVY:
		_heavy_hold_until = 0.0
	_guard_until = minf(_guard_until, _t + delay)
	_tap_at = -1.0
	_busy_until = _t + delay + 0.05
	_move = Vector3.ZERO


## Starts holding the guard now (or keeps holding it) until `until`.
func _hold_guard(f: Fighter, until: float) -> void:
	if not (_guard and _t >= _guard_from and _t < _guard_until):
		_guard_from = _t
		if not f.input.is_held(FighterInput.GUARD) and _tap_at < _t:
			f.input.press(FighterInput.GUARD)
	_guard = true
	_guard_until = maxf(_guard_until, minf(until, _t + float(personality.get("guard_max", 9.0))))


## How long before the expected hit a parry tap is pressed: a fresh guard takes ~0.04 s to come up
## (guard_blend_time) and the parry window lasts 0.12 s, so aim for the middle of what works.
const PARRY_LEAD := 0.08


## A parry is a fresh Guard press shortly before the hit lands: a held guard is let go for a tick
## first, a bot in neutral waits for the tap; the guard is then held for `hold`.
func _parry_tap(at: float, hold := 0.3) -> void:
	at = maxf(at, _t + 0.009)
	if not (_guard and _t >= _guard_from and _t < _guard_until):
		_guard_from = at
	_guard = true
	_tap_at = at
	_tap_track = at
	_guard_until = maxf(_guard_until, at + hold)
	_queue(FighterInput.GUARD, at - _t)


## Human timing error of a planned press (s): wider for slower players.
func _jitter() -> float:
	return rng.randfn(0.0, float(p["reaction"]) * 0.15)


## A fighter that guards or dodges at all does so within this many seconds; a masher never does.
const MASHER_NO_DEFENCE := 8.0


## True while the target throws attacks non-stop and never defends (pressure, and no guard or
## dodge seen for MASHER_NO_DEFENCE s): a button-masher. A quick fighter's strings alone are not
## mashing - a player who also defends is reading the fight, and is traded with as usual.
func _mashing() -> bool:
	return _t - _seen_defend_t >= MASHER_NO_DEFENCE and _pressured()


## True while the target throws attacks non-stop (>= 5 begun in the last 2 s of what it saw,
## mostly Lights): pressure, answered with a fuller guard, pattern taps and armored blow-throughs.
func _pressured() -> bool:
	var n := 0
	var lights := 0
	var since := _t - float(p["reaction"]) - 2.0
	for s in _seen:
		if float(s["start"]) >= since:
			n += 1
			if str(s["info"]["cls"]) == "light":
				lights += 1
	return n >= 5 and lights >= 3


## A reader does not taunt an opponent who keeps attacking (>= 3 attacks seen begin in the last
## 3 s) or never defends (a button-masher comes straight in): a taunt is a long free opening.
func _taunt_risky() -> bool:
	var n := 0
	for s in _seen:
		if float(s["start"]) >= _t - float(p["reaction"]) - 3.0:
			n += 1
	var masher := _seen.size() >= 5 and _t - _seen_defend_t >= MASHER_NO_DEFENCE
	return (n >= 3 or masher) and rng.randf() < _pv("read")


## Answers the newest attack seen begin (once per attack) and keeps that answer up. Returns
## true when it decided this think step.
func _react(f: Fighter, tgt: Fighter, per: Dictionary, attacking: bool, dist: float, dir: Vector3) -> bool:
	if _seen.is_empty():
		return false
	if _blocked_at >= 0.0 and _after_block(f, tgt, dist, dir):
		return true
	var mv: Dictionary = _seen[_seen.size() - 1]
	var info: Dictionary = mv["info"]
	var start := float(mv["start"])
	var eta := start + float(info["first"]) - _t        # until its first hit frame
	var over := start + float(info["last"]) - _t        # until its last threat has passed
	var free := start + float(info["dur"]) - _t         # until the attacker can act again
	# an attacker walking in keeps closing: what it sees is a reaction old, and he goes on walking
	# through his wind-up, so count what he covers by his first hit frame (extrapolated, as a player does)
	var closing := _closing_speed(dir) * (float(p["reaction"]) + maxf(eta, 0.0))
	var in_reach := dist - closing < float(info["reach"]) + 0.55 + _my_bulk
	var committal := float(info["cancel"]) >= float(info["dur"]) - 0.05 or str(info["cls"]) in ["heavy", "ability", "juice"]
	# a cancelable move (a Light in a string) threatens a follow-up until it ends: a guard raised
	# on seeing it covers the next hits even when this one is already past
	var guard_end := over if committal else maxf(over, free)
	var threat := attacking and bool(info["threat"]) and in_reach and guard_end > -0.03
	if int(_answer.get("id", -1)) != int(mv["id"]):
		_answer = {"id": int(mv["id"]), "kind": "none", "punished": false}
		# a predictable stream (a read masher) is misread less often by those who read it
		var err := float(p["mistake"]) * (1.0 - _pv("read") * 0.5 if _mashing() else 1.0)
		if not threat:
			_answer["kind"] = "miss" if attacking and (not in_reach or not bool(info["threat"])) else "none"
		elif rng.randf() < err:
			_answer["kind"] = "mistake"
		else:
			_answer["kind"] = _choose_answer(f, tgt, per, info, eta, guard_end, dist, dir)
	# reads a charge-up: a Heavy held in its wind-up (the move time it sees stands still). Its
	# release cannot be timed, but a grab beats the charge's armor; otherwise back out of reach
	if attacking and in_reach and _per_frozen >= 0.06 and str(mv["slot"]).begins_with("heavy") and not bool(_answer.get("charge", false)):
		_answer["charge"] = true
		if rng.randf() < _pv("read"):
			_tally("charge_read")
			_tap_at = -1.0
			if _lands(f, "grab", dist, dir):
				_answer["kind"] = "counter"
				_commit({"btn": FighterInput.GRAB, "slot": "grab"}, _t, "ch")
				return true
			_answer["kind"] = "dodge"
			_guard_until = _t
			_move = -dir
			return true
	var kind := str(_answer["kind"])
	if not bool(_answer.get("counted", false)):
		_answer["counted"] = true
		_tally("ans_" + kind)
	# ---- punish what was blocked, dodged or whiffed (once per attack) ----
	if committal and not bool(_answer["punished"]) and kind in ["block", "parry", "dodge", "miss"] and free > 0.0:
		_answer["punished"] = true
		if rng.randf() < _pv("punish"):
			_tally("punish_try_" + kind)
			var at := maxf(_t, start + float(info["last"]) + 0.03)
			if kind == "dodge":
				at = maxf(at, _t + f.eff("dodge_time") + Tuning.v("dodge_recovery"))
			var o := _pick_punish(f, start + float(info["dur"]) - at, dist, dir)
			if not o.is_empty():
				_commit(o, at, "pn")
				return true
	if not threat:
		return false
	match kind:
		"block", "parry":
			# under a read stream of attacks the guard bridges the short gaps between them: a guard
			# raised afresh for every hit is still coming up when the next one lands
			var bridge := PRESSURE_BRIDGE_S if _pressured() and rng.randf() < _pv("read") else 0.0
			_hold_guard(f, _t + maxf(guard_end, 0.0) + 0.1 + bridge)
			if kind == "block":
				_move = -dir * 0.2
			return true
		"dodge", "armor", "counter":
			return true
	return false


## A masher's next press waits a little for his button (he presses on a beat, not on the frame).
const STRING_PRESS_LAG := 0.015
const GAP_LEARN_S := 0.04
const GAP_GIVE_UP := 3
const PRESSURE_BRIDGE_S := 0.25


## After blocking a Light of a string, the bot knows from that move's animation when the attacker can
## strike again: his cancel point (reached once the strike has landed) plus the start-up of his
## quickest follow-up (the next hit of his string, which loops, or his Finisher), or his move's end
## plus a fresh move's start-up. The blocked move is the attack it saw begin, or - when the hit came
## before a slow reaction saw it - the next Light of the string it counts along (a guess: a Finisher
## instead fools it). With a gap wider than its own quickest fitting move the bot hits back (read);
## otherwise, reading the string going on, it taps a parry for the string's next hit (parry share),
## guard held until then. Returns true when it acted.
func _after_block(f: Fighter, tgt: Fighter, dist: float, dir: Vector3) -> bool:
	var bt := _blocked_at
	_blocked_at = -1.0
	var c := tgt.creature
	var mv := _blocked_move(c, bt)
	if mv.is_empty():
		return false
	_last_blocked = mv
	var info: Dictionary = mv["info"]
	var start := float(mv["start"])
	var step := c.light_string.find(str(mv["slot"]).split("@")[0])
	if step < 0 or rng.randf() >= _pv("read"):
		return false   # not a Light of his string (Heavies and abilities are punished as openings)
	# every gap counter his next hit interrupted asks for GAP_LEARN_S more gap; after GAP_GIVE_UP more
	# lost than landed it stops hitting back in his string and taps parries instead (learned per target)
	if _pv("punish") > 0.0 and _gap_lost < GAP_GIVE_UP:
		var o := _pick_punish(f, _next_threat_after(c, mv, bt) - _t - 0.02 - GAP_LEARN_S * _gap_lost, dist, dir)
		if not o.is_empty() and int(o["btn"]) != FighterInput.GRAB:
			_tally("gap_counter")
			_commit(o, _t, "gc")
			return true
	if rng.randf() < minf(1.0, float(p["parry"]) * 2.0):
		var ns := str(c.light_string[(step + 1) % c.light_string.size()])
		var next_start := start + maxf(float(info["cancel"]), bt - start) + STRING_PRESS_LAG
		var at := next_start + float(_move_info(c, ns)["first"]) + _contact_after_first(ns) - PARRY_LEAD + _jitter()
		if at > _t + 0.012:
			_hold_guard(f, at)
			_parry_tap(at, 0.25)
			_tally("block_tap")
			return true
	return false


## The attack whose hit was blocked at `bt`: the newest attack known (seen begin, or counted along
## the string at an earlier block) when its hit frames hold `bt`; past them, the next Light of the
## string, taken to have begun when such a hit lands. {} when nothing fits.
func _blocked_move(c: CreatureDef, bt: float) -> Dictionary:
	var ref: Dictionary = _seen[_seen.size() - 1]
	if not _last_blocked.is_empty() and float(_last_blocked["start"]) > float(ref["start"]):
		ref = _last_blocked
	var since := bt - float(ref["start"]) - float(ref["info"]["first"])
	if since < -0.03:
		return {}
	if since <= _hit_span(ref["info"]):
		return ref
	var step := c.light_string.find(str(ref["slot"]).split("@")[0])
	if step < 0 or bt - float(ref["start"]) > float(ref["info"]["dur"]) + 0.4:
		return {}
	var ns := str(c.light_string[(step + 1) % c.light_string.size()])
	var ni := _move_info(c, ns)
	return {"slot": ns, "info": ni, "start": bt - float(ni["first"]) - _contact_after_first(ns)}


## Earliest time (bot clock) the attacker can threaten again after seen attack `mv` connected at
## `hit_t`: its cancel point plus the quickest follow-up's start-up (string moves), or its end plus
## the quickest fresh move's.
func _next_threat_after(c: CreatureDef, mv: Dictionary, hit_t: float) -> float:
	var info: Dictionary = mv["info"]
	var start := float(mv["start"])
	var string: Array = c.light_string
	var fresh := 9.0
	for s in [str(string[0]) if not string.is_empty() else "l1", "heavy", "grab"]:
		if c.moves.has(s):
			fresh = minf(fresh, float(_move_info(c, s)["first"]))
	var nxt := start + float(info["dur"]) + fresh
	var step := string.find(str(mv["slot"]).split("@")[0])
	if step >= 0:
		var cancel_at := start + maxf(float(info["cancel"]), hit_t - start)
		for s in [str(string[(step + 1) % string.size()]), "finisher"]:
			if c.moves.has(s):
				nxt = minf(nxt, cancel_at + float(_move_info(c, s)["first"]))
	return nxt


## The answer to one seen attack: "parry", "dodge", "counter", "armor", "block" or "none".
func _choose_answer(f: Fighter, tgt: Fighter, per: Dictionary, info: Dictionary, eta: float, over: float, dist: float, dir: Vector3) -> String:
	var heavyish := str(info["cls"]) in ["heavy", "ability", "juice"]
	var light := str(info["cls"]) == "light"
	var mash := _pressured() and _pv("read") > 0.0
	# a parry tap already planned for this hit (after blocking the one before it) stands
	if light and _tap_at > _t and _tap_at - _t < 0.3:
		return "parry"
	if _kit_ability(f, tgt, dist, dir, per, true):   # kit hint: reactive abilities (counters, armor)
		return "counter"
	var sidestep := not (light and mash and rng.randf() < _pv("read"))   # a read masher is blocked, not sidestepped
	if _kit_defend(f, tgt, per, eta > 0.0, dir, eta, sidestep):   # kit hints: parry_heavy / dodge_for_guard
		return "parry" if _tap_at > _t else "dodge"
	# strikes beat a grab's start-up; a dodge gets out of it
	if bool(info["grab"]):
		var poke := _pick_punish(f, eta - 0.02, dist, dir)
		if not poke.is_empty() and int(poke["btn"]) != FighterInput.GRAB and rng.randf() < _pv("punish"):
			_commit(poke, _t, "cp")
			return "counter"
		if rng.randf() < float(p["dodge"]) + float(p["block"]) * 0.5:
			_dodge(f, dir, eta)
			return "dodge"
		return "none"
	# armored against Lights right now (Dust Bowl, JUICE...): trade instead of guarding
	if light and f._armor_covers("light"):
		return "none"
	# button-mashing: blow through the Lights with an armored move (read)
	if light and mash and _t >= _armor_next and rng.randf() < _pv("read") * 0.45:
		for o in _own_options(f):
			if bool(o["armored"]) and _lands(f, str(o["slot"]), dist, dir):
				_armor_next = _t + 1.4
				_commit(o, _t, "ar")
				return "armor"
	# hit it before it comes out: counter-poke a slow wind-up that has no armor
	if heavyish and not bool(info["armored"]) and rng.randf() < _pv("punish") * 0.4:
		var o2 := _pick_punish(f, eta - 0.03, dist, dir)
		if not o2.is_empty() and int(o2["btn"]) != FighterInput.GRAB:
			_commit(o2, _t, "cp")
			return "counter"
	# too close for its own strikes while a masher presses in: step back out of the pocket (read)
	if light and mash and f.stamina > 20.0 and rng.randf() < _pv("read") * float(p["spacing"]) * 0.6 and _too_close(f, dist):
		_backstep(f, dir)
		return "dodge"
	# one roll split into the tier's parry / dodge / block shares. A parry needs time to see the
	# wind-up coming; dodges are for heavies and abilities (a dodge's recovery hands a string free
	# hits). Shares that do not apply become blocks.
	var roll := rng.randf()
	var pp := float(p["parry"])
	var pd := float(p["dodge"])
	var pb := float(p["block"]) + (_pv("read") * 0.5 if mash else 0.0)
	if roll < pp and not bool(info["unblockable"]) and eta - PARRY_LEAD > 0.012:
		_parry_tap(_t + eta - PARRY_LEAD + _jitter())
		return "parry"
	# under pressure a dodge's recovery hands the stream free hits: a reader blocks the Heavy (and
	# punishes it) instead
	var dodge_ok := bool(info["unblockable"]) or not (mash and rng.randf() < _pv("read"))
	if roll >= pp and roll < pp + pd and (heavyish or bool(info["unblockable"])) and dodge_ok:
		_dodge(f, dir, eta)
		return "dodge"
	if bool(info["unblockable"]):
		return "none"
	# a Heavy blocked when winded breaks the guard: a good reader sidesteps it instead
	if heavyish and f.stamina < Tuning.v("stamina_low") + 4.0 and rng.randf() < _pv("read"):
		if f.stamina >= 4.0 and not f.statuses.flag("no_dodge"):
			_dodge(f, dir, eta)
			return "dodge"
		return "none"
	# a guard nearly broken is not held against a stream of Lights
	if light and f.stamina < 8.0 and mash:
		return "none"
	if roll < pp + pd + pb:
		_hold_guard(f, _t + maxf(over, 0.0) + 0.08)
		return "block"
	return "none"


## True when the second hit of the Light string connects from here (an opener that whiffs at this
## range can still lead into it).
func _second_light_lands(f: Fighter, dist: float, dir: Vector3) -> bool:
	var ls: Array = f.creature.light_string
	return ls.size() >= 2 and _lands(f, str(ls[1]), dist, dir)


## Nearest body distance at which the first Light or the Heavy can still strike.
func _strike_floor(c: CreatureDef) -> float:
	var first_light := str(c.light_string[0]) if not c.light_string.is_empty() else "l1"
	var r := _min_range(c, first_light)
	if c.moves.has("heavy"):
		r = minf(r, _min_range(c, "heavy"))
	return r


## True when the target's body is nearer than both the first Light and the Heavy can strike.
func _too_close(f: Fighter, dist: float) -> bool:
	return dist - _bulk < _strike_floor(f.creature)


## Dodges straight back (a little to the side) to make room.
func _backstep(f: Fighter, dir: Vector3) -> void:
	_move = (-dir + dir.cross(Vector3.UP) * (0.3 if rng.randf() < 0.5 else -0.3)).normalized()
	_guard = false
	_guard_until = _t
	_queue(FighterInput.DODGE, 0.0)
	_busy_until = _t + 0.1
	_tally("backstep")


## Sidestep (and back off) so the evasion frames cover the hit.
func _dodge(f: Fighter, dir: Vector3, eta: float) -> void:
	var side := dir.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
	_move = (side - dir * 0.5).normalized()
	_guard = false
	_guard_until = _t
	_queue(FighterInput.DODGE, clampf(eta - 0.06, 0.0, 0.3))
	_busy_until = _t + clampf(eta - 0.06, 0.0, 0.3) + 0.05


## A parried attacker is stunned (parry_stun) and the guard may cancel into anything for a moment:
## answer with the strongest move that lands in time.
func _punish_parry(f: Fighter) -> void:
	if rng.randf() >= _pv("punish"):
		return
	var delay := float(p["reaction"]) * 0.35
	var per := _perceived()
	if f.target == null or per.is_empty():
		return
	var tp: Vector3 = per["pos"]
	var d := Vector2(tp.x - f.pos().x, tp.z - f.pos().z).length()
	var o := _pick_punish(f, Tuning.v("parry_stun") - delay - 0.05, d, Vector3(tp.x - f.pos().x, 0.0, tp.z - f.pos().z).normalized())
	if not o.is_empty():
		_tally("parry_punish")
		_commit(o, _t + delay, "pp")


## Mode objectives that are not plain fighting: hold a button at a spot (revives), strike an
## object toward an aim point (balls), throw a carried object, or just stand on a point.
## Returns true when the objective fully decided this think step.
func _objective_actions(f: Fighter, obj: Dictionary) -> bool:
	if obj.is_empty() or not obj.has("pos"):
		return false
	var p: Vector3 = obj["pos"]
	var to := p - f.pos()
	to.y = 0.0
	var dist := to.length()
	var rad := float(obj.get("radius", 0.5))
	if obj.has("hold"):
		if dist > rad:
			_move = to.normalized()
			return true
		_move = Vector3.ZERO
		f.input.set_held(FighterInput.GRAB, true)
		_hold_until = _t + float(p_think()) * 2.0
		return true
	if bool(obj.get("throw", false)) and f.has_flag("carrying"):
		var aim: Vector3 = obj.get("aim", p)
		var ad := aim - f.pos()
		ad.y = 0.0
		_move = ad.normalized()
		f.input.press(FighterInput.GRAB)
		return true
	if bool(obj.get("strike", false)) and dist < 1.6:
		var aim2: Vector3 = obj.get("aim", p)
		var from_ball := aim2 - p
		from_ball.y = 0.0
		_move = (to.normalized() * 0.6 + from_ball.normalized() * 0.4).normalized()
		if rng.randf() < 0.75:
			f.input.press(FighterInput.HEAVY if rng.randf() < 0.3 else FighterInput.LIGHT)
		elif bool(obj.get("grab_ball", false)):
			f.input.press(FighterInput.GRAB)
		return true
	if f.target == null or f.target.pos().distance_to(f.pos()) > float(obj.get("engage", 3.0)):
		if dist > rad:
			_move = to.normalized()
			return true
	return false


func p_think() -> float:
	return float(p["think"])


func _toward(from: Vector3, to: Vector3) -> Vector3:
	var d := to - from
	d.y = 0.0
	return d.normalized() if d.length() > 0.2 else Vector3.ZERO


# =====================================================================================
# Kit hints (optional keys of the creature "ai" block; added with the Dredge/Dozer kits, extended
# with the Stoke/Gusto kits). Absent keys keep the generic behaviour above.
#   "range": [near, far]        preferred engagement distance (root to root) for footwork
#   "attack_range": m           distance at which strikes start (default: the L1 reach estimate)
#   "charge_heavy": p | {"chance": p, "from": profile}
#                               chance a Heavy press is held into the charged version (scaled by
#                               skill); "from" = the lowest bot profile that charges at all
#   "parry_heavy": {"chance": p, "from": profile}   time a parry against a perceived Heavy windup
#   "guard_max": s              longest guard hold; "dodge_for_guard": p turns that share of guard
#                               reactions into sidesteps
#   "dash_in": {"min": m, "max": m, "chance": p}    dodge toward the target, then Light (dash attack)
#   "dash_out": p               chance to dodge back out when closer than range[0]
#   "grab_status": [ids]        targets carrying one of these statuses are grabbed like guarding ones
#   "juice_when": [cond, ...]   JUICE only when an alternative holds (default: target within 3.5 m)
#   "taunt_when": [cond, ...]   taunt at "taunt_chance" per think (x3 for rookie bots) when one holds
#   "commit_when": [cond, ...]  Light strings go on to L3 / the Finisher when one holds
#   "abilities": {slot: {"min": m, "max": m, "chance": c, "apart": m, "when": [cond, ...]}}
#       (`apart`: never while an ally within that many metres performs the same ability)
#       an ability with a hint is used only by its hint (replaces the generic reach test). `when` is a
#       list of alternatives (any may hold; absent = always); each is a dict whose keys must all hold:
#       min / max (distance), self_poise_below, self_health_below (fractions), target_status (id or
#       element), target_heavy (perceived Heavy / Charged Heavy windup), target_winding (any windup),
#       target_ranged (the target has a projectile ability), wall_behind_target (an arena wall
#       within this many metres beyond the target, on the line from this fighter), target_down,
#       target_cornered (target within 1.3 m of a wall), target_closing (distance shrank since the
#       last think), projectile_incoming (an enemy projectile within 4 m flying at this fighter),
#       in_enemy_zone, self_juiced, target_mashing (the bot reads the target pressing attacks
#       non-stop, a button-masher's habit; only as often as its "read" skill), chance (this
#       alternative only fires with that probability).
#       Reactive conditions (target_heavy / target_winding) are also checked while defending.
#       Optional "stick": "away" | "toward" commits the stick for 0.35 s when the ability fires
#       (blinks / dives that travel along the stick).
#   "range_needs_tools": true   "range" holds only while a ranged ability hint (min >= 1.5 m) has a
#                               charge: a zoner with its tools on cooldown closes in and fights
#   "heavy_vs_windup": p, "heavy_reach": m   Heavy into a perceived windup with > 0.3 s left
#   "avoid_zones": true         step out of enemy zones that hurt or build up before closing in
#   (stick / range_needs_tools / heavy_vs_windup / avoid_zones added with the Slurry/Jitters kits)
# NPC kits (Kid Lamprey, minions, bosses; docs/kits/minions.md, bosses.md):
#   "keep_distance": m          ranged-unit shorthand (the campaign's Pelter recipe): range m +- 0.4
#                               plus an implicit hint for its ranged ability ("ranged_slot", default
#                               the longest-reaching one) from 1.5 m out; "prefers": "ranged" = 4 m
#   "pack": n                   at most n allies with a "pack" key attack one target at once; the
#                               rest wait at "pack_ring" m (default 2.2) circling toward its flank
#                               and raise "pack_guard" (an ability slot, or "guard") when it swings
#   "ally_ko_flinch": s         freeze this long after an ally within 3 m is knocked out
#   "rest": [min, max]          wait after each own attack / ability (and queue nothing in its
#                               recovery) - a boss's breather and the punish window
#   "reach": {slot: m}          authored reach (bodies that strike by bending, read by reach_of)
#   "bulky": true               read from the TARGET (bosses): reach is measured to its nearest body
#                               part, and its long moves' recoveries are openings, not threats
# Profiles in skill order: rookie (Punching Bag) < regular (Journeyman) < pro (Contender)
#   < champion (Headliner) < hall_of_famer.
# =====================================================================================

const KIT_PROFILE_ORDER := ["rookie", "regular", "pro", "champion", "hall_of_famer"]

var _kit_last_dist := -1.0
var _kit_dash_until := 0.0


func _kit_hint(slot: String) -> Dictionary:
	var ab = personality.get("abilities", {})
	if typeof(ab) != TYPE_DICTIONARY:
		return {}
	var h = (ab as Dictionary).get(slot, {})
	return h if typeof(h) == TYPE_DICTIONARY else {}


func _kit_ability(f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary, reactive: bool) -> bool:
	for slot in ["ability1", "ability2"]:
		var h := _kit_hint_for(f.creature, slot)
		if h.is_empty() or not f.creature.abilities.has(slot) or int(f.charges_left.get(slot, 1)) <= 0:
			continue
		var ab: MoveDef = f.creature.abilities[slot]
		if f.stamina < ab.stamina * 0.5:
			continue
		var gate := float(p["ability"]) * (0.8 if reactive else 0.35) * float(h.get("chance", 1.0))
		if rng.randf() >= gate:
			continue
		if dist < float(h.get("min", 0.0)) or dist > float(h.get("max", 99.0)):
			continue
		if h.has("apart") and _kit_ally_using(f, slot, float(h["apart"])) != null:
			continue
		var whens = h.get("when", [])
		var ok: bool = typeof(whens) != TYPE_ARRAY or (whens as Array).is_empty()
		if reactive:
			ok = false
		if typeof(whens) == TYPE_ARRAY:
			for w in whens:
				if typeof(w) == TYPE_DICTIONARY and _kit_when(f, tgt, dist, dir, per, w as Dictionary, reactive):
					ok = true
					break
		if ok:
			_kit_stick(h, dir)
			f.input.press(FighterInput.AB1 if slot == "ability1" else FighterInput.AB2)
			return true
	return false


func _kit_stick(h: Dictionary, dir: Vector3) -> void:
	match str(h.get("stick", "")):
		"away":
			_move = -dir
			_kit_hold_until = _t + 0.35
		"toward":
			_move = dir
			_kit_hold_until = _t + 0.35


func _kit_when(f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary, w: Dictionary, reactive: bool) -> bool:
	if reactive and not (w.has("target_heavy") or w.has("target_winding")):
		return false
	var p_state := int(per.get("state", Fighter.State.NEUTRAL))
	var p_attacking := p_state == Fighter.State.ATTACK or p_state == Fighter.State.ABILITY
	var p_winding := p_attacking and float(per.get("st", 0.0)) < float(per.get("first", 0.0))
	for k in w:
		var v = w[k]
		match str(k):
			"min":
				if dist < float(v):
					return false
			"max":
				if dist > float(v):
					return false
			"self_poise_below":
				if f.poise / maxf(1.0, f.effective_max_poise()) >= float(v):
					return false
			"self_health_below":
				if f.health_frac() >= float(v):
					return false
			"target_status":
				if tgt == null or not (tgt.statuses.has(str(v)) or tgt.statuses.has_element(str(v))):
					return false
			"target_heavy":
				if (p_winding and str(per.get("slot", "")).begins_with("heavy")) != bool(v):
					return false
			"target_winding":
				if p_winding != bool(v):
					return false
			"target_ranged":
				if _kit_is_ranged(tgt) != bool(v):
					return false
			"wall_behind_target":
				if f.sim == null or f.sim.arena == null:
					return false
				if f.sim.arena.inside(f.pos() + dir * (dist + float(v)), 0.3):
					return false
			"target_down":
				if (tgt != null and tgt.is_down()) != bool(v):
					return false
			"target_cornered":
				if (tgt != null and f.sim != null and f.sim.arena != null and not f.sim.arena.inside(tgt.pos(), 1.3)) != bool(v):
					return false
			"target_closing":
				if (_kit_last_dist > 0.0 and _kit_last_dist - dist > 0.08) != bool(v):
					return false
			"projectile_incoming":
				if _kit_projectile_incoming(f) != bool(v):
					return false
			"in_enemy_zone":
				if _kit_in_enemy_zone(f) != bool(v):
					return false
			"self_juiced":
				if f.has_flag("juiced") != bool(v):
					return false
			"target_mashing":
				if (_pv("read") > 0.0 and _pressured() and rng.randf() < _pv("read")) != bool(v):
					return false
			"chance":
				if rng.randf() >= float(v):
					return false
	return true


## True when any alternative of a hint's condition list holds (non-reactive).
func _kit_any_when(whens, f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary) -> bool:
	if typeof(whens) != TYPE_ARRAY:
		return false
	for w in whens:
		if typeof(w) == TYPE_DICTIONARY and _kit_when(f, tgt, dist, dir, per, w as Dictionary, false):
			return true
	return false


func _kit_profile_at_least(name_: String) -> bool:
	return KIT_PROFILE_ORDER.find(difficulty) >= maxi(0, KIT_PROFILE_ORDER.find(name_))


func _kit_projectile_incoming(f: Fighter) -> bool:
	if f.sim == null:
		return false
	for e in f.sim.effects.entities:
		if e["kind"] != "projectile" or int(e["team"]) == f.team:
			continue
		var rel: Vector3 = f.pos() - Vector3(e["pos"])
		rel.y = 0.0
		var vel: Vector3 = e["vel"]
		vel.y = 0.0
		if rel.length() < 4.0 and vel.dot(rel) > 0.0:
			return true
	return false


func _kit_in_enemy_zone(f: Fighter) -> bool:
	if f.sim == null:
		return false
	for z in f.sim.effects.entities:
		if z["kind"] != "zone" or int(z["owner"]) == f.index or int(z.get("team", -1)) == f.team:
			continue
		if Vector2(f.pos().x - z["pos"].x, f.pos().z - z["pos"].z).length() <= float(z["radius"]):
			return true
	return false


func _kit_is_ranged(tgt: Fighter) -> bool:
	if tgt == null:
		return false
	for slot in tgt.creature.abilities:
		var m: MoveDef = tgt.creature.abilities[slot]
		for e in m.effects:
			if typeof(e) == TYPE_DICTIONARY and str(e.get("type", "")) == "projectile":
				return true
	return false


func _kit_grab_target(tgt: Fighter) -> bool:
	var gs = personality.get("grab_status", [])
	if tgt == null or typeof(gs) != TYPE_ARRAY:
		return false
	for s in gs:
		if tgt.statuses.has(str(s)) or tgt.statuses.has_element(str(s)):
			return true
	return false


## After a Heavy press: maybe keep holding it so the charged version comes out (skill-scaled).
func _kit_maybe_charge() -> void:
	var cfg = personality.get("charge_heavy", 0.0)
	var ch := 0.0
	if typeof(cfg) == TYPE_DICTIONARY:
		if not _kit_profile_at_least(str(cfg.get("from", "rookie"))):
			return
		ch = float(cfg.get("chance", 0.0))
	elif typeof(cfg) == TYPE_FLOAT or typeof(cfg) == TYPE_INT:
		ch = float(cfg)
	ch *= float(p["combo"])
	if ch > 0.0 and rng.randf() < ch:
		_heavy_hold_until = _t + rng.randf_range(0.6, 1.1)


## Defence hints: a timed parry tap against a perceived Heavy wind-up (profile-gated) or a sidestep
## instead of a long guard. Returns true when it decided this think step.
func _kit_defend(f: Fighter, tgt: Fighter, per: Dictionary, winding: bool, dir: Vector3, eta := -1.0, sidestep := true) -> bool:
	var ph = personality.get("parry_heavy", {})
	if winding and typeof(ph) == TYPE_DICTIONARY and not (ph as Dictionary).is_empty() and _kit_profile_at_least(str(ph.get("from", "champion"))) \
			and tgt != null and str(per.get("slot", "")).begins_with("heavy") and eta - PARRY_LEAD > 0.012 and rng.randf() < float(ph.get("chance", 0.35)):
		_parry_tap(_t + eta - PARRY_LEAD + _jitter())
		return true
	if sidestep and personality.has("dodge_for_guard") and rng.randf() < float(p["block"]) * float(personality["dodge_for_guard"]) and f.stamina > 12.0:
		var side := dir.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
		_move = (side - dir * 0.6).normalized()
		f.input.press(FighterInput.DODGE)
		return true
	return false


func _kit_juice_ok(f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary) -> bool:
	if personality.has("juice_when"):
		return _kit_any_when(personality["juice_when"], f, tgt, dist, dir, per)
	return dist < 3.5


## Light strings go on to L3 / the Finisher while a commit condition holds (e.g. a Sizzling target).
func _kit_commit(f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary) -> bool:
	if not personality.has("commit_when") or f.state != Fighter.State.ATTACK or not f.move_slot in ["l1", "l2", "l3"]:
		return false
	if rng.randf() > float(p["combo"]) + 0.15 or not _kit_any_when(personality["commit_when"], f, tgt, dist, dir, per):
		return false
	f.input.press(FighterInput.HEAVY if f.move_slot in ["l2", "l3"] else FighterInput.LIGHT)
	return true


## Dash-in attacks and hit-and-run exits; returns true when it decided this think step.
func _kit_movement(f: Fighter, dist: float, dir: Vector3) -> bool:
	_kit_last_dist = dist   # "target_closing" compares against this on the next think
	var rg = personality.get("range", [])
	var di = personality.get("dash_in", {})
	if typeof(di) == TYPE_DICTIONARY and not (di as Dictionary).is_empty() and f.state == Fighter.State.NEUTRAL and _t > _kit_dash_until \
			and f.stamina > 20.0 and dist >= float(di.get("min", 1.6)) and dist <= float(di.get("max", 3.6)) \
			and rng.randf() < float(di.get("chance", 0.3)) * float(p["aggression"]):
		_move = dir
		f.input.press(FighterInput.DODGE)
		_queue(FighterInput.LIGHT, rng.randf_range(0.11, 0.16))
		_kit_dash_until = _t + 0.9
		return true
	if personality.has("dash_out") and typeof(rg) == TYPE_ARRAY and (rg as Array).size() >= 2 and dist < float(rg[0]) \
			and f.stamina > 16.0 and _t > _kit_dash_until and f.state == Fighter.State.NEUTRAL \
			and rng.randf() < float(personality["dash_out"]) * float(p["spacing"]):
		_move = (-dir + dir.cross(Vector3.UP) * (0.4 if rng.randf() < 0.5 else -0.4)).normalized()
		f.input.press(FighterInput.DODGE)
		_kit_dash_until = _t + 0.6
		return true
	return false


func _kit_taunt(f: Fighter, tgt: Fighter, dist: float, dir: Vector3, per: Dictionary) -> void:
	if f.hype >= 100.0 or f.state != Fighter.State.NEUTRAL:
		return
	var chance := float(personality.get("taunt_chance", 0.05)) * (3.0 if difficulty == "rookie" else 1.0)
	if rng.randf() < chance and _kit_any_when(personality["taunt_when"], f, tgt, dist, dir, per):
		f.input.press(FighterInput.TAUNT)


func _kit_range_ready(f: Fighter) -> bool:
	if not bool(personality.get("range_needs_tools", false)):
		return true
	for slot in ["ability1", "ability2"]:
		var h := _kit_hint(slot)
		if h.is_empty() or float(h.get("min", 0.0)) < 1.5 or not f.creature.abilities.has(slot):
			continue
		if int(f.charges_left.get(slot, 1)) > 0:
			return true
	return false


func _kit_heavy_vs_windup(f: Fighter, dist: float, per: Dictionary) -> bool:
	var hw := float(personality.get("heavy_vs_windup", 0.0))
	if hw <= 0.0 or f.state != Fighter.State.NEUTRAL or dist > float(personality.get("heavy_reach", 2.2)):
		return false
	var st := int(per.get("state", Fighter.State.NEUTRAL))
	var left := float(per.get("first", 0.0)) - float(per.get("st", 0.0))
	if (st == Fighter.State.ATTACK or st == Fighter.State.ABILITY) and left > 0.3 and rng.randf() < hw:
		f.input.press(FighterInput.HEAVY)
		return true
	return false


# -------------------------------------------------------------------------------------
# NPC-kit hints (keys listed in the kit-hint header above)
# -------------------------------------------------------------------------------------

var _flinch_until := -1.0
var _ev_cursor := -1
var _was_busy := false               ## attacking / using an ability last tick (for "rest")
var _rest_until := -1.0


## The hint that drives `slot`: the authored one, or the implicit hint of a ranged unit's ranged
## ability (keep_distance / prefers ranged). Empty = the generic ability logic uses the slot.
func _kit_hint_for(c: CreatureDef, slot: String) -> Dictionary:
	var h := _kit_hint(slot)
	if not h.is_empty() or _kit_keep_distance() <= 0.0:
		return h
	var ranged := str(personality.get("ranged_slot", ""))
	if ranged == "":
		var best := 0.0
		for s in ["ability1", "ability2"]:
			if c.abilities.has(s) and reach_of(c, s, true) > best:
				best = reach_of(c, s, true)
				ranged = s
	if slot != ranged or not c.abilities.has(slot):
		return {}
	return {"min": 1.5, "max": reach_of(c, slot, true), "chance": 2.5}


func _kit_keep_distance() -> float:
	return float(personality.get("keep_distance", 4.0 if str(personality.get("prefers", "")) == "ranged" else 0.0))


## Preferred engagement distance [near, far] for footwork, or [] for the generic spacing.
func _kit_range() -> Array:
	var r = personality.get("range")
	if r is Array and (r as Array).size() >= 2:
		return r
	var kd := _kit_keep_distance()
	return [kd - 0.4, kd + 0.4] if kd > 0.0 else []


## Every tick, before anything else: starts a "rest" when an attack ends and keeps a flinching
## unit frozen. Returns true when this tick is fully decided.
func _kit_pre_poll(f: Fighter) -> bool:
	var busy := f.state == Fighter.State.ATTACK or f.state == Fighter.State.ABILITY
	var rest = personality.get("rest", [])
	if _was_busy and not busy and rest is Array and (rest as Array).size() >= 2:
		_rest_until = _t + rng.randf_range(float(rest[0]), float(rest[1]))
	_was_busy = busy
	if _t < _flinch_until:
		f.input.move = Vector3.ZERO
		f.input.held = 0
		return true
	return false


## Kit behaviours that replace the rest of a think step (flinch, rest, pack). Returns true when
## they decided it.
func _kit_think(f: Fighter, sim: MatchSim, tgt: Fighter, dist: float, dir: Vector3, attacking: bool,
		my_reach: float, their_reach: float) -> bool:
	if personality.is_empty():
		return false
	var flinch := float(personality.get("ally_ko_flinch", 0.0))
	if flinch > 0.0:
		if _ev_cursor < 0:
			_ev_cursor = sim.event_seq
		for ev in sim.events_since(_ev_cursor):
			_ev_cursor = int(ev["seq"])
			if str(ev["type"]) != "ko":
				continue
			var ki := int(ev.get("fighter", -1))
			if ki >= 0 and ki < sim.fighters.size() and ki != f.index:
				var k: Fighter = sim.fighters[ki]
				if k.team == f.team and k.pos().distance_to(f.pos()) < 3.0:
					_flinch_until = _t + flinch
		if _t < _flinch_until:
			_move = Vector3.ZERO
			_guard = false
			return true
	var rest = personality.get("rest", [])
	if rest is Array and (rest as Array).size() >= 2 and (f.state == Fighter.State.ATTACK or f.state == Fighter.State.ABILITY) \
			and f.move != null and f.state_time > _kit_last_threat(f.move) + 0.05:
		return true   # nothing new is queued in a recovery: the rest follows the move
	if _t < _rest_until and f.state == Fighter.State.NEUTRAL:
		if _t >= _strafe_until:
			_strafe = -1.0 if rng.randf() < 0.5 else 1.0
			_strafe_until = _t + rng.randf_range(0.6, 1.6)
		var circle := dir.cross(Vector3.UP) * _strafe * 0.45
		_move = (circle + dir * 0.5).normalized() * 0.6 if dist > my_reach + 1.0 else circle
		return true
	var pack := int(personality.get("pack", 0))
	if pack > 0 and _kit_range().is_empty() and not _kit_pack_attacker(f, sim, tgt, pack):
		_kit_pack_hold(f, dist, dir, attacking, their_reach)
		return true
	return false


## Steps out of an enemy zone that hurts or builds up (puddles, patches) instead of idling in it,
## sideways relative to the target so the bot keeps facing the fight. Skill-scaled (spacing).
func _kit_avoid_zone(f: Fighter, sim: MatchSim, dir: Vector3) -> bool:
	if not bool(personality.get("avoid_zones", false)) or sim == null:
		return false
	if rng.randf() >= float(p["spacing"]):
		return false
	var fp := f.pos()
	for z in sim.effects.entities:
		if str(z["kind"]) != "zone" or int(z["owner"]) < 0 or int(z["team"]) == f.team:
			continue
		var e: Dictionary = z["e"]
		if float(e.get("tick_damage", 0.0)) <= 0.0 and float(e.get("buildup", 0.0)) <= 0.0:
			continue
		var off := Vector3(fp.x - float(z["pos"].x), 0.0, fp.z - float(z["pos"].z))
		if off.length() > float(z["radius"]) + 0.3:
			continue
		var out := off.normalized() if off.length_squared() > 1e-4 else dir.cross(Vector3.UP)
		var side := dir.cross(Vector3.UP)
		_move = (out + side * (1.0 if side.dot(out) >= 0.0 else -1.0) * 0.5).normalized()
		return true
	return false


## How much closer than its root a "bulky" target's body is to this unit (metres, less a 0.25 m
## allowance for segment thickness), added to the unit's reach. 0 for ordinary bodies.
func _kit_target_bulk(f: Fighter, tgt: Fighter) -> float:
	if tgt == null or tgt.rig == null or not bool(tgt.creature.ai.get("bulky", false)):
		return 0.0
	var me := Vector3(f.pos().x, 0.0, f.pos().z)
	var root_d := me.distance_to(Vector3(tgt.pos().x, 0.0, tgt.pos().z))
	var nearest := root_d
	for b in tgt.rig.bodies:
		var bp: Vector3 = b.global_position
		nearest = minf(nearest, me.distance_to(Vector3(bp.x, 0.0, bp.z)))
	return maxf(0.0, root_d - nearest - 0.25)


## How much closer than its root `body`'s surface is to the point `from` (metres, over the
## ground plane, to the hurt shapes hits are tested against): reach is judged to the body, not
## the root, so a long head (Dozer) or a boss is in range sooner.
static func _surface_depth(from: Vector3, body: Fighter) -> float:
	if body == null or body.rig == null:
		return 0.0
	var me := Vector3(from.x, 0.0, from.z)
	var root_d := me.distance_to(Vector3(body.pos().x, 0.0, body.pos().z))
	var nearest := root_d
	for s: BodyDef.Seg in body.creature.body.segments:
		var t := body.rig.bodies[s.index].global_transform
		for sh: BodyDef.Shape in s.shapes:
			var a := t * sh.hit_a
			var b := t * sh.hit_b
			a.y = 0.0
			b.y = 0.0
			nearest = minf(nearest, me.distance_to(MathX.closest_on_segment(me, a, b)) - sh.hit_r)
	return maxf(0.0, root_d - maxf(nearest, 0.0) - 0.1)


## True when a bulky target's perceived move is past its last threat (hit windows, lunges and
## timed effects, landing included, + 0.1 s): its recovery is an opening, not a threat.
func _kit_opening(per: Dictionary, tgt: Fighter) -> bool:
	if tgt == null or not bool(tgt.creature.ai.get("bulky", false)):
		return false
	var slot := str(per.get("slot", ""))
	var m: MoveDef = tgt.creature.moves.get(slot, tgt.creature.abilities.get(slot))
	if m == null:
		return false
	return float(per.get("st", 0.0)) > _kit_last_threat(m) + 0.1


## Time of a move's last threat: its last hit window, lunge or timed effect (landing included).
static func _kit_last_threat(m: MoveDef) -> float:
	var last := 0.0
	for w in m.windows:
		last = maxf(last, float(w["t1"]))
	for l in m.lunges:
		last = maxf(last, float(l[1]))
	for e in m.effects:
		last = maxf(last, float(e.get("t", 0.0)) + float(e.get("time", 0.0)) + float(e.get("delay", 0.0)))
	return last


func _kit_ability_ready(f: Fighter, slot: String) -> bool:
	return f.creature.abilities.has(slot) and int(f.charges_left.get(slot, 1)) > 0 and not bool(f.mods.get("no_abilities", false))


## An ally within `r` m currently performing ability `slot`, or null.
func _kit_ally_using(f: Fighter, slot: String, r: float) -> Fighter:
	if f.sim == null:
		return null
	for o: Fighter in f.sim.fighters:
		if o == f or o.despawned or o.is_out() or o.team != f.team:
			continue
		if o.state == Fighter.State.ABILITY and o.move_slot.split("@")[0] == slot and o.pos().distance_to(f.pos()) < r:
			return o
	return null


## True when `f` is one of the `n` pack members closest to the target (only they attack).
func _kit_pack_attacker(f: Fighter, sim: MatchSim, tgt: Fighter, n: int) -> bool:
	var mine := f.pos().distance_to(tgt.pos())
	var closer := 0
	for o: Fighter in sim.fighters:
		if o == f or o.despawned or o.is_out() or o.team != f.team or o.target != tgt:
			continue
		var oai: Dictionary = o.creature.ai
		if int(oai.get("pack", 0)) <= 0 or oai.has("range") or float(oai.get("keep_distance", 0.0)) > 0.0 \
				or str(oai.get("prefers", "")) == "ranged":
			continue
		if o.pos().distance_to(tgt.pos()) < mine:
			closer += 1
	return closer < n


## Waiting pack member: hold a ring around the target, drift toward its flank, shield up when
## it swings this way.
func _kit_pack_hold(f: Fighter, dist: float, dir: Vector3, attacking: bool, their_reach: float) -> void:
	var ring := float(personality.get("pack_ring", 2.2))
	if _t >= _strafe_until:
		_strafe = -1.0 if rng.randf() < 0.5 else 1.0
		_strafe_until = _t + rng.randf_range(0.6, 1.8)
	var side := dir.cross(Vector3.UP) * _strafe
	if dist < ring - 0.3:
		_move = (-dir + side * 0.6).normalized()
	elif dist > ring + 0.6:
		_move = (dir + side * 0.4).normalized()
	else:
		_move = side * 0.7
	if attacking and dist < their_reach + 0.8:
		var g := str(personality.get("pack_guard", "guard"))
		if g.begins_with("ability") and _kit_ability_ready(f, g):
			f.input.press(FighterInput.AB1 if g == "ability1" else FighterInput.AB2)
		else:
			_guard = true
			_guard_until = _t + 0.5
			f.input.press(FighterInput.GUARD)
