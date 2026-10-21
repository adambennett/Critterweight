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


# --- review regressions ----------------------------------------------------------------------------

## A state the host could claim at the end: Dose 10, victory and 50,000 Clout each.
func _forged_victory(st: Dictionary) -> Dictionary:
	var forged: Dictionary = st.duplicate(true)
	forged["phase"] = "victory"
	forged["dose"] = 10
	forged["node"] = {}
	forged["result"] = {"victory": true, "abandoned": false, "act": 3, "node": "", "elapsed": 1.0, "dose": 10, "difficulty": "amateur",
		"variant": "off_the_street", "mode": "campaign", "custom": false, "seed_text": str(st.get("seed_text", "")), "players": {}, "stats": {}}
	for p in forged["players"]:
		p["clout"] = 50000
	return forged


## Plays the host's run to its end with synthetic fight results (members follow over loopback).
func _finish_party_run(s: Array, pids: Array) -> void:
	var host: CoopSession = s[0]
	var guard := 0
	while not host.ctrl.is_over() and guard < 400:
		guard += 1
		if host.ctrl.phase() == "map":
			tick_all(s, 11.0)
		elif host.ctrl.phase() == "fight":
			host.complete_fight(fake_result(host.ctrl))
		else:
			CampaignAutoPilot.settle(host.ctrl, pids)
			host._after_change("test")
		tick_all(s, 0.1)
	tick_all(s, 0.1, 3)


## Turns the next reachable node into a group event, and votes the party into it.
func _enter_group_event(s: Array, event_id: String) -> void:
	var host: CoopSession = s[0]
	var nid := str(host.ctrl.available_nodes()[0])
	var n := RunState.node(host.ctrl.state, nid)
	n["type"] = "event"
	n["event"] = event_id
	n["encounter"] = ""
	n.erase("hidden")
	for m in s:
		(m as CoopSession).act("vote", {"node": nid})
	tick_all(s, 0.1, 2)


## Review #3: host-only messages are accepted only from the host (the transport's peer id): a
## member forging run_end / ticket / run_state / host_changed changes nothing for the others.
func test_members_ignore_host_messages_from_other_members() -> void:
	var s := make_party(3)
	var host: CoopSession = s[0]
	var victim: CoopSession = s[1]
	var attacker: CoopSession = s[2]
	var forged := _forged_victory(host.ctrl.state)
	var before := Saves.checksum(victim.profile)
	var position := str(host.ctrl.state.get("position", ""))
	attacker.transport.send("p1", "run_end", {"state": forged})
	attacker.transport.send("p1", "ticket", RunStore.make_ticket(forged, "p2"))
	attacker.transport.send("p1", "run_state", {"state": forged, "host": "p2", "reason": "forged"})
	attacker.transport.send("p1", "host_changed", {"host": "p2"})
	tick_all(s, 0.1, 3)
	check(not victim._credited, "a forged run_end from a member is not credited")
	check_eq(Saves.checksum(victim.profile), before, "the victim's profile is untouched (no Clout, ladder, cosmetics)")
	check_eq(victim.host_id, "p0", "a member cannot make itself host")
	check(str(victim.ticket.get("state", {}).get("phase", "map")) != "victory", "a forged ticket is not kept")
	check_eq(str(victim.state().get("phase", "")), host.ctrl.phase(), "the mirror still shows the host's run")
	check_eq(str(victim.state().get("position", "")), position, "unchanged")


## Review #3: even from the host, a checkpoint or final result must be this party's run and must
## follow from its own decision log before a member keeps or credits it.
func test_host_results_must_follow_their_log() -> void:
	var s := make_party(2)
	var host: CoopSession = s[0]
	var mem: CoopSession = s[1]
	var forged := _forged_victory(host.ctrl.state)
	var notes := []
	mem.notice.connect(func(t: String) -> void: notes.append(t))
	host.transport.send("p1", "ticket", RunStore.make_ticket(forged, "p0"))
	host.transport.send("p1", "run_end", {"state": forged})
	tick_all(s, 0.1, 2)
	check(not mem._credited, "a tampered final result is not credited")
	check(not str(mem.ticket.get("state", {}).get("phase", "map")) in ["victory", "defeat"], "a tampered checkpoint is not kept")
	check(notes.any(func(t): return str(t).contains("not credited")), "the member is told why (%s)" % str(notes))
	# a state of another run (other id/seed) is not mirrored either
	var other := RunController.start_run(cat(), party_cfg(2, {"seed": 999, "created_at": 8})).state
	host.transport.send("p1", "run_state", {"state": other, "host": "p0", "reason": "x"})
	tick_all(s, 0.1)
	check_eq(str(mem.state().get("run_id", "")), str(host.ctrl.state["run_id"]), "another run's state is ignored")
	# the honest end of the run is still credited, from the rebuilt run
	_finish_party_run(s, ["p0", "p1"])
	check_eq(host.ctrl.phase(), "victory", "party run finished")
	check(mem._credited, "the honest result is credited")
	check_eq(int(mem.profile["records"]["runs"]["off_the_street"]["clears"]), 1, "one clear for the member")


