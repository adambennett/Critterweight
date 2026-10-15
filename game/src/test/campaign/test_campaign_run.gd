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


# --- review regressions ----------------------------------------------------------------------------

## Turns the first reachable node into `t` (rest / event ...) so a test can enter it directly.
func _force_node(ctrl: RunController, t: String, event_id := "") -> String:
	var nid := str(ctrl.available_nodes()[0])
	var n := RunState.node(ctrl.state, nid)
	n["type"] = t
	n["encounter"] = ""
	n["event"] = event_id
	n.erase("hidden")
	return nid


func _two_player_run(seed_value: int) -> RunController:
	var cfg := run_cfg("f_stoke", {"seed": seed_value})
	cfg["players"].append({"id": "p1", "name": "Two", "profile_id": "t2", "fighter": "f_dozer"})
	return RunController.start_run(cat(), cfg)


## Review #1 (rules side): Train at a rest adds a technique pick while the phase stays "rest";
## the node completes only once the pick is claimed. advance_if_done() is a harmless no-op then.
func test_rest_train_pick_completes_the_node() -> void:
	var ctrl := new_run({"seed": 4242})
	var nid := _force_node(ctrl, "rest")
	check(ctrl.choose_node(nid, "p0"), "entered the rest stop")
	check(ctrl.rest_choose("p0", "train"), "train: %s" % ctrl.last_error)
	check_eq(ctrl.phase(), "rest", "the node waits for the pick")
	var pend := ctrl.pending_for("p0")
	check_eq(pend.size(), 1, "Train adds one pick")
	check_eq(str(pend[0]["kind"]) if not pend.is_empty() else "", "technique", "a technique pick")
	check(not ctrl.advance_if_done(), "nothing to complete while the pick is pending")
	if pend.is_empty():
		return
	check(ctrl.claim("p0", str(pend[0]["rid"]), str(pend[0]["options"][0])), "claim the technique")
	check_eq(ctrl.phase(), "map", "claiming the pick completes the rest stop")
	check_eq((ctrl.player("p0")["techniques"] as Array).size(), 1, "the technique was learned")


