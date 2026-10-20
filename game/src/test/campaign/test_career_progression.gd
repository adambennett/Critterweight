extends CareerTestCase
## CMP-08 Career loop against the Cage Rules formulas (js/career.js): seeded offers, training gain
## and gym multipliers, healing, popularity deltas and tier caps, titles, purses, withdrawals,
## idempotent results, the crash re-fight (D4), D5 bot tiers and the read helpers WP5 shows (D7).


func after_each() -> void:
	store = null
	super.after_each()


## Books the first offer with `fields`, jumps to fight week and applies `result`.
func settle(ctrl: CareerController, fields: Dictionary, result: Dictionary) -> Dictionary:
	var o := book(ctrl, fields)
	return ctrl.apply_result(result, str(o.get("id", "")))


func ud(winner := 0, opts := {}) -> Dictionary:
	return scoring_result(winner, "Unanimous Decision" if winner >= 0 else "Unanimous Draw", opts)


# ---------------------------------------------------------------------------------------------
# Offers
# ---------------------------------------------------------------------------------------------

func test_offers_are_deterministic_per_seed_and_week() -> void:
	var a := new_career({"seed": 999})
	var b := new_career({"seed": 999})
	check_eq(sig(a.state["offers"]), sig(b.state["offers"]), "same seed + week: the same offers")
	var again := CareerOffers.make_offers(cat(), a.rules, a.state)
	check_eq(sig(again), sig(a.state["offers"]), "regenerating gives the same offers")
	var c := new_career({"seed": 1000})
	check(sig(c.state["offers"]) != sig(a.state["offers"]), "another seed: other offers")
	a.train("power")
	check_eq(int(a.state["week"]), 2, "a week passed")
	check(sig(a.state["offers"]) != sig(b.state["offers"]), "next week: new offers")
	b.train("power")
	check_eq(sig(a.state["offers"]), sig(b.state["offers"]), "still in lockstep with the same choices")
	var st: Dictionary = a.state.duplicate(true)
	st["offer_roll"] = 1
	check(sig(CareerOffers.make_offers(cat(), a.rules, st)) != sig(a.state["offers"]), "a re-roll within the week differs")
	var ids := {}
	for i in 40:
		a.train("rest")
		for o in a.state["offers"]:
			check(not ids.has(str(o["id"])), "offer ids never repeat (%s)" % o["id"])
			ids[str(o["id"])] = true
			check(int(o["weeks"]) >= 4 and int(o["weeks"]) <= 10, "camp 4-10 weeks")
			check_eq(int(o["rounds"]), 3, "three rounds")
			check_near(float(o["round_time"]), 99.0, 0.001, "the preset's 99 s rounds (D6), never 180")
			check(str(o["arena"]) != "" and CareerState.offer_missing(cat(), o).is_empty(), "a playable arena")


func test_offer_pool_follows_popularity() -> void:
	var ctrl := new_career({"seed": 31})
	var counts := {2: 0, 3: 0}
	for pop in [2.0, 10.0, 30.0, 52.0, 80.0]:
		ctrl.state["pop"] = pop
		for wk in range(1, 30):
			ctrl.state["week"] = wk
			var offers := CareerOffers.make_offers(cat(), ctrl.rules, ctrl.state)
			counts[offers.size()] = int(counts.get(offers.size(), 0)) + 1
			var top := CareerState.tier_for(ctrl.rules, pop)
			check_eq(int(offers[0]["tier"]), top, "offer 0 comes from the top tier (pop %d)" % pop)
			for o in offers:
				check(int(o["tier"]) >= top - 1 and int(o["tier"]) <= top, "only the top tier and the one below (pop %d)" % pop)
				var org := CareerState.org(ctrl.rules, str(o["org"]))
				check(pop >= float(org["pop"]), "an org only calls once its popularity gate is met")
				check(not bool(o["title"]), "no title shot below 92")
	check(int(counts[2]) > 20 and int(counts[3]) > int(counts[2]), "2 offers ~40%%, 3 ~60%% (%s)" % [counts])


