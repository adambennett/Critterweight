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
##              --no-sudden-death (--creature id works for the host's own fighter too)
##   --user-rules <name>  host with a player-made rules preset (saved on this machine only, "user:...")
##   --assist <f>         aim-assist multiplier sent with the join (default: from Settings)
##   --app-request <type>  send one app request once in the lobby (app channel test)
##   --party               run the campaign's NetPartyTransport: broadcast one "hello" once another
##                         member is present and record the party messages received
##   --party-run <run id> --party-profile <id> [--party-seat s] [--party-wait s]
##                         resume a suspended co-op party run through the lobby (NetPartyRuns):
##                         a host offers it from its party save, a member claims its seat by run
##                         id; both vote the first route and stop once the run moved on
##   --party-ui            play an online party run through the REAL UI: the lobby screen, OnlineFlow,
##                         CoopFlow and the campaign screens, with PartyPilot pressing their buttons
##                         (fights: the scripted inputs above). Host: --party-new <variant>:<format>
##                         [--party-seed n --party-difficulty d --host-start-after-players n] deals a
##                         run, or --party-offer <run id> offers a saved one; it starts once every seat
##                         is taken. Member: takes its seat from the lobby. Per-player choices:
##                         --party-route s1,s2,.. (per stop: a node type wanted or an exact node id,
##                         in map order), --party-pick first|last|skip, --party-shop buy|leave,
##                         --party-event first|last [--party-event-wait s].
##                         Scripted moments (fight n = the n-th fight this process plays in):
##                         --party-forfeit-fight n (host forfeits fight n),
##                         --party-drop-in-fight n (member drops mid-fight n), --party-ref-timeout-fight
##                         n (calls a ref timeout from the pause menu in fight n, ends it 3 s later),
##                         --party-suspend-after n (host suspends at the map after n fights),
##                         --party-host-leave-in-fight n (the host leaves the session 8 s into fight n),
##                         --party-quit-after-fights n, --party-meta id=level,.. (this player's Cannery
##                         levels), --party-pace s, --party-capture <dir> (windowed: a JPG of every
##                         screen and fight)

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
var _prun: NetPartyRuns = null      ## --party-run
var _pilot: PartyPilot = null       ## --party-ui
var _rng := RandomNumberGenerator.new()
var _wander := Vector3.ZERO
var _wander_t := 0.0
var _bench_t := 0.0


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
		"app_messages": [], "roster_updates": 0, "done": false, "exit_reason": "", "party_messages": [], "party_events": [], "party_run_messages": []}
	var mod_dir := arg("--net-test-mod", "")
	if mod_dir != "":
		_load_test_mod(mod_dir)
	if args.has("--party-ui"):
		# the name the lobby shows and party seats are matched by (NetPartyRuns.seat_for)
		Settings.set_value("network.player_name", arg("--name", "Tester"))
		if args.has("--party-meta"):
			var ups := {}
			for pair in arg("--party-meta").split(",", false):
				var kv := pair.split("=")
				if kv.size() == 2:
					ups[kv[0]] = int(kv[1])
			CampaignProgression.ensure_fields(Profiles.current)
			Profiles.current["camp"]["upgrades"] = ups
		result["party_ui"] = {}
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
	if tok != "" and not tok.begins_with("--"):   # an empty value is dropped from the command line
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
	Net.app_message.connect(func(id: int, t: String, p: Dictionary) -> void:
		# co-op campaign traffic (whole run states) is recorded by the party run itself
		if not t.begins_with(NetPartyTransport.PREFIX):
			_append_bounded("app_messages", {"from": id, "type": t, "payload": p}))
	var err := Net.join(host, port, arg("--password", ""), opts)
	_client = Net.client
	if _client:
		_client.present = args.has("--present") or args.has("--party-ui")
		_client.install_scene = _client.present
		_client.input_sampler = _sample_input
		_client.notice_received.connect(func(_t: String) -> void: pass)
	result["join_error"] = err
	if args.has("--party-ui"):
		OnlineFlow.begin()      # what the Online screen does after join()
		_pilot = PartyPilot.new(self, false)


func _on_joined(w: Dictionary) -> void:
	_start_party()
	if args.has("--party-ui") and (App.top_screen() == null or App.top_screen().screen_name != "lobby"):
		App.goto("lobby")
	result["connected"] = true
	result["welcome"] = w
	result["player_id"] = Net.local_peer_id()
	result["token_hex"] = Net.client.token.hex_encode() if Net.client else ""
	if auto_ready:
		Net.set_ready(true)
	var cr := arg("--creature", "")
	if cr != "":
		Net.set_creature(cr)
	if args.has("--cosmetics"):
		# "slot=id,slot=id": shown to the other players (presentation only)
		var eq := {}
		for pair in arg("--cosmetics").split(",", false):
			var kv := pair.split("=")
			if kv.size() == 2:
				eq[kv[0]] = kv[1]
		Net.set_cosmetics(eq)


func _on_failed(r: Dictionary) -> void:
	result["failure"] = r
	_end("failed: %s" % NetProtocol.reason_name(int(r.get("code", 0))))


