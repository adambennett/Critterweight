extends Node
## Process entry point. Dispatches on command-line user arguments (after `--`):
##   (none)                  normal game (title screen)
##   --test [filter]         run automated tests headless, exit code = failures
##   --probe <name>          run a physics/combat probe and print metrics
##   --server [--config p]   dedicated server (see docs/SERVER.md)
##   --lab-worker <job>      AI Lab training worker (spawned by the Lab UI)
##   --autotest <scenario>   scripted runtime verification of the real game UI
##   --bench <scene>         performance capture

var args: PackedStringArray


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	var mode := "game"
	if args.has("--test"):
		mode = "test"
	elif args.has("--probe"):
		mode = "probe"
	elif args.has("--sandbox"):
		mode = "sandbox"
	elif args.has("--check"):
		mode = "check"
	elif args.has("--server"):
		mode = "server"
	elif args.has("--net-client"):
		mode = "net_client"
	elif args.has("--connect") or args.has("--host"):
		mode = "net"
	elif args.has("--lab-worker"):
		mode = "lab_worker"
	elif args.has("--autotest"):
		mode = "autotest"
	elif args.has("--bench"):
		mode = "bench"
	if args.has("--capture"):
		_setup_capture()
	call_deferred("_start", mode)


func arg_value(flag: String, fallback := "") -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


func _start(mode: String) -> void:
	match mode:
		"test":
			var runner = load("res://src/test/test_runner.gd").new()
			add_child(runner)
			runner.run(arg_value("--test", ""))
		"probe":
			var probe = load("res://src/test/probes.gd").new()
			add_child(probe)
			probe.run(arg_value("--probe", "stand"))
		"sandbox":
			_start_sandbox()
		"check":
			_check_scripts()
		"server":
			# Dedicated server (owned by src/net): headless, no UI.
			Net.call("start_dedicated_from_cli", args)
		"net_client":
			# scripted headless client/host used by the multi-process network tests (src/test/net)
			var nc = load("res://src/test/net/net_test_client.gd").new()
			add_child(nc)
			nc.call("run", args)
		"net":
			# --connect <host:port> / --host: join or host from the command line (src/net)
			Net.call("start_from_cli", args)
		"lab_worker":
			var worker = load("res://src/lab/lab_worker.gd").new()
			add_child(worker)
			worker.call("run_from_cli", args)
		"autotest":
			var at = load("res://src/test/autotest.gd").new()
			add_child(at)
			at.call("run", arg_value("--autotest", ""), args)
		"bench":
			var bench = load("res://src/test/bench.gd").new()
			add_child(bench)
			bench.call("run", arg_value("--bench", "busy"), args)
		_:
			_boot_game()


## Normal game boot: title screen (owned by src/ui).
func _boot_game() -> void:
	if App.has_screen("title"):
		App.goto("title")
	else:
		_start_sandbox()


## Dev sandbox: player (or bot with --autoplay) vs bot in the primary cage.
func _start_sandbox() -> void:
	var cpath := arg_value("--creature", "res://content/dev/dev_biped.json")
	var c := CreatureDef.load_json(cpath)
	var c2 := CreatureDef.load_json(arg_value("--creature2", cpath))
	var arena := ArenaDef.from_dict({"id": "sandbox", "name": "The Can", "base": "octagon", "radius": 5.0, "theme": arg_value("--theme", "can"),
		"spawns": [[0, -1.6, 0], [0, 1.6, 180]]})
	var scene := MatchScene.new()
	add_child(scene)
	var p_kind := "bot" if args.has("--autoplay") else "player"
	scene.start({"arena": arena, "rules": {"rounds": 3, "round_time": 99}, "seed": 11,
		"fighters": [{"creature": c, "team": 0, "kind": p_kind, "difficulty": arg_value("--p1diff", "pro"), "name": "Player"},
			{"creature": c2, "team": 1, "kind": "bot", "difficulty": arg_value("--difficulty", "regular"), "name": "Bot"}]})


## --capture <png path> [--capture-at seconds] [--capture-count n --capture-every s]: saves
## screenshots of the real rendered frame, then quits. Used for runtime verification evidence.
func _setup_capture() -> void:
	var at := float(arg_value("--capture-at", "4.0"))
	var count := int(arg_value("--capture-count", "1"))
	var every := float(arg_value("--capture-every", "1.0"))
	var path := arg_value("--capture", "user://capture.png")
	for k in count:
		var t := get_tree().create_timer(at + k * every, true, false, true)
		t.timeout.connect(_do_capture.bind(path, k, count))


func _do_capture(path: String, k: int, count: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := path if count == 1 else path.get_basename() + "_%02d.png" % k
	img.save_png(out)
	print("CAPTURED ", out, " ", img.get_size())
	if k == count - 1:
		get_tree().quit(0)


## --check: loads every script under res://src (with autoloads present) and reports failures.
func _check_scripts() -> void:
	var files := _collect_scripts("res://src")
	var failures := 0
	for f in files:
		var s = load(f)
		if s == null or not (s as GDScript).can_instantiate():
			print("FAIL ", f)
			failures += 1
	print("checked %d scripts, %d failures" % [files.size(), failures])
	get_tree().quit(failures)


func _collect_scripts(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := dir.path_join(n)
		if d.current_is_dir():
			out.append_array(_collect_scripts(p))
		elif n.ends_with(".gd") or n.ends_with(".gd.remap"):
			out.append(p.trim_suffix(".remap"))
		n = d.get_next()
	return out
