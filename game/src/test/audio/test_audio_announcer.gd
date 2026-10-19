extends TestCase
## Announcer and coach lines: ids, subtitles, trigger selection, interrupt/queue rules, babble plans.

var _subs: Array = []


func before_each() -> void:
	_subs.clear()
	Audio.stop_announcer()
	Audio.announcer_mode = "full"
	Audio.subtitles_on = true
	Audio.subtitle.connect(_on_sub)


func after_each() -> void:
	Audio.subtitle.disconnect(_on_sub)
	Audio.stop_announcer()
	Audio.end_match()


func _on_sub(speaker: String, text: String, seconds: float) -> void:
	_subs.append({"speaker": speaker, "text": text, "seconds": seconds})


func test_all_lines_have_ids_subtitles_and_triggers() -> void:
	var ids := Audio.line_ids()
	var standard_barnaby := 0
	var expansion_barnaby := 0
	var expansion_kendall := 0
	var granny := 0
	for id in ids:
		var l := Audio.line(id)
		check(str(l.get("text", "")) != "", "%s has text" % id)
		check(str(l.get("trigger", "")) != "", "%s has a trigger" % id)
		check(l.has("priority"), "%s has a priority" % id)
		match str(l.get("speaker", "")):
			"barnaby":
				if str(id).begins_with("ann_exp_"):
					expansion_barnaby += 1
				else:
					standard_barnaby += 1
				check(str(l["text"]).length() <= 90, "%s subtitle <= 90 chars (%d)" % [id, str(l["text"]).length()])
			"kendall":
				expansion_kendall += 1
				check(str(l["text"]).length() <= 90, "%s subtitle <= 90 chars (%d)" % [id, str(l["text"]).length()])
			"granny":
				granny += 1
			_:
				fail("%s has an unknown speaker" % id)
	check_eq(standard_barnaby, 163, "standard Barnaby line count")
	check_eq(expansion_barnaby, 515, "expanded Devon/Barnaby line count")
	check_eq(expansion_kendall, 339, "Kendall line count")
	check(granny >= 36, "Granny tutorial lines present (%d)" % granny)


func test_varga_and_knell_ability_uses_get_specific_announcer_calls() -> void:
	Audio.begin_match({"player_index": 0, "fighters": [
		{"index": 0, "creature": "f_dozer", "name": "DOZER", "team": 0},
		{"index": 1, "creature": "f_varga", "name": "VARGA", "team": 1},
	], "seed": 31})
	var acts := Audio.on_sim_event({"type": "ability", "fighter": 1, "slot": "ability1", "id": "cut_the_angle"})
	var varga_line := ""
	for action in acts:
		if str(action).begins_with("line:ann_exp_"):
			varga_line = str(action).trim_prefix("line:")
	check(not varga_line.is_empty(), "Varga ability callout is selected")
	check(str(Audio.line(varga_line).get("text", "")).contains("Cut the Angle"), "callout names Varga's actual ability")
	Audio.stop_announcer()
	Audio.begin_match({"player_index": 0, "fighters": [
		{"index": 0, "creature": "f_dozer", "name": "DOZER", "team": 0},
		{"index": 1, "creature": "f_knell", "name": "KNELL", "team": 1},
	], "seed": 32})
	acts = Audio.on_sim_event({"type": "ability", "fighter": 1, "slot": "ability1", "id": "ghost_light"})
	var knell_line := ""
	for action in acts:
		if str(action).begins_with("line:ann_exp_"):
			knell_line = str(action).trim_prefix("line:")
	check(not knell_line.is_empty(), "Knell ability callout is selected")
	check(str(Audio.line(knell_line).get("text", "")).contains("Ghost Light"), "callout names Knell's actual ability")
	Audio.stop_announcer()
	Audio.begin_match({"player_index": 0, "fighters": [
		{"index": 0, "creature": "f_dozer", "name": "DOZER", "team": 0},
		{"index": 1, "creature": "f_knell", "name": "KNELL", "team": 1},
	], "seed": 33})
	acts = Audio.on_sim_event({"type": "ability", "fighter": 1, "slot": "ability2", "id": "through_the_veil"})
	var phase_line := ""
	for action in acts:
		if str(action).begins_with("line:ann_exp_"):
			phase_line = str(action).trim_prefix("line:")
	check(not phase_line.is_empty(), "Knell's second ability gets a callout")
	var phase_text := str(Audio.line(phase_line).get("text", ""))
	check(phase_text.contains("Through the Veil") or phase_text.contains("phase step"), "callout describes Knell's phase ability")


