extends TestCase
## v0.9.18 Movesets evidence frames (docs/design/MOVESET_COMBAT.md §10): every playable fighter
## performs each move of its pool (sustains held and swept, charges held to full, Varga's techniques
## on his strikes) against a still mirror dummy in the primary cage, and the real rendered frame is
## saved at fixed simulation times; then crowded eight-fighter bot brawls are captured in Movesets
## and in Classic with the same seed (the comparison the release notes show).
##
## Gated (needs a window), so suites skip it:
##   godot --path game --resolution 1600x900 -- --user-root <tmp> --test test_moves_showcase
##         --moves-showcase <out dir> [--moves-fighters f_stoke,f_dredge] [--moves-only flamethrower,cinder_shot]
##         [--moves-crowd-only]

const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_varga", "f_knell"]
const T0 := 1.0                 ## fight time of the first press
const LAG := 1.0 / 60.0         ## a press is consumed on the next tick
const CROWD_TIMES := [6.0, 12.0, 18.0, 24.0]


class Driver:
	extends InputSource
	var starts: Array = []        ## [{t, slot}] moves started directly (Varga's techniques)
	var holds: Array = []         ## [{t0, t1, button}]
	var presses: Array = []       ## [{t, button}]
	var sweep: Array = []         ## [{t0, t1, from, to}] stick angle (rad, fighter-relative) while aiming
	var time := 0.0
	var fired := {}

	func label() -> String:
		return "MovesShowcaseDriver"

	func poll(f: Fighter, sim, dt: float) -> void:
		if sim.mode and sim.mode.phase != MatchMode.Phase.FIGHT:
			return
		time += dt
		f.input.move = Vector3.ZERO
		f.input.held = 0
		for s in sweep:
			if time >= float(s["t0"]) and time < float(s["t1"]):
				var k := (time - float(s["t0"])) / maxf(0.01, float(s["t1"]) - float(s["t0"]))
				var ang := lerpf(float(s["from"]), float(s["to"]), k)
				f.input.move = f.forward().rotated(Vector3.UP, ang) * 0.6
		for h in holds:
			if time >= float(h["t0"]) and time < float(h["t1"]):
				f.input.set_held(int(h["button"]), true)
		for i in presses.size():
			var p: Dictionary = presses[i]
			if not fired.has("p%d" % i) and time >= float(p["t"]):
				fired["p%d" % i] = true
				f.input.press(int(p["button"]))
		for i in starts.size():
			var s2: Dictionary = starts[i]
			if not fired.has("s%d" % i) and time >= float(s2["t"]):
				fired["s%d" % i] = true
				var m: MoveDef = f.creature.moves.get(str(s2["slot"]))
				if m:
					f._start_move(m, str(s2["slot"]), Fighter.State.ATTACK)


func test_zz_moves_showcase() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--moves-showcase")
	if i < 0 or i + 1 >= args.size() or DisplayServer.get_name() == "headless":
		return
	var out_dir := args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var only_f := _list_arg(args, "--moves-fighters")
	var only_m := _list_arg(args, "--moves-only")
	Settings.set_value("access.camera_shake", 0.0, true, false)
	var index := []
	if not args.has("--moves-crowd-only"):
		for cid in ROSTER:
			if not only_f.is_empty() and not only_f.has(cid):
				continue
			var c := Content.creature(cid)
			if c == null:
				continue
			for shot in shots_for(c):
				if not only_m.is_empty() and not only_m.has(str(shot["name"])):
					continue
				var files := await _capture(c, shot, out_dir)
				index.append({"fighter": cid, "shot": shot["name"], "category": shot["category"], "times": shot["at"],
					"labels": shot["labels"], "files": files})
	if only_m.is_empty() and only_f.is_empty():
		for style in ["moves", "classic"]:
			var files2 := await _crowd(style, out_dir)
			index.append({"fighter": "crowd", "shot": "crowd_" + style, "category": "crowd", "times": CROWD_TIMES, "labels": [], "files": files2})
	var f := FileAccess.open(out_dir.path_join("index.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": Saves.game_version(), "shots": index}, "\t"))
	print("MOVES_SHOWCASE_DONE ", index.size())


