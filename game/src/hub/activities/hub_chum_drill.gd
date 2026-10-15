class_name HubChumDrill
extends RefCounted
## Chum Cannon Dodge Drill (HUB.md §3): Ludlow's pneumatic cannon lobs chum buckets into the
## painted 4 x 4 m square for 45 s, faster and faster. Buckets are physical projectiles simulated
## here (ballistic, aimed at where you are heading). A bucket that reaches you is resolved with the
## real combat checks: dodge i-frames (Fighter.is_evading) let it pass, a parry (guard pressed
## <= 0.12 s before contact, Fighter.in_parry_window) pops it for +5, a front guard
## (Fighter.guards_against) blocks it; otherwise it hits: 3 "drill HP" (never real health), a
## shove and a broken streak. Buckets that miss count as dodged. Leaving the square or running out
## of drill HP ends the drill. Streak tiers 15/30/50 pay 10/25/50 Clout; a 50 streak also unlocks
## the "Soaked" profile frame.

const BUCKET_R := 0.28

var mode
var phase := "idle"            ## idle | countdown | running | done
var t := 0.0
var drill_hp := 30
var streak := 0
var best_streak := 0
var fired := 0
var hits_taken := 0
var parries := 0
var buckets: Array = []        ## [{id, pos, vel, age, flight, resolved}]
var _next_fire := 0.0
var _next_id := 1
var cfg := {}
var result := {}
var _outside_t := 0.0


func _init(m) -> void:
	mode = m
	cfg = HubContent.activity("drill")


func running() -> bool:
	return phase == "countdown" or phase == "running"


func start() -> void:
	phase = "countdown"
	t = 0.0
	drill_hp = int(cfg.get("drill_hp", 30))
	streak = 0
	best_streak = 0
	fired = 0
	hits_taken = 0
	parries = 0
	buckets.clear()
	result = {}
	_outside_t = 0.0
	mode.emit_hub({"type": "hub_activity", "activity": "drill", "phase": "countdown", "seconds": float(cfg.get("countdown", 3.0))})


func time_left() -> float:
	if phase == "countdown":
		return float(cfg.get("duration", 45.0))
	return maxf(0.0, float(cfg.get("duration", 45.0)) - t)


func progress() -> float:
	return clampf(t / float(cfg.get("duration", 45.0)), 0.0, 1.0)


func _interval() -> float:
	return lerpf(float(cfg.get("interval_start", 1.7)), float(cfg.get("interval_end", 0.55)), progress())


func _flight() -> float:
	return lerpf(float(cfg.get("flight_start", 1.25)), float(cfg.get("flight_end", 0.7)), progress())


func tick(dt: float) -> void:
	var f: Fighter = mode.player()
	if phase == "countdown":
		t += dt
		if t >= float(cfg.get("countdown", 3.0)):
			phase = "running"
			t = 0.0
			_next_fire = 0.6
			mode.emit_hub({"type": "hub_activity", "activity": "drill", "phase": "start"})
		return
	if phase != "running":
		return
	t += dt
	# leaving the square (with 1.5 s of grace) ends the drill
	if f and not HubLayout.DRILL_SQUARE.grow(0.35).has_point(Vector2(f.pos().x, f.pos().z)):
		_outside_t += dt
		if _outside_t > 1.5:
			finish("left the square")
			return
	else:
		_outside_t = 0.0
	if t >= _next_fire and t < float(cfg.get("duration", 45.0)) - 0.4 and f:
		_fire(f)
		_next_fire = t + _interval()
	_update_buckets(dt, f)
	if t >= float(cfg.get("duration", 45.0)) and buckets.is_empty():
		finish("time")


func _fire(f: Fighter) -> void:
	var muzzle := HubLayout.CANNON_POS + Vector3(-0.7, 1.2, 0.0)
	var fl := _flight()
	# aim where the fighter will be, with a little spread (seeded by the sim RNG)
	var lead := f.rig.com_velocity() * fl * 0.6
	lead.y = 0.0
	var spread := float(cfg.get("spread", 0.7)) * (0.5 + 0.5 * progress())
	var target := f.pos() + lead + Vector3(mode.sim.rng.randf_range(-spread, spread), 0.0, mode.sim.rng.randf_range(-spread, spread))
	target.y = 1.0
	var sq := HubLayout.DRILL_SQUARE.grow(0.3)
	target.x = clampf(target.x, sq.position.x, sq.end.x)
	target.z = clampf(target.z, sq.position.y, sq.end.y)
	var g: float = mode.sim.gravity
	var vel := Vector3((target.x - muzzle.x) / fl, 0.0, (target.z - muzzle.z) / fl)
	vel.y = (target.y - muzzle.y + 0.5 * g * fl * fl) / fl
	buckets.append({"id": _next_id, "pos": muzzle, "vel": vel, "age": 0.0, "flight": fl, "resolved": false})
	_next_id += 1
	fired += 1
	mode.emit_hub({"type": "hub_bucket", "phase": "fire", "pos": muzzle})


