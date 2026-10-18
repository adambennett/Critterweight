extends TestCase
## COOP-01..06 / NET-05: online co-op party runs through the REAL networking path and the REAL UI,
## with independent processes - a listen host and a member (net_test_client.gd --party-ui: the
## lobby screen, OnlineFlow, CoopFlow and the campaign screens, driven by PartyPilot pressing
## their buttons; fights played with scripted controller input). All traffic is LOOPBACK
## (127.0.0.1) on one machine: these results prove the protocol, authority and session flows, not
## off-machine internet connectivity (docs/NETWORKING.md "NAT and port forwarding").
##   * Off the Street, simultaneous format: fights on the session, a ref timeout called from the
##     member's pause menu, per-player picks, an event the member decides, a shop where only the
##     host buys, a member who drops mid-fight and reconnects, the host forfeiting a fight, the
##     run's end credited once to each member's own profile.
##   * Fight Camp, tag-team format: each member's own Cannery levels, tag-ins / assists / cheers
##     from the bench, the host suspending the run, then a NEW session (new processes) resuming
##     it from the party saves through the lobby's seats - an event, rest for both, the next fight -
##     and the host leaving the session mid-fight (the member is told why and that the run is
##     saved; the run stays at that fight).
## Runs use the Sparring difficulty (a real difficulty: softer enemies) and fixed routes (exact map
## stops of a seed) whose first fight is a minion fight the scripted inputs win; a lost fight would
## end the run before the stops under test.

const U := preload("res://src/test/net/net_test_util.gd")

var u = null


func after_each() -> void:
	if u:
		u.kill_all()
	u = null


func _party(d: Dictionary) -> Dictionary:
	return d.get("party_ui", {})


func _log_has(p: Dictionary, k: String, who: String) -> bool:
	for e in p.get("log", []):
		if str(e.get("k", "")) == k and str(e.get("p", "")) == who:
			return true
	return false


func _no_child_errors(pids: Array) -> void:
	for pid in pids:
		var errs: Array = u.errors(pid, ["[ERROR] app: screen"])
		check(errs.is_empty(), "process %d printed no engine/script errors: %s" % [pid, str(errs.slice(0, 5))])


func _host_args(port: int, name_: String, extra: Array, result_name := "") -> Array:
	var a: Array = ["--net-client", "--net-host", "--port", port, "--name", name_, "--script", "aggressive", "--party-ui",
		"--result", u.result_path(result_name if result_name != "" else name_)]
	a.append_array(extra)
	return a


## Cannery levels as whole numbers (JSON reads them back as floats).
static func _levels(d) -> Dictionary:
	var out := {}
	if typeof(d) == TYPE_DICTIONARY:
		for k in d:
			out[str(k)] = int(d[k])
	return out


## Three humans in separate processes (host + two members), Off the Street, simultaneous: everyone
## seated with their own fighter, a fight where three human-driven fighters fight together, a route
## vote split 2-1 (Ben wants a fight at row 2, the host and Ann the event) that the majority
## decides, and the run's end credited once to each of the three profiles.
func test_party_run_three_players_majority_route() -> void:
	await _vote_party("party_three", [["Ann", "f_jitters", false], ["Ben", "f_dredge", true]], "the majority")


## Four humans: the row-2 vote splits 2-2 (the host and Ann the event, Ben and Cal a fight) and the
## Captain - the host in Act 1 - breaks the tie for his pick.
func test_party_run_four_players_captain_breaks_tie() -> void:
	await _vote_party("party_four", [["Ann", "f_jitters", false], ["Ben", "f_dredge", true], ["Cal", "f_gusto", true]],
		"the Captain's tie-break", 543, "a1r1l2,a1r2l3,a1r3l2,a1r4l3")


