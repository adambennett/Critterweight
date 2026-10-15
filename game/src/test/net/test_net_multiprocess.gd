extends TestCase
## NET-01/02/04/05/06/07/08/09/10, VER-04: independent headless processes - a dedicated server
## (`--server --config`), scripted clients and a listen host (`--net-client`, see
## net_test_client.gd) - exchanging real ENet traffic over LOOPBACK (127.0.0.1) on this machine.
## These results prove the protocol, authority and session flows; they are NOT evidence of
## off-machine internet connectivity (see docs/NETWORKING.md "NAT and port forwarding").

const U := preload("res://src/test/net/net_test_util.gd")
const DUEL := {"rules": "duel", "arena": "the_gullet", "weight": 1, "rules_override": {"rounds": 1, "round_time": 75}}

var u = null


func after_each() -> void:
	if u:
		u.kill_all()
	u = null


func _start_server(name_: String, sections: Dictionary, piped := false) -> int:
	var cfg: String = u.write_cfg("%s.cfg" % name_, sections)
	var pid: int = u.spawn(name_, ["--server", "--config", cfg], piped)
	check(pid > 0, "server process spawned")
	var log_ok: bool = await u.wait_until(func() -> bool: return u.out(pid).contains("ready:"), U.SERVER_READY_S)
	check(log_ok, "server reports ready")
	return pid


func _done(d: Dictionary) -> bool:
	return bool(d.get("done", false))


func _no_child_errors(pids: Array) -> void:
	for pid in pids:
		var errs: Array = u.errors(pid, ["[ERROR] app: screen"])
		check(errs.is_empty(), "process %d printed no engine/script errors: %s" % [pid, str(errs.slice(0, 5))])


func test_dedicated_match_two_clients() -> void:
	u = U.new(self, "dedicated_match")
	var port: int = u.base_port
	var pl: String = u.playlist("duel.json", [DUEL])
	var srv := await _start_server("srv", u.server_sections(port, {"match": {"playlist": pl}}))
	var a: int = u.spawn("alice", u.client_args(port, "Alice", "aggressive", ["--ready", "--stop-after-matches", "1", "--quit-after", "110"]))
	var b: int = u.spawn("bob", u.client_args(port, "Bob", "passive", ["--ready", "--present", "--stop-after-matches", "1", "--quit-after", "110"]))
	var ra: Dictionary = await u.wait_json(u.result_path("Alice"), _done, 120.0)
	var rb: Dictionary = await u.wait_json(u.result_path("Bob"), _done, 20.0)
	check(bool(ra.get("connected", false)) and bool(rb.get("connected", false)), "both clients joined")
	var results: Array = ra.get("results", [])
	check_eq(results.size(), 1, "Alice received the authoritative result")
	check_eq((rb.get("results", []) as Array).size(), 1, "Bob received the authoritative result")
	if results.size() == 1 and not (ra.get("matches", []) as Array).is_empty():
		var you := int(ra["matches"][0]["you"])
		var res: Dictionary = results[0]
		var my_team := int(res["fighters"][you]["team"])
		check_eq(int(res["winner_team"]), my_team, "the client whose inputs attacked won")
		check(int(res["fighters"][you]["stats"]["hits"]) >= 5, "server counted Alice's hits")
	check(int(ra.get("hits_dealt", 0)) >= 5, "Alice saw her hits replicated (%d)" % int(ra.get("hits_dealt", 0)))
	check_eq(float(rb.get("my_health_min", -1.0)), 0.0, "Bob was knocked out (authoritative health reached 0)")
	check(int(rb.get("events_total", 0)) > 10, "presenting client consumed replicated events")
	var stats: Dictionary = ra.get("stats", {})
	check(float(stats.get("snapshot_rate", 0.0)) > 20.0 or int(ra.get("snapshots", 0)) > 200, "snapshots arrived at ~30 Hz")
	print("    LOOPBACK duel: Alice hits %d, Bob min health %.1f, Alice in %.1f KB/s out %.1f KB/s, interp %.0f ms" % [
		int(ra.get("hits_dealt", 0)), float(rb.get("my_health_min", -1)), float(stats.get("in_kbps", 0)), float(stats.get("out_kbps", 0)),
		float(stats.get("interp_delay_ms", 0))])
	var slog: String = u.out(srv)
	check(slog.contains("match 1 started") and slog.contains("match 1 finished"), "server ran the match")
	var status: Dictionary = U.read_json(u.path("srv").path_join("server").path_join("status.json"))
	check(not status.is_empty(), "server writes a status file")
	_no_child_errors([srv, a, b])