func test_opponents_follow_the_org_band_and_d5_tiers() -> void:
	var ctrl := new_career({"seed": 77})
	var rules := ctrl.rules
	for o in rules["orgs"]:
		for i in 12:
			var rng := RunRng.stream(5, "opp/%s/%d" % [o["id"], i])
			var opp := CareerOffers.make_opponent(cat(), rules, rng, o, ctrl.state, false)
			var lvl := float(opp["level"])
			check(lvl >= float(o["level"][0]) - 0.0001 and lvl <= float(o["level"][1]) + 0.0001, "%s level in its band" % o["id"])
			for k in CareerDefaults.STATS:
				check(float(opp["stats"][k]) >= 0.15 and float(opp["stats"][k]) <= 0.99, "stat in range")
			check(absi(int(opp["rating"]) - int(round(lvl * 100.0))) <= 6, "rating ~ 100 x level (%d vs %.2f)" % [int(opp["rating"]), lvl])
			check(cat().available_fighters().has(str(opp["fighter"])), "a playable creature")
			check_eq(str(opp["bot_tier"]), CareerOffers.bot_tier(rules, lvl, "normal"), "D5 bot tier from the level")
			var fights := int(opp["record"]["w"]) + int(opp["record"]["l"])
			check(fights >= 2 and fights <= 2 + 24 + 6, "a plausible record")
	var title := CareerOffers.make_opponent(cat(), rules, RunRng.stream(9, "t"), CareerState.belt_org(rules), ctrl.state, true)
	check(float(title["level"]) >= 0.9 and float(title["level"]) <= 0.96, "champions are a class above (0.90-0.96)")
	check_eq(str(title["bot_tier"]), "headliner", "title fights: Headliner on Normal")
	# D5 thresholds and the career difficulty
	check_eq(CareerOffers.bot_tier(rules, 0.30, "normal"), "punching_bag", "< 0.33")
	check_eq(CareerOffers.bot_tier(rules, 0.40, "normal"), "journeyman", "< 0.48")
	check_eq(CareerOffers.bot_tier(rules, 0.55, "normal"), "contender", "< 0.63")
	check_eq(CareerOffers.bot_tier(rules, 0.70, "normal"), "headliner", "otherwise headliner")
	check_eq(CareerOffers.bot_tier(rules, 0.95, "normal"), "headliner", "never Hall-of-Famer on Normal")
	check_eq(CareerOffers.bot_tier(rules, 0.30, "easy"), "punching_bag", "Easy clamps at the bottom")
	check_eq(CareerOffers.bot_tier(rules, 0.70, "easy"), "contender", "Easy: one tier lower")
	check_eq(CareerOffers.bot_tier(rules, 0.30, "hard"), "journeyman", "Hard: one tier higher")
	check_eq(CareerOffers.bot_tier(rules, 0.95, "hard"), "hall_of_famer", "only Hard reaches Hall-of-Famer")
	var hard := new_career({"seed": 77, "difficulty": "hard"})
	check_eq(str(hard.state["difficulty"]), "hard", "difficulty stored in the save")
	check_eq(str(hard.header()["difficulty_name"]), "Hard", "and shown")
	check_eq(str(new_career({"difficulty": "silly"}).state["difficulty"]), "normal", "unknown difficulty -> Normal")


func test_names_are_original() -> void:
	var rules := CareerDefaults.rules()
	# Cage Rules' lists use real fighters' nicknames and a real promotion; none of them may appear
	var banned := ["UFC", "Poatan", "Stylebender", "Durinho", "Bones", "The Reaper", "The Eagle", "Rocky",
		"Showtime", "The Diamond", "Hands of Stone", "Bam Bam", "Rukus", "Tarzan", "El Matador", "Thunder",
		"Hurricane", "The Machine", "Bad Boy", "Diesel", "Mayhem", "Tri-State Cage Wars", "Pacific Fight League",
		"Cage Nation", "Valor FC", "Apex Fighting", "Iron Circuit", "Bayou Brawl", "Rust Belt", "Dagestan", "Newark", "Las Vegas"]
	var texts := []
	for o in rules["orgs"]:
		texts.append(str(o["name"]))
	for k in ["first", "last", "nicks", "towns"]:
		for n in rules["names"][k]:
			texts.append(str(n))
	for t in texts:
		for b in banned:
			check(str(t) != b and not (b.length() > 4 and str(t).contains(b)), "'%s' is original (not '%s')" % [t, b])
	check_eq((rules["orgs"] as Array).size(), 9, "nine promotions")
	var tiers := {}
	for o2 in rules["orgs"]:
		tiers[int(o2["tier"])] = int(tiers.get(int(o2["tier"]), 0)) + 1
	check_eq(tiers, {0: 3, 1: 3, 2: 2, 3: 1}, "in four tiers (Cage Rules spread)")


# ---------------------------------------------------------------------------------------------
# Training, healing, gym
# ---------------------------------------------------------------------------------------------

