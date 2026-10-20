class_name RefereeView
extends Node3D
## Jeremy's Cage Rules referee in a Critterweight arena: VIEW ONLY. A port of render.js `class Referee`
## (the director: where he stands, where he looks, which pose) driving a CreatureView of the imported
## model (assets/models/referee/cage_referee.glb) through RefereePose (the original kinematic pose
## evaluator). He reads plain match data and never changes an outcome: the sim's referee rules
## (counts, protection, stoppages) live in MatchMode; this only shows them.
##
## Invariants:
##  * No physics: nothing under this node is a CollisionObject3D (bodies/areas would share the sim's
##    World3D). Callers must NOT parent it under ModeView (ModeView frees its children) and must NOT
##    add it to camera framing (_camera_points / focus); occluder fading does not know about him.
##  * Driven only by update_view(state, cam_pos, dt) with plain data that exists identically on a
##    host and on network clients; the only local inputs are the camera position and the frame time,
##    so two clients may place him slightly differently (cosmetic, as in Cage Rules).
##  * Fighters are never forced into poses (they are physics rigs): at the bout end he walks to the
##    winner and raises the arm on the winner's side; both arms for a draw.
##  * Units: Critterweight world metres, yaw 0 faces +Z. Distances tuned for Cage Rules' fighters
##    grow by each fighter's extra body radius (fighter "radius" beyond BASE_RADIUS).
##
## Public API:
##   setup(arena: ArenaDef, rules: Dictionary) -> void      (rules: the match rules; intro_time is read)
##   update_view(state: Dictionary, cam_pos: Vector3, dt: float) -> void   (every rendered frame)
##   static state_from_sim(sim: MatchSim, replicated := false) -> Dictionary
##   debug_state() -> Dictionary   (tests / tools: mode, pose, pos, target, face, say)
##
## state = {
##   "phase": int (MatchMode.Phase), "phase_time": float (seconds in the phase; < 0 or missing = the
##   view counts it locally from phase/round changes), "round": int (round index), "winner": int
##   (MatchMode.winner_team: -2 undecided, -1 draw, else the team), "ref": Dictionary
##   (MatchMode.view_state()["referee"], or {}: {"count": {"fighter", "n", "left"}, "stop": int,
##   "wave_off": bool}, every key optional), "fighters": [{"index": int, "team": int, "pos": Vector3
##   (root / ground position), "state": int (Fighter.State), "name": String, "radius": float
##   (optional, horizontal body radius)}] }
##
## MatchScene (local play): after the CreatureViews render in _process,
##   referee_view.update_view(RefereeView.state_from_sim(sim), camera.global_position, delta)
## NetMatchScene (client): every field exists on its NetHudMirror, whose sim carries the replicated
## mode phase/round/winner (snapshot mode block), view_state() (snapshot "view", which holds
## "referee"), and per fighter index/team/display_name/state/creature/despawned and pos()
## (MirrorRig root from the interpolated snapshot). phase_time is NOT replicated (MirrorMode never
## ticks), so pass replicated = true and the view clocks the phase itself. After mirror.update():
##   referee_view.update_view(RefereeView.state_from_sim(mirror.sim, true), camera.global_position, dt)
## (Equivalent by hand: phase/round/winner = _sample["mode"]["phase"/"round"/"winner"], ref =
## _sample["mode"]["view"].get("referee", {}), fighters from _sample["fighters"][i] "root"/"state"
## (skip gen 0) with replica.roster[i] "team"/"name"/"def".)

const DATA_PATH := "res://assets/data/cage_referee.json"
const MATCH_MODE_PATH := "res://src/sim/modes/match_mode.gd"
const BASE_RADIUS := 0.35       ## body radius of a Cage Rules-sized fighter (Varga); larger bodies add clearance
const MAX_EXTRA := 1.2
const MARGIN := 0.45            ## how far inside the floor edge he stays (Cage Rules REF_CAGE vs its fence)
const BODY_R := 0.32            ## his own footprint, kept clear of pits and solid props
const NEUTRAL_EVERY := 0.05     ## seconds between re-evaluations of the neutral spot (it is sticky anyway)
const NEAR_SIDE_COST := 1.5     ## neutral-spot score per metre on the camera's side of the action
const BUBBLE_HEIGHT := 0.62     ## above the head pivot (Cage Rules: head centre + 0.5)
const CREATURE_SHADER := "res://src/view/shaders/creature.gdshader"
const CLOTH_ROUGHNESS := 0.7    ## source roughness from which a surface counts as matte cloth

static var _shader_2s: Shader = null   ## the double-sided creature shader (plain resource cache)

var arena: ArenaDef = null
var rules := {}
var data := {}
var creature: CreatureDef = null
var view: CreatureView = null
var pose_model: RefereePose = null
var bubble: Label3D = null
var poses := {}                 ## name -> RefereePose.Pose

# tuning (Cage Rules render.js constants; tools/cage_rules/import.js exports them into the data)
var kd_hold := 1.5
var ref_speed := 1.3
var ref_room := 1.7
var lunge_v := 5.2
var lunge_t_max := 0.28
var lunge_cd_max := 0.9
var kd_stay := 4.0
var ceremony := {}
var intro_time := 2.2
var round_end_time := 3.0
var decision_time := 6.0