func test_handshake_rejections() -> void:
	u = U.new(self, "rejections")
	var port: int = u.base_port
	var pl: String = u.playlist("duel.json", [DUEL])
	var srv := await _start_server("srv", u.server_sections(port, {"server": {"password": "letmein", "max_players": 1, "max_spectators": 0},
		"match": {"playlist": pl}}))
	var wrong: int = u.spawn("wrong", u.client_args(port, "Wrong", "idle", ["--password", "nope", "--quit-after", "20"]))
	var first: int = u.spawn("first", u.client_args(port, "First", "idle", ["--password", "letmein", "--quit-after", "60"]))
	var r1: Dictionary = await u.wait_json(u.result_path("First"), func(d: Dictionary) -> bool: return bool(d.get("connected", false)), 20.0)
	check(bool(r1.get("connected", false)), "correct password admitted")
	var second: int = u.spawn("second", u.client_args(port, "Second", "idle", ["--password", "letmein", "--quit-after", "20"]))
	var old: int = u.spawn("old", u.client_args(port, "Old", "idle", ["--password", "letmein", "--test-protocol", "1", "--quit-after", "20"]))
	var newer: int = u.spawn("newer", u.client_args(port, "Newer", "idle", ["--password", "letmein", "--test-game-version", "9.9.9", "--quit-after", "20"]))
	var modded: int = u.spawn("modded", u.client_args(port, "Modded", "idle", ["--password", "letmein", "--quit-after", "20",
		"--net-test-mod", "res://src/test/net/fixtures/netcheck_mod"]))
	var expect := {"Wrong": NetProtocol.R_PASSWORD, "Second": NetProtocol.R_FULL, "Old": NetProtocol.R_PROTOCOL,
		"Newer": NetProtocol.R_GAME_VERSION, "Modded": NetProtocol.R_CONTENT}
	for n in expect:
		var r: Dictionary = await u.wait_json(u.result_path(n), _done, 25.0)
		var fail: Dictionary = r.get("failure", {})
		check_eq(int(fail.get("code", -1)), int(expect[n]), "%s rejected as %s (%s)" % [n, NetProtocol.reason_name(int(expect[n])), str(fail.get("message", ""))])
		check(str(fail.get("title", "")) != "" and str(fail.get("message", "")) != "", "%s got a UI-ready reason" % n)
		if n == "Modded":
			# refused on the client's side (Mods.compare against the challenge's package list)
			check(str(fail.get("details", [])).contains("netcheck_mod 0.3.0") and str(fail.get("details", [])).contains("enabled but the host does not"),
				"content mismatch lists the differing package: %s" % str(fail.get("details", [])))
			check_eq(fail.get("mods", {}).get("extra", []), ["netcheck_mod"], "structured mod differences for the UI")
		if n == "Newer":
			check(str(fail.get("details", [])).contains("9.9.9"), "version mismatch shows both versions")
	check(u.running(srv), "server unaffected by the rejected clients")
	_no_child_errors([srv, first])


## MOD-05 / NET-05 end to end: a dedicated server loads exactly the mods its config names
## (server.mods); a client without them is refused on its own side with Mods.compare() wording and
## structured lists for the UI; a presenting client started with `--mods` (the same packages) joins
## and plays the mod's rules preset in the mod's authored arena (props and a hazard) through the
## real network path.
func test_server_mods_and_join_compare() -> void:
	u = U.new(self, "server_mods")
	var port: int = u.base_port
	var pl: String = u.playlist("moon.json", [{"rules": "moon_rules:moon_brawl", "arena": "rust_bucket:the_drain", "weight": 1,
		"rules_override": {"round_time": 40}}])
	var srv := await _start_server("srv", u.server_sections(port, {"server": {"mods": "moon_rules, rust_bucket"},
		"match": {"playlist": pl, "lobby_time": 3}}))
	check(u.out(srv).contains("moon_rules 1.0.0") and u.out(srv).contains("rust_bucket 1.0.0"), "server log lists the loaded mods")
	u.spawn("vanilla", u.client_args(port, "Vanilla", "idle", ["--quit-after", "20"]))
	var rv: Dictionary = await u.wait_json(u.result_path("Vanilla"), _done, 25.0)
	var fail: Dictionary = rv.get("failure", {})
	check_eq(int(fail.get("code", -1)), NetProtocol.R_CONTENT, "client without the mod refused (%s)" % str(fail.get("message", "")))
	check(str(fail.get("details", [])).contains("Missing mod: moon_rules 1.0.0"), "Mods.compare wording: %s" % str(fail.get("details", [])))
	var missing: Array = fail.get("mods", {}).get("missing", [])
	missing.sort()
	check_eq(missing, ["moon_rules", "rust_bucket"], "structured: missing")
	var modded: int = u.spawn("modded", u.client_args(port, "Moony", "aggressive", ["--mods", "moon_rules,rust_bucket", "--ready",
		"--present", "--stop-after-matches", "1", "--quit-after", "100"]))
	var rm: Dictionary = await u.wait_json(u.result_path("Moony"), _done, 110.0)
	check(bool(rm.get("connected", false)), "client with the same mods joined")
	var ms: Array = rm.get("matches", [])
	check(not ms.is_empty() and str(ms[0].get("rules_id", "")) == "moon_rules:moon_brawl", "played the mod's rules preset")
	check(not ms.is_empty() and str(ms[0].get("arena_id", "")) == "rust_bucket:the_drain", "in the mod's authored arena")
	check_eq((rm.get("results", []) as Array).size(), 1, "match finished with a result")
	var st: String = await u.admin(port + 1, ["AUTH " + U.admin_token(), "status"])
	check(st.contains("moon_rules@1.0.0") and st.contains("rust_bucket@1.0.0"), "admin status lists the packages: %s" % st.right(200))
	_no_child_errors([srv, modded])


