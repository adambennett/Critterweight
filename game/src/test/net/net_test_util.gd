extends RefCounted
## Helpers for the multi-process network tests: spawn independent headless game processes
## (dedicated server, scripted clients/hosts), write configs, read their JSON result files and
## console output, talk to the TCP admin, and clean up.
##
## Output capture: every child gets `--log-file <dir>/<label>.engine.log` (Godot writes it line by
## line), which the tests read and scan for engine/script errors. Only processes whose stdin is
## under test are started with pipes (execute_with_pipe): on Windows, children attached to pipes
## showed irregular frame pacing (94 ms loopback RTT, 21 snapshots/s instead of 30), which
## would distort network measurements.
## All traffic in these tests is LOOPBACK (127.0.0.1) on one machine; results are labelled as
## such - they say nothing about off-machine internet connectivity.

const KEEP_OUTPUT := 512 * 1024
## How long a spawned server may take to print "ready:". It is normally up in 1-2 s; on a shared
## machine saturated by parallel jobs (several full suites and stress runs at once) engine start
## alone was seen taking 10 s, and 35-41 s at the worst. Waits for any freshly spawned process to
## answer use this budget.
const SERVER_READY_S := 60.0

var tc: Node                       ## the running TestCase (for awaits)
var root := ""                     ## per-test working folder
var procs := {}                    ## pid -> {label, log, stdio, stderr, out, err}
var base_port := 0
var _spawned := {}                 ## label -> processes started with it


func _init(test_case: Node, name_: String) -> void:
	tc = test_case
	root = Paths.dir("captures").path_join("tests").path_join("net").path_join(name_)
	_wipe(root)
	DirAccess.make_dir_recursive_absolute(root)
	# distinct ports per test process so parallel runs on one machine do not collide
	base_port = 30000 + (OS.get_process_id() % 1500) * 20 + (hash(name_) & 0x7) * 2


## Removes a previous run's files (results, logs, user roots) so nothing stale is read.
static func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
		DirAccess.remove_absolute(dir.path_join(sub))


## The project folder for `--path`, or "" in an exported build: there globalize_path("res://")
## is empty and the executable carries its own pack (a `--path ""` child never wrote a file).
static func project_dir() -> String:
	return "" if OS.has_feature("template") else ProjectSettings.globalize_path("res://")


func path(rel: String) -> String:
	return root.path_join(rel)


## Spawns `game --headless --log-file .. -- <args> --user-root <root>/<label>`. `piped` = with
## stdin/stdout pipes (for console tests). Returns the pid (or -1).
func spawn(label: String, args: Array, piped := false) -> int:
	# a restarted process (same label) logs to a new file: on Windows the previous log can still be
	# locked for a moment after its process exited, and stale lines must never be read as new
	var n := int(_spawned.get(label, 0)) + 1
	_spawned[label] = n
	var logf := path("%s.engine.log" % label) if n == 1 else path("%s.%d.engine.log" % [label, n])
	if FileAccess.file_exists(logf):
		DirAccess.remove_absolute(logf)
	var full := PackedStringArray(["--headless", "--log-file", logf])
	if project_dir() != "":
		full.append_array(["--path", project_dir()])
	full.append("--")
	for a in args:
		full.append(str(a))
	full.append("--user-root")
	full.append(path(label))
	if not piped:
		var pid := OS.create_process(OS.get_executable_path(), full)
		if pid > 0:
			procs[pid] = {"label": label, "log": logf, "stdio": null, "stderr": null, "out": "", "err": ""}
		return pid
	var res := OS.execute_with_pipe(OS.get_executable_path(), full, false)
	if res.is_empty():
		return -1
	var pid2: int = res["pid"]
	procs[pid2] = {"label": label, "log": logf, "stdio": res["stdio"], "stderr": res["stderr"], "out": "", "err": ""}
	return pid2


func send_line(pid: int, line: String) -> void:
	var p: Dictionary = procs.get(pid, {})
	if p.is_empty() or p["stdio"] == null:
		return
	var io: FileAccess = p["stdio"]
	io.store_line(line)
	io.flush()


## Drains piped children (a full pipe would block them). Cheap for non-piped children.
func pump() -> void:
	for pid in procs.keys():
		var p: Dictionary = procs[pid]
		for key in ["stdio", "stderr"]:
			if p[key] == null:
				continue
			var io: FileAccess = p[key]
			for i in 8:
				var chunk := io.get_buffer(65536)
				if chunk.is_empty():
					break
				var field := "out" if key == "stdio" else "err"
				var s := str(p[field]) + chunk.get_string_from_utf8()
				if s.length() > KEEP_OUTPUT:
					s = s.substr(s.length() - KEEP_OUTPUT)
				p[field] = s


## Everything the child printed so far (engine log file, plus the stdout pipe when piped).
func out(pid: int) -> String:
	pump()
	var p: Dictionary = procs.get(pid, {})
	if p.is_empty():
		return ""
	var logf := str(p["log"])
	var text := FileAccess.get_file_as_string(logf) if FileAccess.file_exists(logf) else ""
	return text + str(p["out"]) + str(p["err"])


## Engine/script error lines printed by a child so far (excluding `allowed` substrings).
func errors(pid: int, allowed: Array = []) -> Array:
	var found: Array = []
	for line in out(pid).split("\n"):
		if line.contains("SCRIPT ERROR") or line.begins_with("ERROR:") or line.contains("[ERROR]"):
			var ok := false
			for a in allowed:
				if line.contains(str(a)):
					ok = true
			if not ok and found.size() < 50:
				found.append(line.strip_edges())
	return found


