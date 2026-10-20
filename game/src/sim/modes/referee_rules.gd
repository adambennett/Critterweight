class_name RefereeRules
extends RefCounted
## The referee's gameplay rules for a standard duel (rules "referee": true, MCH-08), adapted from
## Cage Rules' striking-only referee. Owned by MatchMode (created in MatchMode.setup only for the
## standard mode and a two-sided duel). The referee figure itself is view-only (RefereeView) and
## is driven by the plain data this produces (events and MatchMode.view_state().referee).
##
## Rules:
##  * A downed fighter is protected: no opponent hit lands while they are down (KNOCKDOWN, DOWN or
##    GETUP; MatchMode.hit_allowed, active in every phase). The grab / cage package and
##    environment damage are unaffected (Combat.GRAB_PACKAGE).
##  * Knockdown count: on a strike knockdown (RoundJudge.is_strike_knockdown) the referee counts
##    once per second while the fighter stays down ("ref_count" {fighter, n}). Input gets up at any
##    time; the automatic get-up waits REF_KD_STAY s in DOWN (Cage Rules KD_STAY) instead of the
##    normal Tuning value, and staying down regenerates stamina KD_DOWN_RECOVER x faster. A forced
##    get-up (getup.forced) is "ref_wave_up" {fighter}. Throw knockdowns are never counted.
##  * Back off: bots step away (>= ~2.4 m) from a downed opponent (MatchMode.bot_objective).
##  * Stoppage: kd_limit strike knockdowns of one fighter in one round -> "ref_stoppage"
##    {fighter: loser, by: winner, reason: "knockdowns", round}; 10-point scoring ends the match
##    (T.K.O.), Health scoring ends the round (MatchMode.referee_stoppage).
##    The N-knockdown stoppage is a Critterweight addition (Cage Rules stops fights on damage).
##
## Invariants: deterministic, RNG-free, plain-data state; counts, wave-ups and stoppages happen
## only while the mode is in FIGHT and the round is open (begin_round .. close_round), so nothing
## after the bell (or during the intro) can stop a fight; outside that window the get-up time
## is the normal one.

const REF_KD_STAY := 4.0          ## seconds a counted fighter may stay in DOWN before being waved up
## strike knockdowns in one round that stop the fight. Calibrated on bot duels (v0.9.16): 4+ in a
## round is a one-sided beating; 5 stops ~8% of same-tier duels and ~25% of mismatches (3 would
## stop 31% of same-tier duels, 4 would stop 25%), so the cards decide most even fights.
const REF_KD_LIMIT := 5
const KD_DOWN_RECOVER := 2.5      ## stamina regeneration multiplier while staying down on a count
const BACK_OFF_DIST := 2.4        ## where bots wait while an opponent is down (m from the downed fighter)

var sim: MatchSim
var kd_limit := REF_KD_LIMIT      ## tests and calibration may raise it
var open := false                 ## true from round_start until the round closes
var stoppages: Array = []         ## [{fighter, by, round, time, reason}] over the match
var stop_fighter := -1            ## fighter the referee stopped (or who was KO'd), this round
var wave_off := false             ## the round ended by a stoppage or a KO (presentation)
var _kd_round := {}               ## fighter index -> strike knockdowns this round
var _count := {}                  ## fighter index -> {"t0": sim time, "n": seconds counted, "by": idx}
var _cursor := 0
var _round_no := 1


## No back-reference to the mode (RefCounted cycles never free): tick returns a stoppage instead.
func _init(match_sim: MatchSim) -> void:
	sim = match_sim
	_cursor = sim.event_seq


func begin_round(round_no: int) -> void:
	_round_no = round_no
	_kd_round.clear()
	_count.clear()
	stop_fighter = -1
	wave_off = false
	_cursor = sim.event_seq
	open = true


## The round is over (bell, stoppage, KO, sudden death): no more counts or stoppages.
func close_round() -> void:
	open = false
	_count.clear()


func on_round_reset() -> void:
	close_round()
	stop_fighter = -1
	wave_off = false


func is_counting(f: Fighter) -> bool:
	return open and _count.has(f.index)


## A hit an opponent tries to land on `b` (strikes, projectiles, zones): voided while b is down.
func hit_allowed(a: Fighter, b: Fighter) -> bool:
	return not (sim.are_enemies(a, b) and b.is_down())


## Seconds in DOWN before the automatic get-up: REF_KD_STAY while the referee is counting.
func auto_getup_time(f: Fighter, normal: float) -> float:
	return REF_KD_STAY if is_counting(f) else normal


func down_regen_mult(f: Fighter) -> float:
	return KD_DOWN_RECOVER if is_counting(f) else 1.0