# director state (world metres)
var pos := Vector2(0, -1.5)
var vel := Vector2.ZERO
var yaw := 0.0
var goal := Vector2.ZERO
var has_goal := false
var lunge_t := 0.0
var lunge_cd := 0.0
var lunge_vel := Vector2.ZERO
var cam_side := Vector2(0, 1)   ## unit, from the action toward the camera (XZ)
var _time := 0.0
var _placed := false
var _phase := -1
var _round := -1
var _clock := 0.0               ## local phase clock (when phase_time is not supplied)
var _phase_t := 0.0             ## seconds into the phase this frame (supplied or local)
var _over_t := -1.0             ## seconds since the round ended (-1 while not over)
var _stop_loser := -1           ## latched for the round: stopped / KO'd fighter waved off
var _cer_side := 0              ## which side of the winner he announces from (+1/-1 along screen-sideways, 0 = unset)
var _kd := {}                   ## fighter index -> {phase, down_t, left, forced, arrive, counted}
var _models: Array = []         ## up to two active fighters: {index, team, pos: Vector2, state, name, extra}
var _all: Array = []            ## every fighter dict of the frame (normalized)
var _neutral_wait := 0.0
var _floor: Array = []          ## convex floor pieces: [{a: PackedVector2Array, n: PackedVector2Array (inward)}]
var _blockers: Array = []       ## pits and solid props: [{item, def}]
var _centre := Vector2.ZERO
var _say := ""
var _bubble_a := 0.0
var _target_pose: RefereePose.Pose = RefereePose.Pose.new()

# the frame's plan (Referee.update locals), kept for debug_state()
var _mode := "idle"
var _pose_name := "watch"
var _anim := ""
var _tgt := Vector2.ZERO
var _face := Vector2.ZERO
var _max_sp := 1.8
var _rep_r := 1.15
var _speed := 10.0
var _route := false


func setup(arena_: ArenaDef, rules_: Dictionary) -> void:
	arena = arena_
	rules = rules_
	name = "RefereeView"
	data = load_data()
	intro_time = float(rules.get("intro_time", MatchMode.INTRO_TIME))
	var consts: Dictionary = {}
	var mm: Script = load(MATCH_MODE_PATH)
	if mm:
		consts = mm.get_script_constant_map()
	round_end_time = float(consts.get("ROUND_END_TIME", 3.0))
	decision_time = float(consts.get("DECISION_TIME", 6.0))
	var tun: Dictionary = data.get("tuning", {})
	kd_hold = float(tun.get("KD_HOLD", kd_hold))
	ref_speed = float(tun.get("REF_SPEED", ref_speed))
	ref_room = float(tun.get("REF_ROOM", ref_room))
	lunge_v = float(tun.get("LUNGE_V", lunge_v))
	lunge_t_max = float(tun.get("LUNGE_T", lunge_t_max))
	lunge_cd_max = float(tun.get("LUNGE_CD", lunge_cd_max))
	kd_stay = float(tun.get("KD_STAY", kd_stay))
	ceremony = data.get("ceremony", {})
	var pd: Dictionary = data.get("poses", {})
	for k in pd:
		poses[str(k)] = RefereePose.Pose.from_dict(pd[k])
	for k in ["watch", "ready", "go", "stop", "kdWatch", "waveUp", "waveOff", "hold", "raiseL", "raiseR", "raiseBoth"]:
		if not poses.has(k):
			poses[k] = RefereePose.Pose.new()
	# a win: the winner's arm goes up from "ready" (Cage Rules raises it from "hold", a wrist in each
	# hand of the line-up; here the loser is not lined up beside him)
	for side in ["L", "R"]:
		var solo: RefereePose.Pose = (poses["ready"] as RefereePose.Pose).copy()
		var src: RefereePose.Pose = poses["raise" + side]
		if side == "L":
			solo.lh = src.lh
		else:
			solo.rh = src.rh
		solo.hp = src.hp
		poses["raise" + side + "_solo"] = solo
	_target_pose = (poses["watch"] as RefereePose.Pose).copy()
	pose_model = RefereePose.new()
	pose_model.setup(data.get("rig", {}), float(data.get("scale", 1.06)))
	pose_model.snap = true
	creature = make_creature(data)
	view = CreatureView.new()
	add_child(view)
	view.setup(creature)
	_style_model()
	_build_bubble()
	_build_floor()


## The creature shader's toon highlight band turns his near-black cloth into vinyl, so cloth
## (source roughness >= CLOTH_ROUGHNESS) is fully matte; surfaces Cage Rules draws double-sided (the
## slacks' open tubes, recorded by the importer) render both faces as in the original.
func _style_model() -> void:
	if view == null:
		return
	var ds: Array = data.get("double_sided", [])
	for node in view.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si)
			var sm := mi.get_surface_override_material(si) as ShaderMaterial
			if sm == null or not (src is BaseMaterial3D):
				continue
			var bm := src as BaseMaterial3D
			if bm.roughness >= CLOTH_ROUGHNESS:
				sm.set_shader_parameter("roughness_v", 1.0)
			if ds.has(bm.resource_name):
				sm.shader = _double_sided_shader()


## The creature shader with back faces drawn (built once from its source).
static func _double_sided_shader() -> Shader:
	if _shader_2s == null:
		var base: Shader = load(CREATURE_SHADER)
		_shader_2s = Shader.new()
		_shader_2s.code = base.code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode cull_disabled;")
	return _shader_2s


