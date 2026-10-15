class_name NetClient
extends Node
## Client side of a session: connects (optionally through a NetConditioner), answers the
## server's challenge (protocol, build, content hash + package list, password proof, name,
## rejoin token), mirrors the lobby, decodes the match stream (MATCH_START / EVENTS / MATCH_END on
## the reliable events channel, snapshots on the unreliable channel) into a NetReplica, and
## samples + sends local input at 60 Hz with redundancy. It never simulates and never decides
## outcomes. Failures are reported as UI-ready dictionaries (NetProtocol.describe).

signal state_changed(state: int)
signal admitted(welcome: Dictionary)
signal failed(reason: Dictionary)
signal disconnected(reason: Dictionary)
signal lobby_updated(lobby: Dictionary)
signal chat_received(from_id: int, from_name: String, text: String)
signal notice_received(text: String)
signal match_starting(info: Dictionary)
signal match_ready(scene: Node)
signal match_ended(result: Dictionary)
signal returned_to_lobby()
signal app_message(from_id: int, type: String, payload: Dictionary)

enum State { IDLE, CONNECTING, HANDSHAKE, LOBBY, MATCH, CLOSED }

const REDUNDANCY := 4
const HANDSHAKE_LIMIT_MS := 8000

var transport := NetTransport.new()
var conditioner: NetConditioner = null
var state := State.IDLE
var address := ""
var port := 0
var opts := {}
var player_id := 0
var token := PackedByteArray()
var server_name := ""
var server_dedicated := false
var server_tick_rate := 120
var motd := ""
var joined_as_spectator := false
var server_packages: Array = []     ## the server's package list from the challenge
var arena_imported := ""            ## id of the last arena received as a package from the host
var content_check := {}             ## NetProtocol.content_verdict() result of the last challenge
var lobby := {}
var match_info := {}
var my_fighter := -1
var replica := NetReplica.new()
var scene: NetMatchScene = null
var present := true                 ## create a NetMatchScene for matches (false: headless tools)
var install_scene := true           ## hand the scene to App.set_scene (false: caller places it)
var input_sampler: Callable         ## func(fi: FighterInput) -> void; default samples Controls
var input_enabled := true
var last_result := {}
var welcome := {}
var _fail := {}
var _connect_ms := 0
var _handshake_ms := 0
var _input := FighterInput.new()
var _hist: Array[FighterInput] = []
var _seq := 0
var _phys := 0
var _last_tick := 0
var _closed_emitted := false
var _ping_ms := 0
var _last_rx_ms := 0
## stats
var _win_ms := 0
var _win_snaps := 0
var _win_in := 0
var _win_out := 0
var _stats := {"snapshot_rate": 0.0, "in_kbps": 0.0, "out_kbps": 0.0}
var inputs_sent := 0
var malformed := 0


func _ready() -> void:
	name = "NetClient"
	process_physics_priority = -90


## options: {name, password, spectator, creature, token(PackedByteArray), timeout_s,
##           conditioner(NetConditioner), test_protocol, test_game_version}
func connect_to_server(addr: String, port_: int, options: Dictionary = {}) -> Error:
	address = addr.strip_edges()
	port = port_
	opts = options
	replica.interp_mode = str(Settings.get_value("network.interp"))
	transport.timeout_ms = int(options.get("timeout_s", Settings.get_value("network.timeout"))) * 1000
	token = options.get("token", PackedByteArray())
	var ip := address
	if not ip.is_valid_ip_address():
		ip = IP.resolve_hostname(address, IP.TYPE_IPV4)
		if ip == "":
			_fail_now(NetProtocol.describe(NetProtocol.R_CONNECT_FAILED, ["Could not resolve '%s'." % address]))
			return ERR_CANT_RESOLVE
	var target_ip := ip
	var target_port := port
	conditioner = options.get("conditioner", null)
	if conditioner:
		var cerr := conditioner.start(ip, port, 0, "127.0.0.1")
		if cerr != OK:
			_fail_now(NetProtocol.describe(NetProtocol.R_LOCAL_ERROR, ["Network conditioner could not start: %s" % error_string(cerr)]))
			return cerr
		target_ip = "127.0.0.1"
		target_port = conditioner.listen_port
		Log.w("net", "client network conditioner active: %s" % conditioner.describe())
	var err := transport.connect_to(target_ip, target_port)
	if err != OK:
		_fail_now(NetProtocol.describe(NetProtocol.R_LOCAL_ERROR, [transport.last_error]))
		return err
	_set_state(State.CONNECTING)
	_connect_ms = Time.get_ticks_msec()
	_win_ms = _connect_ms
	Log.i("net", "connecting to %s:%d%s" % [address, port, (" via conditioner :%d" % target_port) if conditioner else ""])
	return OK


