extends TestCase
## MCH-08 / ART (v0.9.16 referee): Jeremy's Cage Rules referee model and the view-only RefereeView.
## (a) the imported GLB loads, every body segment binds to a bone at its pivot, nothing physical;
## (b) the GDScript pose evaluator reproduces the segment transforms baked by the original Cage Rules
##     JS (tools/cage_rules/import.js runs render.js FighterModel.update in Node);
## (c) the director's spots with synthetic match states: intro, fight, knockdown, stoppage, ceremony
##     and break stay on the floor, on the far side from the camera, never between the fighters.

const CAM := Vector3(0, 3.2, 8.0)
const DT := 1.0 / 60.0
const POS_TOL := 0.01          ## metres (1 cm)
const ROT_TOL := 2.0           ## degrees


func _referee(arena_id := "arena_gullet") -> RefereeView:
	var rv := RefereeView.new()
	add_child(rv)
	rv.setup(Content.arena(arena_id), {"intro_time": 2.2})
	return rv


func _fighters(a: Vector3, b: Vector3, sa := Fighter.State.NEUTRAL, sb := Fighter.State.NEUTRAL, radius := 0.35) -> Array:
	return [{"index": 0, "team": 0, "pos": a, "state": sa, "name": "Varga", "radius": radius},
		{"index": 1, "team": 1, "pos": b, "state": sb, "name": "Knell", "radius": radius}]


func _state(phase: int, fighters: Array, ref := {}, winner := -2, round_index := 0) -> Dictionary:
	return {"phase": phase, "round": round_index, "winner": winner, "fighters": fighters, "ref": ref}


func _run(rv: RefereeView, st: Dictionary, seconds: float, cam := CAM) -> void:
	for i in int(seconds / DT):
		rv.update_view(st, cam, DT)


func _pos(rv: RefereeView) -> Vector3:
	return rv.debug_state()["pos"]


func _on_floor(rv: RefereeView, p: Vector3) -> bool:
	return rv.arena.clamp_point(p, 0.3).distance_to(p) < 1e-3


func _collision_objects(n: Node) -> int:
	var c := 1 if n is CollisionObject3D else 0
	for k in n.get_children():
		c += _collision_objects(k)
	return c


# ---- (a) model ----------------------------------------------------------------------------------

func test_referee_model_binds_every_segment_and_is_view_only() -> void:
	var data := RefereeView.load_data()
	check(not data.is_empty(), "assets/data/cage_referee.json loads")
	check_near(float(data.get("scale", 0.0)), 1.06, 1e-9, "scaled like Varga")
	check(ResourceLoader.exists(str(data.get("model", ""))), "referee GLB imported")
	check(Content.get_entry("creatures", "cage_referee").is_empty(), "the referee is not a content creature")
	var c := RefereeView.make_creature(data)
	check(c.body != null and c.body.is_valid(), "view-only body parses: %s" % [c.errors])
	check_eq(c.body.segments.size(), 11, "the eleven Cage Rules segments")
	var varga := Content.creature("f_varga")
	var rv := _referee()
	check(rv.view != null and rv.view._skeleton != null, "imported skeleton")
	if rv.view == null or rv.view._skeleton == null:
		rv.queue_free()
		return
	var sk := rv.view._skeleton
	for s: BodyDef.Seg in c.body.segments:
		var bi := rv.view._bone_of_seg[s.index]
		check(bi >= 0, "segment %s bound" % s.id)
		if bi >= 0:
			# bind pose = the segment pivot (sits at the origin; rests are relative to the rig root)
			var rest := sk.get_bone_global_rest(bi).origin
			check(rest.distance_to(s.pivot) < 1e-4, "%s bone rest %s on its pivot %s" % [s.id, rest, s.pivot])
			check(s.pivot.distance_to(varga.body.seg(s.id).pivot) < 1e-5, "%s pivot = Varga's" % s.id)
	_run(rv, _state(MatchMode.Phase.FIGHT, _fighters(Vector3(-1, 0, 0), Vector3(1, 0, 0))), 0.5)
	check_eq(_collision_objects(rv), 0, "no physics bodies or areas under RefereeView")
	var feet_y := minf(rv.view.segment_world(c.body.seg_index["lShin"]).origin.y, rv.view.segment_world(c.body.seg_index["rShin"]).origin.y)
	check(feet_y > 0.2 and feet_y < 0.6, "standing on the floor (shin pivots %.3f m up)" % feet_y)
	rv.queue_free()
	await wait_frames(1)


