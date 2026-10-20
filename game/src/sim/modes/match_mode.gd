class_name MatchMode
extends RefCounted
## Base class for match rules logic. The default implementation is the standard format:
## round-based elimination (1v1, free-for-all or teams) with optional lives/respawns, co-op
## revives, ring-outs, round timer, decisions and sudden death. Bonus modes subclass this and
## override hooks. Phases: intro -> fight -> round_end -> (next round | match_end).
##
## Hooks for subclasses: tick_fight, on_depleted, on_elimination, on_ringout, choose_respawn,
## focus_point, on_grab_pressed, bot_objective, hud_status, hud_state, view_state, build_result.
## Hooks Fighter/Combat query: hit_allowed, auto_getup_time, down_regen_mult, unlimited_health,
## intercept_knockdown, intercept_actions.
##
## Officials (standard mode only, MCH-07/08): rules "scoring": "ten_point" adds a RoundJudge
## (three judges, 10-point must, effectively unlimited HP: every round is fought and the cards
## decide) and rules "referee": true a RefereeRules (knockdown count, no hits on a downed fighter,
## stoppage after RefereeRules.REF_KD_LIMIT knockdowns in a round). Both exist only for the
## standard mode (id() == "standard") and a two-sided duel (_setup_officials); otherwise both stay
## null and every path below is exactly the plain HP rules. Rules without the keys = HP, no
## referee. Under ten_point the round closes only at the bell or by a referee stoppage, through
## _ten_point_close (the one closing procedure), and end_round never derives the match winner
## from round wins.

enum Phase { INTRO, FIGHT, ROUND_END, MATCH_END }

const INTRO_TIME := 2.2
const ROUND_END_TIME := 3.0
const DECISION_TIME := 6.0     ## ROUND_END that ends a judged / refereed match (decision reveal, wave-off, hand raise)
const REVIVE_TIME := 2.0
const REVIVE_RANGE := 1.4

var sim: MatchSim
var rules := {}
var phase := Phase.INTRO
var phase_time := 0.0
var round_index := 0
var round_wins := {}           ## team -> wins
var round_timer := 0.0
var winner_team := -2          ## -2 undecided, -1 draw
var round_winner := -2
var scores := {}               ## team -> score (score-based modes; float)
var sudden_death := false
var _respawns: Array = []      ## [{fighter, at, pos(optional)}]
var _revive := {}              ## downed fighter index -> {progress, by}
var _downed_at := {}           ## fighter index -> time downed
var result := {}
var judge: RoundJudge = null    ## 10-point scoring (null = HP rules)
var referee: RefereeRules = null
var decision := {}              ## 10-point: the last judges_decision ({} until the cards decide)
var _sd_after_draw := false     ## 10-point: sudden death follows a drawn decision


func id() -> String:
	return "standard"


func display_name() -> String:
	return str(rules.get("name", "Standard"))


func setup(match_sim) -> void:
	sim = match_sim
	rules = sim.rules
	round_timer = float(rules.get("round_time", 99.0))
	for f: Fighter in sim.fighters:
		round_wins[f.team] = 0
		scores[f.team] = 0.0
		f.lives = initial_lives()
	_setup_officials()
	_begin_intro()


## Judges / referee from the rules, only for the standard mode and exactly two non-despawned
## fighters on two teams (rules are not validated for local play, so the sim checks itself).
func _setup_officials() -> void:
	if id() != "standard":
		return
	var ten := str(rules.get("scoring", "hp")) == "ten_point"
	var ref := bool(rules.get("referee", false))
	if not ten and not ref:
		return
	var teams_seen: Array[int] = []
	var n := 0
	for f: Fighter in sim.fighters:
		if f.despawned:
			continue
		n += 1
		if not teams_seen.has(f.team):
			teams_seen.append(f.team)
	var duel := n == 2 and teams_seen.size() == 2
	if ten and duel and float(rules.get("round_time", 99.0)) > 0.0:
		judge = RoundJudge.new(sim, teams_seen)
	if ref and duel:
		referee = RefereeRules.new(sim)
		if judge != null:
			judge.referee_on = true
	if (ten and judge == null) or (ref and referee == null):
		Log.w("sim", "10-point scoring / referee need a timed 1v1 duel (%d fighters, %d teams): playing plain HP rules" % [n, teams_seen.size()])