func _list_arg(args: PackedStringArray, flag: String) -> Array:
	var k := args.find(flag)
	if k < 0 or k + 1 >= args.size():
		return []
	return Array(args[k + 1].split(",", false))


## Time (s from the move's start) of a move's first effect, else its first hit window.
static func first_t(m: MoveDef) -> float:
	var t := INF
	for e in m.effects:
		t = minf(t, float((e as Dictionary).get("t", 0.0)))
	if t == INF:
		t = m.first_active() if not m.windows.is_empty() else 0.3
	return t


## The basic move of a fighter's pool (every loadout carries one).
static func basic_of(c: CreatureDef) -> String:
	for id in c.pool:
		if (c.pool[id] as PoolMove).role == "basic":
			return str(id)
	return ""


## One shot per pool move (the basic string is the v0.9.17 animation and is left out):
## {name, category, gap, loadout, presses|holds|starts|sweep, at: [fight times], labels}
static func shots_for(c: CreatureDef) -> Array:
	var out := []
	var basic := basic_of(c)
	for id in c.pool:
		var pm: PoolMove = c.pool[id]
		if pm.role == "basic" or pm.move == null:
			continue
		var shot := {"name": str(id), "category": pm.category, "at": [], "labels": []}
		shot["gap"] = 1.7 if pm.category in ["strike", "counter", "support"] else (3.6 if pm.category == "rush" else 3.0)
		var marks: Array = []
		if not pm.martial.is_empty():
			# a technique: Varga's strike of that group, started directly (its limb and modifier)
			var slots: Dictionary = pm.martial.get("slots", {})
			var key := str(slots.values()[0]) if not slots.is_empty() else ""
			var tm: MoveDef = c.moves.get(key)
			if tm == null:
				continue
			shot["loadout"] = []
			shot["technique"] = str(id)
			shot["starts"] = [{"t": T0, "slot": key}]
			var fa := tm.first_active() if not tm.windows.is_empty() else first_t(tm)
			marks = [[fa * 0.6, "prep"], [fa + 0.03, "contact"], [fa + 0.18, "motion"], [fa + 0.5, "after"], [fa + 1.1, "linger"]]
		else:
			shot["loadout"] = [basic, str(id)] if basic != "" else [str(id)]
			var button: int = Fighter.MOVE_BUTTONS[1 if basic != "" else 0]
			shot["presses"] = [{"t": T0, "button": button}]
			var m: MoveDef = pm.move
			match pm.hold:
				"sustain":
					var held := minf(pm.max_hold, 1.8)
					shot["holds"] = [{"t0": T0, "t1": T0 + held, "button": button}]
					var s0 := float(m.sustain[0]) if m.sustain.size() >= 2 else 0.3
					if pm.aim_turn > 0.0:
						shot["sweep"] = [{"t0": T0 + s0 + 0.3, "t1": T0 + held, "from": 0.0, "to": 0.9}]
					marks = [[s0 * 0.6, "prep"], [s0 + 0.15, "pour"], [s0 + 0.6, "pour2"], [held - 0.05, "swept"], [held + 0.35, "release"], [held + 1.2, "linger"]]
				"charge":
					var cs := m.charge_start()
					var release := cs + m.charge_time + 0.05
					shot["holds"] = [{"t0": T0, "t1": T0 + release, "button": button}]
					var cm: MoveDef = pm.charged if pm.charged != null else m
					var ft := first_t(cm) if pm.charged != null else maxf(0.0, first_t(m) - cs)
					marks = [[cs + m.charge_time * 0.5, "charging"], [release + 0.03, "release"], [release + ft + 0.03, "contact"],
						[release + ft + 0.3, "after"], [release + ft + 1.0, "linger"]]
				_:
					var ft2 := first_t(m) + LAG
					marks = [[ft2 * 0.55, "prep"], [ft2 + 0.03, "contact"], [ft2 + 0.25, "motion"], [ft2 + 0.7, "after"], [ft2 + 1.5, "linger"]]
		for mk in marks:
			shot["at"].append(T0 + float(mk[0]))
			shot["labels"].append(mk[1])
		out.append(shot)
	return out