## Review #4: Dose credit follows the profile's OWN ladder and the difficulty rules.
func test_dose_credit_needs_the_profiles_own_ladder() -> void:
	# a co-op guest on someone else's Dose 10 card, whose Dosage was never opened
	var guest := Profiles.default_profile("guest", "Guest")
	var ctrl := new_run({"seed": 103, "dose": 10})
	play_synthetic(ctrl)
	check_eq(ctrl.phase(), "victory", "precondition: the Dose 10 card was cleared")
	var rep := CampaignProgression.finish_run(cat(), ctrl.state, "p0", guest)
	check(bool(rep["dose_ineligible"]), "the report says Dose 10 is not on this ladder")
	var lg: Dictionary = guest["ladder"]["off_the_street"]
	check_eq(int(lg["unlocked"]), 1, "no Dose unlocked from someone else's card")
	check_eq(int(lg["cleared"]), 0, "nothing cleared on this ladder")
	check(bool(rep["ladder_open"]) and bool(lg["open"]), "a clear on Amateur still opens The Dosage (at Dose 1)")
	check_eq(CampaignProgression.max_selectable_dose(guest, "off_the_street"), 1, "...so only Dose 1 is selectable")
	var cos: Array = guest["unlocks"]["cosmetics"]
	for c in ["badge_dose_10", "jacket_announcer_alt", "badge_lethal_dose", "chant_lethal_dose"]:
		check(not cos.has(c), "no %s from an ineligible Dose" % c)
	check(cos.has("title_f_stoke"), "the clear itself still earns the fighter title")
	check(not (rep["achievements"] as Array).has("ach_fully_dosed"), "no Fully Dosed for an ineligible Dose 10")
	check((rep["records"] as Array).is_empty(), "no Dose 10 records on this profile")
	check((guest["campaign"]["boards"] as Dictionary).is_empty(), "no Dose 10 record board created")
	check_eq(int(guest["records"]["runs"]["off_the_street"]["best_dose"]), 0, "best Dose unchanged")
	# the same card on a profile that reached Dose 10 counts in full
	var vet := Profiles.default_profile("vet", "Vet")
	CampaignProgression.ensure_fields(vet)
	vet["ladder"]["off_the_street"] = {"unlocked": 10, "cleared": 9, "open": true}
	var rep2 := CampaignProgression.finish_run(cat(), ctrl.state, "p0", vet)
	check(not bool(rep2["dose_ineligible"]), "eligible on its own ladder")
	check((vet["unlocks"]["cosmetics"] as Array).has("badge_lethal_dose"), "Lethal Dose badge")
	check((rep2["achievements"] as Array).has("ach_fully_dosed"), "Fully Dosed")
	check(not (rep2["records"] as Array).is_empty(), "Dose 10 records")
	check_eq(int(vet["ladder"]["off_the_street"]["cleared"]), 10, "Dose 10 cleared")
	# a Dose above the highest unlocked one never unlocks anything
	var mid := Profiles.default_profile("mid", "Mid")
	CampaignProgression.ensure_fields(mid)
	mid["ladder"]["off_the_street"] = {"unlocked": 2, "cleared": 1, "open": true}
	check_eq(CampaignProgression.apply_ladder_clear(mid, "off_the_street", 6, true), 0, "Dose 6 on a Dose-2 ladder unlocks nothing")
	check_eq(int(mid["ladder"]["off_the_street"]["unlocked"]), 2, "still Dose 2")
	check_eq(CampaignProgression.apply_ladder_clear(mid, "off_the_street", 1, true), 0, "a lower Dose unlocks nothing")
	check_eq(CampaignProgression.apply_ladder_clear(mid, "off_the_street", 2, true), 3, "the highest unlocked Dose unlocks the next")
	# Sparring takes no Doses: nothing Dose-related is credited, whatever the ladder
	var spar := new_run({"seed": 104, "dose": 3, "difficulty": "sparring"})
	play_synthetic(spar)
	var sp := Profiles.default_profile("sp", "Sp")
	CampaignProgression.ensure_fields(sp)
	sp["ladder"]["off_the_street"] = {"unlocked": 5, "cleared": 4, "open": true}
	var rep3 := CampaignProgression.finish_run(cat(), spar.state, "p0", sp)
	check(bool(rep3["dose_ineligible"]), "a Dose on Sparring is never eligible")
	check(not (sp["unlocks"]["cosmetics"] as Array).has("badge_dose_3"), "no Dose badge from Sparring")
	check_eq(int(sp["ladder"]["off_the_street"]["unlocked"]), 5, "ladder untouched")
	# run creation clamps the Dose to what the profile may play
	var fresh := Profiles.default_profile("fresh", "Fresh")
	check_eq(CampaignProgression.clamp_dose(cat(), fresh, "off_the_street", "amateur", 7), 0, "closed Dosage: base card")
	check_eq(CampaignProgression.clamp_dose(cat(), mid, "off_the_street", "pro", 7), 3, "clamped to the highest unlocked Dose")
	check_eq(CampaignProgression.clamp_dose(cat(), mid, "off_the_street", "sparring", 2), 0, "Sparring: no Dose")


## Review #12: Kid Lamprey's spar is a copy of you at 60% HP — no difficulty, Dose or party scaling.
func test_spar_copy_is_sixty_percent_and_unscaled() -> void:
	var ctrl := new_run({"seed": 106, "difficulty": "title_shot", "dose": 10})
	var plan := EncounterBuilder.plan(cat(), ctrl.state, "evt_fight_spar", {"node_id": "x_evt", "kind": "event", "mini": true, "spar": true, "player": "p0"})
	check_eq((plan["enemies"] as Array).size(), 1, "one sparring partner")
	var e: Dictionary = plan["enemies"][0]
	check_near(float(e["hp_mult"]), 0.6, 0.0001, "the template's 60% HP (not x Title Shot x Dose 2)")
	check_near(float(e["dmg_mult"]), 1.0, 0.0001, "no difficulty/Dose damage scaling")
	check((e["techniques"] as Array).is_empty(), "no Dose 6 extra technique for the copy")
	check_near(float(e["start_hype"]), 0.0, 0.0001, "no Dose 6 starting Hype")
	var built := EncounterBuilder.build_match(cat(), ctrl.state, plan, {"player_kinds": {"p0": "bot"}, "spar_player": "p0"})
	check((built["errors"] as PackedStringArray).is_empty(), "the spar builds: %s" % str(built["errors"]))
	var fighters: Array = built["config"].get("fighters", [])
	check_eq(fighters.size(), 2, "you and your copy")
	if fighters.size() == 2:
		var mods: Dictionary = fighters[1]["mods"]
		check_near(float(mods.get("max_health", 1.0)), 0.6, 0.0001, "the copy fights at 60% HP")
		check_near(float(mods.get("damage", 1.0)), 1.0, 0.0001, "and hits like you")
	# a normal fight on the same card IS scaled (the rule is specific to spars)
	var normal := EncounterBuilder.plan(cat(), ctrl.state, "enc_a1_dock_rats", {"node_id": "x"})
	check(float(normal["enemies"][0]["hp_mult"]) > 1.5, "normal fights keep difficulty/Dose scaling")


