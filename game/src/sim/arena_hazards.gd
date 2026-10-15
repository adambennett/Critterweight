class_name ArenaHazards
extends RefCounted
## Authoritative arena runtime inside one MatchSim (docs/ARENAS_AND_EDITOR.md "Runtime"):
## base hazards (tidal gutter, crane hook, electrified plate grid, crane magnet, wind gusts),
## base quirks (springy walls, corner shove, wet planks, slick steel), every prop behaviour
## (destructibles with element zones, pushables, bouncy tires, fans, timed vents/plates, spring
## pads, bumpers, pits, drain pairs, heavy bags, pickups, ramps, breakable railings), ring-outs
## with respawn at the nearest edge marker, and team spawn clusters.
##
## Tick: ArenaBuilder registers this runtime as MatchSim.hazards; MatchSim.step calls update(dt)
## after effects.update() and before its environment checks, so falls off open edges are caught
## here (at the base's fall_y) before MatchSim's own deep-fall ring-out check. The mode still
## decides what a ring-out costs (MatchMode.on_ringout: rules.ringout_damage /
## ringout_eliminates, mode overrides such as Absolute Unit); this runtime owns the return
## (nearest edge marker, health kept, short invulnerability).
## Determinism: all choices come from `rng`, seeded from (arena id, match seed) and consumed in a
## fixed order; timers advance only in the fight phase, in fixed ticks. Nothing here renders or
## plays audio: views read view_state() and the "arena_*" events.
## Effects integration: solid props register "proxy" prop entities (negative ids, e.hazard set) in
## EffectsSystem.entities so melee (Combat -> hit_props), projectiles and Fighter wall-splat checks
## treat them like any kit prop; spring pads register real "spring_pad" prop entities; timed
## elemental hazards spawn cosmetic zones so zone reactions (Live Puddle, Steam...) still happen.

const GRID_NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const WIND_DIRS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
const PROXY_LIFE := 1.0e12

var sim: MatchSim
var arena: ArenaDef
var rng := RandomNumberGenerator.new()
var clock := 0.0                  ## hazard clock: advances only while the mode is in its fight phase
var enabled := true               ## rules.hazards
var timer_mult := 1.0             ## rules.hazard_timer_mult (scales periods)
var ringout_ko := false            ## rules.ringout_eliminates (used when the sim has no mode)
var hazards: Array = []           ## runtime base hazards
var props: Array = []             ## runtime props: one per ArenaDef.all_props() entry, then spawned bundles
var areas: Array = []
var pending_ringouts: Array = []  ## [{f, at, from}]
var shoves: Array = []            ## kinematic environmental pushes [{f, v, left}]
var history := {"plates": [], "magnet": [], "wind": [], "crane": [], "gutter": [], "ringouts": []}
var _cursor := 0
var _next_proxy := -1000
var _cool := {}                   ## "<what>:<fighter>" -> sim time until which it cools down
var _ringout := {}
var _bundle_serial := 0
var _parked := 0


## MatchSim.hazards entry point (one call per sim tick).
func update(dt: float) -> void:
	tick(dt)


func _init(match_sim: MatchSim, a: ArenaDef, all: Array, bodies: Array) -> void:
	sim = match_sim
	arena = a
	rng.seed = MathX.hash32("arena|%s|%d" % [a.id, int(match_sim.seed_value)])
	var rules: Dictionary = match_sim.rules
	enabled = bool(rules.get("hazards", true))
	timer_mult = clampf(float(rules.get("hazard_timer_mult", 1.0)), 0.25, 4.0)
	ringout_ko = bool(rules.get("ringout_eliminates", false))
	_ringout = a.ringout_params()
	areas = a.areas()
	for h in a.hazard_defs():
		hazards.append(_new_hazard(h))
	for i in all.size():
		_register_prop(all[i], i, bodies[i] if i < bodies.size() else null)


# =====================================================================================
# Setup
# =====================================================================================

func _new_hazard(h: Dictionary) -> Dictionary:
	var period := float(h.get("period", 20.0)) * timer_mult
	return {"def": h, "id": str(h.get("id", "")), "type": str(h.get("type", "")), "phase": "idle", "t": 0.0, "len": 0.0,
		"period": period, "next": float(h.get("first", h.get("period", 20.0))) * timer_mult,
		"telegraph": float(h.get("telegraph", 1.0)), "active": float(h.get("active", 1.0)), "data": {}, "zones": [], "cycle": 0}


func _register_prop(p: Dictionary, index: int, body) -> Dictionary:
	var def := ArenaCatalog.prop(ArenaBuilder.catalog_type(str(p["type"])))
	var rec := {"i": index, "id": str(p.get("id", "")), "type": str(p["type"]), "def": def, "item": p,
		"pos": p["pos"], "yaw": float(p.get("yaw", 0.0)), "body": body, "builtin": bool(p.get("builtin", false)),
		"hp": float(def.get("hp", 0.0)), "hp_max": float(def.get("hp", 0.0)), "destroyed": false, "proxies": [], "proxy_hp": 0.0,
		"phase": "idle", "t": 0.0, "len": 0.0, "next": 0.0, "available": true, "respawn_at": 0.0, "frozen": true,
		"rest_t": 0.0, "inside": {}, "acc": {}, "spawned": false, "pad": {}, "home": Transform3D.IDENTITY}
	if body is Node3D:
		rec["home"] = (body as Node3D).global_transform
	props.append(rec)
	if def.is_empty():
		return rec
	var timed: Dictionary = def["timed"]
	if not timed.is_empty():
		var period := float(timed.get("period", 8.0)) * timer_mult
		rec["period"] = period
		rec["next"] = rng.randf_range(0.6, period) + float(timed.get("telegraph", 1.0))
	if bool(def["splat"]) or str(def["behaviour"]) == "heavy_bag":
		_make_proxies(rec)
	if str(def["behaviour"]) == "spring_pad" and enabled:
		_make_pad(rec)
	return rec


## Splits the footprint into circles along its long axis and registers them as prop entities.
func _make_proxies(rec: Dictionary) -> void:
	var def: Dictionary = rec["def"]
	var item: Dictionary = rec["item"]
	var s := ArenaCatalog.footprint_size(item, def)
	var centers: Array = []
	var r := 0.0
	if ArenaCatalog.footprint_shape(def) == "box":
		var along_x := s.x >= s.y
		var long := maxf(s.x, s.y)
		var short := minf(s.x, s.y)
		var n := maxi(1, ceili(long / maxf(short, 0.6)))
		r = maxf(short * 0.5, long / (2.0 * n))
		for k in n:
			var off := -long * 0.5 + long / (2.0 * n) + long * k / float(n)
			centers.append(Vector2(off, 0.0) if along_x else Vector2(0.0, off))
	else:
		r = s.x * 0.5
		centers.append(Vector2.ZERO)
	var hp := float(rec["hp_max"])
	rec["proxy_hp"] = hp
	for c in centers:
		var w := ArenaCatalog.to_world(item, c)
		var node := Node.new()
		node.name = "ArenaProxy%d" % (-_next_proxy)
		sim.add_child(node)
		var ent := {"id": _next_proxy, "kind": "prop", "prop": "arena_" + str(rec["type"]), "owner": -1, "team": -1,
			"pos": Vector3(w.x, 0.0, w.y), "radius": r, "life": PROXY_LIFE, "age": 0.0, "hp": hp,
			"e": {"hazard": "arena_prop", "arena_index": int(rec["i"])}, "element": "", "vfx": "none", "body": node, "cool": {},
			"local": c}
		_next_proxy -= 1
		sim.effects.entities.append(ent)
		rec["proxies"].append(ent)