## The view data written by tools/cage_rules/import.js ({} when missing).
static func load_data() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("RefereeView: %s is missing" % DATA_PATH)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## A view-only creature (never registered with Content): the referee's body and model.
static func make_creature(d: Dictionary) -> CreatureDef:
	var c := CreatureDef.new()
	c.id = str(d.get("id", "cage_referee"))
	c.display_name = str(d.get("name", "Referee"))
	c.npc_only = true
	var bd: Dictionary = d.get("body", {})
	c.body = BodyDef.from_dict(bd, DATA_PATH)
	c.errors.append_array(c.body.errors)
	var art: Dictionary = (d.get("art", {}) as Dictionary).duplicate()
	art["model"] = str(d.get("model", ""))
	c.art = art
	return c


## Plain referee state from a MatchSim (local play) or a NetHudMirror's sim (replicated = true: its
## mode does not tick, so phase_time is left to the view).
static func state_from_sim(sim: MatchSim, replicated := false) -> Dictionary:
	var st := {"phase": MatchMode.Phase.INTRO, "phase_time": -1.0, "round": 0, "winner": -2, "fighters": [], "ref": {}}
	if sim == null:
		return st
	var m: MatchMode = sim.mode
	if m != null:
		st["phase"] = int(m.phase)
		st["phase_time"] = -1.0 if replicated else m.phase_time
		st["round"] = m.round_index
		st["winner"] = m.winner_team
		var vs: Dictionary = m.view_state()
		var r = vs.get("referee", {})
		st["ref"] = r if typeof(r) == TYPE_DICTIONARY else {}
	var fl: Array = []
	for f: Fighter in sim.fighters:
		if f.despawned:
			continue
		fl.append({"index": f.index, "team": f.team, "pos": f.pos(), "state": int(f.state), "name": f.display_name,
			"radius": body_radius(f.creature.body) if f.creature != null and f.creature.body != null else BASE_RADIUS})
	st["fighters"] = fl
	return st


## Horizontal radius of a body in its rest pose (furthest shape extent from the vertical axis).
static func body_radius(b: BodyDef) -> float:
	var r := 0.0
	for s: BodyDef.Seg in b.segments:
		for sh: BodyDef.Shape in s.shapes:
			var ext := sh.radius
			if sh.type == BodyDef.SHAPE_BOX:
				ext = Vector2(sh.size.x, sh.size.z).length() * 0.5
			for c in [s.pivot + sh.a, s.pivot + sh.b]:
				var cv: Vector3 = c
				r = maxf(r, Vector2(cv.x, cv.z).length() + ext)
	return r


func debug_state() -> Dictionary:
	return {"mode": _mode, "pose": _pose_name, "pos": Vector3(pos.x, 0.0, pos.y), "target": Vector3(_tgt.x, 0.0, _tgt.y),
		"face": Vector3(_face.x, 0.0, _face.y), "say": _say, "yaw": yaw, "cam_side": Vector3(cam_side.x, 0.0, cam_side.y)}


# =====================================================================================
# Frame
# =====================================================================================

func update_view(state: Dictionary, cam_pos: Vector3, dt: float) -> void:
	if pose_model == null:
		return
	dt = clampf(dt, 0.0, 0.1)
	_time += dt
	_read_state(state, dt)
	_update_cam_side(cam_pos, dt)
	_plan(state, dt)
	if not _placed:
		pos = _clamp_floor(_tgt)
		pos = _push_out(pos)
		_placed = true
		pose_model.snap = true
	_move(dt)
	_target_pose.set_from(poses.get(_pose_name, poses["watch"]))
	_animate_hands(_target_pose)
	pose_model.update(pos.x, pos.y, yaw, _target_pose, vel.length() > 0.3, _speed if lunge_t <= 0.0 else maxf(_speed, 22.0), dt, _time)
	if view:
		view.snap_transforms(pose_model.transforms_for(creature.body))
		view.render(1.0)
	_update_bubble(dt)


