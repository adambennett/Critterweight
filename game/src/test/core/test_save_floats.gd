extends TestCase
## SAV-02 regression: random doubles survive the save -> verify -> load round trip (Godot's JSON
## reader can return a 17-digit double one ULP off, which must not read as a damaged file).


func test_random_doubles_round_trip_through_saves() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var dir := temp_dir("save_floats_%d" % Time.get_ticks_usec())
	var bad := 0
	for k in 300:
		var data := {"a": rng.randf() * 1000.0, "b": [rng.randf_range(-1e6, 1e6), rng.randf() * 1e-6, rng.randfn(0.0, 1e9)],
			"c": {"t": Time.get_unix_time_from_system() + rng.randf()}}
		var p := dir.path_join("f%d.json" % k)
		if Saves.write_json(p, "floats", 1, data) != OK:
			bad += 1
			continue
		var r := Saves.read_json(p, "floats", 1)
		if not r["ok"] or str(r["recovered_from"]) != "":
			bad += 1
	check_eq(bad, 0, "every save verified and loaded from the main file")
