extends TestCase
## NET-01/04/06/07/11 (in-process, LOOPBACK 127.0.0.1): a NetServer and NetClients in one process
## talking over real ENet sockets. Fast coverage of the session logic; the multi-process tests
## (test_net_multiprocess.gd) repeat the important flows with independent processes.

var _nodes: Array = []


## Note: the full suite runs with `--fixed-fps`, where frames run faster than real time; the
## server's rate limits refill by simulated time too (NetRateLimiter), so in-process clients
## sending 60 inputs per simulated second are not mistaken for floods.
func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n is NetServer and (n as NetServer).is_running():
				(n as NetServer).close(NetProtocol.R_SHUTDOWN, "", false, 50)
			n.queue_free()
	_nodes.clear()


## A fresh port per test (a closing listen server keeps its port for up to 2 s). The sequence lives
## in Engine metadata: the runner makes a new instance per test, and a script `static var` made
## Godot 4.5.1 crash at exit after `--check` loaded this file.
func _port() -> int:
	var seq := int(Engine.get_meta("net_loopback_port_seq", 0)) + 1
	Engine.set_meta("net_loopback_port_seq", seq)
	return 34000 + (OS.get_process_id() % 500) * 20 + (seq % 10) * 2


func _server(port: int, extra: Dictionary = {}, entries: Array = []) -> NetServer:
	var s := NetServer.new()
	add_child(s)
	_nodes.append(s)
	var cfg := {"name": "Loop", "port": port, "lan_discovery": false, "lobby_time": 3, "results_time": 2,
		"max_players": 4, "max_spectators": 1, "rejoin_grace": 20, "timeout": 5, "kick_ban_seconds": 30}
	for k in extra:
		cfg[k] = extra[k]
	check_eq(s.start(cfg, true), OK, "server starts")
	if entries.is_empty():
		entries = [{"rules": "duel", "arena": "the_gullet", "weight": 1, "rules_override": {"rounds": 1, "round_time": 45}}]
	var pl := NetPlaylist.from_dict({"id": "loop", "name": "Loop", "entries": entries}, "test")
	pl.validate()
	s.set_playlist(pl)
	return s


func _client(port: int, opts: Dictionary, present := false) -> NetClient:
	var c := NetClient.new()
	c.present = present
	c.install_scene = false
	add_child(c)
	_nodes.append(c)
	var o := {"timeout_s": 5}
	for k in opts:
		o[k] = opts[k]
	c.connect_to_server("127.0.0.1", port, o)
	return c


func _until(pred: Callable, timeout_s: float) -> bool:
	var until := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < until:
		if pred.call():
			return true
		await get_tree().physics_frame
	return pred.call()


## Approach the nearest enemy (from the latest replicated snapshot) and jab.
func _aggressive(c: NetClient) -> Callable:
	var state := {"t": 0.0}
	return func(fi: FighterInput) -> void:
		fi.move = Vector3.ZERO
		fi.held = 0
		var snap := c.replica.latest()
		var me := c.my_fighter
		if snap.is_empty() or me < 0:
			return
		var fl: Array = snap["fighters"]
		if me >= fl.size() or int(fl[me]["gen"]) == 0:
			return
		var mine: Vector3 = fl[me]["root"]
		for i in fl.size():
			if i == me or int(fl[i]["gen"]) == 0 or int(fl[i]["state"]) == Fighter.State.KO:
				continue
			var to: Vector3 = fl[i]["root"] - mine
			to.y = 0.0
			if to.length() > 1.15:
				fi.move = to.normalized()
			state["t"] = float(state["t"]) + 1.0 / 120.0
			if to.length() < 1.7 and float(state["t"]) > 0.26:
				state["t"] = 0.0
				fi.press(FighterInput.LIGHT)
			return


func test_session_flow_inprocess() -> void:
	var port := _port()
	var server := _server(port)
	var a := _client(port, {"name": "Ann"})
	var b := _client(port, {"name": "Ben"}, true)
	check(await _until(func() -> bool: return a.state == NetClient.State.LOBBY and b.state == NetClient.State.LOBBY, 8.0), "both admitted")
	check_eq(server.players.size(), 2, "two players")
	check(not a.welcome.is_empty() and int(a.welcome["player_id"]) >= 2, "player ids start at 2 (1 = server)")
	# app channel both ways (server authority helpers)
	var got: Array = []
	server.app_request.connect(func(id: int, t: String, p: Dictionary) -> void: got.append([id, t, p]))
	check(a.send_app("coop.route_vote", {"route": 2, "names": ["x"]}), "client request sent")
	check(await _until(func() -> bool: return got.size() == 1, 3.0), "server received request")
	if got.size() == 1:
		check_eq(int(got[0][0]), a.player_id, "sender identified by session player id")
		check_eq(int(got[0][2]["route"]), 2, "payload intact")
	var recv: Array = []
	b.app_message.connect(func(id: int, t: String, p: Dictionary) -> void: recv.append([id, t, p]))
	check(server.send_app(NetServer.ALL, "coop.checkpoint", {"node": 4, "party": [a.player_id, b.player_id]}), "broadcast")
	check(await _until(func() -> bool: return recv.size() == 1, 3.0), "client received server message")
	# lobby: names, ready -> match
	var names: Array = (b.lobby.get("players", []) as Array).map(func(p): return str(p["name"]))
	names.sort()
	check_eq(names, ["Ann", "Ben"], "lobby lists both")
	a.input_sampler = _aggressive(a)
	a.send_lobby(NetProtocol.LQ_READY, true)
	b.send_lobby(NetProtocol.LQ_READY, true)
	check(await _until(func() -> bool: return a.state == NetClient.State.MATCH and b.state == NetClient.State.MATCH, 10.0), "match started")
	check(await _until(func() -> bool: return a.replica.snapshots_received > 20, 5.0), "snapshots flowing")
	check(b.scene != null and b.scene.views.size() == 2, "spectating client built NetMatchScene with both views")
	# authority: A's input moves A's fighter on the server
	var ai := a.my_fighter
	check(ai >= 0, "A controls a fighter")
	check(await _until(func() -> bool: return server.sim != null and server.sim.mode.phase == MatchMode.Phase.FIGHT, 5.0), "fight phase")
	var p0 := server.sim.fighters[ai].pos()
	await wait_physics(120)
	var p1 := server.sim.fighters[ai].pos()
	check(p0.distance_to(p1) > 0.3, "remote input moved the authoritative fighter (%.2f m)" % p0.distance_to(p1))
	# drop A abruptly: slot reserved, a bot holds the fighter
	var token := a.token
	var a_id := a.player_id
	a.drop()
	check(await _until(func() -> bool: return server.players.has(a_id) and not (server.players[a_id] as NetPlayer).connected, 3.0), "server noticed the drop")
	check_eq(server.sim.fighters[ai].controller_kind, "bot", "a bot holds the slot")
	# rejoin with the token: same player id, same fighter, control returns
	var a2 := _client(port, {"name": "Ann", "token": token})
	a2.input_sampler = _aggressive(a2)
	check(await _until(func() -> bool: return a2.state == NetClient.State.MATCH, 6.0), "rejoined into the running match")
	check(bool(a2.welcome.get("rejoined", false)), "welcome says rejoined")
	check_eq(a2.player_id, a_id, "same player id")
	check_eq(a2.my_fighter, ai, "same fighter slot")
	check_eq(server.sim.fighters[ai].controller_kind, "net", "control handed back")
	# the match ends by KO (B never fights back) and results reach everyone
	check(await _until(func() -> bool: return not a2.last_result.is_empty() and not b.last_result.is_empty(), 45.0), "results received")
	check_eq(int(a2.last_result.get("winner_team", -9)), server.sim.fighters[ai].team if server.sim else -9, "the attacker won")
	check(await _until(func() -> bool: return a2.state == NetClient.State.LOBBY and b.state == NetClient.State.LOBBY, 6.0), "automatic return to the lobby")
	check(b.scene == null, "match scene torn down")
	var reasons: Array = []
	b.disconnected.connect(func(r: Dictionary) -> void: reasons.append(r))
	server.close_async(NetProtocol.R_SHUTDOWN, "Maintenance", true, 3000)
	check(await _until(func() -> bool: return not reasons.is_empty(), 4.0), "client told about shutdown")
	check(await _until(func() -> bool: return server.is_closed(), 4.0), "server finished closing after clients acknowledged")
	if not reasons.is_empty():
		check_eq(int(reasons[0]["code"]), NetProtocol.R_SHUTDOWN)
		check(str(reasons[0]["message"]).contains("Maintenance"), "server message shown")
		check(bool(reasons[0].get("restarting", false)), "restart flag delivered")


