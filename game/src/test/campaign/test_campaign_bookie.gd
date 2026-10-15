extends CampaignTestCase
## AI-03/AI-04: The Bookie's Table — AI pilots every fight; unattended mode runs three complete
## cards back to back (real headless fights, accelerated) with only valid phase transitions;
## pause freezes it, take-over hands decisions back to the player.

const VALID := {
	"map": ["fight", "event", "shop", "rest", "reward"],
	"fight": ["reward", "map", "defeat", "victory"],
	"event": ["reward", "fight", "map"],
	"shop": ["map"],
	"rest": ["map", "reward"],
	"reward": ["map", "victory"],
}


func test_unattended_three_complete_runs() -> void:
	var table := BookieTable.new()
	add_child(table)
	var prof := Profiles.default_profile("bookie_test", "Bookie")
	table.setup(cat(), run_cfg("f_dozer", {"seed": 777, "difficulty": "sparring"}), prof)
	table.fighter_tier = "headliner"
	table.think_delay = 0.0
	table.keep_going = true
	table.max_runs = 3
	table.speed = 24.0
	var t0 := Time.get_ticks_msec()
	await table.play()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("bookie: 3 unattended runs in %.1f s, %d transitions" % [secs, table.transitions.size()])
	check_eq(table.runs_completed, 3, "three complete runs")
	check_eq(table.results.size(), 3, "three results")
	var fights := 0
	for tr in table.transitions:
		var from := str(tr["from"])
		var to := str(tr["to"])
		check(VALID.has(from) and (VALID[from] as Array).has(to), "valid transition %s -> %s at %s" % [from, to, tr["node"]])
		if from == "fight":
			fights += 1
	check(fights >= 3, "real fights were played (%d)" % fights)
	var kinds := {}
	for tr2 in table.transitions:
		kinds[str(tr2["to"])] = true
	check(kinds.size() >= 4, "unattended play went through several node kinds (%s)" % str(kinds.keys()))
	for r in table.results:
		check(r.has("victory"), "each run ended with a result")
	check_eq(int(prof["records"]["runs"]["bookie"]["attempts"]), 3, "results go to the Bookie's own board")
	check_eq(int(prof["ladder"]["off_the_street"]["unlocked"]), 1, "the autobattler never unlocks Doses")
	table.queue_free()


func test_pause_and_take_over() -> void:
	var table := BookieTable.new()
	add_child(table)
	table.setup(cat(), run_cfg("f_gusto", {"seed": 31}))
	table.think_delay = 0.0
	table.speed = 16.0
	table.pause()
	table.play()          # runs in the background (coroutine)
	await wait_frames(10)
	check_eq(table.ctrl.phase(), "map", "paused: nothing happens")
	check(table.transitions.is_empty(), "no transitions while paused")
	var asked := []
	table.decision_needed.connect(func(kind): asked.append(kind))
	table.take_over()
	table.resume()
	await wait_frames(3)
	check(not asked.is_empty(), "after take-over the table asks the player")
	check_eq(table.ctrl.phase(), "map", "and waits for the player's route")
	var id := str(table.ctrl.available_nodes()[0])
	table.ctrl.choose_node(id, "p0")
	table.stop()              # stop before resuming so the loop ends instead of starting the fight
	table.player_decided()
	await wait_frames(2)
	check_eq(str(table.ctrl.state["position"]), id, "the player's choice was used")
	check(not table.running, "the table loop ended cleanly")
	table.queue_free()
