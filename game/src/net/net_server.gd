class_name NetServer
extends Node
## Authoritative session host: a listen server (in-game; the host's own fighter is driven by
## LocalPlayerInput inside the same MatchSim, so the host plays with zero added latency) or a
## dedicated server (headless). Owns:
##  * admission: protocol/build/content/password/capacity/ban checks with precise reasons,
##  * the lobby: players, slots, teams, characters, ready, spectators, bots, playlist votes,
##  * the match: MatchSim at the physics rate, snapshots (unreliable, 30 Hz), simulation events
##    (reliable, tick-stamped), results, automatic return to the lobby / next playlist entry,
##  * robustness: handshake timeouts, rate limits and violation scoring (kicks), disconnect +
##    rejoin within a grace period (a bot holds the fighter meanwhile), kicks/bans, shutdown.
## Clients only ever send input samples and requests; damage, results and rewards are decided
## here. Ordering contract: MATCH_START, EVENTS and MATCH_END share the reliable events channel,
## so a client always learns about a match before any of its events; snapshots carry the match id.

signal lobby_changed()
signal player_joined(info: Dictionary)
signal player_left(info: Dictionary, reason: String)
signal match_started(info: Dictionary)
signal match_finished(result: Dictionary)
signal returned_to_lobby()
signal app_request(from_id: int, type: String, payload: Dictionary)
## A party message relayed to the listen host's own member (see relay_app).
signal app_relayed(from_id: int, type: String, payload: Dictionary)
signal chat_message(from_id: int, from_name: String, text: String)
signal notice_sent(text: String)
signal closed(code: int, message: String)

const PHASE_IDLE := "idle"
const PHASE_LOBBY := "lobby"
const PHASE_MATCH := "match"
const PHASE_RESULTS := "results"
const SERVER_ID := 1
const ALL := 0
const HANDSHAKE_MS := 5000
const MAX_PENDING := 24
const MAX_PENDING_PER_ADDR := 8
const VIOLATION_KICK := 20.0
const VIOLATION_DECAY := 2.0
const LOBBY_MIN_INTERVAL_MS := 100
const COUNTDOWN_RESEND_MS := 1000
const BEACON_MS := 1000
const PICK_TIMEOUT_MS := 20000

var cfg := {}
var dedicated := false
var transport := NetTransport.new()
var conditioner: NetConditioner = null
var lan: NetLanDiscovery = null
var players := {}                 ## player id -> NetPlayer
var _peer_player := {}            ## transport peer id -> player id
var _pending := {}                ## transport peer id -> {since, nonce, addr}
var _next_player_id := 2
var local_player_id := 0
var phase := PHASE_LOBBY
var phase_until := 0
var settings := {"rules": "duel", "arena": "the_gullet", "bots": 0, "bot_difficulty": "regular", "rules_override": {}, "bot_policy": []}
var playlist: NetPlaylist = null
var vote := {}
var current_entry := {}
var match_id := 0
var match_info := {}
var sim: MatchSim = null
var scene: Node = null
var _sim_id := 0                  ## instance id of the running match's sim (detects a freed sim)
var last_result := {}
var started_ms := 0
var _ev_cursor := 0
var _tick_counter := 0
var _snap_every := 4
var _rng := RandomNumberGenerator.new()
var _bans: Array = []
var _lobby_dirty := true
var _lobby_sent_ms := 0
var _closing := false
var _finalized := false
var _close_deadline := 0
var _close_code := NetProtocol.R_SHUTDOWN
var _close_message := ""
var _aborting := ""
var _beacon_ms := 0
var _stats_ms := 0
var _rtt_ms := 0
var _wait_notice_ms := 0
var _bot_serial := 0
## A remote player's unanswered mode pick (Chum Rush supplements) is taken for them after this.
var pick_timeout_ms := PICK_TIMEOUT_MS
var _pick_since := {}             ## fighter index -> ms its pending pick was first seen
var _policy_cache: Array = []
var _policy_cache_ms := 0
var _arena_pkg_cache := {}        ## arena content hash -> ArenaPackage bytes
var _policy_hashes := {}          ## PolicyData instance id -> checksum
## Open co-op party run (party seats, see party_open): {run_id, info, host_seat,
## seats: [{id, name, fighter, session}]}; empty = no party run, party ids are session ids.
var party := {}
var frozen := false               ## a co-op ref timeout holds the running match (set_frozen)
var _frozen_space := RID()
var _results_s := -1              ## results phase length of the running match (-1 = cfg results_time)
var _bot_maker: Callable = Callable()   ## campaign fights: func(Fighter) -> InputSource for a member who drops
var _roster: Array = []           ## per fighter slot: {gen, obj, rig, creature, scale, despawned, team, name, kind, player}
var _gens := PackedByteArray()

## performance / bandwidth measurements (exposed through status())
var perf := {"ticks": 0, "sim_us_total": 0, "sim_us_max": 0, "net_us_total": 0, "net_us_max": 0,
	"phys_ms_total": 0.0, "phys_samples": 0, "snapshot_bytes": 0, "snapshots": 0, "event_bytes": 0, "event_batches": 0,
	"window_start_ms": 0, "window_out": 0, "window_in": 0, "out_bps": 0.0, "in_bps": 0.0,
	"window_ticks": 0, "window_sim_us": 0, "window_sim_max": 0, "tick_ms_avg": 0.0, "tick_ms_max": 0.0}


# =====================================================================================
# Lifecycle
# =====================================================================================

## config: flat dictionary (NetServerConfig keys). args: process CLI (conditioner flags).
func start(config: Dictionary, is_dedicated: bool, args := PackedStringArray()) -> Error:
	cfg = NetServerConfig.defaults()
	for k in config:
		cfg[k] = config[k]
	dedicated = is_dedicated
	name = "NetServer"
	process_physics_priority = -100
	if cfg.has("seed"):
		_rng.seed = int(cfg["seed"])
	else:
		_rng.randomize()
	transport.timeout_ms = int(cfg["timeout"]) * 1000
	if NetProtocol.too_many_packages(Content.package_list()):
		transport.last_error = "%d gameplay packages are loaded; online sessions support up to %d (core included)" % [
			NetProtocol.gameplay_packages(Content.package_list()).size(), NetProtocol.MAX_PACKAGES]
		Log.e("net", "server start failed: %s" % transport.last_error)
		return ERR_INVALID_DATA
	var max_peers := int(cfg["max_players"]) + int(cfg["max_spectators"]) + 8
	conditioner = NetConditioner.from_args(args)
	var err: Error
	if conditioner:
		err = transport.listen(0, "127.0.0.1", max_peers)
		if err == OK:
			err = conditioner.start("127.0.0.1", transport.local_port(), int(cfg["port"]), str(cfg["bind"]))
			if err != OK:
				transport.last_error = "conditioner cannot bind port %d: %s" % [int(cfg["port"]), error_string(err)]
				transport.close()
			else:
				Log.w("net", "server network conditioner active: %s" % conditioner.describe())
	else:
		err = transport.listen(int(cfg["port"]), str(cfg["bind"]), max_peers)
	if err != OK:
		Log.e("net", "server start failed: %s" % transport.last_error)
		return err
	_snap_every = maxi(1, roundi(float(cfg["tick_rate"]) / float(cfg["snapshot_rate"])))
	if bool(cfg["lan_discovery"]):
		lan = NetLanDiscovery.new()
		if lan.start_announcer(int(cfg["discovery_port"])) != OK:
			Log.w("net", "LAN discovery announcer unavailable")
			lan = null
	started_ms = Time.get_ticks_msec()
	perf["window_start_ms"] = started_ms
	phase = PHASE_IDLE if dedicated else PHASE_LOBBY
	if not dedicated:
		var r := NetPlaylist.resolve_rules(str(settings["rules"]), {})
		if r.is_empty():
			var ids: Array = Content.ids("rules")
			if not ids.is_empty():
				settings["rules"] = str(ids[0])
	Log.i("net", "%s server '%s' listening on UDP %s:%d (protocol %d, game %s, content %s)" % [
		"dedicated" if dedicated else "listen", cfg["name"], cfg["bind"], int(cfg["port"]), NetProtocol.VERSION,
		NetProtocol.game_version(), Content.content_hash().substr(0, 12)])
	return OK


func set_playlist(p: NetPlaylist) -> void:
	playlist = p
	vote = {}
	_lobby_dirty = true


## Turns LAN beacons on/off while running (listen host: Settings > Network > LAN discovery).
func set_lan_discovery(on: bool) -> Error:
	cfg["lan_discovery"] = on
	if not on:
		if lan:
			lan.stop()
			lan = null
			Log.i("net", "LAN announcements off")
		return OK
	if lan or not transport.is_open():
		return OK
	lan = NetLanDiscovery.new()
	var err := lan.start_announcer(int(cfg["discovery_port"]))
	if err != OK:
		Log.w("net", "LAN discovery announcer unavailable")
		lan = null
		return err
	_beacon_ms = 0
	Log.i("net", "LAN announcements on")
	return OK


## Snapshots per second to each client (listen host: Settings > Network), applied immediately.
func set_snapshot_rate(rate: int) -> void:
	cfg["snapshot_rate"] = clampi(rate, 10, mini(60, int(cfg["tick_rate"])))
	_snap_every = maxi(1, roundi(float(cfg["tick_rate"]) / float(cfg["snapshot_rate"])))


## Co-op party relay on/off (listen host: Settings > Network), applied immediately.
func set_party_relay(on: bool) -> void:
	cfg["party_relay"] = on


## ArenaPackage bytes of a layout (ArenaPackage.export_package: schema-checked, hashed), cached
## by the layout's content hash. Empty when it cannot be packaged or is over the size cap.
func _arena_package_bytes(arena: ArenaDef) -> PackedByteArray:
	var h := arena.content_hash()
	if _arena_pkg_cache.has(h):
		return _arena_pkg_cache[h]
	var tmp := Paths.dir("downloads").path_join("net_arena_out_%d.zip" % Time.get_ticks_usec())
	var res := ArenaPackage.export_package([arena.to_dict()], tmp, {"name": arena.display_name})
	var bytes := PackedByteArray()
	if bool(res.get("ok", false)):
		bytes = FileAccess.get_file_as_bytes(tmp)
	else:
		Log.w("net", "arena '%s' could not be packaged: %s" % [arena.id, str(res.get("error", ""))])
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	if bytes.size() > NetProtocol.MAX_ARENA_PACKAGE:
		Log.w("net", "arena '%s' package is %d KB, over the %d KB limit" % [arena.id, int(bytes.size() / 1024.0), int(NetProtocol.MAX_ARENA_PACKAGE / 1024.0)])
		bytes = PackedByteArray()
	elif not bytes.is_empty():
		Log.i("net", "arena '%s' packaged for the players: %d bytes" % [arena.id, bytes.size()])
	if _arena_pkg_cache.size() > 8:
		_arena_pkg_cache.clear()
	_arena_pkg_cache[h] = bytes
	return bytes


## AI Lab policies the host can put into bot slots: [{id, name, creature, hash}] (valid ones, at
## most 64; refreshed every few seconds because the list reads the user policy folder).
func _policy_options() -> Array:
	var now := Time.get_ticks_msec()
	if _policy_cache_ms == 0 or now - _policy_cache_ms > 5000:
		_policy_cache_ms = now
		_policy_cache.clear()
		for p in PolicyLibrary.list():
			if typeof(p) == TYPE_DICTIONARY and bool(p.get("valid", false)) and _policy_cache.size() < 64:
				var pid := str(p.get("id", ""))
				_policy_cache.append({"id": pid, "name": str(p.get("name", "")), "creature": str(p.get("creature", "")),
					"hash": _policy_hash(PolicyLibrary.get_policy(pid))})
	return _policy_cache.duplicate(true)


## A policy's content hash: the sha256 checksum of its canonical file form (PolicyData.to_dict,
## the same checksum PolicyIO verifies on load), so players and logs can tell exactly which
## trained network drove a bot. Cached per loaded PolicyData ("" when unavailable).
func _policy_hash(pol: PolicyData) -> String:
	if pol == null:
		return ""
	var key := pol.get_instance_id()
	if not _policy_hashes.has(key):
		if _policy_hashes.size() > 128:
			_policy_hashes.clear()
		_policy_hashes[key] = str(pol.to_dict().get("checksum", ""))
	return _policy_hashes[key]


## Connection timeout in seconds (application heartbeat and ENet), applied immediately.
func set_timeout(seconds: int) -> void:
	cfg["timeout"] = clampi(seconds, 5, 60)
	transport.set_timeout_ms(int(cfg["timeout"]) * 1000)


## Listen host: registers the local player (id 1) who plays through LocalPlayerInput.
func add_local_player(player_name: String, creature_id := "") -> NetPlayer:
	var p := NetPlayer.new()
	p.id = SERVER_ID
	p.peer = -1
	p.is_host = true
	p.name = NetProtocol.clean_name(player_name)
	p.creature = _valid_creature(creature_id)
	p.slot = 0
	p.token = NetProtocol.random_bytes(NetProtocol.TOKEN_BYTES)
	p.joined_ms = Time.get_ticks_msec()
	players[p.id] = p
	local_player_id = p.id
	_lobby_dirty = true
	return p


