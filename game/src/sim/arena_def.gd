class_name ArenaDef
extends RefCounted
## Data description of a playable arena: a supported BASE (The Gullet, Drydock, The Crusher,
## The Rooftop, or a mod base), its playable boundary (within the base's allowed range), the
## base's built-in props/hazards (minus any the layout removed), the layout's own props, and
## spawn points / mode markers. Authored layouts (arena editor) and built-in arenas share this
## format (schema: content/schemas/arena.schema.json, docs/ARENAS_AND_EDITOR.md).
##
## Format 2 (bases): {"base": "<base id>", "variant", "size": [w, d], "modes": [], "flags": {},
##   "removed_builtins": [], "props": [{type, pos, yaw, pos2?, params?}], "markers": {name: [...]}}
## Format 1 (legacy shapes, still accepted): {"base": octagon|square|circle|platform, "radius",
##   "wall_height", "spawns": [[x, z, yaw]], "props", "hazards", "markers"}.
##
## Geometry: the floor is a union of convex pieces (XZ plane, metres). Boundary edges are walls
## (solid) or open (ring-out edges). `inside()` answers "is this point clear of every WALL by
## `margin`" (open edges never block, so splats/slams only happen against real walls), while
## `on_floor()` / `clamp_point()` answer geometric floor containment.
## Units: metres, yaw in radians at runtime (degrees in JSON). Yaw 0 faces +Z.

const BASES := ["octagon", "square", "circle", "platform"]   ## legacy shape bases
const LEGACY_THEME_STYLE := {"can": "gullet", "rooftop": "rooftop", "scrapyard": "crusher", "sewer": "drydock"}
## Format-1 free-form prop names mapped onto the catalog at parse time.
const LEGACY_PROPS := {"crate": "prop_crate", "barrel": "prop_brine_barrel", "pillar": "prop_bollard", "low_wall": "prop_sponsor_board",
	"bumper": "prop_bumper", "tire_stack": "prop_tire_stack", "turnbuckle": "prop_bollard", "bench": "prop_crate"}
const FORMAT := 2
const RINGOUT_DEFAULTS := {"damage_frac": 0.08, "out_time": 2.5, "invuln": 1.0, "fall_y": -1.2}

var id := ""
var display_name := ""
var base := "octagon"          ## base id (gullet/drydock/crusher/rooftop/mod base) or legacy shape
var base_def := {}             ## resolved, normalized base definition ({} for legacy shapes)
var defines_base := false      ## this entry carries its own base_def (the four base arenas)
var variant := ""
var shape := "octagon"         ## octagon | rect | notched_rect | circle
var style := "gullet"          ## visual style (ArenaView builder)
var size := Vector2(10, 10)    ## octagon: flat-to-flat; circle: diameter; rects: width (x) × depth (z)
var notch := Vector2.ZERO      ## notched_rect corner notch size
var radius := 5.0              ## apothem (octagon/square half-size) or radius (circle/platform); half max extent for rects
var wall_height := 2.4         ## 0 = open edges (ring-outs possible)
var ringout := false
var theme := "can"
var description := ""
var modes: Array = []          ## supported mode ids (duel, ffa, teams, coop, spotlight_hog, chumball, absolute_unit, chum_rush, boss)
var flags := {}                ## layout flags, e.g. {"electrified_plates": false}
var removed_builtins: Array = []
var builtins: Array = []       ## resolved built-in props (same shape as props, "builtin": true)
var spawns: Array = []         ## individual spawns: [Vector3(x, 0, z), yaw radians or NAN]
var props: Array = []          ## layout props: {type, pos: Vector3, yaw, scale, pos2?, params, id, uid?}
var hazards: Array = []        ## legacy hazard zones: [{type, pos: Vector3, radius: float, params}]
var markers := {}              ## name -> Array[Vector3] (positions; see markers_of() for full entries)
var marker_entries := {}       ## name -> Array[Dictionary] {pos: Vector3, yaw: float, team: int, size: Vector3, uid?}
var gravity_mult := 1.0
var author := ""
var version := 1
var format := 1
var errors: PackedStringArray = PackedStringArray()
var source := ""

var _pieces: Array = []        ## Array[PackedVector2Array]: convex floor pieces (XZ)
var _boundary := PackedVector2Array()   ## outer boundary polygon (XZ)
var _edges: Array = []         ## [{a: Vector2, b: Vector2, n: Vector2 outward, wall: bool, side: String}]


