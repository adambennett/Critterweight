extends Node
## Scripted network participant for the multi-process network tests (and manual debugging).
## Launched by main.gd for `--net-client`. Every process writes a JSON result file that the
## tests read while it runs (rewritten every 0.5 s and on exit).
##
##   --connect <host:port> | --net-host [--port p]      join a server / host a listen session
##   --name N --password P --spectate --creature id --token <hex> --ready
##   --script idle|aggressive|passive|cheater|wander     how the fighter is driven
##   --vote <index>|none                                 playlist vote in every lobby
##   --present                                           build the real NetMatchScene (headless)
##   --result <path> --quit-after <s> --stop-after-matches <n>
##   --drop-at <s>       abrupt disconnect (crash / pulled cable; the server reserves the slot)
##   --leave-at <s>      graceful leave
##   --blackhole-at <s>  conditioner drops everything from then on (timeout test)
##   --test-protocol N --test-game-version X --net-test-mod <dir>   incompatible-build simulation
##   --net-latency ms --net-jitter ms --net-loss f       network conditioner
##   host only: --host-start-after-players N --rules id --arena id --bots n --rounds n --round-time s
##   --user-rules <name>  host with a player-made rules preset (saved on this machine only, "user:...")
##   --assist <f>         aim-assist multiplier sent with the join (default: from Settings)
##   --app-request <type>  send one app request once in the lobby (app channel test)
##   --party               run the campaign's NetPartyTransport: broadcast one "hello" once another
##                         member is present and record the party messages received

const RESULT_EVERY_MS := 500

var args := PackedStringArray()
var result := {}
var result_path := ""
var script_name := "idle"
var started_ms := 0
var quit_after_ms := 120000
var stop_after_matches := 0
var drop_at_ms := -1
var leave_at_ms := -1
var blackhole_at_ms := -1
var vote_choice := "none"
var auto_ready := false
var hosting := false
var host_start_players := 1
var _host_started_match := 0
var _last_write := 0
var _ended := false
var _press_t := 0.0
var _phase_fight_since := -1
var _cheat_sent := 0
var _cheat_done := false
var _voted_for_match := -1
var _app_sent := false
var _kick_seen_ms := -1
var _events := {}
var _client: NetClient = null
var _server: NetServer = null
var _party = null                   ## NetPartyTransport (--party)
var _party_sent := false
var _rng := RandomNumberGenerator.new()
var _wander := Vector3.ZERO
var _wander_t := 0.0


func arg(flag: String, fallback := "") -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return fallback


func run(a: PackedStringArray) -> void:
	args = a
	name = "NetTestClient"
	_rng.seed = hash(arg("--name", "x")) + OS.get_process_id()
	started_ms = Time.get_ticks_msec()
	Engine.max_fps = 120
	result_path = arg("--result", Paths.file("captures", "net_client_result.json"))
	script_name = arg("--script", "idle")
	quit_after_ms = int(float(arg("--quit-after", "120")) * 1000.0)
	stop_after_matches = int(arg("--stop-after-matches", "0"))
	drop_at_ms = int(float(arg("--drop-at", "-1")) * 1000.0)
	leave_at_ms = int(float(arg("--leave-at", "-1")) * 1000.0)
	blackhole_at_ms = int(float(arg("--blackhole-at", "-1")) * 1000.0)
	vote_choice = arg("--vote", "none")
	auto_ready = args.has("--ready")
	result = {"name": arg("--name", "Tester"), "script": script_name, "pid": OS.get_process_id(), "connected": false,
		"failure": {}, "disconnect": {}, "welcome": {}, "matches": [], "results": [], "events": _events,
		"notices": [], "chat": [], "lobby_phases": [], "hits_dealt": 0, "hits_taken": 0, "damage_dealt": 0.0,
		"damage_taken": 0.0, "my_health_min": -1.0, "my_health_min_before_kick": -1.0, "health_seen": {}, "votes": [],
		"candidates_seen": [], "forged_sent": 0, "kicked": {}, "stats": {}, "snapshots": 0, "max_snapshot_slots": 0,
		"app_messages": [], "roster_updates": 0, "done": false, "exit_reason": "", "party_messages": [], "party_events": []}
	var mod_dir := arg("--net-test-mod", "")
	if mod_dir != "":
		_load_test_mod(mod_dir)
	if args.has("--net-host"):
		_start_host()
	else:
		_start_client()
	_write(true)