func test_rejections_inprocess() -> void:
	var port := _port()
	_server(port, {"password": "sesame", "max_players": 1, "max_spectators": 0})
	var bad := _client(port, {"name": "Bad", "password": "nope"})
	var fails: Array = []
	bad.failed.connect(func(r: Dictionary) -> void: fails.append(r))
	check(await _until(func() -> bool: return not fails.is_empty(), 6.0), "wrong password rejected")
	if not fails.is_empty():
		check_eq(int(fails[0]["code"]), NetProtocol.R_PASSWORD)
	var ok := _client(port, {"name": "Ok", "password": "sesame"})
	check(await _until(func() -> bool: return ok.state == NetClient.State.LOBBY, 6.0), "right password admitted")
	var full := _client(port, {"name": "Late", "password": "sesame"})
	var f2: Array = []
	full.failed.connect(func(r: Dictionary) -> void: f2.append(r))
	check(await _until(func() -> bool: return not f2.is_empty(), 6.0), "full server rejects")
	if not f2.is_empty():
		check_eq(int(f2[0]["code"]), NetProtocol.R_FULL)
	var old := _client(port, {"name": "Old", "password": "sesame", "test_protocol": 1})
	var f3: Array = []
	old.failed.connect(func(r: Dictionary) -> void: f3.append(r))
	check(await _until(func() -> bool: return not f3.is_empty(), 6.0), "protocol mismatch detected")
	if not f3.is_empty():
		check_eq(int(f3[0]["code"]), NetProtocol.R_PROTOCOL)
		check(str(f3[0]["details"]).contains("protocol"), "details explain both sides")
	var ver := _client(port, {"name": "Ver", "password": "sesame", "test_game_version": "0.0.1"})
	var f4: Array = []
	ver.failed.connect(func(r: Dictionary) -> void: f4.append(r))
	check(await _until(func() -> bool: return not f4.is_empty(), 6.0), "build mismatch rejected")
	if not f4.is_empty():
		check_eq(int(f4[0]["code"]), NetProtocol.R_GAME_VERSION)


func test_kick_ban_and_violations_inprocess() -> void:
	var port := _port()
	var server := _server(port)
	var c := _client(port, {"name": "Troll"})
	check(await _until(func() -> bool: return c.state == NetClient.State.LOBBY, 6.0), "admitted")
	var reasons: Array = []
	c.disconnected.connect(func(r: Dictionary) -> void: reasons.append(r))
	check(server.kick(c.player_id, "being rude"), "kick")
	check(await _until(func() -> bool: return not reasons.is_empty(), 4.0), "client told")
	if not reasons.is_empty():
		check_eq(int(reasons[0]["code"]), NetProtocol.R_KICKED)
		check(str(reasons[0]["message"]).contains("being rude"), "kick reason shown")
	var again := _client(port, {"name": "Troll", "token": c.token})
	var f: Array = []
	again.failed.connect(func(r: Dictionary) -> void: f.append(r))
	check(await _until(func() -> bool: return not f.is_empty(), 6.0), "banned rejoin rejected")
	if not f.is_empty():
		check_eq(int(f[0]["code"]), NetProtocol.R_KICKED)
	# protocol abuse leads to a kick, the server keeps serving others
	var v := _client(port, {"name": "Spammer"})
	check(await _until(func() -> bool: return v.state == NetClient.State.LOBBY, 6.0), "admitted")
	var vr: Array = []
	v.disconnected.connect(func(r: Dictionary) -> void: vr.append(r))
	for i in 12:
		v.send_raw(NetProtocol.CH_CONTROL, PackedByteArray([NetProtocol.S_SNAPSHOT, 1, 2, 3]), true)
	check(await _until(func() -> bool: return not vr.is_empty(), 4.0), "violator kicked")
	if not vr.is_empty():
		check_eq(int(vr[0]["code"]), NetProtocol.R_VIOLATION)
	var good := _client(port, {"name": "Fine"})
	check(await _until(func() -> bool: return good.state == NetClient.State.LOBBY, 6.0), "server still admits others")


