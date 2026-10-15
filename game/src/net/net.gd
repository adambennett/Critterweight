extends Node
## Autoload "Net": the one public entry point to networking (docs/NETWORKING.md "API").
## Roles: offline | host (listen server with a local player) | client | dedicated.
## Implementation: NetServer (authority), NetClient (remote view), NetDedicated (headless
## process), NetLanDiscovery (LAN browser), NetConditioner (test/debug network degradation).
##
## UI contract: call host()/join()/leave(); react to the signals below; read lobby() and
## stats(). Failure/disconnect reasons are UI-ready dictionaries {code, title, message, details}.
## Campaign/co-op contract: send_app()/request()/broadcast_app() + app_message/app_request.

signal status_changed(text: String)
## "offline" | "connecting" | "lobby" | "match" | "results"
signal session_state_changed(state: String)
signal connection_failed(reason: Dictionary)
signal disconnected(reason: Dictionary)
signal joined(welcome: Dictionary)
signal lobby_changed(lobby: Dictionary)
signal chat_received(from_id: int, from_name: String, text: String)
signal notice(text: String)
signal match_starting(info: Dictionary)
signal match_started(scene: Node)
signal match_ended(result: Dictionary)
signal returned_to_lobby()
signal peer_joined(info: Dictionary)
signal peer_left(info: Dictionary, reason: String)
## Client side: a message from the server (from_id = 1, the authority).
signal app_message(from_id: int, type: String, payload: Dictionary)
## Authority side (listen host / dedicated): a request from participant `from_id`.
signal app_request(from_id: int, type: String, payload: Dictionary)
signal lan_sessions_changed(sessions: Array)

const SERVER_ID := 1
const ALL := 0
const DISCOVERY_PORT := 7779

var role := "offline"
var server: NetServer = null
var client: NetClient = null
var dedicated_ctl: NetDedicated = null
var lan_browser: NetLanDiscovery = null
var last_failure := {}
var _state := "offline"
var _rejoin := {}                 ## {address, port, token, name, until_ms}
var _lan_wanted := false          ## the UI asked to browse (kept while the setting is off)
var _lan_port := DISCOVERY_PORT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.changed.connect(_on_setting_changed)


## Network settings apply live (Settings > Network): smoothing and timeout to the running
## connection, LAN discovery to browsing and to the listen host's announcements, aim assist to
## the player's next matches.
func _on_setting_changed(key: String, value) -> void:
	match key:
		"network.interp":
			if client:
				client.replica.interp_mode = str(value)
		"network.timeout":
			if client:
				client.transport.set_timeout_ms(int(value) * 1000)
			if role == "host" and server:
				server.set_timeout(int(value))
		"network.lan_discovery":
			var on := bool(value)
			if role == "host" and server:
				server.set_lan_discovery(on)
			if not on and lan_browser:
				lan_browser.stop()
				lan_browser = null
				lan_sessions_changed.emit([])
			elif on and _lan_wanted and lan_browser == null:
				start_lan_discovery(_lan_port)
		"access.target_assist":
			if client:
				client.send_lobby(NetProtocol.LQ_ASSIST, NetProtocol.local_assist())


# =====================================================================================
# Session lifecycle
# =====================================================================================

