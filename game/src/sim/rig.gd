class_name Rig
extends Node3D
## The physical half of a fighter: one RigidBody3D per BodyDef segment joined by
## Generic6DOFJoint3D "muscles". Every tick FighterMotor writes desired GLOBAL segment rotations;
## the Rig converts them to parent-relative targets and feeds them to Jolt's implicit angular
## springs (stable at any stiffness, unlike explicit PD torques). The root segment is tied to a
## static anchor by an angular-only spring (uprightness + facing), held at stance height by a
## hover spring, and driven toward a desired horizontal velocity.
##
## Jolt convention (measured, see docs/DECISIONS.md D-009): a 6DOF angular spring settles where
## relative_rotation = inverse(Euler_XYZ(equilibrium_point)).
##
## Authority: the Rig only exists where the match is simulated (server / offline / AI Lab).
## Clients render from snapshots of `segment_transforms()`.

const LAYER_WORLD := 1
const LAYER_FIGHTERS := 2
const LAYER_PROJECTILES := 4
const LAYER_DEBRIS := 8
const LAYER_PROPS := 16

const HOVER_W := 11.0           ## hover spring natural frequency (rad/s)
const HOVER_ZETA := 0.9
const ROOT_W := 14.0            ## upright / yaw spring natural frequency
const ROOT_ZETA := 1.1
const TONE_EPS := 0.015         ## re-send spring gains when tone changes more than this

var def: BodyDef
var bodies: Array[RigidBody3D] = []
var joints: Array[Generic6DOFJoint3D] = []   ## index = segment index (root slot = anchor joint)
var joint_rids: Array[RID] = []
var rids: Array[RID] = []
var fighter_index := 0
var anchor: StaticBody3D

## ---- control inputs (written by FighterMotor / Fighter each tick) ----
var target_rot: Array[Quaternion] = []
var tracked: PackedByteArray = PackedByteArray()
var seg_muscle: PackedFloat32Array = PackedFloat32Array()  ## per segment 0..1 (stagger)
var seg_speed: PackedFloat32Array = PackedFloat32Array()   ## per segment stiffness multiplier
var muscle := 1.0              ## global tone 0..1 (knockdown/KO lowers it)
var support := 1.0             ## anti-gravity fraction applied while grounded
var hover_enabled := true
var hover_height := 1.0        ## desired root pivot height above the floor
var desired_vel := Vector3.ZERO
var max_accel := 28.0          ## m/s^2 horizontal drive authority
var yaw_target := 0.0
var lean := Vector3.ZERO       ## euler degrees in fighter space (x = pitch forward)
var upright_strength := 1.0    ## 0..1 multiplier on the root spring
var mass_scale := 1.0

## ---- derived state (read by the fighter, views, AI) ----
var ground_y := 0.0
var grounded := true
var ground_dist := 0.0
var total_mass := 1.0
var root_inertia := 1.0
var _qa_off: Array[Quaternion] = []   ## joint frame in body A (rest), per joint
var _qb_off: Array[Quaternion] = []   ## joint frame in body B (rest), per joint
var _sent_tone: PackedFloat32Array = PackedFloat32Array()
var _ray := PhysicsRayQueryParameters3D.new()


