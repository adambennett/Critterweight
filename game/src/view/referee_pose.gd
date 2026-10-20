class_name RefereePose
extends RefCounted
## View-only port of Cage Rules' kinematic pose evaluator (render.js: P() poses, lerpPose, two-bone
## solveIK, the hidden IK skeleton root -> body -> torso -> neck / shoulders -> elbows and body ->
## hips -> knees, _applySkeleton, the breathing bob and the stepping block of FighterModel.update's
## "forced" path), as used by the referee. It turns a pose plus a placement into Critterweight
## segment transforms for a CreatureView (RefereeView). Never touches the simulation.
##
## Invariants:
##  * Poses are the source P() format in SOURCE units (metres, radians, unscaled, Cage Rules frame:
##    +X = his left, +Y up, +Z forward, identical to Critterweight's fighter space). The model's
##    internal state (px, pz, vx, vz) is in source units too, so every threshold matches the source;
##    update() takes and transforms() returns Critterweight world metres (x, z / scale on the way in,
##    scale on the way out, the root stands on y = 0).
##  * Output: one world Transform3D per segment id (SEG_ORDER, the rig's eleven segments), origin on
##    the segment's PIVOT: scale * (frame centre + q * anchor_self), basis = the frame's rotation.
##    That is exactly the bind convention of cage_referee.glb (bones on the pivots, identity rest).
##  * The rig constants come from assets/data/cage_referee.json "rig" (exported from render.js by
##    tools/cage_rules/import.js); the code below only mirrors the source's math. Baked transforms in
##    the same file pin this port to the original (test_referee_view.gd).

const SEG_ORDER := ["pelvis", "chest", "head", "lUpperArm", "lForearm", "rUpperArm", "rForearm", "lThigh", "lShin", "rThigh", "rShin"]
const DOWN := Vector3(0, -1, 0)
const POS_LERP := 1000.0       ## Referee.update passes posLerp 1000: the model sits on the director's spot
const IDX := 2                 ## the referee's model slot (breathing bob phase)


## One pose in the source P() format (defaults = P({})).
class Pose:
	extends RefCounted
	var h := 0.92
	var lean := 0.08
	var yaw := -0.25
	var roll := 0.0
	var lh := Vector3(0.14, 0.42, 0.34)    ## left hand target, torso frame
	var rh := Vector3(-0.16, 0.38, 0.22)
	var lf := Vector2(0.16, 0.2)           ## left foot x, z, root frame
	var rf := Vector2(-0.2, -0.24)
	var lfy := 0.0                         ## foot lift
	var rfy := 0.0
	var hp := 0.05                         ## head pitch / yaw
	var hy := 0.15
	var lie := 0.0
	var ox := 0.0
	var oz := 0.0
	var elbow_out := 0.5
	var elbow_up := 0.0
	var hip_yaw := 0.0
	var l_pole := Vector3(0, 0, 1)
	var r_pole := Vector3(0, 0, 1)

	static func from_dict(d: Dictionary) -> Pose:
		var p := Pose.new()
		p.h = float(d.get("h", p.h))
		p.lean = float(d.get("lean", p.lean))
		p.yaw = float(d.get("yaw", p.yaw))
		p.roll = float(d.get("roll", p.roll))
		p.lh = _v3(d.get("lh", null), p.lh)
		p.rh = _v3(d.get("rh", null), p.rh)
		p.lf = _v2(d.get("lf", null), p.lf)
		p.rf = _v2(d.get("rf", null), p.rf)
		p.lfy = float(d.get("lfy", p.lfy))
		p.rfy = float(d.get("rfy", p.rfy))
		p.hp = float(d.get("hp", p.hp))
		p.hy = float(d.get("hy", p.hy))
		p.lie = float(d.get("lie", p.lie))
		p.ox = float(d.get("ox", p.ox))
		p.oz = float(d.get("oz", p.oz))
		p.elbow_out = float(d.get("elbowOut", p.elbow_out))
		p.elbow_up = float(d.get("elbowUp", p.elbow_up))
		p.hip_yaw = float(d.get("hipYaw", p.hip_yaw))
		p.l_pole = _v3(d.get("lPole", null), p.l_pole)
		p.r_pole = _v3(d.get("rPole", null), p.r_pole)
		return p

	static func _v3(v, fallback: Vector3) -> Vector3:
		if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
			return Vector3(float(v[0]), float(v[1]), float(v[2]))
		return fallback

	static func _v2(v, fallback: Vector2) -> Vector2:
		if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
			return Vector2(float(v[0]), float(v[1]))
		return fallback

	func copy() -> Pose:
		var p := Pose.new()
		p.set_from(self)
		return p

	func set_from(o: Pose) -> void:
		h = o.h
		lean = o.lean
		yaw = o.yaw
		roll = o.roll
		lh = o.lh
		rh = o.rh
		lf = o.lf
		rf = o.rf
		lfy = o.lfy
		rfy = o.rfy
		hp = o.hp
		hy = o.hy
		lie = o.lie
		ox = o.ox
		oz = o.oz
		elbow_out = o.elbow_out
		elbow_up = o.elbow_up
		hip_yaw = o.hip_yaw
		l_pole = o.l_pole
		r_pole = o.r_pole

	## lerpPose(this, b, t, this): every number and array component moves t of the way to b.
	func lerp_to(b: Pose, t: float) -> void:
		h += (b.h - h) * t
		lean += (b.lean - lean) * t
		yaw += (b.yaw - yaw) * t
		roll += (b.roll - roll) * t
		lh += (b.lh - lh) * t
		rh += (b.rh - rh) * t
		lf += (b.lf - lf) * t
		rf += (b.rf - rf) * t
		lfy += (b.lfy - lfy) * t
		rfy += (b.rfy - rfy) * t
		hp += (b.hp - hp) * t
		hy += (b.hy - hy) * t
		lie += (b.lie - lie) * t
		ox += (b.ox - ox) * t
		oz += (b.oz - oz) * t
		elbow_out += (b.elbow_out - elbow_out) * t
		elbow_up += (b.elbow_up - elbow_up) * t
		hip_yaw += (b.hip_yaw - hip_yaw) * t
		l_pole += (b.l_pole - l_pole) * t
		r_pole += (b.r_pole - r_pole) * t


