extends Node
## Physics/combat probes for tuning: print numeric traces of a scripted scenario.
## Run: godot --headless --path game --fixed-fps 120 -- --probe <name> [--creature path]

var sim: MatchSim
var name_ := ""
var t := 0.0
var duration := 6.0
var _cursor := 0
var _log_every := 0.5
var _next_log := 0.0
var _hits := 0
var _dmg := 0.0


func run(probe_name: String) -> void:
	name_ = probe_name
	var main = get_parent()
	for kv in main.arg_value("--tune", "").split(",", false):
		var parts: PackedStringArray = kv.split("=")
		if parts.size() == 2:
			Tuning.values[parts[0]] = float(parts[1])
	var cpath: String = main.arg_value("--creature", "res://content/dev/dev_biped.json")
	var c := CreatureDef.load_json(cpath)
	if not c.is_valid():
		print("CREATURE ERRORS: ", "\n".join(c.errors))
		get_tree().quit(2)
		return
	var c2 := CreatureDef.load_json(main.arg_value("--creature2", cpath))
	var arena := ArenaDef.from_dict({"id": "probe", "base": "octagon", "radius": 5.0, "spawns": [[0, -float(main.arg_value("--gap", "1.1")) * 0.5, 0], [0, float(main.arg_value("--gap", "1.1")) * 0.5, 180]]})
	var s0: InputSource = null
	var s1: InputSource = null
	match probe_name:
		"stand":
			duration = 5.0
		"walk":
			duration = 6.0
			s0 = InputSource.Scripted.new([{"t0": 2.5, "t1": 4.5, "move": Vector3(1, 0, 0)}, {"t0": 4.5, "t1": 5.5, "move": Vector3(0, 0, -1)}])
		"jab":
			duration = 7.0
			s0 = InputSource.Scripted.new([{"t0": 2.4, "t1": 6.5, "press": ["light"], "every": 0.5}])
		"string":
			duration = 7.0
			s0 = InputSource.Scripted.new([{"t0": 2.4, "t1": 6.5, "press": ["light"], "every": 0.2}])
		"heavy":
			duration = 7.0
			s0 = InputSource.Scripted.new([{"t0": 2.4, "t1": 6.5, "press": ["heavy"], "every": 0.9}])
		"guard":
			duration = 7.0
			s0 = InputSource.Scripted.new([{"t0": 2.4, "t1": 6.5, "press": ["light"], "every": 0.45}])
			s1 = InputSource.Scripted.new([{"t0": 0.0, "t1": 7.0, "hold": ["guard"]}])
		"grab":
			duration = 7.0
			s0 = InputSource.Scripted.new([{"t0": 2.4, "t1": 2.5, "press": ["grab"]}, {"t0": 3.2, "t1": 3.3, "press": ["heavy"]}])
		"ability":
			duration = 8.0
			s0 = InputSource.Scripted.new([{"t0": 2.4, "t1": 2.5, "press": ["ability1"]}, {"t0": 4.0, "t1": 4.1, "press": ["ability2"]}])
		"spar":
			duration = 20.0
			s0 = InputSource.Scripted.new([{"t0": 2.3, "t1": 20, "move": "to_target", "press": ["light"], "every": 0.33}])
			s1 = InputSource.Scripted.new([{"t0": 2.3, "t1": 20, "move": "to_target", "press": ["heavy"], "every": 1.1}])
	sim = MatchSim.new()
	add_child(sim)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0}, "seed": 7,
		"fighters": [{"creature": c, "team": 0, "source": s0}, {"creature": c2, "team": 1, "source": s1}]})
	set_physics_process(true)


func _physics_process(dt: float) -> void:
	if sim == null:
		return
	t += dt
	for ev in sim.events_since(_cursor):
		_cursor = int(ev["seq"])
		if ev["type"] in ["hit", "glance", "parry", "knockdown", "grab", "throw", "ko", "burst", "effect", "guard_break"]:
			var desc: String = "%6.2fs %-10s" % [t, ev["type"]]
			if ev["type"] == "hit":
				_hits += 1
				_dmg += float(ev["damage"])
				desc += " f%d->f%d dmg=%.1f q=%.2f part=%s blocked=%s %s" % [ev["fighter"], ev["target"], ev["damage"], ev["quality"], ev["part"], ev["blocked"], ev["slot"]]
			print(desc)
	if name_ == "stand_debug" and fmod(t, 0.25) < dt and t < 2.0:
		var f0 := sim.fighters[0]
		var line := "%5.2f " % t
		for i in f0.rig.bodies.size():
			var b := f0.rig.bodies[i]
			var err := MathX.rotvec(f0.rig.target_rot[i] * b.global_basis.get_rotation_quaternion().inverse())
			line += "%s:w%.0f/e%.0f " % [f0.creature.body.segments[i].id, b.angular_velocity.length(), rad_to_deg(err.length())]
		print(line)
	if t >= _next_log:
		_next_log += _log_every
		for f in sim.fighters:
			var rb := f.rig.root()
			var up := rb.global_basis.y.dot(Vector3.UP)
			var head := f.head_pos()
			var maxw := 0.0
			for b in f.rig.bodies:
				maxw = maxf(maxw, b.angular_velocity.length())
			print("%6.2fs f%d %-9s root=(%.2f,%.2f,%.2f) h=%.2f up=%.3f head_y=%.2f maxw=%.1f hp=%.1f st=%.0f" % [t, f.index, f.state_name(), rb.global_position.x, rb.global_position.y, rb.global_position.z, f.rig.ground_dist, up, head.y, maxw, f.health, f.stamina])
	if t >= duration:
		print("PROBE %s done: hits=%d total_damage=%.1f" % [name_, _hits, _dmg])
		get_tree().quit(0)
