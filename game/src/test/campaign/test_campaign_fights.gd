extends CampaignTestCase
## CNT-08 / CMP-05 / COOP-04: campaign encounters become real MatchSim fights (bots on both
## sides, accelerated): special rules, waves, tag bouts, bosses with two phases and Dazed,
## downed/revive. Outcomes are asserted structurally (fights end, rules fire), not exactly.

const SPEED := 16.0


## A run whose player is a strong test build (custom run) so fights resolve quickly.
func strong_run(extra := {}, fighter := "f_stoke") -> RunController:
	var cfg := run_cfg(fighter, {"seed": 4321, "difficulty": "sparring", "custom": true, "custom_reasons": ["test build"]})
	for k in extra:
		cfg[k] = extra[k]
	var ctrl := RunController.start_run(cat(), cfg)
	for p in ctrl.players():
		(p["run_effects"] as Array).append({"source": "test", "apply": {
			"mods": [{"key": "damage", "mul": 4.0}, {"key": "max_health_add", "add": 300}],
			"patches": [{"op": "mul", "path": "moves.*.poise", "value": 3.0}]}})
		p["hp"] = ctrl.max_hp(p)
	return ctrl


func fight_plan(ctrl: RunController, encounter: String) -> Dictionary:
	ctrl.state["phase"] = "fight"
	ctrl.state["position"] = "test"
	ctrl.state["node"] = {"id": "test", "type": "fight", "pending": {"p0": []}, "fights": 0,
		"fight": {"encounter": encounter, "tier": "normal", "plan": EncounterBuilder.plan(cat(), ctrl.state, encounter, {"node_id": "test"})}}
	return ctrl.current_plan()


func run_fight(ctrl: RunController, encounter: String, tier := "headliner", max_s := 300.0) -> Dictionary:
	fight_plan(ctrl, encounter)
	var built := ctrl.match_config({"bot_tier_players": tier, "player_kinds": {"p0": "bot"}})
	check((built["errors"] as PackedStringArray).is_empty(), "%s builds: %s" % [encounter, "; ".join(built["errors"])])
	SimSpeed.set_scale(SPEED)
	var res: Dictionary = await HeadlessFightRunner.run(self, built["config"], max_s)
	return res


func test_plain_fight_runs_and_reports() -> void:
	var ctrl := strong_run()
	var res: Dictionary = await run_fight(ctrl, "enc_a1_open_tryout")
	var camp: Dictionary = res.get("campaign", {})
	check(not camp.is_empty(), "result has a campaign section")
	check(camp.has("won"), "outcome decided")
	check(bool(camp.get("won", false)), "the strong test build wins an Act 1 tryout")
	check(camp["players"].has("p0"), "per-player report")
	check(float(camp["players"]["p0"]["hp"]) > 0.0, "the winner keeps HP")
	check_eq(int(camp["enemies_total"]), 1, "one enemy")


func test_waves_and_timer_fight() -> void:
	var ctrl := strong_run()
	var plan := fight_plan(ctrl, "enc_a1_timed_scrap")
	check_eq((plan["enemies"] as Array).size(), 6, "6 Scraplings")
	var waves := {}
	for e in plan["enemies"]:
		waves[int(e["wave"])] = true
	check_eq(waves.size(), 2, "split into 2 waves")
	check_near(float(plan["rules"]["round_time"]), 60.0, 0.01, "timed sudden death 60 s")
	var res: Dictionary = await run_fight(ctrl, "enc_a1_timed_scrap")
	var camp: Dictionary = res.get("campaign", {})
	check_eq(int(camp.get("enemies_total", 0)), 6, "all wave enemies reported")
	check(bool(camp.get("won", false)) or bool(camp.get("sudden_death", false)), "wave fight resolves (won or reached sudden death)")


func test_tag_bout_swaps_and_regenerates() -> void:
	var ctrl := strong_run({}, "f_gusto")
	var plan := fight_plan(ctrl, "enc_a1_tag_tryout")
	var built := ctrl.match_config({"bot_tier_players": "headliner", "player_kinds": {"p0": "bot"}})
	var sv := fresh_world()
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	sim.setup(built["config"])
	var mode: CampaignMatchMode = sim.mode
	var parked := 0
	for f in sim.fighters:
		if mode.is_parked(f):
			parked += 1
	check_eq(parked, 1, "one enemy waits on the bench")
	SimSpeed.set_scale(SPEED)
	var saw_tag := false
	var dt := SimSpeed.step_dt()
	var cursor := 0
	while not sim.is_finished and sim.time < 240.0:
		sim.step(dt)
		await get_tree().physics_frame
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			if str(ev["type"]) == "tag":
				saw_tag = true
	check(sim.is_finished, "tag bout finishes")
	check(saw_tag, "the enemy tag team swapped (low HP or KO)")
	check(plan["rule_tags"].size() > 0, "rule tags shown for the tag bout")


