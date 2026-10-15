extends TestCase
## NET-02/NET-08: the shipped example server configs (game/server/*.cfg) and the playlist
## template stay valid as content and code evolve (docs/SERVER.md references them).


func test_example_configs_parse_and_resolve_playlists() -> void:
	var d := DirAccess.open("res://server")
	check(d != null, "res://server exists")
	if d == null:
		return
	var n := 0
	for f in d.get_files():
		if not f.ends_with(".cfg"):
			continue
		n += 1
		var res := NetServerConfig.parse_file("res://server/" + f)
		check((res["errors"] as Array).is_empty(), "%s parses: %s" % [f, str(res["errors"])])
		check((res["warnings"] as Array).is_empty(), "%s has no warnings: %s" % [f, str(res["warnings"])])
		var cfg: Dictionary = res["cfg"]
		var pl := NetPlaylist.load_ref(str(cfg["playlist"]))
		pl.validate()
		check(pl.valid_entries().size() >= 2 and pl.errors.is_empty(), "%s playlist '%s' is valid: %s" % [f, cfg["playlist"], str(pl.errors)])
	check(n >= 3, "example configs shipped (%d)" % n)


func test_playlist_template_is_valid() -> void:
	var p := NetPlaylist.load_file("res://server/playlists/custom_rotation.example.json")
	p.validate()
	check(p.errors.is_empty(), "template validates: %s" % str(p.errors))
	check_eq(p.valid_entries().size(), 5, "all template entries valid")
