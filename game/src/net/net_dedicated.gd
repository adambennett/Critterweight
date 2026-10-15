class_name NetDedicated
extends Node
## Headless dedicated server process controller (`--server [--config <path>]`, docs/SERVER.md):
## config parsing/validation, playlist loading + validation + persisted state, the NetServer,
## the stdin admin console (reader thread), the optional 127.0.0.1 token-authenticated TCP admin,
## a periodic status file (<user>/server/status.json), bounded resources and graceful shutdown.
## Exit codes: 0 normal shutdown, 2 invalid configuration, 3 network start failure.

const STATUS_EVERY_MS := 5000
const FALLBACK_PLAYLIST := {"id": "builtin_fallback", "name": "Built-in fallback",
	"entries": [{"rules": "duel", "arena": "the_gullet", "weight": 1}]}

var server: NetServer = null
var cfg := {}
var console: NetAdminConsole = null
var tcp: NetAdminTcp = null
var config_path := ""
var _args := PackedStringArray()
var _stdin_thread: Thread = null
var _stdin_mutex := Mutex.new()
var _stdin_lines: Array[String] = []
var _stdin_done := false
var _stdin_stop := false
var _stdin_type := 0
var _status_ms := 0
var _shutting_down := false
var _shutdown_at_ms := 0
var _shutdown_msg := ""
var _shutdown_restart := false
var _close_started := false


func run(args: PackedStringArray) -> int:
	_args = args
	name = "NetDedicated"
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var i := args.find("--config")
	if i >= 0 and i + 1 < args.size():
		config_path = args[i + 1]
		var parsed := NetServerConfig.parse_file(config_path)
		cfg = parsed["cfg"]
		errors.append_array(parsed["errors"])
		warnings.append_array(parsed["warnings"])
	else:
		cfg = NetServerConfig.defaults()
		warnings.append("no --config given: running with built-in defaults (see game/server/server.example.cfg)")
	NetServerConfig.apply_cli(cfg, args, errors)
	Log.level = ["debug", "info", "warn", "error"].find(str(cfg["log_level"]))
	for w in warnings:
		Log.w("server", w)
	if not errors.is_empty():
		for e in errors:
			Log.e("server", "config: " + e)
		printerr("Server configuration is invalid; not starting. Fix the errors above.")
		return 2
	var mod_err := _apply_mods()
	if mod_err != "":
		Log.e("server", "mods: " + mod_err)
		printerr("Server mods could not be loaded; not starting. %s" % mod_err)
		return 2
	Engine.physics_ticks_per_second = int(cfg["tick_rate"])
	Engine.max_fps = int(cfg["tick_rate"])
	Engine.max_physics_steps_per_frame = 8
	var playlist := _load_playlist(str(cfg["playlist"]))
	server = NetServer.new()
	add_child(server)
	var err := server.start(cfg, true, args)
	if err != OK:
		Log.e("server", "cannot start: %s" % server.transport.last_error)
		printerr("Server could not start: %s" % server.transport.last_error)
		return 3
	server.set_playlist(playlist)
	console = NetAdminConsole.new(self)
	if bool(cfg["admin_console"]):
		_start_stdin()
	if int(cfg["admin_port"]) > 0:
		tcp = NetAdminTcp.new()
		var terr := tcp.start(int(cfg["admin_port"]), str(cfg["admin_token"]))
		if terr != OK:
			Log.e("server", "TCP admin could not listen on 127.0.0.1:%d (%s)" % [int(cfg["admin_port"]), error_string(terr)])
			tcp = null
		else:
			Log.i("server", "TCP admin listening on 127.0.0.1:%d (token required)" % int(cfg["admin_port"]))
	Log.i("server", "ready: '%s' on UDP %d, %d players max, playlist '%s' (%d valid entries)%s" % [cfg["name"],
		int(cfg["port"]), int(cfg["max_players"]), playlist.display_name, playlist.valid_entries().size(),
		", password protected" if str(cfg["password"]) != "" else ""])
	_write_status("running")
	return 0


