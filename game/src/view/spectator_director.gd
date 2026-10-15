class_name SpectatorDirector
extends RefCounted
## Auto-director for AI-vs-AI spectating (AI-02). Picks who the broadcast camera frames: it
## scores every fighter by recent action (damage dealt and taken, knockdowns, JUICE, low health),
## holds a shot for a few seconds, cuts immediately to big moments (KO, knockdown, JUICE, wall
## splats), and mixes in wide shots of the whole cage. Viewers can lock the camera on one fighter
## (cycle) or hand control back to the director.

const MIN_SHOT := 4.0
const MAX_SHOT := 9.0
const WIDE_EVERY := 3            ## every Nth cut is a wide shot when 3+ fighters are standing

var sim: MatchSim
var locked := -1                 ## fighter index the viewer locked on (-1 = auto)
var focus_index := 0
var shot := "pair"               ## pair | wide | close
var _interest := {}              ## fighter index -> score
var _shot_t := 0.0
var _shot_len := 6.0
var _cuts := 0
var _hold_until := 0.0
var _rng := RandomNumberGenerator.new()


func _init(match_sim: MatchSim) -> void:
	sim = match_sim
	_rng.seed = match_sim.seed_value * 13 + 5


func on_event(ev: Dictionary) -> void:
	var t := str(ev.get("type", ""))
	var fi := int(ev.get("fighter", -1))
	match t:
		"hit":
			var dmg := float(ev.get("damage", 0.0))
			_bump(fi, dmg * 0.6)
			_bump(int(ev.get("target", -1)), dmg * 0.4)
			if dmg >= 14.0:
				_cut_to(fi, "close", 2.2)
		"knockdown", "ko", "guard_break":
			_cut_to(fi, "close", 2.6 if t == "ko" else 2.0)
		"juice":
			_bump(fi, 25.0)
			_cut_to(fi, "close", 2.5)
		"slam", "reaction", "goal", "unit_crowned":
			if fi >= 0:
				_cut_to(fi, "pair", 2.0)


func _bump(i: int, v: float) -> void:
	if i >= 0:
		_interest[i] = float(_interest.get(i, 0.0)) + v


func _cut_to(i: int, kind: String, hold: float) -> void:
	if locked >= 0 or i < 0 or i >= sim.fighters.size():
		return
	focus_index = i
	shot = kind
	_shot_t = 0.0
	_shot_len = maxf(hold, MIN_SHOT * 0.6)
	_hold_until = sim.time + hold


func update(dt: float) -> void:
	for k in _interest.keys():
		_interest[k] = float(_interest[k]) * exp(-dt / 4.0)
	_shot_t += dt
	if locked >= 0:
		focus_index = locked
		shot = "pair"
		return
	if sim.time < _hold_until:
		return
	if _shot_t >= _shot_len or not _valid(focus_index):
		_next_shot()


func _valid(i: int) -> bool:
	return i >= 0 and i < sim.fighters.size() and not sim.fighters[i].despawned and not sim.fighters[i].is_out()


## During a held cut (KO, knockdown) the camera may stay on a fighter who is down or out.
func _framable(i: int) -> bool:
	if i < 0 or i >= sim.fighters.size() or sim.fighters[i].despawned:
		return false
	return _valid(i) or sim.time < _hold_until


func _next_shot() -> void:
	_cuts += 1
	_shot_t = 0.0
	_shot_len = _rng.randf_range(MIN_SHOT, MAX_SHOT)
	var standing := sim.fighters.filter(func(f: Fighter): return not f.despawned and not f.is_out())
	if standing.size() >= 3 and _cuts % WIDE_EVERY == 0:
		shot = "wide"
		return
	shot = "pair"
	var best := -1
	var best_s := -INF
	for f: Fighter in standing:
		var s := float(_interest.get(f.index, 0.0)) + _rng.randf() * 3.0
		s += (1.0 - f.health_frac()) * 6.0
		if f.time < f.juiced_until:
			s += 12.0
		if f.index == focus_index:
			s -= 4.0                 # prefer variety
		if s > best_s:
			best_s = s
			best = f.index
	if best >= 0:
		focus_index = best


## Focus pair for the camera: [focus position, opponent position or null]; [] = frame everyone.
func focus() -> Array:
	if shot == "wide" or not _framable(focus_index):
		return []
	var f := sim.fighters[focus_index]
	var other = f.target.pos() if f.target and not f.target.is_out() else null
	return [f.pos(), other]


## Points the camera should keep in frame for the current shot.
func points() -> Array:
	if shot == "wide" or not _framable(focus_index):
		return []
	var f := sim.fighters[focus_index]
	var pts := [f.pos()]
	if f.target and not f.target.is_out() and not f.target.despawned:
		pts.append(f.target.pos())
	return pts


func cycle_lock(step: int) -> void:
	var ids := []
	for f in sim.fighters:
		if not f.despawned:
			ids.append(f.index)
	if ids.is_empty():
		return
	if locked < 0:
		locked = ids[0] if step > 0 else ids[-1]
	else:
		var at := ids.find(locked)
		var nxt := at + step
		if nxt < 0 or nxt >= ids.size():
			locked = -1              # past either end: back to the auto director
		else:
			locked = ids[nxt]


func label() -> String:
	if locked >= 0 and locked < sim.fighters.size():
		return "Following %s" % sim.fighters[locked].display_name
	return "Auto director (%s)" % shot
