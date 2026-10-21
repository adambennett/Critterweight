extends TestCase
## v0.9.17 commentary engine (docs/audio/COMMENTARY.md): persistent history, fresh selection without
## specificity traps, joke-family spacing, the expiring queue, and the director's accuracy/pacing.

var _log: Array = []


func before_each() -> void:
	_log.clear()
	Audio.stop_announcer()
	Audio.announcer_mode = "full"
	Audio.subtitles_on = true
	Audio.use_memory_history()
	Audio.commentary_event.connect(_on_log)


func after_each() -> void:
	Audio.commentary_event.disconnect(_on_log)
	Audio.stop_announcer()
	Audio.end_match()


func _on_log(ev: Dictionary) -> void:
	_log.append(ev)


func _kinds(kind: String) -> Array:
	return _log.filter(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == kind)


func _duel(seed_value: int, extra := {}) -> void:
	var ctx := {"player_index": 0, "fighters": [{"index": 0, "creature": "f_stoke", "name": "STOKE", "team": 0},
		{"index": 1, "creature": "f_dredge", "name": "DREDGE", "team": 1}], "arena": "the_gullet", "seed": seed_value}
	ctx.merge(extra, true)
	Audio.begin_match(ctx)


# ---- history ------------------------------------------------------------------------------------

func test_history_persists_across_restarts_and_stays_bounded() -> void:
	var path := temp_dir("commentary_history").path_join("h.json")
	var h := CommentaryHistory.new()
	h.path = path
	h.begin_match()
	h.note_play("a", ["bookie"])
	h.begin_match()
	h.note_play("b", ["snacks"])
	h.save_file()
	var h2 := CommentaryHistory.new()
	h2.path = path
	h2.load_file()
	check_eq(h2.match_serial, 2, "match serial survives a restart")
	check_eq(h2.matches_since("a"), 1, "a was heard one match ago")
	check_eq(h2.matches_since("b"), 0, "b was heard this match")
	check_eq(h2.plays_since("a"), 1, "one line since a")
	check_eq(h2.family_plays_since("snacks"), 0, "the snacks family was the last one")
	check(h2.matches_since("never") > 1000, "unheard lines read as never heard")
	for i in CommentaryHistory.MAX_ENTRIES + 50:
		h2.note_play("x%d" % i, [])
	check_eq(h2.entries.size(), CommentaryHistory.MAX_ENTRIES, "the ring is bounded")
	check(h2.matches_since("a") > 1000, "the oldest entries fall out of the window")
	# a damaged file starts fresh instead of failing
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var h3 := CommentaryHistory.new()
	h3.path = path
	h3.load_file()
	check(h3.entries.size() >= 0, "a damaged history loads (backup or empty) without crashing")


# ---- selection ----------------------------------------------------------------------------------

func _table() -> Dictionary:
	return {
		"spec_a": {"id": "spec_a", "speaker": "barnaby", "when": {"creature": "f_stoke"}, "families": ["furnace"]},
		"spec_b": {"id": "spec_b", "speaker": "barnaby", "when": {"creature": "f_stoke"}, "families": ["furnace"]},
		"gen_a": {"id": "gen_a", "speaker": "kendall", "when": {}, "families": ["snacks"]},
		"gen_b": {"id": "gen_b", "speaker": "kendall", "when": {}, "families": ["bookie"]},
		"wrong": {"id": "wrong", "speaker": "barnaby", "when": {"creature": "f_dredge"}, "families": []},
	}


func test_selector_prefers_specific_fresh_lines_but_never_traps_on_them() -> void:
	var h := CommentaryHistory.new()
	var sel := CommentarySelector.new(h)
	sel.seed_match(1)
	var table := _table()
	var ids: Array = table.keys()
	h.begin_match()
	var first := sel.pick(ids, table, {"creature": "f_stoke"})
	check(first in ["spec_a", "spec_b"], "a fresh specific line wins first (%s)" % first)
	check(sel.pick(ids, table, {"creature": "f_gusto"}) != "wrong", "a non-matching line is never picked")
	h.note_play(first, table[first]["families"])
	var second := sel.pick(ids, table, {"creature": "f_stoke"})
	check(second != first, "the line just heard is not repeated (%s)" % second)
	h.note_play(second, table[second]["families"])
	var third := sel.pick(ids, table, {"creature": "f_stoke"})
	check(third in ["gen_a", "gen_b"], "with both specific lines heard this match, a fresh generic line plays (%s)" % third)
	# next match (a rematch): the specific lines heard one match ago still yield to unheard ones
	h.begin_match()
	h.note_play(third, table[third]["families"])
	var fourth := sel.pick(ids, table, {"creature": "f_stoke"})
	check(fourth != third and fourth not in [first, second], "the rematch reaches the remaining unheard line (%s)" % fourth)
	# only heard lines left: the least recent one is chosen rather than nothing
	h.note_play(fourth, table[fourth]["families"])
	check(sel.pick(ids, table, {"creature": "f_stoke"}) != "", "selection never goes silent when everything was heard")


