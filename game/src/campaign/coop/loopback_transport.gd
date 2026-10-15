class_name LoopbackTransport
extends PartyTransport
## In-process PartyTransport for tests and local verification (LOOPBACK — not network
## evidence). Every endpoint belongs to a shared Hub that queues messages; payloads are
## serialized to JSON text and parsed back on delivery (exactly what crosses a real wire),
## so a non-JSON-safe payload fails here first. Supports disconnect/reconnect of members to
## exercise disconnect, rejoin and host-departure flows.

class Hub:
	extends RefCounted
	var endpoints := {}          ## id -> LoopbackTransport
	var queue: Array = []        ## [{to, from, type, text}]
	var dropped := 0
	var delivered := 0

	func join(id: String) -> LoopbackTransport:
		var t := LoopbackTransport.new()
		t._hub_ref = weakref(self)
		t.id = id
		for other in endpoints:
			(endpoints[other] as LoopbackTransport)._events.append({"kind": "joined", "peer": id})
			t._events.append({"kind": "joined", "peer": str(other)})
		endpoints[id] = t
		return t

	func leave(id: String, reason := "disconnected") -> void:
		if not endpoints.has(id):
			return
		endpoints.erase(id)
		for other in endpoints:
			(endpoints[other] as LoopbackTransport)._events.append({"kind": "left", "peer": id, "reason": reason})

	## Delivers queued messages in order (repeat until quiet). Returns how many were delivered.
	func flush() -> int:
		var n := 0
		var guard := 0
		while guard < 64:
			guard += 1
			var batch := queue.duplicate()
			queue.clear()
			var any := false
			for t in endpoints.values():
				if (t as LoopbackTransport)._dispatch_events():
					any = true
			for m in batch:
				var dest := str(m["to"])
				if not endpoints.has(dest) or not endpoints.has(str(m["from"])):
					dropped += 1
					continue
				var payload = JSON.parse_string(str(m["text"]))
				(endpoints[dest] as LoopbackTransport).message_received.emit(str(m["from"]), str(m["type"]), payload if typeof(payload) == TYPE_DICTIONARY else {})
				n += 1
				any = true
			if not any and queue.is_empty():
				break
		delivered += n
		return n


var _hub_ref: WeakRef = null      ## weak: the Hub owns its endpoints (no reference cycle)
var id := ""
var _events: Array = []


func _hub() -> Hub:
	return _hub_ref.get_ref() as Hub if _hub_ref else null


func local_id() -> String:
	return id


func peers() -> Array:
	var out := []
	var hub := _hub()
	if hub == null or not hub.endpoints.has(id):
		return out
	for other in hub.endpoints:
		if str(other) != id:
			out.append(str(other))
	out.sort()
	return out


func send(to: String, type: String, payload: Dictionary) -> void:
	var hub := _hub()
	if hub == null or not hub.endpoints.has(id):
		return
	# full precision: floats must survive the wire bit-exactly (state checksums, replicas)
	var text := JSON.stringify(payload, "", false, true)
	if to == "":
		for p in peers():
			hub.queue.append({"to": p, "from": id, "type": type, "text": text})
	else:
		hub.queue.append({"to": to, "from": id, "type": type, "text": text})


func poll(_dt: float) -> void:
	var hub := _hub()
	if hub:
		hub.flush()


func close() -> void:
	var hub := _hub()
	if hub:
		hub.leave(id, "left")


func _dispatch_events() -> bool:
	if _events.is_empty():
		return false
	var evs := _events.duplicate()
	_events.clear()
	for e in evs:
		if str(e["kind"]) == "joined":
			peer_joined.emit(str(e["peer"]))
		else:
			peer_left.emit(str(e["peer"]), str(e.get("reason", "")))
	return true
