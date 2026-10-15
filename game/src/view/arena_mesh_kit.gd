class_name ArenaMeshKit
## Procedural mesh helpers for arena set dressing and props (docs/design/ART_DIRECTION.md:
## chunky, beveled, no knife edges). Everything is built once per arena, cached by key, and
## flat-shaded per face so bevels catch the rim light. Units: metres. UV2-free, UV in metres
## (so procedural surface shaders tile consistently).

static var _cache := {}


static func _key(parts: Array) -> String:
	var s := ""
	for p in parts:
		s += str(p) + "|"
	return s


## Box of `size` centred on the origin with every edge chamfered by `bevel` (flat shaded).
static func chamfer_box(size: Vector3, bevel := 0.04) -> ArrayMesh:
	var key := _key(["cbox", size, bevel])
	if _cache.has(key):
		return _cache[key]
	var h := size * 0.5
	var b := clampf(bevel, 0.0, minf(h.x, minf(h.y, h.z)) * 0.9)
	var hi := h - Vector3(b, b, b)      # inner (inset) half extents
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 6 main faces: on axis A at sign s, spanning the inset range of the two other axes
	for axis in 3:
		var o1 := (axis + 1) % 3
		var o2 := (axis + 2) % 3
		for s in [-1.0, 1.0]:
			var q: Array = []
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var v := Vector3.ZERO
				v[axis] = s * h[axis]
				v[o1] = c.x * hi[o1]
				v[o2] = c.y * hi[o2]
				q.append(v)
			var n := Vector3.ZERO
			n[axis] = s
			_quad(st, q[0], q[1], q[2], q[3], n)
	# 12 edge strips: edge along axis A between the faces of axes B (sign s1) and C (sign s2)
	for axis in 3:
		var bx := (axis + 1) % 3
		var cx := (axis + 2) % 3
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var q2: Array = []
				for along in [-1.0, 1.0]:
					var on_b := Vector3.ZERO      # point on face B's border
					on_b[axis] = along * hi[axis]
					on_b[bx] = s1 * h[bx]
					on_b[cx] = s2 * hi[cx]
					var on_c := Vector3.ZERO      # point on face C's border
					on_c[axis] = along * hi[axis]
					on_c[bx] = s1 * hi[bx]
					on_c[cx] = s2 * h[cx]
					q2.append(on_b)
					q2.append(on_c)
				var n2 := Vector3.ZERO
				n2[bx] = s1
				n2[cx] = s2
				_quad(st, q2[0], q2[2], q2[3], q2[1], n2.normalized())
	# 8 corner triangles
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var a := Vector3(sx * h.x, sy * hi.y, sz * hi.z)
				var bb := Vector3(sx * hi.x, sy * h.y, sz * hi.z)
				var c3 := Vector3(sx * hi.x, sy * hi.y, sz * h.z)
				_tri(st, a, bb, c3, Vector3(sx, sy, sz).normalized())
	var m := st.commit()
	_cache[key] = m
	return m


## Adds a quad with consistent outward winding (flips if needed so the normal faces `n`).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var fn := (b - a).cross(c - a)
	if fn.dot(n) > 0.0:
		var t := b
		b = c
		c = t
	st.set_normal(n)
	for v in [a, b, c]:
		st.set_uv(_planar_uv(v, n))
		st.add_vertex(v)


static func _planar_uv(v: Vector3, n: Vector3) -> Vector2:
	var an := n.abs()
	if an.y >= an.x and an.y >= an.z:
		return Vector2(v.x, v.z)
	if an.x >= an.z:
		return Vector2(v.z, -v.y)
	return Vector2(v.x, -v.y)


## Cylinder (axis Y, centred) with chamfered top/bottom rims. r_top/r_bottom may differ.
static func cylinder(r_top: float, r_bottom: float, h: float, seg := 20, bevel := 0.03, caps := true) -> ArrayMesh:
	var key := _key(["cyl", r_top, r_bottom, h, seg, bevel, caps])
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hh := h * 0.5
	var b := clampf(bevel, 0.0, minf(hh, minf(r_top, r_bottom)) * 0.8)
	# profile rings (radius, y) from bottom centre to top centre
	var prof: Array = [Vector2(r_bottom - b, -hh), Vector2(r_bottom, -hh + b), Vector2(r_top, hh - b), Vector2(r_top - b, hh)]
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var dm := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		for k in prof.size() - 1:
			var p0: Vector2 = prof[k]
			var p1: Vector2 = prof[k + 1]
			var slope := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
			var n := (dm * slope.x + Vector3.UP * slope.y).normalized()
			var v00 := d0 * p0.x + Vector3.UP * p0.y
			var v01 := d1 * p0.x + Vector3.UP * p0.y
			var v10 := d0 * p1.x + Vector3.UP * p1.y
			var v11 := d1 * p1.x + Vector3.UP * p1.y
			_smooth_quad(st, v00, v01, v11, v10, n, d0, d1, slope, TAU * r_top * float(i) / seg, TAU * r_top * float(i + 1) / seg)
		if caps:
			var top: Vector2 = prof[prof.size() - 1]
			var bot: Vector2 = prof[0]
			_tri(st, Vector3.UP * top.y, d0 * top.x + Vector3.UP * top.y, d1 * top.x + Vector3.UP * top.y, Vector3.UP)
			_tri(st, Vector3.UP * bot.y, d1 * bot.x + Vector3.UP * bot.y, d0 * bot.x + Vector3.UP * bot.y, Vector3.DOWN)
	var m := st.commit()
	_cache[key] = m
	return m


