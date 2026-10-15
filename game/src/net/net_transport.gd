class_name NetTransport
extends RefCounted
## Thin wrapper over one ENetConnection host used by both the server and the client:
## stable integer peer ids (server = 1 on the client side; remote peers 2.. on the server side),
## channel/flag mapping, per-peer timeouts, disconnect reason codes, and traffic statistics
## (application payload per channel + ENet wire totals for bandwidth measurements).
## poll() drains ENet events into plain dictionaries: {type, peer, channel, data, code}.

const EV_CONNECT := 1
const EV_DISCONNECT := 2
const EV_RECEIVE := 3
const MAX_EVENTS_PER_POLL := 4096

var host: ENetConnection = null
var server_mode := false
var timeout_ms := 10000
var _peers := {}          ## peer id -> ENetPacketPeer
var _ids := {}            ## ENetPacketPeer -> peer id
var _next_id := 2
var last_error := ""

## statistics (application payload bytes / packets)
var bytes_in := 0
var bytes_out := 0
var packets_in := 0
var packets_out := 0
var out_by_channel := PackedInt64Array([0, 0, 0, 0])
var in_by_channel := PackedInt64Array([0, 0, 0, 0])
## ENet wire totals (ENet headers included; IP/UDP headers excluded)
var wire_in := 0
var wire_out := 0
var wire_packets_in := 0
var wire_packets_out := 0


func is_open() -> bool:
	return host != null


## Server: binds `port` on `bind_address` ("*" = all interfaces).
func listen(port: int, bind_address := "*", max_peers := 32) -> Error:
	close()
	host = ENetConnection.new()
	var err := host.create_host_bound(bind_address, port, max_peers, NetProtocol.CHANNEL_COUNT)
	if err != OK:
		last_error = "cannot bind UDP port %d on %s: %s" % [port, bind_address, error_string(err)]
		host = null
		return err
	server_mode = true
	return OK


## Client: starts connecting to address:port (resolution must already be done by the caller for
## hostnames; ENet resolves too but blocks). The server is peer id 1.
func connect_to(address: String, port: int) -> Error:
	close()
	host = ENetConnection.new()
	var err := host.create_host(1, NetProtocol.CHANNEL_COUNT)
	if err != OK:
		last_error = "cannot create network host: %s" % error_string(err)
		host = null
		return err
	var p := host.connect_to_host(address, port, NetProtocol.CHANNEL_COUNT, NetProtocol.VERSION)
	if p == null:
		last_error = "cannot connect to %s:%d" % [address, port]
		host.destroy()
		host = null
		return ERR_CANT_CONNECT
	server_mode = false
	_peers[1] = p
	_ids[p] = 1
	_apply_timeout(p)
	return OK


func local_port() -> int:
	return host.get_local_port() if host else 0


func _apply_timeout(p: ENetPacketPeer) -> void:
	var t := maxi(timeout_ms, 1000)
	p.set_timeout(32, t, t)


func set_timeout_ms(ms: int) -> void:
	timeout_ms = ms
	for p in _peers.values():
		_apply_timeout(p)


func poll() -> Array:
	var out: Array = []
	if host == null:
		return out
	for i in MAX_EVENTS_PER_POLL:
		var e: Array = host.service(0)
		var t: int = e[0]
		if t == ENetConnection.EVENT_NONE:
			break
		if t == ENetConnection.EVENT_ERROR:
			last_error = "ENet service error"
			break
		var p: ENetPacketPeer = e[1]
		match t:
			ENetConnection.EVENT_CONNECT:
				var id := int(_ids.get(p, 0))
				if id == 0:
					if server_mode:
						id = _next_id
						_next_id += 1
					else:
						id = 1
					_peers[id] = p
					_ids[p] = id
				_apply_timeout(p)
				out.append({"type": EV_CONNECT, "peer": id, "data": e[2]})
			ENetConnection.EVENT_DISCONNECT:
				var id2 := int(_ids.get(p, 0))
				_ids.erase(p)
				if id2 != 0:
					_peers.erase(id2)
				out.append({"type": EV_DISCONNECT, "peer": id2, "code": int(e[2])})
			ENetConnection.EVENT_RECEIVE:
				var id3 := int(_ids.get(p, 0))
				var pkt := p.get_packet()
				var ch: int = e[3]
				bytes_in += pkt.size()
				packets_in += 1
				if ch >= 0 and ch < in_by_channel.size():
					in_by_channel[ch] += pkt.size()
				if id3 != 0:
					out.append({"type": EV_RECEIVE, "peer": id3, "channel": ch, "data": pkt})
	_pop_wire_stats()
	return out


func _pop_wire_stats() -> void:
	if host == null:
		return
	wire_out += int(host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	wire_in += int(host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	wire_packets_out += int(host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS))
	wire_packets_in += int(host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS))


func has_peer(id: int) -> bool:
	return _peers.has(id)


func peer_ids() -> Array:
	return _peers.keys()


func send(peer_id: int, channel: int, data: PackedByteArray, reliable: bool) -> Error:
	var p: ENetPacketPeer = _peers.get(peer_id)
	if p == null or p.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return ERR_UNAVAILABLE
	var flags := ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT
	var err := p.send(channel, data, flags)
	if err == OK:
		bytes_out += data.size()
		packets_out += 1
		if channel >= 0 and channel < out_by_channel.size():
			out_by_channel[channel] += data.size()
	return err


## Disconnects a peer. later = after queued packets are delivered (reasons arrive reliably).
func disconnect_peer(peer_id: int, code: int, later := true) -> void:
	var p: ENetPacketPeer = _peers.get(peer_id)
	if p == null:
		return
	if later:
		p.peer_disconnect_later(code)
	else:
		p.peer_disconnect_now(code)
		_peers.erase(peer_id)
		_ids.erase(p)


func flush() -> void:
	if host:
		host.flush()


func rtt_ms(peer_id: int) -> float:
	var p: ENetPacketPeer = _peers.get(peer_id)
	return float(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else 0.0


func rtt_var_ms(peer_id: int) -> float:
	var p: ENetPacketPeer = _peers.get(peer_id)
	return float(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)) if p else 0.0


## ENet's packet-loss estimate as a fraction 0..1.
func loss(peer_id: int) -> float:
	var p: ENetPacketPeer = _peers.get(peer_id)
	return float(p.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)) / 65536.0 if p else 0.0


func address(peer_id: int) -> String:
	var p: ENetPacketPeer = _peers.get(peer_id)
	return p.get_remote_address() if p else ""


func remote_port(peer_id: int) -> int:
	var p: ENetPacketPeer = _peers.get(peer_id)
	return p.get_remote_port() if p else 0


## Pumps the host for up to `ms` so queued packets (e.g. close notices) leave before teardown.
func drain(ms: int) -> void:
	if host == null:
		return
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		var e: Array = host.service(5)
		if int(e[0]) == ENetConnection.EVENT_DISCONNECT:
			var p: ENetPacketPeer = e[1]
			var id := int(_ids.get(p, 0))
			_ids.erase(p)
			_peers.erase(id)
		elif int(e[0]) == ENetConnection.EVENT_RECEIVE:
			(e[1] as ENetPacketPeer).get_packet()
		if _peers.is_empty():
			break
	host.flush()


func close(code := NetProtocol.R_SHUTDOWN) -> void:
	if host:
		for p in _peers.values():
			(p as ENetPacketPeer).peer_disconnect_now(code)
		host.flush()
		host.destroy()
	host = null
	_peers.clear()
	_ids.clear()