## Starts a listen server with the local player. cfg (all optional; defaults from Settings):
## {name, port, max_players, max_spectators, password, lan_discovery, player_name, creature,
##  rules, arena, bots, bot_difficulty, rejoin_grace, results_time, timeout}
func host(cfg: Dictionary = {}) -> Error:
	if role != "offline":
		leave()
	var pname := str(cfg.get("player_name", Settings.get_value("network.player_name")))
	var c := NetServerConfig.defaults()
	c["name"] = str(cfg.get("name", "%s's session" % NetProtocol.clean_name(pname)))
	c["port"] = int(cfg.get("port", Settings.get_value("network.port")))
	c["max_players"] = clampi(int(cfg.get("max_players", Settings.get_value("network.max_players"))), 1, NetProtocol.MAX_PLAYERS)
	c["max_spectators"] = clampi(int(cfg.get("max_spectators", 4)), 0, NetProtocol.MAX_SPECTATORS)
	c["password"] = str(cfg.get("password", Settings.get_value("network.password")))
	c["lan_discovery"] = bool(cfg.get("lan_discovery", Settings.get_value("network.lan_discovery")))
	c["timeout"] = int(cfg.get("timeout", Settings.get_value("network.timeout")))
	c["rejoin_grace"] = int(cfg.get("rejoin_grace", 60))
	c["results_time"] = int(cfg.get("results_time", 8))
	c["bot_difficulty"] = str(cfg.get("bot_difficulty", "regular"))
	for k in ["discovery_port", "kick_ban_seconds", "snapshot_rate"]:
		if cfg.has(k):
			c[k] = int(cfg[k])
	server = NetServer.new()
	add_child(server)
	var err := server.start(c, false, PackedStringArray(cfg.get("conditioner_args", [])))
	if err != OK:
		var reason := NetProtocol.describe(NetProtocol.R_LOCAL_ERROR, [server.transport.last_error,
			"Another program (or another game instance) may be using UDP port %d. Pick another port in Settings > Network." % int(c["port"])])
		server.queue_free()
		server = null
		_fail(reason)
		return err
	for k in ["rules", "arena", "bots", "bot_difficulty"]:
		if cfg.has(k):
			server.host_set(k, cfg[k])
	server.add_local_player(pname, str(cfg.get("creature", "")))
	_connect_server_signals()
	role = "host"
	_set_state("lobby")
	status_changed.emit("Hosting '%s' on UDP port %d" % [c["name"], int(c["port"])])
	return OK


## Joins a session. options: {name, password, spectator, creature, timeout_s, conditioner_args}
func join(address: String, port: int, password := "", options: Dictionary = {}) -> Error:
	if role != "offline":
		leave()
	var opts := options.duplicate()
	opts["password"] = password
	if not opts.has("name"):
		opts["name"] = Settings.get_value("network.player_name")
	if opts.has("conditioner_args"):
		var cond := NetConditioner.from_args(PackedStringArray(opts["conditioner_args"]))
		if cond:
			opts["conditioner"] = cond
	if _rejoin.has("address") and str(_rejoin["address"]) == address and int(_rejoin["port"]) == port \
			and Time.get_ticks_msec() < int(_rejoin["until_ms"]) and not opts.has("token"):
		opts["token"] = _rejoin["token"]
	client = NetClient.new()
	add_child(client)
	_connect_client_signals()
	role = "client"
	_set_state("connecting")
	status_changed.emit("Connecting to %s:%d..." % [address, port])
	var err := client.connect_to_server(address, port, opts)
	return err


## Rejoins the last session with the saved token (within the server's grace period).
func can_rejoin() -> bool:
	return _rejoin.has("address") and Time.get_ticks_msec() < int(_rejoin["until_ms"])


func rejoin() -> Error:
	if not can_rejoin():
		return ERR_UNAVAILABLE
	return join(str(_rejoin["address"]), int(_rejoin["port"]), str(_rejoin.get("password", "")), {"token": _rejoin["token"]})


## Leaves the current session. A listen host closes it for everyone ("The host left"); the
## server node finishes delivering that notice in the background, then frees itself.
func leave() -> void:
	match role:
		"host":
			var s := server
			server = null
			if s.match_info.size() > 0 and s.scene != null and is_instance_valid(s.scene) and App.current_scene == s.scene:
				App.set_scene(null)
			s.closed.connect(func(_c: int, _m: String) -> void: s.queue_free(), CONNECT_ONE_SHOT)
			s.close_async(NetProtocol.R_HOST_LEFT, "The host left the session.", false, 2000)
		"client":
			if client:
				client.leave()
			_drop_client()
		"dedicated":
			if dedicated_ctl:
				dedicated_ctl.request_shutdown("Server shutting down.")
	if role != "dedicated":
		role = "offline"
		_set_state("offline")


