extends CareerTestCase
## Writes a representative set of player saves with THIS build, so a later build can prove it still
## loads them (test_saves_from_older_build.gd). Gated; only runs with a target folder:
##   godot --headless --path game -- --user-root <root> --test test_zz_save_fixture_writer --write-save-fixtures <root>
## The files land in the user-data root through the game's own stores: settings, a suspended Off
## the Street run (four nodes in), a Career after one booked bout, and a user rules preset.
## Uses only APIs that existed in v0.9.16 (it was run on the v0.9.16 checkout for the v0.9.17 fixtures).


func test_zz_write_save_fixtures() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--write-save-fixtures")
	if i < 0 or i + 1 >= args.size():
		return
	var out := args[i + 1]
	var profile := "tester"
	# settings the player changed
	Settings.set_value("audio.master", 60, false, true)
	Settings.set_value("access.subtitle_size", "large", false, true)
	Settings.set_value("graphics.effects", 1, false, true)
	# a suspended Off the Street run, four nodes in
	var rs := RunStore.new(out.path_join("runs"))
	var ctrl := new_run({"seed": 606})
	for k in 4:
		if ctrl.is_over():
			break
		ctrl.choose_node(str(ctrl.available_nodes()[0]), "p0")
		settle_node(ctrl)
	check_eq(rs.save(ctrl.state, profile), OK, "run saved")
	# a Career with one bout booked and fought
	store = CareerStore.new(out.path_join("careers"))
	var car := new_career({"fighter": "f_varga", "seed": 4242, "slot": 1}, true)
	book(car)
	car.apply_result(scoring_result(0, "decision"))
	check_eq(store.save(car.state, profile, 1), OK, "career saved")
	# a user rules preset
	var pr := RulePresets.save({"name": "Fixture Duel", "mode": "standard", "rounds": 2, "round_time": 75, "health_mult": 1.25})
	check(bool(pr.get("ok", true)), "preset saved")
	var f := FileAccess.open(out.path_join("fixture_info.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"game_version": Saves.game_version(), "content_hash": Content.content_hash(),
			"run_phase": ctrl.phase(), "career_week": car.state.get("week", -1), "preset": pr}, "\t"))
	print("SAVE_FIXTURES_WRITTEN ", out)
