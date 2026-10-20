extends TestCase
## MCH-07: 10-point must scoring (rules "scoring": "ten_point", RoundJudge). Every round is fought
## and judged, nobody is knocked out by damage, three deterministic judges score each round from
## the event stream, the cards decide (ties: sudden death or a draw), cards are plain data that
## survive Saves, and rules without the new keys play exactly as before.
## Run: godot --headless --path game --fixed-fps 120 -- --test test_ten_point_scoring

const TEN := {"mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "rounds": 3, "round_time": 4.0,
	"intro_time": 0.3, "win": "ko", "lives": 1, "sudden_death": true, "scoring": "ten_point"}


func _rules(over := {}) -> Dictionary:
	var r := TEN.duplicate(true)
	r.merge(over, true)
	return r


func _duel(rules: Dictionary, sources := [null, null], creatures := ["dev_biped", "dev_biped"], seed_value := 11) -> MatchSim:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var entries := []
	for i in 2:
		entries.append({"creature": Content.creature(str(creatures[i])), "team": i, "source": sources[i], "kind": "bot" if sources[i] else "dummy"})
	sim.setup({"arena": Content.arena("the_gullet"), "rules": rules, "seed": seed_value, "fighters": entries, "mode": ModeRegistry.create("standard")})
	return sim


## Steps in phase with physics (D-026), collecting every event into log["events"]. `until` may
## end the run early; per-tick checks go in `each`.
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


func _attacker() -> InputSource:
	return InputSource.Scripted.new([{"t0": 0.0, "t1": 999.0, "move": "to_target", "press": ["light"], "every": 0.25},
		{"t0": 0.0, "t1": 999.0, "press": ["heavy"], "every": 1.3}])


func _to_fight(sim: MatchSim, log: Dictionary) -> void:
	await _run(sim, 3.0, log, func(): return sim.mode.phase == MatchMode.Phase.FIGHT)


# ---------------------------------------------------------------------------------------------

