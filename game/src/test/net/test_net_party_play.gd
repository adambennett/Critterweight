extends TestCase
## COOP-01..06 / NET-05 (in-process, LOOPBACK 127.0.0.1): online party runs on the real session
## code - a listen host (Net) running a NetPartyRuns with its CoopSession, and a member emulated by a
## NetClient in the same process that speaks the party protocol through the authority's relay
## (exactly the bytes a member's CoopSession sends). Fights are networked campaign matches
## (NetServer.start_campaign_match) presented by the member's NetMatchScene. The member-side
## CoopSession, the campaign screens and independent processes are covered by
## test_net_party_campaign.gd.

var _nodes: Array = []
var _dirs: Array = []
var _runs: Array = []


func after_each() -> void:
	for r in _runs:
		(r as NetPartyRuns).close()
	_runs.clear()
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	if Net.is_session_active():
		Net.leave()
	for d in _dirs:
		_remove_tree(str(d))
	_dirs.clear()


func _port() -> int:
	var seq := int(Engine.get_meta("net_party_play_port_seq", 0)) + 1
	Engine.set_meta("net_party_play_port_seq", seq)
	return 36000 + (OS.get_process_id() % 500) * 20 + (seq % 10) * 2


func _client(port: int, name_: String, present := false) -> NetClient:
	var c := NetClient.new()
	c.present = present
	c.install_scene = false
	add_child(c)
	_nodes.append(c)
	c.connect_to_server("127.0.0.1", port, {"timeout_s": 8, "name": name_})
	return c


func _until(pred: Callable, timeout_s: float) -> bool:
	var until := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < until:
		if pred.call():
			return true
		await get_tree().physics_frame
	return pred.call()


func _store() -> RunStore:
	var dir := Paths.dir("captures").path_join("tests").path_join("net").path_join("party_play_%d_%d" % [OS.get_process_id(), _dirs.size()])
	_dirs.append(dir)
	return RunStore.new(dir)


func _remove_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in d.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


## Party messages a NetClient received from the party's host: [{type, payload}] (unpacked).
func _party_inbox(c: NetClient) -> Array:
	var box: Array = []
	c.app_message.connect(func(_from: int, t: String, p: Dictionary) -> void:
		if not t.begins_with(NetPartyTransport.PREFIX):
			return
		var up := NetProtocol.unpack_party_payload(p)
		box.append({"type": t.substr(NetPartyTransport.PREFIX.length()), "payload": up.get("value", {}), "ok": bool(up["ok"])}))
	return box


## What a member's CoopSession would send: a party message relayed by the authority to `to`.
func _send(c: NetClient, to: String, type: String, payload: Dictionary) -> void:
	c.send_app(NetProtocol.APP_RELAY, {"to": to, "type": NetPartyTransport.PREFIX + type, "payload": payload})


func _last(box: Array, type: String) -> Dictionary:
	for i in range(box.size() - 1, -1, -1):
		if str(box[i]["type"]) == type:
			return box[i]["payload"]
	return {}