## True while 10-point scoring runs: damage never depletes (Fighter.receive_hit, on_depleted).
func unlimited_health() -> bool:
	return judge != null


func has_referee() -> bool:
	return referee != null


## Lives each fighter starts a round with. -1 = unlimited: score modes with respawn, presets that
## enable respawn without a lives count, and "lives": 0. An explicit positive count counts down.
func initial_lives() -> int:
	var respawn := bool(rules.get("respawn", false))
	if rules.has("lives"):
		var lv := int(rules["lives"])
		if lv <= 0:
			return -1 if respawn else 1
		return lv
	return -1 if respawn and str(rules.get("win", "ko")) == "score" else 1


func rounds_to_win() -> int:
	return int(ceil(float(rules.get("rounds", 3)) / 2.0))


func _begin_intro() -> void:
	phase = Phase.INTRO
	phase_time = 0.0
	sim.input_enabled = false
	sim.emit_event({"type": "round_intro", "round": round_index + 1})


func tick(dt: float) -> void:
	phase_time += dt
	if judge != null:
		_hold_full_health()
	match phase:
		Phase.INTRO:
			if phase_time >= float(rules.get("intro_time", INTRO_TIME)):
				phase = Phase.FIGHT
				phase_time = 0.0
				sim.input_enabled = true
				round_timer = float(rules.get("round_time", 99.0))
				sim.emit_event({"type": "round_start", "round": round_index + 1})
				for f in sim.fighters:
					if not f.despawned:
						f.hooks.fire("round_start", {})
				if judge != null:
					judge.begin_round()
				if referee != null:
					referee.begin_round(round_index + 1)
		Phase.FIGHT:
			# order: respawns, revives, mode logic, judges, sudden death, referee, timer (a
			# sudden-death clean hit wins before any stoppage is considered)
			_tick_respawns(dt)
			_tick_revives(dt)
			tick_fight(dt)
			if judge != null:
				judge.scan()
			if sudden_death:
				tick_sudden_death()
			if referee != null and phase == Phase.FIGHT:
				var stop := referee.tick(phase_time)
				if not stop.is_empty():
					referee_stoppage(stop)
			# (with officials, a round the referee just stopped never also times out)
			var live := phase == Phase.FIGHT or (judge == null and referee == null)
			if live and float(rules.get("round_time", 99.0)) > 0.0 and not sudden_death:
				round_timer -= dt
				if round_timer <= 0.0:
					round_timer = 0.0
					on_timeout()
		Phase.ROUND_END:
			var wait := ROUND_END_TIME
			if winner_team != -2 and (judge != null or referee != null):
				wait = DECISION_TIME
			if phase_time >= wait:
				if winner_team != -2:
					phase = Phase.MATCH_END
					phase_time = 0.0
					sim.emit_event({"type": "match_end", "winner": winner_team})
					sim.finish(build_result())
				else:
					round_index += 1
					sudden_death = false
					sim.reset_round()
					_begin_intro()
		Phase.MATCH_END:
			pass


## Per-tick mode logic during the fight phase (bonus modes override).
func tick_fight(_dt: float) -> void:
	pass


## 10-point scoring: HP never visibly or mechanically drops (no low-HP hooks, AI or announcer).
func _hold_full_health() -> void:
	for f: Fighter in sim.fighters:
		if not f.despawned and f.health < f.max_health:
			f.health = f.max_health


## Called when a fighter's health is depleted: KO, downed (revivable) or respawn.
func on_depleted(f: Fighter, attacker: Fighter, hit: Dictionary) -> void:
	if judge != null:
		# 10-point scoring: nobody is knocked out by damage (DoT, self damage, ring-outs land here)
		f.health = f.max_health
		sim.emit_event({"type": "unlimited_refill", "fighter": f.index})
		return
	# a fighter who fell off the arena is never left "downed" out there (nobody could reach them)
	if bool(rules.get("revive", false)) and not bool(hit.get("ringout", false)) and _team_has_standing_ally(f):
		f.set_downed()
		_downed_at[f.index] = sim.time
		return
	eliminate(f, attacker)