func _read_state(state: Dictionary, dt: float) -> void:
	var ph := int(state.get("phase", MatchMode.Phase.FIGHT))
	var rd := int(state.get("round", 0))
	if ph != _phase or rd != _round:
		if ph == MatchMode.Phase.INTRO or rd != _round:
			_stop_loser = -1
			_cer_side = 0
			_kd.clear()
		_clock = 0.0
		_phase = ph
		_round = rd
	else:
		_clock += dt
	var supplied := float(state.get("phase_time", -1.0))
	_phase_t = supplied if supplied >= 0.0 else _clock
	# the time since the round ended runs on through MATCH_END (the bout-end ceremony)
	if ph == MatchMode.Phase.ROUND_END and supplied >= 0.0:
		_over_t = supplied
	elif ph == MatchMode.Phase.ROUND_END or ph == MatchMode.Phase.MATCH_END:
		_over_t = 0.0 if _over_t < 0.0 else _over_t + dt
	else:
		_over_t = -1.0
	_all.clear()
	_models.clear()
	for fd in state.get("fighters", []):
		if typeof(fd) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = fd
		var p3 := Vector3.ZERO
		var pv = d.get("pos", Vector3.ZERO)
		if typeof(pv) == TYPE_VECTOR3:
			p3 = pv
		var e := {"index": int(d.get("index", _all.size())), "team": int(d.get("team", 0)), "pos": Vector2(p3.x, p3.z),
			"y": p3.y, "state": int(d.get("state", 0)), "name": str(d.get("name", "")),
			"extra": clampf(float(d.get("radius", BASE_RADIUS)) - BASE_RADIUS, 0.0, MAX_EXTRA)}
		_all.append(e)
		if int(e["state"]) != Fighter.State.INACTIVE and p3.y > -3.0 and _models.size() < 2:
			_models.append(e)
	# knockdown bookkeeping (Referee.update): did he get up on his own, or did the count run out?
	var ref: Dictionary = state.get("ref", {}) if typeof(state.get("ref", {})) == TYPE_DICTIONARY else {}
	var cnt: Dictionary = ref.get("count", {}) if typeof(ref.get("count", {})) == TYPE_DICTIONARY else {}
	var cnt_f := int(cnt.get("fighter", -1)) if not cnt.is_empty() else -1
	for e2 in _all:
		var i := int(e2["index"])
		if not _kd.has(i):
			_kd[i] = {"phase": "", "down_t": 0.0, "left": -1.0, "forced": false, "arrive": -1.0, "counted": false}
		var k: Dictionary = _kd[i]
		var st := int(e2["state"])
		var kph := ""
		if st == Fighter.State.KNOCKDOWN:
			kph = "fall"
		elif st == Fighter.State.DOWN:
			kph = "down"
		elif st == Fighter.State.GETUP:
			kph = "rise"
		if kph == "":
			k["counted"] = false
			k["down_t"] = 0.0
			k["left"] = -1.0
			k["arrive"] = -1.0
		else:
			if str(k["phase"]) == "":
				k["arrive"] = -1.0
				k["down_t"] = 0.0
				k["left"] = -1.0
			if kph == "down":
				k["down_t"] = float(k["down_t"]) + dt
			if cnt_f == i:
				k["counted"] = true
				k["left"] = float(cnt.get("left", -1.0))
			if kph == "rise" and str(k["phase"]) != "rise":
				var left := float(k["left"])
				k["forced"] = (left >= 0.0 and left <= 0.25) or (left < 0.0 and float(k["down_t"]) >= kd_stay - 0.15)
		k["phase"] = kph
	# a stoppage (TKO) or, with HP scoring, a KO is waved off: latched for the round
	var stop := int(ref.get("stop", -1))
	if stop >= 0:
		_stop_loser = stop
	elif bool(ref.get("wave_off", false)) and _stop_loser < 0:
		var winner := int(state.get("winner", -2))
		for e3 in _all:
			if int(e3["state"]) == Fighter.State.KO:
				_stop_loser = int(e3["index"])
				break
		if _stop_loser < 0 and winner >= 0:
			for e4 in _all:
				if int(e4["team"]) != winner:
					_stop_loser = int(e4["index"])
					break


func _update_cam_side(cam_pos: Vector3, dt: float) -> void:
	var mid := _mid()
	var want := Vector2(cam_pos.x, cam_pos.z) - mid
	if want.length() < 0.05:
		return
	want = want.normalized()
	var c := cam_side + (want - cam_side) * RefereePose.expo(dt, 6.0)
	cam_side = c.normalized() if c.length() > 0.001 else want


func _mid() -> Vector2:
	if _models.is_empty():
		return _centre
	if _models.size() == 1:
		return _models[0]["pos"]
	return ((_models[0]["pos"] as Vector2) + (_models[1]["pos"] as Vector2)) * 0.5


func _m(i: int) -> Vector2:
	if _models.is_empty():
		return _centre
	return _models[mini(i, _models.size() - 1)]["pos"]


func _extra_max() -> float:
	var e := 0.0
	for m in _models:
		e = maxf(e, float(m["extra"]))
	return e


func _model_of(index: int) -> Dictionary:
	for m in _models:
		if int(m["index"]) == index:
			return m
	for a in _all:
		if int(a["index"]) == index:
			return a
	return {}


# =====================================================================================
# Director (render.js Referee.update)
# =====================================================================================

func _plan(state: Dictionary, dt: float) -> void:
	var ph := int(state.get("phase", MatchMode.Phase.FIGHT))
	var phase_t := _phase_t
	var winner := int(state.get("winner", -2))
	var mid := _mid()
	_tgt = pos
	_face = mid
	_max_sp = 1.8
	_rep_r = 1.15
	_speed = 10.0
	_route = false
	_say = ""
	_anim = ""
	_pose_name = "watch"
	if ph != MatchMode.Phase.FIGHT:
		has_goal = false
	var kd_i := -1
	if ph == MatchMode.Phase.FIGHT:
		for m in _models:
			var k: Dictionary = _kd.get(int(m["index"]), {})
			if not k.is_empty() and str(k["phase"]) != "" and bool(k["counted"]):
				kd_i = int(m["index"])
				break
	if _over_t >= 0.0:
		_plan_over(winner, mid, dt)
	elif kd_i >= 0:
		_plan_knockdown(kd_i)
	elif ph == MatchMode.Phase.INTRO:
		# between them for the instructions, then "fight!"
		_mode = "intro"
		_tgt = mid - cam_side * (0.8 + _extra_max() * 0.5)
		_pose_name = "go" if phase_t > intro_time - 0.6 else "ready"
	else:
		_mode = "fight"
		var d := _m(0).distance_to(_m(1))
		_tgt = _neutral(mid, clampf(2.5 + d * 0.4, 2.7, 3.3) + _extra_max(), dt)
		_max_sp = 2.2
		_route = true
		_pose_name = "watch"


