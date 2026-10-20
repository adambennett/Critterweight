extends TestCase
## MCH-08: the referee's gameplay rules (rules "referee": true, RefereeRules): no opponent hit
## lands on a downed fighter, strike knockdowns are counted (ref_count) and a fighter who stays
## down is waved back up at the count (getup.forced + ref_wave_up), bots back off a downed
## opponent, and REF_KD_LIMIT knockdowns in one round stop the fight (10-point: the match, T.K.O.;
## Health scoring: the round, best-of continues). Throw / hazard knockdowns are never counted, and
## nothing is counted outside the live round.
## Run: godot --headless --path game --fixed-fps 120 -- --test test_referee_rules

const CAGE := {"mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "rounds": 3, "round_time": 40.0,
	"intro_time": 0.3, "win": "ko", "lives": 1, "sudden_death": true, "scoring": "ten_point", "referee": true}


func _rules(over := {}) -> Dictionary:
	var r := CAGE.duplicate(true)
	r.merge(over, true)
	return r


func _duel(rules: Dictionary, sources := [null, null], seed_value := 13) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var entries := []
	for i in 2:
		entries.append({"creature": Content.creature("dev_biped"), "team": i, "source": sources[i], "kind": "bot" if sources[i] else "dummy"})
	sim.setup({"arena": Content.arena("the_gullet"), "rules": rules, "seed": seed_value, "fighters": entries, "mode": ModeRegistry.create("standard")})
	return sim


func _run(sim: MatchSim, seconds: float, log: Dictionary, until: Callable = Callable(), each: Callable = Callable()) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	if not log.has("events"):
		log["events"] = []
		log["cur"] = 0
	for i in int(seconds / dt):
		sim.step(dt)
		for ev in sim.events_since(int(log["cur"])):
			(log["events"] as Array).append(ev)
			log["cur"] = int(ev["seq"])
		if each.is_valid():
			each.call()
		await get_tree().physics_frame
		if sim.is_finished or (until.is_valid() and bool(until.call())):
			return


func _of(log: Dictionary, type: String) -> Array:
	return (log.get("events", []) as Array).filter(func(e): return str(e["type"]) == type)


## Gets straight back up whenever it is down (a player pressing a direction).
func _riser() -> InputSource:
	return InputSource.Scripted.new([{"t0": 0.0, "t1": 999.0, "move": Vector3(0.8, 0.0, 0.0)}])


func _knock(sim: MatchSim, victim: int, by: int, log: Dictionary) -> void:
	# wait until the victim stands (a fresh knockdown, not one stacked on the last)
	await _run(sim, 6.0, log, func(): return sim.fighters[victim].state in [Fighter.State.NEUTRAL, Fighter.State.GUARD])
	sim.fighters[victim].knock_down("poise", sim.fighters[by])


func test_downed_fighter_is_protected_counted_and_waved_up() -> void:
	var bot := BotBrain.new("champion", 9)
	var sim := _duel(_rules(), [bot, null])
	var log := {}
	var b := sim.fighters[0]
	var d := sim.fighters[1]
	await _run(sim, 8.0, log, func(): return sim.mode.phase == MatchMode.Phase.FIGHT and b.pos().distance_to(d.pos()) < 1.6 and not d.is_down())
	check(b.pos().distance_to(d.pos()) < 1.6, "the bot closed in")
	d.knock_down("poise", b)   # the bot's knockdown blow
	var t_kd := sim.time
	var kd_tick := sim.tick_count
	var far := [false]
	var count_seen := [false]
	var each := func():
		if d.is_down():
			if sim.time - t_kd <= 1.5 and b.pos().distance_to(d.pos()) >= 2.0:
				far[0] = true
			var vs := sim.mode.view_state()
			if vs.has("referee") and (vs["referee"] as Dictionary).has("count"):
				count_seen[0] = true
	await _run(sim, 9.0, log, func(): return d.state == Fighter.State.NEUTRAL, each)
	var kd: Array = _of(log, "knockdown")
	check(not kd.is_empty() and int(kd[-1]["by"]) == 0, "knockdown attributed to the bot: %s" % str(kd))
	check(bool(far[0]), "the bot backed off >= 2 m within 1.5 s")
	var ups := _of(log, "getup")
	var up_tick: int = int(ups[-1]["tick"]) if not ups.is_empty() else sim.tick_count
	var landed := (log["events"] as Array).filter(func(e): return str(e["type"]) == "hit" and int(e["target"]) == 1 \
		and int(e["tick"]) > kd_tick and int(e["tick"]) <= up_tick and float(e["damage"]) > 0.0)
	check_eq(landed.size(), 0, "no hit landed while the dummy was down: %s" % str(landed))
	var counts := _of(log, "ref_count")
	check(counts.size() >= 4, "the referee counts while it stays down (%d)" % counts.size())
	for i in counts.size():
		check_eq(int(counts[i]["n"]), i + 1, "count %d" % (i + 1))
		check_eq(int(counts[i]["fighter"]), 1)
	check(bool(count_seen[0]), "view_state.referee.count while counting")
	check(not ups.is_empty() and bool(ups[-1].get("forced", false)), "the dummy was waved up (getup.forced)")
	check_eq(_of(log, "ref_wave_up").size(), 1, "ref_wave_up")
	var t_up := float(up_tick - kd_tick) / Engine.physics_ticks_per_second
	check(t_up >= RefereeRules.REF_KD_STAY, "stayed down for the count (%.2f s)" % t_up)
	check(not sim.mode.view_state().has("referee"), "view_state.referee disappears when idle")


