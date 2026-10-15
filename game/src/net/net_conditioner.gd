class_name NetConditioner
extends RefCounted
## Network conditioner for tests and debugging: an in-process UDP relay that sits between ENet
## endpoints and degrades every datagram in BOTH directions with a one-way delay, uniform jitter
## and random loss (optionally a full blackhole). Because it works below ENet, ENet's real
## acknowledgements, retransmissions and timeouts are exercised exactly as on a bad network.
##
## Client side: the client connects to 127.0.0.1:<relay port>, the relay forwards to the server.
## Server side: the relay owns the public port and forwards to the server's internal port.
## CLI: --net-latency <ms one-way> --net-jitter <+-ms> --net-loss <0..1> [--net-reorder]
## Runs on its own thread (1 ms resolution); stats are read under a mutex.

var latency_ms := 0.0
var jitter_ms := 0.0
var loss := 0.0
var reorder := false
var blackhole := false
var listen_port := 0

var _target_ip := ""
var _target_port := 0
var _sock: PacketPeerUDP = null
var _clients := {}            ## "ip:port" -> {udp, ip, port, last_us}
var _up: Array = []           ## [{at, key, data}] towards the target
var _down: Array = []         ## [{at, key, data}] towards the original sender
var _last_up := {}
var _last_down := {}
var _rng := RandomNumberGenerator.new()
var _thread: Thread = null
var _mutex := Mutex.new()
var _running := false
var _stats := {"up": 0, "down": 0, "up_dropped": 0, "down_dropped": 0, "clients": 0}


static func from_args(args: PackedStringArray) -> NetConditioner:
	var lat := _arg_f(args, "--net-latency", 0.0)
	var jit := _arg_f(args, "--net-jitter", 0.0)
	var los := _arg_f(args, "--net-loss", 0.0)
	if lat <= 0.0 and jit <= 0.0 and los <= 0.0:
		return null
	var c := NetConditioner.new()
	c.configure(lat, jit, los, args.has("--net-reorder"))
	return c


static func _arg_f(args: PackedStringArray, flag: String, fallback: float) -> float:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size():
		return float(args[i + 1])
	return fallback


func configure(latency: float, jitter: float, loss_rate: float, allow_reorder := false) -> void:
	_mutex.lock()
	latency_ms = maxf(0.0, latency)
	jitter_ms = clampf(jitter, 0.0, latency if latency > 0.0 else jitter)
	loss = clampf(loss_rate, 0.0, 1.0)
	reorder = allow_reorder
	_mutex.unlock()


func set_blackhole(on: bool) -> void:
	_mutex.lock()
	blackhole = on
	_mutex.unlock()


func describe() -> String:
	return "latency %d ms one-way, jitter +-%d ms, loss %.1f%%%s" % [roundi(latency_ms), roundi(jitter_ms), loss * 100.0, ", reorder" if reorder else ""]


## Starts relaying datagrams received on bind_ip:port (0 = ephemeral) to target_ip:target_port.
func start(target_ip: String, target_port: int, port := 0, bind_ip := "127.0.0.1") -> Error:
	_sock = PacketPeerUDP.new()
	var err := _sock.bind(port, bind_ip)
	if err != OK:
		_sock = null
		return err
	listen_port = _sock.get_local_port()
	_target_ip = target_ip
	_target_port = target_port
	_rng.randomize()
	_running = true
	_thread = Thread.new()
	_thread.start(_loop)
	return OK


func stop() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_running = false
	_mutex.unlock()
	_thread.wait_to_finish()
	_thread = null
	for c in _clients.values():
		(c["udp"] as PacketPeerUDP).close()
	_clients.clear()
	if _sock:
		_sock.close()
	_sock = null


func stats() -> Dictionary:
	_mutex.lock()
	var s := _stats.duplicate()
	_mutex.unlock()
	s["latency_ms"] = latency_ms
	s["jitter_ms"] = jitter_ms
	s["loss"] = loss
	s["blackhole"] = blackhole
	return s


func _loop() -> void:
	while true:
		_mutex.lock()
		var run := _running
		var lat := latency_ms
		var jit := jitter_ms
		var los := loss
		var ro := reorder
		var hole := blackhole
		_mutex.unlock()
		if not run:
			return
		var now := Time.get_ticks_usec()
		# from senders (clients) towards the target
		while _sock.get_available_packet_count() > 0:
			var pkt := _sock.get_packet()
			var ip := _sock.get_packet_ip()
			var port := _sock.get_packet_port()
			var key := "%s:%d" % [ip, port]
			if not _clients.has(key):
				var u := PacketPeerUDP.new()
				if u.bind(0, "127.0.0.1" if _target_ip.begins_with("127.") else "*") != OK:
					continue
				u.set_dest_address(_target_ip, _target_port)
				_clients[key] = {"udp": u, "ip": ip, "port": port, "last_us": now}
			_clients[key]["last_us"] = now
			_schedule(_up, _last_up, key, pkt, now, lat, jit, los, ro, hole, "up")
		# replies from the target back to each sender
		for key2 in _clients.keys():
			var c: Dictionary = _clients[key2]
			var u2: PacketPeerUDP = c["udp"]
			while u2.get_available_packet_count() > 0:
				var pkt2 := u2.get_packet()
				_schedule(_down, _last_down, key2, pkt2, now, lat, jit, los, ro, hole, "down")
		# deliveries due
		_deliver(_up, now, true)
		_deliver(_down, now, false)
		# forget idle senders after 2 minutes
		for key3 in _clients.keys():
			if now - int(_clients[key3]["last_us"]) > 120000000:
				(_clients[key3]["udp"] as PacketPeerUDP).close()
				_clients.erase(key3)
		_mutex.lock()
		_stats["clients"] = _clients.size()
		_mutex.unlock()
		OS.delay_usec(500)


func _schedule(q: Array, last: Dictionary, key: String, pkt: PackedByteArray, now: int, lat: float,
		jit: float, los: float, ro: bool, hole: bool, dir: String) -> void:
	if hole or (los > 0.0 and _rng.randf() < los):
		_mutex.lock()
		_stats[dir + "_dropped"] = int(_stats[dir + "_dropped"]) + 1
		_mutex.unlock()
		return
	var delay := lat + (_rng.randf_range(-jit, jit) if jit > 0.0 else 0.0)
	var at := now + int(maxf(delay, 0.0) * 1000.0)
	if not ro:
		at = maxi(at, int(last.get(key, 0)))
		last[key] = at
	q.append({"at": at, "key": key, "data": pkt})


func _deliver(q: Array, now: int, up: bool) -> void:
	if q.is_empty():
		return
	var keep: Array = []
	var sent := 0
	for item in q:
		var it: Dictionary = item
		if int(it["at"]) > now:
			keep.append(it)
			continue
		var c: Dictionary = _clients.get(it["key"], {})
		if c.is_empty():
			continue
		if up:
			(c["udp"] as PacketPeerUDP).put_packet(it["data"])
		else:
			_sock.set_dest_address(str(c["ip"]), int(c["port"]))
			_sock.put_packet(it["data"])
		sent += 1
	q.clear()
	q.append_array(keep)
	if sent > 0:
		_mutex.lock()
		var k := "up" if up else "down"
		_stats[k] = int(_stats[k]) + sent
		_mutex.unlock()