func test_oversized_and_flood_inprocess() -> void:
	var port := _port()
	var server := _server(port)
	var big := _client(port, {"name": "Bigmouth"})
	check(await _until(func() -> bool: return big.state == NetClient.State.LOBBY, 6.0), "admitted")
	var r1: Array = []
	big.disconnected.connect(func(r: Dictionary) -> void: r1.append(r))
	var huge := PackedByteArray([NetProtocol.C_CHAT])
	huge.resize(5000)
	big.send_raw(NetProtocol.CH_CONTROL, huge, true)
	check(await _until(func() -> bool: return not r1.is_empty(), 4.0), "oversized message kicks at once")
	if not r1.is_empty():
		check_eq(int(r1[0]["code"]), NetProtocol.R_VIOLATION)
	var flood := _client(port, {"name": "Flooder"})
	check(await _until(func() -> bool: return flood.state == NetClient.State.LOBBY, 6.0), "admitted")
	var r2: Array = []
	flood.disconnected.connect(func(r: Dictionary) -> void: r2.append(r))
	var w := NetWriter.new(NetProtocol.C_INPUT)
	w.u16(1)
	w.u32(0)
	w.u8(1)
	NetSnapshot.write_input(w, FighterInput.new())
	var pkt := w.data()
	for i in 3000:
		flood.send_raw(NetProtocol.CH_INPUT, pkt, false)
	check(await _until(func() -> bool: return not r2.is_empty(), 4.0), "input flood kicked")
	if not r2.is_empty():
		check(int(r2[0]["code"]) in [NetProtocol.R_VIOLATION, NetProtocol.R_FLOOD], "flood/violation reason (%s)" % NetProtocol.reason_name(int(r2[0]["code"])))
	var ok := _client(port, {"name": "Polite"})
	check(await _until(func() -> bool: return ok.state == NetClient.State.LOBBY, 6.0), "server unaffected")
	check(server.is_running(), "server running")


func test_host_leaving_ends_session() -> void:
	var port := _port()
	check_eq(Net.host({"port": port, "player_name": "Hosty", "lan_discovery": false, "max_players": 4}), OK, "listen server up")
	check(Net.is_host() and Net.is_authority() and Net.is_session_active(), "roles")
	check_eq(Net.local_peer_id(), NetServer.SERVER_ID, "host is player 1")
	var c := _client(port, {"name": "Guest"})
	check(await _until(func() -> bool: return c.state == NetClient.State.LOBBY, 6.0), "guest admitted")
	check_eq(Net.peers().size(), 2, "host + guest listed")
	var reqs: Array = []
	var on_req := func(id: int, t: String, p: Dictionary) -> void: reqs.append([id, t, p])
	Net.app_request.connect(on_req)
	c.send_app("coop.ready_check", {"ok": true})
	check(await _until(func() -> bool: return reqs.size() == 1, 3.0), "host received the guest request via Net.app_request")
	Net.app_request.disconnect(on_req)
	var reasons: Array = []
	c.disconnected.connect(func(r: Dictionary) -> void: reasons.append(r))
	Net.leave()
	check(not Net.is_session_active(), "host is offline again at once")
	check(await _until(func() -> bool: return not reasons.is_empty(), 4.0), "guest told")
	if not reasons.is_empty():
		check_eq(int(reasons[0]["code"]), NetProtocol.R_HOST_LEFT, "host_left reason")
		check(str(reasons[0]["message"]).contains("host left"), "clear message: %s" % str(reasons[0]["message"]))


func test_timeout_inprocess() -> void:
	var port := _port()
	var server := _server(port, {"timeout": 5})
	var cond := NetConditioner.new()
	cond.configure(1.0, 0.0, 0.0)
	var c := _client(port, {"name": "Faraway", "conditioner": cond, "timeout_s": 5})
	check(await _until(func() -> bool: return c.state == NetClient.State.LOBBY, 6.0), "admitted through the conditioner")
	var reasons: Array = []
	c.disconnected.connect(func(r: Dictionary) -> void: reasons.append(r))
	var t0 := Time.get_ticks_msec()
	cond.set_blackhole(true)
	check(await _until(func() -> bool: return not reasons.is_empty(), 12.0), "client detects the dead link")
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	if not reasons.is_empty():
		check_eq(int(reasons[0]["code"]), NetProtocol.R_TIMEOUT, "reported as a timeout")
	check(took >= 3.0 and took <= 11.0, "timeout honours the 5 s setting (took %.1f s)" % took)
	check(await _until(func() -> bool: return server._connected_count() == 0, 8.0), "server dropped the peer too")


func test_lan_discovery_inprocess() -> void:
	var port := _port()
	var dport := 32700 + randi() % 200
	_server(port, {"lan_discovery": true, "discovery_port": dport, "name": "LAN Test Box"})
	var browser := NetLanDiscovery.new()
	check_eq(browser.start_listener(dport), OK, "listener bound")
	var found := {}
	var finder := func() -> bool:
		browser.poll()
		for s in browser.list():
			if str(s["name"]) == "LAN Test Box":
				found.merge(s, true)
				return true
		return false
	var ok: bool = await _until(finder, 4.0)
	check(ok, "session discovered via beacon (loopback/LAN broadcast on this machine)")
	if ok:
		check_eq(int(found["port"]), port, "game port advertised")
		check(bool(found["compatible"]), "same build is compatible")
		check(bool(found["dedicated"]), "dedicated flag")
	browser.stop()


## A listen host whose match scene is removed by another path (a menu changing scenes) ends the
## match for everyone with an aborted result instead of touching a freed simulation.
func test_host_scene_removed_mid_match() -> void:
	var port := _port()
	check_eq(Net.host({"port": port, "player_name": "Hosty", "lan_discovery": false, "max_players": 4, "results_time": 2}), OK, "listen server up")
	var c := _client(port, {"name": "Guest"})
	check(await _until(func() -> bool: return c.state == NetClient.State.LOBBY, 6.0), "guest admitted")
	check_eq(Net.host_start(), "", "host starts the match")
	check(await _until(func() -> bool: return c.state == NetClient.State.MATCH and Net.server != null and Net.server.sim != null, 8.0), "match running")
	var ended: Array = []
	c.match_ended.connect(func(r: Dictionary) -> void: ended.append(r))
	App.set_scene(null)
	check(await _until(func() -> bool: return not ended.is_empty(), 4.0), "guest told the match ended")
	if not ended.is_empty():
		check(bool(ended[0].get("aborted", false)), "aborted result")
	check(Net.is_session_active(), "the session itself continues")
	check(await _until(func() -> bool: return c.state == NetClient.State.LOBBY, 6.0), "back in the lobby")
	Net.leave()


## Chum Rush supplement picks offered to a remote player wait for its own choice (a `mode.pick`
## request the server validates); an unanswered pick is taken for it after the timeout and a
## dropped player's bot takes it at once, so one player can never stall the break between waves.
func test_mode_picks_for_remote_players_inprocess() -> void:
	# supplements are campaign content; the test brings three plain ones of its own
	var sups: Array[String] = []
	for i in 3:
		sups.append("nettest_supplement_%d" % i)
		Content.register_runtime("supplements", {"id": sups[i], "name": "Test supplement %d" % i, "mods": {"damage": 1.05}}, "test")
	await _mode_picks_session()
	for id in sups:
		Content.unregister_runtime("supplements", id)