## Review #3: host_changed counts only from the successor the election rule picks (next
## connected member in Captain order) — and only once the host is really gone.
func test_host_change_only_from_the_elected_successor() -> void:
	var s := make_party(3)
	var host: CoopSession = s[0]
	var p1: CoopSession = s[1]
	var p2: CoopSession = s[2]
	tick_all(s, 11.0)
	check_eq(host.ctrl.phase(), "fight", "a node boundary passed: members hold a checkpoint")
	# p2 is not next after p0 (p1 is): ignored
	p2.transport.send("p1", "host_changed", {"host": "p2"})
	tick_all(s, 0.1)
	check_eq(p1.host_id, "p0", "a claim from the wrong member is ignored")
	# p1 claims while p0 is still connected: held, not followed
	p1.transport.send("p2", "host_changed", {"host": "p1"})
	tick_all(s, 0.1)
	check_eq(p2.host_id, "p0", "no host change while the host is still here")
	# p0 really leaves: the held claim of the rightful successor is followed at once
	hub.leave("p0")
	tick_all([p1, p2], 0.1, 2)
	check_eq(p2.host_id, "p1", "the successor's claim is followed once the host is gone")
	check(not p2.waiting_host, "no 60 s wait needed")


## Review #5: a group event's vote offers only what every member can pay; a pick that still
## fails is dropped and the error broadcast; idle parties resolve too — never a loop.
func test_group_event_vote_never_loops() -> void:
	var s := make_party(2)
	var host: CoopSession = s[0]
	host.ctrl.player("p0")["scrip"] = 200
	host.ctrl.player("p1")["scrip"] = 20
	_enter_group_event(s, "evt_the_belt")
	check_eq(host.ctrl.phase(), "event", "in the group event")
	tick_all(s, 0.1)
	check(host.event_vote != null, "the party votes")
	if host.event_vote == null:
		return
	check_eq(host.event_vote.options, ["window"], "Buy (50 Scrip each) is not on the ballot: Member 1 has 20")
	# nobody votes: the timer resolves it (the deterministic pick can only be what the party can pay)
	tick_all(s, 11.0, 2)
	check(host.ctrl.phase() != "event", "the idle party moved on")
	# a pick that fails at resolution (Scrip spent since the vote opened) is dropped and reported
	var s2 := make_party(2)
	var h2: CoopSession = s2[0]
	h2.ctrl.player("p0")["scrip"] = 200
	h2.ctrl.player("p1")["scrip"] = 200
	_enter_group_event(s2, "evt_the_belt")
	tick_all(s2, 0.1)
	check(h2.event_vote != null and (h2.event_vote.options as Array).has("buy"), "Buy is on the ballot while everyone can pay")
	var notes := []
	(s2[1] as CoopSession).notice.connect(func(t: String) -> void: notes.append(t))
	h2.act("event_choice", {"choice": "buy"})
	h2.ctrl.player("p1")["scrip"] = 10
	(s2[1] as CoopSession).act("event_choice", {"choice": "buy"})
	tick_all(s2, 0.1, 2)
	check_eq(h2.ctrl.phase(), "event", "the failed pick changed nothing")
	check(notes.any(func(t): return str(t).contains("could not be done")), "every member hears why (%s)" % str(notes))
	tick_all(s2, 0.1)
	check(h2.event_vote != null and not (h2.event_vote.options as Array).has("buy"), "the failed pick is not offered again")
	var rounds := 0
	while h2.ctrl.phase() == "event" and rounds < 4:
		rounds += 1
		tick_all(s2, 11.0)
	check(h2.ctrl.phase() != "event", "the next vote resolves")
	var chosen := ""
	for e in h2.ctrl.state["log"]:
		if str(e["k"]) == "event":
			chosen = str(e["d"]["choice"])
	check_eq(chosen, "window", "with what the party could pay")


