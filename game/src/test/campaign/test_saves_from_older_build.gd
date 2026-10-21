extends CareerTestCase
## Player saves written by an older build still load and continue in this one (SAV, v0.9.17 R2).
## The fixtures under res://src/test/fixtures/saves_v0916/ were written by the v0.9.16 release
## checkout through its own stores (test_zz_save_fixture_writer.gd): settings with changed values,
## a suspended Off the Street run four nodes in, a Career after one fought bout, and a user rules
## preset. Each is copied to a temporary folder, loaded, checked and played on.

const FIX := "res://src/test/fixtures/saves_v0916"
const PROFILE := "tester"

var _root := ""
var _saved_settings := {}


func before_each() -> void:
	_root = temp_dir("older_saves_%d" % Time.get_ticks_usec())
	_saved_settings = {"values": Settings.values.duplicate(true), "path": Settings.path_override, "ro": Settings.read_only}


func after_each() -> void:
	Settings.values = _saved_settings["values"]
	Settings.path_override = _saved_settings["path"]
	Settings.read_only = _saved_settings["ro"]
	super.after_each()


func _have_fixtures() -> bool:
	if not DirAccess.dir_exists_absolute(FIX):
		skip("the save fixtures are source files (not exported with the game); checked in the source suite")
		return false
	return true


## Copies a fixture folder (recursively) into the temporary root and returns its copy.
func _copy(rel: String) -> String:
	var dst := _root.path_join(rel)
	_copy_dir(FIX.path_join(rel), dst)
	return dst


