extends TestCase
## MCH-05/06: rules validation with explanations, mode defaults, user presets (save, version,
## duplicate, rename, delete, export, import), registration in Content across reloads, and that a
## custom preset actually drives a match.


func after_each() -> void:
	for r in RulePresets.list():
		RulePresets.delete(str(r["id"]))


func test_every_core_preset_and_mode_default_validates() -> void:
	for id in Content.ids("rules"):
		var r := Content.get_entry("rules", str(id))
		if str(r.get("mode", "")) == "tutorial":
			continue
		var probs := RulesValidator.validate(RulesValidator.normalize(r))
		check(not RulesValidator.has_errors(probs), "core preset %s is valid: %s" % [id, str(probs)])
	for m in RulesValidator.EDITABLE_MODES:
		var d := RulesValidator.defaults_for(m)
		d["name"] = "x"
		check(not RulesValidator.has_errors(RulesValidator.validate(d)), "defaults for %s are valid: %s" % [m, str(RulesValidator.validate(d))])


func test_invalid_combinations_are_explained() -> void:
	var cases := [
		[{"mode": "chumball", "format": "ffa", "teams": 0}, "format"],
		[{"mode": "standard", "format": "duel", "teams": 2, "players": [2, 4]}, "players_max"],
		[{"mode": "standard", "format": "teams", "teams": 1}, "teams"],
		[{"mode": "standard", "format": "ffa", "win": "survive"}, "win"],
		[{"mode": "standard", "format": "duel", "name": ""}, "name"],
		[{"mode": "no_such_mode"}, "mode"],
		[{"mode": "standard", "format": "duel", "fighter_hooks": [{"on": "nonsense", "do": []}]}, "fighter_hooks"],
	]
	for c in cases:
		var r: Dictionary = {"name": "t"}
		r.merge(c[0], true)
		var probs := RulesValidator.validate(r)
		var hit := probs.filter(func(p): return p["field"] == c[1] and p["severity"] == "error")
		check(not hit.is_empty(), "%s flags '%s': %s" % [str(c[0]), c[1], str(probs)])
		for p in hit:
			check(str(p["text"]).length() > 12, "explanation is a sentence: %s" % p["text"])
	var w := RulesValidator.validate({"name": "t", "mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "rounds": 2, "respawn": true, "lives": 1})
	check(w.any(func(p): return p["field"] == "rounds" and p["severity"] == "warning"), "even rounds warn")
	check(w.any(func(p): return p["field"] == "respawn" and p["severity"] == "warning"), "useless respawn warns")


func test_normalize_clamps_and_keeps_unknown_keys() -> void:
	var n := RulesValidator.normalize({"mode": "standard", "damage_mult": 99.0, "rounds": -3, "players": [9, 1], "my_mod_key": 7})
	check_near(float(n["damage_mult"]), 4.0, 0.001, "clamped damage")
	check_eq(int(n["rounds"]), 1, "clamped rounds")
	check_eq(n["players"], [8, 8], "players clamped and ordered")
	check_eq(int(n["my_mod_key"]), 7, "unknown keys kept for mods")


func test_presets_save_version_duplicate_rename_export_import_delete() -> void:
	var r := RulesValidator.defaults_for("standard")
	r["name"] = "Glass Cannon"
	r["damage_mult"] = 2.0
	r["health_mult"] = 0.75
	var res := RulePresets.save(r)
	check(res["ok"], "saved: %s" % str(res["problems"]))
	var id := str(res["id"])
	check(id.begins_with("user:"), "user id")
	check(not Content.get_entry("rules", id).is_empty(), "registered in Content")
	check_eq(Content.origin_of("rules", id), "user")
	check_eq(int(Content.get_entry("rules", id)["version"]), 1, "version 1")
	res = RulePresets.save(Content.get_entry("rules", id), id)
	check_eq(int(Content.get_entry("rules", id)["version"]), 2, "re-save bumps version")
	# survives a full content reload (e.g. mods toggled)
	Mods.apply()
	check(not Content.get_entry("rules", id).is_empty(), "re-registered after reload")
	var dup := RulePresets.duplicate_preset(id)
	check(dup["ok"] and str(dup["id"]) != id, "duplicate")
	check(str(Content.get_entry("rules", str(dup["id"]))["name"]).begins_with("Copy of"), "copy name")
	var core_dup := RulePresets.duplicate_preset("duel")
	check(core_dup["ok"], "built-in presets can be duplicated")
	check(not RulePresets.rename("duel", "Nope")["ok"], "built-ins can't be renamed")
	var ren := RulePresets.rename(id, "Glass Jaw")
	check(ren["ok"] and str(Content.get_entry("rules", id)["name"]) == "Glass Jaw", "renamed in place")
	var out := RulePresets.export_preset(id, temp_dir("rules_export"))
	check(out.ends_with(".rules.json") and FileAccess.file_exists(out), "exported")
	var imp := RulePresets.import_preset(out)
	check(imp["ok"] and str(imp["id"]) != id, "imported as a new preset")
	check_near(float(Content.get_entry("rules", str(imp["id"]))["damage_mult"]), 2.0, 0.001, "values survive the round trip")
	var bad := temp_dir("rules_bad").path_join("bad.rules.json")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{\"name\": \"x\"}")
	f.close()
	check(not RulePresets.import_preset(bad)["ok"], "a file without a mode is rejected")
	check(RulePresets.delete(id), "deleted")
	check(Content.get_entry("rules", id).is_empty(), "unregistered")
	check(DirAccess.dir_exists_absolute(RulePresets.dir().path_join(".removed")), "moved aside, not destroyed")
	check(not RulePresets.save({"name": "", "mode": "standard"})["ok"], "invalid presets are not saved")


func test_custom_preset_drives_a_match() -> void:
	var r := RulesValidator.defaults_for("standard")
	r["name"] = "Moon Duel"
	r["gravity_mult"] = 0.5
	r["damage_mult"] = 1.5
	r["round_time"] = 30.0
	var res := RulePresets.save(r)
	var cfg := App.resolve_match_config({"arena": "the_gullet", "rules": str(res["id"]), "seed": 3,
		"fighters": [{"creature": "dev_biped", "team": 0}, {"creature": "dev_biped", "team": 1}]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var entries := []
	for e in cfg["fighters"]:
		var d: Dictionary = e.duplicate()
		d["source"] = null
		entries.append(d)
	sim.setup({"arena": cfg["arena"], "rules": cfg["rules"], "seed": 3, "mode": cfg["mode"], "fighters": entries})
	check_near(sim.gravity, 9.81 * 0.5, 0.01, "gravity from the preset")
	check_near(float(sim.fighters[0].mods["damage"]), 1.5, 0.01, "damage from the preset")
	check_near(sim.mode.round_timer, 30.0, 0.01, "round time from the preset")
	await step_sim(sim, 0.5)
