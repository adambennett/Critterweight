extends TestCase
## LAB-02 (imitation data from normal matches): with the Lab's "record my matches" switch on, a
## normal MatchScene match driven by (simulated) device input records the human player's
## observations and labelled actions into a dataset; with the switch off nothing is recorded.

var dir := ""


func before_each() -> void:
	dir = temp_dir("lab_rec_%d" % Time.get_ticks_usec())
	LabRecording.config_path_override = dir.path_join("recording.json")
	LabRecording.reload()
	PolicyDataset.root_override = dir.path_join("datasets")


func after_each() -> void:
	for a in ["move_up", "light", "guard"]:
		Input.action_release(a)
	LabRecording.config_path_override = ""
	LabRecording.reload()
	PolicyDataset.root_override = ""


func _start_match() -> MatchScene:
	var cfg := App.resolve_match_config({"arena": "the_gullet", "rules": {"rounds": 1, "round_time": 30}, "seed": 4,
		"fighters": [{"creature": "dev_biped", "team": 0, "kind": "player", "name": "Tester"},
			{"creature": "dev_biped", "team": 1, "kind": "bot", "difficulty": "rookie"}]})
	var scene := MatchScene.new()
	add_child(scene)
	scene.start(cfg)
	return scene


func test_player_matches_are_recorded_when_enabled() -> void:
	LabRecording.set_enabled(true)
	var scene := _start_match()
	check(scene.sim.input_sources[0] is PolicyRecorder, "the player's input is wrapped by the recorder")
	await wait_physics(int(2.4 * Engine.physics_ticks_per_second))
	# simulated device input: walk forward and jab on a rhythm, guard now and then
	Input.action_press("move_up")
	for k in 16:
		Input.action_press("light")
		await wait_physics(4)
		Input.action_release("light")
		await wait_physics(10)
		if k % 5 == 4:
			Input.action_press("guard")
			await wait_physics(20)
			Input.action_release("guard")
	Input.action_release("move_up")
	scene.queue_free()
	await wait_frames(2)
	var listed := PolicyDataset.list("dev_biped")
	check_eq(listed.size(), 1, "one dataset for the fighter")
	if listed.is_empty():
		return
	var ds: Dictionary = listed[0]
	check_eq(str(ds["source"]), "human", "marked as human play")
	check(int(ds["samples"]) >= 30, "samples recorded (%d)" % int(ds["samples"]))
	var all := PolicyDataset.load_all(str(ds["path"]))
	var lights := 0
	var guards := 0
	var toward := 0
	for k in int(all["count"]):
		if int(all["buttons"][k]) == PolicyActions.B_LIGHT:
			lights += 1
		if int(all["buttons"][k]) in [PolicyActions.B_GUARD_HOLD, PolicyActions.B_GUARD_TAP]:
			guards += 1
		if int(all["moves"][k]) != 0:
			toward += 1
	check(lights >= 8, "jab presses labelled as light (%d)" % lights)
	check(guards >= 2, "guarding labelled (%d)" % guards)
	check(toward >= 10, "movement labelled (%d)" % toward)


func test_nothing_is_recorded_when_disabled() -> void:
	LabRecording.set_enabled(false)
	var scene := _start_match()
	check(scene.sim.input_sources[0] is LocalPlayerInput, "the player's input is untouched")
	await wait_physics(30)
	scene.queue_free()
	await wait_frames(2)
	check(PolicyDataset.list().is_empty(), "no dataset written")
