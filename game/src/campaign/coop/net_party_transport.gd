class_name NetPartyTransport
extends PartyTransport
## PartyTransport over the Net autoload's application message channel (owned by the network
## subsystem). Wiring contract this adapter expects from Net (docs/CAMPAIGN_SYSTEMS.md):
##   Net.send_app(target_peer: String, type: String, payload: Dictionary) -> void
##       target "" = broadcast to every session member; reliable, ordered.
##   signal Net.app_message(from_peer: String, type: String, payload: Dictionary)
##   signal Net.member_joined(peer: String) / Net.member_left(peer: String, reason: String)
##   Net.local_member_id() -> String ; Net.member_ids() -> Array
## Campaign message types are namespaced "cmp/<type>" on the wire so they never collide with
## other subsystems' app messages. Until Net provides these members the adapter reports itself
## unavailable (available() == false) and the campaign menu offers co-op only over loopback.
## Large payloads (whole run states) travel deflated (NetProtocol.pack_party_payload) and are
## unpacked with bounded size/value checks before CoopSession sees them; a payload that does not
## unpack is dropped (CoopSession then simply never sees it).

const PREFIX := "cmp/"

var _net: Node = null


func _init() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	_net = tree.root.get_node_or_null("Net") if tree else null
	if available():
		_net.connect("app_message", _on_app_message)
		if _net.has_signal("member_joined"):
			_net.connect("member_joined", _on_member_joined)
		if _net.has_signal("member_left"):
			_net.connect("member_left", _on_member_left)


func _on_member_joined(p) -> void:
	peer_joined.emit(str(p))


func _on_member_left(p, r) -> void:
	peer_left.emit(str(p), str(r))


func available() -> bool:
	return _net != null and _net.has_method("send_app") and _net.has_signal("app_message")


func local_id() -> String:
	return str(_net.call("local_member_id")) if available() and _net.has_method("local_member_id") else ""


func peers() -> Array:
	return _net.call("member_ids") if available() and _net.has_method("member_ids") else []


var dropped := 0                  ## received party payloads that failed to unpack


func send(to: String, type: String, payload: Dictionary) -> void:
	if available():
		_net.call("send_app", to, PREFIX + type, NetProtocol.pack_party_payload(payload))


func _on_app_message(from_peer, type, payload) -> void:
	var t := str(type)
	if t.begins_with(PREFIX) and typeof(payload) == TYPE_DICTIONARY:
		var up := NetProtocol.unpack_party_payload(payload)
		if not bool(up["ok"]):
			dropped += 1
			Log.w("net", "party message '%s' from %s dropped: %s" % [t, str(from_peer), str(up["error"])])
			return
		message_received.emit(str(from_peer), t.substr(PREFIX.length()), up["value"])


func close() -> void:
	if _net == null:
		return
	for pair in [["app_message", _on_app_message], ["member_joined", _on_member_joined], ["member_left", _on_member_left]]:
		if _net.has_signal(str(pair[0])) and _net.is_connected(str(pair[0]), pair[1]):
			_net.disconnect(str(pair[0]), pair[1])
