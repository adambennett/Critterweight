extends TestCase
## v0.9.18 Movesets on the network (protocol 7, docs/design/MOVESET_COMBAT.md §9): loadout requests
## are cleaned, roster entries carry the combat style and loadout, snapshots carry charges per
## cooldown slot, and an online client's mirror fighter shows the server's loadout.

const STREAM_LOADOUT := ["ember_jab", "fire_spin", "cinder_shot", "flamethrower"]
const MARTIAL_LOADOUT := ["spiral_hook", "pressure_palm", "meteor_hammer", "shockwave_kicks"]
var _sessions: Array = []


func after_each() -> void:
	for n in _sessions:
		if is_instance_valid(n):
			if n is NetServer:
				(n as NetServer).close(NetProtocol.R_SHUTDOWN, "", false, 50)
			n.queue_free()
	_sessions.clear()


func _until(pred: Callable, seconds := 8.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if pred.call():
			return true
		await get_tree().physics_frame
	return pred.call()


## Actual ENet sockets on loopback. These clients do not install an app scene or run a simulation.
func _session(combat: String) -> Array:
	var port := 47000 + OS.get_process_id() % 1000 + (10 if combat == "classic" else 0)
	var server := NetServer.new()
	add_child(server)
	_sessions.append(server)
	if not check_eq(server.start({"name": "Moves integration", "port": port, "lan_discovery": false,
		"max_players": 2, "lobby_time": 60, "results_time": 2, "timeout": 8}, true), OK, "server starts"):
		return []
	var playlist := NetPlaylist.from_dict({"id": "moves_integration", "name": "Moves integration", "entries": [
		{"rules": "duel", "arena": "the_gullet", "weight": 1, "rules_override": {
			"combat": combat, "rounds": 1, "round_time": 0, "intro_time": 0.2}}]}, "test")
	playlist.validate()
	server.set_playlist(playlist)
	var clients := []
	for fid in ["f_stoke", "f_varga"]:
		var client := NetClient.new()
		client.present = false
		client.install_scene = false
		add_child(client)
		_sessions.append(client)
		client.connect_to_server("127.0.0.1", port, {"name": fid, "creature": fid, "timeout_s": 8})
		clients.append(client)
	var a: NetClient = clients[0]
	var b: NetClient = clients[1]
	if not check(await _until(func() -> bool: return a.state == NetClient.State.LOBBY and b.state == NetClient.State.LOBBY), "both clients admitted"):
		return []
	a.send_lobby(NetProtocol.LQ_LOADOUT, STREAM_LOADOUT)
	b.send_lobby(NetProtocol.LQ_LOADOUT, MARTIAL_LOADOUT)
	if not check(await _until(func() -> bool:
		return server.players[a.player_id].loadout == STREAM_LOADOUT and server.players[b.player_id].loadout == MARTIAL_LOADOUT), "custom loadouts cross the client request channel"):
		return []
	a.send_lobby(NetProtocol.LQ_READY, true)
	b.send_lobby(NetProtocol.LQ_READY, true)
	if not check(await _until(func() -> bool:
		return a.state == NetClient.State.MATCH and b.state == NetClient.State.MATCH and server.sim != null \
			and server.sim.mode.phase == MatchMode.Phase.FIGHT), "both clients enter the authoritative fight"):
		return []
	return [server, a, b]


func _received(client: NetClient, kind: String, pool: String) -> Array:
	var out := []
	for item in client.replica._events:
		var ev: Dictionary = item["ev"]
		if str(ev.get("type", "")) == kind and str(ev.get("pool", "")) == pool:
			out.append(ev)
	return out


func test_custom_loadouts_streams_and_martial_inputs_over_loopback() -> void:
	var session: Array = await _session("moves")
	if session.is_empty():
		return
	var server: NetServer = session[0]
	var a: NetClient = session[1]
	var b: NetClient = session[2]
	var stoke: Fighter = server.sim.fighters[a.my_fighter]
	var varga: Fighter = server.sim.fighters[b.my_fighter]
	check_eq(stoke.loadout, STREAM_LOADOUT, "the server equips the nondefault ordinary loadout")
	check_eq(varga.loadout, MARTIAL_LOADOUT, "the server equips all four martial groups")
	check_eq(a.replica.roster[b.my_fighter]["loadout"], MARTIAL_LOADOUT, "the opponent receives the martial loadout")
	check_eq(b.replica.roster[a.my_fighter]["loadout"], STREAM_LOADOUT, "the opponent receives the ordinary loadout")
	stoke.rig.place(Vector3(0, 0, -1), 0.0)
	varga.rig.place(Vector3(0, 0, 1), PI)
	await wait_physics(12)
	var once := {"pressed": false, "holding": true}
	a.input_sampler = func(fi: FighterInput) -> void:
		fi.move = Vector3.ZERO
		fi.held = 0
		if bool(once["holding"]):
			fi.set_held(FighterInput.AB2, true)
			if not bool(once["pressed"]):
				once["pressed"] = true
				fi.press(FighterInput.AB2)
	var hp := varga.health
	check(await _until(func() -> bool: return varga.health < hp - 1.0 and _received(b, "effect", "flamethrower").size() >= 2),
		"slot-four input sustains fire, damages on the authority and delivers its effect ticks to the opponent")
	once["holding"] = false
	check(await _until(func() -> bool:
		return not _received(b, "sustain", "flamethrower").filter(func(e: Dictionary) -> bool: return str(e.get("phase", "")) == "end").is_empty()),
		"release crosses the input channel and ends the remote stream")
	var ticks := _received(b, "effect", "flamethrower")
	if not ticks.is_empty():
		check_near(float(ticks[0].get("radius", 0.0)), 3.2, 0.01, "the remote VFX receives the true range")
		check_near(float(ticks[0].get("cone_deg", 0.0)), 40.0, 0.01, "and the true cone angle")
	await wait_physics(240)
	var palm := {"pressed": false}
	b.input_sampler = func(fi: FighterInput) -> void:
		fi.move = Vector3.ZERO
		fi.held = 0
		fi.set_held(FighterInput.MMA_MOD2, true)
		if not bool(palm["pressed"]):
			palm["pressed"] = true
			fi.press(FighterInput.LIGHT)
	check(await _until(func() -> bool: return not _received(a, "effect", "pressure_palm").is_empty()),
		"the actual modifier-plus-limb input selects the equipped ranged Pressure Palm and replicates its effect")
	check(await _until(func() -> bool: return b.replica.snapshots_received >= 20), "snapshots keep flowing during both attacks")


func test_classic_rule_survives_the_same_loopback_setup() -> void:
	var session: Array = await _session("classic")
	if session.is_empty():
		return
	var server: NetServer = session[0]
	var a: NetClient = session[1]
	var b: NetClient = session[2]
	for f in server.sim.fighters:
		check_eq(f.combat_style, "classic", "the server honours the explicit Classic rule")
	check_eq(a.replica.roster[b.my_fighter]["combat"], "classic", "the ordinary client agrees on Classic")
	check_eq(b.replica.roster[a.my_fighter]["combat"], "classic", "the martial client agrees on Classic")
	check(server.sim.fighters[b.my_fighter].move_overrides.is_empty(), "Classic Varga keeps his original strikes")


func test_loadout_requests_are_cleaned() -> void:
	check_eq(NetProtocol.clean_loadout(["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire", "extra"]),
		["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"], "at most four moves")
	check_eq(NetProtocol.clean_loadout(["ok_id", "Bad Id!", "ok_id", 42]), ["ok_id", "42"], "plain ids only, no duplicates")
	check_eq(NetProtocol.clean_loadout("nope"), [], "not a list")


func test_roster_carries_combat_style_and_loadout() -> void:
	var w := NetWriter.new(NetProtocol.S_ROSTER)
	NetSnapshot.encode_roster(w, [{"slot": 0, "gen": 1, "creature": "f_stoke", "scale": 1.0, "team": 0, "name": "STOKE", "kind": "net",
		"despawned": false, "tags": [], "combat": "moves", "loadout": ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"]},
		{"slot": 1, "gen": 1, "creature": "f_dredge", "scale": 1.0, "team": 1, "name": "DREDGE", "kind": "bot",
		"despawned": false, "tags": [], "combat": "classic", "loadout": []}])
	var r := NetReader.new(w.data())
	r.u8()
	var out := NetSnapshot.decode_roster(r)
	check(r.ok and out.size() == 2, "decodes")
	check_eq(str(out[0]["combat"]), "moves", "style")
	check_eq(out[0]["loadout"], ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"], "loadout")
	check_eq(str(out[1]["combat"]), "classic", "Classic fighters say so")


func test_snapshot_carries_charges_and_the_mirror_shows_the_loadout() -> void:
	var sim := make_sim("", {"rounds": 1, "round_time": 0, "combat": "moves"}, [{"creature": "f_stoke", "team": 0}, {"creature": "f_dredge", "team": 1}])
	await step_sim(sim, 0.3)
	var f := sim.fighters[0]
	check_eq(f.loadout, ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"], "Stoke's default loadout")
	f.charges_left["m3"] = 0
	f.cooldown_left["m3"] = 4.5
	var gens := PackedByteArray()
	gens.resize(sim.fighters.size())
	gens.fill(1)
	var r := NetReader.new(NetSnapshot.encode_body(sim, gens))
	var snap := NetSnapshot.decode_body(r)
	check(not snap.is_empty(), "snapshot decodes")
	var fd: Dictionary = (snap["fighters"] as Array)[0]
	check(is_equal_approx(float((fd["cooldowns"] as Dictionary).get("m3", 0.0)), 4.5), "the cooldown of slot m3 travels")
	check_eq(int((fd["charges"] as Dictionary).get("m3", -1)), 0, "and its charges")
	check_eq(int((fd["charges"] as Dictionary).get("m2", -1)), 1, "a ready slot has its charge")
