extends CampaignTestCase
## CMP-06 / CNT-07: seeded, reproducible, valid fight cards; pacing; reward rarity rules.


func test_same_seed_same_card() -> void:
	var a := RunState.create(cat(), run_cfg("f_stoke", {"seed": 777}))
	var b := RunState.create(cat(), run_cfg("f_stoke", {"seed": 777}))
	check_eq(JSON.stringify(a["acts"]), JSON.stringify(b["acts"]), "same seed + fighter + difficulty must produce the same card")
	var c := RunState.create(cat(), run_cfg("f_stoke", {"seed": 778}))
	check(JSON.stringify(a["acts"]) != JSON.stringify(c["acts"]), "different seeds should produce different cards")


func test_seed_text_round_trip() -> void:
	for s in [1, 777, 123456789012345, RunRng.normalize_seed(RunRng.derive(5, "x")), RunRng.fresh_seed()]:
		check_eq(RunRng.text_to_seed(RunRng.seed_to_text(s)), s, "seed text round trip for %d" % s)
		check(s <= RunRng.SEED_MASK, "run seeds fit in 53 bits")
		var back = JSON.parse_string(JSON.stringify({"seed": s}, "", false, true))
		check_eq(int(back["seed"]), s, "a run seed survives a JSON round trip exactly")
	check(RunRng.text_to_seed("hello world") != 0, "free text seeds hash to a seed")
	check_eq(RunRng.text_to_seed("hello world"), RunRng.text_to_seed("hello world"), "free text seeds are stable")


func test_streams_independent_of_call_order() -> void:
	var r1 := RunRng.stream(99, "node/a1r2l0/reward/p0/0")
	var x1 := r1.range_i(0, 1000000)
	var _noise := RunRng.stream(99, "something/else").range_i(0, 100)
	var r2 := RunRng.stream(99, "node/a1r2l0/reward/p0/0")
	check_eq(r2.range_i(0, 1000000), x1, "a stream depends only on (seed, key)")


func test_map_validity_500_seeds() -> void:
	var fighters := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters"]
	var pacing: Dictionary = cat().rules.get("pacing", {})
	var bad := 0
	var min_total := INF
	var max_total := 0.0
	var fights_min := 99
	var fights_max := 0
	var types_seen := {}
	var fallbacks := 0
	for s in range(1, 501):
		var st := RunState.create(cat(), run_cfg(fighters[s % 6], {"seed": s * 7919, "dose": s % 11}))
		var run_min := 0.0
		var run_max := 0.0
		var run_fmin := 0
		var run_fmax := 0
		for m in st["acts"]:
			if int(m.get("attempt", 0)) < 0:
				fallbacks += 1
			var probs := ActMap.problems(m, cat().rules)
			if not probs.is_empty():
				bad += 1
				if bad <= 5:
					fail("seed %d act %d: %s" % [s, m["act"], probs[0]])
			var amin := INF
			var amax := 0.0
			var kmin := 99
			var kmax := 0
			for p in ActMap.all_paths(m):
				var secs := ActMap.path_seconds(m, p, pacing)
				amin = minf(amin, secs)
				amax = maxf(amax, secs)
				var k := ActMap.path_fights(m, p) + 2   # row 1 fight + boss
				kmin = mini(kmin, k)
				kmax = maxi(kmax, k)
			run_min += amin + float(pacing.get("act_transition", 30))
			run_max += amax + float(pacing.get("act_transition", 30))
			run_fmin += kmin
			run_fmax += kmax
			for id in m["nodes"]:
				types_seen[str(m["nodes"][id]["type"])] = true
		min_total = minf(min_total, run_min)
		max_total = maxf(max_total, run_max)
		fights_min = mini(fights_min, run_fmin)
		fights_max = maxi(fights_max, run_fmax)
	check_eq(bad, 0, "maps with violated generator rules")
	check(fallbacks <= 5, "the hand-built fallback layout should be (almost) never needed (%d of 1500 acts)" % fallbacks)
	check(min_total / 60.0 >= float(pacing.get("target_min", 25)) - 0.01, "shortest route %.1f min must be >= 25 min" % (min_total / 60.0))
	check(max_total / 60.0 <= float(pacing.get("target_max", 40)) + 0.01, "longest route %.1f min must be <= 40 min" % (max_total / 60.0))
	check(fights_min >= 12 and fights_max <= 15, "fights per run %d..%d must stay within 12..15" % [fights_min, fights_max])
	for t in ["fight", "elite", "event", "shop", "rest", "mystery", "boss"]:
		check(types_seen.has(t), "node type %s appears" % t)


