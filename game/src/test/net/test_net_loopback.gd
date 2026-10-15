extends TestCase
## NET-01/04/06/07/11 (in-process, LOOPBACK 127.0.0.1): a NetServer and NetClients in one process
## talking over real ENet sockets. Fast coverage of the session logic; the multi-process tests
## (test_net_multiprocess.gd) repeat the important flows with independent processes.

var _nodes: Array = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			if n is NetServer and (n as NetServer).is_running():
				(n as NetServer).close(NetProtocol.R_SHUTDOWN, "", false, 50)
			n.queue_free()
	_nodes.clear()


func _port() -> int:
	return 31000 + (OS.get_process_id() % 1200) * 7 + randi() % 5


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