# ---- rig (source units; from the data file, defaults = the values render.js derives from physics.js)
var scale := 1.06
var hip_h := 0.92
var sh_x := 0.23
var sh_y := 0.51
var hip_xx := 0.10
var hip_y := -0.08
var upper_l := 0.28
var fore_l := 0.32
var thigh_l := 0.48
var shin_l := 0.49
var neck_y := 0.68
var seg_offset := {"pelvis": 0.0, "chest": 0.34, "head": 0.0, "lUpperArm": -0.14, "lForearm": -0.14, "rUpperArm": -0.14,
	"rForearm": -0.14, "lThigh": -0.24, "lShin": -0.24, "rThigh": -0.24, "rShin": -0.24}
var anchor_self := {}          ## seg id -> Vector3

# ---- model state (FighterModel: px/pz/vx/vz in source units)
var px := 0.0
var pz := 0.0
var yaw := 0.0
var vx := 0.0
var vz := 0.0
var step_phase := 0.0
var pose := Pose.new()         ## the smoothed pose (FighterModel.pose)
var initialized := false
var snap := false              ## jump straight to the next forced placement and pose
var _xf := {}                  ## seg id -> Transform3D, Critterweight world


func setup(rig: Dictionary, scale_: float) -> void:
	scale = scale_
	hip_h = float(rig.get("hip_h", hip_h))
	sh_x = float(rig.get("sh_x", sh_x))
	sh_y = float(rig.get("sh_y", sh_y))
	hip_xx = float(rig.get("hip_xx", hip_xx))
	hip_y = float(rig.get("hip_y", hip_y))
	upper_l = float(rig.get("upper_l", upper_l))
	fore_l = float(rig.get("fore_l", fore_l))
	thigh_l = float(rig.get("thigh_l", thigh_l))
	shin_l = float(rig.get("shin_l", shin_l))
	neck_y = float(rig.get("neck_y", neck_y))
	var so: Dictionary = rig.get("seg_offset", {})
	for k in so:
		seg_offset[str(k)] = float(so[k])
	var an: Dictionary = rig.get("anchor_self", {})
	for id in SEG_ORDER:
		anchor_self[id] = Pose._v3(an.get(id, null), Vector3.ZERO)


static func expo(dt: float, k: float) -> float:
	return 1.0 - exp(-dt * k)


