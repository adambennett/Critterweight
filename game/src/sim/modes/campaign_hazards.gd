class_name CampaignHazards
extends RefCounted
## Arena hazards for campaign fights and boss arenas, built only from the simulation's effects
## vocabulary (areas, zones, props, pushes/pulls, delayed strikes) so they obey every combat rule
## (guard, statuses, reactions, credit). Parameters come from campaign rules "hazards" (data);
## an encounter lists {kind, every?, ...overrides}. Positions are derived from the arena radius
## unless the arena layout provides markers named "hazard_<kind>".
##
## Timed kinds: crane_hook, gutter_flood, magnet, plates, wind, steam_vents, chain_sweep,
## floor_flood, juice_vat. Static kinds (set up at the bell): fire_barrels, sludge_drums,
## batteries, spring_pads, sponsor_boards, juice_cans, mooring_blocks, scrap_piles.
## Every telegraphed hazard emits {"type": "hazard_telegraph", kind, pos, radius, shape, time}
## at least `telegraph` seconds before it acts (presentation draws the decal).

var _mode_ref: WeakRef             ## CampaignMatchMode (weak: the mode owns this runner)
var sim: MatchSim
var defs := {}
var list: Array = []              ## active hazards: {kind, def, next, state...}
var pending: Array = []           ## telegraphed actions: {at, kind, fn, args}
var pickups: Array = []           ## juice cans: {pos, radius, ready_at, hype}
var blocks: Array = []            ## mooring blocks: Vector3 positions (dry spots)
var anchor := Vector3.ZERO        ## chain sweep centre (boss bollard)
var rng := RandomNumberGenerator.new()


func _init(m, hazards: Array, hazard_defs: Dictionary) -> void:
	_mode_ref = weakref(m)
	sim = m.sim
	defs = hazard_defs
	rng.seed = sim.seed_value * 7 + 3
	for h in hazards:
		add(h)


func add(h: Dictionary) -> void:
	var kind := str(h.get("kind", ""))
	var def: Dictionary = defs.get(kind, {}).duplicate(true)
	if def.is_empty():
		return
	for k in h:
		if k != "kind":
			def[k] = h[k]
	var every := float(def.get("every", 0.0))
	var e := {"kind": kind, "def": def, "next": sim.time + (every * 0.6 if every > 0.0 else 0.0), "state": {}, "setup": false}
	list.append(e)
	if _mode()._bell_done:
		_setup_static(e)


func remove_kind(kind: String) -> void:
	list = list.filter(func(e): return e["kind"] != kind)


func has_kind(kind: String) -> bool:
	for e in list:
		if e["kind"] == kind:
			return true
	return false


func on_bell() -> void:
	for e in list:
		_setup_static(e)
		var every := float(e["def"].get("every", 0.0))
		if every > 0.0:
			e["next"] = sim.time + every * 0.6


static func _has_num(arr: Array, v: int) -> bool:
	for x in arr:
		if int(x) == v:
			return true
	return false


func _mode():
	return _mode_ref.get_ref() if _mode_ref else null


func radius() -> float:
	return sim.arena.radius if sim.arena else 5.0


## Points for a static hazard: arena markers "hazard_<kind>" if present, else a ring.
func points(kind: String, count: int, ring: float, phase := 0.0) -> Array:
	if sim.arena and sim.arena.markers.has("hazard_" + kind):
		return (sim.arena.markers["hazard_" + kind] as Array).slice(0, count)
	var out := []
	for i in count:
		var a := phase + TAU * float(i) / float(maxi(1, count))
		out.append(Vector3(cos(a), 0.0, sin(a)) * radius() * ring)
	return out