func _mode_picks_session() -> void:
	var port := _port()
	var server := _server(port, {}, [{"rules": "chum_rush", "arena": "the_gullet", "weight": 1, "bots": 0,
		"rules_override": {"round_time": 300}}])
	var a := _client(port, {"name": "Picker"})
	check(await _until(func() -> bool: return a.state == NetClient.State.LOBBY, 6.0), "admitted")
	a.send_lobby(NetProtocol.LQ_READY, true)
	check(await _until(func() -> bool: return server.sim != null and a.my_fighter >= 0 and server.sim.mode.phase == MatchMode.Phase.FIGHT, 20.0), "chum rush running")
	if server.sim == null or a.my_fighter < 0:
		return
	var me := a.my_fighter
	var mode = server.sim.mode
	mode.call("_offer_picks")
	check((mode.get("pending_pick") as Dictionary).has(me), "the remote player's pick waits for its choice")
	var offered: Array = ((mode.get("pending_pick") as Dictionary).get(me, []) as Array).duplicate()
	check(await _until(func() -> bool: return _hud_picks(a).has(me), 3.0), "the offer reached the client (mode HUD state)")
	a.send_app("mode.pick", {"choice": 1})
	check(await _until(func() -> bool: return not (mode.get("pending_pick") as Dictionary).has(me), 3.0), "the choice was applied")
	if offered.size() > 1:
		check_eq(_last_pick(server, me), str(offered[1]), "the chosen supplement")
	server.pick_timeout_ms = 400
	mode.call("_offer_picks")
	var offered2: Array = ((mode.get("pending_pick") as Dictionary).get(me, []) as Array).duplicate()
	check(await _until(func() -> bool: return not (mode.get("pending_pick") as Dictionary).has(me), 4.0), "an unanswered pick is taken after the timeout")
	if not offered2.is_empty():
		check_eq(_last_pick(server, me), str(offered2[0]), "the first offer was taken")
	server.pick_timeout_ms = 60000
	mode.call("_offer_picks")
	a.drop()
	check(await _until(func() -> bool: return not (mode.get("pending_pick") as Dictionary).has(me), 4.0), "the bot holding a dropped player's fighter takes its pick")


func _hud_picks(c: NetClient) -> Array:
	var out: Array = []
	var snap := c.replica.latest()
	if snap.is_empty():
		return out
	var hud = (snap.get("mode", {}) as Dictionary).get("hud", {})
	var picks = hud.get("picks", {}) if typeof(hud) == TYPE_DICTIONARY else {}
	if typeof(picks) == TYPE_DICTIONARY:
		for k in picks:
			out.append(int(k))
	return out


func _last_pick(server: NetServer, idx: int) -> String:
	var up := ""
	if server.sim == null:
		return up
	for ev in server.sim.events:
		if str(ev.get("type", "")) == "pick_taken" and int(ev.get("fighter", -1)) == idx:
			up = str(ev.get("upgrade", ""))
	return up


## Party messages for co-op (the campaign's NetPartyTransport contract): any member reaches one
## other member or all of them through the authority, with the sender's member id; membership
## events follow connections. The host side runs the campaign's own adapter.
func test_party_relay_inprocess() -> void:
	var port := _port()
	check_eq(Net.host({"port": port, "player_name": "Hosty", "lan_discovery": false, "max_players": 4}), OK, "listen server up")
	var party := NetPartyTransport.new()
	var got_host: Array = []
	party.message_received.connect(func(f: String, t: String, p: Dictionary) -> void: got_host.append([f, t, p]))
	var joined: Array = []
	party.peer_joined.connect(func(peer: String) -> void: joined.append(peer))
	var left: Array = []
	party.peer_left.connect(func(peer: String, r: String) -> void: left.append([peer, r]))
	check(party.available() and party.local_id() == "1", "the campaign adapter sees Net (the host is member 1)")
	var a := _client(port, {"name": "Ann"})
	var b := _client(port, {"name": "Ben"})
	check(await _until(func() -> bool: return a.state == NetClient.State.LOBBY and b.state == NetClient.State.LOBBY, 6.0), "both admitted")
	var ida := str(a.player_id)
	var idb := str(b.player_id)
	var both := [ida, idb]
	both.sort()
	check(await _until(func() -> bool: return party.peers() == both, 3.0), "members listed: %s" % str(party.peers()))
	check(joined.has(ida) and joined.has(idb), "member_joined for both")
	var got_a: Array = []
	a.app_message.connect(func(f: int, t: String, p: Dictionary) -> void: got_a.append([str(f), t, p]))
	var got_b: Array = []
	b.app_message.connect(func(f: int, t: String, p: Dictionary) -> void: got_b.append([str(f), t, p]))
	# a client broadcasts: the other client and the host's adapter get it with Ann's id
	a.send_app(NetProtocol.APP_RELAY, {"to": "", "type": "cmp/vote", "payload": {"node": 2}})
	check(await _until(func() -> bool: return got_b.size() == 1 and got_host.size() == 1, 3.0), "broadcast reached the other members")
	if got_b.size() == 1 and got_host.size() == 1:
		check_eq(got_b[0], [ida, "cmp/vote", {"node": 2}], "sender id and payload kept")
		check_eq(got_host[0], [ida, "vote", {"node": 2}], "the adapter strips its prefix")
	check(got_a.is_empty(), "no echo to the sender")
	# one member only
	a.send_app(NetProtocol.APP_RELAY, {"to": idb, "type": "cmp/claim", "payload": {"pick": 1}})
	check(await _until(func() -> bool: return got_b.size() == 2, 3.0), "direct message delivered")
	await wait_physics(10)
	check_eq(got_host.size(), 1, "not to the others")
	# the sender id comes from the connection the message arrived on, never from the message: a
	# member dressing a relayed message up as the host's (from/host fields around or inside the
	# payload) still arrives as itself, so CoopSession can trust `from` for host-only messages
	a.send_app(NetProtocol.APP_RELAY, {"to": "", "type": "cmp/run_end", "from": "1", "host": "1",
		"payload": {"from": "1", "host": "1", "victory": true}})
	check(await _until(func() -> bool: return got_b.size() == 3 and got_host.size() == 2, 3.0), "forged-looking broadcast delivered")
	if got_b.size() == 3 and got_host.size() == 2:
		check_eq(str(got_b[2][0]), ida, "a member's relayed message carries its own id, whatever the payload says")
		check_eq(str(got_host[1][0]), ida, "the host's adapter sees the true sender too")
	# a direct request to the authority is not a party message (it arrives as Net.app_request)
	a.send_app("cmp/run_end", {"victory": true})
	await wait_physics(10)
	check_eq(got_host.size(), 2, "a direct request never reaches the party channel")
	# the host broadcasts through the adapter
	party.send("", "ticket", {"node": 3})
	check(await _until(func() -> bool: return got_a.size() == 1 and got_b.size() == 4, 3.0), "host broadcast reached both clients")
	if got_a.size() == 1:
		check_eq(got_a[0], ["1", "cmp/ticket", {"node": 3}], "from member 1")
	# reserved types and oversized party messages are never relayed
	a.send_app(NetProtocol.APP_RELAY, {"to": "", "type": "mode.pick", "payload": {}})
	a.send_app(NetProtocol.APP_RELAY, {"to": "", "type": "cmp/huge", "payload": {"blob": "x".repeat(NetProtocol.MAX_RELAY_PAYLOAD + 100)}})
	await wait_physics(20)
	check_eq(got_b.size(), 4, "reserved types and oversized messages are not relayed")
	b.drop()
	check(await _until(func() -> bool: return not left.is_empty(), 4.0), "member_left when a member drops")
	if not left.is_empty():
		check_eq(str(left[0][0]), idb)
	Net.leave()
	check(left.size() >= 2 and str(left[-1][0]) == ida and str(left[-1][1]) == "session ended", "member_left for everyone when the session ends: %s" % str(left))
	party.close()