func test_selector_spaces_joke_families() -> void:
	var h := CommentaryHistory.new()
	var sel := CommentarySelector.new(h)
	sel.seed_match(9)
	var table := {
		"bookie_1": {"speaker": "kendall", "when": {}, "families": ["bookie"]},
		"bookie_2": {"speaker": "kendall", "when": {}, "families": ["bookie"]},
		"snack_1": {"speaker": "kendall", "when": {}, "families": ["snacks"]},
	}
	h.begin_match()
	h.note_play("bookie_1", ["bookie"])
	check_eq(sel.pick(table.keys(), table, {}), "snack_1", "a bookie bit right after a bookie bit is avoided")


# ---- the queue ----------------------------------------------------------------------------------

func test_queue_expires_stale_calls_and_results_invalidate() -> void:
	_duel(5)
	check(Audio.announce("ann_low_01"), "a line is playing")
	check(Audio.announce("ann_combo_01", {}, {"ttl": 0.2, "priority": 60}), "a play-by-play call waits instead of being dropped")
	check_eq(Audio.announcer_queue().size(), 1, "one call waits")
	# the announcer's clock is wall time (it follows the recordings), not the fixed-step test clock
	var until := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	Audio._finish_line()
	check(not _kinds("expired").is_empty(), "the late combo call expired rather than playing late (%s)" % str(_log))
	check(str(Audio._ann_current.get("id", "")) != "ann_combo_01", "the stale call did not start")
	Audio.stop_announcer()
	check(Audio.announce("ann_low_01"), "a line is playing")
	check(Audio.announce("ann_kd_01", {}, {"tag": "round"}), "a knockdown call is queued")
	var acts := Audio.on_sim_event({"type": "ref_stoppage", "fighter": 1, "by": 0, "reason": "knockdowns", "round": 2}, Vector3.ZERO, {"time": 50.0})
	check(acts.has("ann_bell_triple"), "the stoppage bell rings (%s)" % str(acts))
	var waiting_kd := Audio.announcer_queue().filter(func(e: Dictionary) -> bool: return str(e["id"]) == "ann_kd_01")
	check(waiting_kd.is_empty(), "the stale knockdown call never follows the stoppage")
	check(not _kinds("invalidated").is_empty() or not _kinds("interrupted").is_empty(), "the stale call was invalidated or cut")


func test_interrupts_fade_and_low_lines_wait_for_room() -> void:
	_duel(6)
	check(Audio.announce("ann_low_01"), "a line is playing")
	check(not Audio.announce("ann_idle_01", {}, {"priority": 10}), "color-level chatter is never queued behind a line")
	check(Audio.announce("ann_ko_01"), "a KO interrupts")
	check_eq(str(Audio._ann_current.get("id", "")), "ann_ko_01", "the KO owns the booth")
	check(not _kinds("interrupted").is_empty(), "the interruption is logged")


# ---- the director -------------------------------------------------------------------------------

func _director(extra := {}) -> CommentaryDirector:
	var d := CommentaryDirector.new()
	var ctx := {"fighters": [{"index": 0, "creature": "f_varga", "name": "VARGA", "team": 0}, {"index": 1, "creature": "f_knell", "name": "KNELL", "team": 1}],
		"player_index": 0, "context": "versus", "seed": 3, "rounds": 3}
	ctx.merge(extra, true)
	d.begin(ctx)
	return d


func _triggers(reqs: Array) -> Array:
	return reqs.map(func(r: Dictionary) -> String: return str(r["trigger"]))