func test_hit_rules_on_a_downed_fighter() -> void:
	for ref in [true, false]:
		var sim := _duel(_rules({"referee": ref}))
		var log := {}
		await _run(sim, 3.0, log, func(): return sim.mode.phase == MatchMode.Phase.FIGHT)
		var a := sim.fighters[0]
		var v := sim.fighters[1]
		v.knock_down("throw", a)
		var before: int = sim.event_seq
		sim.effects.effect_hit(a, v, {"damage": 6.0, "poise": 0.0, "stun": 0.0}, a.pos())
		sim.combat.apply_simple_damage(a, v, 5.0, "zone")
		sim.combat.apply_simple_damage(a, v, 5.0, "slam")
		sim.combat.apply_simple_damage(null, v, 5.0, "crane_drop")
		var hits := sim.events_since(before).filter(func(e): return str(e["type"]) == "hit")
		var kinds := hits.map(func(e): return str(e["slot"]))
		if ref:
			check_eq(kinds, ["slam", "crane_drop"], "referee: strikes and zones voided, the cage package and hazards land")
			check(hits.all(func(e): return bool(e.get("was_down", false))), "was_down marks hits on a downed fighter")
		else:
			check_eq(kinds, ["effect", "zone", "slam", "crane_drop"], "no referee: everything lands as before")


func test_knockdown_limit_stops_a_ten_point_fight() -> void:
	var sim := _duel(_rules(), [null, _riser()])
	var log := {}
	await _run(sim, 3.0, log, func(): return sim.mode.phase == MatchMode.Phase.FIGHT)
	for k in RefereeRules.REF_KD_LIMIT:
		await _knock(sim, 1, 0, log)
		await _run(sim, 0.05, log)
	var stops := _of(log, "ref_stoppage")
	check_eq(stops.size(), 1, "one stoppage")
	if stops.size() == 1:
		check_eq(int(stops[0]["fighter"]), 1)
		check_eq(int(stops[0]["by"]), 0)
		check_eq(str(stops[0]["reason"]), "knockdowns")
		check_eq(int(stops[0]["round"]), 1)
	await _run(sim, 10.0, log)
	check(sim.is_finished, "the match is over")
	check_eq(int(sim.result["winner_team"]), 0, "T.K.O. win")
	check_eq(int(sim.result["rounds"]), 1, "a round-1 stoppage ends the match")
	var sc: Dictionary = sim.result["scoring"]
	check_eq(str(sc["method"]), "TKO")
	check_eq((sc["cards"] as Array).size(), 1, "the partial round is scored")
	check(bool(sc["cards"][0]["stoppage"]), "card marks the stoppage")
	check_eq(int(sc["cards"][0]["tally"][0]["knockdowns"]), RefereeRules.REF_KD_LIMIT, "the knockdowns are on the card")
	var st: Dictionary = sc["stoppage"]
	check(int(st.get("fighter", -1)) == 1 and int(st.get("by", -1)) == 0 and int(st.get("round", 0)) == 1 and str(st.get("reason", "")) == "knockdowns", "stoppage block: %s" % str(st))
	check(float(st.get("time", -1.0)) > 0.0, "time into the round")
	check_eq((sim.result["referee"]["stoppages"] as Array).size(), 1)
	var order := (log["events"] as Array).filter(func(e): return str(e["type"]) in ["ref_stoppage", "round_scored", "judges_decision", "round_end", "timeout"]).map(func(e): return str(e["type"]))
	check_eq(order, ["ref_stoppage", "round_scored", "judges_decision", "round_end"], "closing order (no bell on a stoppage)")
	check_eq(str(_of(log, "judges_decision")[0]["method"]), "TKO")