## The one elimination path (KO, ring-out KO, bleed-out): stats, events, score hook, lives,
## respawn queue and the round check.
func eliminate(f: Fighter, attacker: Fighter) -> void:
	if f.state != Fighter.State.KO:
		f.knock_out(attacker)
	if referee != null and phase == Phase.FIGHT:
		referee.note_ko(f)   # a KO under a referee is waved off like a stoppage (presentation)
	if attacker and attacker != f:
		attacker.stats_record["kos"] += 1
	sim.emit_event({"type": "elimination", "fighter": f.index, "by": attacker.index if attacker else -1})
	on_elimination(f, attacker)
	if f.lives > 0:
		f.lives -= 1
	if bool(rules.get("respawn", false)) and (f.lives != 0):
		queue_respawn(f, float(rules.get("respawn_delay", 3.0)))
	check_round_over()


func queue_respawn(f: Fighter, delay: float, at = null) -> void:
	_respawns.append({"fighter": f, "at": sim.time + delay, "pos": at})


## Ring-out default (ARENAS.md §1): 8% max HP, out for 2.5 s, respawn near the fall point.
func on_ringout(f: Fighter, attacker: Fighter) -> void:
	if judge != null and phase == Phase.FIGHT:
		judge.note_ringout(f, attacker)
	var dmg := f.max_health * float(rules.get("ringout_damage", 0.08))
	if bool(rules.get("ringout_eliminates", false)) or f.health - dmg <= 0.0:
		f.health = 0.0
		on_depleted(f, attacker, {"ringout": true})
		if f.health > 0.0 and not f.is_out():
			# the mode refilled the fighter (practice, tutorial): bring them back like a normal ring-out
			_ringout_return(f)
		elif not f.is_out():
			f.knock_out(attacker)
		return
	f.health -= dmg
	_ringout_return(f)


func _ringout_return(f: Fighter) -> void:
	f.set_inactive(true)
	var p := f.pos()
	var back := sim.clamp_to_arena(Vector3(p.x, 0.0, p.z), 1.6)
	queue_respawn(f, float(rules.get("ringout_out_time", 2.5)), back)
	sim.emit_event({"type": "ringout_respawn_pending", "fighter": f.index})


## Hook for score modes (e.g. KO counts).
func on_elimination(_f: Fighter, attacker: Fighter) -> void:
	if attacker and str(rules.get("win", "ko")) == "score":
		scores[attacker.team] = float(scores.get(attacker.team, 0.0)) + float(rules.get("ko_points", 1.0))


func on_round_reset() -> void:
	if referee != null:
		referee.on_round_reset()
	_respawns.clear()
	_revive.clear()
	_downed_at.clear()
	# scores are per round (round wins carry the match)
	for t in scores:
		scores[t] = 0.0
	for f: Fighter in sim.fighters:
		if not f.despawned:
			f.lives = initial_lives()


func _team_has_standing_ally(f: Fighter) -> bool:
	for o: Fighter in sim.fighters:
		if o != f and o.team == f.team and not o.is_out() and not o.despawned:
			return true
	return false


## Where a fighter respawns. Bonus modes override (e.g. far from the objective).
func choose_respawn(f: Fighter) -> Array:
	return sim.safe_spawn_for(f)


func _tick_respawns(_dt: float) -> void:
	for r in _respawns.duplicate():
		if sim.time >= float(r["at"]):
			_respawns.erase(r)
			var f: Fighter = r["fighter"]
			if phase == Phase.FIGHT and not f.despawned:
				var sp: Array = choose_respawn(f)
				if r["pos"] != null:
					sp = [r["pos"], f.facing_yaw]
				f.respawn(sp[0], sp[1])
				sim.emit_event({"type": "respawn", "fighter": f.index})