func test_director_distinguishes_knockdown_stoppage_knockout_and_decisions() -> void:
	var d := _director({"referee": true, "ten_point": true})
	var kd := d.on_event({"type": "knockdown", "fighter": 1, "reason": "hit", "by": 0}, {"time": 10.0, "referee": true})
	check_eq(_triggers(kd), ["knockdown"], "a knockdown is a knockdown call")
	check(bool(kd[0]["ctx"].get("referee", false)) and not kd[0]["ctx"].has("who"), "under a referee the call knows it and drops 'I'm not the ref'")
	# 10-point: stoppage, the partial round's card, the T.K.O. decision and the round_end in one tick
	check(d.on_event({"type": "ref_stoppage", "fighter": 1, "by": 0}, {"time": 12.0}).is_empty(), "the stoppage call waits for its round_end")
	check(d.on_event({"type": "round_scored", "winner": 0, "judges": [[10, 9], [10, 9], [10, 9]]}, {"time": 12.0}).is_empty(),
		"no round-card call over a T.K.O.")
	check(d.on_event({"type": "judges_decision", "winner": 0, "method": "TKO"}, {"time": 12.0}).is_empty(), "the T.K.O. decision has no call of its own")
	var stop := d.on_event({"type": "round_end", "winner": 0, "round": 1}, {"time": 12.0})
	check_eq(_triggers(stop), ["stoppage"], "a referee stoppage is a stoppage call, not a knockout")
	check_eq(int(stop[0]["priority"]), 100, "result calls are critical")
	check_eq(str(stop[0]["ctx"].get("ends", "")), "fight", "a 10-point stoppage ends the bout")
	check_eq(str(stop[0]["vars"].get("w", "")), "VARGA", "the T.K.O. names the winner")
	check(d.finished, "nothing but the result after a T.K.O.")
	var d2 := _director({"ten_point": true})
	check_eq(_triggers(d2.on_event({"type": "judges_decision", "winner": 1, "method": "Split Decision"}, {"time": 300.0})), ["decision"], "a decision")
	var split := d2.on_event({"type": "judges_decision", "winner": 1, "method": "Split Decision"}, {"time": 300.0})
	check_eq(str(split[0]["ctx"]["kind"]), "split", "split decision kind")
	check_eq(str(split[0]["vars"].get("p", "")), "KNELL", "the decision names the winner")
	check(d2.on_event({"type": "judges_decision", "winner": 0, "method": "TKO"}, {}).is_empty(), "no second call after a stoppage")
	var d3 := _director()
	check(d3.on_event({"type": "ko", "fighter": 1, "by": 0}, {"time": 20.0}).is_empty(), "a KO call waits for its round_end")
	var ko := d3.on_event({"type": "round_end", "winner": 0, "round": 1, "decided": false}, {"time": 20.0})
	check_eq(_triggers(ko), ["ko"], "a real knockout")
	check_eq(str(ko[0]["ctx"].get("ends", "")), "round", "a KO that takes round 1 of a best-of-three does not end the bout")
	check(not d3.finished, "the bout goes on")
	d3.on_event({"type": "ko", "fighter": 1, "by": 0}, {"time": 80.0})
	var ko2 := d3.on_event({"type": "round_end", "winner": 0, "round": 2, "decided": true}, {"time": 80.0})
	check_eq(str(ko2[0]["ctx"].get("ends", "")), "fight", "the deciding KO ends the fight")
	check_eq(int(ko2[0]["priority"]), 100, "and is a critical call")
	var d4 := _director({"rounds": 1})
	d4.on_event({"type": "ko", "fighter": 1, "by": 0}, {"time": 20.0})
	var elim := d4.on_tick([1.0, 0.0], -1.0, 0.25)
	check_eq(str(elim[0]["ctx"].get("ends", "")), "none", "an elimination in a match that continues")