# ---- (b) the pose evaluator port ----------------------------------------------------------------

func test_pose_port_reproduces_the_cage_rules_baked_transforms() -> void:
	var data := RefereeView.load_data()
	var baked: Array = data.get("baked", [])
	var pd: Dictionary = data.get("poses", {})
	var scale := float(data.get("scale", 1.06))
	check(baked.size() >= 12 + 4 + 3, "every REF_POSE, the animated hands, placement, lerp and step are baked")
	var ids := []
	var worst_p := 0.0
	var worst_r := 0.0
	for smp in baked:
		var s: Dictionary = smp
		ids.append(str(s["id"]))
		var m := RefereePose.new()
		m.setup(data.get("rig", {}), scale)
		var pose := RefereePose.Pose.from_dict(pd[str(s["pose"])])
		if bool(s.get("anim", false)):
			RefereeView.set_hands(pose, str(s["pose"]), float(s["u"]))
		if s.has("start"):
			var st: Dictionary = s["start"]
			m.initialized = true
			m.snap = false
			m.px = float(st["px"])
			m.pz = float(st["pz"])
			m.yaw = float(st["yaw"])
			m.vx = float(st["vx"])
			m.vz = float(st["vz"])
			m.step_phase = float(st["step"])
			m.pose = RefereePose.Pose.from_dict(pd[str(st["pose"])])
		else:
			m.snap = true
		m.update(float(s["x"]) * scale, float(s["z"]) * scale, float(s["yaw"]), pose, bool(s["moving"]), float(s["speed"]), float(s["dt"]), float(s["time"]))
		var segs: Dictionary = s["segs"]
		for id in RefereePose.SEG_ORDER:
			var want: Dictionary = segs[id]
			var wp := Vector3(float(want["p"][0]), float(want["p"][1]), float(want["p"][2]))
			var wq := Quaternion(float(want["q"][0]), float(want["q"][1]), float(want["q"][2]), float(want["q"][3])).normalized()
			var got := m.transform_of(id)
			var dp := got.origin.distance_to(wp)
			var dr := rad_to_deg(got.basis.get_rotation_quaternion().angle_to(wq))
			worst_p = maxf(worst_p, dp)
			worst_r = maxf(worst_r, dr)
			check(dp < POS_TOL, "%s %s position %s, Cage Rules %s" % [s["id"], id, got.origin, wp])
			check(dr < ROT_TOL, "%s %s rotation off by %.2f deg" % [s["id"], id, dr])
	for k in ["watch", "ground", "ready", "go", "stop", "kdWatch", "waveUp", "waveOff", "hold", "raiseL", "raiseR", "raiseBoth"]:
		check(ids.has(k), "static pose %s is baked" % k)
	print("  referee pose port: worst position error %.6f m, worst rotation error %.4f deg over %d samples" % [worst_p, worst_r, baked.size()])


# ---- (c) director -------------------------------------------------------------------------------

func test_intro_between_the_fighters_on_the_far_side_then_go() -> void:
	var rv := _referee()
	var f := _fighters(Vector3(-1.6, 0, 0), Vector3(1.6, 0, 0))
	var st := _state(MatchMode.Phase.INTRO, f)
	st["phase_time"] = 0.0
	for i in 60:
		st["phase_time"] = i * DT
		rv.update_view(st, CAM, DT)
	var d := rv.debug_state()
	check_eq(str(d["mode"]), "intro")
	check_eq(str(d["pose"]), "ready", "instructions first")
	var p: Vector3 = d["pos"]
	check(p.z < -0.4 and absf(p.x) < 0.3, "between them, nudged to the far side from the camera: %s" % p)
	check(_on_floor(rv, p), "on the floor")
	st["phase_time"] = 1.9
	rv.update_view(st, CAM, DT)
	check_eq(str(rv.debug_state()["pose"]), "go", "\"fight!\" in the last 0.6 s of the intro")
	rv.queue_free()
	await wait_frames(1)