## Round over: wave off a stoppage, then (bout over) walk to the winner and raise his arm, or (more
## rounds to come) the break in the centre. Cage Rules' timeline is scaled to this ROUND_END.
func _plan_over(winner: int, mid: Vector2, dt: float) -> void:
	var t := _over_t
	var decided := winner != -2
	var stop_c: Dictionary = ceremony.get("stoppage", {})
	var dec_c: Dictionary = ceremony.get("decision", {})
	var stoppage := _stop_loser >= 0 and not _model_of(_stop_loser).is_empty()
	var length := decision_time if decided else round_end_time
	var src: Dictionary = stop_c if stoppage else dec_c
	var k := length / maxf(0.1, float(src.get("end", 6.0)))
	var wave_until := float(src.get("cut", 3.45 if stoppage else 1.65)) * k
	var raise_at := float(src.get("raise", 4.9 if stoppage else 3.1)) * k
	if stoppage and t < wave_until:
		# jump in between them and wave it off
		_mode = "wave_off"
		var lm := _model_of(_stop_loser)
		var lp: Vector2 = lm["pos"]
		var wp := _other_than(_stop_loser, lp - cam_side)
		var u := wp - lp
		var l := u.length()
		u = u / l if l > 0.001 else -cam_side
		_tgt = lp + u * (0.85 + float(lm["extra"]))
		_face = lp
		_max_sp = 4.5
		_rep_r = 0.55
		_speed = 24.0
		_pose_name = "waveOff"
		_anim = "waveOff"
		return
	if not decided:
		# the break: centre of the arena, facing the camera (off to the far side if a fighter is there);
		# straight there like Cage Rules (the round is over), repulsion still keeps him off them
		_mode = "break"
		_tgt = _centre
		for m in _models:
			if (m["pos"] as Vector2).distance_to(_centre) < 1.0 + float(m["extra"]):
				_tgt = _centre - cam_side * (1.1 + float(m["extra"]))
				break
		_face = _tgt + cam_side * 5.0
		_pose_name = "ready"
		return
	if not stoppage and t < wave_until:
		# the cards are read: a neutral spot close to the action
		_mode = "decision"
		_tgt = _neutral(mid, 1.5 + _extra_max(), dt)
		_route = true
		_pose_name = "ready"
		return
	# the announcement: beside the winner, facing the camera
	_mode = "ceremony"
	_face = pos + cam_side * 5.0
	_rep_r = 0.4
	_max_sp = 2.4
	_speed = 9.0
	var draw := winner < 0
	var wm := {}
	if not draw:
		for m in _all:
			if int(m["team"]) == winner:
				wm = m
				break
	if wm.is_empty() and not draw:
		draw = true
	var lr := cam_side.orthogonal()     ## screen-sideways on the floor
	var arrived := false
	if draw:
		_tgt = mid - cam_side * 0.15
		if _models.size() >= 2 and _m(0).distance_to(_m(1)) < 1.4:
			_tgt = mid - cam_side * 0.9
		arrived = pos.distance_to(_tgt) < 0.4
		if pos.distance_to(_tgt) > 0.6:
			_face = _tgt
		var up := t >= raise_at and (arrived or t >= raise_at + 0.8)
		_pose_name = "raiseBoth" if up else "hold"
		if up:
			_say = "It's a draw!"
		_mode = "raise" if up else "ceremony"
		return
	var wpos: Vector2 = wm["pos"]
	var gap := 0.6 + float(wm["extra"])
	var lose := _other_than(int(wm["index"]), wpos + lr)
	# between the winner and the loser like the Cage Rules line-up, unless the loser is in the way;
	# the side sticks once chosen while it stays usable
	var room := 0.6 + _extra_of_other(int(wm["index"]))
	if _cer_side == 0:
		var a := wpos + lr * gap
		var b := wpos - lr * gap
		_cer_side = 1 if a.distance_to(lose) < b.distance_to(lose) else -1
	var spot := wpos + lr * gap * _cer_side - cam_side * 0.15
	if _blocked_spot(spot) or spot.distance_to(lose) < room:
		var other := wpos - lr * gap * _cer_side - cam_side * 0.15
		if not _blocked_spot(other) and other.distance_to(lose) >= room:
			_cer_side = -_cer_side
			spot = other
	_tgt = _clamp_floor(spot)
	arrived = pos.distance_to(_tgt) < 0.4
	if pos.distance_to(_tgt) > 0.6:
		_face = _tgt     # walk over facing where he goes; he turns to the camera once there
	var raised := t >= raise_at and (arrived or t >= raise_at + 0.8)
	# the winner's side as he faces the camera: his left is +X of his own frame
	var face_dir := cam_side
	var left_dir := Vector2(face_dir.y, -face_dir.x)
	var on_left := (wpos - pos).dot(left_dir) > 0.0
	if raised:
		_pose_name = "raiseL_solo" if on_left else "raiseR_solo"
		var nm := str(wm["name"])
		_say = "%s wins!" % (nm if nm != "" else "Fighter %d" % (int(wm["index"]) + 1))
		_mode = "raise"
	else:
		_pose_name = "ready"