func test_director_detects_whiffs_exchanges_and_pressure() -> void:
	var d := _director()
	d.on_event({"type": "round_start", "round": 1}, {"time": 1.0})
	d.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 5.0, "slot": "l1"}, {"time": 2.0})   # first hit
	# a committed heavy that touches nothing is a whiff
	d.on_event({"type": "move_start", "fighter": 1, "slot": "heavy"}, {"time": 5.0})
	var whiff := d.on_tick([1.0, 1.0], 80.0, 1.0)
	check("whiff" in _triggers(d.on_tick([1.0, 1.0], 80.0, 0.25)) or "whiff" in _triggers(whiff), "an attack that hit nothing is a whiff")
	# ... but one that lands is not
	var d2 := _director()
	d2.on_event({"type": "round_start", "round": 1}, {"time": 1.0})
	d2.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 5.0, "slot": "l1"}, {"time": 2.0})
	d2.on_event({"type": "move_start", "fighter": 1, "slot": "heavy"}, {"time": 5.0})
	d2.on_event({"type": "hit", "fighter": 1, "target": 0, "damage": 3.0, "slot": "heavy", "blocked": true}, {"time": 5.4})
	var calls: Array = []
	for i in 6:
		calls.append_array(_triggers(d2.on_tick([1.0, 1.0], 80.0, 0.25)))
	check(not calls.has("whiff"), "a blocked heavy is not a whiff (%s)" % str(calls))
	# a trade inside the exchange window
	var d3 := _director()
	d3.on_event({"type": "round_start", "round": 1}, {"time": 1.0})
	d3.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 4.0, "slot": "l1"}, {"time": 2.0})
	d3.on_event({"type": "hit", "fighter": 1, "target": 0, "damage": 4.0, "slot": "l1"}, {"time": 6.0})
	var trade := d3.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 4.0, "slot": "l1"}, {"time": 6.5})
	check_eq(_triggers(trade), ["exchange"], "both fighters landing in a second is an exchange")
	# unanswered offence
	var d4 := _director()
	d4.on_event({"type": "round_start", "round": 1}, {"time": 1.0})
	var got: Array = []
	for k in 6:
		got.append_array(_triggers(d4.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 4.0, "slot": "l1"}, {"time": 2.0 + 1.4 * k})))
	check(got.has("pressure"), "four unanswered hits is pressure (%s)" % str(got))


func test_director_does_not_spam_repeated_abilities() -> void:
	var d := _director()
	d.on_event({"type": "round_start", "round": 1}, {"time": 1.0})
	var calls := 0
	for k in 8:
		calls += d.on_event({"type": "ability", "fighter": 0, "slot": "ability1", "id": "cut_the_angle"}, {"time": 3.0 + 6.0 * k}).size()
	check(calls <= 2, "an ability cast every six seconds is called at most twice in 48 s (%d)" % calls)


func test_director_paces_lulls_with_observations_and_color() -> void:
	var d := _director()
	d.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	var reqs: Array = []
	for k in 160:     # 40 quiet seconds
		reqs.append_array(d.on_tick([0.62, 0.6], 60.0, 0.25))
	check(not reqs.is_empty(), "a quiet stretch gets some talk")
	check(reqs.size() <= 6, "but not a wall of it (%d requests in 40 s)" % reqs.size())
	for r in reqs:
		check(str(r["class"]) in ["low", "color"], "lull talk is low priority (%s)" % str(r))
	# the talk budget: a booth that has been talking nonstop holds its color lines
	var d2 := _director()
	d2.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	d2.note_line_started(0.0)
	var quiet: Array = []
	for k2 in 100:
		quiet.append_array(d2.on_tick([1.0, 1.0], 80.0, 0.25))
	check(quiet.filter(func(r: Dictionary) -> bool: return str(r["class"]) == "color").is_empty(), "no color over nonstop talk")


func test_career_bout_context_reaches_the_booth() -> void:
	var cfg := {"context": {"career": true, "title": true, "booth": {"title": true, "debut": false, "champion": false, "streak": 3}}}
	var ac := MatchScene.audio_context(cfg)
	check_eq(str(ac["context"]), "career", "a career bout is a career context")
	check(bool((ac["career"] as Dictionary).get("title", false)), "the title fight is known")
	var d := _director({"context": "career", "career": {"title": true}})
	var intro := d.on_event({"type": "round_intro", "round": 1}, {"time": 0.0})
	check_eq(_triggers(intro), ["career_intro"], "a career walk-in")
	check_eq(str(intro[0]["ctx"].get("kind", "")), "title", "a title fight walk-in")
	check_eq(str(MatchScene.audio_context({"spectate": true})["context"]), "spectate", "spectating has no player to address")


# ---- review fixes (v0.9.17) ---------------------------------------------------------------------

## Lines for a trigger whose conditions this context satisfies.
func _eligible(trigger: String, ctx: Dictionary) -> Array:
	var out: Array = []
	for id in Audio.trigger_line_ids(trigger):
		var when: Dictionary = Audio.line(str(id)).get("when", {})
		var ok := true
		for k in when:
			if not ctx.has(k) or not CommentarySelector.matches(ctx[k], when[k]):
				ok = false
				break
		if ok:
			out.append(str(id))
	return out