func _set_state(s: int) -> void:
	if state != s:
		state = s
		state_changed.emit(s)


func is_connected_to_server() -> bool:
	return state == State.LOBBY or state == State.MATCH


## Graceful leave: tells the server (no rejoin reservation) and closes. `reason` overrides the
## reported reason (e.g. a local content problem that forced the leave).
func leave(reason: Dictionary = {}) -> void:
	if transport.is_open() and is_connected_to_server():
		var w := NetWriter.new(NetProtocol.C_LEAVE)
		transport.send(1, NetProtocol.CH_CONTROL, w.data(), true)
		transport.disconnect_peer(1, NetProtocol.R_LEFT, true)
		transport.drain(250)
	if reason.is_empty():
		_finish(NetProtocol.describe(NetProtocol.R_LEFT), false)
	else:
		_finish(reason, true)


## Abrupt drop (tests: simulates a crash / pulled cable; the server keeps the slot for rejoin).
func drop() -> void:
	if transport.is_open():
		transport.disconnect_peer(1, NetProtocol.R_TIMEOUT, false)
		transport.flush()
	_finish(NetProtocol.describe(NetProtocol.R_TIMEOUT, ["Connection dropped locally."]), false)


func _fail_now(reason: Dictionary) -> void:
	_fail = reason
	_finish(reason, true)


func _finish(reason: Dictionary, as_failure: bool) -> void:
	if _closed_emitted:
		return
	_closed_emitted = true
	var was := state
	_end_match_presentation()
	# a content refusal on our side tells the server why we never said hello (its log shows it)
	transport.close(NetProtocol.R_CONTENT if int(reason.get("code", 0)) == NetProtocol.R_CONTENT else NetProtocol.R_LEFT)
	if conditioner:
		conditioner.stop()
	_set_state(State.CLOSED)
	Log.i("net", "client closed: %s - %s" % [NetProtocol.reason_name(int(reason.get("code", 0))), str(reason.get("message", ""))])
	if as_failure or was == State.CONNECTING or was == State.HANDSHAKE or was == State.IDLE:
		failed.emit(reason)
	else:
		disconnected.emit(reason)


func _exit_tree() -> void:
	if transport.is_open():
		transport.close()
	if conditioner:
		conditioner.stop()


# =====================================================================================
# Loop
# =====================================================================================

func _physics_process(_dt: float) -> void:
	if not transport.is_open():
		return
	for ev in transport.poll():
		match int(ev["type"]):
			NetTransport.EV_CONNECT:
				_set_state(State.HANDSHAKE)
				_handshake_ms = Time.get_ticks_msec()
			NetTransport.EV_DISCONNECT:
				_on_disconnect(int(ev.get("code", 0)))
				return
			NetTransport.EV_RECEIVE:
				_on_packet(int(ev["channel"]), ev["data"])
				if not transport.is_open():
					return
	var now := Time.get_ticks_msec()
	if is_connected_to_server():
		# heartbeat: the server answers every ping, so both sides always hear each other at
		# least once per second and can apply the configured timeout precisely
		if now - _ping_ms >= 1000:
			_ping_ms = now
			var pw := NetWriter.new(NetProtocol.C_PING)
			pw.u32(now)
			transport.send(1, NetProtocol.CH_CONTROL, pw.data(), false)
		if _last_rx_ms > 0 and now - _last_rx_ms > transport.timeout_ms:
			_finish(NetProtocol.describe(NetProtocol.R_TIMEOUT, ["Nothing received from the server for %d s." % roundi(transport.timeout_ms / 1000.0)]), false)
			return
	if state == State.CONNECTING and now - _connect_ms > transport.timeout_ms + 1500:
		_fail_now(NetProtocol.describe(NetProtocol.R_CONNECT_FAILED, ["No answer from %s:%d within %d s." % [address, port, roundi(transport.timeout_ms / 1000.0)]]))
		return
	if state == State.HANDSHAKE and now - _handshake_ms > HANDSHAKE_LIMIT_MS:
		_fail_now(NetProtocol.describe(NetProtocol.R_HANDSHAKE_TIMEOUT))
		return
	if state == State.MATCH and my_fighter >= 0:
		_sample_and_send()
	transport.flush()


