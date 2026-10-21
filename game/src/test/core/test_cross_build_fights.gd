extends TestCase
## Cross-build gameplay check (v0.9.17, docs/evidence/verification/v0.9.17): seeded pro-bot fights
## stepped headless at the fixed 1/120 s tick, every simulation event written with its tick, so the
## same file run in two checkouts shows whether combat plays out identically (timing, damage, hits,
## knockdowns, results). Uses only APIs that existed in v0.9.16, so it runs in the previous release's
## checkout unchanged.
##
## Gated, so suites skip it:
##   godot --headless --path game --fixed-fps 120 -- --user-root <tmp> --test test_cross_build_fights --fights-out <file.json>

const ROSTER := ["f_stoke", "f_dredge", "f_gusto", "f_dozer", "f_slurry", "f_jitters", "f_varga", "f_knell"]
const KEYS := ["type", "fighter", "target", "slot", "move", "blocked", "parried", "reason", "by", "winner", "round", "id", "reaction", "status", "element"]


func test_zz_cross_build_fights() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--fights-out")
	if i < 0 or i + 1 >= args.size():
		return
	var out := {"version": str(ProjectSettings.get_setting("application/config/version", "")), "fights": []}
	var n := 0
	# every fighter against the next two in the roster, both corners, plus one eight-fighter brawl
	for k in ROSTER.size():
		for step in [1, 3]:
			n += 1
			var a: String = ROSTER[k]
			var b: String = ROSTER[(k + step) % ROSTER.size()]
			out["fights"].append(await _fight([a, b], 500 + n, 75.0))
	out["fights"].append(await _fight(ROSTER, 999, 40.0))
	var f := FileAccess.open(args[i + 1], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("CROSS_BUILD_FIGHTS_DONE ", out["fights"].size())


func _fight(ids: Array, seed_value: int, seconds: float) -> Dictionary:
	var rules: Dictionary = Content.get_entry("rules", "duel" if ids.size() == 2 else "free_for_all").duplicate(true)
	rules["rounds"] = 1
	rules["round_time"] = seconds
	rules["intro_time"] = 0.5
	rules.erase("sudden_death")
	var fighters := []
	for k in ids.size():
		var c := Content.creature(str(ids[k]))
		var brain := BotBrain.new("pro", seed_value * 10 + k)
		brain.set_personality(c.ai)
		fighters.append({"creature": c, "team": k, "source": brain, "kind": "bot"})
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sv.size = Vector2i(2, 2)
	add_child(sv)
	var sim := MatchSim.new()
	sim.running = false
	sv.add_child(sim)
	await get_tree().physics_frame
	sim.setup({"arena": Content.arena("the_gullet"), "rules": rules, "seed": seed_value, "fighters": fighters,
		"mode": ModeRegistry.create("standard"), "no_record": true})
	var dt := 1.0 / 120.0
	var cursor := 0
	var events: Array = []
	while not sim.is_finished and sim.time < seconds + 20.0:
		sim.step(dt)
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			var e := {"tick": sim.tick_count}
			for key in KEYS:
				if ev.has(key):
					var v = ev[key]
					e[key] = v if typeof(v) in [TYPE_INT, TYPE_STRING, TYPE_BOOL] else (snappedf(float(v), 0.0001) if typeof(v) == TYPE_FLOAT else str(v))
			if ev.has("damage"):
				e["damage"] = snappedf(float(ev["damage"]), 0.0001)
			events.append(e)
		await get_tree().physics_frame
	var health := []
	for fi in sim.fighters:
		health.append(snappedf(float(fi.health), 0.0001))
	var res := {"fighters": ids, "seed": seed_value, "ticks": sim.tick_count, "finished": sim.is_finished,
		"winner_team": int(sim.result.get("winner_team", -1)) if sim.is_finished else -1, "health": health,
		"events": events, "digest": JSON.stringify(events).sha256_text()}
	sv.queue_free()
	return res
