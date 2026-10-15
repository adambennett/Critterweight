extends TestCase
## NET-03: snapshot accuracy and size on a real simulation, forward-kinematics reconstruction,
## roster generations, interpolation/teleport handling, event scheduling, and the HUD mirror
## driving the real FightHud.


func _fighting_sim(n: int) -> MatchSim:
	var fighters := []
	for i in n:
		var src := InputSource.Scripted.new([{"t0": 0.0, "t1": 30.0, "move": "to_target", "press": ["light"], "every": 0.3}])
		fighters.append({"creature": "dev_biped", "team": i, "source": src})
	return make_sim("the_gullet", {"rounds": 1, "round_time": 0, "format": "ffa"}, fighters, 5)


func _gens(sim: MatchSim) -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(sim.fighters.size())
	g.fill(1)
	return g


func test_fk_reconstruction_matches_simulation() -> void:
	var sim := _fighting_sim(2)
	await step_sim(sim, 4.0)
	var body := NetSnapshot.encode_body(sim, _gens(sim))
	var r := NetReader.new(body)
	var d := NetSnapshot.decode_body(r)
	check(r.ok and r.at_end(), "decodes exactly: %s" % r.error)
	var worst_pos := 0.0
	var worst_rot := 0.0
	for i in sim.fighters.size():
		var f := sim.fighters[i]
		var fd: Dictionary = d["fighters"][i]
		var xf := NetSnapshot.fk(f.creature.body, fd["root"], fd["rots"])
		var truth := f.rig.segment_transforms()
		check_eq(xf.size(), truth.size(), "all segments rebuilt")
		for s in truth.size():
			worst_pos = maxf(worst_pos, xf[s].origin.distance_to(truth[s].origin))
			worst_rot = maxf(worst_rot, rad_to_deg(xf[s].basis.get_rotation_quaternion().angle_to(truth[s].basis.get_rotation_quaternion())))
		check_near(float(fd["health"]), f.health, 0.051, "health")
		check_eq(int(fd["state"]), f.state, "state")
	print("    FK reconstruction: worst segment position error %.2f mm, rotation error %.3f deg" % [worst_pos * 1000.0, worst_rot])
	check(worst_pos < 0.02, "segment positions within 2 cm (worst %.4f m)" % worst_pos)
	check(worst_rot < 0.3, "segment rotations within 0.3 deg (worst %.3f)" % worst_rot)


func test_snapshot_sizes_fit_one_packet() -> void:
	var sim2 := _fighting_sim(2)
	await step_sim(sim2, 1.0)
	var b2 := NetSnapshot.encode_body(sim2, _gens(sim2)).size() + 9
	var sim8 := _fighting_sim(8)
	await step_sim(sim8, 1.0)
	var b8 := NetSnapshot.encode_body(sim8, _gens(sim8)).size() + 9
	print("    snapshot sizes (dev_biped, 13 segments): 2 fighters %d B, 8 fighters %d B" % [b2, b8])
	check(b2 < 400, "duel snapshot < 400 B (%d)" % b2)
	check(b8 < 1200, "8-fighter snapshot stays under one MTU (%d)" % b8)


func test_roster_codec_and_generations() -> void:
	var w := NetWriter.new()
	NetSnapshot.encode_roster(w, [{"slot": 3, "gen": 7, "creature": "dev_biped", "scale": 1.6, "team": 1, "name": "Unit",
		"kind": "net", "despawned": false}])
	var r := NetReader.new(w.data())
	var es := NetSnapshot.decode_roster(r)
	check(r.ok and es.size() == 1, "roster decodes")
	var rep := NetReplica.new()
	rep.reset({"tick_rate": 120, "snapshot_rate": 30, "match_id": 1, "fighters": [
		{"slot": 0, "gen": 1, "creature": "dev_biped", "scale": 1.0, "team": 0, "name": "A", "kind": "net", "despawned": false}]})
	check(rep.apply_roster_entry(es[0]), "new slot is a body change")
	check_eq(rep.slot_count(), 4, "slots grow with the roster")
	var same := (es[0] as Dictionary).duplicate()
	same["kind"] = "bot"
	check(not rep.apply_roster_entry(same), "controller change keeps the generation (no view rebuild)")
	check_eq(str(rep.roster[3]["kind"]), "bot")
	check(rep.roster[3].get("def") != null, "creature definition resolved for the slot")