func _process(dt: float) -> void:
	var now_ms := Time.get_ticks_msec()
	if state == State.MATCH:
		replica.advance(dt, now_ms / 1000.0)
	if now_ms - _win_ms >= 1000:
		var span := float(now_ms - _win_ms) / 1000.0
		_stats["snapshot_rate"] = float(_win_snaps) / span
		_stats["in_kbps"] = float(transport.wire_in - _win_in) / span / 1024.0
		_stats["out_kbps"] = float(transport.wire_out - _win_out) / span / 1024.0
		if transport.has_peer(1):
			_stats["rtt_ms"] = transport.rtt_ms(1)
			_stats["rtt_var_ms"] = transport.rtt_var_ms(1)
			_stats["loss"] = transport.loss(1)
			_stats["rtt_max_ms"] = maxf(float(_stats.get("rtt_max_ms", 0.0)), transport.rtt_ms(1))
		_win_snaps = 0
		_win_in = transport.wire_in
		_win_out = transport.wire_out
		_win_ms = now_ms


func _on_disconnect(code: int) -> void:
	var reason := _fail
	if reason.is_empty():
		if state == State.CONNECTING:
			reason = NetProtocol.describe(NetProtocol.R_CONNECT_FAILED, ["No answer from %s:%d." % [address, port]])
		elif code != 0 and code != NetProtocol.R_TIMEOUT:
			reason = NetProtocol.describe(code)
		else:
			reason = NetProtocol.describe(NetProtocol.R_TIMEOUT)
	_finish(reason, state == State.CONNECTING or state == State.HANDSHAKE)


# =====================================================================================
# Receiving
# =====================================================================================