func build(body_def: BodyDef, index: int, pos: Vector3, yaw: float, material: PhysicsMaterial = null) -> void:
	def = body_def
	fighter_index = index
	name = "Rig%d" % index
	var n := def.segments.size()
	target_rot.resize(n)
	tracked.resize(n)
	seg_muscle.resize(n)
	seg_speed.resize(n)
	_qa_off.resize(n)
	_qb_off.resize(n)
	_sent_tone.resize(n)
	_sent_tone.fill(-1.0)
	var mat := material
	if mat == null:
		mat = PhysicsMaterial.new()
		mat.friction = 0.45
		mat.bounce = 0.0
	total_mass = 0.0
	for s: BodyDef.Seg in def.segments:
		var rb := RigidBody3D.new()
		rb.name = s.id
		rb.mass = s.mass * mass_scale
		total_mass += rb.mass
		rb.can_sleep = false
		rb.continuous_cd = s.part in ["arm", "leg", "tail", "wing", "horn"]
		rb.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		rb.linear_damp = 0.05
		rb.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		rb.angular_damp = 0.3
		rb.physics_material_override = mat
		rb.collision_layer = LAYER_FIGHTERS if s.collide else 0
		rb.collision_mask = (LAYER_WORLD | LAYER_FIGHTERS | LAYER_PROPS) if s.collide else LAYER_WORLD
		for sh: BodyDef.Shape in s.shapes:
			var cs := CollisionShape3D.new()
			match sh.type:
				BodyDef.SHAPE_CAPSULE:
					var seg_len := sh.a.distance_to(sh.b)
					if seg_len < 0.005:
						var sp := SphereShape3D.new()
						sp.radius = sh.radius
						cs.shape = sp
						cs.position = sh.a
					else:
						var cap := CapsuleShape3D.new()
						cap.radius = sh.radius
						cap.height = seg_len + sh.radius * 2.0
						cs.shape = cap
						cs.transform = Transform3D(Basis(MathX.rotation_between(Vector3.UP, sh.b - sh.a)), (sh.a + sh.b) * 0.5)
				BodyDef.SHAPE_SPHERE:
					var sp2 := SphereShape3D.new()
					sp2.radius = sh.radius
					cs.shape = sp2
					cs.position = sh.a
				BodyDef.SHAPE_BOX:
					var bx := BoxShape3D.new()
					bx.size = sh.size
					cs.shape = bx
					cs.position = sh.a
			rb.add_child(cs)
		add_child(rb)
		bodies.append(rb)
		rids.append(rb.get_rid())
		tracked[s.index] = 1
		seg_muscle[s.index] = 1.0
		seg_speed[s.index] = 1.0
	for i in n:
		for k in range(i + 1, n):
			bodies[i].add_collision_exception_with(bodies[k])
	place(pos, yaw)
	var yq := MathX.yaw_basis(yaw).get_rotation_quaternion()
	# anchor for the root's angular spring (no collision, never moves)
	anchor = StaticBody3D.new()
	anchor.name = "Anchor"
	anchor.collision_layer = 0
	anchor.collision_mask = 0
	add_child(anchor)
	anchor.global_transform = Transform3D.IDENTITY
	joints.resize(n)
	joint_rids.resize(n)
	for s: BodyDef.Seg in def.segments:
		var j := Generic6DOFJoint3D.new()
		j.name = "J_" + s.id
		add_child(j)
		var body_b := bodies[s.index]
		j.global_transform = Transform3D(Basis(yq), body_b.global_position)
		var body_a: PhysicsBody3D = anchor if s.parent < 0 else bodies[s.parent]
		j.node_a = j.get_path_to(body_a)
		j.node_b = j.get_path_to(body_b)
		j.exclude_nodes_from_collision = true
		for ax in ["x", "y", "z"]:
			j.set("linear_limit_%s/enabled" % ax, s.parent >= 0)
			j.set("angular_limit_%s/enabled" % ax, false)
			j.set("angular_spring_%s/enabled" % ax, true)
			j.set("angular_spring_%s/stiffness" % ax, 0.0)
			j.set("angular_spring_%s/damping" % ax, 0.0)
		joints[s.index] = j
		joint_rids[s.index] = j.get_rid()
		# joint frame expressed in each body's rest frame
		var a_rest := Quaternion.IDENTITY if s.parent < 0 else yq
		_qa_off[s.index] = a_rest.inverse() * yq
		_qb_off[s.index] = yq.inverse() * yq
	root_inertia = 0.0
	for s: BodyDef.Seg in def.segments:
		root_inertia += s.mass * mass_scale * (s.pivot + s.com_local - def.segments[0].pivot).length_squared()
	root_inertia = maxf(root_inertia, total_mass * 0.05)
	hover_height = def.hover_height
	yaw_target = yaw
	_ray.collision_mask = LAYER_WORLD | LAYER_PROPS
	_ray.exclude = rids