func test_talk_budget_recovers_after_interrupted_and_stopped_lines() -> void:
	var d := _director()
	d.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	d.note_line_started(1.0)          # a line ...
	d.t = 2.0
	d.note_line_started(2.0)          # ... cut off by a bigger call: its end is never reported
	d.t = 4.0
	d.note_line_finished(4.0)
	d.t = 40.0
	check(d.talk_share() < 0.01, "an interrupted line's talk time ends where the next began (%.2f)" % d.talk_share())
	var hit := d.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 5.0, "slot": "l1"}, {"time": 40.0})
	check_eq(_triggers(hit), ["first_hit"], "play-by-play still gets through after an interruption")
	# a line that never reports its end at all counts at most MAX_LINE_SECONDS
	var d2 := _director()
	d2.note_line_started(0.0)
	d2.t = 60.0
	check(d2.talk_share() < 0.01, "a lost open interval cannot hold the budget at 100%% (%.2f)" % d2.talk_share())
	# Audio: stop_announcer closes the cut line's interval
	_duel(11)
	check(Audio.announce("ann_low_01"), "a line is playing")
	Audio.stop_announcer()
	Audio._director.t += 40.0
	check(Audio._director.talk_share() < 0.01, "a stopped line's talk time ends at the stop")


func test_stoppage_in_a_best_of_ends_only_the_round() -> void:
	var d := _director({"referee": true})     # Health scoring, best of three
	d.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	check(d.on_event({"type": "ref_stoppage", "fighter": 1, "by": 0}, {"time": 40.0}).is_empty(), "held for the round_end")
	var r := d.on_event({"type": "round_end", "winner": 0, "round": 1, "decided": false}, {"time": 40.0})
	check_eq(_triggers(r), ["stoppage"], "one call: the stoppage, no 'Bell! That round goes to' on top (%s)" % str(_triggers(r)))
	check_eq(str(r[0]["ctx"].get("ends", "")), "round", "it stops the round, not the bout")
	check_eq(int(r[0]["priority"]), 85, "a round stoppage is a high call, not a result")
	check(not d.finished, "the bout goes on")
	var round_lines := _eligible("stoppage", r[0]["ctx"])
	check(not round_lines.is_empty(), "round stoppage lines exist")
	for id in round_lines:
		var w: Dictionary = Audio.line(str(id)).get("when", {})
		check(str(w.get("ends", "")) != "fight", "no 'your winner by T.K.O.' line fits a round stoppage (%s)" % str(id))
	d.on_event({"type": "round_start", "round": 2}, {"time": 50.0})
	var hit := d.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 5.0, "slot": "l1"}, {"time": 52.0})
	check_eq(_triggers(hit), ["first_hit"], "round two still gets play-by-play")
	d.on_event({"type": "ref_stoppage", "fighter": 1, "by": 0}, {"time": 90.0})
	var fin := d.on_event({"type": "round_end", "winner": 0, "round": 2, "decided": true}, {"time": 90.0})
	check_eq(str(fin[0]["ctx"].get("ends", "")), "fight", "the deciding stoppage is the T.K.O.")
	check(d.finished, "and ends the bout")
	# KO lines that sound final are kept for KOs that end the fight
	for id2 in _eligible("ko", {"ends": "round", "kind": []}):
		check(not str(Audio.line(str(id2)).get("text", "")).to_upper().begins_with("IT'S OVER"), "no 'It's over!' on a round KO (%s)" % str(id2))


func test_names_follow_the_players_corner() -> void:
	var d := _director()      # VARGA is the player (index 0), KNELL the opponent
	d.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	var fh := d.on_event({"type": "hit", "fighter": 1, "target": 0, "damage": 5.0, "slot": "l1"}, {"time": 2.0})
	check_eq(str(fh[0]["ctx"].get("who", "")), "opponent", "the opponent landed first")
	var said := Audio._substitute("{o} gets there first. Shake it off, {p}, you've got plenty of face left.", fh[0]["vars"])
	check_eq(said, "KNELL gets there first. Shake it off, VARGA, you've got plenty of face left.", "the legacy line names the right fighters")
	var kd := d.on_event({"type": "knockdown", "fighter": 0, "reason": "hit", "by": 1}, {"time": 5.0})
	check_eq(str(kd[0]["vars"].get("p", "")), "VARGA", "'{p} is down, folks' is the player who went down")
	var ro := d.on_event({"type": "ringout", "fighter": 1, "by": 0}, {"time": 9.0})
	check(not ro[0]["ctx"].has("who"), "the player ringing the opponent out is not 'you go off the roof'")
	var ro2 := d.on_event({"type": "ringout", "fighter": 0, "by": 1}, {"time": 30.0})
	check_eq(str(ro2[0]["ctx"].get("who", "")), "player", "the player going over is")
	check_eq(str(ro2[0]["vars"].get("p", "")), "VARGA", "and names the player")