func _on_packet(channel: int, data: PackedByteArray) -> void:
	_last_rx_ms = Time.get_ticks_msec()
	if data.is_empty() or data.size() > NetProtocol.MAX_SERVER_PACKET:
		malformed += 1
		return
	var id := int(data[0])
	var r := NetReader.new(data, 1)
	match id:
		NetProtocol.S_CHALLENGE:
			_on_challenge(r)
		NetProtocol.S_WELCOME:
			_on_welcome(r)
		NetProtocol.S_REJECT:
			var code := r.u8()
			var msg := r.text(400)
			var n := r.count(32)
			var details: Array = []
			for i in n:
				details.append(r.text(200))
			_fail = NetProtocol.describe(code, details, msg if code == NetProtocol.R_KICKED else "")
			_fail["server_message"] = msg
		NetProtocol.S_KICKED:
			var kcode := r.u8()
			var why := r.text(200)
			_fail = NetProtocol.describe(kcode if kcode != 0 else NetProtocol.R_KICKED, [], why)
			_fail["server_message"] = why
		NetProtocol.S_CLOSING:
			var ccode := r.u8()
			var cmsg := r.text(400)
			var restarting := r.u8() == 1
			_fail = NetProtocol.describe(ccode, ["The server is restarting; try again shortly."] if restarting else [], cmsg)
			_fail["restarting"] = restarting
			_fail["server_message"] = cmsg
		NetProtocol.S_LOBBY:
			var blob := r.blob(NetProtocol.MAX_SERVER_PACKET, true)
			var v = bytes_to_var(blob) if r.ok else null
			if typeof(v) == TYPE_DICTIONARY:
				_on_lobby(v)
			else:
				malformed += 1
		NetProtocol.S_CHAT:
			var from := r.u32()
			var fname := r.text(80)
			var text := r.text(800)
			if r.ok:
				chat_received.emit(from, fname, text)
		NetProtocol.S_NOTICE:
			var t := r.text(1000)
			if r.ok:
				notice_received.emit(t)
		NetProtocol.S_MATCH_START:
			var blob2 := r.blob(NetProtocol.MAX_SERVER_PACKET, true)
			var v2 = bytes_to_var(blob2) if r.ok else null
			if typeof(v2) == TYPE_DICTIONARY:
				_on_match_start(v2)
			else:
				malformed += 1
		NetProtocol.S_SNAPSHOT:
			_on_snapshot(r)
		NetProtocol.S_ROSTER:
			if state != State.MATCH:
				return
			var _rtick := r.u32()
			var entries := NetSnapshot.decode_roster(r)
			if not r.ok:
				malformed += 1
				return
			for e in entries:
				replica.apply_roster_entry(e)
			if scene:
				scene.sync_roster()
		NetProtocol.S_EVENTS:
			if state != State.MATCH:
				return
			var evs := NetEventCodec.decode_batch(r)
			if r.ok:
				replica.add_events(evs)
			else:
				malformed += 1
		NetProtocol.S_MATCH_END:
			var blob3 := r.blob(NetProtocol.MAX_SERVER_PACKET, true)
			var v3 = bytes_to_var(blob3) if r.ok else null
			if typeof(v3) == TYPE_DICTIONARY:
				last_result = v3
				if scene:
					scene.show_result(last_result)
				match_ended.emit(last_result)
		NetProtocol.S_APP:
			var from2 := r.u32()
			var atype := r.text(NetProtocol.MAX_APP_TYPE)
			var ablob := r.blob(NetProtocol.MAX_APP_PAYLOAD + 64, true)
			if not r.ok or not NetProtocol.valid_app_type(atype):
				malformed += 1
				return
			var dec := NetProtocol.decode_payload(ablob)
			if bool(dec["ok"]):
				app_message.emit(from2, atype, dec["value"])
			else:
				malformed += 1
		NetProtocol.S_PONG:
			pass
		_:
			malformed += 1


func _on_challenge(r: NetReader) -> void:
	var proto := r.u16()
	var gv := r.text(32)
	var sname := r.text(80)
	var nonce := r.raw(NetProtocol.NONCE_BYTES)
	var flags := r.u8()
	if not r.ok:
		_fail_now(NetProtocol.describe(NetProtocol.R_VIOLATION, ["The server sent an invalid challenge."]))
		return
	server_name = sname
	server_dedicated = flags & 2 != 0
	var my_proto := int(opts.get("test_protocol", NetProtocol.VERSION))
	if proto != my_proto:
		_fail_now(NetProtocol.describe(NetProtocol.R_PROTOCOL, ["Server: game %s, network protocol %d" % [gv, proto],
			"You: game %s, network protocol %d" % [NetProtocol.game_version(), my_proto]]))
		return
	# a different build is "update the game", not a content problem: say so before comparing content
	var my_gv := str(opts.get("test_game_version", NetProtocol.game_version()))
	if gv != my_gv:
		_fail_now(NetProtocol.describe(NetProtocol.R_GAME_VERSION, ["Server game version: %s" % gv, "Your game version: %s" % my_gv]))
		return
	r.u8()  # players (shown by LAN beacons; the lobby state follows)
	r.u8()  # max players
	var server_hash := r.text(80)
	server_packages = NetProtocol.read_packages(r)
	if not r.ok:
		_fail_now(NetProtocol.describe(NetProtocol.R_VIOLATION, ["The server sent an invalid challenge (%s)." % r.error]))
		return
	if NetProtocol.too_many_packages(Content.package_list()):
		_fail_now(NetProtocol.describe(NetProtocol.R_CONTENT, ["You have %d gameplay mods enabled; online sessions support up to %d. Disable some in the Mods screen." % [
			NetProtocol.gameplay_packages(Content.package_list()).size() - 1, NetProtocol.MAX_PACKAGES - 1]]))
		return
	# content check on our side first (Mods.compare wording for the join error), MOD-05
	content_check = NetProtocol.content_verdict(Mods.compare(server_packages), server_packages, server_hash == Content.content_hash())
	if not bool(content_check["ok"]):
		var reason := NetProtocol.describe(NetProtocol.R_CONTENT, content_check["details"])
		reason["mods"] = {"missing": content_check["missing"], "extra": content_check["extra"],
			"mismatched": content_check["mismatched"], "modified": content_check["hash_only"]}
		_fail_now(reason)
		return
	var w := NetWriter.new(NetProtocol.C_HELLO)
	w.u16(my_proto)
	w.text(my_gv, 32)
	w.text(Content.content_hash(), 80)
	NetProtocol.write_packages(w, opts.get("test_packages", Content.package_list()))
	w.text(NetProtocol.clean_name(str(opts.get("name", Settings.get_value("network.player_name")))), 80)
	w.blob(NetProtocol.password_proof(nonce, str(opts.get("password", ""))))
	w.blob(token)
	w.u8(1 if bool(opts.get("spectator", false)) else 0)
	w.text(str(opts.get("creature", "")), 64)
	w.u8(NetProtocol.assist_to_byte(float(opts.get("assist", NetProtocol.local_assist()))))
	transport.send(1, NetProtocol.CH_CONTROL, w.data(), true)


