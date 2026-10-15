class_name CosmeticAttachments
extends RefCounted
## View-only fighter cosmetics (docs/HUB_SYSTEMS.md §16): the Cannery's gold tooth (gag piece),
## trash-can lid (idle prop), replica belt (walkout back piece) and rooftop scarf (neckwear) as small
## meshes that ride a body segment. CreatureView owns the nodes and moves them with the segment
## every frame; they have no collision, no physics and the simulation never sees them.
##
## Anchors are fitted to what you SEE: for forged models CreatureView hands in the model's own
## vertices per segment (segment-local rest positions), so rings sit on the skin and the lid on the
## forearm's outer side; fallback (segment-primitive) bodies use their body shapes. Works for every
## body plan (biped, avian, crab, quadruped, serpent, hopper). A creature can override one with
## art.attach.<kind> = {segment, offset: [x,y,z], rotation_deg: [x,y,z], size}. Coordinates are
## SEGMENT-LOCAL (rest orientation is identity: +Z forward, +Y up, +X the creature's left).
##   tooth: the front of the head, low (the mouth), hanging down — it is also the gag piece
##   lid:   on the outer side of the distal LEFT arm/wing, facing out; armless bodies wear it on the
##          back (upright bodies) or on top (quadrupeds, crabs)
##   belt:  a sash over the shoulder around the torso under the head
##   scarf: a ring where the head meets its parent segment, tails trailing behind

const KINDS := ["tooth", "lid", "belt", "scarf"]
## Pieces put away while the round is live (shown in the hub, on the walkout and when celebrating).
const WALKOUT_ONLY := ["lid", "belt"]
const BELT_TILT_DEG := 38.0


## {seg: int, xf: Transform3D (segment-local; basis = the piece's orientation), size: float} or {}.
## `points`: segment index -> PackedVector3Array of the model's vertices (segment-local), or {}.
static func anchor(c: CreatureDef, kind: String, points := {}) -> Dictionary:
	var body: BodyDef = c.body
	var over: Dictionary = (c.art.get("attach", {}) as Dictionary).get(kind, {})
	if not over.is_empty() and body.seg_index.has(str(over.get("segment", ""))):
		var si: int = body.seg_index[str(over["segment"])]
		var rot: Vector3 = MathX.vec3(over.get("rotation_deg", [0, 0, 0])) * (PI / 180.0)
		return {"seg": si, "xf": Transform3D(Basis.from_euler(rot), MathX.vec3(over.get("offset", [0, 0, 0]))), "size": float(over.get("size", 0.2))}
	match kind:
		"tooth":
			return _mouth(body, points)
		"lid":
			var arm := _arm_anchor(body, points)
			return arm if not arm.is_empty() else _back_anchor(body, points)
		"belt":
			return _belt_anchor(body, points)
		"scarf":
			return _neck_anchor(body, points)
	return {}