func test_client_cannot_inject_damage() -> void:
	u = U.new(self, "inject")
	var port: int = u.base_port
	var pl: String = u.playlist("duel.json", [DUEL])
	var srv := await _start_server("srv", u.server_sections(port, {"match": {"playlist": pl}}))
	var victim: int = u.spawn("victim", u.client_args(port, "Victim", "passive", ["--ready", "--quit-after", "45"]))
	var cheat: int = u.spawn("cheater", u.client_args(port, "Cheater", "cheater", ["--ready", "--quit-after", "45"]))
	var rc: Dictionary = await u.wait_json(u.result_path("Cheater"), _done, 60.0)
	check(int(rc.get("forged_sent", 0)) >= 7, "cheater sent forged traffic (%d messages)" % int(rc.get("forged_sent", 0)))
	var kicked: Dictionary = rc.get("kicked", {})
	check_eq(int(kicked.get("code", -1)), NetProtocol.R_VIOLATION, "cheater kicked for protocol violations")
	var rv: Dictionary = await u.wait_json(u.result_path("Victim"), func(d: Dictionary) -> bool: return int(d.get("kick_notice_ms", -1)) > 0, 15.0)
	check(int(rv.get("kick_notice_ms", -1)) > 0, "victim saw the kick notice")
	check_near(float(rv.get("my_health_min_before_kick", -1.0)), 100.0, 0.05, "forged hits/app requests never changed the victim's authoritative health")
	var slog: String = u.out(srv)
	check(slog.contains("protocol violation by player"), "server logged the violations")
	check(slog.contains("unexpected message id"), "forged server messages refused")
	check(u.running(srv), "server keeps running")
	_no_child_errors([srv, victim])


func test_disconnect_and_rejoin() -> void:
	u = U.new(self, "rejoin")
	var port: int = u.base_port
	var pl: String = u.playlist("duel.json", [{"rules": "duel", "arena": "the_gullet", "weight": 1, "rules_override": {"rounds": 1, "round_time": 90}}])
	var srv := await _start_server("srv", u.server_sections(port, {"server": {"rejoin_grace": 40}, "match": {"playlist": pl}}))
	var ann: int = u.spawn("ann", u.client_args(port, "Ann", "aggressive", ["--ready", "--drop-at", "11", "--quit-after", "40"]))
	var ben: int = u.spawn("ben", u.client_args(port, "Ben", "passive", ["--ready", "--stop-after-matches", "1", "--quit-after", "120"]))
	var r1: Dictionary = await u.wait_json(u.result_path("Ann"), _done, 40.0)
	check(int(r1.get("dropped_at_ms", -1)) > 0, "Ann dropped abruptly mid-match")
	var token := str(r1.get("token_hex", ""))
	check(token.length() == 32, "rejoin token issued")
	var you := -1
	if not (r1.get("matches", []) as Array).is_empty():
		you = int(r1["matches"][0]["you"])
	var slog_ok: bool = await u.wait_until(func() -> bool: return u.out(srv).contains("slot reserved"), 10.0)
	check(slog_ok, "server reserved the slot")
	var ann2: int = u.spawn("ann2", u.client_args(port, "Ann", "aggressive", ["--token", token, "--stop-after-matches", "1", "--quit-after", "110"], "Ann2"))
	var r2: Dictionary = await u.wait_json(u.result_path("Ann2"), _done, 120.0)
	var w: Dictionary = r2.get("welcome", {})
	check(bool(w.get("rejoined", false)), "server recognised the rejoin")
	check_eq(int(r2.get("player_id", -1)), int(r1.get("player_id", -2)), "same player id")
	if not (r2.get("matches", []) as Array).is_empty():
		check_eq(int(r2["matches"][0]["you"]), you, "same fighter slot")
	var res: Array = r2.get("results", [])
	check_eq(res.size(), 1, "rejoined client got the result")
	if res.size() == 1 and you >= 0:
		check_eq(int(res[0]["winner_team"]), int(res[0]["fighters"][you]["team"]), "Ann's slot won (bot held it, then Ann)")
	var slog: String = u.out(srv)
	check(slog.contains("rejoined"), "server logged the rejoin")
	# Ben may be writing his final result right now (it is replaced, not appended): poll it
	var rben: Dictionary = await u.wait_json(u.result_path("Ben"), func(d: Dictionary) -> bool:
		return str(d.get("notices", [])).contains("a bot holds their fighter"), 10.0)
	check(str(rben.get("notices", [])).contains("a bot holds their fighter"), "other players were told a bot holds the slot")
	_no_child_errors([srv, ben, ann2])


