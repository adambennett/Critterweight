extends TestCase
## Recorded dialogue coverage, names, bindings, queue semantics and packaged audio integrity.
var library: SpeechLibrary

func before_each() -> void:
	library = SpeechLibrary.new()
	Audio.stop_announcer()
	Audio.announcer_mode = "full"

func after_each() -> void:
	Audio.stop_announcer()
	Audio.end_match()

func test_every_authored_voice_clip_is_installed_and_decodable() -> void:
	check(library.catalog.get("clips", {}).size() >= 700, "full spoken cast and reusable vocabulary installed")
	check_eq(library.catalog.get("voices", {}).get("coach_buck", ""), "voc_b36c5rxpfuzb", "owner's coach casting")
	var total := 0.0
	for id in library.catalog.get("clips", {}):
		var clip: Dictionary = library.catalog["clips"][id]
		var path := str(clip["path"])
		check(ResourceLoader.exists(path), "imported recording exists: %s" % id)
		var stream := load(path) as AudioStreamWAV
		check(stream != null, "WAV decodes: %s" % id)
		if stream:
			check(stream.get_length() > 0.08 and stream.get_length() < 30.0, "recording duration bounded: %s" % id)
			check(absf(stream.get_length() - float(clip["seconds"])) < 0.02, "subtitle timing matches audio: %s" % id)
			total += stream.get_length()
	check(total > 600.0, "full dialogue coverage, not a few sample clips")

func test_all_announcer_and_hub_templates_resolve_without_babble() -> void:
	var vars := {"p": "Custom Hero", "o": "Custom Rival", "n": 2, "player": "Custom Hero", "boss": "Bilge", "fighter": "Dozer", "act": 2, "kos": 24, "dose": 3, "parts": 2}
	for item in library.catalog.get("lines", []):
		var text := str(item["template"])
		for part in item["parts"]:
			if part.has("token"):
				var token := str(part["token"])
				text = text.replace("{" + token + "}", str(vars.get(token, "sample binding or move")))
		var recording := library.resolve(str(item["id"]), str(item["speaker"]), str(item["template"]), text, vars, {})
		check(not recording.is_empty(), "recording for %s" % item["id"])
		var spoken := library.resolve("say:rendered", str(item["speaker"]), text, text, {}, {})
		check(not spoken.is_empty(), "rendered dialogue lookup for %s" % item["id"])
	for id in Content.ids("announcer"):
		var entry := Content.get_entry("announcer", id)
		check(not library.resolve(id, str(entry["speaker"]), str(entry["text"]), str(entry["text"]), vars, {}).is_empty(), "authored announcer %s covered" % id)

