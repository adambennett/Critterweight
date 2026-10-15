class_name NetAdminConsole
extends RefCounted
## Dedicated-server administration commands, shared by the stdin console and the
## token-authenticated TCP admin (127.0.0.1 only). A fixed whitelist of commands - there is no
## way to evaluate code, run programs or touch arbitrary files through it.

const HELP := """commands:
  status                      server, match and performance summary
  players                     connected/reserved players and spectators
  kick <id|name> [reason]     remove a player (temporary ban: kick_ban_seconds)
  next                        start now (lobby) / end the match (match) / continue (results)
  playlist [show]             entries, validation errors, history
  playlist reload             re-read and re-validate the current playlist
  playlist set <id|path>      switch to another playlist (applies from the next vote)
  say <text>                  broadcast a server notice
  shutdown [--restart] [msg]  notify clients, save state and stop
  help                        this text"""

var dedicated   ## NetDedicated


func _init(owner_) -> void:
	dedicated = owner_


func execute(line: String, source := "console") -> String:
	var text := line.strip_edges()
	if text == "":
		return ""
	if text.length() > 512:
		return "error: command too long"
	var parts := text.split(" ", false)
	var cmd := parts[0].to_lower()
	var rest := text.substr(parts[0].length()).strip_edges()
	var server: NetServer = dedicated.server
	if server == null:
		return "error: server not running"
	Log.i("admin", "[%s] %s" % [source, text if not cmd.begins_with("auth") else "auth ***"])
	match cmd:
		"help", "?":
			return HELP
		"status":
			return _status(server)
		"players":
			return _players(server)
		"kick":
			if parts.size() < 2:
				return "usage: kick <id|name> [reason]"
			var p := server.find_player(parts[1])
			if p == null:
				return "no player '%s'" % parts[1]
			var reason := rest.substr(parts[1].length()).strip_edges()
			if reason == "":
				reason = "kicked by admin"
			return "kicked %d '%s'" % [p.id, p.name] if server.kick(p.id, reason) else "cannot kick '%s'" % parts[1]
		"next", "skip":
			return server.skip("admin")
		"playlist":
			var sub := parts[1].to_lower() if parts.size() > 1 else "show"
			match sub:
				"show":
					return _playlist(server)
				"reload":
					return dedicated.reload_playlist("")
				"set":
					if parts.size() < 3:
						return "usage: playlist set <id|path>"
					return dedicated.reload_playlist(rest.substr(3).strip_edges())
			return "usage: playlist [show|reload|set <id|path>]"
		"say":
			if rest == "":
				return "usage: say <text>"
			server.notice("[server] " + NetProtocol.clean_text(rest, 300))
			return "sent"
		"shutdown", "quit", "exit", "stop":
			var restart := rest.begins_with("--restart")
			var msg := rest.substr(9).strip_edges() if restart else rest
			dedicated.request_shutdown(msg if msg != "" else ("Server restarting." if restart else "Server shutting down."), restart)
			return "shutting down"
	return "unknown command '%s' (try: help)" % cmd


func _status(server: NetServer) -> String:
	var s := server.status()
	var lines := PackedStringArray()
	lines.append("%s | phase %s | up %ds | players %d/%d (+%d reserved) | spectators %d" % [s["name"], s["phase"],
		int(s["uptime_s"]), s["players"], int(s["max_players"]), s["reserved"], s["spectators"]])
	lines.append("match %d %s | fighters %d | tick %d | playlist %s (%d played)" % [s["match_id"], s["entry"], s["fighters"],
		s["tick"], s["playlist"], s["matches_played"]])
	lines.append("sim %.2f ms avg (1 s window %.2f avg / %.2f max) | physics frame %.2f ms | net %.3f ms/tick" % [float(s["sim_ms_avg"]),
		float(s["tick_ms_avg_1s"]), float(s["tick_ms_max_1s"]), float(s["physics_frame_ms_avg"]), float(s["net_ms_avg"])])
	lines.append("traffic out %.1f KB/s in %.1f KB/s | snapshot %.0f B avg | mem %.1f MB | objects %d nodes %d orphans %d" % [
		float(s["out_kbps"]), float(s["in_kbps"]), float(s["snapshot_bytes_avg"]), float(s["mem_static_mb"]), s["objects"], s["nodes"], s["orphans"]])
	return "\n".join(lines)


func _players(server: NetServer) -> String:
	var rows := server.players_public()
	if rows.is_empty():
		return "no players"
	var lines := PackedStringArray()
	for r in rows:
		lines.append("#%d %-20s %s slot %d team %d fighter %d ping %d ms loss %.0f%% %s%s" % [int(r["id"]), str(r["name"]),
			"spectator" if r["spectator"] else "player   ", int(r["slot"]), int(r["team"]), int(r["fighter"]), int(r["ping"]),
			float(r["loss"]) * 100.0, "" if r["connected"] else "[disconnected, slot reserved] ", str(r["address"])])
	return "\n".join(lines)


func _playlist(server: NetServer) -> String:
	var pl := server.playlist
	if pl == null:
		return "no playlist"
	var s := pl.summary()
	var lines := PackedStringArray()
	lines.append("playlist '%s' (%s) from %s: %d valid, %d invalid, voting %s (%d candidates), repeat avoidance %d" % [
		s["name"], s["id"], s["source"], s["valid"], s["invalid"], "on" if s["voting"] else "off", s["candidates"], s["repeat_avoidance"]])
	for e in s["entries"]:
		lines.append("  %2d. %-28s weight %-5s %s" % [int(e["index"]) + 1, str(e["key"]), str(e["weight"]),
			"ok" if e["valid"] else "INVALID: " + "; ".join(PackedStringArray(e["errors"]))])
	for err in s["errors"]:
		lines.append("  ! " + str(err))
	lines.append("history: %s" % ", ".join(PackedStringArray(s["history"])))
	return "\n".join(lines)