## Solid props that are not wall-splat surfaces (tire stacks, bumpers, ramps, mooring blocks,
## low sacks, pushables) still stop projectiles; splat props and heavy bags already do through
## their proxies. Returns the index into `props` of the prop in the way, or -1.
func blocking_prop(p: Vector3, radius: float) -> int:
	for k in props.size():
		var rec: Dictionary = props[k]
		var def: Dictionary = rec["def"]
		if def.is_empty() or not bool(def["solid"]) or str(def["body"]) == "none" or bool(rec["destroyed"]) or not (rec["proxies"] as Array).is_empty():
			continue
		var item: Dictionary = rec["item"]
		if p.y > float(def["height"]) * float(item.get("scale", 1.0)) + radius:
			continue
		var body = rec["body"]
		if body is RigidBody3D and not (body as RigidBody3D).freeze:
			# a pushed prop: its footprint moved with the body
			var bp := (body as Node3D).global_position
			var s := ArenaCatalog.footprint_size(item, def)
			if Vector2(p.x - bp.x, p.z - bp.z).length() < maxf(s.x, s.y) * 0.5 + radius:
				return k
		elif ArenaCatalog.footprint_distance(item, def, Vector2(p.x, p.z)) < radius:
			return k
	return -1


func _make_pad(rec: Dictionary) -> void:
	var def: Dictionary = rec["def"]
	var params: Dictionary = def["params"]
	var pos: Vector3 = rec["pos"]
	var ent := {"id": _next_proxy, "kind": "prop", "prop": "spring_pad", "owner": -1, "team": -1,
		"pos": Vector3(pos.x, 0.0, pos.z), "radius": ArenaCatalog.footprint_size(rec["item"], def).x * 0.5,
		"life": PROXY_LIFE, "age": 0.0, "hp": 0.0, "body": null, "cool": {}, "element": "", "vfx": "spring_pad",
		"e": {"hazard": "arena_pad", "arena_index": int(rec["i"]), "launch_up": float(params.get("up", 2.5)), "launch_forward": float(params.get("forward", 3.0))}}
	_next_proxy -= 1
	sim.effects.entities.append(ent)
	rec["pad"] = ent


func _remove_entities(list: Array) -> void:
	for ent in list:
		var n = ent.get("body")
		if n is Node and is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			(n as Node).queue_free()
		var k := _entity_index(ent)
		if k >= 0:
			sim.effects.entities.remove_at(k)
	list.clear()


func _entity_index(ent: Dictionary) -> int:
	var id := int(ent["id"])
	var arr: Array = sim.effects.entities
	for k in arr.size():
		if int(arr[k]["id"]) == id and is_same(arr[k], ent):
			return k
	return -1


## Called once fighters exist (ArenaBuilder.spawn_hazards) and after every round reset.
func on_fighters_ready() -> void:
	place_teams()


# =====================================================================================
# Tick
# =====================================================================================

func tick(dt: float) -> void:
	_process_events()
	var fighting := sim.mode == null or sim.mode.phase == MatchMode.Phase.FIGHT
	if fighting:
		clock += dt
		if hazards_live():
			_tick_hazards(dt)
	_tick_props(dt, fighting)
	_tick_areas(dt)
	_apply_shoves(dt)
	_check_falls()
	_tick_ringouts()


## True while the base's timed hazards run: rules.hazards is on and the mode does not schedule
## arena hazards itself (campaign fights: CampaignMatchMode/BossMode own a CampaignHazards
## runner built from campaign data, so the base hazards stay off and nothing fires twice).
func hazards_live() -> bool:
	if not enabled:
		return false
	var m = sim.mode
	return not (m != null and ("hazards" in m) and m.get("hazards") != null)


## Test/tool hook: advances only the hazard clock and state machines (no event processing).
func debug_advance(seconds: float, dt := 1.0 / 120.0) -> void:
	var n := int(round(seconds / dt))
	for i in n:
		clock += dt
		_tick_hazards(dt)
		_tick_timed_props(dt)


func _process_events() -> void:
	for ev in sim.events_since(_cursor):
		_cursor = int(ev["seq"])
		match str(ev["type"]):
			"round_reset":
				reset_round()
			"splat", "slam":
				_on_splat(ev)
			"hit":
				_on_hit(ev)


func _emit(ev: Dictionary) -> void:
	sim.emit_event(ev)


## Shared timed-cycle state machine: idle -> telegraph -> active -> idle. Returns the transition.
static func _cycle(hz: Dictionary, clk: float, dt: float) -> String:
	match str(hz["phase"]):
		"idle":
			if clk >= float(hz["next"]) - float(hz["telegraph"]):
				hz["phase"] = "telegraph"
				hz["t"] = 0.0
				hz["len"] = float(hz["telegraph"])
				return "telegraph"
		"telegraph":
			hz["t"] = float(hz["t"]) + dt
			if clk >= float(hz["next"]):
				hz["phase"] = "active"
				hz["t"] = 0.0
				hz["len"] = float(hz["active"])
				return "active"
		"active":
			hz["t"] = float(hz["t"]) + dt
			if float(hz["t"]) >= float(hz["active"]):
				hz["phase"] = "idle"
				hz["t"] = 0.0
				hz["len"] = 0.0
				hz["next"] = float(hz["next"]) + float(hz["period"])
				hz["cycle"] = int(hz.get("cycle", 0)) + 1
				return "end"
	return ""


# =====================================================================================
# Base hazards
# =====================================================================================

func _tick_hazards(dt: float) -> void:
	for hz in hazards:
		var tr := _cycle(hz, clock, dt)
		match str(hz["type"]):
			"tidal_gutter":
				_gutter(hz, tr, dt)
			"crane_hook":
				_crane(hz, tr, dt)
			"plate_grid":
				_plates(hz, tr, dt)
			"crane_magnet":
				_magnet(hz, tr, dt)
			"wind_gust":
				_wind(hz, tr, dt)
		if tr != "":
			var ev := {"type": "arena_hazard", "hazard": hz["id"], "kind": hz["type"], "phase": tr}
			for k in hz["data"]:
				if k in ["cell", "spot", "dir", "pos"]:
					ev[k] = hz["data"][k]
			_emit(ev)


func _gutter(hz: Dictionary, tr: String, dt: float) -> void:
	var def: Dictionary = hz["def"]
	var rect := arena.strip_rect(def)
	match tr:
		"active":
			history["gutter"].append(clock)
			hz["data"]["acc"] = 0.0
			# cosmetic Brine proxies so zone reactions (Live Puddle, Steam, Mud) still happen
			var n := maxi(1, int(ceil(rect.size.x if rect.size.x > rect.size.y else rect.size.y)))
			for k in n:
				var f := (k + 0.5) / float(n)
				var c := Vector3(rect.position.x + rect.size.x * f, 0.0, rect.get_center().y) if rect.size.x > rect.size.y else Vector3(rect.get_center().x, 0.0, rect.position.y + rect.size.y * f)
				var z := sim.effects.spawn_zone(null, {"kind": "brine_puddle", "radius": 0.9, "duration": float(hz["active"]) + 0.1,
					"cosmetic": true, "hazard": "arena_gutter", "skip_zone_reaction": true, "vfx": "none"}, c)
				if not z.is_empty():
					hz["zones"].append(z)
		"end":
			_remove_entities(hz["zones"])
	if str(hz["phase"]) != "active":
		return
	hz["data"]["acc"] = float(hz["data"].get("acc", 0.0)) + dt
	if float(hz["data"]["acc"]) < 0.5:
		return
	hz["data"]["acc"] = float(hz["data"]["acc"]) - 0.5
	var amount := float(def.get("buildup_per_s", 15.0)) * 0.5
	for f in sim.fighters:
		if f.is_out() or not _at_floor_level(f):
			continue
		var p := f.pos()
		if rect.has_point(Vector2(p.x, p.z)) and f.creature.element != "brine":
			f.statuses.add_buildup("brine", amount, null)