func is_running() -> bool:
	return transport.is_open() and not _closing


func is_closed() -> bool:
	return _finalized


## Graceful close (blocking - for quitting processes): tells every client why (and whether a
## restart is expected), pumps the network for up to `wait_ms` so the notices are acknowledged,
## then tears everything down. Prefer close_async() when the process keeps running.
func close(code := NetProtocol.R_SHUTDOWN, message := "", restarting := false, wait_ms := 400) -> void:
	if _finalized:
		return
	begin_close(code, message, restarting)
	transport.drain(wait_ms)
	_finalize_close()


## Graceful close without blocking: notices go out now; the server keeps servicing the network
## until every client has acknowledged and disconnected (or `max_ms` passes), then emits `closed`.
## ENet drops undelivered packets when a disconnect overtakes them, so this is how the shutdown
## reason reliably reaches slow or high-latency clients.
func close_async(code := NetProtocol.R_SHUTDOWN, message := "", restarting := false, max_ms := 2500) -> void:
	if _closing:
		return
	begin_close(code, message, restarting)
	_close_deadline = Time.get_ticks_msec() + max_ms


func begin_close(code: int, message: String, restarting: bool) -> void:
	if _closing:
		return
	_closing = true
	_close_code = code
	_close_message = message
	var w := NetWriter.new(NetProtocol.S_CLOSING)
	w.u8(code)
	w.text(message, 400)
	w.u8(1 if restarting else 0)
	var data := w.data()
	for p in players.values():
		var np: NetPlayer = p
		if np.peer > 0:
			transport.send(np.peer, NetProtocol.CH_CONTROL, data, true)
			transport.disconnect_peer(np.peer, code, true)
	for peer in _pending.keys():
		transport.disconnect_peer(int(peer), code, true)
	transport.flush()
	Log.i("net", "server closing (%s)%s" % [NetProtocol.reason_name(code), (": " + message) if message != "" else ""])


func _finalize_close() -> void:
	if _finalized:
		return
	_finalized = true
	var code := _close_code
	var message := _close_message
	Log.i("net", "server closed (%s)%s" % [NetProtocol.reason_name(code), (": " + message) if message != "" else ""])
	_teardown_match()
	transport.close()
	if conditioner:
		conditioner.stop()
		conditioner = null
	if lan:
		lan.stop()
		lan = null
	players.clear()
	_peer_player.clear()
	_pending.clear()
	party = {}
	closed.emit(code, message)


func _exit_tree() -> void:
	if not _finalized and transport.is_open():
		close(NetProtocol.R_SHUTDOWN, "", false, 100)


# =====================================================================================
# Main loop
# =====================================================================================

func _physics_process(dt: float) -> void:
	if _finalized or not transport.is_open():
		return
	if _closing:
		# async close: keep servicing so the closing notices are acknowledged
		for ev in transport.poll():
			pass
		transport.flush()
		if transport.peer_ids().is_empty() or (_close_deadline > 0 and Time.get_ticks_msec() >= _close_deadline):
			_finalize_close()
		return
	var t0 := Time.get_ticks_usec()
	for ev in transport.poll():
		_on_transport_event(ev)
	match phase:
		PHASE_LOBBY:
			_tick_lobby()
		PHASE_MATCH, PHASE_RESULTS:
			_replicate()
		PHASE_IDLE:
			_tick_idle()
	var t1 := Time.get_ticks_usec()
	if sim != null and dedicated and not frozen and (phase == PHASE_MATCH or phase == PHASE_RESULTS):
		sim.step(dt)
		var sim_us := Time.get_ticks_usec() - t1
		perf["sim_us_total"] = int(perf["sim_us_total"]) + sim_us
		perf["sim_us_max"] = maxi(int(perf["sim_us_max"]), sim_us)
		perf["window_sim_us"] = int(perf["window_sim_us"]) + sim_us
		perf["window_sim_max"] = maxi(int(perf["window_sim_max"]), sim_us)
		perf["ticks"] = int(perf["ticks"]) + 1
		perf["window_ticks"] = int(perf["window_ticks"]) + 1
	var t2 := Time.get_ticks_usec()
	if phase == PHASE_RESULTS and Time.get_ticks_msec() >= phase_until:
		_finish_results()
	_housekeeping()
	transport.flush()
	var net_us := (t1 - t0) + (Time.get_ticks_usec() - t2)
	perf["net_us_total"] = int(perf["net_us_total"]) + net_us
	perf["net_us_max"] = maxi(int(perf["net_us_max"]), net_us)
	perf["net_ticks"] = int(perf.get("net_ticks", 0)) + 1


