extends "res://src/test/kits/kit_sj_helpers.gd"
## Unit tests for the small generic engine extensions added for the Slurry / Jitters kits (all
## data-driven, none keyed to a fighter id): hooks "emerge" event (with main's cooldown action, the
## Drain Dive refund) and the "hit_part" condition the Bonk relies on; kit trait stats
## getup_speed / held_time (stacking with run mods);
## Fighter.is_airborne(); charge bounce; debuff.require_status; projectile burst_on_hit and lob
## arrive_y; spring pads ignore airborne fighters; keyed joints skip the gait wave; "ballistic"
## leaps / launches are not ground-braked; the extra bot kit hints (range_needs_tools, ability
## "stick", heavy_vs_windup, avoid_zones) on top of the shared kit-hint mechanism.


func _pair(a = "dev_biped", b = "dev_biped", gap := 2.0) -> MatchSim:
	return duel(a, b, gap, [], [], [], [], 7.0)


func test_hook_emerge_event() -> void:
	var sim := _pair()
	await run(sim, 0.3)
	var f := sim.fighters[0]
	f.hooks.add({"on": "emerge", "do": [{"type": "cooldown", "slot": "ability2", "add": -3.0}]}, "test")
	f.cooldown_left["ability2"] = 5.0
	f.charges_left["ability2"] = 0
	var cursor := sim.event_seq
	f.begin_submerge(f.pos() + Vector3(0, 0, 1.0), 0.2, [])
	await run(sim, 0.1)
	check_near(float(f.cooldown_left["ability2"]), 5.0 - 0.1, 0.02, "emerge fired before the fighter resurfaced")
	await run(sim, 0.2)
	check_near(float(f.cooldown_left["ability2"]), 5.0 - 0.3 - 3.0, 0.02, "emerge refund")
	check(not sim.events_since(cursor).filter(func(e): return str(e["type"]) == "submerge").is_empty(), "no submerge event")
	check(Hooks.validate({"on": "emerge", "do": [{"type": "cooldown", "slot": "ability1", "add": -1}]}).is_empty(), "emerge hook rejected")
	sim.queue_free()


func test_hook_hit_part_condition() -> void:
	var sim := _pair()
	var f := sim.fighters[0]
	var h := {"if": {"hit_part": "head"}, "do": [{"type": "damage_add", "amount": 3.0}]}
	var head_hit := {"part": "head", "damage": 10.0}
	var core_hit := {"part": "core", "damage": 10.0}
	f.hooks.run_inline(h, {"hit": head_hit})
	f.hooks.run_inline(h, {"hit": core_hit})
	check_eq(float(head_hit["damage"]), 13.0, "head hit bonus")
	check_eq(float(core_hit["damage"]), 10.0, "core hit untouched")
	f.hooks.run_inline(h, {})
	sim.queue_free()


## Kit trait stats getup_speed / held_time parse like any stat and multiply with the run/rules
## mods of the same name. A campaign spawn entry REPLACES Fighter.mods values, so a technique such
## as Rubber Core (getup_speed x1.5) must stack with the kit's own trait instead of overwriting it.
func test_kit_trait_stats() -> void:
	var d: Dictionary = Content.creature_entry("dev_biped").duplicate(true)
	var stt: Dictionary = d.get("stats", {})
	stt["getup_speed"] = 1.3
	stt["held_time"] = 0.7
	d["stats"] = stt
	var c := CreatureDef.from_dict(d)
	check(c.is_valid(), "trait stats rejected: %s" % str(c.errors))
	check_near(c.stat("getup_speed"), 1.3, 1e-6, "parsed getup_speed")
	var plain := Content.creature("dev_biped")
	check_near(plain.stat("getup_speed"), 1.0, 1e-6, "default getup_speed")
	check_near(plain.stat("held_time"), 1.0, 1e-6, "default held_time")
	var sim := duel(c, "dev_biped", 2.0, [])
	var f := sim.fighters[0]
	check_near(f.getup_speed_mult(), 1.3, 1e-6, "kit get-up trait")
	check_near(f.held_time_mult(), 0.7, 1e-6, "kit hold trait")
	f.mods["getup_speed"] = 1.5          # what a campaign spawn entry writes for Rubber Core
	f.mods["held_time_mult"] = 1.2
	check_near(f.getup_speed_mult(), 1.95, 1e-6, "get-up trait stacks with a run mod")
	check_near(f.held_time_mult(), 0.84, 1e-6, "hold trait stacks with a run mod")
	check_near(sim.fighters[1].getup_speed_mult(), 1.0, 1e-6, "plain fighter unchanged")
	sim.queue_free()