## Co-op revives: an ally holding Grab next to a downed fighter for REVIVE_TIME revives them;
## downed fighters bleed out after `downed_time` seconds (default 15).
func _tick_revives(dt: float) -> void:
	if _downed_at.is_empty():
		return
	var bleed := float(rules.get("downed_time", 15.0))
	for idx in _downed_at.keys():
		var f := sim.fighters[idx]
		if f.state != Fighter.State.DOWNED:
			_downed_at.erase(idx)
			_revive.erase(idx)
			continue
		var reviver: Fighter = null
		for o: Fighter in sim.fighters:
			if o == f or o.team != f.team or o.is_out() or o.despawned:
				continue
			if o.pos().distance_to(f.pos()) <= REVIVE_RANGE and o.input.is_held(FighterInput.GRAB) and o.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD]:
				reviver = o
				break
		var r: Dictionary = _revive.get(idx, {"progress": 0.0, "by": -1})
		if reviver:
			r["progress"] = float(r["progress"]) + dt * float(reviver.mods.get("revive_speed", 1.0))
			r["by"] = reviver.index
			reviver.rig.desired_vel = Vector3.ZERO
			if float(r["progress"]) >= REVIVE_TIME:
				_revive.erase(idx)
				_downed_at.erase(idx)
				f.revive(float(rules.get("revive_health", 0.35)))
				sim.emit_event({"type": "revived_by", "fighter": f.index, "by": reviver.index})
				continue
		else:
			r["progress"] = maxf(0.0, float(r["progress"]) - dt * 2.0)
		_revive[idx] = r
		if sim.time - float(_downed_at[idx]) > bleed:
			_downed_at.erase(idx)
			_revive.erase(idx)
			sim.emit_event({"type": "bled_out", "fighter": f.index})
			eliminate(f, sim.last_attacker_of(f))


func revive_progress(f: Fighter) -> float:
	return float(_revive.get(f.index, {}).get("progress", 0.0)) / REVIVE_TIME


func downed_time_left(f: Fighter) -> float:
	if not _downed_at.has(f.index):
		return 0.0
	return maxf(0.0, float(rules.get("downed_time", 15.0)) - (sim.time - float(_downed_at[f.index])))


func alive_teams() -> Array:
	var teams := []
	for f: Fighter in sim.fighters:
		if f.despawned:
			continue
		if f.is_out() and not _pending_respawn(f):
			continue
		if not teams.has(f.team):
			teams.append(f.team)
	return teams


## Beaten for this round: KO'd, downed or inactive and NOT about to come back. A ring-out parks
## the fighter (inactive) until its respawn, which must not read as a loss in round-over checks.
func is_beaten(f: Fighter) -> bool:
	return f.despawned or (f.is_out() and not _pending_respawn(f))


func _pending_respawn(f: Fighter) -> bool:
	for r in _respawns:
		if r["fighter"] == f:
			return true
	return false


func check_round_over() -> void:
	if phase != Phase.FIGHT:
		return
	if judge != null:
		return   # 10-point: nobody is knocked out; the bell or the referee ends a round
	if str(rules.get("win", "ko")) == "score":
		var target := float(rules.get("score_target", 5))
		for t in scores:
			if float(scores[t]) >= target:
				end_round(int(t))
				return
	var teams := alive_teams()
	if teams.size() <= 1:
		end_round(teams[0] if teams.size() == 1 else -1)


func on_timeout() -> void:
	if judge != null:
		_ten_point_close({})
		return
	# decision: score first (score modes), then remaining health fraction per team
	var totals := {}
	for f: Fighter in sim.fighters:
		if f.despawned:
			continue
		var v := float(scores.get(f.team, 0.0)) * 1000.0
		if not f.is_out():
			v += f.health_frac() * 100.0 + float(maxi(f.lives, 0)) * 100.0
		totals[f.team] = float(totals.get(f.team, 0.0)) + v
	var best := -1
	var best_v := -INF
	var tie := false
	for t in totals:
		if totals[t] > best_v + 0.001:
			best_v = totals[t]
			best = t
			tie = false
		elif absf(totals[t] - best_v) <= 0.001:
			tie = true
	sim.emit_event({"type": "timeout"})
	if tie and bool(rules.get("sudden_death", true)):
		start_sudden_death()
		return
	end_round(-1 if tie else best)


