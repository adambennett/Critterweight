extends TestCase
## AUD-01/AUD-02: the sound bank is complete and imported, nothing clips, loops are valid.
## Reads assets/audio/bank.json + manifest.json (written by `node tools/audio/build.js`).

const MANIFEST := "res://assets/audio/manifest.json"
const FREQUENT := ["hit_light", "hit_heavy", "hit_guard", "parry", "whoosh_light", "whoosh_heavy", "knockdown", "ko", "grab", "dodge", "ui_move", "crowd_ooh", "crowd_cheer"]


func _manifest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func test_bank_loads_and_every_id_resolves() -> void:
	check(Audio.bank_loaded, "bank.json loaded")
	check(Audio.sfx_ids().size() >= 250, "bank has at least 250 sfx ids (got %d)" % Audio.sfx_ids().size())
	var problems := Audio.validate()
	for p in problems:
		fail(str(p))
	check(problems.is_empty(), "validate() found %d problems" % problems.size())


func test_frequent_sounds_have_variations() -> void:
	for id in FREQUENT:
		var e: Dictionary = Audio._sfx_entries.get(id, {})
		check(not e.is_empty(), "%s exists" % id)
		var n: int = e.get("files", []).size()
		var min_variants := 1 if id in ["crowd_cheer", "ui_move"] else 3
		check(n >= min_variants, "%s has >= %d variants (got %d)" % [id, min_variants, n])
		var pr: Array = e.get("pitch", [1, 1])
		check(float(pr[0]) < float(pr[1]) or id.begins_with("ui_"), "%s has a random pitch range" % id)


func test_required_ids_present() -> void:
	var required := ["hit_light", "hit_heavy", "hit_layer_chitin", "hit_layer_jelly", "hit_guard", "parry", "wall_splat_fence", "wall_splat_concrete",
		"wall_splat_steel", "wall_splat_railing", "knockdown", "ko", "ko_piece", "whoosh_light", "whoosh_heavy", "whoosh_spin", "charge_loop", "leap",
		"hover_loop", "dodge", "blink_down", "blink_up", "grab", "throw_release",
		"ui_move", "ui_accept", "ui_back", "ui_error", "ui_toggle", "ui_slider", "ui_tab", "ui_stamp", "ui_scrip", "ui_supplement", "ui_banned", "ui_hype_full", "ui_cooldown_ready", "ui_round_card", "ui_fight",
		"crowd_murmur", "crowd_excited", "crowd_roar", "crowd_ooh", "crowd_aww", "crowd_boo", "crowd_gasp", "crowd_laugh", "crowd_chant", "crowd_can_shower",
		"amb_gullet", "amb_drydock", "amb_crusher", "amb_rooftop", "amb_hub_main", "amb_hub_juice_bar", "amb_hub_dock", "amb_menu",
		"ann_bell", "ann_sting", "juice_stoke", "juice_dredge", "juice_gusto", "juice_dozer", "juice_slurry", "juice_jitters", "juice_generic"]
	for el in ["scorch", "brine", "static", "sludge", "grit", "gale"]:
		required.append_array(["el_hit_" + el, "zone_" + el, "proj_launch_" + el, "proj_loop_" + el, "proj_hit_" + el])
	for stt in ["sizzle", "soaked", "jolted", "gunked", "caked", "winded"]:
		required.append("status_" + stt)
	for r in ["steam_burst", "flare_up", "backdraft", "short_out", "mudbound", "dilute", "catalyze", "stormfront_mark", "stormfront_strike", "crust", "spray", "sandblast"]:
		required.append("react_" + r)
	for plan in ["biped", "crab", "avian", "quadruped"]:
		for s in ["canvas", "concrete", "steel", "plank", "gravel"]:
			required.append("step_%s_%s" % [plan, s])
	for s2 in ["canvas", "concrete", "steel", "plank", "gravel"]:
		required.append_array(["drag_serpent_" + s2, "hop_land_" + s2])
	for fighter in ["stoke", "dredge", "gusto", "dozer", "slurry", "jitters", "scrapling", "blister", "bilge", "conduit", "snappington", "lamprey"]:
		for type in ["grunt", "hurt", "ko", "taunt", "juice", "idle"]:
			required.append("voice_%s_%s" % [fighter, type])
	var missing := []
	for id in required:
		if not Audio.has_sfx(id):
			missing.append(id)
	check(missing.is_empty(), "missing ids: %s" % ", ".join(missing))


func test_no_file_peaks_above_minus_one_dbfs() -> void:
	var m := _manifest()
	check(not m.is_empty(), "manifest.json readable")
	var files: Dictionary = m.get("files", {})
	check(files.size() >= 500, "manifest lists every rendered file (%d)" % files.size())
	var worst := -200.0
	var worst_file := ""
	for rel in files:
		var pk := float(files[rel]["peak_db"])
		if pk > worst:
			worst = pk
			worst_file = str(rel)
	check(worst <= -0.99, "loudest sample peak %.2f dBFS in %s must be <= -1 dBFS" % [worst, worst_file])