func test_airborne_flag_and_spring_pad_skip() -> void:
	var sim := _pair("dev_biped", "dev_biped", 4.0)
	await run(sim, 0.3)
	var f := sim.fighters[0]
	check(not f.is_airborne(), "grounded fighter reported airborne")
	f.begin_airborne([], 0.6)
	check(f.is_airborne(), "is_airborne false during a leap")
	sim.effects.fire(f, {"type": "prop", "prop": "spring_pad", "at": "self", "radius": 1.0, "duration": 5.0, "launch_up": 2.0, "launch_forward": 0.0}, null)
	var st := await run(sim, 0.3)
	check(events(st, "spring", "fighter", 0).is_empty(), "a pad launched an airborne fighter")
	var st2 := await run(sim, 1.5)
	var landed := events(st2, "land", "fighter", 0)
	var sprung := events(st2, "spring", "fighter", 0)
	if check(not landed.is_empty() and not sprung.is_empty(), "expected a landing then a pad launch (%d / %d)" % [landed.size(), sprung.size()]):
		check(int(sprung[0]["tick"]) >= int(landed[0]["tick"]), "the pad launched the fighter before it landed")
	sim.queue_free()


func test_charge_bounce() -> void:
	var sim := _pair("dev_biped", "dev_biped", 4.0)
	await run(sim, 0.3)
	var f := sim.fighters[0]
	var tgt := sim.fighters[1]
	f.facing_yaw = PI * 0.5
	f._charge = {"speed": 7.0, "dist": 2.0, "max": 3.0, "bounce": 1, "bounce_distance": 1.2}
	var cursor := sim.event_seq
	check(f._charge_bounce(), "first wall contact not consumed by the bounce")
	var to := tgt.pos() - f.pos()
	to.y = 0.0
	check(f.forward().dot(to.normalized()) > 0.99, "bounce did not turn toward the target")
	check_eq(float(f._charge["dist"]), 0.0, "leg distance reset")
	check_near(float(f._charge["max"]), 1.2, 1e-6, "second leg length")
	check(sim.events_since(cursor).any(func(e): return str(e["type"]) == "bounce"), "no bounce event")
	check(not f._charge_bounce(), "bounced twice with bounce = 1")
	# no target: reflect off the fence (heading outward along +Z comes back inward)
	f.target = null
	f.facing_yaw = 0.0
	f._charge = {"speed": 7.0, "dist": 0.5, "max": 3.0, "bounce": 1, "bounce_distance": 1.0}
	f.rig.place(Vector3(0, f.rig.ground_y, 5.5), 0.0)
	check(f._charge_bounce(), "targetless bounce failed")
	check(f.forward().z < -0.5, "targetless bounce did not reflect inward (%s)" % str(f.forward()))
	f._charge = {}
	sim.queue_free()


func test_debuff_require_status() -> void:
	var sim := _pair("dev_biped", "dev_biped", 2.0)
	await run(sim, 0.3)
	var f := sim.fighters[0]
	var o := sim.fighters[1]
	var e := {"type": "debuff", "radius": 10.0, "require_status": "gunked", "status": {"id": "kit_test_debuff", "duration": 2.0}}
	sim.effects.fire(f, e, null)
	check(not o.statuses.has("kit_test_debuff"), "debuff ignored require_status")
	o.statuses.add_buildup("sludge", 100.0, f)
	check(o.statuses.has("gunked"), "setup: gunk failed")
	sim.effects.fire(f, e, null)
	check(o.statuses.has("kit_test_debuff"), "debuff missed a target carrying the status")
	sim.queue_free()


func test_projectile_burst_on_hit_option() -> void:
	for burst in [true, false]:
		var sim := _pair("dev_biped", "dev_biped", 3.0)
		await run(sim, 0.3)
		var e := {"type": "projectile", "id": "kit_test_orb", "aim": "target", "speed": 8.0, "life": 1.0, "radius": 0.2, "damage": 2.0,
			"on_expire": {"type": "area", "id": "kit_test_burst", "radius": 1.0, "damage": 1.0}}
		if not burst:
			e["burst_on_hit"] = false
		sim.effects.fire(sim.fighters[0], e, null)
		var st := await run(sim, 1.2)
		check(not hits(st, 0, "kit_test_orb", 1).is_empty(), "orb missed (burst=%s)" % str(burst))
		check(hits(st, 0, "kit_test_burst", 1).is_empty() != burst, "burst_on_hit=%s: on_expire after a fighter hit = %s" % [str(burst), str(not hits(st, 0, "kit_test_burst", 1).is_empty())])
		sim.queue_free()
	# a timed-out orb still bursts with burst_on_hit = false
	var sim2 := _pair("dev_biped", "dev_biped", 6.0)
	await run(sim2, 0.3)
	sim2.effects.fire(sim2.fighters[0], {"type": "projectile", "id": "kit_test_orb", "aim": "target", "speed": 4.0, "life": 0.5, "radius": 0.2,
		"damage": 2.0, "burst_on_hit": false, "on_expire": {"type": "area", "id": "kit_test_burst", "radius": 1.0, "damage": 1.0}}, null)
	var cursor := sim2.event_seq
	await run(sim2, 0.8)
	check(sim2.events_since(cursor).any(func(ev): return str(ev["type"]) == "effect" and str(ev["effect"]) == "area"), "timeout burst missing")
	sim2.queue_free()