func test_knockdown_limit_ends_only_the_round_under_health_scoring() -> void:
	var sim := _duel(_rules({"scoring": "hp"}), [null, _riser()])
	check(sim.mode.judge == null and sim.mode.referee != null, "HP scoring with a referee")
	var log := {}
	for rnd in 2:
		await _run(sim, 8.0, log, func(): return sim.mode.phase == MatchMode.Phase.FIGHT)
		for k in RefereeRules.REF_KD_LIMIT:
			await _knock(sim, 1, 0, log)
			await _run(sim, 0.05, log)
		check_eq(sim.mode.phase, MatchMode.Phase.ROUND_END, "round %d stopped" % (rnd + 1))
		if rnd == 0:
			check_eq(sim.mode.winner_team, -2, "best-of continues after a round stoppage")
			check(bool(sim.mode.view_state()["referee"].get("wave_off", false)), "wave-off for the presentation")
	await _run(sim, 10.0, log)
	check(sim.is_finished, "finished")
	check_eq(int(sim.result["winner_team"]), 0, "2-0 on round stoppages")
	check_eq(int(sim.result["rounds"]), 2, "best of three ends 2-0")
	check(not sim.result.has("scoring"), "no cards under Health scoring")
	check_eq((sim.result["referee"]["stoppages"] as Array).size(), 2, "both stoppages in result.referee")
	check(_of(log, "round_scored").is_empty() and _of(log, "judges_decision").is_empty(), "no judging events")
	var ends := _of(log, "round_end")
	check_eq(ends.size(), 2)
	var me: Dictionary = _of(log, "match_end")[0]
	check_near(float(int(me["tick"]) - int(ends[1]["tick"])) / Engine.physics_ticks_per_second, MatchMode.DECISION_TIME, 0.05, "the final ROUND_END gets the ceremony time")


func test_throw_and_hazard_knockdowns_are_never_counted() -> void:
	var sim := _duel(_rules(), [null, _riser()])
	var log := {}
	await _run(sim, 3.0, log, func(): return sim.mode.phase == MatchMode.Phase.FIGHT)
	var a := sim.fighters[0]
	var v := sim.fighters[1]
	for k in RefereeRules.REF_KD_LIMIT + 1:
		await _run(sim, 6.0, log, func(): return v.state == Fighter.State.NEUTRAL)
		if k % 2 == 0:
			v.knock_down("throw", a)
		else:
			sim.combat.apply_simple_damage(null, v, 4.0, "crane_drop", {"knockdown": true, "poise": 30.0})
		await _run(sim, 0.05, log)
		check(not sim.mode.referee.is_counting(v), "no count for a %s knockdown" % ("throw" if k % 2 == 0 else "hazard"))
	await _run(sim, 6.0, log, func(): return v.state == Fighter.State.NEUTRAL)
	check(_of(log, "ref_count").is_empty() and _of(log, "ref_stoppage").is_empty(), "no counts, no stoppage")
	check_eq(sim.mode.phase, MatchMode.Phase.FIGHT, "the fight goes on")
	check_near(sim.mode.auto_getup_time(v), Tuning.v("knockdown_auto_getup") / v.getup_speed_mult(), 1e-6, "normal get-up time")


func test_referee_reads_every_event_with_a_full_event_ring() -> void:
	# the ring is full in any real match: emitting while reading must not skip the next event
	var sim := _duel(_rules())
	var log := {}
	await _run(sim, 3.0, log, func(): return sim.mode.phase == MatchMode.Phase.FIGHT)
	var ref := sim.mode.referee
	sim.fighters[1].knock_down("poise", sim.fighters[0])
	ref.tick(1.0)
	check(ref.is_counting(sim.fighters[1]), "counting")
	for k in MatchSim.MAX_EVENTS + 10:
		sim.emit_event({"type": "filler"})
	var before := sim.event_seq
	sim.emit_event({"type": "getup", "fighter": 1, "forced": true})
	sim.emit_event({"type": "knockdown", "fighter": 1, "reason": "poise", "by": 0})
	ref.tick(2.0)
	var evs := sim.events_since(before)
	check(evs.any(func(e): return str(e["type"]) == "ref_wave_up"), "the wave-up was announced")
	check_eq(ref.knockdowns_this_round(sim.fighters[1]), 2, "the knockdown right after it was still counted")


func test_nothing_is_counted_outside_the_live_round() -> void:
	var sim := _duel(_rules({"round_time": 2.0}))
	var log := {}
	# during the intro
	sim.fighters[1].knock_down("poise", sim.fighters[0])
	await _run(sim, 2.0, log, func(): return sim.mode.phase == MatchMode.Phase.FIGHT)
	check(_of(log, "ref_count").is_empty(), "no count from an intro knockdown")
	# after the bell
	await _run(sim, 4.0, log, func(): return sim.mode.phase == MatchMode.Phase.ROUND_END)
	var v := sim.fighters[1]
	await _run(sim, 2.5, log, func(): return v.state == Fighter.State.NEUTRAL)
	var before := _of(log, "ref_count").size()
	v.knock_down("poise", sim.fighters[0])
	await _run(sim, 0.5, log)
	check(not sim.mode.referee.is_counting(v), "no count after the bell")
	check_eq(_of(log, "ref_count").size(), before, "no counts after the bell")
	check_near(sim.mode.auto_getup_time(v), Tuning.v("knockdown_auto_getup") / v.getup_speed_mult(), 1e-6, "normal get-up time outside FIGHT")
