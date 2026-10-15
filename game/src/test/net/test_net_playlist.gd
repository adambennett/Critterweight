extends TestCase
## NET-08: playlist rules - weighted candidates, vote resolution (tie / no-vote), repeat
## avoidance, minimum players and bot fill, validation of invalid entries and missing content,
## persistence across restarts, and the shipped example playlists.


func _pl(entries: Array, extra: Dictionary = {}) -> NetPlaylist:
	var d := {"id": "t_%d" % randi(), "name": "T", "entries": entries}
	for k in extra:
		d[k] = extra[k]
	var p := NetPlaylist.from_dict(d, "test")
	p.validate()
	p.rng.seed = 99
	return p


func test_weights_are_relative_probabilities() -> void:
	var p := _pl([{"id": "a", "rules": "duel", "arena": "the_gullet", "weight": 5},
		{"id": "b", "rules": "free_for_all", "arena": "the_gullet", "weight": 3},
		{"id": "c", "rules": "teams_2v2", "arena": "the_gullet", "weight": 2}],
		{"voting": {"candidates": 1, "enabled": false}, "repeat_avoidance": 0})
	check((p.errors as Array).is_empty(), "valid: %s" % str(p.errors))
	var counts := {"a": 0, "b": 0, "c": 0}
	var n := 10000
	for i in n:
		var c := p.draw_candidates(4, true, 1)
		counts[str(c[0]["key"])] += 1
	check_near(float(counts["a"]) / n, 0.5, 0.025, "weight 5 of 10")
	check_near(float(counts["b"]) / n, 0.3, 0.025, "weight 3 of 10")
	check_near(float(counts["c"]) / n, 0.2, 0.025, "weight 2 of 10")


func test_candidates_are_distinct_and_avoid_repeats() -> void:
	var p := _pl([{"id": "a", "rules": "duel", "arena": "the_gullet", "weight": 1},
		{"id": "b", "rules": "duel", "arena": "the_gullet", "weight": 1, "rules_override": {"round_time": 60}},
		{"id": "c", "rules": "free_for_all", "arena": "the_gullet", "weight": 1},
		{"id": "d", "rules": "teams_2v2", "arena": "the_gullet", "weight": 1}],
		{"voting": {"candidates": 3}, "repeat_avoidance": 2})
	var h1: Array[String] = ["a", "b"]
	p.history = h1
	for i in 200:
		var cands := p.draw_candidates(4, true, 3)
		var keys := cands.map(func(e): return str(e["key"]))
		check(not keys.has("a") and not keys.has("b"), "last 2 played excluded: %s" % str(keys))
		check_eq(keys.size(), 2, "only 2 fresh entries remain")
	var h2: Array[String] = ["a", "b", "c", "d"]
	p.history = h2
	p.repeat_avoidance = 4
	var relaxed := p.draw_candidates(4, true, 3)
	check(not relaxed.is_empty(), "exclusion relaxed when it would leave nothing")
	var rk := relaxed.map(func(e): return str(e["key"]))
	check(not rk.has("d"), "the very last entry is still avoided: %s" % str(rk))


func test_vote_resolution_rules() -> void:
	var p := _pl([{"id": "a", "rules": "duel", "arena": "the_gullet", "weight": 1},
		{"id": "b", "rules": "duel", "arena": "the_gullet", "weight": 4, "rules_override": {"round_time": 50}},
		{"id": "c", "rules": "duel", "arena": "the_gullet", "weight": 2, "rules_override": {"round_time": 40}}])
	var cands: Array = [p.find_entry("a"), p.find_entry("b"), p.find_entry("c")]
	var r1 := p.resolve_vote(cands, {2: 0, 3: 0, 4: 2})
	check_eq(str(r1["entry"]["key"]), "a", "plurality wins regardless of weight")
	check_eq(str(r1["reason"]), "votes")
	var r2 := p.resolve_vote(cands, {2: 0, 3: 2})
	check_eq(str(r2["entry"]["key"]), "c", "tie -> higher weight among the tied")
	check_eq(str(r2["reason"]), "tie")
	var r3 := p.resolve_vote(cands, {})
	check_eq(str(r3["entry"]["key"]), "b", "no votes -> highest weight")
	check_eq(str(r3["reason"]), "no_votes")
	var same: Array = [p.find_entry("c"), p.find_entry("c").duplicate()]
	same[1]["key"] = "c2"
	var r4 := p.resolve_vote(same, {2: 0, 3: 1})
	check_eq(int(r4["index"]), 0, "equal weight tie -> first drawn")
	var r5 := p.resolve_vote(cands, {2: 9, 3: -1})
	check_eq(str(r5["reason"]), "no_votes", "invalid votes are ignored")