func _on_disconnected(r: Dictionary) -> void:
	result["disconnect"] = r
	if int(r.get("code", 0)) in [NetProtocol.R_KICKED, NetProtocol.R_VIOLATION, NetProtocol.R_FLOOD]:
		result["kicked"] = r
	var why := "disconnected: %s" % NetProtocol.reason_name(int(r.get("code", 0)))
	if _pilot != null:
		# --party-ui: let the UI react first (OnlineFlow's dialog), the pilot records what the player
		# was told, then ends (unless it is already ending for its own scripted reason). This runs
		# before OnlineFlow's handler (connected first): the run's last state is recorded here.
		_pilot._record()
		if _pilot._end_t < 0.0:
			_pilot.info["end_reason"] = why
			_pilot._end_t = 2.0
		return
	_end(why)


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
	if int(fl[me]["state"]) == Fighter.State.INACTIVE and script_name == "aggressive":
		# a tag partner on the bench (co-op campaign): assists, cheers, then tags back in - like a
		# player, at a moment the teammate in the cage is free to tag out (not mid-attack)
		_bench_t += dt
		if fmod(_bench_t, 2.5) < dt:
			fi.press(FighterInput.AB1)
		if fmod(_bench_t, 4.0) < dt:
			fi.press(FighterInput.TAUNT)
		if _bench_t > 3.0 and fmod(_bench_t, 0.25) < dt:
			for i in fl.size():
				if i == me or int(fl[i]["gen"]) == 0 or int(_client.replica.roster.get(i, {}).get("team", i)) != my_team:
					continue
				if int(fl[i]["state"]) in [Fighter.State.NEUTRAL, Fighter.State.GUARD]:
					fi.press(FighterInput.TARGET)
					break
		return
	_bench_t = 0.0
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
	for k in ["rules", "arena", "bots", "creature"]:
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
		base["damage_mult"] = 2.0   # also keeps the test's KO well inside the round with roster fighters
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
	if arg("--party-run", "") != "":
		_party_run_host_open()
	if args.has("--party-ui"):
		OnlineFlow.begin()      # what the Online screen does after host()
		App.goto("lobby")
		_pilot = PartyPilot.new(self, true)
	var ov := {}
	if args.has("--rounds"):
		ov["rounds"] = int(arg("--rounds"))
	if args.has("--round-time"):
		ov["round_time"] = float(arg("--round-time"))
	if args.has("--no-sudden-death"):
		ov["sudden_death"] = false   # a draw at the bell ends the match (tests with a fixed time budget)
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
	var _bench := 0.0

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
		if f.state == Fighter.State.INACTIVE:
			# a tag partner on the bench (co-op campaign): assists, cheers, then tags back in when
			# the teammate in the cage is free to tag out (not mid-attack)
			_bench += dt
			if fmod(_bench, 2.5) < dt:
				f.input.press(FighterInput.AB1)
			if fmod(_bench, 4.0) < dt:
				f.input.press(FighterInput.TAUNT)
			if _bench > 3.0 and fmod(_bench, 0.25) < dt:
				for o: Fighter in (sim as MatchSim).fighters:
					if o != f and o.team == f.team and not o.is_out() and o.state in [Fighter.State.NEUTRAL, Fighter.State.GUARD]:
						f.input.press(FighterInput.TARGET)
						break
			return
		_bench = 0.0
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
	# a host offering a party run never starts versus matches on its own
	if hosting and _server and _server.phase == NetServer.PHASE_LOBBY and arg("--party-run", "") == "" and not args.has("--party-ui"):
		var remote := 0
		var unready := 0
		for p in _server.players.values():
			if (p as NetPlayer).peer > 0 and (p as NetPlayer).connected and not (p as NetPlayer).spectator:
				remote += 1
				if not (p as NetPlayer).ready:
					unready += 1
		var limit := int(arg("--host-auto-start-limit", "0"))
		var ready_ok := unready == 0 or not args.has("--host-start-when-ready")
		if remote + 1 >= host_start_players and ready_ok and _host_started_match <= _server.match_id and (limit <= 0 or _server.match_id < limit):
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
	if _client.scene != null and not result.has("dressed"):
		# how the presenting client dressed each fighter (cosmetics from MATCH_START)
		var dressed := {}
		for i in (_client.scene.views as Array).size():
			var v = _client.scene.views[i]
			if v is CreatureView:
				var ids: Array = []
				for a in (v as CreatureView).cosmetics():
					ids.append(str(a.get("id", "")))
				dressed[str(i)] = {"attachments": ids, "juice": (v as CreatureView).juice_color.to_html(false)}
		if not dressed.is_empty():
			result["dressed"] = dressed
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
		# the fighter's full health (it starts full): tests compare against it, not a fixed number
		result["my_health_max"] = maxf(float(result.get("my_health_max", 0.0)), hm)
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
	if arg("--party-run", "") != "" and not _ended:
		_party_run_step(dt)
	if _pilot != null and not _ended:
		_pilot.step(dt)