## A party run with the host (Stoke) and `members` ([name, fighter, wants_a_fight_at_row_2]) on seed
## 193 for three players; four use 543 (Dock Rats | Commission Hearing | shop | fight). The host forfeits fight 2
## to end it. The host's route takes the event at row 2, so `why` says what must carry his pick.
func _vote_party(label: String, members: Array, why: String, seed_value := 193, route := "a1r1l0,a1r2l1,a1r3l1,a1r4l3") -> void:
	u = U.new(self, label)
	var port: int = u.base_port
	var route_nodes := route.split(",")
	var alternate := route_nodes.duplicate()
	alternate[1] = "fight"
	var fight_route := ",".join(alternate)
	if members.size() == 3:
		# Roster-dependent event eligibility changes the content shuffle. Seed 193's four-player
		# opening is Timed Scrap; use a verified Dock Rats route so this remains a voting test.
		var players := [{"fighter": "f_stoke"}]
		for member in members:
			players.append({"fighter": member[1]})
		var fixture := RunState.create(CampaignFlow.make_catalog(false), {"seed": seed_value, "players": players, "variant": "off_the_street", "difficulty": "sparring"})
		var nodes: Dictionary = fixture["acts"][0]["nodes"]
		check_eq(nodes[route_nodes[0]]["encounter"], "enc_a1_dock_rats", "voting fixture starts with the intended untimed minion fight")
		check_eq(nodes[route_nodes[1]]["event"], "evt_commission_hearing", "voting fixture reaches its personal event")
		for i in range(1, route_nodes.size()):
			check(nodes[route_nodes[i - 1]]["edges"].has(route_nodes[i]), "fixture route is connected")
		if not _failures.is_empty():
			return
	var budget := U.SERVER_READY_S + 360.0
	var host: int = u.spawn("host", _host_args(port, "Hosty", ["--creature", "f_stoke", "--party-new", "off_the_street:simultaneous",
		"--party-seed", str(seed_value), "--party-difficulty", "sparring", "--party-route", route, "--party-pick", "first", "--party-shop", "leave",
		"--party-event-wait", "4", "--party-forfeit-fight", "2", "--party-forfeit-after", "8", "--quit-after", str(budget + 60.0)]))
	check(host > 0, "host process spawned")
	var r0: Dictionary = await u.wait_json(u.result_path("Hosty"), func(d: Dictionary) -> bool: return bool(d.get("connected", false)), U.SERVER_READY_S)
	check(bool(r0.get("connected", false)), "the host's session is up")
	var pids := [host]
	for m in members:
		pids.append(u.spawn(str(m[0]).to_lower(), u.client_args(port, str(m[0]), "aggressive", ["--creature", str(m[1]), "--party-ui",
			"--party-route", fight_route if bool(m[2]) else route, "--party-pick", "first", "--party-shop", "leave", "--quit-after", str(budget)])))
	var results := []
	for m in members:
		results.append(_party(await u.wait_json(u.result_path(str(m[0])), func(d: Dictionary) -> bool: return bool(d.get("done", false)), budget)))
	var ph := _party(await u.wait_json(u.result_path("Hosty"), func(d: Dictionary) -> bool: return bool(d.get("done", false)), 60.0))
	var n := members.size() + 1
	check_eq(str(ph.get("deal_error", "?")), "", "the host dealt the run from the lobby")
	var want_fighters := ["f_stoke"]
	for m in members:
		want_fighters.append(str(m[1]))
	# seats follow the order the members joined in (they start together), so compare as a set
	var dealt: Array = (ph.get("dealt_players", []) as Array).map(func(p: Dictionary) -> String: return str(p.get("fighter", "")))
	dealt.sort()
	want_fighters.sort()
	check_eq(dealt, want_fighters, "%d players, each with their lobby fighter" % n)
	check_eq(ph.get("started_with_missing", ["?"]), [], "started once every member had a seat")
	var fights: Array = ph.get("fights", [])
	check(not fights.is_empty(), "fights were played on the session")
	if not fights.is_empty():
		var kinds: Array = (fights[0].get("fighters", []) as Array).map(func(f: Dictionary) -> String: return str(f.get("kind", "")))
		var want_kinds := ["player"]
		for m in members:
			want_kinds.append("net")
		check(kinds.slice(0, n) == want_kinds, "%d human-driven fighters: the host's local, each member's from their input stream: %s" % [n, str(kinds)])
	var st: Dictionary = ph.get("state", {})
	check(int(st.get("fights_won", 0)) >= 1, "the party won its first fight (%s)" % str(st))
	var path: Array = st.get("path", [])
	check(path.size() >= 2 and str(path[1]) == route_nodes[1], "%s took the host's stop at row 2: %s" % [why, str(path)])
	for k in members.size():
		if not bool(members[k][2]):
			continue
		var votes: Array = (results[k].get("decisions", []) as Array).filter(func(d: Dictionary) -> bool:
			return str(d.get("kind", "")) == "vote" and str(d.get("position", "")) == route_nodes[0])
		var row2 := str(votes[0].get("detail", "")) if not votes.is_empty() else ""
		check(row2 != "" and not row2.begins_with(route_nodes[1]), "%s voted for another stop at row 2: %s" % [members[k][0], row2])
	check(bool(st.get("over", false)), "the run ended (%s)" % str(st.get("phase", "")))
	for p in [ph] + results:
		var who := str(p.get("role", "?")) + " " + str(p.get("seat", ""))
		check_eq(str(p.get("top", "")), "run_summary", "%s: the run summary" % who)
		check_eq(int(p.get("credited_on_disk", -1)), 1, "%s: the run credited once to their own profile (on disk)" % who)
	for k in members.size():
		check_eq(int(results[k].get("state", {}).get("log_size", -1)), int(st.get("log_size", -2)), "%s's replica ends with the host's run" % members[k][0])
	_no_child_errors(pids)