## Tie-breaker: the next clean hit wins (standard); bonus modes override. After drawn cards
## (10-point) every fighter takes part, including one away after a ring-out.
func start_sudden_death() -> void:
	sudden_death = true
	sim.emit_event({"type": "sudden_death"})
	for f: Fighter in sim.fighters:
		if not f.despawned and (not f.is_out() or judge != null):
			f.hooks.add({"on": "hit_dealt", "do": [{"type": "set_flag", "flag": "sudden_death_winner", "seconds": 999.0}]}, "sudden_death")


func tick_sudden_death() -> void:
	tick_sudden_death_standard()


func tick_sudden_death_standard() -> void:
	for f: Fighter in sim.fighters:
		if f.has_flag("sudden_death_winner"):
			if judge != null and _sd_after_draw:
				_ten_point_sudden_death_won(f.team)
			else:
				end_round(f.team)
			return


func end_round(team: int) -> void:
	if phase != Phase.FIGHT:
		return
	if judge != null:
		_close_round(team, team)
		return
	if referee != null:
		referee.close_round()
	phase = Phase.ROUND_END
	phase_time = 0.0
	round_winner = team
	sim.input_enabled = false
	for f in sim.fighters:
		if not f.despawned:
			f.hooks.remove_source("sudden_death")
	if team >= 0:
		round_wins[team] = int(round_wins.get(team, 0)) + 1
		for f: Fighter in sim.fighters:
			if f.team == team and not f.despawned:
				f.celebrate()
	var total_rounds := int(rules.get("rounds", 3))
	if team >= 0 and int(round_wins[team]) >= rounds_to_win():
		winner_team = team
	elif round_index + 1 >= total_rounds * 2:
		winner_team = _most_round_wins()
	# "decided": this round_end also decides the bout (presentation: the booth calls a KO that ends
	# the fight differently from one that only takes a round). Emitted after the decision, same tick.
	sim.emit_event({"type": "round_end", "winner": team, "round": round_index + 1, "decided": winner_team != -2})


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


# =====================================================================================
# 10-point scoring and the referee (judge / referee are null for every other match)
# =====================================================================================

## ROUND_END without any best-of logic (10-point): `team` celebrates and is the round_end winner,
## `credit` gets the round win on the cards (round_wins is display-only under 10-point).
func _close_round(team: int, credit: int) -> void:
	if phase != Phase.FIGHT:
		return
	if referee != null:
		referee.close_round()
	phase = Phase.ROUND_END
	phase_time = 0.0
	round_winner = team
	sim.input_enabled = false
	for f in sim.fighters:
		if not f.despawned:
			f.hooks.remove_source("sudden_death")
	if credit >= 0:
		round_wins[credit] = int(round_wins.get(credit, 0)) + 1
	if team >= 0:
		for f: Fighter in sim.fighters:
			if f.team == team and not f.despawned:
				f.celebrate()
	sim.emit_event({"type": "round_end", "winner": team, "round": round_index + 1})


