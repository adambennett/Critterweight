class_name CameraOccluders
extends RefCounted
## Fades the arena geometry that stands between the fight camera and the fighters: pit walls,
## tall props, posts and the set dressing outside the cage. A wall can never hide the fight.
## View-only: nothing in the simulation changes, and a faded mesh still collides as before.
##
## collect() picks the meshes that could block (tall enough, not enclosing the whole arena);
## update() tests the segments from the camera to the points of interest against each nearby
## mesh's own box and eases the blocking ones to FADE transparency, the rest back to their own.

const FADE := 0.78            ## transparency of a blocking mesh
const SPEED := 7.0            ## transparency change per second
const MIN_HEIGHT := 0.6       ## shorter meshes never cover a fighter
const MIN_TOP := 1.0          ## nor do meshes that end below the fighters' chests
const INTERVAL_US := 33000    ## re-test at most ~30 times a second (fades are eased anyway)

const CROWD_CLEAR := 0.9      ## crowd figures this close to a line of sight shrink out of the way
const CROWD_NEAR := 7.0       ## only figures this close to the camera are tested
const CROWD_CLOSE := 3.0      ## figures this close to the camera always shrink away

## [{node, aabb (local), r (bounding radius), base (own transparency), t, moving, inv, c}]
var _items: Array = []
var _last_us := 0
var _blocking := 0
var _crowd: MultiMeshInstance3D = null
var _crowd_base: Array[Transform3D] = []
var _crowd_world := PackedVector3Array()    ## each figure's chest, world space
var _crowd_scale := {}                      ## instance -> current scale (missing = 1)


## The arena's crowd (one MultiMesh): figures standing in a line of sight shrink away and grow
## back once it is clear, so a wide shot from the stands is never filled by a spectator.
func set_crowd(mmi: MultiMeshInstance3D) -> void:
	_crowd = mmi
	_crowd_base.clear()
	_crowd_world.clear()
	_crowd_scale.clear()
	if mmi == null or mmi.multimesh == null:
		return
	# the placements ArenaSetDressing.crowd() recorded; else what the renderer reports
	var known: Array = mmi.get_meta("instance_transforms", [])
	for i in mmi.multimesh.instance_count:
		var xf: Transform3D = known[i] if i < known.size() else mmi.multimesh.get_instance_transform(i)
		_crowd_base.append(xf)
		_crowd_world.append(mmi.global_transform * (xf.origin + Vector3.UP * 0.8))


## Crowd figures shrunk (or shrinking) after the last update.
func crowd_hidden() -> int:
	return _crowd_scale.size()


## Every GeometryInstance3D under `root` that could block the view. Meshes under `moving`
## (props that can be shoved or knocked over) are re-read each update; the rest are cached.
## Meshes whose footprint contains `centre` (stands rings, the yard slab around a pit, floors)
## never fade.
func collect(root: Node, moving: Node = null, centre := Vector2.ZERO) -> void:
	_items.clear()
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		if n is MultiMeshInstance3D or n is Label3D or n is GPUParticles3D or n is CPUParticles3D:
			continue
		var gi := n as GeometryInstance3D
		var local := gi.get_aabb()
		if local.size == Vector3.ZERO:
			continue
		var xf := gi.global_transform
		var g := xf * local
		if g.size.y < MIN_HEIGHT or g.end.y < MIN_TOP:
			continue
		if centre.x > g.position.x and centre.x < g.end.x and centre.y > g.position.z and centre.y < g.end.z:
			continue
		_items.append({"node": gi, "aabb": local, "r": g.size.length() * 0.5 + 0.2, "base": gi.transparency, "t": 0.0,
			"moving": moving != null and moving.is_ancestor_of(gi), "inv": xf.affine_inverse(), "c": xf * local.get_center()})


func size() -> int:
	return _items.size()


## Meshes faded (or still fading) after the last update.
func blocking() -> int:
	return _blocking


