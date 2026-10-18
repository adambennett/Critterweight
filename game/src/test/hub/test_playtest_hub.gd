extends HubTestCase

func test_cannon_difficulties_speed_and_tracking() -> void:
	make_hub("f_dozer", "loading_dock")
	var drill := mode.drill
	drill.start("standard")
	var interval := drill._interval()
	var flight := drill._flight()
	drill.start("advanced")
	check(drill._interval() < interval and drill._flight() < flight, "Pressure shoots faster and gives less warning")
	drill.start("expert")
	check(drill._interval() < interval * 0.5, "Homing hell more than doubles the initial fire rate")
	var pos := player().pos() + Vector3(-4, 3, 0)
	var bucket := {"id": 7, "pos": pos, "vel": Vector3(0, 0, 3), "age": 0.0, "flight": 1.0, "resolved": false}
	drill.buckets = [bucket]
	drill._update_buckets(0.05, player())
	check(float((bucket["vel"] as Vector3).x) > 0, "expert bucket steers toward the player")
	bucket["age"] = 0.8
	var committed: Vector3 = bucket["vel"]
	drill._update_buckets(0.01, player())
	check_near((bucket["vel"] as Vector3).x, committed.x, 0.0001, "last quarter-second is committed, allowing a dodge")
	drill.cancel()
	for i in 3:
		var board := App.push("hub_board", {"kind": "drill", "scene": self}) as HubBoard
		await wait_frames(3)
		var choices := board.list.focusables()
		(choices[i] as Button).pressed.emit()
		check_eq(drill.difficulty, str(HubChumDrill.DIFFICULTIES.keys()[i]), "difficulty button launches its own selected level")
		check(drill.running(), "selecting a level starts the challenge")
		drill.cancel()
		await wait_frames(2)

func test_called_crate_shots_reward_variety_and_reset_the_dock() -> void:
	make_hub("f_stoke", "loading_dock")
	var toss := mode.crates
	toss.start()
	var origin := Vector3(HubLayout.CRATE_LANE_X, 1, HubLayout.CRATE_LINE_Z + 0.2)
	for i in 3:
		toss.on_throw(i, origin)
		toss.on_land(i, Vector3(HubLayout.CRATE_LANE_X, 0, HubLayout.CRATE_LINE_Z - float(HubLayout.CRATE_RINGS[i]["dist"])), false)
	check_eq(toss.points, 125, "three called rings: 35 base + 25/30/35 bonuses")
	check_eq(toss.combo, 3, "changing distances builds a streak")
	toss.on_throw(0, origin)
	check_eq(toss.thrown, 3, "the same crate cannot be scored twice")
	toss.on_throw(3, origin)
	toss.on_land(3, Vector3.ZERO, true)
	check_eq(toss.combo, 0, "a water miss breaks the streak")
	var crate: RigidBody3D = mode.world["crates"][0]
	crate.global_position += Vector3(3, 0, -5)
	toss.finish("test")
	for i in mode.world["crates"].size():
		var c: RigidBody3D = mode.world["crates"][i]
		check(c.global_position.is_equal_approx(HubWorld.crate_home(i)), "crate %d reset after the game" % i)
	check(mode.flying.is_empty(), "no old throws remain active")

func test_crate_pickup_cannot_reach_through_main_floor_wall() -> void:
	make_hub("f_stoke")
	var crate: RigidBody3D = mode.world["crates"][0]
	crate.global_position = Vector3(-6, 0.4, -8.7)
	await teleport(Vector3(-6, 0, -7.2), 180)
	check(not mode.carryable_visible(player(), crate), "the real main-floor wall blocks pickup sight")
	check(mode._nearest_carryable(player()).get("index", -1) != 0, "crate is excluded from grab targeting through the wall")
	await teleport(Vector3(-6, 0, -9.7), 0)
	check(mode.carryable_visible(player(), crate), "the same crate is reachable on the dock side")

func test_camera_controls_match_every_frame_of_a_room_turn() -> void:
	var camera := HubCamera.new()
	add_child(camera)
	camera.set_process(false)
	camera.snap()
	camera.set_space("loading_dock")
	for i in 12:
		camera._process(0.04)
		var displayed := Vector3(camera.global_basis.z.x, 0, camera.global_basis.z.z).normalized()
		check(camera.input_basis().z.dot(displayed) > 0.999, "movement matches the visible camera during turn %d" % i)
	camera.queue_free()