func test_judge_math_is_pure_and_matches_the_documented_rules() -> void:
	var c := RoundJudge.CLOSE
	check_eq(RoundJudge.card_pair(0.0, 0, 0), [10, 10], "level")
	check_eq(RoundJudge.card_pair(c - 0.01, 0, 0), [10, 10], "just under CLOSE is 10-10")
	check_eq(RoundJudge.card_pair(c, 0, 0), [10, 9], "CLOSE is 10-9")
	check_eq(RoundJudge.card_pair(-c, 0, 0), [9, 10], "10-9 the other way")
	check_eq(RoundJudge.card_pair(RoundJudge.DOMINANT, 0, 0), [10, 8], "dominant round")
	check_eq(RoundJudge.card_pair(RoundJudge.DOMINANT - 0.01, 0, 0), [10, 9], "just under DOMINANT")
	check_eq(RoundJudge.card_pair(RoundJudge.DOMINANT_KD, 1, 0), [10, 8], "knockdown + DOMINANT_KD")
	check_eq(RoundJudge.card_pair(RoundJudge.DOMINANT_KD, 1, 1), [10, 9], "level knockdowns: no knockdown 10-8")
	check_eq(RoundJudge.card_pair(RoundJudge.DOMINANT_KD, 0, 1), [10, 9], "the loser's knockdown never gives the winner 10-8")
	check_eq(RoundJudge.card_pair(-RoundJudge.DOMINANT_KD, 0, 2), [8, 10], "knockdown 10-8 the other way")
	# the three perspectives
	var t := RoundJudge.empty_tally()
	t["dmg_pts"] = 20.0
	t["landed"] = 10
	t["knockdowns"] = 1
	t["throws"] = 1
	t["ringouts"] = 1
	t["parries"] = 2
	t["guard_breaks"] = 1
	var p := 20.0 + RoundJudge.W_LANDED * 10 + RoundJudge.W_KD + RoundJudge.W_THROW + RoundJudge.W_RINGOUT + RoundJudge.W_PARRY * 2 + RoundJudge.W_GUARD_BREAK
	check_near(RoundJudge.base_score(t), p, 1e-6, "P")
	check_near(RoundJudge.judge_score(0, t), p, 1e-6, "Even card = P")
	check_near(RoundJudge.judge_score(1, t), p + 0.5 * 10 + 2.0, 1e-6, "Volume = P + 0.5 landed + parries")
	check_near(RoundJudge.judge_score(2, t), p + 0.25 * 20.0 + 2.0, 1e-6, "Impact = P + 0.25 dmg_pts + 2 knockdowns")
	check_eq(RoundJudge.JUDGE_NAMES, ["Even card", "Volume", "Impact"])
	# decisions: every judge pattern
	var cases := [
		[[[10, 9], [10, 9], [10, 9]], 0, "Unanimous Decision"],
		[[[10, 9], [10, 9], [10, 10]], 0, "Majority Decision"],
		[[[9, 10], [10, 9], [9, 10]], 1, "Split Decision"],
		[[[10, 10], [10, 10], [10, 10]], -1, "Unanimous Draw"],
		[[[10, 9], [10, 10], [10, 10]], -1, "Majority Draw"],
		[[[10, 9], [9, 10], [10, 10]], -1, "Split Draw"],
	]
	for cs in cases:
		var d := RoundJudge.decide_cards([{"judges": cs[0]}])
		check_eq(int(d["winner_slot"]), int(cs[1]), "winner for %s" % str(cs[0]))
		check_eq(str(d["method"]), str(cs[2]), "method for %s" % str(cs[0]))
	# over three rounds the totals decide: 29-28, 29-28, 28-29 -> split
	var three := [{"judges": [[10, 9], [10, 9], [10, 9]]}, {"judges": [[10, 9], [9, 10], [9, 10]]}, {"judges": [[9, 10], [10, 9], [9, 10]]}]
	check_eq(RoundJudge.totals_of(three), [[29, 28], [29, 28], [28, 29]], "judges' totals")
	check_eq(str(RoundJudge.decide_cards(three)["method"]), "Split Decision")
	# plain numbers: whole values are ints (what Saves keeps), others 0.1
	check_eq(typeof(RoundJudge.plain(12.0)), TYPE_INT, "whole -> int")
	check_near(float(RoundJudge.plain(12.34)), 12.3, 1e-9, "0.1")