func _load_test_mod(dir: String) -> void:
	var mpath := dir.path_join("manifest.json")
	var man = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	if typeof(man) != TYPE_DICTIONARY:
		result["mod_error"] = "cannot read %s" % mpath
		return
	Content.reload([{"id": str(man["id"]), "version": str(man.get("version", "0.0.0")), "path": dir, "manifest": man}])
	result["content_hash"] = Content.content_hash()


func _conditioner_args() -> Array:
	var out: Array = []
	for f in ["--net-latency", "--net-jitter", "--net-loss"]:
		if args.has(f):
			out.append(f)
			out.append(arg(f, "0"))
	if args.has("--net-reorder"):
		out.append("--net-reorder")
	return out


# =====================================================================================
# Client
# =====================================================================================

func _start_client() -> void:
	var target := arg("--connect", "127.0.0.1:7777")
	var host := target.substr(0, target.rfind(":"))
	var port := int(target.substr(target.rfind(":") + 1))
	var opts := {"spectator": args.has("--spectate"), "creature": arg("--creature", ""), "name": arg("--name", "Tester"),
		"conditioner_args": _conditioner_args()}
	if args.has("--test-protocol"):
		opts["test_protocol"] = int(arg("--test-protocol"))
	if args.has("--test-game-version"):
		opts["test_game_version"] = arg("--test-game-version")
	var tok := arg("--token", "")
	if tok != "":
		opts["token"] = tok.hex_decode()
	if args.has("--timeout"):
		opts["timeout_s"] = int(arg("--timeout"))
	if args.has("--assist"):
		opts["assist"] = float(arg("--assist"))
	Net.joined.connect(_on_joined)
	Net.connection_failed.connect(_on_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.lobby_changed.connect(_on_lobby)
	Net.notice.connect(_on_notice)
	Net.chat_received.connect(func(id: int, n: String, t: String) -> void: _append_bounded("chat", {"from": id, "name": n, "text": t}))
	Net.match_starting.connect(_on_match_starting)
	Net.match_ended.connect(_on_match_ended)
	Net.app_message.connect(func(id: int, t: String, p: Dictionary) -> void: _append_bounded("app_messages", {"from": id, "type": t, "payload": p}))
	var err := Net.join(host, port, arg("--password", ""), opts)
	_client = Net.client
	if _client:
		_client.present = args.has("--present")
		_client.install_scene = args.has("--present")
		_client.input_sampler = _sample_input
		_client.notice_received.connect(func(_t: String) -> void: pass)
	result["join_error"] = err


func _on_joined(w: Dictionary) -> void:
	_start_party()
	result["connected"] = true
	result["welcome"] = w
	result["player_id"] = Net.local_peer_id()
	result["token_hex"] = Net.client.token.hex_encode() if Net.client else ""
	if auto_ready:
		Net.set_ready(true)
	var cr := arg("--creature", "")
	if cr != "":
		Net.set_creature(cr)


func _on_failed(r: Dictionary) -> void:
	result["failure"] = r
	_end("failed: %s" % NetProtocol.reason_name(int(r.get("code", 0))))


func _on_disconnected(r: Dictionary) -> void:
	result["disconnect"] = r
	if int(r.get("code", 0)) in [NetProtocol.R_KICKED, NetProtocol.R_VIOLATION, NetProtocol.R_FLOOD]:
		result["kicked"] = r
	_end("disconnected: %s" % NetProtocol.reason_name(int(r.get("code", 0))))


func _on_lobby(l: Dictionary) -> void:
	var ph := str(l.get("phase", ""))
	var phases: Array = result["lobby_phases"]
	if phases.is_empty() or str(phases.back()) != ph:
		phases.append(ph)
		if phases.size() > 200:
			phases.remove_at(0)
	result["lobby_last"] = {"phase": ph, "players": l.get("players", []), "countdown": l.get("countdown", -1),
		"playlist": l.get("playlist", {}), "settings": l.get("settings", {}), "match_id": l.get("match_id", 0)}
	var v: Dictionary = l.get("vote", {})
	if not v.is_empty() and bool(v.get("open", false)):
		var cands: Array = v.get("candidates", [])
		var keys: Array = []
		for c in cands:
			keys.append(str(c.get("key", "")))
		var seen: Array = result["candidates_seen"]
		if seen.is_empty() or str(seen.back()) != ",".join(PackedStringArray(keys)):
			seen.append(",".join(PackedStringArray(keys)))
		var mid := int(l.get("match_id", 0))
		if vote_choice != "none" and _voted_for_match != mid and not cands.is_empty():
			var idx := clampi(int(vote_choice), 0, cands.size() - 1) if vote_choice.is_valid_int() else cands.size() - 1
			Net.vote(idx)
			_voted_for_match = mid
			(result["votes"] as Array).append({"match_after": mid, "index": idx, "key": keys[idx]})
		if auto_ready and Net.client:
			var me := _lobby_player(l, Net.local_peer_id())
			if not me.is_empty() and not bool(me.get("ready", false)):
				Net.set_ready(true)
	if not _app_sent and args.has("--app-request") and ph != "":
		_app_sent = true
		Net.request(arg("--app-request"), {"hello": "world", "n": 3, "list": [1, 2, 3]})


func _lobby_player(l: Dictionary, pid: int) -> Dictionary:
	for p in l.get("players", []):
		if int(p.get("id", -1)) == pid:
			return p
	return {}


func _on_notice(t: String) -> void:
	_append_bounded("notices", {"t_ms": Time.get_ticks_msec() - started_ms, "text": t})
	if t.contains("kicked") and _kick_seen_ms < 0:
		_kick_seen_ms = Time.get_ticks_msec() - started_ms
		result["kick_notice_ms"] = _kick_seen_ms


func _on_match_starting(info: Dictionary) -> void:
	var rules: Dictionary = info.get("rules", {})
	(result["matches"] as Array).append({"match_id": info.get("match_id"), "you": info.get("you"), "rules_id": info.get("rules_id"),
		"arena_id": info.get("arena_id"), "mode": info.get("mode"), "entry": info.get("entry", {}), "fighters": (info.get("fighters", []) as Array).size(),
		"rules_name": str(rules.get("name", "")), "damage_mult": float(rules.get("damage_mult", 1.0)),
		"rules_known_here": not Content.get_entry("rules", str(info.get("rules_id", ""))).is_empty(),
		"arena_imported": _client.arena_imported if _client else "", "arena_name": (info.get("_arena_def").display_name if info.get("_arena_def") is ArenaDef else ""),
		"t_ms": Time.get_ticks_msec() - started_ms})
	_phase_fight_since = -1


func _on_match_ended(r: Dictionary) -> void:
	var slim := {"match_id": r.get("match_id"), "winner_team": r.get("winner_team"), "aborted": r.get("aborted", false),
		"mode": r.get("mode"), "rounds": r.get("rounds"), "players": r.get("players", {}), "entry": r.get("entry", {}),
		"fighters": r.get("fighters", []), "t_ms": Time.get_ticks_msec() - started_ms}
	(result["results"] as Array).append(slim)
	if stop_after_matches > 0 and (result["results"] as Array).size() >= stop_after_matches:
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if Net.client:
				Net.client.leave()
			_end("stopped after %d matches" % stop_after_matches))