func _crane(hz: Dictionary, tr: String, dt: float) -> void:
	var def: Dictionary = hz["def"]
	var data: Dictionary = hz["data"]
	match tr:
		"telegraph":
			var spots: Array = def.get("spots", [Vector2.ZERO])
			data["spot"] = spots[rng.randi_range(0, spots.size() - 1)] if not spots.is_empty() else Vector2.ZERO
			data["hooked"] = []
			history["crane"].append(data["spot"])
		"active":
			var spot: Vector2 = data.get("spot", Vector2.ZERO)
			var r := float(def.get("radius", 0.75))
			var hooked: Array = []
			for f in sim.fighters:
				if f.is_out() or f.is_down() or f.is_evading() or f.held_by != null:
					continue
				var p := f.pos()
				if Vector2(p.x, p.z).distance_to(spot) <= r + 0.15 and _at_floor_level(f):
					hooked.append(f.index)
					f.stun(float(hz["active"]) + 0.3, true)
					_emit({"type": "arena_hooked", "fighter": f.index, "pos": p})
			data["hooked"] = hooked
		"end":
			for idx in data.get("hooked", []):
				var f: Fighter = sim.fighters[int(idx)]
				if not f.is_out():
					sim.combat.apply_simple_damage(null, f, float(def.get("damage", 8.0)), "crane_drop", {"knockdown": true, "poise": 30.0})
					_emit({"type": "arena_dropped", "fighter": f.index, "pos": f.pos()})
			data["hooked"] = []
	if str(hz["phase"]) == "active":
		var spot2: Vector2 = data.get("spot", Vector2.ZERO)
		var lift_t := clampf(float(hz["t"]) / 0.45, 0.0, 1.0)
		for idx in data.get("hooked", []):
			var f2: Fighter = sim.fighters[int(idx)]
			if f2.is_out():
				continue
			if not f2.is_down():
				f2.stun(0.2, true)
			var root := f2.rig.root()
			var target := Vector3(spot2.x, f2.rig.def.hover_height + float(def.get("height", 2.0)) * lift_t, spot2.y)
			var err := target - root.global_position
			var acc := err * 40.0 - f2.rig.com_velocity() * 9.0 + Vector3.UP * sim.gravity
			f2.rig.apply_body_impulse(acc * dt * f2.rig.total_mass)


func _plates(hz: Dictionary, tr: String, dt: float) -> void:
	var def: Dictionary = hz["def"]
	var data: Dictionary = hz["data"]
	var cells := arena.grid_cells(def)
	var g: Array = def.get("grid", [3, 3])
	var gx := int(g[0])
	match tr:
		"telegraph":
			var last := int(data.get("cell", -1))
			var cands: Array = []
			for k in cells.size():
				if k == last:
					continue
				if last >= 0 and _grid_adjacent(k, last, gx):
					continue
				cands.append(k)
			var pick: int = cands[rng.randi_range(0, cands.size() - 1)] if not cands.is_empty() else 0
			data["cell"] = pick
			history["plates"].append(pick)
		"active":
			data["inside"] = {}
			data["acc"] = {}
			var c: Rect2 = cells[int(data["cell"])]
			var z := sim.effects.spawn_zone(null, {"kind": "static_field", "radius": minf(c.size.x, c.size.y) * 0.5, "duration": float(hz["active"]),
				"cosmetic": true, "flinch_on_entry": 0.0, "hazard": "arena_plate", "vfx": "none"}, Vector3(c.get_center().x, 0.0, c.get_center().y))
			if not z.is_empty():
				hz["zones"].append(z)
		"end":
			_remove_entities(hz["zones"])
			data["inside"] = {}
	if str(hz["phase"]) == "active":
		_electrify(cells[int(data["cell"])], def, data, dt, true)


## Applies a live plate (rect) to fighters standing on it: hit on entry, then every `tick` s.
func _electrify(r: Rect2, def: Dictionary, data: Dictionary, dt: float, damages: bool) -> void:
	var inside: Dictionary = data.get("inside", {})
	var acc: Dictionary = data.get("acc", {})
	var tick_len := float(def.get("tick", 1.0))
	for f in sim.fighters:
		var key := f.index
		var on := not f.is_out() and _at_floor_level(f) and r.has_point(Vector2(f.pos().x, f.pos().z)) and not _on_mat(f)
		if not on:
			inside.erase(key)
			acc.erase(key)
			continue
		if not inside.has(key):
			inside[key] = true
			acc[key] = 0.0
			_zap(f, def, damages)
			continue
		acc[key] = float(acc[key]) + dt
		if float(acc[key]) >= tick_len:
			acc[key] = float(acc[key]) - tick_len
			_zap(f, def, damages)
	data["inside"] = inside
	data["acc"] = acc


func _zap(f: Fighter, def: Dictionary, damages: bool) -> void:
	var dmg := float(def.get("damage", 0.0))
	if damages and dmg > 0.0:
		sim.combat.apply_simple_damage(null, f, dmg, "electrified_plate", {"element": "static"})
	if f.creature.element != "static":
		f.statuses.add_buildup("static", float(def.get("buildup", 20.0)), null)
	if float(def.get("flinch", 0.15)) > 0.0:
		f.flinch(float(def.get("flinch", 0.15)))
	_emit({"type": "arena_zap", "fighter": f.index, "pos": f.pos()})


static func _grid_adjacent(a: int, b: int, gx: int) -> bool:
	var pa := Vector2i(a % gx, floori(float(a) / float(gx)))
	var pb := Vector2i(b % gx, floori(float(b) / float(gx)))
	for d in GRID_NEIGHBORS:
		if pa + d == pb:
			return true
	return false


func _magnet(hz: Dictionary, tr: String, dt: float) -> void:
	var def: Dictionary = hz["def"]
	var data: Dictionary = hz["data"]
	match tr:
		"telegraph":
			var cells := _magnet_cells()
			var pick := rng.randi_range(0, cells.size() - 1)
			var c: Rect2 = cells[pick]
			data["cell"] = pick
			data["pos"] = c.get_center()
			history["magnet"].append(pick)
		"end":
			_drop_bundle(hz)
	if str(hz["phase"]) != "active":
		return
	var center: Vector2 = data.get("pos", Vector2.ZERO)
	var radius := float(def.get("radius", 3.0))
	var speed := float(def.get("speed", 2.5))
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE or f.held_by != null or _on_mat(f):
			continue
		var p := f.pos()
		var to := center - Vector2(p.x, p.z)
		var d := to.length()
		if d > radius or d < 0.05:
			continue
		var mult := f.statuses.mult("push_taken")
		if f.statuses.has_element("grit"):
			mult *= float(def.get("caked_resist", 0.5))
		var stepv := minf(speed * mult * dt, d)
		_translate(f, Vector3(to.x, 0.0, to.y).normalized() * stepv)
	for rec in props:
		if rec["destroyed"] or str(rec["def"].get("behaviour", "")) != "crate" or not (rec["body"] is RigidBody3D):
			continue
		var rb: RigidBody3D = rec["body"]
		var to2 := center - Vector2(rb.global_position.x, rb.global_position.z)
		if to2.length() <= radius and to2.length() > 0.3:
			_thaw(rec, Vector3(to2.x, 0.0, to2.y).normalized() * speed)


func _magnet_cells() -> Array:
	for h in hazards:
		if str(h["type"]) == "plate_grid":
			return arena.grid_cells(h["def"])
	return arena.grid_cells({"grid": [3, 3]})


