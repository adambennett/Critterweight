extends CampaignTestCase
## COOP-01..06 over the LOOPBACK PartyTransport (in-process; not network evidence): voting and
## ties, per-player picks without duplication, disconnect -> bot -> rejoin, host departure ->
## resume from a member's replica, everyone leaving -> suspended run, pause budget, per-player
## progression, tag-team format.

var hub: LoopbackTransport.Hub


func party_cfg(n := 3, extra := {}) -> Dictionary:
	var fighters := ["f_stoke", "f_dozer", "f_gusto", "f_jitters"]
	var cfg := run_cfg("f_stoke", {"seed": 2024, "created_at": 7})
	cfg["players"] = []
	for i in n:
		cfg["players"].append({"id": "p%d" % i, "name": "Member %d" % i, "profile_id": "m%d" % i, "fighter": fighters[i]})
	for k in extra:
		cfg[k] = extra[k]
	return cfg


func make_party(n := 3, extra := {}) -> Array:
	hub = LoopbackTransport.Hub.new()
	var ts := []
	for i in n:
		ts.append(hub.join("p%d" % i))
	var host := CoopSession.host_new(ts[0], cat(), party_cfg(n, extra), null, Profiles.default_profile("m0", "M0"))
	var sessions := [host]
	for i in range(1, n):
		sessions.append(CoopSession.member_join(ts[i], cat(), "p0", null, Profiles.default_profile("m%d" % i, "M%d" % i)))
	tick_all(sessions, 0.1)
	return sessions


func tick_all(sessions: Array, dt: float, times := 1) -> void:
	for k in times:
		for s in sessions:
			(s as CoopSession).tick(dt)


func test_route_vote_rules() -> void:
	var v := RouteVote.new(["a", "b", "c"], ["p0", "p1", "p2"], "p0", 10.0, 1, "k")
	v.cast("p1", "b")
	v.cast("p2", "b")
	v.cast("p0", "a")
	check_eq(str(v.result()["option"]), "b", "majority wins")
	var t := RouteVote.new(["a", "b"], ["p0", "p1"], "p0", 10.0, 1, "k")
	t.cast("p0", "a")
	t.cast("p1", "b")
	check_eq(str(t.result()["option"]), "a", "tie -> the Captain's vote")
	check_eq(str(t.result()["reason"]), "captain_tiebreak", "reason")
	var idle := RouteVote.new(["a", "b"], ["p0", "p1", "p2"], "p0", 10.0, 5, "k2")
	idle.cast("p1", "a")
	idle.cast("p2", "b")
	var r1 := str(idle.result()["option"])
	check(r1 in ["a", "b"] and str(idle.result()["reason"]) == "captain_idle_random", "idle Captain -> random among the tied")
	check_eq(str(idle.result()["option"]), r1, "deterministic")
	var none := RouteVote.new(["a", "b"], ["p0", "p1"], "p0", 10.0, 9, "k3")
	check_eq(str(none.result()["reason"]), "all_abstained_random", "all abstain")
	check(not v.cast("intruder", "a"), "only party members vote")
	check(not v.cast("p0", "zzz"), "only offered options")


func test_party_vote_drives_the_route() -> void:
	var s := make_party(3)
	var host: CoopSession = s[0]
	check(host.vote != null, "a vote opens on the map")
	var opts: Array = host.vote.options
	check(opts.size() >= 3, "row 1 offers 3+ routes")
	(s[0] as CoopSession).act("vote", {"node": str(opts[0])})
	(s[1] as CoopSession).act("vote", {"node": str(opts[1])})
	(s[2] as CoopSession).act("vote", {"node": str(opts[1])})
	tick_all(s, 0.1, 3)
	check_eq(str(host.ctrl.state["position"]), str(opts[1]), "majority route taken")
	for m in s:
		check_eq(str((m as CoopSession).state().get("position", "")), str(opts[1]), "every member mirrors the route")


func test_party_vote_tie_goes_to_captain() -> void:
	var s := make_party(2)
	var host: CoopSession = s[0]
	var opts: Array = host.vote.options
	check_eq(host.ctrl.captain(), "p0", "the host captains Act 1")
	(s[0] as CoopSession).act("vote", {"node": str(opts[0])})
	(s[1] as CoopSession).act("vote", {"node": str(opts[1])})
	tick_all(s, 0.1, 3)
	check_eq(str(host.ctrl.state["position"]), str(opts[0]), "tie broken by the Captain")


func test_vote_timer_with_abstainers() -> void:
	var s := make_party(3)
	var host: CoopSession = s[0]
	var opts: Array = host.vote.options
	(s[1] as CoopSession).act("vote", {"node": str(opts[2])})
	tick_all(s, 0.1, 2)
	check_eq(str(host.ctrl.state["position"]), "", "the vote stays open while others think")
	tick_all(s, 11.0)
	check_eq(str(host.ctrl.state["position"]), str(opts[2]), "after 10 s the single vote decides (others abstain)")


