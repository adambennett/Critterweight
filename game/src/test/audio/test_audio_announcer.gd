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
		check(not l.has("retired"), "%s: retired lines are never loaded" % id)
		match str(l.get("speaker", "")):
			"barnaby":
				if str(id).begins_with("ann_exp_"):
					expansion_barnaby += 1
				elif str(id).begins_with("ann_"):
					standard_barnaby += 1
				check(str(l["text"]).length() <= 90, "%s subtitle <= 90 chars (%d)" % [id, str(l["text"]).length()])
			"kendall":
				if str(id).begins_with("ann_exp_"):
					expansion_kendall += 1
				check(str(l["text"]).length() <= 90, "%s subtitle <= 90 chars (%d)" % [id, str(l["text"]).length()])
			"granny":
				granny += 1
			_:
				fail("%s has an unknown speaker" % id)
	# v0.9.17 (docs/audio/COMMENTARY.md §5): 59 lines that assert something the game does not have
	# (feints, ropes, a corner crew, 'Devon' on air) or get a fact wrong are retired
	check_eq(standard_barnaby, 162, "standard Barnaby line count (ann_round_03 retired)")
	check_eq(expansion_barnaby, 480, "expanded Devon/Barnaby line count after retirements")
	check_eq(expansion_kendall, 318, "Kendall line count after retirements")
	check(granny >= 36, "Granny tutorial lines present (%d)" % granny)
	# the colour bug: situational lines are no longer lull chatter
	for id in Audio.trigger_line_ids("color"):
		var l2 := Audio.line(id)
		check(str(l2.get("situation", "generic")) == "generic" or not (l2.get("when", {}) as Dictionary).is_empty(),
			"%s in the lull pool is generic or gated to its situation (%s)" % [id, l2.get("situation", "")])


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


func test_trigger_picks_specific_fresh_lines_deterministically() -> void:
	Audio.use_memory_history()
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_dredge", "name": "DREDGE", "team": 0}, {"index": 1, "creature": "f_stoke", "name": "STOKE", "team": 1}], "seed": 3})
	var juice := Audio.pick_line("juice", {"creature": "f_dredge"})
	check_eq(str(Audio.line(juice).get("when", {}).get("creature", "")), "f_dredge", "JUICE line is per fighter (%s)" % juice)
	var counter := Audio.pick_line("big_hit", {"kind": ["counter"]})
	check_eq(str(Audio.line(counter).get("when", {}).get("kind", "")), "counter", "counter big hit (%s)" % counter)
	var wall := Audio.pick_line("big_hit", {"kind": ["wall"]})
	check_eq(str(Audio.line(wall).get("when", {}).get("kind", "")), "wall", "wall splat big hit (%s)" % wall)
	var ko := Audio.pick_line("ko", {"kind": ["heavy", "fast"], "target": "opponent", "ends": "fight"})
	check(str(Audio.line(ko).get("when", {}).get("kind", "")) in ["heavy", "fast"], "KO picks a heavy/fast line (got %s)" % ko)
	Audio.use_memory_history()
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_dredge", "name": "DREDGE", "team": 0}, {"index": 1, "creature": "f_stoke", "name": "STOKE", "team": 1}], "seed": 3})
	var juice2 := Audio.pick_line("juice", {"creature": "f_dredge"})
	check_eq(juice2, juice, "selection is deterministic for a seed and history")
	check(Audio.pick_line("ko", {"kind": ["zone"]}) == "ann_ko_06", "zone KO line")
	check_eq(Audio.pick_line("boss_phase2", {"boss": "b_conduit"}), "ann_boss_conduit_p2", "boss phase line")
	check_eq(Audio.pick_line("tutorial", {"exercise": 7, "phase": "success"}), "coach_tut_07_success", "coach line by exercise/phase")
	# a pool never repeats inside a match while fresh lines remain
	var seen := {}
	for i in 5:
		var id := Audio.pick_line("idle", {})
		check(not seen.has(id), "idle line %s not repeated" % id)
		seen[id] = true
		Audio.commentary_history().note_play(id, Audio.line(id).get("families", []))
	check_eq(Audio.pick_line("nothing_here", {}), "", "unknown trigger yields no line")