## Called by App.quit(): close sessions gracefully and quickly.
func shutdown() -> void:
	stop_lan_discovery()
	match role:
		"host":
			server.close(NetProtocol.R_HOST_LEFT, "The host closed the game.", false, 300)
			_drop_server()
		"client":
			if client:
				client.leave()
			_drop_client()
		"dedicated":
			if dedicated_ctl and dedicated_ctl.server:
				dedicated_ctl.server.close(NetProtocol.R_SHUTDOWN, "Server shutting down.", false, 300)
	role = "offline"


## Dedicated server from a config dictionary (flat NetServerConfig keys) - mostly for tools.
func start_dedicated(cfg: Dictionary) -> Error:
	var args := PackedStringArray(["--server"])
	for k in cfg:
		args.append("--" + str(k).replace("_", "-"))
		args.append(str(cfg[k]))
	start_dedicated_from_cli(args)
	return OK if role == "dedicated" else FAILED


## `--server [--config <path>] [overrides]` (main.gd). Exits the process on fatal errors.
func start_dedicated_from_cli(args: PackedStringArray) -> void:
	var wi := args.find("--write-example-config")
	if wi >= 0:
		var dst := args[wi + 1] if wi + 1 < args.size() and not args[wi + 1].begins_with("--") else "server.cfg"
		get_tree().quit(NetDedicated.write_example_config(dst))
		return
	dedicated_ctl = NetDedicated.new()
	add_child(dedicated_ctl)
	var code := dedicated_ctl.run(args)
	if code != 0:
		get_tree().quit(code)
		return
	server = dedicated_ctl.server
	role = "dedicated"
	_connect_server_signals()


## `--connect <host:port>` / `--host` (main.gd): join or host from the command line with the
## normal presentation (handy for LAN parties and debugging). Also accepts --password, --name,
## --spectate and the conditioner flags.
func start_from_cli(args: PackedStringArray) -> void:
	var ci := args.find("--connect")
	var cond_args: Array = []
	for f in ["--net-latency", "--net-jitter", "--net-loss"]:
		var k := args.find(f)
		if k >= 0 and k + 1 < args.size():
			cond_args.append(f)
			cond_args.append(args[k + 1])
	if ci >= 0 and ci + 1 < args.size():
		var target := args[ci + 1]
		var host_part := target
		var port := int(Settings.get_value("network.port"))
		if target.contains(":"):
			host_part = target.substr(0, target.rfind(":"))
			port = int(target.substr(target.rfind(":") + 1))
		var opts := {"spectator": args.has("--spectate"), "conditioner_args": cond_args}
		var ni := args.find("--name")
		if ni >= 0 and ni + 1 < args.size():
			opts["name"] = args[ni + 1]
		var pi := args.find("--password")
		join(host_part, port, args[pi + 1] if pi >= 0 and pi + 1 < args.size() else "", opts)
	elif args.has("--host"):
		var hcfg := {"conditioner_args": cond_args}
		var hp := args.find("--port")
		if hp >= 0 and hp + 1 < args.size():
			hcfg["port"] = int(args[hp + 1])
		host(hcfg)


func _drop_server() -> void:
	if server:
		server.queue_free()
	server = null


func _drop_client() -> void:
	if client:
		client.queue_free()
	client = null


func _fail(reason: Dictionary) -> void:
	last_failure = reason
	Log.w("net", "%s: %s %s" % [reason.get("title", ""), reason.get("message", ""), str(reason.get("details", []))])
	connection_failed.emit(reason)
	status_changed.emit(str(reason.get("title", "")))


func _set_state(s: String) -> void:
	if _state != s:
		_state = s
		session_state_changed.emit(s)


