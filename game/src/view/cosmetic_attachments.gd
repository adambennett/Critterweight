class_name CosmeticAttachments
extends RefCounted
## View-only fighter cosmetics (docs/HUB_SYSTEMS.md §16): the Cannery's gold tooth (gag piece),
## trash-can lid (idle prop), replica belt (walkout back piece) and rooftop scarf (neckwear) as small
## meshes that ride a body segment. CreatureView owns the nodes and moves them with the segment
## every frame; they have no collision, no physics and the simulation never sees them.
##
## Anchors are fitted to what you SEE: for forged models CreatureView hands in the model's own
## vertices per segment (segment-local rest positions), so rings hug the skin and the lid sits on
## the forearm's outer side; fallback (segment-primitive) bodies use their body shapes. Works for
## every body plan (biped, avian, crab, quadruped, serpent, hopper). A creature can override one with
## art.attach.<kind> = {segment, offset: [x,y,z], rotation_deg: [x,y,z], size}. Coordinates are
## SEGMENT-LOCAL (rest orientation is identity: +Z forward, +Y up, +X the creature's left).
##   tooth: the front of the lower face on its middle line (the mouth), hanging down; a head with
##          nothing on its middle line (eye stalks) wears it on the body below them. Also the gag piece.
##          A scarf that would run across the mouth dips under the chin instead.
##   lid:   on the outer side of the distal LEFT arm/wing, facing out; armless bodies wear it on the
##          back (upright bodies) or on top (quadrupeds, crabs)
##   belt:  a sash over the shoulder around the torso under the head; a girth strap round horizontal
##          bodies; a waist belt low on a hopper (all face up top)
##   scarf: an (elliptical) ring at the narrowest part between head and body, tails trailing behind
## Rings are fitted ellipses: `radii` = their half extents along the ring's own x and z axes.

const KINDS := ["tooth", "lid", "belt", "scarf"]
## Pieces put away while the round is live (shown in the hub, on the walkout and when celebrating).
const WALKOUT_ONLY := ["lid", "belt"]
const BELT_TILT_DEG := 38.0
## |x| of the vertices that count as the middle line of a face (the mouth is on it, eyes are not).
const MIDLINE := 0.035


## {seg: int, xf: Transform3D (segment-local; basis = the piece's orientation), size: float,
##  radii: Vector2 (rings: half extents along the oriented x and z; else size, size)} or {}.
## `points`: segment index -> PackedVector3Array of the model's vertices (segment-local), or {}.
static func anchor(c: CreatureDef, kind: String, points := {}) -> Dictionary:
	var body: BodyDef = c.body
	var over: Dictionary = (c.art.get("attach", {}) as Dictionary).get(kind, {})
	if not over.is_empty() and body.seg_index.has(str(over.get("segment", ""))):
		var si: int = body.seg_index[str(over["segment"])]
		var rot: Vector3 = MathX.vec3(over.get("rotation_deg", [0, 0, 0])) * (PI / 180.0)
		var sz := float(over.get("size", 0.2))
		return {"seg": si, "xf": Transform3D(Basis.from_euler(rot), MathX.vec3(over.get("offset", [0, 0, 0]))), "size": sz, "radii": Vector2(sz, sz)}
	var out := {}
	match kind:
		"tooth":
			out = _mouth(body, points)
		"lid":
			out = _arm_anchor(body, points)
			if out.is_empty():
				out = _back_anchor(body, points)
		"belt":
			out = _belt_anchor(body, points)
		"scarf":
			out = _neck_anchor(body, points)
	if not out.is_empty() and not out.has("radii"):
		out["radii"] = Vector2(float(out["size"]), float(out["size"]))
	return out


