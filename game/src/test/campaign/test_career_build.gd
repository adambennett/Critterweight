extends CareerTestCase
## CMP-08 / design contract D2: the fixed career stat -> fighter mapping, checked on real fighters
## in a MatchSim (make_sim): each stat moves the intended Fighter quantities in the intended
## direction, never the "defense" or "poise" multipliers; carried injuries handicap the right
## systems; career builds never leak into plain creatures, Fight Camp builds or other runs.

const LOW := 0.2
const HIGH := 0.9


func _stats(stat: String, v: float) -> Dictionary:
	var s := {}
	for k in CareerDefaults.STATS:
		s[k] = 0.5
	s[stat] = v
	return s


## A sim with the career-built f_stoke as fighter 0 and a plain f_stoke as fighter 1.
func _sim(stats: Dictionary, injury := {}) -> MatchSim:
	var rules := CareerDefaults.for_catalog(cat())
	var b := CareerBuild.compose(cat(), rules, "f_stoke", stats, injury)
	check(b["creature"] != null, "career build composes: %s" % [b["errors"]])
	return make_sim("the_gullet", {"rounds": 1, "round_time": 0}, [
		{"creature": b["creature"], "team": 0, "mods": b["mods"]},
		{"creature": "f_stoke", "team": 1}], 7)


func _pair(stat: String) -> Array:
	return [_sim(_stats(stat, LOW)), _sim(_stats(stat, HIGH))]


func _forbidden_untouched(f: Fighter, what: String) -> void:
	check_near(float(f.mods["defense"]), 1.0, 0.000001, "%s: the 'defense' multiplier is never touched" % what)
	check_near(float(f.mods["poise"]), 1.0, 0.000001, "%s: the 'poise' multiplier is never touched" % what)


## HP lost by `victim` to a fixed 10-damage hit from `source` (null = environment).
func _hit(sim: MatchSim, source: Fighter, victim: Fighter) -> float:
	var hp := victim.health
	sim.combat.apply_simple_damage(source, victim, 10.0, "test")
	return hp - victim.health


func test_mid_stats_are_the_base_kit() -> void:
	var rules := CareerDefaults.for_catalog(cat())
	var b := CareerBuild.compose(cat(), rules, "f_stoke", _stats("power", 0.5))
	for k in b["mods"]:
		var ident := float(CampaignCatalog.MOD_DEFAULTS.get(k, 0.0))
		check_near(float(b["mods"][k]), ident, 0.000001, "0.5 in every stat leaves %s at its identity" % k)
	var base := Content.creature("f_stoke")
	var c: CreatureDef = b["creature"]
	for slot in base.moves:
		check_near(c.moves[slot].poise, base.moves[slot].poise, 0.0001, "0.5 power keeps %s poise" % slot)
	var block := CareerBuild.apply_block(rules, _stats("power", 0.7))
	for m in block["mods"]:
		check(CampaignCatalog.MOD_DEFAULTS.has(str(m["key"])), "%s is a known build modifier" % m["key"])
		check(not CareerBuild.FORBIDDEN.has(str(m["key"])), "never %s" % m["key"])


func test_stamina_raises_tank_and_regen() -> void:
	var p := _pair("stamina")
	await wait_physics(1)
	var lo: Fighter = (p[0] as MatchSim).fighters[0]
	var hi: Fighter = (p[1] as MatchSim).fighters[0]
	check(hi.max_stamina > lo.max_stamina, "max stamina %.1f > %.1f" % [hi.max_stamina, lo.max_stamina])
	check(float(hi.mods["stamina_regen"]) > float(lo.mods["stamina_regen"]), "stamina regen")
	_forbidden_untouched(hi, "stamina")


func test_chin_raises_poise_and_getup_never_the_poise_multiplier() -> void:
	var p := _pair("chin")
	await wait_physics(1)
	var lo: Fighter = (p[0] as MatchSim).fighters[0]
	var hi: Fighter = (p[1] as MatchSim).fighters[0]
	check(hi.effective_max_poise() > lo.effective_max_poise(), "max poise %.1f > %.1f" % [hi.effective_max_poise(), lo.effective_max_poise()])
	check(hi.getup_speed_mult() > lo.getup_speed_mult(), "quicker get-up")
	_forbidden_untouched(hi, "chin")
	_forbidden_untouched(lo, "chin")
	# incoming poise damage is NOT divided by chin (that would square the effect)
	var sim_lo: MatchSim = p[0]
	var sim_hi: MatchSim = p[1]
	var pl := lo.poise
	sim_lo.combat.apply_simple_damage(null, lo, 1.0, "test", {"poise": 10.0})
	var ph := hi.poise
	sim_hi.combat.apply_simple_damage(null, hi, 1.0, "test", {"poise": 10.0})
	check_near(pl - lo.poise, ph - hi.poise, 0.0001, "the same blow takes the same poise")