func test_tally_counts_only_what_a_side_did_to_the_other() -> void:
	var sim := _duel(_rules({"round_time": 30.0}))
	var log := {}
	await _to_fight(sim, log)
	var j := sim.mode.judge
	check(j != null and sim.mode.unlimited_health(), "judge runs for a timed standard duel")
	var mh := sim.fighters[1].max_health
	var base := {"point": Vector3.ZERO, "normal": Vector3.UP, "parried": false, "blocked": false, "counter": false, "element": "",
		"quality": 1.0, "move": "x", "slot": "l1", "knockdown": false, "otg": false}
	var hits := [
		{"fighter": 0, "target": 1, "damage": 10.0, "part": "head", "melee": true},
		{"fighter": 0, "target": 1, "damage": 2.5, "part": "arm", "melee": true, "blocked": true},
		{"fighter": 0, "target": 1, "damage": 0.0, "part": "core", "melee": true, "parried": true},
		{"fighter": 0, "target": 1, "damage": 9.0, "part": "core", "melee": false, "slot": "throw"},
		{"fighter": 0, "target": 1, "damage": 4.0, "part": "leg", "melee": true, "was_down": true},
		{"fighter": 1, "target": 1, "damage": 5.0, "part": "core", "melee": false},
		{"fighter": -1, "target": 1, "damage": 8.0, "part": "core", "melee": false},
	]
	for h in hits:
		var ev: Dictionary = base.duplicate()
		ev.merge(h, true)
		ev["type"] = "hit"
		sim.emit_event(ev)
	sim.emit_event({"type": "dot", "fighter": 1, "damage": 3.0, "by": 0, "element": "", "status": "burn"})
	sim.emit_event({"type": "dot", "fighter": 1, "damage": 3.0, "by": -1, "element": "", "status": "burn"})
	for kd in [["poise", 0], ["throw", 0], ["poise", -1], ["move", 1], ["move", 0]]:
		sim.emit_event({"type": "knockdown", "fighter": 1, "reason": kd[0], "by": kd[1]})
	sim.emit_event({"type": "throw", "fighter": 0, "victim": 1, "kind": "throw"})
	sim.emit_event({"type": "parry", "fighter": 1, "attacker": 0, "pos": Vector3.ZERO})
	sim.emit_event({"type": "guard_break", "fighter": 1})
	for slot in ["l1", "heavy@juiced", "ability1", "pummel", "grab"]:
		sim.emit_event({"type": "move_start", "fighter": 0, "slot": slot, "id": "m"})
	var rng_before := sim.rng.state
	j.scan()
	check_eq(sim.rng.state, rng_before, "the judge never touches sim.rng")
	var t: Array = j.live_tally()
	var a: Dictionary = t[0]
	var b: Dictionary = t[1]
	check_near(float(a["damage"]), 10.0 + 2.5 + 9.0 + 4.0 + 3.0, 1e-6, "damage: clean, blocked chip, throw, OTG (no referee), enemy DoT")
	check_near(float(a["dmg_pts"]), float(a["damage"]) / mh * 100.0 * RoundJudge.K_DMG, 1e-6, "damage normalised by the target's HP")
	check_eq(int(a["landed"]), 2, "clean melee strikes only (the throw and the parried one are not strikes landed)")
	check_eq(int(a["blocked"]), 1, "blocked strikes")
	check_eq(int(a["knockdowns"]), 2, "only strike knockdowns by the opponent (not throw / hazard / self)")
	check_eq(int(a["throws"]), 1)
	check_eq(int(a["guard_breaks"]), 1, "the opponent's guard break is credited")
	check_eq(int(a["thrown"]), 2, "strikes started (lights and heavies, not abilities, pummels, grabs)")
	check_eq(int(b["parries"]), 1, "parries credit the defender")
	check_near(float(b["damage"]), 0.0, 1e-9, "self damage and hazards never score")
	check_near(float(b["taken_head"]), 10.0, 1e-6, "taken by part: head")
	check_near(float(b["taken_legs"]), 4.0, 1e-6, "taken by part: legs")
	check_near(float(b["taken_body"]) + float(b["taken_head"]) + float(b["taken_legs"]), float(a["damage"]), 1e-6, "taken parts add up to the other side's damage")
	# with a referee the OTG hit is never credited
	var sim2 := _duel(_rules({"round_time": 30.0, "referee": true}))
	var log2 := {}
	await _to_fight(sim2, log2)
	var ev2: Dictionary = base.duplicate()
	ev2.merge({"type": "hit", "fighter": 0, "target": 1, "damage": 4.0, "part": "leg", "melee": true, "was_down": true}, true)
	sim2.emit_event(ev2)
	sim2.mode.judge.scan()
	check_near(float(sim2.mode.judge.live_tally()[0]["damage"]), 0.0, 1e-9, "referee: damage on a downed fighter is not credited")


func test_unlimited_health_keeps_the_knockdown_of_a_huge_blow() -> void:
	for ten in [true, false]:
		var sim := _duel(_rules({"round_time": 30.0, "scoring": "ten_point" if ten else "hp"}))
		var log := {}
		await _to_fight(sim, log)
		var f1 := sim.fighters[1]
		f1.receive_hit({"attacker": sim.fighters[0], "damage": 999.0, "point": f1.pos(), "seg": 0, "poise": 999.0, "knockdown": false, "stun": 0.3})
		if ten:
			check_eq(f1.state, Fighter.State.KNOCKDOWN, "10-point: the blow still knocks down")
			check_near(f1.health, f1.max_health, 1e-6, "10-point: HP stays full")
			check(not f1.is_out(), "10-point: never knocked out")
		else:
			check_eq(f1.state, Fighter.State.KO, "HP rules: the same blow knocks out (unchanged)")