func test_fight_neutral_spot_is_a_far_side_t_and_never_between_them() -> void:
	var rv := _referee()
	var a := Vector3(-1.1, 0, 0)
	var b := Vector3(1.1, 0, 0)
	_run(rv, _state(MatchMode.Phase.FIGHT, _fighters(a, b)), 3.0)
	var p := _pos(rv)
	check_eq(str(rv.debug_state()["mode"]), "fight")
	check_eq(str(rv.debug_state()["pose"]), "watch")
	check(p.z < -1.5, "the T on the far side from the camera: %s" % p)
	check(_on_floor(rv, p), "on the floor: %s" % p)
	# a standing exchange that circles the arena under the broadcast camera (FightCamera squares up to
	# the fighters' line), and once more under a camera that stays put: he keeps out of their line
	for orbit in [true, false]:
		var far := 0
		var frames := 0
		var closest := 99.0
		var cam_yaw := 0.0
		for i in int(10.0 / DT):
			var t := i * DT
			var c := Vector3(sin(t * 0.35) * 1.2, 0, cos(t * 0.27) * 0.8)
			var ang := t * 0.55
			var off := Vector3(cos(ang), 0, sin(ang)) * (0.9 + 0.3 * sin(t * 1.3))
			var fa := c + off
			var fb := c - off
			var mid := (fa + fb) * 0.5
			var cam := CAM
			if orbit:
				cam_yaw = _camera_yaw(cam_yaw, fa, fb, DT)
				cam = mid + Vector3(sin(cam_yaw), 0, cos(cam_yaw)) * 7.0 + Vector3.UP * 3.2
			rv.update_view(_state(MatchMode.Phase.FIGHT, _fighters(fa, fb)), cam, DT)
			var q := _pos(rv)
			check(_on_floor(rv, q), "stays on the floor at %.2f s: %s" % [t, q])
			if t < 1.0:
				continue
			frames += 1
			var between := RefereeView.seg_dist(Vector2(q.x, q.z), Vector2(fa.x, fa.z), Vector2(fb.x, fb.z))
			closest = minf(closest, between)
			if (q - mid).dot(cam - mid) < 0.0:
				far += 1
		print("  referee exchange (%s camera): far side %d / %d frames, closest %.2f m to the fighters' line" % ["orbiting" if orbit else "fixed", far, frames, closest])
		check(closest > 0.6, "never between the fighters (closest %.2f m to their line)" % closest)
		check(far > frames * (0.9 if orbit else 0.7), "on the far side from the camera (%d / %d frames)" % [far, frames])
	rv.queue_free()
	await wait_frames(1)


## FightCamera's yaw rule: square up to the fighters' line, the nearer of the two sides, eased.
func _camera_yaw(yaw: float, fa: Vector3, fb: Vector3, dt: float) -> float:
	var line := fb - fa
	line.y = 0.0
	var desired := yaw
	if line.length() > 0.3:
		var perp := atan2(line.z, -line.x)
		var alt := wrapf(perp + PI, -PI, PI)
		desired = perp if absf(wrapf(perp - yaw, -PI, PI)) < absf(wrapf(alt - yaw, -PI, PI)) else alt
	return lerp_angle(yaw, desired, MathX.damp_factor(0.6, dt) * 0.6)