## The node tree for one attachment (unparented; the caller places it at the anchor's origin in
## segment space). `orient` turns the piece (disc/ring axis); scarf tails always hang down and back.
## `style`: {color, accent} from the cosmetic's data.
static func build(kind: String, style: Dictionary, size: float, orient := Basis.IDENTITY) -> Node3D:
	var top := Node3D.new()
	top.name = "Cosmetic_" + kind
	var root := Node3D.new()
	root.name = "Oriented"
	root.basis = orient
	top.add_child(root)
	var col := Color.from_string(str(style.get("color", "#E8B923")), Color(0.9, 0.72, 0.15))
	var acc := Color.from_string(str(style.get("accent", "#F7E7A1")), col.lightened(0.4))
	match kind:
		"tooth":
			var t := CylinderMesh.new()
			t.top_radius = size * 0.5
			t.bottom_radius = size * 0.18
			t.height = size * 1.5
			t.radial_segments = 6
			t.rings = 1
			_mesh(root, t, _mat(col, 0.22, 0.85, Color(col.r, col.g, col.b) * 0.35), Transform3D(Basis.IDENTITY, Vector3(0, -size * 0.55, 0)))
		"lid":
			var disc := CylinderMesh.new()
			disc.top_radius = size
			disc.bottom_radius = size * 0.97
			disc.height = size * 0.1
			disc.radial_segments = 20
			disc.rings = 1
			var metal := _mat(col, 0.45, 0.75)
			_mesh(root, disc, metal, Transform3D(Basis.IDENTITY, Vector3(0, size * 0.05, 0)))
			var rim := TorusMesh.new()
			rim.inner_radius = size * 0.93
			rim.outer_radius = size * 1.04
			rim.rings = 20
			rim.ring_segments = 6
			_mesh(root, rim, _mat(col.darkened(0.25), 0.5, 0.7), Transform3D(Basis.IDENTITY, Vector3(0, size * 0.05, 0)))
			for k in 3:
				# the pressed rings of a trash-can lid
				var ring := TorusMesh.new()
				ring.inner_radius = size * (0.28 + 0.2 * k)
				ring.outer_radius = size * (0.32 + 0.2 * k)
				ring.rings = 18
				ring.ring_segments = 4
				_mesh(root, ring, _mat(col.lightened(0.12), 0.4, 0.75), Transform3D(Basis.IDENTITY, Vector3(0, size * 0.1, 0)))
			var knob := TorusMesh.new()
			knob.inner_radius = size * 0.1
			knob.outer_radius = size * 0.18
			knob.rings = 12
			knob.ring_segments = 6
			_mesh(root, knob, _mat(acc, 0.4, 0.6), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, size * 0.2, 0)))
		"belt":
			var band := TorusMesh.new()
			band.inner_radius = size - 0.022
			band.outer_radius = size + 0.03
			band.rings = 32
			band.ring_segments = 6
			_mesh(root, band, _mat(col, 0.7, 0.0), Transform3D.IDENTITY)
			var plate := BoxMesh.new()
			var pw := clampf(size * 0.62, 0.12, 0.26)
			plate.size = Vector3(pw, pw * 0.68, 0.035)
			var gold := _mat(acc, 0.25, 0.85, Color(acc.r, acc.g, acc.b) * 0.2)
			_mesh(root, plate, gold, Transform3D(Basis.IDENTITY, Vector3(0, 0, size + 0.035)))
			var gem := SphereMesh.new()
			gem.radius = pw * 0.15
			gem.height = pw * 0.3
			_mesh(root, gem, _mat(Color("#C8322E"), 0.15, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, 0, size + 0.06)))
			for side in [-1.0, 1.0]:
				var side_plate := BoxMesh.new()
				side_plate.size = Vector3(pw * 0.45, pw * 0.45, 0.03)
				var ang := float(side) * 0.55
				_mesh(root, side_plate, gold, Transform3D(Basis(Vector3.UP, ang), Vector3(sin(ang), 0, cos(ang)) * (size + 0.03)))
			# the back of the sash too (seen from the follow camera behind you)
			var back_plate := BoxMesh.new()
			back_plate.size = Vector3(pw * 0.5, pw * 0.4, 0.03)
			_mesh(root, back_plate, gold, Transform3D(Basis.IDENTITY, Vector3(0, 0, -(size + 0.03))))
		"scarf":
			var wrap := TorusMesh.new()
			var th := clampf(size * 0.3, 0.035, 0.07)
			wrap.inner_radius = size - th * 0.5
			wrap.outer_radius = size + th
			wrap.rings = 24
			wrap.ring_segments = 8
			var cloth := _mat(col, 0.9, 0.0)
			_mesh(root, wrap, cloth, Transform3D.IDENTITY)
			for k in 2:
				var tail := BoxMesh.new()
				tail.size = Vector3(clampf(size * 0.42, 0.06, 0.12), clampf(size * 1.6, 0.18, 0.34), 0.03)
				var tilt := Basis(Vector3.RIGHT, 0.35 + 0.25 * k) * Basis(Vector3.FORWARD, (k - 0.5) * 0.5)
				_mesh(top, tail, cloth if k == 0 else _mat(acc, 0.9, 0.0), Transform3D(tilt, Vector3((k - 0.5) * size * 0.45, -tail.size.y * 0.42, -(size + th * 0.8))))
	return top


