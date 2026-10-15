extends SceneTree
## Windowed runtime verification of "Spectate this bot" / "Fight this bot" (not part of --test):
##   godot --path game --resolution 1600x900 -s res://src/test/lab/lab_match_capture.gd -- \
##         --user-root <dir with trained policies> --out <capture dir> [--policy <id>] [--seconds 12]
## Opens the Lab's Policies tab, starts a real spectated match (policy vs Bot: Rookie) through the
## screen's button handler, captures frames, counts the policy fighter's hits, then does the same
## for a fight (the local player stays idle) and writes match_report.json.

var out_dir := ""
var policy_id := ""
var seconds := 12.0
var report := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else OS.get_user_data_dir().path_join("captures")
	var j := args.find("--policy")
	policy_id = args[j + 1] if j >= 0 and j + 1 < args.size() else ""
	var k := args.find("--seconds")
	seconds = float(args[k + 1]) if k >= 0 and k + 1 < args.size() else 12.0
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(name_: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("match_%s.png" % name_)
	img.save_png(path)
	print("CAPTURED ", path)


func _select_policy(screen: Node) -> String:
	var pols: Array = screen.get("_pols")
	var list: ItemList = screen.get("_pol_list")
	for idx in pols.size():
		var s: Dictionary = pols[idx]
		if bool(s.get("valid", false)) and (policy_id == "" or str(s.get("id", "")) == policy_id):
			list.select(idx)
			screen.call("_show_policy")
			return str(s["id"])
	return ""


func _count(scene: Node) -> Dictionary:
	var sim = scene.get("sim")
	var hits := [0, 0]
	var dmg := [0.0, 0.0]
	for ev: Dictionary in sim.events:
		if str(ev["type"]) == "hit":
			var a := int(ev.get("fighter", -1))
			if a == 0 or a == 1:
				hits[a] += 1
				dmg[a] += float(ev.get("damage", 0.0))
	var labels := []
	for src in sim.input_sources:
		labels.append(src.label() if src != null else "none")
	return {"hits": hits, "damage": dmg, "sources": labels, "time": sim.time, "health": [sim.fighters[0].health, sim.fighters[1].health]}


func _run() -> void:
	var app := root.get_node("App")
	await create_timer(0.5).timeout
	var screen: Node = app.call("goto", "lab", {"tab": 2})
	await create_timer(1.0).timeout
	var pid := _select_policy(screen)
	report["policy"] = pid
	if pid == "":
		print("NO POLICY AVAILABLE")
		quit(1)
		return
	await _shot("policies_tab")
	screen.call("_spectate")
	await create_timer(seconds).timeout
	await _shot("spectate")
	report["spectate"] = _count(app.get("current_scene"))
	# back to the Lab and fight it (the local player does nothing)
	screen = app.call("goto", "lab", {"tab": 2})
	await create_timer(1.0).timeout
	_select_policy(screen)
	screen.call("_fight")
	await create_timer(seconds).timeout
	await _shot("fight")
	report["fight"] = _count(app.get("current_scene"))
	var f := FileAccess.open(out_dir.path_join("match_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("MATCH_REPORT ", JSON.stringify(report))
	quit(0)
