class_name ArenaDef
extends RefCounted
## Data description of a playable arena: a supported base (cage/ring/platform), its playable
## boundary, props/obstacles/hazards placed on it, spawn points and mode markers.
## Authored layouts (arena editor) and built-in arenas share this format
## (schema: content/schemas/arena.schema.json).

const BASES := ["octagon", "square", "circle", "platform"]

var id := ""
var display_name := ""
var base := "octagon"
var radius := 5.0              ## apothem (octagon/square half-size) or radius (circle/platform)
var wall_height := 2.4         ## 0 = open edges (ring-outs possible)
var ringout := false
var theme := "can"
var spawns: Array = []         ## [Vector3(x, 0, z) with .y unused, yaw radians] -> stored as [Vector3, float]
var props: Array = []          ## [{type, pos: Vector3, yaw: float, scale: float}]
var hazards: Array = []        ## [{type, pos: Vector3, radius: float, params}]
var markers := {}              ## name -> Array[Vector3]
var gravity_mult := 1.0
var author := ""
var version := 1
var errors: PackedStringArray = PackedStringArray()
var source := ""


static func from_dict(d: Dictionary, src := "") -> ArenaDef:
	var a := ArenaDef.new()
	a.source = src
	a.id = str(d.get("id", ""))
	a.display_name = str(d.get("name", a.id))
	a.base = str(d.get("base", "octagon"))
	if not BASES.has(a.base):
		a.errors.append("unknown arena base '%s'" % a.base)
	a.radius = clampf(float(d.get("radius", 5.0)), 2.5, 12.0)
	a.wall_height = float(d.get("wall_height", 2.4 if a.base != "platform" else 0.0))
	a.ringout = bool(d.get("ringout", a.wall_height <= 0.01))
	a.theme = str(d.get("theme", "can"))
	a.gravity_mult = float(d.get("gravity_mult", 1.0))
	a.author = str(d.get("author", ""))
	a.version = int(d.get("version", 1))
	for s in d.get("spawns", []):
		if typeof(s) == TYPE_ARRAY and s.size() >= 2:
			a.spawns.append([Vector3(float(s[0]), 0.0, float(s[1])), deg_to_rad(float(s[2])) if s.size() > 2 else NAN])
	for p in d.get("props", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		a.props.append({"type": str(p.get("type", "")), "pos": MathX.vec3(p.get("pos", [0, 0, 0])),
			"yaw": deg_to_rad(float(p.get("yaw", 0.0))), "scale": float(p.get("scale", 1.0))})
	for h in d.get("hazards", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		a.hazards.append({"type": str(h.get("type", "")), "pos": MathX.vec3(h.get("pos", [0, 0, 0])),
			"radius": float(h.get("radius", 1.0)), "params": h.get("params", {})})
	var md: Dictionary = d.get("markers", {})
	for k in md:
		var pts := []
		for m in md[k]:
			if typeof(m) == TYPE_ARRAY and m.size() >= 2:
				pts.append(Vector3(float(m[0]), float(m[2]) if m.size() > 2 else 0.0, float(m[1])))
		a.markers[str(k)] = pts
	if a.id == "":
		a.errors.append("arena without id")
	return a


func to_dict() -> Dictionary:
	var sp := []
	for s in spawns:
		var v: Vector3 = s[0]
		sp.append([snappedf(v.x, 0.01), snappedf(v.z, 0.01), snappedf(rad_to_deg(s[1]), 0.1) if not is_nan(s[1]) else 0.0])
	var pr := []
	for p in props:
		var v2: Vector3 = p["pos"]
		pr.append({"type": p["type"], "pos": [snappedf(v2.x, 0.01), snappedf(v2.y, 0.01), snappedf(v2.z, 0.01)], "yaw": snappedf(rad_to_deg(p["yaw"]), 0.1), "scale": p["scale"]})
	var hz := []
	for h in hazards:
		var v3: Vector3 = h["pos"]
		hz.append({"type": h["type"], "pos": [snappedf(v3.x, 0.01), 0.0, snappedf(v3.z, 0.01)], "radius": h["radius"], "params": h["params"]})
	var mk := {}
	for k in markers:
		var arr := []
		for v4: Vector3 in markers[k]:
			arr.append([snappedf(v4.x, 0.01), snappedf(v4.z, 0.01)])
		mk[k] = arr
	return {"id": id, "name": display_name, "base": base, "radius": radius, "wall_height": wall_height,
		"ringout": ringout, "theme": theme, "gravity_mult": gravity_mult, "author": author, "version": version,
		"spawns": sp, "props": pr, "hazards": hz, "markers": mk}


## Point clamped inside the playable boundary with a margin (horizontal only).
func clamp_point(p: Vector3, margin: float) -> Vector3:
	var lim := radius - margin
	match base:
		"square":
			return Vector3(clampf(p.x, -lim, lim), p.y, clampf(p.z, -lim, lim))
		"octagon":
			var q := p
			for i in 8:
				var a := TAU * i / 8.0
				var n := Vector3(cos(a), 0.0, sin(a))
				var d := q.dot(n)
				if d > lim:
					q -= n * (d - lim)
			return q
		_:
			var h := Vector2(p.x, p.z)
			if h.length() > lim:
				h = h.normalized() * lim
			return Vector3(h.x, p.y, h.y)


func inside(p: Vector3, margin := 0.0) -> bool:
	return clamp_point(p, margin).distance_squared_to(p) < 1e-6


## Default spawn ring when an arena does not define enough spawns.
func spawn_point(i: int, count: int) -> Array:
	if i < spawns.size():
		var s: Array = spawns[i]
		var yaw: float = s[1]
		if is_nan(yaw):
			yaw = atan2(-s[0].x, -s[0].z)
		return [s[0], yaw]
	var r := radius * 0.55
	var a := TAU * float(i) / float(maxi(count, 2)) + PI * 0.5
	var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
	return [p, atan2(-p.x, -p.z)]