func test_spectating_never_addresses_a_player() -> void:
	for extra in [{"context": "spectate"}, {"player_index": -1}]:
		var d := _director(extra)
		d.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
		var fh := d.on_event({"type": "hit", "fighter": 1, "target": 0, "damage": 5.0, "slot": "l1"}, {"time": 2.0})
		check(not fh[0]["ctx"].has("who") and not fh[0]["ctx"].has("target"), "no 'you' or 'your opponent' while spectating (%s)" % str(extra))
		var kd := d.on_event({"type": "knockdown", "fighter": 0, "reason": "hazard", "by": -1}, {"time": 4.0})
		check(not kd[0]["ctx"].has("who"), "a hazard knockdown is nobody's (%s)" % str(extra))
		var low := d.on_tick([0.15, 0.9], 60.0, 0.25)
		var lows := low.filter(func(r: Dictionary) -> bool: return str(r["trigger"]) == "low_health")
		check(not lows.is_empty() and not lows[0]["ctx"].has("who"), "low health without 'kid' lines (%s)" % str(extra))
		var re := d.on_event({"type": "round_end", "winner": 1, "round": 1, "decided": false}, {"time": 99.0})
		check(not re.is_empty() and not re[0]["ctx"].has("who"), "a round result is nobody's loss (%s)" % str(extra))
	# teams: the player's side winning a round is the player's round even when listed second
	var t := CommentaryDirector.new()
	t.begin({"fighters": [{"index": 0, "creature": "f_stoke", "name": "A", "team": 0}, {"index": 1, "creature": "f_dredge", "name": "B", "team": 1},
		{"index": 2, "creature": "f_gusto", "name": "C", "team": 0}, {"index": 3, "creature": "f_dozer", "name": "D", "team": 1}],
		"player_index": 2, "context": "versus", "seed": 1, "rounds": 3})
	var won := t.on_event({"type": "round_end", "winner": 0, "round": 1, "decided": false}, {"time": 99.0})
	check_eq(str(won[0]["ctx"].get("who", "")), "player", "the player's team won the round")
	check_eq(str(won[0]["vars"].get("w", "")), "A & C", "the round goes to the team")


func test_an_ability_that_hits_is_never_called_a_miss() -> void:
	var d := _director()
	d.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	d.on_event({"type": "ability", "fighter": 1, "slot": "ability1", "id": "f_knell.ability1"}, {"time": 1.0})
	d.on_event({"type": "hit", "fighter": 1, "target": 0, "damage": 8.0, "slot": "effect"}, {"time": 1.5})   # also the first hit
	d.on_event({"type": "ability", "fighter": 1, "slot": "ability1", "id": "f_knell.ability1"}, {"time": 5.0})
	d.on_event({"type": "hit", "fighter": 1, "target": 0, "damage": 8.0, "slot": "effect"}, {"time": 5.5})
	d.on_event({"type": "ability", "fighter": 1, "slot": "ability2", "id": "f_knell.ability2"}, {"time": 6.0})
	d.on_event({"type": "hit", "fighter": 1, "target": 0, "damage": 6.0, "slot": "effect", "blocked": true}, {"time": 6.4})
	var calls: Array = []
	for k in 40:
		calls.append_array(_triggers(d.on_tick([0.8, 1.0], 80.0, 0.25)))
	check(not calls.has("ability_miss"), "landed or blocked abilities are not misses (%s)" % str(calls))
	# a punished taunt is the round's first hit too
	var d2 := _director()
	d2.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	d2.on_event({"type": "taunt", "fighter": 0}, {"time": 1.0})
	check_eq(_triggers(d2.on_event({"type": "hit", "fighter": 1, "target": 0, "damage": 5.0, "slot": "l1"}, {"time": 2.0})), ["taunt_punished"], "taunt punished")
	check(not _triggers(d2.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 5.0, "slot": "l1"}, {"time": 9.0})).has("first_hit"),
		"the next hit is not 'lands first'")


