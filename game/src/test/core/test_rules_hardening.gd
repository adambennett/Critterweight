extends TestCase
## MCH-05/06 hardening: preset imports check the file size before reading anything, and
## "fighter_mods" accept only whitelisted modifiers with finite, clamped values — in
## RulesValidator (presets) and again in MatchSim (rules from mods, imports or a host).


func after_each() -> void:
	for r in RulePresets.list():
		RulePresets.delete(str(r["id"]))


func _store(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ---------------------------------------------------------------------------------------------
# J. size before content

func test_preset_import_checks_the_size_before_reading() -> void:
	var d := temp_dir("rules_size_%d" % Time.get_ticks_usec())
	var big := d.path_join("huge.rules.json")
	_store(big, JSON.stringify({"name": "Huge", "mode": "standard", "format": "duel", "pad": "x".repeat(300 * 1024)}))
	var r := RulePresets.import_preset(big)
	check(not r["ok"] and str(r["problems"]).contains("too large"), "oversized file refused: %s" % str(r["problems"]))
	var lim := RulePresets.read_limited(big, 1024)
	check(not lim["ok"] and str(lim["text"]) == "" and str(lim["error"]).contains("too large"), "nothing is read past the limit")
	var ok := RulePresets.read_limited(big, 1024 * 1024)
	check(ok["ok"] and str(ok["text"]).length() > 300 * 1024, "within the limit the text is read")
	var empty := d.path_join("empty.rules.json")
	_store(empty, "")
	check(not RulePresets.import_preset(empty)["ok"], "empty file refused")
	check(not RulePresets.import_preset(d.path_join("missing.rules.json"))["ok"], "missing file refused")


# ---------------------------------------------------------------------------------------------
# K. fighter_mods whitelist and clamps

func test_fighter_mods_are_whitelisted_and_clamped() -> void:
	var raw := {"damage": INF, "defense": [1, 2], "poise": 0.0, "speed": 1e300, "evil_key": 3.0, "no_grabs": true,
		"no_juice": "yes", "start_hype": 500.0, "max_health_add": -50.0, "knockback_taken": NAN, "heal": {"x": 1}}
	var clean := RulesValidator.clean_fighter_mods(raw)
	check(not clean.has("damage") and not clean.has("defense") and not clean.has("knockback_taken") and not clean.has("heal"), "non-numbers and non-finite values dropped: %s" % str(clean))
	check(not clean.has("evil_key") and not clean.has("no_juice"), "unknown keys and wrongly typed flags dropped")
	check_near(float(clean.get("poise", -1.0)), 0.1, 0.0001, "poise clamped above zero (it divides)")
	check_near(float(clean.get("speed", -1.0)), 3.0, 0.0001, "huge values clamped")
	check_near(float(clean.get("start_hype", -1.0)), 100.0, 0.0001, "start hype clamped")
	check_near(float(clean.get("max_health_add", -1.0)), 0.0, 0.0001, "negative health add clamped")
	check_eq(clean.get("no_grabs"), true, "flags kept")
	check(RulesValidator.clean_fighter_mods("not a dictionary").is_empty(), "garbage gives nothing")
	# validate() explains every bad entry; normalize() keeps only the clean ones
	var rules := RulesValidator.defaults_for("standard")
	rules["name"] = "Hostile"
	rules["fighter_mods"] = raw
	var probs := RulesValidator.validate(rules).filter(func(p): return p["field"] == "fighter_mods")
	check(probs.size() >= 8, "each bad fighter modifier is an error: %s" % str(probs))
	check_eq(RulesValidator.normalize(rules)["fighter_mods"], clean, "normalize keeps the clean subset")
	# an imported preset file is cleaned before it is saved
	var d := temp_dir("rules_mods_%d" % Time.get_ticks_usec())
	var path := d.path_join("hostile.rules.json")
	_store(path, "{\"name\": \"Hostile\", \"mode\": \"standard\", \"format\": \"duel\", \"teams\": 2, \"players\": [2, 2], \"fighter_mods\": {\"damage\": 1e300, \"defense\": [1, 2], \"poise\": 0, \"no_grabs\": true}}")
	var imp := RulePresets.import_preset(path)
	check(imp["ok"], "imported: %s" % str(imp["problems"]))
	var saved := Content.get_entry("rules", str(imp["id"]))
	check_eq(saved.get("fighter_mods", {}), {"damage": 4.0, "poise": 0.1, "no_grabs": true}, "stored cleaned")


func test_match_sim_clamps_rule_modifiers_at_use() -> void:
	var rules := {"rounds": 1, "round_time": 0, "damage_mult": [1], "health_mult": INF, "gravity_mult": 50.0, "knockback_mult": 1e300,
		"fighter_mods": {"damage": INF, "defense": [1], "poise": 0.0, "speed": 1e300, "evil": 3.0, "no_grabs": true, "max_health_add": 1e9}}
	var sim := make_sim("the_gullet", rules, [{"creature": "dev_biped", "team": 0}, {"creature": "dev_biped", "team": 1}])
	var m: Dictionary = sim.fighters[0].mods
	check_near(float(m["damage"]), 1.0, 0.0001, "an Array damage_mult and an INF damage modifier are ignored")
	check_near(float(m["defense"]), 1.0, 0.0001, "an Array modifier is ignored (no script error)")
	check_near(float(m["poise"]), 0.1, 0.0001, "zero poise clamped (it is a divisor)")
	check_near(float(m["speed"]), 3.0, 0.0001, "huge speed clamped")
	check_near(float(m["max_health"]), 1.0, 0.0001, "INF health_mult ignored")
	check_near(float(m["knockback_taken"]), 3.0, 0.0001, "knockback_mult clamped to its range")
	check_near(float(m["max_health_add"]), 200.0, 0.0001, "health add clamped")
	check(not m.has("evil"), "unknown modifiers are not applied")
	check(bool(m.get("no_grabs", false)), "flags applied")
	check_near(sim.gravity, 9.81 * sim.arena.gravity_mult * 2.0, 0.001, "gravity clamped to the rules range")
	check(is_finite(sim.fighters[0].max_health) and sim.fighters[0].max_health > 0.0, "finite health")
	await step_sim(sim, 0.25)
