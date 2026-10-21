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


func test_career_from_v0916_loads_and_books_the_next_bout() -> void:
	if not _have_fixtures():
		return
	var cs := CareerStore.new(_copy("careers"))
	var r := CareerController.load_career(cat(), cs, PROFILE, 1)
	if not check(bool(r["ok"]), "the v0.9.16 career loads: %s" % str(r.get("error", ""))):
		return
	var ctrl: CareerController = r["ctrl"]
	check_eq(str(ctrl.state.get("fighter", "")), "f_varga", "the career fighter is kept")
	check_eq(int((ctrl.state.get("record", {}) as Dictionary).get("w", 0)), 1, "its won bout is on the record")
	check_eq((ctrl.state.get("history", []) as Array).size(), 1, "and in its history")
	if not ctrl.is_booked():
		var offers: Array = ctrl.state.get("offers", [])
		check(not offers.is_empty(), "it has fight offers")
		if not offers.is_empty():
			check(ctrl.accept(str((offers[0] as Dictionary)["id"])), "the next bout can be booked: %s" % ctrl.last_error)
	check_eq(cs.save(ctrl.state, PROFILE, 1), OK, "and saves again")


func test_settings_and_rules_preset_from_v0916_load() -> void:
	if not _have_fixtures():
		return
	var sdir := _copy("profiles")
	Settings.path_override = sdir.path_join("settings.json")
	Settings.read_only = false
	var old_file := Saves.read_json(Settings.path_override, "settings", Settings.VERSION)
	check(bool(old_file["ok"]) and not (old_file["data"] as Dictionary).has("cosmetic.legacy_varga"), "the v0.9.16 file predates the Legacy Varga option")
	# loaded the way the game starts (defaults first, then the file): a key the old file lacks must
	# come from the defaults, never from whatever this process held before
	Settings.values["cosmetic.legacy_varga"] = true
	Settings.init_defaults()
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
		var rd := Saves.read_json(pdir.path_join(f), RulePresets.KIND, RulePresets.VERSION)
		if check(bool(rd["ok"]), "%s reads: %s" % [f, str(rd.get("error", ""))]):
			var data: Dictionary = rd["data"]
			check_eq(str(data.get("name", "")), "Fixture Duel", "preset name kept")
			check(not RulesValidator.has_errors(RulesValidator.validate(RulesValidator.normalize(data))), "the preset still validates")