func test_color_commentary_paces_and_interrupts_a_rare_conversation() -> void:
	Audio.begin_match({"player_index": 0, "fighters": [
		{"index": 0, "creature": "f_varga", "name": "VARGA", "team": 0},
		{"index": 1, "creature": "f_knell", "name": "KNELL", "team": 1},
		{"index": 2, "creature": "f_dozer", "name": "DOZER", "team": 1},
	], "seed": 44})
	var context := Audio._color_context()
	check(context["element"].has("scrap"), "color context includes Scrap fighters")
	check(context["element"].has("spectral"), "color context includes Spectral fighters")
	check(context["matchup"].has("f_dozer|f_varga"), "color context includes cross-team matchup")
	var matchup_line := Audio.pick_line("matchup_color", context)
	check(not matchup_line.is_empty(), "matchup-specific color lines can be selected")
	check(not Audio.pick_line("element_color", {"element": "scrap"}).is_empty(), "Scrap rules lines are selectable")
	check(not Audio.pick_line("element_color", {"element": "spectral"}).is_empty(), "Spectral rules lines are selectable")
	check(Audio.announce_color_commentary(true).begins_with("ann_exp_"), "rare conversation starts with a recorded line")
	var first: Dictionary = Audio.line(str(Audio._ann_current.get("id", "")))
	var conversation_id := str(first.get("conversation_id", ""))
	check(not conversation_id.is_empty(), "first take identifies its conversation")
	check_eq(Audio._ann_conversation_queue.size(), 9, "nine remaining turns are queued")
	Audio._finish_line()
	await get_tree().create_timer(0.55).timeout
	var second: Dictionary = Audio.line(str(Audio._ann_current.get("id", "")))
	check_eq(str(second.get("conversation_id", "")), conversation_id, "conversation continues in order")
	check_eq(int(second.get("conversation_turn", 0)), 2, "second take is turn two")
	check(Audio.announce("ann_ko_01"), "high-priority event interrupts the conversation")
	check(Audio._ann_conversation_queue.is_empty(), "priority event cancels remaining booth turns")
	check_eq(Audio._ann_active_conversation, "", "interrupted conversation is cleared")


func test_announce_emits_subtitle_and_substitutes_names() -> void:
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "STOKE", "team": 0}, {"index": 1, "creature": "f_gusto", "name": "GUSTO", "team": 1}], "arena": "the_gullet", "seed": 7})
	check(Audio.announce("ann_first_03"), "line accepted")
	check_eq(_subs.size(), 1, "one subtitle emitted")
	if _subs.size() == 1:
		check_eq(str(_subs[0]["speaker"]), "barnaby", "speaker")
		check_eq(str(_subs[0]["text"]), "STOKE lands first! The crowd approves, loudly, with cans!", "{p} substituted")
		check(float(_subs[0]["seconds"]) > 0.5 and float(_subs[0]["seconds"]) <= 5.0, "subtitle duration sane")
	check(not Audio.announce("no_such_line"), "unknown line id is rejected without crashing")