## Teleports the whole body to its rest pose at `pos` (floor point under the root) facing `yaw`.
func place(pos: Vector3, yaw: float) -> void:
	var yb := MathX.yaw_basis(yaw)
	var root_pivot: Vector3 = def.segments[0].pivot
	for s: BodyDef.Seg in def.segments:
		var rb := bodies[s.index]
		var local := s.pivot - Vector3(root_pivot.x, 0.0, root_pivot.z)
		rb.global_transform = Transform3D(yb, pos + yb * local)
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		target_rot[s.index] = yb.get_rotation_quaternion()
	yaw_target = yaw


## Moves every segment by `delta` keeping the current pose; removes velocity along `delta`'s
## opposite (used to pull a body back through a boundary it should never have crossed).
func shift(delta: Vector3) -> void:
	var back := -delta.normalized() if delta.length_squared() > 1e-8 else Vector3.ZERO
	for rb in bodies:
		rb.global_position += delta
		var out := rb.linear_velocity.dot(back)
		if out > 0.0:
			rb.linear_velocity -= back * out


func root() -> RigidBody3D:
	return bodies[0]


func root_pos() -> Vector3:
	return bodies[0].global_position


## Velocity of the whole body's centre of mass.
func com_velocity() -> Vector3:
	var acc := Vector3.ZERO
	for rb in bodies:
		acc += rb.linear_velocity * rb.mass
	return acc / total_mass


func com_position() -> Vector3:
	var acc := Vector3.ZERO
	for i in bodies.size():
		var rb := bodies[i]
		var sd: BodyDef.Seg = def.segments[i]
		acc += (rb.global_transform * sd.com_local) * rb.mass
	return acc / total_mass


## Actual facing yaw of the root (projection of its local +Z on the floor plane).
func actual_yaw() -> float:
	var f := bodies[0].global_basis.z
	return atan2(f.x, f.z)


func point_velocity(seg_index: int, world_point: Vector3) -> Vector3:
	var rb := bodies[seg_index]
	var sd: BodyDef.Seg = def.segments[seg_index]
	var com := rb.global_transform * sd.com_local
	return rb.linear_velocity + rb.angular_velocity.cross(world_point - com)


func segment_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(bodies.size())
	for i in bodies.size():
		out[i] = bodies[i].global_transform
	return out


func probe_ground() -> void:
	var space := get_world_3d().direct_space_state
	var p := bodies[0].global_position
	_ray.from = p + Vector3.UP * 0.2
	_ray.to = p + Vector3.DOWN * (hover_height + 0.6)
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		grounded = false
		ground_dist = 99.0
	else:
		ground_y = hit.position.y
		ground_dist = p.y - ground_y
		grounded = ground_dist < hover_height + 0.35