func _setup_static(e: Dictionary) -> void:
	if bool(e["setup"]):
		return
	e["setup"] = true
	var d: Dictionary = e["def"]
	var n := int(d.get("count", 1))
	match str(e["kind"]):
		"fire_barrels", "batteries":
			for p in points(str(e["kind"]), n, 0.5, 0.4):
				sim.effects.spawn_hazard_zone(p, {"hazard": e["kind"], "radius": float(d.get("radius", 0.9)), "element": str(d.get("element", "")),
					"buildup": float(d.get("buildup", 15.0)), "tick_damage": float(d.get("tick_damage", 0.0)), "tick": 0.5,
					"flinch_on_entry": float(d.get("flinch", 0.0)), "vfx": e["kind"]})
		"sludge_drums":
			e["state"]["pts"] = points("sludge_drums", n, 0.55, 1.1)
			e["next"] = sim.time
			e["def"]["every"] = 6.0
		"spring_pads":
			for p2 in points("spring_pads", n, 0.6, 0.25):
				sim.effects._spawn_prop(null, {"prop": "spring_pad", "radius": float(d.get("radius", 1.2)), "duration": 1e9, "launch_up": 2.5, "launch_forward": 3.0}, p2)
		"sponsor_boards", "scrap_piles", "mooring_blocks":
			var ring := 0.72 if e["kind"] == "sponsor_boards" else (0.45 if e["kind"] == "mooring_blocks" else 0.5)
			for p3 in points(str(e["kind"]), n, ring, 0.7):
				sim.effects._spawn_prop(null, {"prop": "rubble", "radius": float(d.get("radius", 0.9)), "hp": float(d.get("hp", 0.0)), "duration": 1e9}, p3)
				if e["kind"] == "mooring_blocks":
					blocks.append(p3)
		"juice_cans":
			for p4 in points("juice_cans", n, 0.45, 0.8):
				pickups.append({"pos": p4, "radius": float(d.get("radius", 0.8)), "ready_at": 0.0, "hype": float(d.get("hype", 50.0)), "respawn": float(d.get("respawn", 20.0))})
	sim.emit_event({"type": "hazard_setup", "kind": e["kind"], "name": str(d.get("name", e["kind"]))})


func tick(dt: float) -> void:
	for p in pending.duplicate():
		if sim.time >= float(p["at"]):
			pending.erase(p)
			(p["fn"] as Callable).callv(p["args"])
	for e in list:
		var d: Dictionary = e["def"]
		var every := float(d.get("every", 0.0))
		if every > 0.0 and sim.time >= float(e["next"]):
			e["next"] = sim.time + every
			_trigger(e)
		_continuous(e, dt)
	for pk in pickups:
		if sim.time < float(pk["ready_at"]):
			continue
		for f: Fighter in sim.fighters:
			if f.is_out() or _mode().is_parked(f):
				continue
			var pp: Vector3 = pk["pos"]
			if Vector2(f.pos().x - pp.x, f.pos().z - pp.z).length() <= float(pk["radius"]):
				f.hype = clampf(f.hype + float(pk["hype"]), 0.0, 100.0)
				pk["ready_at"] = sim.time + float(pk["respawn"])
				sim.emit_event({"type": "pickup", "fighter": f.index, "kind": "juice_can", "pos": pp})
				break


func _telegraph(kind: String, pos: Vector3, r: float, shape: String, t: float, extra := {}) -> void:
	var ev := {"type": "hazard_telegraph", "kind": kind, "pos": pos, "radius": r, "shape": shape, "time": t}
	for k in extra:
		ev[k] = extra[k]
	sim.emit_event(ev)


func _later(t: float, fn: Callable, args: Array) -> void:
	pending.append({"at": sim.time + t, "fn": fn, "args": args})


func _random_fighter_pos(prefer_party := true) -> Vector3:
	var cands := []
	for f: Fighter in sim.fighters:
		if f.is_out() or _mode().is_parked(f):
			continue
		if prefer_party and not _mode().is_party(f):
			continue
		cands.append(f)
	if cands.is_empty() and prefer_party:
		return _random_fighter_pos(false)
	if cands.is_empty():
		return Vector3.ZERO
	var f2: Fighter = cands[rng.randi_range(0, cands.size() - 1)]
	return f2.ground_pos()