func test_min_players_and_bot_fill() -> void:
	var p := _pl([{"id": "teams_nobots", "rules": "teams_2v2", "arena": "the_gullet", "weight": 1, "bots": 0},
		{"id": "teams_bots", "rules": "teams_2v2", "arena": "the_gullet", "weight": 1},
		{"id": "ffa_min4", "rules": "free_for_all", "arena": "the_gullet", "weight": 1, "min_players": 4, "bots": 1}])
	var e1 := p.find_entry("teams_nobots")
	var e2 := p.find_entry("teams_bots")
	var e3 := p.find_entry("ffa_min4")
	check_eq(p.limits_for(e1), Vector2i(4, 4), "2v2 needs 4 fighters")
	check(not p.can_start(e1, 2, true), "bots: 0 -> waits for 4 humans")
	check(p.can_start(e1, 4, false), "4 humans start without bots")
	check(p.can_start(e2, 2, true), "server bot fill completes the teams")
	check(not p.can_start(e2, 2, false), "no server bots -> wait")
	check(p.can_start(e3, 3, false), "entry allows 1 bot: 3 humans + 1 bot = 4")
	check(not p.can_start(e3, 2, true), "entry allows only 1 bot: 2 humans are not enough")
	check(p.can_start(e2, 0, true), "empty server showcase: all bots")


func test_invalid_entries_are_reported_and_skipped() -> void:
	var p := _pl([{"rules": "duel", "arena": "the_gullet", "weight": 2},
		{"rules": "duel", "arena": "no_such_arena", "weight": 1},
		{"rules": "no_such_rules", "arena": "the_gullet", "weight": 1},
		{"rules": "duel", "arena": "the_gullet", "weight": -1},
		{"rules": "duel", "arena": "the_gullet", "weight": 1, "min_players": 5},
		{"rules": "duel", "weight": 1},
		"not an object"])
	check_eq(p.valid_entries().size(), 1, "only the first entry is valid")
	var all := "\n".join(PackedStringArray(p.errors))
	check(all.contains("entry 2") and all.contains("arena 'no_such_arena' not found"), "missing arena named")
	check(all.contains("entry 3") and all.contains("rules preset 'no_such_rules' not found"), "missing rules named")
	check(all.contains("entry 4") and all.contains("weight must be 0 or more"), "negative weight")
	check(all.contains("entry 5") and all.contains("min_players 5 is outside"), "impossible player count")
	check(all.contains("entry 6") and all.contains("missing 'arena'"), "missing field")
	check(all.contains("entry 7") and all.contains("not an object"), "malformed entry")
	check(all.contains("skipped"), "errors say the entry is skipped")
	var only := p.draw_candidates(2, true, 3)
	check_eq(only.size(), 1, "invalid entries are never drawn")
	var none := _pl([{"rules": "nope", "arena": "nope", "weight": 1}])
	check(str(none.errors).contains("no valid entries"), "unusable playlist flagged")
	var missing := NetPlaylist.load_ref("definitely_not_a_playlist")
	check(not missing.errors.is_empty() and str(missing.errors).contains("not found"), "unknown playlist id explained")


func test_state_persists_across_restarts() -> void:
	var p := _pl([{"id": "a", "rules": "duel", "arena": "the_gullet", "weight": 1},
		{"id": "b", "rules": "free_for_all", "arena": "the_gullet", "weight": 1}])
	p.id = "persist_test_%d" % OS.get_process_id()
	p.record_played(p.find_entry("a"))
	p.record_played(p.find_entry("b"))
	check_eq(p.save_state(), OK, "saved")
	var q := _pl([{"id": "a", "rules": "duel", "arena": "the_gullet", "weight": 1},
		{"id": "b", "rules": "free_for_all", "arena": "the_gullet", "weight": 1}])
	q.id = p.id
	var msg := q.load_state()
	check(msg.contains("2 matches played"), msg)
	check_eq(q.history, p.history, "history restored")
	Saves.delete_save(p.state_path())


func test_shipped_playlists_are_valid() -> void:
	var ids: Array = Content.ids("playlists")
	check(ids.size() >= 2, "at least two example playlists ship (%s)" % str(ids))
	for id in ids:
		var p := NetPlaylist.load_ref(str(id))
		p.validate()
		check(p.valid_entries().size() >= 2, "%s has >= 2 valid entries" % id)
		check(p.errors.is_empty(), "%s validates cleanly: %s" % [id, str(p.errors)])
	check(Content.errors.is_empty() or not str(Content.errors).contains("playlist"), "content loader accepted the playlists: %s" % str(Content.errors))
