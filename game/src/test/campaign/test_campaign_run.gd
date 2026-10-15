extends CampaignTestCase
## CMP-01/02/05/07, COOP-06, SAV-03 (duplicates): run state machine with synthetic fight results.


func test_synthetic_run_to_victory() -> void:
	var ctrl := new_run({"seed": 31337})
	var acts_seen := {}
	var n := 0
	while not ctrl.is_over() and n < 40:
		acts_seen[int(ctrl.state["act"])] = true
		var av := ctrl.available_nodes()
		check(not av.is_empty(), "the map always offers a route (no softlock)")
		if av.is_empty():
			return
		check(ctrl.choose_node(str(av[0]), "p0"), "choose node: %s" % ctrl.last_error)
		settle_node(ctrl)
		n += 1
	check_eq(ctrl.phase(), "victory", "run ends in victory")
	check_eq(acts_seen.size(), 3, "all three acts visited")
	check_eq(n, 21, "3 acts x (6 rows + boss) = 21 nodes")
	var res := ctrl.summary()
	check(bool(res.get("victory", false)), "summary says victory")
	check(int(ctrl.player("p0")["clout"]) >= 150, "run clear Clout accrued")


func test_synthetic_defeat_ends_run() -> void:
	var ctrl := new_run({"seed": 5})
	play_synthetic(ctrl, 1)
	check_eq(ctrl.phase(), "defeat", "losing a fight ends the run")
	check(not ctrl.choose_node("a1r2l0", "p0"), "no routes after defeat")
	check(not bool(ctrl.summary()["victory"]), "summary says defeat")


func test_fight_rewards_and_hp_carry() -> void:
	var ctrl := new_run({"seed": 77})
	var start_scrip := int(ctrl.player("p0")["scrip"])
	check_eq(start_scrip, 60, "Off the Street starts with 60 Scrip")
	ctrl.choose_node(str(ctrl.available_nodes()[0]), "p0")
	check_eq(ctrl.phase(), "fight", "row 1 is a fight")
	check(not ctrl.current_plan().is_empty(), "fight plan stored in the node session")
	ctrl.complete_fight(fake_result(ctrl, true, 0.5))
	var p := ctrl.player("p0")
	check(int(p["scrip"]) >= start_scrip + 40 and int(p["scrip"]) <= start_scrip + 70, "fight Scrip 40-70 (got %d)" % (int(p["scrip"]) - start_scrip))
	check_near(float(p["hp"]), ctrl.max_hp(p) * 0.5, 0.01, "HP carries out of the fight")
	check_near(float(p["hype_carry"]), 20.0, 0.01, "Hype carries at 50%")
	check_eq(ctrl.phase(), "reward", "fight win opens rewards")
	var pend := ctrl.pending_for("p0")
	check_eq(pend.size(), 1, "one supplement pick")
	check_eq((pend[0]["options"] as Array).size(), 3, "pick from 3")


func test_duplicate_rewards_are_rejected() -> void:
	var ctrl := new_run({"seed": 78})
	ctrl.choose_node(str(ctrl.available_nodes()[0]), "p0")
	var result := fake_result(ctrl)
	check(ctrl.complete_fight(result), "first fight result applies")
	var scrip_after := int(ctrl.player("p0")["scrip"])
	check(not ctrl.complete_fight(result), "second identical fight result is rejected")
	check_eq(int(ctrl.player("p0")["scrip"]), scrip_after, "no duplicate Scrip")
	var e: Dictionary = ctrl.pending_for("p0")[0]
	var rid := str(e["rid"])
	var choice := str(e["options"][0])
	# keep a copy of the claim to resend it
	var before := (ctrl.player("p0")["supplements"] as Array).size()
	check(ctrl.claim("p0", rid, choice), "claim once")
	check(not ctrl.claim("p0", rid, choice), "claiming the same reward again is rejected")
	check_eq((ctrl.player("p0")["supplements"] as Array).size(), before + 1, "exactly one supplement granted")


func test_reroll_costs_and_limits() -> void:
	var ctrl := new_run({"seed": 79})
	ctrl.choose_node(str(ctrl.available_nodes()[0]), "p0")
	ctrl.complete_fight(fake_result(ctrl))
	var p := ctrl.player("p0")
	p["scrip"] = 100
	var rid := str(ctrl.pending_for("p0")[0]["rid"])
	var first: Array = (ctrl.pending_for("p0")[0]["options"] as Array).duplicate()
	check(ctrl.reroll("p0", rid), "reroll 1")
	check_eq(int(p["scrip"]), 70, "reroll costs 30 Scrip")
	check(JSON.stringify(first) != JSON.stringify(ctrl.pending_for("p0")[0]["options"]), "reroll changes the offer")
	check(ctrl.reroll("p0", rid), "reroll 2")
	check(not ctrl.reroll("p0", rid), "max 2 rerolls per node")