func _append_bounded(key: String, v) -> void:
	var arr: Array = result[key]
	arr.append(v)
	if arr.size() > 300:
		arr.remove_at(0)


## Scripted "player" input (runs every physics tick inside NetClient, like LocalPlayerInput).
func _sample_input(fi: FighterInput) -> void:
	fi.move = Vector3.ZERO
	fi.held = 0
	if _client == null:
		return
	var me := _client.my_fighter
	var snap := _client.replica.latest()
	if snap.is_empty() or me < 0:
		return
	var fl: Array = snap["fighters"]
	if me >= fl.size() or int(fl[me]["gen"]) == 0:
		return
	var my_root: Vector3 = fl[me]["root"]
	var my_team := int(_client.replica.roster.get(me, {}).get("team", me))
	var best := -1
	var bd := INF
	for i in fl.size():
		if i == me or int(fl[i]["gen"]) == 0:
			continue
		var st := int(fl[i]["state"])
		if st == Fighter.State.KO or st == Fighter.State.INACTIVE or st == Fighter.State.DOWNED:
			continue
		if int(_client.replica.roster.get(i, {}).get("team", i)) == my_team:
			continue
		var d := my_root.distance_to(fl[i]["root"])
		if d < bd:
			bd = d
			best = i
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	_press_t += dt
	match script_name:
		"aggressive":
			if best < 0:
				return
			var to: Vector3 = fl[best]["root"] - my_root
			to.y = 0.0
			if bd > 1.15:
				fi.move = to.normalized()
			if bd < 1.7 and _press_t >= 0.26:
				_press_t = 0.0
				fi.press(FighterInput.HEAVY if _rng.randf() < 0.2 else FighterInput.LIGHT)
		"wander":
			_wander_t -= dt
			if _wander_t <= 0.0:
				_wander_t = _rng.randf_range(0.5, 2.0)
				var a := _rng.randf() * TAU
				_wander = Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(0.0, 1.0)
			fi.move = _wander
			if best >= 0 and bd < 1.6 and _press_t >= 0.4:
				_press_t = 0.0
				fi.press(FighterInput.LIGHT)
		"cheater":
			_cheat(fl, me, best, my_root)
		_:
			pass