func _to_reward(s: Array) -> void:
	var host: CoopSession = s[0]
	tick_all(s, 11.0)
	check_eq(host.ctrl.phase(), "fight", "row 1 fight")
	host.complete_fight(fake_result(host.ctrl))
	tick_all(s, 0.1, 2)


func test_per_player_picks_without_duplication() -> void:
	var s := make_party(3)
	var host: CoopSession = s[0]
	_to_reward(s)
	check_eq(host.ctrl.phase(), "reward", "rewards after the fight")
	var offers := {}
	for pid in ["p0", "p1", "p2"]:
		var pend := host.ctrl.pending_for(pid)
		check_eq(pend.size(), 1, "%s has their own pick" % pid)
		offers[pid] = pend[0]
	var e1: Dictionary = offers["p1"]
	(s[1] as CoopSession).act("pick", {"rid": e1["rid"], "choice": e1["options"][0]})
	(s[1] as CoopSession).act("pick", {"rid": e1["rid"], "choice": e1["options"][0]})   # resent
	(s[2] as CoopSession).act("pick", {"rid": e1["rid"], "choice": e1["options"][0]})   # someone else's pick
	tick_all(s, 0.1, 3)
	var p1 := host.ctrl.player("p1")
	var n1 := 0
	for sp in p1["supplements"]:
		n1 += int(sp["stacks"])
	check_eq(n1, 1, "p1 got exactly one supplement")
	var n2 := 0
	for sp2 in host.ctrl.player("p2")["supplements"]:
		n2 += int(sp2["stacks"])
	check_eq(n2, 0, "p2 cannot claim p1's reward")
	check_eq(host.ctrl.pending_for("p2").size(), 1, "p2's own pick still waits")
	check(int(host.ctrl.player("p0")["scrip"]) >= 100 and int(host.ctrl.player("p1")["scrip"]) >= 100, "Scrip is per player at 100%")


func test_disconnect_bot_takes_over_then_rejoin() -> void:
	var s := make_party(3)
	var host: CoopSession = s[0]
	_to_reward(s)
	hub.leave("p2")
	tick_all(s, 0.1, 3)
	check(bool(host.ctrl.player("p2")["bot"]), "a bot takes the disconnected member's fighter")
	check_eq(host.ctrl.pending_for("p2").size(), 0, "the bot's pick was auto-chosen")
	# rejoin: reconnect the transport and ask for the fighter back
	var t2 := hub.join("p2")
	var back := CoopSession.member_join(t2, cat(), "p0", null, Profiles.default_profile("m2", "M2"))
	s[2] = back
	back.rejoin()
	for pid in ["p0", "p1"]:
		for e in host.ctrl.pending_for(pid).duplicate():
			(s[int(pid.substr(1))] as CoopSession).act("pick", {"rid": e["rid"], "choice": e["options"][0]})
	tick_all(s, 0.1, 4)
	check_eq(host.ctrl.phase(), "map", "node finished")
	check(not bool(host.ctrl.player("p2")["bot"]), "the member reclaims their fighter at the node boundary")
	check_eq(str(back.state().get("run_id", "")), str(host.ctrl.state["run_id"]), "rejoined member mirrors the run")


func test_host_departure_resumes_from_member_replica() -> void:
	var s := make_party(3)
	var host: CoopSession = s[0]
	tick_all(s, 11.0)                      # vote times out -> route chosen, fight pending
	check_eq(host.ctrl.phase(), "fight", "fight pending")
	var boundary: Dictionary = (s[1] as CoopSession).ticket.get("state", {})
	check(not boundary.is_empty(), "members hold a replica checkpoint")
	hub.leave("p0")
	tick_all([s[1], s[2]], 0.1, 2)
	check((s[1] as CoopSession).waiting_host, "members wait for the host")
	tick_all([s[1], s[2]], 30.0)
	check_eq((s[1] as CoopSession).host_id, "p0", "still waiting after 30 s")
	tick_all([s[1], s[2]], 31.0, 2)
	var new_host: CoopSession = s[1]
	check(new_host.is_host(), "the next member resumes as host")
	check_eq((s[2] as CoopSession).host_id, "p1", "the other member follows the new host")
	check_eq(str(new_host.ctrl.state["position"]), str(boundary.get("position", "")), "resumed from the last node boundary")
	check(bool(new_host.ctrl.player("p0")["bot"]), "the departed host's fighter is a bot now")
	# the run continues under the new host
	tick_all([s[1], s[2]], 11.0)
	check_eq(new_host.ctrl.phase(), "fight", "the party carries on")


