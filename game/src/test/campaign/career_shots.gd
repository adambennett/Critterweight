extends Node
## Visual evidence runner for the Career screens (windowed, not a test; like referee_shots).
## Run (use a scratch user root: it writes careers into it; seed its window size first):
##   godot --headless --path game -- --user-root <scratch dir> --ui-seed-window 1280x800
##   godot --path game --resolution 1280x800 res://src/test/campaign/career_shots.tscn -- \
##         --user-root <scratch dir> --out <dir> [--no-fight]
## Builds a career with real controller calls (training, a booked fight settled with a synthetic
## 10-point result, a gym upgrade) plus a second career, then saves <out>/career_*.png:
## slots, new career, hub TRAINING / OFFERS / GYM / HISTORY (unbooked), the result with its
## scorecards, CAMP booked mid-camp, FIGHT WEEK, and (unless --no-fight) a real presented career
## bout a few seconds in, its pause menu and the pull-out confirmation.

var args: PackedStringArray
var out := ""
var cat: CampaignCatalog
var store: CareerStore


func _arg(flag: String, fallback := "") -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	call_deferred("_start")


func _start() -> void:
	out = _arg("--out", Paths.dir("captures"))
	DirAccess.make_dir_recursive_absolute(out)
	cat = CareerFlow.default_catalog()
	store = CareerStore.new()
	var pid := CareerFlow.profile_key()
	for n in range(1, CareerStore.SLOTS + 1):
		if store.occupied(pid, n):
			store.move_aside(pid, n)
	var fighters := cat.available_fighters()
	if fighters.is_empty():
		print("SHOTS: no playable fighters")
		get_tree().quit(1)
		return
	# career A: two training weeks, a fight (won on the cards), an upgrade
	var a := _create(1, {"name": "Rivet Grimes", "nick": "Low Tide", "fighter": str(fighters[0]), "seed": 9001})
	a.train("power")
	a.train("rest")
	a.accept(str(a.state["offers"][0]["id"]))
	var guard := 0
	while not a.fight_ready() and guard < 20:
		a.train(["power", "speed", "stamina", "chin"][guard % 4])
		guard += 1
	var won := a.apply_result(_ten_point(0, "Split Decision"), a.booked_id())
	a.buy_upgrade("power")
	a.train("defence")
	# career B in slot 2: a champion-looking veteran for the slot list
	var b := _create(2, {"name": "Pip Saltmarsh", "nick": "", "fighter": str(fighters[mini(3, fighters.size() - 1)]), "seed": 31337, "difficulty": "hard"})
	b.state["pop"] = 81.0
	b.state["record"] = {"w": 14, "l": 3, "d": 1, "tko": 6, "dec": 8}
	b.state["week"] = 140
	b.state["streak"] = 4
	b.train("clinch")
	var fa := CareerFlow.make(cat, a)
	App.goto("main_menu")
	App.push("career", {"catalog": cat})
	await _shot("career_slots")
	App.push("career_new", {"catalog": cat, "slot": 3})
	# the first fighter preview compiles the creature shaders (about a second at 1 fps)
	await _shot("career_new", 3.0)
	for tab in ["camp", "offers", "gym", "history"]:
		fa.show_hub(tab)
		await _shot("career_hub_%s" % ("training" if tab == "camp" else tab))
	App.goto("career_result", {"flow": fa, "summary": won})
	await _shot("career_result")
	a.accept(str(a.state["offers"][0]["id"]))
	a.train("speed")
	fa.show_hub("camp")
	await _shot("career_hub_camp_booked")
	guard = 0
	while not a.fight_ready() and guard < 20:
		a.train("power")
		guard += 1
	fa.show_hub("camp")
	await _shot("career_hub_fight_week")
	if not args.has("--no-fight"):
		if fa.fight():
			await get_tree().create_timer(4.5).timeout
			await _shot("career_fight_start", 0.0)
			MatchFlow.open_pause()
			await _shot("career_fight_pause", 0.6)
			var p := App.top_screen()
			if p != null and p.has_method("_ask_quit"):
				p.call("_ask_quit")
				await _shot("career_fight_pull_out", 0.6)
		else:
			print("SHOTS: the fight did not start: ", fa.last_error)
	get_tree().quit(0)


func _create(slot_n: int, opts: Dictionary) -> CareerController:
	var o := {"difficulty": "normal", "created_at": int(Time.get_unix_time_from_system())}
	for k in opts:
		o[k] = opts[k]
	var r := CareerController.create(cat, o, store, CareerFlow.profile_key(), slot_n)
	if not bool(r["ok"]):
		print("SHOTS: create failed: ", r["error"])
	return r["ctrl"]


## A B1-shaped 10-point result for the booked bout (team 0 = the career fighter).
func _ten_point(winner: int, method: String) -> Dictionary:
	var cards := []
	# per round: the three judges' [team 0, team 1] scores (a 2-1 split for team 0 over three rounds)
	var judges := [[[10, 9], [10, 9], [10, 9]], [[9, 10], [9, 10], [10, 9]], [[10, 9], [9, 10], [10, 9]]]
	for i in 3:
		cards.append({"round": i + 1, "teams": [0, 1], "judges": judges[i], "scores": [[44.5, 38.0], [41.0, 42.5], [47.5, 40.0]],
			"tally": [{"landed": 16 + i, "damage": 140.0 + 10 * i, "knockdowns": 1 if i == 2 else 0, "throws": 1, "parries": 2, "ringouts": 0,
				"taken_head": 12.0, "taken_body": 60.0, "taken_legs": 4.0},
				{"landed": 13 + i, "damage": 120.0, "knockdowns": 0, "throws": 0, "parries": 1, "ringouts": 0,
				"taken_head": 18.0, "taken_body": 80.0, "taken_legs": 6.0}],
			"winner": 0 if i != 1 else 1, "stoppage": false})
	return {"mode": "standard", "winner_team": winner, "rounds": 3, "time": 312.0, "fighters": [],
		"scoring": {"mode": "ten_point", "method": method, "winner": winner, "teams": [0, 1], "cards": cards,
			"totals": [[29, 28], [28, 29], [30, 27]], "judges": ["Even card", "Volume", "Impact"], "stoppage": {}, "sudden_death": false}}


func _shot(name_: String, settle := 0.9) -> void:
	if settle > 0.0:
		await get_tree().create_timer(settle, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out.path_join(name_ + ".png")
	img.save_png(path)
	print("SHOT ", path, " ", img.get_size())