func test_shop_rest_event_flows() -> void:
	# find a seed whose first rows offer a shop/rest/event quickly via direct session setup
	var ctrl := new_run({"seed": 4040})
	var p := ctrl.player("p0")
	p["scrip"] = 500
	# drive to the first row-6 node (rest or shop) using synthetic fights
	var reached_shop := false
	var reached_rest := false
	var n := 0
	while not ctrl.is_over() and n < 8:
		var av := ctrl.available_nodes()
		var pick := str(av[0])
		for id in av:
			if ctrl.visible_type(str(id)) in ["shop", "rest"]:
				pick = str(id)
		ctrl.choose_node(pick, "p0")
		n += 1
		if ctrl.phase() == "shop":
			reached_shop = true
			var v := ctrl.shop_view("p0")
			check(v["items"].size() >= 4, "shop shows supplements + technique")
			var bought := false
			for it in v["items"]:
				if not bought and int(it["price"]) <= int(p["scrip"]):
					bought = ctrl.shop_buy("p0", str(it["slot"]))
					check(not ctrl.shop_buy("p0", str(it["slot"])), "a slot cannot be bought twice")
			check(bought, "bought something")
			ctrl.shop_leave("p0")
		elif ctrl.phase() == "rest":
			reached_rest = true
			p["hp"] = 10.0
			check(ctrl.rest_choose("p0", "patch_up"), "patch up")
			check(float(p["hp"]) > 10.0, "rest healed")
			check(not ctrl.rest_choose("p0", "patch_up"), "only one rest choice")
		settle_node(ctrl)
	check(reached_shop or reached_rest, "reached a shop or rest node")


func test_event_choice_and_outcome() -> void:
	var ctrl := new_run({"seed": 900})
	# put the run into an event node directly (any event node on the act 1 map)
	var m := RunState.current_map(ctrl.state)
	var evt_node := ""
	for id in m["nodes"]:
		if str(m["nodes"][id]["type"]) == "event":
			evt_node = str(id)
	check(evt_node != "", "act 1 has an event")
	# walk a valid path to it is not needed: force the session the way choose_node builds it
	ctrl.state["position"] = ""
	ctrl.state["phase"] = "map"
	var path := _path_to(m, evt_node)
	for i in path.size():
		if i < path.size() - 1:
			ctrl.choose_node(str(path[i]), "p0")
			settle_node(ctrl)
		else:
			ctrl.choose_node(str(path[i]), "p0")
	check_eq(ctrl.phase(), "event", "entered the event")
	var v := ctrl.event_view("p0")
	check(not str(v["title"]).is_empty() and not str(v["text"]).is_empty(), "event has text")
	check(not (v["choices"] as Array).is_empty(), "event has choices")
	var c := CampaignAutoPilot.choose_event(ctrl, "p0")
	check(ctrl.choose_event("p0", c), "choose event: %s" % ctrl.last_error)
	check(not ctrl.choose_event("p0", c), "an event is decided once")


func _path_to(m: Dictionary, target: String) -> Array:
	for p in ActMap.all_paths(m):
		var i: int = p.find(target)
		if i >= 0:
			return p.slice(0, i + 1)
	return []


func test_ladder_unlock_rule() -> void:
	var prof := Profiles.default_profile("t", "T")
	CampaignProgression.ensure_fields(prof)
	check_eq(CampaignProgression.max_selectable_dose(prof, "off_the_street"), 0, "The Dosage starts closed")
	check_eq(CampaignProgression.apply_ladder_clear(prof, "off_the_street", 0, false), 0, "a Sparring clear does not open it")
	check_eq(CampaignProgression.apply_ladder_clear(prof, "off_the_street", 0, true), 1, "first Amateur+ clear opens Dose 1")
	check_eq(CampaignProgression.max_selectable_dose(prof, "off_the_street"), 1, "Dose 1 selectable")
	check_eq(CampaignProgression.apply_ladder_clear(prof, "off_the_street", 1, true), 2, "clearing the highest (1) unlocks 2")
	check_eq(CampaignProgression.apply_ladder_clear(prof, "off_the_street", 1, true), 0, "clearing a lower Dose unlocks nothing")
	for d in range(2, 12):
		CampaignProgression.apply_ladder_clear(prof, "off_the_street", mini(d, 10), true)
	check_eq(CampaignProgression.max_selectable_dose(prof, "off_the_street"), 10, "max Dose 10")
	check_eq(int(prof["ladder"]["off_the_street"]["unlocked"]), 10, "never above 10")
	check_eq(CampaignProgression.max_selectable_dose(prof, "fight_camp"), 0, "variants have separate ladders")