func _on_welcome(r: NetReader) -> void:
	var pid := r.u32()
	var tok := r.blob(64)
	var flags := r.u8()
	var sname := r.text(80)
	var tick_rate := r.u16()
	var snap_rate := r.u8()
	var m := r.text(400)
	if not r.ok:
		_fail_now(NetProtocol.describe(NetProtocol.R_VIOLATION, ["The server sent an invalid welcome."]))
		return
	player_id = pid
	token = tok
	server_name = sname
	server_tick_rate = tick_rate
	motd = m
	joined_as_spectator = flags & 2 != 0
	welcome = {"player_id": pid, "rejoined": flags & 1 != 0, "spectator": joined_as_spectator,
		"spectator_because_full": flags & 4 != 0, "dedicated": flags & 8 != 0, "server_name": sname,
		"tick_rate": tick_rate, "snapshot_rate": snap_rate, "motd": m}
	# MATCH_START travels on another channel and may overtake this message under loss
	if state != State.MATCH:
		_set_state(State.LOBBY)
	Log.i("net", "joined '%s' as player %d%s" % [sname, pid, " (rejoined)" if flags & 1 != 0 else ""])
	admitted.emit(welcome)


func _on_lobby(d: Dictionary) -> void:
	lobby = d
	lobby_updated.emit(lobby)
	var ph := str(d.get("phase", ""))
	# a lobby state from before this match (delayed on the control channel) must not end it
	var fresh := int(d.get("match_id", 0)) >= int(match_info.get("match_id", 0))
	if state == State.MATCH and (ph == "lobby" or ph == "idle") and fresh:
		_end_match_presentation()
		_set_state(State.LOBBY)
		returned_to_lobby.emit()


func _on_match_start(info: Dictionary) -> void:
	if not (info.get("fighters") is Array) or not (info.get("arena") is Dictionary) or not (info.get("rules") is Dictionary):
		malformed += 1
		return
	# the full rules dictionary is checked again here with the rules editor's validator
	var bad_rules := NetProtocol.rules_problem(info["rules"])
	if bad_rules != "":
		Log.e("net", "the server's rules failed validation: %s" % bad_rules)
		leave(NetProtocol.describe(NetProtocol.R_CONTENT, ["The server's rules failed validation here: %s" % bad_rules]))
		return
	var bad_arena := _prepare_arena(info)
	if bad_arena != "":
		Log.e("net", "arena problem: %s" % bad_arena)
		leave(NetProtocol.describe(NetProtocol.R_CONTENT, [bad_arena]))
		return
	_end_match_presentation()
	match_info = info
	my_fighter = int(info.get("you", -1))
	replica.reset(info)
	_hist.clear()
	_input = FighterInput.new()
	_set_state(State.MATCH)
	match_starting.emit(info)
	if present:
		var s := NetMatchScene.new()
		s.stats_provider = stats
		if install_scene and get_node_or_null("/root/App") != null:
			App.clear_screens()
			App.set_scene(s)
		else:
			add_child(s)
		var err := s.start(info, replica, self)
		if err != "":
			Log.e("net", "cannot present match: %s" % err)
			scene = s
			leave(NetProtocol.describe(NetProtocol.R_CONTENT, [err]))
			return
		scene = s
		match_ready.emit(s)