func test_manifest_matches_files_on_disk() -> void:
	# the report's measurements only mean something if they describe the committed files
	if OS.has_feature("template"):
		# the stream checks above cover the packaged game
		skip("exported builds ship imported samples, not the source .wav files")
		return
	var m := _manifest()
	var files: Dictionary = m.get("files", {})
	var checked := 0
	var bad := []
	for rel in files:
		var path := "res://assets/audio/" + str(rel)
		if not FileAccess.file_exists(path):
			bad.append(str(rel) + " (missing)")
			continue
		var h := FileAccess.get_sha256(path)
		if h != str(files[rel]["sha256"]):
			bad.append(str(rel))
		checked += 1
	check(bad.is_empty(), "%d files differ from the manifest: %s" % [bad.size(), ", ".join(bad.slice(0, 10))])
	check(checked >= 500, "hashed %d files" % checked)


func test_music_tracks_loops_and_layers() -> void:
	var required := ["fight_night_poster", "cannery_radio", "combat_a", "combat_b", "boss", "victory", "defeat", "title_night"]
	var community := [
		"menu_mintodog_scifi_stage_select", "combat_mintodog_jazzy_battle", "combat_mintodog_fairy_battles",
		"combat_mintodog_hard_battle_1", "combat_mintodog_hard_battle_2", "boss_mintodog_trance_boss_battle",
		"boss_mintodog_hard_boss_battle_1", "boss_mintodog_hard_boss_battle_2"]
	required.append_array(community)
	var music: Dictionary = Audio.bank.get("music", {})
	for t in required:
		check(music.has(t), "track %s in bank" % t)
	if not music.has("combat_a"): return
	check_eq(int(music["combat_a"]["bpm"]), 160, "replacement combat_a bpm")
	check_eq(int(music["combat_b"]["bpm"]), 160, "replacement combat_b bpm")
	check_eq(int(music["boss"]["bpm"]), 155, "replacement boss bpm")
	for t in music:
		var e: Dictionary = music[t]
		var sections: Array = e.get("sections", [])
		check(not sections.is_empty() and sections[0].has("start_bar") and sections[0].has("bars"), "%s sections carry start_bar/bars for music_jump" % t)
		var stream := Audio._stream(str(e["file"]))
		check(stream is AudioStreamWAV or stream is AudioStreamMP3 or stream is AudioStreamOggVorbis, "%s stream loads in a supported format" % t)
		if stream == null: continue
		check(stream.get_length() > 0.0, "%s has a positive duration" % t)
		if bool(e.get("replacement", false)):
			check((e.get("layers", []) as Array).is_empty(), "%s replacement has no mismatched generated stems" % t)
			if e.get("loop") != null:
				if stream is AudioStreamMP3: check((stream as AudioStreamMP3).loop, "%s MP3 loops" % t)
				elif stream is AudioStreamOggVorbis: check((stream as AudioStreamOggVorbis).loop, "%s Ogg loops" % t)
				elif stream is AudioStreamWAV: check((stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s WAV loops" % t)
			else:
				check(bool(e.get("stinger", false)), "%s is a stinger when it does not loop" % t)
			continue
		if not (stream is AudioStreamWAV): continue
		var w: AudioStreamWAV = stream
		var frames := int(round(w.get_length() * float(w.mix_rate)))
		check_near(float(frames) / float(w.mix_rate), float(e["seconds"]), 0.002, "%s generated length matches bank" % t)
		var lp = e.get("loop")
		if lp is Dictionary:
			var begin := int(lp["begin"])
			var end_frame := int(lp["end"])
			check(begin >= 0 and begin < end_frame and end_frame <= frames, "%s loop %d-%d inside %d frames" % [t, begin, end_frame, frames])
			check_eq(w.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s imported as forward loop" % t)
			check_eq(w.loop_begin, begin, "%s loop_begin" % t)
			check_eq(w.loop_end, end_frame, "%s loop_end" % t)
			var bs := float(e["bar_seconds"]) * float(e["sr"])
			check_near(float(begin) / bs, round(float(begin) / bs), 0.01, "%s loop begin on a bar" % t)
			check_near(float(end_frame) / bs, round(float(end_frame) / bs), 0.01, "%s loop end on a bar" % t)
		else:
			check(bool(e.get("stinger", false)), "%s has no loop so it must be a stinger" % t)
		for L in e.get("layers", []):
			var ls = load(str(L["file"]))
			check(ls is AudioStreamWAV, "%s layer %s loads" % [t, L["id"]])
			var lb := int(L.get("loop_bars", 0))
			check(lb > 0 and int(e["bars"]) % lb == 0, "%s layer %s (%d bars) divides the track" % [t, L["id"], lb])

func test_replacement_assets_are_present_and_hashed() -> void:
	const REPLACEMENTS := "res://assets/audio/replacements/replacement-audio-inventory.json"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(REPLACEMENTS))
	check(typeof(parsed) == TYPE_DICTIONARY, "replacement inventory is readable")
	if typeof(parsed) != TYPE_DICTIONARY: return
	var files: Array = parsed.get("files", [])
	check(files.size() >= 100, "replacement inventory includes selected clips (%d)" % files.size())
	var missing := []
	var bad_hash := []
	for entry in files:
		var rel := str(entry.get("file", ""))
		var path := "res://" + rel
		var stream = ResourceLoader.load(path)
		if not (stream is AudioStream):
			missing.append(rel)
		elif FileAccess.file_exists(path) and FileAccess.get_sha256(path) != str(entry.get("sha256", "")):
			# Source builds can hash the downloaded file directly. Exported builds keep the
			# imported stream in the PCK, so there is no loose source file to hash there.
			bad_hash.append(rel)
	check(missing.is_empty(), "replacement audio missing or unloadable: %s" % ", ".join(missing.slice(0, 10)))
	check(bad_hash.is_empty(), "replacement audio hashes changed: %s" % ", ".join(bad_hash.slice(0, 10)))
	var used := []
	for value in Audio.bank:
		_collect_replacement_paths(Audio.bank[value], used)
	var used_unique := {}
	for rel in used: used_unique[str(rel)] = true
	check(used_unique.size() >= 50, "replacement files are wired into the bank (%d unique paths)" % used_unique.size())
	for rel in used_unique:
		check(parsed.get("paths", {}).has(str(rel)), "replacement bank path has provenance: %s" % rel)


func _collect_replacement_paths(value, out: Array) -> void:
	if value is String and value.begins_with("res://assets/audio/replacements/"):
		out.append(value.trim_prefix("res://"))
	elif value is Array:
		for item in value: _collect_replacement_paths(item, out)
	elif value is Dictionary:
		for item in value.values(): _collect_replacement_paths(item, out)

func test_size_budget() -> void:
	var m := _manifest()
	var total := int(m.get("bytes", 0))
	check(total > 0 and total <= 140 * 1048576, "rendered audio %.1f MB stays near the ~120 MB budget" % (total / 1048576.0))


## Every sound or track the code asks for by a literal id exists (a missing id is silent at
## runtime: the menu once asked for a "menu_theme" track that was never in the bank).
func test_literal_ids_in_code_exist() -> void:
	if OS.has_feature("template"):
		skip("scans GDScript source; exported builds ship compiled scripts (runs in the source suite)")
		return
	var re := RegEx.create_from_string('Audio\\.(music|sfx|ui|ambience)\\("([^"]+)"')
	var missing := []
	var seen := 0
	var dirs := ["res://src"]
	while not dirs.is_empty():
		var dir: String = dirs.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for sub in d.get_directories():
			if sub != "test":
				dirs.append(dir.path_join(sub))
		for f in d.get_files():
			if not f.ends_with(".gd"):
				continue
			for m in re.search_all(FileAccess.get_file_as_string(dir.path_join(f))):
				seen += 1
				var kind := m.get_string(1)
				var id := m.get_string(2)
				var ok := (Audio.bank.get("music", {}) as Dictionary).has(id) if kind == "music" else Audio.has_sfx(id)
				if not ok:
					missing.append("%s(\"%s\") in %s" % [kind, id, f])
	check(seen > 20, "scanned %d literal audio ids" % seen)
	check(missing.is_empty(), "ids not in the bank: %s" % [missing])


## Every fighter, minion and boss speaks with its own voice set from the bank (minions and bosses
## used to fall back to Stoke's voice because only the roster table was read).
func test_every_creature_has_a_voice_in_the_bank() -> void:
	var missing := []
	for kind in Content.CREATURE_KINDS:
		for id in Content.ids(kind):
			if Content.origin_of(kind, str(id)) != "core":
				continue
			var voice := str(Audio.creature_audio(str(id)).get("voice", ""))
			for t in ["hurt", "ko"]:
				if not Audio.has_sfx("voice_%s_%s" % [voice, t]):
					missing.append("%s -> voice_%s_%s" % [id, voice, t])
	check(missing.is_empty(), "creature voices missing from the bank: %s" % [missing])

func test_menu_focus_uses_soft_interface_ticks() -> void:
	var entry: Dictionary = Audio._sfx_entries.get("ui_move", {})
	var expected := [
		"res://assets/audio/replacements/interface/tick_001.ogg",
	]
	var files: Array = entry.get("files", [])
	check(files == expected and files.size() == 1, "menu focus uses one consistent brief interface tick")
	check(float(entry.get("gain", 0.0)) <= -14.0, "menu focus cue is mixed quietly")
	var pitch: Array = entry.get("pitch", [])
	check(pitch.size() == 2, "menu focus pitch range is present")
	if pitch.size() == 2:
		check_near(float(pitch[0]), 1.0, 0.001, "menu focus pitch stays fixed")
		check_near(float(pitch[1]), 1.0, 0.001, "menu focus pitch stays fixed")
	for path in files:
		var stream := Audio._stream(str(path))
		check(stream != null, "menu focus cue loads: %s" % path)
		if stream != null:
			check(stream.get_length() <= 0.12, "menu focus cue stays brief: %s" % path)