func test_shutdown_via_console_is_announced() -> void:
	u = U.new(self, "shutdown_console")
	var port: int = u.base_port
	var pl: String = u.playlist("duel.json", [DUEL])
	var srv := await _start_server("srv", u.server_sections(port, {"match": {"playlist": pl}}), true)
	var w: int = u.spawn("watcher", u.client_args(port, "Watcher", "idle", ["--quit-after", "60"]))
	var r0: Dictionary = await u.wait_json(u.result_path("Watcher"), func(d: Dictionary) -> bool: return bool(d.get("connected", false)), 20.0)
	check(bool(r0.get("connected", false)), "client connected")
	u.send_line(srv, "status")
	check(await u.wait_until(func() -> bool: return u.out(srv).contains("players 1/4"), 5.0), "console 'status' answers")
	u.send_line(srv, "players")
	check(await u.wait_until(func() -> bool: return u.out(srv).contains("#2 Watcher"), 5.0), "console 'players' lists the client")
	u.send_line(srv, "say Hello from the admin")
	var r1: Dictionary = await u.wait_json(u.result_path("Watcher"), func(d: Dictionary) -> bool: return str(d.get("notices", [])).contains("Hello from the admin"), 5.0)
	check(str(r1.get("notices", [])).contains("Hello from the admin"), "'say' reaches clients")
	u.send_line(srv, "frobnicate")
	check(await u.wait_until(func() -> bool: return u.out(srv).contains("unknown command 'frobnicate'"), 5.0), "unknown commands refused")
	u.send_line(srv, "shutdown --restart Back in five minutes")
	var r2: Dictionary = await u.wait_json(u.result_path("Watcher"), _done, 10.0)
	var d: Dictionary = r2.get("disconnect", {})
	check_eq(int(d.get("code", -1)), NetProtocol.R_SHUTDOWN, "client told the server shut down")
	check(str(d.get("message", "")).contains("Back in five minutes"), "admin message shown: %s" % str(d.get("message", "")))
	check(bool(d.get("restarting", false)), "restart expected flag")
	check(await u.wait_exit(srv, 8.0), "server process exited")
	check_eq(u.exit_code(srv), 0, "clean exit code")
	var status: Dictionary = U.read_json(u.path("srv").path_join("server").path_join("status.json"))
	check_eq(str(status.get("state", "")), "stopped", "status file says stopped")
	_no_child_errors([srv, w])


func test_tcp_admin_is_local_and_authenticated() -> void:
	u = U.new(self, "tcp_admin")
	var port: int = u.base_port
	var admin_port: int = port + 1
	var token := "test-token-0123456789abcdef"
	var pl: String = u.playlist("duel.json", [DUEL])
	var srv := await _start_server("srv", u.server_sections(port, {"match": {"playlist": pl},
		"admin": {"console": "false", "port": admin_port, "token": token}}))
	var pest: int = u.spawn("pest", u.client_args(port, "Pest", "idle", ["--quit-after", "60"]))
	await u.wait_json(u.result_path("Pest"), func(d: Dictionary) -> bool: return bool(d.get("connected", false)), 20.0)
	var bad: String = await u.admin(admin_port, ["AUTH wrong-token-wrong-token"])
	check(bad.contains("ERR auth"), "wrong token refused: %s" % bad)
	var good: String = await u.admin(admin_port, ["AUTH " + token, "status", "playlist", "kick Pest spamming the lobby"])
	check(good.contains("OK"), "token accepted")
	check(good.contains("phase") and good.contains("\n."), "status answered with terminator")
	check(good.contains("playlist '"), "playlist shown")
	check(good.contains("kicked"), "kick executed")
	var rp: Dictionary = await u.wait_json(u.result_path("Pest"), _done, 10.0)
	check_eq(int(rp.get("kicked", {}).get("code", -1)), NetProtocol.R_KICKED, "client kicked")
	check(str(rp.get("kicked", {}).get("message", "")).contains("spamming the lobby"), "kick reason delivered")
	var back: int = u.spawn("pest2", u.client_args(port, "Pest", "idle", ["--token", str(rp.get("token_hex", "")), "--quit-after", "20"], "Pest2"))
	var rb: Dictionary = await u.wait_json(u.result_path("Pest2"), _done, 20.0)
	check_eq(int(rb.get("failure", {}).get("code", -1)), NetProtocol.R_KICKED, "kicked player cannot come straight back")
	var bye: String = await u.admin(admin_port, ["AUTH " + token, "shutdown"])
	check(bye.contains("shutting down"), "shutdown via TCP admin")
	check(await u.wait_exit(srv, 10.0), "server exited")
	check(u.out(srv).contains("TCP admin listening on 127.0.0.1"), "admin bound to localhost only")
	_no_child_errors([srv])


