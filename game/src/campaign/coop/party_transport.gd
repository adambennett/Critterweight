class_name PartyTransport
extends RefCounted
## Message transport for a co-op campaign party (abstract). CoopSession talks only to this
## interface: LoopbackTransport (in-process, tests and local verification) and
## NetPartyTransport (the Net autoload's app-message channel) implement it.
## Contract:
##   * local_id() is the member's stable party id (== RunState player id, e.g. "p0").
##   * send(to, type, payload): to "" = broadcast to every other member. Payloads are
##     JSON-safe Dictionaries (implementations may serialize them); delivery is ordered per
##     sender; messages to a member who left are dropped.
##   * message_received / peer_joined / peer_left are emitted from poll() (or the network
##     thread's equivalent) — never re-entrantly from send().
## Message types are listed in docs/CAMPAIGN_SYSTEMS.md#co-op-protocol.

signal message_received(from: String, type: String, payload: Dictionary)
signal peer_joined(peer: String)
signal peer_left(peer: String, reason: String)


func local_id() -> String:
	return ""


func peers() -> Array:
	return []


func is_connected_to(peer: String) -> bool:
	return peers().has(peer)


func send(_to: String, _type: String, _payload: Dictionary) -> void:
	pass


func poll(_dt: float) -> void:
	pass


func close() -> void:
	pass