func test_training_gain_matches_cage_rules() -> void:
	var ctrl := new_career()
	ctrl.state["stats"]["power"] = 0.40
	var expect := 0.026 * 1.0 * 1.0 * (pow(0.6, 1.2) + 0.1)
	check_near(ctrl.preview_gain("power"), expect, 0.0000001, "base gain at 0.40")
	ctrl.state["gym"]["power"] = 5
	ctrl.state["gym"]["coach"] = 5
	check_near(ctrl.preview_gain("power"), expect * 2.5 * 1.6, 0.0000001, "L5 room x2.5, L5 coach x1.6")
	check_near(ctrl.preview_gain("speed"), 0.026 * 1.6 * (pow(1.0 - float(ctrl.state["stats"]["speed"]), 1.2) + 0.1), 0.0000001, "the coach counts for every stat, the room only for its own")
	ctrl.state["injury"] = {"head": 60.0, "body": 40.0, "legs": 30.0}
	check_near(ctrl.preview_gain("power"), expect * 2.5 * 1.6 * 0.5, 0.0000001, "130 injury: x0.5")
	ctrl.state["injury"] = {"head": 100.0, "body": 100.0, "legs": 50.0}
	check_near(ctrl.preview_gain("power"), expect * 2.5 * 1.6 * 0.35, 0.0000001, "floored at x0.35")
	ctrl.state["injury"] = {"head": 0.0, "body": 0.0, "legs": 0.0}
	ctrl.state["gym"]["power"] = 0
	ctrl.state["gym"]["coach"] = 0
	var g := ctrl.preview_gain("power")
	var rep := ctrl.train("power")
	check(bool(rep["ok"]), "trained")
	check_near(float(ctrl.state["stats"]["power"]), snappedf(0.40 + g, 0.0001), 0.000001, "the stat grows by the previewed gain (4 dp)")
	check_near(float(rep["gain"]), float(rep["after"]) - float(rep["before"]), 0.000001, "the report shows the gain")
	var row: Dictionary = ctrl.train_rows()[3]
	check_eq(str(row["id"]), "power", "train grid in stat order")
	check_near(float(row["gain"]), ctrl.preview_gain("power"), 0.0000001, "train buttons show the exact model gain")


func test_diminishing_returns_and_cap() -> void:
	var ctrl := new_career()
	var gains := []
	for s in [0.4, 0.6, 0.8, 0.9, 0.95]:
		ctrl.state["stats"]["power"] = s
		gains.append(ctrl.preview_gain("power"))
	for i in range(1, gains.size()):
		check(float(gains[i]) < float(gains[i - 1]), "gains shrink as the stat grows")
	check(float(gains[gains.size() - 1]) > 0.026 * 0.1, "but never stop (floor)")
	ctrl.state["stats"]["power"] = 0.989
	ctrl.train("power")
	check_near(float(ctrl.state["stats"]["power"]), 0.99, 0.000001, "capped at 0.99")
	ctrl.train("power")
	check_near(float(ctrl.state["stats"]["power"]), 0.99, 0.000001, "stays at the cap")
	check(bool(ctrl.stat_rows()[3]["capped"]), "shown as capped")


func test_healing_and_rest() -> void:
	var ctrl := new_career()
	ctrl.state["injury"] = {"head": 30.0, "body": 30.0, "legs": 5.0}
	var cond := ctrl.condition()
	check_eq(str(cond["regions"][0]["level"]), "hurt", "30 is 'hurt'")
	check_eq(str(cond["regions"][2]["level"]), "sore", "5 is 'sore'")
	ctrl.train("chin")
	check_near(float(ctrl.state["injury"]["head"]), 20.0, 0.0001, "a training week heals 10")
	check_near(float(ctrl.state["injury"]["legs"]), 0.0, 0.0001, "never below 0")
	ctrl.state["gym"]["recovery"] = 2
	check_near(ctrl.heal_amount(false), 18.0, 0.0001, "recovery +4 per level")
	check_near(ctrl.heal_amount(true), 45.0, 0.0001, "resting x2.5")
	ctrl.state["injury"] = {"head": 50.0, "body": 0.0, "legs": 0.0}
	var stats_before := sig(ctrl.state["stats"])
	var rep := ctrl.rest()
	check(bool(rep["ok"]), "rested")
	check_near(float(ctrl.state["injury"]["head"]), 5.0, 0.0001, "a rest week heals 45")
	check_eq(sig(ctrl.state["stats"]), stats_before, "no stat gains while resting")
	var rest_row: Dictionary = ctrl.train_rows()[6]
	check_eq(str(rest_row["id"]), "rest", "Rest is the seventh button")
	check(not bool(rest_row["healthy"]) and not str(rest_row["desc"]).contains("healthy"), "no 'healthy' hint while hurt")
	ctrl.state["injury"] = {"head": 0.0, "body": 0.0, "legs": 0.0}
	check(str(ctrl.train_rows()[6]["desc"]).contains("healthy"), "Rest hints that a healthy fighter should train")
	check_eq(str(ctrl.condition()["line"]), "Healthy and ready.", "fight-night line")