## Review #13: a custom run proves nothing — it never sets Fight Camp milestone flags.
func test_custom_fight_camp_runs_set_no_camp_milestones() -> void:
	var prof := Profiles.default_profile("t", "T")
	var ctrl := new_run({"seed": 105, "variant": "fight_camp", "custom": true, "custom_reasons": ["test build"]})
	play_synthetic(ctrl)
	check_eq(ctrl.phase(), "victory", "precondition: cleared")
	CampaignProgression.finish_run(cat(), ctrl.state, "p0", prof)
	var flags: Dictionary = prof["camp"]["flags"]
	for f in ["beat_act1", "beat_act2", "beat_run"]:
		check(not bool(flags.get(f, false)), "custom run: no %s" % f)
	prof["camp"]["clout"] = 1000
	var locked := FightCamp.buy_upgrade(cat(), prof, "meta_walkout")
	check(not bool(locked["ok"]) and str(locked["error"]).contains("locked"), "Walkout Music stays locked after a custom clear")
	var normal := new_run({"seed": 115, "variant": "fight_camp"})   # another run id (credit is per run)
	play_synthetic(normal)
	check_eq(normal.phase(), "victory", "precondition: cleared")
	CampaignProgression.finish_run(cat(), normal.state, "p0", prof)
	for f2 in ["beat_act1", "beat_act2", "beat_run"]:
		check(bool(flags.get(f2, false)), "standard run: %s" % f2)
	check(bool(FightCamp.buy_upgrade(cat(), prof, "meta_walkout")["ok"]), "a standard clear opens Walkout Music")


## Review #14: a boss's own phase-2 threshold from content is used; Dose 8 only brings it sooner.
func test_boss_own_phase_two_threshold_is_used() -> void:
	var c := cat()
	c.boss_fights["fight_bilge"] = (c.boss_fights["fight_bilge"] as Dictionary).duplicate(true)   # this test's catalog only
	c.boss_fights["fight_bilge"]["phase2_at"] = 0.4
	var cases := [[0, 0.4, "the boss's own 40%"], [8, 0.65, "Dose 8 No Mercy: 65%"]]
	for cs in cases:
		var ctrl := new_run({"seed": 107, "dose": int(cs[0])})
		var plan := EncounterBuilder.plan(c, ctrl.state, "boss_a1", {"node_id": "x", "kind": "boss"})
		var built := EncounterBuilder.build_match(c, ctrl.state, plan, {"player_kinds": {"p0": "bot"}})
		var mode = built["config"].get("mode")
		check(mode is BossMode, "a boss fight")
		if mode is BossMode:
			check_near(float((mode as BossMode).cfg.get("phase2_at", -1.0)), float(cs[1]), 0.0001, str(cs[2]))
	c.boss_fights["fight_bilge"]["phase2_at"] = 0.7
	var d8 := new_run({"seed": 107, "dose": 8})
	check_near(EncounterBuilder.boss_phase2_at(c, d8.state, c.boss_fights["fight_bilge"]), 0.7, 0.0001, "Dose 8 never makes phase 2 come later")


## Review #5 (rules side): a group choice is only available while EVERY member can pay their
## share; the autopilot picks only those; an event where nothing can be taken resolves by PASS.
func test_group_event_choices_need_the_whole_party_to_pay() -> void:
	var ctrl := _two_player_run(2024)
	var nid := _force_node(ctrl, "event", "evt_the_belt")
	ctrl.player("p0")["scrip"] = 200
	ctrl.player("p1")["scrip"] = 20
	check(ctrl.choose_node(nid, "p0"), "entered the event")
	check_eq(ctrl.phase(), "event", "group event")
	var sess: Dictionary = ctrl.session().get("event", {})
	check_eq(EventRunner.available_choices(ctrl, sess, "p0"), ["window"], "Buy (50 Scrip each) is out: Two cannot pay their share")
	var buy := {}
	for ch in ctrl.event_view("p0").get("choices", []):
		if str(ch["id"]) == "buy":
			buy = ch
	check(not bool(buy.get("available", true)) and str(buy.get("reason", "")).contains("Two"), "the reason names who cannot pay (%s)" % str(buy.get("reason", "")))
	check(not ctrl.choose_event("p0", "buy"), "buying is refused")
	check(ctrl.last_error.contains("Two"), "and the error says why (%s)" % ctrl.last_error)
	check(not ctrl.choose_event("p0", EventRunner.PASS), "no passing while a choice is open")
	check_eq(CampaignAutoPilot.choose_event(ctrl, "p0"), "window", "unattended play picks what the party can pay")
	check(CampaignAutoPilot.settle(ctrl, ["p0", "p1"]), "the autopilot settles the group event")
	check(ctrl.phase() != "event", "resolved")
	# an event where nothing at all can be taken: PASS (no softlock), replayable
	var c := cat()
	c.events["evt_review_toll"] = {"id": "evt_review_toll", "type": "event", "title": "Toll", "text": "Pay up.", "group": true,
		"choices": [{"id": "pay", "label": "Pay", "cost": {"scrip": 900}, "outcomes": [{"effects": [{"op": "nothing"}]}]}]}
	var ctrl2 := _two_player_run(2025)
	var nid2 := _force_node(ctrl2, "event", "evt_review_toll")
	ctrl2.choose_node(nid2, "p0")
	check(EventRunner.available_choices(ctrl2, ctrl2.session().get("event", {}), "p0").is_empty(), "nothing affordable")
	check_eq(CampaignAutoPilot.choose_event(ctrl2, "p0"), EventRunner.PASS, "the autopilot passes")
	check(CampaignAutoPilot.settle(ctrl2, ["p0", "p1"]), "and the event resolves")
	check_eq(ctrl2.phase(), "map", "the party moved on")
	var last_event := {}
	for e in ctrl2.state["log"]:
		if str(e["k"]) == "event":
			last_event = e
	check_eq(str(last_event.get("d", {}).get("choice", "")), EventRunner.PASS, "the pass is logged like any choice (replays reproduce it)")