func test_boss_fight_two_phases_and_daze() -> void:
	var ctrl := strong_run()
	fight_plan(ctrl, "boss_a1")
	var built := ctrl.match_config({"bot_tier_players": "headliner", "player_kinds": {"p0": "bot"}})
	check((built["errors"] as PackedStringArray).is_empty(), "boss builds")
	var sv := fresh_world()
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	sim.setup(built["config"])
	check(sim.mode is BossMode, "boss fights use BossMode")
	var bm: BossMode = sim.mode
	check(bm.boss != null, "boss found")
	check(bool(bm.boss.flags.get("boss_ungrabbable", false)), "bosses start ungrabbable")
	SimSpeed.set_scale(SPEED)
	var dt := SimSpeed.step_dt()
	var cursor := 0
	var events := {}
	var telegraph_ok := true
	while not sim.is_finished and sim.time < 400.0:
		sim.step(dt)
		await get_tree().physics_frame
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			var t := str(ev["type"])
			events[t] = int(events.get(t, 0)) + 1
			if t == "boss_telegraph" and float(ev.get("time", 0.0)) < 0.5:
				telegraph_ok = false
			if t == "boss_dazed":
				check(not bool(bm.boss.flags.get("boss_ungrabbable", true)), "a Dazed boss can be grabbed")
	check(sim.is_finished, "boss fight finishes")
	check(int(events.get("boss_telegraph", 0)) > 0, "boss used telegraphed special attacks")
	check(telegraph_ok, "every telegraph >= 0.5 s")
	check_eq(int(events.get("boss_phase", 0)), 1, "exactly one phase transition")
	check_eq(bm.phase_no, 2, "phase 2 reached")
	check(int(events.get("boss_dazed", 0)) > 0, "poise break dazed the boss")
	var camp: Dictionary = sim.result.get("campaign", {})
	check_eq(int(camp.get("boss", {}).get("phase", 0)), 2, "result reports the phase")


func test_boss_cannot_skip_phase_two() -> void:
	var ctrl := strong_run()
	fight_plan(ctrl, "boss_a1")
	var built := ctrl.match_config({"player_kinds": {"p0": "bot"}})
	var sv := fresh_world()
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	sim.setup(built["config"])
	var bm: BossMode = sim.mode
	bm.phase = MatchMode.Phase.FIGHT
	bm.on_depleted(bm.boss, sim.fighters[0], {})
	check(not bm.boss.is_out(), "a depleted phase-1 boss is held at the threshold")
	check_eq(bm.phase_no, 2, "and moves to phase 2")
	check(bm.intercept_knockdown(bm.boss, "move", sim.fighters[0]), "bosses never take ordinary knockdowns")


func test_rematch_elite_is_phase_one_only() -> void:
	var ctrl := strong_run()
	var plan := fight_plan(ctrl, "elite_a3_bilge_rematch")
	var boss_e := {}
	for e in plan["enemies"]:
		if e["kind"] == "boss":
			boss_e = e
	check_near(float(boss_e.get("start_hp_frac", 0.0)), 0.6, 0.001, "Bilge Rematch starts at 60% HP")
	var built := ctrl.match_config({"player_kinds": {"p0": "bot"}})
	var sv := fresh_world()
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	sim.setup(built["config"])
	var bm: BossMode = sim.mode
	check_near(bm.boss.health / bm.boss.max_health, 0.6, 0.01, "HP set")
	bm.phase = MatchMode.Phase.FIGHT
	bm.boss.health = 1.0
	bm.on_depleted(bm.boss, sim.fighters[0], {})
	check(bm.boss.is_out(), "phase-1-only bosses can be KO'd")


func test_downed_and_revive_in_coop() -> void:
	var cfg := run_cfg("f_stoke", {"seed": 99})
	cfg["players"].append({"id": "p1", "name": "Two", "profile_id": "t2", "fighter": "f_dozer"})
	var ctrl := RunController.start_run(cat(), cfg)
	fight_plan(ctrl, "enc_a1_open_tryout")
	var built := ctrl.match_config({"player_kinds": {"p0": "bot", "p1": "bot"}})
	var sv := fresh_world()
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	sim.setup(built["config"])
	var mode: CampaignMatchMode = sim.mode
	mode.phase = MatchMode.Phase.FIGHT
	var a: Fighter = sim.fighters[0]
	var b: Fighter = sim.fighters[1]
	a.health = 0.0
	mode.on_depleted(a, null, {})
	check_eq(a.state, Fighter.State.DOWNED, "a co-op player at 0 HP is Downed, not out")
	check_eq(mode.outcome, "", "the fight goes on while an ally stands")
	# the bot ally walks over and revives (hold Grab within 1.5 m for 2 s)
	b.rig.place(a.pos() + Vector3(0.8, 0, 0), 0.0)
	SimSpeed.set_scale(SPEED)
	var dt := SimSpeed.step_dt()
	var revived := false
	for i in 120 * 4:
		mode._tick_downed(dt)
		if a.state != Fighter.State.DOWNED:
			revived = true
			break
	check(revived, "the ally revived the downed player")
	check_near(a.health / a.max_health, 0.3, 0.01, "revived at 30% HP")
	# all down = defeat
	a.health = 0.0
	mode.on_depleted(a, null, {})
	b.health = 0.0
	mode.on_depleted(b, null, {})
	check_eq(mode.outcome, "loss", "everyone down ends the fight")