## Protocol abuse once the fight is on: forged server messages, malformed input, unknown ids,
## a "damage" app request. The server must ignore/score all of it and eventually kick us.
func _cheat(fl: Array, me: int, victim: int, my_root: Vector3) -> void:
	var mode: Dictionary = _client.replica.latest().get("mode", {})
	if int(mode.get("phase", 0)) != MatchMode.Phase.FIGHT or _cheat_done:
		return
	if _phase_fight_since < 0:
		_phase_fight_since = Time.get_ticks_msec()
		return
	if Time.get_ticks_msec() - _phase_fight_since < 600:
		return
	# 1. forged server->client event claiming a 999-damage hit on the victim
	var w := NetWriter.new(NetProtocol.S_EVENTS)
	NetEventCodec.encode_batch(w, [{"type": "hit", "fighter": me, "target": victim, "damage": 999.0, "point": Vector3.ZERO,
		"normal": Vector3.UP, "blocked": false}], 0)
	_client.send_raw(NetProtocol.CH_EVENTS, w.data(), true)
	# 2. forged snapshot
	var w2 := NetWriter.new(NetProtocol.S_SNAPSHOT)
	w2.u16(1)
	w2.u32(1)
	w2.u16(0)
	_client.send_raw(NetProtocol.CH_SNAPSHOT, w2.data(), false)
	# 3. "damage" app request (valid message, must have no effect)
	_client.send_app("damage", {"target": victim, "amount": 999.0, "kill": true})
	# 4. malformed input: zero samples, then a truncated sample
	var w3 := NetWriter.new(NetProtocol.C_INPUT)
	w3.u16(5)
	w3.u32(0)
	w3.u8(0)
	_client.send_raw(NetProtocol.CH_INPUT, w3.data(), false)
	var w4 := NetWriter.new(NetProtocol.C_INPUT)
	w4.u16(6)
	w4.u32(0)
	w4.u8(3)
	w4.u8(127)
	_client.send_raw(NetProtocol.CH_INPUT, w4.data(), false)
	# 5. unknown message ids and a lobby request only the host may make
	_client.send_raw(NetProtocol.CH_CONTROL, PackedByteArray([200, 1, 2, 3]), true)
	var w5 := NetWriter.new(NetProtocol.C_LOBBY)
	w5.u8(NetProtocol.LQ_HOST_START)
	_client.send_raw(NetProtocol.CH_CONTROL, w5.data(), true)
	_cheat_sent += 7
	result["forged_sent"] = _cheat_sent
	if _cheat_sent >= 7 * 60:
		_cheat_done = true


# =====================================================================================
# Listen host
# =====================================================================================

