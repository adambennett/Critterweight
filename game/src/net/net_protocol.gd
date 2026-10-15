class_name NetProtocol
## Wire protocol of CRITTERWEIGHT networking (docs/NETWORKING.md is the readable spec).
##
## Every ENet packet is [u8 message id][payload]. Ids 1..63 travel client -> server, 64..127
## server -> client; a peer that receives an id meant for the other direction (or an unknown id,
## or a payload that fails bounds-checked decoding) commits a protocol violation.
## Bump VERSION whenever any layout below changes; the handshake refuses mismatched versions.
## History: 1 = first layout; 2 = input samples carry FighterInput.BUTTON_COUNT counters (the
## TAG button), fighter slots with roster generations (spawn/despawn/rebuild), mode view/HUD state;
## 3 = the challenge carries the server's gameplay content hash and package list (id, version,
## hash, client_only) so the joining side runs Mods.compare() before it says hello; hello package
## entries carry hash + client_only, hello ends with the player's aim-assist level (LQ_ASSIST
## updates it). The challenge prefix (protocol, game version, name, nonce, flags) never changes,
## so a mismatched protocol is always recognised.

const VERSION := 3

## ---- channels (ENet) ----
const CH_CONTROL := 0      ## reliable ordered: handshake, lobby, chat, app messages, match lifecycle
const CH_EVENTS := 1       ## reliable ordered: simulation events (compact, tick-stamped)
const CH_SNAPSHOT := 2     ## unreliable sequenced: server snapshots
const CH_INPUT := 3        ## unreliable sequenced: client input samples (redundant)
const CHANNEL_COUNT := 4

## ---- client -> server ----
const C_HELLO := 1
const C_LEAVE := 2
const C_LOBBY := 3         ## lobby request (ready/creature/team/spectate/host settings ...)
const C_CHAT := 4
const C_VOTE := 5
const C_INPUT := 6
const C_APP := 7
const C_PING := 8

## ---- server -> client ----
const S_CHALLENGE := 64
const S_WELCOME := 65
const S_REJECT := 66
const S_LOBBY := 67
const S_CHAT := 68
const S_NOTICE := 69
const S_MATCH_START := 70
const S_SNAPSHOT := 71
const S_EVENTS := 72
const S_MATCH_END := 73
const S_APP := 74
const S_CLOSING := 75
const S_KICKED := 76
const S_PONG := 77
const S_ROSTER := 78          ## fighter slot changes (events channel, before the events of that tick)

## Maximum accepted payload size (bytes, including the id byte) per client -> server message.
const MAX_SIZE := {C_HELLO: 16384, C_LEAVE: 16, C_LOBBY: 512, C_CHAT: 600, C_VOTE: 16,
	C_INPUT: 256, C_APP: 65536 + 256, C_PING: 32}
## Server -> client messages are bounded too (clients reject anything bigger).
const MAX_SERVER_PACKET := 1 << 20

## ---- C_LOBBY request kinds ----
const LQ_READY := 1
const LQ_CREATURE := 2
const LQ_TEAM := 3
const LQ_SPECTATE := 4
const LQ_ASSIST := 5          ## aim-assist level for the next matches (accessibility setting)
const LQ_HOST_RULES := 10     ## host only (listen server): rules preset id
const LQ_HOST_ARENA := 11     ## host only: arena id
const LQ_HOST_BOTS := 12      ## host only: bot count + difficulty
const LQ_HOST_START := 13     ## host only: start the match now
const LQ_HOST_KICK := 14      ## host only: kick a player

## ---- reasons (reject / kick / close / local failures) ----
const R_NONE := 0
const R_PROTOCOL := 1
const R_GAME_VERSION := 2
const R_CONTENT := 3
const R_FULL := 4
const R_PASSWORD := 5
const R_KICKED := 6
const R_HANDSHAKE_TIMEOUT := 7
const R_VIOLATION := 8
const R_SHUTDOWN := 9
const R_HOST_LEFT := 10
const R_TIMEOUT := 11
const R_FLOOD := 12
const R_LEFT := 13
const R_CONNECT_FAILED := 20
const R_LOCAL_ERROR := 21
const R_REPLACED := 22