func test_lob_arrive_height() -> void:
	var sim := _pair("dev_biped", "dev_biped", 5.0)
	await run(sim, 0.3)
	var f := sim.fighters[0]
	var o := sim.fighters[1]
	o.invuln_until = 99.0   # let the glob fly through the target point
	sim.effects.fire(f, {"type": "projectile", "id": "kit_test_lob", "lob": true, "range": 9.0, "speed": 8.0, "radius": 0.2, "life": 3.0,
		"arrive_y": 0.45, "damage": 1.0}, null)
	var tp := o.pos()
	var best := 99.0
	var y_at := -1.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in int(1.2 / dt):
		sim.step(dt)
		await get_tree().physics_frame
		for ent in sim.effects.entities:
			if str(ent["kind"]) == "projectile":
				var p: Vector3 = ent["pos"]
				var d := Vector2(p.x - tp.x, p.z - tp.z).length()
				if d < best:
					best = d
					y_at = p.y - f.rig.ground_y
	check(best < 0.2, "the lob never crossed the target point (closest %.2f m)" % best)
	check_near(y_at, 0.45, 0.12, "lob height over the target point")
	sim.queue_free()


func test_keyed_joints_skip_gait_wave() -> void:
	var sim := duel("f_slurry", "dev_biped", 4.0, [])
	await run(sim, 0.4)
	var f := sim.fighters[0]
	var si: int = f.creature.body.seg_index["body2"]
	var parent: int = f.creature.body.segments[si].parent
	var rel := func() -> Quaternion:
		return f.rig.bodies[parent].global_basis.get_rotation_quaternion().inverse() * f.rig.target_rot[si]
	for keyed in [false, true]:
		if keyed:
			f.motor.overlay_joints[si] = Quaternion.IDENTITY
		else:
			f.motor.overlay_joints.erase(si)
		f.motor._wave_phase = 0.0
		f.motor.update(0.0)
		var q0: Quaternion = rel.call()
		f.motor._wave_phase = 1.3
		f.motor.update(0.0)
		var q1: Quaternion = rel.call()
		var moved := q0.angle_to(q1)
		if keyed:
			check(moved < 0.01, "keyed joint still waved (%.3f rad)" % moved)
		else:
			check(moved > 0.02, "serpent core joint did not wave (%.3f rad)" % moved)
	f.motor.overlay_joints.erase(si)
	sim.queue_free()


func test_ballistic_flights_not_ground_braked() -> void:
	var speeds := {}
	for ballistic in [false, true]:
		var sim := _pair("dev_biped", "dev_biped", 6.0)
		await run(sim, 0.4)
		var f := sim.fighters[0]
		if ballistic:
			f.begin_airborne([], 0.6)
			f.rig.ballistic = true
			f.rig.apply_body_impulse(Vector3(3.0, 2.5, 0.0) * f.rig.total_mass)
		else:
			f.rig.apply_body_impulse(Vector3(3.0, 0.0, 0.0) * f.rig.total_mass)
		await run(sim, 0.2)
		var v := f.rig.com_velocity()
		speeds[ballistic] = Vector2(v.x, v.z).length()
		sim.queue_free()
	check(float(speeds[true]) > 2.4, "ballistic body was braked (%.2f m/s)" % float(speeds[true]))
	check(float(speeds[true]) > float(speeds[false]) + 0.5, "grounded drive did not brake (%.2f vs %.2f)" % [float(speeds[false]), float(speeds[true])])
	# the leap option sets the flag for the flight only; landing clears it; leaps without it keep the old rule
	var sim2 := _pair("dev_biped", "dev_biped", 4.0)
	await run(sim2, 0.4)
	var f2 := sim2.fighters[0]
	sim2.effects.fire(f2, {"type": "leap", "distance": 1.0, "height": 0.3, "to_target": true, "ballistic": true}, null)
	check(f2.rig.ballistic and f2.is_airborne(), "a ballistic leap did not set the flag")
	await run(sim2, 1.2)
	check(not f2.is_airborne() and not f2.rig.ballistic, "landing did not clear the ballistic flag")
	sim2.effects.fire(f2, {"type": "leap", "distance": 1.0, "height": 0.3, "to_target": true}, null)
	check(not f2.rig.ballistic, "a plain leap became ballistic")
	sim2.queue_free()