func test_conditioner_profile_still_completes_match() -> void:
	u = U.new(self, "conditioner")
	var port: int = u.base_port
	var pl: String = u.playlist("duel.json", [{"rules": "duel", "arena": "the_gullet", "weight": 1, "rules_override": {"rounds": 1, "round_time": 90}}])
	var srv := await _start_server("srv", u.server_sections(port, {"server": {"timeout": 10}, "match": {"playlist": pl}}))
	var lag := ["--net-latency", "80", "--net-jitter", "20", "--net-loss", "0.02"]
	var a: int = u.spawn("lag1", u.client_args(port, "Lag1", "aggressive", ["--ready", "--stop-after-matches", "1", "--quit-after", "150"] + lag))
	var b: int = u.spawn("lag2", u.client_args(port, "Lag2", "passive", ["--ready", "--present", "--stop-after-matches", "1", "--quit-after", "150"] + lag))
	var ra: Dictionary = await u.wait_json(u.result_path("Lag1"), _done, 160.0)
	var rb: Dictionary = await u.wait_json(u.result_path("Lag2"), _done, 20.0)
	check_eq((ra.get("results", []) as Array).size(), 1, "match completed under 80 +- 20 ms one-way, 2% loss (each direction)")
	check_eq((rb.get("results", []) as Array).size(), 1, "second client also got the result")
	check(int(ra.get("hits_dealt", 0)) > 0, "inputs still landed hits")
	var st: Dictionary = ra.get("stats", {})
	var cond: Dictionary = st.get("conditioner", {})
	check(float(st.get("rtt_max_ms", 0.0)) >= 140.0, "RTT reflects the profile (max %.0f ms)" % float(st.get("rtt_max_ms", 0.0)))
	check(int(cond.get("up_dropped", 0)) + int(cond.get("down_dropped", 0)) > 0, "packets were actually dropped")
	check(float(st.get("interp_delay_ms", 0.0)) > 45.0, "interpolation buffer widened for jitter (%.0f ms)" % float(st.get("interp_delay_ms", 0.0)))
	print("    LOOPBACK + conditioner (80+-20 ms one-way, 2%% loss): RTT max %.0f ms, interp %.0f ms, jitter p95 %.0f ms, dropped %d/%d, starved frames %d/%d" % [
		float(st.get("rtt_max_ms", 0)), float(st.get("interp_delay_ms", 0)), float(st.get("jitter_ms", 0)),
		int(cond.get("up_dropped", 0)) + int(cond.get("down_dropped", 0)), int(cond.get("up", 0)) + int(cond.get("down", 0)),
		int(st.get("starved_frames", 0)), int(st.get("frames", 0))])
	_no_child_errors([srv, a, b])