func session_state() -> String:
	return _state


# =====================================================================================
# Signals plumbing
# =====================================================================================

func _connect_server_signals() -> void:
	server.lobby_changed.connect(func() -> void: lobby_changed.emit(server.lobby_state()))
	server.player_joined.connect(func(i: Dictionary) -> void: peer_joined.emit(i))
	server.player_left.connect(func(i: Dictionary, r: String) -> void: peer_left.emit(i, r))
	server.chat_message.connect(func(id: int, n: String, t: String) -> void: chat_received.emit(id, n, t))
	server.notice_sent.connect(func(t: String) -> void: notice.emit(t))
	server.app_request.connect(func(id: int, t: String, p: Dictionary) -> void: app_request.emit(id, t, p))
	server.match_started.connect(_on_server_match_started)
	server.match_finished.connect(func(r: Dictionary) -> void:
		_set_state("results")
		match_ended.emit(r))
	server.returned_to_lobby.connect(func() -> void:
		_set_state("lobby")
		returned_to_lobby.emit())
	server.closed.connect(func(_c: int, _m: String) -> void: pass)


func _on_server_match_started(info: Dictionary) -> void:
	_set_state("match")
	match_starting.emit(info)
	if server.scene:
		match_started.emit(server.scene)


func _connect_client_signals() -> void:
	client.admitted.connect(func(w: Dictionary) -> void:
		_rejoin = {"address": client.address, "port": client.port, "token": client.token, "password": str(client.opts.get("password", "")),
			"until_ms": Time.get_ticks_msec() + 3600 * 1000}
		if client.state != NetClient.State.MATCH:
			_set_state("lobby")
		status_changed.emit("Connected to '%s'" % client.server_name)
		joined.emit(w))
	client.failed.connect(func(r: Dictionary) -> void:
		_fail(r)
		role = "offline"
		_set_state("offline")
		_drop_client.call_deferred())
	client.disconnected.connect(func(r: Dictionary) -> void:
		last_failure = r
		if int(r.get("code", 0)) == NetProtocol.R_KICKED or int(r.get("code", 0)) == NetProtocol.R_LEFT:
			_rejoin.clear()
		disconnected.emit(r)
		status_changed.emit(str(r.get("title", "Disconnected")))
		role = "offline"
		_set_state("offline")
		_drop_client.call_deferred())
	client.lobby_updated.connect(func(l: Dictionary) -> void: lobby_changed.emit(l))
	client.chat_received.connect(func(id: int, n: String, t: String) -> void: chat_received.emit(id, n, t))
	client.notice_received.connect(func(t: String) -> void: notice.emit(t))
	client.match_starting.connect(func(i: Dictionary) -> void:
		_set_state("match")
		match_starting.emit(i))
	client.match_ready.connect(func(s: Node) -> void: match_started.emit(s))
	client.match_ended.connect(func(r: Dictionary) -> void:
		_set_state("results")
		match_ended.emit(r))
	client.returned_to_lobby.connect(func() -> void:
		_set_state("lobby")
		returned_to_lobby.emit())
	client.app_message.connect(func(id: int, t: String, p: Dictionary) -> void: app_message.emit(id, t, p))


# =====================================================================================
# Roles & queries
# =====================================================================================

func is_online() -> bool:
	return role != "offline"


## Used by the UI (MatchFlow): online sessions never pause.
func is_session_active() -> bool:
	return role != "offline"


## True where the authoritative simulation runs: offline, listen host, dedicated server.
func is_authority() -> bool:
	return role == "offline" or role == "host" or role == "dedicated"


func is_server() -> bool:
	return role == "host" or role == "dedicated"


func is_client() -> bool:
	return role == "client"


func is_host() -> bool:
	return role == "host"


func is_dedicated() -> bool:
	return role == "dedicated"


