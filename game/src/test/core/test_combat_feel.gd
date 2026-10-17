extends TestCase
## CMB-08 / CMB-05 (combat feel, 0.9.11): a landed hit is felt (hit pause, camera punch, a damage
## chunk that stays lit on the health bar), and arena geometry between the fight camera and the
## fighters fades instead of hiding the fight. All view-side: the simulation is untouched.


func after_each() -> void:
	Engine.time_scale = 1.0


func test_hit_feedback_scales_with_damage_and_involvement() -> void:
	var light := HitFeel.hit_pause(4.0, false, false, true)
	var heavy := HitFeel.hit_pause(14.0, false, false, true)
	check(light >= 0.05 and heavy > light and heavy <= 0.12, "a bigger hit pauses longer, within 50-120 ms (%.3f, %.3f)" % [light, heavy])
	check(HitFeel.hit_pause(14.0, false, true, true) > heavy, "a counter hit pauses longer still")
	check(HitFeel.hit_pause(14.0, true, false, true) < light, "a blocked hit only ticks")
	check(HitFeel.hit_pause(14.0, false, false, false) == 0.0, "bots hitting bots never pause the game")
	check(HitFeel.punch(8.0, false, false) == 0.0 and HitFeel.punch(8.0, false, true) > 0.5, "only a local player's hits punch the camera")
	check(HitFeel.trauma(8.0, true) > HitFeel.trauma(8.0, false) * 2.0, "a local player's hit shakes the camera clearly")
	var r := HitFeel.rumble(10.0, false)
	check(float(r[1]) > 0.0 and float(r[2]) >= 0.12, "a landed hit rumbles both motors")


func test_the_damage_chunk_stays_lit_then_drains() -> void:
	var trail := 1.0
	var hold := 0.0
	var prev := 1.0
	var frac := 0.9                       # a 10 % hit lands
	var t := 0.0
	while t < FightHud.TRAIL_HOLD - 0.05:
		var s := FightHud.trail_step(trail, hold, frac, prev, 0.05)
		trail = s[0]
		hold = s[1]
		prev = frac
		t += 0.05
	check(is_equal_approx(trail, 1.0), "the lost chunk is still fully shown %.2f s after the hit (%.3f)" % [t, trail])
	for k in 60:
		var s2 := FightHud.trail_step(trail, hold, frac, prev, 0.05)
		trail = s2[0]
		hold = s2[1]
	check(is_equal_approx(trail, frac), "then it drains down to the health (%.3f)" % trail)
	var healed := FightHud.trail_step(trail, hold, 0.95, frac, 0.05)
	check(is_equal_approx(float(healed[0]), 0.95), "a heal snaps the trail up")


func test_a_hit_pause_freezes_the_match_then_restores_its_speed() -> void:
	var cfg := App.resolve_match_config({"arena": "the_gullet", "rules": {"rounds": 1, "round_time": 30}, "seed": 4,
		"fighters": [{"creature": "dev_biped", "team": 0, "kind": "player", "name": "Tester"},
			{"creature": "dev_biped", "team": 1, "kind": "bot", "difficulty": "rookie"}]})
	var scene := MatchScene.new()
	add_child(scene)
	scene.start(cfg)
	Engine.time_scale = 0.75              # e.g. the accessibility game speed
	scene.hit_pause(0.08)
	check(scene.hit_paused() and Engine.time_scale < 0.05, "the match nearly stops (%.3f)" % Engine.time_scale)
	scene.hit_pause(0.03)                 # a second hit during the pause extends, never stacks
	check(Engine.time_scale > 0.02, "pauses do not compound (%.3f)" % Engine.time_scale)
	await get_tree().create_timer(0.2, true, false, true).timeout
	check(not scene.hit_paused() and is_equal_approx(Engine.time_scale, 0.75), "afterwards the match runs at its own speed again (%.3f)" % Engine.time_scale)
	scene.config["online"] = true
	scene.hit_pause(0.1)
	check(not scene.hit_paused() and is_equal_approx(Engine.time_scale, 0.75), "an online (listen-host) match never pauses")
	scene.config["online"] = false
	scene.hit_pause(0.5)
	scene.queue_free()
	await wait_frames(2)
	check(is_equal_approx(Engine.time_scale, 1.0), "leaving the match mid-pause restores normal speed (%.3f)" % Engine.time_scale)