func test_weeks_and_idle_popularity() -> void:
	var ctrl := new_career()
	ctrl.state["pop"] = 2.0
	ctrl.train("power")
	check_near(float(ctrl.state["pop"]), 1.4, 0.0001, "an unbooked week costs 0.6 popularity")
	ctrl.state["pop"] = 0.3
	ctrl.train("power")
	check_near(float(ctrl.state["pop"]), 0.0, 0.0001, "never below 0")
	ctrl.state["pop"] = 10.0
	var o: Dictionary = ctrl.state["offers"][0]
	check(ctrl.accept(str(o["id"])), "accept")
	check((ctrl.state["offers"] as Array).is_empty(), "offers cleared once booked")
	check_eq(int(ctrl.booked()["weeks_left"]), int(o["weeks"]), "camp length")
	var weeks := int(o["weeks"])
	for i in weeks:
		check(bool(ctrl.train("speed" if i % 2 == 0 else "rest")["ok"]), "camp week %d" % i)
	check_near(float(ctrl.state["pop"]), 10.0, 0.0001, "camp weeks cost no popularity")
	check(ctrl.fight_ready(), "fight week")
	check_eq((ctrl.booked()["plan"] as Array).size(), weeks, "the plan records every week")
	check(not bool(ctrl.train("power")["ok"]), "no training on fight week")
	check(ctrl.train_rows().is_empty(), "the train grid hides on fight week")
	check(not ctrl.accept("whatever"), "cannot sign twice")


func test_gym_upgrades() -> void:
	var ctrl := new_career()
	var rows := ctrl.upgrade_rows()
	check_eq(rows.size(), 8, "eight facilities")
	check_eq(int(rows[0]["next_cost"]), 1500, "first level costs 1500")
	check_eq(int(rows[7]["next_cost"]), 6000, "the coach costs 6000")
	check(bool(rows[0]["affordable"]) and not bool(rows[7]["affordable"]), "affordability from the bank")
	var r := ctrl.buy_upgrade("stamina")
	check(bool(r["ok"]) and int(r["level"]) == 1, "bought level 1")
	check_eq(int(ctrl.state["money"]), 500, "money spent")
	check(not bool(ctrl.buy_upgrade("stamina")["ok"]), "level 2 (4000) is not affordable")
	check(not bool(ctrl.buy_upgrade("nope")["ok"]), "unknown facility")
	ctrl.state["money"] = 10000000
	ctrl.state["gym"]["power"] = 5
	check(not bool(ctrl.buy_upgrade("power")["ok"]), "level 5 is the top")
	check(bool(ctrl.upgrade_rows()[3]["maxed"]), "shown as maxed")
	var total := 0
	for id in ["stamina", "chin", "speed", "power", "clinch", "defence", "recovery", "coach"]:
		ctrl.state["gym"][id] = 0
	for id2 in ["stamina", "chin", "speed", "power", "clinch", "defence", "recovery", "coach"]:
		for lv in 5:
			total += ctrl.upgrade_cost(id2, lv)
	check_eq(total, 1674500, "a full gym costs $1,674,500 (Cage Rules)")
	check(str(ctrl.news()[0]["text"]).contains("upgraded to level 1"), "news line")


# ---------------------------------------------------------------------------------------------
# Results: popularity, money, record, titles
# ---------------------------------------------------------------------------------------------

func test_popularity_deltas_match_cage_rules() -> void:
	var cases := [
		# [pop, tier, rounds, result, expected delta, label]
		[2.0, 0, 3, ud(0), 4.0, "decision win, tier 0: +4"],
		[30.0, 1, 3, scoring_result(0, "TKO", {"rounds": 1, "stoppage_round": 1}), 16.8, "R1 finish of 3 at tier 1: (4 + 3 + 2 x 2.5) x 1.4"],
		[30.0, 1, 3, scoring_result(0, "TKO", {"rounds": 3, "stoppage_round": 3}), 9.8, "R3 finish of 3 at tier 1: (4 + 3) x 1.4"],
		[55.0, 2, 3, scoring_result(0, "Split Decision"), 5.4, "split win at tier 2: 4 x 1.8 x 0.75"],
		[55.0, 2, 3, scoring_result(0, "Majority Decision"), 7.2, "majority win at tier 2: 4 x 1.8"],
		[10.0, 0, 3, scoring_result(-1, "Split Draw"), 0.5, "draw: +0.5"],
		[80.0, 3, 3, ud(1), -6.6, "decision loss at tier 3: -(3 + 1.5 x 2.4)"],
		[30.0, 1, 3, scoring_result(1, "TKO", {"rounds": 1, "stoppage_round": 1}), -7.1, "R1 finish loss at tier 1: -(3 + 2.1) - 2"],
		[30.0, 1, 3, scoring_result(1, "TKO", {"rounds": 2, "stoppage_round": 2}), -5.1, "a later finish loss: no extra -2"],
		[2.0, 0, 3, ud(0, {"landed": [15, 15]}), 5.5, "fight-of-the-night pace: +1.5"],
		[40.0, 0, 3, ud(0), 2.0, "capped at 42 by tier 0"],
		[42.0, 0, 3, ud(0), 0.0, "nothing more at the cap"],
		[42.0, 0, 3, scoring_result(-1, "Majority Draw"), 0.0, "the cap applies to draws too"],
		[42.0, 0, 3, ud(1), -4.5, "losses are never capped"],
	]
	for c in cases:
		var ctrl := new_career({"seed": 55})
		ctrl.state["pop"] = float(c[0])
		var s := settle(ctrl, {"tier": int(c[1]), "rounds": int(c[2]), "title": false}, c[3])
		check(bool(s["ok"]), "%s: applied (%s)" % [c[5], s.get("error", "")])
		check_near(float(s["d_pop"]), float(c[4]), 0.0001, str(c[5]))
		check_near(float(ctrl.state["pop"]), clampf(float(c[0]) + float(c[4]), 0.0, 100.0), 0.0001, "%s: new popularity" % c[5])
	# streak bonus counts the streak BEFORE this fight
	var st := new_career({"seed": 56})
	st.state["streak"] = 2
	var s2 := settle(st, {"tier": 0, "title": false}, ud(0))
	check_near(float(s2["d_pop"]), 5.5, 0.0001, "a third win in a row: +1.5")
	check_eq(int(st.state["streak"]), 3, "streak +1")
	st.state["streak"] = 1
	var s3 := settle(st, {"tier": 0, "title": false}, ud(0))
	check_near(float(s3["d_pop"]), 4.0, 0.0001, "no bonus after a single win")