## The one closing procedure of a judged round, at the bell (stoppage {}) or on a referee
## stoppage: score the round, then end the match (stoppage, last round with a winner or a draw
## without sudden death), start sudden death (drawn cards with sudden_death on: no round_end, the
## phase stays FIGHT with the timer at 0) or move on to the next round.
func _ten_point_close(stoppage: Dictionary) -> void:
	if phase != Phase.FIGHT or judge == null or not judge.counting:
		return
	if referee != null:
		referee.close_round()
	var card := judge.score_round(round_index + 1, stoppage)
	if stoppage.is_empty():
		sim.emit_event({"type": "timeout"})
	var ev := card.duplicate(true)
	ev["type"] = "round_scored"
	ev["totals"] = judge.totals()
	sim.emit_event(ev)
	var credit := int(card["winner"])
	if not stoppage.is_empty():
		var by := int(stoppage.get("by", -1))
		var wt: int = sim.fighters[by].team if by >= 0 and by < sim.fighters.size() else -1
		winner_team = wt
		_emit_decision(wt, "TKO", judge.judges_leaning(), stoppage)
		_close_round(wt, credit)
		return
	if round_index + 1 >= int(rules.get("rounds", 3)):
		var d := judge.decide()
		var w := int(d["winner"])
		if w >= 0:
			winner_team = w
			_emit_decision(w, str(d["method"]), d["judges"], {})
			_close_round(w, credit)
		elif bool(rules.get("sudden_death", true)):
			_emit_decision(-1, str(d["method"]), d["judges"], {})
			_sd_after_draw = true
			if credit >= 0:
				round_wins[credit] = int(round_wins.get(credit, 0)) + 1
			start_sudden_death()
		else:
			winner_team = -1
			_emit_decision(-1, str(d["method"]), d["judges"], {})
			_close_round(-1, credit)
		return
	_close_round(credit, credit)


## The sudden death after drawn cards was won by `team` (its clean hit).
func _ten_point_sudden_death_won(team: int) -> void:
	winner_team = team
	_emit_decision(team, "Sudden Death (after a %s)" % str(decision.get("method", "Draw")), decision.get("judges", [-1, -1, -1]), {})
	_close_round(team, -1)


## A judges_decision event (and `decision`): {winner (team | -1), method, totals [[A,B] x3],
## judges [team | -1 x3], teams [ta, tb]}.
func _emit_decision(winner: int, method: String, judges_view: Array, stoppage: Dictionary) -> void:
	decision = {"winner": winner, "method": method, "totals": judge.totals(), "judges": judges_view.duplicate(),
		"teams": [judge.teams[0], judge.teams[1]], "stoppage": stoppage.duplicate()}
	var ev := decision.duplicate(true)
	ev.erase("stoppage")
	ev["type"] = "judges_decision"
	sim.emit_event(ev)


## The referee stopped the fight (RefereeRules.tick): 10-point ends the match with the partial
## round scored (T.K.O.); Health scoring ends the round like a KO and best-of continues.
func referee_stoppage(stop: Dictionary) -> void:
	if phase != Phase.FIGHT:
		return
	if judge != null:
		_ten_point_close(stop)
		return
	var by := int(stop.get("by", -1))
	end_round(sim.fighters[by].team if by >= 0 and by < sim.fighters.size() else -1)


## Whether an opponent's hit on `b` may land (Combat.deliver / apply_simple_damage). The referee
## keeps every opponent hit off a downed fighter, in every phase.
func hit_allowed(a: Fighter, b: Fighter, _h: Dictionary) -> bool:
	if referee != null:
		return referee.hit_allowed(a, b)
	return true


## Seconds a fighter in DOWN waits before the automatic get-up (Fighter._st_down). A referee's
## count waits RefereeRules.REF_KD_STAY while the round is live.
func auto_getup_time(f: Fighter) -> float:
	var normal := Tuning.v("knockdown_auto_getup") / f.getup_speed_mult()
	if referee != null and phase == Phase.FIGHT:
		return referee.auto_getup_time(f, normal)
	return normal


## Stamina regeneration multiplier while a fighter stays DOWN (Fighter._update_timers).
func down_regen_mult(f: Fighter) -> float:
	if referee != null and phase == Phase.FIGHT:
		return referee.down_regen_mult(f)
	return 1.0


## Plain-data 10-point result block (see build_result), {} without a judge.
func scoring_result() -> Dictionary:
	if judge == null:
		return {}
	var stop: Dictionary = decision.get("stoppage", {})
	var method := str(decision.get("method", ""))
	if method == "":
		method = "No decision"
	return {"mode": "ten_point", "method": method, "winner": int(decision.get("winner", -1)),
		"teams": [judge.teams[0], judge.teams[1]], "cards": judge.cards.duplicate(true), "totals": judge.totals(),
		"judges": RoundJudge.JUDGE_NAMES.duplicate(), "stoppage": stop.duplicate(true), "sudden_death": _sd_after_draw}