func test_everyone_leaves_run_suspended_and_resumable() -> void:
	var store := RunStore.new(temp_dir("coop_store_%d" % Time.get_ticks_usec()))
	hub = LoopbackTransport.Hub.new()
	var t0 := hub.join("p0")
	var t1 := hub.join("p1")
	var host := CoopSession.host_new(t0, cat(), party_cfg(2), null, Profiles.default_profile("m0", "M0"))
	var mem := CoopSession.member_join(t1, cat(), "p0", store, Profiles.default_profile("m1", "M1"))
	tick_all([host, mem], 0.1, 2)
	hub.leave("p0")
	tick_all([mem], 61.0, 2)
	check(mem.suspended, "alone with no one to host: the run is suspended")
	var r := store.load_slot("m1", "party_%s" % host.ctrl.state["run_id"], cat())
	check(bool(r["ok"]), "the member's party save holds the run: %s" % r["error"])
	# later the original host (or anyone holding the save) resumes and invites a new member
	var hub2 := LoopbackTransport.Hub.new()
	var a := hub2.join("p0")
	var b := hub2.join("p1")
	var resumed := CoopSession.host_resume(a, cat(), r["state"])
	var joiner := CoopSession.member_join(b, cat(), "p0")
	joiner.rejoin()
	resumed.tick(0.1)
	joiner.tick(0.1)
	resumed.tick(0.1)
	check(resumed.is_host() and resumed.ctrl.phase() == "map", "resumed at the node boundary")
	check(not bool(resumed.ctrl.player("p1")["bot"]), "the invited member takes the open slot")


func test_pause_budget_per_player() -> void:
	var s := make_party(2)
	var host: CoopSession = s[0]
	check(not host.request_pause("p1"), "no ref timeout outside fights")
	tick_all(s, 11.0)
	check_eq(host.ctrl.phase(), "fight", "in a fight")
	(s[1] as CoopSession).act("pause", {})
	tick_all(s, 0.1, 2)
	check(host.is_paused(), "ref timeout called")
	tick_all(s, 31.0)
	check(not host.is_paused(), "the timeout ends when the 30 s budget runs out")
	check(not host.request_pause("p1"), "budget spent for this run")
	check(host.request_pause("p0"), "other players keep their own budget")


func test_progression_credited_per_player() -> void:
	var s := make_party(2, {"variant": "fight_camp"})
	var host: CoopSession = s[0]
	var reports := []
	for m in s:
		(m as CoopSession).run_finished.connect(func(rep): reports.append(rep))
	# finish the run quickly (synthetic results) on the host
	var guard := 0
	while not host.ctrl.is_over() and guard < 400:
		guard += 1
		if host.ctrl.phase() == "map":
			tick_all(s, 11.0)
		elif host.ctrl.phase() == "fight":
			host.complete_fight(fake_result(host.ctrl))
		else:
			CampaignAutoPilot.settle(host.ctrl, ["p0", "p1"])
			host._after_change("test")
		tick_all(s, 0.1)
	check_eq(host.ctrl.phase(), "victory", "party run finished")
	tick_all(s, 0.1, 3)
	check_eq(reports.size(), 2, "each member credited their own profile")
	var p0_clout := int((s[0] as CoopSession).profile["camp"]["clout"])
	var p1_clout := int((s[1] as CoopSession).profile["camp"]["clout"])
	check(p0_clout > 0 and p1_clout > 0, "Clout goes to each member's own profile")
	(s[1] as CoopSession)._credited = false
	(s[1] as CoopSession)._credit_self(host.ctrl.state)
	check_eq(int((s[1] as CoopSession).profile["camp"]["clout"]), p1_clout, "a resent run_end does not pay twice")


func test_tag_team_format() -> void:
	var cfg := party_cfg(2, {"coop_format": "tag"})
	var ctrl := RunController.start_run(cat(), cfg)
	check_eq(RunState.party_mode(ctrl.state), "tag", "tag-team is a run setting")
	var plan := EncounterBuilder.plan(cat(), ctrl.state, "boss_a1", {"node_id": "x"})
	check_near(float(plan["enemies"][0]["hp_mult"]), 1.3, 0.001, "tag-team boss HP x1.3")
	var dock := EncounterBuilder.plan(cat(), ctrl.state, "enc_a1_dock_rats", {"node_id": "x"})
	check_eq((dock["enemies"] as Array).size(), 4, "tag-team: enemy count x1")
	ctrl.choose_node(str(ctrl.available_nodes()[0]), "p0")
	var built := ctrl.match_config({"player_kinds": {"p0": "bot", "p1": "bot"}})
	var sv := fresh_world()
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	sim.setup(built["config"])
	var mode: CampaignMatchMode = sim.mode
	var active := 0
	for f in sim.fighters:
		if mode.is_party(f) and not mode.is_parked(f):
			active += 1
	check_eq(active, 1, "one active party fighter; the partner waits on the apron")