func test_knockdown_hold_off_watch_and_wave_up() -> void:
	var rv := _referee()
	var att := Vector3(-0.5, 0, 0.2)
	var down := Vector3(0.7, 0, 0.2)
	_run(rv, _state(MatchMode.Phase.FIGHT, _fighters(att, down)), 2.0)
	# a throw knockdown (no count) is not his: he stays at his spot
	_run(rv, _state(MatchMode.Phase.FIGHT, _fighters(att, down, Fighter.State.NEUTRAL, Fighter.State.KNOCKDOWN)), 0.3)
	check_eq(str(rv.debug_state()["mode"]), "fight", "uncounted knockdown: no intervention")
	_run(rv, _state(MatchMode.Phase.FIGHT, _fighters(att, down)), 0.5)
	# a counted strike knockdown: rush in, arm out, "Back up!"
	var left := 4.0
	var saw_hold := false
	var hold_between := true
	var t := 0.0
	while t < 1.4:
		var stt := Fighter.State.KNOCKDOWN if t < 0.6 else Fighter.State.DOWN
		rv.update_view(_state(MatchMode.Phase.FIGHT, _fighters(att, down, Fighter.State.NEUTRAL, stt),
			{"count": {"fighter": 1, "n": 1, "left": left}}), CAM, DT)
		t += DT
		left -= DT if t >= 0.6 else 0.0
		var d := rv.debug_state()
		if str(d["mode"]) == "kd_hold":
			saw_hold = true
			check_eq(str(d["pose"]), "stop")
			check_eq(str(d["say"]), "Back up!")
			var tg: Vector3 = d["target"]
			var along := (tg - down).dot((att - down).normalized())
			hold_between = hold_between and along > 0.2 and along < (att - down).length()
			check(tg.z <= down.z + 0.01, "a little to the far side of their line: %s" % tg)
	check(saw_hold, "holds the attacker off")
	check(hold_between, "stands between the downed fighter and the attacker")
	check(rv.bubble_text() == "Back up!", "speech bubble shows \"Back up!\" (%s)" % rv.bubble_text())
	# after KD_HOLD he bends over the downed fighter
	var modes := {}
	while left > 1.2:
		rv.update_view(_state(MatchMode.Phase.FIGHT, _fighters(att, down, Fighter.State.NEUTRAL, Fighter.State.DOWN),
			{"count": {"fighter": 1, "n": 1 + int(4.0 - left), "left": left}}), CAM, DT)
		left -= DT
		modes[str(rv.debug_state()["mode"])] = true
	check(modes.has("kd_watch"), "kdWatch over the downed fighter: %s" % [modes.keys()])
	check_eq(str(rv.debug_state()["pose"]), "kdWatch")
	check(_pos(rv).distance_to(down) < 1.6, "close to the downed fighter: %s" % _pos(rv))
	# the last second of the count: wave him up, and keep waving through a forced get-up
	while left > 0.05:
		rv.update_view(_state(MatchMode.Phase.FIGHT, _fighters(att, down, Fighter.State.NEUTRAL, Fighter.State.DOWN),
			{"count": {"fighter": 1, "n": 4, "left": left}}), CAM, DT)
		left -= DT
	check_eq(str(rv.debug_state()["mode"]), "wave_up", "waves him up in the last second")
	check_eq(str(rv.debug_state()["pose"]), "waveUp")
	rv.update_view(_state(MatchMode.Phase.FIGHT, _fighters(att, down, Fighter.State.NEUTRAL, Fighter.State.GETUP),
		{"count": {"fighter": 1, "n": 4, "left": 0.0}}), CAM, DT)
	check_eq(str(rv.debug_state()["mode"]), "wave_up", "keeps waving through the forced get-up")
	# standing again: back to his spot
	_run(rv, _state(MatchMode.Phase.FIGHT, _fighters(att, down)), 0.2)
	check_eq(str(rv.debug_state()["mode"]), "fight")
	check(_on_floor(rv, _pos(rv)), "on the floor")
	rv.queue_free()
	await wait_frames(1)


