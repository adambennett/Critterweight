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
		check(n >= 3, "%s has >= 3 variants (got %d)" % [id, n])
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
		# exported builds ship imported samples, not the source .wav files; the stream checks above
		# cover the packaged game
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
	var music: Dictionary = Audio.bank.get("music", {})
	for t in required:
		check(music.has(t), "track %s in bank" % t)
	if not music.has("combat_a"):
		return
	# tempo contract: combat A/B share 128 BPM so they can crossfade on bar lines; boss is 132
	check_eq(int(music["combat_a"]["bpm"]), 128, "combat_a bpm")
	check_eq(int(music["combat_b"]["bpm"]), 128, "combat_b bpm")
	check_eq(int(music["boss"]["bpm"]), 132, "boss bpm")
	for t in music:
		var e: Dictionary = music[t]
		var sections: Array = e.get("sections", [])
		check(not sections.is_empty() and sections[0].has("start_bar") and sections[0].has("bars"), "%s sections carry start_bar/bars for music_jump" % t)
		var s = load(str(e["file"]))
		check(s is AudioStreamWAV, "%s stream loads" % t)
		if not (s is AudioStreamWAV):
			continue
		var w: AudioStreamWAV = s
		var frames := int(round(w.get_length() * float(w.mix_rate)))
		check_near(float(frames) / float(w.mix_rate), float(e["seconds"]), 0.002, "%s length matches the bank" % t)
		var lp = e.get("loop")
		if lp != null:
			var begin := int(lp["begin"])
			var end := int(lp["end"])
			check(begin >= 0 and begin < end and end <= frames, "%s loop %d-%d inside %d frames" % [t, begin, end, frames])
			check_eq(w.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s imported as forward loop" % t)
			check_eq(w.loop_begin, begin, "%s loop_begin" % t)
			check_eq(w.loop_end, end, "%s loop_end" % t)
			# loop points sit exactly on bar lines
			var bs := float(e["bar_seconds"]) * float(e["sr"])
			check_near(float(begin) / bs, round(float(begin) / bs), 0.01, "%s loop begin on a bar" % t)
			check_near(float(end) / bs, round(float(end) / bs), 0.01, "%s loop end on a bar" % t)
		else:
			check(bool(e.get("stinger", false)), "%s has no loop so it must be a stinger" % t)
		for L in e.get("layers", []):
			var ls = load(str(L["file"]))
			check(ls is AudioStreamWAV, "%s layer %s loads" % [t, L["id"]])
			var lb := int(L.get("loop_bars", 0))
			check(lb > 0 and int(e["bars"]) % lb == 0, "%s layer %s (%d bars) divides the track" % [t, L["id"], lb])
	# intensity + variant layers exist where the design asks for them
	var ca_layers := []
	for L2 in music["combat_a"].get("layers", []):
		ca_layers.append(str(L2["id"]))
	check(ca_layers.has("lead") and ca_layers.has("perc2"), "combat_a has lead + percussion variant layers (%s)" % str(ca_layers))
	var boss_layers := []
	for L3 in music["boss"].get("layers", []):
		boss_layers.append(str(L3["id"]))
	for want in ["p2", "bilge", "conduit", "snappington"]:
		check(boss_layers.has(want), "boss has layer %s" % want)


func test_size_budget() -> void:
	var m := _manifest()
	var total := int(m.get("bytes", 0))
	check(total > 0 and total <= 140 * 1048576, "rendered audio %.1f MB stays near the ~120 MB budget" % (total / 1048576.0))
