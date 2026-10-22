extends TestCase
## Profiles v2 (v0.9.18 Movesets, docs/design/MOVESET_COMBAT.md §5 and §8; SAV-04): the player's
## custom versus loadouts are a declared profile field (`loadouts`: creature id -> pool move ids).
## v1 profiles, the v0.9.16 fixture profile included, migrate by adding the field empty and are
## written back as version 2; versus setup reads and writes it through Profiles, and a malformed or
## no longer valid saved loadout falls back to the fighter's recommended loadout.

const FIX := "res://src/test/fixtures/saves_v0916/profiles"

var dir := ""
var _profile := {}


func before_each() -> void:
	dir = temp_dir("profile_loadouts_%d" % Time.get_ticks_usec())
	_profile = Profiles.current


func after_each() -> void:
	App.clear_screens()
	if App.current_scene != null:
		App.set_scene(null)
	Profiles.current = _profile


## A Profiles instance (not the autoload) over a profiles folder.
func _profiles_at(root: String) -> Node:
	var p: Node = load("res://src/persist/profiles.gd").new()
	p.set("root_override", root)
	p.call("startup")
	return p


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


func test_v1_profiles_migrate_to_v2() -> void:
	check_eq(Profiles.VERSION, 2, "profiles are version 2 since v0.9.18")
	check_eq(Profiles.default_profile("x", "X").get("loadouts"), {}, "new profiles declare the field")
	var root := dir.path_join("profiles")
	var v1 := Profiles.default_profile("rookie", "Rookie")
	v1.erase("loadouts")
	(v1["stats"] as Dictionary)["wins"] = 7
	var path := root.path_join("rookie").path_join("profile.json")
	check_eq(Saves.write_json(path, "profile", 1, v1), OK, "a v1 profile on disk")
	var p := _profiles_at(root)
	check_eq(str(p.call("id")), "rookie", "it opens")
	var cur: Dictionary = p.get("current")
	check_eq(cur.get("loadouts"), {}, "with an empty loadouts field")
	check_eq(int(cur["stats"]["wins"]), 7, "everything else is kept")
	var disk := Saves.read_json(path, "profile", Profiles.VERSION)
	check(bool(disk["ok"]) and int(disk["version"]) == Profiles.VERSION and not bool(disk["migrated"]), "written back as version 2")
	if bool(disk["ok"]):
		check_eq((disk["data"] as Dictionary).get("loadouts"), {}, "with the field")
	p.free()
	# the migration itself
	var m = Profiles.migrate(v1, 1)
	check(typeof(m) == TYPE_DICTIONARY and (m as Dictionary).get("loadouts") == {}, "v1 -> v2 adds empty loadouts")
	check(not v1.has("loadouts"), "the input is not modified")
	check(Profiles.migrate(v1, 0) == null and Profiles.migrate(v1, Profiles.VERSION + 1) == null, "unknown versions are refused")
	check(Profiles.migrate("junk", 1) == null, "a non-object is refused")
	# a v1 file written by a v0.9.18 development build may already carry loadouts: keep the good ones
	var dev := v1.duplicate(true)
	var too_long: Array = []
	for i in Profiles.MAX_LOADOUT + 1:
		too_long.append("m%d" % i)
	dev["loadouts"] = {"f_stoke": ["ember_jab", "cinder_shot"], "f_dredge": "junk", "f_gusto": ["a", "a"],
		"f_dozer": too_long, "f_jitters": ["ember_jab", 3], "f_knell": []}
	var md: Dictionary = Profiles.migrate(dev, 1)
	check_eq(md["loadouts"], {"f_stoke": ["ember_jab", "cinder_shot"]}, "only well-formed saved loadouts survive")


func test_v0916_fixture_profile_migrates() -> void:
	_fixture_profile_migrates(FIX, "0.9.16")


func test_published_v0917_fixture_profile_migrates() -> void:
	_fixture_profile_migrates("res://src/test/fixtures/saves_v0917/profiles", "0.9.17")


func _fixture_profile_migrates(fixture: String, version: String) -> void:
	if not DirAccess.dir_exists_absolute(fixture):
		skip("the save fixtures are source files (not exported with the game); checked in the source suite")
		return
	var root := dir.path_join("fixture")
	_copy_dir(fixture, root)
	var path := root.path_join("rookie").path_join("profile.json")
	var before := Saves.read_json(path, "profile", 1)
	check(bool(before["ok"]) and int(before["version"]) == 1, "the v%s profile is version 1" % version)
	if not bool(before["ok"]):
		return
	var old: Dictionary = before["data"]
	check(not old.has("loadouts"), "written before profiles had loadouts")
	var p := _profiles_at(root)
	check_eq(str(p.call("id")), "rookie", "the v%s profile opens" % version)
	var cur: Dictionary = p.get("current")
	check_eq(cur.get("loadouts"), {}, "custom loadouts start empty")
	for k in old:
		check_eq(cur.get(k), old[k], "%s kept" % k)
	var disk := Saves.read_json(path, "profile", Profiles.VERSION)
	check(bool(disk["ok"]) and int(disk["version"]) == Profiles.VERSION, "and is saved as version 2")
	p.free()