static func _mesh(parent: Node3D, m: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _mat(color: Color, rough: float, metal: float, emissive := Color.BLACK) -> StandardMaterial3D:
	var m: StandardMaterial3D = Materials.toon(color, rough, metal, 0.35, emissive).duplicate()
	m.next_pass = Materials.outline_material(0.006)
	return m


# ---- segments -----------------------------------------------------------------------------------

static func _head(body: BodyDef) -> BodyDef.Seg:
	for s: BodyDef.Seg in body.segments:
		if s.part == "head":
			return s
	return null


## The heaviest core/shell segment: the body itself.
static func _core(body: BodyDef) -> BodyDef.Seg:
	var best: BodyDef.Seg = null
	for s: BodyDef.Seg in body.segments:
		if s.part in ["core", "shell"] and (best == null or s.mass > best.mass):
			best = s
	return best if best != null else body.segments[0]


## The torso the head sits on: the heaviest core/shell segment within two joints of the head
## (a biped's chest, Gusto's torso, Dozer's chest, Slurry's upper coils); hoppers: the body.
static func _upper_core(body: BodyDef) -> BodyDef.Seg:
	var head := _head(body)
	if head == null:
		return _core(body)
	var best: BodyDef.Seg = null
	var p := head.parent
	var hops := 0
	while p >= 0 and hops < 2:
		var s: BodyDef.Seg = body.segments[p]
		if s.part in ["core", "shell"] and (best == null or s.mass > best.mass):
			best = s
		p = s.parent
		hops += 1
	return best if best != null else _core(body)


## The distal LEFT arm/wing segment (no arm/wing children), or null.
static func _left_arm(body: BodyDef) -> BodyDef.Seg:
	var best: BodyDef.Seg = null
	for s: BodyDef.Seg in body.segments:
		if not (s.part in ["arm", "wing"]) or s.pivot.x < 0.05:
			continue
		var distal := true
		for ci in s.children:
			if (body.segments[ci] as BodyDef.Seg).part in ["arm", "wing"]:
				distal = false
		if distal and (best == null or s.pivot.x > best.pivot.x):
			best = s
	return best


## Surface points of a segment (segment-local): the model's vertices when given, else points on
## its body shapes (spheres/capsules sampled in rings, box corners).
static func _pts(s: BodyDef.Seg, points: Dictionary) -> PackedVector3Array:
	var given = points.get(s.index, null)
	if given is PackedVector3Array and not (given as PackedVector3Array).is_empty():
		return given
	var out := PackedVector3Array()
	for sh: BodyDef.Shape in s.shapes:
		if sh.type == BodyDef.SHAPE_BOX:
			for ix in [-0.5, 0.5]:
				for iy in [-0.5, 0.5]:
					for iz in [-0.5, 0.5]:
						out.append(sh.a + Vector3(float(ix) * sh.size.x, float(iy) * sh.size.y, float(iz) * sh.size.z))
			continue
		var a := sh.a
		var b := sh.b if sh.type == BodyDef.SHAPE_CAPSULE else sh.a
		var r := sh.radius
		for t in [0.0, 0.5, 1.0]:
			var c := a.lerp(b, float(t))
			for lat in 7:
				var phi := PI * (float(lat) / 6.0 - 0.5)
				for lon in 12:
					var th := TAU * float(lon) / 12.0
					out.append(c + Vector3(cos(phi) * sin(th), sin(phi), cos(phi) * cos(th)) * r)
	return out


static func _centroid(p: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for v in p:
		c += v
	return c / maxf(1.0, float(p.size()))


static func _aabb(p: PackedVector3Array) -> AABB:
	if p.is_empty():
		return AABB()
	var box := AABB(p[0], Vector3.ZERO)
	for v in p:
		box = box.expand(v)
	return box


## Radius of the body's outline in the plane through `c` with normal `n` (points within `slab`).
static func _ring_radius(p: PackedVector3Array, c: Vector3, n: Vector3, slab: float) -> float:
	var r := 0.0
	for v in p:
		var d := (v - c).dot(n)
		if absf(d) <= slab:
			r = maxf(r, ((v - c) - n * d).length())
	return r


## Like _ring_radius but ignores protrusions (a snout, a beak, an antenna): the largest distance
## that is at most 1.5x the median distance of the points in the slab.
static func _ring_radius_robust(p: PackedVector3Array, c: Vector3, n: Vector3, slab: float) -> float:
	var ds: Array[float] = []
	for v in p:
		var d := (v - c).dot(n)
		if absf(d) <= slab:
			ds.append(((v - c) - n * d).length())
	if ds.is_empty():
		return 0.0
	ds.sort()
	var cap := ds[ds.size() / 2] * 1.5
	var r := 0.0
	for d2 in ds:
		if d2 <= cap:
			r = maxf(r, d2)
	return r


# ---- anchors ------------------------------------------------------------------------------------

static func _mouth(body: BodyDef, points: Dictionary) -> Dictionary:
	var s := _head(body)
	if s == null:
		s = _core(body)
	var p := _pts(s, points)
	if p.is_empty():
		return {}
	var box := _aabb(p)
	# the front of the lower half of the head: the mouth
	var mid_y := box.position.y + box.size.y * 0.55
	var front := Vector3(0, 0, -INF)
	for v in p:
		if v.y <= mid_y and v.z > front.z:
			front = v
	if front.z == -INF:
		return {}
	var size := clampf(box.size.y * 0.1, 0.022, 0.05)
	return {"seg": s.index, "xf": Transform3D(Basis.IDENTITY, front + Vector3(size * 0.6, size * 0.4, -size * 0.25)), "size": size}


static func _arm_anchor(body: BodyDef, points: Dictionary) -> Dictionary:
	var s := _left_arm(body)
	if s == null:
		return {}
	var p := _pts(s, points)
	if p.is_empty():
		return {}
	var box := _aabb(p)
	# the lid sits on the outer (+X) side of the arm, centred along it
	var outer := box.end.x
	var acc := Vector3.ZERO
	var n := 0
	for v in p:
		if v.x >= outer - maxf(0.03, box.size.x * 0.25):
			acc += v
			n += 1
	var c := acc / maxf(1.0, float(n))
	c.x = outer + 0.02
	var size := clampf(maxf(box.size.y, box.size.z) * 0.6, 0.18, 0.27)
	# the disc's axis (its local +Y) points out of the creature's left side
	return {"seg": s.index, "xf": Transform3D(Basis(Vector3.FORWARD, PI * 0.5), c), "size": size}


static func _back_anchor(body: BodyDef, points: Dictionary) -> Dictionary:
	var s := _upper_core(body)
	var p := _pts(s, points)
	if p.is_empty():
		return {}
	var box := _aabb(p)
	var size := clampf(minf(box.size.x, box.size.y) * 0.42, 0.18, 0.3)
	if body.gait in ["quadruped", "crab"]:
		# carried flat on top of a horizontal body, axis up
		var top := Vector3(box.position.x + box.size.x * 0.5, box.end.y + 0.02, box.position.z + box.size.z * 0.5)
		return {"seg": s.index, "xf": Transform3D(Basis(Vector3.RIGHT, -0.15), top), "size": size}
	# slung on the back of an upright body: the disc faces backwards (local +Y -> -Z)
	var back := Vector3(box.position.x + box.size.x * 0.5, box.position.y + box.size.y * 0.55, box.position.z - 0.02)
	return {"seg": s.index, "xf": Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), back), "size": size}