## Knockdown: rush in between them and hold the attacker off with an outstretched arm, then bend over
## the downed fighter; near the end of the count wave him up, and keep waving while he rises.
func _plan_knockdown(kd_i: int) -> void:
	var k: Dictionary = _kd[kd_i]
	var dmod := _model_of(kd_i)
	var dm: Vector2 = dmod["pos"]
	var ex_d := float(dmod["extra"])
	var am := _other_than(kd_i, dm - cam_side * 1.5)
	var u := am - dm
	var l := u.length()
	if l < 0.001:
		u = -cam_side
		l = 1.0
	else:
		u /= l
	# a little to the side of the line, on the far side from the camera, so he does not hide the downed man
	var p := Vector2(-u.y, u.x)
	if p.dot(cam_side) > 0.0:
		p = -p
	_max_sp = 4.6
	_rep_r = 0.55
	var kph := str(k["phase"])
	var left := float(k["left"])
	var wave := (kph == "down" and ((left >= 0.0 and left < 1.0) or (left < 0.0 and float(k["down_t"]) > kd_stay - 1.0))) \
		or (kph == "rise" and bool(k["forced"]))
	var arrive := float(k["arrive"])
	var holding := not wave and kph != "rise" and (arrive < 0.0 or _time - arrive < kd_hold)
	if holding:
		_mode = "kd_hold"
		var along := minf(1.1 + ex_d, l * 0.55)
		_tgt = dm + u * along + p * 0.3
		if arrive < 0.0 and _tgt.distance_to(pos) < 0.5:
			k["arrive"] = _time
		_face = am
		_pose_name = "stop"
		_speed = 20.0
		_say = "Back up!"
	else:
		_tgt = dm + u * (0.8 + ex_d) + p * (0.5 + ex_d * 0.5)
		_max_sp = 2.5
		_face = dm
		if wave:
			_mode = "wave_up"
			_speed = 22.0
			_pose_name = "waveUp"
			_anim = "waveUp"
		else:
			_mode = "kd_watch"
			_pose_name = "watch" if kph == "rise" else "kdWatch"


func _other_than(index: int, fallback: Vector2) -> Vector2:
	for m in _models:
		if int(m["index"]) != index:
			return m["pos"]
	for a in _all:
		if int(a["index"]) != index:
			return a["pos"]
	return fallback


func _extra_of_other(index: int) -> float:
	for m in _models:
		if int(m["index"]) != index:
			return float(m["extra"])
	return 0.0


## The "T": about D out from the middle of the action, square to the line between the fighters, on
## the far side from the camera; angled off or closer rather than drifting onto their line when the
## edge is in the way; sticks with the current spot until it has gone bad.
func _neutral(mid: Vector2, d_want: float, dt: float) -> Vector2:
	_neutral_wait -= dt
	if has_goal and _neutral_wait > 0.0:
		return goal
	_neutral_wait = NEUTRAL_EVERY
	var m0 := _m(0)
	var m1 := _m(1)
	var u := m1 - m0
	var gap := u.length()
	var n := -cam_side
	if gap > 0.3:
		n = Vector2(-u.y, u.x) / gap
		if n.dot(cam_side) > 0.0:
			n = -n
	var ra := atan2(pos.y - mid.y, pos.x - mid.x)
	var best := goal
	var best_s := -1e9
	for side in [1.0, -1.0]:
		for ang in [0.0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9]:
			for dd in [d_want, d_want * 0.8, maxf(1.4, d_want * 0.6)]:
				var sgn: float = side
				var an: float = ang
				var dist: float = dd
				var c := cos(an)
				var s := sin(an)
				var p := mid + Vector2(n.x * c - n.y * s, n.x * s + n.y * c) * sgn * dist
				var over := _over(p)
				var score := -absf(an) * 1.2 - (1.0 - dist / d_want) * 2.5 - (3.5 if sgn < 0.0 else 0.0) - over * 6.0
				if over > 0.0:
					p = _clamp_floor(p)
				# Critterweight: also weigh how far a spot is on the camera's side of the action (the camera
				# may stay put while the fighters' line turns; Cage Rules' camera always squares up to it)
				score -= maxf(0.0, (p - mid).dot(cam_side)) * NEAR_SIDE_COST
				for m in _models:
					var room := ref_room + float(m["extra"])
					var md := p.distance_to(m["pos"])
					if md < room:
						score -= (room - md) * 6.0
				score -= maxf(0.0, BODY_R - _blocked_distance(p)) * 6.0
				var da := wrapf(atan2(p.y - mid.y, p.x - mid.x) - ra, -PI, PI)
				score -= absf(da) * 0.5
				if has_goal:
					score -= p.distance_to(goal) * 0.6
				if score > best_s:
					best_s = score
					best = p
	if not has_goal or best.distance_to(goal) > 0.4:
		goal = best
		has_goal = true
	return goal


## He walks round the fighters, never through them: when the straight line passes close to either
## of them or the gap between them, he heads for a point further round an arc about the action.
func _route_to(t: Vector2, mid: Vector2) -> Vector2:
	var m0 := _m(0)
	var m1 := _m(1)
	var half := m0.distance_to(m1) * 0.5
	var ex := _extra_max()
	var near := 1e9
	for i in 9:
		var q := pos + (t - pos) * (i / 8.0)
		near = minf(near, seg_dist(q, m0, m1))
	if near > 1.0 + ex:
		return t
	var ra := atan2(pos.y - mid.y, pos.x - mid.x)
	var da := wrapf(atan2(t.y - mid.y, t.x - mid.x) - ra, -PI, PI)
	var r := maxf(maxf(pos.distance_to(mid), half + 1.2 + ex), 1.6 + ex)
	var step := minf(absf(da) + 0.15, 0.7)
	var dir := 1.0 if da >= 0.0 else -1.0
	var w := mid + Vector2(cos(ra + dir * step), sin(ra + dir * step)) * r
	var w2 := mid + Vector2(cos(ra - dir * step), sin(ra - dir * step)) * r
	if _over(w) > _over(w2) + 0.3:
		w = w2
	return _clamp_floor(w)