func _area(kind: String, pos: Vector3, r: float, d: Dictionary, shape := "circle", inner := 0.0) -> void:
	var e := {"type": "area", "shape": shape, "radius": r, "inner": inner, "damage": float(d.get("damage", 0.0)),
		"knockback": float(d.get("knockback", 1.5)), "poise": float(d.get("poise", 10.0)), "stun": float(d.get("stun", 0.3)),
		"launch": float(d.get("launch", 0.0)), "element": str(d.get("element", "")), "buildup": float(d.get("buildup", 0.0)),
		"knockdown": bool(d.get("trip", false)), "id": kind, "unblockable": bool(d.get("unblockable", false))}
	sim.effects.area(null, e, pos)
	sim.emit_event({"type": "effect", "fighter": -1, "effect": "area", "pos": pos, "element": e["element"], "vfx": kind,
		"radius": r, "shape": shape, "yaw": 0.0, "move": kind})


func _trigger(e: Dictionary) -> void:
	var d: Dictionary = e["def"]
	var tel := float(d.get("telegraph", 1.0))
	match str(e["kind"]):
		"crane_hook":
			var p := _random_fighter_pos()
			_telegraph("crane_hook", p, float(d.get("radius", 1.8)), "circle", tel)
			_later(tel, _area, ["crane_hook", p, float(d.get("radius", 1.8)), d])
		"gutter_flood":
			var pts := _gutter_points(d)
			for gp in pts:
				_telegraph("gutter_flood", gp, float(d.get("radius", 1.6)), "circle", tel)
			_later(tel, _flood, [pts, d])
		"magnet":
			_telegraph("magnet", Vector3.ZERO, float(d.get("radius", 4.0)), "circle", tel)
			_later(tel, _magnet_start, [d])
		"plates":
			_plates_cycle(e)
		"wind":
			var a := rng.randf() * TAU
			var dir := Vector3(cos(a), 0.0, sin(a))
			_telegraph("wind", Vector3.ZERO, radius(), "arrow", tel, {"dir": dir})
			_later(tel, _wind, [dir, d])
		"steam_vents":
			var vents := points("steam_vents", int(d.get("count", 4)), 0.7, 0.3)
			var vp: Vector3 = vents[rng.randi_range(0, vents.size() - 1)]
			_telegraph("steam_vents", vp, float(d.get("radius", 1.2)), "circle", tel)
			_later(tel, _area, ["steam_vents", vp, float(d.get("radius", 1.2)), d])
		"chain_sweep":
			_telegraph("chain_sweep", anchor, float(d.get("radius", 4.0)), "ring", tel, {"inner": float(d.get("inner", 0.5))})
			_later(tel, _area, ["chain_sweep", anchor, float(d.get("radius", 4.0)), d, "ring", float(d.get("inner", 0.5))])
		"sludge_drums":
			for sp in e["state"].get("pts", []):
				sim.effects.spawn_zone(null, {"kind": "sludge_puddle", "radius": float(d.get("radius", 1.2)), "duration": 6.2}, sp)


func _continuous(e: Dictionary, dt: float) -> void:
	var d: Dictionary = e["def"]
	match str(e["kind"]):
		"magnet":
			var until := float(e["state"].get("pull_until", -1.0))
			if sim.time < until:
				for f: Fighter in sim.fighters:
					if f.is_out() or _mode().is_parked(f) or f.flags.get("boss", false):
						continue
					var to := -f.pos()
					to.y = 0.0
					if to.length() > float(d.get("radius", 4.0)) or to.length() < 0.2:
						continue
					var k := 0.5 if f.statuses.has_element("grit") else 1.0
					var dv := to.normalized() * float(d.get("pull", 2.5)) * k
					var v := f.rig.com_velocity()
					var want := Vector3(dv.x - v.x * 0.15, 0.0, dv.z - v.z * 0.15)
					f.rig.apply_body_impulse(want * f.rig.total_mass * dt * 6.0)
		"floor_flood":
			var t := float(e["state"].get("t", 0.0)) + dt
			if t >= float(d.get("tick", 1.0)):
				t = 0.0
				for f2: Fighter in sim.fighters:
					if f2.is_out() or _mode().is_parked(f2) or _on_block(f2):
						continue
					f2.statuses.add_buildup("brine", float(d.get("buildup", 15.0)), null)
			e["state"]["t"] = t
		"juice_vat":
			var r := float(d.get("radius", 2.5))
			for f3: Fighter in sim.fighters:
				if f3.is_out() or _mode().is_parked(f3):
					continue
				if Vector2(f3.pos().x, f3.pos().z).length() <= r:
					f3.hype = clampf(f3.hype + float(d.get("hype_per_s", 15.0)) * dt, 0.0, 100.0)
					f3.health = maxf(1.0, f3.health - float(d.get("hp_per_s", 2.0)) * dt)