func _drop_bundle(hz: Dictionary) -> void:
	var def: Dictionary = hz["def"]
	var center: Vector2 = hz["data"].get("pos", Vector2.ZERO)
	var bdef := ArenaCatalog.prop(str(def.get("drop", "prop_scrap_bundle")))
	if bdef.is_empty():
		return
	# crush whoever stands under it, then push them clear of the new wall
	var half := ArenaCatalog.footprint_size({"type": bdef["id"]}, bdef).x * 0.5
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE:
			continue
		var p := f.pos()
		var off := Vector2(p.x, p.z) - center
		if absf(off.x) <= half + 0.35 and absf(off.y) <= half + 0.35:
			sim.combat.apply_simple_damage(null, f, float(def.get("crush_damage", 6.0)), "scrap_bundle", {"knockdown": true, "poise": 20.0})
			var dir := Vector3(off.x, 0.0, off.y)
			if dir.length() < 0.05:
				dir = Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf_range(0.0, TAU))
			var need := half + 0.6 - maxf(absf(off.x), absf(off.y))
			shove(f, dir, maxf(need, 0.3), 0.2)
	_bundle_serial += 1
	var item := {"type": bdef["id"], "pos": Vector3(center.x, 0.0, center.y), "yaw": deg_to_rad(15.0 * rng.randi_range(0, 5)),
		"scale": 1.0, "params": {}, "id": "bundle%d" % _bundle_serial, "builtin": false}
	var body := ArenaBuilder.build_prop_body(sim, item, bdef, 1000 + _bundle_serial)
	var rec := _register_prop(item, props.size(), body)
	rec["spawned"] = true
	_emit({"type": "arena_drop", "prop": bdef["id"], "id": item["id"], "index": rec["i"], "pos": item["pos"]})
	var live: Array = []
	for r in props:
		if bool(r["spawned"]) and not bool(r["destroyed"]):
			live.append(r)
	while live.size() > int(def.get("max_drops", 3)):
		_destroy(live.pop_front(), "crumble")


func _wind(hz: Dictionary, tr: String, dt: float) -> void:
	var def: Dictionary = hz["def"]
	var data: Dictionary = hz["data"]
	if tr == "telegraph":
		var d: Vector2 = WIND_DIRS[rng.randi_range(0, 3)]
		data["dir"] = d
		history["wind"].append(d)
	if str(hz["phase"]) != "active":
		return
	var dir: Vector2 = data.get("dir", Vector2.RIGHT)
	var speed := float(def.get("push", 1.5)) / maxf(float(hz["active"]), 0.05)
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE or f.held_by != null or f.has_flag("hovering"):
			continue
		var mult := f.statuses.mult("push_taken")
		if f.creature.element == "gale":
			mult *= float(def.get("gale_resist", 0.5))
		_translate(f, Vector3(dir.x, 0.0, dir.y) * speed * mult * dt)


# =====================================================================================
# Props
# =====================================================================================

func _tick_props(dt: float, fighting: bool) -> void:
	for rec in props:
		if bool(rec["destroyed"]):
			continue
		var def: Dictionary = rec["def"]
		if def.is_empty():
			continue
		if float(rec["hp_max"]) > 0.0:
			if (rec["proxies"] as Array).is_empty():
				_melee_scan(rec)
			if _sync_damage(rec):
				continue
		match str(def["behaviour"]):
			"crate":
				_pushable(rec, dt)
			"fan":
				if enabled and fighting:
					_fan(rec, dt)
			"bumper":
				if enabled:
					_bumper(rec)
			"drain_pair":
				if enabled:
					_drains(rec)
			"heavy_bag":
				_sync_proxies_to_body(rec)
			"pickup":
				_pickup(rec)
			"ramp":
				_ramp(rec)
		if not def["bounce"].is_empty():
			_tire(rec)
		if enabled and not def["touch"].is_empty():
			_touch(rec, dt)
	if fighting and enabled:
		_tick_timed_props(dt)


func _tick_timed_props(dt: float) -> void:
	for rec in props:
		if bool(rec["destroyed"]):
			continue
		var def: Dictionary = rec["def"]
		if def.is_empty() or def["timed"].is_empty():
			continue
		var timed: Dictionary = def["timed"]
		var hz := {"phase": rec["phase"], "t": rec["t"], "len": rec["len"], "next": rec["next"], "period": rec.get("period", 8.0),
			"telegraph": float(timed.get("telegraph", 1.0)), "active": float(timed.get("active", 1.0))}
		var tr := _cycle(hz, clock, dt)
		for k in ["phase", "t", "len", "next"]:
			rec[k] = hz[k]
		if tr != "":
			_emit({"type": "arena_prop_cycle", "prop": rec["type"], "index": rec["i"], "phase": tr, "pos": rec["pos"]})
		match str(def["behaviour"]):
			"steam_vent":
				if tr == "active":
					_vent_burst(rec)
			"electric_plate":
				var r := ArenaCatalog.footprint_aabb(rec["item"], def)
				if tr == "active":
					rec["acc"] = {"inside": {}, "acc": {}}
					var z := sim.effects.spawn_zone(null, {"kind": "static_field", "radius": minf(r.size.x, r.size.y) * 0.5, "duration": float(timed.get("active", 2.0)),
						"cosmetic": true, "flinch_on_entry": 0.0, "hazard": "arena_plate", "vfx": "none"}, Vector3(r.get_center().x, 0.0, r.get_center().y))
					rec["zone"] = z
				if str(rec["phase"]) == "active":
					_electrify(r, def["params"], rec["acc"], dt, true)
				if tr == "end":
					rec["acc"] = {}


## Damages runtime prop `i` (applied on the next tick, like a hit). For modes, scripts and tests.
func damage_prop(i: int, amount: float) -> void:
	if i >= 0 and i < props.size() and not bool(props[i]["destroyed"]):
		props[i]["melee"] = float(props[i].get("melee", 0.0)) + amount


## Low destructibles (no blocking proxies, so no wall splats) take melee damage here with the
## same rule Combat applies to prop entities: half the move's damage per tick of weapon overlap.
func _melee_scan(rec: Dictionary) -> void:
	var def: Dictionary = rec["def"]
	var item: Dictionary = rec["item"]
	if rec["body"] is Node3D:
		var b := rec["body"] as Node3D
		item = {"type": rec["type"], "pos": b.global_position, "yaw": b.global_rotation.y, "params": rec["item"].get("params", {})}
	var top := float(def["height"]) + 0.35
	for a in sim.fighters:
		if a.move == null or not (a.state == Fighter.State.ATTACK or a.state == Fighter.State.ABILITY) or a.move.damage <= 0.0:
			continue
		var widx := a.move.window_index(a.state_time)
		if widx < 0:
			continue
		for wname in a.move.windows[widx]["weapons"]:
			var w: BodyDef.Weapon = a.creature.body.weapons.get(wname)
			if w == null:
				continue
			var wp := a.rig.bodies[w.seg].global_transform * w.local
			if wp.y > top:
				continue
			if ArenaCatalog.footprint_distance(item, def, Vector2(wp.x, wp.z)) <= w.radius:
				rec["melee"] = float(rec.get("melee", 0.0)) + a.move.damage * 0.5
				break


## Proxy/melee HP sync; returns true when the prop was destroyed this tick.
func _sync_damage(rec: Dictionary) -> bool:
	var dmg := float(rec.get("melee", 0.0))
	rec["melee"] = 0.0
	var phpv := float(rec["proxy_hp"])
	for ent in rec["proxies"]:
		dmg = maxf(dmg, phpv - maxf(float(ent["hp"]), 0.0) if float(ent["hp"]) > 0.0 else phpv)
	if dmg <= 0.0:
		return false
	rec["hp"] = float(rec["hp"]) - dmg
	rec["hit_t"] = sim.time
	if float(rec["hp"]) <= 0.0:
		_destroy(rec, "damage")
		return true
	rec["proxy_hp"] = rec["hp"]
	for ent2 in rec["proxies"]:
		ent2["hp"] = rec["hp"]
	if str(rec["def"]["behaviour"]) == "crate":
		var near := _nearest_fighter(rec["body"].global_position if rec["body"] is Node3D else rec["pos"], 2.5)
		if near:
			var away: Vector3 = (rec["body"] as Node3D).global_position - near.pos()
			away.y = 0.0
			_thaw(rec, away.normalized() * 2.5 + Vector3.UP * 0.6)
	_emit({"type": "arena_prop_hit", "prop": rec["type"], "index": rec["i"], "hp": rec["hp"], "pos": rec["pos"]})
	return false