func test_replica_interpolation_teleports_and_events() -> void:
	var rep := NetReplica.new()
	rep.reset({"tick_rate": 120, "snapshot_rate": 30, "match_id": 1, "fighters": [
		{"slot": 0, "gen": 1, "creature": "dev_biped", "scale": 1.0, "team": 0, "name": "A", "kind": "net", "despawned": false}]})
	var c := Content.creature("dev_biped")
	var rots: Array[Quaternion] = []
	for s in c.body.segments.size():
		rots.append(Quaternion.IDENTITY)
	var mk := func(root: Vector3, gen: int) -> Dictionary:
		return {"fighters": [{"gen": gen, "state": 0, "flags": 0, "root": root, "rots": rots, "health": 100.0, "max_health": 100.0,
			"stamina": 100.0, "max_stamina": 100.0, "poise": 100.0, "max_poise": 100.0, "hype": 0.0, "lives": 1, "target": -1,
			"cooldowns": {}, "statuses": []}], "entities": [], "props": [],
			"mode": {"phase": 1, "round": 0, "timer": 50.0, "flags": 1, "winner": -2, "round_winner": -2, "teams": [], "status": "",
				"view": {"ball": Vector3(0, 0, 0)}, "hud": {}}}
	rep.add_snapshot(120, mk.call(Vector3(0, 1, 0), 1), 10.0)
	rep.add_snapshot(124, mk.call(Vector3(1, 1, 0), 1), 10.0333)
	rep.render_time = 122.0 / 120.0
	var s: Dictionary = rep.sample()
	var root: Vector3 = s["fighters"][0]["root"]
	check_near(root.x, 0.5, 0.01, "halfway interpolation")
	check_eq((s["fighters"][0]["xforms"] as Array).size(), c.body.segments.size(), "transforms rebuilt")
	# teleport (respawn/round reset): no smear across the arena
	rep.add_snapshot(128, mk.call(Vector3(-4, 1, 0), 1), 10.0666)
	rep.render_time = 125.0 / 120.0
	var t: Vector3 = rep.sample()["fighters"][0]["root"]
	check(t.x > 0.9 or t.x < -3.9, "teleport snaps instead of sliding (%s)" % t)
	# generation change: the new body is not interpolated from the old one
	rep.add_snapshot(132, mk.call(Vector3(-4.5, 1, 0), 2), 10.1)
	rep.render_time = 131.0 / 120.0
	var g: Dictionary = rep.sample()["fighters"][0]
	check_eq(int(g["gen"]), 2, "switches to the new generation past the midpoint")
	check_eq((g["xforms"] as Array).size(), 0, "unknown generation is not rendered until its roster entry arrives")
	# events fire when the render clock reaches their tick
	rep.add_events([{"type": "hit", "tick": 140}, {"type": "ko", "tick": 125}])
	var due := rep.pop_due_events()
	check_eq(due.size(), 1, "only past events are due")
	check_eq(str(due[0]["type"]), "ko")
	rep.render_time = 141.0 / 120.0
	check_eq(rep.pop_due_events().size(), 1, "the later event follows")


func test_hud_mirror_drives_real_fight_hud() -> void:
	var rep := NetReplica.new()
	rep.reset({"tick_rate": 120, "snapshot_rate": 30, "match_id": 1, "fighters": [
		{"slot": 0, "gen": 1, "creature": "dev_biped", "scale": 1.0, "team": 0, "name": "Alice", "kind": "net", "despawned": false},
		{"slot": 1, "gen": 1, "creature": "dev_biped", "scale": 1.0, "team": 1, "name": "Bob", "kind": "bot", "despawned": false}]})
	var mirror := NetHudMirror.new()
	mirror.build({"rules": {"rounds": 3, "round_time": 99, "lives": 1}, "mode": "standard", "you": 0}, rep)
	check_eq(mirror.sim.fighters[0].controller_kind, "player", "this client's own fighter is presented as the local player")
	check_eq(mirror.sim.fighters[1].controller_kind, "bot", "others keep their kind")
	var c := Content.creature("dev_biped")
	var rots: Array[Quaternion] = []
	for s in c.body.segments.size():
		rots.append(Quaternion.IDENTITY)
	var fd := {"gen": 1, "state": 0, "flags": NetSnapshot.F_JUICED, "root": Vector3.ZERO, "rots": rots, "health": 42.0,
		"max_health": 100.0, "stamina": 50.0, "max_stamina": 100.0, "poise": 80.0, "max_poise": 100.0, "hype": 100.0,
		"lives": 2, "target": 1, "cooldowns": {"ability1": 2.5}, "statuses": [{"id": "status_scorch", "element": "scorch", "left": 1.5}]}
	var sample := {"fighters": [fd, fd.duplicate()], "mode": {"phase": 1, "round": 1, "timer": 42.5, "flags": 1, "winner": -2,
		"round_winner": -2, "teams": [{"team": 0, "wins": 1, "score": 0}], "status": "SUDDEN DEATH",
		"hud": {"rows": [{"label": "Red", "value": 3, "team": 0}], "status": "SUDDEN DEATH"}, "view": {}}}
	mirror.update(sample, 1.0 / 60.0)
	var f0 := mirror.sim.fighters[0]
	check_near(f0.health, 42.0, 0.001, "health mirrored")
	check(f0.time < f0.juiced_until, "juice flag mirrored")
	check_eq(f0.target, mirror.sim.fighters[1], "target mirrored")
	check_eq(mirror.sim.mode.hud_status(), "SUDDEN DEATH")
	check_eq(int(mirror.sim.mode.round_wins[0]), 1)
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := FightHud.new()
	layer.add_child(hud)
	hud.setup(mirror.sim, 0)
	await wait_frames(5)
	check(is_instance_valid(hud), "FightHud runs on the mirror")
	layer.queue_free()
	await wait_frames(1)
	mirror.free_all()