func test_every_round_is_fought_and_nobody_is_knocked_out() -> void:
	# the attacker wins every round; best-of would end 2-0, and these HP settings would KO quickly
	var sim := _duel(_rules({"health_mult": 0.25, "damage_mult": 4.0}), [_attacker(), null])
	var log := {}
	var low := [0]
	var each := func():
		for f in sim.fighters:
			if f.health < f.max_health - 1e-6:
				low[0] = int(low[0]) + 1
	await _run(sim, 40.0, log, Callable(), each)
	check(sim.is_finished, "match finished")
	check_eq(int(low[0]), 0, "HP never below max at the end of any tick")
	check(_of(log, "ko").is_empty() and _of(log, "elimination").is_empty(), "nobody is knocked out")
	var scored := _of(log, "round_scored")
	check_eq(scored.size(), 3, "every round is scored")
	check_eq(_of(log, "round_intro").filter(func(e): return int(e["round"]) == 3).size(), 1, "round 3 is fought after a 2-0 lead")
	check_eq(int(sim.result["rounds"]), 3, "three rounds")
	check_eq(int(sim.result["winner_team"]), 0, "the attacker wins on the cards")
	var sc: Dictionary = sim.result.get("scoring", {})
	check_eq(str(sc.get("mode", "")), "ten_point")
	check(str(sc.get("method", "")).ends_with("Decision"), "a decision: %s" % str(sc.get("method", "")))
	check_eq((sc.get("cards", []) as Array).size(), 3, "three cards in the result")
	check_eq(sc.get("teams", []), [0, 1])
	check_eq(sc.get("judges", []), ["Even card", "Volume", "Impact"])
	check_eq(int(sim.result["round_wins"][0]), 3, "round wins = rounds won on the cards")
	for c in sc.get("cards", []):
		check_eq(int(c["winner"]), 0, "round %d to the attacker" % int(c["round"]))
		check_eq(int(c["judges"][0][0]), 10, "10 for the round winner")
		check(float(c["tally"][0]["damage"]) > float(c["tally"][1]["damage"]), "the cards follow the damage")
	check_eq(_of(log, "judges_decision").size(), 1, "one decision")
	check_eq(_of(log, "timeout").size(), 3, "the bell (timeout) still rings every round")
	var last_end: Dictionary = _of(log, "round_end")[-1]
	var me: Dictionary = _of(log, "match_end")[0]
	check_near(float(int(me["tick"]) - int(last_end["tick"])) / Engine.physics_ticks_per_second, MatchMode.DECISION_TIME, 0.05, "the decision gets DECISION_TIME")
	var hs := sim.mode.hud_state()
	check_eq(int(hs["cards"]["n"]), 3, "hud_state cards")
	check_eq(hs["cards"]["t"], sc["totals"], "hud_state totals = result totals")
	check(not hs.has("sd"), "no sudden death flag")