func _destroy(rec: Dictionary, cause: String) -> void:
	if bool(rec["destroyed"]):
		return
	rec["destroyed"] = true
	rec["hp"] = 0.0
	_remove_entities(rec["proxies"])
	var pos: Vector3 = rec["pos"]
	if rec["body"] is Node3D:
		pos = Vector3((rec["body"] as Node3D).global_position.x, 0.0, (rec["body"] as Node3D).global_position.z)
		if bool(rec["spawned"]):
			(rec["body"] as Node).queue_free()
			rec["body"] = null
		else:
			_parked += 1
			ArenaBuilder.park_body(rec["body"], _parked)
	var od: Dictionary = rec["def"].get("on_destroy", {})
	if not od.is_empty() and cause != "fell":
		if str(od.get("zone", "")) != "":
			sim.effects.spawn_zone(null, {"kind": str(od["zone"]), "radius": float(od.get("radius", 1.5)), "duration": float(od.get("duration", 4.0))}, pos)
		var burst: Dictionary = od.get("burst", {})
		if not burst.is_empty():
			var e := {"radius": float(burst.get("radius", 1.5)), "damage": float(burst.get("damage", 0.0)), "element": str(burst.get("element", "")),
				"buildup": float(burst.get("buildup", 0.0)), "stun": float(burst.get("stun", 0.2)), "knockback": float(burst.get("knockback", 0.0)),
				"poise": 10.0, "unblockable": true, "id": "arena_burst", "class": "hazard"}
			sim.effects.area(null, e, pos)
	_emit({"type": "arena_prop_destroyed", "prop": rec["type"], "id": rec["id"], "index": rec["i"], "pos": pos, "cause": cause})


func _restore(rec: Dictionary) -> void:
	var def: Dictionary = rec["def"]
	rec["destroyed"] = false
	rec["hp"] = rec["hp_max"]
	rec["frozen"] = true
	rec["available"] = true
	rec["phase"] = "idle"
	rec["t"] = 0.0
	if rec["body"] is Node3D:
		ArenaBuilder.unpark_body(rec["body"], rec["home"], def)
		if rec["body"] is RigidBody3D and str(def["body"]) == "dynamic":
			(rec["body"] as RigidBody3D).freeze = true
	rec["item"]["pos"] = rec["pos"]
	_remove_entities(rec["proxies"])
	if bool(def.get("splat", false)) or str(def.get("behaviour", "")) == "heavy_bag":
		_make_proxies(rec)


## Pushables stay frozen (immovable) until a fighter hits them at the shove threshold.
func _pushable(rec: Dictionary, dt: float) -> void:
	if not (rec["body"] is RigidBody3D):
		return
	var rb: RigidBody3D = rec["body"]
	var def: Dictionary = rec["def"]
	if bool(rec["frozen"]):
		var min_speed := float(def["push"].get("min_speed", 2.0))
		var cur := {"type": rec["type"], "pos": rb.global_position, "yaw": rb.global_rotation.y, "params": rec["item"].get("params", {})}
		for f in sim.fighters:
			if f.is_out() or f.state == Fighter.State.INACTIVE:
				continue
			var fp := f.pos()
			if fp.y > rb.global_position.y + 1.2:
				continue   # standing on top of it
			if ArenaCatalog.footprint_distance(cur, def, Vector2(fp.x, fp.z)) > 0.55:
				continue
			var v := f.rig.com_velocity()
			v.y = 0.0
			var to := rb.global_position - fp
			to.y = 0.0
			var closing := v.dot(to.normalized())
			if closing >= min_speed:
				_thaw(rec, to.normalized() * closing * 0.85 + Vector3.UP * 0.3)
				_emit({"type": "arena_shoved", "prop": rec["type"], "index": rec["i"], "fighter": f.index, "pos": rb.global_position})
				break
		return
	_sync_proxies_to_body(rec)
	if rb.global_position.y < -6.0:
		_destroy(rec, "fell")
		return
	if rb.linear_velocity.length() < 0.15 and rb.angular_velocity.length() < 0.3:
		rec["rest_t"] = float(rec["rest_t"]) + dt
		if float(rec["rest_t"]) > 0.4:
			rb.freeze = true
			rec["frozen"] = true
			rec["rest_t"] = 0.0
	else:
		rec["rest_t"] = 0.0


func _thaw(rec: Dictionary, vel: Vector3) -> void:
	if not (rec["body"] is RigidBody3D):
		return
	var rb: RigidBody3D = rec["body"]
	rb.freeze = false
	rb.linear_velocity = vel
	rec["frozen"] = false
	rec["rest_t"] = 0.0


func _sync_proxies_to_body(rec: Dictionary) -> void:
	if not (rec["body"] is Node3D):
		return
	var b := rec["body"] as Node3D
	var item := {"pos": b.global_position, "yaw": b.global_rotation.y}
	for ent in rec["proxies"]:
		var w := ArenaCatalog.to_world(item, ent.get("local", Vector2.ZERO))
		ent["pos"] = Vector3(w.x, 0.0, w.y)


func _fan(rec: Dictionary, dt: float) -> void:
	var params: Dictionary = rec["def"]["params"]
	var length := float(params.get("length", 5.0))
	var width := float(params.get("width", 1.5))
	var speed := float(params.get("speed", 1.5))
	var half := ArenaCatalog.footprint_size(rec["item"], rec["def"]).y * 0.5
	var yaw := float(rec["yaw"])
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE or f.held_by != null:
			continue
		var p := f.pos()
		if p.y > 2.6:
			continue
		var l := ArenaCatalog.to_local(rec["item"], Vector2(p.x, p.z))
		if l.y >= half and l.y <= half + length and absf(l.x) <= width * 0.5:
			_translate(f, fwd * speed * f.statuses.mult("push_taken") * dt)


func _vent_burst(rec: Dictionary) -> void:
	var params: Dictionary = rec["def"]["params"]
	var pos: Vector3 = rec["pos"]
	var yaw := float(rec["yaw"])
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var length := float(params.get("length", 2.0))
	var half_cone := deg_to_rad(float(params.get("cone_deg", 70.0))) * 0.5
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE or f.is_evading():
			continue
		var to := f.pos() - pos
		if to.y > 3.0:
			continue
		to.y = 0.0
		var along := to.dot(fwd)
		var above := to.length() <= 0.7
		var in_cone := along >= -0.1 and along <= length + 0.3 and absf(fwd.signed_angle_to(to, Vector3.UP)) <= half_cone
		if not (above or in_cone):
			continue
		var e := {"damage": float(params.get("damage", 6.0)), "element": str(params.get("element", "scorch")), "buildup": float(params.get("buildup", 30.0)),
			"stun": 0.25, "poise": 10.0, "knockback": 0.0, "unblockable": true, "id": "steam_vent", "class": "hazard"}
		sim.effects.effect_hit(null, f, e, pos)
		shove(f, fwd if in_cone else (to.normalized() if to.length() > 0.05 else fwd), float(params.get("push", 1.5)), 0.3)
	_emit({"type": "arena_vent", "index": rec["i"], "pos": pos, "yaw": yaw})