func test_voluntary_get_up_is_watched_not_waved() -> void:
	var rv := _referee()
	var att := Vector3(-0.6, 0, 0)
	var down := Vector3(0.6, 0, 0)
	_run(rv, _state(MatchMode.Phase.FIGHT, _fighters(att, down, Fighter.State.NEUTRAL, Fighter.State.DOWN),
		{"count": {"fighter": 1, "n": 1, "left": 3.0}}), 2.0)
	rv.update_view(_state(MatchMode.Phase.FIGHT, _fighters(att, down, Fighter.State.NEUTRAL, Fighter.State.GETUP),
		{"count": {"fighter": 1, "n": 2, "left": 2.5}}), CAM, DT)
	check_eq(str(rv.debug_state()["mode"]), "kd_watch", "a fighter who gets up on his own is watched")
	check_eq(str(rv.debug_state()["pose"]), "watch")
	rv.queue_free()
	await wait_frames(1)


func test_stoppage_wave_off_then_the_winners_arm_goes_up() -> void:
	var rv := _referee()
	var win := Vector3(-0.7, 0, 0.3)
	var lose := Vector3(0.8, 0, 0.1)
	_run(rv, _state(MatchMode.Phase.FIGHT, _fighters(win, lose)), 1.5)
	var f := _fighters(win, lose, Fighter.State.NEUTRAL, Fighter.State.DOWN)
	var modes := []
	var raised_side := ""
	var t := 0.0
	while t < rv.decision_time:
		var st := _state(MatchMode.Phase.ROUND_END, f, {"stop": 1}, 0)
		st["phase_time"] = t
		rv.update_view(st, CAM, DT)
		t += DT
		var d := rv.debug_state()
		var md := str(d["mode"])
		if modes.is_empty() or modes[modes.size() - 1] != md:
			modes.append(md)
		var p: Vector3 = d["pos"]
		check(_on_floor(rv, p), "on the floor at %.2f s: %s" % [t, p])
		if md == "wave_off" and t > 1.0:
			check_eq(str(d["pose"]), "waveOff")
			check(p.distance_to(lose) < 1.4, "waving it off over the loser: %s" % p)
		if md == "raise":
			raised_side = str(d["pose"])
	check_eq(modes[0], "wave_off", "waves it off first: %s" % [modes])
	check(modes.has("raise"), "then raises the winner's arm: %s" % [modes])
	var d2 := rv.debug_state()
	var p2: Vector3 = d2["pos"]
	check(p2.distance_to(win) < 1.3, "beside the winner: %s vs %s" % [p2, win])
	check_eq(str(d2["say"]), "Varga wins!")
	check_eq(rv.bubble_text(), "Varga wins!")
	# the raised hand is on the winner's side (his left = +X of his own frame)
	var c := rv.creature.body
	var lh := rv.view.segment_world(c.seg_index["lForearm"])
	var rh := rv.view.segment_world(c.seg_index["rForearm"])
	var raised := lh if lh.origin.y > rh.origin.y else rh
	var other := rh if raised == lh else lh
	var flat := func(v: Vector3) -> Vector2: return Vector2(v.x - win.x, v.z - win.z)
	check(absf(lh.origin.y - rh.origin.y) > 0.25, "one arm clearly up")
	check((flat.call(raised.origin) as Vector2).length() < (flat.call(other.origin) as Vector2).length(),
		"the raised arm is the one on the winner's side (%s)" % raised_side)
	var fwd := MathX.forward_of_yaw(float(d2["yaw"]))
	check(fwd.dot((CAM - p2).normalized()) > 0.7, "faces the camera for the announcement")
	rv.queue_free()
	await wait_frames(1)


