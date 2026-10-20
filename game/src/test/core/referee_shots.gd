extends Node
## Visual evidence runner for the Cage Rules referee (windowed, not a test; like arena_shots).
## Run:  godot --path game --resolution 1280x720 res://src/test/core/referee_shots.tscn -- \
##         --out <dir> [--arena arena_gullet] [--poses watch,stop,kdWatch,waveOff,raiseR_solo] [--live 6.0]
##         [--size 1600x900]
## Starts a real local match (Varga vs Knell bots, long intro so they stand in their stance), adds a
## RefereeView beside the arena like the match scenes do, then:
##  * --poses: holds each pose next to the left fighter (facing him, or the camera for raises) and
##    saves <out>/referee_<pose>.png from a close 3/4 camera, then <out>/referee_front_ready.png;
##  * --live S: instead runs the director live for S sim seconds from the match camera and saves
##    <out>/referee_live.png.

var args: PackedStringArray
var scene: MatchScene
var rv: RefereeView
var cam: Camera3D
var _hold := ""
var _hold_at := Vector3.ZERO
var _hold_yaw := 0.0
var _t := 0.0


func _arg(flag: String, fallback := "") -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	call_deferred("_start")


func _start() -> void:
	var out := _arg("--out", "user://")
	var live := float(_arg("--live", "-1"))
	var a := Content.arena(_arg("--arena", "arena_gullet"))
	var rules := {"rounds": 3, "round_time": 99, "intro_time": 2.2 if live > 0.0 else 600.0, "format": "duel"}
	var fs := []
	for id in ["f_varga", "f_knell"]:
		fs.append({"creature": Content.creature(id), "team": fs.size(), "kind": "bot", "difficulty": "pro", "name": Content.creature(id).display_name})
	scene = MatchScene.new()
	add_child(scene)
	scene.start({"arena": a, "rules": rules, "seed": 7, "fighters": fs})
	rv = RefereeView.new()
	scene.add_child(rv)
	rv.setup(a, rules)
	if live > 0.0:
		var cap := Time.get_ticks_msec() + 60000
		var k := 0
		while scene.sim.time < live and Time.get_ticks_msec() < cap:
			await get_tree().process_frame
			k += 1
			if k % 30 == 0:
				var d := rv.debug_state()
				print("REF t=%.2f mode=%s pose=%s ref=%s f0=%s f1=%s" % [scene.sim.time, d["mode"], d["pose"], d["pos"],
					scene.sim.fighters[0].pos(), scene.sim.fighters[1].pos()])
		await _save(out.path_join("referee_live.png"))
		get_tree().quit(0)
		return
	await get_tree().create_timer(1.5).timeout
	cam = Camera3D.new()
	cam.fov = 42.0
	scene.add_child(cam)
	cam.current = true
	var f0 := scene.sim.fighters[0].pos()
	var f1 := scene.sim.fighters[1].pos()
	var along := Vector3(f1.x - f0.x, 0, f1.z - f0.z).normalized()
	var side := Vector3(-along.z, 0, along.x)
	for pose in _arg("--poses", "watch,stop,kdWatch,waveOff,raiseR_solo").split(",", false):
		var raise := pose.begins_with("raise")
		_hold = pose
		_hold_at = Vector3(f0.x, 0, f0.z) + along * 1.15 + side * (0.35 if raise else 0.0)
		var look := Vector3(f0.x, 0, f0.z) + along * 0.6
		var cam_dir := (side * 1.0 + along * 0.35).normalized()
		_hold_yaw = atan2(f0.x - _hold_at.x, f0.z - _hold_at.z) if not raise else atan2(cam_dir.x, cam_dir.z)
		cam.look_at_from_position(look + cam_dir * 4.2 + Vector3.UP * 1.55, look + Vector3.UP * 0.95)
		for i in 24:
			await get_tree().process_frame
		await _save(out.path_join("referee_%s.png" % pose))
	# a close front view (materials, clothes, hands) in "ready", facing the camera
	var cd := (side + along * 0.1).normalized()
	_hold = "ready"
	_hold_at = Vector3(f0.x, 0, f0.z) + along * 1.15 + side * 0.35
	_hold_yaw = atan2(cd.x, cd.z)
	cam.look_at_from_position(_hold_at + cd * 3.0 + Vector3.UP * 1.2, _hold_at + Vector3.UP * 0.95)
	for i in 24:
		await get_tree().process_frame
	await _save(out.path_join("referee_front_ready.png"))
	get_tree().quit(0)


func _process(dt: float) -> void:
	if rv == null or scene == null or scene.sim == null:
		return
	_t += dt
	var cam_pos := cam.global_position if cam != null and cam.current else scene.camera.global_position
	rv.update_view(RefereeView.state_from_sim(scene.sim), cam_pos, dt)
	if _hold != "":
		# pin a pose at a spot (the director's choice is overridden for the shot)
		var p: RefereePose.Pose = (rv.poses[_hold] as RefereePose.Pose).copy()
		if _hold == "waveOff" or _hold == "waveUp":
			RefereeView.set_hands(p, _hold, 0.5)
		rv.pose_model.snap = true
		rv.pose_model.update(_hold_at.x, _hold_at.z, _hold_yaw, p, false, 12.0, dt, _t)
		rv.view.snap_transforms(rv.pose_model.transforms_for(rv.creature.body))
		rv.view.render(1.0)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var sz := _arg("--size", "1600x900").split("x")
	img.resize(int(sz[0]), int(sz[1]), Image.INTERPOLATE_LANCZOS)
	img.save_png(path)
	print("SHOT ", path, " ", img.get_size())