func test_speed_raises_footwork_and_tempo() -> void:
	var p := _pair("speed")
	await wait_physics(1)
	var lo: Fighter = (p[0] as MatchSim).fighters[0]
	var hi: Fighter = (p[1] as MatchSim).fighters[0]
	check(hi.speed_mult() > lo.speed_mult(), "locomotion %.3f > %.3f" % [hi.speed_mult(), lo.speed_mult()])
	check(float(hi.mods["move_speed"]) > float(lo.mods["move_speed"]), "strike tempo")
	_forbidden_untouched(hi, "speed")


func test_power_raises_damage_and_knockdown_force() -> void:
	var p := _pair("power")
	await wait_physics(1)
	var sim_lo: MatchSim = p[0]
	var sim_hi: MatchSim = p[1]
	var lo: Fighter = sim_lo.fighters[0]
	var hi: Fighter = sim_hi.fighters[0]
	check(_hit(sim_hi, hi, sim_hi.fighters[1]) > _hit(sim_lo, lo, sim_lo.fighters[1]), "a powerful fighter's blow does more damage")
	for slot in ["l1", "heavy", "heavy_charged"]:
		check(hi.creature.moves[slot].poise > lo.creature.moves[slot].poise, "%s knocks harder (poise %.1f > %.1f)" % [slot, hi.creature.moves[slot].poise, lo.creature.moves[slot].poise])
	check(_hit(sim_hi, null, hi) == _hit(sim_lo, null, lo), "power changes nothing about damage TAKEN")
	_forbidden_untouched(hi, "power")


func test_clinch_improves_the_grab_game() -> void:
	var p := _pair("clinch")
	await wait_physics(1)
	var lo: Fighter = (p[0] as MatchSim).fighters[0]
	var hi: Fighter = (p[1] as MatchSim).fighters[0]
	check(float(hi.mods["grab_hold_add"]) > float(lo.mods["grab_hold_add"]), "holds last longer")
	check(int(hi.mods["grab_escape_add"]) > int(lo.mods["grab_escape_add"]), "your holds take more presses to escape (whole presses)")
	check(is_equal_approx(float(hi.mods["grab_escape_add"]), roundf(float(hi.mods["grab_escape_add"]))), "whole presses only")
	check(float(hi.mods["throw_distance"]) > float(lo.mods["throw_distance"]), "bigger throws")
	check(float(hi.mods["splat_damage_add"]) > float(lo.mods["splat_damage_add"]), "harder wall splats")
	check(hi.held_time_mult() < lo.held_time_mult(), "held for less time when grabbed (victim side)")
	_forbidden_untouched(hi, "clinch")


func test_defence_improves_guard_parry_dodge_never_damage_taken() -> void:
	var p := _pair("defence")
	await wait_physics(1)
	var sim_lo: MatchSim = p[0]
	var sim_hi: MatchSim = p[1]
	var lo: Fighter = sim_lo.fighters[0]
	var hi: Fighter = sim_hi.fighters[0]
	var chip_lo := Tuning.v("guard_damage_mult") * float(lo.mods["guard_absorb_mult"])
	var chip_hi := Tuning.v("guard_damage_mult") * float(hi.mods["guard_absorb_mult"])
	check(chip_hi < chip_lo, "less chip through the guard (%.3f < %.3f)" % [chip_hi, chip_lo])
	check(float(hi.mods["parry_window_add"]) > float(lo.mods["parry_window_add"]), "wider parry window")
	check(float(hi.mods["dodge_iframes_add"]) > float(lo.mods["dodge_iframes_add"]), "safer dodges")
	check(float(hi.mods["dodge_cost"]) < float(lo.mods["dodge_cost"]), "cheaper dodges")
	# defence never multiplies damage taken (the 'defense' mod would INCREASE it)
	check_near(_hit(sim_hi, sim_hi.fighters[1], hi), _hit(sim_lo, sim_lo.fighters[1], lo), 0.0001, "an unguarded fixed hit does the same")
	_forbidden_untouched(hi, "defence")
	_forbidden_untouched(lo, "defence")