func build_result() -> Dictionary:
	var per := []
	for f: Fighter in sim.fighters:
		if f.despawned and not f.flags.get("keep_in_results", false):
			continue
		per.append({"index": f.index, "team": f.team, "creature": f.creature.id, "name": f.display_name,
			"stats": f.stats_record.duplicate(), "health": f.health, "out": f.is_out(), "kind": f.controller_kind})
	result = {"mode": id(), "winner_team": winner_team, "round_wins": round_wins.duplicate(), "scores": scores.duplicate(),
		"rounds": round_index + 1, "fighters": per, "time": sim.time}
	if judge != null:
		result["scoring"] = scoring_result()
	if referee != null:
		result["referee"] = {"stoppages": referee.stoppages.duplicate(true)}
	return result


## Objective point a fighter should face instead of the nearest enemy (null = none).
func focus_point(_f: Fighter):
	return null


## Lets a mode consume buffered presses before the fighter acts (e.g. a ball carrier's attack
## buttons throw the ball). Return true if the fighter should not act this tick.
func intercept_actions(_f: Fighter) -> bool:
	return false


## Lets a mode consume a Grab press (e.g. pick up the ball). Return true if handled.
func on_grab_pressed(_f: Fighter) -> bool:
	return false


## HUD: one-line objective/score text.
func hud_status() -> String:
	if sudden_death:
		return "SUDDEN DEATH — next clean hit wins"
	return ""


## HUD: structured score rows [{label, value, team, highlight}] for the scoreboard widget.
## 10-point adds "cards": {"n": rounds scored, "t": judges' running totals [[A,B] x3]} (teams
## ascending) and "sd": true while a sudden death follows drawn cards, and leaves out the
## duplicate "status" (hud_status() has it): duel snapshots stay < 400 B.
func hud_state() -> Dictionary:
	var rows := []
	if str(rules.get("win", "ko")) == "score":
		for t in scores:
			rows.append({"label": TeamColors.name(int(t)), "value": int(scores[t]), "team": int(t)})
	var hs := {"rows": rows, "status": hud_status()}
	if judge != null:
		# the status text already travels once per snapshot (NetHudMirror puts it back here)
		hs.erase("status")
		hs["cards"] = {"n": judge.cards.size(), "t": judge.totals()}
		if sudden_death and _sd_after_draw:
			hs["sd"] = true
	return hs


## Presentation state for ModeView (positions of lights, balls, gates...). Must be plain data
## so it can be replicated to network clients. With a referee, "referee" is present only while
## something is happening: {"count": {fighter, n, left}, "stop": loser index, "wave_off": true}.
func view_state() -> Dictionary:
	var downed := []
	for idx in _downed_at:
		var f := sim.fighters[idx]
		downed.append({"fighter": idx, "left": downed_time_left(f), "revive": revive_progress(f)})
	var v := {"mode": id(), "downed": downed}
	if referee != null:
		var rv := referee.view()
		if not rv.is_empty():
			v["referee"] = rv
	return v


## Bot helper: where should this fighter go / what should it prioritise (empty = just fight).
func bot_objective(_f: Fighter) -> Dictionary:
	# a referee wants the attacker off a downed opponent: step back and wait
	if referee != null:
		var back := referee.back_off_objective(_f)
		if not back.is_empty():
			return back
	# revive downed allies when nobody else is
	for idx in _downed_at:
		var d := sim.fighters[idx]
		if d.team == _f.team and d != _f and d.pos().y > -0.5 and sim.arena.inside(d.pos(), -0.3):
			return {"pos": d.pos(), "engage": 1.0, "hold": "grab", "radius": REVIVE_RANGE * 0.7}
	return {}


## Called by Fighter.knock_down before a knockdown happens. Return true to cancel it (the mode
## then applies its own reaction, e.g. a boss's Dazed state). reason: poise|move|throw|hit.
func intercept_knockdown(_f: Fighter, _reason: String, _by: Fighter) -> bool:
	return false