# =====================================================================================
# Parsing
# =====================================================================================

static func from_dict(d: Dictionary, src := "") -> ArenaDef:
	var a := ArenaDef.new()
	a.source = src
	a.id = str(d.get("id", ""))
	a.display_name = str(d.get("name", a.id))
	a.base = str(d.get("base", "octagon"))
	a.description = str(d.get("description", ""))
	a.author = str(d.get("author", ""))
	a.version = int(d.get("version", 1))
	a.gravity_mult = float(d.get("gravity_mult", 1.0))
	a.theme = str(d.get("theme", "can"))
	a.format = int(d.get("format", 1 if BASES.has(a.base) else FORMAT))
	for m in d.get("modes", []):
		a.modes.append(str(m).trim_prefix("mode_"))
	var fl = d.get("flags", {})
	if typeof(fl) == TYPE_DICTIONARY:
		a.flags = (fl as Dictionary).duplicate(true)
	for r in d.get("removed_builtins", []):
		a.removed_builtins.append(str(r))
	if BASES.has(a.base):
		a._setup_legacy(d)
	else:
		var bd = d.get("base_def", null)
		if typeof(bd) == TYPE_DICTIONARY:
			a.base_def = ArenaCatalog.normalize_base(bd, a.base)
			a.defines_base = true
		else:
			a.base_def = ArenaCatalog.base(a.base)
		if a.base_def.is_empty():
			a.errors.append("unknown arena base '%s'" % a.base)
			a._setup_legacy({"base": "octagon", "radius": 5.0})
		else:
			a._setup_base(d)
	# legacy spawns array (format 1); format 2 spawns come from markers below
	for s in d.get("spawns", []):
		if typeof(s) == TYPE_ARRAY and s.size() >= 2:
			a.spawns.append([Vector3(float(s[0]), 0.0, float(s[1])), deg_to_rad(float(s[2])) if s.size() > 2 else NAN])
	var pidx := 0
	for p in d.get("props", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		a.props.append(_parse_prop(p, "p%d" % pidx))
		pidx += 1
	for h in d.get("hazards", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		a.hazards.append({"type": str(h.get("type", "")), "pos": MathX.vec3(h.get("pos", [0, 0, 0])),
			"radius": float(h.get("radius", 1.0)), "params": h.get("params", {})})
	var md = d.get("markers", {})
	if typeof(md) == TYPE_DICTIONARY:
		for k in md:
			var key := str(k).trim_prefix("marker_")
			var pts := []
			var entries := []
			if typeof(md[k]) != TYPE_ARRAY:
				continue
			for m in md[k]:
				# accepted forms: [x, z] | [x, z, y] | {"pos": [x, y, z], "yaw": deg, "team": n, "size": [w, h, d]}
				if typeof(m) == TYPE_ARRAY and m.size() >= 2:
					var p3 := Vector3(float(m[0]), float(m[2]) if m.size() > 2 else 0.0, float(m[1]))
					pts.append(p3)
					entries.append({"pos": p3, "yaw": 0.0, "team": -1, "size": Vector3.ZERO})
				elif typeof(m) == TYPE_DICTIONARY:
					var p4 := MathX.vec3(m.get("pos", [0, 0, 0]))
					pts.append(p4)
					var me := {"pos": p4, "yaw": deg_to_rad(float(m.get("yaw", 0.0))), "team": int(m.get("team", -1)), "size": MathX.vec3(m.get("size", [0, 0, 0]))}
					if m.has("uid"):
						me["uid"] = int(m["uid"])
					entries.append(me)
			a.markers[key] = pts
			a.marker_entries[key] = entries
	# format 2: individual spawn markers are the spawn ring
	if a.marker_entries.has("spawn"):
		for me in a.marker_entries["spawn"]:
			if int(me["team"]) < 0:
				a.spawns.append([me["pos"], float(me["yaw"])])
	if a.id == "":
		a.errors.append("arena without id")
	return a


static func _parse_prop(p: Dictionary, fallback_id: String) -> Dictionary:
	var t := str(p.get("type", ""))
	var out := {"type": str(LEGACY_PROPS.get(t, t)), "pos": MathX.vec3(p.get("pos", [0, 0, 0])),
		"yaw": deg_to_rad(float(p.get("yaw", 0.0))), "scale": float(p.get("scale", 1.0)),
		"params": (p.get("params", {}) as Dictionary).duplicate(true) if typeof(p.get("params", {})) == TYPE_DICTIONARY else {},
		"id": str(p.get("id", fallback_id)), "builtin": false}
	if p.has("pos2"):
		out["pos2"] = MathX.vec3(p.get("pos2", [0, 0, 0]))
	if p.has("uid"):
		out["uid"] = int(p["uid"])
	return out


func _setup_legacy(d: Dictionary) -> void:
	base_def = {}
	shape = str(d.get("base", base))
	if not BASES.has(shape):
		shape = "octagon"
	radius = clampf(float(d.get("radius", 5.0)), 2.5, 12.0)
	wall_height = float(d.get("wall_height", 2.4 if shape != "platform" else 0.0))
	ringout = bool(d.get("ringout", wall_height <= 0.01))
	style = str(LEGACY_THEME_STYLE.get(theme, "gullet"))
	variant = "night"
	size = Vector2(radius * 2.0, radius * 2.0)
	match shape:
		"square":
			_set_geometry("rect", size, Vector2.ZERO, wall_height > 0.01)
		"circle", "platform":
			_set_geometry("circle", size, Vector2.ZERO, wall_height > 0.01)
		_:
			_set_geometry("octagon", size, Vector2.ZERO, wall_height > 0.01)


func _setup_base(d: Dictionary) -> void:
	var bd := base_def
	shape = str(bd["shape"])
	style = str(bd["style"])
	notch = bd["notch"]
	wall_height = float(bd["wall_height"])
	ringout = bool(bd["open_edges"])
	var vs: Dictionary = bd["variants"]
	variant = str(d.get("variant", bd["default_variant"]))
	if not vs.has(variant):
		variant = str(bd["default_variant"])
	var sz = d.get("size", null)
	var want: Vector2 = bd["size"]
	if typeof(sz) == TYPE_ARRAY and (sz as Array).size() >= 1:
		want = Vector2(float(sz[0]), float(sz[1] if (sz as Array).size() > 1 else sz[0]))
	size = clamp_size(bd, want)
	_set_geometry(shape, size, notch, not ringout)
	_resolve_builtins()


## Clamps a requested boundary size into the base's allowed range (snapped to its step).
static func clamp_size(bd: Dictionary, want: Vector2) -> Vector2:
	var lo: Vector2 = bd["size_min"]
	var hi: Vector2 = bd["size_max"]
	var step := maxf(0.05, float(bd["size_step"]))
	var w := clampf(snappedf(want.x, step), lo.x, hi.x)
	var h := clampf(snappedf(want.y, step), lo.y, hi.y)
	if bool(bd["uniform"]):
		h = w
	return Vector2(w, h)


# =====================================================================================
# Geometry
# =====================================================================================

func _set_geometry(kind: String, sz: Vector2, nt: Vector2, walled: bool) -> void:
	shape = kind
	_pieces.clear()
	_edges.clear()
	var hw := sz.x * 0.5
	var hd := sz.y * 0.5
	match kind:
		"rect":
			_boundary = PackedVector2Array([Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)])
			_pieces.append(_boundary)
			radius = maxf(hw, hd)
		"notched_rect":
			var nx := clampf(nt.x, 0.0, hw)
			var nz := clampf(nt.y, 0.0, hd)
			_boundary = PackedVector2Array([Vector2(-hw + nx, -hd), Vector2(hw, -hd), Vector2(hw, hd - nz), Vector2(hw - nx, hd - nz),
				Vector2(hw - nx, hd), Vector2(-hw, hd), Vector2(-hw, -hd + nz), Vector2(-hw + nx, -hd + nz)])
			_pieces.append(PackedVector2Array([Vector2(-hw + nx, -hd), Vector2(hw, -hd), Vector2(hw, hd - nz), Vector2(-hw + nx, hd - nz)]))
			_pieces.append(PackedVector2Array([Vector2(-hw, -hd + nz), Vector2(hw - nx, -hd + nz), Vector2(hw - nx, hd), Vector2(-hw, hd)]))
			radius = maxf(hw, hd)
		"circle":
			var pts := PackedVector2Array()
			for i in 40:
				var ang := TAU * i / 40.0
				pts.append(Vector2(cos(ang), sin(ang)) * hw)
			_boundary = pts
			_pieces.append(pts)
			radius = hw
		_:
			# octagon: flats face ±X, ±Z and the diagonals; vertices at 22.5° + k·45°
			var circ := hw / cos(PI / 8.0)
			var pts2 := PackedVector2Array()
			for i in 8:
				var ang2 := TAU * i / 8.0 + PI / 8.0
				pts2.append(Vector2(cos(ang2), sin(ang2)) * circ)
			_boundary = pts2
			_pieces.append(pts2)
			radius = hw
	# outward normals (works for either winding)
	var sgn := 1.0 if _signed_area(_boundary) > 0.0 else -1.0
	for i in _boundary.size():
		var a := _boundary[i]
		var b := _boundary[(i + 1) % _boundary.size()]
		var t := (b - a).normalized()
		var n := Vector2(t.y, -t.x) * sgn
		var side := ""
		if absf(n.x) > 0.99:
			side = "e" if n.x > 0.0 else "w"
		elif absf(n.y) > 0.99:
			side = "n" if n.y > 0.0 else "s"
		_edges.append({"a": a, "b": b, "n": n, "wall": walled, "side": side})


static func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## Clamps p into a convex polygon shrunk by `margin` (iterated half-plane projection).
static func _clamp_convex(poly: PackedVector2Array, p: Vector2, margin: float) -> Vector2:
	var sgn := 1.0 if _signed_area(poly) > 0.0 else -1.0
	var q := p
	for _it in 4:
		var moved := false
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var t := (b - a).normalized()
			var n_in := Vector2(-t.y, t.x) * sgn
			var s := (q - a).dot(n_in) - margin
			if s < 0.0:
				q -= n_in * s
				moved = true
		if not moved:
			break
	return q


static func _inside_convex(poly: PackedVector2Array, p: Vector2, margin: float) -> bool:
	var sgn := 1.0 if _signed_area(poly) > 0.0 else -1.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var t := (b - a).normalized()
		var n_in := Vector2(-t.y, t.x) * sgn
		if (p - a).dot(n_in) < margin - 1e-6:
			return false
	return true


## Point clamped inside the playable floor with a margin (horizontal only).
func clamp_point(p: Vector3, margin: float) -> Vector3:
	var p2 := Vector2(p.x, p.z)
	var best := p2
	var best_d := INF
	for piece in _pieces:
		var q := _clamp_convex(piece, p2, margin)
		var dd := q.distance_squared_to(p2)
		if dd < best_d:
			best_d = dd
			best = q
			if dd < 1e-12:
				break
	return Vector3(best.x, p.y, best.y)


## True when p is on the floor with at least `margin` to every boundary edge.
func on_floor(p: Vector3, margin := 0.0) -> bool:
	var p2 := Vector2(p.x, p.z)
	for piece in _pieces:
		if _inside_convex(piece, p2, margin):
			return true
	return false


## True when p is clear of every WALL by `margin` (open edges never block). For fully walled
## arenas this is plain geometric containment, exactly as before.
func inside(p: Vector3, margin := 0.0) -> bool:
	if not has_open_edges():
		return clamp_point(p, margin).distance_squared_to(p) < 1e-6
	return not near_wall(p, margin)


func has_open_edges() -> bool:
	for e in _edges:
		if not bool(e["wall"]):
			return true
	return false


## True when p is within `dist` of a wall edge segment.
func near_wall(p: Vector3, dist: float) -> bool:
	var p2 := Vector2(p.x, p.z)
	for e in _edges:
		if bool(e["wall"]) and _seg_dist(p2, e["a"], e["b"]) < dist:
			return true
	return false


## Distance to the nearest boundary edge (open edges only when `open_only`).
func edge_distance(p: Vector3, open_only := false) -> float:
	var p2 := Vector2(p.x, p.z)
	var best := INF
	for e in _edges:
		if open_only and bool(e["wall"]):
			continue
		best = minf(best, _seg_dist(p2, e["a"], e["b"]))
	return best


## Inward unit normal (XZ as Vector3) of the closest wall, or ZERO when there is none.
func wall_normal_near(p: Vector3) -> Vector3:
	var p2 := Vector2(p.x, p.z)
	var best := INF
	var n := Vector2.ZERO
	for e in _edges:
		if not bool(e["wall"]):
			continue
		var dd := _seg_dist(p2, e["a"], e["b"])
		if dd < best:
			best = dd
			n = -(e["n"] as Vector2)
	return Vector3(n.x, 0.0, n.y)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func boundary_polygon() -> PackedVector2Array:
	return _boundary


func floor_pieces() -> Array:
	return _pieces


## [{a, b, n (outward), wall, side}] boundary edges.
func boundary_edges() -> Array:
	return _edges


## Corner vertices of walled boundaries (octagon posts, rect corners) as XZ points.
func corners() -> PackedVector2Array:
	return _boundary


func floor_area() -> float:
	return absf(_signed_area(_boundary))


## Axis-aligned XZ bounds of the floor.
func extent() -> Rect2:
	var r := Rect2(_boundary[0], Vector2.ZERO)
	for v in _boundary:
		r = r.expand(v)
	return r


## The boundary edge on a side ("n" +Z, "s" -Z, "e" +X, "w" -X) — the longest one if several.
func edge_on_side(side: String) -> Dictionary:
	var best := {}
	var best_l := -1.0
	for e in _edges:
		if str(e["side"]) != side:
			continue
		var l: float = (e["a"] as Vector2).distance_to(e["b"])
		if l > best_l:
			best_l = l
			best = e
	return best


# =====================================================================================
# Base features (built-ins, hazards, areas, quirks)
# =====================================================================================

func _scale_pos(p: Vector3) -> Vector3:
	if base_def.is_empty():
		return p
	var b0: Vector2 = base_def["size"]
	return Vector3(p.x * size.x / maxf(0.01, b0.x), p.y, p.z * size.y / maxf(0.01, b0.y))


func _resolve_builtins() -> void:
	builtins.clear()
	for b in base_def.get("builtins", []):
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var p := _parse_prop(b, str(b.get("id", "builtin%d" % builtins.size())))
		p["builtin"] = true
		p["removable"] = bool(b.get("removable", true))
		p["pos"] = _scale_pos(p["pos"])
		var anchor := str(b.get("anchor", ""))
		if anchor != "":
			var e := edge_on_side(anchor)
			if not e.is_empty():
				var a: Vector2 = e["a"]
				var bb: Vector2 = e["b"]
				var n: Vector2 = e["n"]
				var inset := float(b.get("inset", 0.05))
				var mid := (a + bb) * 0.5 - n * inset
				p["pos"] = Vector3(mid.x, float(p["pos"].y), mid.y)
				if bool(b.get("span", false)):
					var params: Dictionary = p["params"]
					params["length"] = a.distance_to(bb) - float(b.get("span_trim", 0.0))
					p["yaw"] = atan2(n.x, n.y) + PI * 0.5
		if p.has("pos2"):
			p["pos2"] = _scale_pos(p["pos2"])
		builtins.append(p)


func builtin_removed(bid: String) -> bool:
	return removed_builtins.has(bid)


## Built-ins (not removed) followed by the layout's own props. Every entry has "builtin".
func all_props() -> Array:
	var out := []
	for b in builtins:
		if not builtin_removed(str(b["id"])):
			out.append(b)
	out.append_array(props)
	return out


## Base hazard definitions active for this layout (layout flags can disable them).
func hazard_defs() -> Array:
	var out := []
	for h in base_def.get("hazards", []):
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var fl := str(h.get("flag", ""))
		if fl != "" and not bool(flags.get(fl, true)):
			continue
		var c: Dictionary = (h as Dictionary).duplicate(true)
		if c.has("spots"):
			var spots := []
			for s in c["spots"]:
				var v := _scale_pos(Vector3(float(s[0]), 0.0, float(s[1])))
				spots.append(Vector2(v.x, v.z))
			c["spots"] = spots
		out.append(c)
	return out


## Every base hazard (ignoring flags) — the editor lists them as toggles.
func base_hazards_all() -> Array:
	return base_def.get("hazards", [])


## Floor areas of the base for the current size: [{id, type, rect: Rect2 (x, z), params}].
func areas() -> Array:
	var out := []
	var ext := extent()
	for ar in base_def.get("areas", []):
		if typeof(ar) != TYPE_DICTIONARY:
			continue
		var r := Rect2()
		var t := str(ar.get("type", ""))
		var width := float(ar.get("width", 1.5))
		match str(ar.get("side", "")):
			"n":
				r = Rect2(ext.position.x, ext.end.y - width, ext.size.x, width)
			"s":
				r = Rect2(ext.position.x, ext.position.y, ext.size.x, width)
			"e":
				r = Rect2(ext.end.x - width, ext.position.y, width, ext.size.y)
			"w":
				r = Rect2(ext.position.x, ext.position.y, width, ext.size.y)
			"center_x":
				r = Rect2(ext.position.x, -width * 0.5, ext.size.x, width)
			"center_z":
				r = Rect2(-width * 0.5, ext.position.y, width, ext.size.y)
			_:
				r = ext
		out.append({"id": str(ar.get("id", t)), "type": t, "rect": r, "params": ar})
	return out


## Rect of a base hazard that runs along an axis (tidal gutter).
func strip_rect(h: Dictionary) -> Rect2:
	var ext := extent()
	var width := float(h.get("width", 1.5))
	if str(h.get("axis", "x")) == "z":
		return Rect2(-width * 0.5, ext.position.y, width, ext.size.y)
	return Rect2(ext.position.x, -width * 0.5, ext.size.x, width)


## Plate grid cells for a plate_grid hazard: Array of Rect2 (row-major, index = j * gx + i).
func grid_cells(h: Dictionary) -> Array:
	var g: Array = h.get("grid", [3, 3])
	var gx := int(g[0])
	var gz := int(g[1])
	var ext := extent()
	var cw := ext.size.x / float(gx)
	var cd := ext.size.y / float(gz)
	var out := []
	for j in gz:
		for i in gx:
			out.append(Rect2(ext.position.x + cw * i, ext.position.y + cd * j, cw, cd))
	return out


func quirk(key: String, fallback = 0.0):
	return base_def.get("quirks", {}).get(key, fallback)


func ringout_params() -> Dictionary:
	var out := RINGOUT_DEFAULTS.duplicate()
	var r: Dictionary = base_def.get("ringout", {})
	for k in r:
		out[k] = r[k]
	return out


func allows_pits() -> bool:
	return bool(base_def.get("allow_pits", ringout)) or bool(flags.get("allow_pits", false))


func variant_def() -> Dictionary:
	var vs: Dictionary = base_def.get("variants", {})
	return vs.get(variant, {})


func supports_mode(m: String) -> bool:
	return modes.is_empty() or modes.has(m.trim_prefix("mode_"))


# =====================================================================================
# Markers & spawns
# =====================================================================================

## Marker positions by name ("spotlight_anchor", "goal", "ball_spawn", "wave_gate", "unit_spawn",
## "boss", "spawn", "respawn", ...). Accepts names with or without the "marker_" prefix.
func marker_points(name_: String) -> Array:
	var n := name_.trim_prefix("marker_")
	return markers.get(n, markers.get("marker_" + n, []))


func markers_of(name_: String) -> Array:
	var n := name_.trim_prefix("marker_")
	return marker_entries.get(n, marker_entries.get("marker_" + n, []))


## Spawn entries of a team cluster (team slot 0 = A, 1 = B).
func team_spawns(team_slot: int) -> Array:
	var out := []
	for me in markers_of("spawn"):
		if int(me["team"]) == team_slot:
			out.append(me)
	return out


func has_team_clusters() -> bool:
	return not team_spawns(0).is_empty() and not team_spawns(1).is_empty()


## Spawn point i of `count` fighters: [Vector3, yaw]. Format-2 arenas treat the individual
## spawns as a ring (entry k and k + n/2 are opposite), so `count` fighters are spread evenly
## (2 fighters -> opposite points, 4 -> every other point). Legacy arenas use spawns[i].
func spawn_point(i: int, count: int) -> Array:
	var n := spawns.size()
	if n > 0 and format >= 2 and count > 0 and count <= n:
		var k := int(round(float(i) * float(n) / float(count))) % n
		return _spawn_entry(k)
	if i < n:
		return _spawn_entry(i)
	var r := radius * 0.55
	var a := TAU * float(i) / float(maxi(count, 2)) + PI * 0.5
	var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
	return [p, atan2(-p.x, -p.z)]


func _spawn_entry(k: int) -> Array:
	var s: Array = spawns[k]
	var yaw: float = s[1]
	var sp: Vector3 = s[0]
	if is_nan(yaw):
		yaw = atan2(-sp.x, -sp.z)
	return [sp, yaw]


# =====================================================================================
# Serialization
# =====================================================================================

func to_dict() -> Dictionary:
	var pr := []
	for p in props:
		pr.append(prop_to_json(p))
	var mk := {}
	for k in marker_entries:
		var arr := []
		for me in marker_entries[k]:
			arr.append(marker_to_json(me))
		mk[k] = arr
	if format < 2 or base_def.is_empty():
		var sp := []
		for s in spawns:
			var v: Vector3 = s[0]
			sp.append([r2(v.x), r2(v.z), r1(rad_to_deg(s[1])) if not is_nan(s[1]) else 0.0])
		var hz := []
		for h in hazards:
			var v3: Vector3 = h["pos"]
			hz.append({"type": h["type"], "pos": [r2(v3.x), 0.0, r2(v3.z)], "radius": h["radius"], "params": h["params"]})
		return {"id": id, "name": display_name, "base": base, "radius": radius, "wall_height": wall_height,
			"ringout": ringout, "theme": theme, "gravity_mult": gravity_mult, "author": author, "version": version,
			"spawns": sp, "props": pr, "hazards": hz, "markers": mk}
	var out := {"id": id, "name": display_name, "base": base, "variant": variant, "format": FORMAT,
		"version": version, "author": author, "size": [r2(size.x), r2(size.y)],
		"modes": modes.duplicate(), "flags": flags.duplicate(true), "removed_builtins": removed_builtins.duplicate(),
		"props": pr, "markers": mk}
	if description != "":
		out["description"] = description
	if defines_base:
		out["base_def"] = _base_def_json()
	return out


## Rounding for serialization: roundf(v * 100) / 100 is the double closest to the short decimal
## (snappedf's multiply is not), so values survive JSON text round trips bit-exactly.
static func r2(v: float) -> float:
	return roundf(v * 100.0) / 100.0


static func r1(v: float) -> float:
	return roundf(v * 10.0) / 10.0


static func prop_to_json(p: Dictionary) -> Dictionary:
	var v: Vector3 = p["pos"]
	var o := {"type": str(p["type"]), "pos": [r2(v.x), r2(v.y), r2(v.z)],
		"yaw": r1(rad_to_deg(float(p.get("yaw", 0.0))))}
	if float(p.get("scale", 1.0)) != 1.0:
		o["scale"] = float(p["scale"])
	if p.has("pos2"):
		var v2: Vector3 = p["pos2"]
		o["pos2"] = [r2(v2.x), r2(v2.y), r2(v2.z)]
	var params: Dictionary = p.get("params", {})
	if not params.is_empty():
		o["params"] = params.duplicate(true)
	return o


static func marker_to_json(me: Dictionary) -> Dictionary:
	var v: Vector3 = me["pos"]
	var o := {"pos": [r2(v.x), r2(v.y), r2(v.z)], "yaw": r1(rad_to_deg(float(me.get("yaw", 0.0)))),
		"team": int(me.get("team", -1))}
	var s: Vector3 = me.get("size", Vector3.ZERO)
	if s != Vector3.ZERO:
		o["size"] = [s.x, s.y, s.z]
	return o


## JSON-ready copy of base_def (normalized Vector2 fields turned back into arrays).
func _base_def_json() -> Dictionary:
	var o: Dictionary = base_def.duplicate(true)
	for k in ["size", "size_min", "size_max", "notch"]:
		if o.get(k) is Vector2:
			var v: Vector2 = o[k]
			o[k] = [v.x, v.y]
	return o


## Canonical sha256 of the layout as serialized by to_dict() (used by packages and multiplayer
## to check that two peers run the same arena). Keys are sorted, integral floats normalized.
func content_hash() -> String:
	return JSON.stringify(canonical(to_dict()), "", true, true).sha256_text()


static func canonical(v):
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and floorf(f) == f and absf(f) < 9.0e15:
				return int(f)
			var q := roundf(f * 10000.0) / 10000.0
			return int(q) if floorf(q) == q else q
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[str(k)] = canonical(v[k])
			return out
		TYPE_ARRAY:
			var arr := []
			for e in v:
				arr.append(canonical(e))
			return arr
	return v
