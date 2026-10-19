extends TestCase
## NET-03/NET-06/NET-09: wire-format primitives, quantization accuracy, event codec, bounds-checked
## decoding of hostile input, payload sanitizing, beacons, reasons and the server config parser.


func test_writer_reader_roundtrip() -> void:
	var w := NetWriter.new(42)
	w.u8(250).i8(-100).u16(65000).i16(-30000).u32(4000000000).i32(-2000000000).u64(1234567890123)
	w.f32(3.25).boolean(true).varint(300).svarint(-12345).text("héllo wörld", 64).blob(PackedByteArray([1, 2, 3]))
	w.vec3q(Vector3(1.234, -0.5, 7.75))
	var r := NetReader.new(w.data(), 1)
	check_eq(int(w.data()[0]), 42, "message id")
	check_eq(r.u8(), 250)
	check_eq(r.i8(), -100)
	check_eq(r.u16(), 65000)
	check_eq(r.i16(), -30000)
	check_eq(r.u32(), 4000000000)
	check_eq(r.i32(), -2000000000)
	check_eq(r.u64(), 1234567890123)
	check_near(r.f32(), 3.25, 0.0001)
	check_eq(r.boolean(), true)
	check_eq(r.varint(), 300)
	check_eq(r.svarint(), -12345)
	check_eq(r.text(64), "héllo wörld")
	check_eq(r.blob(16), PackedByteArray([1, 2, 3]))
	var v := r.vec3q()
	check(v.distance_to(Vector3(1.234, -0.5, 7.75)) < 0.001, "vec3q within 1 mm (%s)" % v)
	check(r.expect_end(), "consumed exactly: %s" % r.error)


func test_text_truncates_on_character_boundary() -> void:
	var w := NetWriter.new()
	w.text("ääääää", 5)  # 2 bytes per char: must keep 2 whole characters (4 bytes)
	var r := NetReader.new(w.data())
	check_eq(r.text(255), "ää")