## The node tree for one attachment (unparented; the caller places it at the anchor's origin in
## segment space). `orient` turns the piece (disc/ring axis); scarf tails always hang down from the
## back of the ring. `style`: {color, accent} from the cosmetic's data. `radii`: a ring's half
## extents (x, z) in its own plane (zero = round, `size`).
static func build(kind: String, style: Dictionary, size: float, orient := Basis.IDENTITY, radii := Vector2.ZERO) -> Node3D:
	var top := Node3D.new()
	top.name = "Cosmetic_" + kind
	var root := Node3D.new()
	root.name = "Oriented"
	root.basis = orient
	top.add_child(root)
	var col := Color.from_string(str(style.get("color", "#E8B923")), Color(0.9, 0.72, 0.15))
	var acc := Color.from_string(str(style.get("accent", "#F7E7A1")), col.lightened(0.4))
	var rr := radii if radii.x > 0.0 and radii.y > 0.0 else Vector2(size, size)
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
			_mesh(root, ellipse_ring(rr.x, rr.y, 0.026), _mat(col, 0.7, 0.0), Transform3D.IDENTITY)
			var plate := BoxMesh.new()
			var pw := clampf(size * 0.62, 0.12, 0.26)
			plate.size = Vector3(pw, pw * 0.68, 0.035)
			var gold := _mat(acc, 0.25, 0.85, Color(acc.r, acc.g, acc.b) * 0.2)
			_mesh(root, plate, gold, Transform3D(Basis.IDENTITY, Vector3(0, 0, rr.y + 0.035)))
			var gem := SphereMesh.new()
			gem.radius = pw * 0.15
			gem.height = pw * 0.3
			_mesh(root, gem, _mat(Color("#C8322E"), 0.15, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, 0, rr.y + 0.06)))
			for side in [-1.0, 1.0]:
				var side_plate := BoxMesh.new()
				side_plate.size = Vector3(pw * 0.45, pw * 0.45, 0.03)
				var at := _ellipse_point(rr, float(side) * 0.55, 0.03)
				_mesh(root, side_plate, gold, Transform3D(Basis(Vector3.UP, atan2(at.x, at.z)), at))
			# the back of the sash too (seen from the follow camera behind you)
			var back_plate := BoxMesh.new()
			back_plate.size = Vector3(pw * 0.5, pw * 0.4, 0.03)
			_mesh(root, back_plate, gold, Transform3D(Basis.IDENTITY, Vector3(0, 0, -(rr.y + 0.03))))
		"scarf":
			var th := scarf_tube(size)
			var cloth := _mat(col, 0.9, 0.0)
			_mesh(root, ellipse_ring(rr.x + th * 0.4, rr.y + th * 0.4, th), cloth, Transform3D.IDENTITY)
			# the tails hang from the back of the ring (the point furthest back and up, whatever way
			# the ring is turned)
			var back := Vector3.ZERO
			var best := -INF
			for k in 24:
				var p := orient * _ellipse_point(rr, TAU * float(k) / 24.0, th)
				if p.y * 0.5 - p.z > best:
					best = p.y * 0.5 - p.z
					back = p
			for k in 2:
				var tail := BoxMesh.new()
				tail.size = Vector3(clampf(size * 0.42, 0.06, 0.12), clampf(size * 1.6, 0.18, 0.34), 0.03)
				var tilt := Basis(Vector3.RIGHT, 0.35 + 0.25 * k) * Basis(Vector3.FORWARD, (k - 0.5) * 0.5)
				_mesh(top, tail, cloth if k == 0 else _mat(acc, 0.9, 0.0), Transform3D(tilt, back + Vector3((k - 0.5) * size * 0.45, -tail.size.y * 0.42, -0.01)))
	return top


## A point on the ellipse (half extents r.x, r.y in the x/z plane) at angle `a` from its front (+Z),
## pushed `out` further along the outline's normal.
static func _ellipse_point(r: Vector2, a: float, out := 0.0) -> Vector3:
	var p := Vector3(r.x * sin(a), 0.0, r.y * cos(a))
	var n := Vector3(r.y * sin(a), 0.0, r.x * cos(a)).normalized()
	return p + n * out