func test_drawn_cards_and_sudden_death_resolve_without_a_round_4() -> void:
	var sim := _duel(_rules({"round_time": 2.0}))
	var log := {}
	await _run(sim, 30.0, log, func(): return sim.mode.sudden_death)
	check(sim.mode.sudden_death, "drawn cards start sudden death")
	var dec := _of(log, "judges_decision")
	check_eq(dec.size(), 1, "the drawn decision is announced")
	check_eq(str(dec[0]["method"]), "Unanimous Draw", "idle fighters: 10-10 x3")
	check_eq(int(dec[0]["winner"]), -1)
	check_eq(sim.mode.phase, MatchMode.Phase.FIGHT, "the phase stays FIGHT")
	check_near(sim.mode.round_timer, 0.0, 1e-6, "the timer stays at 0")
	check(_of(log, "round_end").filter(func(e): return int(e["round"]) == 3).is_empty(), "no round_end before sudden death resolves")
	var hs := sim.mode.hud_state()
	check(bool(hs.get("sd", false)), "hud_state.sd during sudden death after drawn cards")
	check_eq(sim.mode.hud_status(), "SUDDEN DEATH — next clean hit wins", "status text stays short")
	await _run(sim, 2.0, log)
	check(not sim.is_finished, "sudden death waits for a clean hit")
	sim.fighters[1].set_flag("sudden_death_winner", 999.0)   # what the hit_dealt hook does
	await _run(sim, 10.0, log)
	check(sim.is_finished, "finished")
	check_eq(int(sim.result["winner_team"]), 1, "the clean hit wins")
	check_eq(int(sim.result["rounds"]), 3, "no round 4")
	check(_of(log, "round_intro").filter(func(e): return int(e["round"]) == 4).is_empty(), "no round 4 intro")
	dec = _of(log, "judges_decision")
	check_eq(dec.size(), 2, "exactly one more decision")
	check_eq(str(dec[1]["method"]), "Sudden Death (after a Unanimous Draw)")
	check_eq(str(sim.result["scoring"]["method"]), "Sudden Death (after a Unanimous Draw)")
	check(bool(sim.result["scoring"]["sudden_death"]), "result marks the sudden death")


func test_drawn_cards_without_sudden_death_are_a_draw_after_exactly_n_rounds() -> void:
	var sim := _duel(_rules({"round_time": 2.0, "sudden_death": false}))
	var log := {}
	await _run(sim, 40.0, log)
	check(sim.is_finished, "finished")
	check_eq(int(sim.result["winner_team"]), -1, "a draw")
	check_eq(int(sim.result["rounds"]), 3, "exactly three rounds")
	check_eq(_of(log, "round_scored").size(), 3)
	check(_of(log, "sudden_death").is_empty(), "no sudden death")
	check_eq(str(sim.result["scoring"]["method"]), "Unanimous Draw")


func test_cards_are_deterministic_and_survive_saves() -> void:
	var runs := []
	for k in 2:
		var sim := _duel(_rules({"sudden_death": false}), [_attacker(), InputSource.Scripted.new([{"t0": 0.0, "t1": 999.0, "hold": ["guard"]}])], ["dev_biped", "dev_biped"], 21)
		var log := {}
		await _run(sim, 40.0, log)
		check(sim.is_finished, "run %d finished" % k)
		runs.append(sim.result.get("scoring", {}))
	check_eq(JSON.stringify(runs[0]), JSON.stringify(runs[1]), "same seed and inputs: identical cards")
	var sc: Dictionary = runs[0]
	var stable = Saves.stabilize(sc)
	check_eq(JSON.stringify(stable, "", true, true), JSON.stringify(sc, "", true, true), "the scoring block is a JSON fixed point")
	check(_same(stable, sc), "identical after Saves.stabilize (types and values)")
	check(_keys_are_strings(sc), "no dictionary keyed by a team or fighter index")
	for c in sc["cards"]:
		check(_same(Saves.stabilize(c), c), "card %d identical after Saves.stabilize" % int(c["round"]))
		check_eq((c["tally"] as Array).size(), 2, "tally aligned with teams")


