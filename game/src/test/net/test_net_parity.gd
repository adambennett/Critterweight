extends TestCase
## Presentation parity (NET-05): every simulation event the local MatchScene reacts to must also be
## handled by NetMatchScene, so online play shows the same sparks, flashes, callouts and gags.
## This test fails when someone adds feedback for a new event to MatchScene but not to the
## networked scene. It also reports event types the compact codec does not have a 1-byte id for
## (they still replicate, as strings).


static func handled_events(path: String) -> Array:
	var src := FileAccess.get_file_as_string(path)
	var start := src.find("func _on_event(")
	if start < 0:
		return []
	var end := src.find("\nfunc ", start + 10)
	var body := src.substr(start, end - start) if end > 0 else src.substr(start)
	var re := RegEx.new()
	re.compile("\"([a-z0-9_]+)\"")
	var out: Array = []
	for line in body.split("\n"):
		if line.begins_with("\t\t\"") and line.strip_edges().ends_with(":"):
			for m in re.search_all(line):
				var n := m.get_string(1)
				if not out.has(n):
					out.append(n)
	return out


func test_net_scene_handles_every_local_event() -> void:
	var local := handled_events("res://src/app/match_scene.gd")
	var net := handled_events("res://src/net/net_match_scene.gd")
	check(local.size() >= 10, "parsed MatchScene event handlers (%d)" % local.size())
	var missing: Array = []
	for e in local:
		if not net.has(e):
			missing.append(e)
	check(missing.is_empty(), "NetMatchScene lacks feedback for: %s" % str(missing))


func test_codec_knows_emitted_event_types() -> void:
	var re := RegEx.new()
	re.compile("\"type\":\\s*\"([a-z0-9_]+)\"")
	var found: Array = []
	for f in _scripts("res://src/sim"):
		for m in re.search_all(FileAccess.get_file_as_string(f)):
			var n := m.get_string(1)
			if not found.has(n):
				found.append(n)
	var unknown: Array = []
	for n in found:
		if not NetEventCodec.TYPES.has(n):
			unknown.append(n)
	if not unknown.is_empty():
		print("    note: event types without a 1-byte codec id (sent as strings): %s" % str(unknown))
	check(found.size() >= 20, "found the simulation's event types (%d)" % found.size())


func _scripts(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	return out
