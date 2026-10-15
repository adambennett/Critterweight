class_name LabRewards
extends RefCounted
## Objectives ("styles") for AI Lab training: episode reward = Σ weight[term] × raw[term].
## Raw terms are measured from the real simulation's event stream and state (never from
## anything the rules do not produce), so every style is learned under the same combat rules.
## Presets are starting points; the Lab UI exposes every term weight.
##
## Term meanings (per episode, from the learner's point of view):
##   damage_dealt / damage_taken   health removed (hits, chip, throws, slams, damage over time)
##   hits / hits_taken             clean (unblocked, unparried) damaging hits
##   blocks                        enemy hits stopped by our guard
##   parries / got_parried         parries we performed / parries the enemy performed on us
##   counter_hits                  our hits that interrupted an enemy windup
##   knockdowns_dealt / _taken     knockdowns of enemies / of us
##   throws, taunts, juice_used    actions performed
##   hype_gain                     hype meter gained (points)
##   approach                      metres closed toward the target while beyond 1.3 m (potential-
##                                 based shaping: it cannot be farmed by walking back and forth)
##   survival                      seconds not knocked out
##   win / loss / draw             round result (KO, or decision on health at the time limit)
##   ko_dealt / ko_taken           knockouts

const TERMS: PackedStringArray = ["damage_dealt", "damage_taken", "hits", "hits_taken", "blocks", "parries", "got_parried",
	"counter_hits", "knockdowns_dealt", "knockdowns_taken", "throws", "taunts", "hype_gain", "juice_used",
	"approach", "survival", "win", "loss", "draw", "ko_dealt", "ko_taken"]

const PRESETS := {
	"aggressive": {"name": "Aggressive: damage", "help": "Deal damage, land clean hits and knockdowns; taking hits matters less.",
		"weights": {"damage_dealt": 1.0, "damage_taken": -0.35, "hits": 0.5, "knockdowns_dealt": 3.0, "ko_dealt": 10.0, "win": 10.0, "loss": -5.0, "approach": 0.5}},
	"defensive": {"name": "Defensive: survival", "help": "Avoid damage: guard, parry and stay standing; win on health.",
		"weights": {"damage_taken": -1.2, "damage_dealt": 0.35, "blocks": 0.8, "parries": 3.0, "survival": 0.25, "win": 8.0, "loss": -15.0, "ko_taken": -10.0}},
	"technician": {"name": "Technician: parries & counters", "help": "Rewards parries, counter hits, throws and clean trades.",
		"weights": {"parries": 4.0, "counter_hits": 2.0, "blocks": 0.5, "throws": 2.0, "damage_dealt": 0.6, "damage_taken": -0.6, "got_parried": -1.5, "win": 10.0, "loss": -10.0}},
	"showboat": {"name": "Showboat: taunts & hype", "help": "Play to the crowd: taunt, build hype, pop JUICE — and still land some hits.",
		"weights": {"taunts": 2.0, "hype_gain": 0.15, "juice_used": 8.0, "damage_dealt": 0.5, "damage_taken": -0.3, "win": 6.0, "loss": -4.0}},
	"win_only": {"name": "Win only", "help": "Sparse: +10 for a win, -10 for a loss, nothing else. Hardest to learn from.",
		"weights": {"win": 10.0, "loss": -10.0}},
	"drill": {"name": "Drill: approach & hit", "help": "Controlled learning task: close the distance and land hits.",
		"weights": {"damage_dealt": 1.0, "hits": 1.0, "approach": 0.5}},
}

const ENGAGE_RANGE := 1.3


static func preset_ids() -> Array:
	return ["aggressive", "defensive", "technician", "showboat", "win_only", "drill"]


## Full weight dictionary (every term present) for a preset plus optional overrides.
static func weights_for(preset: String, overrides := {}) -> Dictionary:
	var w := {}
	for t in TERMS:
		w[t] = 0.0
	var p: Dictionary = PRESETS.get(preset, PRESETS["aggressive"])
	var pw: Dictionary = p["weights"]
	for k in pw:
		w[k] = float(pw[k])
	for k in overrides:
		if w.has(k) and typeof(overrides[k]) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(overrides[k])):
			w[k] = clampf(float(overrides[k]), -100.0, 100.0)
	return w


static func score(raw: Dictionary, weights: Dictionary) -> float:
	var s := 0.0
	for k in weights:
		s += float(weights[k]) * float(raw.get(k, 0.0))
	return s


