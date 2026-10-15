extends TestCase
## UI-01 / UI-07 / UI-08: every option the Settings screen shows is read by the game. A visible key
## counts as wired when settings.gd itself acts on it (outside the SCHEMA table) or another script
## reads it by name.
## Source scan: skipped inside an exported build (scripts there are compiled tokens).


func _scripts(dir: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out[dir.path_join(f)] = FileAccess.get_file_as_string(dir.path_join(f))
	for sub in d.get_directories():
		if sub != "test":
			_scripts(dir.path_join(sub), out)


func test_every_visible_setting_is_read_somewhere() -> void:
	if OS.has_feature("template"):
		check(true, "source scan skipped in an exported build")
		return
	var sources := {}
	_scripts("res://src", sources)
	check(sources.size() > 100, "scanned the game scripts (%d)" % sources.size())
	var settings_src := str(sources.get("res://src/persist/settings.gd", ""))
	# everything after the SCHEMA table (set_value, presets, apply) counts as a reader
	var apply_part := settings_src.substr(settings_src.find("\n]\n"))
	var unwired := []
	for s: Dictionary in Settings.SCHEMA:
		if bool(s.get("hidden", false)):
			continue
		var key := str(s["key"])
		var quoted := "\"%s\"" % key
		var used := apply_part.contains(quoted) or (key.begins_with("graphics.") and apply_part.contains("\"graphics.\""))
		if not used:
			for path in sources:
				if path != "res://src/persist/settings.gd" and str(sources[path]).contains(quoted):
					used = true
					break
		if not used:
			unwired.append(key)
	check(unwired.is_empty(), "settings nobody reads: %s" % [unwired])