## An elliptical tube ring in the x/z plane (round tube of radius `tube` around the ellipse with half
## extents rx, rz) — a torus that can hug an oval body.
static func ellipse_ring(rx: float, rz: float, tube: float, segs := 36, sides := 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		var c := Vector3(rx * sin(a), 0.0, rz * cos(a))
		var n := Vector3(rz * sin(a), 0.0, rx * cos(a)).normalized()
		for j in sides + 1:
			var b := TAU * float(j) / float(sides)
			var d := n * cos(b) + Vector3.UP * sin(b)
			st.set_normal(d)
			st.set_uv(Vector2(float(i) / float(segs), float(j) / float(sides)))
			st.add_vertex(c + d * tube)
	for i in segs:
		for j in sides:
			var a0 := i * (sides + 1) + j
			var b0 := (i + 1) * (sides + 1) + j
			st.add_index(a0)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(b0 + 1)
	return st.commit()


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


## The body's outline where the plane through `c` (normal = basis.y) cuts it, seen from `c`: the
## furthest point of the slab (points within `slab` of the plane) in each of 16 directions, then
## the in-plane bounding box (along basis.x and basis.z) of those, directions that stick out further
## than 1.5x the median dropped (a snout, a beak, a jaw). Independent of how densely the model is
## meshed. {center: Vector3, rx, rz, n} or {} when fewer than `min_count` points are in the slab or
## the cut doesn't go round `c` (a stub, two separate stalks).
static func _ring_fit(p: PackedVector3Array, c: Vector3, basis: Basis, slab: float, min_count: int) -> Dictionary:
	const BINS := 16
	const MIN_BINS := 11
	var n := basis.y.normalized()
	var bx := basis.x.normalized()
	var bz := basis.z.normalized()
	var far: Array[float] = []
	far.resize(BINS)
	far.fill(-1.0)
	var dirs: Array[Vector2] = []
	dirs.resize(BINS)
	var count := 0
	for v in p:
		var d := v - c
		if absf(d.dot(n)) > slab:
			continue
		var q := Vector2(d.dot(bx), d.dot(bz))
		var b := int(floor((q.angle() + PI) / TAU * float(BINS))) % BINS
		count += 1
		if q.length() > far[b]:
			far[b] = q.length()
			dirs[b] = q
	if count < maxi(min_count, 3):
		return {}
	var filled: Array[float] = []
	for r in far:
		if r >= 0.0:
			filled.append(r)
	if filled.size() < MIN_BINS:
		return {}
	filled.sort()
	var cap := filled[filled.size() / 2] * 1.5 + 0.01
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for b in BINS:
		if far[b] >= 0.0 and far[b] <= cap:
			lo = lo.min(dirs[b])
			hi = hi.max(dirs[b])
	var ctr := (lo + hi) * 0.5
	return {"center": c + bx * ctr.x + bz * ctr.y, "rx": (hi.x - lo.x) * 0.5, "rz": (hi.y - lo.y) * 0.5, "n": count}


## A ring anchor from a fit: slightly loose so it sits on the skin, not in it.
static func _ring_anchor(seg: int, basis: Basis, f: Dictionary, margin: float) -> Dictionary:
	var radii := Vector2(maxf(float(f["rx"]), 0.05) + margin, maxf(float(f["rz"]), 0.05) + margin)
	return {"seg": seg, "xf": Transform3D(basis, f["center"] as Vector3), "size": (radii.x + radii.y) * 0.5, "radii": radii}


# ---- anchors ------------------------------------------------------------------------------------

## The front of a face between two heights: the point furthest forward, counting distance from the
## middle line against it (eyes and cheeks either side lose to a mouth on the middle), or z = -INF.
static func _front_midline(p: PackedVector3Array, y_max: float, y_min := -INF) -> Vector3:
	var front := Vector3(0, 0, -INF)
	var best := -INF
	for v in p:
		if v.y <= y_max and v.y >= y_min and v.z - 2.0 * absf(v.x) > best:
			best = v.z - 2.0 * absf(v.x)
			front = v
	return front


static func _has_midline(p: PackedVector3Array, y_max: float) -> bool:
	var n := 0
	for v in p:
		if absf(v.x) <= MIDLINE and v.y <= y_max:
			n += 1
	return n >= 3


static func _mouth(body: BodyDef, points: Dictionary) -> Dictionary:
	var s := _head(body)
	if s == null:
		s = _core(body)
	var p := _pts(s, points)
	if p.is_empty():
		return {}
	var box := _aabb(p)
	var size := clampf(box.size.y * 0.1, 0.022, 0.05)
	# the front of the lower face, on its middle line (a head's lower third: under a snout or a nose;
	# a body that is all face (a hopper): its lower half)
	var low := box.position.y + box.size.y * (0.35 if s.part == "head" else 0.55)
	var front := _front_midline(p, low)
	var seg := s
	if s.parent >= 0 and not _has_midline(p, low):
		# nothing on the middle line (Dredge's eye stalks): the mouth is on the body below them
		var parent: BodyDef.Seg = body.segments[s.parent]
		var joint := s.pivot - parent.pivot
		front = _front_midline(_pts(parent, points), joint.y + 0.02, joint.y - 0.35)
		seg = parent
	if front.z == -INF:
		return {}
	return {"seg": seg.index, "xf": Transform3D(Basis.IDENTITY, front + Vector3(size * 0.6, size * 0.4, -size * 0.25)), "size": size}


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
	# horizontal body (quadruped, crab) a girth strap around the chest with the plate on top; a hopper
	# is all face up top, so a waist belt low around its body
	var basis := Basis(Vector3.FORWARD, deg_to_rad(BELT_TILT_DEG))
	if body.gait in ["quadruped", "crab"]:
		basis = Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.FORWARD, deg_to_rad(12.0))
	elif _head(body) == null:
		basis = Basis.IDENTITY
		c.y = box.position.y + box.size.y * 0.2
	var f := _ring_fit(p, c, basis, maxf(0.04, box.size.y * 0.08), 6)
	if f.is_empty():
		var r := maxf(box.size.x, box.size.z) * 0.5
		f = {"center": c, "rx": r, "rz": r, "n": 0}
	return _ring_anchor(s.index, basis, f, 0.02)