## Limits shared by both sides.
const MAX_NAME := 20
const MAX_CHAT := 200
const MAX_PLAYERS := 8
const MAX_SPECTATORS := 8
const MAX_FIGHTERS := 8       ## fighters chosen from lobby players + bots for PvP formats
const MAX_SLOTS := 32         ## replicated fighter slots (modes may spawn minions: MatchSim allows 24)
const MAX_SEGMENTS := 24
const MAX_INPUT_SAMPLES := 8
const INPUT_HZ := 60
const TOKEN_BYTES := 16
const NONCE_BYTES := 16
const MAX_APP_TYPE := 64
const MAX_APP_PAYLOAD := 65536
const MAX_PACKAGES := 64      ## content packages listed in the handshake (core + mods)
## Aim-assist multipliers of the accessibility setting "access.target_assist" (same table as
## MatchScene). Remote players send theirs; the server clamps to MAX_ASSIST.
const ASSIST_LEVELS := {"low": 0.5, "normal": 1.0, "high": 1.8}
const MAX_ASSIST := 1.8


## UI-ready description of a failure/disconnect reason. `details` are extra lines (e.g. which
## content packages differ). Returns {code, title, message, details}.
static func describe(code: int, details: Array = [], server_text := "") -> Dictionary:
	var title := "Disconnected"
	var msg := ""
	match code:
		R_PROTOCOL:
			title = "Incompatible build"
			msg = "The server uses a different network protocol. Both sides need the same game version."
		R_GAME_VERSION:
			title = "Incompatible build"
			msg = "The server runs a different game version. Both sides need the same version to play together."
		R_CONTENT:
			title = "Content mismatch"
			msg = "Your installed content or mods differ from the server's. Match the packages listed below, then try again."
		R_FULL:
			title = "Server full"
			msg = "All player and spectator slots are taken. Try again later."
		R_PASSWORD:
			title = "Wrong password"
			msg = "This session is password protected and the password was not accepted."
		R_KICKED:
			title = "Kicked"
			msg = "You were removed from the session."
		R_HANDSHAKE_TIMEOUT:
			title = "Connection failed"
			msg = "The server did not finish the handshake in time."
		R_VIOLATION:
			title = "Disconnected"
			msg = "The connection sent invalid data and was closed (protocol violation)."
		R_SHUTDOWN:
			title = "Server closed"
			msg = "The server shut down."
		R_HOST_LEFT:
			title = "Session ended"
			msg = "The host left the session."
		R_TIMEOUT:
			title = "Connection lost"
			msg = "No response from the other side (timed out). Check your network connection."
		R_FLOOD:
			title = "Disconnected"
			msg = "Too much data was sent too quickly (flood protection)."
		R_LEFT:
			title = "Left session"
			msg = "You left the session."
		R_CONNECT_FAILED:
			title = "Connection failed"
			msg = "Could not reach the server. Check the address and port, and that the host's port is reachable (port forwarding for internet play)."
		R_LOCAL_ERROR:
			title = "Network error"
			msg = "The network session could not be started on this computer."
		R_REPLACED:
			title = "Disconnected"
			msg = "This player connected again from another session."
		_:
			msg = "The connection was closed."
	if server_text != "":
		match code:
			R_KICKED:
				msg = "You were removed from the session: %s" % server_text
			R_SHUTDOWN:
				msg = "The server shut down: %s" % server_text
			_:
				if not msg.contains(server_text):
					msg += "\n" + server_text
	return {"code": code, "title": title, "message": msg, "details": details.duplicate()}


static func reason_name(code: int) -> String:
	match code:
		R_PROTOCOL: return "incompatible_protocol"
		R_GAME_VERSION: return "incompatible_build"
		R_CONTENT: return "content_mismatch"
		R_FULL: return "server_full"
		R_PASSWORD: return "bad_password"
		R_KICKED: return "kicked"
		R_HANDSHAKE_TIMEOUT: return "handshake_timeout"
		R_VIOLATION: return "protocol_violation"
		R_SHUTDOWN: return "server_shutdown"
		R_HOST_LEFT: return "host_left"
		R_TIMEOUT: return "timeout"
		R_FLOOD: return "flood"
		R_LEFT: return "left"
		R_CONNECT_FAILED: return "connect_failed"
		R_LOCAL_ERROR: return "local_error"
		R_REPLACED: return "replaced"
	return "none" if code == R_NONE else "unknown_%d" % code