func test_trigger_picks_most_specific_line_and_rotates() -> void:
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_dredge", "name": "DREDGE", "team": 0}, {"index": 1, "creature": "f_stoke", "name": "STOKE", "team": 1}], "seed": 3})
	check_eq(Audio.pick_line("juice", {"creature": "f_dredge"}).begins_with("ann_juice_dredge"), true, "JUICE line is per fighter")
	check_eq(Audio.pick_line("big_hit", {"kind": ["counter"]}), "ann_big_09", "counter big hit")
	check_eq(Audio.pick_line("big_hit", {"kind": ["wall"]}), "ann_big_06", "wall splat big hit")
	var ko := Audio.pick_line("ko", {"kind": ["heavy", "fast"], "target": "opponent"})
	check(ko == "ann_ko_03" or ko == "ann_ko_09", "KO picks among the equally specific heavy/fast lines (got %s)" % ko)
	Audio._ann_rotation.clear()
	check_eq(Audio.pick_line("ko", {"kind": ["heavy", "fast"], "target": "opponent"}), ko, "selection is deterministic for a seed")
	check(Audio.pick_line("ko", {"kind": ["zone"]}) == "ann_ko_06", "zone KO line")
	check_eq(Audio.pick_line("boss_phase2", {"boss": "b_conduit"}), "ann_boss_conduit_p2", "boss phase line")
	check_eq(Audio.pick_line("tutorial", {"exercise": 7, "phase": "success"}), "coach_tut_07_success", "coach line by exercise/phase")
	# generic pool rotates and does not repeat inside a match
	var seen := {}
	for i in 5:
		var id := Audio.pick_line("idle", {})
		check(not seen.has(id), "idle line %s not repeated" % id)
		seen[id] = true
		Audio._ann_used[id] = true
	check_eq(Audio.pick_line("nothing_here", {}), "", "unknown trigger yields no line")


func test_priority_interrupt_and_queue_rules() -> void:
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_jitters", "name": "JITTERS", "team": 0}], "seed": 1})
	check(Audio.announce("ann_low_01"), "low-priority line starts when idle")
	check(not Audio.announce("ann_combo_01"), "combo (40) is dropped while a line plays")
	check(Audio.announce("ann_kd_01"), "knockdown (80) is queued while a line plays")
	check_eq(_subs.size(), 1, "queued line has not spoken yet")
	check(Audio.announce("ann_ko_01"), "KO (100) interrupts")
	check_eq(_subs.size(), 2, "KO spoke immediately")
	check_eq(str(_subs[1]["text"]), "IT'S OVER! Goodnight, good luck, and good grief!", "KO text")
	Audio.announcer_mode = "reduced"
	check(not Audio.announce("ann_parry_01"), "reduced mode keeps only KO/round/JUICE-class triggers")
	Audio.announcer_mode = "off"
	check(not Audio.announce("ann_ko_02"), "off mode speaks nothing")
	Audio.announcer_mode = "full"