func test_record_buckets_streak_and_pay() -> void:
	var ctrl := new_career({"seed": 57})
	var s := settle(ctrl, {"tier": 0, "title": false}, scoring_result(0, "TKO", {"rounds": 2, "stoppage_round": 2, "stoppage_time": 61.5}))
	check(bool(s["finish"]) and str(s["method"]) == "TKO", "a referee stoppage is a finish")
	check_eq(int(s["round"]), 2, "round of the stoppage")
	check_near(float(s["time"]), 61.5, 0.001, "time into the round")
	check_eq(int(ctrl.state["record"]["tko"]), 1, "TKO bucket")
	check_eq(int(ctrl.state["money"]), 2000 + int(s["purse"]) + int(s["bonus"]), "a win pays purse + bonus")
	var money := int(ctrl.state["money"])
	var s2 := settle(ctrl, {"tier": 0, "title": false}, ud(0))
	check_eq(int(ctrl.state["record"]["dec"]), 1, "decision bucket")
	check_eq(int(ctrl.state["streak"]), 2, "two in a row")
	check_eq(ctrl.streak_text(), "2 in a row", "header streak")
	money += int(s2["purse"]) + int(s2["bonus"])
	var s3 := settle(ctrl, {"tier": 0, "title": false}, scoring_result(-1, "Unanimous Draw"))
	check_eq(int(ctrl.state["record"]["d"]), 1, "draw")
	check_eq(int(ctrl.state["streak"]), 0, "a draw resets the streak")
	check_eq(int(ctrl.state["money"]), money + int(s3["purse"]), "a draw pays the purse only")
	money = int(ctrl.state["money"])
	var s4 := settle(ctrl, {"tier": 0, "title": false}, ud(1))
	check_eq(int(ctrl.state["record"]["l"]), 1, "loss")
	check_eq(int(ctrl.state["streak"]), -1, "losing streak")
	check_eq(int(ctrl.state["money"]), money + int(s4["purse"]), "a loss pays the purse only")
	check_eq(CareerState.record_text(ctrl.state["record"]), "2-1-1", "W-L-D")
	check_eq((ctrl.state["history"] as Array).size(), 4, "every fight in the history")
	var h: Dictionary = ctrl.history()[0]
	check_eq(str(h["result"]), "loss", "newest first")
	check_eq(h["totals"], [[27, 30], [28, 29], [28, 29]], "compact card totals, career fighter first")
	check(str(ctrl.news()[0]["text"]).begins_with("Lost to"), "news line for the fight")
	# HP-scoring results (no judges) still settle
	var hp := settle(ctrl, {"tier": 0, "title": false}, hp_result(0, true))
	check(bool(hp["ok"]) and bool(hp["finish"]) and str(hp["method"]) == "KO", "an HP-scoring KO is a finish: %s" % hp.get("error", ""))
	check_eq(int(ctrl.state["record"]["tko"]), 2, "into the stoppage bucket")
	var hp2 := settle(ctrl, {"tier": 0, "title": false}, hp_result(-1))
	check(bool(hp2["ok"]) and bool(hp2["draw"]), "winner_team -1 is a draw")
	var bad := new_career({"seed": 58})
	var o := book(bad, {})
	check(not bool(bad.apply_result({"winner_team": -2, "fighters": []}, str(o["id"]))["ok"]), "an undecided result is refused")
	check(bad.is_booked(), "and changes nothing")