## Applies hover/drive forces and updates every joint's spring target. Call from _physics_process.
func step(_dt: float) -> void:
	probe_ground()
	var g := 9.81
	var root_rb := bodies[0]
	var m := total_mass
	# ---- anti-gravity support (muscles carrying the body) ----
	var sup := support * muscle if grounded else 0.0
	if sup > 0.0:
		for rb in bodies:
			rb.apply_central_force(Vector3.UP * rb.mass * g * sup)
	# ---- hover spring on the root ----
	if hover_enabled and grounded and muscle > 0.05:
		var err := hover_height - ground_dist
		var vy := root_rb.linear_velocity.y
		var fy := m * (HOVER_W * HOVER_W * err - 2.0 * HOVER_ZETA * HOVER_W * vy) * muscle
		fy = clampf(fy, -m * g * 2.0, m * g * 3.0)
		root_rb.apply_central_force(Vector3(0.0, fy, 0.0))
	# ---- horizontal drive (shared across segments so limbs travel with the body) ----
	if muscle > 0.05 and (grounded or support > 0.0):
		var v := com_velocity()
		var dv := Vector3(desired_vel.x - v.x, 0.0, desired_vel.z - v.z)
		var acc := dv * 12.0
		var amax := max_accel * muscle
		if acc.length() > amax:
			acc = acc.normalized() * amax
		for rb in bodies:
			rb.apply_central_force(acc * rb.mass)
	# ---- root orientation spring (upright + facing) ----
	var up_k := upright_strength * muscle
	var q_root_t := (MathX.yaw_basis(yaw_target) * Basis.from_euler(lean * MathX.DEG, EULER_ORDER_XYZ)).get_rotation_quaternion()
	var rk := root_inertia * ROOT_W * ROOT_W * up_k
	var rc := root_inertia * 2.0 * ROOT_ZETA * ROOT_W * sqrt(maxf(up_k, 0.0))
	_send_gains(0, up_k, rk, rc)
	_send_target(0, Quaternion.IDENTITY, q_root_t)
	# ---- segment springs ----
	for i in range(1, bodies.size()):
		var s: BodyDef.Seg = def.segments[i]
		var tone := muscle * seg_muscle[i]
		if tracked[i] == 0:
			tone = 0.0
		var w0 := s.w0 * seg_speed[i]
		var inertia := s.i_eff * mass_scale
		var k := inertia * w0 * w0 * tone * s.strength
		var c := inertia * 2.0 * s.zeta * w0 * sqrt(maxf(tone, 0.0))
		_send_gains(i, tone * seg_speed[i], k, c)
		_send_target(i, bodies[s.parent].global_basis.get_rotation_quaternion(), target_rot[i])


func _send_gains(i: int, tone_key: float, k: float, c: float) -> void:
	if absf(_sent_tone[i] - tone_key) < TONE_EPS and _sent_tone[i] >= 0.0:
		return
	_sent_tone[i] = tone_key
	var rid := joint_rids[i]
	for ax in 3:
		PhysicsServer3D.generic_6dof_joint_set_param(rid, ax, PhysicsServer3D.G6DOF_JOINT_ANGULAR_SPRING_STIFFNESS, k)
		PhysicsServer3D.generic_6dof_joint_set_param(rid, ax, PhysicsServer3D.G6DOF_JOINT_ANGULAR_SPRING_DAMPING, c)


## q_a: actual global rotation of body A (identity for the anchor); q_b_target: desired global
## rotation of body B. Converts to the joint's relative frame and writes equilibrium angles.
func _send_target(i: int, q_a: Quaternion, q_b_target: Quaternion) -> void:
	var rel := (q_a * _qa_off[i]).inverse() * (q_b_target * _qb_off[i])
	var e := Basis(rel.inverse()).get_euler(EULER_ORDER_XYZ)
	var rid := joint_rids[i]
	PhysicsServer3D.generic_6dof_joint_set_param(rid, Vector3.AXIS_X, PhysicsServer3D.G6DOF_JOINT_ANGULAR_SPRING_EQUILIBRIUM_POINT, e.x)
	PhysicsServer3D.generic_6dof_joint_set_param(rid, Vector3.AXIS_Y, PhysicsServer3D.G6DOF_JOINT_ANGULAR_SPRING_EQUILIBRIUM_POINT, e.y)
	PhysicsServer3D.generic_6dof_joint_set_param(rid, Vector3.AXIS_Z, PhysicsServer3D.G6DOF_JOINT_ANGULAR_SPRING_EQUILIBRIUM_POINT, e.z)


## Instantly zeroes velocities (used when (re)spawning).
func freeze_motion() -> void:
	for rb in bodies:
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO


func apply_impulse_at(seg_index: int, impulse: Vector3, world_point: Vector3) -> void:
	var rb := bodies[seg_index]
	rb.apply_impulse(impulse, world_point - rb.global_position)


## Pushes the whole body (distributed by mass) — knockback.
func apply_body_impulse(impulse: Vector3) -> void:
	for rb in bodies:
		rb.apply_central_impulse(impulse * (rb.mass / total_mass))