static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Aim-assist multiplier chosen in this machine's accessibility settings.
static func local_assist() -> float:
	return float(ASSIST_LEVELS.get(str(Settings.get_value("access.target_assist")), 1.0))


## Assist level on the wire: hundredths in one byte. Decoding clamps to [0, MAX_ASSIST], so a
## modified client cannot ask for more help than the setting offers.
static func assist_to_byte(a: float) -> int:
	return clampi(roundi(a * 100.0), 0, 255)


static func assist_from_byte(b: int) -> float:
	return clampf(float(b) / 100.0, 0.0, MAX_ASSIST)


## Package list on the wire: [u8 n] n x ([str id][str version][str hash][u8 1 = client_only]),
## at most MAX_PACKAGES entries (Content.package_list() / Mods.fingerprint() format).
static func write_packages(w: NetWriter, pkgs: Array) -> void:
	var n := mini(pkgs.size(), MAX_PACKAGES)
	w.u8(n)
	for i in n:
		var p: Dictionary = pkgs[i] if typeof(pkgs[i]) == TYPE_DICTIONARY else {}
		w.text(str(p.get("id", "")), 64)
		w.text(str(p.get("version", "")), 32)
		w.text(str(p.get("hash", "")), 80)
		w.u8(1 if bool(p.get("client_only", false)) else 0)


static func read_packages(r: NetReader) -> Array:
	var out: Array = []
	var n := r.count(MAX_PACKAGES)
	for i in n:
		var id := r.text(64)
		var ver := r.text(32)
		var h := r.text(80)
		var fl := r.u8()
		if not r.ok:
			return []
		out.append({"id": id, "version": ver, "hash": h, "client_only": fl & 1 != 0})
	return out


## Content compatibility for joining (MOD-05); symmetric, so the client (before it says hello)
## and the server (authority, on hello) reach the same verdict. `cmp` = Mods.compare(remote_pkgs)
## on this machine, `remote_pkgs` = the other side's package list, `same_gameplay_hash` =
## whether both Content.content_hash() values match. Missing, extra or different-version gameplay
## packages block. A package that differs only in its package hash (same version) passes when the
## gameplay hashes match - e.g. a folder install vs. the same package as an archive, or edited
## presentation files - because the simulation cannot diverge. client_only packages never count.
## Returns {ok, details: [UI lines, Mods.compare wording], hash_only: [ids], missing, extra,
## mismatched}.
static func content_verdict(cmp: Dictionary, remote_pkgs: Array, same_gameplay_hash: bool) -> Dictionary:
	var local_ver := {}
	for p in Content.package_list():
		local_ver[str(p["id"])] = str(p["version"])
	var remote_ver := {}
	for p in remote_pkgs:
		if typeof(p) == TYPE_DICTIONARY:
			remote_ver[str(p.get("id", ""))] = str(p.get("version", ""))
	var hash_only: Array = []
	var version_mismatch: Array = []
	for id in cmp.get("mismatched", []):
		if local_ver.has(str(id)) and str(local_ver[str(id)]) == str(remote_ver.get(str(id), "")):
			hash_only.append(str(id))
		else:
			version_mismatch.append(str(id))
	var missing: Array = (cmp.get("missing", []) as Array).duplicate()
	var extra: Array = (cmp.get("extra", []) as Array).duplicate()
	var blocking := not missing.is_empty() or not extra.is_empty() or not version_mismatch.is_empty()
	var ok := not blocking and same_gameplay_hash
	var details: Array = []
	if not ok:
		for m in cmp.get("messages", []):
			details.append(str(m))
		# a same-version hash difference reads "you have 1.0.0, the host has 1.0.0": say what it is
		for id in hash_only:
			var v := str(local_ver[id])
			var generic := "Different version of %s: you have %s, the host has %s" % [id, v, v]
			var better := "Your copy of %s %s differs from the host's (same version, different files): install the host's copy of the package" % [id, v]
			var at := details.find(generic)
			if at >= 0:
				details[at] = better
			elif not details.has(better):
				details.append(better)
		if details.is_empty():
			details.append("Same packages and versions, but their gameplay files differ (an installed package was modified). Reinstall the packages on both sides.")
	return {"ok": ok, "details": details, "hash_only": hash_only, "missing": missing, "extra": extra,
		"mismatched": version_mismatch}


