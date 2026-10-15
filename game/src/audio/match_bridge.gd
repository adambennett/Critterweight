class_name AudioMatchBridge
extends Node
## Reads a local MatchSim every physics tick and feeds the Audio autoload: simulation events
## (through Audio.on_sim_event), footsteps per body plan and surface, zone/projectile loops,
## hover/charge loops, crowd heat and the low-health / timer watchers. It only READS sim state
## (view rule: never changes gameplay). Created by Audio.attach_match(sim, player_index).

const PLAN_CADENCE := {"biped": 0.42, "crab": 0.3, "avian": 0.36, "quadruped": 0.5, "serpent": 0.0, "hopper": 0.55}
const MAX_ZONE_LOOPS := 6

var sim: Node = null
var player_index := 0
var _cursor := 0
var _step_dist := {}            ## fighter index -> distance accumulated since the last step
var _step_count := {}           ## fighter index -> steps (Stoke's belly clank every 4th)
var _drag := {}                 ## fighter index -> loop handle (serpent drag / hover)
var _zone_loops := {}           ## entity id -> {handle, id}
var _proj_loops := {}           ## entity id -> handle
var _surface := "canvas"
var _tick_accum := 0.0
var _was_airborne := {}
var _juice_state := {}


func attach(match_sim: Node, p_index: int) -> void:
	sim = match_sim
	player_index = p_index
	_cursor = int(sim.get("event_seq"))
	var arena = sim.get("arena")
	if arena != null:
		var theme := str(arena.get("theme"))
		var aid := str(arena.get("id"))
		if aid.contains("crusher") or theme == "steel":
			_surface = "steel"
		elif aid.contains("drydock") or theme == "concrete":
			_surface = "concrete"
		elif aid.contains("rooftop") or theme == "tar":
			_surface = "gravel"
		else:
			_surface = "canvas"
	set_physics_process(true)


func _exit_tree() -> void:
	for i in _drag:
		Audio.stop_loop(int(_drag[i]), 0.2)
	for z in _zone_loops:
		Audio.stop_loop(int(_zone_loops[z]["handle"]), 0.3)
	for p in _proj_loops:
		Audio.stop_loop(int(_proj_loops[p]), 0.1)


func _physics_process(dt: float) -> void:
	if sim == null or not is_instance_valid(sim):
		queue_free()
		return
	var fighters: Array = sim.get("fighters")
	var listener := Vector3.ZERO
	if player_index >= 0 and player_index < fighters.size():
		listener = fighters[player_index].pos()
	# events
	var health: Array = []
	for f in fighters:
		health.append(f.health_frac())
	for ev in sim.call("events_since", _cursor):
		_cursor = int(ev["seq"])
		var fi := int(ev.get("fighter", -1))
		var info := {"health": health, "time": float(sim.get("time"))}
		if fi >= 0 and fi < fighters.size():
			var atk: Fighter = fighters[fi]
			info["pos"] = atk.pos()
			if ev.get("type", "") == "hit":
				info["attacker_juiced"] = atk.time < atk.juiced_until
		if ev.get("type", "") == "round_start":
			var mode = sim.get("mode")
			if mode != null:
				var rounds := int(sim.get("rules").get("rounds", 3))
				info["final_round"] = int(ev.get("round", 1)) >= rounds
		Audio.on_sim_event(ev, listener, info)
	# footsteps, drags, hovers
	for f in fighters:
		_footsteps(f, dt)
	# zones and projectiles
	_entity_loops(fighters, listener)
	# watchers (4 Hz)
	_tick_accum += dt
	if _tick_accum >= 0.25:
		var mode2 = sim.get("mode")
		var time_left := -1.0
		if mode2 != null and mode2.get("round_timer") != null and float(sim.get("rules").get("round_time", 99.0)) > 0.0:
			time_left = float(mode2.get("round_timer"))
		Audio.on_match_tick(health, time_left, _tick_accum)
		# music intensity: lead layer when any fighter is below 50 % HP
		var lowest := 1.0
		for h in health:
			if float(h) > 0.0:
				lowest = minf(lowest, float(h))
		Audio.music_intensity(clampf((0.5 - lowest) / 0.35, 0.0, 1.0))
		_tick_accum = 0.0