func _copy_dir(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	var d := DirAccess.open(src)
	if d == null:
		return
	for f in d.get_files():
		var data := FileAccess.get_file_as_bytes(src.path_join(f))
		var out := FileAccess.open(dst.path_join(f), FileAccess.WRITE)
		if out:
			out.store_buffer(data)
	for sub in d.get_directories():
		_copy_dir(src.path_join(sub), dst.path_join(sub))


func test_run_from_v0916_resumes_verifies_and_finishes() -> void:
	if not _have_fixtures():
		return
	var rs := RunStore.new(_copy("runs"))
	var r := rs.load_slot(PROFILE, "off_the_street", cat())
	if not check(bool(r["ok"]), "the v0.9.16 run loads: %s" % str(r.get("error", ""))):
		return
	var v := RunController.verify(cat(), r["state"])
	check(bool(v["ok"]), "its decision log still rebuilds it: %s" % str(v.get("error", "")))
	var ctrl := RunController.from_state(cat(), r["state"])
	check(not ctrl.is_over(), "suspended mid-run")
	play_synthetic(ctrl)
	check(ctrl.is_over(), "and it plays on to the end (%s)" % ctrl.phase())
	check_eq(rs.save(ctrl.state, PROFILE), OK, "and saves again in the current format")


## Career v1 -> v2 (v0.9.18 Movesets, MOVESET_COMBAT.md §8): the v0.9.16 career loads through the
## explicit migration with the starting moves of a new career (its fighter's recommended loadouts
## learned, the default one equipped, nothing drilled), books its next bout, plays it for real
## (headless, a bot in the career fighter's corner) with that loadout, and saves as version 2.
func test_career_from_v0916_migrates_books_and_plays_the_next_bout() -> void:
	if not _have_fixtures():
		return
	var cs := CareerStore.new(_copy("careers"))
	var raw := Saves.read_json(cs.slot_path(PROFILE, 1), CareerStore.KIND, 1)
	check(bool(raw["ok"]) and int(raw["version"]) == 1, "the fixture is a version 1 career")
	check(typeof(raw["data"]) == TYPE_DICTIONARY and not (raw["data"] as Dictionary).has("moves"), "written before careers had moves")
	var r := CareerController.load_career(cat(), cs, PROFILE, 1)
	if not check(bool(r["ok"]), "the v0.9.16 career loads: %s" % str(r.get("error", ""))):
		return
	check(bool(r["load"]["migrated"]), "through the v1 -> v2 migration")
	var ctrl: CareerController = r["ctrl"]
	check_eq(int(ctrl.state.get("version", 0)), CareerState.VERSION, "now a current-format career")
	check_eq(int(ctrl.state.get("migrated_from", 0)), 1, "which records the format it came from")
	check_eq(str(ctrl.state.get("fighter", "")), "f_varga", "the career fighter is kept")
	check_eq(int((ctrl.state.get("record", {}) as Dictionary).get("w", 0)), 1, "its won bout is on the record")
	check_eq((ctrl.state.get("history", []) as Array).size(), 1, "and in its history")
	check_eq(int(ctrl.state.get("week", 0)), 2, "the calendar is kept")
	var kit := ctrl.creature()
	if not check(kit != null, "the career fighter's kit resolves"):
		return
	var want := CareerMoves.starting(kit)
	check_eq(ctrl.state.get("moves", {}), want, "default moves: the recommended loadouts learned, the default loadout equipped")
	check(not (want["equipped"] as Array).is_empty(), "a loadout is equipped")
	check_eq(want["equipped"], CareerMoves.default_loadout(kit), "the default loadout")
	check((ctrl.state["moves"]["drilled"] as Dictionary).is_empty(), "nothing drilled")
	var probs := CareerState.check(cat(), ctrl.state)
	check(probs.filter(func(p) -> bool: return str(p).begins_with("moves")).is_empty(), "the moves block is valid: %s" % [probs])
	check(not ctrl.repairs.has("moves updated"), "the migration itself produced valid moves (no repair needed)")
	if not ctrl.is_booked():
		var offers: Array = ctrl.state.get("offers", [])
		check(not offers.is_empty(), "it has fight offers")
		if offers.is_empty():
			return
		check(ctrl.accept(str((offers[0] as Dictionary)["id"])), "the next bout can be booked: %s" % ctrl.last_error)
	var guard := 0
	while not ctrl.fight_ready() and guard < 20:
		check(bool(ctrl.train("power")["ok"]), "a camp week")
		guard += 1
	check(ctrl.begin_fight(), "fight week: the bout launches: %s" % ctrl.last_error)
	var built := ctrl.fight_config({"player_kind": "bot", "player_bot_tier": "contender"})
	if not check((built["errors"] as PackedStringArray).is_empty(), "the bout builds: %s" % [built["errors"]]):
		return
	var cfg: Dictionary = built["config"]
	check_eq(str((cfg["rules"] as Dictionary).get("combat", "")), "moves", "a Movesets bout (the career preset's combat style)")
	check_eq(cfg["fighters"][0]["loadout"], want["equipped"], "the career fighter brings its default loadout")
	# the D6 cap; without 10-point scoring in the build, drawn HP rounds can add rounds
	var rounds := int(cfg["rules"]["rounds"])
	var max_s := maxf(float(built["max_seconds"]), rounds * 2 * (99.0 + 2.2 + 3.0) + 36.0)
	SimSpeed.set_scale(16.0)
	var res: Dictionary = await HeadlessFightRunner.run(self, cfg, max_s)
	SimSpeed.restore()
	check(int(res.get("winner_team", -2)) != -2, "the bout reached a result")
	var s := ctrl.apply_result(res, ctrl.booked_id())
	check(bool(s.get("ok", false)), "and it settles: %s" % str(s.get("error", "")))
	check_eq((ctrl.state.get("history", []) as Array).size(), 2, "a second bout in the history")
	check_eq(cs.save(ctrl.state, PROFILE, 1), OK, "and saves again")
	var back := Saves.read_json(cs.slot_path(PROFILE, 1), CareerStore.KIND, CareerState.VERSION)
	check(bool(back["ok"]) and int(back["version"]) == CareerState.VERSION and not bool(back["migrated"]), "in the current format")
	if bool(back["ok"]):
		check_eq((back["data"] as Dictionary).get("moves", {}), ctrl.state["moves"], "with its moves")


func test_settings_and_rules_preset_from_v0916_load() -> void:
	if not _have_fixtures():
		return
	var sdir := _copy("profiles")
	Settings.path_override = sdir.path_join("settings.json")
	Settings.read_only = false
	Settings.load_settings()
	check_eq(int(Settings.get_value("audio.master")), 60, "a changed volume is kept")
	check_eq(str(Settings.get_value("access.subtitle_size")), "large", "a changed subtitle size is kept")
	check_eq(int(Settings.get_value("graphics.effects")), 1, "a changed effects quality is kept")
	check_eq(bool(Settings.get_value("cosmetic.legacy_varga")), false, "new options start at their defaults")
	check(not Settings.read_only, "the older file is writable (not mistaken for a newer one)")
	var pdir := _copy("presets/rules")
	var files := DirAccess.get_files_at(pdir)
	check(files.size() >= 1, "the user preset is there")
	for f in files:
		# rules_preset v1 -> v2 (v0.9.18, MOVESET_COMBAT.md §1): read through the presets' own migration
		var rd := Saves.read_json(pdir.path_join(f), RulePresets.KIND, RulePresets.VERSION, Callable(RulePresets, "_migrate"))
		if check(bool(rd["ok"]), "%s reads: %s" % [f, str(rd.get("error", ""))]):
			check(bool(rd["migrated"]) and int(rd["version"]) == 1, "%s is a v1 preset, migrated on read" % f)
			var data: Dictionary = rd["data"]
			check_eq(str(data.get("name", "")), "Fixture Duel", "preset name kept")
			check_eq(int(data.get("rounds", 0)), 2, "its own fields kept")
			check_eq(str(data.get("combat", "")), "moves", "a preset written before the combat rule plays Movesets")
			check_eq(str(data.get("migrated_from", "")), "rules_preset v1", "and records its migration")
			check(not RulesValidator.has_errors(RulesValidator.validate(RulesValidator.normalize(data))), "the preset still validates")
