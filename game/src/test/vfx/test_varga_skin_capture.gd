extends TestCase
## Evidence frames for the "Legacy Varga skin" (docs/ART_REVAMP.md v0.9.17): a real match (Varga vs
## Varga, bots) captured with the upgraded default, then the setting switched on mid-match (the
## model swaps live) and captured again, then switched back. Gated (needs a window):
##   godot --path game --resolution 1600x900 -- --user-root <tmp> --test test_varga_skin_capture --varga-skin-capture <out dir>

const KEY := "cosmetic.legacy_varga"


func test_zz_varga_skin_capture() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--varga-skin-capture")
	if i < 0 or i + 1 >= args.size() or DisplayServer.get_name() == "headless":
		return
	var out := args[i + 1]
	DirAccess.make_dir_recursive_absolute(out)
	Settings.set_value("access.camera_shake", 0.0, true, false)
	Settings.set_value(KEY, false, true, false)
	App.start_match({"arena": "the_gullet", "rules": "duel", "seed": 17, "no_record": true,
		"fighters": [{"creature": "f_varga", "team": 0, "kind": "bot", "difficulty": "pro", "name": "VARGA"},
			{"creature": "f_varga", "team": 1, "kind": "bot", "difficulty": "pro", "name": "VARGA"}]})
	var shots := [[6.0, "1_default", false], [6.8, "2_legacy_live_swap", true], [9.0, "3_legacy", true], [9.8, "4_default_again", false]]
	var t0 := Time.get_ticks_msec()
	for s in shots:
		while (Time.get_ticks_msec() - t0) / 1000.0 < float(s[0]):
			await get_tree().process_frame
		if bool(Settings.get_value(KEY)) != bool(s[2]):
			Settings.set_value(KEY, bool(s[2]), true, false)
			await get_tree().process_frame
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out.path_join("varga_skin_%s.png" % str(s[1]))
		img.save_png(path)
		print("VARGA_SKIN_CAPTURE ", path)
	Settings.set_value(KEY, false, true, false)