## This process's session player id (1 = the server / listen host; 0 offline or connecting).
func local_peer_id() -> int:
	match role:
		"host", "dedicated":
			return SERVER_ID
		"client":
			return client.player_id if client else 0
	return 0


## Participants as public dictionaries: {id, name, slot, team, creature, ready, spectator, host,
## connected, fighter, ping, vote}.
func peers() -> Array:
	var l := lobby()
	return (l.get("players", []) as Array).duplicate(true)


func player(id: int) -> Dictionary:
	for p in peers():
		if int(p["id"]) == id:
			return p
	return {}


func lobby() -> Dictionary:
	if server:
		return server.lobby_state()
	if client:
		return client.lobby
	return {}


## Fighter index of the local player in the current match (-1 spectator / none).
func local_fighter() -> int:
	if role == "host" and server:
		var p: NetPlayer = server.players.get(SERVER_ID)
		return p.fighter if p else -1
	if client:
		return client.my_fighter
	return -1


## This computer's IPv4 addresses other players could use, LAN addresses first (192.168.x,
## 10.x, 172.16-31.x), then any others; loopback and link-local (169.254.x) are left out. The
## public internet address is not known locally (it belongs to the router): see the invite help.
func local_addresses() -> Array[String]:
	var lan: Array[String] = []
	var other: Array[String] = []
	for a in IP.get_local_addresses():
		var s := str(a)
		if not s.is_valid_ip_address() or s.contains(":") or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		var p := s.split(".")
		var private := s.begins_with("10.") or s.begins_with("192.168.") or (p[0] == "172" and int(p[1]) >= 16 and int(p[1]) <= 31)
		if private:
			if not lan.has(s):
				lan.append(s)
		elif not other.has(s):
			other.append(s)
	lan.sort()
	other.sort()
	return lan + other


## Copyable invite line for the session this machine hosts (Platform.invite_text), e.g. for a
## chat or the clipboard. `address` defaults to the first LAN address; pass the public address
## (or a host name) for internet play. "" when not hosting.
func invite_text(address := "") -> String:
	if not is_server() or server == null:
		return ""
	var addr := address
	if addr == "":
		var all := local_addresses()
		addr = all[0] if not all.is_empty() else "127.0.0.1"
	return Platform.invite_text(addr, int(server.cfg["port"]), str(server.cfg["password"]) != "")


## Live diagnostics: RTT, loss, snapshot rate, bytes/s, interpolation, server tick cost...
func stats() -> Dictionary:
	var s := {"role": role, "state": _state}
	if client:
		s.merge(client.stats())
	if server:
		s["server"] = server.status()
	return s


## Disables local input (e.g. while a menu overlay is open); neutral input is sent instead.
func set_input_enabled(on: bool) -> void:
	if client:
		client.input_enabled = on


# =====================================================================================
# Lobby actions (work for the listen host and for clients)
# =====================================================================================

func set_ready(on: bool) -> void:
	if role == "host":
		server.set_ready(SERVER_ID, on)
	elif client:
		client.send_lobby(NetProtocol.LQ_READY, on)


func set_creature(id: String) -> void:
	if role == "host":
		server.set_creature(SERVER_ID, id)
	elif client:
		client.send_lobby(NetProtocol.LQ_CREATURE, id)


func set_team(team: int) -> void:
	if role == "host":
		server.set_team(SERVER_ID, team)
	elif client:
		client.send_lobby(NetProtocol.LQ_TEAM, team)


func set_spectator(on: bool) -> void:
	if role == "host":
		server.set_spectator(SERVER_ID, on)
	elif client:
		client.send_lobby(NetProtocol.LQ_SPECTATE, on)


func send_chat(text: String) -> void:
	if role == "host":
		server.say_as(SERVER_ID, text)
	elif client:
		client.send_chat(text)


func vote(candidate: int) -> void:
	if role == "host":
		server.cast_vote(SERVER_ID, candidate)
	elif client:
		client.send_vote(candidate)


