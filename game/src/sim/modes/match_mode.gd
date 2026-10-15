class_name MatchMode
extends RefCounted
## Base class for match rules logic. The default implementation is the standard format:
## round-based elimination (1v1, free-for-all or teams) with optional lives (stocks),
## respawns, revives, round timer and decisions. Bonus modes subclass this and override hooks.
##
## Phases: intro -> fight -> round_end -> (next round | match_end).

enum Phase { INTRO, FIGHT, ROUND_END, MATCH_END }

const INTRO_TIME := 2.2
const ROUND_END_TIME := 3.0

var sim: MatchSim
var rules := {}
var phase := Phase.INTRO
var phase_time := 0.0
var round_index := 0
var round_wins := {}           ## team -> wins
var round_timer := 0.0
var winner_team := -2          ## -2 undecided, -1 draw
var round_winner := -2
var scores := {}               ## team -> score (score-based modes)
var _respawns: Array = []      ## [{fighter, at}]
var result := {}


func id() -> String:
	return "standard"


func setup(match_sim) -> void:
	sim = match_sim
	rules = sim.rules
	round_timer = float(rules.get("round_time", 99.0))
	for f: Fighter in sim.fighters:
		round_wins[f.team] = 0
		scores[f.team] = 0
		f.lives = int(rules.get("lives", 1))
	_begin_intro()


func rounds_to_win() -> int:
	return int(ceil(float(rules.get("rounds", 3)) / 2.0))


func _begin_intro() -> void:
	phase = Phase.INTRO
	phase_time = 0.0
	sim.input_enabled = false
	sim.emit_event({"type": "round_intro", "round": round_index + 1})


func tick(dt: float) -> void:
	phase_time += dt
	match phase:
		Phase.INTRO:
			if phase_time >= INTRO_TIME:
				phase = Phase.FIGHT
				phase_time = 0.0
				sim.input_enabled = true
				round_timer = float(rules.get("round_time", 99.0))
				sim.emit_event({"type": "round_start", "round": round_index + 1})
		Phase.FIGHT:
			_tick_respawns(dt)
			tick_fight(dt)
			if float(rules.get("round_time", 99.0)) > 0.0:
				round_timer -= dt
				if round_timer <= 0.0:
					round_timer = 0.0
					on_timeout()
		Phase.ROUND_END:
			if phase_time >= ROUND_END_TIME:
				if winner_team != -2:
					phase = Phase.MATCH_END
					phase_time = 0.0
					sim.emit_event({"type": "match_end", "winner": winner_team})
					sim.finish(build_result())
				else:
					round_index += 1
					sim.reset_round()
					_begin_intro()
		Phase.MATCH_END:
			pass


## Per-tick mode logic during the fight phase (bonus modes override).
func tick_fight(_dt: float) -> void:
	pass


## Called when a fighter's health is depleted. Returns nothing; decides KO/downed/respawn.
func on_depleted(f: Fighter, attacker: Fighter, _hit: Dictionary) -> void:
	if bool(rules.get("revive", false)) and _team_has_standing_ally(f):
		f.set_downed()
		return
	f.knock_out()
	if attacker and attacker != f:
		attacker.stats_record["kos"] += 1
	sim.emit_event({"type": "elimination", "fighter": f.index, "by": attacker.index if attacker else -1})
	on_elimination(f, attacker)
	if f.lives > 0:
		f.lives -= 1
	if bool(rules.get("respawn", false)) and (f.lives != 0):
		_respawns.append({"fighter": f, "at": sim.time + float(rules.get("respawn_delay", 3.0))})
	check_round_over()


## Hook for score modes (e.g. KO counts).
func on_elimination(_f: Fighter, attacker: Fighter) -> void:
	if attacker and str(rules.get("win", "ko")) == "score":
		scores[attacker.team] = int(scores.get(attacker.team, 0)) + 1


func _team_has_standing_ally(f: Fighter) -> bool:
	for o: Fighter in sim.fighters:
		if o != f and o.team == f.team and not o.is_out():
			return true
	return false