func _start_host() -> void:
	hosting = true
	host_start_players = int(arg("--host-start-after-players", "1"))
	var cfg := {"port": int(arg("--port", "7777")), "player_name": arg("--name", "Host"), "lan_discovery": args.has("--lan"),
		"conditioner_args": _conditioner_args(), "results_time": int(arg("--results-time", "4"))}
	if args.has("--password"):
		cfg["password"] = arg("--password")
	for k in ["rules", "arena", "bots"]:
		if args.has("--" + k):
			cfg[k] = arg("--" + k)
	if args.has("--discovery-port"):
		cfg["discovery_port"] = int(arg("--discovery-port"))
	if args.has("--user-arena"):
		# a player-made layout (arena editor) saved on this machine only: players get it as a package
		var src: Dictionary = Content.get_entry("arenas", "layout_gullet_classic").duplicate(true)
		for k in src.keys():
			if str(k).begins_with("_"):
				src.erase(k)
		src.erase("example")
		src["id"] = "net_test_cage"
		src["name"] = arg("--user-arena")
		var saved_arena := ArenaLibrary.save_layout(src)
		result["user_arena"] = saved_arena
		cfg["arena"] = ArenaLibrary.content_id("net_test_cage")
	if args.has("--user-rules"):
		# a player-made preset (MCH-06) exists only on this machine: hosting sends it in full
		var base: Dictionary = Content.get_entry("rules", str(cfg.get("rules", "duel"))).duplicate(true)
		base["name"] = arg("--user-rules")
		base["damage_mult"] = 1.25
		base.erase("override")
		var saved := RulePresets.save(base)
		result["user_rules"] = saved
		cfg["rules"] = str(saved.get("id", ""))
	var err := Net.host(cfg)
	result["host_error"] = err
	if err != OK:
		result["failure"] = Net.last_failure
		_end("host failed")
		return
	_server = Net.server
	_start_party()
	result["connected"] = true
	result["player_id"] = 1
	var ov := {}
	if args.has("--rounds"):
		ov["rounds"] = int(arg("--rounds"))
	if args.has("--round-time"):
		ov["round_time"] = float(arg("--round-time"))
	if not ov.is_empty():
		Net.host_set("rules_override", ov)
	Net.match_starting.connect(_on_host_match_started)
	Net.match_ended.connect(_on_match_ended)
	Net.notice.connect(_on_notice)
	Net.app_request.connect(func(id: int, t: String, p: Dictionary) -> void:
		_append_bounded("app_messages", {"from": id, "type": t, "payload": p})
		Net.send_app(id, "echo." + t.replace(".", "_"), {"got": p}))


func _on_host_match_started(info: Dictionary) -> void:
	(result["matches"] as Array).append({"match_id": info.get("match_id"), "rules_id": info.get("rules_id"),
		"arena_id": info.get("arena_id"), "fighters": (info.get("fighters", []) as Array).size(), "t_ms": Time.get_ticks_msec() - started_ms})
	# fighter modifiers as the authoritative simulation applies them (aim assist of remote players)
	if _server and _server.sim:
		var mods: Array = []
		for f in _server.sim.fighters:
			mods.append({"name": f.display_name, "kind": f.controller_kind, "assist": float(f.mods.get("assist", 1.0))})
		result["fighter_mods"] = mods
	var me := Net.local_fighter()
	if me >= 0 and _server.sim and script_name != "idle":
		_server.sim.set_input_source(me, HostScript.new(script_name))
	result["host_fighter"] = me


class HostScript:
	extends InputSource
	var mode := "aggressive"
	var _t := 0.0

	func _init(m: String) -> void:
		mode = m

	func label() -> String:
		return "Scripted host"

	func poll(f: Fighter, sim, dt: float) -> void:
		_t += dt
		f.input.move = Vector3.ZERO
		f.input.held = 0
		if mode != "aggressive":
			return
		var best: Fighter = null
		var bd := INF
		for o: Fighter in (sim as MatchSim).fighters:
			if o == f or o.is_out() or o.team == f.team:
				continue
			var d := o.pos().distance_to(f.pos())
			if d < bd:
				bd = d
				best = o
		if best == null:
			return
		var to := best.pos() - f.pos()
		to.y = 0.0
		if bd > 1.15:
			f.input.move = to.normalized()
		if bd < 1.7 and _t >= 0.26:
			_t = 0.0
			f.input.press(FighterInput.LIGHT)


# =====================================================================================
# Loop / results
# =====================================================================================

