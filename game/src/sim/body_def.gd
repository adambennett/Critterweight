class_name BodyDef
extends RefCounted
## Parsed, validated description of a creature's physical body (segments, joints, IK chains,
## weapons, base poses). Authored as JSON (schema: content/schemas/body.schema.json).
##
## All rest-pose coordinates are in FIGHTER SPACE at yaw 0, standing on the floor (y = 0):
##   +Z forward, +Y up, +X = the creature's LEFT. Every segment's rest orientation is identity,
##   and its rigid body origin sits on its joint pivot.

const SHAPE_CAPSULE := 0
const SHAPE_SPHERE := 1
const SHAPE_BOX := 2

const GAITS := ["biped", "avian", "quadruped", "crab", "serpent", "hopper"]


class Shape:
	var type := SHAPE_CAPSULE
	var a := Vector3.ZERO       ## capsule start (segment-local) or sphere/box center
	var b := Vector3.ZERO       ## capsule end (segment-local)
	var radius := 0.05
	var size := Vector3.ONE * 0.1  ## box full size
	## For hit tests: boxes are approximated by a capsule along their longest axis.
	var hit_a := Vector3.ZERO
	var hit_b := Vector3.ZERO
	var hit_r := 0.05


class Seg:
	var id := ""
	var index := 0
	var parent := -1
	var pivot := Vector3.ZERO       ## rest pivot, fighter space
	var shapes: Array = []          ## Array[Shape], segment-local (relative to pivot)
	var mass := 1.0
	var part := "core"              ## head|core|arm|leg|tail|wing|shell|horn|fin
	var hurt_mult := 1.0
	var w0 := 30.0                  ## muscle natural frequency (rad/s)
	var zeta := 1.0                 ## muscle damping ratio
	var strength := 1.0             ## torque cap multiplier
	var guard := false              ## blocks hits while guarding
	var collide := true
	var children: PackedInt32Array = PackedInt32Array()
	var i_eff := 0.1                ## effective inertia of the subtree about the pivot (computed)
	var com_local := Vector3.ZERO   ## centre of mass of own shapes (segment-local)


class Chain:
	var name := ""
	var segs: PackedInt32Array = PackedInt32Array()  ## root-to-tip
	var kind := "limb2"            ## limb2 (two-bone IK) | spine (euler poses) | tail (wave/euler)
	var effector_rest := Vector3.ZERO  ## fighter space, rest
	var effector_local := Vector3.ZERO ## local to last segment
	var pole := Vector3.FORWARD    ## fighter-space bend hint
	var len1 := 0.0
	var len2 := 0.0
	var is_leg := false
	var gait_group := 0
	var foot_home := Vector3.ZERO  ## fighter-space home position of the effector in stance


class Weapon:
	var name := ""
	var seg := 0
	var local := Vector3.ZERO
	var radius := 0.1


class Pose:
	var name := ""
	var chains := {}   ## chain name -> {"target": Vector3, "pole": Vector3 or null}
	var joints := {}   ## segment index -> Quaternion (local, relative to parent)
	var lean := Vector3.ZERO      ## root lean euler degrees (x pitch forward, z roll)
	var height := 0.0             ## root height offset (m)


var id := ""
var display_name := ""
var gait := "biped"
var hover_height := 1.0
var scale := 1.0
var segments: Array = []           ## Array[Seg], parents before children
var seg_index := {}                ## id -> int
var chains := {}                   ## name -> Chain
var leg_chains: Array = []         ## Array[Chain]
var weapons := {}                  ## name -> Weapon
var poses := {}                    ## name -> Pose
var total_mass := 0.0
var height := 1.0                  ## approximate standing height
var stride := 0.45
var step_height := 0.12
var step_time := 0.22
var errors: PackedStringArray = PackedStringArray()


static func from_dict(d: Dictionary, path := "") -> BodyDef:
	var b := BodyDef.new()
	b._parse(d, path)
	return b


static func load_json(path: String) -> BodyDef:
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		var bad := BodyDef.new()
		bad.errors.append("%s: not a JSON object" % path)
		return bad
	return from_dict(parsed, path)