## FighterModel.update, forced path. x, z: Critterweight world metres; yaw_ radians (0 faces +Z);
## target: the pose to ease toward at `speed` (snap copies it); moving drives the stepping; time is
## the clock of the breathing bob.
func update(x: float, z: float, yaw_: float, target: Pose, moving: bool, speed: float, dt: float, time: float) -> void:
	var tx := x / scale
	var tz := z / scale
	var was_snap := snap
	snap = false
	if not initialized or was_snap:
		px = tx
		pz = tz
		yaw = yaw_
		initialized = true
		vx = 0.0
		vz = 0.0
	var opx := px
	var opz := pz
	px += (tx - px) * expo(dt, POS_LERP)
	pz += (tz - pz) * expo(dt, POS_LERP)
	if dt > 0.0:
		var ev := expo(dt, 10.0)
		vx += ((px - opx) / dt - vx) * ev
		vz += ((pz - opz) / dt - vz) * ev
	yaw += wrapf(yaw_ - yaw, -PI, PI) * expo(dt, 10.0)
	if was_snap:
		pose.set_from(target)
	else:
		pose.lerp_to(target, expo(dt, speed if speed > 0.0 else 12.0))
	var bob := sin(time * 2.1 + IDX) * 0.012
	_solve(pose.copy(), bob, moving, dt)


func transform_of(id: String) -> Transform3D:
	return _xf.get(id, Transform3D.IDENTITY)


## Transforms in a body's segment order (unknown segments keep identity).
func transforms_for(body: BodyDef) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(body.segments.size())
	for s: BodyDef.Seg in body.segments:
		out[s.index] = transform_of(s.id)
	return out


## three.js Euler order 'XYZ' (the default of Object3D.rotation and Euler).
static func euler_xyz(x: float, y: float, z: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, x) * Quaternion(Vector3.UP, y) * Quaternion(Vector3(0, 0, 1), z)


## three.js Quaternion.setFromUnitVectors (shortest arc, with its opposite-vector branch).
static func from_unit_vectors(a: Vector3, b: Vector3) -> Quaternion:
	var r := a.dot(b) + 1.0
	var q: Quaternion
	if r < 2.220446049250313e-16:
		if absf(a.x) > absf(a.z):
			q = Quaternion(-a.y, a.x, 0.0, 0.0)
		else:
			q = Quaternion(0.0, -a.z, a.y, 0.0)
	else:
		q = Quaternion(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x, r)
	return q.normalized()


