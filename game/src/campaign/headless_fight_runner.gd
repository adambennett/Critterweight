class_name HeadlessFightRunner
extends RefCounted
## Runs a campaign match without presentation, in its own physics world (a SubViewport with
## own_world_3d, so concurrent/consecutive sims never share bodies), stepping MatchSim once per
## physics frame with the fixed 1/120 s step. Used by The Bookie's Table "fast-forward", co-op
## loopback tests and campaign tests; combine with SimSpeed to run faster than real time.
## The fight obeys exactly the same rules as a presented match (same MatchSim, modes, bots).
##
## Usage: var result = await HeadlessFightRunner.run(host_node, match_config, 420.0)

## Returns the MatchSim result (with result["campaign"]); on the safety time cap the mode is
## asked for a decision so a run can never hang on a stalemate.
static func run(host: Node, config: Dictionary, max_seconds := 420.0) -> Dictionary:
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sv.size = Vector2i(2, 2)
	host.add_child(sv)
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	sim.setup(config)
	var dt := SimSpeed.step_dt()
	var tree := host.get_tree()
	while not sim.is_finished and sim.time < max_seconds:
		sim.step(dt)
		await tree.physics_frame
	var res: Dictionary = sim.result
	if not sim.is_finished:
		var m = sim.mode
		if m is CampaignMatchMode:
			(m as CampaignMatchMode)._decide_by_health()
		# let the round-end phase run out so the mode builds its final result
		var guard := 0
		while not sim.is_finished and guard < 600:
			sim.step(dt)
			await tree.physics_frame
			guard += 1
		res = sim.result if sim.is_finished else sim.mode.build_result()
		res["timed_out"] = true
	sv.queue_free()
	return res