## Party seats: a resumed party run keeps its own member ids (seats) although everyone has new
## session ids. Here the run's seat 2 is the listen host (session 1) and seat 1 goes to the
## player who joined second (session 2) - the ids are swapped on purpose. The authority stamps
## seat ids from the connection, routes by seat, refuses wrong-run / taken / double claims and
## keeps unseated players out of the party channel.
func test_party_seats_inprocess() -> void:
	var port := _port()
	check_eq(Net.host({"port": port, "player_name": "Hosty", "lan_discovery": false, "max_players": 4}), OK, "listen server up")
	var party := NetPartyTransport.new()
	var got_host: Array = []
	party.message_received.connect(func(f: String, t: String, p: Dictionary) -> void: got_host.append([f, t, p]))
	var changes: Array = []
	Net.party_changed.connect(func(pt: Dictionary) -> void: changes.append(pt))
	var a := _client(port, {"name": "Ann"})
	var c := _client(port, {"name": "Cid"})
	check(await _until(func() -> bool: return a.state == NetClient.State.LOBBY and c.state == NetClient.State.LOBBY, 6.0), "both admitted")
	var run_id := "run_TESTSEATS_7"
	var seats := [{"id": "1", "name": "Ann", "fighter": "f_stoke"}, {"id": "2", "name": "Hosty", "fighter": "f_dozer"}]
	check(Net.party_open("run bad id!", seats, "2") != "", "a malformed run id is refused")
	check(Net.party_open(run_id, [{"id": "p0", "name": "X"}], "p0") != "", "seat ids must be online member ids")
	check(Net.party_open(run_id, seats, "3") != "", "the host's seat must be one of the run's")
	check_eq(Net.party_open(run_id, seats, "2"), "", "party run opened")
	check_eq(Net.local_member_id(), "2", "the host is its seat, not session 1")
	check_eq(party.local_id(), "2", "and so is its party transport")
	check(Net.member_ids().is_empty(), "nobody else is seated yet (session players are not members)")
	check(not changes.is_empty() and str(changes[-1].get("run_id", "")) == run_id, "party_changed announced the offer")
	check(await _until(func() -> bool: return str(a.lobby.get("party", {}).get("run_id", "")) == run_id, 3.0), "the offer reached the players")
	# claims: wrong run, taken seat, then the right one
	var answers_a: Array = []
	a.app_message.connect(func(f: int, t: String, p: Dictionary) -> void: answers_a.append([f, t, p]))
	var answers_c: Array = []
	c.app_message.connect(func(f: int, t: String, p: Dictionary) -> void: answers_c.append([f, t, p]))
	a.send_app(NetProtocol.APP_PARTY_CLAIM, {"run_id": "run_OTHER_1", "seat": "1"})
	a.send_app(NetProtocol.APP_PARTY_CLAIM, {"run_id": run_id, "seat": "2"})
	check(await _until(func() -> bool: return answers_a.size() == 2, 3.0), "refused claims are answered")
	if answers_a.size() == 2:
		check(str(answers_a[0][2].get("error", "")).contains("different run"), "a claim for another run is refused: %s" % str(answers_a[0]))
		check(str(answers_a[1][2].get("error", "")).contains("taken"), "the host's seat cannot be taken: %s" % str(answers_a[1]))
	a.send_app(NetProtocol.APP_PARTY_CLAIM, {"run_id": run_id, "seat": "1"})
	check(await _until(func() -> bool: return Net.member_ids() == ["1"], 3.0), "Ann holds seat 1 (session %d): %s" % [a.player_id, str(Net.member_ids())])
	c.send_app(NetProtocol.APP_PARTY_CLAIM, {"run_id": run_id, "seat": "1"})
	check(await _until(func() -> bool: return answers_c.size() == 1, 3.0), "Cid's claim is answered")
	if answers_c.size() == 1:
		check(str(answers_c[0][2].get("error", "")).contains("taken"), "a held seat cannot be claimed: %s" % str(answers_c[0]))
	a.send_app(NetProtocol.APP_PARTY_CLAIM, {"run_id": run_id, "seat": "1"})
	await wait_physics(10)
	# party traffic: seat ids stamped by the authority, routed by seat, outsiders kept out
	answers_a.clear()
	answers_c.clear()
	a.send_app(NetProtocol.APP_RELAY, {"to": "2", "type": "cmp/hello", "payload": {"player": "1"}})
	check(await _until(func() -> bool: return got_host.size() == 1, 3.0), "the host got the seated member's message")
	if got_host.size() == 1:
		check_eq(got_host[0][0], "1", "from seat 1 (Ann's session id is %d)" % a.player_id)
	party.send("1", "run_state", {"n": 1})
	check(await _until(func() -> bool: return answers_a.size() >= 1, 3.0), "the host's message reached seat 1")
	if not answers_a.is_empty():
		check_eq([answers_a[-1][0], answers_a[-1][1]], [2, "cmp/run_state"], "from the host's seat 2, not session 1")
	c.send_app(NetProtocol.APP_RELAY, {"to": "", "type": "cmp/run_end", "payload": {"victory": true}})
	c.send_app(NetProtocol.APP_RELAY, {"to": "2", "type": "cmp/run_end", "payload": {"victory": true}})
	party.send("", "notice", {"text": "members only"})
	await wait_physics(20)
	check_eq(got_host.size(), 1, "an unseated player cannot send into the party")
	check(answers_c.is_empty(), "nor receives party messages: %s" % str(answers_c))
	# a seat is freed when its holder leaves the session, then another player can take it
	a.leave()
	check(await _until(func() -> bool: return Net.member_ids().is_empty(), 4.0), "member_left when Ann goes")
	check(await _until(func() -> bool: return int(Net.party()["seats"][0]["session"]) == 0, 4.0), "her seat is free again")
	c.send_app(NetProtocol.APP_PARTY_CLAIM, {"run_id": run_id, "seat": "1"})
	check(await _until(func() -> bool: return Net.member_ids() == ["1"], 3.0), "a new member takes the open seat")
	# closing the offer turns member ids back into session ids
	Net.party_close()
	check(await _until(func() -> bool: return Net.local_member_id() == "1" and Net.member_ids() == [str(c.player_id)], 3.0),
		"session ids again after party_close: %s" % str(Net.member_ids()))
	check(not changes.is_empty() and changes[-1].is_empty(), "party_changed({}) on close")
	Net.leave()
	party.close()