## Host + Ann (emulated member) in a party run of `fmt`, released and at its first fight on the
## session. Returns {pr, ann, box, seat} or {} (failures are recorded).
func _party_at_first_fight(fmt: String, variant := "off_the_street") -> Dictionary:
	var port := _port()
	check_eq(Net.host({"port": port, "player_name": "Hosty", "lan_discovery": false, "max_players": 4, "results_time": 2}), OK, "listen server up")
	var ann := _client(port, "Ann", true)
	var box := _party_inbox(ann)
	if not await _until(func() -> bool: return ann.state == NetClient.State.LOBBY, 8.0):
		check(false, "Ann admitted")
		return {}
	var cat := CampaignFlow.make_catalog(false)
	var pr := NetPartyRuns.new(cat, _store(), Profiles.default_profile("party_play_host", "Hosty"))
	var seat := str(ann.player_id)
	var cfg := {"seed": 4, "variant": variant, "difficulty": "amateur", "dose": 0, "created_at": 9, "coop_format": fmt,
		"players": [{"id": "1", "name": "Hosty", "fighter": "f_stoke", "profile_id": "party_play_host"},
			{"id": seat, "name": "Ann", "fighter": "f_dozer", "profile_id": ""}]}
	check_eq(pr.start_new_as_host(cfg), "", "a %s party run dealt" % fmt)
	pr.start_ticking()
	_runs.append(pr)
	check(pr.session != null and not pr.session.is_live(), "dealt runs wait (held) while members take their seats")
	var run_id := str(Net.party().get("run_id", ""))
	if not await _until(func() -> bool: return str(ann.lobby.get("party", {}).get("run_id", "")) == run_id, 4.0):
		check(false, "the offer reached Ann")
		return {}
	ann.send_app(NetProtocol.APP_PARTY_CLAIM, {"run_id": run_id, "seat": seat})
	check(await _until(func() -> bool: return Net.member_ids() == [seat], 4.0), "Ann takes her seat")
	_send(ann, "1", "hello", {"player": seat})
	check(await _until(func() -> bool: return not _last(box, "run_state").is_empty(), 4.0), "the host answers Ann's hello with the run")
	check(not bool(_last(box, "run_state").get("live", true)), "a held run says so (members wait in the lobby)")
	_send(ann, "1", "vote", {"node": "a1r1l0"})
	check(await _until(func() -> bool: return _last(box, "error").has("text"), 4.0), "a vote before the start is refused")
	check_eq(pr.start_host(), "", "the host starts the run")
	check(await _until(func() -> bool: return bool(_last(box, "run_state").get("live", false)), 4.0), "members hear the run is on")
	check(await _until(func() -> bool: return not _last(box, "vote_open").is_empty(), 4.0), "the route vote opens for everyone")
	var opts: Array = _last(box, "vote_open").get("options", [])
	if opts.is_empty():
		check(false, "vote options")
		return {}
	# both vote the same first-row fight: the vote resolves at once (everyone voted)
	_send(ann, "1", "vote", {"node": str(opts[0])})
	check(pr.session.act("vote", {"node": str(opts[0])}), "the host's own vote counts: %s" % pr.session.last_error)
	check(await _until(func() -> bool: return pr.session.ctrl.phase() == "fight", 6.0), "the party enters the fight node (%s)" % pr.session.ctrl.phase())
	check(await _until(func() -> bool: return ann.state == NetClient.State.MATCH, 10.0), "the fight is played on the session: Ann's client is in the match")
	return {"pr": pr, "ann": ann, "box": box, "seat": seat}


func _fight_until_phase(phase: int, timeout_s: float) -> bool:
	return await _until(func() -> bool:
		var s := Net.server
		return s != null and s.sim != null and s.sim.mode != null and s.sim.mode.phase == phase, timeout_s)


func test_party_payloads_travel_packed() -> void:
	var cat := CampaignCatalog.new(Content, "")
	var ctrl := RunController.start_run(cat, {"seed": 11, "variant": "off_the_street", "difficulty": "amateur", "dose": 0, "created_at": 1,
		"players": [{"id": "1", "name": "A", "fighter": "f_stoke"}, {"id": "2", "name": "B", "fighter": "f_dozer"}]})
	var small := {"node": "a1r1l0"}
	check_eq(NetProtocol.pack_party_payload(small), small, "small party messages travel as they are")
	var big := {"state": ctrl.state, "host": "1", "reason": "x"}
	var packed := NetProtocol.pack_party_payload(big)
	check(packed.has("_z") and var_to_bytes(packed).size() < var_to_bytes(big).size() / 2, "a run state travels deflated (%d -> %d bytes)" % [
		var_to_bytes(big).size(), var_to_bytes(packed).size()])
	var up := NetProtocol.unpack_party_payload(packed)
	check(bool(up["ok"]), "and unpacks: %s" % str(up.get("error", "")))
	check_eq(Saves.checksum(RunStore.json_stable(up.get("value", {}).get("state", {}))), Saves.checksum(RunStore.json_stable(ctrl.state)), "bit-exact")
	check(bool(NetProtocol.decode_payload(NetProtocol.encode_payload(packed))["ok"]), "the packed form passes the app channel's checks")
	# (inflation itself is capped at MAX_PARTY_UNPACKED by decompress_dynamic)
	var bomb := PackedByteArray()
	bomb.resize(1 << 20)
	var forged := {"_z": bomb.compress(FileAccess.COMPRESSION_DEFLATE), "_n": 64}
	check(not bool(NetProtocol.unpack_party_payload(forged)["ok"]), "a payload inflating past its announced size is refused")
	check(not bool(NetProtocol.unpack_party_payload({"_z": forged["_z"], "_n": NetProtocol.MAX_PARTY_UNPACKED + 1})["ok"]), "and one announcing more than the cap")
	check(not bool(NetProtocol.unpack_party_payload({"_z": "text", "_n": 10})["ok"]), "a malformed packed payload is refused")
	var obj := Node.new()
	var raw_obj := var_to_bytes_with_objects({"o": obj})
	obj.free()
	var objs := {"_z": raw_obj.compress(FileAccess.COMPRESSION_DEFLATE), "_n": raw_obj.size()}
	var uo := NetProtocol.unpack_party_payload(objs)
	check(not bool(uo["ok"]) or typeof((uo["value"] as Dictionary).get("o")) != TYPE_OBJECT, "never objects")