func test_every_node_resolves_to_valid_content() -> void:
	for s in range(1, 41):
		var st := RunState.create(cat(), run_cfg("f_jitters", {"seed": s * 31}))
		for m in st["acts"]:
			for id in m["nodes"]:
				var n: Dictionary = m["nodes"][id]
				match str(n["type"]):
					"fight", "elite", "boss":
						check(cat().encounters.has(str(n["encounter"])), "%s encounter %s exists" % [id, n["encounter"]])
						var tier := str(cat().encounters[str(n["encounter"])].get("tier", ""))
						check_eq(tier, "normal" if n["type"] == "fight" else str(n["type"]), "%s tier" % id)
						check_eq(int(cat().encounters[str(n["encounter"])].get("act", 0)), int(m["act"]), "%s act" % id)
					"event":
						check(cat().events.has(str(n["event"])), "%s event exists" % id)
					"mystery":
						var h: Dictionary = n["hidden"]
						check(str(h.get("type", "")) in ["fight", "event", "shop", "treasure"], "%s mystery result" % id)


func test_varied_cards() -> void:
	# visibly different seeded runs: different encounters, events and enemies across seeds
	var encs := {}
	var evts := {}
	for s in range(1, 21):
		var st := RunState.create(cat(), run_cfg("f_gusto", {"seed": s * 101}))
		var sig := []
		for m in st["acts"]:
			for id in m["nodes"]:
				var n: Dictionary = m["nodes"][id]
				if str(n.get("encounter", "")) != "":
					encs[str(n["encounter"])] = true
				if str(n.get("event", "")) != "":
					evts[str(n["event"])] = true
	check(encs.size() >= 30, "20 seeds should use most encounters (got %d)" % encs.size())
	check(evts.size() >= 18, "20 seeds should use most eligible events (got %d)" % evts.size())


func test_dose10_forces_commissioners_cut() -> void:
	var st := RunState.create(cat(), run_cfg("f_stoke", {"seed": 4242, "dose": 10}))
	for id in st["acts"][2]["nodes"]:
		var n: Dictionary = st["acts"][2]["nodes"][id]
		if str(n["type"]) == "elite":
			check_eq(str(n["encounter"]), "elite_a3_commissioners_cut", "Dose 10 Title Card elite")


func test_rarity_guarantees_and_distinct_offers() -> void:
	var ctrl := new_run({"seed": 9})
	var p := ctrl.player("p0")
	for i in 60:
		var elite := RewardRoller.supplement_offer(cat(), ctrl.state, p, "t/elite/%d" % i, {"source": "elite", "n": 3, "min_rarity": "prescription"})
		check_eq(elite.size(), 3, "elite offers 3")
		var has_rx := false
		var seen := {}
		for id in elite:
			check(not seen.has(id), "offers are distinct")
			seen[id] = true
			if RewardRoller.rarity_index(str(cat().supplements[id]["rarity"])) >= 1:
				has_rx = true
		check(has_rx, "elite offer has a Prescription+")
		var boss := RewardRoller.supplement_offer(cat(), ctrl.state, p, "t/boss/%d" % i, {"source": "boss", "n": 3, "min_rarity": "black_market", "banned_chance": 0.05})
		var has_bm := false
		for id2 in boss:
			if RewardRoller.rarity_index(str(cat().supplements[id2]["rarity"])) >= 2:
				has_bm = true
		check(has_bm, "boss offer has a Black Market+")
	# items at max stack / owned gear are never offered
	p["supplements"] = [{"id": "sup_mouthguard", "stacks": 1}, {"id": "sup_marrow_shake", "stacks": 2}]
	for j in 80:
		var o := RewardRoller.supplement_offer(cat(), ctrl.state, p, "t/x/%d" % j, {"source": "fight", "n": 3})
		check(not o.has("sup_mouthguard") and not o.has("sup_marrow_shake"), "maxed items excluded")


func test_synergy_weights_favor_owned_tags() -> void:
	var ctrl := new_run({"seed": 10})
	var p := ctrl.player("p0")
	var counts_plain := 0
	var counts_syn := 0
	for i in 400:
		for id in RewardRoller.supplement_offer(cat(), ctrl.state, p, "s/%d" % i, {"source": "fight", "n": 3}):
			if (cat().supplements[id].get("tags", []) as Array).has("tank"):
				counts_plain += 1
	p["supplements"] = [{"id": "sup_cartilage_chews", "stacks": 1}, {"id": "sup_bulk_powder", "stacks": 1}]
	for i in 400:
		for id in RewardRoller.supplement_offer(cat(), ctrl.state, p, "s/%d" % i, {"source": "fight", "n": 3}):
			if (cat().supplements[id].get("tags", []) as Array).has("tank"):
				counts_syn += 1
	check(counts_syn > counts_plain, "holding 2 tank items raises tank offers (%d vs %d)" % [counts_syn, counts_plain])