func _bumper(rec: Dictionary) -> void:
	var params: Dictionary = rec["def"]["params"]
	var pos: Vector3 = rec["pos"]
	var r := ArenaCatalog.footprint_size(rec["item"], rec["def"]).x * 0.5 + 0.5
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE or f.held_by != null:
			continue
		var to := f.pos() - pos
		if to.y > 1.6:
			continue
		to.y = 0.0
		if to.length() > r or not _ready("bumper%d:%d" % [int(rec["i"]), f.index], float(params.get("cooldown", 0.6))):
			continue
		sim.combat.apply_simple_damage(null, f, float(params.get("damage", 2.0)), "bumper", {"stun": 0.2})
		shove(f, to.normalized() if to.length() > 0.05 else Vector3.RIGHT, float(params.get("push", 3.0)), 0.35)
		_emit({"type": "arena_bumper", "index": rec["i"], "fighter": f.index, "pos": pos})


func _tire(rec: Dictionary) -> void:
	var b: Dictionary = rec["def"]["bounce"]
	var pos: Vector3 = rec["pos"]
	var r := ArenaCatalog.footprint_size(rec["item"], rec["def"]).x * 0.5 + 0.55
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE or f.held_by != null:
			continue
		var to := f.pos() - pos
		if to.y > 1.6:
			continue
		to.y = 0.0
		if to.length() > r:
			continue
		var v := f.rig.com_velocity()
		v.y = 0.0
		if -v.dot(to.normalized()) < float(b.get("min_speed", 2.5)):
			continue
		if not _ready("tire%d:%d" % [int(rec["i"]), f.index], 0.8):
			continue
		shove(f, to.normalized(), float(b.get("rebound", 1.5)), 0.3)
		_emit({"type": "arena_bounce", "index": rec["i"], "fighter": f.index, "pos": pos})


func _drains(rec: Dictionary) -> void:
	var params: Dictionary = rec["def"]["params"]
	var item: Dictionary = rec["item"]
	if not item.has("pos2"):
		return
	var ends: Array = [item["pos"], item["pos2"]]
	var r := float(params.get("radius", 0.5))
	var inside: Dictionary = rec["inside"]
	for f in sim.fighters:
		for k in 2:
			var key := "%d:%d" % [f.index, k]
			var c: Vector3 = ends[k]
			var p := f.pos()
			var on := not f.is_out() and _at_floor_level(f) and Vector2(p.x - c.x, p.z - c.z).length() <= r
			var was := bool(inside.get(key, false))
			inside[key] = on
			if not on or was:
				continue
			if f.is_down() or f.is_evading() or f.held_by != null or f.holding != null or f.state == Fighter.State.INACTIVE:
				continue
			if not _ready("drain%d:%d" % [int(rec["i"]), f.index], float(params.get("cooldown", 3.0)) + float(params.get("delay", 0.5))):
				continue
			var dest: Vector3 = ends[1 - k]
			inside["%d:%d" % [f.index, 1 - k]] = true
			f.begin_submerge(Vector3(dest.x, 0.0, dest.z), float(params.get("delay", 0.5)), [])
			_emit({"type": "arena_drain", "index": rec["i"], "fighter": f.index, "from": c, "to": dest})


func _pickup(rec: Dictionary) -> void:
	var pk: Dictionary = rec["def"]["pickup"]
	if not bool(rec["available"]):
		if sim.time >= float(rec["respawn_at"]):
			rec["available"] = true
			_emit({"type": "arena_pickup_respawn", "index": rec["i"], "prop": rec["type"], "pos": rec["pos"]})
		return
	var pos: Vector3 = rec["pos"]
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE:
			continue
		var p := f.pos()
		if Vector2(p.x - pos.x, p.z - pos.z).length() > float(pk.get("radius", 0.7)) or p.y > pos.y + 2.0:
			continue
		var amount := float(pk.get("amount", 15.0))
		if str(pk.get("kind", "health")) == "health":
			if f.health >= f.max_health - 0.01:
				continue
			f.heal(amount)
		else:
			if f.hype >= 100.0:
				continue
			f.hype = minf(100.0, f.hype + amount)
		rec["available"] = false
		rec["respawn_at"] = sim.time + float(pk.get("respawn", 30.0))
		_emit({"type": "arena_pickup", "index": rec["i"], "prop": rec["type"], "fighter": f.index, "kind": str(pk.get("kind", "health")), "amount": amount, "pos": pos})
		break


func _ramp(rec: Dictionary) -> void:
	var params: Dictionary = rec["def"]["params"]
	var s := ArenaCatalog.footprint_size(rec["item"], rec["def"])
	var yaw := float(rec["yaw"])
	var up_dir := Vector3(sin(yaw), 0.0, cos(yaw))
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE or f.held_by != null:
			continue
		var p := f.pos()
		var l := ArenaCatalog.to_local(rec["item"], Vector2(p.x, p.z))
		if absf(l.x) > s.x * 0.5 or l.y < s.y * 0.5 - 0.45 or l.y > s.y * 0.5 + 0.1:
			continue
		var v := f.rig.com_velocity()
		var along := Vector3(v.x, 0.0, v.z).dot(up_dir)
		var fast := f.state == Fighter.State.DODGE or along >= 5.0
		if along < float(params.get("min_speed", 3.5)) or not fast:
			continue
		if not _ready("ramp%d:%d" % [int(rec["i"]), f.index], 1.0):
			continue
		var vy := sqrt(2.0 * sim.gravity * float(params.get("lip_air", 0.5)))
		f.rig.apply_body_impulse(Vector3.UP * vy * f.rig.total_mass)
		f.begin_airborne([], 2.0 * vy / sim.gravity + 0.15)
		_emit({"type": "arena_ramp", "index": rec["i"], "fighter": f.index, "pos": p})


func _touch(rec: Dictionary, dt: float) -> void:
	var t: Dictionary = rec["def"]["touch"]
	var pos: Vector3 = rec["pos"]
	var reach := ArenaCatalog.footprint_size(rec["item"], rec["def"]).x * 0.5 + float(t.get("reach", 0.35)) + 0.3
	var acc: Dictionary = rec["acc"]
	for f in sim.fighters:
		if f.is_out() or f.state == Fighter.State.INACTIVE:
			acc.erase(f.index)
			continue
		var p := f.pos()
		if Vector2(p.x - pos.x, p.z - pos.z).length() > reach or p.y > 2.0:
			acc.erase(f.index)
			continue
		acc[f.index] = float(acc.get(f.index, 0.0)) + dt
		if float(acc[f.index]) >= 0.5:
			acc[f.index] = float(acc[f.index]) - 0.5
			var el := str(t.get("element", "scorch"))
			if f.creature.element != el:
				f.statuses.add_buildup(el, float(t.get("buildup_per_s", 10.0)) * 0.5, null)


# =====================================================================================
# Areas & quirks
# =====================================================================================

func _tick_areas(dt: float) -> void:
	for ar in areas:
		var t := str(ar["type"])
		var r: Rect2 = ar["rect"]
		var params: Dictionary = ar["params"]
		for f in sim.fighters:
			if f.is_out() or f.state != Fighter.State.DODGE or not _at_floor_level(f):
				continue
			var p := f.pos()
			if not r.has_point(Vector2(p.x, p.z)):
				continue
			match t:
				"wet_planks":
					f.statuses.add({"id": "slick", "name": "Slick", "duration": 0.25, "dash": float(params.get("dash_mult", 1.3))})
					# slippery: the dodge keeps sliding through its recovery instead of stopping
					var dur := f.eff("dodge_time")
					var rec_t := Tuning.v("dodge_recovery")
					if f.state_time >= dur and f.state_time < dur + rec_t:
						_translate(f, f.dodge_dir * float(params.get("slide", 0.5)) / maxf(rec_t, 0.02) * dt)
				"slick_floor":
					if not _on_mat(f):
						f.statuses.add({"id": "slick", "name": "Slick", "duration": 0.25, "dash": float(params.get("dash_mult", 1.1))})