func test_draw_raises_both_arms_and_decision_waits_for_the_cards() -> void:
	var rv := _referee()
	var a := Vector3(-1.0, 0, 0)
	var b := Vector3(1.0, 0, 0)
	var f := _fighters(a, b)
	var seen := {}
	var t := 0.0
	while t < rv.decision_time:
		var st := _state(MatchMode.Phase.ROUND_END, f, {}, -1)
		st["phase_time"] = t
		rv.update_view(st, CAM, DT)
		t += DT
		seen[str(rv.debug_state()["mode"])] = true
		check(_on_floor(rv, _pos(rv)), "on the floor")
	check(seen.has("decision") and not seen.has("wave_off"), "a decision has no wave-off: %s" % [seen.keys()])
	check_eq(str(rv.debug_state()["pose"]), "raiseBoth", "both arms up for a draw")
	check_eq(str(rv.debug_state()["say"]), "It's a draw!")
	var p := _pos(rv)
	check(absf(p.x) < 0.5, "between both fighters: %s" % p)
	# match end keeps the announcement up
	rv.update_view(_state(MatchMode.Phase.MATCH_END, f, {}, -1), CAM, DT)
	check_eq(str(rv.debug_state()["pose"]), "raiseBoth")
	rv.queue_free()
	await wait_frames(1)


func test_break_between_rounds_goes_to_the_centre_facing_the_camera() -> void:
	var rv := _referee()
	var f := _fighters(Vector3(-2.2, 0, 0.5), Vector3(2.0, 0, -0.4))
	_run(rv, _state(MatchMode.Phase.FIGHT, f), 1.0)
	_run(rv, _state(MatchMode.Phase.ROUND_END, f), 2.5)
	var d := rv.debug_state()
	check_eq(str(d["mode"]), "break")
	check_eq(str(d["pose"]), "ready")
	check((d["pos"] as Vector3).length() < 0.5, "in the centre: %s" % d["pos"])
	check(MathX.forward_of_yaw(float(d["yaw"])).dot((CAM - (d["pos"] as Vector3)).normalized()) > 0.7, "faces the camera")
	# an HP-scored KO with the referee is waved off before the break
	var f2 := _fighters(Vector3(-0.6, 0, 0), Vector3(0.7, 0, 0), Fighter.State.CELEBRATE, Fighter.State.KO)
	_run(rv, _state(MatchMode.Phase.FIGHT, f2, {}, -2, 1), 0.5)
	rv.update_view(_state(MatchMode.Phase.ROUND_END, f2, {"wave_off": true}, -2, 1), CAM, DT)
	check_eq(str(rv.debug_state()["mode"]), "wave_off", "a KO is waved off")
	rv.queue_free()
	await wait_frames(1)


func test_rect_arena_with_props_and_large_fighters_keeps_him_clear() -> void:
	var rv := _referee("arena_drydock")
	var ar := rv.arena
	var ext := ar.extent()
	# fighters pressed against the far wall: his far-side spot is off the floor, so he angles off
	var a := Vector3(-0.9, 0, ext.position.y + 1.0)
	var b := Vector3(0.9, 0, ext.position.y + 1.0)
	var big := _fighters(a, b, Fighter.State.NEUTRAL, Fighter.State.NEUTRAL, 0.9)
	_run(rv, _state(MatchMode.Phase.FIGHT, big), 4.0)
	var p := _pos(rv)
	check(_on_floor(rv, p), "on the floor of a rect arena: %s" % p)
	for fp in [a, b]:
		var v: Vector3 = fp
		check(Vector2(p.x - v.x, p.z - v.z).length() > 1.2, "keeps room from a large fighter (%s vs %s)" % [p, v])
	for item in ar.all_props():
		var def := ArenaCatalog.prop(str(item.get("type", "")))
		if not def.is_empty() and bool(def.get("solid", false)):
			check(ArenaCatalog.footprint_distance(item, def, Vector2(p.x, p.z)) > 0.2, "not inside %s" % item.get("type", ""))
	# walking a long way across the rect never leaves the floor
	for i in int(6.0 / DT):
		var t := i * DT
		var c := Vector3(sin(t * 0.6) * (ext.size.x * 0.35), 0, cos(t * 0.4) * (ext.size.y * 0.35))
		rv.update_view(_state(MatchMode.Phase.FIGHT, _fighters(c + Vector3(0.8, 0, 0), c - Vector3(0.8, 0, 0), Fighter.State.NEUTRAL, Fighter.State.NEUTRAL, 0.9)), CAM, DT)
		check(_on_floor(rv, _pos(rv)), "on the floor at %.2f s: %s" % [t, _pos(rv)])
	rv.queue_free()
	await wait_frames(1)