## Equipped cosmetics travel with the player info (presentation only): validated against the
## known cosmetic ids (each in its own slot; headliner badges of installed fighters as frames),
## shown in the lobby rows and in MATCH_START per fighter, never in the simulation.
func test_cosmetics_travel_with_players_inprocess() -> void:
	var clean := NetProtocol.clean_cosmetics({"piece": "hub_gold_tooth", "frame": "hub_badge_headliner_f_stoke",
		"juice": "hub_frame_soaked", "back": "made_up_item", "neck": 42, "Bad Slot!": "hub_gold_tooth"})
	check_eq(clean, {"piece": "hub_gold_tooth", "frame": "hub_badge_headliner_f_stoke"}, "only known items, each in its own slot")
	check(NetProtocol.clean_cosmetics({"frame": "hub_badge_headliner_no_such_fighter"}).is_empty(), "badges need an installed fighter")
	var port := _port()
	var server := _server(port, {}, [{"rules": "duel", "arena": "the_gullet", "weight": 1, "rules_override": {"rounds": 1, "round_time": 20}}])
	var a := _client(port, {"name": "Ann"})
	var b := _client(port, {"name": "Ben"})
	check(await _until(func() -> bool: return a.state == NetClient.State.LOBBY and b.state == NetClient.State.LOBBY, 6.0), "both admitted")
	a.send_lobby(NetProtocol.LQ_COSMETICS, {"piece": "hub_gold_tooth", "juice": "hub_juice_sizzle", "frame": "hub_frame_soaked", "back": "made_up_item"})
	b.send_lobby(NetProtocol.LQ_COSMETICS, {"frame": "hub_badge_headliner_f_stoke"})
	var row_of := func(c: NetClient, pid: int) -> Dictionary:
		for p in c.lobby.get("players", []):
			if int(p.get("id", 0)) == pid:
				return p
		return {}
	check(await _until(func() -> bool: return (row_of.call(b, a.player_id) as Dictionary).get("cosmetics", {}).size() == 3, 4.0),
		"Ben's lobby shows Ann's cosmetics: %s" % str((row_of.call(b, a.player_id) as Dictionary).get("cosmetics", {})))
	check_eq((row_of.call(a, b.player_id) as Dictionary).get("cosmetics", {}), {"frame": "hub_badge_headliner_f_stoke"}, "and Ann sees Ben's badge")
	a.send_lobby(NetProtocol.LQ_READY, true)
	b.send_lobby(NetProtocol.LQ_READY, true)
	check(await _until(func() -> bool: return a.state == NetClient.State.MATCH and b.state == NetClient.State.MATCH, 15.0), "match started")
	var dressed: Dictionary = a.match_info.get("cosmetics", {})
	check_eq(dressed.get(str(a.my_fighter), {}), {"piece": "hub_gold_tooth", "juice": "hub_juice_sizzle", "frame": "hub_frame_soaked"}, "MATCH_START dresses Ann's fighter")
	check_eq(dressed.get(str(b.my_fighter), {}), {"frame": "hub_badge_headliner_f_stoke"}, "and Ben's")
	if server.sim != null:
		for f in server.sim.fighters:
			for k in f.mods:
				check(not str(k) in ["piece", "juice", "frame", "cosmetics"], "no cosmetic reaches the simulation (%s)" % str(k))
	# a listen host shows its own equipped items too
	var port2 := _port()
	check_eq(Net.host({"port": port2, "player_name": "Hosty", "lan_discovery": false, "cosmetics": {"back": "hub_replica_belt", "piece": "nope"}}), OK, "listen host up")
	var hrow: Dictionary = (Net.lobby().get("players", []) as Array)[0]
	check_eq(hrow.get("cosmetics", {}), {"back": "hub_replica_belt"}, "the host's row carries its cosmetics")
	Net.set_cosmetics({"frame": "hub_frame_sign_fixer"})
	check_eq((Net.lobby().get("players", []) as Array)[0].get("cosmetics", {}), {"frame": "hub_frame_sign_fixer"}, "set_cosmetics changes them")
	check_eq(Net.cosmetics_profile(hrow)["unlocks"]["cosmetics"], ["hub_replica_belt"], "a stand-in profile for the view helpers")
	# a lobby row's framed name card (ProfileFrame) comes from the row, never from this machine's profile
	var fr := ProfileFrame.style(Net.cosmetics_profile({"id": 2, "cosmetics": {"frame": "hub_frame_soaked"}}))
	check_eq(str(fr.get("id", "")), "hub_frame_soaked", "a row's name-card frame")
	check(ProfileFrame.style(Net.cosmetics_profile({"id": 3, "cosmetics": {}})).is_empty(), "a row without a frame shows none")
	Net.leave()


## A member re-verifies the run a host resumes against its own party save before playing on:
## the same run (id + seed), a state that follows from its decision log, a log that continues the
## member's (the host may be ahead, never behind or different).
func test_party_run_member_checks() -> void:
	var cat := CampaignCatalog.new(Content, "dev_biped")
	var cfg := {"seed": 777, "variant": "off_the_street", "difficulty": "amateur", "dose": 0, "created_at": 5,
		"players": [{"id": "1", "name": "Ann", "profile_id": "ann", "fighter": "f_stoke"},
			{"id": "2", "name": "Ben", "profile_id": "ben", "fighter": "f_dozer"}]}
	var ctrl := RunController.start_run(cat, cfg)
	var own: Dictionary = RunStore.json_stable(ctrl.state)
	check_eq(NetPartyRuns.check_resumed(cat, own, own), "", "the same run checks out")
	var ahead := RunController.from_state(cat, own.duplicate(true))
	check(ahead.choose_node(str(ahead.available_nodes()[0]), "1"), "one more decision: %s" % ahead.last_error)
	var ahead_st: Dictionary = RunStore.json_stable(ahead.state)
	check_eq(NetPartyRuns.check_resumed(cat, own, ahead_st), "", "a host that is further along is fine")
	check(NetPartyRuns.check_resumed(cat, ahead_st, own).contains("older"), "a host behind the member's save is refused")
	var other_cfg := cfg.duplicate(true)
	other_cfg["seed"] = 778
	other_cfg["run_id"] = str(own["run_id"])
	var other: Dictionary = RunStore.json_stable(RunController.start_run(cat, other_cfg).state)
	check(NetPartyRuns.check_resumed(cat, own, other).contains("not the one"), "another run under the same id is refused")
	var forged: Dictionary = own.duplicate(true)
	(forged["players"][1] as Dictionary)["scrip"] = 9999
	check(NetPartyRuns.check_resumed(cat, own, forged).contains("does not check out"), "a state that does not follow from its log is refused")
	check_eq(NetPartyRuns.seats_of(own), [{"id": "1", "name": "Ann", "fighter": "f_stoke"}, {"id": "2", "name": "Ben", "fighter": "f_dozer"}], "seats from the run")
	check_eq(NetPartyRuns.seat_for(own, "ben", "Ben"), "2", "the host finds its own seat by profile id")
	check_eq(NetPartyRuns.seat_for(own, "nobody", "Ann"), "1", "or by name")
	var loop_run: Dictionary = own.duplicate(true)
	(loop_run["players"][0] as Dictionary)["id"] = "p0"
	check(NetPartyRuns.seats_of(loop_run).is_empty(), "runs not started online have no seats")


