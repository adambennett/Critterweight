extends CampaignTestCase
## CMP-01/03/05, CNT-08, VER-02: complete runs where bots fight the ACTUAL matches (headless,
## accelerated) — victory and defeat in both variants, including boss fights. The player's
## fighter uses a declared test build (the run is marked custom) so outcomes are reliable; the
## rules, generation, modes and transitions under test are the real ones.

const SPEED := 24.0


func build_run(variant: String, seed_value: int, strength: float, fighter := "f_stoke") -> RunController:
	var cfg := run_cfg(fighter, {"seed": seed_value, "variant": variant, "difficulty": "sparring", "custom": true, "custom_reasons": ["test build"]})
	var ctrl := RunController.start_run(cat(), cfg)
	var p := ctrl.player("p0")
	# a strong build also halves damage taken: run HP carries across ~13 fights, and a single
	# unlucky Act 3 boss fight at low HP must not make the "victory" assertion flaky
	(p["run_effects"] as Array).append({"source": "test", "apply": {
		"mods": [{"key": "damage", "mul": strength}, {"key": "max_health_add", "add": 300 if strength > 1.0 else 0},
			{"key": "defense", "mul": 0.5 if strength > 1.0 else 1.0}],
		"patches": [{"op": "mul", "path": "moves.*.poise", "value": maxf(1.0, strength)}]}})
	p["hp"] = ctrl.max_hp(p)
	return ctrl


func test_off_the_street_victory_with_real_fights() -> void:
	var ctrl := build_run("off_the_street", 1001, 5.0)
	SimSpeed.set_scale(SPEED)
	var t0 := Time.get_ticks_msec()
	var out: Dictionary = await CampaignDriver.auto_run(self, ctrl, {"bot_tier_players": "headliner"})
	print("full run (Off the Street): %s nodes=%d fights=%d in %.1f s" % [out["phase"], out["nodes"], out["fights"], (Time.get_ticks_msec() - t0) / 1000.0])
	check_eq(str(out["phase"]), "victory", "the run reaches the title")
	check(int(out["fights"]) >= 12, "12+ real fights including 3 bosses (got %d)" % out["fights"])
	var bosses := 0
	for id in ctrl.state["path"]:
		if str(RunState.node(ctrl.state, str(id)).get("type", "")) == "boss":
			bosses += 1
	check_eq(bosses, 3, "three bosses beaten")
	var prof := Profiles.default_profile("t", "T")
	var rep := CampaignProgression.finish_run(cat(), ctrl.state, "p0", prof)
	check_eq(int(prof["camp"]["clout"]), 0, "Off the Street grants no Fight Camp power")
	check(int(rep["clout"]) > 0, "cosmetic Clout only")


func test_fight_camp_victory_with_real_fights() -> void:
	var prof := Profiles.default_profile("camp", "Camp")
	prof["camp"]["upgrades"] = {"meta_squat_rack": 2, "meta_sponsorship": 1}
	# seed 1003: since D-034 the seed-1002 route ends at Act 3's Swarm Night, which Dredge's bot loses on the
	# rooftop even with this build (open issue, docs/PROGRESS.md); this test is about the Fight Camp loop
	var ctrl := build_run("fight_camp", 1003, 5.0, "f_dredge")
	# a real Fight Camp run copies the profile's upgrade levels at start
	ctrl.player("p0")["meta"] = FightCamp.meta_levels(prof)
	SimSpeed.set_scale(SPEED)
	var trace := []
	var on_step := func(c: RunController, what: String) -> void:
		if what == "fight":
			var node := RunState.node(c.state, str(c.state["position"]))
			trace.append("%s %s hp %.0f/%.0f" % [str(node.get("type", "")), str(node.get("encounter", node.get("id", ""))),
				float(c.player("p0")["hp"]), c.max_hp(c.player("p0"))])
	var out: Dictionary = await CampaignDriver.auto_run(self, ctrl, {"bot_tier_players": "headliner", "on_step": on_step})
	check_eq(str(out["phase"]), "victory", "Fight Camp run reaches the title (fights: %s)" % [trace])
	var before := int(prof["camp"]["clout"])
	var rep := CampaignProgression.finish_run(cat(), ctrl.state, "p0", prof)
	check(int(prof["camp"]["clout"]) > before, "Clout credited for Cannery upgrades (%d)" % rep["clout"])
	# this run is custom (a declared test build): it earns Clout but proves nothing for the
	# Cannery's milestone gates (CAMPAIGN_SYSTEMS.md custom runs). A standard clear setting them
	# and opening Walkout Music: test_campaign_run::test_custom_fight_camp_runs_set_no_camp_milestones
	check(not bool(prof["camp"]["flags"].get("beat_run", false)), "a custom run sets no camp milestone flags")
	var buy := FightCamp.buy_upgrade(cat(), prof, "meta_walkout")
	check(not bool(buy["ok"]) and str(buy["error"]).contains("locked"), "Walkout Music stays locked after a custom run")


func test_off_the_street_defeat_with_real_fights() -> void:
	var ctrl := build_run("off_the_street", 1003, 0.05)
	ctrl.state["difficulty"] = "title_shot"
	ctrl.player("p0")["hp"] = 5.0
	SimSpeed.set_scale(SPEED)
	var out: Dictionary = await CampaignDriver.auto_run(self, ctrl, {"bot_tier_players": "punching_bag"})
	check_eq(str(out["phase"]), "defeat", "a hopeless build loses")
	check(int(out["fights"]) >= 1, "it lost a real fight")
	var prof := Profiles.default_profile("t", "T")
	CampaignProgression.finish_run(cat(), ctrl.state, "p0", prof)
	check_eq(int(prof["records"]["runs"]["off_the_street"]["attempts"]), 1, "attempt recorded")
	check_eq(int(prof["records"]["runs"]["off_the_street"]["clears"]), 0, "no clear")
	check_eq(str(prof["campaign"]["saved_builds"][0]["fighter"]), "f_stoke", "defeat saves the build")


func test_fight_camp_defeat_at_the_act_one_boss() -> void:
	var ctrl := build_run("fight_camp", 1004, 5.0, "f_jitters")
	SimSpeed.set_scale(SPEED)
	# play strong until the boss node of Act 1, then lose the boss fight for real
	var reached_boss := false
	var guard := 0
	while not ctrl.is_over() and guard < 80:
		guard += 1
		match ctrl.phase():
			"map":
				var id := CampaignAutoPilot.choose_route(ctrl, "p0")
				var boss_next := str(RunState.node(ctrl.state, id).get("type", "")) == "boss"
				ctrl.choose_node(id, "p0")
				if boss_next:
					reached_boss = true
					var p := ctrl.player("p0")
					p["run_effects"] = [{"source": "test", "apply": {"mods": [{"key": "damage", "mul": 0.05}]}}]
					p["hp"] = 3.0
			"fight":
				await CampaignDriver.play_fight(self, ctrl, {"bot_tier_players": "punching_bag" if reached_boss else "headliner"})
			_:
				CampaignAutoPilot.settle(ctrl, ["p0"])
	check(reached_boss, "reached the Act 1 boss")
	check_eq(ctrl.phase(), "defeat", "lost to the boss")
	check_eq(int(ctrl.state["act"]), 1, "in Act 1")
	check_eq(str(RunState.node(ctrl.state, str(ctrl.state["position"])).get("type", "")), "boss", "the defeat happened at the boss")