## Off the Street, simultaneous allied combat (the default format).
func test_party_run_off_the_street_simultaneous() -> void:
	u = U.new(self, "party_ots")
	var port: int = u.base_port
	# seed 193: Dock Rats (minions) | Sponsor Read (a personal event) | the shop | Hot Pipes
	var route := "a1r1l0,a1r2l1,a1r3l1,a1r4l3"
	var budget := U.SERVER_READY_S + 360.0
	var host: int = u.spawn("host", _host_args(port, "Hosty", ["--creature", "f_stoke", "--party-new", "off_the_street:simultaneous",
		"--party-seed", "193", "--party-difficulty", "sparring", "--party-route", route, "--party-pick", "first", "--party-shop", "buy",
		"--party-event-wait", "4", "--party-forfeit-fight", "2", "--party-forfeit-after", "8", "--quit-after", str(budget + 60.0)]))
	check(host > 0, "host process spawned")
	var r0: Dictionary = await u.wait_json(u.result_path("Hosty"), func(d: Dictionary) -> bool: return bool(d.get("connected", false)), U.SERVER_READY_S)
	check(bool(r0.get("connected", false)), "the host's session is up")
	var ann: int = u.spawn("ann", u.client_args(port, "Ann", "aggressive", ["--creature", "f_jitters", "--party-ui", "--party-route", route,
		"--party-pick", "last", "--party-shop", "leave", "--party-ref-timeout-fight", "1", "--party-drop-in-fight", "2", "--quit-after", str(budget)]))
	# Ann drops mid-fight in her second fight (crash / pulled cable): her process ends
	var ra: Dictionary = await u.wait_json(u.result_path("Ann"), func(d: Dictionary) -> bool: return bool(d.get("done", false)), budget)
	var pa := _party(ra)
	check(str(ra.get("exit_reason", "")).begins_with("disconnected"), "Ann's first process dropped its connection: %s" % str(ra.get("exit_reason", "")))
	var notes := str(pa.get("notes", []))
	check(notes.contains("dropping the connection"), "in a fight, as scripted: %s" % notes)
	var seat := str(pa.get("seat", ""))
	check(seat != "" and seat != "1", "Ann played seat %s" % seat)
	# she comes back with her rejoin token (same session player, the seat kept for her)
	var ann2: int = u.spawn("ann", u.client_args(port, "Ann", "aggressive", ["--creature", "f_jitters", "--party-ui", "--party-route", route,
		"--party-pick", "last", "--party-shop", "leave", "--token", str(ra.get("token_hex", "")), "--quit-after", str(budget)], "Ann2"))
	var rb: Dictionary = await u.wait_json(u.result_path("Ann2"), func(d: Dictionary) -> bool: return bool(d.get("done", false)), budget)
	var rh: Dictionary = await u.wait_json(u.result_path("Hosty"), func(d: Dictionary) -> bool: return bool(d.get("done", false)), 60.0)
	var ph := _party(rh)
	var pb := _party(rb)
	# the deal: both players with their lobby fighters, started with everyone seated
	check_eq(str(ph.get("deal_error", "?")), "", "the host dealt the run from the lobby")
	var dealt: Array = ph.get("dealt_players", [])
	check_eq(dealt.map(func(p: Dictionary) -> String: return str(p.get("fighter", ""))), ["f_stoke", "f_jitters"], "each with their lobby fighter")
	check_eq(ph.get("started_with_missing", ["?"]), [], "started once Ann had her seat")
	# fight 1: a networked campaign match, both humans driving their own fighters
	var fights: Array = ph.get("fights", [])
	check(not fights.is_empty(), "fights were played on the session")
	if not fights.is_empty():
		var f1: Dictionary = fights[0]
		check_eq(str(f1.get("campaign", {}).get("format", "")), "coop", "the first fight: simultaneous allied combat")
		var kinds: Array = (f1.get("fighters", []) as Array).map(func(f: Dictionary) -> String: return str(f.get("kind", "")))
		check(kinds.slice(0, 2) == ["player", "net"], "the host's fighter local, Ann's from her input stream: %s" % str(kinds.slice(0, 3)))
	var st: Dictionary = ph.get("state", {})
	check(int(st.get("fights_won", 0)) >= 1, "the party won its first fight (%s)" % str(st))
	# pause rules: Ann's ref timeout (her pause menu) froze the host's match for everyone, from her budget
	var anotes := str(pa.get("notes", []))
	check(anotes.contains("calling a ref timeout in fight 1: pressed"), "Ann called a ref timeout from her pause menu in the first fight: %s" % anotes)
	check(anotes.contains("ending my ref timeout: pressed"), "and ended it early from the same menu")
	check(bool(ph.get("frozen_seen", false)), "the host's match froze")
	check(str(ph.get("ref_banner", "")).contains("called by Ann"), "the host's screen named the caller: '%s'" % str(ph.get("ref_banner", "")))
	check(str(pa.get("ref_banner", "")).contains("REF TIMEOUT"), "Ann's screen showed it too: '%s'" % str(pa.get("ref_banner", "")))
	var left := float((ph.get("pause_budget", {}) as Dictionary).get(seat, 30.0))
	check(left < 30.0 and left > 20.0, "her 30 s budget went down by the timeout (%.1f s left)" % left)
	# per-player decisions through the host's authority
	check(_log_has(ph, "claim", "1") and _log_has(ph, "claim", seat), "both picked their own rewards")
	check(_log_has(ph, "event", seat), "Ann answered the event for the party (the host waited): %s" % str(ph.get("log", []).map(func(e): return "%s/%s" % [e.k, e.p])))
	check(_log_has(ph, "buy", "1"), "the host bought at the shop")
	check(_log_has(ph, "leave", seat) and not _log_has(ph, "buy", seat), "Ann left the shop without buying")
	var kinds_done: Array = (ph.get("decisions", []) as Array).map(func(e: Dictionary) -> String: return str(e.get("kind", "")))
	check(kinds_done.has("buy") and kinds_done.has("leave_shop"), "through the host's own shop screen: %s" % str(kinds_done))
	# the rejoined member: her fighter back in the running fight, then the rest of the run
	var bf: Array = pb.get("fights", [])
	check(bf.any(func(f: Dictionary) -> bool: return int(f.get("you", -1)) >= 0), "after reconnecting Ann drove a fighter again: %s" % str(bf))
	check_eq(int(rb.get("player_id", -1)), int(ra.get("player_id", -2)), "the same session player (rejoin token)")
	check(str(u.out(host)).contains("rejoined"), "the host saw her rejoin")
	# the end: the host forfeited a fight (pause menu), the run is over, each member credited once
	check(str(ph.get("notes", [])).contains("forfeiting fight 2"), "the host forfeited the second fight")
	check(bool(st.get("over", false)) and str(st.get("phase", "")) == "defeat", "a lost fight ends the run (%s)" % str(st.get("phase", "")))
	check_eq(str(ph.get("top", "")), "run_summary", "the host's run summary")
	check_eq(str(pb.get("top", "")), "run_summary", "Ann's run summary")
	for p in [ph, pb]:
		var who := str(p.get("role", "?"))
		check_eq(int(p.get("credited_on_disk", -1)), 1, "%s: the run credited once to their own profile (on disk)" % who)
		check_eq(int(p.get("history_on_disk", -1)), 1, "%s: one history entry" % who)
		check(not bool(p.get("report", {}).get("duplicate", true)), "%s: a fresh credit report" % who)
		check(not bool(p.get("party_save", true)), "%s: the finished run's party save is cleared" % who)
	check_eq(int(pb.get("state", {}).get("log_size", -1)), int(st.get("log_size", -2)), "Ann's replica ends with the host's run")
	_no_child_errors([host, ann, ann2])