func is_valid() -> bool:
	return errors.is_empty()


func _err(msg: String) -> void:
	errors.append("%s: %s" % [id if id != "" else "<body>", msg])


func _parse(d: Dictionary, path: String) -> void:
	id = str(d.get("id", ""))
	display_name = str(d.get("name", id))
	if id == "":
		errors.append("%s: body is missing 'id'" % path)
	gait = str(d.get("gait", "biped"))
	if not GAITS.has(gait):
		_err("unknown gait '%s' (expected one of %s)" % [gait, ", ".join(GAITS)])
	scale = float(d.get("scale", 1.0))
	hover_height = float(d.get("hover_height", 1.0)) * scale
	stride = float(d.get("stride", 0.45)) * scale
	step_height = float(d.get("step_height", 0.12)) * scale
	step_time = float(d.get("step_time", 0.22))
	var segs: Array = d.get("segments", [])
	if segs.is_empty():
		_err("no segments")
		return
	for sd in segs:
		if typeof(sd) != TYPE_DICTIONARY:
			_err("segment entry is not an object")
			continue
		var s := Seg.new()
		s.id = str(sd.get("id", ""))
		if s.id == "" or seg_index.has(s.id):
			_err("segment id missing or duplicated: '%s'" % s.id)
			continue
		var parent_id = sd.get("parent", null)
		if parent_id == null or str(parent_id) == "":
			if not segments.is_empty():
				_err("segment '%s' has no parent; only the first segment may be the root" % s.id)
				continue
			s.parent = -1
		else:
			if not seg_index.has(str(parent_id)):
				_err("segment '%s' references unknown/later parent '%s' (list parents first)" % [s.id, parent_id])
				continue
			s.parent = seg_index[str(parent_id)]
		s.pivot = MathX.vec3(sd.get("pivot", [0, 0, 0])) * scale
		s.mass = maxf(0.05, float(sd.get("mass", 1.0)))
		s.part = str(sd.get("part", "core"))
		s.hurt_mult = float(sd.get("hurt", 1.0))
		s.w0 = float(sd.get("w0", 30.0))
		s.zeta = float(sd.get("zeta", 1.0))
		s.strength = float(sd.get("strength", 1.0))
		s.guard = bool(sd.get("guard", false))
		s.collide = bool(sd.get("collide", true))
		var shapes_in: Array = sd.get("shapes", [])
		if shapes_in.is_empty() and sd.has("shape"):
			shapes_in = [sd["shape"]]
		if shapes_in.is_empty():
			_err("segment '%s' has no shapes" % s.id)
		for shd in shapes_in:
			var sh := _parse_shape(shd, s.pivot)
			if sh:
				s.shapes.append(sh)
		s.index = segments.size()
		seg_index[s.id] = s.index
		segments.append(s)
		if s.parent >= 0:
			var p: Seg = segments[s.parent]
			p.children.append(s.index)
		total_mass += s.mass
	_compute_inertia()
	_compute_height()
	for cname in d.get("chains", {}):
		_parse_chain(str(cname), d["chains"][cname])
	for wname in d.get("weapons", {}):
		_parse_weapon(str(wname), d["weapons"][wname])
	for pname in d.get("poses", {}):
		poses[str(pname)] = parse_pose(str(pname), d["poses"][pname])
	if not poses.has("stance"):
		_err("missing required pose 'stance'")
	if gait in ["biped", "avian", "quadruped", "crab"] and leg_chains.is_empty():
		_err("gait '%s' needs at least one chain with \"leg\": true" % gait)