func test_clock_decisions_and_sudden_death_name_the_real_winner() -> void:
	var d := _director()
	d.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	check(d.on_event({"type": "timeout"}, {"time": 99.0}).is_empty(), "a round clock running out is not a decision call")
	var r1 := d.on_event({"type": "round_end", "winner": 1, "round": 1, "decided": false}, {"time": 99.0})
	check_eq(_triggers(r1), ["round_end"], "a timed round gets its bell call")
	check_eq(str(r1[0]["vars"].get("w", "")), "KNELL", "naming the round's winner")
	check_eq(str(r1[0]["ctx"].get("who", "")), "opponent", "which is the opponent")
	d.on_event({"type": "round_start", "round": 3}, {"time": 200.0})
	d.on_event({"type": "timeout"}, {"time": 299.0})
	var r3 := d.on_event({"type": "round_end", "winner": 1, "round": 3, "decided": true}, {"time": 299.0})
	check_eq(_triggers(r3), ["time"], "the clock decided the bout")
	check_eq(str(r3[0]["vars"].get("p", "")), "KNELL", "'the cards say {p}' names the winner, not the player")
	var d2 := _director({"rounds": 3})
	d2.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	d2.on_event({"type": "timeout"}, {"time": 99.0})
	check_eq(_triggers(d2.on_event({"type": "sudden_death"}, {"time": 99.0})), ["time"], "sudden death is called")
	var sd := d2.on_event({"type": "round_end", "winner": 0, "round": 1, "decided": false}, {"time": 101.0})
	check_eq(str(sd[0]["ctx"].get("kind", "")), "sudden_death_won", "one touch settled the round")
	d2.on_event({"type": "round_start", "round": 2}, {"time": 110.0})
	check(not d2._sudden_death, "the next round is not sudden death")
	# 10-point: the decision ends the bout; closeness comes from the cards, not the (full) health
	var t1 := _director({"ten_point": true, "referee": true})
	t1.on_event({"type": "judges_decision", "winner": 0, "method": "Unanimous Decision", "totals": [[30, 27], [30, 27], [29, 28]]}, {"time": 300.0})
	check(t1.finished, "no whiffs or colour during the decision ceremony")
	var me1 := t1.on_event({"type": "match_end", "winner": 0}, {"time": 301.0})
	check(not bool(me1[0]["follow"]["ctx"].get("close", true)), "a 30-27 card is not a close fight")
	var t2 := _director({"ten_point": true})
	t2.on_event({"type": "judges_decision", "winner": 1, "method": "Unanimous Decision", "totals": [[28, 29], [28, 29], [28, 29]]}, {"time": 300.0})
	var me2 := t2.on_event({"type": "match_end", "winner": 1}, {"time": 301.0})
	check(bool(me2[0]["follow"]["ctx"].get("close", false)), "one point on every card is close")


func test_count_scorecard_and_first_of_the_night_lines_fit_the_moment() -> void:
	var d := _director({"referee": true, "ten_point": true})
	d.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	var thrown := d.on_event({"type": "knockdown", "fighter": 1, "reason": "throw", "by": 0}, {"time": 5.0, "referee": true})
	check(not bool(thrown[0]["ctx"].get("counted", true)), "a throw knockdown is never counted or scored")
	var ctx: Dictionary = (thrown[0]["ctx"] as Dictionary).duplicate()
	ctx["scoring"] = "ten_point"
	# a throw still scores as a throw; what it never gets is a count or a knockdown on the cards
	var wrong := RegEx.create_from_string("\\bcount|scorecard|judges|changed the score")
	for id in _eligible("knockdown", ctx):
		var text := str(Audio.line(str(id)).get("text", "")).to_lower()
		check(wrong.search(text) == null, "no count or scorecard talk after a throw (%s: %s)" % [str(id), text])
	var struck := d.on_event({"type": "knockdown", "fighter": 1, "reason": "hit", "by": 0}, {"time": 30.0, "referee": true})
	check(bool(struck[0]["ctx"].get("counted", false)), "a strike knockdown by the opponent is counted")
	d.on_event({"type": "round_start", "round": 2}, {"time": 100.0})
	var fh := d.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 5.0, "slot": "l1"}, {"time": 102.0})
	check_eq(str(fh[0]["ctx"].get("round", "")), "2plus", "a later round's first hit knows it")
	for id2 in _eligible("first_hit", fh[0]["ctx"]):
		var text2 := str(Audio.line(str(id2)).get("text", "")).to_lower()
		check(not text2.contains("of the night") and not text2.contains("of the fight"), "no 'first of the night' in round two (%s)" % str(id2))