func _physics_process(_dt: float) -> void:
	if _ended:
		return
	var t := Time.get_ticks_msec() - started_ms
	if hosting and _server and _server.phase == NetServer.PHASE_LOBBY:
		var remote := 0
		for p in _server.players.values():
			if (p as NetPlayer).peer > 0 and (p as NetPlayer).connected and not (p as NetPlayer).spectator:
				remote += 1
		if remote + 1 >= host_start_players and _host_started_match <= _server.match_id:
			_host_started_match = _server.match_id + 1
			var e := Net.host_start()
			if e != "":
				result["host_start_error"] = e
	if _client and _client.state == NetClient.State.MATCH:
		_track_match()
	if drop_at_ms >= 0 and t >= drop_at_ms and _client:
		drop_at_ms = -1
		result["dropped_at_ms"] = t
		_client.drop()
		return
	if leave_at_ms >= 0 and t >= leave_at_ms:
		leave_at_ms = -1
		Net.leave()
		_end("left")
		return
	if blackhole_at_ms >= 0 and t >= blackhole_at_ms and _client and _client.conditioner:
		blackhole_at_ms = -1
		_client.conditioner.set_blackhole(true)
		result["blackhole_at_ms"] = t
	if t >= quit_after_ms:
		_end("quit-after")
		return
	if Time.get_ticks_msec() - _last_write >= RESULT_EVERY_MS:
		_write(false)


func _track_match() -> void:
	var rep := _client.replica
	result["snapshots"] = rep.snapshots_received
	result["roster_updates"] = rep.roster_updates
	var snap := rep.latest()
	if snap.is_empty():
		return
	var fl: Array = snap["fighters"]
	result["max_snapshot_slots"] = maxi(int(result["max_snapshot_slots"]), fl.size())
	var hs: Dictionary = result["health_seen"]
	for i in fl.size():
		if int(fl[i]["gen"]) == 0:
			continue
		var h := float(fl[i]["health"])
		var k := str(i)
		hs[k] = minf(float(hs.get(k, h)), h)
	var me := _client.my_fighter
	if me >= 0 and me < fl.size() and int(fl[me]["gen"]) != 0:
		var hm := float(fl[me]["health"])
		result["my_health_min"] = hm if float(result["my_health_min"]) < 0.0 else minf(float(result["my_health_min"]), hm)
		if _kick_seen_ms < 0:
			result["my_health_min_before_kick"] = hm if float(result["my_health_min_before_kick"]) < 0.0 else minf(float(result["my_health_min_before_kick"]), hm)
	if not _client.present:
		for ev in rep.pop_due_events():
			_count_event(ev)


func _count_event(ev: Dictionary) -> void:
	var ty := str(ev.get("type", ""))
	_events[ty] = int(_events.get(ty, 0)) + 1
	if ty == "hit" and _client:
		var me := _client.my_fighter
		if int(ev.get("fighter", -1)) == me and me >= 0:
			result["hits_dealt"] = int(result["hits_dealt"]) + 1
			result["damage_dealt"] = float(result["damage_dealt"]) + float(ev.get("damage", 0.0))
		if int(ev.get("target", -1)) == me and me >= 0:
			result["hits_taken"] = int(result["hits_taken"]) + 1
			result["damage_taken"] = float(result["damage_taken"]) + float(ev.get("damage", 0.0))


func _start_party() -> void:
	if _party != null or not args.has("--party"):
		return
	_party = NetPartyTransport.new()
	_party.message_received.connect(func(f: String, t: String, p: Dictionary) -> void:
		_append_bounded("party_messages", {"from": f, "type": t, "payload": p}))
	_party.peer_joined.connect(func(peer: String) -> void: _append_bounded("party_events", "joined:" + peer))
	_party.peer_left.connect(func(peer: String, r: String) -> void: _append_bounded("party_events", "left:%s:%s" % [peer, r]))


func _process(dt: float) -> void:
	if _party != null and not _party_sent and not (_party.peers() as Array).is_empty():
		_party_sent = true
		result["party_local_id"] = _party.local_id()
		result["party_peers"] = _party.peers()
		_party.send("", "hello", {"name": str(result["name"])})
	if _client and _client.present and _client.scene:
		# presentation consumes events itself; count them from the replica's stats instead
		result["events_total"] = _client.replica.events_received


func _end(reason: String) -> void:
	if _ended:
		return
	_ended = true
	result["exit_reason"] = reason
	result["done"] = true
	_write(true)
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit(0))


func _write(_force: bool) -> void:
	_last_write = Time.get_ticks_msec()
	result["t_ms"] = Time.get_ticks_msec() - started_ms
	if _client and is_instance_valid(_client):
		result["stats"] = _client.stats()
	elif _server and is_instance_valid(_server):
		result["server_status"] = _server.status()
	var tmp := result_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(result_path)
	DirAccess.rename_absolute(tmp, result_path)