func test_finish_run_progression_off_the_street() -> void:
	var prof := Profiles.default_profile("t", "T")
	prof["camp"]["upgrades"] = {"meta_heavy_bag": 3}
	var ctrl := new_run({"seed": 101})
	play_synthetic(ctrl)
	check_eq(ctrl.phase(), "victory", "victory")
	var rep := CampaignProgression.finish_run(cat(), ctrl.state, "p0", prof)
	check(bool(rep["ladder_open"]), "first Amateur clear opens The Dosage")
	check(int(rep["clout"]) > 0, "Off the Street earns (cosmetic) Clout")
	check_eq(int(prof["camp"]["clout"]), 0, "Off the Street Clout never becomes Fight Camp power")
	check(int(prof["unlocks"]["cosmetic_clout"]) > 0, "it goes to the cosmetics wallet")
	check((prof["unlocks"]["cosmetics"] as Array).has("title_f_stoke"), "fighter title cosmetic on first clear")
	check_eq(int(prof["records"]["runs"]["off_the_street"]["clears"]), 1, "clear recorded")
	check_eq((prof["history"] as Array).size(), 1, "history entry")
	var again := CampaignProgression.finish_run(cat(), ctrl.state, "p0", prof)
	check(bool(again["duplicate"]), "crediting the same run twice is rejected")
	check_eq(int(prof["records"]["runs"]["off_the_street"]["clears"]), 1, "no double credit")


func test_custom_runs_keep_stats_but_no_records() -> void:
	var prof := Profiles.default_profile("t", "T")
	var ctrl := new_run({"seed": 102, "custom": true, "custom_reasons": ["game speed 0.8"]})
	play_synthetic(ctrl)
	var rep := CampaignProgression.finish_run(cat(), ctrl.state, "p0", prof)
	check(not bool(rep["ladder_open"]), "custom runs never unlock The Dosage")
	check((rep["records"] as Array).is_empty(), "custom runs set no records")
	check_eq(int(prof["records"]["runs"]["off_the_street"]["attempts"]), 1, "but count as an attempt")
	check(bool(prof["history"][0]["custom"]), "history marks the run custom")
	var normal := new_run({"seed": 102})
	play_synthetic(normal)
	check(CampaignProgression.clout_for(cat(), ctrl.state, ctrl.player("p0")) < CampaignProgression.clout_for(cat(), normal.state, normal.player("p0")),
		"custom runs earn reduced Clout")


func test_fight_camp_meta_applies_only_in_fight_camp() -> void:
	var meta := {"meta_squat_rack": 3, "meta_heavy_bag": 2, "meta_sponsorship": 1}
	var cfg_ots := run_cfg("f_stoke", {"seed": 5})
	cfg_ots["players"][0]["meta"] = meta
	var ots := RunController.start_run(cat(), cfg_ots)
	var cfg_fc := run_cfg("f_stoke", {"seed": 5, "variant": "fight_camp"})
	cfg_fc["players"][0]["meta"] = meta
	var fc := RunController.start_run(cat(), cfg_fc)
	check_eq((ots.player("p0")["meta"] as Dictionary).size(), 0, "Off the Street never carries Cannery upgrades")
	check_near(ots.max_hp(ots.player("p0")) + 12.0, fc.max_hp(fc.player("p0")), 0.01, "Squat Rack x3 = +12 HP only in Fight Camp")
	check_eq(int(fc.player("p0")["scrip"]), 100, "Sponsorship adds 40 starting Scrip in Fight Camp")
	check_eq(int(ots.player("p0")["scrip"]), 60, "and nothing in Off the Street")
	var b_ots := BuildApplier.compose(cat(), ots.state, ots.player("p0"))
	var b_fc := BuildApplier.compose(cat(), fc.state, fc.player("p0"))
	check_near(float(b_ots["mods"].get("damage", 1.0)), 1.0, 0.0001, "no meta damage in Off the Street")
	check_near(float(b_fc["mods"].get("damage", 1.0)), 1.04, 0.0001, "Heavy Bag x2 = +4% damage in Fight Camp")
	# a plain versus fighter (no campaign build) is untouched: the profile's camp data is never read
	var c := Content.creature("dev_biped")
	check(c != null, "dev creature")