## Per FIGHT tick (MatchMode.tick, after sudden death): knockdowns, counts, wave-ups. Returns the
## stoppage {fighter, by, round, time (s into the round), reason} when the referee stops it, else {}.
func tick(round_seconds: float) -> Dictionary:
	if not open:
		_cursor = sim.event_seq
		return {}
	var stop := {}
	var evs: Array = sim.events
	var i := evs.size()
	while i > 0 and int(evs[i - 1]["seq"]) > _cursor:
		i -= 1
	# a copy: emitting below appends to (and trims) the event ring
	for ev: Dictionary in evs.slice(i):
		if not open:
			break
		_cursor = int(ev["seq"])
		match str(ev.get("type", "")):
			"knockdown":
				if RoundJudge.is_strike_knockdown(sim, ev):
					stop = _strike_knockdown(int(ev["fighter"]), int(ev["by"]), round_seconds)
			"getup":
				var gi := int(ev.get("fighter", -1))
				if _count.has(gi):
					_count.erase(gi)
					if bool(ev.get("forced", false)):
						sim.emit_event({"type": "ref_wave_up", "fighter": gi})
	if not open:
		return stop
	for fi in _count.keys():
		var f := sim.fighters[fi]
		if f.state != Fighter.State.KNOCKDOWN and f.state != Fighter.State.DOWN:
			_count.erase(fi)
			continue
		var c: Dictionary = _count[fi]
		var secs := int(floorf(sim.time - float(c["t0"])))
		while int(c["n"]) < secs:
			c["n"] = int(c["n"]) + 1
			sim.emit_event({"type": "ref_count", "fighter": int(fi), "n": int(c["n"])})
	return stop


func _strike_knockdown(v: int, by: int, round_seconds: float) -> Dictionary:
	_kd_round[v] = int(_kd_round.get(v, 0)) + 1
	_count[v] = {"t0": sim.time, "n": 0, "by": by}
	if int(_kd_round[v]) < kd_limit:
		return {}
	var stop := {"fighter": v, "by": by, "round": _round_no, "time": RoundJudge.plain(round_seconds), "reason": "knockdowns"}
	stoppages.append(stop.duplicate())
	stop_fighter = v
	wave_off = true
	sim.emit_event({"type": "ref_stoppage", "fighter": v, "by": by, "reason": "knockdowns", "round": _round_no})
	close_round()
	return stop


## Strike knockdowns a fighter has suffered this round.
func knockdowns_this_round(f: Fighter) -> int:
	return int(_kd_round.get(f.index, 0))


## A KO under Health scoring with the referee on is waved off like a stoppage (presentation).
func note_ko(f: Fighter) -> void:
	if open:
		stop_fighter = f.index
		wave_off = true


## Bots back off while an opponent is down: {pos, engage 0, radius} (never hold / target keys,
## see BotBrain._objective_actions), or {} when nobody near them is down.
func back_off_objective(f: Fighter) -> Dictionary:
	if f.is_out() or f.despawned:
		return {}
	for o: Fighter in sim.fighters:
		if o.despawned or not sim.are_enemies(f, o) or not o.is_down():
			continue
		var dp := o.pos()
		var away := f.pos() - dp
		away.y = 0.0
		if away.length_squared() < 1e-4:
			away = -o.forward()
			away.y = 0.0
		away = away.normalized() if away.length_squared() > 1e-6 else Vector3(1.0, 0.0, 0.0)
		var spot := sim.clamp_to_arena(Vector3(dp.x, 0.0, dp.z) + away * BACK_OFF_DIST, 1.0)
		return {"pos": spot, "engage": 0.0, "radius": 0.4}
	return {}


## Presentation data for view_state().referee: only the active parts (B3), {} when idle.
## {"count": {"fighter", "n", "left"}} while counting, "stop": loser index, "wave_off": true.
func view() -> Dictionary:
	var v := {}
	for fi in _count:
		var f := sim.fighters[fi]
		var c: Dictionary = _count[fi]
		var left := REF_KD_STAY
		if f.state == Fighter.State.DOWN:
			left = maxf(0.0, REF_KD_STAY - f.state_time)
		elif f.state == Fighter.State.KNOCKDOWN:
			left = REF_KD_STAY + maxf(0.0, Tuning.v("knockdown_min") / f.getup_speed_mult() - f.state_time)
		v["count"] = {"fighter": int(fi), "n": int(c["n"]), "left": snappedf(left, 0.1)}
		break
	if stop_fighter >= 0:
		v["stop"] = stop_fighter
	if wave_off:
		v["wave_off"] = true
	return v