## Backed up near the edge with a fighter close: slide round the inside of the arena, whichever
## way takes him further from the fighters (and, all else equal, toward where he wanted to go).
func _escape_arc(t: Vector2) -> Vector2:
	var m0 := _m(0)
	var m1 := _m(1)
	var rel := pos - _centre
	var r := maxf(rel.length(), 0.5)
	var ra := atan2(rel.y, rel.x)
	var best := pos
	var best_s := -1e9
	for dir in [1.0, -1.0]:
		var a: float = ra + float(dir) * 0.75
		var q := _clamp_floor(_centre + Vector2(cos(a), sin(a)) * r, MARGIN + 0.25)
		var s := seg_dist(q, m0, m1) * 2.0 - t.distance_to(q) * 0.3
		for m in _models:
			s += minf(2.5, q.distance_to(m["pos"]))
		if s > best_s:
			best_s = s
			best = q
	return best


## The hop out of the way: whichever of 16 directions gets him clear of both fighters without
## cutting between them or running off the floor.
func _lunge_dir() -> Vector2:
	var m0 := _m(0)
	var m1 := _m(1)
	var reach := lunge_v * lunge_t_max
	var best := Vector2(1, 0)
	var best_s := -1e9
	for i in 16:
		var a := i / 16.0 * TAU
		var u := Vector2(cos(a), sin(a))
		var e := pos + u * reach
		var s := 0.0
		var over := _over(e)
		if over > 0.0:
			s -= over * 8.0
			e = _clamp_floor(e)
		s -= maxf(0.0, BODY_R - _blocked_distance(e)) * 8.0
		var line := 1e9
		for kk in range(1, 5):
			line = minf(line, seg_dist(pos + (e - pos) * (kk / 4.0), m0, m1))
		s += minf(line, 1.5) * 3.0
		for m in _models:
			s += minf(2.0, e.distance_to(m["pos"])) * 2.0
		if s > best_s:
			best_s = s
			best = u
	return best


func _move(dt: float) -> void:
	var mid := _mid()
	var near_fence := _edge_distance(pos) < MARGIN + 0.6
	var near := 1e9
	for m in _models:
		near = minf(near, pos.distance_to(m["pos"]) - float(m["extra"]))
	var t := _tgt
	if _route and not _models.is_empty():
		if near_fence and near < 1.8:
			t = _escape_arc(t)
			_max_sp = maxf(_max_sp, 2.6)
		else:
			t = _route_to(t, mid)
	# walk there: eased speed, a dead zone so he is not forever shuffling, and he steps away from
	# anyone too close (a push into the edge becomes a slide along it)
	var want := Vector2.ZERO
	var d := t - pos
	var dl := d.length()
	if dl > (0.06 if vel.length() > 0.2 else 0.3):
		var sp := minf(_max_sp, dl * 2.6) * ref_speed
		want = d / dl * sp
	# (Cage Rules switches this off for its centre line-up; here the fighters are never lined up)
	var out := _out_normal(pos) if near_fence else Vector2.ZERO
	for m in _models:
		var rel := pos - (m["pos"] as Vector2)
		var rd := maxf(rel.length(), 0.001)
		var rep := _rep_r + float(m["extra"])
		if rd < rep:
			var push := (rep - rd) * 5.0 * ref_speed
			var u := rel / rd
			if near_fence and out != Vector2.ZERO:
				var o := u.dot(out)
				if o > 0.0:
					u -= out * o
					var ul := u.length()
					u = u / ul if ul > 0.05 else Vector2(-out.y, out.x)
			want += u * push
	lunge_cd = maxf(0.0, lunge_cd - dt)
	if _route and lunge_t <= 0.0 and lunge_cd <= 0.0 and not _models.is_empty() and (near < 0.75 or (near_fence and near < 1.15)):
		lunge_vel = _lunge_dir() * lunge_v
		lunge_t = lunge_t_max
		lunge_cd = lunge_cd_max
	if lunge_t > 0.0:
		lunge_t -= dt
		vel = lunge_vel
	else:
		vel += (want - vel) * RefereePose.expo(dt, 8.0)
	pos += vel * dt
	pos = _clamp_floor(pos)
	pos = _push_out(pos)
	var f := _face - pos
	if f.length() > 0.2:
		yaw = atan2(f.x, f.y)


## Per-frame hands of the animated poses (render.js: waveOff crosses at 9 rad/s, waveUp lifts at 8).
func _animate_hands(p: RefereePose.Pose) -> void:
	if _anim == "waveOff":
		set_hands(p, _anim, 0.5 + 0.5 * sin(_time * 9.0))
	elif _anim == "waveUp":
		set_hands(p, _anim, 0.5 + 0.5 * sin(_time * 8.0))


## The waveOff / waveUp hand targets at phase u (0..1), exactly as Referee.update animates them.
static func set_hands(p: RefereePose.Pose, kind: String, u: float) -> void:
	if kind == "waveOff":
		p.lh = Vector3(0.45 - 0.6 * u, 0.86, 0.32)
		p.rh = Vector3(-0.45 + 0.6 * u, 0.86, 0.24)
	elif kind == "waveUp":
		p.lh = Vector3(0.2, 0.05 + 0.6 * u, 0.46 - 0.1 * u)
		p.rh = Vector3(-0.2, 0.05 + 0.6 * u, 0.46 - 0.1 * u)


# =====================================================================================
# Speech bubble (HubNpcView style: billboard Label3D, no depth test)
# =====================================================================================