func _tick_respawns(_dt: float) -> void:
	for r in _respawns.duplicate():
		if sim.time >= float(r["at"]):
			_respawns.erase(r)
			var f: Fighter = r["fighter"]
			if phase == Phase.FIGHT:
				var sp: Array = sim.safe_spawn_for(f)
				f.respawn(sp[0], sp[1])
				sim.emit_event({"type": "respawn", "fighter": f.index})


func alive_teams() -> Array:
	var teams := []
	for f: Fighter in sim.fighters:
		if f.is_out() and not _pending_respawn(f):
			continue
		if not teams.has(f.team):
			teams.append(f.team)
	return teams


func _pending_respawn(f: Fighter) -> bool:
	for r in _respawns:
		if r["fighter"] == f:
			return true
	return false


func check_round_over() -> void:
	if phase != Phase.FIGHT:
		return
	if str(rules.get("win", "ko")) == "score":
		var target := int(rules.get("score_target", 5))
		for t in scores:
			if int(scores[t]) >= target:
				end_round(int(t))
				return
	var teams := alive_teams()
	if teams.size() <= 1:
		end_round(teams[0] if teams.size() == 1 else -1)


func on_timeout() -> void:
	# decision: score first (score modes), then remaining health fraction per team
	var best := -1
	var best_v := -INF
	var tie := false
	var totals := {}
	for f: Fighter in sim.fighters:
		var v := float(scores.get(f.team, 0)) * 1000.0
		if not f.is_out():
			v += f.health_frac() * 100.0 + float(f.lives) * 100.0
		totals[f.team] = float(totals.get(f.team, 0.0)) + v
	for t in totals:
		if totals[t] > best_v + 0.001:
			best_v = totals[t]
			best = t
			tie = false
		elif absf(totals[t] - best_v) <= 0.001:
			tie = true
	sim.emit_event({"type": "timeout"})
	end_round(-1 if tie else best)


func end_round(team: int) -> void:
	if phase != Phase.FIGHT:
		return
	phase = Phase.ROUND_END
	phase_time = 0.0
	round_winner = team
	sim.input_enabled = false
	if team >= 0:
		round_wins[team] = int(round_wins.get(team, 0)) + 1
		for f: Fighter in sim.fighters:
			if f.team == team:
				f.celebrate()
	sim.emit_event({"type": "round_end", "winner": team, "round": round_index + 1})
	var total_rounds := int(rules.get("rounds", 3))
	if team >= 0 and int(round_wins[team]) >= rounds_to_win():
		winner_team = team
	elif round_index + 1 >= total_rounds * 2:
		winner_team = _most_round_wins()


func _most_round_wins() -> int:
	var best := -1
	var bv := -1
	var tie := false
	for t in round_wins:
		if int(round_wins[t]) > bv:
			bv = int(round_wins[t])
			best = int(t)
			tie = false
		elif int(round_wins[t]) == bv:
			tie = true
	return -1 if tie else best


func build_result() -> Dictionary:
	var per := []
	for f: Fighter in sim.fighters:
		per.append({"index": f.index, "team": f.team, "creature": f.creature.id, "name": f.display_name,
			"stats": f.stats_record.duplicate(), "health": f.health, "out": f.is_out()})
	result = {"mode": id(), "winner_team": winner_team, "round_wins": round_wins.duplicate(), "scores": scores.duplicate(),
		"rounds": round_index + 1, "fighters": per, "time": sim.time}
	return result


## HUD helper: short text describing the objective/score for this mode.
func hud_status() -> String:
	return ""


## Bot helper: where should this fighter go / what should it prioritize (null = just fight).
func bot_objective(_f: Fighter) -> Dictionary:
	return {}


## Called by Fighter.knock_down before a knockdown happens. Return true to cancel it (the mode
## then applies its own reaction, e.g. a boss's Dazed state). reason: poise|move|throw|hit.
func intercept_knockdown(_f: Fighter, _reason: String, _by: Fighter) -> bool:
	return false
