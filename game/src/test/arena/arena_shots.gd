extends Node
## Visual evidence runner for arenas and the arena editor (windowed, not a test).
## Run:  godot --path game --resolution 1600x900 res://src/test/arena/arena_shots.tscn -- \
##         --arena arena_crusher [--fighters 4] [--hazard-at 8.9] [--cam overview|match|low]
##         [--editor] [--out <file.jpg|png>] [--at 4.0] [--size 1600x900]
##         [--when wind_gust:telegraph:0.4]   (after --at, wait until that hazard state is live)
## Starts a real local match (bots) on the arena (or the arena editor screen with --editor),
## optionally fast-forwards the arena hazard clock so a telegraph/active state is on screen,
## then saves the rendered frame resized to --size and quits.

var args: PackedStringArray
var scene: MatchScene
var cam: Camera3D


func _arg(flag: String, fallback := "") -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	call_deferred("_start")


func _start() -> void:
	var at := float(_arg("--at", "4.0"))
	if args.has("--gallery"):
		_start_gallery()
	elif args.has("--editor"):
		var params := {}
		if _arg("--arena") != "":
			params["example"] = _arg("--arena")
		App.goto("arena_editor", params)
		var scr = App.top_screen()
		if scr and scr.has_method("debug_setup"):
			scr.call("debug_setup", _arg("--editor-script", ""))
	else:
		_start_match()
	await get_tree().create_timer(at, true, false, true).timeout
	var when := _arg("--when")   # "<hazard type>:<phase>[:<min seconds into phase>]"
	if when != "" and scene != null:
		var w := when.split(":")
		var limit := Time.get_ticks_msec() + 30000
		while not _hazard_in(w[0], w[1] if w.size() > 1 else "active", float(w[2]) if w.size() > 2 else 0.0):
			if Time.get_ticks_msec() > limit:
				push_error("--when %s never happened" % when)
				break
			await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var sz := _arg("--size", "1600x900").split("x")
	img.resize(int(sz[0]), int(sz[1]), Image.INTERPOLATE_LANCZOS)
	var out := _arg("--out", "user://arena_shot.jpg")
	if out.ends_with(".png"):
		img.save_png(out)
	else:
		img.save_jpg(out, 0.9)
	print("SHOT ", out, " ", img.get_size())
	get_tree().quit(0)


func _start_match() -> void:
	var id := _arg("--arena", "arena_gullet")
	var a := Content.arena(id)
	if a == null:
		push_error("unknown arena %s" % id)
		a = Content.arena("arena_gullet")
	if _arg("--variant") != "":
		var d := a.to_dict()
		d["variant"] = _arg("--variant")
		d["id"] = a.id
		if not d.has("base_def") and a.defines_base:
			d["base_def"] = a.base_def
		a = ArenaDef.from_dict(d)
	var n := int(_arg("--fighters", "2"))
	var c := Content.creature("dev_biped")
	var fs := []
	for i in n:
		fs.append({"creature": c, "team": i if not args.has("--teams") else i % 2, "kind": "bot", "difficulty": "pro", "name": "Bot %d" % (i + 1)})
	scene = MatchScene.new()
	add_child(scene)
	scene.start({"arena": a, "rules": {"rounds": 3, "round_time": 99}, "seed": int(_arg("--seed", "11")), "fighters": fs})
	var hz_at := float(_arg("--hazard-at", "-1"))
	if hz_at >= 0.0:
		_fast_forward.call_deferred(hz_at)
	var mode := _arg("--cam", "overview")
	if mode != "match":
		cam = Camera3D.new()
		cam.fov = 52.0
		scene.add_child(cam)
		var ext := a.extent()
		var r := maxf(ext.size.x, ext.size.y) * 0.5
		match mode:
			"low":
				cam.position = Vector3(r * 0.95, 3.0, r * 1.35)
				cam.look_at(Vector3(0, 0.6, 0))
			"top":
				cam.position = Vector3(0.01, r * 2.6, r * 0.9)
				cam.look_at(Vector3(0, 0, 0))
			_:
				var presets := {"gullet": [Vector3(5.7, 6.7, 8.7), Vector3(0, 0, -0.4)],
					"drydock": [Vector3(6.0, 8.2, -10.8), Vector3(0, -0.2, 0.9)],
					"crusher": [Vector3(4.8, 9.6, 9.2), Vector3(0, 0, -0.6)],
					"rooftop": [Vector3(-3.5, 6.8, -11.0), Vector3(0.5, -0.2, 1.2)]}
				var pr: Array = presets.get(a.style, [Vector3(r * 0.95, r * 0.78 + 2.0, r * 1.45), Vector3(0, 0, -0.4)])
				cam.position = pr[0]
				cam.look_at(pr[1])
		cam.current = true


## Every palette prop and built-in part on one Crusher floor, labelled (visual QA of the catalog).
func _start_gallery() -> void:
	var props := []
	var markers := {}
	var ids := ArenaCatalog.prop_ids()
	var k := 0
	for id in ids:
		var d := ArenaCatalog.prop(id)
		var col := k % 6
		var row := int(k / 6.0)
		var pos := [-5.0 + col * 2.0, 0.0, -4.6 + row * 2.0]
		if bool(d["is_marker"]):
			var mname := str(d["marker"]["name"])
			if not markers.has(mname):
				markers[mname] = []
			markers[mname].append({"pos": pos, "yaw": 180.0, "team": 0 if mname in ["spawn", "goal"] else -1})
		else:
			var p := {"type": id, "pos": pos, "yaw": 200.0 if str(d["behaviour"]) in ["fan", "steam_vent", "ramp"] else 160.0}
			if ArenaCatalog.footprint_shape(d) == "pair":
				p["pos2"] = [pos[0] + 1.2, 0.0, pos[2] + 0.8]
			if id == "prop_edge_railing":
				p["params"] = {"length": 1.8}
			props.append(p)
		k += 1
	var removed := []
	for b in ArenaCatalog.base("drydock")["builtins"]:
		removed.append(str(b["id"]))
	var a := ArenaDef.from_dict({"id": "gallery", "name": "Gallery", "base": "drydock", "props": props, "markers": markers,
		"removed_builtins": removed, "flags": {"tidal_gutter": false, "crane_hook": false}})
	var view := ArenaView.new()
	view.set_editor_mode(true)
	add_child(view)
	view.build(a)
	cam = Camera3D.new()
	cam.fov = 48.0
	add_child(cam)
	var half := _arg("--half", "")
	cam.position = Vector3(0.0, 6.2, 8.2) if half == "" else Vector3(-2.6 if half == "left" else 2.6, 5.0, 6.4)
	cam.look_at(Vector3(0 if half == "" else (-2.6 if half == "left" else 2.6), 0, -0.2))
	cam.current = true


func _hazard_in(type: String, phase: String, min_t: float) -> bool:
	var hz = scene.sim.arena_nodes.get("hazards")
	if not hz is ArenaHazards:
		return true
	for h in (hz as ArenaHazards).hazards:
		var d: Dictionary = h
		if str(d["type"]) == type and str(d["phase"]) == phase and float(d.get("t", 0.0)) >= min_t:
			return true
	return false


func _fast_forward(t: float) -> void:
	# skip the intro so the hazard clock runs, then jump the clock to just before an event
	scene.sim.mode.phase = MatchMode.Phase.FIGHT
	scene.sim.input_enabled = true
	var hz = scene.sim.arena_nodes.get("hazards")
	if hz is ArenaHazards:
		(hz as ArenaHazards).clock = t