## What every machine's screens read from CoopSession (LOOPBACK PartyTransport, in-process): a
## held run, the open vote on a member, refused acts with reasons, a ref timeout, and a shared
## event outcome that survives the node completing.
func test_coop_session_views_on_every_machine() -> void:
	var hub := LoopbackTransport.Hub.new()
	var th := hub.join("1")
	var tm := hub.join("2")
	var cat := CampaignCatalog.new(Content, "")
	var cfg := {"seed": 1, "variant": "off_the_street", "difficulty": "amateur", "dose": 0, "created_at": 3,
		"players": [{"id": "1", "name": "Hosty", "fighter": "f_stoke"}, {"id": "2", "name": "Ann", "fighter": "f_dozer"}]}
	var host := CoopSession.host_new(th, cat, cfg, null, Profiles.default_profile("h", "Hosty"), true)
	var mem := CoopSession.member_join(tm, cat, "1", null, Profiles.default_profile("m", "Ann"))
	var both := func(n := 3) -> void:
		for i in n:
			host.tick(0.1)
			mem.tick(0.1)
	both.call()
	check(mem.ctrl != null and not mem.is_live() and not host.is_live(), "a held run reaches the member, marked not live")
	check(not host.act("vote", {"node": "a1r1l0"}), "nothing is decided while held")
	check(host.last_error.contains("not started"), "with a reason: %s" % host.last_error)
	host.release()
	both.call()
	check(host.is_live() and mem.is_live(), "released: live everywhere")
	var vv := mem.vote_view()
	check(bool(vv.get("open", false)) and (vv.get("options", []) as Array).has("a1r1l0") and float(vv.get("left", 0.0)) > 0.0,
		"the member sees the open vote and its timer: %s" % str(vv))
	check(mem.act("vote", {"node": "a1r1l0"}), "a member's vote is sent")
	both.call()
	check_eq(str(host.vote_view().get("votes", {}).get("2", "")), "a1r1l0", "the host counted it")
	check_eq(str(mem.vote_view().get("votes", {}).get("2", "")), "a1r1l0", "and every member sees it")
	check(not host.act("vote", {"node": "zzz"}), "an invalid vote is refused")
	check(host.act("vote", {"node": "a1r1l0"}), "the host votes")
	both.call()
	check_eq(host.ctrl.phase(), "fight", "everyone voted: the party is at the fight")
	check(mem.vote_view().is_empty(), "the member's vote view closed")
	check_eq(str(mem.fight_view().get("encounter", "")), str(host.fight_view().get("encounter", "")), "both know the fight")
	# ref timeout from the member's budget; only the caller ends it early
	check(mem.act("pause", {}), "the member calls a ref timeout")
	both.call(1)
	check(host.is_paused() and mem.is_paused(), "paused on every machine")
	check_eq(str(mem.pause_view().get("by", "")), "2", "called by the member")
	check(not host.act("resume", {}), "the host cannot end the member's timeout")
	mem.act("resume", {})
	both.call(1)
	check(not host.is_paused() and not mem.is_paused(), "the caller ended it")
	check(float(mem.pause_view().get("budget", {}).get("2", 30.0)) < 30.0, "her budget went down: %s" % str(mem.pause_view().get("budget", {})))
	# the fight (decided like the network fight driver would): won, picks per player
	var players := {}
	for p in host.ctrl.players():
		players[str(p["id"])] = {"hp": host.ctrl.max_hp(p), "hype": 0.0, "out": false, "knockdowns": 0, "kos": 1}
	host.complete_fight({"campaign": {"won": true, "time": 40.0, "players": players}})
	both.call()
	for pid in ["1", "2"]:
		var who: CoopSession = host if pid == "1" else mem
		for e in host.ctrl.pending_for(pid).duplicate():
			who.act("pick", {"rid": str(e["rid"]), "choice": "skip"})
			both.call(1)
	both.call()
	check_eq(host.ctrl.phase(), "map", "everyone picked: back on the map")
	var ev_node := ""
	for o in host.ctrl.available_nodes():
		if host.ctrl.visible_type(str(o)) == "event":
			ev_node = str(o)
	check(ev_node != "", "an event is reachable (seed 1: %s)" % str(host.ctrl.available_nodes()))
	if ev_node == "":
		return
	host.act("vote", {"node": ev_node})
	mem.act("vote", {"node": ev_node})
	both.call()
	check_eq(host.ctrl.phase(), "event", "at the event")
	var choice := EventRunner.PASS
	for c in host.ctrl.event_view("2").get("choices", []):
		if bool((c as Dictionary).get("available", false)):
			choice = str(c["id"])
			break
	mem.act("event_choice", {"choice": choice})
	host.act("event_choice", {"choice": choice})
	both.call(4)
	check(host.ctrl.phase() != "event", "the event was decided (%s)" % host.ctrl.phase())
	var le := mem.last_event
	check(not le.is_empty() and str(le.get("node", "")) == ev_node and str(le.get("title", "")) != "",
		"the member has the outcome even after the node moved on: %s" % str(le))
	check(str(le.get("by", "")) in ["2", "party"], "decided by the member (first answer) or the party's vote: %s" % str(le.get("by", "")))
	check_eq(host.last_event.get("texts", []), le.get("texts", []), "the same outcome lines on both machines")


