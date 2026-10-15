class_name FighterMotor
extends RefCounted
## Converts "what the creature is trying to do" (base pose, move keyframe overlay, look target,
## locomotion) into desired global segment rotations on its Rig.
##
##  * limb2 chains (arms, legs, wings, claws) are solved with two-bone IK toward targets authored
##    in fighter rest space (moves animate effector paths, not joint angles);
##  * legs flagged `leg` are driven by a procedural gait (planted feet, alternating step groups);
##  * other segments track parent-relative local rotations from the pose (identity = rest), with
##    procedural tail / serpent body waves layered on top.

var def: BodyDef
var rig: Rig
var time := 0.0

## ---- inputs written by Fighter each tick ----
var base_pose: BodyDef.Pose
var guard_pose: BodyDef.Pose
var guard_blend := 0.0                 ## 0..1 blend from base_pose toward guard_pose
var overlay_chains := {}               ## chain name -> Vector3 (fighter rest space)
var overlay_poles := {}                ## chain name -> Vector3
var overlay_joints := {}               ## seg index -> Quaternion (local)
var overlay_lean := Vector3.ZERO
var overlay_height := 0.0
var look_target := Vector3.ZERO
var has_look := false
var locomotion_vel := Vector3.ZERO     ## world horizontal velocity used by the gait
var gait_enabled := true
var tuck := false                      ## airborne / falling: legs pull in instead of stepping

## ---- internal ----
var _rest := {}                        ## chain name -> [Basis B1^T, Basis B2^T]
var _feet: Array = []                  ## Array[Dictionary]
var _wave_phase := 0.0
var _hop_phase := 0.0
var _root_rest := Vector3.ZERO


func _init(body_def: BodyDef, r: Rig) -> void:
	def = body_def
	rig = r
	_root_rest = def.segments[0].pivot
	base_pose = def.poses.get("stance")
	guard_pose = def.poses.get("guard", base_pose)
	for cname in def.chains:
		var c: BodyDef.Chain = def.chains[cname]
		if c.kind != "limb2":
			continue
		var s0: BodyDef.Seg = def.segments[c.segs[0]]
		var s1: BodyDef.Seg = def.segments[c.segs[1]]
		var bone1 := (s1.pivot - s0.pivot).normalized()
		var bone2 := (c.effector_rest - s1.pivot).normalized()
		var u := (c.effector_rest - s0.pivot).normalized()
		var pole_perp := (c.pole - u * c.pole.dot(u))
		if pole_perp.length_squared() < 1e-8:
			pole_perp = Vector3.FORWARD
		var n := u.cross(pole_perp.normalized()).normalized()
		_rest[cname] = [MathX.frame_from(bone1, n).transposed(), MathX.frame_from(bone2, n).transposed()]
	for c: BodyDef.Chain in def.leg_chains:
		_feet.append({"chain": c, "planted": Vector3.ZERO, "stepping": false, "from": Vector3.ZERO,
			"to": Vector3.ZERO, "t": 0.0, "dur": def.step_time, "group": c.gait_group, "idle": 0.0})


## Re-plants feet under the current root (after spawn / getting up).
func reset_feet() -> void:
	var y := MathX.yaw_basis(rig.actual_yaw())
	var rp := rig.root_pos()
	for f in _feet:
		var c: BodyDef.Chain = f["chain"]
		var home := c.foot_home - Vector3(_root_rest.x, 0.0, _root_rest.z)
		f["planted"] = Vector3(rp.x, rig.ground_y, rp.z) + y * Vector3(home.x, 0.0, home.z) + Vector3(0, c.foot_home.y, 0)
		f["stepping"] = false


func feet_planted_ratio() -> float:
	if _feet.is_empty():
		return 1.0
	var n := 0
	for f in _feet:
		if not f["stepping"]:
			n += 1
	return float(n) / _feet.size()