## solveIK: [upper rotation, lower rotation], both relative to the chain root's parent frame (the
## lower group's local rotation is upper.inverse() * lower).
static func solve_ik(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Array[Quaternion]:
	var d := target - root
	var dist := d.length()
	var max_r := l1 + l2 - 0.005
	var min_r := absf(l1 - l2) + 0.02
	var dn := DOWN
	if dist >= 1e-4:
		dn = d / dist
	else:
		dist = 1e-4
	dist = clampf(dist, min_r, max_r)
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a := acos(cos_a)
	var p := pole - dn * pole.dot(dn)
	if p.length_squared() < 1e-6:
		p = Vector3(0, 0, 1) - dn * dn.z
	p = p.normalized()
	var u := dn * cos(a) + p * sin(a)
	var e := root + u * l1
	var l := (root + dn * dist - e).normalized()
	return [from_unit_vectors(DOWN, u), from_unit_vectors(DOWN, l)]


## The hidden IK skeleton for pose p (already a per-frame copy), then _applySkeleton.
func _solve(p: Pose, bob: float, moving: bool, dt: float) -> void:
	var q_root := Quaternion(Vector3.UP, yaw)
	var root := Vector3(px, 0.0, pz)
	# body (hips) and torso (authored in the root frame, so the hip yaw is undone)
	var body_pos := root + q_root * Vector3(p.ox, p.h + bob, p.oz)
	var q_body := q_root * euler_xyz(p.lie, p.hip_yaw, 0.0)
	var q_torso_local := euler_xyz(p.lean, p.yaw, p.roll)
	if p.hip_yaw != 0.0:
		q_torso_local = Quaternion(Vector3.UP, -p.hip_yaw) * q_torso_local
	var q_torso := q_body * q_torso_local
	var torso_pos := body_pos
	var q_neck := q_torso * euler_xyz(p.hp, p.hy, 0.0)
	var neck_pos := torso_pos + q_torso * Vector3(0, neck_y, 0)
	# arms (torso frame)
	var pole_y := -0.4 - p.elbow_out * 0.3 + p.elbow_up
	var l_sh := Vector3(sh_x, sh_y, 0)
	var r_sh := Vector3(-sh_x, sh_y, 0)
	var la := solve_ik(l_sh, p.lh, upper_l, fore_l, Vector3(1, pole_y, -0.6))
	var ra := solve_ik(r_sh, p.rh, upper_l, fore_l, Vector3(-1, pole_y, -0.6))
	# legs (body frame)
	var l_hip := Vector3(hip_xx, hip_y, 0)
	var r_hip := Vector3(-hip_xx, hip_y, 0)
	var ll: Array[Quaternion]
	var rl: Array[Quaternion]
	if p.lie > -0.5:
		var lfx := p.lf.x
		var lfz := p.lf.y
		var rfx := p.rf.x
		var rfz := p.rf.y
		var lfy := p.lfy
		var rfy := p.rfy
		if moving:
			# stride along the way he is actually travelling, in his own frame (heel to toe forward and
			# back, step-and-close sideways); each foot lifts while it moves the way he goes
			step_phase += dt * 9.0
			var s := sin(step_phase)
			var c := cos(step_phase)
			var cy := cos(yaw)
			var sy := sin(yaw)
			var sp := Vector2(vx, vz).length()
			var ux := 0.0
			var uz := 1.0
			if sp > 0.15:
				ux = (vx * cy - vz * sy) / sp
				uz = (vx * sy + vz * cy) / sp
			var amp := 0.12 - 0.03 * absf(ux)
			lfx += ux * amp * s
			lfz += uz * amp * s
			rfx -= ux * amp * s
			rfz -= uz * amp * s
			lfy += maxf(0.0, c) * 0.08
			rfy += maxf(0.0, -c) * 0.08
		var ch := cos(p.hip_yaw)
		var shy := sin(p.hip_yaw)
		var lx := lfx - p.ox
		var lz := lfz - p.oz
		var lt := Vector3(lx * ch - lz * shy, lfy - (p.h + bob) + 0.05, lx * shy + lz * ch)
		var rx := rfx - p.ox
		var rz := rfz - p.oz
		var rt := Vector3(rx * ch - rz * shy, rfy - (p.h + bob) + 0.05, rx * shy + rz * ch)
		ll = solve_ik(l_hip, lt, thigh_l, shin_l, p.l_pole)
		rl = solve_ik(r_hip, rt, thigh_l, shin_l, p.r_pole)
	else:
		# lying on the back: targets straight in the body frame, knees tipped toward the head
		ll = solve_ik(l_hip, Vector3(p.lf.x, p.lfy, p.lf.y), thigh_l, shin_l, p.l_pole + Vector3(0, 0.3, 0))
		rl = solve_ik(r_hip, Vector3(p.rf.x, p.rfy, p.rf.y), thigh_l, shin_l, p.r_pole + Vector3(0, 0.3, 0))
	# bone world frames
	var q_lsh := q_torso * la[0]
	var q_rsh := q_torso * ra[0]
	var lsh_pos := torso_pos + q_torso * l_sh
	var rsh_pos := torso_pos + q_torso * r_sh
	var lel_pos := lsh_pos + q_lsh * Vector3(0, -upper_l, 0)
	var rel_pos := rsh_pos + q_rsh * Vector3(0, -upper_l, 0)
	var q_lel := q_torso * la[1]
	var q_rel := q_torso * ra[1]
	var q_lhip := q_body * ll[0]
	var q_rhip := q_body * rl[0]
	var lhip_pos := body_pos + q_body * l_hip
	var rhip_pos := body_pos + q_body * r_hip
	var lkn_pos := lhip_pos + q_lhip * Vector3(0, -thigh_l, 0)
	var rkn_pos := rhip_pos + q_rhip * Vector3(0, -thigh_l, 0)
	var q_lkn := q_body * ll[1]
	var q_rkn := q_body * rl[1]
	_seg("pelvis", body_pos, q_body)
	_seg("chest", torso_pos, q_torso)
	_seg("head", neck_pos, q_neck)
	_seg("lUpperArm", lsh_pos, q_lsh)
	_seg("rUpperArm", rsh_pos, q_rsh)
	_seg("lForearm", lel_pos, q_lel)
	_seg("rForearm", rel_pos, q_rel)
	_seg("lThigh", lhip_pos, q_lhip)
	_seg("rThigh", rhip_pos, q_rhip)
	_seg("lShin", lkn_pos, q_lkn)
	_seg("rShin", rkn_pos, q_rkn)


## _segFromBone: the segment frame sits on the bone, pushed along its own y by the segment offset;
## stored as the Critterweight transform (origin on the scaled pivot).
func _seg(id: String, bone_pos: Vector3, q: Quaternion) -> void:
	var off := float(seg_offset.get(id, 0.0))
	var centre := bone_pos + q * Vector3(0, off, 0)
	var a: Vector3 = anchor_self.get(id, Vector3.ZERO)
	_xf[id] = Transform3D(Basis(q), (centre + q * a) * scale)
