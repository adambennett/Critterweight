extends TestCase
## CNT-03 / ELEMENTS.md: build-up thresholds, statuses, reactions, resist matrix, caps.


func _two() -> MatchSim:
	return make_sim("the_gullet", {"rounds": 1, "round_time": 0}, [{"creature": "dev_biped", "team": 0}, {"creature": "dev_biped", "team": 1}])


func test_matchup_matrix_is_mild_and_cyclic() -> void:
	check_near(Elements.damage_mult("scorch", "gale"), 1.15, 0.001)
	check_near(Elements.damage_mult("gale", "scorch"), 0.85, 0.001)
	check_near(Elements.damage_mult("scorch", "grit"), 1.0, 0.001, "neutral pair")
	check_eq(Elements.reactions.size(), 14, "fourteen reactions")


func test_buildup_triggers_status_at_threshold() -> void:
	var sim := _two()
	var b := sim.fighters[1]
	b.statuses.add_buildup("scorch", 60.0, sim.fighters[0])
	check(not b.statuses.has_element("scorch"), "below threshold")
	b.statuses.add_buildup("scorch", 45.0, sim.fighters[0])
	check(b.statuses.has_element("scorch"), "Sizzle at 100")
	check_near(float(b.statuses.element_status("scorch")["left"]), 5.0, 0.01, "Sizzle duration")


func test_reaction_short_out_consumes_soaked_and_damages() -> void:
	var sim := _two()
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	b.statuses.add_buildup("brine", 100.0, a)
	check(b.statuses.has_element("brine"), "Soaked")
	var hp := b.health
	b.statuses.add_buildup("static", 100.0, a)
	check(not b.statuses.has_element("brine"), "Soaked consumed")
	check(b.health < hp, "Short-Out damage dealt")
	var found := false
	for ev in sim.events:
		if ev["type"] == "reaction" and ev["reaction"] == "short_out":
			found = true
	check(found, "reaction event emitted")


func test_max_three_element_statuses() -> void:
	var sim := _two()
	var b := sim.fighters[1]
	for el in ["scorch", "static", "grit", "gale"]:
		var st: Dictionary = Elements.defs[el]["status"].duplicate()
		st["element"] = el
		b.statuses.add(st)
	var n := 0
	for s in b.statuses.active:
		if str(s.get("element", "")) != "":
			n += 1
	check(n <= 3, "at most three element statuses (got %d)" % n)


func test_self_element_immunity_from_own_attacks() -> void:
	var sim := _two()
	var a := sim.fighters[0]
	a.creature.element = "scorch"
	a.statuses.add_buildup("scorch", 200.0, a)
	check(not a.statuses.has_element("scorch"), "own element from own source ignored")
	a.creature.element = ""


## A fighter whose element changes mid-fight (a boss's element cycle sets mods.effect_element)
## re-elements its elemental areas and projectiles; neutral effects stay neutral.
func test_effect_element_override_follows_the_fighter() -> void:
	var sim := make_sim("", {"rounds": 1, "round_time": 0}, [{"creature": "dev_biped", "team": 0}, {"creature": "dev_biped", "team": 1}])
	var f := sim.fighters[0]
	f.mods["effect_element"] = "static"
	var n := sim.effects.entities.size()
	sim.effects.fire(f, {"type": "projectile", "speed": 6.0, "element": "scorch", "damage": 3.0}, null)
	sim.effects.fire(f, {"type": "projectile", "speed": 6.0, "damage": 3.0}, null)
	check_eq(str(sim.effects.entities[n]["element"]), "static", "an elemental projectile takes the cycled element")
	check_eq(str(sim.effects.entities[n + 1]["element"]), "", "a neutral projectile stays neutral")
