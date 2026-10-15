class_name NetLanDiscovery
extends RefCounted
## LAN discovery via UDP broadcast beacons.
##
## Servers (listen or dedicated, when enabled) send a small beacon once per second to the
## discovery port on: 255.255.255.255, the x.y.z.255 broadcast address of every local IPv4
## interface (Windows sends a limited broadcast out of one interface only), and 127.0.0.1.
## Because only one process per machine can bind a UDP port, beacons go to PORT_SPAN
## consecutive ports and listeners take the first free one, so several game instances on one PC
## can all browse. Listeners dedupe by the server's random instance id and expire silent entries.
## Beacons are untrusted input: bounded, validated, and only ever displayed or used as an address.
##
## Beacon: "CWLAN1" [u16 protocol][u64 instance][u16 game port][str name][str game version]
##   [str content hash prefix][u8 players][u8 max players][u8 spectators][u8 max spectators]
##   [u8 flags: 1 password, 2 dedicated, 4 in match][str rules][str arena][str phase]

const MAGIC := "CWLAN1"
const PORT_SPAN := 4
const EXPIRE_MS := 4500
const MAX_SESSIONS := 64
const F_PASSWORD := 1
const F_DEDICATED := 2
const F_IN_MATCH := 4

var discovery_port := 7779
var instance_id := 0
var listening_port := 0
var sessions := {}            ## instance id -> session dict
var _tx: PacketPeerUDP = null
var _rx: PacketPeerUDP = null
var _targets: Array[String] = []
var _hash_prefix := ""


func start_announcer(port: int) -> Error:
	discovery_port = port
	_tx = PacketPeerUDP.new()
	_tx.set_broadcast_enabled(true)
	var err := _tx.bind(0, "*")
	if err != OK:
		_tx = null
		return err
	var c := Crypto.new()
	instance_id = c.generate_random_bytes(8).decode_s64(0)
	_targets = broadcast_targets()
	return OK


static func broadcast_targets() -> Array[String]:
	var out: Array[String] = ["255.255.255.255", "127.0.0.1"]
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.contains(":") or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		var parts := s.split(".")
		if parts.size() != 4:
			continue
		var bc := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not out.has(bc):
			out.append(bc)
	return out


## info: {port, name, players, max_players, spectators, max_spectators, password, dedicated,
##        in_match, rules, arena, phase}
func announce(info: Dictionary) -> void:
	if _tx == null:
		return
	var pkt := encode_beacon(info, instance_id)
	for t in _targets:
		for k in PORT_SPAN:
			_tx.set_dest_address(t, discovery_port + k)
			_tx.put_packet(pkt)


static func encode_beacon(info: Dictionary, inst: int) -> PackedByteArray:
	var w := NetWriter.new()
	w.raw(MAGIC.to_ascii_buffer())
	w.u16(NetProtocol.VERSION)
	w.u64(inst)
	w.u16(int(info.get("port", 7777)))
	w.text(str(info.get("name", "")), 80)
	w.text(NetProtocol.game_version(), 32)
	w.text(Content.content_hash().substr(0, 16), 16)
	w.u8(int(info.get("players", 0)))
	w.u8(int(info.get("max_players", 0)))
	w.u8(int(info.get("spectators", 0)))
	w.u8(int(info.get("max_spectators", 0)))
	var flags := 0
	if bool(info.get("password", false)):
		flags |= F_PASSWORD
	if bool(info.get("dedicated", false)):
		flags |= F_DEDICATED
	if bool(info.get("in_match", false)):
		flags |= F_IN_MATCH
	w.u8(flags)
	w.text(str(info.get("rules", "")), 64)
	w.text(str(info.get("arena", "")), 64)
	w.text(str(info.get("phase", "")), 16)
	return w.data()


## Returns {} when the packet is not a valid beacon.
static func decode_beacon(data: PackedByteArray) -> Dictionary:
	if data.size() < 8 or data.size() > 600:
		return {}
	if data.slice(0, 6).get_string_from_ascii() != MAGIC:
		return {}
	var r := NetReader.new(data, 6)
	var d := {}
	d["protocol"] = r.u16()
	d["instance"] = r.u64()
	d["port"] = r.u16()
	d["name"] = NetProtocol.clean_text(r.text(80), 40)
	d["game_version"] = r.text(32)
	d["content"] = r.text(16)
	d["players"] = r.u8()
	d["max_players"] = r.u8()
	d["spectators"] = r.u8()
	d["max_spectators"] = r.u8()
	var flags := r.u8()
	d["password"] = flags & F_PASSWORD != 0
	d["dedicated"] = flags & F_DEDICATED != 0
	d["in_match"] = flags & F_IN_MATCH != 0
	d["rules"] = r.text(64)
	d["arena"] = r.text(64)
	d["phase"] = r.text(16)
	if not r.ok or int(d["port"]) == 0:
		return {}
	return d


## Starts listening on the first free port of discovery_port .. +PORT_SPAN-1.
func start_listener(port: int) -> Error:
	discovery_port = port
	_hash_prefix = Content.content_hash().substr(0, 16)
	for k in PORT_SPAN:
		var rx := PacketPeerUDP.new()
		if rx.bind(port + k, "*") == OK:
			_rx = rx
			listening_port = port + k
			return OK
	return ERR_ALREADY_IN_USE


func is_listening() -> bool:
	return _rx != null


## Reads pending beacons and expires silent sessions. Returns true if the list changed.
func poll() -> bool:
	if _rx == null:
		return false
	var changed := false
	var now := Time.get_ticks_msec()
	var budget := 256
	while _rx.get_available_packet_count() > 0 and budget > 0:
		budget -= 1
		var pkt := _rx.get_packet()
		var d := decode_beacon(pkt)
		if d.is_empty():
			continue
		var ip := _rx.get_packet_ip()
		var inst := int(d["instance"])
		var key := str(inst)
		if not sessions.has(key) and sessions.size() >= MAX_SESSIONS:
			continue
		var prev: Dictionary = sessions.get(key, {})
		# prefer a real LAN address over loopback when the same server is heard on both
		var addr := ip
		if not prev.is_empty() and str(prev["address"]) != ip and ip.begins_with("127."):
			addr = str(prev["address"])
		d["address"] = addr
		d["last_seen"] = now
		var reasons: Array[String] = []
		if int(d["protocol"]) != NetProtocol.VERSION:
			reasons.append("different network protocol")
		elif str(d["game_version"]) != NetProtocol.game_version():
			reasons.append("different game version (%s)" % d["game_version"])
		elif str(d["content"]) != _hash_prefix:
			reasons.append("different content/mods")
		d["compatible"] = reasons.is_empty()
		d["incompatible_reason"] = ", ".join(PackedStringArray(reasons))
		if prev.is_empty() or _differs(prev, d):
			changed = true
		sessions[key] = d
	for key2 in sessions.keys():
		if now - int(sessions[key2]["last_seen"]) > EXPIRE_MS:
			sessions.erase(key2)
			changed = true
	return changed


static func _differs(a: Dictionary, b: Dictionary) -> bool:
	for k in ["name", "players", "max_players", "phase", "rules", "arena", "address", "port", "password", "in_match"]:
		if a.get(k) != b.get(k):
			return true
	return false


func list() -> Array:
	var out: Array = []
	for s in sessions.values():
		out.append((s as Dictionary).duplicate())
	out.sort_custom(func(x, y): return str(x["name"]) < str(y["name"]))
	return out


func stop() -> void:
	if _tx:
		_tx.close()
	if _rx:
		_rx.close()
	_tx = null
	_rx = null
	sessions.clear()
