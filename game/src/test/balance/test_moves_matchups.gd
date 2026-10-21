extends TestCase
## v0.9.18 Movesets round-robin (docs/design/MOVESET_COMBAT.md §10): pro bots fight every ordered
## pair of the playable roster, once per side, in Movesets and in Classic with the same seeds, and
## the report says what changed: each fighter's win rate, fight lengths and knockouts, how much of
## the damage each kind of move did, which loadout moves the bots used (none may be dead weight)
## and how often a press was denied. Headless, faster than real time.
##
## Gated (long), so suites skip it:
##   godot --headless --path game --fixed-fps 120 -- --user-root <tmp> --test test_moves_matchups
##         --matchups <out.json> [--matchups-bouts 2] [--matchups-styles moves,classic] [--matchups-time 60]

const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_varga", "f_knell"]


func test_zz_moves_matchups() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--matchups")
	if i < 0 or i + 1 >= args.size():
		return
	var out_path := args[i + 1]
	var bouts := int(_arg(args, "--matchups-bouts", "1"))
	var round_time := float(_arg(args, "--matchups-time", "60"))
	var styles := Array(_arg(args, "--matchups-styles", "moves,classic").split(",", false))
	var report := {"version": Saves.game_version(), "bouts_per_side": bouts, "round_time": round_time, "styles": {}}
	for style in styles:
		var rows: Array = []
		var seed_value := 100
		for a in ROSTER:
			for b in ROSTER:
				if a == b:
					continue
				for k in bouts:
					seed_value += 1
					rows.append(await _bout(str(style), a, b, seed_value, round_time))
		report["styles"][style] = {"bouts": rows, "summary": _summary(rows)}
		print("MATCHUPS ", style, " ", JSON.stringify(report["styles"][style]["summary"]["fighters"]))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
	var md := FileAccess.open(out_path.get_basename() + ".md", FileAccess.WRITE)
	if md:
		md.store_string(_markdown(report))
	print("MATCHUPS_DONE ", out_path)


func _arg(args: PackedStringArray, flag: String, def: String) -> String:
	var k := args.find(flag)
	return args[k + 1] if k >= 0 and k + 1 < args.size() else def


func _bout(style: String, a: String, b: String, seed_value: int, round_time: float) -> Dictionary:
	var rules: Dictionary = Content.get_entry("rules", "duel").duplicate(true)
	rules["combat"] = style
	rules["rounds"] = 1
	rules["round_time"] = round_time
	rules["sudden_death"] = false
	rules["intro_time"] = 0.2
	var brains := [BotBrain.new("pro", seed_value * 2), BotBrain.new("pro", seed_value * 2 + 1)]
	var fighters := []
	for k in 2:
		var c := Content.creature([a, b][k])
		brains[k].set_personality(c.ai)
		fighters.append({"creature": c, "team": k, "source": brains[k], "kind": "bot", "difficulty": "pro"})
	var cfg := {"arena": Content.arena("the_gullet"), "rules": rules, "seed": seed_value, "fighters": fighters,
		"mode": ModeRegistry.create("standard"), "no_record": true}
	var events: Array = []
	var sim_ref := [null]
	var res := await _run_collect(cfg, round_time + 30.0, events, sim_ref)
	var row := {"a": a, "b": b, "seed": seed_value, "winner": -1, "time": 0.0, "ko": false, "damage": [0.0, 0.0],
		"by_cat": [{}, {}], "denied": [0, 0], "moves_used": [{}, {}], "loadout": [[], []], "bot": [brains[0].tally.duplicate(), brains[1].tally.duplicate()]}
	var sim: MatchSim = sim_ref[0]
	if sim != null:
		for k in 2:
			row["loadout"][k] = sim.fighters[k].loadout.duplicate()
	row["winner"] = int(res.get("winner_team", -1))       # a duel: team k is fighter k
	row["time"] = float(res.get("time", 0.0))
	for ev in events:
		var t := str(ev.get("type", ""))
		var fi := int(ev.get("fighter", -1))
		if fi < 0 or fi > 1:
			continue
		match t:
			"hit":
				if int(ev.get("target", -1)) != 1 - fi or bool(ev.get("blocked", false)):
					continue
				var d := float(ev.get("damage", 0.0))
				row["damage"][fi] = float(row["damage"][fi]) + d
				var cat := str(ev.get("cat", "classic"))
				var bc: Dictionary = row["by_cat"][fi]
				bc[cat] = float(bc.get(cat, 0.0)) + d
			"move_denied":
				row["denied"][fi] = int(row["denied"][fi]) + 1
			"move_start":
				var pool := str(ev.get("pool", ""))
				if pool != "":
					var mu: Dictionary = row["moves_used"][fi]
					mu[pool] = int(mu.get(pool, 0)) + 1
			"ko":
				row["ko"] = true
	return row