func test_purse_and_bonus_formulas() -> void:
	var ctrl := new_career({"seed": 60})
	var rules := ctrl.rules
	for pop in [2.0, 20.0, 40.0, 60.0, 85.0, 95.0]:
		ctrl.state["pop"] = pop
		for wk in range(1, 25):
			ctrl.state["week"] = wk
			for o in CareerOffers.make_offers(cat(), rules, ctrl.state):
				var org := CareerState.org(rules, str(o["org"]))
				var purse := int(o["purse"])
				var weeks := int(o["weeks"])
				check_eq(purse % 50, 0, "purses round to $50")
				var pop_in := clampf((pop - float(org["pop"])) / 30.0, 0.0, 1.0)
				var prem := 1.0 + (10 - weeks) * 0.03
				var mult := 2.5 if bool(o["title"]) else 1.0
				var lo := lerpf(float(org["purse"][0]), float(org["purse"][1]), pop_in * 0.7) * prem * mult
				var hi := lerpf(float(org["purse"][0]), float(org["purse"][1]), pop_in * 0.7 + 0.3) * prem * mult
				check(purse >= lo - 25.0 and purse <= hi + 25.0, "%s purse %d in [%.0f, %.0f]" % [o["org"], purse, lo, hi])
				var frac := 1.0 if int(o["tier"]) == 3 else 0.6
				check_eq(int(o["bonus"]), int(round(purse * frac / 50.0)) * 50, "win bonus %d%% of the purse" % int(frac * 100))
				if bool(o["title"]):
					check(weeks == 10 and int(o["rounds"]) == 5, "title fights: 10-week camp, 5 rounds")


func test_title_shot_champion_defences_and_belt_loss() -> void:
	var ctrl := new_career({"seed": 61})
	ctrl.state["pop"] = 91.9
	ctrl.state["week"] = 40
	ctrl._roll_offers(false)
	for o in ctrl.state["offers"]:
		check(not bool(o["title"]), "no title shot below 92")
	ctrl.state["pop"] = 92.0
	ctrl._roll_offers(false)
	var t: Dictionary = ctrl.state["offers"][0]
	check(bool(t["title"]) and not bool(t["defence"]), "at 92 the champion agrees to fight you (offer 0)")
	check_eq(str(t["org"]), "grand_circuit", "the top promotion holds the belt")
	check_eq(int(t["rounds"]), 5, "five rounds")
	check(float(t["opp"]["level"]) >= 0.9, "a champion-level opponent")
	check(str(ctrl.hints()["lines"][0]).contains("champion has agreed"), "offers hint")
	check(ctrl.accept(str(t["id"])), "accept the title fight")
	ctrl.state["booked"]["weeks_left"] = 0
	var s := ctrl.apply_result(scoring_result(0, "Unanimous Decision", {"rounds": 5}), str(t["id"]))
	check(bool(s["ok"]), "applied")
	check(bool(ctrl.state["champion"]) and int(ctrl.state["title_defences"]) == 0, "new champion")
	check_eq(str(s["title_note"]), "NEW GRAND CIRCUIT CHAMPION", "title note")
	check_near(float(s["d_pop"]), 8.0, 0.0001, "title win +6 on top of 9.6, capped at 100")
	check_eq(ctrl.standing()["text"], "Grand Circuit Champion", "standing")
	check(str(ctrl.hints()["lines"][0]).contains("You are the champion"), "champion hint")
	var d: Dictionary = ctrl.state["offers"][0]
	check(bool(d["title"]) and bool(d["defence"]), "the champion's first offer is a title defence")
	check(str(d["note"]).contains("Title defence"), "defence note")
	check(ctrl.accept(str(d["id"])), "accept the defence")
	ctrl.state["booked"]["weeks_left"] = 0
	var s2 := ctrl.apply_result(scoring_result(0, "Split Decision", {"rounds": 5}), str(d["id"]))
	check_eq(int(ctrl.state["title_defences"]), 1, "defended once")
	check_eq(str(s2["title_note"]), "Title defended (1)", "note")
	var d2: Dictionary = ctrl.state["offers"][0]
	check(ctrl.accept(str(d2["id"])), "next defence")
	ctrl.state["booked"]["weeks_left"] = 0
	ctrl.apply_result(scoring_result(-1, "Split Draw", {"rounds": 5}), str(d2["id"]))
	check(bool(ctrl.state["champion"]) and int(ctrl.state["title_defences"]) == 1, "a draw keeps the belt (no defence counted)")
	# a non-title loss never costs the belt
	var nt: Dictionary = ctrl.state["offers"][ctrl.state["offers"].size() - 1]
	nt["title"] = false
	nt["defence"] = false
	check(ctrl.accept(str(nt["id"])), "a non-title fight")
	ctrl.state["booked"]["weeks_left"] = 0
	ctrl.apply_result(ud(1), str(nt["id"]))
	check(bool(ctrl.state["champion"]), "still champion after a non-title loss")
	var d3: Dictionary = ctrl.state["offers"][0]
	check(bool(d3["title"]), "title defence offered")
	check(ctrl.accept(str(d3["id"])), "defend")
	ctrl.state["booked"]["weeks_left"] = 0
	var pop := float(ctrl.state["pop"])
	var s3 := ctrl.apply_result(ud(1, {"rounds": 5}), str(d3["id"]))
	check(not bool(ctrl.state["champion"]), "a title loss costs the belt")
	check_eq(str(s3["title_note"]), "Belt lost", "note")
	check_near(float(s3["d_pop"]), -9.6, 0.0001, "title loss: -(3 + 3.6) - 3")
	check_near(float(ctrl.state["pop"]), pop - 9.6, 0.0001, "popularity")