func _bot_on(_sim: MatchSim, personality: Dictionary) -> BotBrain:
	var bot := BotBrain.new("champion", 99)
	bot.set_personality(personality)
	bot.p["ability"] = 1.0
	bot.p["aggression"] = 1.0
	bot.p["spacing"] = 1.0
	bot._next_think = 1e9
	return bot


func test_bot_kit_hints() -> void:
	var sim := _pair("dev_biped", "dev_biped", 3.0)
	await run(sim, 0.3)
	var f := sim.fighters[0]
	var tgt := sim.fighters[1]
	var dir := (tgt.pos() - f.pos())
	dir.y = 0.0
	var dist := dir.length()
	dir = dir / dist
	var bot0 := _bot_on(sim, {"attack_range": 1.4})
	# ability hint inside its band (and only there)
	var bot := _bot_on(sim, {"abilities": {"ability1": {"min": 1.0, "max": 6.0, "chance": 1000.0}}})
	var n0 := int(f.input.press_count[FighterInput.AB1])
	check(bot._kit_ability(f, tgt, dist, dir, {}, false), "ability hint did not fire in its band")
	check_eq(int(f.input.press_count[FighterInput.AB1]), n0 + 1, "AB1 press")
	check(not bot._kit_ability(f, tgt, 9.0, dir, {}, false), "ability hint fired out of its band")
	# poise gate + "stick": "away" (a dive away when poise is low)
	var bot2 := _bot_on(sim, {"abilities": {"ability2": {"max": 6.0, "chance": 1000.0, "when": [{"self_poise_below": 0.4}], "stick": "away"}}})
	check(not bot2._kit_ability(f, tgt, dist, dir, {}, false), "poise gate ignored at full poise")
	f.poise = f.effective_max_poise() * 0.2
	check(bot2._kit_ability(f, tgt, dist, dir, {}, false), "poise-gated hint did not fire at low poise")
	check(bot2._move.dot(dir) < -0.99 and bot2._kit_hold_until > bot2._t, "stick away was not committed")
	f.poise = f.effective_max_poise()
	# heavy against a long windup
	var bot3 := _bot_on(sim, {"heavy_vs_windup": 1.0, "heavy_reach": 4.0})
	var nh := int(f.input.press_count[FighterInput.HEAVY])
	check(bot3._kit_heavy_vs_windup(f, dist, {"state": Fighter.State.ATTACK, "first": 0.7, "st": 0.1}), "heavy_vs_windup ignored a long windup")
	check_eq(int(f.input.press_count[FighterInput.HEAVY]), nh + 1, "Heavy press")
	check(not bot3._kit_heavy_vs_windup(f, dist, {"state": Fighter.State.ATTACK, "first": 0.3, "st": 0.1}), "heavy_vs_windup fired on a short windup")
	check(not bot0._kit_heavy_vs_windup(f, dist, {"state": Fighter.State.ATTACK, "first": 0.7, "st": 0.1}), "heavy_vs_windup without the hint")
	sim.queue_free()


func test_bot_avoid_zones_hint() -> void:
	var sim := _pair("dev_biped", "dev_biped", 3.0)
	await run(sim, 0.3)
	var f := sim.fighters[0]
	var foe := sim.fighters[1]
	var dir := (foe.pos() - f.pos()).normalized()
	var bot := _bot_on(sim, {"avoid_zones": true})
	var plain := _bot_on(sim, {})
	check(not bot._kit_avoid_zone(f, sim, dir), "no zone, yet avoidance fired")
	sim.effects.spawn_zone(foe, {"kind": "sludge_puddle", "radius": 1.0, "duration": 5.0}, f.pos() + Vector3(0.3, 0, 0))
	check(bot._kit_avoid_zone(f, sim, dir), "standing in an enemy puddle, no avoidance")
	check(bot._move.x < 0.0, "avoidance did not step out of the puddle (%s)" % str(bot._move))
	check(not plain._kit_avoid_zone(f, sim, dir), "avoidance without the hint")
	sim.queue_free()


func test_bot_range_needs_tools_hint() -> void:
	var sim := _pair()
	await run(sim, 0.3)
	var f := sim.fighters[0]
	var bot := _bot_on(sim, {"range": [3.0, 5.0], "range_needs_tools": true,
		"abilities": {"ability1": {"min": 2.5, "max": 9.0}, "ability2": {"min": 0.0, "max": 2.0}}})
	check(bot._kit_range_ready(f), "range dropped while a ranged tool is ready")
	f.charges_left["ability1"] = 0
	check(not bot._kit_range_ready(f), "range held with every ranged tool on cooldown (a melee-range hint must not count)")
	var bot2 := _bot_on(sim, {"range": [0.7, 1.4]})
	check(bot2._kit_range_ready(f), "a range without range_needs_tools must always hold")
	sim.queue_free()