## Fight Camp, tag-team format; the run is suspended and resumed in a new session through the lobby,
## and that session ends when the host leaves mid-fight.
func test_party_run_fight_camp_tag_saved_and_resumed() -> void:
	u = U.new(self, "party_camp")
	var port: int = u.base_port
	var budget := U.SERVER_READY_S + 300.0
	# seed 4: Hot Pipes | Press Conference (a personal event) | rest | Timed Scrap
	var common := ["--party-route", "a1r1l0,a1r2l2,a1r3l3,a1r4l2"]
	var host: int = u.spawn("host", _host_args(port, "Hosty", ["--creature", "f_stoke", "--party-new", "fight_camp:tag", "--party-seed", "4",
		"--party-difficulty", "sparring", "--party-suspend-after", "1", "--party-meta", "meta_heavy_bag=1", "--quit-after", str(budget)] + common))
	var r0: Dictionary = await u.wait_json(u.result_path("Hosty"), func(d: Dictionary) -> bool: return bool(d.get("connected", false)), U.SERVER_READY_S)
	check(bool(r0.get("connected", false)), "the host's session is up")
	var ann: int = u.spawn("ann", u.client_args(port, "Ann", "aggressive", ["--creature", "f_jitters", "--party-ui", "--party-quit-when-ended",
		"--party-meta", "meta_squat_rack=2,meta_sponsorship=1,no_such_upgrade=5", "--quit-after", str(budget)] + common))
	var rh: Dictionary = await u.wait_json(u.result_path("Hosty"), func(d: Dictionary) -> bool: return bool(d.get("done", false)), budget)
	var ra: Dictionary = await u.wait_json(u.result_path("Ann"), func(d: Dictionary) -> bool: return bool(d.get("done", false)), 60.0)
	var ph := _party(rh)
	var pa := _party(ra)
	var seat := str(pa.get("seat", ""))
	# each player's own Cannery levels in the deal (clamped to the installed upgrades)
	var metas := {}
	for p in ph.get("state", {}).get("players", []):
		metas[str(p.get("id", ""))] = _levels(p.get("meta", {}))
	check_eq(metas.get("1", {}), {"meta_heavy_bag": 1}, "the host's own Cannery levels")
	check_eq(metas.get(seat, {}), {"meta_squat_rack": 2, "meta_sponsorship": 1}, "Ann's own levels (unknown upgrades dropped)")
	check_eq(str(ph.get("state", {}).get("variant", "")), "fight_camp", "a Fight Camp party run")
	# the tag fight: one fighter in at a time, the benched partner assists / cheers / tags in
	var fights: Array = ph.get("fights", [])
	check(not fights.is_empty() and str((fights[0] as Dictionary).get("campaign", {}).get("format", "")) == "tag", "a tag-team fight: %s" % str(fights.slice(0, 1)))
	if not fights.is_empty():
		var kinds: Array = ((fights[0] as Dictionary).get("fighters", []) as Array).map(func(f: Dictionary) -> String: return str(f.get("kind", "")))
		check(kinds.slice(0, 2) == ["player", "net"], "both humans in it: %s" % str(kinds.slice(0, 3)))
	# Ann starts on the bench: her assists and cheers travel as her controller input to the host's
	# simulation (the host's own bench time depends on the fight: a fighter knocked out stays out)
	var ev: Dictionary = ph.get("camp_events", {})
	check(int(ev.get("assist:member", 0)) >= 1, "Ann called an assist from the bench over the network: %s" % str(ev))
	check(int(ev.get("cheer:member", 0)) >= 1, "Ann cheered from the bench: %s" % str(ev))
	check(int(ph.get("state", {}).get("fights_won", 0)) >= 1, "the tag fight was won")
	# suspended by the host: both keep the run in their party saves
	check(str(ph.get("notes", [])).contains("suspending"), "the host suspended the run at the map")
	check_eq(str(ra.get("exit_reason", "")), "the host ended the party run", "Ann went back to the lobby")
	check(bool(ph.get("party_save", false)) and bool(pa.get("party_save", false)), "the run is in both party saves")
	var rid := str(ph.get("run_id", ""))
	var log1 := int(ph.get("state", {}).get("log_size", 0))
	_no_child_errors([host, ann])
	# a NEW session: the host offers the saved run, Ann rejoins her seat by run id; the run goes on
	# (an event Ann answers, rest for both, the next fight) until the host leaves the session
	# 8 s into that fight (host departure)
	var port2: int = port + 2
	var host2: int = u.spawn("host", _host_args(port2, "Hosty", ["--creature", "f_stoke", "--party-offer", rid, "--party-event-wait", "4",
		"--party-host-leave-in-fight", "1", "--party-wait", str(U.SERVER_READY_S + 60.0), "--quit-after", str(budget)] + common, "Hosty2"))
	var r2: Dictionary = await u.wait_json(u.result_path("Hosty2"), func(d: Dictionary) -> bool: return bool(d.get("connected", false)), U.SERVER_READY_S)
	check(bool(r2.get("connected", false)), "the new session is up")
	var ann2: int = u.spawn("ann", u.client_args(port2, "Ann", "aggressive", ["--creature", "f_jitters", "--party-ui", "--party-event", "last",
		"--quit-after", str(budget)] + common, "Ann2"))
	var rh2: Dictionary = await u.wait_json(u.result_path("Hosty2"), func(d: Dictionary) -> bool: return bool(d.get("done", false)), budget)
	var rb2: Dictionary = await u.wait_json(u.result_path("Ann2"), func(d: Dictionary) -> bool: return bool(d.get("done", false)), 60.0)
	var ph2 := _party(rh2)
	var pb2 := _party(rb2)
	var st2: Dictionary = ph2.get("state", {})
	check_eq(str(ph2.get("offer_error", "?")), "", "the host offered the saved run from the lobby")
	check_eq(str(pb2.get("claimed", "")), seat, "Ann took her old seat (her save remembers it)")
	check_eq(ph2.get("started_with_missing", ["?"]), [], "resumed with everyone back")
	check_eq(str(st2.get("run_id", "")), rid, "the same run")
	check(int(st2.get("log_size", 0)) > log1, "and it went on from the save (%d -> %d decisions)" % [log1, int(st2.get("log_size", 0))])
	check(_log_has(ph2, "event", seat), "Ann answered the event (the host waited): %s" % str(ph2.get("log", []).map(func(e): return "%s/%s" % [e.k, e.p])))
	check(_log_has(ph2, "rest", "1") and _log_has(ph2, "rest", seat), "both rested, each their own choice")
	for p in [ph2, pb2]:
		var kinds_done: Array = (p.get("decisions", []) as Array).map(func(e: Dictionary) -> String: return str(e.get("kind", "")))
		check(kinds_done.has("rest"), "%s: through their own rest screen: %s" % [str(p.get("role", "?")), str(kinds_done)])
	var f2: Array = ph2.get("fights", [])
	check(not f2.is_empty() and ((f2[0] as Dictionary).get("fighters", []) as Array).size() >= 2 and
		str(((f2[0] as Dictionary).get("fighters", []) as Array)[1].get("kind", "")) == "net", "the next fight on the new session, Ann driving her fighter: %s" % str(f2.slice(0, 1)))
	# a tag-in from the bench in one of the two tag fights (whoever was benched, when the partner in
	# the cage was free to tag out)
	var ev2: Dictionary = ph2.get("camp_events", {})
	var tags := int(ev.get("tag:host", 0)) + int(ev.get("tag:member", 0)) + int(ev2.get("tag:host", 0)) + int(ev2.get("tag:member", 0))
	check(tags >= 1, "a tag-in happened: %s / %s" % [str(ev), str(ev2)])
	# host departure mid-fight: the session ends for Ann with the reason and how to get the run back;
	# the match ends unscored and the run stays at that fight in both party saves
	check(str(ph2.get("notes", [])).contains("leaving the session in fight 1"), "the host left the session mid-fight")
	check_eq(str(rb2.get("exit_reason", "")), "disconnected: host_left", "Ann was told the host left")
	var dlg: Dictionary = pb2.get("dialog", {})
	check(str(dlg.get("body", "")).contains("party run is saved"), "and that the party run is saved and how to resume it: %s" % str(dlg))
	check_eq(str(st2.get("phase", "")), "fight", "the run is still at that fight")
	check_eq(int(st2.get("fights", -1)), 1, "the unfinished fight was not scored")
	check(bool(ph2.get("party_save", false)) and bool(pb2.get("party_save", false)), "the run stays in both party saves")
	check_eq(int(pb2.get("state", {}).get("log_size", -1)), int(st2.get("log_size", -2)), "both machines on the same run")
	_no_child_errors([host2, ann2])
