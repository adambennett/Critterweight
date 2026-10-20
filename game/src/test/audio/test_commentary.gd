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
	var stop := d.on_event({"type": "ref_stoppage", "fighter": 1, "by": 0}, {"time": 12.0})
	check_eq(_triggers(stop), ["stoppage"], "a referee stoppage is a stoppage call, not a knockout")
	check_eq(int(stop[0]["priority"]), 100, "result calls are critical")
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