## Accumulates raw terms for one learner during one episode.
class Tracker:
	extends RefCounted
	var me := 0
	var raw := {}
	var act_hist := PackedInt32Array()      ## decisions per move class (9) then button class (12)
	var _cursor := 0
	var _last_dist := -1.0
	var _tick := 0
	var _hype_prev := 0.0

	func _init() -> void:
		act_hist.resize(PolicyActions.OUTPUTS)

	func start(sim: MatchSim, learner_index: int) -> void:
		me = learner_index
		raw.clear()
		for t in LabRewards.TERMS:
			raw[t] = 0.0
		act_hist.resize(PolicyActions.OUTPUTS)
		act_hist.fill(0)
		_cursor = sim.event_seq
		_last_dist = -1.0
		_tick = 0
		_hype_prev = sim.fighters[me].hype

	func note_action(move: int, button: int) -> void:
		act_hist[move] += 1
		act_hist[PolicyActions.MOVE_COUNT + button] += 1

	func _enemy(sim: MatchSim, idx: int) -> bool:
		return idx >= 0 and idx < sim.fighters.size() and idx != me and sim.are_enemies(sim.fighters[me], sim.fighters[idx])

	## Call once per tick after sim.step().
	func update(sim: MatchSim, dt: float) -> void:
		_tick += 1
		var evs := sim.events
		var n := evs.size()
		var i := n - 1
		while i >= 0 and int(evs[i]["seq"]) > _cursor:
			i -= 1
		for j in range(i + 1, n):
			_on_event(sim, evs[j])
		_cursor = sim.event_seq
		var f := sim.fighters[me]
		if not f.is_out():
			raw["survival"] += dt
		var h := f.hype
		if h > _hype_prev:
			raw["hype_gain"] += h - _hype_prev
		_hype_prev = h
		if _tick % 8 == 0 and f.target != null and not f.target.is_out():
			var d := Vector2(f.target.pos().x - f.pos().x, f.target.pos().z - f.pos().z).length()
			if _last_dist >= 0.0:
				raw["approach"] += maxf(_last_dist, LabRewards.ENGAGE_RANGE) - maxf(d, LabRewards.ENGAGE_RANGE)
			_last_dist = d

	func _on_event(sim: MatchSim, ev: Dictionary) -> void:
		var who := int(ev.get("fighter", -1))
		match str(ev["type"]):
			"hit":
				var tgt := int(ev.get("target", -1))
				var dmg := float(ev.get("damage", 0.0))
				var blocked := bool(ev.get("blocked", false))
				var parried := bool(ev.get("parried", false))
				if who == me and _enemy(sim, tgt):
					raw["damage_dealt"] += dmg
					if not blocked and not parried and dmg > 0.0:
						raw["hits"] += 1.0
						if bool(ev.get("counter", false)):
							raw["counter_hits"] += 1.0
				elif tgt == me:
					raw["damage_taken"] += dmg
					if blocked:
						raw["blocks"] += 1.0
					elif not parried and dmg > 0.0:
						raw["hits_taken"] += 1.0
			"dot":
				if who == me:
					raw["damage_taken"] += float(ev.get("damage", 0.0))
				elif _enemy(sim, who):
					raw["damage_dealt"] += float(ev.get("damage", 0.0))
			"parry":
				if who == me:
					raw["parries"] += 1.0
				elif _enemy(sim, who):
					raw["got_parried"] += 1.0
			"knockdown":
				if who == me:
					raw["knockdowns_taken"] += 1.0
				elif _enemy(sim, who):
					raw["knockdowns_dealt"] += 1.0
			"ko":
				if who == me:
					raw["ko_taken"] += 1.0
				elif _enemy(sim, who):
					raw["ko_dealt"] += 1.0
			"throw":
				if who == me:
					raw["throws"] += 1.0
			"taunt":
				if who == me:
					raw["taunts"] += 1.0
			"juice":
				if who == me:
					raw["juice_used"] += 1.0

	## Records the round result. winner_team: team index, -1 draw, -2 undecided (decided here on health).
	func finish(sim: MatchSim, winner_team: int) -> String:
		var my_team := sim.fighters[me].team
		var w := winner_team
		if w == -2:
			var mine := 0.0
			var theirs := 0.0
			for f: Fighter in sim.fighters:
				if f.team == my_team:
					mine += f.health_frac()
				else:
					theirs += f.health_frac()
			w = -1 if absf(mine - theirs) < 0.001 else (my_team if mine > theirs else -3)
		var outcome := "draw"
		if w == my_team:
			outcome = "win"
			raw["win"] = 1.0
		elif w == -1:
			raw["draw"] = 1.0
		else:
			outcome = "loss"
			raw["loss"] = 1.0
		return outcome