func test_reader_never_reads_past_end() -> void:
	var r := NetReader.new(PackedByteArray([1, 2]))
	check_eq(r.u32(), 0, "truncated u32 returns 0")
	check(not r.ok, "truncation flagged")
	check_eq(r.u8(), 0, "reads after failure return 0")
	var r2 := NetReader.new(PackedByteArray([200, 65, 66]))
	check_eq(r2.text(16), "", "string longer than its limit is rejected")
	check(not r2.ok)
	var r3 := NetReader.new(PackedByteArray([9]))
	r3.count(8)
	check(not r3.ok, "count above maximum rejected")
	var r4 := NetReader.new(PackedByteArray([1, 0, 0]))
	r4.u8()
	check(not r4.expect_end(), "trailing bytes rejected")
	var r5 := NetReader.new(PackedByteArray([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
	r5.varint()
	check(not r5.ok, "over-long varint rejected")
	var r6 := NetReader.new(PackedByteArray([0, 0, 0xC0, 0x7F]))
	r6.f32()
	check(not r6.ok, "NaN float rejected")


func test_quaternion_quantization_error() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	for i in 5000:
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if axis.length() < 0.01:
			continue
		var q := Quaternion(axis.normalized(), rng.randf_range(-PI, PI))
		var back := NetWriter.unpack_quat(NetWriter.pack_quat(q))
		var err := rad_to_deg(q.angle_to(back))
		worst = maxf(worst, err)
	check(worst < 0.2, "smallest-three 32-bit rotation error < 0.2 deg (worst %.4f)" % worst)
	var ident := NetWriter.unpack_quat(NetWriter.pack_quat(Quaternion.IDENTITY))
	check(rad_to_deg(Quaternion.IDENTITY.angle_to(ident)) < 0.2, "identity survives")


func test_position_quantization_and_clamp() -> void:
	var w := NetWriter.new()
	w.vec3q(Vector3(31.0, -12.345, 0.0004))
	w.vec3q(Vector3(500.0, -500.0, 0.0))
	var r := NetReader.new(w.data())
	var a := r.vec3q()
	check(a.distance_to(Vector3(31.0, -12.345, 0.0004)) < 0.0009, "1 mm resolution (%s)" % a)
	var b := r.vec3q()
	check(absf(b.x - 32767.0 / 1024.0) < 0.001 and absf(b.y + 32767.0 / 1024.0) < 0.001, "out of range clamps to +-32 m")


func test_event_codec_roundtrip() -> void:
	var evs := [
		{"type": "hit", "seq": 5, "tick": 100, "fighter": 0, "target": 1, "damage": 12.5, "point": Vector3(0.1, 1.2, -0.3),
			"normal": Vector3(0, 0, 1), "blocked": false, "parried": false, "counter": true, "part": "head", "element": "",
			"quality": 0.75, "move": "dev_l1", "slot": "l1", "knockdown": false, "otg": false},
		{"type": "match_start", "tick": 100, "arena": "the_gullet", "mode": "standard", "seed": 99887766},
		{"type": "brand_new_event", "tick": 103, "custom_key": "x", "nested": {"a": [1, 2.5, "three"], 4: Vector2(1, 2)},
			"far": Vector3(100, 0, -50), "inf": Vector3.INF, "c": Color(1, 0, 0, 0.5)},
	]
	var w := NetWriter.new()
	NetEventCodec.encode_batch(w, evs, 100)
	var r := NetReader.new(w.data())
	var out := NetEventCodec.decode_batch(r)
	check(r.ok and r.at_end(), "decoded cleanly: %s" % r.error)
	check_eq(out.size(), 3)
	var h: Dictionary = out[0]
	check_eq(str(h["type"]), "hit")
	check_eq(int(h["tick"]), 100)
	check_near(float(h["damage"]), 12.5, 0.001)
	check((h["point"] as Vector3).distance_to(Vector3(0.1, 1.2, -0.3)) < 0.002, "point quantized")
	check_eq(str(h["part"]), "head")
	check_eq(bool(h["counter"]), true)
	check(not h.has("seq"), "seq is implicit")
	check(not (out[1] as Dictionary).has("seed"), "server seed never leaves the server")
	var c: Dictionary = out[2]
	check_eq(str(c["type"]), "brand_new_event", "unknown event types travel as strings")
	check_eq(int(c["tick"]), 103)
	check_eq(str(c["custom_key"]), "x")
	var nested: Dictionary = c["nested"]
	check_eq(nested["a"], [1, 2.5, "three"], "nested arrays")
	check_eq(nested[4], Vector2(1, 2), "int dictionary keys")
	check_eq(c["far"], Vector3(100, 0, -50), "far vectors use full floats")
	check(not (c["inf"] as Vector3).is_finite(), "non-finite marker vectors survive")
	check((c["c"] as Color).is_equal_approx(Color(1, 0, 0, 128.0 / 255.0)), "colors")


func test_event_codec_survives_garbage() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var survived := 0
	for i in 3000:
		var n := rng.randi_range(0, 96)
		var b := PackedByteArray()
		b.resize(n)
		for k in n:
			b[k] = rng.randi() & 0xFF
		var r := NetReader.new(b)
		var evs := NetEventCodec.decode_batch(r)
		var r2 := NetReader.new(b)
		NetSnapshot.decode_body(r2)
		var r3 := NetReader.new(b)
		NetSnapshot.decode_roster(r3)
		if typeof(evs) == TYPE_ARRAY:
			survived += 1
	check_eq(survived, 3000, "random bytes never crash the decoders")
	# a valid batch truncated at every possible length must fail cleanly
	var w := NetWriter.new()
	NetEventCodec.encode_batch(w, [{"type": "hit", "tick": 5, "damage": 3.0, "point": Vector3.ONE}], 5)
	var full := w.data()
	for cut in full.size():
		var rr := NetReader.new(full.slice(0, cut))
		NetEventCodec.decode_batch(rr)
		check(not rr.ok, "truncated batch (%d/%d bytes) rejected" % [cut, full.size()])


func test_input_sample_codec_is_strict() -> void:
	var fi := FighterInput.new()
	fi.move = Vector3(0.6, 0.0, -0.8)
	fi.set_held(FighterInput.GUARD, true)
	fi.press(FighterInput.LIGHT)
	fi.press(FighterInput.LIGHT)
	fi.press(FighterInput.HEAVY)
	var w := NetWriter.new()
	NetSnapshot.write_input(w, fi)
	check_eq(w.size(), 17, "core sample stays compact without guest counters")
	var back := NetSnapshot.read_input(NetReader.new(w.data()))
	check(back.move.distance_to(fi.move) < 0.02, "move survives (%s)" % back.move)
	check(back.is_held(FighterInput.GUARD), "held bits")
	check_eq(int(back.press_count[FighterInput.LIGHT]), 2, "press counters")
	# hostile sample: every bit set, extreme move
	var raw := PackedByteArray([127, 127, 0xFF, 0xFF, 0xFF, 0xFF])
	for i in FighterInput.BUTTON_COUNT:
		raw.append(255)
	var h := NetSnapshot.read_input(NetReader.new(raw))
	check(h.move.length() <= 1.0001, "move clamped to unit length")
	check_eq(h.held, (1 << FighterInput.BUTTON_COUNT) - 1, "undefined held bits masked")


func test_remote_input_redundancy_and_jitter_buffer() -> void:
	var ri := NetRemoteInput.new(2, "P")
	var f := Fighter.new()
	var mk := func(seq_presses: int) -> FighterInput:
		var s := FighterInput.new()
		for k in seq_presses:
			s.press(FighterInput.LIGHT)
		s.move = Vector3(1, 0, 0)
		return s
	# packet with samples 3,2,1 (newest first): each light press counted once
	var batch: Array[FighterInput] = [mk.call(3), mk.call(2), mk.call(1)]
	ri.push(3, batch)
	# duplicate/redundant packet (same seqs) must not add samples
	ri.push(3, batch)
	check_eq(ri.buffered(), 3, "redundant copies ignored")
	var dt := 1.0 / 120.0
	for i in 8:
		ri.poll(f, null, dt)
	check_eq(ri.samples_applied, 3, "one sample per 1/60 s")
	check(f.input.move.x > 0.9, "move applied")
	# counters are remapped into the fighter's space: first sample sets the baseline
	var base := int(f.input.press_count[FighterInput.LIGHT])
	var batch2: Array[FighterInput] = [mk.call(5)]
	ri.push(4, batch2)
	ri.poll(f, null, dt)
	ri.poll(f, null, dt)
	check_eq(int(f.input.press_count[FighterInput.LIGHT]), (base + 2) & 0xFF, "two new presses arrive, none invented")
	# starvation neutralizes movement after 0.25 s
	for i in 60:
		ri.poll(f, null, dt)
	check_eq(f.input.move, Vector3.ZERO, "starved input goes neutral")
	f.free()


func test_payload_sanitizer() -> void:
	var good := NetProtocol.decode_payload(NetProtocol.encode_payload({"route": 2, "names": ["a", "b"], "nested": {"x": 1.5}}))
	check(bool(good["ok"]), "plain data accepted")
	check_eq(int(good["value"]["route"]), 2)
	var not_dict := NetProtocol.decode_payload(var_to_bytes([1, 2, 3]))
	check(not bool(not_dict["ok"]), "non-dictionary rejected")
	var obj := NetProtocol.decode_payload(var_to_bytes_with_objects({"obj": RefCounted.new()}))
	check(not bool(obj["ok"]), "encoded objects rejected")
	var deep := {}
	var cur := deep
	for i in 20:
		var nxt := {}
		cur["d"] = nxt
		cur = nxt
	check(not bool(NetProtocol.decode_payload(var_to_bytes(deep))["ok"]), "excessive nesting rejected")
	var many := {"a": []}
	for i in 9000:
		(many["a"] as Array).append(i)
	check(not bool(NetProtocol.decode_payload(var_to_bytes(many))["ok"]), "too many values rejected")
	check(not bool(NetProtocol.decode_payload(PackedByteArray([1, 2]))["ok"]), "garbage rejected")
	check(NetProtocol.valid_app_type("coop.route_vote"), "type ok")
	check(not NetProtocol.valid_app_type("Bad Type!"), "type with spaces/caps rejected")
	check(not NetProtocol.valid_app_type(""), "empty type rejected")


func test_beacon_codec() -> void:
	var b := NetLanDiscovery.encode_beacon({"port": 7777, "name": "LAN Party", "players": 3, "max_players": 8,
		"password": true, "dedicated": true, "in_match": false, "rules": "duel", "arena": "the_gullet", "phase": "lobby"}, 42)
	var d := NetLanDiscovery.decode_beacon(b)
	check_eq(str(d.get("name", "")), "LAN Party")
	check_eq(int(d.get("port", 0)), 7777)
	check_eq(int(d.get("instance", 0)), 42)
	check_eq(bool(d.get("password", false)), true)
	check_eq(int(d.get("players", 0)), 3)
	check(NetLanDiscovery.decode_beacon(PackedByteArray([1, 2, 3])).is_empty(), "garbage is not a beacon")
	var bad := b.duplicate()
	bad[0] = 88
	check(NetLanDiscovery.decode_beacon(bad).is_empty(), "wrong magic rejected")
	# protocol 4: the server's gameplay packages ride along; a beacon without them still decodes
	check(bool(d.get("packages_listed", false)), "the package list is in the beacon")
	var ids: Array = (d.get("packages", []) as Array).map(func(p: Dictionary) -> String: return str(p["id"]))
	check(ids.has("core"), "with core (%s)" % str(ids))
	var head := b.slice(0, b.size() - _packages_tail_size(d))
	var old := NetLanDiscovery.decode_beacon(head)
	check(not old.is_empty() and not bool(old.get("packages_listed", false)), "an older beacon without the list still decodes")
	var cut := b.slice(0, b.size() - 3)
	check(NetLanDiscovery.decode_beacon(cut).is_empty(), "a truncated package list is refused")
	check(b.size() <= NetLanDiscovery.MAX_BEACON, "beacon within %d B (%d)" % [NetLanDiscovery.MAX_BEACON, b.size()])


## Bytes the package list takes at the end of an encoded beacon.
func _packages_tail_size(d: Dictionary) -> int:
	var n := 1
	for p in d.get("packages", []):
		for k in ["id", "version", "hash"]:
			n += 1 + str(p[k]).to_utf8_buffer().size()
	return n


## The LAN list explains why a session cannot be joined, in the join check's own wording.
func test_lan_compatibility_lines() -> void:
	var mine := Content.content_hash().substr(0, 16)
	var base := NetLanDiscovery.decode_beacon(NetLanDiscovery.encode_beacon({"port": 7777, "name": "S"}, 1))
	check(NetLanDiscovery.compatibility(base, mine).is_empty(), "same build and content: nothing to explain")
	var proto := base.duplicate(true)
	proto["protocol"] = NetProtocol.VERSION + 1
	check(str(NetLanDiscovery.compatibility(proto, mine)).contains("network protocol"), "different protocol")
	var ver := base.duplicate(true)
	ver["game_version"] = "9.9.9"
	check(str(NetLanDiscovery.compatibility(ver, mine)).contains("theirs 9.9.9"), "different game version with both versions")
	var modded := base.duplicate(true)
	modded["content"] = "0123456789abcdef"
	(modded["packages"] as Array).append({"id": "moon_rules", "version": "1.0.0", "hash": "ab".repeat(6), "client_only": false})
	var lines := NetLanDiscovery.compatibility(modded, mine)
	check(str(lines).contains("Missing mod: moon_rules 1.0.0"), "names the mod we lack (Mods.compare wording): %s" % str(lines))
	var same_list := base.duplicate(true)
	same_list["content"] = "0123456789abcdef"
	check(str(NetLanDiscovery.compatibility(same_list, mine)).contains("different files"), "same list, different files")
	var unlisted := modded.duplicate(true)
	unlisted["packages_more"] = true
	check(str(NetLanDiscovery.compatibility(unlisted, mine)).contains("join to see"), "a list cut short does not guess")


func test_parse_address() -> void:
	var a := Net.parse_address("192.168.1.20", 7777)
	check_eq([a["address"], a["port"], a["error"]], ["192.168.1.20", 7777, ""], "address alone keeps the default port")
	var b := Net.parse_address("  play.example.net:27015 ", 7777)
	check_eq([b["address"], b["port"], b["error"]], ["play.example.net", 27015, ""], "name:port")
	var c := Net.parse_address("[::1]:7800", 7777)
	check_eq([c["address"], c["port"], c["error"]], ["::1", 7800, ""], "[v6]:port")
	check_eq(str(Net.parse_address("::1", 7777)["address"]), "::1", "a bare IPv6 address is not split")
	for t in ["", "host:0", "host:70000", "host:abc", "[::1", "two words"]:
		check(str(Net.parse_address(t, 7777)["error"]) != "", "'%s' is refused with a reason" % t)


func test_recent_servers_list() -> void:
	var path := Paths.file("profiles", Net.RECENT_FILE)
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	for e in Net.recent_servers():
		Net.forget_server(str(e["address"]), int(e["port"]))
	check(Net.recent_servers().is_empty(), "starts empty")
	Net.remember_server("10.0.0.1", 7777, "First")
	Net.remember_server("10.0.0.2", 7778, "Second", true)
	Net.remember_server("10.0.0.1", 7777, "First again")
	var r := Net.recent_servers()
	check_eq(r.size(), 2, "the same server is listed once")
	check_eq(str(r[0]["name"]), "First again", "newest first, renamed")
	check(bool(r[1]["dedicated"]), "dedicated flag kept")
	for i in 12:
		Net.remember_server("10.1.0.%d" % i, 7777, "S%d" % i)
	check_eq(Net.recent_servers().size(), Net.MAX_RECENT, "at most %d kept" % Net.MAX_RECENT)
	Net.forget_server("10.1.0.11", 7777)
	check(not Net.recent_servers().any(func(e: Dictionary) -> bool: return str(e["address"]) == "10.1.0.11"), "forget removes it")
	for e in Net.recent_servers():
		Net.forget_server(str(e["address"]), int(e["port"]))
	if before != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(before)
		f.close()


func test_reason_texts_are_ui_ready() -> void:
	for code in [NetProtocol.R_PROTOCOL, NetProtocol.R_GAME_VERSION, NetProtocol.R_CONTENT, NetProtocol.R_FULL,
			NetProtocol.R_PASSWORD, NetProtocol.R_KICKED, NetProtocol.R_HANDSHAKE_TIMEOUT, NetProtocol.R_VIOLATION,
			NetProtocol.R_SHUTDOWN, NetProtocol.R_HOST_LEFT, NetProtocol.R_TIMEOUT, NetProtocol.R_FLOOD,
			NetProtocol.R_CONNECT_FAILED, NetProtocol.R_LOCAL_ERROR]:
		var d := NetProtocol.describe(code, ["detail line"])
		check(str(d["title"]) != "" and str(d["message"]).length() > 15, "reason %d has a title and message" % code)
		check_eq((d["details"] as Array).size(), 1)
		check(not NetProtocol.reason_name(code).begins_with("unknown"), "reason %d has a stable name" % code)
	var k := NetProtocol.describe(NetProtocol.R_KICKED, [], "spamming")
	check(str(k["message"]).contains("spamming"), "kick reason shown")
	check_eq(NetProtocol.clean_name("  \u0001Al​ice\n  "), "Alice", "names sanitized")
	check_eq(NetProtocol.clean_name(""), "Rookie", "empty name gets a default")


func test_password_proof_never_contains_password() -> void:
	var nonce := NetProtocol.random_bytes(16)
	var p := NetProtocol.password_proof(nonce, "hunter2")
	check_eq(p.size(), 32, "sha256 proof")
	check(not p.get_string_from_utf8().contains("hunter2"), "password not in clear")
	check(NetProtocol.bytes_equal(p, NetProtocol.password_proof(nonce, "hunter2")), "deterministic for a nonce")
	check(not NetProtocol.bytes_equal(p, NetProtocol.password_proof(NetProtocol.random_bytes(16), "hunter2")), "fresh nonce, fresh proof")
	check(NetProtocol.password_proof(nonce, "").is_empty(), "no password, no proof")


func test_server_config_parser() -> void:
	var text := """
# comment
[server]
name = "Quoted Name"   # trailing comment
port = 8000
max_players = 6
lan_discovery = no
tick_rate = 120
[match]
playlist = bargain_bin
bot_difficulty = pro
empty_behavior = showcase
[admin]
port = 0
mystery = 1
"""
	var res := NetServerConfig.parse_text(text, "t.cfg")
	check((res["errors"] as Array).is_empty(), "valid config: %s" % str(res["errors"]))
	var cfg: Dictionary = res["cfg"]
	check_eq(str(cfg["name"]), "Quoted Name")
	check_eq(int(cfg["port"]), 8000)
	check_eq(int(cfg["max_players"]), 6)
	check_eq(bool(cfg["lan_discovery"]), false)
	check_eq(str(cfg["bot_difficulty"]), "pro")
	check_eq(str(cfg["empty_behavior"]), "showcase")
	check_eq(int(cfg["timeout"]), 10, "unspecified keys keep safe defaults")
	check(str(res["warnings"]).contains("admin.mystery"), "unknown keys warned")
	var bad := NetServerConfig.parse_text("[server]\nport = 80\nmax_players = lots\n[match]\nbot_difficulty = god\n[admin]\nport = 9000\ntoken = short\n", "bad.cfg")
	var errs := "\n".join(PackedStringArray(bad["errors"]))
	check(errs.contains("bad.cfg:2") and errs.contains("server.port"), "port range error with line number: %s" % errs)
	check(errs.contains("max_players must be a whole number"), "type error")
	check(errs.contains("bot_difficulty must be one of"), "enum error")
	check(errs.contains("admin.token is shorter than 16"), "TCP admin needs a strong token")
	var cli_errs: Array[String] = []
	var c2 := NetServerConfig.defaults()
	NetServerConfig.apply_cli(c2, PackedStringArray(["--server", "--port", "9100", "--max-players", "99"]), cli_errs)
	check_eq(int(c2["port"]), 9100, "CLI override")
	check(not cli_errs.is_empty(), "invalid CLI value rejected")
	var d := NetServerConfig.defaults()
	check_eq(int(d["admin_port"]), 0, "TCP admin is off by default")
	check_eq(str(d["password"]), "", "open by default but documented")


func test_package_list_codec() -> void:
	var pk := [{"id": "core", "version": "1.0.0", "hash": "", "client_only": false},
		{"id": "moon_rules", "version": "1.0.0", "hash": "ab".repeat(32), "client_only": false},
		{"id": "fancy_hats", "version": "2.1.0", "hash": "cd".repeat(32), "client_only": true}]
	var w := NetWriter.new(NetProtocol.S_CHALLENGE)
	NetProtocol.write_packages(w, pk)
	var r := NetReader.new(w.data(), 1)
	var back := NetProtocol.read_packages(r)
	check(r.ok and r.expect_end(), "package list decodes exactly")
	check_eq(back, pk.slice(0, 2), "gameplay packages round trip (id, version, hash); client_only ones never travel")
	var big: Array = []
	for i in NetProtocol.MAX_PACKAGES + 1:
		big.append({"id": "mod_%d" % i, "version": "1.0.0", "hash": "", "client_only": false})
	check(NetProtocol.too_many_packages(big), "more gameplay packages than the handshake lists is refused up front")
	big[0]["client_only"] = true
	check(not NetProtocol.too_many_packages(big), "client_only packages do not count")
	var many: Array = []
	for i in 80:
		many.append({"id": "mod_%d" % i, "version": "1.0.0", "hash": "", "client_only": false})
	var w2 := NetWriter.new(NetProtocol.S_CHALLENGE)
	NetProtocol.write_packages(w2, many)
	check_eq(NetProtocol.read_packages(NetReader.new(w2.data(), 1)).size(), NetProtocol.MAX_PACKAGES, "capped at MAX_PACKAGES")
	var bad := w.data()
	bad[1] = 200
	var r3 := NetReader.new(bad, 1)
	check(NetProtocol.read_packages(r3).is_empty() and not r3.ok, "count over the limit is refused")
	var cut := w.data().slice(0, 40)
	var r4 := NetReader.new(cut, 1)
	check(NetProtocol.read_packages(r4).is_empty() and not r4.ok, "truncated list is refused")


## MOD-05: the join verdict over Mods.compare() is symmetric and explains itself in UI lines.
func test_content_verdict() -> void:
	var mine := Content.package_list()
	var same := NetProtocol.content_verdict(Mods.compare(mine), mine, true)
	check(bool(same["ok"]) and (same["details"] as Array).is_empty(), "identical packages join")
	var theirs := mine.duplicate(true)
	theirs.append({"id": "moon_rules", "version": "1.0.0", "hash": "ab".repeat(32), "client_only": false})
	var v1 := NetProtocol.content_verdict(Mods.compare(theirs), theirs, false)
	check(not bool(v1["ok"]), "host has a mod we lack: refused")
	check_eq(v1["missing"], ["moon_rules"])
	check(str(v1["details"]).contains("Missing mod: moon_rules 1.0.0"), "Mods.compare wording: %s" % str(v1["details"]))
	var cosmetic := mine.duplicate(true)
	cosmetic.append({"id": "fancy_hats", "version": "2.1.0", "hash": "cd".repeat(32), "client_only": true})
	check(bool(NetProtocol.content_verdict(Mods.compare(cosmetic), cosmetic, true)["ok"]), "client_only packages never block")
	var core_v := str(mine[0]["version"])
	# synthetic Mods.compare results: same-version hash differences pass only with equal gameplay hashes
	var hash_cmp := {"compatible": false, "missing": [], "extra": [], "mismatched": ["core"],
		"messages": ["Different version of core: you have %s, the host has %s" % [core_v, core_v]]}
	var v2 := NetProtocol.content_verdict(hash_cmp, [{"id": "core", "version": core_v}], true)
	check(bool(v2["ok"]), "same version, different package files, same gameplay: allowed")
	check_eq(v2["hash_only"], ["core"])
	var v3 := NetProtocol.content_verdict(hash_cmp, [{"id": "core", "version": core_v}], false)
	check(not bool(v3["ok"]), "...but not when the gameplay hash differs")
	check(str(v3["details"]).contains("Your copy of core") and not str(v3["details"]).contains("Different version of core"),
		"explained as a modified copy: %s" % str(v3["details"]))
	var ver_cmp := {"compatible": false, "missing": [], "extra": [], "mismatched": ["core"],
		"messages": ["Different version of core: you have %s, the host has 9.9.9" % core_v]}
	var v4 := NetProtocol.content_verdict(ver_cmp, [{"id": "core", "version": "9.9.9"}], false)
	check(not bool(v4["ok"]) and v4["mismatched"] == ["core"], "different versions block")
	var v5 := NetProtocol.content_verdict(Mods.compare(mine), mine, false)
	check(not bool(v5["ok"]) and str(v5["details"]).contains("gameplay files differ"), "same lists, different gameplay hash: refused with an explanation")


func test_assist_level_on_the_wire() -> void:
	check_eq(NetProtocol.assist_from_byte(NetProtocol.assist_to_byte(0.5)), 0.5)
	check_eq(NetProtocol.assist_from_byte(NetProtocol.assist_to_byte(1.8)), 1.8)
	check_eq(NetProtocol.assist_from_byte(255), NetProtocol.MAX_ASSIST, "a forged level is clamped to the setting's maximum")
	check_eq(NetProtocol.assist_to_byte(-3.0), 0)
	check_eq(NetProtocol.assist_from_byte(70), 0.5, "only the setting's own levels are accepted (0.7 -> low)")
	check_eq(NetProtocol.assist_from_byte(0), 0.5, "and nothing below the lowest level")
	var lvl := NetProtocol.local_assist()
	check(lvl in NetProtocol.ASSIST_LEVELS.values(), "local setting maps to a known level (%.2f)" % lvl)


func test_server_mods_config() -> void:
	var res := NetServerConfig.parse_text("[server]
mods = moon_rules, rust_bucket ,moon_rules
mods_dir = C:/srv/mods
", "m.cfg")
	check((res["errors"] as Array).is_empty(), "mods keys parse: %s" % str(res["errors"]))
	check_eq(NetServerConfig.mod_ids(res["cfg"]), ["moon_rules", "rust_bucket"], "ids trimmed, order kept, duplicates dropped")
	check_eq(str(res["cfg"]["mods_dir"]), "C:/srv/mods")
	var bad := NetServerConfig.parse_text("[server]
mods = Moon Rules!
", "b.cfg")
	check(str(bad["errors"]).contains("not a mod id"), "invalid mod id refused: %s" % str(bad["errors"]))
	var c := NetServerConfig.defaults()
	var errs: Array[String] = []
	NetServerConfig.apply_cli(c, PackedStringArray(["--server", "--mods", "moon_rules"]), errs)
	check_eq(NetServerConfig.mod_ids(c), ["moon_rules"], "--mods on the command line")
	var pol := NetServerConfig.parse_text("[match]\nbot_policy = dev_biped_es_drill, dev_biped_bc_regular\nplayer_assist = false\n", "p.cfg")
	check((pol["errors"] as Array).is_empty(), "policy keys parse")
	check_eq(NetServerConfig.policy_ids(pol["cfg"]), ["dev_biped_es_drill", "dev_biped_bc_regular"], "AI Lab policies for bot slots")
	check_eq(bool(pol["cfg"]["player_assist"]), false, "the server can decide aim assist for everyone")
	check_eq(bool(NetServerConfig.defaults()["party_relay"]), true, "party relay on by default")


func test_rate_limiter() -> void:
	var rl := NetRateLimiter.new(10.0, 5.0)
	var ok := 0
	for i in 20:
		if rl.take():
			ok += 1
	check_eq(ok, 5, "burst capacity")
	await wait_physics(13)
	check(rl.take(), "refills with (wall-clock or simulated) time")


func test_mixed_core_and_guest_input_samples_preserve_packet_boundaries() -> void:
	var plain := FighterInput.new()
	plain.press(FighterInput.LIGHT)
	var guest := FighterInput.new()
	guest.press(FighterInput.MMA_CHECK)
	guest.set_held(FighterInput.MMA_CHECK, false) # released presses still need their counter
	var w := NetWriter.new()
	NetSnapshot.write_input(w, plain)
	NetSnapshot.write_input(w, guest)
	NetSnapshot.write_input(w, plain)
	check_eq(w.size(), 17 + 24 + 17, "only the guest sample pays for extended counters")
	var r := NetReader.new(w.data())
	check_eq(NetSnapshot.read_input(r).press_count, plain.press_count)
	check_eq(NetSnapshot.read_input(r).press_count, guest.press_count)
	check_eq(NetSnapshot.read_input(r).press_count, plain.press_count)
	check(r.ok and r.at_end(), "mixed redundancy batch consumes exact bytes")
	var truncated := NetReader.new(w.data().slice(17, 40))
	NetSnapshot.read_input(truncated)
	check(not truncated.ok, "truncated guest extension is rejected")


func test_guest_input_redundancy_stays_inside_bandwidth_budget() -> void:
	var core := FighterInput.new()
	var guest := FighterInput.new()
	guest.press(FighterInput.MMA_LL)
	check_eq(NetClient.input_batch_count([core, core, core, core]), 4, "standard roster keeps four samples")
	check_eq(NetClient.input_batch_count([guest, guest, guest, guest]), 3, "guest keeps three samples without increasing send rate")
	check_eq(NetClient.input_batch_count([core, guest, core, guest]), 3, "tagging across layouts stays within budget")