func test_withdraw() -> void:
	new_store()
	var ctrl := new_career({}, true)
	ctrl.state["pop"] = 10.0
	var o := book(ctrl, {})
	var money := int(ctrl.state["money"])
	var week := int(ctrl.state["week"])
	var rec := sig(ctrl.state["record"])
	var inj := sig(ctrl.state["injury"])
	check(ctrl.withdraw(), "pulled out")
	check_near(float(ctrl.state["pop"]), 6.0, 0.0001, "popularity -4")
	check_eq(int(ctrl.state["week"]), week + 1, "week +1")
	check_eq(int(ctrl.state["money"]), money, "no purse")
	check_eq(sig(ctrl.state["record"]), rec, "record unchanged")
	check_eq(sig(ctrl.state["injury"]), inj, "injuries unchanged")
	check(not ctrl.is_booked() and not (ctrl.state["offers"] as Array).is_empty(), "new offers")
	check(str(ctrl.state["offers"][0]["id"]).begins_with("w%d" % (week + 1)), "for the new week")
	check(str(ctrl.news()[0]["text"]).contains("Pulled out"), "news line")
	check(not bool(ctrl.apply_result(ud(0), str(o["id"]))["ok"]), "a late result for the withdrawn fight is refused")
	var back := store.load_slot("tester", 1, cat())
	check_eq(sig(back["state"]), sig(ctrl.state), "the withdrawal was autosaved")
	ctrl.state["pop"] = 1.0
	book(ctrl, {})
	ctrl.withdraw()
	check_near(float(ctrl.state["pop"]), 0.0, 0.0001, "never below 0")
	check(not ctrl.withdraw(), "nothing booked")


func test_duplicate_result_rejected() -> void:
	var ctrl := new_career({"seed": 62})
	var o := book(ctrl, {"tier": 0})
	var res := ud(0)
	var s := ctrl.apply_result(res, str(o["id"]))
	check(bool(s["ok"]), "first result applies")
	var before := sig(ctrl.state)
	var s2 := ctrl.apply_result(res, str(o["id"]))
	check(not bool(s2["ok"]) and bool(s2["duplicate"]), "the same fight id is claimed once")
	var s3 := ctrl.apply_result(res)
	check(not bool(s3["ok"]), "an anonymous repeat finds no booked fight")
	check_eq(sig(ctrl.state), before, "nothing changed")
	check((ctrl.state["claims"] as Array).has(str(o["id"])), "claimed")