## Host-only settings: rules (preset id), arena (id), bots (count), bot_difficulty,
## rules_override (dict). Returns "" or an error text.
func host_set(key: String, value) -> String:
	if role != "host":
		return "only the host can change session settings"
	return server.host_set(key, value)


func host_start() -> String:
	if role != "host":
		return "only the host can start the match"
	return server.host_start()


func host_kick(player_id: int, reason := "kicked by the host") -> bool:
	if role != "host":
		return false
	return server.kick(player_id, reason)


# =====================================================================================
# App message channel (co-op campaign, custom systems)
# =====================================================================================

## target: a player id, ALL (0), or SERVER_ID (1).
## * On the authority (host/dedicated): delivers to that player / everyone as `app_message`
##   (the listen host's own player receives it locally too).
## * On a client: target must be SERVER_ID; the authority receives it as `app_request`.
## Payloads are plain data (no objects), <= 64 KB; types match [a-z0-9_.:/-]{1,64}.
func send_app(target: int, type: String, payload: Dictionary = {}) -> bool:
	if not NetProtocol.valid_app_type(type):
		push_warning("Net.send_app: invalid type '%s'" % type)
		return false
	match role:
		"host", "dedicated":
			var sent := server.send_app(target, type, payload)
			if role == "host" and (target == ALL or target == SERVER_ID):
				app_message.emit.call_deferred(SERVER_ID, type, payload.duplicate(true))
				sent = true
			return sent
		"client":
			if target != SERVER_ID:
				push_warning("Net.send_app: clients can only message the server (use a server-side relay)")
				return false
			return client.send_app(type, payload)
	return false


## Client -> authority request (on the listen host it is delivered locally as app_request).
func request(type: String, payload: Dictionary = {}) -> bool:
	if role == "host":
		if not NetProtocol.valid_app_type(type):
			return false
		if type.begins_with("mode."):
			server.handle_mode_request(SERVER_ID, type, payload)
		else:
			app_request.emit.call_deferred(SERVER_ID, type, payload.duplicate(true))
		return true
	return send_app(SERVER_ID, type, payload)


## Authority -> everyone.
func broadcast_app(type: String, payload: Dictionary = {}) -> bool:
	if not is_server():
		return false
	return send_app(ALL, type, payload)


# =====================================================================================
# LAN discovery (browser side; servers announce themselves when lan_discovery is on)
# =====================================================================================

## Starts listening for LAN beacons. Honours Settings > Network > LAN discovery: while it is off
## this returns ERR_UNAVAILABLE (and status_changed says so), and browsing starts by itself when
## the setting is switched on again (until stop_lan_discovery()).
func start_lan_discovery(port := DISCOVERY_PORT) -> Error:
	_lan_wanted = true
	_lan_port = port
	if lan_browser:
		return OK
	if not bool(Settings.get_value("network.lan_discovery")):
		status_changed.emit("LAN discovery is off (Settings > Network)")
		return ERR_UNAVAILABLE
	lan_browser = NetLanDiscovery.new()
	var err := lan_browser.start_listener(port)
	if err != OK:
		lan_browser = null
		status_changed.emit("LAN discovery unavailable (ports %d-%d busy)" % [port, port + NetLanDiscovery.PORT_SPAN - 1])
	return err


func stop_lan_discovery() -> void:
	_lan_wanted = false
	if lan_browser:
		lan_browser.stop()
	lan_browser = null


func is_lan_discovery_active() -> bool:
	return lan_browser != null and lan_browser.is_listening()


## [{name, address, port, players, max_players, spectators, max_spectators, password,
##   dedicated, in_match, rules, arena, phase, game_version, compatible, incompatible_reason}]
func lan_sessions() -> Array:
	return lan_browser.list() if lan_browser else []


func _process(_dt: float) -> void:
	if lan_browser and lan_browser.poll():
		lan_sessions_changed.emit(lan_browser.list())