func _box(root: Node3D, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	root.add_child(mi)
	mi.position = pos
	return mi


func test_a_wall_between_the_camera_and_the_fight_fades() -> void:
	var root := Node3D.new()
	add_child(root)
	var wall := _box(root, Vector3(6, 3, 0.4), Vector3(0, 1.5, 4))
	wall.transparency = 0.2               # its own look comes back when it stops blocking
	_box(root, Vector3(30, 4, 30), Vector3(0, 2, 0))      # stands ring around the arena: never fades
	_box(root, Vector3(1, 0.5, 1), Vector3(0, 0.25, 2))   # a low crate: never covers a fighter
	var occ := CameraOccluders.new()
	occ.collect(root)
	check(occ.size() == 1, "only the wall can block (%d)" % occ.size())
	occ.update(Vector3(0, 2, 8), [Vector3(0, 1, 0)], true)
	check(occ.blocking() == 1 and wall.transparency >= 0.7, "a low camera behind the wall sees through it (%.2f)" % wall.transparency)
	occ.update(Vector3(0, 6, 8), [Vector3(0, 1, 0)], true)
	check(occ.blocking() == 0 and is_equal_approx(wall.transparency, 0.2), "from above the wall it is solid again (%.2f)" % wall.transparency)
	var turned := Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 1.5, 4)).affine_inverse()
	check(CameraOccluders.segment_hits_box(turned, AABB(Vector3(-3, -1.5, -0.2), Vector3(6, 3, 0.4)), Vector3(0, 1, 8), Vector3(0, 1, 0)),
		"the box test follows the mesh's own rotation")
	root.queue_free()


func test_crowd_figures_in_the_line_of_sight_shrink_away() -> void:
	var root := Node3D.new()
	add_child(root)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 2
	var xfs: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0, 0, 6)),   # right in front of the camera
		Transform3D(Basis.IDENTITY, Vector3(5, 0, 6))]                               # off to the side
	for i in 2:
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.set_meta("instance_transforms", xfs)     # as ArenaSetDressing.crowd() records them
	root.add_child(mmi)
	var occ := CameraOccluders.new()
	occ.collect(root)
	occ.set_crowd(mmi)
	occ.update(Vector3(0, 1.5, 8), [Vector3(0, 1, 0)], true)
	check(occ.crowd_hidden() == 1, "only the spectator in front of the camera ducks (%d)" % occ.crowd_hidden())
	occ.update(Vector3(0, 6, 8), [Vector3(0, 1, 0)], true)
	check(occ.crowd_hidden() == 0, "and stands back up once the view is clear (%d)" % occ.crowd_hidden())
	root.queue_free()


func test_a_pit_wall_fades_in_a_real_arena() -> void:
	var a := Content.arena("arena_crusher")
	var av := ArenaView.new()
	add_child(av)
	av.build(a)
	var ext := a.extent()
	var mid := ext.get_center()
	var cam := Vector3(ext.end.x + 3.0, 1.2, mid.y)       # outside the east plate, below its top
	av.fade_occluders(cam, [Vector3(mid.x, 1.0, mid.y)])
	av.occluders.update(cam, [Vector3(mid.x, 1.0, mid.y)], true)
	check(av.occluders.size() > 0 and av.occluders.blocking() > 0, "the steel plate in front of the camera fades (%d of %d)" % [av.occluders.blocking(), av.occluders.size()])
	av.occluders.update(Vector3(mid.x, 5.0, mid.y + 0.5), [Vector3(mid.x, 1.0, mid.y)], true)
	check(av.occluders.blocking() == 0, "nothing fades for a camera straight above the fight (%d)" % av.occluders.blocking())
	av.queue_free()