## Computes rig.target_rot for every segment. dt = physics step.
func update(dt: float) -> void:
	time += dt
	var yaw := rig.actual_yaw()
	var yb := MathX.yaw_basis(yaw)
	var rp := rig.root_pos()
	# Rest-space points map to world rigidly with the root's position and yaw, so authored
	# heights stay consistent when the creature crouches or bobs.
	var gb := guard_blend
	# ---- root height / lean ----
	var h := base_pose.height if base_pose else 0.0
	var lean := base_pose.lean if base_pose else Vector3.ZERO
	if guard_pose and gb > 0.0:
		h = lerpf(h, guard_pose.height, gb)
		lean = lean.lerp(guard_pose.lean, gb)
	rig.hover_height = def.hover_height + h + overlay_height
	rig.lean = lean + overlay_lean
	# ---- hopper bounce ----
	if def.gait == "hopper" and gait_enabled and not tuck:
		var spd := Vector2(locomotion_vel.x, locomotion_vel.z).length()
		if spd > 0.3:
			_hop_phase += dt * (2.6 + spd * 0.6)
		else:
			_hop_phase = lerpf(_hop_phase, roundf(_hop_phase), MathX.damp_factor(0.1, dt))
		rig.hover_height += absf(sin(_hop_phase * PI)) * def.step_height * minf(1.0, spd)
	# ---- limb chains ----
	for cname in def.chains:
		var c: BodyDef.Chain = def.chains[cname]
		if c.kind != "limb2":
			continue
		if c.is_leg and not overlay_chains.has(cname):
			continue
		var target := _chain_target(cname, c, gb)
		var pole := c.pole
		if overlay_poles.has(cname):
			pole = overlay_poles[cname]
		else:
			var bp = _pose_pole(cname, gb)
			if bp != null:
				pole = bp
		_solve_limb(cname, c, to_world(rp, yb, target), yb * pole)
	# ---- legs: gait ----
	_update_gait(dt, yb, rp)
	# ---- parent-relative segments (spine, head, tail, body) ----
	var spd2 := Vector2(locomotion_vel.x, locomotion_vel.z).length()
	_wave_phase += dt * (3.0 + spd2 * 2.5)
	for s: BodyDef.Seg in def.segments:
		if s.parent < 0 or _in_limb(s.index):
			continue
		var local := _joint_local(s.index, gb)
		var keyed := overlay_joints.has(s.index)   # a move that keys a joint owns it: no gait wave
		if s.part == "tail" and not keyed:
			var amp := 0.18 + spd2 * 0.05
			local = Quaternion(Vector3.UP, sin(_wave_phase - s.index * 0.7) * amp) * local
		elif def.gait == "serpent" and s.part == "core" and not keyed:
			var amp2 := minf(0.45, 0.1 + spd2 * 0.12)
			local = Quaternion(Vector3.UP, sin(_wave_phase * 1.4 - s.index * 1.1) * amp2) * local
		var parent_q := rig.bodies[s.parent].global_basis.get_rotation_quaternion()
		var q_t := parent_q * local
		if s.part == "head" and has_look:
			q_t = _apply_look(s, q_t)
		rig.target_rot[s.index] = q_t


## Fighter-rest-space point -> world, rotating about the vertical axis through the root pivot.
func to_world(rp: Vector3, yb: Basis, p: Vector3) -> Vector3:
	return rp + yb * (p - _root_rest)


func _in_limb(idx: int) -> bool:
	for cname in def.chains:
		var c: BodyDef.Chain = def.chains[cname]
		if c.kind == "limb2" and c.segs.has(idx):
			return true
	return false


func _chain_target(cname: String, c: BodyDef.Chain, gb: float) -> Vector3:
	if overlay_chains.has(cname):
		return overlay_chains[cname]
	return base_chain_target(cname, c)


## Base/guard pose target for a chain (no move overlay), fighter rest space.
func base_chain_target(cname: String, c: BodyDef.Chain) -> Vector3:
	var t := c.effector_rest
	if base_pose and base_pose.chains.has(cname):
		t = base_pose.chains[cname]["target"]
	if guard_pose and guard_blend > 0.0 and guard_pose.chains.has(cname):
		t = t.lerp(guard_pose.chains[cname]["target"], guard_blend)
	return t


func _pose_pole(cname: String, gb: float):
	var p = null
	if base_pose and base_pose.chains.has(cname):
		p = base_pose.chains[cname]["pole"]
	if gb > 0.5 and guard_pose and guard_pose.chains.has(cname) and guard_pose.chains[cname]["pole"] != null:
		p = guard_pose.chains[cname]["pole"]
	return p


func _joint_local(idx: int, gb: float) -> Quaternion:
	if overlay_joints.has(idx):
		return overlay_joints[idx]
	return base_joint_local(idx)


## Base/guard pose local rotation for a segment (no move overlay).
func base_joint_local(idx: int) -> Quaternion:
	var q := Quaternion.IDENTITY
	if base_pose and base_pose.joints.has(idx):
		q = base_pose.joints[idx]
	if guard_pose and guard_blend > 0.0 and guard_pose.joints.has(idx):
		q = q.slerp(guard_pose.joints[idx], guard_blend)
	return q


