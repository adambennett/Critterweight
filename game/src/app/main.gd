extends Node
## Process entry point. Dispatches on command-line user arguments (after `--`):
##   (none)                  normal game (title screen)
##   --test [filter]         run automated tests headless, exit code = failures
##   --tutorial [n]          start Granny's tutorial at exercise n (0-based) [--creature id]
##   --probe <name>          run a physics/combat probe and print metrics
##   --server [--config p]   dedicated server (see docs/SERVER.md)
##   --lab-worker <job>      AI Lab training worker (spawned by the Lab UI)
##   --autotest <scenario>   scripted runtime verification of the real game UI
##   --bench <scene>         performance capture

var args: PackedStringArray


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	# integration points other owners' menus call into
	TutorialHook.launcher = Callable(Tutorial, "start_lesson")
	if not args.has("--test") and not args.has("--server") and not args.has("--lab-worker") and not args.has("--check"):
		UiNav.ensure()   # UI-only actions (LB/RB, Y, X) and focus guard exist even when no menu ran first
	var mode := "game"
	if args.has("--test"):
		mode = "test"
	elif args.has("--probe"):
		mode = "probe"
	elif args.has("--sandbox"):
		mode = "sandbox"
	elif args.has("--tutorial"):
		mode = "tutorial"
	elif args.has("--check"):
		mode = "check"
	elif args.has("--server"):
		mode = "server"
	elif args.has("--lab-worker"):
		mode = "lab_worker"
	elif args.has("--autotest"):
		mode = "autotest"
	elif args.has("--bench"):
		mode = "bench"
	if args.has("--capture"):
		_setup_capture()
	call_deferred("_start", mode)


func _exit_tree() -> void:
	# static Callables outliving their scripts crash the engine at exit
	TutorialHook.launcher = Callable()


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
		"tutorial":
			Tutorial.start(int(arg_value("--tutorial", "0")), arg_value("--creature", ""))
		"check":
			_check_scripts()
		"server":
			# Dedicated server (owned by src/net): headless, no UI.
			Net.call("start_dedicated_from_cli", args)
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


## Normal game boot: title screen (owned by src/ui). `--screen <name>` opens a screen directly
## (captures, runtime checks).
func _boot_game() -> void:
	var direct := arg_value("--screen", "")
	if direct != "" and App.has_screen(direct):
		App.goto(direct)
	elif App.has_screen("title"):
		App.goto("title")
	else:
		_start_sandbox()


## Dev sandbox: player (or bot with --autoplay) vs bots.
##   --rules <preset id> (default duel)   --arena <arena id> (default the_gullet)
##   --n <fighters> (default by preset)  --creature/--creature2 <json path or creature id>
##   --spectate (with --autoplay): auto-director camera + spectator overlay
func _start_sandbox() -> void:
	var c1 = _sandbox_creature(arg_value("--creature", "dev_biped"))
	var c2 = _sandbox_creature(arg_value("--creature2", arg_value("--creature", "dev_biped")))
	var rules_id := arg_value("--rules", "duel")
	var preset := Content.get_entry("rules", rules_id)
	var n := int(arg_value("--n", "0"))
	if n <= 0:
		var pl: Array = preset.get("players", [2, 2])
		n = int(pl[0]) if pl.size() > 0 else 2
		n = maxi(n, 2)
	var teams := int(preset.get("teams", 2))
	var fighters := []
	for i in n:
		var kind := "bot"
		if i == 0 and not args.has("--autoplay"):
			kind = "player"
		var team := i
		if str(preset.get("format", "")) in ["teams", "tag", "coop"]:
			team = i % maxi(teams, 1) if str(preset.get("format", "")) != "coop" else 0
		fighters.append({"creature": c1 if i == 0 else c2, "team": team, "kind": kind,
			"difficulty": arg_value("--difficulty", "regular") if i > 0 else arg_value("--p1diff", "pro"),
			"name": "Player" if kind == "player" else "Bot %d" % i})
	var cfg := {"arena": arg_value("--arena", "the_gullet"), "rules": rules_id, "seed": int(arg_value("--seed", "11")), "fighters": fighters}
	if args.has("--spectate"):
		# AI-vs-AI with the auto-director camera and spectator controls (same path as the menu)
		cfg["spectate"] = true
		MatchFlow.launch(cfg)
	else:
		App.start_match(cfg)


func _sandbox_creature(spec: String):
	if spec.ends_with(".json"):
		return CreatureDef.load_json(spec)
	var c := Content.creature(spec)
	return c if c else Content.creature("dev_biped")


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