## Review #9: one member's choice on a GROUP event is a vote, never the decision.
func test_member_choice_on_group_event_is_a_vote() -> void:
	var s := make_party(3)
	var host: CoopSession = s[0]
	var nid := str(host.ctrl.available_nodes()[0])
	var n := RunState.node(host.ctrl.state, nid)
	n["type"] = "event"
	n["event"] = "evt_lost_dog"
	n["encounter"] = ""
	n.erase("hidden")
	for i in 3:
		(s[i] as CoopSession).act("vote", {"node": nid})
	host.tick(0.1)                    # the route vote resolves: the party is in the event
	(s[2] as CoopSession).tick(0.0)
	check_eq(str((s[2] as CoopSession).state().get("phase", "")), "event", "the member sees the group event")
	(s[2] as CoopSession).act("event_choice", {"choice": "feed"})
	host.tick(0.1)                    # arrives before the host opened the event vote itself
	check_eq(host.ctrl.phase(), "event", "one member did not decide for the party")
	check(host.event_vote != null and str(host.event_vote.votes.get("p2", "")) == "feed", "it counted as p2's vote")
	host.act("event_choice", {"choice": "pet"})
	(s[1] as CoopSession).act("event_choice", {"choice": "pet"})
	tick_all(s, 0.1, 2)
	var chosen := ""
	for e in host.ctrl.state["log"]:
		if str(e["k"]) == "event":
			chosen = str(e["d"]["choice"])
	check_eq(chosen, "pet", "the majority decided")


## Review #11: party slots are cleared when the run ends (they are no suspended runs then), on
## the host and on every member.
func test_party_slots_cleared_at_run_end() -> void:
	var host_store := RunStore.new(temp_dir("coop_host_%d" % Time.get_ticks_usec()))
	var mem_store := RunStore.new(temp_dir("coop_mem_%d" % Time.get_ticks_usec()))
	hub = LoopbackTransport.Hub.new()
	var t0 := hub.join("p0")
	var t1 := hub.join("p1")
	var host := CoopSession.host_new(t0, cat(), party_cfg(2), host_store, Profiles.default_profile("m0", "M0"))
	var mem := CoopSession.member_join(t1, cat(), "p0", mem_store, Profiles.default_profile("m1", "M1"))
	var s := [host, mem]
	tick_all(s, 0.1, 2)
	var slot := RunStore.slot_for(host.ctrl.state)
	tick_all(s, 11.0)
	check(bool(host_store.load_slot("m0", slot, cat())["exists"]), "the host saves the party run while it goes on")
	check(bool(mem_store.load_slot("m1", slot, cat())["ok"]), "the member keeps a verified replica checkpoint")
	_finish_party_run(s, ["p0", "p1"])
	check(host.ctrl.is_over(), "the run ended")
	check(mem._credited, "the member was credited")
	check(not bool(host_store.load_slot("m0", slot, cat())["exists"]), "the host's party slot is cleared at the end")
	check(not bool(mem_store.load_slot("m1", slot, cat())["exists"]), "the member's party slot is cleared at the end")
	check(host_store.list("m0", cat()).is_empty() and mem_store.list("m1", cat()).is_empty(), "nothing left to resume")


## Review #4: a co-op host can only deal a Dose its own profile has unlocked.
func test_host_dose_clamped_to_own_ladder() -> void:
	hub = LoopbackTransport.Hub.new()
	var host := CoopSession.host_new(hub.join("p0"), cat(), party_cfg(2, {"dose": 7}), null, Profiles.default_profile("m0", "M0"))
	check_eq(int(host.ctrl.state["dose"]), 0, "a closed Dosage deals the base card")


# ---------------------------------------------------------------------------------------------
# v0.9.18 moves: learn / equip / drill are member intents (docs/CAMPAIGN_SYSTEMS.md "Moves in runs")
# ---------------------------------------------------------------------------------------------

const MOVES_PARTY := [{"id": "p0", "name": "A", "profile_id": "m0", "fighter": "f_stoke"}, {"id": "p1", "name": "B", "profile_id": "m1", "fighter": "f_stoke"}]
const BRAWLER := ["ember_jab", "furnace_haymaker", "flare_rush", "cinder_shot"]


## The shortest route to the act's first `t` stop with no elite or boss on the way (an elite's
## move tutor would teach the one move Stoke has left to learn).
func _route_to(m: Dictionary, t: String) -> Array:
	var best := []
	for p in ActMap.all_paths(m):
		var pa: Array = p
		for i in pa.size():
			var ty := str(ActMap.node(m, str(pa[i])).get("type", ""))
			if ty == t:
				if best.is_empty() or i + 1 < best.size():
					best = pa.slice(0, i + 1)
				break
			if ty in ["elite", "boss"]:
				break
	return best