func test_listen_host_with_remote_client() -> void:
	u = U.new(self, "listen_host")
	var port: int = u.base_port
	# the host plays a rules preset it made itself ("user:..."): only it has that preset
	var host: int = u.spawn("host", ["--net-client", "--net-host", "--port", port, "--name", "Hosty", "--script", "aggressive",
		"--host-start-after-players", "2", "--rules", "duel", "--user-rules", "Spicy Duel", "--user-arena", "Net Test Cage", "--rounds", "1",
		"--round-time", "75", "--party", "--stop-after-matches", "1", "--quit-after", "110", "--result", u.result_path("Hosty")])
	var r0: Dictionary = await u.wait_json(u.result_path("Hosty"), func(d: Dictionary) -> bool: return bool(d.get("connected", false)), U.SERVER_READY_S)
	check(bool(r0.get("connected", false)), "listen server up")
	var g: int = u.spawn("guest", u.client_args(port, "Guest", "passive", ["--ready", "--app-request", "coop.hello", "--assist", "1.8",
		"--party", "--stop-after-matches", "1", "--quit-after", "110"]))
	var rg: Dictionary = await u.wait_json(u.result_path("Guest"), _done, 120.0)
	var rh: Dictionary = await u.wait_json(u.result_path("Hosty"), _done, 20.0)
	check_eq((rg.get("results", []) as Array).size(), 1, "remote client got the listen server's result")
	check_eq((rh.get("results", []) as Array).size(), 1, "host finished the match")
	if (rh.get("results", []) as Array).size() == 1:
		var res: Dictionary = rh["results"][0]
		var hf := int(rh.get("host_fighter", -1))
		check(hf >= 0, "host had a fighter (local input source, zero added latency)")
		if hf >= 0:
			check_eq(int(res["winner_team"]), int(res["fighters"][hf]["team"]), "host's local fighter won against the remote client")
	check_eq(float(rg.get("my_health_min", -1.0)), 0.0, "remote fighter knocked out by the host")
	check(str(rh.get("app_messages", [])).contains("coop.hello"), "host received the client's app request")
	check(str(rg.get("app_messages", [])).contains("echo.coop_hello"), "client received the host's reply")
	# user rules preset: sent in full, the guest never had it
	var preset := str(rh.get("user_rules", {}).get("id", ""))
	check(preset.begins_with("user:"), "host saved a user preset (%s)" % preset)
	var gm: Array = rg.get("matches", [])
	if not gm.is_empty():
		check_eq(str(gm[0].get("rules_id", "")), preset, "match ran with the host's own preset")
		check_eq(str(gm[0].get("rules_name", "")), "Spicy Duel", "full rules dictionary arrived")
		check_eq(float(gm[0].get("damage_mult", 0.0)), 1.25, "custom values arrived")
		check(not bool(gm[0].get("rules_known_here", true)), "the guest does not have that preset installed")
		# user arena: the host's own layout reaches the guest as an arena package, imported into a
		# sandbox and checked against the host's content hash before the match is built
		check_eq(str(gm[0].get("arena_id", "")), "user:net_test_cage", "match ran in the host's own layout")
		check_eq(str(gm[0].get("arena_imported", "")), "user:net_test_cage", "the guest imported the arena package")
		check_eq(str(gm[0].get("arena_name", "")), "Net Test Cage", "and built the same arena")
	# aim assist of the remote player is part of its authoritative fighter
	var guest_assist := -1.0
	var host_assist := -1.0
	for fm in rh.get("fighter_mods", []):
		if str(fm.get("kind", "")) == "net":
			guest_assist = float(fm.get("assist", -1.0))
		elif str(fm.get("kind", "")) == "player":
			host_assist = float(fm.get("assist", -1.0))
	check_eq(guest_assist, 1.8, "guest's aim assist applied on the host")
	check(host_assist in NetProtocol.ASSIST_LEVELS.values(), "host's own fighter uses its local setting (%.2f)" % host_assist)
	# co-op party transport (the campaign's NetPartyTransport) over the real network path
	var gid := str(int(rg.get("player_id", 0)))
	check_eq(str(rh.get("party_local_id", "")), "1", "host is party member 1")
	check_eq(str(rg.get("party_local_id", "")), gid, "guest's member id is its session player id")
	check(_party_from(rg, "1"), "guest's party transport got the host's broadcast: %s" % str(rg.get("party_messages", [])))
	check(_party_from(rh, gid), "host's party transport got the guest's broadcast: %s" % str(rh.get("party_messages", [])))
	_no_child_errors([host, g])