## Servers load exactly the mods their configuration names (server.mods / --mods), from
## server.mods_dir (--mods-dir) when given, else from the user mods folder of this server's data
## directory - never a player's mod set. Mods are data only (docs/MODDING.md). Returns "" or why
## the configured set cannot be loaded (the server then refuses to start).
func _apply_mods() -> String:
	var want := NetServerConfig.mod_ids(cfg)
	var dir := str(cfg.get("mods_dir", ""))
	if dir != "":
		if not DirAccess.dir_exists_absolute(dir):
			return "server.mods_dir '%s' does not exist" % dir
		Mods.use_root(dir)
	var have: Array = Mods.load_order.duplicate()
	var sorted_want: Array = []
	sorted_want.append_array(want)
	sorted_want.sort()
	have.sort()
	if dir != "" or sorted_want != have:
		var res := Mods.enable_only(want)
		if not (res["missing"] as Array).is_empty():
			return "not installed in %s: %s" % [Mods.mods_dir(), ", ".join(PackedStringArray(res["missing"]))]
	var problems: Array[String] = []
	for id in want:
		if not Mods.load_order.has(id):
			var why: Array = Mods.load_report.get(id, [])
			problems.append("%s (%s)" % [id, "; ".join(PackedStringArray(why)) if not why.is_empty() else ("safe mode" if Mods.safe_mode else "not loaded")])
	if not problems.is_empty():
		return "cannot load: %s" % ", ".join(PackedStringArray(problems))
	var pk: Array[String] = []
	for p in Content.package_list():
		pk.append("%s %s%s" % [p["id"], p["version"], " (client only)" if bool(p["client_only"]) else ""])
	Log.i("server", "content: %s; gameplay hash %s" % [", ".join(PackedStringArray(pk)), Content.content_hash().substr(0, 12)])
	return ""


func _load_playlist(ref: String) -> NetPlaylist:
	var p := NetPlaylist.load_ref(ref)
	if p.errors.is_empty() or not p.entries.is_empty():
		p.validate()
	for e in p.errors:
		Log.w("playlist", e)
	if p.valid_entries().is_empty():
		Log.e("playlist", "playlist '%s' is unusable; falling back to a built-in duel rotation" % ref)
		var fb := NetPlaylist.from_dict(FALLBACK_PLAYLIST, "builtin")
		fb.validate()
		p = fb
	Log.i("playlist", p.load_state())
	return p


## Admin `playlist reload` / `playlist set <ref>`.
func reload_playlist(ref: String) -> String:
	var target := ref if ref != "" else str(cfg["playlist"])
	var p := NetPlaylist.load_ref(target)
	p.validate()
	if p.valid_entries().is_empty():
		var msg := "playlist '%s' not applied: %s" % [target, "; ".join(PackedStringArray(p.errors))]
		Log.w("playlist", msg)
		return msg
	p.load_state()
	cfg["playlist"] = target
	server.set_playlist(p)
	for e in p.errors:
		Log.w("playlist", e)
	return "playlist '%s' loaded: %d valid, %d invalid entries (applies from the next vote)" % [p.display_name,
		p.valid_entries().size(), p.entries.size() - p.valid_entries().size()]


# =====================================================================================
# stdin console (reader thread; lines are executed on the main thread)
# =====================================================================================

func _start_stdin() -> void:
	var t := OS.get_stdin_type()
	if t != OS.STD_HANDLE_CONSOLE and t != OS.STD_HANDLE_PIPE and t != OS.STD_HANDLE_FILE:
		Log.i("server", "admin console disabled: no usable stdin")
		return
	_stdin_type = t
	_stdin_thread = Thread.new()
	_stdin_thread.start(_stdin_loop)
	Log.i("server", "admin console ready on stdin (type 'help')")