func test_state_from_sim_and_from_the_net_mirror() -> void:
	var sim := make_sim("arena_gullet", {"rounds": 3, "round_time": 99, "format": "duel"},
		[{"creature": "f_varga", "team": 0}, {"creature": "f_knell", "team": 1}])
	var st := RefereeView.state_from_sim(sim)
	check_eq(int(st["phase"]), MatchMode.Phase.INTRO)
	check_eq(int(st["winner"]), -2)
	check(float(st["phase_time"]) >= 0.0, "local play supplies the phase time")
	check_eq((st["fighters"] as Array).size(), 2)
	var f0: Dictionary = st["fighters"][0]
	check(f0["pos"] is Vector3 and str(f0["name"]) != "", "plain fighter data")
	check(float(f0["radius"]) > 0.25 and float(f0["radius"]) < 0.6, "Varga's body radius %.3f" % float(f0["radius"]))
	var rv := _referee()
	_run(rv, st, 0.3)
	check(_on_floor(rv, _pos(rv)), "runs from a real sim's state")
	rv.queue_free()
	# the network client's mirror: the same fields from replicated data, phase time left to the view
	var rep := NetReplica.new()
	rep.reset({"tick_rate": 120, "snapshot_rate": 30, "match_id": 1, "fighters": [
		{"slot": 0, "gen": 1, "creature": "dev_biped", "scale": 1.0, "team": 0, "name": "Alice", "kind": "net", "despawned": false},
		{"slot": 1, "gen": 1, "creature": "dev_biped", "scale": 1.0, "team": 1, "name": "Bob", "kind": "bot", "despawned": false}]})
	var mirror := NetHudMirror.new()
	mirror.build({"rules": {"rounds": 3, "round_time": 99, "lives": 1, "referee": true}, "mode": "standard", "you": 0}, rep)
	var c := Content.creature("dev_biped")
	var rots: Array[Quaternion] = []
	for s in c.body.segments.size():
		rots.append(Quaternion.IDENTITY)
	var fd := {"gen": 1, "state": Fighter.State.DOWN, "flags": 0, "root": Vector3(0.5, 0.9, 0.0), "rots": rots, "health": 100.0,
		"max_health": 100.0, "stamina": 50.0, "max_stamina": 100.0, "poise": 80.0, "max_poise": 100.0, "hype": 0.0,
		"lives": 1, "target": 0, "cooldowns": {}, "statuses": []}
	var fa := fd.duplicate()
	fa["state"] = Fighter.State.NEUTRAL
	fa["root"] = Vector3(-0.5, 0.9, 0.0)
	var sample := {"fighters": [fa, fd], "mode": {"phase": MatchMode.Phase.FIGHT, "round": 1, "timer": 42.5, "flags": 1, "winner": -2,
		"round_winner": -2, "teams": [], "status": "", "hud": {}, "view": {"mode": "standard", "referee": {"count": {"fighter": 1, "n": 2, "left": 2.0}}}}}
	mirror.update(sample, 1.0 / 60.0)
	var ms := RefereeView.state_from_sim(mirror.sim, true)
	check_eq(int(ms["phase"]), MatchMode.Phase.FIGHT)
	check_eq(int(ms["round"]), 1)
	check(float(ms["phase_time"]) < 0.0, "replicated: the view clocks the phase itself")
	check_eq(int((ms["ref"]["count"] as Dictionary)["fighter"]), 1, "view_state.referee from the snapshot")
	var mf: Array = ms["fighters"]
	check_eq(mf.size(), 2)
	check_eq(str(mf[0]["name"]), "Alice")
	check_eq(int(mf[1]["state"]), Fighter.State.DOWN)
	check((mf[1]["pos"] as Vector3).distance_to(Vector3(0.5, 0.9, 0.0)) < 1e-4, "root position from the snapshot")
	mirror.free_all()
	await wait_frames(1)
