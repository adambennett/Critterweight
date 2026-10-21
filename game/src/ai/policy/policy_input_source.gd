class_name PolicyInputSource
extends InputSource
## Drives a fighter with a trained policy, in normal matches (fight / spectate / hosts) and in AI
## Lab training alike: the SAME encoder (PolicyObs, obs_v1), network (PolicyMLP) and decoder
## (PolicyActions, act_v1) are used everywhere, so what was learned is what plays.
##
## Every `decision_ticks` physics ticks (default 8 = 15 Hz) it encodes an observation, runs the
## network and picks a move class + button class (argmax, or sampled with a seeded RNG for
## stochastic policies); between decisions the action is repeated tick by tick. Decisions of
## several policy fighters are staggered by `phase` so their cost spreads over ticks.
## Instrumentation: decisions, total_usec, max_usec (inference budget, docs/AI_LAB.md).

var policy: PolicyData
var net: PolicyMLP
var encoder: PolicyObs
var mode := "argmax"
var temperature := 1.0
var rng := RandomNumberGenerator.new()
var decision_ticks := 8
var mask := PackedByteArray()
var label_text := ""
## Optional hook called after each decision: (obs: PackedFloat32Array, move: int, button: int)
var on_decision: Callable = Callable()

var decisions := 0
var total_usec := 0
var max_usec := 0
var encode_usec := 0
var forward_usec := 0
var last_logits := PackedFloat32Array()

var _phase := 0
var _window_tick := 0
var _window_len := 0
var _decided := false
var _move := 0
var _button := 0
var _prev_move := 0
var _prev_button := 0
var _move_vec := Vector3.ZERO
var _all_mask := PackedByteArray()


## A source for `p`. `phase` (e.g. the fighter index) staggers the decision tick.
static func create(p: PolicyData, seed_value: int, phase := 0) -> PolicyInputSource:
	var s := PolicyInputSource.new()
	s.setup(p, seed_value, phase)
	return s


func setup(p: PolicyData, seed_value: int, phase := 0) -> void:
	policy = p
	net = p.net
	net.compile()
	encoder = PolicyObs.new(p.target_lag)
	mode = p.act_mode
	temperature = p.temperature
	rng.seed = seed_value
	decision_ticks = PolicyActions.decision_ticks(p.decision_hz)
	_phase = posmod(phase * 3, decision_ticks)
	mask = p.button_mask.duplicate()
	if mask.size() != PolicyActions.BUTTON_COUNT:
		mask = PolicyActions.button_mask(null)
	_all_mask.resize(PolicyActions.MOVE_COUNT)
	_all_mask.fill(1)
	label_text = "AI: %s" % p.name if p.name != "" else "AI policy"


## Restricts the button head to what a creature can actually do (missing ability slots).
func apply_creature_mask(c: CreatureDef) -> void:
	var cm := PolicyActions.button_mask(c)
	for k in PolicyActions.BUTTON_COUNT:
		mask[k] = mask[k] & cm[k]


func label() -> String:
	return label_text


func reset() -> void:
	encoder.reset()
	_decided = false
	_window_tick = 0
	_prev_move = 0
	_prev_button = 0
	_move = 0
	_button = 0


func poll(f: Fighter, sim, _dt: float) -> void:
	if not _decided or _window_tick >= _window_len:
		_decide(f, sim)
	PolicyActions.apply_tick(f.input, _move_vec, _button, _prev_button, _window_tick)
	_window_tick += 1


func _decide(f: Fighter, sim) -> void:
	var t0 := Time.get_ticks_usec()
	if _decided:
		_prev_move = _move
		_prev_button = _button
	var obs := encoder.encode(f, sim as MatchSim, _prev_move, _prev_button)
	var t1 := Time.get_ticks_usec()
	var logits := net.forward(obs)
	var t2 := Time.get_ticks_usec()
	encode_usec += t1 - t0
	forward_usec += t2 - t1
	last_logits = logits
	_move = PolicyActions.choose(logits, 0, PolicyActions.MOVE_COUNT, _all_mask, mode, temperature, rng)
	_button = PolicyActions.choose(logits, PolicyActions.MOVE_COUNT, PolicyActions.BUTTON_COUNT, mask, mode, temperature, rng)
	var tp = f.target.pos() if f.target != null and not f.target.is_out() else null
	var fr := PolicyActions.frame(f, tp)
	_move_vec = PolicyActions.move_world(_move, fr[0], fr[1])
	_window_len = decision_ticks if _decided else maxi(1, decision_ticks - _phase)
	_window_tick = 0
	_decided = true
	var us := Time.get_ticks_usec() - t0
	decisions += 1
	total_usec += us
	max_usec = maxi(max_usec, us)
	if on_decision.is_valid():
		on_decision.call(obs, _move, _button)


func mean_decision_usec() -> float:
	return float(total_usec) / float(maxi(decisions, 1))


## MatchScene / server hook: an InputSource for a fighter entry {creature: CreatureDef,
## policy_id, difficulty}. Falls back to a scripted bot (and logs why) when the policy is
## missing, invalid or made for another fighter, so a match never fails to start.
## combat: the match's combat style. Policies (act_v1 / obs_v1) were learned on Classic inputs:
## in a Movesets match the fighter is played by the scripted bot instead (v0.9.18,
## docs/design/MOVESET_COMBAT.md §9), and the log says so.
static func for_match(entry: Dictionary, seed_value: int, index: int, combat := "classic") -> InputSource:
	var pid := str(entry.get("policy_id", ""))
	var c: CreatureDef = entry.get("creature") as CreatureDef
	var pol := PolicyLibrary.get_policy(pid)
	var why := PolicyLibrary.last_error(pid) if pol == null else PolicyLibrary.compatibility(pol, c.id if c != null else "")
	if why == "" and combat == "moves":
		why = "Lab policies play Classic combat; this match uses Movesets"
	if pol != null and why == "":
		var src := PolicyInputSource.create(pol, seed_value, index)
		src.apply_creature_mask(c)
		for w in PolicyLibrary.warnings_for(pol):
			Log.w("policy", w)
		return src
	Log.w("policy", "policy '%s' unavailable (%s); a scripted bot fights instead" % [pid, why])
	var bb := BotBrain.new(str(entry.get("difficulty", "regular")), seed_value)
	if c != null:
		bb.set_personality(c.ai)
	bb.label_text = "Bot (policy unavailable)"
	return bb