## D4: a bout interrupted by a crash (saved with in_fight, never reported) is re-fought on load
## with the same seed, opponent, bot and arena, and its result still applies exactly once.
func test_interrupted_fight_is_refought_with_the_same_seed() -> void:
	new_store()
	var ctrl := new_career({"seed": 63}, true)
	var o: Dictionary = ctrl.state["offers"][0]
	check(ctrl.accept(str(o["id"])), "accept")
	while not ctrl.fight_ready():
		ctrl.train("power")
	check(not ctrl.interrupted(), "not started yet")
	var cfg1 := ctrl.fight_config()
	check((cfg1["errors"] as PackedStringArray).is_empty(), "the bout builds: %s" % [cfg1["errors"]])
	check(ctrl.begin_fight(), "launch: %s" % ctrl.last_error)
	var on_disk := store.load_slot("tester", 1, cat())
	check(bool(on_disk["state"]["booked"]["in_fight"]), "the in-fight marker was saved before the bout")
	# ...the process dies mid-fight; the career is loaded again
	var r := CareerController.load_career(cat(), store, "tester", 1)
	check(bool(r["ok"]), "loads: %s" % r["error"])
	var back: CareerController = r["ctrl"]
	check(back.interrupted() and back.fight_ready(), "the interrupted bout is waiting")
	var cfg2 := back.fight_config()
	check_eq(int(cfg2["seed"]), int(cfg1["seed"]), "same fight seed")
	check_eq(int(cfg2["seed"]), RunRng.derive(int(ctrl.state["seed"]), "fight/%s" % o["id"]) & 0x7FFFFFFF, "seed derived from the career seed and the offer id")
	check_eq(sig(back.booked()["offer"]["opp"]), sig(o["opp"]), "same opponent")
	var f1: Array = cfg1["config"]["fighters"]
	var f2: Array = cfg2["config"]["fighters"]
	check_eq((f2[1]["creature"] as CreatureDef).id, (f1[1]["creature"] as CreatureDef).id, "same opponent creature")
	check_eq(sig(f2[1]["mods"]), sig(f1[1]["mods"]), "same opponent build")
	check_eq(sig(f2[0]["mods"]), sig(f1[0]["mods"]), "same career fighter build")
	check_eq((cfg2["config"]["arena"] as ArenaDef).id, (cfg1["config"]["arena"] as ArenaDef).id, "same arena")
	check_eq(str((f2[1]["source"] as BotBrain).label_text), str((f1[1]["source"] as BotBrain).label_text), "same bot tier")
	check(back.begin_fight(), "re-fought")
	check_eq(int(back.booked()["starts"]), 2, "two launches recorded")
	var s := back.apply_result(ud(0), str(o["id"]))
	check(bool(s["ok"]), "the re-fought result applies: %s" % s.get("error", ""))
	check(not bool(back.apply_result(ud(0), str(o["id"]))["ok"]), "once")
	check(not back.interrupted(), "nothing pending")


# ---------------------------------------------------------------------------------------------
# Read helpers (D7)
# ---------------------------------------------------------------------------------------------

func test_standing_danger_and_hints() -> void:
	var r := CareerDefaults.rules()
	check_eq(CareerController.standing_of(r, 74.0, false)["contender"], 15, "#15 at 74")
	check_eq(CareerController.standing_of(r, 80.0, false)["text"], "#10 contender · The Big League", "#10 at 80")
	check_eq(CareerController.standing_of(r, 92.0, false)["contender"], 1, "#1 at 92")
	check_eq(CareerController.standing_of(r, 30.0, false)["text"], "National · Regional champion material", "tier + popularity label")
	check_eq(CareerController.standing_of(r, 95.0, true)["text"], "Grand Circuit Champion", "champion")
	check_eq(CareerState.pop_label(r, 2.0), "Unknown", "label")
	check_eq(CareerState.pop_label(r, 92.0), "Superstar", "label")
	check_eq(CareerOffers.danger(r, -8), "FAVOURED", "<= -8")
	check_eq(CareerOffers.danger(r, -7), "EVEN", "-7")
	check_eq(CareerOffers.danger(r, 6), "EVEN", "<= 6")
	check_eq(CareerOffers.danger(r, 16), "UNDERDOG", "<= 16")
	check_eq(CareerOffers.danger(r, 17), "LONG SHOT", "else")
	var ctrl := new_career({"seed": 64})
	check_eq(str(ctrl.hints()["lines"][0]), "Next up: Rust Bucket Fight Series starts calling at popularity 6 (you are at 2).", "next-promotion hint")
	var row: Dictionary = ctrl.offer_rows()[0]
	for k in ["org_name", "tier_name", "billed", "record_text", "rating", "danger", "bot_tier", "bot_tier_name", "purse", "bonus", "weeks", "rounds_label"]:
		check(row.has(k), "offer rows carry %s" % k)
	check_eq(str(row["rounds_label"]), "3 × 1:39", "rounds display")
	check_eq(int(row["danger_diff"]), int(row["rating"]) - ctrl.rating(), "danger from the rating difference")
	book(ctrl, {})
	var card := ctrl.fight_card()
	check_eq((card["rows"] as Array).size(), 6, "six-row stat comparison")
	check(card["me"].has("rating") and card["opp"].has("danger") and card["opp"].has("bot_tier_name"), "card sides")
	check(bool(card["fight_week"]), "fight week")
	var hd := ctrl.header()
	for k2 in ["billed", "record_text", "money_text", "week_label", "pop", "pop_label", "standing", "streak_text", "rating"]:
		check(hd.has(k2), "header carries %s" % k2)
	check_eq(str(hd["billed"]), "Tester \"The Test\"", "name \"nick\"")
	check_eq(CareerController.money_text(1674500), "$1,674,500", "money format")
	check_eq(CareerFight.billed_name("Rivet Gravelgut", "Low Tide"), "Rivet \"Low Tide\" Gravelgut", "ring name")