func running(pid: int) -> bool:
	return pid > 0 and OS.is_process_running(pid)


func exit_code(pid: int) -> int:
	return OS.get_process_exit_code(pid)


func kill_all() -> void:
	pump()
	for pid in procs.keys():
		if OS.is_process_running(int(pid)):
			OS.kill(int(pid))
	for pid in procs.keys():
		var p: Dictionary = procs[pid]
		if str(p["out"]) != "" or str(p["err"]) != "":
			var f := FileAccess.open(path("%s_%d.pipe.txt" % [p["label"], int(pid)]), FileAccess.WRITE)
			if f:
				f.store_string(str(p["out"]) + "\n--- stderr ---\n" + str(p["err"]))
				f.close()
		for key in ["stdio", "stderr"]:
			if p[key] != null:
				(p[key] as FileAccess).close()
	procs.clear()


## Writes a server config (INI) from {section: {key: value}}.
func write_cfg(rel: String, sections: Dictionary) -> String:
	var lines := PackedStringArray(["# generated by the network tests"])
	for sec in sections:
		lines.append("[%s]" % sec)
		var d: Dictionary = sections[sec]
		for k in d:
			lines.append("%s = %s" % [k, str(d[k])])
	var p := path(rel)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return p


func write_json(rel: String, data) -> String:
	var p := path(rel)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return p


static func read_json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var text := FileAccess.get_file_as_string(p)
	if text.strip_edges() == "":
		return {}
	# JSON.parse() (unlike parse_string) stays quiet: a child may be rewriting the file right now
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	return j.data if typeof(j.data) == TYPE_DICTIONARY else {}


## Waits until `pred.call(result_dict)` is true for the JSON file at `p` (or timeout).
func wait_json(p: String, pred: Callable, timeout_s: float) -> Dictionary:
	var until := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var last := {}
	while Time.get_ticks_msec() < until:
		pump()
		var d := read_json(p)
		if not d.is_empty():
			last = d
			if pred.call(d):
				return d
		await tc.get_tree().create_timer(0.25).timeout
	var final := read_json(p)    # one last read after the deadline (a busy runner can wake late)
	return final if not final.is_empty() else last


func wait_until(pred: Callable, timeout_s: float) -> bool:
	var until := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < until:
		pump()
		if pred.call():
			return true
		await tc.get_tree().create_timer(0.2).timeout
	# one last look: a busy runner can wake up after the deadline with the condition already met
	pump()
	return bool(pred.call())


func wait_exit(pid: int, timeout_s: float) -> bool:
	return await wait_until(func() -> bool: return not OS.is_process_running(pid), timeout_s)


func sleep(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		pump()
		await tc.get_tree().create_timer(0.2).timeout


## One TCP admin session (127.0.0.1): sends each line, collects everything received.
func admin(port: int, lines: Array, per_line_s := 1.5) -> String:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host("127.0.0.1", port) != OK:
		return "connect failed"
	var until := Time.get_ticks_msec() + 4000
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < until:
		tcp.poll()
		await tc.get_tree().create_timer(0.05).timeout
	var text := ""
	for l in lines:
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		tcp.put_data((str(l) + "\n").to_utf8_buffer())
		var t_end := Time.get_ticks_msec() + int(per_line_s * 1000.0)
		while Time.get_ticks_msec() < t_end:
			tcp.poll()
			# the server may close after a command (shutdown, refused token): reading a closed
			# socket only prints an engine error, and nothing unread is lost (poll keeps the
			# connection open while received bytes are waiting)
			if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				break
			var n := tcp.get_available_bytes()
			if n > 0:
				text += tcp.get_utf8_string(n)
			await tc.get_tree().create_timer(0.05).timeout
	tcp.disconnect_from_host()
	return text


## Command line for net_test_client.gd connecting to 127.0.0.1:port. The result file is
## <name>.json unless `result_name` is given (e.g. a second process using the same player name).
func client_args(port: int, name_: String, script := "idle", extra: Array = [], result_name := "") -> Array:
	var a: Array = ["--net-client", "--connect", "127.0.0.1:%d" % port, "--name", name_, "--script", script,
		"--result", result_path(result_name if result_name != "" else name_)]
	a.append_array(extra)
	return a


func result_path(name_: String) -> String:
	return path("%s.json" % name_.to_lower())


## Minimal dedicated-server config sections for tests (TCP admin on port+1 with a test token).
func server_sections(port: int, overrides: Dictionary = {}) -> Dictionary:
	var s := {"server": {"name": "Test Server", "port": port, "max_players": 4, "max_spectators": 2,
		"lan_discovery": "false", "timeout": 6, "rejoin_grace": 30, "stats_interval": 5, "kick_ban_seconds": 60},
		"match": {"lobby_time": 4, "results_time": 2, "bots": "true", "bot_difficulty": "regular"},
		"admin": {"console": "true", "port": port + 1, "token": admin_token()}}
	for sec in overrides:
		if not s.has(sec):
			s[sec] = {}
		var d: Dictionary = overrides[sec]
		for k in d:
			s[sec][k] = d[k]
	return s


static func admin_token() -> String:
	return "net-tests-admin-token-0123456789"


## Graceful stop through the TCP admin (port+1).
func shutdown_server(port: int) -> String:
	return await admin(port + 1, ["AUTH " + admin_token(), "shutdown"])


## Playlist file with one or more entries (short rounds unless overridden).
func playlist(rel: String, entries: Array, extra: Dictionary = {}) -> String:
	var d := {"id": rel.get_basename(), "name": "Test " + rel.get_basename(), "entries": entries}
	for k in extra:
		d[k] = extra[k]
	return write_json(rel, d)