## Reader thread. Consoles block until a line is typed; pipes may be non-blocking (empty reads
## just mean "nothing yet"); a redirected file ends with repeated empty reads (EOF).
func _stdin_loop() -> void:
	var empties := 0
	var pending := ""
	while true:
		_stdin_mutex.lock()
		var stop_now := _stdin_stop
		_stdin_mutex.unlock()
		if stop_now:
			break
		var chunk := OS.read_string_from_stdin(1024)
		if chunk == "":
			empties += 1
			if _stdin_type == OS.STD_HANDLE_FILE and empties > 25:
				break
			OS.delay_msec(50)
			continue
		empties = 0
		# reads return whole lines with the final line break removed: a chunk ends a line
		pending += chunk.replace("\r", "")
		if not pending.ends_with("\n"):
			pending += "\n"
		var stop := false
		while pending.contains("\n"):
			var nl := pending.find("\n")
			var line := pending.substr(0, nl).strip_edges()
			pending = pending.substr(nl + 1)
			if line == "":
				continue
			_stdin_mutex.lock()
			if _stdin_lines.size() < 64:
				_stdin_lines.append(line.substr(0, 512))
			_stdin_mutex.unlock()
			var cmd := line.split(" ", false)[0].to_lower() if line.split(" ", false).size() > 0 else ""
			if cmd in ["shutdown", "quit", "exit", "stop"]:
				stop = true
		if stop:
			break
		if pending.length() > 4096:
			pending = ""
	_stdin_mutex.lock()
	_stdin_done = true
	_stdin_mutex.unlock()


func _process(_dt: float) -> void:
	if server == null:
		return
	_stdin_mutex.lock()
	var lines := _stdin_lines.duplicate()
	_stdin_lines.clear()
	_stdin_mutex.unlock()
	for l in lines:
		var out := console.execute(l, "console")
		if out != "":
			print(out)
	if tcp:
		tcp.poll(console)
	var now := Time.get_ticks_msec()
	if now - _status_ms >= STATUS_EVERY_MS and not _shutting_down:
		_status_ms = now
		_write_status("running")
	if _shutting_down and now >= _shutdown_at_ms and not _close_started:
		_close_started = true
		_begin_close()


func _write_status(state: String) -> void:
	var s := server.status() if server else {}
	s["state"] = state
	s["config"] = config_path
	s["port"] = cfg.get("port", 0)
	s["pid"] = OS.get_process_id()
	s["time"] = Time.get_datetime_string_from_system(true)
	s["log"] = Log.log_path()
	var f := FileAccess.open(Paths.file("server", "status.json.tmp"), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(s, "\t"))
	f.close()
	var final := Paths.file("server", "status.json")
	if FileAccess.file_exists(final):
		DirAccess.remove_absolute(final)
	DirAccess.rename_absolute(Paths.file("server", "status.json.tmp"), final)


## Graceful shutdown: clients are told why (and whether a restart is expected), playlist state
## is saved, then the process exits. Used by the console, TCP admin and Net.shutdown().
func request_shutdown(message: String, restarting := false) -> void:
	if _shutting_down:
		return
	_shutting_down = true
	_shutdown_msg = message
	_shutdown_restart = restarting
	_shutdown_at_ms = Time.get_ticks_msec() + 100
	Log.w("server", "shutdown requested: %s%s" % [message, " (restart expected)" if restarting else ""])


## Notifies clients and waits (without blocking the loop) until they acknowledged or 3 s passed.
func _begin_close() -> void:
	if server == null or server.is_closed():
		_finish_shutdown(0, "")
		return
	if server.playlist:
		server.playlist.save_state()
	server.closed.connect(_finish_shutdown, CONNECT_ONE_SHOT)
	server.close_async(NetProtocol.R_SHUTDOWN, _shutdown_msg, _shutdown_restart, 3000)


func _finish_shutdown(_code: int, _msg: String) -> void:
	set_process(false)
	if tcp:
		tcp.stop()
	_write_status("stopped")
	Log.w("server", "server stopped")
	var reader_blocked := false
	if _stdin_thread != null:
		_stdin_mutex.lock()
		_stdin_stop = true
		_stdin_mutex.unlock()
		# pipes/files notice the stop flag within ~50 ms; an interactive console read cannot be
		# interrupted until Enter is pressed
		for i in 10:
			_stdin_mutex.lock()
			var done := _stdin_done
			_stdin_mutex.unlock()
			if done:
				break
			OS.delay_msec(30)
		_stdin_mutex.lock()
		reader_blocked = not _stdin_done
		_stdin_mutex.unlock()
		if not reader_blocked:
			_stdin_thread.wait_to_finish()
			_stdin_thread = null
	if reader_blocked:
		# State is saved and the log flushed (warning line above); end the process directly
		# (exit code 0 on Windows) instead of waiting for a key press on the console.
		OS.kill(OS.get_process_id())
		return
	get_tree().quit(0)