func _on_splat(ev: Dictionary) -> void:
	var fi := int(ev.get("fighter", -1))
	if fi < 0 or fi >= sim.fighters.size():
		return
	var f: Fighter = sim.fighters[fi]
	var pos: Vector3 = ev.get("pos", f.pos())
	# breakable railings: a splat into one tears it off
	for rec in props:
		if bool(rec["destroyed"]) or str(rec["def"].get("behaviour", "")) != "railing":
			continue
		if ArenaCatalog.footprint_distance(rec["item"], rec["def"], Vector2(pos.x, pos.z)) <= 1.0:
			if bool(rec["def"]["params"].get("break_on_splat", true)):
				_destroy(rec, "splat")
	# springy cage walls rebound the splatted fighter
	var rebound := float(arena.quirk("wall_rebound", 0.0))
	if rebound > 0.0 and arena.near_wall(pos, 1.3) and not f.is_out():
		shove(f, arena.wall_normal_near(pos), rebound, 0.2)
		_emit({"type": "arena_rebound", "fighter": fi, "pos": pos})


func _on_hit(ev: Dictionary) -> void:
	var shove_k := float(arena.quirk("corner_shove", 0.0))
	if shove_k <= 0.0 or bool(ev.get("blocked", false)) or bool(ev.get("parried", false)):
		return
	var ti := int(ev.get("target", -1))
	if ti < 0 or ti >= sim.fighters.size():
		return
	var f: Fighter = sim.fighters[ti]
	if f.is_out():
		return
	var p := f.pos()
	var radius := float(arena.quirk("corner_radius", 1.6))
	for v in arena.corners():
		if Vector2(p.x, p.z).distance_to(v) <= radius:
			var out := -Vector3(v.x, 0.0, v.y).normalized()
			var vel := f.rig.com_velocity()
			vel.y = 0.0
			f.rig.apply_body_impulse(out * vel.length() * shove_k * f.rig.total_mass)
			_emit({"type": "arena_corner_shove", "fighter": ti, "pos": p})
			return


# =====================================================================================
# Ring-outs
# =====================================================================================

func _check_falls() -> void:
	var fall_y := float(_ringout.get("fall_y", -1.2))
	for f in sim.fighters:
		if f.state == Fighter.State.INACTIVE:
			continue
		var p := f.pos()
		if p.y >= fall_y:
			continue
		if f.is_out():
			if f.state == Fighter.State.DOWNED:
				var sp := respawn_point_near(p)
				f.rig.place(sp[0], sp[1])
				f.rig.freeze_motion()
			elif p.y < -30.0:
				# a knocked-out body that went over the edge: park it instead of falling forever
				f.rig.place(Vector3(p.x, -30.0, p.z), f.facing_yaw)
				f.rig.freeze_motion()
			continue
		_ring_out(f, p)


func _ring_out(f: Fighter, from: Vector3) -> void:
	var by := _last_attacker(f)
	history["ringouts"].append(f.index)
	_emit({"type": "ringout", "fighter": f.index, "pos": from, "by": by.index if by else -1, "arena": true})
	_drop_shoves(f)
	var out_time := float(sim.rules.get("ringout_out_time", _ringout.get("out_time", 2.5)))
	var m = sim.mode
	if m != null and m.has_method("on_ringout"):
		# The mode prices the ring-out (rules.ringout_damage / ringout_eliminates, and overrides
		# such as Absolute Unit's). A fighter it leaves standing is returned by this runtime.
		m.on_ringout(f, by)
		if f.state != Fighter.State.INACTIVE:
			return          # knocked out / downed by it
		_mode_hold(f, true)
	else:
		if ringout_ko:
			sim.on_fighter_depleted(f, by, {"ringout": true})
			return
		var frac := float(sim.rules.get("ringout_damage", _ringout.get("damage_frac", 0.08)))
		sim.combat.apply_dot(by, f, frac * f.max_health, "ringout", "", false)
		if f.is_out():
			return
		f.set_inactive(true)
	pending_ringouts.append({"f": f, "at": sim.time + out_time, "from": from})


func _tick_ringouts() -> void:
	for r in pending_ringouts.duplicate():
		var f: Fighter = r["f"]
		if f.pos().y < -30.0:
			var from: Vector3 = r["from"]
			f.rig.place(Vector3(from.x, -30.0, from.z), f.facing_yaw)
			f.rig.freeze_motion()
		if sim.time < float(r["at"]):
			continue
		pending_ringouts.erase(r)
		_mode_hold(f, false)
		if f.state != Fighter.State.INACTIVE:
			continue
		var sp := respawn_point_near(r["from"])
		f.set_inactive(false)
		f.rig.place(sp[0], sp[1])
		f.rig.freeze_motion()
		f.rig.hover_enabled = true
		f.rig.support = 1.0
		f.rig.upright_strength = 1.0
		f.facing_yaw = float(sp[1])
		f.motor.reset_feet()
		f.invuln_until = f.time + float(_ringout.get("invuln", 1.0))
		_emit({"type": "ringout_return", "fighter": f.index, "pos": sp[0]})


## Holds a ring-out fighter in the mode's respawn queue while this runtime returns it: the mode
## keeps counting it as alive but never respawns it itself (MatchMode's respawn() would refill
## its health and use the fall point instead of the nearest edge marker).
func _mode_hold(f: Fighter, on: bool) -> void:
	var m = sim.mode
	if m == null or not ("_respawns" in m):
		return
	var list: Array = m.get("_respawns")
	if on:
		for e in list:
			if e["fighter"] == f:
				e["at"] = INF
				e["arena_ringout"] = true
				return
		list.append({"fighter": f, "at": INF, "pos": null, "arena_ringout": true})
	else:
		for e in list.duplicate():
			if bool(e.get("arena_ringout", false)) and e["fighter"] == f:
				list.erase(e)


## Nearest respawn marker (edge markers on the Rooftop, pit markers elsewhere) to `p`, falling
## back to individual spawns and finally to a clamped floor point. Returns [Vector3, yaw].
func respawn_point_near(p: Vector3) -> Array:
	var best: Array = []
	var bd := INF
	for me in arena.markers_of("respawn"):
		var d := Vector2(p.x, p.z).distance_to(Vector2(me["pos"].x, me["pos"].z))
		if d < bd:
			bd = d
			best = [me["pos"], float(me["yaw"])]
	if best.is_empty():
		for i in arena.spawns.size():
			var sp := arena.spawn_point(i, arena.spawns.size())
			var d2 := Vector2(p.x, p.z).distance_to(Vector2(sp[0].x, sp[0].z))
			if d2 < bd:
				bd = d2
				best = sp
	if best.is_empty():
		var c := arena.clamp_point(Vector3(p.x, 0.0, p.z), 1.5)
		best = [Vector3(c.x, 0.0, c.z), atan2(-c.x, -c.z)]
	return best


func _last_attacker(f: Fighter) -> Fighter:
	for k in range(sim.events.size() - 1, -1, -1):
		var ev: Dictionary = sim.events[k]
		if sim.tick_count - int(ev.get("tick", 0)) > 720:
			break
		if str(ev["type"]) == "hit" and int(ev.get("target", -1)) == f.index and int(ev.get("fighter", -1)) >= 0:
			return sim.fighters[int(ev["fighter"])]
	return null


# =====================================================================================
# Teams, rounds, helpers
# =====================================================================================

