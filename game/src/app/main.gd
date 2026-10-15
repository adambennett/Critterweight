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
		_:
			pass