## Before a match is built the client checks the arena: local content or an imported layout
## package must match the host's content hash; damaged or oversized packages are refused.
func test_arena_checks_before_the_match() -> void:
	var c := NetClient.new()
	_nodes.append(c)
	var good := Content.arena("the_gullet")
	var info := {"arena_id": "the_gullet", "arena_hash": good.content_hash(), "arena": good.to_dict()}
	check_eq(c._prepare_arena(info), "", "local core arena with the host's hash")
	check(info.get("_arena_def") == good, "the local ArenaDef is used")
	var other := {"arena_id": "the_gullet", "arena_hash": "0".repeat(64), "arena": good.to_dict()}
	check(c._prepare_arena(other).contains("differs from the host's"), "a different content hash blocks the match")
	var junk := PackedByteArray()
	junk.resize(4096)
	var forged := {"arena_id": "user:forged", "arena_hash": "x", "arena_package": junk}
	check(c._prepare_arena(forged).contains("was refused"), "a damaged arena package is refused")
	var huge := PackedByteArray()
	huge.resize(NetProtocol.MAX_ARENA_PACKAGE + 1)
	check(c._prepare_arena({"arena_id": "user:big", "arena_package": huge}).contains("too large"), "an oversized package is refused unopened")
	# a real package round trip: export a layout, import it into the sandbox, same hash
	var layout: Dictionary = Content.get_entry("arenas", "layout_gullet_classic").duplicate(true)
	for k in layout.keys():
		if str(k).begins_with("_"):
			layout.erase(k)
	layout.erase("example")
	layout["id"] = "user:loopback_cage"
	var a := ArenaDef.from_dict(layout, "user")
	var server := NetServer.new()
	_nodes.append(server)
	var bytes: PackedByteArray = server._arena_package_bytes(a)
	check(bytes.size() > 0 and bytes.size() <= NetProtocol.MAX_ARENA_PACKAGE, "layout packaged (%d bytes)" % bytes.size())
	var pinfo := {"arena_id": "user:loopback_cage", "arena_hash": a.content_hash(), "arena_package": bytes}
	check_eq(c._prepare_arena(pinfo), "", "imported into the sandbox and verified")
	check_eq(c.arena_imported, "user:loopback_cage")
	check(Content.arena("user:loopback_cage") == null, "sandboxed: not added to the player's own arenas")
	var wrong_id := {"arena_id": "user:other_cage", "arena_hash": a.content_hash(), "arena_package": bytes}
	check(c._prepare_arena(wrong_id).contains("does not contain"), "a package without the announced arena is refused")
	# the whole MATCH_START path: rules that fail the rules editor's validation, or a different
	# arena, end the session with a content reason before anything is built
	var broken_rules := {"name": "Broken", "mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "win": "none"}
	var cases := [
		["invalid rules", {"fighters": [], "arena": good.to_dict(), "arena_id": "the_gullet", "arena_hash": good.content_hash(), "rules": broken_rules}],
		["arena hash differs", {"fighters": [], "arena": good.to_dict(), "arena_id": "the_gullet", "arena_hash": "0".repeat(64),
			"rules": Content.get_entry("rules", "duel")}]]
	for cs in cases:
		var c2 := NetClient.new()
		c2.present = false
		c2.install_scene = false
		_nodes.append(c2)
		var got: Array = []
		c2.failed.connect(func(r: Dictionary) -> void: got.append(r))
		c2._on_match_start(cs[1])
		check(got.size() == 1 and int(got[0].get("code", 0)) == NetProtocol.R_CONTENT,
			"%s: the client leaves with a content reason (%s)" % [cs[0], str(got)])
		check(c2.state == NetClient.State.CLOSED and c2.match_info.is_empty(), "%s: no match was built" % cs[0])


## AI Lab policies fill bot slots in a server match (the server runs them; clients only see the
## fighter), and rules that fail the rules editor's validation never start.
func test_policy_bots_and_rules_validation_inprocess() -> void:
	var port := _port()
	var pid := "dev_biped_es_drill"
	var server := _server(port, {}, [{"rules": "duel", "arena": "the_gullet", "weight": 1, "min_players": 2,
		"bot_policy": pid, "rules_override": {"rounds": 1, "round_time": 30}}])
	var pol := PolicyLibrary.get_policy(pid)
	check(pol != null, "built-in policy available: %s" % PolicyLibrary.last_error(pid))
	var a := _client(port, {"name": "Solo"})
	check(await _until(func() -> bool: return a.state == NetClient.State.LOBBY, 6.0), "admitted")
	a.send_lobby(NetProtocol.LQ_READY, true)
	check(await _until(func() -> bool: return server.sim != null and a.my_fighter >= 0, 15.0), "match with a bot started")
	if server.sim != null and a.my_fighter >= 0 and pol != null:
		var bot := 1 - a.my_fighter
		var f := server.sim.fighters[bot]
		check_eq(f.controller_kind, "policy", "the bot slot runs the AI Lab policy")
		check_eq(f.creature.id, pol.creature, "as the policy's own creature")
		check(server.sim.input_sources[bot] is PolicyInputSource, "driven by PolicyInputSource on the server")
		check(await _until(func() -> bool: return str(a.replica.roster.get(bot, {}).get("kind", "")) == "policy", 3.0), "clients see a policy fighter, nothing to load")
		# the exact trained network is identified by its content hash (the checksum PolicyIO verifies)
		var want := str(pol.to_dict().get("checksum", ""))
		check_eq(want.length(), 64, "policy checksum is a sha256")
		var listed: Array = a.match_info.get("policies", [])
		check(listed.size() == 1 and int(listed[0].get("fighter", -1)) == bot and str(listed[0].get("id", "")) == pid
			and str(listed[0].get("hash", "")) == want, "MATCH_START names the policy and its hash: %s" % str(listed))
		var opt_hash := ""
		for o in server._policy_options():   # a listen host's lobby options (dedicated: playlist decides)
			if str(o.get("id", "")) == pid:
				opt_hash = str(o.get("hash", ""))
		check_eq(opt_hash, want, "the host's policy options carry the same hash")
	# invalid rules are refused by the authority with the validator's reason
	var bad := {"name": "Broken", "mode": "standard", "format": "duel", "teams": 2, "players": [2, 2], "win": "none"}
	var err := server.start_match("broken", bad, "the_gullet", 2, 2, 1, "regular", {})
	check(err.begins_with("invalid rules"), "invalid rules refused: %s" % err)
	check(NetProtocol.rules_problem(Content.get_entry("rules", "duel")) == "", "shipped presets validate")


## MOD-05 authority: the server repeats the content check on hello, so a client that lies about
## its packages (or skipped its own Mods.compare) is refused; client_only extras never block.
func test_content_check_on_server_inprocess() -> void:
	var port := _port()
	_server(port)
	var pk := Content.package_list()
	var liar := _client(port, {"name": "Liar",
		"test_packages": pk + [{"id": "phantom_mod", "version": "1.0.0", "hash": "ab".repeat(32), "client_only": false}]})
	var f: Array = []
	liar.failed.connect(func(r: Dictionary) -> void: f.append(r))
	check(await _until(func() -> bool: return not f.is_empty(), 6.0), "server refused the hello")
	if not f.is_empty():
		check_eq(int(f[0]["code"]), NetProtocol.R_CONTENT)
		check(str(f[0]["details"]).contains("phantom_mod 1.0.0"), "the extra package is named: %s" % str(f[0]["details"]))
	var dandy := _client(port, {"name": "Dandy",
		"test_packages": pk + [{"id": "fancy_hats", "version": "2.0.0", "hash": "cd".repeat(32), "client_only": true}]})
	check(await _until(func() -> bool: return dandy.state == NetClient.State.LOBBY, 6.0), "client_only packages never block joining")
	check(bool(dandy.content_check.get("ok", false)), "the client compared against the server's list first")
	check_eq(dandy.server_packages.size(), pk.size(), "the challenge carried the server's package list")


## A remote player's aim-assist setting travels with the join (and LQ_ASSIST) into the fighter
## modifiers of the authoritative simulation; forged levels are clamped.
func test_assist_reaches_server_fighter_inprocess() -> void:
	var port := _port()
	var server := _server(port)
	var a := _client(port, {"name": "Steady", "assist": 1.8})
	var b := _client(port, {"name": "Shaky", "assist": 9.0})
	check(await _until(func() -> bool: return a.state == NetClient.State.LOBBY and b.state == NetClient.State.LOBBY, 8.0), "both admitted")
	check(await _until(func() -> bool: return server.players.has(a.player_id) and server.players.has(b.player_id), 3.0), "players registered")
	check_eq((server.players[a.player_id] as NetPlayer).assist, 1.8, "hello carried the assist level")
	check_eq((server.players[b.player_id] as NetPlayer).assist, NetProtocol.MAX_ASSIST, "forged level clamped")
	b.send_lobby(NetProtocol.LQ_ASSIST, 0.5)
	check(await _until(func() -> bool: return is_equal_approx((server.players[b.player_id] as NetPlayer).assist, 0.5), 3.0), "LQ_ASSIST updates it")
	a.send_lobby(NetProtocol.LQ_READY, true)
	b.send_lobby(NetProtocol.LQ_READY, true)
	check(await _until(func() -> bool: return server.sim != null and a.my_fighter >= 0 and b.my_fighter >= 0, 10.0), "match started")
	if server.sim != null and a.my_fighter >= 0 and b.my_fighter >= 0:
		check_eq(float(server.sim.fighters[a.my_fighter].mods.get("assist", -1.0)), 1.8, "fighter mods carry the player's assist")
		check_eq(float(server.sim.fighters[b.my_fighter].mods.get("assist", -1.0)), 0.5, "updated level used for the match")


## Settings > Network apply live: smoothing to the running replica, timeout to the connection,
## LAN discovery to browsing and to the listen host's beacons; invite text for the host.
func test_network_settings_apply_live() -> void:
	var keys := ["network.interp", "network.timeout", "network.lan_discovery", "network.send_rate", "network.party_relay"]
	var saved := {}
	for k in keys:
		saved[k] = Settings.get_value(k)
	var port := _port()
	var dport := 32950 + randi() % 40
	Settings.set_value("network.lan_discovery", true, false, false)
	check_eq(Net.host({"port": port, "player_name": "Hosty", "lan_discovery": true, "discovery_port": dport, "max_players": 4,
		"password": "pw"}), OK, "listen server up")
	check(Net.server.lan != null, "host announces on the LAN")
	var inv := Net.invite_text()
	check(inv.contains(":%d" % port) and inv.contains("password"), "invite line names the port and the password hint: %s" % inv)
	check(Net.invite_text("example.org").contains("example.org:%d" % port), "invite with an explicit public address")
	var c := _client(port, {"name": "Guest", "password": "pw"})
	check(await _until(func() -> bool: return c.state == NetClient.State.LOBBY, 6.0), "guest admitted")
	Settings.set_value("network.lan_discovery", false, false, false)
	check(Net.server.lan == null, "switching LAN discovery off stops the host's beacons")
	check_eq(Net.start_lan_discovery(dport), ERR_UNAVAILABLE, "browsing refused while the setting is off")
	check(not Net.is_lan_discovery_active(), "no browser")
	Settings.set_value("network.lan_discovery", true, false, false)
	check(Net.server.lan != null, "switching it on resumes beacons")
	check(Net.is_lan_discovery_active(), "browsing the UI asked for starts by itself")
	Net.stop_lan_discovery()
	Settings.set_value("network.timeout", 7, false, false)
	check_eq(int(Net.server.cfg["timeout"]), 7, "host timeout follows the setting")
	Settings.set_value("network.send_rate", 20, false, false)
	check_eq(int(Net.server.cfg["snapshot_rate"]), 20, "update rate follows the setting")
	Settings.set_value("network.party_relay", false, false, false)
	check(not bool(Net.server.cfg["party_relay"]), "co-op relay can be switched off")
	Net.leave()
	# client side: the replica picks up the smoothing mode at once
	var port2 := port + 5
	_server(port2)
	check_eq(Net.join("127.0.0.1", port2, "", {"name": "Joiner"}), OK, "joining")
	check(await _until(func() -> bool: return Net.client != null and Net.client.state == NetClient.State.LOBBY, 6.0), "joined")
	Settings.set_value("network.interp", "high", false, false)
	check_eq(Net.client.replica.interp_mode, "high", "smoothing applied to the running connection")
	Settings.set_value("network.timeout", 9, false, false)
	check_eq(Net.client.transport.timeout_ms, 9000, "timeout applied to the running connection")
	Net.leave()
	for k in keys:
		Settings.set_value(k, saved[k], false, false)