func test_campaign_match_checks() -> void:
	var good := {"mode": "campaign", "rules": {"rounds": 1, "round_time": 150.0, "mode": "campaign", "friendly_fire": false, "lives": 1},
		"campaign": {"stand_in": ""}}
	check_eq(NetProtocol.campaign_match_problem(good), "", "a campaign fight's rules")
	var boss := good.duplicate(true)
	boss["mode"] = "boss"
	check_eq(NetProtocol.campaign_match_problem(boss), "", "a boss fight")
	var bad_mode := good.duplicate(true)
	bad_mode["mode"] = "chumball"
	check(NetProtocol.campaign_match_problem(bad_mode) != "", "only the campaign modes")
	var extra := good.duplicate(true)
	extra["rules"]["damage_mult"] = 5.0
	check(NetProtocol.campaign_match_problem(extra).contains("damage_mult"), "no extra rules ride along")
	var long_round := good.duplicate(true)
	long_round["rules"]["round_time"] = 99999.0
	check(NetProtocol.campaign_match_problem(long_round) != "", "round time bounded")
	var stand := good.duplicate(true)
	stand["campaign"]["stand_in"] = "no_such_creature"
	check(NetProtocol.campaign_match_problem(stand).contains("stand-ins"), "a stand-in that is not installed is named")