func _arena(gap: float, id: String) -> ArenaDef:
	var arena: Dictionary = Content.get_entry("arenas", "the_gullet").duplicate(true)
	arena["id"] = id
	arena["spawns"] = [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]
	var mk: Dictionary = arena.get("markers", {})
	mk.erase("spawn")
	mk.erase("marker_spawn")
	return ArenaDef.from_dict(arena)


func _capture(c: CreatureDef, shot: Dictionary, out_dir: String) -> Array:
	var d := Driver.new()
	for k in ["starts", "presses", "holds", "sweep"]:
		if shot.has(k):
			d.set(k, shot[k])
	var me := {"creature": c.id, "team": 0, "kind": "scripted", "source": d, "name": c.id.trim_prefix("f_").to_upper()}
	if not (shot["loadout"] as Array).is_empty():
		me["loadout"] = shot["loadout"]
	elif shot.has("technique"):
		# Varga: the recommended loadout that carries this technique
		for lid in c.loadouts:
			if (c.loadouts[lid]["moves"] as Array).has(str(shot["technique"])):
				me["loadout"] = (c.loadouts[lid]["moves"] as Array).duplicate()
	var scene := App.start_match({"arena": _arena(float(shot.get("gap", 3.0)), "moves_showcase"), "seed": 7, "no_record": true,
		"rules": {"id": "moves_showcase", "name": "Movesets showcase", "mode": "standard", "rounds": 1, "round_time": 0, "intro_time": 0.4, "combat": "moves"},
		"fighters": [me, {"creature": c.id, "team": 1, "kind": "scripted", "source": null, "name": "DUMMY"}]})
	await get_tree().physics_frame
	var files := []
	var times: Array = shot["at"]
	var labels: Array = shot["labels"]
	for k in times.size():
		while d.time < float(times[k]):
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out_dir.path_join("%s_%s_%d_%s.png" % [c.id, str(shot["name"]), k, str(labels[k])])
		img.save_png(path)
		files.append(path.get_file())
		print("MOVES_SHOWCASE ", path)
	return files


## Eight pro bots, one of each fighter, free-for-all in the primary cage: the same seed in Movesets
## and in Classic, frames at the same fight times.
func _crowd(style: String, out_dir: String) -> Array:
	var fighters := []
	for k in ROSTER.size():
		fighters.append({"creature": ROSTER[k], "team": k, "kind": "bot", "difficulty": "pro", "name": ROSTER[k].trim_prefix("f_").to_upper()})
	var rules: Dictionary = Content.get_entry("rules", "free_for_all").duplicate(true)
	rules["combat"] = style
	rules["round_time"] = 0
	rules["intro_time"] = 0.4
	var scene := App.start_match({"arena": Content.arena("the_gullet"), "seed": 21, "no_record": true, "rules": rules, "fighters": fighters})
	await get_tree().physics_frame
	while scene.sim.mode.phase != MatchMode.Phase.FIGHT:
		await get_tree().physics_frame
	var fight_t0 := scene.sim.time
	var files := []
	for k in CROWD_TIMES.size():
		while scene.sim.time - fight_t0 < float(CROWD_TIMES[k]) and not scene.sim.is_finished:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out_dir.path_join("crowd_%s_%d.png" % [style, k])
		img.save_png(path)
		files.append(path.get_file())
		print("MOVES_SHOWCASE ", path)
	return files