## Two-sided team matches start in the arena's team clusters (A = lower team id, B = the other).
func place_teams() -> void:
	if not arena.has_team_clusters():
		return
	var teams := {}
	for f in sim.fighters:
		if not teams.has(f.team):
			teams[f.team] = []
		teams[f.team].append(f)
	if teams.size() != 2:
		return
	var multi := false
	for t in teams:
		if (teams[t] as Array).size() >= 2:
			multi = true
	if not multi:
		return
	var ids: Array = teams.keys()
	ids.sort()
	for slot in 2:
		var members: Array = teams[ids[slot]]
		var pts := arena.team_spawns(slot)
		for k in members.size():
			var me: Dictionary = pts[k % pts.size()]
			var f: Fighter = members[k]
			var pos: Vector3 = me["pos"]
			if k >= pts.size():
				pos += Vector3(0.6, 0.0, 0.6) * float(floori(float(k) / float(pts.size())))
			f.rig.place(pos, float(me["yaw"]))
			f.rig.freeze_motion()
			f.facing_yaw = float(me["yaw"])
			f.motor.reset_feet()


func reset_round() -> void:
	clock = 0.0
	for hz in hazards:
		_remove_entities(hz["zones"])
		var fresh := _new_hazard(hz["def"])
		for k in fresh:
			hz[k] = fresh[k]
	for rec in props.duplicate():
		if bool(rec["spawned"]):
			_remove_entities(rec["proxies"])
			if rec["body"] is Node and is_instance_valid(rec["body"]):
				(rec["body"] as Node).queue_free()
			props.erase(rec)
			continue
		if bool(rec["destroyed"]):
			_restore(rec)
		else:
			rec["hp"] = rec["hp_max"]
			rec["proxy_hp"] = rec["hp_max"]
			for ent in rec["proxies"]:
				ent["hp"] = rec["hp_max"]
			if rec["body"] is RigidBody3D and str(rec["def"].get("body", "")) == "dynamic":
				ArenaBuilder.unpark_body(rec["body"], rec["home"], rec["def"])
				(rec["body"] as RigidBody3D).freeze = true
				rec["frozen"] = true
			rec["available"] = true
			rec["phase"] = "idle"
			rec["t"] = 0.0
	for r in pending_ringouts:
		_mode_hold(r["f"], false)
	pending_ringouts.clear()
	shoves.clear()
	_cool.clear()
	place_teams()


## Moves a fighter kinematically by `dist` metres along `dir` over `dur` seconds (scaled by its
## push multiplier). Kinematic so the fighter's own drive cannot cancel environmental pushes.
func shove(f: Fighter, dir: Vector3, dist: float, dur: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-6 or dist <= 0.0:
		return
	shoves.append({"f": f, "v": d.normalized() * dist * f.statuses.mult("push_taken") / maxf(dur, 0.01), "left": dur})


func _apply_shoves(dt: float) -> void:
	for s in shoves.duplicate():
		var f: Fighter = s["f"]
		if f.is_out() or f.state == Fighter.State.INACTIVE or f.held_by != null:
			shoves.erase(s)
			continue
		var stepv := minf(dt, float(s["left"]))
		_translate(f, (s["v"] as Vector3) * stepv)
		s["left"] = float(s["left"]) - dt
		if float(s["left"]) <= 0.0:
			shoves.erase(s)


func _drop_shoves(f: Fighter) -> void:
	for s in shoves.duplicate():
		if s["f"] == f:
			shoves.erase(s)


func _translate(f: Fighter, delta: Vector3) -> void:
	for rb in f.rig.bodies:
		rb.global_position += delta


func _ready(key: String, cooldown: float) -> bool:
	if float(_cool.get(key, -1.0)) > sim.time:
		return false
	_cool[key] = sim.time + cooldown
	return true


func _nearest_fighter(p: Vector3, max_d: float) -> Fighter:
	var best: Fighter = null
	var bd := max_d
	for f in sim.fighters:
		if f.is_out():
			continue
		var d := Vector2(f.pos().x - p.x, f.pos().z - p.z).length()
		if d < bd:
			bd = d
			best = f
	return best


## Standing (or lying) on the floor itself, not on a raised prop and not high in the air.
func _at_floor_level(f: Fighter) -> bool:
	return f.rig.ground_y < 0.2 and f.pos().y < f.rig.def.hover_height + 0.6


func _on_mat(f: Fighter) -> bool:
	var p := Vector2(f.pos().x, f.pos().z)
	for rec in props:
		if not bool(rec["destroyed"]) and str(rec["def"].get("behaviour", "")) == "mat":
			if ArenaCatalog.footprint_distance(rec["item"], rec["def"], p) <= 0.0:
				return true
	return false


# =====================================================================================
# Views, bots, tools
# =====================================================================================

## Snapshot for ArenaView (and network snapshots): hazard phases + prop states. Plain data.
func view_state() -> Dictionary:
	var hz_out := []
	for hz in hazards:
		var d := {"id": hz["id"], "type": hz["type"], "phase": hz["phase"], "t": hz["t"], "len": hz["len"],
			"next_in": maxf(0.0, float(hz["next"]) - clock), "cycle": hz.get("cycle", 0)}
		for k in hz["data"]:
			if k in ["cell", "spot", "dir", "pos", "hooked"]:
				d[k] = hz["data"][k]
		hz_out.append(d)
	var pr_out := []
	for rec in props:
		var e := {"i": rec["i"], "type": rec["type"], "destroyed": rec["destroyed"], "available": rec["available"],
			"hp": rec["hp"], "hp_max": rec["hp_max"], "phase": rec["phase"], "t": rec["t"], "len": rec["len"], "spawned": rec["spawned"]}
		if bool(rec["spawned"]):
			e["pos"] = rec["pos"]
			e["yaw"] = rec["yaw"]
		if not bool(rec["available"]):
			e["respawn_in"] = maxf(0.0, float(rec["respawn_at"]) - sim.time)
		if rec["body"] is Node3D and is_instance_valid(rec["body"]) and str(rec["def"].get("body", "")) in ["dynamic", "bag"]:
			e["xform"] = (rec["body"] as Node3D).global_transform
		pr_out.append(e)
	return {"clock": clock, "enabled": hazards_live(), "hazards": hz_out, "props": pr_out, "ringouts": pending_ringouts.size()}


## 0..1 danger of standing at p right now (active hazards 1.0, telegraphed 0.6) — for bots.
func danger_at(p: Vector3) -> float:
	var p2 := Vector2(p.x, p.z)
	var best := 0.0
	for hz in hazards:
		var ph := str(hz["phase"])
		if ph == "idle":
			continue
		var w := 1.0 if ph == "active" else 0.6
		var def: Dictionary = hz["def"]
		match str(hz["type"]):
			"tidal_gutter":
				if arena.strip_rect(def).grow(0.2).has_point(p2):
					best = maxf(best, w)
			"crane_hook":
				if p2.distance_to(hz["data"].get("spot", Vector2(999, 999))) <= float(def.get("radius", 0.75)) + 0.3:
					best = maxf(best, w)
			"plate_grid":
				var cells := arena.grid_cells(def)
				var c := int(hz["data"].get("cell", -1))
				if c >= 0 and (cells[c] as Rect2).has_point(p2):
					best = maxf(best, w)
			"crane_magnet":
				if p2.distance_to(hz["data"].get("pos", Vector2(999, 999))) <= float(def.get("radius", 3.0)):
					best = maxf(best, w * 0.8)
	for rec in props:
		if bool(rec["destroyed"]) or rec["def"].is_empty():
			continue
		var beh := str(rec["def"]["behaviour"])
		if beh == "pit" and ArenaCatalog.footprint_distance(rec["item"], rec["def"], p2) < 0.4:
			best = maxf(best, 1.0)
		elif beh in ["steam_vent", "electric_plate"] and str(rec["phase"]) != "idle":
			if ArenaCatalog.footprint_distance(rec["item"], rec["def"], p2) < (2.0 if beh == "steam_vent" else 0.2):
				best = maxf(best, 1.0 if str(rec["phase"]) == "active" else 0.6)
	if arena.has_open_edges() and arena.edge_distance(p, true) < 0.8:
		best = maxf(best, 0.7)
	return best