## A suspended co-op party run resumed through the lobby (independent processes, LOOPBACK). Ann
## (member id 1, who hosted it) and Ben (2) played the run online until everyone left; both
## kept it in their party saves. Now Ben hosts a new session and offers the run, Ann joins and
## claims her seat by run id. Their new session ids are the other way round (Ben 1, Ann 2): the
## seats keep the run's ids, so CoopSession (host_resume / member_join over NetPartyTransport)
## runs unchanged - Ann gets her fighter back, both vote and the run moves on identically.
func test_party_run_resumed_through_the_lobby() -> void:
	u = U.new(self, "party_run")
	var port: int = u.base_port
	var cat := CampaignCatalog.new(Content, "dev_biped")
	var cfg := {"seed": 4242, "variant": "off_the_street", "difficulty": "amateur", "dose": 0, "created_at": 3,
		"players": [{"id": "1", "name": "Ann", "profile_id": "ann", "fighter": "f_stoke"},
			{"id": "2", "name": "Ben", "profile_id": "ben", "fighter": "f_dozer"}]}
	var ctrl := RunController.start_run(cat, cfg)
	var st: Dictionary = ctrl.state
	var rid := str(st.get("run_id", ""))
	check_eq(ctrl.phase(), "map", "a party run waiting at the map")
	check_eq(RunStore.new(u.path("host").path_join("runs")).save(st, "ben", "party_" + rid), OK, "Ben's party save")
	check_eq(RunStore.new(u.path("ann").path_join("runs")).save(st, "ann", "party_" + rid), OK, "Ann's party save")
	var host: int = u.spawn("host", ["--net-client", "--net-host", "--port", port, "--name", "Ben", "--party-run", rid,
		"--party-profile", "ben", "--quit-after", "70", "--result", u.result_path("Ben")])
	var r0: Dictionary = await u.wait_json(u.result_path("Ben"), func(d: Dictionary) -> bool: return d.get("party_run", {}).has("open_error"), U.SERVER_READY_S)
	check_eq(str(r0.get("party_run", {}).get("open_error", "?")), "", "Ben offers the run from his party save")
	var ann: int = u.spawn("ann", u.client_args(port, "Ann", "idle", ["--party-run", rid, "--party-profile", "ann", "--quit-after", "70"]))
	var ra: Dictionary = await u.wait_json(u.result_path("Ann"), _done, 75.0)
	var rb: Dictionary = await u.wait_json(u.result_path("Ben"), _done, 20.0)
	var pa: Dictionary = ra.get("party_run", {})
	var pb: Dictionary = rb.get("party_run", {})
	# identity: seats keep the run's member ids although the session ids are swapped
	check_eq(int(ra.get("player_id", -1)), 2, "Ann is session player 2")
	check_eq(str(pa.get("claim_error", "?")), "", "Ann claimed her seat by run id")
	check_eq([str(pa.get("net_seat", "")), str(pa.get("me", ""))], ["1", "1"], "Ann plays as member 1 of the run")
	check_eq([str(pb.get("seat", "")), str(pb.get("me", "")), bool(pb.get("is_host", false))], ["2", "2", true], "Ben hosts as member 2")
	check_eq(str(pa.get("host_id", "")), "2", "Ann's CoopSession knows Ben (seat 2) as the host")
	check_eq(str(pa.get("error", "?")), "", "the run Ben resumed checked out against Ann's own save")
	check_eq(str(pb.get("start_error", "?")), "", "Ben's CoopSession resumed the run")
	check_eq(pb.get("started_with_missing", ["?"]), [], "after Ann was back")
	var host_msgs: Array = ra.get("party_run_messages", [])
	check(not host_msgs.is_empty() and host_msgs.all(func(m: Dictionary) -> bool: return str(m.get("from", "")) == "2"),
		"every party message Ann got came from the host's seat: %s" % str(host_msgs.slice(0, 3)))
	# the run itself: Ann's fighter back, both voted, both moved on the same way
	var ann_player := {}
	for p in pb.get("players", []):
		if str(p.get("id", "")) == "1":
			ann_player = p
	check(not ann_player.is_empty() and not bool(ann_player.get("bot", true)) and bool(ann_player.get("connected", false)),
		"Ann's fighter is hers again (not a bot): %s" % str(ann_player))
	var votes := 0
	for m in host_msgs:
		if str(m.get("type", "")) == "vote_result":
			for n in (m.get("counts", {}) as Dictionary).values():
				votes += int(n)
	check_eq(votes, 2, "both members voted the route")
	check_eq(str(pa.get("run_id", "")), rid, "the same run")
	check(str(pb.get("position", "")) != str(pb.get("start_position", "")) and str(pb.get("phase", "map")) != "map",
		"the run moved on (%s -> %s, %s)" % [pb.get("start_position", ""), pb.get("position", ""), pb.get("phase", "")])
	check_eq([str(pa.get("position", "")), str(pa.get("phase", "")), int(pa.get("log_size", -1))],
		[str(pb.get("position", "")), str(pb.get("phase", "")), int(pb.get("log_size", -2))], "and identically on both machines")
	_no_child_errors([host, ann])


func _party_from(r: Dictionary, sender: String) -> bool:
	for m in r.get("party_messages", []):
		if typeof(m) == TYPE_DICTIONARY and str(m.get("from", "")) == sender and str(m.get("type", "")) == "hello":
			return true
	return false


## Bonus modes change the fighter list mid-match (Chum Rush minions spawn and despawn into
## reused slots; the Absolute Unit is rebuilt with a scaled body): the roster generations must
## keep clients consistent, and the presenting client (NetMatchScene + ModeView + audio bridge on
## the mirror) must run without errors.
func test_bonus_modes_over_network() -> void:
	u = U.new(self, "bonus_modes")
	var port: int = u.base_port
	var pl: String = u.playlist("bonus.json", [
		{"id": "rush", "rules": "chum_rush", "arena": "the_gullet", "weight": 1, "bots": 0, "rules_override": {"round_time": 35}},
		{"id": "unit", "rules": "absolute_unit", "arena": "the_gullet", "weight": 1, "min_players": 4,
			"rules_override": {"round_time": 40, "score_target": 12}}],
		{"voting": {"enabled": false, "candidates": 1}, "repeat_avoidance": 1})
	var srv := await _start_server("srv", u.server_sections(port, {"match": {"playlist": pl, "results_time": 2}}))
	var a: int = u.spawn("brawler", u.client_args(port, "Brawler", "aggressive", ["--ready", "--stop-after-matches", "2", "--quit-after", "200"]))
	var b: int = u.spawn("viewer", u.client_args(port, "Viewer", "wander", ["--ready", "--present", "--stop-after-matches", "2", "--quit-after", "200"]))
	var ra: Dictionary = await u.wait_json(u.result_path("Brawler"), _done, 210.0)
	var rb: Dictionary = await u.wait_json(u.result_path("Viewer"), _done, 20.0)
	var modes: Array = []
	for m in ra.get("matches", []):
		modes.append(str(m.get("mode", "")))
	modes.sort()
	check_eq(modes, ["absolute_unit", "chum_rush"], "both bonus modes were played over the network")
	check_eq((ra.get("results", []) as Array).size(), 2, "both matches finished and advanced automatically")
	check(int(ra.get("roster_updates", 0)) > 4, "roster changes replicated (%d updates)" % int(ra.get("roster_updates", 0)))
	check(int(ra.get("max_snapshot_slots", 0)) > 2, "minion slots appeared in snapshots (%d slots)" % int(ra.get("max_snapshot_slots", 0)))
	check(int(rb.get("events_total", 0)) > 20, "presenting client consumed events")
	print("    LOOPBACK bonus modes: roster updates %d, max slots %d, events %d" % [int(ra.get("roster_updates", 0)),
		int(ra.get("max_snapshot_slots", 0)), int(rb.get("events_total", 0))])
	_no_child_errors([srv, a, b])