## Two-bone IK: target and pole in world space. Writes target rotations for both segments.
func _solve_limb(cname: String, c: BodyDef.Chain, target: Vector3, pole: Vector3) -> void:
	var s0 := c.segs[0]
	var s1 := c.segs[1]
	var shoulder := rig.bodies[s0].global_position
	var to_t := target - shoulder
	var dist := to_t.length()
	if dist < 1e-4:
		return
	var u := to_t / dist
	var l1 := c.len1
	var l2 := c.len2
	var d := clampf(dist, absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var pole_perp := pole - u * pole.dot(u)
	if pole_perp.length_squared() < 1e-8:
		pole_perp = (rig.bodies[0].global_basis.z - u * rig.bodies[0].global_basis.z.dot(u))
	pole_perp = pole_perp.normalized()
	var elbow := shoulder + u * (l1 * cos_a) + pole_perp * (l1 * sin_a)
	var end := shoulder + u * d
	var d1 := (elbow - shoulder).normalized()
	var d2 := (end - elbow).normalized()
	var n := u.cross(pole_perp).normalized()
	var rest: Array = _rest[cname]
	var b1: Basis = MathX.frame_from(d1, n) * rest[0]
	var b2: Basis = MathX.frame_from(d2, n) * rest[1]
	rig.target_rot[s0] = b1.get_rotation_quaternion()
	rig.target_rot[s1] = b2.get_rotation_quaternion()


func _apply_look(s: BodyDef.Seg, q_t: Quaternion) -> Quaternion:
	var head := rig.bodies[s.index].global_position
	var want := look_target - head
	if want.length_squared() < 0.01:
		return q_t
	var fwd := q_t * Vector3.BACK   # the head faces +Z in fighter space
	var rot := MathX.rotation_between(fwd, want.normalized())
	var ang := rot.get_angle()
	var lim := deg_to_rad(50.0)
	if ang > lim:
		rot = Quaternion.IDENTITY.slerp(rot, lim / ang)
	return rot * q_t


func _update_gait(dt: float, yb: Basis, rp: Vector3) -> void:
	if _feet.is_empty():
		return
	var vel := Vector3(locomotion_vel.x, 0.0, locomotion_vel.z)
	var speed := vel.length()
	var gy := rig.ground_y
	var any_stepping := {}
	for f in _feet:
		if f["stepping"]:
			any_stepping[f["group"]] = true
	for f in _feet:
		var c: BodyDef.Chain = f["chain"]
		if overlay_chains.has(c.name):
			continue
		var home_off := c.foot_home - Vector3(_root_rest.x, 0.0, _root_rest.z)
		var home := Vector3(rp.x, gy + c.foot_home.y, rp.z) + yb * Vector3(home_off.x, 0.0, home_off.z)
		var foot_pos: Vector3
		if tuck or not gait_enabled:
			# legs pulled up under the body while airborne / limp-ish
			foot_pos = to_world(rp, yb, c.foot_home + Vector3(0.0, 0.25 * def.scale, 0.1 * def.scale))
			f["planted"] = Vector3(foot_pos.x, gy + c.foot_home.y, foot_pos.z)
			f["stepping"] = false
		else:
			var desired := home + vel * 0.12
			if f["stepping"]:
				f["t"] = float(f["t"]) + dt / float(f["dur"])
				# retarget the landing point while swinging so fast turns stay planted
				f["to"] = Vector3(f["to"]).lerp(desired + vel * float(f["dur"]) * 0.35, MathX.damp_factor(0.05, dt))
				if f["t"] >= 1.0:
					f["stepping"] = false
					f["planted"] = f["to"]
					foot_pos = f["planted"]
				else:
					var t := MathX.smooth01(f["t"])
					foot_pos = Vector3(f["from"]).lerp(f["to"], t) + Vector3.UP * def.step_height * sin(PI * float(f["t"])) * clampf(0.5 + speed * 0.25, 0.5, 1.4)
			else:
				foot_pos = f["planted"]
				foot_pos.y = gy + c.foot_home.y
				f["planted"] = foot_pos
				var err := Vector2(foot_pos.x - desired.x, foot_pos.z - desired.z).length()
				f["idle"] = float(f["idle"]) + dt
				var threshold := def.stride * 0.5
				var want_step := err > threshold or (err > def.stride * 0.12 and float(f["idle"]) > 0.35)
				if want_step:
					var blocked := false
					for g in any_stepping:
						if g != f["group"]:
							blocked = true
					if not blocked:
						var dur := clampf(def.step_time * (1.0 - minf(speed, 6.0) * 0.07), 0.12, 0.32)
						f["stepping"] = true
						f["t"] = 0.0
						f["dur"] = dur
						f["from"] = foot_pos
						f["to"] = desired + vel * dur * 0.35
						f["idle"] = 0.0
						any_stepping[f["group"]] = true
		_solve_limb(c.name, c, foot_pos, yb * c.pole)