func test_priority_interrupt_and_queue_rules() -> void:
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_jitters", "name": "JITTERS", "team": 0}], "seed": 1})
	check(Audio.announce("ann_low_01"), "low-priority line starts when idle")
	check(Audio.announce("ann_combo_01"), "a combo call (40) waits briefly instead of being dropped")
	check_eq(Audio.announcer_queue().size(), 1, "it is queued with an expiry")
	check_eq(_subs.size(), 1, "queued line has not spoken yet")
	check(Audio.announce("ann_kd_01"), "a knockdown (80) cuts into low-priority talk")
	check_eq(str(Audio._ann_current.get("id", "")), "ann_kd_01", "the knockdown is on air")
	check(Audio.announce("ann_ko_01"), "KO (100) interrupts")
	check_eq(str(_subs[-1]["text"]), "IT'S OVER! Goodnight, good luck, and good grief!", "KO text")
	check(Audio.announcer_queue().is_empty(), "the KO made the waiting combo call stale")
	check(not Audio.announce("ann_idle_01", {}, {"priority": 10}), "color-level chatter is never queued behind a line")
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
	# v0.9.17: the KO call waits for the same tick's round_end, which says whether it ends the bout
	var ends := Audio.on_sim_event({"type": "round_end", "winner": 0, "round": 1, "decided": true})
	var ko_line := false
	for a2 in ends:
		if str(a2).begins_with("line:") and str(Audio.line(str(a2).trim_prefix("line:")).get("trigger", "")) == "ko":
			ko_line = true
	check(ko_line, "KO line once the KO is known to end the bout (%s)" % str(ends))
	acts = Audio.on_sim_event({"type": "unknown_event_type", "fighter": 0})
	check(acts.is_empty(), "unknown events are ignored safely")
	check_eq(Audio.sfx("hit_light", p), -1, "headless: sfx() is a no-op returning -1")
	check_eq(Audio.sfx("definitely_missing_id"), -1, "missing id never crashes")