func test_ceremonial_winner_names_never_replace_other_names() -> void:
	var lib = Audio._speech
	var ceremony: Dictionary = lib.catalog.get("tokens", {}).get("devon_ceremony", {})
	var normal: Dictionary = lib.catalog.get("tokens", {}).get("devon", {})
	if ceremony.is_empty() or not normal.has("adam") or not ceremony.has("stoke"):
		check(false, "the speech catalog has the ceremony and normal vocabularies")
		return
	var ctx := {"player_index": 0, "fighters": [{"index": 0, "name": "ADAM", "creature": "f_stoke"}, {"index": 1, "name": "DREDGE", "creature": "f_dredge"}]}
	check_eq(lib._token("devon", "w", "ADAM", ctx), [normal["adam"]], "a winner named ADAM is said as 'Adam', not as his creature")
	check_eq(lib._token("devon", "w", "STOKE", ctx), [ceremony["stoke"]], "a ceremonially recorded name uses the ceremonial take")


func test_a_second_interrupt_inside_the_fade_keeps_the_new_line() -> void:
	_duel(12)
	# headless runs have no speech players: lend Audio two for the check
	var keep_a: AudioStreamPlayer = Audio._speech_player
	var keep_b: AudioStreamPlayer = Audio._speech_player_b
	var live := AudioStreamPlayer.new()
	var fading := AudioStreamPlayer.new()
	add_child(live)
	add_child(fading)
	Audio._speech_player = live
	Audio._speech_player_b = fading
	# the first interrupt's fade is running on the other player; then a second interrupt comes
	fading.volume_db = -20.0
	var tw := Audio.create_tween()
	tw.tween_property(fading, "volume_db", -40.0, 5.0)
	Audio._speech_fade = tw
	Audio._stop_speech(true)
	check(not tw.is_valid(), "the earlier fade is killed before the players swap again")
	check(is_equal_approx(fading.volume_db, Audio.SPEECH_DB), "the faded player is reset at once, never left mid-fade")
	check(not fading.playing, "and stopped")
	check(Audio._speech_fade == null, "nothing fades when nothing was playing")
	Audio._speech_player = keep_a
	Audio._speech_player_b = keep_b
	live.queue_free()
	fading.queue_free()


func test_movesets_moves_are_called_by_name_and_kind() -> void:
	var d := _director({"fighters": [{"index": 0, "creature": "f_stoke", "name": "STOKE", "team": 0},
		{"index": 1, "creature": "f_dredge", "name": "DREDGE", "team": 1}]})
	d.on_event({"type": "round_start", "round": 1}, {"time": 0.0})
	d.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 3.0, "slot": "l1"}, {"time": 0.5})   # the round's first hit
	var cast := d.on_event({"type": "ability", "fighter": 0, "slot": "mv.flamethrower", "id": "f_stoke.mv.flamethrower",
		"pool": "flamethrower", "cat": "stream"}, {"time": 2.0})
	check_eq(_triggers(cast), ["ability"], "the Flamethrower is called")
	check(not cast.is_empty() and str(cast[0]["ctx"].get("id", "")) == "flamethrower" and str(cast[0]["ctx"].get("cat", "")) == "stream",
		"by the move's own id and its kind (%s)" % str(cast[0]["ctx"] if not cast.is_empty() else {}))
	var hit := d.on_event({"type": "hit", "fighter": 0, "target": 1, "damage": 1.6, "slot": "mv.flamethrower", "pool": "flamethrower",
		"cat": "stream", "tick": true}, {"time": 2.4})
	check_eq(_triggers(hit), ["ability_hit"], "the stream touching Dredge is a landed move")
	check(not hit.is_empty() and str(hit[0]["ctx"].get("id", "")) == "flamethrower" and str(hit[0]["ctx"].get("cat", "")) == "stream",
		"named and of its kind")
	# a lobbed Cinder Shot that touches nobody is a miss of a projectile
	d.on_event({"type": "ability", "fighter": 0, "slot": "mv.cinder_shot", "id": "f_stoke.mv.cinder_shot", "pool": "cinder_shot",
		"cat": "projectile"}, {"time": 12.0})
	var misses: Array = []
	for k in 16:
		for r in d.on_tick([0.8, 1.0], 80.0, 0.25):
			if str(r["trigger"]) == "ability_miss":
				misses.append(r)
	check(misses.size() == 1 and str(misses[0]["ctx"].get("id", "")) == "cinder_shot" and str(misses[0]["ctx"].get("cat", "")) == "projectile",
		"a projectile that touched nobody is called a miss, by name and kind (%s)" % str(misses))
