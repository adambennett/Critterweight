class_name HubMeshKit
extends RefCounted
## Batched procedural geometry for The Cannery (view only). Boxes, prisms, cones, spheres and
## quads are appended to ONE SurfaceTool per batch and committed as a single ArrayMesh drawn with
## the shared hub_surface material: albedo = vertex colour (stored linear), UV.x = pattern id,
## UV.y = 1 when the camera's see-through cylinder may cut it (walls, furniture), 0 for floors.
## A whole room of set dressing costs one draw call (plus its shadow pass).

const PLAIN := 0
const BRICK := 1
const TILE_WHITE := 2
const TILE_BLUE := 3
const PLANK := 4
const CONCRETE := 5
const PLASTER := 6
const CORRUGATED := 7
const MAT := 8
const HAZARD := 9
const WOOD_FLOOR := 10
const PAINT := 11

var st := SurfaceTool.new()
var verts := 0


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func _v(p: Vector3, n: Vector3, c: Color, pattern: int, cut: bool) -> void:
	st.set_color(c)
	st.set_uv(Vector2(float(pattern), 1.0 if cut else 0.0))
	st.set_normal(n)
	st.add_vertex(p)
	verts += 1


static func lin(c: Color) -> Color:
	return c.srgb_to_linear()


## Emits one triangle given counter-clockwise (seen from its front) as Godot's clockwise front face.
func _t3(pa: Vector3, na: Vector3, pb: Vector3, nb: Vector3, pc: Vector3, nc: Vector3, lc: Color, pattern: int, cut: bool) -> void:
	_v(pa, na, lc, pattern, cut)
	_v(pc, nc, lc, pattern, cut)
	_v(pb, nb, lc, pattern, cut)


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, pattern := PLAIN, cut := true) -> void:
	var n := (b - a).cross(c - a).normalized()
	var lc := lin(col)
	_t3(a, n, b, n, c, n, lc, pattern, cut)


## Quad a-b-c-d (counter-clockwise seen from the front).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, pattern := PLAIN, cut := true, double := false) -> void:
	var n := (b - a).cross(c - a).normalized()
	var lc := lin(col)
	_t3(a, n, b, n, c, n, lc, pattern, cut)
	_t3(a, n, c, n, d, n, lc, pattern, cut)
	if double:
		_t3(a, -n, d, -n, c, -n, lc, pattern, cut)
		_t3(a, -n, c, -n, b, -n, lc, pattern, cut)


func box(center: Vector3, size: Vector3, col: Color, pattern := PLAIN, cut := true, basis := Basis.IDENTITY, skip_bottom := true) -> void:
	var h := size * 0.5
	var corners := []
	for i in 8:
		var p := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		corners.append(center + basis * p)
	var faces := [[1, 3, 7, 5], [4, 6, 2, 0], [2, 6, 7, 3], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]]
	for fi in faces.size():
		if skip_bottom and fi == 3:
			continue
		var f: Array = faces[fi]
		quad(corners[f[0]], corners[f[1]], corners[f[2]], corners[f[3]], col, pattern, cut)


func box_aabb(b: AABB, col: Color, pattern := PLAIN, cut := true) -> void:
	box(b.get_center(), b.size, col, pattern, cut)


## Prism/cylinder along a->b with `sides` facets (rounded look with 10+).
func cyl(a: Vector3, b: Vector3, r: float, col: Color, sides := 12, pattern := PLAIN, cut := true, caps := true, r_b := -1.0) -> void:
	var rb := r if r_b < 0.0 else r_b
	var axis := (b - a)
	var len := axis.length()
	if len < 1e-4:
		return
	var ax := axis / len
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.95 else Vector3.RIGHT).normalized()
	var v := ax.cross(u).normalized()
	var lc := lin(col)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var p0 := a + d0 * r
		var p1 := a + d1 * r
		var q0 := b + d0 * rb
		var q1 := b + d1 * rb
		var n0 := d0
		var n1 := d1
		_t3(p0, n0, q1, n1, q0, n0, lc, pattern, cut)
		_t3(p0, n0, p1, n1, q1, n1, lc, pattern, cut)
		if caps:
			if rb > 0.0:
				_t3(b, ax, q0, ax, q1, ax, lc, pattern, cut)
			if r > 0.0:
				_t3(a, -ax, p1, -ax, p0, -ax, lc, pattern, cut)


func sphere(c: Vector3, r: float, col: Color, rings := 6, sectors := 10, pattern := PLAIN, cut := true, squash := Vector3.ONE) -> void:
	var lc := lin(col)
	for i in rings:
		var t0 := PI * i / rings
		var t1 := PI * (i + 1) / rings
		for j in sectors:
			var p0 := TAU * j / sectors
			var p1 := TAU * (j + 1) / sectors
			var n00 := Vector3(sin(t0) * cos(p0), cos(t0), sin(t0) * sin(p0))
			var n01 := Vector3(sin(t0) * cos(p1), cos(t0), sin(t0) * sin(p1))
			var n10 := Vector3(sin(t1) * cos(p0), cos(t1), sin(t1) * sin(p0))
			var n11 := Vector3(sin(t1) * cos(p1), cos(t1), sin(t1) * sin(p1))
			var v00 := c + n00 * r * squash
			var v01 := c + n01 * r * squash
			var v10 := c + n10 * r * squash
			var v11 := c + n11 * r * squash
			_t3(v00, n00, v11, n11, v10, n10, lc, pattern, cut)
			_t3(v00, n00, v01, n01, v11, n11, lc, pattern, cut)


## Flat floor patch (top face only) at height y.
func floor_rect(r: Rect2, y: float, col: Color, pattern := CONCRETE) -> void:
	quad(Vector3(r.position.x, y, r.end.y), Vector3(r.end.x, y, r.end.y), Vector3(r.end.x, y, r.position.y), Vector3(r.position.x, y, r.position.y), col, pattern, false)


## Vertical wall slab between two XZ points (thickness t, from y0 to y1), cut-able.
func wall(a: Vector2, b: Vector2, y0: float, y1: float, t: float, col: Color, pattern := PLASTER) -> void:
	var d := b - a
	var len := d.length()
	if len < 1e-4:
		return
	var ang := atan2(d.y, d.x)
	var mid := (a + b) * 0.5
	box(Vector3(mid.x, (y0 + y1) * 0.5, mid.y), Vector3(len, y1 - y0, t), col, pattern, true, Basis(Vector3.UP, -ang))


func commit(nm: String, mat: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	if verts == 0:
		return mi
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
