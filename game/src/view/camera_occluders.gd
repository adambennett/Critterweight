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

## [{node, aabb (local), r (bounding radius), base (own transparency), t, moving, inv, c}]
var _items: Array = []
var _last_us := 0
var _blocking := 0


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