func _parse_shape(shd, pivot: Vector3) -> Shape:
	if typeof(shd) != TYPE_DICTIONARY:
		_err("shape is not an object")
		return null
	var sh := Shape.new()
	var t := str(shd.get("type", "capsule"))
	sh.radius = float(shd.get("radius", 0.05)) * scale
	match t:
		"capsule":
			sh.type = SHAPE_CAPSULE
			sh.a = MathX.vec3(shd.get("a", [0, 0, 0])) * scale - pivot
			sh.b = MathX.vec3(shd.get("b", [0, 0, 0])) * scale - pivot
			sh.hit_a = sh.a
			sh.hit_b = sh.b
			sh.hit_r = sh.radius
		"sphere":
			sh.type = SHAPE_SPHERE
			sh.a = MathX.vec3(shd.get("center", [0, 0, 0])) * scale - pivot
			sh.b = sh.a
			sh.hit_a = sh.a
			sh.hit_b = sh.a
			sh.hit_r = sh.radius
		"box":
			sh.type = SHAPE_BOX
			sh.a = MathX.vec3(shd.get("center", [0, 0, 0])) * scale - pivot
			sh.size = MathX.vec3(shd.get("size", [0.1, 0.1, 0.1])) * scale
			var half := sh.size * 0.5
			var axis := 0
			if half.y >= half.x and half.y >= half.z:
				axis = 1
			elif half.z >= half.x and half.z >= half.y:
				axis = 2
			var r := 0.0
			var along := Vector3.ZERO
			match axis:
				0:
					r = sqrt(half.y * half.z)
					along = Vector3(maxf(0.0, half.x - r), 0, 0)
				1:
					r = sqrt(half.x * half.z)
					along = Vector3(0, maxf(0.0, half.y - r), 0)
				2:
					r = sqrt(half.x * half.y)
					along = Vector3(0, 0, maxf(0.0, half.z - r))
			sh.hit_a = sh.a - along
			sh.hit_b = sh.a + along
			sh.hit_r = r
		_:
			_err("unknown shape type '%s'" % t)
			return null
	return sh


func _shape_com(sh: Shape) -> Vector3:
	if sh.type == SHAPE_CAPSULE:
		return (sh.a + sh.b) * 0.5
	return sh.a


func _compute_inertia() -> void:
	# Own centre of mass per segment (shape centroids weighted by rough volume).
	for s: Seg in segments:
		var acc := Vector3.ZERO
		var wsum := 0.0
		for sh: Shape in s.shapes:
			var vol := 0.0
			match sh.type:
				SHAPE_CAPSULE:
					vol = PI * sh.radius * sh.radius * (sh.a.distance_to(sh.b) + sh.radius * 4.0 / 3.0)
				SHAPE_SPHERE:
					vol = 4.0 / 3.0 * PI * pow(sh.radius, 3)
				SHAPE_BOX:
					vol = sh.size.x * sh.size.y * sh.size.z
			acc += _shape_com(sh) * vol
			wsum += vol
		s.com_local = acc / wsum if wsum > 0.0 else Vector3.ZERO
	# Effective inertia of each subtree about its pivot (perpendicular axis approximation).
	for idx in range(segments.size() - 1, -1, -1):
		var s: Seg = segments[idx]
		s.i_eff = _subtree_inertia(idx, s.pivot)


func _subtree_inertia(idx: int, about: Vector3) -> float:
	var s: Seg = segments[idx]
	var com_world := s.pivot + s.com_local
	var ext := 0.05
	for sh: Shape in s.shapes:
		ext = maxf(ext, sh.radius)
		if sh.type == SHAPE_CAPSULE:
			ext = maxf(ext, sh.a.distance_to(sh.b) * 0.5)
	var own := s.mass * (com_world.distance_squared_to(about) + 0.25 * ext * ext)
	for c in s.children:
		own += _subtree_inertia(c, about)
	return own


func _compute_height() -> void:
	var top := 0.0
	for s: Seg in segments:
		for sh: Shape in s.shapes:
			top = maxf(top, s.pivot.y + maxf(sh.a.y, sh.b.y) + sh.radius)
	height = top