## Name sanitizer shared by client and server: printable, trimmed, bounded, never empty.
static func clean_name(s: String) -> String:
	var out := ""
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 32 or c == 127 or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E):
			continue
		out += ch
	out = out.strip_edges()
	if out.length() > MAX_NAME:
		out = out.substr(0, MAX_NAME).strip_edges()
	return out if out != "" else "Rookie"


static func clean_text(s: String, max_len: int) -> String:
	var out := ""
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 32 or c == 127:
			continue
		out += ch
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.substr(0, max_len)
	return out


## Challenge response: the password never travels in clear text.
static func password_proof(nonce: PackedByteArray, password: String) -> PackedByteArray:
	if password == "":
		return PackedByteArray()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(nonce)
	ctx.update(("critterweight:" + password).to_utf8_buffer())
	return ctx.finish()


## Constant-time comparison (tokens, proofs).
static func bytes_equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


static func random_bytes(n: int) -> PackedByteArray:
	var c := Crypto.new()
	return c.generate_random_bytes(n)


## App message types: short lowercase identifiers ("coop.route_vote", "run:checkpoint").
static func valid_app_type(t: String) -> bool:
	if t.length() < 1 or t.length() > MAX_APP_TYPE:
		return false
	for ch in t:
		var c := ch.unicode_at(0)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or ch in ["_", ".", ":", "-", "/"]
		if not ok:
			return false
	return true


## Encodes an app payload (plain data only; objects are never serialized).
static func encode_payload(payload: Dictionary) -> PackedByteArray:
	return var_to_bytes(payload)


## Decodes and validates an untrusted app payload. Allowed: null, bool, int, finite float,
## String (<= 8192 chars), Vector2/3/4, Color, Array, Dictionary (String/int keys) and packed
## arrays, nested at most 12 deep and 8192 values in total. Returns {ok, value, error}.
static func decode_payload(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_APP_PAYLOAD:
		return {"ok": false, "error": "payload larger than %d bytes" % MAX_APP_PAYLOAD}
	if bytes.size() < 4:
		return {"ok": false, "error": "payload too short"}
	var v = bytes_to_var(bytes)
	if typeof(v) != TYPE_DICTIONARY:
		return {"ok": false, "error": "payload must be a dictionary"}
	var budget := [8192]
	var err := _check_value(v, 0, budget)
	if err != "":
		return {"ok": false, "error": err}
	return {"ok": true, "value": v}


static func _check_value(v, depth: int, budget: Array) -> String:
	budget[0] = int(budget[0]) - 1
	if int(budget[0]) < 0:
		return "payload has too many values"
	if depth > 12:
		return "payload nested too deeply"
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_COLOR:
			return ""
		TYPE_FLOAT:
			return "" if is_finite(float(v)) else "non-finite number in payload"
		TYPE_STRING, TYPE_STRING_NAME:
			return "" if str(v).length() <= 8192 else "string longer than 8192 characters"
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return ""
		TYPE_PACKED_STRING_ARRAY:
			for s in v:
				if str(s).length() > 8192:
					return "string longer than 8192 characters"
			return ""
		TYPE_ARRAY:
			for e in v:
				var r := _check_value(e, depth + 1, budget)
				if r != "":
					return r
			return ""
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for k in d:
				if typeof(k) != TYPE_STRING and typeof(k) != TYPE_STRING_NAME and typeof(k) != TYPE_INT:
					return "dictionary keys must be strings or integers"
				var r2 := _check_value(d[k], depth + 1, budget)
				if r2 != "":
					return r2
			return ""
	return "unsupported value type %s in payload" % type_string(typeof(v))