func _update_buckets(dt: float, f: Fighter) -> void:
	var g: float = mode.sim.gravity
	for b in buckets.duplicate():
		var vel: Vector3 = b["vel"]
		vel.y -= g * dt
		var p: Vector3 = b["pos"] + vel * dt
		b["vel"] = vel
		b["pos"] = p
		b["age"] = float(b["age"]) + dt
		if f and not bool(b["resolved"]) and p.distance_squared_to(f.pos()) < 6.0:
			var c: Dictionary = mode.sim.combat.find_contact(p, BUCKET_R, f)
			if not c.is_empty():
				_resolve(b, f, c)
		if p.y <= BUCKET_R * 0.6:
			if not bool(b["resolved"]) or str(b.get("how", "")) == "evaded":
				streak += 1
				best_streak = maxi(best_streak, streak)
				mode.emit_hub({"type": "hub_bucket", "phase": "miss", "pos": Vector3(p.x, 0.05, p.z), "streak": streak})
			else:
				mode.emit_hub({"type": "hub_bucket", "phase": "splat", "pos": Vector3(p.x, 0.05, p.z)})
			buckets.erase(b)
		elif bool(b["resolved"]) and str(b.get("how", "")) != "evaded":
			buckets.erase(b)


func _resolve(b: Dictionary, f: Fighter, c: Dictionary) -> void:
	var from: Vector3 = b["pos"] - (b["vel"] as Vector3).normalized() * 1.0
	if f.is_evading():
		b["resolved"] = true
		b["how"] = "evaded"
		return       # flies through; it counts as dodged when it lands
	if f.in_parry_window() and f.guards_against(from):
		b["resolved"] = true
		b["how"] = "parried"
		parries += 1
		streak += int(cfg.get("parry_bonus", 5))
		best_streak = maxi(best_streak, streak)
		f.gain_hype(Tuning.v("parry_hype"))
		mode.emit_hub({"type": "hub_bucket", "phase": "parry", "pos": c["point"], "streak": streak})
		return
	if f.guards_against(from):
		b["resolved"] = true
		b["how"] = "blocked"
		streak += 1
		best_streak = maxi(best_streak, streak)
		f.spend_stamina(4.0)
		mode.emit_hub({"type": "hub_bucket", "phase": "block", "pos": c["point"], "streak": streak})
		return
	b["resolved"] = true
	b["how"] = "hit"
	hits_taken += 1
	drill_hp -= int(cfg.get("bucket_damage", 3))
	streak = 0
	var push: Vector3 = (b["vel"] as Vector3)
	push.y = 0.0
	f.rig.apply_body_impulse(push.normalized() * 1.6 * f.rig.total_mass)
	f.stagger(int(c["seg"]), 0.6)
	mode.emit_hub({"type": "hub_bucket", "phase": "hit", "pos": c["point"], "drill_hp": drill_hp})
	if drill_hp <= 0:
		finish("drill HP")


func cancel() -> void:
	if running():
		buckets.clear()
		phase = "done"
		result = {"streak": best_streak, "cancelled": true}
		mode.emit_hub({"type": "hub_activity", "activity": "drill", "phase": "cancel"})


func finish(reason: String) -> void:
	if phase == "done":
		return
	phase = "done"
	buckets.clear()
	var rew: Dictionary = mode.state.reward_tiers("drill", float(best_streak), cfg.get("tiers", [15, 30, 50]), cfg.get("clout", [10, 25, 50]), "Chum Cannon drill")
	var frame := ""
	if best_streak >= int(cfg.get("frame_streak", 50)):
		if mode.state.unlock_cosmetic(str(cfg.get("frame", "hub_frame_soaked"))):
			frame = str(cfg.get("frame", "hub_frame_soaked"))
	result = {"streak": best_streak, "fired": fired, "hits": hits_taken, "parries": parries, "drill_hp": drill_hp, "reason": reason,
		"tier": int(rew["tier"]), "new_tier": int(rew["tier"]) > int(rew["previous"]), "clout": int(rew["clout"]), "frame": frame}
	mode.emit_hub({"type": "hub_activity", "activity": "drill", "phase": "end", "result": result})