func test_rules_without_the_keys_play_exactly_as_before() -> void:
	var base: Dictionary = Content.get_entry("rules", "duel").duplicate(true)
	base.erase("_package")
	base.erase("_file")
	base["round_time"] = 5.0
	base["intro_time"] = 0.3
	var explicit := base.duplicate(true)
	explicit["scoring"] = "hp"
	explicit["referee"] = false
	var traces := []
	for r in [base, explicit]:
		var b0 := BotBrain.new("pro", 501)
		var b1 := BotBrain.new("pro", 502)
		var sim := _duel(r, [b0, b1], ["f_stoke", "f_gusto"], 77)
		check(sim.mode.judge == null and sim.mode.referee == null, "no officials")
		check(not sim.mode.unlimited_health() and not sim.mode.has_referee())
		var log := {}
		await _run(sim, 12.0, log)
		var tr := []
		for e in log["events"]:
			tr.append("%s:%d:%s" % [str(e["type"]), int(e["tick"]), str(snappedf(float(e.get("damage", 0.0)), 0.001))])
		traces.append({"events": tr, "hp": [snappedf(sim.fighters[0].health, 0.001), snappedf(sim.fighters[1].health, 0.001)],
			"has_scoring": sim.mode.build_result().has("scoring") or sim.mode.build_result().has("referee"),
			"hud": sim.mode.hud_state().has("cards"), "view": sim.mode.view_state().has("referee")})
	check(not traces[0]["events"].is_empty(), "the duel ran")
	check_eq(traces[0]["events"].size(), traces[1]["events"].size(), "same number of events")
	check(traces[0]["events"] == traces[1]["events"], "identical event streams with and without explicit hp/no-referee keys")
	check_eq(traces[0]["hp"], traces[1]["hp"], "identical health")
	for t in traces:
		check(not bool(t["has_scoring"]) and not bool(t["hud"]) and not bool(t["view"]), "no 10-point / referee data in HP results")


func test_officials_only_run_in_a_timed_standard_duel() -> void:
	# rules are not validated for local play: the sim checks the shape itself
	var ffa := MatchSim.new()
	ffa.running = false
	fresh_world().add_child(ffa)
	var entries := []
	for i in 3:
		entries.append({"creature": Content.creature("dev_biped"), "team": i, "source": null})
	ffa.setup({"arena": Content.arena("the_gullet"), "rules": {"mode": "standard", "format": "ffa", "teams": 0, "scoring": "ten_point", "referee": true, "round_time": 30.0},
		"seed": 1, "fighters": entries, "mode": ModeRegistry.create("standard")})
	check(ffa.mode.judge == null and ffa.mode.referee == null, "three fighters: plain HP rules")
	var untimed := _duel(_rules({"round_time": 0.0, "referee": true}))
	check(untimed.mode.judge == null, "no timer: no judges")
	check(untimed.mode.referee != null, "the referee still works without a timer")
	for mid in ["tag_team", "practice"]:
		var m := ModeRegistry.create(mid)
		var s := MatchSim.new()
		s.running = false
		fresh_world().add_child(s)
		var es := []
		for i in (4 if mid == "tag_team" else 2):
			es.append({"creature": Content.creature("dev_biped"), "team": i % 2, "source": null})
		s.setup({"arena": Content.arena("the_gullet"), "rules": {"mode": mid, "scoring": "ten_point", "referee": true, "round_time": 30.0}, "seed": 1, "fighters": es, "mode": m})
		check(s.mode.judge == null and s.mode.referee == null, "%s ignores the keys" % mid)


# ---------------------------------------------------------------------------------------------

func _same(a, b) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			if (a as Dictionary).size() != (b as Dictionary).size():
				return false
			for k in a:
				if not (b as Dictionary).has(k) or not _same(a[k], b[k]):
					return false
			return true
		TYPE_ARRAY:
			if (a as Array).size() != (b as Array).size():
				return false
			for i in (a as Array).size():
				if not _same(a[i], b[i]):
					return false
			return true
	return a == b


func _keys_are_strings(v) -> bool:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				if typeof(k) != TYPE_STRING or not _keys_are_strings(v[k]):
					return false
		TYPE_ARRAY:
			for e in v:
				if not _keys_are_strings(e):
					return false
	return true