## `points`: what must stay visible (fighters' bodies and heads, the camera's look point).
## `force` re-tests now and jumps straight to the result (tests, a camera cut); otherwise at most
## every INTERVAL_US, easing.
func update(cam: Vector3, points: Array, force := false) -> void:
	var now := Time.get_ticks_usec()
	if not force and _last_us != 0 and now - _last_us < INTERVAL_US:
		return
	var step := 1.0 if force or _last_us == 0 else SPEED * float(now - _last_us) / 1e6
	_last_us = now
	_blocking = 0
	for it: Dictionary in _items:
		var gi: GeometryInstance3D = it["node"]
		if not is_instance_valid(gi):
			continue
		var hit := false
		if bool(it["moving"]):
			if gi.is_visible_in_tree():
				var xf := gi.global_transform
				it["inv"] = xf.affine_inverse()
				it["c"] = xf * (it["aabb"] as AABB).get_center()
			else:
				it["c"] = Vector3(INF, INF, INF)
		var c: Vector3 = it["c"]
		var r := float(it["r"])
		for p: Vector3 in points:
			if _near_segment(c, cam, p, r) and segment_hits_box(it["inv"], it["aabb"], cam, p):
				hit = true
				break
		var want := FADE if hit else 0.0
		var t := move_toward(float(it["t"]), want, step)
		if t != float(it["t"]):
			it["t"] = t
			gi.transparency = maxf(float(it["base"]), t)
		if t > 0.0:
			_blocking += 1
	if _crowd != null and is_instance_valid(_crowd) and _crowd.visible:
		_update_crowd(cam, points, step * 1.5)


func _update_crowd(cam: Vector3, points: Array, step: float) -> void:
	var mm := _crowd.multimesh
	for i in _crowd_world.size():
		var w := _crowd_world[i]
		var duck := false
		var d2 := w.distance_squared_to(cam)
		if d2 < CROWD_CLOSE * CROWD_CLOSE:
			duck = true                  # right under the lens: a giant blob filling the shot
		elif d2 < CROWD_NEAR * CROWD_NEAR:
			for p: Vector3 in points:
				if _near_segment(w, cam, p, CROWD_CLEAR):
					duck = true
					break
		var cur := float(_crowd_scale.get(i, 1.0))
		var want := 0.0 if duck else 1.0
		if cur == want:
			continue
		var s := move_toward(cur, want, step)
		if s >= 1.0:
			_crowd_scale.erase(i)
		else:
			_crowd_scale[i] = s
		_set_figure_scale(mm, i, s)


func _set_figure_scale(mm: MultiMesh, i: int, s: float) -> void:
	var b := _crowd_base[i]
	mm.set_instance_transform(i, Transform3D(b.basis.scaled(Vector3.ONE * maxf(s, 0.001)), b.origin))


## What a wall must never hide: the camera's look point, and the followed fighter and its target
## (body and head height). `focus` is a scene's camera focus, [position, target position or null].
static func points_for(cam: FightCamera, focus: Array) -> Array:
	var pts: Array = [cam.center + Vector3.UP * 0.9]
	for p in focus:
		if p is Vector3:
			pts.append(p)
			pts.append(p + Vector3.UP * 0.6)
	return pts


## Puts every mesh back to its own transparency.
func clear() -> void:
	for it: Dictionary in _items:
		var gi: GeometryInstance3D = it["node"]
		if is_instance_valid(gi):
			gi.transparency = float(it["base"])
		it["t"] = 0.0
	_blocking = 0
	if _crowd != null and is_instance_valid(_crowd) and _crowd.multimesh != null:
		for i: int in _crowd_scale.keys():
			_set_figure_scale(_crowd.multimesh, i, 1.0)
	_crowd_scale.clear()


static func _near_segment(c: Vector3, a: Vector3, b: Vector3, r: float) -> bool:
	var ab := b - a
	var l2 := ab.length_squared()
	var k := 0.0 if l2 < 1e-6 else clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return c.distance_squared_to(a + ab * k) <= r * r


## Does the segment a-b (world space) cross `box` (the mesh's local AABB) given the mesh's
## inverse global transform? Slab test in the mesh's own space, so rotated walls are exact.
static func segment_hits_box(inv: Transform3D, box: AABB, a: Vector3, b: Vector3) -> bool:
	var p := inv * a
	var d := inv * b - p
	var t0 := 0.0
	var t1 := 1.0
	for axis in 3:
		var lo := box.position[axis]
		var hi := box.end[axis]
		if absf(d[axis]) < 1e-9:
			if p[axis] < lo or p[axis] > hi:
				return false
			continue
		var ta := (lo - p[axis]) / d[axis]
		var tb := (hi - p[axis]) / d[axis]
		if ta > tb:
			var s := ta
			ta = tb
			tb = s
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true