## MCH-07/08 (v0.9.16): 10-point bells, the judges' decision (read with the WINNER's name, from the
## recorded "time" / "draw" templates), the referee's count, wave-up and stoppage. No new Content
## lines: the counts above stay pinned. The campaign's own "decision" event stays unmapped.
func test_ten_point_and_referee_event_mapping() -> void:
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "STOKE", "team": 0},
		{"index": 1, "creature": "f_dredge", "name": "DREDGE", "team": 1}], "arena": "the_gullet", "seed": 12})
	var lines := func(acts: Array) -> Array:
		return acts.filter(func(a): return str(a).begins_with("line:"))
	# every 10-point bell is a timeout: the bell rings, the cards are not announced yet
	var acts := Audio.on_sim_event({"type": "timeout"}, Vector3.ZERO, {"ten_point": true})
	check(acts.has("ann_bell"), "10-point bell (%s)" % str(acts))
	check((lines.call(acts) as Array).is_empty(), "no decision line at a 10-point bell (%s)" % str(acts))
	acts = Audio.on_sim_event({"type": "round_scored", "round": 1, "teams": [0, 1], "judges": [[10, 9], [10, 9], [10, 9]], "winner": 0})
	check(acts.has("ui_card_flip"), "the scorecard turns over (%s)" % str(acts))
	# Health scoring keeps the old decision call at time (a match is judged one way throughout)
	Audio.end_match()
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "STOKE", "team": 0},
		{"index": 1, "creature": "f_dredge", "name": "DREDGE", "team": 1}], "arena": "the_gullet", "seed": 13})
	acts = Audio.on_sim_event({"type": "timeout"})
	var hp_call := ""
	for a0 in acts:
		if str(a0).begins_with("line:"):
			hp_call = str(a0).trim_prefix("line:")
	check(acts.has("ann_bell") and str(Audio.line(hp_call).get("when", {}).get("kind", "")) == "decision", "HP timeout still goes to the cards (%s)" % str(acts))
	Audio.stop_announcer()
	Audio.end_match()
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "STOKE", "team": 0},
		{"index": 1, "creature": "f_dredge", "name": "DREDGE", "team": 1}], "arena": "the_gullet", "seed": 14, "ten_point": true})
	_subs.clear()
	# the decision names the winner (DREDGE), not the local player
	acts = Audio.on_sim_event({"type": "judges_decision", "winner": 1, "method": "Split Decision", "totals": [[29, 28], [28, 29], [28, 29]],
		"judges": [0, 1, 1], "teams": [0, 1]}, Vector3.ZERO, {"ten_point": true})
	check(acts.has("ann_sting") and acts.has("line:ann_time_02"), "decision call (%s)" % str(acts))
	check(not _subs.is_empty() and str(_subs[-1]["text"]).contains("DREDGE") and not str(_subs[-1]["text"]).contains("STOKE"),
		"the winner's name is read: %s" % str(_subs))
	Audio.stop_announcer()
	# a sudden-death win after drawn cards
	acts = Audio.on_sim_event({"type": "judges_decision", "winner": 0, "method": "Sudden Death (after a Split Draw)", "teams": [0, 1]},
		Vector3.ZERO, {"ten_point": true})
	check(acts.has("line:ann_time_04"), "sudden-death win call (%s)" % str(acts))
	Audio.stop_announcer()
	# a T.K.O. decision: the stoppage already had its call
	acts = Audio.on_sim_event({"type": "judges_decision", "winner": 0, "method": "TKO", "teams": [0, 1]}, Vector3.ZERO, {"ten_point": true})
	check((lines.call(acts) as Array).is_empty(), "no second call for a T.K.O. decision (%s)" % str(acts))
	# drawn cards: the draw line, unless a sudden death follows (it has its own call), and once only
	acts = Audio.on_sim_event({"type": "judges_decision", "winner": -1, "method": "Split Draw", "teams": [0, 1]}, Vector3.ZERO,
		{"ten_point": true, "sudden_death_follows": true})
	check((lines.call(acts) as Array).is_empty(), "no draw line before a sudden death (%s)" % str(acts))
	acts = Audio.on_sim_event({"type": "judges_decision", "winner": -1, "method": "Majority Draw", "teams": [0, 1]}, Vector3.ZERO, {"ten_point": true})
	var drew := false
	for a in acts:
		drew = drew or str(a).begins_with("line:ann_draw_")
	check(drew, "drawn decision uses the draw line (%s)" % str(acts))
	Audio.stop_announcer()
	acts = Audio.on_sim_event({"type": "match_end", "winner": -1})
	check((lines.call(acts) as Array).is_empty(), "the draw is not announced twice (%s)" % str(acts))
	# the referee: Barnaby's "I'm not the ref!" knockdown quip stays out while one is counting
	Audio.stop_announcer()
	Audio.on_sim_event({"type": "hit", "fighter": 0, "target": 1, "damage": 6.0, "point": Vector3.ZERO, "normal": Vector3.UP, "blocked": false,
		"parried": false, "counter": false, "part": "head", "element": "", "quality": 0.5, "move": "l1", "slot": "l1", "knockdown": false, "otg": false})
	Audio.stop_announcer()
	# without a referee the player's "I'm not the ref!" quip is an eligible knockdown call ...
	check_eq(CommentarySelector.matched_keys(Audio.line("ann_kd_04").get("when", {}), {"who": "player"}), 1, "the quip matches a player's knockdown")
	# ... and with one counting it never plays
	Audio.end_match()
	Audio.use_memory_history()
	Audio.begin_match({"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "STOKE", "team": 0},
		{"index": 1, "creature": "f_dredge", "name": "DREDGE", "team": 1}], "arena": "the_gullet", "seed": 15, "referee": true})
	Audio.on_sim_event({"type": "hit", "fighter": 0, "target": 1, "damage": 6.0, "point": Vector3.ZERO, "normal": Vector3.UP, "blocked": false,
		"parried": false, "counter": false, "part": "head", "element": "", "quality": 0.5, "move": "l1", "slot": "l1", "knockdown": false, "otg": false})
	Audio.stop_announcer()
	acts = Audio.on_sim_event({"type": "knockdown", "fighter": 1, "reason": "move", "by": 0}, Vector3.ZERO, {"referee": true})
	check(acts.has("knockdown") and not acts.has("line:ann_kd_04"), "no 'I'm not the ref!' under a referee (%s)" % str(acts))
	check(not (lines.call(acts) as Array).is_empty(), "another knockdown call instead (%s)" % str(acts))
	acts = Audio.on_sim_event({"type": "ref_count", "fighter": 1, "n": 2})
	check(acts.has("ui_timer_tick"), "count tick (%s)" % str(acts))
	acts = Audio.on_sim_event({"type": "ref_wave_up", "fighter": 1})
	check((lines.call(acts) as Array).is_empty(), "wave-up has no announcer line (%s)" % str(acts))
	Audio.stop_announcer()
	# the stopping knockdown's call is still queued behind another line when the referee waves it off
	check(Audio.announce("ann_combo_01"), "a line is playing")
	check(Audio.announce("ann_kd_01", {}, {"priority": 60}) and not Audio.announcer_queue().is_empty(), "a knockdown call is queued")
	acts = Audio.on_sim_event({"type": "ref_stoppage", "fighter": 1, "by": 0, "reason": "knockdowns", "round": 2})
	check(acts.has("ann_bell_triple") and acts.has("ko"), "stoppage bell + KO sound (%s)" % str(acts))
	check(Audio.announcer_queue().filter(func(e: Dictionary) -> bool: return str(e["id"]) == "ann_kd_01").is_empty(),
		"the stale knockdown call never follows the T.K.O. call")
	for a2 in acts:
		if str(a2).begins_with("line:"):
			check_eq(str(Audio.line(str(a2).trim_prefix("line:")).get("trigger", "")), "stoppage", "a stoppage is called as a stoppage, never 'KNOCKED OUT' (%s)" % a2)
	# the campaign's own "decision" (party / enemy HP) is untouched: no mapping
	Audio.stop_announcer()
	acts = Audio.on_sim_event({"type": "decision", "party": 0.5, "enemy": 0.4})
	check(acts.is_empty(), "campaign decision stays unmapped (%s)" % str(acts))
	# the bridge's look-ahead for drawn cards
	check(AudioMatchBridge._sudden_death_after([{"type": "judges_decision"}, {"type": "sudden_death"}], 0), "sudden death follows")
	check(not AudioMatchBridge._sudden_death_after([{"type": "judges_decision"}, {"type": "round_end"}, {"type": "sudden_death"}], 0),
		"a round_end ends the look-ahead")


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
