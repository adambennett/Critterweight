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
		skip("scans GDScript source; exported builds ship compiled scripts (runs in the source suite)")
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


## UI-04: window settings apply tentatively, then Keep confirms them and Revert rolls them back.
## The settings screen's 15 s countdown dialog times out to Revert (settings_screen.gd).
func test_display_changes_confirm_or_roll_back() -> void:
	var before := str(Settings.get_value("display.window_mode"))
	var other := "windowed" if before != "windowed" else "borderless"
	var prev := Settings.apply_display_tentative({"display.window_mode": other})
	check_eq(str(Settings.get_value("display.window_mode")), other, "the change applies at once")
	Settings.revert_display(prev)
	check_eq(str(Settings.get_value("display.window_mode")), before, "Revert (the countdown's default) restores the old mode")
	prev = Settings.apply_display_tentative({"display.window_mode": other})
	var seen := []
	var on_changed := func(k: String, _v) -> void:
		seen.append(k)
	Settings.changed.connect(on_changed)
	Settings.confirm_display()
	Settings.changed.disconnect(on_changed)
	check_eq(str(Settings.get_value("display.window_mode")), other, "Keep confirms the new mode")
	check(seen.has("display.window_mode"), "and announces it to the game")
	Settings.revert_display(prev)
	Settings.confirm_display()
	check_eq(str(Settings.get_value("display.window_mode")), before, "the test leaves the window mode as it found it")