# =====================================================================================
# Party run (--party-run <run id>): resume a suspended co-op party run through the lobby
# =====================================================================================

func _party_runs() -> NetPartyRuns:
	if _prun == null:
		var prof := Profiles.default_profile(arg("--party-profile", "default"), arg("--name", "Tester"))
		_prun = NetPartyRuns.new(CampaignCatalog.new(Content, "dev_biped"), RunStore.new(), prof)
	return _prun


## Host: offers the run as soon as the session is up.
func _party_run_host_open() -> void:
	var pr := {"role": "host", "open_error": _party_runs().open_as_host(arg("--party-run"), arg("--party-seat", ""))}
	pr["seat"] = _prun.seat
	result["party_run"] = pr


func _party_run_step(dt: float) -> void:
	var pr: Dictionary = result.get("party_run", {"role": "host" if hosting else "member"})
	var runs := _party_runs()
	var rid := arg("--party-run")
	if not hosting and runs.role == "" and not pr.has("claim_error") and str(Net.party().get("run_id", "")) == rid:
		pr["claim_error"] = runs.claim(arg("--party-seat", ""))
		pr["offer"] = Net.party()
	if hosting and runs.role == "host" and runs.session == null:
		# start once every member is back (or after --party-wait s without them, default 30)
		if runs.missing_seats().is_empty() or Time.get_ticks_msec() - started_ms > int(float(arg("--party-wait", "30")) * 1000.0):
			pr["started_with_missing"] = runs.missing_seats()
			pr["start_error"] = runs.start_host()
			if runs.session:
				runs.session.transport.message_received.connect(_on_party_run_message)
	var had := runs.session != null
	runs.tick(dt)
	var s := runs.session
	if s != null and not had and not hosting:
		s.transport.message_received.connect(_on_party_run_message)
	pr["seat"] = runs.seat
	pr["net_seat"] = Net.party_seat()
	pr["members"] = Net.member_ids()
	pr["error"] = runs.error
	if s != null and s.ctrl != null:
		var st: Dictionary = s.ctrl.state
		var pos := str(st.get("position", ""))
		if not pr.has("start_position"):
			pr["start_position"] = pos
			pr["start_log_size"] = (st.get("log", []) as Array).size()
		# route vote: once per map position (members also when the host opens it)
		var opts: Array = s.ctrl.available_nodes() if s.ctrl.phase() == "map" else []
		if not opts.is_empty() and str(pr.get("voted_at", "-")) != "@" + pos and (not hosting or s.vote != null):
			pr["voted_at"] = "@" + pos
			pr["voted"] = str(opts[0])
			s.act("vote", {"node": str(opts[0])})
		pr["frames_with_run"] = int(pr.get("frames_with_run", 0)) + 1
		pr["me"] = s.me
		pr["host_id"] = s.host_id
		pr["is_host"] = s.is_host()
		pr["run_id"] = str(st.get("run_id", ""))
		pr["position"] = pos
		pr["phase"] = s.ctrl.phase()
		pr["log_size"] = (st.get("log", []) as Array).size()
		var ps: Array = []
		for p in s.ctrl.players():
			ps.append({"id": str(p.get("id", "")), "bot": bool(p.get("bot", false)), "connected": bool(p.get("connected", true))})
		pr["players"] = ps
		if pos != str(pr["start_position"]) and s.ctrl.phase() != "map" and not pr.has("done_ms"):
			pr["done_ms"] = Time.get_ticks_msec() - started_ms
	result["party_run"] = pr
	if pr.has("done_ms") and Time.get_ticks_msec() - started_ms - int(pr["done_ms"]) > 2000:
		_end("party run moved on")


func _on_party_run_message(from: String, type: String, payload: Dictionary) -> void:
	_append_bounded("party_run_messages", {"from": from, "type": type, "t_ms": Time.get_ticks_msec() - started_ms,
		"counts": payload.get("counts", {}) if type == "vote_result" else {},
		"position": str(payload.get("state", {}).get("position", "")) if type == "run_state" else ""})
	# a member votes when the host opens the vote (and once on arrival, in _party_run_step)
	if type == "vote_open" and _prun != null and _prun.session != null and not hosting:
		var opts: Array = payload.get("options", [])
		if not opts.is_empty():
			_prun.session.act("vote", {"node": str(opts[0])})


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
	var text := JSON.stringify(result, "\t")
	var tmp := result_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	# On Windows the test runner may hold the result file open for a moment while it polls it; then
	# the replace fails. Retry briefly, and as a last resort write in place (the reader tolerates a
	# partial file and polls again) - losing the final write made a refused client look silent.
	for attempt in 8:
		if FileAccess.file_exists(result_path):
			DirAccess.remove_absolute(result_path)
		if DirAccess.rename_absolute(tmp, result_path) == OK:
			return
		OS.delay_msec(15)
	var g := FileAccess.open(result_path, FileAccess.WRITE)
	if g:
		g.store_string(text)
		g.close()
	DirAccess.remove_absolute(tmp)


# =====================================================================================
# --party-ui: an online party run played through the real lobby and campaign screens
# =====================================================================================