static func _neck_anchor(body: BodyDef, points: Dictionary) -> Dictionary:
	var head := _head(body)
	if head == null or head.parent < 0:
		# no neck (hoppers): a band round the top of the body, above the face
		var core := _core(body)
		var cp := _pts(core, points)
		if cp.is_empty():
			return {}
		var box := _aabb(cp)
		var top := Vector3(box.position.x + box.size.x * 0.5, box.position.y + box.size.y * 0.78, box.position.z + box.size.z * 0.5)
		var tf := _ring_fit(cp, top, Basis.IDENTITY, 0.025, 6)
		if tf.is_empty():
			return {}
		return _ring_anchor(core.index, Basis.IDENTITY, tf, 0.015)
	var parent: BodyDef.Seg = body.segments[head.parent]
	var joint := head.pivot - parent.pivot              # the neck, in the parent's local space
	var hp := PackedVector3Array()
	for v in _pts(head, points):
		hp.append(v + joint)
	# a head on a neck (Gusto, Slurry, Dozer) vs a head sitting on the body itself (Stoke, Dredge's
	# eye stalks, the dev biped)
	var on_body := parent == _core(body) or parent.parent < 0
	# the neck's direction: parent pivot -> head pivot; a head on the body that grows away from that
	# line (eye stalks standing up off a crab's front) goes by its own bulk
	var axis := joint.normalized() if joint.length() > 0.02 else Vector3.UP
	if on_body:
		var cen := _centroid(hp)
		if cen.distance_to(joint) > 0.05 and axis.angle_to((cen - joint).normalized()) > deg_to_rad(35.0):
			axis = (cen - joint).normalized()
	var basis := Basis(MathX.rotation_between(Vector3.UP, axis))
	# the head's lowest part along it (1st percentile: a stray vertex doesn't count)
	var ts: Array[float] = []
	for v in hp:
		ts.append((v - joint).dot(axis))
	ts.sort()
	var lo := ts[int(ts.size() * 0.01)] if not ts.is_empty() else 0.0
	var best := {}
	if on_body:
		# round the base of the head, just above where it meets the body
		best = _ring_fit(hp, joint + axis * (lo + 0.03), basis, 0.035, 6)
	if best.is_empty():
		# the narrowest cut through head + neck from 18 cm below the head up to just into it, among the
		# well-filled ones (a cut through the end of a segment is a stub): where a scarf gets tied
		var both := hp.duplicate()
		both.append_array(_pts(parent, points))
		var fits: Array[Dictionary] = []
		var counts: Array[int] = []
		var t := lo - 0.18
		while t <= lo + 0.03 + 0.0001:
			var f := _ring_fit(both, joint + axis * t, basis, 0.02, 6)
			if not f.is_empty():
				f["t"] = t
				fits.append(f)
				counts.append(int(f["n"]))
			t += 0.015
		if fits.is_empty():
			return {"seg": parent.index, "xf": Transform3D(basis, joint), "size": 0.1, "radii": Vector2(0.1, 0.1)}
		counts.sort()
		var need := maxi(8, int(counts[counts.size() / 2] * 0.25))
		var best_m := INF
		for f in fits:
			if int(f["n"]) >= need:
				best_m = minf(best_m, (float(f["rx"]) + float(f["rz"])) * 0.5)
		best = fits[0]
		for f in fits:
			# ties (within 6 mm) go to the cut closest to the head
			if int(f["n"]) >= need and (float(f["rx"]) + float(f["rz"])) * 0.5 <= best_m + 0.006:
				best = f
	return _clear_mouth(body, points, head, parent, _ring_anchor(parent.index, basis, best, 0.012))