func _process(_dt: float) -> void:
	# Godot's TIME_PHYSICS_PROCESS monitor is the longest physics frame (script + Jolt step) of
	# the previous second; sampled here so status() can report it during matches.
	if sim != null and (phase == PHASE_MATCH or phase == PHASE_RESULTS):
		perf["phys_max_ms"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0


func _on_transport_event(ev: Dictionary) -> void:
	match int(ev["type"]):
		NetTransport.EV_CONNECT:
			_on_connect(int(ev["peer"]))
		NetTransport.EV_DISCONNECT:
			_on_peer_disconnected(int(ev["peer"]), int(ev.get("code", 0)))
		NetTransport.EV_RECEIVE:
			_on_receive(int(ev["peer"]), int(ev["channel"]), ev["data"])


# =====================================================================================
# Admission
# =====================================================================================

func _on_connect(peer: int) -> void:
	var addr := transport.address(peer)
	var same := 0
	for v in _pending.values():
		if str(v["addr"]) == addr:
			same += 1
	if _pending.size() >= MAX_PENDING or same >= MAX_PENDING_PER_ADDR:
		Log.w("net", "refusing connection from %s: too many pending handshakes" % addr)
		transport.disconnect_peer(peer, NetProtocol.R_FULL, false)
		return
	var nonce := NetProtocol.random_bytes(NetProtocol.NONCE_BYTES)
	_pending[peer] = {"since": Time.get_ticks_msec(), "nonce": nonce, "addr": addr}
	var w := NetWriter.new(NetProtocol.S_CHALLENGE)
	w.u16(NetProtocol.VERSION)
	w.text(NetProtocol.game_version(), 32)
	w.text(str(cfg["name"]), 80)
	w.raw(nonce)
	var flags := 0
	if str(cfg["password"]) != "":
		flags |= 1
	if dedicated:
		flags |= 2
	w.u8(flags)
	w.u8(_count_players(false))
	w.u8(int(cfg["max_players"]))
	# v3: what the joining side compares with Mods.compare() before it says hello
	w.text(Content.content_hash(), 80)
	NetProtocol.write_packages(w, Content.package_list())
	transport.send(peer, NetProtocol.CH_CONTROL, w.data(), true)


func _reject(peer: int, code: int, message: String, details: Array = []) -> void:
	var w := NetWriter.new(NetProtocol.S_REJECT)
	w.u8(code)
	w.text(message, 400)
	var n := mini(details.size(), 32)
	w.u8(n)
	for i in n:
		w.text(str(details[i]), 200)
	transport.send(peer, NetProtocol.CH_CONTROL, w.data(), true)
	transport.disconnect_peer(peer, code, true)
	_pending.erase(peer)
	Log.i("net", "rejected %s: %s %s%s" % [transport.address(peer), NetProtocol.reason_name(code), message,
		(" [" + "; ".join(PackedStringArray(details)) + "]") if not details.is_empty() else ""])


func _handle_hello(peer: int, data: PackedByteArray) -> void:
	var pend: Dictionary = _pending.get(peer, {})
	if pend.is_empty():
		return
	var r := NetReader.new(data, 1)
	var proto := r.u16()
	var gv := r.text(32)
	# the rest of the layout depends on the protocol: check it before reading further
	if r.ok and proto != NetProtocol.VERSION:
		_reject(peer, NetProtocol.R_PROTOCOL, "server protocol %d, client protocol %d" % [NetProtocol.VERSION, proto],
			["Server game version: %s" % NetProtocol.game_version(), "Your game version: %s" % gv])
		return
	var chash := r.text(80)
	var pkgs := NetProtocol.read_packages(r)
	var pname := r.text(80)
	var proof := r.blob(64)
	var token := r.blob(32)
	var flags := r.u8()
	var creature := r.text(64)
	var assist := NetProtocol.assist_from_byte(r.u8())
	if not r.ok or not r.expect_end():
		_reject(peer, NetProtocol.R_VIOLATION, "malformed hello (%s)" % r.error)
		return
	if gv != NetProtocol.game_version():
		_reject(peer, NetProtocol.R_GAME_VERSION, "server runs %s, you run %s" % [NetProtocol.game_version(), gv],
			["Server game version: %s" % NetProtocol.game_version(), "Your game version: %s" % gv])
		return
	# authority check (the client already compared on its side; a modified one may not have)
	var verdict := NetProtocol.content_verdict(Mods.compare(pkgs), pkgs, chash == Content.content_hash())
	if not bool(verdict["ok"]):
		_reject(peer, NetProtocol.R_CONTENT, "content differs", content_diff(pkgs))
		return
	if not (verdict["hash_only"] as Array).is_empty():
		Log.i("net", "%s: package(s) %s differ only outside gameplay files; allowed" % [str(pend["addr"]), str(verdict["hash_only"])])
	var addr := str(pend["addr"])
	var clean := NetProtocol.clean_name(pname)
	var ban := _ban_for(token, addr, clean)
	if not ban.is_empty():
		_reject(peer, NetProtocol.R_KICKED, str(ban.get("reason", "kicked")),
			["You can rejoin in %d s." % ceili((int(ban["until"]) - Time.get_ticks_msec()) / 1000.0)])
		return
	if str(cfg["password"]) != "":
		var expect := NetProtocol.password_proof(pend["nonce"], str(cfg["password"]))
		if not NetProtocol.bytes_equal(expect, proof):
			_reject(peer, NetProtocol.R_PASSWORD, "wrong password")
			return
	# rejoin into a reserved slot?
	var rejoin: NetPlayer = null
	if token.size() == NetProtocol.TOKEN_BYTES:
		for p in players.values():
			var np: NetPlayer = p
			if np.peer != -1 and NetProtocol.bytes_equal(np.token, token):
				rejoin = np
				break
	if rejoin:
		_pending.erase(peer)
		rejoin.assist = assist
		_bind_rejoin(rejoin, peer, addr)
		return
	var want_spectate := flags & 1 != 0
	var as_spectator := want_spectate
	if not want_spectate and _count_players(true) >= int(cfg["max_players"]):
		as_spectator = true
	if as_spectator and _count_spectators() >= int(cfg["max_spectators"]):
		_reject(peer, NetProtocol.R_FULL, "%d/%d players, %d/%d spectators" % [_count_players(true), int(cfg["max_players"]),
			_count_spectators(), int(cfg["max_spectators"])])
		return
	_pending.erase(peer)
	var p2 := NetPlayer.new()
	p2.id = _next_player_id
	_next_player_id += 1
	p2.peer = peer
	p2.name = _unique_name(clean, p2.id)
	p2.creature = _valid_creature(creature)
	p2.assist = assist
	p2.spectator = as_spectator
	p2.slot = -1 if as_spectator else _free_slot()
	p2.token = NetProtocol.random_bytes(NetProtocol.TOKEN_BYTES)
	p2.address = addr
	p2.joined_ms = Time.get_ticks_msec()
	p2.last_rx_ms = p2.joined_ms
	players[p2.id] = p2
	_peer_player[peer] = p2.id
	_send_welcome(p2, false, as_spectator and not want_spectate)
	Log.i("net", "player %d '%s' joined from %s%s" % [p2.id, p2.name, addr, " as spectator" if as_spectator else ""])
	notice("%s joined%s." % [p2.name, " (spectating)" if as_spectator else ""])
	player_joined.emit(p2.to_public())
	_lobby_dirty = true
	if phase == PHASE_IDLE:
		_enter_lobby()
	if phase == PHASE_MATCH or phase == PHASE_RESULTS:
		_send_match_start(p2)


func _send_welcome(p: NetPlayer, rejoined: bool, full_spectator: bool) -> void:
	var w := NetWriter.new(NetProtocol.S_WELCOME)
	w.u32(p.id)
	w.blob(p.token)
	var flags := 0
	if rejoined:
		flags |= 1
	if p.spectator:
		flags |= 2
	if full_spectator:
		flags |= 4
	if dedicated:
		flags |= 8
	w.u8(flags)
	w.text(str(cfg["name"]), 80)
	w.u16(int(cfg["tick_rate"]))
	w.u8(int(cfg["snapshot_rate"]))
	w.text(str(cfg["motd"]), 400)
	transport.send(p.peer, NetProtocol.CH_CONTROL, w.data(), true)
	_send_lobby_to(p)


func _bind_rejoin(p: NetPlayer, peer: int, addr: String) -> void:
	if p.peer > 0 and p.connected:
		# same player connected again (e.g. crashed client restarted before the old link timed out)
		var old := p.peer
		_peer_player.erase(old)
		var w := NetWriter.new(NetProtocol.S_KICKED)
		w.u8(NetProtocol.R_REPLACED)
		w.text("You connected again from another session.", 200)
		transport.send(old, NetProtocol.CH_CONTROL, w.data(), true)
		transport.disconnect_peer(old, NetProtocol.R_REPLACED, true)
	p.peer = peer
	p.connected = true
	p.left_voluntarily = false
	p.address = addr
	p.match_seen = 0
	p.last_rx_ms = Time.get_ticks_msec()
	_peer_player[peer] = p.id
	if sim != null and p.fighter >= 0 and p.fighter < sim.fighters.size() and phase == PHASE_MATCH:
		if p.input == null:
			p.input = NetRemoteInput.new(p.id, p.name)
		p.input.rebind()
		sim.set_input_source(p.fighter, p.input)
		sim.fighters[p.fighter].controller_kind = "net"
	_send_welcome(p, true, false)
	Log.i("net", "player %d '%s' rejoined from %s (fighter %d)" % [p.id, p.name, addr, p.fighter])
	notice("%s is back%s." % [p.name, " and has their fighter again" if p.fighter >= 0 and phase == PHASE_MATCH else ""])
	_lobby_dirty = true
	if phase == PHASE_MATCH or phase == PHASE_RESULTS:
		_send_match_start(p)


## Human-readable explanation of a content mismatch from the joining player's side (MOD-05),
## used when the server refuses a hello (clients normally refuse first, with Mods.compare()).
## Presentation-only (client_only) packages never count.
func content_diff(client_pkgs: Array) -> Array:
	var mine := {}
	for p in Content.package_list():
		if not bool(p.get("client_only", false)):
			mine[str(p["id"])] = p
	var theirs := {}
	for p in client_pkgs:
		if typeof(p) == TYPE_DICTIONARY and not bool(p.get("client_only", false)):
			theirs[str(p.get("id", ""))] = p
	var lines: Array = []
	var ids: Array = mine.keys()
	ids.sort()
	for id in ids:
		var mv := str(mine[id]["version"])
		if not theirs.has(id):
			lines.append("Missing on your side: %s %s (the server uses it)" % [id, mv])
		elif str(theirs[id].get("version", "")) != mv:
			lines.append("Different version of %s: server %s, yours %s" % [id, mv, str(theirs[id].get("version", ""))])
		elif str(mine[id].get("hash", "")) != "" and str(theirs[id].get("hash", "")) != "" and str(mine[id]["hash"]) != str(theirs[id]["hash"]):
			lines.append("Your copy of %s %s differs from the server's (same version, different files)" % [id, mv])
	var tids: Array = theirs.keys()
	tids.sort()
	for id in tids:
		if not mine.has(id):
			lines.append("Not on the server: %s %s (disable it to join)" % [id, str(theirs[id].get("version", ""))])
	if lines.is_empty():
		lines.append("Same packages and versions, but their gameplay files differ (an installed package was modified). Reinstall the packages on both sides.")
	return lines


func _ban_for(token: PackedByteArray, addr: String, pname: String) -> Dictionary:
	var now := Time.get_ticks_msec()
	_bans = _bans.filter(func(b): return int(b["until"]) > now)
	for b in _bans:
		var bd: Dictionary = b
		if token.size() > 0 and NetProtocol.bytes_equal(bd["token"], token):
			return bd
		if str(bd["addr"]) == addr and str(bd["name"]) == pname:
			return bd
	return {}


func _count_players(include_reserved: bool) -> int:
	var n := 0
	for p in players.values():
		var np: NetPlayer = p
		if np.spectator:
			continue
		if np.connected or include_reserved:
			n += 1
	return n


func _count_spectators() -> int:
	var n := 0
	for p in players.values():
		if (p as NetPlayer).spectator:
			n += 1
	return n


func _free_slot() -> int:
	var used := {}
	for p in players.values():
		var np: NetPlayer = p
		if not np.spectator and np.slot >= 0:
			used[np.slot] = true
	for s in NetProtocol.MAX_PLAYERS:
		if not used.has(s):
			return s
	return -1


func _unique_name(n: String, self_id: int) -> String:
	var taken := {}
	for p in players.values():
		var np: NetPlayer = p
		if np.id != self_id:
			taken[np.name.to_lower()] = true
	if not taken.has(n.to_lower()):
		return n
	for k in range(2, 100):
		var cand := "%s (%d)" % [n.substr(0, NetProtocol.MAX_NAME - 4), k]
		if not taken.has(cand.to_lower()):
			return cand
	return "%s#%d" % [n.substr(0, 12), self_id]


func _valid_creature(id: String) -> String:
	var playable := Content.playable_creatures()
	if playable.has(id):
		return id
	return str(playable[0]) if not playable.is_empty() else ""


# =====================================================================================
# Receiving
# =====================================================================================

func _on_receive(peer: int, channel: int, data: PackedByteArray) -> void:
	var pid := int(_peer_player.get(peer, 0))
	if data.is_empty():
		_violation_peer(peer, pid, 5.0, "empty packet")
		return
	var id := int(data[0])
	if not NetProtocol.MAX_SIZE.has(id):
		_violation_peer(peer, pid, 6.0, "unexpected message id %d" % id)
		return
	if data.size() > int(NetProtocol.MAX_SIZE[id]):
		if pid != 0:
			kick(pid, "oversized message", NetProtocol.R_VIOLATION)
		else:
			_reject(peer, NetProtocol.R_VIOLATION, "oversized message")
		return
	var expected_ch := NetProtocol.CH_INPUT if id == NetProtocol.C_INPUT else NetProtocol.CH_CONTROL
	if channel != expected_ch:
		_violation_peer(peer, pid, 3.0, "message %d on channel %d" % [id, channel])
		return
	if pid == 0:
		if id == NetProtocol.C_HELLO and _pending.has(peer):
			_handle_hello(peer, data)
		elif _pending.has(peer):
			_reject(peer, NetProtocol.R_VIOLATION, "message %d before handshake" % id)
		return
	var p: NetPlayer = players.get(pid)
	if p == null:
		return
	p.bytes_in += data.size()
	p.last_rx_ms = Time.get_ticks_msec()
	if not p.rl_bytes.take(float(data.size())):
		kick(p.id, "flooding", NetProtocol.R_FLOOD)
		return
	match id:
		NetProtocol.C_INPUT:
			_handle_input(p, data)
		NetProtocol.C_HELLO:
			_violation(p, 4.0, "duplicate hello")
		NetProtocol.C_LEAVE:
			p.left_voluntarily = true
			transport.disconnect_peer(p.peer, NetProtocol.R_LEFT, true)
		NetProtocol.C_LOBBY:
			if _rate(p, p.rl_control):
				_handle_lobby(p, data)
		NetProtocol.C_CHAT:
			if _rate(p, p.rl_chat):
				_handle_chat(p, data)
		NetProtocol.C_VOTE:
			if _rate(p, p.rl_control):
				_handle_vote(p, data)
		NetProtocol.C_APP:
			if _rate(p, p.rl_app):
				_handle_app(p, data)
		NetProtocol.C_PING:
			if _rate(p, p.rl_control):
				_handle_ping(p, data)


func _rate(p: NetPlayer, rl: NetRateLimiter) -> bool:
	if rl.take(1.0):
		return true
	_violation(p, 0.5, "rate limit")
	return false


func _violation_peer(peer: int, pid: int, points: float, why: String) -> void:
	if pid != 0 and players.has(pid):
		_violation(players[pid], points, why)
	elif _pending.has(peer):
		_reject(peer, NetProtocol.R_VIOLATION, why)


func _violation(p: NetPlayer, points: float, why: String) -> void:
	var now := Time.get_ticks_msec()
	p.violations = maxf(0.0, p.violations - float(now - p.violation_ms) / 1000.0 * VIOLATION_DECAY) + points
	p.violation_ms = now
	if p.violation_log < 8:
		p.violation_log += 1
		Log.w("net", "protocol violation by player %d '%s': %s (score %.1f)" % [p.id, p.name, why, p.violations])
	if p.violations >= VIOLATION_KICK:
		kick(p.id, "protocol violation (%s)" % why, NetProtocol.R_VIOLATION)


func _handle_input(p: NetPlayer, data: PackedByteArray) -> void:
	if not p.rl_input.take(1.0):
		_violation(p, 0.25, "input rate")
		return
	var r := NetReader.new(data, 1)
	var seq := r.u16()
	var ack_tick := r.u32()
	var n := r.count(NetProtocol.MAX_INPUT_SAMPLES)
	var samples: Array[FighterInput] = []
	for i in n:
		samples.append(NetSnapshot.read_input(r))
	if not r.ok or n == 0 or not r.expect_end():
		_violation(p, 4.0, "malformed input (%s)" % r.error)
		return
	p.last_input_seq = seq
	p.last_ack_tick = ack_tick
	if p.input != null and phase == PHASE_MATCH and p.fighter >= 0:
		p.input.push(seq, samples)


func _handle_lobby(p: NetPlayer, data: PackedByteArray) -> void:
	var r := NetReader.new(data, 1)
	var kind := r.u8()
	match kind:
		NetProtocol.LQ_READY:
			var v := r.boolean()
			if r.expect_end():
				set_ready(p.id, v)
		NetProtocol.LQ_CREATURE:
			var cid := r.text(64)
			if r.expect_end():
				set_creature(p.id, cid)
		NetProtocol.LQ_TEAM:
			var t := r.i8()
			if r.expect_end():
				set_team(p.id, t)
		NetProtocol.LQ_SPECTATE:
			var s := r.boolean()
			if r.expect_end():
				set_spectator(p.id, s)
		NetProtocol.LQ_ASSIST:
			var a := r.u8()
			if r.expect_end():
				p.assist = NetProtocol.assist_from_byte(a)
		NetProtocol.LQ_COSMETICS:
			var cb := r.blob(NetProtocol.MAX_COSMETICS_BYTES)
			if r.expect_end():
				var dec := NetProtocol.decode_payload(cb)
				if bool(dec["ok"]):
					set_cosmetics(p.id, dec["value"])
				else:
					_violation(p, 2.0, "bad cosmetics payload: %s" % str(dec["error"]))
		_:
			# host-only requests never come over the network (the listen host is local)
			_violation(p, 2.0, "lobby request %d not allowed" % kind)
			return
	if not r.ok:
		_violation(p, 3.0, "malformed lobby request (%s)" % r.error)


func _handle_chat(p: NetPlayer, data: PackedByteArray) -> void:
	var r := NetReader.new(data, 1)
	var text := r.text(600)
	if not r.expect_end():
		_violation(p, 3.0, "malformed chat")
		return
	say_as(p.id, text)


func _handle_vote(p: NetPlayer, data: PackedByteArray) -> void:
	var r := NetReader.new(data, 1)
	var c := r.i8()
	if not r.expect_end():
		_violation(p, 3.0, "malformed vote")
		return
	cast_vote(p.id, c)


func _handle_app(p: NetPlayer, data: PackedByteArray) -> void:
	var r := NetReader.new(data, 1)
	var t := r.text(NetProtocol.MAX_APP_TYPE)
	var blob := r.blob(NetProtocol.MAX_APP_PAYLOAD)
	if not r.expect_end() or not NetProtocol.valid_app_type(t):
		_violation(p, 5.0, "malformed app message")
		return
	var dec := NetProtocol.decode_payload(blob)
	if not bool(dec["ok"]):
		_violation(p, 5.0, "bad app payload: %s" % dec["error"])
		return
	if t == NetProtocol.APP_RELAY:
		var v: Dictionary = dec["value"]
		var it := str(v.get("type", ""))
		var ip = v.get("payload", {})
		var to := str(v.get("to", ""))
		if typeof(ip) != TYPE_DICTIONARY or not NetProtocol.valid_app_type(it) or it.begins_with("net.") or it.begins_with("mode.") or to.length() > 12:
			_violation(p, 1.0, "bad relay request")
			return
		if p.spectator or not bool(cfg.get("party_relay", true)):
			return
		if blob.size() > NetProtocol.MAX_RELAY_PAYLOAD:
			_violation(p, 1.0, "relay payload of %d bytes" % blob.size())
			return
		# the server sends one copy per recipient: the extra copies count against the sender's
		# app and byte budgets, so a client cannot multiply its upload through the relay
		var copies := relay_targets(p.id, to).size()
		if copies > 1 and (not p.rl_app.take(float(copies - 1)) or not p.rl_bytes.take(float(blob.size() * (copies - 1)))):
			_violation(p, 0.5, "relay rate")
			return
		relay_app(p.id, to, it, ip)
		return
	if t.begins_with("net."):
		match t:
			NetProtocol.APP_PARTY_CLAIM:
				_party_claim(p, dec["value"])
			NetProtocol.APP_PARTY_LEAVE:
				if _party_unseat(p.id):
					_flush_lobby_now()
			_:
				_violation(p, 1.0, "unknown request '%s'" % t)
		return
	if t.begins_with("mode."):
		handle_mode_request(p.id, t, dec["value"])
		return
	app_request.emit(p.id, t, dec["value"])


## Built-in requests from players that a mode exposes for remote humans (validated here):
##   mode.pick {choice: int}  - take one of the offered upgrades (Chum Rush breaks)
func handle_mode_request(pid: int, t: String, payload: Dictionary) -> void:
	var p: NetPlayer = players.get(pid)
	if p == null or sim == null or phase != PHASE_MATCH or p.fighter < 0 or sim.mode == null:
		return
	match t:
		"mode.pick":
			if sim.mode.has_method("choose_pick"):
				sim.mode.call("choose_pick", p.fighter, int(payload.get("choice", -1)))
		_:
			if p.peer > 0:
				_violation(p, 1.0, "unknown mode request '%s'" % t)


## Mode picks offered to human players (Chum Rush supplements between waves) must not let one
## player stall the session: an unanswered pick is taken for them (first offer) after
## pick_timeout_ms - remote players and the listen host's own player alike. Bots choose at once.
func _check_mode_picks(now: int) -> void:
	if sim == null or not is_instance_valid(sim) or sim.mode == null or phase != PHASE_MATCH:
		_pick_since.clear()
		return
	var pend = sim.mode.get("pending_pick")
	if typeof(pend) != TYPE_DICTIONARY or not sim.mode.has_method("choose_pick"):
		return
	var pd: Dictionary = pend
	for k in _pick_since.keys():
		if not pd.has(k):
			_pick_since.erase(k)
	for k in pd.keys():
		var i := int(k)
		if i < 0 or i >= sim.fighters.size() or not (sim.fighters[i].controller_kind in ["net", "player"]):
			continue
		if not _pick_since.has(i):
			_pick_since[i] = now
		elif now - int(_pick_since[i]) >= pick_timeout_ms:
			_pick_since.erase(i)
			sim.mode.call("choose_pick", i, 0)
			notice("%s's pick was made automatically (no answer within %d s)." % [sim.fighters[i].display_name, roundi(pick_timeout_ms / 1000.0)])


func _handle_ping(p: NetPlayer, data: PackedByteArray) -> void:
	var r := NetReader.new(data, 1)
	var echo := r.u32()
	if not r.expect_end():
		_violation(p, 2.0, "malformed ping")
		return
	var w := NetWriter.new(NetProtocol.S_PONG)
	w.u32(echo)
	w.u32(Time.get_ticks_msec())
	transport.send(p.peer, NetProtocol.CH_CONTROL, w.data(), false)


# =====================================================================================
# Lobby actions (shared by network requests and the local host)
# =====================================================================================

func set_ready(pid: int, v: bool) -> void:
	var p: NetPlayer = players.get(pid)
	if p and p.ready != v:
		p.ready = v
		_lobby_dirty = true


func set_creature(pid: int, cid: String) -> void:
	var p: NetPlayer = players.get(pid)
	if p == null:
		return
	if not Content.playable_creatures().has(cid):
		if pid != local_player_id:
			_violation(p, 1.0, "unknown creature '%s'" % cid.substr(0, 40))
		return
	p.creature = cid
	_lobby_dirty = true


## A player's equipped cosmetics (wearables, name-card frame, JUICE colour): validated against the
## known cosmetic ids (NetProtocol.clean_cosmetics) and shown to everyone - lobby rows and the
## fighter's look in matches. Presentation only: the simulation never reads them.
func set_cosmetics(pid: int, v) -> void:
	var p: NetPlayer = players.get(pid)
	if p == null:
		return
	var clean := NetProtocol.clean_cosmetics(v)
	if clean != p.cosmetics:
		p.cosmetics = clean
		_lobby_dirty = true


func set_team(pid: int, t: int) -> void:
	var p: NetPlayer = players.get(pid)
	if p:
		p.team = clampi(t, -1, NetProtocol.MAX_FIGHTERS - 1)
		_lobby_dirty = true


func set_spectator(pid: int, on: bool) -> void:
	var p: NetPlayer = players.get(pid)
	if p == null or p.spectator == on:
		return
	if on:
		p.spectator = true
		p.slot = -1
		p.ready = false
	else:
		if _count_players(true) >= int(cfg["max_players"]):
			_send_notice_to(p, "No free player slot right now.")
			return
		p.spectator = false
		p.slot = _free_slot()
	_lobby_dirty = true


func cast_vote(pid: int, c: int) -> void:
	var p: NetPlayer = players.get(pid)
	if p == null or vote.is_empty() or not bool(vote.get("open", false)):
		return
	var cands: Array = vote.get("candidates", [])
	p.vote = c if c >= 0 and c < cands.size() else -1
	_lobby_dirty = true


## Host settings (listen server). Returns an error text or "".
func host_set(key: String, value) -> String:
	match key:
		"rules":
			# any preset the host has: core, mods, or the player's own saved presets ("user:...")
			var r := NetPlaylist.resolve_rules(str(value), settings["rules_override"])
			if r.is_empty():
				return "unknown rules preset '%s'" % str(value)
			var bad := NetProtocol.rules_problem(r)
			if bad != "":
				return "rules preset '%s' is invalid: %s" % [str(value), bad]
			settings["rules"] = str(value)
		"arena":
			if Content.arena(str(value)) == null:
				return "unknown arena '%s'" % str(value)
			settings["arena"] = str(value)
		"bots":
			settings["bots"] = clampi(int(value), 0, NetProtocol.MAX_FIGHTERS - 1)
		"bot_difficulty":
			if not BotBrain.PROFILES.has(str(value)):
				return "unknown bot difficulty '%s'" % str(value)
			settings["bot_difficulty"] = str(value)
		"rules_override":
			if typeof(value) != TYPE_DICTIONARY:
				return "rules_override must be a dictionary"
			var r2 := NetPlaylist.resolve_rules(str(settings["rules"]), value)
			var bad2 := NetProtocol.rules_problem(r2) if not r2.is_empty() else ""
			if bad2 != "":
				return "these rule changes are invalid: %s" % bad2
			settings["rules_override"] = (value as Dictionary).duplicate(true)
		"bot_policy":
			# AI Lab policies for the bot slots (one id or a list, used in turn; "" / [] = scripted bots)
			var ids: Array = []
			if typeof(value) == TYPE_ARRAY:
				ids = (value as Array).map(func(x) -> String: return str(x)).filter(func(x: String) -> bool: return x != "")
			elif str(value) != "":
				ids = [str(value)]
			for pid in ids:
				if PolicyLibrary.get_policy(str(pid)) == null:
					return "AI policy '%s' is not available: %s" % [pid, PolicyLibrary.last_error(str(pid))]
			settings["bot_policy"] = ids
		"playlist":
			# listen host: a content playlist ("" = none) - players vote on its candidates and the
			# host starts the winner (host_start); dedicated servers take theirs from the config
			if dedicated:
				return "a dedicated server's playlist comes from its config"
			var plid := str(value)
			if plid == "":
				set_playlist(null)
			else:
				var pd := Content.get_entry("playlists", plid)
				if pd.is_empty():
					return "unknown playlist '%s'" % plid
				var pl := NetPlaylist.from_dict(pd, "content")
				pl.validate()
				if pl.valid_entries().is_empty():
					return "playlist '%s' has no entry this game can play" % plid
				set_playlist(pl)
		_:
			return "unknown setting '%s'" % key
	_lobby_dirty = true
	return ""


func say_as(pid: int, raw_text: String) -> void:
	var p: NetPlayer = players.get(pid)
	if p == null:
		return
	var text := NetProtocol.clean_text(raw_text, NetProtocol.MAX_CHAT)
	if text == "":
		return
	var w := NetWriter.new(NetProtocol.S_CHAT)
	w.u32(p.id)
	w.text(p.name, 80)
	w.text(text, 800)
	_broadcast_control(w.data())
	Log.i("chat", "%s: %s" % [p.name, text])
	chat_message.emit(p.id, p.name, text)


## Server notice to everyone (admin `say`, joins/leaves, playlist decisions).
func notice(text: String) -> void:
	var w := NetWriter.new(NetProtocol.S_NOTICE)
	w.text(text, 1000)
	_broadcast_control(w.data())
	notice_sent.emit(text)


func _send_notice_to(p: NetPlayer, text: String) -> void:
	if p.peer > 0:
		var w := NetWriter.new(NetProtocol.S_NOTICE)
		w.text(text, 1000)
		transport.send(p.peer, NetProtocol.CH_CONTROL, w.data(), true)
	elif p.peer == -1:
		notice_sent.emit(text)


func _broadcast_control(data: PackedByteArray) -> void:
	for p in players.values():
		var np: NetPlayer = p
		if np.peer > 0 and np.connected:
			transport.send(np.peer, NetProtocol.CH_CONTROL, data, true)


## App messages: server -> one player (id), or ALL. Returns false if nothing was sent.
func send_app(target: int, type: String, payload: Dictionary) -> bool:
	if not NetProtocol.valid_app_type(type):
		Log.w("net", "send_app: invalid type '%s'" % type)
		return false
	var bytes := NetProtocol.encode_payload(payload)
	if bytes.size() > NetProtocol.MAX_APP_PAYLOAD:
		Log.w("net", "send_app: payload of %d bytes exceeds %d" % [bytes.size(), NetProtocol.MAX_APP_PAYLOAD])
		return false
	var w := NetWriter.new(NetProtocol.S_APP)
	w.u32(SERVER_ID)
	w.text(type, NetProtocol.MAX_APP_TYPE)
	w.blob(bytes, true)
	var data := w.data()
	var sent := false
	for p in players.values():
		var np: NetPlayer = p
		if (target == ALL or np.id == target) and np.peer > 0 and np.connected:
			transport.send(np.peer, NetProtocol.CH_CONTROL, data, true)
			sent = true
	return sent


## Party relay (co-op transport): a member's message to one other member ("<id>") or to every
## other member (""), passed on with the sender's member id - always taken from the connection
## (`from_id` is the session player id the message arrived from), never from the message. Party
## member ids are session player ids, or the run's seat ids while a party run is open (then only
## seated players send or receive). Recipients are connected players (spectators are not party
## members); the listen host's own member gets it via `app_relayed`. Reserved types (net.*,
## mode.*) are never relayed. Returns how many members it reached.
func relay_app(from_id: int, to: String, type: String, payload: Dictionary) -> int:
	if not NetProtocol.valid_app_type(type) or type.begins_with("net.") or type.begins_with("mode."):
		return 0
	var from_member := party_member_of(from_id)
	if from_member <= 0:
		return 0
	var bytes := NetProtocol.encode_payload(payload)
	if bytes.size() > NetProtocol.MAX_APP_PAYLOAD:
		return 0
	var w := NetWriter.new(NetProtocol.S_APP)
	w.u32(from_member)
	w.text(type, NetProtocol.MAX_APP_TYPE)
	w.blob(bytes, true)
	var data := w.data()
	var targets := relay_targets(from_id, to)
	for np in targets:
		if np.peer == -1:
			app_relayed.emit.call_deferred(from_member, type, payload.duplicate(true))
		else:
			transport.send(np.peer, NetProtocol.CH_CONTROL, data, true)
	return targets.size()


## Members a party message from session player `from_id` to member `to` ("" = all others)
## reaches: connected players, not spectators, not the sender; the listen host's own member
## included. While a party run is open, `to` is a seat id and only seated players take part.
func relay_targets(from_id: int, to: String) -> Array[NetPlayer]:
	var out: Array[NetPlayer] = []
	if not party.is_empty():
		if _seat_of_session(from_id) == "":
			return out
		for s in party["seats"]:
			var sd: Dictionary = s
			var sid := int(sd["session"])
			if sid <= 0 or sid == from_id or (to != "" and str(sd["id"]) != to):
				continue
			var tp: NetPlayer = players.get(sid)
			if tp != null and tp.connected and not tp.spectator and (tp.peer == -1 or tp.peer > 0):
				out.append(tp)
		return out
	for p in players.values():
		var np: NetPlayer = p
		if np.id == from_id or np.spectator or not np.connected or (to != "" and str(np.id) != to):
			continue
		if np.peer == -1 or np.peer > 0:
			out.append(np)
	return out


# =====================================================================================
# Party seats (co-op party runs in the lobby)
# =====================================================================================

## The party member id of session player `session_id`: the session id itself, or - while a
## party run is open - the seat it holds (0 = not seated, not a party member).
func party_member_of(session_id: int) -> int:
	if party.is_empty():
		return session_id
	var seat := _seat_of_session(session_id)
	return int(seat) if seat != "" else 0


func _seat_of_session(session_id: int) -> String:
	if party.is_empty():
		return ""
	for s in party["seats"]:
		if int(s["session"]) == session_id:
			return str(s["id"])
	return ""


## Listen host: opens a co-op party run in the lobby. A run keeps the member ids it was played
## with (its player ids), but a new session gives everyone new session ids, so each run player
## becomes a seat that one session player holds; party messages then carry seat ids, stamped by
## this server from the connection, and only seated players take part. `seats`: [{id, name,
## fighter}] (ids = the run's player ids: 1-9 digit numbers, as runs started online have);
## `host_seat`: the host's own seat; `info`: a small plain summary for the lobby. Members claim
## their seat (net.party_claim, by run id). Returns "" or why not.
func party_open(run_id: String, seats: Array, host_seat: String, info: Dictionary = {}) -> String:
	if dedicated or local_player_id <= 0:
		return "party runs are hosted by a player (listen host)"
	if not NetProtocol.valid_party_run_id(run_id):
		return "invalid run id"
	if seats.is_empty() or seats.size() > NetProtocol.MAX_PARTY_SEATS:
		return "a party run has 1-%d players" % NetProtocol.MAX_PARTY_SEATS
	var out: Array = []
	var seen := {}
	for s in seats:
		if typeof(s) != TYPE_DICTIONARY:
			return "invalid seat"
		var sid := str((s as Dictionary).get("id", ""))
		if not NetProtocol.valid_seat_id(sid):
			return "seat '%s' is not an online member id (runs started online only)" % sid.left(16)
		if seen.has(sid):
			return "seat '%s' is listed twice" % sid
		seen[sid] = true
		out.append({"id": sid, "name": NetProtocol.clean_name(str(s.get("name", "Player"))),
			"fighter": str(s.get("fighter", "")).left(64), "session": 0})
	if not seen.has(host_seat):
		return "the host's seat '%s' is not in this run" % host_seat.left(16)
	var enc := NetProtocol.encode_payload(info)
	if enc.size() > NetProtocol.MAX_PARTY_INFO or not bool(NetProtocol.decode_payload(enc)["ok"]):
		return "party info must be small plain data"
	for s2 in out:
		if str(s2["id"]) == host_seat:
			s2["session"] = local_player_id
	party = {"run_id": run_id, "info": info.duplicate(true), "host_seat": host_seat, "seats": out}
	Log.i("net", "party run %s open: %d seats, host seat %s" % [run_id, out.size(), host_seat])
	_flush_lobby_now()
	return ""


func party_close() -> void:
	if party.is_empty():
		return
	Log.i("net", "party run %s closed" % str(party["run_id"]))
	party = {}
	_flush_lobby_now()


## A member claims a seat of the open party run: the run id must match, the seat must exist and
## be free (a seat whose holder disconnected stays theirs until their reservation ends), the
## claimant must be a player without a seat. The answer is the lobby (or an error message).
func _party_claim(p: NetPlayer, v: Dictionary) -> void:
	var why := ""
	var seat := str(v.get("seat", ""))
	if party.is_empty():
		why = "no party run is open"
	elif str(v.get("run_id", "")) != str(party["run_id"]):
		why = "the host offers a different run"
	elif p.spectator:
		why = "spectators cannot take a seat"
	elif _seat_of_session(p.id) != "":
		why = "you already hold seat %s" % _seat_of_session(p.id)
	else:
		why = "no such seat"
		for s in party["seats"]:
			if str(s["id"]) == seat:
				why = "" if int(s["session"]) <= 0 else "that seat is taken"
				if why == "":
					s["session"] = p.id
	if why != "":
		send_app(p.id, NetProtocol.APP_PARTY_CLAIM_RESULT, {"ok": false, "seat": seat, "error": why})
		return
	Log.i("net", "player %d '%s' took seat %s of party run %s" % [p.id, p.name, seat, str(party["run_id"])])
	_flush_lobby_now()


## Frees the seat a session player holds (left the session, or gave it up). True if it held one.
func _party_unseat(session_id: int) -> bool:
	if party.is_empty() or session_id == local_player_id:
		return false
	for s in party["seats"]:
		if int(s["session"]) == session_id:
			s["session"] = 0
			return true
	return false


func _party_public() -> Dictionary:
	if party.is_empty():
		return {}
	var seats: Array = []
	for s in party["seats"]:
		var sid := int(s["session"])
		var np: NetPlayer = players.get(sid)
		seats.append({"id": s["id"], "name": s["name"], "fighter": s["fighter"], "session": sid,
			"connected": np != null and np.connected})
	return {"run_id": party["run_id"], "info": party["info"], "host_seat": party["host_seat"], "seats": seats}


## Seat changes go out at once (members switch their party ids on it), not on the lobby timer.
func _flush_lobby_now() -> void:
	_lobby_dirty = false
	_lobby_sent_ms = Time.get_ticks_msec()
	if transport.is_open():
		_broadcast_control(_lobby_packet())
	lobby_changed.emit()


# =====================================================================================
# Disconnects, kicks, reservations
# =====================================================================================

func _on_peer_disconnected(peer: int, code: int) -> void:
	if _pending.has(peer):
		if code == NetProtocol.R_CONTENT:
			Log.i("net", "%s did not join: their content differs (they compared before saying hello)" % str(_pending[peer]["addr"]))
		_pending.erase(peer)
		return
	var pid := int(_peer_player.get(peer, 0))
	_peer_player.erase(peer)
	if pid == 0:
		return
	var p: NetPlayer = players.get(pid)
	if p == null or p.peer != peer:
		return
	p.peer = 0
	p.connected = false
	p.disconnected_ms = Time.get_ticks_msec()
	var grace := int(cfg["rejoin_grace"])
	var why := "left" if p.left_voluntarily else ("timed out" if code == 0 else NetProtocol.reason_name(code))
	if p.left_voluntarily or grace <= 0 or p.spectator or code == NetProtocol.R_KICKED or code == NetProtocol.R_LEFT:
		_remove_player(p, why)
		return
	_bot_takeover(p)
	Log.i("net", "player %d '%s' disconnected (%s); slot reserved for %d s" % [p.id, p.name, why, grace])
	notice("%s lost connection%s. They can rejoin within %d s." % [p.name,
		" - a bot holds their fighter" if p.fighter >= 0 and phase == PHASE_MATCH else "", grace])
	_lobby_dirty = true
	_check_empty()


func _remove_player(p: NetPlayer, reason: String) -> void:
	if not players.has(p.id):
		return
	_bot_takeover(p)
	players.erase(p.id)
	if p.peer > 0:
		_peer_player.erase(p.peer)
	_party_unseat(p.id)
	Log.i("net", "player %d '%s' removed (%s)" % [p.id, p.name, reason])
	notice("%s left (%s)." % [p.name, reason])
	player_left.emit(p.to_public(), reason)
	_lobby_dirty = true
	_check_empty()


func _bot_takeover(p: NetPlayer) -> void:
	if sim == null or p.fighter < 0 or p.fighter >= sim.fighters.size() or phase != PHASE_MATCH:
		return
	var f := sim.fighters[p.fighter]
	if f.controller_kind == "bot":
		return
	_bot_serial += 1
	var bot: InputSource = null
	if _bot_maker.is_valid():
		# a co-op campaign fight: the party run's own bot rules (tier capped at Contender)
		bot = _bot_maker.call(f)
	if bot == null:
		var bb := BotBrain.new(str(cfg.get("bot_difficulty", "regular")), int(match_info.get("seed", 1)) * 31 + 977 * _bot_serial + p.fighter)
		bb.set_personality(f.creature.ai)
		bot = bb
	if bot is BotBrain:
		(bot as BotBrain).label_text = "%s (bot)" % p.name
	sim.set_input_source(p.fighter, bot)
	f.controller_kind = "bot"
	# a pick offered to the player (e.g. Chum Rush supplements) is taken by the bot right away
	var pend = sim.mode.get("pending_pick") if sim.mode else null
	if typeof(pend) == TYPE_DICTIONARY and (pend as Dictionary).has(p.fighter) and sim.mode.has_method("choose_pick"):
		sim.mode.call("choose_pick", p.fighter, 0)


## Kicks a player (admin / host / violations). Kicked players are banned for kick_ban_seconds.
func kick(pid: int, reason: String, code := NetProtocol.R_KICKED) -> bool:
	var p: NetPlayer = players.get(pid)
	if p == null or p.peer == -1:
		return false
	var ban_s := int(cfg["kick_ban_seconds"])
	if ban_s > 0 and code != NetProtocol.R_REPLACED:
		_bans.append({"token": p.token, "addr": p.address, "name": p.name, "reason": reason,
			"until": Time.get_ticks_msec() + ban_s * 1000})
		while _bans.size() > 256:
			_bans.pop_front()
	Log.w("net", "kicking player %d '%s': %s" % [p.id, p.name, reason])
	if p.peer > 0:
		var w := NetWriter.new(NetProtocol.S_KICKED)
		w.u8(code)
		w.text(reason, 200)
		transport.send(p.peer, NetProtocol.CH_CONTROL, w.data(), true)
		transport.disconnect_peer(p.peer, code, true)
		_peer_player.erase(p.peer)
	p.peer = 0
	p.connected = false
	_remove_player(p, "kicked: %s" % reason)
	return true


func find_player(id_or_name: String) -> NetPlayer:
	if id_or_name.is_valid_int() and players.has(id_or_name.to_int()):
		return players[id_or_name.to_int()]
	for p in players.values():
		var np: NetPlayer = p
		if np.name.to_lower() == id_or_name.to_lower():
			return np
	return null


func _human_players() -> Array:
	var out: Array = []
	for p in players.values():
		var np: NetPlayer = p
		if not np.spectator and np.connected:
			out.append(np)
	return out


func _connected_count() -> int:
	var n := 0
	for p in players.values():
		if (p as NetPlayer).connected:
			n += 1
	return n


func _check_empty() -> void:
	if not dedicated:
		return
	if _connected_count() > 0:
		return
	if str(cfg["empty_behavior"]) == "idle":
		if phase == PHASE_MATCH:
			end_match_now("everyone left")
		elif phase == PHASE_LOBBY:
			_enter_idle()


func _enter_idle() -> void:
	phase = PHASE_IDLE
	vote = {}
	phase_until = 0
	_lobby_dirty = true
	Log.i("net", "server idle (no players)")


func _enter_lobby() -> void:
	phase = PHASE_LOBBY
	vote = {}
	phase_until = 0
	_lobby_dirty = true


# =====================================================================================
# Lobby / voting (dedicated) and match start
# =====================================================================================

func _tick_idle() -> void:
	if not dedicated:
		return
	if _connected_count() > 0 or str(cfg["empty_behavior"]) == "showcase":
		_enter_lobby()


func _tick_lobby() -> void:
	if not dedicated:
		# a listen host with a playlist: players vote while the host decides when to start
		if playlist != null and vote.is_empty():
			_open_vote()
			phase_until = 0
			_lobby_dirty = true
		return
	var humans := _human_players()
	if _connected_count() == 0 and str(cfg["empty_behavior"]) == "idle":
		_enter_idle()
		return
	var now := Time.get_ticks_msec()
	if vote.is_empty():
		_open_vote()
		return
	if not humans.is_empty() and phase_until - now > 3000:
		var all_ready := true
		for p in humans:
			if not (p as NetPlayer).ready:
				all_ready = false
		if all_ready:
			phase_until = now + 3000
			_lobby_dirty = true
	if now >= phase_until:
		_close_vote_and_start()


func _open_vote() -> void:
	var now := Time.get_ticks_msec()
	var humans := _human_players().size()
	var cands: Array = []
	if playlist:
		cands = playlist.draw_candidates(humans, bool(cfg["bots"]), mini(playlist.candidates_count, int(cfg["vote_candidates"])))
	for p in players.values():
		(p as NetPlayer).vote = -1
	vote = {"open": true, "candidates": cands, "opened": now}
	phase_until = now + int(cfg["lobby_time"]) * 1000
	if humans == 0 and str(cfg["empty_behavior"]) == "showcase":
		phase_until = now + 3000
	_lobby_dirty = true
	if cands.is_empty() and now - _wait_notice_ms > 15000:
		_wait_notice_ms = now
		notice("Waiting for players: no playlist entry can start with %d player%s." % [humans, "" if humans == 1 else "s"])


func _close_vote_and_start() -> void:
	var cands: Array = vote.get("candidates", [])
	if cands.is_empty():
		_open_vote()
		return
	var votes := {}
	for p in players.values():
		var np: NetPlayer = p
		if np.vote >= 0 and np.connected:
			votes[np.id] = np.vote
	var res := playlist.resolve_vote(cands, votes)
	vote["open"] = false
	var entry: Dictionary = res["entry"]
	var tally: Array = res["tally"]
	var why := ""
	match str(res["reason"]):
		"votes":
			why = "won the vote (%s)" % "-".join(PackedStringArray(tally.map(func(x): return str(x))))
		"tie":
			why = "tie broken by playlist weight (%s)" % "-".join(PackedStringArray(tally.map(func(x): return str(x))))
		_:
			why = "no votes: highest weight"
	Log.i("net", "playlist pick: %s (%s)" % [entry["key"], why])
	notice("Next: %s - %s." % [entry["name"], why])
	var lim := playlist.limits_for(entry)
	var bots_allowed := NetPlaylist.bot_allowance(entry, bool(cfg["bots"]))
	var policies: Array = entry.get("bot_policy", [])
	if policies.is_empty():
		policies = NetServerConfig.policy_ids(cfg)
	var err := start_match(str(entry["rules"]), playlist.rules_for(entry), str(entry["arena"]), lim.x, lim.y, bots_allowed,
		str(cfg["bot_difficulty"]), playlist.describe_entry(entry), 0, policies)
	if err != "":
		Log.w("net", "cannot start '%s': %s" % [entry["key"], err])
		notice("Cannot start %s: %s" % [entry["name"], err])
		if err.begins_with("missing content") or err.begins_with("invalid rules"):
			entry["valid"] = false
			(entry["errors"] as Array).append(err)
			playlist.errors.append("entry %d (%s): %s - skipped" % [int(entry["index"]) + 1, entry["key"], err])
		_open_vote()


## Listen host: start with the host's lobby settings - or, with a playlist, the voted entry.
func host_start() -> String:
	if phase != PHASE_LOBBY:
		return "a match is already running"
	if playlist != null:
		if (vote.get("candidates", []) as Array).is_empty():
			_open_vote()
			phase_until = 0
		if (vote.get("candidates", []) as Array).is_empty():
			var n := _human_players().size()
			return "no playlist entry can start with %d player%s" % [n, "" if n == 1 else "s"]
		_close_vote_and_start()
		return "" if phase == PHASE_MATCH else "the voted entry could not start (see the notices)"
	var rules := NetPlaylist.resolve_rules(str(settings["rules"]), settings["rules_override"])
	if rules.is_empty():
		return "unknown rules preset '%s'" % settings["rules"]
	var lim := NetPlaylist.format_limits(rules)
	var extra := int(settings["bots"])
	return start_match(str(settings["rules"]), rules, str(settings["arena"]), lim.x, lim.y,
		NetProtocol.MAX_FIGHTERS, str(settings["bot_difficulty"]),
		{"key": "%s@%s" % [settings["rules"], settings["arena"]], "rules": settings["rules"], "arena": settings["arena"],
			"name": "%s @ %s" % [str(rules.get("name", settings["rules"])), str(settings["arena"])]}, extra, settings["bot_policy"])


## Starts a match. lo/hi: fighters needed / max human fighters. Returns "" or an error.
func start_match(rules_id: String, rules: Dictionary, arena_id: String, lo: int, hi: int, bot_allow: int,
		bot_difficulty: String, entry_info: Dictionary, extra_bots := 0, bot_policies: Array = []) -> String:
	var arena := Content.arena(arena_id)
	if arena == null:
		return "missing content: arena '%s' is not installed" % arena_id
	# a player-made layout ("user:...") exists only here: players get it as an arena package
	var arena_pkg := PackedByteArray()
	if arena_id.begins_with(ArenaLibrary.PREFIX) or Content.origin_of("arenas", arena_id) == "user":
		arena_pkg = _arena_package_bytes(arena)
		if arena_pkg.is_empty():
			return "missing content: arena '%s' could not be packaged for the players" % arena_id
	if rules.is_empty():
		return "missing content: rules preset '%s' is not installed" % rules_id
	# the full rules dictionary goes to every client, so it must pass the rules editor's validation
	var bad_rules := NetProtocol.rules_problem(rules)
	if bad_rules != "":
		return "invalid rules '%s': %s" % [rules_id, bad_rules]
	var mode_id := str(rules.get("mode", "standard"))
	if not ModeRegistry.ids().has(mode_id):
		return "missing content: mode '%s' is not installed" % mode_id
	var lim := NetPlaylist.format_limits(rules)
	hi = mini(hi, lim.y)
	# choose human fighters: players who sat out longest first, then by slot
	var humans := _human_players()
	humans.sort_custom(func(a, b): return a.sat_out > b.sat_out or (a.sat_out == b.sat_out and a.slot < b.slot))
	var chosen: Array = humans.slice(0, hi)
	for p in humans:
		var np: NetPlayer = p
		if chosen.has(np):
			np.sat_out = 0
		else:
			np.sat_out += 1
	var want := maxi(lo, chosen.size())
	var n_bots := clampi(want - chosen.size(), 0, bot_allow)
	n_bots = clampi(maxi(n_bots, extra_bots), 0, maxi(0, lim.y - chosen.size()))
	if chosen.size() + n_bots < lim.x or chosen.size() + n_bots < lo:
		return "not enough players (%d of %d needed; bots %s)" % [chosen.size(), lo, "allowed" if bot_allow > 0 else "disabled"]
	var total := chosen.size() + n_bots
	var teams := _team_layout(rules, chosen, total)
	var seed_v := _rng.randi() & 0x7FFFFFFF
	var fighters: Array = []
	var playable := Content.playable_creatures()
	for i in chosen.size():
		var p2: NetPlayer = chosen[i]
		var c := Content.creature(_valid_creature(p2.creature))
		if c == null:
			return "missing content: creature '%s'" % p2.creature
		var e := {"creature": c, "team": teams[i], "name": p2.name, "difficulty": bot_difficulty}
		if p2.peer == -1:
			e["kind"] = "player"
		else:
			p2.input = NetRemoteInput.new(p2.id, p2.name)
			e["kind"] = "net"
			e["source"] = p2.input
			# the remote player's accessibility aim assist (MatchScene does this for local players):
			# one of the setting's levels, or the normal level when the server decides for everyone
			e["mods"] = {"assist": p2.assist if bool(cfg.get("player_assist", true)) else 1.0}
		# presentation only: views dress the fighter (MatchScene / NetMatchScene); MatchSim ignores it
		if not p2.cosmetics.is_empty():
			e["cosmetics"] = p2.cosmetics.duplicate()
		p2.fighter = i
		fighters.append(e)
	var policy_list: Array = []      ## [{fighter, id, name, hash}] for MATCH_START and the log
	for b in n_bots:
		var idx := chosen.size() + b
		var cid := str(playable[_rng.randi() % playable.size()]) if not playable.is_empty() else ""
		# AI Lab policies drive their own creature; the server runs them, clients need nothing
		var pid := str(bot_policies[b % bot_policies.size()]) if not bot_policies.is_empty() else ""
		var pol: PolicyData = PolicyLibrary.get_policy(pid) if pid != "" else null
		if pol != null and Content.creature(pol.creature) != null:
			cid = pol.creature
		var cdef := Content.creature(cid)
		if cdef == null:
			return "missing content: no playable creature for bots"
		var e2 := {"creature": cdef, "team": teams[idx], "kind": "bot", "difficulty": bot_difficulty,
			"name": "Bot %d (%s)" % [b + 1, bot_difficulty.capitalize()]}
		if pid != "":
			e2["kind"] = "policy"
			e2["policy_id"] = pid
			e2["name"] = "%s %d" % [pol.name if pol != null and pol.name != "" else "Lab bot", b + 1]
			# the exact network is identified by its checksum ("" = missing or incompatible: the
			# scripted bot PolicyInputSource.for_match falls back to fights instead)
			var usable := pol != null and PolicyLibrary.compatibility(pol, cdef.id) == ""
			policy_list.append({"fighter": idx, "id": pid, "name": str(e2["name"]), "hash": _policy_hash(pol) if usable else ""})
		if dedicated:
			if pid != "":
				e2["source"] = PolicyInputSource.for_match(e2, seed_v * 31 + idx, idx)
			else:
				var bb := BotBrain.new(bot_difficulty, seed_v * 31 + idx)
				bb.set_personality(cdef.ai)
				e2["source"] = bb
		fighters.append(e2)
	for p3 in players.values():
		var np3: NetPlayer = p3
		if not chosen.has(np3):
			np3.fighter = -1
			np3.input = null
	match_id += 1
	_aborting = ""
	current_entry = entry_info.duplicate(true)
	var mode := ModeRegistry.create(mode_id)
	var cfg_m := {"arena": arena, "rules": rules.duplicate(true), "seed": seed_v, "mode": mode, "fighters": fighters,
		"online": true, "audio_context": "coop" if str(rules.get("format", "")) == "coop" else "versus"}
	if dedicated:
		sim = MatchSim.new()
		sim.running = false
		add_child(sim)
		sim.setup(cfg_m)
	else:
		scene = App.start_match(cfg_m, func(_r: Dictionary) -> void: pass)
		sim = scene.get("sim")
	if sim == null:
		return "the match could not be created"
	_sim_id = sim.get_instance_id()
	sim.finished.connect(_on_sim_finished)
	_ev_cursor = 0
	_tick_counter = 0
	_roster.clear()
	_gens = PackedByteArray()
	_check_roster()
	var fl := _roster_public()
	var public_rules := {}
	for k in rules:
		if not str(k).begins_with("_"):
			public_rules[k] = rules[k]
	match_info = {"match_id": match_id, "arena": arena.to_dict(), "arena_id": arena_id, "arena_hash": arena.content_hash(),
		"rules": public_rules, "rules_id": rules_id, "mode": mode_id, "tick_rate": int(cfg["tick_rate"]),
		"snapshot_rate": int(cfg["snapshot_rate"]), "fighters": fl, "entry": current_entry, "seed": seed_v}
	if not arena_pkg.is_empty():
		match_info["arena_package"] = arena_pkg
	# each human fighter's equipped cosmetics (fighter index -> {slot: id}), for the players' views
	var dressed := {}
	for i2 in chosen.size():
		var pc: NetPlayer = chosen[i2]
		if not pc.cosmetics.is_empty():
			dressed[str(i2)] = pc.cosmetics.duplicate()
	if not dressed.is_empty():
		match_info["cosmetics"] = dressed
	if not policy_list.is_empty():
		match_info["policies"] = policy_list
		for pe in policy_list:
			Log.i("net", "fighter %d: AI Lab policy '%s' %s" % [int(pe["fighter"]), str(pe["id"]),
				str(pe["hash"]).substr(0, 16) if str(pe["hash"]) != "" else "(unavailable: scripted bot)"])
	phase = PHASE_MATCH
	phase_until = 0
	for p5 in players.values():
		var np5: NetPlayer = p5
		np5.ready = false
		if np5.peer > 0 and np5.connected:
			_send_match_start(np5)
	_lobby_dirty = true
	Log.i("net", "match %d started: %s on %s, %d fighters (%d humans, %d bots)" % [match_id, rules_id, arena_id, total, chosen.size(), n_bots])
	match_started.emit(match_info)
	return ""


## Team per fighter index (humans first, then bots), matching the local setup rules:
## duel/ffa: everyone on their own team; teams/tag: round-robin honouring requests;
## coop: humans on team 0, bots join them, or face them when the preset has 2+ teams.
func _team_layout(rules: Dictionary, chosen: Array, total: int) -> Array[int]:
	var out: Array[int] = []
	out.resize(total)
	var fmt := str(rules.get("format", ""))
	var nteams := int(rules.get("teams", 0))
	if fmt == "coop":
		for i in total:
			out[i] = 0 if i < chosen.size() or nteams < 2 else 1
		return out
	var team_mode := fmt == "teams" or fmt == "tag" or (nteams >= 2 and fmt != "duel" and fmt != "ffa" and total > nteams)
	if not team_mode:
		for i in total:
			out[i] = i
		return out
	nteams = maxi(2, nteams)
	var per := ceili(float(total) / float(nteams))
	var counts: Array[int] = []
	counts.resize(nteams)
	counts.fill(0)
	var assigned: Array[bool] = []
	assigned.resize(total)
	assigned.fill(false)
	for i in chosen.size():
		var want := (chosen[i] as NetPlayer).team
		if want >= 0 and want < nteams and counts[want] < per:
			out[i] = want
			counts[want] += 1
			assigned[i] = true
	for i in total:
		if assigned[i]:
			continue
		var best := 0
		for t in nteams:
			if counts[t] < counts[best]:
				best = t
		out[i] = best
		counts[best] += 1
	return out


## Listen host: plays a co-op campaign fight of the party run (NetPartyRuns) as a match of this
## session. `cfg_m`: EncounterBuilder.build_match's config - the party's fighters with their
## builds and carried HP, the enemies with their brains, the campaign mode (party format: tag or
## simultaneous). `owners`: fighter index -> session player id of the party's human members. The
## host's own fighter is its local player ("player"); a connected member's fighter is driven by
## a NetRemoteInput fed from that member's input stream ("net"); a member who is away keeps the
## party bot the builder gave them, and gets the fighter back if they reconnect mid-fight
## (_bind_rejoin). `info`: plain campaign details for every client ({name, encounter, rule_tags,
## format, stand_in, run_id, node}); a client presents the fight like any match (NetMatchScene)
## after its own campaign checks (NetProtocol.campaign_match_problem). `bot_maker`: what drives
## a member's fighter if they drop mid-fight (the run's bot rules). The result goes out like any
## match's (match_finished, MATCH_END); `results_s` is this match's results phase. Returns "" or
## why not.
func start_campaign_match(cfg_m: Dictionary, owners: Dictionary, info: Dictionary, bot_maker: Callable = Callable(), results_s := 4) -> String:
	if dedicated or local_player_id <= 0:
		return "campaign fights are hosted by a player (listen host)"
	if phase != PHASE_LOBBY:
		return "a match is already running"
	var fighters: Array = cfg_m.get("fighters", [])
	if fighters.is_empty() or fighters.size() > NetProtocol.MAX_SLOTS:
		return "a campaign fight needs 1-%d fighters" % NetProtocol.MAX_SLOTS
	if not (cfg_m.get("mode") is MatchMode) or not (cfg_m.get("arena") is ArenaDef):
		return "the campaign fight was not built"
	var camp := NetProtocol.campaign_match_problem({"mode": (cfg_m["mode"] as MatchMode).id(), "rules": cfg_m.get("rules", {}), "campaign": info})
	if camp != "":
		return "invalid campaign fight: %s" % camp
	for p in players.values():
		var np: NetPlayer = p
		np.fighter = -1
		np.input = null
	var chosen: Array[NetPlayer] = []
	for k in owners:
		var i := int(k)
		var np2: NetPlayer = players.get(int(owners[k]))
		if np2 == null or np2.spectator or i < 0 or i >= fighters.size():
			continue
		var e: Dictionary = fighters[i]
		np2.fighter = i
		chosen.append(np2)
		if np2.peer == -1:
			e["kind"] = "player"
			e.erase("source")
		elif np2.connected and np2.peer > 0:
			np2.input = NetRemoteInput.new(np2.id, np2.name)
			e["kind"] = "net"
			e["source"] = np2.input
			var m: Dictionary = (e.get("mods", {}) as Dictionary).duplicate()
			m["assist"] = np2.assist if bool(cfg.get("player_assist", true)) else 1.0
			e["mods"] = m
		if not np2.cosmetics.is_empty():
			e["cosmetics"] = np2.cosmetics.duplicate()
	match_id += 1
	_aborting = ""
	_results_s = clampi(results_s, 1, 60)
	current_entry = {"key": "campaign:%s" % str(info.get("encounter", "")), "name": str(info.get("name", "Campaign fight")),
		"campaign": true, "rules": "campaign", "arena": (cfg_m["arena"] as ArenaDef).id}
	cfg_m["online"] = true
	if not cfg_m.has("audio_context"):
		cfg_m["audio_context"] = "coop"
	scene = App.start_match(cfg_m, func(_r: Dictionary) -> void: pass)
	sim = scene.get("sim") if scene != null else null
	if sim == null:
		_results_s = -1
		return "the campaign fight could not be created"
	_bot_maker = bot_maker
	_sim_id = sim.get_instance_id()
	sim.finished.connect(_on_sim_finished)
	_ev_cursor = 0
	_tick_counter = 0
	_roster.clear()
	_gens = PackedByteArray()
	_check_roster()
	# the arena exactly as the simulation runs it (its look/variant included), so every client
	# rebuilds and hash-checks the same layout
	var arena: ArenaDef = sim.arena
	var public_rules := {}
	var rules: Dictionary = cfg_m.get("rules", {})
	for k in rules:
		if not str(k).begins_with("_"):
			public_rules[k] = rules[k]
	match_info = {"match_id": match_id, "arena": arena.to_dict(), "arena_id": arena.id, "arena_hash": arena.content_hash(),
		"rules": public_rules, "rules_id": "campaign", "mode": sim.mode.id(), "tick_rate": int(cfg["tick_rate"]),
		"snapshot_rate": int(cfg["snapshot_rate"]), "fighters": _roster_public(), "entry": current_entry,
		"seed": int(cfg_m.get("seed", 0)), "campaign": info.duplicate(true)}
	var dressed := {}
	for np3 in chosen:
		if not np3.cosmetics.is_empty():
			dressed[str(np3.fighter)] = np3.cosmetics.duplicate()
	if not dressed.is_empty():
		match_info["cosmetics"] = dressed
	phase = PHASE_MATCH
	phase_until = 0
	for p5 in players.values():
		var np5: NetPlayer = p5
		np5.ready = false
		if np5.peer > 0 and np5.connected:
			_send_match_start(np5)
	_lobby_dirty = true
	Log.i("net", "match %d started: campaign fight '%s' (%s), %d fighters, party %s" % [match_id, str(info.get("name", "")),
		sim.mode.id(), sim.fighters.size(), str(owners)])
	match_started.emit(match_info)
	return ""


## Co-op ref timeout: holds (or releases) the running match - no simulation steps and the physics
## space inactive - while snapshots keep going out (clients see the frozen fight).
func set_frozen(on: bool) -> void:
	if on and (sim == null or phase != PHASE_MATCH):
		return
	if on == frozen:
		return
	frozen = on
	if sim != null and is_instance_valid(sim):
		sim.paused = on
		var w := sim.get_world_3d() if sim.is_inside_tree() else null
		if w != null:
			_frozen_space = w.space
	if _frozen_space.is_valid():
		PhysicsServer3D.space_set_active(_frozen_space, not on)
	if not on:
		_frozen_space = RID()
	Log.i("net", "match %d %s (ref timeout)" % [match_id, "frozen" if on else "resumed"])


func _results_time() -> int:
	return _results_s if _results_s > 0 else int(cfg["results_time"])


func _send_match_start(p: NetPlayer) -> void:
	if sim == null or match_info.is_empty():
		return
	var info := match_info.duplicate(true)
	info.erase("seed")
	info["fighters"] = _roster_public()
	info["you"] = p.fighter if not p.spectator else -1
	info["you_player"] = p.id
	info["elapsed_tick"] = sim.tick_count
	info["phase"] = phase
	var w := NetWriter.new(NetProtocol.S_MATCH_START)
	w.blob(var_to_bytes(info), true)
	transport.send(p.peer, NetProtocol.CH_EVENTS, w.data(), true)
	p.match_seen = match_id
	if phase == PHASE_RESULTS and not last_result.is_empty():
		_send_match_end_to(p)


# =====================================================================================
# Replication
# =====================================================================================

func _viewers() -> Array:
	var out: Array = []
	for p in players.values():
		var np: NetPlayer = p
		if np.peer > 0 and np.connected and np.match_seen == match_id:
			out.append(np)
	return out


func _replicate() -> void:
	# (a freed sim compares equal to null: check the remembered instance instead)
	if _sim_id != 0 and not is_instance_id_valid(_sim_id):
		_lost_match_scene()
		return
	if sim == null:
		return
	var changed := _check_roster()
	if not changed.is_empty():
		_send_roster(changed)
	_send_events()
	_tick_counter += 1
	if _tick_counter >= _snap_every:
		_tick_counter = 0
		_send_snapshot()


## Detects fighter slot changes (spawn into a slot, despawn, rebuild, controller/team/name).
## Body identity changes bump the slot generation. Returns the changed slot indices.
func _check_roster() -> Array:
	var changed: Array = []
	if sim == null:
		return changed
	var owners := {}
	for p in players.values():
		var np: NetPlayer = p
		if np.fighter >= 0:
			owners[np.fighter] = np.id
	var n := mini(sim.fighters.size(), NetProtocol.MAX_SLOTS)
	if _gens.size() < n:
		_gens.resize(n)
	for i in n:
		var f := sim.fighters[i]
		var cur := {"obj": f.get_instance_id(), "rig": f.rig.get_instance_id() if f.rig else 0,
			"creature": f.creature.id if f.creature else "", "scale": f.creature.body.scale if f.creature else 1.0,
			"despawned": NetSnapshot.is_despawned(f), "team": f.team, "name": f.display_name,
			"kind": f.controller_kind, "player": int(owners.get(i, 0)), "tags": NetSnapshot.flag_tags(f),
			"combat": f.combat_style, "loadout": f.loadout.duplicate()}
		if i >= _roster.size():
			cur["gen"] = 1
			_roster.append(cur)
			changed.append(i)
		else:
			var old: Dictionary = _roster[i]
			var body_changed: bool = old["obj"] != cur["obj"] or old["rig"] != cur["rig"] or old["creature"] != cur["creature"] \
				or absf(float(old["scale"]) - float(cur["scale"])) > 0.0001 or old["despawned"] != cur["despawned"]
			var info_changed: bool = old["team"] != cur["team"] or old["name"] != cur["name"] or old["kind"] != cur["kind"] \
				or old["player"] != cur["player"] or old["tags"] != cur["tags"] or old["combat"] != cur["combat"] \
				or old["loadout"] != cur["loadout"]
			if body_changed or info_changed:
				cur["gen"] = (int(old["gen"]) % 255) + 1 if body_changed else int(old["gen"])
				_roster[i] = cur
				changed.append(i)
		var e: Dictionary = _roster[i]
		_gens[i] = 0 if bool(e["despawned"]) else int(e["gen"])
	return changed


func _roster_public() -> Array:
	var out: Array = []
	for i in _roster.size():
		var e: Dictionary = _roster[i]
		out.append({"index": i, "slot": i, "gen": e["gen"], "player": e["player"], "name": e["name"],
			"creature": e["creature"], "scale": e["scale"], "team": e["team"], "kind": e["kind"], "despawned": e["despawned"],
			"tags": e["tags"], "combat": e["combat"], "loadout": e["loadout"]})
	return out


func _send_roster(slots: Array) -> void:
	var entries: Array = []
	for i in slots:
		var e: Dictionary = _roster[int(i)]
		entries.append({"slot": int(i), "gen": e["gen"], "creature": e["creature"], "scale": e["scale"], "team": e["team"],
			"name": e["name"], "kind": e["kind"], "despawned": e["despawned"], "tags": e["tags"], "combat": e["combat"],
			"loadout": e["loadout"]})
	var w := NetWriter.new(NetProtocol.S_ROSTER)
	w.u32(sim.tick_count)
	NetSnapshot.encode_roster(w, entries)
	var data := w.data()
	for p in _viewers():
		transport.send((p as NetPlayer).peer, NetProtocol.CH_EVENTS, data, true)


func _send_events() -> void:
	var evs := sim.events_since(_ev_cursor)
	if evs.is_empty():
		return
	_ev_cursor = int(evs.back()["seq"])
	var viewers := _viewers()
	var i := 0
	while i < evs.size():
		var chunk := evs.slice(i, i + NetEventCodec.MAX_PER_BATCH)
		i += chunk.size()
		var w := NetWriter.new(NetProtocol.S_EVENTS)
		NetEventCodec.encode_batch(w, chunk, sim.tick_count)
		var data := w.data()
		perf["event_bytes"] = int(perf["event_bytes"]) + data.size() * viewers.size()
		perf["event_batches"] = int(perf["event_batches"]) + 1
		for p in viewers:
			transport.send((p as NetPlayer).peer, NetProtocol.CH_EVENTS, data, true)


func _send_snapshot() -> void:
	var viewers := _viewers()
	if viewers.is_empty():
		return
	var body := NetSnapshot.encode_body(sim, _gens)
	for p in viewers:
		var np: NetPlayer = p
		var w := NetWriter.new(NetProtocol.S_SNAPSHOT)
		w.u16(match_id & 0xFFFF)
		w.u32(sim.tick_count)
		w.u16(maxi(np.last_input_seq, 0))
		w.raw(body)
		transport.send(np.peer, NetProtocol.CH_SNAPSHOT, w.data(), false)
	perf["snapshot_bytes"] = int(perf["snapshot_bytes"]) + (body.size() + 9) * viewers.size()
	perf["snapshots"] = int(perf["snapshots"]) + 1
	perf["last_snapshot_size"] = body.size() + 9


func _on_sim_finished(result: Dictionary) -> void:
	if phase != PHASE_MATCH:
		return
	_send_events()
	last_result = result.duplicate(true)
	last_result["match_id"] = match_id
	last_result["aborted"] = _aborting != ""
	last_result["abort_reason"] = _aborting
	last_result["entry"] = current_entry.duplicate(true)
	var owners := {}
	for p in players.values():
		var np: NetPlayer = p
		if np.fighter >= 0:
			owners[np.fighter] = np.id
	last_result["players"] = owners
	last_result["next_in"] = _results_time()
	phase = PHASE_RESULTS
	phase_until = Time.get_ticks_msec() + _results_time() * 1000
	if playlist and not current_entry.is_empty() and _aborting == "":
		var e := playlist.find_entry(str(current_entry.get("key", "")))
		if not e.is_empty():
			playlist.record_played(e)
			var serr := playlist.save_state()
			if serr != OK:
				Log.w("net", "could not save playlist state: %s" % error_string(serr))
	for v in _viewers():
		_send_match_end_to(v)
	_lobby_dirty = true
	Log.i("net", "match %d finished: winner team %d%s" % [match_id, int(result.get("winner_team", -2)),
		(" (aborted: %s)" % _aborting) if _aborting != "" else ""])
	match_finished.emit(last_result)


## Listen host: its MatchScene (and with it the simulation) was removed by something other than
## Net (a menu changed scenes). End the match for everyone with an aborted result instead of
## touching a freed simulation; the session continues in the lobby.
func _lost_match_scene() -> void:
	Log.w("net", "match %d: the host's match scene was removed; ending the match" % match_id)
	sim = null
	scene = null
	_sim_id = 0
	set_frozen(false)
	if phase != PHASE_MATCH:
		return
	_aborting = "the host left the match"
	last_result = {"match_id": match_id, "winner_team": -1, "aborted": true, "abort_reason": _aborting,
		"entry": current_entry.duplicate(true), "players": {}, "next_in": _results_time(), "fighters": []}
	phase = PHASE_RESULTS
	phase_until = Time.get_ticks_msec() + _results_time() * 1000
	for v in _viewers():
		_send_match_end_to(v)
	_lobby_dirty = true
	notice("The host left the match.")
	match_finished.emit(last_result)


func _send_match_end_to(p: NetPlayer) -> void:
	var w := NetWriter.new(NetProtocol.S_MATCH_END)
	w.blob(var_to_bytes(last_result), true)
	transport.send(p.peer, NetProtocol.CH_EVENTS, w.data(), true)


## Ends the running match immediately (admin `next`, everyone left). No winner.
func end_match_now(reason: String) -> void:
	if phase != PHASE_MATCH or sim == null:
		return
	_aborting = reason
	var res := sim.mode.build_result() if sim.mode else {}
	res["winner_team"] = -1
	sim.finish(res)
	if phase == PHASE_MATCH:
		_on_sim_finished(res)


## Admin `next`: lobby -> start now; match -> end now; results -> continue now.
func skip(reason := "admin") -> String:
	match phase:
		PHASE_LOBBY:
			if dedicated:
				phase_until = 0
				return "starting the next match now"
			return host_start()
		PHASE_MATCH:
			end_match_now(reason)
			return "match ended"
		PHASE_RESULTS:
			phase_until = 0
			return "continuing"
	return "nothing to skip (server idle)"


func _finish_results() -> void:
	_teardown_match()
	for p in players.values():
		var np: NetPlayer = p
		np.fighter = -1
		np.input = null
		np.ready = false
		np.vote = -1
	phase = PHASE_LOBBY
	vote = {}
	phase_until = 0
	_lobby_dirty = true
	returned_to_lobby.emit()
	if dedicated and _connected_count() == 0 and str(cfg["empty_behavior"]) == "idle":
		_enter_idle()


func _teardown_match() -> void:
	set_frozen(false)
	_results_s = -1
	_bot_maker = Callable()
	if sim != null and is_instance_valid(sim):
		if sim.finished.is_connected(_on_sim_finished):
			sim.finished.disconnect(_on_sim_finished)
		if dedicated:
			sim.queue_free()
	if scene != null and is_instance_valid(scene):
		if App.current_scene == scene:
			App.set_scene(null)
		else:
			scene.queue_free()
	sim = null
	scene = null
	_sim_id = 0
	match_info = {}
	current_entry = {}


# =====================================================================================
# Housekeeping, lobby state, status
# =====================================================================================

func _housekeeping() -> void:
	var now := Time.get_ticks_msec()
	for peer in _pending.keys():
		if now - int(_pending[peer]["since"]) > HANDSHAKE_MS:
			_reject(int(peer), NetProtocol.R_HANDSHAKE_TIMEOUT, "handshake timed out")
	var grace_ms := int(cfg["rejoin_grace"]) * 1000
	var timeout_ms := int(cfg["timeout"]) * 1000
	for p in players.values():
		var np: NetPlayer = p
		if not np.connected and np.peer != -1 and now - np.disconnected_ms > grace_ms:
			_remove_player(np, "did not return within %d s" % int(cfg["rejoin_grace"]))
		elif np.connected and np.peer > 0 and np.last_rx_ms > 0 and now - np.last_rx_ms > timeout_ms:
			# application-level timeout (clients send at least a ping every second)
			var dead := np.peer
			Log.i("net", "player %d '%s' timed out (no data for %d s)" % [np.id, np.name, int(cfg["timeout"])])
			transport.disconnect_peer(dead, NetProtocol.R_TIMEOUT, false)
			_on_peer_disconnected(dead, 0)
	if now - _rtt_ms > 500:
		_rtt_ms = now
		for p in players.values():
			var np2: NetPlayer = p
			if np2.peer > 0:
				np2.rtt_ms = transport.rtt_ms(np2.peer)
				np2.loss = transport.loss(np2.peer)
	var countdown := phase_until > 0 and (phase == PHASE_LOBBY or phase == PHASE_RESULTS)
	if (_lobby_dirty and now - _lobby_sent_ms >= LOBBY_MIN_INTERVAL_MS) or (countdown and now - _lobby_sent_ms >= COUNTDOWN_RESEND_MS):
		_lobby_dirty = false
		_lobby_sent_ms = now
		var data := _lobby_packet()
		_broadcast_control(data)
		lobby_changed.emit()
	if lan and now - _beacon_ms >= BEACON_MS:
		_beacon_ms = now
		lan.announce(beacon_info())
	_check_mode_picks(now)
	if now - int(perf["window_start_ms"]) >= 1000:
		var span := float(now - int(perf["window_start_ms"])) / 1000.0
		perf["out_bps"] = float(transport.wire_out - int(perf["window_out"])) / span
		perf["in_bps"] = float(transport.wire_in - int(perf["window_in"])) / span
		perf["window_out"] = transport.wire_out
		perf["window_in"] = transport.wire_in
		perf["window_start_ms"] = now
		var wt := int(perf["window_ticks"])
		perf["tick_ms_avg"] = float(perf["window_sim_us"]) / 1000.0 / float(wt) if wt > 0 else 0.0
		perf["tick_ms_max"] = float(perf["window_sim_max"]) / 1000.0
		if wt > 0:
			perf["phys_ms_total"] = float(perf["phys_ms_total"]) + float(perf.get("phys_max_ms", 0.0))
			perf["phys_samples"] = int(perf["phys_samples"]) + 1
		perf["window_ticks"] = 0
		perf["window_sim_us"] = 0
		perf["window_sim_max"] = 0
	if dedicated and now - _stats_ms >= int(cfg["stats_interval"]) * 1000:
		_stats_ms = now
		Log.i("stats", stats_line())


func _send_lobby_to(p: NetPlayer) -> void:
	if p.peer > 0:
		transport.send(p.peer, NetProtocol.CH_CONTROL, _lobby_packet(), true)


func _lobby_packet() -> PackedByteArray:
	var w := NetWriter.new(NetProtocol.S_LOBBY)
	w.blob(var_to_bytes(lobby_state()), true)
	return w.data()


func lobby_state() -> Dictionary:
	var now := Time.get_ticks_msec()
	var plist: Array = []
	var sorted_players: Array = players.values()
	sorted_players.sort_custom(func(a, b): return (a.slot if a.slot >= 0 else 99) < (b.slot if b.slot >= 0 else 99) or ((a.slot if a.slot >= 0 else 99) == (b.slot if b.slot >= 0 else 99) and a.id < b.id))
	for p in sorted_players:
		plist.append((p as NetPlayer).to_public())
	var rules := NetPlaylist.resolve_rules(str(settings["rules"]), settings["rules_override"])
	var ad := Content.arena(str(settings["arena"]))
	var vote_pub := {}
	if not vote.is_empty():
		var cands: Array = []
		var tally: Array[int] = []
		for c in vote.get("candidates", []):
			cands.append(playlist.describe_entry(c) if playlist else {})
			tally.append(0)
		for p2 in players.values():
			var np: NetPlayer = p2
			if np.vote >= 0 and np.vote < tally.size():
				tally[np.vote] += 1
		vote_pub = {"open": bool(vote.get("open", false)), "candidates": cands, "tally": tally}
	var st := {"phase": phase, "countdown": maxf(0.0, float(phase_until - now) / 1000.0) if phase_until > 0 else -1.0,
		"name": cfg["name"], "motd": cfg["motd"], "dedicated": dedicated, "max_players": cfg["max_players"],
		"max_spectators": cfg["max_spectators"], "password": str(cfg["password"]) != "", "host_id": local_player_id,
		"players": plist, "vote": vote_pub, "match_id": match_id,
		"settings": {"rules": settings["rules"], "rules_name": str(rules.get("name", settings["rules"])),
			"arena": settings["arena"], "arena_name": ad.display_name if ad else str(settings["arena"]),
			"mode": str(rules.get("mode", "standard")), "bots": settings["bots"], "bot_difficulty": settings["bot_difficulty"],
			"rules_override": settings["rules_override"], "bot_policy": settings["bot_policy"],
			"player_assist": bool(cfg.get("player_assist", true)), "party_relay": bool(cfg.get("party_relay", true))},
		"entry": current_entry, "game_version": NetProtocol.game_version()}
	if playlist:
		var errs: Array = playlist.errors.slice(0, 8)
		st["playlist"] = {"id": playlist.id, "name": playlist.display_name, "valid": playlist.valid_entries().size(),
			"invalid": playlist.entries.size() - playlist.valid_entries().size(), "errors": errs}
	if not dedicated:
		st["options"] = {"creatures": Content.playable_creatures(), "rules": Content.ids("rules"), "arenas": Content.ids("arenas"),
			"bot_difficulties": BotBrain.PROFILES.keys(), "bot_policies": _policy_options()}
	else:
		st["options"] = {"creatures": Content.playable_creatures()}
	if not last_result.is_empty() and phase == PHASE_RESULTS:
		st["last_result"] = {"winner_team": last_result.get("winner_team", -2), "aborted": last_result.get("aborted", false)}
	if not party.is_empty():
		st["party"] = _party_public()
	return st


func beacon_info() -> Dictionary:
	return {"port": int(cfg["port"]), "name": str(cfg["name"]), "players": _count_players(false),
		"max_players": int(cfg["max_players"]), "spectators": _count_spectators(), "max_spectators": int(cfg["max_spectators"]),
		"password": str(cfg["password"]) != "", "dedicated": dedicated, "in_match": phase == PHASE_MATCH,
		"rules": str(current_entry.get("rules", settings["rules"])), "arena": str(current_entry.get("arena", settings["arena"])),
		"phase": phase}


func status() -> Dictionary:
	var ticks := maxi(1, int(perf["ticks"]))
	var net_ticks := maxi(1, int(perf.get("net_ticks", 0)))
	var snaps := maxi(1, int(perf["snapshots"]))
	return {"name": cfg.get("name", ""), "phase": phase, "uptime_s": float(Time.get_ticks_msec() - started_ms) / 1000.0,
		"players": _count_players(false), "reserved": _count_players(true) - _count_players(false),
		"spectators": _count_spectators(), "max_players": cfg.get("max_players", 0), "match_id": match_id,
		"entry": current_entry.get("key", ""), "fighters": sim.fighters.size() if sim else 0,
		"tick": sim.tick_count if sim else 0,
		"sim_ms_avg": float(perf["sim_us_total"]) / 1000.0 / float(ticks),
		"sim_ms_max": float(perf["sim_us_max"]) / 1000.0,
		"tick_ms_avg_1s": perf["tick_ms_avg"], "tick_ms_max_1s": perf["tick_ms_max"],
		"physics_frame_max_ms": float(perf.get("phys_max_ms", 0.0)),
		"physics_frame_max_ms_avg": float(perf["phys_ms_total"]) / maxf(1.0, float(perf["phys_samples"])),
		"net_ms_avg": float(perf["net_us_total"]) / 1000.0 / float(net_ticks),
		"net_ms_max": float(perf["net_us_max"]) / 1000.0,
		"snapshot_bytes_avg": float(perf["snapshot_bytes"]) / float(snaps),
		"last_snapshot_size": perf.get("last_snapshot_size", 0),
		"out_kbps": float(perf["out_bps"]) / 1024.0, "in_kbps": float(perf["in_bps"]) / 1024.0,
		"wire_out_total": transport.wire_out, "wire_in_total": transport.wire_in,
		"mem_static_mb": OS.get_static_memory_usage() / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"playlist": playlist.id if playlist else "", "matches_played": playlist.matches_played if playlist else match_id,
		"content_hash": Content.content_hash().substr(0, 12), "packages": _package_labels()}


func _package_labels() -> Array:
	var out: Array = []
	for p in Content.package_list():
		out.append("%s@%s" % [p["id"], p["version"]])
	return out


func stats_line() -> String:
	var s := status()
	return "phase=%s players=%d spect=%d match=%d fighters=%d sim_ms(1s avg/max)=%.2f/%.2f phys_frame_max_ms=%.2f out=%.1fKB/s in=%.1fKB/s mem=%.1fMB objects=%d nodes=%d orphans=%d" % [
		s["phase"], s["players"], s["spectators"], s["match_id"], s["fighters"], float(s["tick_ms_avg_1s"]), float(s["tick_ms_max_1s"]),
		float(s["physics_frame_max_ms"]), float(s["out_kbps"]), float(s["in_kbps"]), float(s["mem_static_mb"]), s["objects"], s["nodes"], s["orphans"]]


func players_public() -> Array:
	var out: Array = []
	for p in players.values():
		var np: NetPlayer = p
		var d := np.to_public()
		d["address"] = np.address
		d["loss"] = np.loss
		d["violations"] = snappedf(np.violations, 0.1)
		out.append(d)
	return out