func _on_block(f: Fighter) -> bool:
	for b in blocks:
		var bp: Vector3 = b
		if Vector2(f.pos().x - bp.x, f.pos().z - bp.z).length() <= 0.95:
			return true
	return false


func _gutter_points(d: Dictionary) -> Array:
	if sim.arena and sim.arena.markers.has("hazard_gutter_flood"):
		return sim.arena.markers["hazard_gutter_flood"]
	var line: Array = d.get("line", [-0.62, -0.62, 0.62, -0.62])
	var a := Vector3(float(line[0]), 0.0, float(line[1])) * radius()
	var b := Vector3(float(line[2]), 0.0, float(line[3])) * radius()
	var out := []
	var n := 4
	for i in n:
		out.append(a.lerp(b, float(i) / float(n - 1)))
	return out


func _flood(pts: Array, d: Dictionary) -> void:
	for p in pts:
		sim.effects.spawn_zone(null, {"kind": "brine_puddle", "radius": float(d.get("radius", 1.6)), "duration": float(d.get("duration", 6.0))}, p)
	sim.emit_event({"type": "hazard", "kind": "gutter_flood"})


func _magnet_start(d: Dictionary) -> void:
	for e in list:
		if e["kind"] == "magnet":
			e["state"]["pull_until"] = sim.time + float(d.get("duration", 1.5))
	sim.emit_event({"type": "hazard", "kind": "magnet"})


func _wind(dir: Vector3, d: Dictionary) -> void:
	for f: Fighter in sim.fighters:
		if f.is_out() or _mode().is_parked(f):
			continue
		var k := float(d.get("winded_mult", 2.0)) if f.statuses.has_element("gale") else 1.0
		f.rig.apply_body_impulse(dir * float(d.get("push", 1.5)) * 2.0 * k * f.rig.total_mass * f.statuses.mult("push_taken"))
	sim.emit_event({"type": "hazard", "kind": "wind", "dir": dir})


## Electrified plates: 3x3 grid; patterns cross -> checkerboard -> ring, then a random plate.
## Mat cells never electrify.
func _plates_cycle(e: Dictionary) -> void:
	var d: Dictionary = e["def"]
	var grid := int(d.get("grid", 3))
	var mats: Array = d.get("mats", [0, 4, 8])
	var step := int(e["state"].get("step", 0))
	e["state"]["step"] = step + 1
	var cells := []
	var pattern_i := step if step < 3 else 3
	match pattern_i:
		0:
			cells = [1, 3, 4, 5, 7]
		1:
			cells = [0, 2, 4, 6, 8]
		2:
			cells = [0, 1, 2, 3, 5, 6, 7, 8]
		_:
			cells = [rng.randi_range(0, grid * grid - 1)]
	var size := radius() * 1.3 / grid
	var tel := float(d.get("telegraph", 1.0))
	var pts := []
	for c in cells:
		var ci := int(c)
		if _has_num(mats, ci):
			continue
		var cx: float = float(ci % grid) - (grid - 1) * 0.5
		var cz: float = float(floori(float(ci) / float(grid))) - (grid - 1) * 0.5
		var p := Vector3(cx * size, 0.0, cz * size)
		pts.append(p)
		_telegraph("plates", p, size * 0.5, "square", tel)
	_later(tel, _electrify, [pts, size * 0.55, d])


func _electrify(pts: Array, r: float, d: Dictionary) -> void:
	for p in pts:
		sim.effects.spawn_zone(null, {"kind": "static_field", "radius": r, "duration": float(d.get("duration", 1.5)),
			"tick": 0.5, "tick_damage": float(d.get("damage", 8.0)) * 0.34, "buildup": float(d.get("buildup", 40.0)) * 0.34,
			"element": "static", "flinch_on_entry": 0.15, "skip_zone_reaction": false}, p)
	sim.emit_event({"type": "hazard", "kind": "plates", "count": pts.size()})