func test_injuries_handicap_poise_stamina_and_footwork() -> void:
	var mid := _stats("power", 0.5)
	var healthy := _sim(mid)
	var hurt := _sim(mid, {"head": 60.0, "body": 60.0, "legs": 60.0})
	await wait_physics(1)
	var h: Fighter = healthy.fighters[0]
	var x: Fighter = hurt.fighters[0]
	check(x.effective_max_poise() < h.effective_max_poise(), "head injury: less poise")
	check(float(x.mods["stamina_regen"]) < float(h.mods["stamina_regen"]), "body injury: slower stamina regen")
	check(x.speed_mult() < h.speed_mult(), "leg injury: slower footwork")
	check_near(float(x.mods["move_speed"]), float(h.mods["move_speed"]), 0.000001, "legs never slow the strikes")
	check_near(x.max_health, h.max_health, 0.0001, "HP untouched (unlimited under 10-point anyway)")
	_forbidden_untouched(x, "injured")
	var rules := CareerDefaults.for_catalog(cat())
	check(CareerBuild.injury_mods(rules, {}).is_empty(), "no handicap when healthy")
	var worst := CareerBuild.injury_mods(rules, {"head": 100.0, "body": 100.0, "legs": 100.0})
	for m in worst:
		if m.has("mul"):
			check(float(m["mul"]) >= 0.7 - 0.0001, "handicaps are bounded (%s)" % m["key"])
		else:
			check(float(m["add"]) >= -15.0 - 0.0001, "poise penalty bounded")


## Career power stays inside career fights: plain creatures, Fight Camp builds and runs are
## unchanged before and after any number of career builds.
func test_career_builds_never_leak() -> void:
	var rules := CareerDefaults.for_catalog(cat())
	var base := Content.creature("f_stoke")
	var heavy_before: float = base.moves["heavy"].poise
	var raw_before := sig(cat().resolver.creature_dict("f_stoke"))
	var run := new_run({"seed": 88})
	var run_p: Dictionary = run.state["players"][0]
	var run_before := BuildApplier.compose(cat(), run.state, run_p, {"party": "solo"})
	var camp_p := {"id": "p0", "fighter": "f_stoke", "meta": {"meta_heavy_bag": 2}, "techniques": [], "supplements": [], "side_effects": []}
	var camp_st := {"variant": "fight_camp", "dose": 0, "players": [camp_p]}
	var camp_before := BuildApplier.compose(cat(), camp_st, camp_p, {"party": "solo"})
	var maxed := {}
	for k in CareerDefaults.STATS:
		maxed[k] = 0.99
	var cb := CareerBuild.compose(cat(), rules, "f_stoke", maxed, {"head": 50.0})
	check((cb["creature"] as CreatureDef).moves["heavy"].poise > heavy_before, "the career build is stronger")
	check_near(Content.creature("f_stoke").moves["heavy"].poise, heavy_before, 0.0001, "Content.creature is untouched")
	check(Content.creature("f_stoke") == base, "the same cached CreatureDef")
	check_eq(sig(cat().resolver.creature_dict("f_stoke")), raw_before, "the creature entry is untouched")
	var run_after := BuildApplier.compose(cat(), run.state, run_p, {"party": "solo"})
	check_eq(sig(run_after["mods"]), sig(run_before["mods"]), "an Off the Street build is unchanged")
	check_eq(sig(run_after["creature_dict"]), sig(run_before["creature_dict"]), "and its creature")
	var camp_after := BuildApplier.compose(cat(), camp_st, camp_p, {"party": "solo"})
	check_eq(sig(camp_after["mods"]), sig(camp_before["mods"]), "a Fight Camp build is unchanged")
	check(not (run_after["sources"] as Array).has("career") and not (camp_after["sources"] as Array).has("career"), "no career package anywhere else")
	check((cb["sources"] as Array).has("career"), "the career package is only in career builds")
	# the career's own pseudo state never loads Fight Camp meta
	var pkgs := BuildApplier.packages(cat(), {"variant": "career", "dose": 0}, CareerBuild.pseudo_player("f_stoke", {}), false)
	for pk in pkgs:
		check(str(pk["kind"]) != "meta", "no meta upgrades in career builds")