## HeadlessFightRunner, keeping every event and the simulation (for the loadouts).
func _run_collect(cfg: Dictionary, max_seconds: float, events: Array, sim_ref: Array) -> Dictionary:
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sv.size = Vector2i(2, 2)
	add_child(sv)
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	sim.setup(cfg)
	sim_ref[0] = sim
	var dt := 1.0 / 120.0
	var cursor := 0
	while not sim.is_finished and sim.time < max_seconds:
		sim.step(dt)
		for ev in sim.events_since(cursor):
			events.append(ev)
			cursor = int(ev["seq"])
		await get_tree().physics_frame
	var res: Dictionary = sim.result.duplicate(true) if sim.is_finished else {"winner_team": -1, "timed_out": true, "time": sim.time}
	sv.queue_free()
	return res


func _summary(rows: Array) -> Dictionary:
	var fighters := {}
	for id in ROSTER:
		fighters[id] = {"bouts": 0, "wins": 0, "kos": 0, "time": 0.0, "damage": 0.0, "by_cat": {}, "denied": 0, "moves_used": {}}
	var draws := 0
	for r in rows:
		if int(r["winner"]) < 0:
			draws += 1
		for k in 2:
			var id := str([r["a"], r["b"]][k])
			var s: Dictionary = fighters[id]
			s["bouts"] = int(s["bouts"]) + 1
			s["time"] = float(s["time"]) + float(r["time"])
			s["damage"] = float(s["damage"]) + float(r["damage"][k])
			s["denied"] = int(s["denied"]) + int(r["denied"][k])
			if int(r["winner"]) == k:
				s["wins"] = int(s["wins"]) + 1
				if bool(r["ko"]):
					s["kos"] = int(s["kos"]) + 1
			for cat in (r["by_cat"][k] as Dictionary):
				s["by_cat"][cat] = float(s["by_cat"].get(cat, 0.0)) + float(r["by_cat"][k][cat])
			for mv in (r["moves_used"][k] as Dictionary):
				s["moves_used"][mv] = int(s["moves_used"].get(mv, 0)) + int(r["moves_used"][k][mv])
	for id in fighters:
		var s2: Dictionary = fighters[id]
		var n := maxi(1, int(s2["bouts"]))
		s2["win_rate"] = snappedf(float(s2["wins"]) / n, 0.01)
		s2["avg_time"] = snappedf(float(s2["time"]) / n, 0.1)
		s2["avg_damage"] = snappedf(float(s2["damage"]) / n, 0.1)
	return {"fighters": fighters, "bouts": rows.size(), "draws": draws}


func _markdown(report: Dictionary) -> String:
	var out := "# Movesets round-robin (%s)\n\nPro bots, every ordered pair of the roster x %d per side, one %d-second round in the primary cage.\n\n" % [
		str(report["version"]), int(report["bouts_per_side"]), int(report["round_time"])]
	out += "| Fighter | " + " | ".join(PackedStringArray((report["styles"] as Dictionary).keys().map(func(s): return "%s win rate | %s avg fight (s) | %s avg damage" % [s, s, s]))) + " |\n"
	out += "|---|" + "---|---|---|".repeat((report["styles"] as Dictionary).size()) + "\n"
	for id in ROSTER:
		var cells := []
		for style in report["styles"]:
			var s: Dictionary = report["styles"][style]["summary"]["fighters"][id]
			cells.append("%.0f%% | %.1f | %.1f" % [float(s["win_rate"]) * 100.0, float(s["avg_time"]), float(s["avg_damage"])])
		out += "| %s | %s |\n" % [id, " | ".join(PackedStringArray(cells))]
	if (report["styles"] as Dictionary).has("moves"):
		out += "\n## Movesets: damage by kind of move and moves used\n\n| Fighter | Damage by kind | Moves used (starts) | Denied presses |\n|---|---|---|---|\n"
		for id in ROSTER:
			var s3: Dictionary = report["styles"]["moves"]["summary"]["fighters"][id]
			out += "| %s | %s | %s | %d |\n" % [id, JSON.stringify(s3["by_cat"]), JSON.stringify(s3["moves_used"]), int(s3["denied"])]
	return out
