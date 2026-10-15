class_name CampaignDriver
extends RefCounted
## Plays a run without presentation: pending fights run as real headless MatchSims (bots pilot
## every party fighter), every other decision goes to a chooser (default CampaignAutoPilot).
## Used by The Bookie's Table fast-forward/unattended mode, co-op loopback hosts and tests.
## opts: {bot_tier_players: tier for the party's bots (default "contender"),
##        max_fight_seconds: safety cap per fight (default 420),
##        route: Callable(ctrl) -> node id (default auto-pilot), pids: players to auto-decide,
##        max_nodes: safety cap, on_step: Callable(ctrl, what) progress callback}

## Runs the pending fight of `ctrl` headless and applies its result. Returns the result.
static func play_fight(host: Node, ctrl: RunController, opts := {}) -> Dictionary:
	var built := ctrl.match_config({"bot_tier_players": str(opts.get("bot_tier_players", "contender")),
		"player_kinds": opts.get("player_kinds", _all_bots(ctrl))})
	if not (built["errors"] as PackedStringArray).is_empty() or (built["config"] as Dictionary).is_empty():
		push_warning("campaign fight could not be built: %s" % "; ".join(built["errors"]))
		var forfeit := {"campaign": {"won": false, "time": 0.0, "players": {}, "error": "; ".join(built["errors"])}}
		ctrl.complete_fight(forfeit)
		return forfeit
	var res: Dictionary = await HeadlessFightRunner.run(host, built["config"], float(opts.get("max_fight_seconds", 420.0)))
	ctrl.complete_fight(res)
	return res


static func _all_bots(ctrl: RunController) -> Dictionary:
	var k := {}
	for pid in RunState.player_ids(ctrl.state):
		k[pid] = "bot"
	return k


## Plays until the run ends (or max_nodes). Returns {nodes, fights, victory, phase}.
static func auto_run(host: Node, ctrl: RunController, opts := {}) -> Dictionary:
	var pids: Array = opts.get("pids", RunState.player_ids(ctrl.state))
	var max_nodes := int(opts.get("max_nodes", 60))
	var on_step: Callable = opts.get("on_step", Callable())
	var nodes := 0
	var fights := 0
	var guard := 0
	while not ctrl.is_over() and guard < 400:
		guard += 1
		match ctrl.phase():
			"map":
				if nodes >= max_nodes:
					break
				var route: Callable = opts.get("route", Callable())
				var id := str(route.call(ctrl)) if route.is_valid() else CampaignAutoPilot.choose_route(ctrl, str(pids[0]))
				if not ctrl.choose_node(id, str(pids[0])):
					push_warning("route choice failed: %s" % ctrl.last_error)
					break
				nodes += 1
				if on_step.is_valid():
					on_step.call(ctrl, "node")
			"fight":
				await play_fight(host, ctrl, opts)
				fights += 1
				if on_step.is_valid():
					on_step.call(ctrl, "fight")
			_:
				if not CampaignAutoPilot.settle(ctrl, pids):
					# nothing left to decide for our players (e.g. waiting on others): bail out
					push_warning("auto_run stalled in phase %s" % ctrl.phase())
					break
	return {"nodes": nodes, "fights": fights, "victory": ctrl.phase() == "victory", "phase": ctrl.phase()}