## The match's arena, checked before anything is built: a player-made layout arrives as an
## ArenaPackage (size-capped, imported into a sandbox folder - not the player's own library - with
## every package check), core and mod arenas come from local content; either way the layout's
## content hash must equal the host's. Puts the ArenaDef into info["_arena_def"]. Returns "" or why.
func _prepare_arena(info: Dictionary) -> String:
	var aid := str(info.get("arena_id", ""))
	var want := str(info.get("arena_hash", ""))
	var def: ArenaDef = null
	var pkg = info.get("arena_package", null)
	if typeof(pkg) == TYPE_PACKED_BYTE_ARRAY and (pkg as PackedByteArray).size() > 0:
		var bytes: PackedByteArray = pkg
		if bytes.size() > NetProtocol.MAX_ARENA_PACKAGE:
			return "The host's arena package is too large (%d KB)." % int(bytes.size() / 1024.0)
		var sandbox := Paths.dir("downloads").path_join("net_arenas")
		# only the current match's layout lives here: earlier imports never pile up or get reused
		DirAccess.make_dir_recursive_absolute(sandbox)
		for old in DirAccess.get_files_at(sandbox):
			DirAccess.remove_absolute(sandbox.path_join(old))
		var res := ArenaPackage.import_bytes(bytes, sandbox)
		if not bool(res.get("ok", false)):
			return "The host's arena '%s' was refused: %s" % [aid, "; ".join(PackedStringArray(res.get("errors", [])))]
		var listed := false
		for d in res.get("arenas", []):
			listed = listed or str((d as Dictionary).get("id", "")) == aid
		if not listed:
			return "The host's arena package does not contain arena '%s'." % aid
		var lr := ArenaLibrary.load_layout(ArenaLibrary.path_for(aid, sandbox))
		if not bool(lr.get("ok", false)):
			return "The host's arena '%s' could not be loaded after import." % aid
		def = ArenaDef.from_dict(lr["data"], "user")
		if def.id != aid:
			return "The host's arena package does not contain arena '%s'." % aid
		arena_imported = aid
	else:
		def = Content.arena(aid)
	if def == null:
		# not installed here (an older host sent no package): use the layout from MATCH_START
		def = ArenaDef.from_dict(info.get("arena", {}), "net")
	if not def.errors.is_empty():
		return "The host's arena '%s' is invalid: %s" % [aid, "; ".join(def.errors)]
	if want != "" and def.content_hash() != want:
		return "Your copy of arena '%s' differs from the host's (content hash). Update or reinstall it." % aid
	info["_arena_def"] = def
	return ""


func _end_match_presentation() -> void:
	if scene != null and is_instance_valid(scene):
		if get_node_or_null("/root/App") != null and App.current_scene == scene:
			App.set_scene(null)
		else:
			scene.queue_free()
	scene = null
	my_fighter = -1


func _on_snapshot(r: NetReader) -> void:
	if state != State.MATCH:
		return
	var mid := r.u16()
	var tick := r.u32()
	var _ack := r.u16()
	if mid != (int(match_info.get("match_id", 0)) & 0xFFFF):
		return
	var body := NetSnapshot.decode_body(r)
	if not r.ok or body.is_empty():
		malformed += 1
		return
	_last_tick = tick
	_win_snaps += 1
	replica.add_snapshot(tick, body, Time.get_ticks_msec() / 1000.0)


# =====================================================================================
# Sending
# =====================================================================================

