extends CareerTestCase
## CMP-08: a real career bout end to end. The booked offer becomes a headless-ready match config
## (Cage Rules preset rules, career builds on both sides, a seeded bot opponent), runs through
## HeadlessFightRunner in its own physics world at SimSpeed, and apply_result settles it — with
## result.scoring when 10-point scoring is in the build, from winner_team otherwise.

const SPEED := 16.0


func after_each() -> void:
	store = null
	super.after_each()


func test_bout_config_shape() -> void:
	var ctrl := new_career({"seed": 2023})
	var o := book(ctrl, {})
	var built := ctrl.fight_config({"player_kind": "bot", "player_bot_tier": "contender"})
	check((built["errors"] as PackedStringArray).is_empty(), "builds: %s" % [built["errors"]])
	var cfg: Dictionary = built["config"]
	check(bool(cfg["no_record"]), "no_record: career bouts never count as versus matches (D9)")
	check(bool(cfg["context"]["career"]) and str(cfg["context"]["fight_id"]) == str(o["id"]), "career context")
	var r: Dictionary = cfg["rules"]
	check_eq(str(r.get("mode", "")), "standard", "standard mode")
	check_eq(str(r.get("format", "")), "duel", "1v1")
	check_eq(str(r.get("scoring", "")), "ten_point", "10-point scoring")
	check(bool(r.get("referee", false)), "with the referee")
	check_eq(int(r["rounds"]), 3, "three rounds")
	check_near(float(r["round_time"]), 99.0, 0.001, "99 s rounds (D6)")
	check(not bool(r["sudden_death"]), "no sudden death: career bouts can be drawn")
	check(cfg["arena"] is ArenaDef and cfg["mode"] is MatchMode, "pre-resolved arena and mode")
	var fs: Array = cfg["fighters"]
	check_eq(fs.size(), 2, "two fighters")
	check_eq(int(fs[0]["team"]), 0, "the career fighter is team 0")
	check_eq((fs[0]["creature"] as CreatureDef).id, "f_stoke", "the career's fighter")
	check(fs[0]["source"] is BotBrain, "a bot pilots the career fighter in unattended runs")
	check_eq(int(fs[1]["team"]), 1, "the opponent is team 1")
	check_eq((fs[1]["creature"] as CreatureDef).id, str(o["opp"]["fighter"]), "the offer's opponent")
	check(fs[1]["source"] is BotBrain, "with its own bot")
	check_eq(str(fs[1]["name"]), str(o["opp"]["name"]), "billed under the ring name")
	var presented := ctrl.fight_config()
	check_eq(str(presented["config"]["fighters"][0]["kind"]), "player", "presented bouts: the local player")
	# titles are five rounds
	var t := new_career({"seed": 2023})
	book(t, {"rounds": 5, "title": true})
	check_eq(int(t.fight_config()["config"]["rules"]["rounds"]), 5, "title bouts: five rounds")
	check(float(t.fight_config()["max_seconds"]) >= 5 * (99.0 + 2.2 + 3.0) + 6.0 + 30.0, "D6 headless time cap")


func test_headless_career_bout_end_to_end() -> void:
	new_store()
	var ctrl := new_career({"seed": 2024}, true)
	var o: Dictionary = ctrl.state["offers"][0]
	check(ctrl.accept(str(o["id"])), "accept: %s" % ctrl.last_error)
	while not ctrl.fight_ready():
		ctrl.train("power")
	check(ctrl.begin_fight(), "launch: %s" % ctrl.last_error)
	var built := ctrl.fight_config({"player_kind": "bot", "player_bot_tier": "contender"})
	check((built["errors"] as PackedStringArray).is_empty(), "builds: %s" % [built["errors"]])
	if not (built["errors"] as PackedStringArray).is_empty():
		return
	var cfg: Dictionary = built["config"]
	var rounds := int(cfg["rules"]["rounds"])
	# D6 cap; without 10-point scoring in the build, drawn HP rounds can add rounds (best of N)
	var max_s := maxf(float(built["max_seconds"]), rounds * 2 * (99.0 + 2.2 + 3.0) + 36.0)
	SimSpeed.set_scale(SPEED)
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = await HeadlessFightRunner.run(self, cfg, max_s)
	SimSpeed.restore()
	var real_ms := Time.get_ticks_msec() - t0
	check(int(res.get("winner_team", -2)) != -2, "the bout reached a result (%s)" % str(res.get("winner_team")))
	check(not bool(res.get("timed_out", false)), "within the time cap")
	var money := int(ctrl.state["money"])
	var week := int(ctrl.state["week"])
	var s := ctrl.apply_result(res, str(o["id"]))
	check(bool(s["ok"]), "apply_result accepts the real result: %s" % s.get("error", ""))
	if not bool(s["ok"]):
		return
	check(str(s["method"]) != "", "a method")
	check(str(s["result"]) in ["win", "loss", "draw"], "a result")
	check(int(ctrl.state["money"]) >= money + int(o["purse"]), "the purse was paid")
	check_eq(int(ctrl.state["week"]), week + 1, "the fight takes a week")
	check_eq((ctrl.state["history"] as Array).size(), 1, "history entry")
	check(not ctrl.is_booked() and not ctrl.interrupted(), "settled")
	for r in CareerDefaults.REGIONS:
		var v := float(ctrl.state["injury"][r])
		check(v >= 0.0 and v <= 100.0, "injury %s in range" % r)
	check(not bool(ctrl.apply_result(res, str(o["id"]))["ok"]), "the same bout applies once")
	var back := store.load_slot("tester", 1, cat())
	check_eq(sig(back["state"]), sig(ctrl.state), "the result was autosaved")
	var sc: Dictionary = s.get("scoring", {})
	var inj: Dictionary = s["injury_added"]
	# calibration data for the report (placeholder injury / action constants)
	print("CAREER-MEASURE scoring=%s method=%s winner=%d round=%d landed=%s kds=%s action=%.1f d_pop=%.1f inj=%d/%d/%d (total %d) sim_time=%.1f real_ms=%d cards=%d" % [
		str(not sc.is_empty()), str(s["method"]), int(res.get("winner_team", -2)), int(s["round"]), str(s["landed"]),
		str(s["knockdowns"]), float(s["action"]), float(s["d_pop"]), int(inj["head"]), int(inj["body"]), int(inj["legs"]),
		int(inj["head"]) + int(inj["body"]) + int(inj["legs"]), float(res.get("time", 0.0)), real_ms, (sc.get("cards", []) as Array).size()])
