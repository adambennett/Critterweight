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


## MCH-07/08/09: Scoring and Referee fields (standard only, defaults = the old behaviour), their
## validation, and the built-in Cage Rules preset (= the Standard Duel + 10-point + referee).
func test_scoring_and_referee_fields_validate_and_default_to_the_old_rules() -> void:
	var std := RulesValidator.fields_for("standard")
	check(std.has("scoring") and std.has("referee"), "standard shows Scoring and Referee")
	for m in RulesValidator.EDITABLE_MODES:
		if m != "standard":
			check(not RulesValidator.fields_for(m).has("scoring") and not RulesValidator.fields_for(m).has("referee"), "%s has no Scoring / Referee rows" % m)
			check(not RulesValidator.defaults_for(m).has("scoring"), "%s defaults lack the keys" % m)
	var d := RulesValidator.defaults_for("standard")
	check_eq(str(d["scoring"]), "hp", "default Health scoring")
	check_eq(d["referee"], false, "default no referee")
	var old := Content.get_entry("rules", "duel")
	check(not old.has("scoring") and not old.has("referee"), "the shipped duel has no new keys")
	var n := RulesValidator.normalize(old)
	check(str(n["scoring"]) == "hp" and n["referee"] == false, "an old preset normalizes to Health scoring, no referee")
	check_eq(str(RulesValidator.normalize({"mode": "standard", "scoring": "eleven_point"})["scoring"]), "hp", "unknown scoring -> Health")
	var duel := {"name": "t", "mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "rounds": 3, "round_time": 99.0, "win": "ko"}
	var bad := [
		[{"format": "ffa", "teams": 0, "players": [2, 8], "scoring": "ten_point"}, "scoring"],
		[{"scoring": "ten_point", "round_time": 0.0}, "round_time"],
		[{"scoring": "ten_point", "win": "score", "score_target": 5}, "win"],
		[{"format": "teams", "players": [4, 8], "referee": true}, "referee"],
	]
	for c in bad:
		var r := duel.duplicate(true)
		r.merge(c[0], true)
		var probs := RulesValidator.validate(r)
		var hit := probs.filter(func(p): return p["field"] == c[1] and p["severity"] == "error")
		check(not hit.is_empty(), "%s flags '%s': %s" % [str(c[0]), c[1], str(probs)])
		for p in hit:
			check(str(p["text"]).length() > 12, "explanation is a sentence: %s" % p["text"])
	var ok := duel.duplicate(true)
	ok.merge({"scoring": "ten_point", "referee": true, "ringout_eliminates": true, "rounds": 2}, true)
	var pr := RulesValidator.validate(ok)
	check(not RulesValidator.has_errors(pr), "10-point + referee duel is valid: %s" % str(pr))
	check(pr.any(func(p): return p["field"] == "ringout_eliminates" and p["severity"] == "warning"), "ring-out elimination warns under 10-point")
	check(not pr.any(func(p): return p["field"] == "rounds"), "no even-rounds warning under 10-point (every round is judged)")
	var hp2 := duel.duplicate(true)
	hp2.merge({"rounds": 2, "referee": true}, true)
	var pr2 := RulesValidator.validate(hp2)
	check(not RulesValidator.has_errors(pr2), "Health scoring with a referee is valid")
	check(pr2.any(func(p): return p["field"] == "rounds" and p["severity"] == "warning"), "even rounds still warn under Health scoring")
	var tag := {"name": "t", "mode": "tag_team", "format": "tag", "teams": 2, "players": [4, 4], "scoring": "ten_point", "referee": true}
	check(not RulesValidator.validate(tag).any(func(p): return p["field"] in ["scoring", "referee"]), "other modes ignore the keys")
	check(RulesValidator.describe(ok).contains("10-point") and RulesValidator.describe(ok).contains("referee"), "describe: %s" % RulesValidator.describe(ok))
	check(not RulesValidator.describe(duel).contains("10-point") and not RulesValidator.describe(duel).contains("referee"), "describe unchanged without the keys")
	check(str(RulesValidator.field("referee")["help"]).contains("%d knockdowns" % RefereeRules.REF_KD_LIMIT), "referee help names the knockdown limit")
	var editor: GDScript = load("res://src/ui/screens/rules_editor_screen.gd")
	var labels: Dictionary = editor.get_script_constant_map()["VALUE_LABELS"]
	check(str(labels.get("hp", "")) == "Health" and str(labels.get("ten_point", "")) == "10-point must", "editor value labels")


func test_cage_rules_preset_is_the_standard_duel_with_officials() -> void:
	var cage := Content.get_entry("rules", "cage_rules")
	var duel := Content.get_entry("rules", "duel")
	check(not cage.is_empty(), "Cage Rules is a built-in preset")
	check_eq(Content.origin_of("rules", "cage_rules"), "core")
	check_eq(str(cage.get("name", "")), "Cage Rules")
	check_eq(str(cage.get("scoring", "")), "ten_point")
	check_eq(cage.get("referee", false), true)
	var probs := RulesValidator.validate(RulesValidator.normalize(cage))
	check(not RulesValidator.has_errors(probs), "valid: %s" % str(probs))
	var own := ["id", "name", "description", "scoring", "referee", "_package", "_file"]
	for k in duel:
		if not k in own:
			check(cage.has(k) and cage[k] == duel[k], "'%s' inherited from the duel (%s vs %s)" % [k, str(cage.get(k)), str(duel[k])])
	for k in cage:
		if not k in own:
			check(duel.has(k), "'%s' is a duel key" % k)
	check(str(cage["description"]) != str(duel["description"]) and str(cage["description"]).length() <= 200, "own description")
	# a user copy keeps the officials through save / load
	var dup := RulePresets.duplicate_preset("cage_rules")
	check(dup["ok"], "copy saved")
	var copy := Content.get_entry("rules", str(dup["id"]))
	check(str(copy.get("scoring", "")) == "ten_point" and copy.get("referee", false) == true, "the copy keeps 10-point + referee")
	var listed := RulePresets.list().filter(func(r): return str(r["id"]) == str(dup["id"]))
	check(not listed.is_empty() and str(listed[0].get("scoring", "")) == "ten_point", "reads back from disk")


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
