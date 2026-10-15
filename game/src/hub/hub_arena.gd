class_name HubArenaDef
extends ArenaDef
## The arena a hub MatchSim runs on: a wall-less, ring-out-free stand-in whose real geometry is
## built by HubWorld. ArenaBuilder only creates a small floor patch under the Main Floor (the
## hub's own floor slabs cover everything); `inside()`/`clamp_point()` answer for the whole hub
## bounding box so sim helpers that ask "is this point in the arena?" (charges, splats, respawns)
## behave sensibly everywhere in the Cannery, including the separate basement/roof/pier regions.

const BOUNDS := Rect2(-40.0, -50.0, 100.0, 80.0)   ## x, z, width, depth — covers every hub region


static func make() -> HubArenaDef:
	var a := HubArenaDef.new()
	a.id = "hub_cannery"
	a.display_name = "The Cannery"
	a.base = "square"
	a.theme = "concrete"        # footsteps: concrete surface (AudioMatchBridge)
	# a legacy open square: ArenaBuilder lays only an 8 x 8 m floor patch (inside the Main Floor)
	# and no walls; the geometry helpers (extent, edges) are initialised like any legacy arena
	a._setup_legacy({"base": "square", "radius": 4.0, "wall_height": 0.0, "ringout": false})
	a.spawns = [[Vector3(-4.0, 0.0, -0.5), PI]]
	a.source = "hub"
	return a


func clamp_point(p: Vector3, margin: float) -> Vector3:
	return Vector3(clampf(p.x, BOUNDS.position.x + margin, BOUNDS.end.x - margin), p.y,
		clampf(p.z, BOUNDS.position.y + margin, BOUNDS.end.y - margin))


func inside(p: Vector3, margin := 0.0) -> bool:
	return p.x >= BOUNDS.position.x + margin and p.x <= BOUNDS.end.x - margin and p.z >= BOUNDS.position.y + margin and p.z <= BOUNDS.end.y - margin


func spawn_point(_i: int, _count: int) -> Array:
	return [spawns[0][0], spawns[0][1]]