## A scarf whose front would run across the mouth (a face low on the head, like Stoke's) is tipped
## forward about the back of the ring: it dips under the chin, the back stays where it was, and the
## mouth and the gold tooth stay in view.
static func _clear_mouth(body: BodyDef, points: Dictionary, head: BodyDef.Seg, parent: BodyDef.Seg, anc: Dictionary) -> Dictionary:
	var m := _mouth(body, points)
	if m.is_empty():
		return anc
	var mp: Vector3 = (m["xf"] as Transform3D).origin
	if int(m["seg"]) == head.index:
		mp += head.pivot - parent.pivot
	elif int(m["seg"]) != parent.index:
		return anc
	var tooth_tip := mp - Vector3(0, float(m["size"]) * 1.3, 0)
	var xf: Transform3D = anc["xf"]
	var r: Vector2 = anc["radii"]
	var axis := xf.basis.y.normalized()
	var fwd := xf.basis.z.normalized()
	var front := xf.origin + fwd * r.y
	var tube := scarf_tube(float(anc["size"]))
	var drop := (front - tooth_tip).dot(axis) + tube + 0.02
	if drop <= 0.0 or (mp - xf.origin).dot(fwd) < r.y * 0.3 or (front - mp).dot(axis) > tube + 0.05:
		return anc   # already under the mouth, the mouth isn't in front of the ring, or it's well above it
	var back := xf.origin - fwd * r.y
	var rot := Basis(xf.basis.x.normalized(), asin(clampf(drop / (2.0 * r.y), 0.0, 0.5)))
	var out := anc.duplicate()
	out["xf"] = Transform3D(rot * xf.basis, back + rot * (xf.origin - back))
	return out


## The scarf's tube radius for a ring of mean radius `size`.
static func scarf_tube(size: float) -> float:
	return clampf(size * 0.18, 0.025, 0.04)
