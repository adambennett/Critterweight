class_name NetAdminTcp
extends RefCounted
## Optional remote-admin endpoint for the dedicated server: a line-based TCP protocol bound to
## 127.0.0.1 ONLY (use an SSH tunnel for real remote access). The first line must be
## `AUTH <token>` (constant-time comparison; config admin.token, >= 16 characters). After that
## each line is one NetAdminConsole command; every response ends with a line containing ".".
## Limits: 2 connections, 512-byte lines, 120 s idle timeout; 5 failed logins within a minute
## lock the endpoint for 60 s. Nothing but the console's command whitelist can be reached.

const MAX_CONNS := 2
const MAX_LINE := 512
const IDLE_MS := 120000
const LOCKOUT_MS := 60000

var port := 0
var _token := PackedByteArray()
var _server: TCPServer = null
var _conns: Array = []          ## [{peer: StreamPeerTCP, buf: PackedByteArray, authed: bool, last: int}]
var _fails: Array[int] = []
var _locked_until := 0


func start(port_: int, token: String) -> Error:
	if token.length() < 16:
		return ERR_INVALID_PARAMETER
	_token = token.sha256_buffer()
	_server = TCPServer.new()
	var err := _server.listen(port_, "127.0.0.1")
	if err != OK:
		_server = null
		return err
	port = port_
	return OK


func stop() -> void:
	for c in _conns:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_conns.clear()
	if _server:
		_server.stop()
	_server = null


func poll(console: NetAdminConsole) -> void:
	if _server == null:
		return
	var now := Time.get_ticks_msec()
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _conns.size() >= MAX_CONNS or now < _locked_until:
			peer.put_data("ERR busy or locked\n".to_utf8_buffer())
			peer.disconnect_from_host()
			continue
		peer.set_no_delay(true)
		peer.put_data("CRITTERWEIGHT admin. Send: AUTH <token>\n".to_utf8_buffer())
		_conns.append({"peer": peer, "buf": PackedByteArray(), "authed": false, "last": now})
	for c in _conns.duplicate():
		var peer2: StreamPeerTCP = c["peer"]
		peer2.poll()
		if peer2.get_status() != StreamPeerTCP.STATUS_CONNECTED or now - int(c["last"]) > IDLE_MS:
			peer2.disconnect_from_host()
			_conns.erase(c)
			continue
		var avail := mini(peer2.get_available_bytes(), 4096)
		if avail <= 0:
			continue
		var res: Array = peer2.get_data(avail)
		if int(res[0]) != OK:
			continue
		var buf: PackedByteArray = c["buf"]
		buf.append_array(res[1])
		c["last"] = now
		while true:
			var nl := buf.find(10)
			if nl < 0:
				if buf.size() > MAX_LINE:
					peer2.put_data("ERR line too long\n".to_utf8_buffer())
					peer2.disconnect_from_host()
					_conns.erase(c)
				break
			var line := buf.slice(0, nl).get_string_from_utf8().strip_edges()
			buf = buf.slice(nl + 1)
			if not bool(c["authed"]):
				if line.begins_with("AUTH ") and NetProtocol.bytes_equal(line.substr(5).strip_edges().sha256_buffer(), _token):
					c["authed"] = true
					peer2.put_data("OK\n".to_utf8_buffer())
					Log.i("admin", "TCP admin authenticated from 127.0.0.1")
				else:
					_fails.append(now)
					_fails = _fails.filter(func(t): return now - t < 60000)
					if _fails.size() >= 5:
						_locked_until = now + LOCKOUT_MS
						Log.w("admin", "TCP admin locked for %d s after repeated failed logins" % (LOCKOUT_MS / 1000))
					Log.w("admin", "TCP admin authentication failed")
					peer2.put_data("ERR auth\n".to_utf8_buffer())
					peer2.disconnect_from_host()
					_conns.erase(c)
					break
				continue
			var out := console.execute(line, "tcp")
			peer2.put_data((out + "\n.\n").to_utf8_buffer())
		c["buf"] = buf