func _parse_chain(cname: String, cd) -> void:
	if typeof(cd) != TYPE_DICTIONARY:
		_err("chain '%s' is not an object" % cname)
		return
	var c := Chain.new()
	c.name = cname
	c.kind = str(cd.get("kind", "limb2"))
	for sid in cd.get("segments", []):
		if not seg_index.has(str(sid)):
			_err("chain '%s' references unknown segment '%s'" % [cname, sid])
			return
		c.segs.append(seg_index[str(sid)])
	if c.segs.is_empty():
		_err("chain '%s' has no segments" % cname)
		return
	c.pole = MathX.vec3(cd.get("pole", [0, 0, 1]), Vector3.FORWARD).normalized()
	c.is_leg = bool(cd.get("leg", false))
	c.gait_group = int(cd.get("group", 0))
	if c.kind == "limb2":
		if c.segs.size() != 2:
			_err("limb2 chain '%s' needs exactly 2 segments" % cname)
			return
		c.effector_rest = MathX.vec3(cd.get("effector", [0, 0, 0])) * scale
		var s0: Seg = segments[c.segs[0]]
		var s1: Seg = segments[c.segs[1]]
		if s1.parent != c.segs[0]:
			_err("chain '%s': second segment must be the child of the first" % cname)
			return
		c.len1 = s0.pivot.distance_to(s1.pivot)
		c.len2 = s1.pivot.distance_to(c.effector_rest)
		c.effector_local = c.effector_rest - s1.pivot
		if c.len1 < 0.01 or c.len2 < 0.01:
			_err("chain '%s' has degenerate bone lengths" % cname)
		if not cd.has("pole"):
			# Default bend hint = the direction the rest elbow/knee already bends toward, so the
			# IK reproduces the rest pose exactly (no muscle torque at rest). An authored pole must
			# contain the rest bend for the same reason (docs/CREATURES.md "poles").
			var axis := (c.effector_rest - s0.pivot).normalized()
			var mid := s1.pivot - s0.pivot
			var perp := mid - axis * mid.dot(axis)
			if perp.length() > 0.005:
				c.pole = perp.normalized()
		c.foot_home = MathX.vec3(cd.get("home", [c.effector_rest.x, c.effector_rest.y, c.effector_rest.z])) * scale
	chains[cname] = c
	if c.is_leg:
		leg_chains.append(c)


func _parse_weapon(wname: String, wd) -> void:
	if typeof(wd) != TYPE_DICTIONARY:
		_err("weapon '%s' is not an object" % wname)
		return
	var sid := str(wd.get("segment", ""))
	if not seg_index.has(sid):
		_err("weapon '%s' references unknown segment '%s'" % [wname, sid])
		return
	var w := Weapon.new()
	w.name = wname
	w.seg = seg_index[sid]
	var s: Seg = segments[w.seg]
	w.local = MathX.vec3(wd.get("point", [0, 0, 0])) * scale - s.pivot
	w.radius = float(wd.get("radius", 0.1)) * scale
	weapons[wname] = w


## Parses a pose (also used by moves for keyframes). Unknown names are reported as errors.
func parse_pose(pname: String, pd) -> Pose:
	var p := Pose.new()
	p.name = pname
	if typeof(pd) != TYPE_DICTIONARY:
		_err("pose '%s' is not an object" % pname)
		return p
	var cd: Dictionary = pd.get("chains", {})
	for cname in cd:
		if not chains.has(str(cname)):
			_err("pose '%s' references unknown chain '%s'" % [pname, cname])
			continue
		var entry = cd[cname]
		var target := Vector3.ZERO
		var pole = null
		if typeof(entry) == TYPE_ARRAY:
			target = MathX.vec3(entry) * scale
		elif typeof(entry) == TYPE_DICTIONARY:
			target = MathX.vec3(entry.get("target", [0, 0, 0])) * scale
			if entry.has("pole"):
				pole = MathX.vec3(entry["pole"]).normalized()
		p.chains[str(cname)] = {"target": target, "pole": pole}
	var jd: Dictionary = pd.get("joints", {})
	for sid in jd:
		if not seg_index.has(str(sid)):
			_err("pose '%s' references unknown segment '%s'" % [pname, sid])
			continue
		p.joints[seg_index[str(sid)]] = MathX.euler_deg(MathX.vec3(jd[sid]))
	p.lean = MathX.vec3(pd.get("lean", [0, 0, 0]))
	p.height = float(pd.get("height", 0.0)) * scale
	return p


func seg(id_: String) -> Seg:
	return segments[seg_index[id_]] if seg_index.has(id_) else null