## Review #3/#6 (rules side): everything that changes the outcome is in the log, so a run
## rebuilt from its own start config + log verifies — and a tampered state does not.
func test_verify_rebuilds_runs_and_rejects_tampering() -> void:
	var ctrl := new_run({"seed": 2468})
	ctrl.choose_node(str(ctrl.available_nodes()[0]), "p0")
	settle_node(ctrl)
	check(ctrl.mark_custom([CampaignFlow.REASON_GAME_SPEED]), "the run becomes custom mid-way")
	check(not ctrl.mark_custom([CampaignFlow.REASON_GAME_SPEED]), "once per reason")
	play_synthetic(ctrl)
	var wire = JSON.parse_string(JSON.stringify(RunStore.json_stable(ctrl.state), "", false, true))
	var v := RunController.verify(cat(), wire)
	check(bool(v["ok"]), "an honest run verifies: %s" % v["error"])
	if v["ctrl"] != null:
		check(bool((v["ctrl"] as RunController).state["custom"]), "the custom mark is replayed")
	var tamper := {
		"a forged Dose": func(s: Dictionary) -> void: s["dose"] = 10,
		"forged Clout": func(s: Dictionary) -> void: s["players"][0]["clout"] = 50000,
		"a forged result": func(s: Dictionary) -> void: s["result"]["victory"] = not bool(s["result"]["victory"]),
		"a dropped decision": func(s: Dictionary) -> void: (s["log"] as Array).remove_at(3),
		"a forged un-custom": func(s: Dictionary) -> void: s["custom"] = false,
	}
	for what in tamper:
		var forged: Dictionary = (wire as Dictionary).duplicate(true)
		(tamper[what] as Callable).call(forged)
		check(not bool(RunController.verify(cat(), forged)["ok"]), "%s does not follow from the log" % what)
	# incremental (party tickets): a continuation is checked from the last verified checkpoint
	var run2 := new_run({"seed": 2470})
	for i in 3:
		run2.choose_node(str(run2.available_nodes()[0]), "p0")
		settle_node(run2)
	var first := RunController.verify(cat(), RunStore.json_stable(run2.state))
	check(bool(first["ok"]), "checkpoint 1 verifies: %s" % first["error"])
	for i2 in 2:
		run2.choose_node(str(run2.available_nodes()[0]), "p0")
		settle_node(run2)
	var next_st: Dictionary = RunStore.json_stable(run2.state)
	var inc := RunController.verify_from(cat(), first["ctrl"], next_st)
	check(bool(inc["ok"]), "the continuation verifies incrementally: %s" % inc["error"])
	var rewritten: Dictionary = next_st.duplicate(true)
	rewritten["players"][0]["scrip"] = 9999
	check(not bool(RunController.verify_from(cat(), first["ctrl"], rewritten)["ok"]), "a tampered continuation is rejected")
	var other := new_run({"seed": 2471})
	var o := RunController.verify_from(cat(), first["ctrl"], RunStore.json_stable(other.state))
	check(bool(o["ok"]) and str((o["ctrl"] as RunController).state["run_id"]) == str(other.state["run_id"]),
		"another run is never taken for a continuation: it is rebuilt on its own (full replay)")
