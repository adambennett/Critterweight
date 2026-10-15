class_name HubTestCase
extends TestCase
## Shared helpers for the hub tests: a headless hub sim with a throwaway profile, a nav-path
## walking driver and event filters. Run: godot --headless --path game --fixed-fps 120 -- --test hub


## Walks a fighter through a list of world points (XZ), one after the other.
class PathDriver:
	extends InputSource
	var points: Array = []
	var index := 0
	var reach := 0.35
	var press_next := []        ## button names to press once on the next poll
	var hold := []              ## button names held while set
	## Like a player: a waypoint someone is standing on (Ludlow parked on his mopping spot) is
	## given up after a few seconds without progress (the last one counts once within 1.5 m).
	var lenient := false
	var skips := 0              ## waypoints given up on (lenient mode)

	func set_path(pts: Array) -> void:
		points = pts
		index = 0
		_best = INF
		_since = 0.0
		_blocked = 0.0

	func done() -> bool:
		return index >= points.size()

	var _best := INF
	var _since := 0.0
	var _blocked := 0.0
	var _side := 0.0

	func poll(f: Fighter, _sim, dt: float) -> void:
		f.input.move = Vector3.ZERO
		f.input.held = 0
		for b in hold:
			f.input.set_held(FighterInput.BUTTON_NAMES.find(b), true)
		for b2 in press_next:
			f.input.press(FighterInput.BUTTON_NAMES.find(b2))
		press_next = []
		while index < points.size():
			var target: Vector3 = points[index]
			var to := Vector3(target.x - f.pos().x, 0.0, target.z - f.pos().z)
			var last := index == points.size() - 1
			if to.length() <= reach or (lenient and _blocked > 3.0 and (not last or to.length() < 1.5)):
				if to.length() > reach:
					skips += 1
				index += 1
				_best = INF
				_since = 0.0
				_blocked = 0.0
				continue
			# a player steps around something in the way (Ludlow on his rounds, a stray crate)
			if to.length() < _best - 0.1:
				_best = to.length()
				_since = 0.0
				_blocked = 0.0
			else:
				_since += dt
				_blocked += dt
			if _since > 1.5:
				_side = 0.45
				_since = 0.0
			var dir := to.normalized()
			if _side > 0.0:
				_side -= dt
				dir = (dir + dir.cross(Vector3.UP) * 1.2).normalized()
			f.input.move = dir
			return


var profile := {}
var state: HubState
var sim: MatchSim
var mode: HubMode
var driver: PathDriver


func make_hub(fighter := "f_stoke", spot := "main_floor", prof := {}) -> MatchSim:
	profile = prof if not prof.is_empty() else {"id": "hub_test", "name": "Tester", "camp": {"clout": 0, "clout_total": 0, "upgrades": {}, "secrets": [], "flags": {}}, "history": []}
	state = HubState.new(profile)
	driver = PathDriver.new()
	var fid := fighter if Content.creature(fighter) != null else Cannery.pick_fighter(state)
	sim = Cannery.build_sim(fresh_world(), state, fid, spot, driver, 7)
	mode = sim.mode as HubMode
	mode.auto_transition = true
	return sim


func player() -> Fighter:
	return sim.fighters[0]


## Steps until `cond` holds or `limit` seconds pass. Returns true when it held.
func run_until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	while t < limit:
		if cond.call():
			return true
		sim.step(dt)
		await get_tree().physics_frame
		t += dt
	return cond.call()


## Walks a nav path (names from HubLayout.NAV) and returns true when the last point is reached.
func walk_nav(names: Array, limit := 40.0) -> bool:
	var pts := []
	for n in names:
		pts.append(HubLayout.NAV[n])
	driver.set_path(pts)
	return await run_until(func(): return driver.done(), limit)


func walk_to(nav_name: String, limit := 40.0) -> bool:
	var from := HubLayout.nearest_nav(player().pos())
	var path := HubLayout.nav_path(from, nav_name)
	if path.is_empty():
		fail("no nav path %s -> %s" % [from, nav_name])
		return false
	return await walk_nav(path, limit)


func events_of(type: String, after := 0) -> Array:
	var out := []
	for ev in sim.events_since(after):
		if str(ev["type"]) == type:
			out.append(ev)
	return out


func last_seq() -> int:
	return sim.event_seq


## Presses a fighter button (name from FighterInput.BUTTON_NAMES) through the driver.
func press(button: String) -> void:
	driver.press_next.append(button)


func teleport(pos: Vector3, yaw_deg := 0.0) -> void:
	mode.teleport(player(), pos, deg_to_rad(yaw_deg))
	await run_until(func(): return false, 0.15)
