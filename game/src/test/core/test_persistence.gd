extends TestCase
## SAV-02: versioned, checksummed, atomic saves with recovery (REQUIREMENTS.md).

var dir := ""


func before_each() -> void:
	dir = temp_dir("persist_%d" % Time.get_ticks_usec())


func test_round_trip_preserves_data() -> void:
	var p := dir.path_join("rt.json")
	var data := {"a": 1, "b": [1.5, 2, "x"], "nested": {"k": true, "ü": "unicode ✓"}}
	check_eq(Saves.write_json(p, "test", 3, data), OK, "write")
	var r := Saves.read_json(p, "test", 3)
	check(r["ok"], "read ok: %s" % r["error"])
	check_eq(int(r["data"]["a"]), 1)
	check_eq(str(r["data"]["nested"]["ü"]), "unicode ✓")
	check_eq(str(r["recovered_from"]), "")


func test_interrupted_write_recovers_newest_valid_copy() -> void:
	var p := dir.path_join("crash.json")
	Saves.write_json(p, "test", 1, {"gen": 1})
	Saves.simulate_crash_after_tmp = true
	Saves.write_json(p, "test", 1, {"gen": 2})
	Saves.simulate_crash_after_tmp = false
	var r := Saves.read_json(p, "test", 1)
	check(r["ok"], "recovered")
	check_eq(int(r["data"]["gen"]), 2, "newest verified temp copy wins")
	check_eq(str(r["recovered_from"]), "tmp")


func test_damaged_main_falls_back_to_backup() -> void:
	var p := dir.path_join("dmg.json")
	Saves.write_json(p, "test", 1, {"gen": 1})
	Saves.write_json(p, "test", 1, {"gen": 2})
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var r := Saves.read_json(p, "test", 1)
	check(r["ok"], "backup used")
	check_eq(int(r["data"]["gen"]), 1)
	check_eq(str(r["recovered_from"]), "bak")
	check(FileAccess.file_exists(p), "damaged file was not deleted")


func test_tampered_checksum_is_detected() -> void:
	var p := dir.path_join("tamper.json")
	Saves.write_json(p, "test", 1, {"clout": 10})
	var txt := FileAccess.get_file_as_string(p).replace("\"clout\": 10", "\"clout\": 99999")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	DirAccess.remove_absolute(p + ".bak")
	var r := Saves.read_json(p, "test", 1)
	check(not r["ok"], "edited file rejected")
	check(str(r["error"]).contains("checksum"), "error explains checksum: %s" % r["error"])


func test_newer_version_is_left_untouched() -> void:
	var p := dir.path_join("newer.json")
	Saves.write_json(p, "test", 9, {"x": 1})
	var before := FileAccess.get_file_as_string(p)
	var r := Saves.read_json(p, "test", 2)
	check(not r["ok"] and r["newer"], "refuses newer format")
	check_eq(FileAccess.get_file_as_string(p), before, "file unchanged")


func test_migration_runs_for_older_versions() -> void:
	var p := dir.path_join("old.json")
	Saves.write_json(p, "test", 1, {"hp": 5})
	var r := Saves.read_json(p, "test", 2, func(d, v): return {"hp": int(d["hp"]) * 2, "migrated_from": v})
	check(r["ok"] and r["migrated"], "migrated")
	check_eq(int(r["data"]["hp"]), 10)


func test_unicode_and_space_paths() -> void:
	var p := dir.path_join("Dossier Ünïcödé ✓").path_join("profile file.json")
	check_eq(Saves.write_json(p, "test", 1, {"ok": true}), OK, "write into non-ASCII path with spaces")
	check(Saves.read_json(p, "test", 1)["ok"], "read back")


func test_settings_coercion_and_presets() -> void:
	var v = Settings.set_value("audio.music", 250, false, false)
	check_eq(int(v), 100, "clamped to max")
	var w = Settings.set_value("display.window_mode", "nonsense", false, false)
	check(str(w) in ["windowed", "borderless", "fullscreen"], "invalid enum coerced")
	Settings.set_value("graphics.preset", "low", false, false)
	check_eq(int(Settings.get_value("graphics.ao")), 0, "preset applied")
	Settings.set_value("graphics.ao", 2, false, false)
	check_eq(str(Settings.get_value("graphics.preset")), "custom", "manual change marks preset custom")
	Settings.set_value("graphics.preset", "high", false, false)