## Simultaneous format: the host's fight driver builds the campaign match from the run and plays it
## on the session; the member presents it; a ref timeout freezes it for everyone; the authoritative
## result is applied once and the member sees the run that follows (reward picks per player).
func test_party_fight_simultaneous_inprocess() -> void:
	var p := await _party_at_first_fight("simultaneous")
	if p.is_empty():
		return
	var pr: NetPartyRuns = p["pr"]
	var ann: NetClient = p["ann"]
	var box: Array = p["box"]
	var seat := str(p["seat"])
	var info: Dictionary = ann.match_info.get("campaign", {})
	check(not info.is_empty() and str(info.get("format", "")) == "coop", "MATCH_START carries the campaign fight (%s)" % str(info))
	check(str(info.get("name", "")) != "", "and its encounter's name")
	var srv := Net.server
	var host_fighter := Net.local_fighter()
	check(host_fighter >= 0 and ann.my_fighter >= 0 and host_fighter != ann.my_fighter, "each member drives their own fighter (%d / %d)" % [host_fighter, ann.my_fighter])
	if srv.sim != null and ann.my_fighter >= 0:
		check_eq(srv.sim.fighters[host_fighter].controller_kind, "player", "the host's fighter: local input")
		check_eq(srv.sim.fighters[ann.my_fighter].controller_kind, "net", "Ann's: her input stream")
		check(srv.sim.input_sources[ann.my_fighter] is NetRemoteInput, "a NetRemoteInput on the authority")
		check_eq(srv.sim.fighters[ann.my_fighter].creature.id, "f_dozer", "with her run fighter")
		check_eq(srv.sim.mode.id(), "campaign", "the campaign mode runs on the host")
		check(ann.scene != null and ann.scene.views.size() == srv.sim.fighters.size(), "Ann's NetMatchScene shows every fighter")
		for e in ann.replica.roster.values():
			check(e.get("def") != null, "roster creature '%s' resolved on Ann's side" % str(e.get("creature", "")))
	check(await _fight_until_phase(MatchMode.Phase.FIGHT, 15.0), "the bell rings")
	# Ann's ref timeout: the whole fight freezes for everyone, from her budget
	_send(ann, "1", "pause", {})
	check(await _until(func() -> bool: return srv.frozen, 4.0), "Ann's ref timeout freezes the host's match")
	check(await _until(func() -> bool: return not _last(box, "paused").is_empty(), 3.0), "and every member hears it")
	var t0 := srv.sim.time
	await wait_physics(30)
	check_eq(srv.sim.time, t0, "no simulation while frozen")
	check(srv.sim.paused, "the match itself is paused")
	_send(ann, "1", "resume", {})
	check(await _until(func() -> bool: return not srv.frozen, 4.0), "she ends it early")
	await wait_physics(10)
	check(srv.sim.time > t0, "the fight goes on")
	var left := float(pr.session.pause_view()["budget"].get(seat, 99.0))
	check(left < 30.0 and left > 0.0, "her ref timeout budget went down (%.2f s left)" % left)
	check(not pr.session.act("resume", {}), "only the caller ends a timeout")
	# the party wins: the authoritative result goes into the run once
	(srv.sim.mode as CampaignMatchMode)._finish(true)
	check(await _until(func() -> bool: return pr.fights_played == 1 and pr.session.ctrl.phase() == "reward", 10.0),
		"the result is applied to the run (%s)" % pr.session.ctrl.phase())
	var lf := pr.session.ctrl.last_fight()
	check(bool(lf.get("won", false)) and (lf.get("players", {}) as Dictionary).has(seat), "the logged fight result has both members: %s" % str(lf.keys()))
	check(await _until(func() -> bool: return str(_last(box, "run_state").get("state", {}).get("phase", "")) == "reward", 4.0), "Ann gets the run that follows")
	check(await _until(func() -> bool: return ann.state == NetClient.State.LOBBY and Net.session_state() == "lobby", 10.0), "the session is back in its lobby after the results")
	check(not pr.fight_running and srv.sim == null, "no fight on the session any more")
	# per-player picks: Ann claims only her own pending reward, through the host
	var pend := pr.session.ctrl.pending_for(seat).duplicate(true)
	var host_pend := pr.session.ctrl.pending_for("1").size()
	check(not pend.is_empty(), "Ann has her own pick waiting")
	if not pend.is_empty():
		var e: Dictionary = pend[0]
		_send(ann, "1", "pick", {"rid": str(e["rid"]), "choice": "skip"})
		check(await _until(func() -> bool: return pr.session.ctrl.pending_for(seat).size() < pend.size(), 4.0), "her pick is applied by the host")
		_send(ann, "1", "pick", {"rid": str(e["rid"]), "choice": "skip"})
		check(await _until(func() -> bool: return _last(box, "error").has("text"), 4.0), "a resent pick is refused (claim ledger)")
	check_eq(pr.session.ctrl.pending_for("1").size(), host_pend, "the host's own picks are untouched by hers")