func _footsteps(f: Fighter, dt: float) -> void:
	var i := f.index
	var pal := Audio.creature_audio(f.creature.id)
	var plan := str(pal.get("plan", f.creature.body.gait))
	var state := f.state_name()
	var vel := f.rig.com_velocity()
	var speed := Vector2(vel.x, vel.z).length()
	var pos := f.ground_pos()
	var moving: bool = speed > 0.6 and state in ["neutral", "guard", "attack", "ability", "grabbing"] and f.rig.grounded
	if plan == "serpent":
		var h := int(_drag.get(i, 0))
		if moving and h == 0:
			_drag[i] = Audio.sfx_loop("drag_serpent_" + _surface, pos)
		elif h != 0:
			if not moving or not Audio.is_playing(h):
				Audio.stop_loop(h, 0.15)
				_drag.erase(i)
			else:
				Audio.set_loop_pos(h, pos)
				Audio.set_loop_volume(h, clampf((speed - 0.6) * 4.0, -12.0, 0.0), 0.1)
				if randf() < dt * 1.5:
					Audio.sfx(str(pal.get("drip", "serpent_drip")), pos)
		return
	var airborne: bool = not f.rig.grounded or bool(f.flags.get("leaping", false))
	if plan == "hopper":
		if airborne and not bool(_was_airborne.get(i, false)):
			Audio.sfx("hop_takeoff", pos)
		elif not airborne and bool(_was_airborne.get(i, false)):
			Audio.sfx(str(pal.get("land", "hop_land_" + _surface)), pos)
		_was_airborne[i] = airborne
		return
	if plan == "avian" and state == "dodge":
		if randf() < dt * 6.0:
			Audio.sfx("flap", pos)
	if not moving:
		_step_dist[i] = 0.0
		return
	var cadence := float(PLAN_CADENCE.get(plan, 0.42)) * f.creature.body.scale
	var d := float(_step_dist.get(i, 0.0)) + speed * dt
	if d >= cadence:
		d -= cadence
		var n := int(_step_count.get(i, 0)) + 1
		_step_count[i] = n
		var sid := "step_%s_%s" % [plan, _surface]
		Audio.sfx(sid if Audio.has_sfx(sid) else "step_biped_" + _surface, pos, 0.0, 1.0)
		var extra := str(pal.get("step_extra", ""))
		if extra != "" and n % 4 == 0:
			Audio.sfx(extra, pos)
		if plan == "quadruped" and _surface == "gravel":
			Audio.sfx("gravel_scatter", pos, -6.0)
	_step_dist[i] = d


func _entity_loops(fighters: Array, listener: Vector3) -> void:
	var effects = sim.get("effects")
	if effects == null:
		return
	var ents: Array = effects.get("entities")
	var seen := {}
	var zones: Array = []
	for ent in ents:
		var eid := int(ent["id"])
		seen[eid] = true
		if str(ent["kind"]) == "zone":
			zones.append(ent)
		else:
			var el := str(ent.get("element", ""))
			var lid := "proj_loop_" + el
			if not Audio.has_sfx(lid):
				continue
			if not _proj_loops.has(eid):
				_proj_loops[eid] = Audio.sfx_loop(lid, ent["pos"])
			else:
				Audio.set_loop_pos(int(_proj_loops[eid]), ent["pos"])
	# nearest zones only (max 6 audible)
	zones.sort_custom(func(a, b): return (a["pos"] as Vector3).distance_squared_to(listener) < (b["pos"] as Vector3).distance_squared_to(listener))
	var audible := {}
	for k in mini(zones.size(), MAX_ZONE_LOOPS):
		var z: Dictionary = zones[k]
		var zid := int(z["id"])
		audible[zid] = true
		var vfx := str(z.get("vfx", ""))
		var el2 := str(z.get("element", ""))
		var lid2 := "zone_" + vfx
		if not Audio.has_sfx(lid2):
			lid2 = "zone_" + el2
		if not Audio.has_sfx(lid2):
			lid2 = "zone_steam"
		if not _zone_loops.has(zid):
			_zone_loops[zid] = {"handle": Audio.sfx_loop(lid2, z["pos"]), "id": lid2}
		else:
			Audio.set_loop_pos(int(_zone_loops[zid]["handle"]), z["pos"])
	for zid2 in _zone_loops.keys():
		if not seen.has(zid2) or not audible.has(zid2):
			Audio.stop_loop(int(_zone_loops[zid2]["handle"]), 0.3)
			_zone_loops.erase(zid2)
	for pid in _proj_loops.keys():
		if not seen.has(pid):
			Audio.stop_loop(int(_proj_loops[pid]), 0.08)
			_proj_loops.erase(pid)