func test_members_learn_equip_and_drill_through_the_host() -> void:
	var seed_value := 0
	for sd in range(1, 600):
		var probe := run_cfg("f_stoke", {"seed": sd})
		probe["players"] = MOVES_PARTY.duplicate(true)
		if not _route_to(RunState.act_map(RunState.create(cat(), probe), 1), "rest").is_empty():
			seed_value = sd
			break
	check(seed_value > 0, "precondition: a party card with a rest stop")
	var cfg := run_cfg("f_stoke", {"seed": seed_value, "created_at": 9})
	cfg["players"] = MOVES_PARTY.duplicate(true)
	hub = LoopbackTransport.Hub.new()
	var host := CoopSession.host_new(hub.join("p0"), cat(), cfg, null, Profiles.default_profile("m0", "M0"))
	var mem := CoopSession.member_join(hub.join("p1"), cat(), "p0", null, Profiles.default_profile("m1", "M1"))
	var s := [host, mem]
	tick_all(s, 0.1, 2)
	# equip at the map: the member's intent becomes the member's decision in the party's log
	check(mem.act("equip", {"loadout": BRAWLER}), "the member sends an equip")
	tick_all(s, 0.1, 3)
	check_eq(RunMoves.moves_of(host.ctrl.player("p1"))["equipped"], BRAWLER, "the host applied it to the member's fighter")
	check_eq(RunMoves.moves_of(host.ctrl.player("p0"))["equipped"], (RunMoves.info(cat(), "f_stoke")["loadouts"]["furnace"] as Dictionary)["moves"], "and only to theirs")
	var eq := []
	for e in host.ctrl.state["log"]:
		if str(e["k"]) == "equip":
			eq.append(e)
	check(eq.size() == 1 and str(eq[0]["p"]) == "p1", "logged as the member's decision")
	check_eq(int(mem.ticket.get("log_size", 0)), (host.ctrl.state["log"] as Array).size(), "the member accepted (verified) the checkpoint with it")
	mem.act("equip", {"loadout": ["ember_jab", "fire_spin"]})       # not learned
	tick_all(s, 0.1, 2)
	check_eq(RunMoves.moves_of(host.ctrl.player("p1"))["equipped"], BRAWLER, "an invalid equip is refused by the host")
	check(mem.last_error.contains("not learned"), "and the member is told why (%s)" % mem.last_error)
	# the party votes its way to the rest stop
	var path := _route_to(RunState.current_map(host.ctrl.state), "rest")
	for j in path.size():
		host.act("vote", {"node": str(path[j])})
		mem.act("vote", {"node": str(path[j])})
		tick_all(s, 0.1, 3)
		if j == path.size() - 1:
			break
		var guard := 0
		while host.ctrl.phase() != "map" and not host.ctrl.is_over() and guard < 20:
			guard += 1
			if host.ctrl.phase() == "fight":
				host.complete_fight(fake_result(host.ctrl))
			else:
				settle_node(host.ctrl)          # first options, leave shops, patch up: nothing learned on the way
				host._after_change("test")
			tick_all(s, 0.1, 2)
	check_eq(host.ctrl.phase(), "rest", "the party reached the rest stop")
	if host.ctrl.phase() != "rest":
		return
	host.act("rest", {"option": "learn"})
	mem.act("rest", {"option": "drill"})
	tick_all(s, 0.1, 3)
	var lp := host.ctrl.pending_for("p0")
	var dp := host.ctrl.pending_for("p1")
	check(lp.size() == 1 and dp.size() == 1, "a move pick for the host, a drill pick for the member")
	if lp.is_empty() or dp.is_empty():
		return
	# (the pending lists are live: picks leave them when claimed)
	var taught := str(lp[0]["options"][0])
	var learn_src := "pick:" + str(lp[0]["rid"])
	var md := RunMoves.split_drill(str(dp[0]["options"][0]))
	var drill_src := "pick:" + str(dp[0]["rid"])
	check(host.act("learn", {"move": taught, "source": learn_src}), "the host learns: %s" % host.last_error)
	mem.act("drill", {"move": str(md[0]), "style": str(md[1]), "source": drill_src})
	mem.act("drill", {"move": str(md[0]), "style": str(md[1]), "source": drill_src})    # resent
	tick_all(s, 0.1, 3)
	check((RunMoves.moves_of(host.ctrl.player("p0"))["learned"] as Array).has(taught), "the host learned the move")
	check_eq(str((RunMoves.moves_of(host.ctrl.player("p1"))["drilled"] as Dictionary).get(str(md[0]), "")), str(md[1]), "the member drilled the style")
	var drills := 0
	for e2 in host.ctrl.state["log"]:
		if str(e2["k"]) == "drill":
			drills += 1
	check_eq(drills, 1, "once, though the intent was resent")
	check_eq(host.ctrl.phase(), "map", "the rest stop is done")
	check_eq(int(mem.ticket.get("log_size", 0)), (host.ctrl.state["log"] as Array).size(), "the member's replica verified learn, equip and drill")
	check_eq(RunMoves.moves_of(mem.state()["players"][1])["drilled"], RunMoves.moves_of(host.ctrl.player("p1"))["drilled"], "and mirrors them")
	check(bool(RunController.verify(cat(), RunStore.json_stable(host.ctrl.state))["ok"]), "the party run verifies as a whole")