func test_custom_names_use_slot_audio_while_subtitles_keep_the_name() -> void:
	var ctx := {"player_index": 3, "seed": 4, "fighters": [{"index": 3, "creature": "f_dozer", "name": "HaloFan", "team": 0}, {"index": 6, "creature": "f_stoke", "name": "RivalName", "team": 1}]}
	var entry := Audio.line("ann_first_03")
	var plan := library.resolve("ann_first_03", "barnaby", str(entry["text"]), "", {"p": "HaloFan"}, ctx)
	var player_four := str(library.catalog["tokens"]["devon"]["player 4"])
	# v0.9.17: an unrecorded custom name is voiced by its fighter's recorded name when that names
	# nobody else in the match ("Dozer lands first!"), the subtitle keeps the custom name
	check(plan.get("ids", []).has(str(library.catalog["tokens"]["devon"]["dozer"])), "custom player is voiced by its fighter's name")
	var mirror := {"player_index": 3, "seed": 4, "fighters": [{"index": 3, "creature": "f_dozer", "name": "HaloFan", "team": 0},
		{"index": 6, "creature": "f_dozer", "name": "Dozer", "team": 1}]}
	var mirrored := library.resolve("ann_first_03", "barnaby", str(entry["text"]), "", {"p": "HaloFan"}, mirror)
	check(mirrored.get("ids", []).has(player_four), "in a mirror match the custom player keeps the slot name (Player 4)")
	var bot := library.resolve("ann_first_03", "barnaby", str(entry["text"]), "", {"p": "Dredge (bot)"},
		{"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "Rookie"}, {"index": 1, "creature": "f_dredge", "name": "Dredge (bot)"}]})
	check(bot.get("ids", []).has(str(library.catalog["tokens"]["devon"]["dredge"])), "a bot's '(bot)' decoration is not read as Player 2")
	Audio.begin_match(ctx)
	check(Audio.announce("ann_first_03"), "recorded custom-name line starts")
	check(bool(Audio._ann_current.get("recorded", false)), "audio dispatcher selected recording")
	check_eq(Audio._substitute("Winner: {p}", {}), "Winner: HaloFan", "visible name unchanged")
	var punctuated := str(entry["text"]).replace("{p}", "Halo.Fan!")
	check(not library.resolve("say:profile", "barnaby", punctuated, punctuated, {}, {}).is_empty(), "punctuation in profile names still resolves")
	var rookie := library.resolve("ann_first_03", "barnaby", str(entry["text"]), "", {"p": "Rookie"}, ctx)
	check(rookie.get("ids", []).has(library.catalog["tokens"]["devon"]["rookie"]), "default name gets its own recording")

func test_live_control_bindings_share_natural_action_audio() -> void:
	var raw := "Step in and plant your feet. Then tap {light}, let it land, tap again. Three times. Mash it and they trip over each other."
	var keyboard := library.resolve("say:test", "granny", raw, raw.replace("{light}", "[J]"), {}, {})
	var controller := library.resolve("say:test", "granny", raw, raw.replace("{light}", "[X]"), {}, {})
	check(not keyboard.is_empty(), "keyboard tutorial lookup")
	check_eq(keyboard.get("ids", []), controller.get("ids", []), "binding changes do not read obsolete buttons")
	check(keyboard.get("ids", []).has(library.catalog["tokens"]["coach_buck"]["light attack"]), "coach says action name")

func test_dynamic_recaps_and_first_lesson_compositions_resolve() -> void:
	var text := "STOKE walks out for FIGHT CAMP, Amateur difficulty, DOSE 3! 24 KNOCKOUTS on the night! I counted every one! Past Act 1, a boss down, and then Conduit in Act 2! What a night!"
	var plan := library.resolve("say:recap", "barnaby", text, text, {}, {})
	check(not plan.is_empty(), "compound recap has speech for every sentence")
	check(plan.get("ids", []).has(library.catalog["tokens"]["devon"]["twenty"]), "multi-word numeric value spoken")
	check(plan.get("ids", []).has(library.catalog["tokens"]["devon"]["conduit"]), "boss is named")
	var ex := Content.get_entry("tutorial", "tut_footwork")
	text = Tutorial.jab_for("f_stoke") + " " + str(ex["intro"])
	check(not library.resolve("say:intro", "granny", text, text, {}, {}).is_empty(), "first lesson joke and introduction both voiced")

func test_recorded_priority_queue_stop_and_unknown_mod_fallback() -> void:
	check(Audio.announce("ann_low_01"), "recording starts")
	check(Audio.announce("ann_combo_01"), "a play-by-play recording waits behind it")
	check_eq(Audio.announcer_queue().size(), 1, "one recording waits")
	check(Audio.announce("ann_ko_01"), "KO interrupts")
	check_eq(str(Audio._ann_current.get("id", "")), "ann_ko_01", "KO owns current recording")
	check(Audio.announcer_queue().is_empty(), "the KO made the waiting call stale")
	Audio._finish_line()
	check(str(Audio._ann_current.get("id", "")) != "ann_combo_01", "a stale call never follows the KO")
	Audio.stop_announcer()
	check(not Audio.announcer_busy() and Audio._speech_clips.is_empty(), "stop clears playback and queue")
	check(library.resolve("ann_low_01", "barnaby", "A mod replaced this text.", "A mod replaced this text.", {}, {}).is_empty(), "overridden content never plays stale built-in speech")

func test_recorded_player_uses_full_clips_and_completion_signals() -> void:
	var old_enabled: bool = Audio.enabled
	var old_player: AudioStreamPlayer = Audio._speech_player
	var player := AudioStreamPlayer.new()
	player.volume_db = -80.0
	Audio.add_child(player)
	player.finished.connect(Audio._advance_speech)
	Audio._speech_player = player
	Audio.enabled = true
	check(Audio.announce("ann_first_03", {"p": "Rookie"}), "recorded playback starts")
	var count := 0
	while Audio.announcer_busy() and count < 16:
		check(player.stream is AudioStreamWAV, "each phrase uses an imported WAV")
		check_eq(player.pitch_scale, 1.0, "recording has no random pitch variation")
		player.stop()
		player.finished.emit()
		count += 1
	check(count > 1 and count < 16, "name and sentence clips advance to completion")
	check(not Audio.announcer_busy(), "last clip releases the dialogue channel")
	Audio.announce("ann_low_01")
	Audio.stop_announcer()
	check(not player.playing and player.stream == null, "explicit stop silences the player")
	Audio.enabled = old_enabled
	Audio._speech_player = old_player
	player.free()

func test_bubble_pacing_uses_recorded_duration() -> void:
	var text := str(Audio.line("ann_intro_stoke_01").get("text", ""))
	# A fixed introduction has no dynamic substitutions, so world bubbles can use its exact length.
	var plan := library.resolve("", "barnaby", text, text, {}, {})
	check(not plan.is_empty(), "fighter introduction is recorded")
	check(absf(Audio.speech_seconds("barnaby", text) - float(plan.get("seconds", -1.0))) < 0.001, "bubble pacing follows recording")
	check_eq(Audio.speech_seconds("barnaby", "Unrecorded custom mod sentence."), 0.0, "unrecorded dialogue retains fallback timing")

func test_owner_player_names_and_spelling_aliases_use_recordings_in_every_voice() -> void:
	var names := ["The Dragon", "Adam", "Bennett", "Jeremy", "Austin", "Kenny", "Sam", "McKenna", "Kenna", "Princess Jeremy", "Princess Worm", "The Werm", "Jerm the Worm", "Charizard", "Volk", "Blastoise", "Pikachu"]
	var aliases := {"Princess Werm": "Princess Worm", "Jerm the Werm": "Jerm the Worm", "The Worm": "The Werm"}
	for voice in ["devon", "kendall", "coach_buck"]:
		var vocabulary: Dictionary = library.catalog["tokens"][voice]
		for player_name in names:
			check(vocabulary.has(player_name.to_lower()), "%s has %s" % [voice, player_name])
			if not vocabulary.has(player_name.to_lower()):
				continue
			var id := str(vocabulary[player_name.to_lower()])
			check(library.catalog["clips"].has(id), "name has an installed clip")
			check_eq(library._token(voice, "p", "  " + player_name.to_upper() + "  ", {}), [id], "name matches case-insensitively without slot fallback")
		for alias in aliases:
			check_eq(library._token(voice, "p", alias, {}), library._token(voice, "p", aliases[alias], {}), "worm/werm spellings share audio")