func _sample_and_send() -> void:
	if input_enabled and input_sampler.is_valid():
		input_sampler.call(_input)
	elif input_enabled and scene != null:
		Controls.fill(_input, scene.input_basis())
	else:
		_input.move = Vector3.ZERO
		_input.held = 0
	_phys += 1
	var every := maxi(1, roundi(float(Engine.physics_ticks_per_second) / float(NetProtocol.INPUT_HZ)))
	if _phys % every != 0:
		return
	_seq = (_seq + 1) & 0xFFFF
	_hist.push_front(_input.duplicate_input())
	while _hist.size() > REDUNDANCY:
		_hist.pop_back()
	var w := NetWriter.new(NetProtocol.C_INPUT)
	w.u16(_seq)
	w.u32(_last_tick)
	w.u8(_hist.size())
	for fi in _hist:
		NetSnapshot.write_input(w, fi)
	transport.send(1, NetProtocol.CH_INPUT, w.data(), false)
	inputs_sent += 1


func send_lobby(kind: int, value) -> void:
	if not is_connected_to_server():
		return
	var w := NetWriter.new(NetProtocol.C_LOBBY)
	w.u8(kind)
	match kind:
		NetProtocol.LQ_READY, NetProtocol.LQ_SPECTATE:
			w.boolean(bool(value))
		NetProtocol.LQ_CREATURE:
			w.text(str(value), 64)
		NetProtocol.LQ_TEAM:
			w.i8(int(value))
		NetProtocol.LQ_ASSIST:
			w.u8(NetProtocol.assist_to_byte(float(value)))
	transport.send(1, NetProtocol.CH_CONTROL, w.data(), true)


func send_chat(text: String) -> void:
	if not is_connected_to_server():
		return
	var w := NetWriter.new(NetProtocol.C_CHAT)
	w.text(NetProtocol.clean_text(text, NetProtocol.MAX_CHAT), 600)
	transport.send(1, NetProtocol.CH_CONTROL, w.data(), true)


func send_vote(candidate: int) -> void:
	if not is_connected_to_server():
		return
	var w := NetWriter.new(NetProtocol.C_VOTE)
	w.i8(candidate)
	transport.send(1, NetProtocol.CH_CONTROL, w.data(), true)


func send_app(type: String, payload: Dictionary) -> bool:
	if not is_connected_to_server() or not NetProtocol.valid_app_type(type):
		return false
	var bytes := NetProtocol.encode_payload(payload)
	if bytes.size() > NetProtocol.MAX_APP_PAYLOAD:
		return false
	var w := NetWriter.new(NetProtocol.C_APP)
	w.text(type, NetProtocol.MAX_APP_TYPE)
	w.blob(bytes)
	return transport.send(1, NetProtocol.CH_CONTROL, w.data(), true) == OK


## Raw send for tests that probe server validation (malformed / forged packets).
func send_raw(channel: int, data: PackedByteArray, reliable: bool) -> Error:
	return transport.send(1, channel, data, reliable)


func stats() -> Dictionary:
	var s := replica.stats()
	var live := transport.has_peer(1)
	s["rtt_ms"] = transport.rtt_ms(1) if live else float(_stats.get("rtt_ms", 0.0))
	s["rtt_var_ms"] = transport.rtt_var_ms(1) if live else float(_stats.get("rtt_var_ms", 0.0))
	s["rtt_max_ms"] = float(_stats.get("rtt_max_ms", 0.0))
	s["loss"] = transport.loss(1) if live else float(_stats.get("loss", 0.0))
	s["snapshot_rate"] = _stats["snapshot_rate"]
	s["in_kbps"] = _stats["in_kbps"]
	s["out_kbps"] = _stats["out_kbps"]
	s["wire_in_total"] = transport.wire_in
	s["wire_out_total"] = transport.wire_out
	s["payload_in_total"] = transport.bytes_in
	s["payload_out_total"] = transport.bytes_out
	s["in_by_channel"] = Array(transport.in_by_channel)
	s["inputs_sent"] = inputs_sent
	s["malformed"] = malformed
	s["state"] = State.keys()[state]
	if conditioner:
		s["conditioner"] = conditioner.stats()
	return s
