class_name MathX
## Small, allocation-free math helpers shared by the simulation and views.
##
## Conventions (see docs/DESIGN.md "Fighter space"):
##   Fighter space: +Z forward (toward the target), +Y up, +X = the fighter's LEFT.
##   Yaw is a rotation about +Y; yaw 0 faces world +Z.

const DEG := PI / 180.0


static func clampf01(v: float) -> float:
	return clampf(v, 0.0, 1.0)


static func smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func yaw_basis(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw)


static func yaw_of_dir(d: Vector3) -> float:
	return atan2(d.x, d.z)


static func forward_of_yaw(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)


static func vec3(a: Array, fallback := Vector3.ZERO) -> Vector3:
	if a == null or a.size() < 3:
		return fallback
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Euler degrees (intrinsic X then Y then Z, as authored in content JSON) -> Quaternion.
static func euler_deg(e: Vector3) -> Quaternion:
	return Basis.from_euler(e * DEG, EULER_ORDER_XYZ).get_rotation_quaternion()


## Rotation vector (axis * angle, radians) of the shortest rotation represented by q.
static func rotvec(q: Quaternion) -> Vector3:
	if q.w < 0.0:
		q = Quaternion(-q.x, -q.y, -q.z, -q.w)
	var w := clampf(q.w, -1.0, 1.0)
	var half := acos(w)
	var s := sin(half)
	if s < 1e-6:
		return Vector3(q.x, q.y, q.z) * 2.0
	var k := (2.0 * half) / s
	return Vector3(q.x * k, q.y * k, q.z * k)


## Orthonormal basis whose first column is `primary` and whose second column is the part of
## `secondary` perpendicular to it. Used by IK so rest and target frames are built identically.
static func frame_from(primary: Vector3, secondary: Vector3) -> Basis:
	var e1 := primary.normalized()
	var e2 := secondary - e1 * secondary.dot(e1)
	if e2.length_squared() < 1e-10:
		e2 = e1.cross(Vector3.RIGHT if absf(e1.x) < 0.9 else Vector3.FORWARD)
	e2 = e2.normalized()
	var e3 := e1.cross(e2)
	return Basis(e1, e2, e3)


## Shortest rotation taking unit vector a onto unit vector b.
static func rotation_between(a: Vector3, b: Vector3) -> Quaternion:
	a = a.normalized()
	b = b.normalized()
	var d := a.dot(b)
	if d > 0.999999:
		return Quaternion.IDENTITY
	if d < -0.999999:
		var axis := a.cross(Vector3.RIGHT)
		if axis.length_squared() < 1e-6:
			axis = a.cross(Vector3.UP)
		return Quaternion(axis.normalized(), PI)
	var c := a.cross(b)
	return Quaternion(c.x, c.y, c.z, 1.0 + d).normalized()


## Closest point on segment [a, b] to p.
static func closest_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-12:
		return a
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return a + ab * t


## Closest points between segments [p1,q1] and [p2,q2]; returns [c1, c2].
static func closest_between_segments(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-10 and e <= 1e-10:
		return [p1, p2]
	if a <= 1e-10:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-10:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom != 0.0:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]


## Exponential smoothing factor for a time constant tau (seconds) over dt.
static func damp_factor(tau: float, dt: float) -> float:
	if tau <= 0.0:
		return 1.0
	return 1.0 - exp(-dt / tau)


## Deterministic 32-bit string hash (FNV-1a) for stable ids and seeds.
static func hash32(s: String) -> int:
	var h := 2166136261
	for b in s.to_utf8_buffer():
		h = (h ^ b) * 16777619
		h &= 0xFFFFFFFF
	return h
