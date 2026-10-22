extends TestCase
## The tail lookup preserves the full scan's cursor semantics without scanning old events per frame.


func test_event_tail_matches_full_scan_after_history_rollover() -> void:
	var sim := MatchSim.new()
	for i in 1000:
		sim.emit_event({"type": "probe", "value": i})
	check_eq(sim.events.size(), MatchSim.MAX_EVENTS, "bounded history rolls over")
	for cursor in [-1, 0, 1, 487, 488, 489, 998, 999, 1000, 1001]:
		var expected := sim.events.filter(func(e: Dictionary) -> bool: return int(e["seq"]) > cursor)
		check_eq(sim.events_since(cursor), expected, "same ordered tail for cursor %d" % cursor)
	var tail := sim.events_since(998)
	tail.clear()
	check_eq(sim.events.size(), MatchSim.MAX_EVENTS, "the result array does not own the history")
	sim.free()


func test_event_tail_handles_empty_and_sparse_sequences() -> void:
	var sim := MatchSim.new()
	check(sim.events_since(-1).is_empty(), "empty history is safe")
	sim.events = [{"seq": 2}, {"seq": 8}, {"seq": 31}]
	for cursor in [-1, 2, 3, 8, 30, 31, 50]:
		var expected := sim.events.filter(func(e: Dictionary) -> bool: return int(e["seq"]) > cursor)
		check_eq(sim.events_since(cursor), expected, "sparse sequences for cursor %d" % cursor)
	sim.free()