## Side quad of a cylinder band with per-vertex smooth normals around the axis.
static func _smooth_quad(st: SurfaceTool, v00: Vector3, v01: Vector3, v11: Vector3, v10: Vector3, _n: Vector3, d0: Vector3, d1: Vector3, slope: Vector2, u0: float, u1: float) -> void:
	var n0 := (d0 * slope.x + Vector3.UP * slope.y).normalized()
	var n1 := (d1 * slope.x + Vector3.UP * slope.y).normalized()
	var verts := [[v00, n0, Vector2(u0, -v00.y)], [v11, n1, Vector2(u1, -v11.y)], [v01, n1, Vector2(u1, -v01.y)],
		[v00, n0, Vector2(u0, -v00.y)], [v10, n0, Vector2(u0, -v10.y)], [v11, n1, Vector2(u1, -v11.y)]]
	# keep outward winding
	var fn := (v11 - v00).cross(v01 - v00)
	if fn.dot(n0 + n1) > 0.0:
		verts = [[v00, n0, Vector2(u0, -v00.y)], [v01, n1, Vector2(u1, -v01.y)], [v11, n1, Vector2(u1, -v11.y)],
			[v00, n0, Vector2(u0, -v00.y)], [v11, n1, Vector2(u1, -v11.y)], [v10, n0, Vector2(u0, -v10.y)]]
	for v in verts:
		st.set_normal(v[1])
		st.set_uv(v[2])
		st.add_vertex(v[0])


## Tube (pipe/rail) through a polyline with radius r.
static func tube(points: PackedVector3Array, r: float, seg := 10, closed := false) -> ArrayMesh:
	var key := _key(["tube", points, r, seg, closed])
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var count := n if closed else n - 1
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % n]
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 1e-4:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(dir).normalized()
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var o0 := side * cos(t0) + up * sin(t0)
			var o1 := side * cos(t1) + up * sin(t1)
			var verts := [[a + o0 * r, o0], [b + o1 * r, o1], [b + o0 * r, o0], [a + o0 * r, o0], [a + o1 * r, o1], [b + o1 * r, o1]]
			if ((b + o1 * r) - (a + o0 * r)).cross((b + o0 * r) - (a + o0 * r)).dot(o0 + o1) > 0.0:
				verts = [[a + o0 * r, o0], [b + o0 * r, o0], [b + o1 * r, o1], [a + o0 * r, o0], [b + o1 * r, o1], [a + o1 * r, o1]]
			for v in verts:
				st.set_normal(v[1])
				st.set_uv(Vector2(float(k) / seg, 0.0))
				st.add_vertex(v[0])
	var m := st.commit()
	_cache[key] = m
	return m