func test_replay_reproduces_the_run() -> void:
	var ctrl := new_run({"seed": 2468})
	play_synthetic(ctrl)
	var replayed := RunController.replay(cat(), ctrl.state["start_cfg"], (ctrl.state["log"] as Array).slice(1))
	var a: Dictionary = ctrl.state.duplicate(true)
	var b: Dictionary = replayed.state.duplicate(true)
	for st in [a, b]:
		st.erase("elapsed")
		st["result"].erase("elapsed")
	check_eq(Saves.checksum(b), Saves.checksum(a), "seed + decision log rebuild the identical run")


func test_difficulty_and_dose_modifiers() -> void:
	var base := RunRules.compute(cat(), {"difficulty": "amateur", "dose": 0})
	var hard := RunRules.compute(cat(), {"difficulty": "title_shot", "dose": 10})
	check_near(float(base["enemy_hp_mult"]), 1.0, 0.0001, "Amateur enemy HP")
	check_near(float(hard["enemy_hp_mult"]), 1.4 * 1.15, 0.0001, "Title Shot x Dose 2 enemy HP")
	check_near(float(hard["enemy_damage_mult"]), 1.5 * 1.15, 0.0001, "Title Shot x Dose 4 enemy damage")
	check_near(float(hard["scrip_mult"]), 1.3 * 0.8, 0.0001, "Dose 1 Thin Wallet")
	check_eq(str(hard["bot_tier"]), "hall_of_famer", "Dose 10 bots")
	check_near(float(hard["boss_phase2_at"]), 0.65, 0.0001, "Dose 8 No Mercy")
	check_near(float(hard["shop_price_mult"]), 1.3, 0.0001, "Dose 9 prices")
	check_near(float(hard["rest_heal_mult"]), 0.5, 0.0001, "Dose 10 rest heal")
	var spar := RunRules.compute(cat(), {"difficulty": "sparring", "dose": 0})
	check_eq(str(spar["bot_tier"]), "punching_bag", "Sparring bots")
	var ctrl := new_run({"seed": 3, "dose": 3})
	var ctrl0 := new_run({"seed": 3, "dose": 0})
	check_near(ctrl.max_hp(ctrl.player("p0")), ctrl0.max_hp(ctrl0.player("p0")) * 0.9, 0.01, "Dose 3 Cut Weight: max HP -10%")


func test_coop_scaling_plan() -> void:
	var cfg := run_cfg("f_stoke", {"seed": 11})
	cfg["players"].append({"id": "p1", "name": "Two", "profile_id": "t2", "fighter": "f_dozer"})
	cfg["players"].append({"id": "p2", "name": "Three", "profile_id": "t3", "fighter": "f_gusto"})
	var ctrl := RunController.start_run(cat(), cfg)
	var solo := new_run({"seed": 11})
	var plan3 := EncounterBuilder.plan(cat(), ctrl.state, "enc_a1_dock_rats", {"node_id": "x"})
	var plan1 := EncounterBuilder.plan(cat(), solo.state, "enc_a1_dock_rats", {"node_id": "x"})
	check_eq((plan1["enemies"] as Array).size(), 4, "solo: 4 Scraplings")
	check_eq((plan3["enemies"] as Array).size(), 8, "3 players: count x2")
	check_near(float(plan3["enemies"][0]["hp_mult"]), 1.7, 0.001, "3 players: enemy HP x(1 + 0.35 x 2)")
	var boss3 := EncounterBuilder.plan(cat(), ctrl.state, "boss_a1", {"node_id": "x"})
	check_near(float(boss3["enemies"][0]["hp_mult"]), 2.2, 0.001, "3 players: boss HP x(1 + 0.6 x 2)")
	var single := EncounterBuilder.plan(cat(), ctrl.state, "enc_a1_wet_floor", {"node_id": "x"})
	var fighters := 0
	for e in single["enemies"]:
		if e["kind"] == "fighter":
			fighters += 1
	check_eq(fighters, 2, "single-fighter templates add a second fighter at 3+ players")