func test_lan_discovery_between_processes() -> void:
	u = U.new(self, "lan")
	var port: int = u.base_port
	var dport: int = port + 3
	var pl: String = u.playlist("duel.json", [DUEL])
	var srv := await _start_server("srv", u.server_sections(port, {"server": {"lan_discovery": "true", "discovery_port": dport,
		"name": "Basement Cage"}, "match": {"playlist": pl}}))
	var browser := NetLanDiscovery.new()
	check_eq(browser.start_listener(dport), OK, "browser listening")
	var found := {}
	var finder := func() -> bool:
		browser.poll()
		for s in browser.list():
			if str(s["name"]) == "Basement Cage":
				found.merge(s, true)
				return true
		return false
	var ok: bool = await u.wait_until(finder, 6.0)
	check(ok, "server process discovered by beacon (same machine)")
	if ok:
		check_eq(int(found["port"]), port, "advertised port")
		check(bool(found["compatible"]), "compatible build/content")
	browser.stop()
	_no_child_errors([srv])


func test_playlist_rotation_voting_and_restart() -> void:
	u = U.new(self, "playlist")
	var port: int = u.base_port
	var short := {"rounds": 1, "round_time": 6}
	var pl: String = u.playlist("rotation.json", [
		{"id": "a_duel", "rules": "duel", "arena": "the_gullet", "weight": 1, "rules_override": short},
		{"id": "b_ffa", "rules": "free_for_all", "arena": "the_gullet", "weight": 3, "min_players": 3, "rules_override": short},
		{"id": "c_teams", "rules": "teams_2v2", "arena": "the_gullet", "weight": 2, "rules_override": short},
		{"id": "d_missing_arena", "rules": "duel", "arena": "missing_arena", "weight": 5},
		{"id": "e_missing_rules", "rules": "no_such_rules", "arena": "the_gullet", "weight": 5}],
		{"voting": {"enabled": true, "candidates": 3}, "repeat_avoidance": 1})
	var sections: Dictionary = u.server_sections(port, {"match": {"playlist": pl, "lobby_time": 6, "results_time": 2}})
	var srv := await _start_server("srv", sections)
	var slog0: String = u.out(srv)
	check(slog0.contains("entry 4 (d_missing_arena): arena 'missing_arena' not found - skipped"), "missing arena reported")
	check(slog0.contains("entry 5 (e_missing_rules): rules preset 'no_such_rules' not found - skipped"), "missing rules reported")
	var v1: int = u.spawn("v1", u.client_args(port, "V1", "idle", ["--ready", "--vote", "0", "--stop-after-matches", "3", "--quit-after", "150"]))
	var v2: int = u.spawn("v2", u.client_args(port, "V2", "idle", ["--ready", "--vote", "1", "--stop-after-matches", "3", "--quit-after", "150"]))
	var r1: Dictionary = await u.wait_json(u.result_path("V1"), _done, 160.0)
	var results: Array = r1.get("results", [])
	check_eq(results.size(), 3, "three matches ran and advanced automatically")
	var keys: Array = []
	for r in results:
		keys.append(str(r.get("entry", {}).get("key", "")))
	for k in keys:
		check(k in ["a_duel", "b_ffa", "c_teams"], "only valid entries played (%s)" % k)
	for i in range(1, keys.size()):
		check(keys[i] != keys[i - 1], "repeat avoidance: %s then %s" % [keys[i - 1], keys[i]])
	var slog: String = u.out(srv)
	check(slog.contains("tie broken by playlist weight"), "split votes resolved by weight")
	print("    LOOPBACK playlist rotation: %s" % " -> ".join(PackedStringArray(keys)))
	# restart: the history survives and repeat avoidance continues
	await u.shutdown_server(port)
	check(await u.wait_exit(srv, 10.0), "server stopped")
	var srv2 := await _start_server("srv", sections)
	var slog2: String = u.out(srv2)
	check(slog2.contains("restored playlist state: 3 matches played"), "state restored after restart")
	_no_child_errors([v1, v2, srv2])