## Flat polygon slab: top face at y_top (UV = XZ metres) and vertical sides down to y_bottom.
## Two surfaces: 0 = top, 1 = sides.
static func slab(poly: PackedVector2Array, y_top: float, y_bottom: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	for k in range(0, idx.size(), 3):
		var a := poly[idx[k]]
		var b := poly[idx[k + 1]]
		var c := poly[idx[k + 2]]
		_tri(st, Vector3(a.x, y_top, a.y), Vector3(b.x, y_top, b.y), Vector3(c.x, y_top, c.y), Vector3.UP)
	var top := st.commit()
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var area := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		area += p.x * q.y - q.x * p.y
	var sgn := 1.0 if area > 0.0 else -1.0
	var run := 0.0
	for i in poly.size():
		var a2 := poly[i]
		var b2 := poly[(i + 1) % poly.size()]
		var t := (b2 - a2).normalized()
		var n2 := Vector3(t.y, 0.0, -t.x) * sgn
		var l := a2.distance_to(b2)
		var verts := [Vector3(a2.x, y_top, a2.y), Vector3(b2.x, y_top, b2.y), Vector3(b2.x, y_bottom, b2.y), Vector3(a2.x, y_bottom, a2.y)]
		var uvs := [Vector2(run, 0), Vector2(run + l, 0), Vector2(run + l, y_top - y_bottom), Vector2(run, y_top - y_bottom)]
		var order := [0, 1, 2, 0, 2, 3]
		if (verts[1] - verts[0]).cross(verts[2] - verts[0]).dot(n2) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for o in order:
			st2.set_normal(n2)
			st2.set_uv(uvs[o])
			st2.add_vertex(verts[o])
		run += l
	st2.commit(top)
	return top


## Polygon offset inward by `d` (outward if negative) with mitred corners, keeping one vertex per
## input vertex so bands can be stitched edge by edge (works for convex and mildly concave shapes).
static func inset_polygon(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := poly.size()
	var area := 0.0
	for i in n:
		area += poly[i].x * poly[(i + 1) % n].y - poly[(i + 1) % n].x * poly[i].y
	var sgn := 1.0 if area > 0.0 else -1.0
	var out := PackedVector2Array()
	for i in n:
		var prev := poly[(i - 1 + n) % n]
		var cur := poly[i]
		var nxt := poly[(i + 1) % n]
		var t0 := (cur - prev).normalized()
		var t1 := (nxt - cur).normalized()
		var n0 := Vector2(-t0.y, t0.x) * sgn      # inward normal of the incoming edge
		var n1 := Vector2(-t1.y, t1.x) * sgn
		var bis := n0 + n1
		var l := bis.length()
		if l < 1e-4:
			out.append(cur + n0 * d)
			continue
		bis /= l
		var cosh := maxf(bis.dot(n0), 0.2)
		out.append(cur + bis * (d / cosh))
	return out


## Thin ring band (between a polygon offset by `inset` and by `inset + width`) lying flat at y.
static func outline_band(poly: PackedVector2Array, inset: float, width: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o := inset_polygon(poly, inset)
	var i2 := inset_polygon(poly, inset + width)
	var run := 0.0
	for k in o.size():
		var a := o[k]
		var b := o[(k + 1) % o.size()]
		var c := i2[(k + 1) % i2.size()]
		var d := i2[k]
		var l := a.distance_to(b)
		var va := Vector3(a.x, y, a.y)
		var vb := Vector3(b.x, y, b.y)
		var vc := Vector3(c.x, y, c.y)
		var vd := Vector3(d.x, y, d.y)
		for tri2 in [[va, vb, vc, Vector2(run, 0), Vector2(run + l, 0), Vector2(run + l, width)], [va, vc, vd, Vector2(run, 0), Vector2(run + l, width), Vector2(run, width)]]:
			var p0: Vector3 = tri2[0]
			var p1: Vector3 = tri2[1]
			var p2: Vector3 = tri2[2]
			var uv := [tri2[3], tri2[4], tri2[5]]
			var verts := [p0, p1, p2]
			if (p1 - p0).cross(p2 - p0).y > 0.0:
				verts = [p0, p2, p1]
				uv = [tri2[3], tri2[5], tri2[4]]
			for j in 3:
				st.set_normal(Vector3.UP)
				st.set_uv(uv[j])
				st.add_vertex(verts[j])
		run += l
	return st.commit()


## Flat quad on the XZ plane centred at the origin (UV 0..1), facing +Y.
static func floor_quad(size: Vector2) -> ArrayMesh:
	var key := _key(["fq", size])
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var v := [Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, -h.y), Vector3(h.x, 0, h.y), Vector3(-h.x, 0, h.y)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for o in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.UP)
		st.set_uv(uv[o])
		st.add_vertex(v[o])
	var m := st.commit()
	_cache[key] = m
	return m


## Flat disc (fan) on XZ facing +Y, UV 0..1 across the diameter.
static func floor_disc(r: float, seg := 40) -> ArrayMesh:
	var key := _key(["fd", r, seg])
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		for v in [Vector3.ZERO, p1, p0]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x / (2.0 * r) + 0.5, v.z / (2.0 * r) + 0.5))
			st.add_vertex(v)
	var m := st.commit()
	_cache[key] = m
	return m


## Convenience: a MeshInstance3D with material and local transform, added under `parent`.
static func add(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box(parent: Node3D, size: Vector3, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, bevel := 0.03) -> MeshInstance3D:
	return add(parent, chamfer_box(size, bevel), mat, pos, rot)


static func cyl(parent: Node3D, r: float, h: float, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, seg := 18, bevel := 0.02, r_top := -1.0) -> MeshInstance3D:
	return add(parent, cylinder(r if r_top < 0.0 else r_top, r, h, seg, bevel), mat, pos, rot)


## Text painted on a surface (sponsor boards, stencils). Faces +Z of `parent` space unless rotated.
static func label(parent: Node3D, text: String, size_px: int, color: Color, pos: Vector3, rot := Vector3.ZERO, outline := Color(0, 0, 0, 0), font_path := "res://assets/fonts/BarlowCondensed-900.woff2", pixel := 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 8 if outline.a > 0.0 else 0
	l.outline_modulate = outline
	l.position = pos
	l.rotation = rot
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.font = load(font_path)
	parent.add_child(l)
	return l