## Presses the real screens' buttons like a player would (one action every --party-pace s): the
## lobby's seat / start / offer, the map's route vote, reward picks, events, the shop, rest and the
## run summary; scripted moments (forfeit, drop, suspend) at given fights. Records what it saw and
## did into result["party_ui"] for the multi-process tests.
class PartyPilot:
	extends RefCounted
	var tc = null                       ## the NetTestClient node
	var host := false
	var pace := 0.6
	var info := {"screens": [], "decisions": [], "fights": [], "notes": []}
	var dealt := false
	var started := false
	var finished := false
	var _wait := 1.0
	var _record_t := 0.0
	var _bought := {}
	var _event_seen := {}
	var _claim_ms := -100000
	var _ready_ms := -1
	var _offer_seen_ms := -1
	var _voted_at := ""
	var _match_seen := -1
	var _fight_t := 0.0
	var _ev_cursor := 0
	var _camp_events := {}
	var _start_ms := 0
	var _dropped := false
	var _forfeited := false
	var _suspended := false
	var _left := false
	var _timeout_at := -1.0
	var _timeout_done := false
	var _end_t := -1.0
	var _shots := 0
	var _shot_screen := ""

	func _init(client, is_host: bool) -> void:
		tc = client
		host = is_host
		pace = float(tc.arg("--party-pace", "0.6"))
		_start_ms = Time.get_ticks_msec()
		info["role"] = "host" if host else "member"
		App.screen_changed.connect(_on_screen)

	func _on_screen(screen_name: String) -> void:
		var arr: Array = info["screens"]
		if arr.is_empty() or str(arr.back()) != screen_name:
			arr.append(screen_name)
		# capturing: let the new screen be photographed before this player acts on it
		_wait = maxf(_wait, 2.0 if str(tc.arg("--party-capture", "")) != "" else pace)
		_capture(screen_name, 1.4)

	func _note(text: String) -> void:
		(info["notes"] as Array).append({"t_ms": Time.get_ticks_msec() - _start_ms, "text": text})

	func _decide(kind: String, detail: String) -> void:
		var c := _ctrl()
		(info["decisions"] as Array).append({"kind": kind, "detail": detail, "position": str(c.state.get("position", "")) if c else "",
			"t_ms": Time.get_ticks_msec() - _start_ms})

	func _ctrl() -> RunController:
		var pr: NetPartyRuns = OnlineFlow.party
		return pr.session.ctrl if pr != null and pr.session != null else null

	func step(dt: float) -> void:
		_record_t -= dt
		if _record_t <= 0.0:
			_record_t = 0.5
			_record()
		if _end_t >= 0.0:
			_end_t -= dt
			if _end_t < 0.0:
				_record()
				tc._end(str(info.get("end_reason", "done")))
			return
		if host:
			_host_lobby()
		else:
			_member_lobby()
		_fight_moments(dt)
		_scripted_ends()
		_wait -= dt
		if _wait > 0.0:
			return
		_wait = pace
		var top: Screen = App.top_screen()
		if top == null:
			return
		var modal := _modal(top)
		if modal != null:
			var bs: Array = modal.get("_buttons")
			if not bs.is_empty():
				_note("modal: pressed %s" % (bs[0] as Button).text)
				(bs[0] as Button).pressed.emit()
				_capture(top.screen_name, 1.0)
			return
		match top.screen_name:
			"run_map":
				_vote(top)
			"reward":
				_reward(top)
			"event":
				_event(top)
			"shop":
				_shop(top)
			"rest":
				_rest(top)
			"run_summary":
				_summary(top)
			"dialog":
				# a message box (e.g. a refused seat): read it, press its first button
				var bs := _buttons_under(top)
				if not bs.is_empty():
					_note("dialog: %s - %s" % [str(top.params.get("title", "")), str(top.params.get("body", "")).left(160)])
					info["dialog"] = {"title": str(top.params.get("title", "")), "body": str(top.params.get("body", ""))}
					(bs[0] as Button).pressed.emit()

	func _buttons_under(n: Node) -> Array:
		var out: Array = []
		var stack: Array = [n]
		while not stack.is_empty():
			var c: Node = stack.pop_front()
			if c is Button and not (c as Button).disabled:
				out.append(c)
			stack.append_array(c.get_children())
		return out

	func _modal(top: Node) -> Node:
		for c in top.get_children():
			if c is CampaignUI.Modal and not (c as CampaignUI.Modal).closing:
				return c
		return null

	# --- lobby ---------------------------------------------------------------------------

	func _host_lobby() -> void:
		if dealt:
			var pr: NetPartyRuns = OnlineFlow.party
			if not started and pr != null and pr.role == "host":
				var waited := (Time.get_ticks_msec() - _start_ms) / 1000.0
				if pr.missing_seats().is_empty() or waited > float(tc.arg("--party-wait", "150")):
					info["started_with_missing"] = pr.missing_seats()
					var top: Screen = App.top_screen()
					if top != null and top.screen_name == "lobby":
						top.call("_start_match")       # the lobby's Start (Y / R) starts the party run
					else:
						pr.start_host()
					started = pr.is_live()
					info["start_ms"] = Time.get_ticks_msec() - _start_ms
			return
		var top2: Screen = App.top_screen()
		if top2 == null or top2.screen_name != "lobby":
			return
		var offer := str(tc.arg("--party-offer", ""))
		if offer != "":
			top2.call("_offer_saved", offer)          # the lobby's "Offer this run"
			dealt = OnlineFlow.party != null
			info["offer_error"] = "" if dealt else "the lobby could not offer the run"
			if dealt:
				info["run_id"] = OnlineFlow.party.run_id
			return
		var need := int(tc.arg("--host-start-after-players", "2"))
		var here := 0
		for p in Net.lobby().get("players", []):
			if bool((p as Dictionary).get("connected", false)) and not bool((p as Dictionary).get("spectator", false)):
				here += 1
		if here < need:
			_ready_ms = -1
			return
		# like a host who looks at the lobby first: the players' Cannery levels arrive with their join
		if _ready_ms < 0:
			_ready_ms = Time.get_ticks_msec()
		if Time.get_ticks_msec() - _ready_ms < 3000:
			return
		var spec := str(tc.arg("--party-new", "off_the_street:simultaneous")).split(":")
		var cat := CampaignFlow.make_catalog(false)
		var cfg := LobbyScreen.party_config(cat, spec[0], spec[1] if spec.size() > 1 else "simultaneous", str(tc.arg("--party-difficulty", "sparring")))
		cfg["seed"] = int(tc.arg("--party-seed", "1"))
		cfg["seeded"] = true
		var pr2 := NetPartyRuns.new(cat, RunStore.new(), Profiles.current)
		var err := pr2.start_new_as_host(cfg)
		info["deal_error"] = err
		if err == "":
			OnlineFlow.set_party(pr2)
			dealt = true
			info["dealt_players"] = cfg["players"]
			info["run_id"] = pr2.run_id
			top2.call("_refresh", true)

	func _member_lobby() -> void:
		if OnlineFlow.party != null or finished:
			return
		var top: Screen = App.top_screen()
		if top == null or top.screen_name != "lobby" or Net.party().is_empty():
			return
		if Time.get_ticks_msec() - _claim_ms < 3000:
			return
		if _offer_seen_ms < 0:
			# the offer just appeared: (captures) show it with its seats for a moment first
			_offer_seen_ms = Time.get_ticks_msec()
			top.call("_refresh", true)
			_capture("lobby_offer", 1.2)
		if str(tc.arg("--party-capture", "")) != "" and Time.get_ticks_msec() - _offer_seen_ms < 2500:
			return
		_claim_ms = Time.get_ticks_msec()
		top.call("_claim_seat")                 # the lobby's "Take my seat" / "Rejoin this run"
		if OnlineFlow.party != null:
			info["claimed"] = OnlineFlow.party.seat
			_note("claimed seat %s" % OnlineFlow.party.seat)

	# --- campaign screens --------------------------------------------------------------------

	func _route_want(c: RunController) -> String:
		var route := str(tc.arg("--party-route", "fight")).split(",", false)
		var k := (c.state.get("path", []) as Array).size()
		return str(route[k]) if k < route.size() else "fight"

	func _vote(top: Screen) -> void:
		var flow: CampaignFlow = top.get("flow")
		var c := flow.ctrl
		if c.phase() != "map":
			return
		var vv := flow.vote_view()
		if vv.is_empty():
			return
		var key := "%d/%s" % [int(c.state.get("act", 1)), str(c.state.get("position", ""))]
		if _voted_at == key:
			return
		var want := _route_want(c)
		var opts: Array = vv.get("options", [])
		var pick := want if opts.has(want) else ""     # an exact stop (a1r2l1) or a node type
		for o in opts:
			if pick == "" and c.visible_type(str(o)) == want:
				pick = str(o)
				break
		if pick == "":
			for o2 in opts:
				if c.visible_type(str(o2)) == "fight":
					pick = str(o2)
					break
		if pick == "" and not opts.is_empty():
			pick = str(opts[0])
		var btn = (top.get("_node_buttons") as Dictionary).get(pick)
		if btn is Button and not (btn as Button).disabled:
			(btn as Button).pressed.emit()
			_voted_at = key
			_decide("vote", "%s:%s" % [pick, c.visible_type(pick)])

	func _first_enabled(arr: Array, last := false) -> Button:
		var list := arr.duplicate()
		if last:
			list.reverse()
		for b in list:
			if b is Button and is_instance_valid(b) and not (b as Button).disabled:
				return b
		return null

	func _reward(top: Screen) -> void:
		var mode := str(tc.arg("--party-pick", "first"))
		var b: Button = null
		if mode == "skip":
			for a in top.get("_actions"):
				if a is Button and (a as Button).text == "SKIP" and not (a as Button).disabled:
					b = a
		else:
			b = _first_enabled(top.get("_cards"), mode == "last")
		if b == null:
			b = _first_enabled(top.get("_actions"), true)
		if b != null:
			var entry: Dictionary = top.get("_entry")
			_decide("pick", "%s:%s" % [str(entry.get("rid", "")), b.tooltip_text if b.tooltip_text != "" else b.text])
			b.pressed.emit()

	func _event(top: Screen) -> void:
		var bs: Array = top.get("_buttons")
		if bool(top.get("_showing")):
			var cont := _first_enabled(bs)
			if cont != null:
				_decide("event_continue", cont.text)
				cont.pressed.emit()
			return
		# --party-event-wait: let the other player answer a personal event first
		var c := _ctrl()
		var key := str(c.state.get("position", "")) if c else ""
		if not _event_seen.has(key):
			_event_seen[key] = Time.get_ticks_msec()
		if Time.get_ticks_msec() - int(_event_seen[key]) < int(float(tc.arg("--party-event-wait", "0")) * 1000.0):
			return
		var b := _first_enabled(bs, str(tc.arg("--party-event", "first")) == "last")
		if b != null:
			_decide("event", _label_of(b).left(80))
			b.pressed.emit()

	## A button's text, or the labels of a card button (event choices are cards).
	## Opens the pause menu the way the Pause button does and presses one of its entries by label.
	func _pause_menu_press(entry: String) -> String:
		MatchFlow.open_pause()
		var top: Screen = App.top_screen()
		if top == null or top.screen_name != "pause":
			return "no pause menu"
		var seen: Array = []
		for b in _buttons_under(top):
			var lt := _label_of(b as Button)
			seen.append(lt)
			if lt.to_lower().contains(entry.to_lower()):
				(b as Button).pressed.emit()
				return "pressed %s" % entry
		App.pop()
		return "no '%s' in the pause menu: %s" % [entry, str(seen)]

	func _label_of(b: Button) -> String:
		if b.text != "":
			return b.text
		var parts: Array = []
		var stack: Array = [b]
		while not stack.is_empty() and parts.size() < 3:
			var n: Node = stack.pop_front()
			if n is Label and (n as Label).text != "":
				parts.append((n as Label).text)
			stack.append_array(n.get_children())
		return " ".join(PackedStringArray(parts))

	func _shop(top: Screen) -> void:
		var c := _ctrl()
		var node := str(c.state.get("position", "")) if c else ""
		if str(tc.arg("--party-shop", "leave")) == "buy" and not _bought.has(node):
			_bought[node] = true
			var card := _first_enabled(top.get("_cards"))
			if card != null:
				_decide("buy", card.tooltip_text)
				card.pressed.emit()
				return
			_note("nothing affordable at the shop")
		for b in top.get("_buttons"):
			if b is Button and (b as Button).text.begins_with("LEAVE") and not (b as Button).disabled:
				_decide("leave_shop", node)
				(b as Button).pressed.emit()
				return

	func _rest(top: Screen) -> void:
		var b := _first_enabled(top.get("_cards"))
		if b != null:
			_decide("rest", _label_of(b).left(40))
			b.pressed.emit()

	func _summary(top: Screen) -> void:
		if finished:
			return
		finished = true
		var flow: CampaignFlow = top.get("flow")
		info["summary"] = flow.ctrl.summary().duplicate(true)
		info["report"] = flow.report.duplicate(true)
		_note("run summary shown")
		if tc.args.has("--party-stay"):
			return
		info["end_reason"] = "run summary"
		_end_t = 3.0

	# --- fights and scripted moments ------------------------------------------------------

	func _fight_moments(dt: float) -> void:
		var in_match := Net.session_state() in ["match", "results"]
		var mid := -1
		var phase := -1
		if host and Net.server != null:
			mid = Net.server.match_id if in_match else -1
			if Net.server.sim != null and Net.server.sim.mode != null:
				phase = Net.server.sim.mode.phase
				_scan_events(Net.server.sim)
		elif Net.client != null and in_match:
			mid = int(Net.client.match_info.get("match_id", -1))
			var m: Dictionary = Net.client.replica.latest().get("mode", {})
			phase = int(m.get("phase", -1))
		if in_match and mid >= 0 and mid != _match_seen:
			_match_seen = mid
			_fight_t = 0.0
			_ev_cursor = 0
			var mi: Dictionary = Net.server.match_info if host else Net.client.match_info
			var f := {"match_id": mid, "campaign": mi.get("campaign", {}), "you": Net.local_fighter(), "t_ms": Time.get_ticks_msec() - _start_ms}
			if host and Net.server.sim != null:
				var kinds: Array = []
				for fi in Net.server.sim.fighters:
					kinds.append({"kind": (fi as Fighter).controller_kind, "creature": (fi as Fighter).creature.id, "team": (fi as Fighter).team})
				f["fighters"] = kinds
			(info["fights"] as Array).append(f)
			_capture("fight_early", 4.0)
			_capture("fight", 8.0)
			_capture("fight_late", 16.0)
		# what a ref timeout looked like here: the host's match frozen, the REF TIMEOUT banner
		if in_match:
			if host and Net.server != null and Net.server.frozen:
				info["frozen_seen"] = true
			var ov = OnlineFlow.coop.get("_overlay") if OnlineFlow.coop != null else null
			if ov is Node and is_instance_valid(ov):
				var bl := (ov as Node).get_node_or_null("Banner") as Label
				if bl != null and bl.visible and bl.text != "":
					info["ref_banner"] = bl.text
		if not in_match or phase != MatchMode.Phase.FIGHT:
			return
		_fight_t += dt
		# fight n = the n-th fight this player fights in (an event's spar may leave them watching)
		var n := 0
		for fd in info["fights"]:
			if int((fd as Dictionary).get("you", -1)) >= 0:
				n += 1
		if (info["fights"] as Array).is_empty() or int((info["fights"] as Array).back().get("you", -1)) < 0:
			return
		# member: drop the connection mid-fight (crash / pulled cable); the test restarts us
		if not host and not _dropped and n == int(tc.arg("--party-drop-in-fight", "0")) and _fight_t > 3.0 and Net.client != null:
			_dropped = true
			_note("dropping the connection in fight %d" % n)
			tc._write(true)
			Net.client.drop()
			return
		# a ref timeout (pause menu > Call a ref timeout) in fight n, ended early by the caller
		if n == int(tc.arg("--party-ref-timeout-fight", "0")) and OnlineFlow.coop != null:
			if _timeout_at < 0.0 and _fight_t > 5.0:
				_timeout_at = _fight_t
				_note("calling a ref timeout in fight %d: %s" % [n, _pause_menu_press("Call a ref timeout")])
				_capture("fight_timeout", 1.0)
			elif _timeout_at >= 0.0 and not _timeout_done and _fight_t > _timeout_at + 3.0:
				_timeout_done = true
				_note("ending my ref timeout: %s" % _pause_menu_press("End my ref timeout"))
		# host departure mid-fight n (SESSION > Leave / closing the game): the match ends unscored,
		# the session ends for everyone, the run stays at this fight in every party save
		if host and not _left and n == int(tc.arg("--party-host-leave-in-fight", "0")) and _fight_t > 8.0:
			_left = true
			_note("leaving the session in fight %d" % n)
			_record()
			OnlineFlow.leave()
			info["end_reason"] = "the host left the session"
			_end_t = 3.0
			return
		# host: forfeit fight n (pause menu > Forfeit this fight), once every member is back
		if host and not _forfeited and n == int(tc.arg("--party-forfeit-fight", "0")) and _fight_t > float(tc.arg("--party-forfeit-after", "6")):
			var everyone_back := true
			if Net.server.sim != null:
				for fi2 in Net.server.sim.fighters:
					var role := str((fi2 as Fighter).flags.get("campaign_role", ""))
					if role == "player" and (fi2 as Fighter).controller_kind == "bot":
						everyone_back = false
			if everyone_back or _fight_t > float(tc.arg("--party-forfeit-max", "150")):
				_forfeited = true
				info["forfeit_with_everyone_back"] = everyone_back
				_note("forfeiting fight %d" % n)
				OnlineFlow.coop.forfeit_fight()

	func _scan_events(sim: MatchSim) -> void:
		for ev in sim.events_since(_ev_cursor):
			_ev_cursor = int(ev["seq"])
			var t := str(ev.get("type", ""))
			if not t in ["tag", "assist", "cheer", "downed", "downed_timer", "revived", "revive", "elimination", "ko"]:
				continue
			var fi := int(ev.get("fighter", -1))
			var who := "enemy"
			if fi >= 0 and fi < sim.fighters.size():
				var f: Fighter = sim.fighters[fi]
				if str(f.flags.get("campaign_role", "")) == "player":
					who = "host" if fi == Net.local_fighter() else "member"
			var key := "%s:%s" % [t, who]
			_camp_events[key] = int(_camp_events.get(key, 0)) + 1

	func _scripted_ends() -> void:
		var pr: NetPartyRuns = OnlineFlow.party
		var c := _ctrl()
		var fights := int(c.state.get("stats", {}).get("fights", 0)) if c else 0
		var at_map := c != null and c.phase() == "map" and Net.session_state() == "lobby"
		var top: Screen = App.top_screen()
		var on_map := top != null and top.screen_name == "run_map"
		if host and not _suspended and pr != null and started and at_map and on_map and fights >= int(tc.arg("--party-suspend-after", "999")):
			_suspended = true
			_note("suspending the party run after %d fights" % fights)
			_record()
			OnlineFlow.coop.suspend()           # the map's "SUSPEND PARTY RUN (everyone)"
			info["end_reason"] = "suspended"
			_end_t = 4.0
			return
		if at_map and on_map and fights >= int(tc.arg("--party-quit-after-fights", "999")):
			info["end_reason"] = "quit after %d fights" % fights
			_record()
			_end_t = 2.0
			return
		# a member whose host suspended the run is back in the lobby
		if not host and started and pr == null and not finished and tc.args.has("--party-quit-when-ended"):
			info["end_reason"] = "the host ended the party run"
			_end_t = 2.0
		if not host and pr != null and pr.is_live():
			started = true

	# --- records ---------------------------------------------------------------------------

	func _record() -> void:
		var pr: NetPartyRuns = OnlineFlow.party
		info["camp_events"] = _camp_events.duplicate()
		info["t_ms"] = Time.get_ticks_msec() - _start_ms
		info["session_state"] = Net.session_state()
		var top: Screen = App.top_screen()
		info["top"] = top.screen_name if top != null else ""
		if top != null and top.screen_name == "dialog":
			info["dialog"] = {"title": str(top.params.get("title", "")), "body": str(top.params.get("body", ""))}
		if pr != null:
			info["seat"] = pr.seat
			info["run_id"] = pr.run_id
			info["live"] = pr.is_live()
			info["fights_played"] = pr.fights_played
			info["fight_error"] = pr.fight_error
		var c := _ctrl()
		if c != null:
			var st: Dictionary = c.state
			var ps: Array = []
			for p in c.players():
				var pd: Dictionary = p
				var sups: Array = []
				for s in pd.get("supplements", []):
					sups.append(str((s as Dictionary).get("id", "")))
				ps.append({"id": str(pd.get("id", "")), "name": str(pd.get("name", "")), "bot": bool(pd.get("bot", false)),
					"connected": bool(pd.get("connected", true)), "hp": float(pd.get("hp", 0.0)), "scrip": int(pd.get("scrip", 0)),
					"supplements": sups, "techniques": (pd.get("techniques", []) as Array).duplicate(), "meta": (pd.get("meta", {}) as Dictionary).duplicate()})
			var lg: Array = []
			for e in st.get("log", []):
				var ed: Dictionary = e
				lg.append({"k": str(ed.get("k", "")), "p": str(ed.get("p", "")), "d": str(ed.get("d", {})).left(160)})
			info["state"] = {"phase": c.phase(), "position": str(st.get("position", "")), "act": int(st.get("act", 1)),
				"path": (st.get("path", []) as Array).duplicate(), "log_size": lg.size(), "variant": str(st.get("variant", "")),
				"coop_format": str(st.get("coop_format", "")), "difficulty": str(st.get("difficulty", "")),
				"fights": int(st.get("stats", {}).get("fights", 0)), "fights_won": int(st.get("stats", {}).get("fights_won", 0)),
				"over": c.is_over(), "players": ps, "run_id": str(st.get("run_id", ""))}
			info["log"] = lg
			if pr.session != null:
				info["last_event"] = pr.session.last_event.duplicate()
				info["is_host"] = pr.session.is_host()
				info["pause_budget"] = (pr.session.pause_view().get("budget", {}) as Dictionary).duplicate()
		if OnlineFlow.coop != null and not OnlineFlow.coop.report.is_empty():
			info["report"] = OnlineFlow.coop.report.duplicate(true)
		# what this player's own profile holds about the run (memory and the file on disk)
		var rid := str(info.get("run_id", ""))
		var seat := str(info.get("seat", ""))
		if rid != "" and seat != "":
			var key := "%s:%s" % [rid, seat]
			var credited: Array = Profiles.current.get("campaign", {}).get("credited_runs", [])
			info["credited_in_memory"] = credited.count(key)
			var disk := Saves.read_json(Profiles.call("_profile_path", Profiles.id()), "profile", Profiles.VERSION)
			var dd = disk.get("data", {})
			var dcred: Array = (dd as Dictionary).get("campaign", {}).get("credited_runs", []) if typeof(dd) == TYPE_DICTIONARY else []
			info["credited_on_disk"] = dcred.count(key)
			var hist := 0
			for h in (dd as Dictionary).get("history", []) if typeof(dd) == TYPE_DICTIONARY else []:
				if str((h as Dictionary).get("run_id", "")) == rid:
					hist += 1
			info["history_on_disk"] = hist
			info["party_save"] = FileAccess.file_exists(RunStore.new().slot_path(CampaignFlow.profile_key(), NetPartyRuns.slot_of(rid)))
		tc.result["party_ui"] = info

	# --- captures (windowed runs only) ---------------------------------------------------------

	func _capture(label_text: String, after: float) -> void:
		var dir := str(tc.arg("--party-capture", ""))
		if dir == "" or DisplayServer.get_name() == "headless":
			return
		_shots += 1
		var n := _shots
		tc.get_tree().create_timer(after).timeout.connect(func() -> void: _shoot(dir, n, label_text))

	func _shoot(dir: String, n: int, label_text: String) -> void:
		await RenderingServer.frame_post_draw
		var img: Image = (tc as Node).get_viewport().get_texture().get_image()
		if img.get_width() > 1600:
			img.resize(1600, int(1600.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
		DirAccess.make_dir_recursive_absolute(dir)
		var top: Screen = App.top_screen()
		var what := label_text if label_text.begins_with("fight") else (top.screen_name if top != null else label_text)
		var path: String = dir.path_join("%s_%02d_%s.jpg" % ["host" if host else "member", n, what])
		img.save_jpg(path, 0.85)
		if not info.has("captures"):
			info["captures"] = []
		(info["captures"] as Array).append(path.get_file())