static func _belt_anchor(body: BodyDef, points: Dictionary) -> Dictionary:
	var s := _upper_core(body)
	var p := _pts(s, points)
	if p.is_empty():
		return {}
	var box := _aabb(p)
	var c := box.position + box.size * 0.5
	# a sash from the left shoulder to the right hip: the ring tilted about the forward axis; on a
	# horizontal body (quadruped, crab) a girth strap around the chest with the plate on top
	var basis := Basis(Vector3.FORWARD, deg_to_rad(BELT_TILT_DEG))
	if body.gait in ["quadruped", "crab"]:
		basis = Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.FORWARD, deg_to_rad(12.0))
	var n: Vector3 = basis.y
	var r := _ring_radius(p, c, n, maxf(0.04, box.size.y * 0.08))
	if r <= 0.01:
		r = maxf(box.size.x, box.size.z) * 0.5
	return {"seg": s.index, "xf": Transform3D(basis, c), "size": r + 0.02}


static func _neck_anchor(body: BodyDef, points: Dictionary) -> Dictionary:
	var head := _head(body)
	if head == null or head.parent < 0:
		# no neck (hoppers): a ring around the top of the body
		var core := _core(body)
		var cp := _pts(core, points)
		if cp.is_empty():
			return {}
		var box := _aabb(cp)
		var c := box.position + box.size * 0.5 + Vector3(0, box.size.y * 0.32, 0)
		var rr := _ring_radius_robust(cp, c, Vector3.UP, 0.03)
		return {"seg": core.index, "xf": Transform3D(Basis.IDENTITY, c), "size": maxf(rr, 0.08) + 0.015}
	var parent: BodyDef.Seg = body.segments[head.parent]
	var joint := head.pivot - parent.pivot              # the neck, in the parent's local space
	# the neck's direction: parent pivot -> head pivot (up for bipeds, forward for Dozer)
	var axis := joint.normalized() if joint.length() > 0.02 else Vector3.UP
	# the outline of the base of the head (the head's own points, parent frame), ignoring a snout or
	# a beak: the narrowest of a few slabs just above the joint
	var hp := PackedVector3Array()
	for v in _pts(head, points):
		hp.append(v + joint)
	var best_r := INF
	var best_t := 0.0
	for k in 4:
		var t := 0.01 + 0.025 * k
		var rr := _ring_radius_robust(hp, joint + axis * t, axis, 0.015)
		if rr > 0.04 and rr < best_r:
			best_r = rr
			best_t = t
	if best_r == INF:
		best_r = 0.1
	var basis := Basis(MathX.rotation_between(Vector3.UP, axis))
	return {"seg": parent.index, "xf": Transform3D(basis, joint + axis * best_t), "size": best_r + 0.012}