## Tag-team format: one party fighter in at a time; the benched member (Ann) calls an assist and
## tags in with her own inputs over the network; the host's fighter goes to the bench.
func test_party_fight_tag_inprocess() -> void:
	var p := await _party_at_first_fight("tag", "fight_camp")
	if p.is_empty():
		return
	var pr: NetPartyRuns = p["pr"]
	var ann: NetClient = p["ann"]
	var srv := Net.server
	check_eq(str(ann.match_info.get("campaign", {}).get("format", "")), "tag", "a tag-team fight")
	if srv.sim == null or ann.my_fighter < 0:
		check(false, "fight running")
		return
	var mine := ann.my_fighter
	var host_fighter := Net.local_fighter()
	check(await _fight_until_phase(MatchMode.Phase.FIGHT, 15.0), "the bell rings")
	check_eq(srv.sim.fighters[mine].state, Fighter.State.INACTIVE, "Ann starts on the bench (parked)")
	check(srv.sim.fighters[host_fighter].state != Fighter.State.INACTIVE, "the host's fighter is in")
	check(await _until(func() -> bool:
		var fl: Array = ann.replica.latest().get("fighters", [])
		return mine < fl.size() and int((fl[mine] as Dictionary).get("state", -1)) == Fighter.State.INACTIVE, 4.0),
		"Ann's view shows her fighter benched")
	# her controller: Ability 1 = assist from the bench, then Switch Target = tag in
	var step := {"n": 0}
	ann.input_sampler = func(fi: FighterInput) -> void:
		fi.move = Vector3.ZERO
		fi.held = 0
		step["n"] = int(step["n"]) + 1
		if int(step["n"]) == 30:
			fi.press(FighterInput.AB1)
		if int(step["n"]) == 150:
			fi.press(FighterInput.TARGET)
	var seen := {}
	var ok := await _until(func() -> bool:
		if srv.sim == null:
			return false
		for ev in srv.sim.events:
			var t := str(ev.get("type", ""))
			if t in ["assist", "tag"] and int(ev.get("fighter", -1)) == mine:
				seen[t] = true
		return seen.has("tag"), 12.0)
	check(ok, "Ann tagged in from the bench (events seen: %s)" % str(seen.keys()))
	check(seen.has("assist"), "and called an assist first")
	check(srv.sim.fighters[mine].state != Fighter.State.INACTIVE, "her fighter is in the fight now")
	check_eq(srv.sim.fighters[host_fighter].state, Fighter.State.INACTIVE, "the host's fighter went to the bench")
	(srv.sim.mode as CampaignMatchMode)._finish(true)
	check(await _until(func() -> bool: return pr.fights_played == 1 and pr.session.ctrl.phase() == "reward", 10.0), "the tag fight's result is applied")
	check_eq(str(pr.session.ctrl.state.get("variant", "")), "fight_camp", "in a Fight Camp party run")


## A member who drops mid-fight: the run's bot (tier capped at Contender) takes her fighter at once;
## when she reconnects with her token she drives it again (same session id, same seat).
func test_party_member_drop_and_rejoin_mid_fight_inprocess() -> void:
	var p := await _party_at_first_fight("simultaneous")
	if p.is_empty():
		return
	var pr: NetPartyRuns = p["pr"]
	var ann: NetClient = p["ann"]
	var srv := Net.server
	var mine := ann.my_fighter
	var token := ann.token
	var sid := ann.player_id
	check(await _fight_until_phase(MatchMode.Phase.FIGHT, 15.0), "the bell rings")
	ann.drop()
	check(await _until(func() -> bool: return srv.sim != null and srv.sim.fighters[mine].controller_kind == "bot", 6.0), "a bot holds her fighter")
	if srv.sim != null:
		var b = srv.sim.input_sources[mine]
		check(b is BotBrain and str((b as BotBrain).label_text).contains("Ann"), "the party's bot, labelled for her")
	check(await _until(func() -> bool: return pr.session.ctrl.player(str(sid)).get("bot", false) == true, 6.0), "the run marks her away (decisions auto-chosen)")
	var back := NetClient.new()
	back.present = false
	back.install_scene = false
	add_child(back)
	_nodes.append(back)
	back.connect_to_server("127.0.0.1", srv.cfg["port"], {"timeout_s": 8, "name": "Ann", "token": token})
	check(await _until(func() -> bool: return back.player_id == sid and back.state == NetClient.State.MATCH, 8.0), "Ann reconnects into the running fight")
	check(await _until(func() -> bool: return srv.sim != null and srv.sim.fighters[mine].controller_kind == "net", 4.0), "and drives her fighter again")
	check_eq(back.my_fighter, mine, "the same fighter")
	var held := ""
	for s in Net.party().get("seats", []):
		if int((s as Dictionary).get("session", 0)) == sid:
			held = str((s as Dictionary).get("id", ""))
	check_eq(held, str(p["seat"]), "her seat was kept for her")
	(srv.sim.mode as CampaignMatchMode)._finish(true)
	check(await _until(func() -> bool: return pr.fights_played == 1, 10.0), "the fight ends normally")