func test_sim_event_mapping() -> void:
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "STOKE", "team": 0}, {"index": 1, "creature": "f_dredge", "name": "DREDGE", "team": 1}], "arena": "the_gullet", "seed": 11})
	var p := Vector3(0, 1, 0)
	var acts := Audio.on_sim_event({"type": "hit", "fighter": 0, "target": 1, "damage": 6.0, "point": p, "normal": Vector3.UP, "blocked": false, "parried": false, "counter": false, "part": "head", "element": "scorch", "quality": 0.7, "move": "l1", "slot": "l1", "knockdown": false, "otg": false})
	check(acts.has("hit_light"), "light hit plays hit_light (%s)" % str(acts))
	check(acts.has("hit_layer_chitin"), "Dredge takes the chitin layer")
	check(acts.has("el_hit_scorch"), "Scorch hit layer")
	var first := false
	for a in acts:
		if str(a).begins_with("line:ann_first_"):
			first = true
	check(first, "first hit announces first blood (%s)" % str(acts))
	acts = Audio.on_sim_event({"type": "hit", "fighter": 1, "target": 0, "damage": 16.0, "point": p, "normal": Vector3.UP, "blocked": false, "parried": false, "counter": true, "part": "core", "element": "", "quality": 1.0, "move": "heavy", "slot": "heavy", "knockdown": false, "otg": false})
	check(acts.has("hit_heavy") and acts.has("counter"), "heavy counter hit (%s)" % str(acts))
	acts = Audio.on_sim_event({"type": "hit", "fighter": 1, "target": 0, "damage": 2.0, "point": p, "normal": Vector3.UP, "blocked": true, "parried": false, "counter": false, "part": "arm", "element": "", "quality": 0.5, "move": "l1", "slot": "l1", "knockdown": false, "otg": false})
	check(acts.has("hit_guard") and not acts.has("hit_light"), "blocked hit is a guard thup")
	acts = Audio.on_sim_event({"type": "parry", "fighter": 0, "attacker": 1, "pos": p})
	check(acts.has("parry"), "parry sound")
	acts = Audio.on_sim_event({"type": "knockdown", "fighter": 1, "reason": "poise"})
	check(acts.has("knockdown") and (acts.has("line:ann_kd_03") or acts.has("line:ann_kd_04")), "poise knockdown by the player + a matching line (%s)" % str(acts))
	acts = Audio.on_sim_event({"type": "juice", "fighter": 0, "id": "meltdown"})
	check(acts.has("juice_pulse") and acts.has("juice_stoke"), "JUICE signature per fighter (%s)" % str(acts))
	acts = Audio.on_sim_event({"type": "reaction", "fighter": 1, "reaction": "short_out", "name": "Short-Out", "a": "static", "b": "brine", "pos": p})
	check(acts.has("react_short_out"), "reaction sound")
	acts = Audio.on_sim_event({"type": "ability", "fighter": 0, "slot": "ability1", "id": "steam_vent"})
	check(acts.has("ab_steam_vent"), "ability signature by move id")
	acts = Audio.on_sim_event({"type": "ability", "fighter": 0, "slot": "ability2", "id": "unknown_move_xyz"})
	check(acts.has("ab_generic"), "unknown ability falls back to the generic sound")
	acts = Audio.on_sim_event({"type": "effect", "fighter": 0, "effect": "projectile", "pos": p, "element": "brine", "vfx": "orb"})
	check(acts.has("proj_launch_brine"), "projectile launch by element")
	acts = Audio.on_sim_event({"type": "ko", "fighter": 1})
	check(acts.has("ko"), "KO sound")
	var ko_line := false
	for a2 in acts:
		if str(a2).begins_with("line:ann_ko_"):
			ko_line = true
	check(ko_line, "KO line (%s)" % str(acts))
	acts = Audio.on_sim_event({"type": "unknown_event_type", "fighter": 0})
	check(acts.is_empty(), "unknown events are ignored safely")
	check_eq(Audio.sfx("hit_light", p), -1, "headless: sfx() is a no-op returning -1")
	check_eq(Audio.sfx("definitely_missing_id"), -1, "missing id never crashes")


func test_babble_plan() -> void:
	var voice: Dictionary = Audio.bank.get("voices", {}).get("barnaby", {})
	check(not voice.is_empty(), "barnaby voice bank in bank.json")
	var p := Babble.plan("Eighty-five kilos of newt and a furnace where his conscience should be: STOKE!", voice, 1, false, ["STOKE"])
	check(float(p["duration"]) > 1.5 and float(p["duration"]) <= 4.0, "plan duration %.2f within the 4 s cap" % float(p["duration"]))
	var grains: Array = p["grains"]
	check(grains.size() >= 20, "plan has grains (%d)" % grains.size())
	var fanfare := false
	for g in grains:
		if str(g["id"]) == "fanfare":
			fanfare = true
		check(voice["grains"].has(str(g["id"])), "grain %s exists in the bank" % g["id"])
	check(fanfare, "fighter name gets the fanfare grain")
	var long_text := "Guard. Hold it. He's gonna throw three. You'll take a little, not a lot. Guard costs stamina, so don't live there."
	var gv: Dictionary = Audio.bank["voices"].get("granny", {})
	var p2 := Babble.plan(long_text, gv, 2, false, [], "pleased")
	check(float(p2["duration"]) <= 4.0, "long coach line capped at 4 s (%.2f)" % float(p2["duration"]))
	var p3 := Babble.plan("Round {n}! Somebody's cornerman is lying.", voice, 5, true, [])
	check(float(p3["duration"]) < float(Babble.plan("Round {n}! Somebody's cornerman is lying.", voice, 5, false, [])["duration"]), "reduced mode halves the babble")
	check_eq(Babble.syllabify("Eighty-five").size(), 3, "syllable count")
	check_eq(Babble.letter_class("s"), "sibilant", "letter class")