func _build_bubble() -> void:
	bubble = Label3D.new()
	bubble.name = "Bubble"
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if ResourceLoader.exists("res://assets/fonts/Barlow-600.woff2"):
		bubble.font = load("res://assets/fonts/Barlow-600.woff2")
	bubble.font_size = 40
	bubble.pixel_size = 0.0042
	bubble.outline_size = 12
	bubble.outline_modulate = Color(0.07, 0.07, 0.1, 0.95)
	bubble.modulate = Color(1, 1, 1, 0)
	bubble.visible = false
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 620
	bubble.no_depth_test = true
	bubble.render_priority = 2
	add_child(bubble)


func _update_bubble(dt: float) -> void:
	if bubble == null:
		return
	if _say != "":
		bubble.text = _say
		_bubble_a = minf(1.0, _bubble_a + dt * 8.0)
	else:
		_bubble_a = maxf(0.0, _bubble_a - dt * 4.0)
	var head := Vector3(pos.x, 1.6, pos.y)
	if view and creature.body.seg_index.has("head"):
		head = view.segment_world(int(creature.body.seg_index["head"])).origin
	bubble.position = head + Vector3(0, BUBBLE_HEIGHT, 0)
	bubble.modulate = Color(1, 1, 1, _bubble_a)
	bubble.outline_modulate = Color(0.07, 0.07, 0.1, 0.95 * _bubble_a)
	bubble.visible = _bubble_a > 0.0


func bubble_text() -> String:
	return bubble.text if bubble and bubble.visible else ""


# =====================================================================================
# Arena bounds (ArenaDef floor, pits and solid props)
# =====================================================================================

func _build_floor() -> void:
	_floor.clear()
	_blockers.clear()
	_centre = Vector2.ZERO
	if arena == null:
		return
	var ext := arena.extent()
	_centre = ext.get_center()
	for piece in arena.floor_pieces():
		var poly: PackedVector2Array = piece
		var area := 0.0
		for i in poly.size():
			area += poly[i].x * poly[(i + 1) % poly.size()].y - poly[(i + 1) % poly.size()].x * poly[i].y
		var sgn := 1.0 if area > 0.0 else -1.0
		var a := PackedVector2Array()
		var n := PackedVector2Array()
		for i in poly.size():
			var p0 := poly[i]
			var p1 := poly[(i + 1) % poly.size()]
			var t := (p1 - p0).normalized()
			a.append(p0)
			n.append(Vector2(-t.y, t.x) * sgn)
		_floor.append({"a": a, "n": n})
	for item in arena.all_props():
		var def := ArenaCatalog.prop(str(item.get("type", "")))
		if def.is_empty():
			continue
		if str(def.get("behaviour", "")) == "pit" or bool(def.get("solid", false)):
			_blockers.append({"item": item, "def": def})


## How far p lies outside the floor shrunk by `margin` (0 inside); half-plane violation per piece.
func _over(p: Vector2, margin := MARGIN) -> float:
	if _floor.is_empty():
		return maxf(0.0, p.length() - (3.9 if arena == null else arena.radius - margin))
	var best := INF
	for piece in _floor:
		var a: PackedVector2Array = piece["a"]
		var n: PackedVector2Array = piece["n"]
		var worst := 0.0
		for i in a.size():
			worst = maxf(worst, margin - (p - a[i]).dot(n[i]))
		best = minf(best, worst)
		if best <= 0.0:
			return 0.0
	return best


func _clamp_floor(p: Vector2, margin := MARGIN) -> Vector2:
	if arena == null:
		return p.limit_length(3.9)
	var q := arena.clamp_point(Vector3(p.x, 0.0, p.y), margin)
	return Vector2(q.x, q.z)


func _edge_distance(p: Vector2) -> float:
	if arena == null:
		return 3.9 + MARGIN - p.length()
	return arena.edge_distance(Vector3(p.x, 0.0, p.y))


## Outward unit normal of the nearest boundary edge (the "fence" a push slides along).
func _out_normal(p: Vector2) -> Vector2:
	if arena == null:
		return p.normalized()
	var best := INF
	var n := Vector2.ZERO
	for e in arena.boundary_edges():
		var dd := seg_dist(p, e["a"], e["b"])
		if dd < best:
			best = dd
			n = e["n"]
	return n


## Signed distance from p to the nearest pit / solid prop footprint (INF when there is none).
func _blocked_distance(p: Vector2) -> float:
	var best := INF
	for b in _blockers:
		best = minf(best, ArenaCatalog.footprint_distance(b["item"], b["def"], p))
	return best


func _blocked_spot(p: Vector2) -> bool:
	return _blocked_distance(p) < BODY_R or _over(p) > 0.05


## Pushes p out of pits and solid props (numerical gradient of the footprint distance).
func _push_out(p: Vector2) -> Vector2:
	if _blockers.is_empty():
		return p
	var q := p
	for _it in 3:
		var dd := _blocked_distance(q)
		if dd >= BODY_R:
			break
		var h := 0.02
		var g := Vector2(_blocked_distance(q + Vector2(h, 0)) - _blocked_distance(q - Vector2(h, 0)),
			_blocked_distance(q + Vector2(0, h)) - _blocked_distance(q - Vector2(0, h)))
		if g.length() < 1e-5:
			g = q - _centre
		q += g.normalized() * (BODY_R - dd + 0.01)
	return _clamp_floor(q)


## Distance on the floor from p to the segment a-b (render.js segDist).
static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var v := b - a
	var l2 := v.length_squared()
	var u := clampf((p - a).dot(v) / l2, 0.0, 1.0) if l2 > 1e-6 else 0.0
	return p.distance_to(a + v * u)