func test_saved_loadouts_round_trip_and_are_sanitized() -> void:
	var root := dir.path_join("roundtrip")
	var p := _profiles_at(root)
	var id := str(p.call("id"))
	check(id != "", "a fresh profile")
	p.call("save_loadout", "f_stoke", ["ember_jab", "flare_rush"])
	p.call("save_loadout", "f_dredge", ["x", "x"])
	p.call("save_loadout", "", ["ember_jab"])
	check_eq(p.call("saved_loadout", "f_stoke"), ["ember_jab", "flare_rush"], "a saved loadout reads back")
	check_eq(p.call("saved_loadout", "f_dredge"), [], "a malformed one is never stored")
	check_eq(p.call("saved_loadout", "f_gusto"), [], "none for other fighters")
	var disk := Saves.read_json(root.path_join(id).path_join("profile.json"), "profile", Profiles.VERSION)
	check(bool(disk["ok"]), "saved")
	if bool(disk["ok"]):
		check_eq((disk["data"] as Dictionary).get("loadouts"), {"f_stoke": ["ember_jab", "flare_rush"]}, "in the profile file")
	var cur: Dictionary = p.get("current")
	cur["loadouts"] = {"f_stoke": ["ember_jab", 4]}
	check_eq(p.call("saved_loadout", "f_stoke"), [], "a hand-edited entry reads as none")
	cur["loadouts"] = ["not", "a", "map"]
	check_eq(p.call("saved_loadout", "f_stoke"), [], "and so does a malformed field")
	p.free()


func test_versus_setup_falls_back_to_the_recommended_loadout() -> void:
	var c := Content.creature("f_stoke")
	if not check(c != null and not c.loadouts.is_empty(), "Stoke has recommended loadouts"):
		return
	var rec := c.resolve_loadout([])
	Profiles.current = Profiles.default_profile("vs_loadouts", "Tester")
	var vs := App.goto("versus_setup", {"mode": "versus"}) as VersusSetup
	await wait_frames(2)
	if not check(vs != null, "versus setup opens"):
		return
	var me := {"creature": "f_stoke", "kind": "player", "team": 0, "tier": "regular"}
	check_eq(vs.slot_loadout(me), rec, "no saved loadout: the recommended one")
	var custom := ["ember_jab", "cinder_shot", "flare_rush"]
	Profiles.current["loadouts"] = {"f_stoke": custom}
	check_eq(vs.slot_loadout(me), custom, "a saved custom loadout is used")
	check_eq(vs.slot_loadout({"creature": "f_stoke", "kind": "bot", "team": 1, "tier": "regular"}), rec, "only in the player's own slot")
	for bad in [["flamethrower", "cinder_shot"], ["ember_jab", "renamed_move"], ["ember_jab", "ember_jab"], ["ember_jab", 7], "ember_jab", {"a": 1}, []]:
		Profiles.current["loadouts"] = {"f_stoke": bad}
		check_eq(vs.slot_loadout(me), rec, "an invalid saved loadout (%s) falls back to the recommended one" % str(bad))
	Profiles.current["loadouts"] = "garbage"
	check_eq(vs.slot_loadout(me), rec, "a malformed loadouts field too")
	Profiles.current.erase("loadouts")
	check_eq(vs.slot_loadout(me), rec, "and a missing one")
	# the slot's own pick wins while it validates; an invalid pick falls back to the saved loadout
	Profiles.current["loadouts"] = {"f_stoke": custom}
	var pick := ["ember_jab", "flamethrower"]
	check_eq(vs.slot_loadout({"creature": "f_stoke", "kind": "player", "loadout": pick}), pick, "the slot's own pick")
	check_eq(vs.slot_loadout({"creature": "f_stoke", "kind": "player", "loadout": ["gone"]}), custom, "an invalid pick: the saved loadout")
	check_eq(vs.slot_loadout({"creature": "f_stoke", "kind": "bot", "loadout": ["gone"]}), rec, "or the recommended one for a bot")
	# what reaches the match is always valid
	Profiles.current["loadouts"] = {"f_stoke": ["ember_jab", "renamed_move"]}
	var s0: Dictionary = (vs.setup["slots"] as Array)[0]
	s0["creature"] = "f_stoke"
	s0["kind"] = "player"
	s0.erase("loadout")
	var cfg := vs.build_config()
	var fd: Dictionary = (cfg["fighters"] as Array)[0]
	check_eq(fd.get("loadout", []), rec, "the launched fighter entry carries the recommended loadout")
	check_eq(c.loadout_problem(fd.get("loadout", [])), "", "a valid one")