## Simultaneous format, downed and revived over the network: the host's fighter goes down (the
## campaign mode's downed state and bleed-out timer); Ann sees it on her screen, walks over with
## her own controller and holds Grab next to it - the revive is her input on the host's simulation.
func test_party_member_revives_a_downed_ally_inprocess() -> void:
	var p := await _party_at_first_fight("simultaneous")
	if p.is_empty():
		return
	var pr: NetPartyRuns = p["pr"]
	var ann: NetClient = p["ann"]
	var srv := Net.server
	var mine := ann.my_fighter
	var downed := Net.local_fighter()
	check(await _fight_until_phase(MatchMode.Phase.FIGHT, 15.0), "the bell rings")
	if srv.sim == null or mine < 0 or downed < 0:
		check(false, "fight running")
		return
	var mode := srv.sim.mode as CampaignMatchMode
	# the enemies stand still: this test is about the revive, not the fight
	for f: Fighter in srv.sim.fighters:
		if not mode.is_party(f):
			srv.sim.set_input_source(f.index, InputSource.Scripted.new([]))
	mode._down(srv.sim.fighters[downed])
	check_eq(srv.sim.fighters[downed].state, Fighter.State.DOWNED, "the host's fighter is down")
	check(await _until(func() -> bool:
		var fl: Array = ann.replica.latest().get("fighters", [])
		return downed < fl.size() and int((fl[downed] as Dictionary).get("state", -1)) == Fighter.State.DOWNED, 4.0),
		"Ann's view shows her ally down")
	var seen := {"progress": 0.0}
	# her controller: walk to the downed ally (positions from her replica), then hold Grab
	ann.input_sampler = func(fi: FighterInput) -> void:
		fi.move = Vector3.ZERO
		fi.held = 0
		var snap := ann.replica.latest()
		var fl: Array = snap.get("fighters", [])
		if mine >= fl.size() or downed >= fl.size():
			return
		for d in (snap.get("mode", {}).get("view", {}) as Dictionary).get("downed", []):
			if int((d as Dictionary).get("fighter", -1)) == downed:
				seen["progress"] = maxf(float(seen["progress"]), float((d as Dictionary).get("revive", 0.0)))
		var to: Vector3 = (fl[downed] as Dictionary)["root"] - (fl[mine] as Dictionary)["root"]
		to.y = 0.0
		if to.length() > 0.9:
			fi.move = to.normalized()
		else:
			fi.set_held(FighterInput.GRAB, true)
	var by := {"i": -2}
	var ok := await _until(func() -> bool:
		if srv.sim == null:
			return false
		for ev in srv.sim.events:
			if str(ev.get("type", "")) == "revived_by" and int(ev.get("fighter", -1)) == downed:
				by["i"] = int(ev.get("by", -1))
				return true
		return false, 15.0)
	check(ok, "the downed fighter was revived before bleeding out")
	check_eq(int(by["i"]), mine, "by Ann's fighter, holding Grab from her own controller")
	check(srv.sim != null and srv.sim.fighters[downed].state != Fighter.State.DOWNED, "the host's fighter is back up")
	check(float(seen["progress"]) > 0.0, "Ann's screen showed the revive filling (%.2f)" % float(seen["progress"]))
	ann.input_sampler = Callable()
	(srv.sim.mode as CampaignMatchMode)._finish(true)
	check(await _until(func() -> bool: return pr.fights_played == 1, 10.0), "the fight ends normally")


## A fight the host's game never finished (its match scene was removed) is not applied: the run
## stays at the fight and plays it again from its start.
func test_party_fight_replayed_when_the_hosts_match_is_lost_inprocess() -> void:
	var p := await _party_at_first_fight("simultaneous")
	if p.is_empty():
		return
	var pr: NetPartyRuns = p["pr"]
	var srv := Net.server
	var first_match := srv.match_id
	App.set_scene(null)        # e.g. a menu replaced the host's match scene
	check(await _until(func() -> bool: return srv.phase == NetServer.PHASE_LOBBY or srv.match_id > first_match, 12.0), "the aborted match ends")
	check_eq(pr.fights_played, 0, "nothing applied")
	check_eq(pr.session.ctrl.phase(), "fight", "the run is still at the fight")
	check(await _until(func() -> bool: return srv.match_id > first_match and srv.sim != null, 12.0), "the fight starts again")
	check(await _fight_until_phase(MatchMode.Phase.FIGHT, 15.0), "the bell rings again")
	(srv.sim.mode as CampaignMatchMode)._finish(true)
	check(await _until(func() -> bool: return pr.fights_played == 1 and pr.session.ctrl.phase() == "reward", 10.0), "and is applied once")
