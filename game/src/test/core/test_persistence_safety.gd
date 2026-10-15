extends TestCase
## SAV-02 hardening: files written by a NEWER game version are never overwritten (Saves refuses,
## Settings/Profiles/mod sets go read-only and say so), a write never deletes the only valid copy,
## and recovery follows the write order (a sequence number), not the wall clock.

var dir := ""


func before_each() -> void:
	dir = temp_dir("persist_safety_%d" % Time.get_ticks_usec())


func after_each() -> void:
	Saves.clock_override = -1.0
	Saves.simulate_crash_after_tmp = false


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _store(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _quarantined(path: String) -> Array:
	return Array(DirAccess.get_files_at(path.get_base_dir())).filter(func(f): return str(f).begins_with(path.get_file() + ".damaged-"))


# ---------------------------------------------------------------------------------------------
# E. newer formats are never overwritten

func test_saves_never_overwrite_a_newer_format() -> void:
	var p := dir.path_join("future.json")
	check_eq(Saves.write_json(p, "test", 9, {"x": 1}), OK, "a newer build wrote this")
	var before := _text(p)
	check_eq(Saves.write_json(p, "test", 1, {"x": 2}), ERR_FILE_CANT_WRITE, "this build refuses to write over it")
	check_eq(_text(p), before, "file unchanged")
	check(not FileAccess.file_exists(p + ".bak") and not FileAccess.file_exists(p + ".tmp"), "nothing rotated or staged")
	check(Saves.write_json(p, "test", 1, {"x": 3}) != OK and _text(p) == before, "a second write cannot erase it either")
	check(Saves.is_newer(p, "test", 1), "is_newer() tells callers")
	# a newer copy kept as .bak (main file damaged) is protected the same way
	var q := dir.path_join("future_bak.json")
	Saves.write_json(q + ".src", "test", 7, {"y": 1})
	DirAccess.rename_absolute(q + ".src", q + ".bak")
	_store(q, "{ damaged")
	var bak_before := _text(q + ".bak")
	var r := Saves.read_json(q, "test", 1)
	check(not r["ok"] and r["newer"], "reading reports the newer copy")
	check_eq(Saves.write_json(q, "test", 1, {"y": 2}), ERR_FILE_CANT_WRITE, "and writing is refused")
	check_eq(_text(q + ".bak"), bak_before, "the newer .bak survives")
	# a newer format that hashes differently is still recognised as newer, not as damaged
	var s := dir.path_join("future_hash.json")
	Saves.write_json(s, "test", 5, {"z": 1})
	_store(s, _text(s).replace("\"checksum\": \"", "\"checksum\": \"v5-"))
	check(Saves.read_json(s, "test", 1)["newer"], "newer even when its checksum scheme is unknown")


func test_a_write_never_deletes_the_only_valid_copy() -> void:
	var p := dir.path_join("dmg.json")
	Saves.write_json(p, "test", 1, {"gen": 1})
	Saves.write_json(p, "test", 1, {"gen": 2})
	_store(p, "{ damaged main file")
	var bak := _text(p + ".bak")
	check(Saves.read_json(p, "test", 1)["recovered_from"] == "bak", "the .bak is the only valid copy")
	check_eq(Saves.write_json(p, "test", 1, {"gen": 3}), OK, "write")
	check_eq(_text(p + ".bak"), bak, "the valid .bak was not replaced by the damaged file")
	check_eq(_quarantined(p).size(), 1, "the damaged file was moved aside, not deleted")
	if _quarantined(p).size() == 1:
		check_eq(_text(p.get_base_dir().path_join(str(_quarantined(p)[0]))), "{ damaged main file", "with its content")
	check_eq(Saves.write_json(p, "test", 1, {"gen": 4}), OK, "second write")
	check_eq(int(Saves.read_json(p, "test", 1)["data"]["gen"]), 4, "newest data")
	check_eq(_quarantined(p).size(), 1, "the quarantined copy is still there after another write")
	# quarantining twice in the same second keeps both copies
	_store(p, "{ damaged again")
	var q1 := Saves.quarantine(p)
	_store(p, "{ and again")
	var q2 := Saves.quarantine(p)
	check(q1 != "" and q2 != "" and q1 != q2 and FileAccess.file_exists(q1) and FileAccess.file_exists(q2), "quarantine never replaces an earlier copy")


func test_settings_from_a_newer_version_are_left_untouched() -> void:
	var p := dir.path_join("settings.json")
	Saves.write_json(p, "settings", Settings.VERSION + 1, {"audio.music": 10, "future.option": true})
	var before := _text(p)
	var s = load("res://src/persist/settings.gd").new()
	s.path_override = p
	s.init_defaults()
	s.load_settings()
	check(bool(s.read_only), "read-only mode")
	check(str(s.load_error).contains("newer"), "the player is told: %s" % s.load_error)
	s.set_value("audio.music", 40, false, true)
	s.save_settings()
	check_eq(_text(p), before, "settings.json unchanged")
	check(not FileAccess.file_exists(p + ".bak"), "not rotated")
	s.free()
	# a damaged settings file is kept (quarantined), never deleted by later saves
	var d := dir.path_join("settings_damaged.json")
	_store(d, "{ broken")
	var s2 = load("res://src/persist/settings.gd").new()
	s2.path_override = d
	s2.init_defaults()
	s2.load_settings()
	check(not bool(s2.read_only) and str(s2.load_error).contains("could not be read"), "damaged is not newer")
	s2.save_settings()
	s2.save_settings()
	check_eq(_quarantined(d).size(), 1, "the damaged file survives two saves")
	s2.free()


func test_profiles_from_a_newer_version_are_never_overwritten() -> void:
	var root := dir.path_join("profiles")
	var index := root.path_join("index.json")
	var rookie := root.path_join("rookie").path_join("profile.json")
	Saves.write_json(index, "profile_index", 2, {"profiles": [{"id": "rookie", "name": "Rookie"}], "active": "rookie"})
	Saves.write_json(rookie, "profile", 2, {"id": "rookie", "name": "Rookie", "stats": {"wins": 99}})
	var index_before := _text(index)
	var rookie_before := _text(rookie)
	var p = load("res://src/persist/profiles.gd").new()
	p.root_override = root
	p.startup()
	check(bool(p.index_read_only), "profile list is read-only")
	check(str(p.read_only_note).contains("newer") and str(p.last_error) != "", "the player is told: %s" % p.read_only_note)
	check(str(p.id()) != "" and str(p.id()) != "rookie", "a fresh profile is used instead of the newer one (%s)" % p.id())
	p.record_match(true, false, "dev_biped", {"kos": 1}, 30.0)
	p.rename("Someone")
	var made: String = p.create("Rookie")
	check(made != "rookie", "create() never lands on the newer profile's folder (%s)" % made)
	check_eq(_text(index), index_before, "index.json unchanged")
	check_eq(_text(rookie), rookie_before, "rookie/profile.json unchanged")
	check(not FileAccess.file_exists(index + ".bak") and not FileAccess.file_exists(rookie + ".bak"), "nothing rotated")
	p.free()
	# our own list, but one listed profile is newer: it is skipped, never deleted
	var root2 := dir.path_join("profiles2")
	Saves.write_json(root2.path_join("index.json"), "profile_index", 1, {"profiles": [{"id": "champ", "name": "Champ"}, {"id": "rookie", "name": "Rookie"}], "active": "champ"})
	Saves.write_json(root2.path_join("champ/profile.json"), "profile", 2, {"id": "champ"})
	Saves.write_json(root2.path_join("rookie/profile.json"), "profile", 1, Profiles.default_profile("rookie", "Rookie"))
	var champ_before := _text(root2.path_join("champ/profile.json"))
	var p2 = load("res://src/persist/profiles.gd").new()
	p2.root_override = root2
	p2.startup()
	check_eq(str(p2.id()), "rookie", "the next usable profile is opened")
	p2.delete_profile("champ")
	check_eq(_text(root2.path_join("champ/profile.json")), champ_before, "a newer profile is not deleted")
	p2.free()


# ---------------------------------------------------------------------------------------------
# H. recovery follows the write order, not the clock

func test_recovery_follows_the_write_order_not_the_clock() -> void:
	var p := dir.path_join("clock.json")
	Saves.clock_override = 2000000000.0      # a clock running ahead...
	Saves.write_json(p, "test", 1, {"gen": 1})
	Saves.clock_override = 1000000000.0      # ...then corrected backwards
	Saves.write_json(p, "test", 1, {"gen": 2})
	var r := Saves.read_json(p, "test", 1)
	check_eq(int(r["data"]["gen"]), 2, "the valid main file wins over an older .bak with a later timestamp")
	check_eq(str(r["recovered_from"]), "", "no recovery needed")
	# an interrupted write (verified .tmp, rotation never happened) is still the newest data
	var q := dir.path_join("clock_tmp.json")
	Saves.clock_override = 2000000000.0
	Saves.write_json(q, "test", 1, {"gen": 1})
	Saves.clock_override = 1000000000.0
	Saves.simulate_crash_after_tmp = true
	Saves.write_json(q, "test", 1, {"gen": 2})
	Saves.simulate_crash_after_tmp = false
	var r2 := Saves.read_json(q, "test", 1)
	check_eq(int(r2["data"]["gen"]), 2, "the later write wins even with an earlier timestamp")
	check_eq(str(r2["recovered_from"]), "tmp")
	# sequence numbers keep counting across writes
	var env = JSON.parse_string(_text(p))
	check_eq(int(env["seq"]), 2, "seq stored in the envelope")
	# a .bak never beats a valid main file, whatever its numbers say
	var b := dir.path_join("bak_seq.json")
	Saves.write_json(b, "test", 1, {"gen": 1})
	Saves.write_json(b, "test", 1, {"gen": 2})
	var bak_env: Dictionary = JSON.parse_string(_text(b + ".bak"))
	bak_env["seq"] = 99
	_store(b + ".bak", JSON.stringify(bak_env, "\t"))
	check_eq(int(Saves.read_json(b, "test", 1)["data"]["gen"]), 2, "main file preferred over a .bak")
