extends "res://src/test/kits/kit_sj_helpers.gd"
## SLURRY (f_slurry) kit verification (docs/kits/f_slurry.md, ROSTER §5). Every move connects at
## its intended range against a standing dummy and whiffs outside it, applies its damage /
## knockback / stun / Sludge build-up and properties, obeys guard/parry rules and cooldowns, and
## never tips Slurry over, spins it out, sinks it, pushes it out of the cage or carries an active
## weapon past the 1.6 m reach cap. Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_f_slurry

const ID := "f_slurry"


func _rows() -> Array:
	return [
		{"label": "L1 Head Butt", "string": ["l1"], "steps": [press(T, "light")], "vs": [["f_jitters", 1.3], ["dev_biped", 1.1]],
			"miss": 2.4, "key": "l1", "dmg": [1.5, 8.0], "el": "sludge", "kb": "away"},
		{"label": "L2 Tail Flick", "string": ["l2"], "steps": [press(T, "light")], "vs": [["dev_biped", 1.3], ["f_jitters", 0.9]],
			"miss": 2.4, "key": "l2", "dmg": [1.2, 6.5], "el": "sludge", "kb": "away"},
		{"label": "L3 Fang Snap", "string": ["l3"], "steps": [press(T, "light")], "vs": [["f_jitters", 1.3], ["dev_biped", 1.3]],
			"miss": 2.4, "key": "l3", "dmg": [1.5, 11.0], "el": "sludge", "kb": "pull"},
		{"label": "Heavy Tail Sweep", "steps": [press(T, "heavy")], "vs": [["f_jitters", 1.3], ["dev_biped", 1.5]], "miss": 3.0,
			"key": "heavy", "dmg": [4.0, 19.0], "el": "sludge", "kb": "away", "secs": 3.0},
		{"label": "Charged Heavy Rear & Crash", "steps": [hold(T, T + 0.85, "heavy")], "vs": [["dev_biped", 1.4], ["f_jitters", 1.8]],
			"miss": 2.8, "key": "heavy_charged", "dmg": [6.0, 30.0], "el": "sludge", "kb": "away", "secs": 3.6},
		{"label": "Finisher Venom Spit", "string": ["l1"], "steps": [press(T, "light"), press(T + 0.16, "heavy")],
			"vs": [["dev_biped", 3.0], ["f_jitters", 4.6]], "miss": 6.0, "key": "venom_spit", "dmg": [7.5, 8.5], "el": "sludge", "kb": "away"},
		{"label": "Dash Attack Slither Strike", "steps": [stick(T - 0.05, T + 0.3, "toward"), press(T, "dodge"), press(T + 0.1, "light")],
			"vs": [["f_jitters", 3.0], ["dev_biped", 2.5]], "miss": 4.5, "key": "dash_attack", "dmg": [2.0, 10.0], "el": "sludge", "kb": "away"},
		{"label": "Ability 1 Sludge Lob", "steps": [press(T, "ability1")], "vs": [["dev_biped", 6.0], ["f_jitters", 6.0]], "miss": 11.4,
			"radius": 8.0, "key": "sludge_lob", "dmg": [5.5, 6.5], "el": "sludge", "kb": "away", "secs": 3.0},
		{"label": "Ability 2 Drain Dive", "steps": [stick(T - 0.05, T + 0.8, "toward"), press(T, "ability2")],
			"vs": [["f_jitters", 5.4], ["dev_biped", 5.4]], "miss": 9.0, "radius": 8.0, "key": "drain_emerge", "dmg": [4.5, 5.5], "el": "sludge"},
		{"label": "JUICE Overflow wave", "steps": [press(T, "juice")], "hype": 100.0, "vs": [["dev_biped", 3.0], ["f_jitters", 3.0]],
			"miss": 6.6, "radius": 8.0, "key": "overflow_wave", "dmg": [8.5, 9.6], "el": "sludge", "kb": "away", "secs": 2.0},
	]


## The campaign uses a roster creature as soon as it parses with zero errors.
func test_creature_parses_cleanly() -> void:
	var c := Content.creature(ID)
	if check(c != null, "creature missing"):
		check(c.errors.is_empty(), "parse errors: %s" % str(c.errors))
		for slot in c.light_string:
			check(c.moves.has(str(slot)), "light string slot %s is not defined" % str(slot))
		for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "pummel", "taunt"]:
			check(c.moves.has(slot), "move %s missing" % slot)
		for slot in ["ability1", "ability2", "juice"]:
			check(c.abilities.has(slot), "ability %s missing" % slot)
		for kind in ["throw_fwd", "throw_side", "throw_back"]:
			check(c.throws.has(kind), "throw %s missing" % kind)


func test_moves_connect_in_range_and_whiff_outside() -> void:
	for row in _rows():
		var st := await check_move_row(ID, row)
		var hs := hits(st, 0, str(row["key"]), 1)
		print("  %-28s vs %-10s @%.1f  dmg %5s  part %-5s  kb %+.2f m  max reach %.2f (%s)" % [row["label"], row["vs"][0][0], float(row["vs"][0][1]),
			"%.1f" % float(hs[0]["damage"]) if not hs.is_empty() else "-", str(hs[0]["part"]) if not hs.is_empty() else "-",
			kb_along(st), float(st["max_reach"]), st["reach_weapon"]])


## Grab: Coil connects at 1.2 m and whiffs at 2.2 m; Squeeze pummels are 4 dmg + Sludge 10 at most
## every 0.4 s (3 max); the three throws carry their distances / damage, Gulp-and-Spit adds +30.
func test_coil_grab_pummel_and_throws() -> void:
	# whiff outside the coil reach
	var simw := duel(ID, "dev_biped", 2.2, [press(T, "grab")])
	var stw := await run(simw, 1.6)
	check(events(stw, "grab").is_empty(), "Coil grabbed at 2.2 m (should whiff)")
	check_sane(stw, simw.fighters[0], "Coil whiff")
	simw.queue_free()
	# pummels: Light mashed every 0.1 s while holding
	var sim := duel(ID, "dev_biped", 1.2, [press(T, "grab"), {"t0": T + 0.5, "t1": T + 1.7, "press": ["light"], "every": 0.1}])
	var st := await run(sim, 2.4)
	check(not events(st, "grab").is_empty(), "Coil did not grab at 1.2 m")
	check(st["d_states"].has("held"), "dummy never held")
	var pm := hits(st, 0, "pummel", 1)
	check(pm.size() == 3, "expected 3 pummels (pummel_max), got %d" % pm.size())
	for i in pm.size():
		check_near(float(pm[i]["damage"]), 4.0, 0.3, "Squeeze damage")
		if i > 0:
			var gap_s := (int(pm[i]["tick"]) - int(pm[i - 1]["tick"])) / float(Engine.physics_ticks_per_second)
			check(gap_s >= 0.39, "pummels %.2f s apart (cadence 0.4 s)" % gap_s)
	check(float(st["d_buildup"].get("sludge", 0.0)) >= 25.0 or st["d_statuses"].has("gunked"), "pummels built no Sludge")
	sim.queue_free()
	# throws: forward / side / back by stick direction
	for th in [["throw_fwd", "toward", 10.0, 2.0], ["throw_side", Vector3(1, 0, 0), 9.0, 2.0], ["throw_back", "away", 9.0, 0.4]]:
		var steps := [press(T, "grab"), stick(T + 0.7, T + 0.82, th[1]), press(T + 0.8, "grab")]
		var sim2 := duel(ID, "dev_biped", 1.2, steps)
		var st2 := await run(sim2, 2.6)
		var tev := events(st2, "throw")
		if check(tev.size() == 1, "%s: no throw (events %d)" % [th[0], tev.size()]):
			check_eq(str(tev[0]["kind"]), str(th[0]), "throw kind")
		var thits := hits(st2, 0, "throw", 1)
		if check(thits.size() == 1, "%s: no throw damage" % th[0]):
			check_near(float(thits[0]["damage"]), float(th[2]), 0.4, "%s damage" % th[0])
		var moved := Vector2(sim2.fighters[1].pos().x - float(st2["d_start"].x), sim2.fighters[1].pos().z - float(st2["d_start"].z)).length()
		check(moved >= float(th[3]), "%s: dummy only travelled %.2f m" % [th[0], moved])
		if th[0] == "throw_back":
			check(sim2.fighters[1].pos().z < float(st2["d_start"].z) - 0.3, "Gulp-and-Spit did not drag the target back")
		check(st2["d_states"].has("knockdown") or st2["d_states"].has("down"), "%s: dummy not knocked down" % th[0])
		if th[0] == "throw_back":
			check(float(st2["d_buildup"].get("sludge", 0.0)) >= 29.0 or st2["d_statuses"].has("gunked"), "Gulp-and-Spit: no +30 Sludge")
		check_sane(st2, sim2.fighters[0], str(th[0]))
		sim2.queue_free()


## L3 pull (0.5 m toward Slurry) and Tail Sweep: multi-target, trips (knockdown) Gunked targets only.
func test_tail_sweep_multi_target_and_gunked_trip() -> void:
	var spawns := [[0, -0.7, 0], [0.7, 0.6, 180], [-0.7, 0.6, 180]]
	var sim := duel(ID, "f_jitters", 0.0, [press(T, "heavy")], [], spawns, ["f_jitters"])
	var st := await run(sim, 3.0, "heavy")
	check(not hits(st, 0, "heavy", 1).is_empty() and not hits(st, 0, "heavy", 2).is_empty(),
		"Tail Sweep should hit both dummies (hits: %s)" % _hit_summary(st))
	check_sane(st, sim.fighters[0], "Tail Sweep multi")
	sim.queue_free()
	for gunked in [false, true]:
		var sim2 := duel(ID, "dev_biped", 1.4, [press(T, "heavy")])
		if gunked:
			sim2.fighters[1].statuses.add_buildup("sludge", 100.0, sim2.fighters[0])
			check(sim2.fighters[1].statuses.has("gunked"), "pre-Gunk failed")
		var st2 := await run(sim2, 2.4, "heavy")
		var hs := hits(st2, 0, "heavy", 1)
		check(not hs.is_empty(), "Tail Sweep missed (gunked=%s)" % str(gunked))
		var tripped: bool = st2["d_states"].has("knockdown") or st2["d_states"].has("down")
		check(tripped == gunked, "Tail Sweep trip on Gunked: gunked=%s tripped=%s" % [str(gunked), str(tripped)])
		sim2.queue_free()


## Rear & Crash: armor against Lights during the rear, a Sludge puddle at the impact point, and a
## guard-crushing block (guard drain far above a normal Heavy's).
func test_rear_and_crash_armor_puddle_guard_crush() -> void:
	# armor: the dummy jabs into the rear; Slurry keeps going and lands the crash
	var jabs := {"t0": T + 0.3, "t1": T + 1.3, "press": ["light"], "every": 0.2}
	var sim := duel(ID, "dev_biped", 1.3, [hold(T, T + 0.85, "heavy")], [jabs])
	var st := await run(sim, 3.4, "heavy_charged")
	var took := hits(st, 1, "", 0)
	check(not took.is_empty(), "dummy jabs never reached Slurry during the rear (test setup)")
	check(not hits(st, 0, "heavy_charged", 1).is_empty(), "Rear & Crash was interrupted by Lights (armor)")
	var zones := sim.effects.entities.filter(func(z): return z["kind"] == "zone" and str(z["zone_kind"]) == "sludge_puddle" and int(z["owner"]) == 0)
	if check(zones.size() == 1, "Rear & Crash left %d puddles" % zones.size()):
		check_near(float(zones[0]["radius"]), 1.3, 0.01, "crash puddle radius")
		var zoff: Vector3 = zones[0]["pos"] - sim.fighters[0].pos()
		check(Vector2(zoff.x, zoff.z).length() < 2.6, "crash puddle %.2f m from Slurry" % Vector2(zoff.x, zoff.z).length())
	sim.queue_free()
	# guard crush vs a guarded Tail Sweep
	var drains := {}
	for slot in ["heavy", "heavy_charged"]:
		var steps := [press(T, "heavy")] if slot == "heavy" else [hold(T, T + 0.85, "heavy")]
		var sim2 := duel(ID, "dev_biped", 1.4, steps, [hold(T - 0.2, T + 2.5, "guard")])
		var st2 := await run(sim2, 3.4, slot)
		var hs := hits(st2, 0, slot, 1)
		var blocked := hs.filter(func(h): return bool(h["blocked"]))
		if check(not blocked.is_empty(), "%s was not blocked by a held guard (hits %s)" % [slot, _hit_summary(st2)]):
			drains[slot] = sim2.fighters[1].max_stamina - float(st2["d_min_stamina"])
		sim2.queue_free()
	if drains.size() == 2:
		check(float(drains["heavy_charged"]) >= 30.0 and float(drains["heavy_charged"]) > 3.0 * float(drains["heavy"]),
			"guard-crush drain %.1f vs Tail Sweep %.1f" % [float(drains["heavy_charged"]), float(drains["heavy"])])


## Venom Spit: reflectable, guardable, never parryable (projectile).
func test_venom_spit_reflect_guard_no_parry() -> void:
	var steps := [press(T, "light"), press(T + 0.16, "heavy")]
	var c := creature(ID, ["l1"])
	# reference run: when does the spit land?
	var sim0 := duel(c, "dev_biped", 2.6, steps)
	var st0 := await run(sim0, 1.6, "venom_spit")
	var t_hit := float(st0["hit_t"])
	check(t_hit > 0.0, "reference spit missed")
	sim0.queue_free()
	# reflect
	var sim := duel(c, "dev_biped", 2.6, steps)
	sim.fighters[1].set_flag("reflect", 5.0)
	var st := await run(sim, 1.6)
	check(not events(st, "reflect").is_empty(), "Venom Spit was not reflected")
	check(hits(st, 0, "venom_spit", 1).is_empty(), "reflected spit still hurt the reflector")
	sim.queue_free()
	# guard (held) and a parry-timed press: both just block
	for late in [false, true]:
		var g := hold(T - 0.2, T + 1.5, "guard") if not late else hold(t_hit - 0.06, t_hit + 1.0, "guard")
		var sim2 := duel(c, "dev_biped", 2.6, steps, [g])
		var st2 := await run(sim2, 1.6)
		var hs := hits(st2, 0, "venom_spit", 1)
		var all: Array = st2["hits"].filter(func(h): return str(h.get("move", "")) == "venom_spit")
		check(not all.is_empty() and bool(all[0]["blocked"]) and not bool(all[0]["parried"]),
			"Venom Spit should be blocked, never parried (late=%s, %s)" % [str(late), _hit_summary(st2)])
		check(hs.is_empty() or float(hs[0]["damage"]) < 3.0, "blocked spit dealt full damage")
		sim2.queue_free()


## Lights obey guard (25% damage, blocked) and parry (no damage, attacker staggered, +10 Hype).
func test_head_butt_guard_and_parry() -> void:
	var c := creature(ID, ["l1"])
	var sim0 := duel(c, "f_jitters", 1.4, [press(T, "light")])
	var st0 := await run(sim0, 1.2, "l1")
	var t_hit := float(st0["hit_t"])
	var raw := hits(st0, 0, "l1", 1)
	check(t_hit > 0.0 and not raw.is_empty(), "reference Head Butt missed")
	sim0.queue_free()
	var sim := duel(c, "f_jitters", 1.4, [press(T, "light")], [hold(T - 0.2, T + 1.0, "guard")])
	var st := await run(sim, 1.2)
	var hs: Array = st["hits"].filter(func(h): return int(h.get("fighter", -1)) == 0 and str(h.get("slot", "")) == "l1")
	if check(not hs.is_empty() and bool(hs[0]["blocked"]), "Head Butt into guard was not blocked (%s)" % _hit_summary(st)) and not raw.is_empty():
		check(float(hs[0]["damage"]) <= float(raw[0]["damage"]) * 0.35, "guarded damage %.2f vs %.2f" % [float(hs[0]["damage"]), float(raw[0]["damage"])])
	sim.queue_free()
	var sim2 := duel(c, "f_jitters", 1.4, [press(T, "light")], [hold(t_hit - 0.06, t_hit + 0.6, "guard")])
	var st2 := await run(sim2, 1.2)
	var ps: Array = st2["hits"].filter(func(h): return int(h.get("fighter", -1)) == 0 and bool(h["parried"]))
	check(not ps.is_empty(), "Head Butt was not parried by a guard pressed 0.06 s before impact (%s)" % _hit_summary(st2))
	check(st2["states"].has("hitstun"), "parried Slurry was not staggered")
	check(sim2.fighters[1].hype >= 9.9, "parry Hype %.1f" % sim2.fighters[1].hype)
	sim2.queue_free()


## Slither Strike through Slurry's own puddle: +2 damage and +10 Sludge build-up.
func test_slither_strike_puddle_bonus() -> void:
	var steps := [stick(T - 0.05, T + 0.3, "toward"), press(T, "dodge"), press(T + 0.1, "light")]
	var sim0 := duel(ID, "dev_biped", 3.4, steps)
	var st0 := await run(sim0, 1.4, "dash_attack")
	var h0 := hits(st0, 0, "dash_attack", 1)
	var at: Vector3 = st0["a_at_hit"]
	var d_at: Vector3 = st0["d_at_hit"]
	sim0.queue_free()
	if not check(not h0.is_empty(), "reference Slither Strike missed"):
		return
	# a small puddle under Slurry's root at the moment of impact (the dummy stays outside it)
	var sim := duel(ID, "dev_biped", 3.4, steps)
	var r := clampf(Vector2(d_at.x - at.x, d_at.z - at.z).length() - 0.35, 0.3, 0.8)
	sim.effects.spawn_zone(sim.fighters[0], {"kind": "sludge_puddle", "radius": r, "duration": 6.0, "owner_immune": true}, at)
	var st := await run(sim, 1.4, "dash_attack")
	var h1 := hits(st, 0, "dash_attack", 1)
	if check(not h1.is_empty(), "Slither Strike missed with the puddle"):
		check_near(float(h1[0]["damage"]) - float(h0[0]["damage"]), 2.0, 0.35, "puddle damage bonus")
		var b0 := float(st0["d_buildup"].get("sludge", 0.0))
		var b1 := float(st["d_buildup"].get("sludge", 0.0))
		check(b1 - b0 >= 9.0, "puddle build-up bonus %.1f" % (b1 - b0))
	sim.queue_free()


## Sludge Lob: 2 charges then a 7 s cooldown per charge; the glob leaves a puddle (r 1.3, 5 s)
## that never hurts Slurry (owner immune) but ticks on enemies.
func test_sludge_lob_charges_cooldown_and_puddle() -> void:
	var steps := [press(T, "ability1"), press(T + 0.7, "ability1"), press(T + 1.4, "ability1")]
	var sim := duel(ID, "dev_biped", 12.0, steps, [], [[0, -5.5, 0], [4.0, 3.0, 180]], [], 8.0)
	var f := sim.fighters[0]
	var st := await run(sim, 2.7)
	var used := events(st, "ability", "slot", "ability1")
	check(used.size() == 2, "Sludge Lob fired %d times from 2 charges" % used.size())
	check_eq(int(f.charges_left.get("ability1", -1)), 0, "charges left")
	check(float(f.cooldown_left.get("ability1", 0.0)) > 4.0 and float(f.cooldown_left.get("ability1", 0.0)) <= 7.0,
		"cooldown %.2f" % float(f.cooldown_left.get("ability1", 0.0)))
	var puddles := sim.effects.entities.filter(func(z): return z["kind"] == "zone" and str(z["zone_kind"]) == "sludge_puddle" and int(z["owner"]) == 0)
	check(puddles.size() == 2, "expected 2 lob puddles, got %d" % puddles.size())
	for z in puddles:
		check_near(float(z["radius"]), 1.3, 0.01, "lob puddle radius")
		check_near(float(z["life"]), 5.0, 0.01, "lob puddle duration")
	await run(sim, 5.0)
	check_eq(int(f.charges_left.get("ability1", -1)), 1, "one charge back after 7 s")
	sim.queue_free()
	# owner immunity: Slurry and the dummy both stand in a Slurry puddle for 2 s
	var sim2 := duel(ID, "dev_biped", 1.6, [])
	sim2.effects.spawn_zone(sim2.fighters[0], {"kind": "sludge_puddle", "radius": 1.6, "duration": 5.0, "owner_immune": true}, Vector3.ZERO)
	await run(sim2, 2.2)
	check_eq(sim2.fighters[0].health, sim2.fighters[0].max_health, "Slurry hurt by its own puddle")
	check(sim2.fighters[1].health < sim2.fighters[1].max_health, "the puddle did not tick on the enemy")
	sim2.queue_free()


## Drain Dive: invulnerable while submerged, resurfaces ≤ 4.5 m along the stick, the emerge circle
## launches, and emerging inside Slurry's own puddle refunds 3 s of the 9 s cooldown.
func test_drain_dive_invuln_distance_refund() -> void:
	var steps := [stick(T - 0.05, T + 0.8, "toward"), press(T, "ability2")]
	var jabs := {"t0": T + 0.28, "t1": T + 0.9, "press": ["light"], "every": 0.12}
	var sim := duel(ID, "dev_biped", 1.3, steps, [jabs])
	var f := sim.fighters[0]
	var start := Vector3.ZERO
	var evading_mid := false
	var dt := 1.0 / Engine.physics_ticks_per_second
	if not Engine.is_in_physics_frame():   # step in phase with physics (AGENTS.md, D-026)
		await get_tree().physics_frame
	for i in int(1.6 / dt):
		sim.step(dt)
		await get_tree().physics_frame
		if absf(sim.time - T) < dt * 0.5:
			start = f.pos()
		if absf(sim.time - (T + 0.45)) < dt * 0.5:
			evading_mid = f.is_evading()
	check(evading_mid, "Slurry is not invulnerable mid-dive")
	var hurt := sim.events.filter(func(e): return str(e["type"]) == "hit" and int(e["target"]) == 0 and float(e["damage"]) > 0.0 and int(e["tick"]) * dt > T + 0.25 and int(e["tick"]) * dt < T + 0.68)
	check(hurt.is_empty(), "Slurry was hit while submerged")
	var travel := Vector2(f.pos().x - start.x, f.pos().z - start.z).length()
	check(travel <= 4.7, "dive travelled %.2f m (max 4.5)" % travel)
	sim.queue_free()
	# cooldown refund: emerge inside an own puddle vs not
	var cds := {}
	for in_puddle in [false, true]:
		var sim2 := duel(ID, "dev_biped", 9.0, steps, [], [], [], 8.0)
		var f2 := sim2.fighters[0]
		if in_puddle:
			var dest := f2.pos() + Vector3(0, 0, 4.5)
			sim2.effects.spawn_zone(f2, {"kind": "sludge_puddle", "radius": 1.5, "duration": 6.0, "owner_immune": true}, dest)
		await run(sim2, T + 1.0)
		cds[in_puddle] = float(f2.cooldown_left.get("ability2", 0.0))
		sim2.queue_free()
	check_near(float(cds[false]) - float(cds[true]), 3.0, 0.05, "Drain Dive refund")
	check(float(cds[false]) > 7.5, "dive cooldown %.2f (9 s)" % float(cds[false]))


## Overflow: armored activation, Hype spent, wave, three river puddles (8 s), extra damage on
## Gunked enemies, the state ends after 6 s with the JUICE crash (slowdown).
func test_overflow_juice_activation_and_end() -> void:
	var sim := duel(ID, "dev_biped", 3.0, [press(T, "juice")], [], [], [], 8.0)
	var f := sim.fighters[0]
	var d := sim.fighters[1]
	f.hype = 100.0
	d.statuses.add_buildup("sludge", 100.0, f)
	var st := await run(sim, T + 0.25)
	check(not events(st, "juice").is_empty(), "JUICE did not start at 100 Hype")
	check(f.time < f.armor_until and f.armor_level == "all", "activation not fully armored")
	check(f.time < f.invuln_until, "activation not invulnerable for its first 0.3 s")
	check_eq(f.hype, 0.0, "Hype after activation")
	var st2 := await run(sim, 1.75)
	var puddles := sim.effects.entities.filter(func(z): return z["kind"] == "zone" and str(z["zone_kind"]) == "sludge_puddle" and int(z["owner"]) == 0)
	check(puddles.size() == 3, "Overflow river: %d puddles" % puddles.size())
	for z in puddles:
		check_near(float(z["life"]), 8.0, 0.01, "river duration")
	check(not hits(st2, 0, "overflow_wave", 1).is_empty(), "the wave missed at 3.0 m")
	check(not events(st2, "dot", "status", "overflow_gunk").is_empty(), "Gunked enemy took no Overflow extra damage")
	check(f.has_flag("juiced"), "not juiced 2 s in")
	var st3 := await run(sim, 5.0)
	var ends := events(st3, "juice_end")
	if check(ends.size() == 1, "JUICE did not end"):
		var t_end := int(ends[0]["tick"]) / float(Engine.physics_ticks_per_second)
		check_near(t_end, T + 0.45 + 6.0, 0.1, "JUICE end time")
	check(f.speed_mult() < 0.8, "no JUICE crash slowdown (%.2f)" % f.speed_mult())
	check_sane(st3, f, "Overflow")
	sim.queue_free()


## The Overflow state itself: every Light also spits (3 dmg, Sludge 10, 4 m), Slurry heals while
## touching sludge.
func test_overflow_state_spit_and_heal() -> void:
	var c := creature(ID, ["l1"])
	var js: Dictionary = {}
	for e in c.abilities["juice"].effects:
		if str(e.get("type", "")) == "juice_state":
			js = e
	check(not js.is_empty(), "juice_state effect missing")
	var sim := duel(c, "dev_biped", 3.2, [press(T, "light")])
	var f := sim.fighters[0]
	await run(sim, 0.3)
	f.apply_juice_state(js)
	var st := await run(sim, 1.0)
	var sp := hits(st, 0, "overflow_spit", 1)
	if check(not sp.is_empty(), "a JUICE Light fired no spit (%s)" % _hit_summary(st)):
		check_near(float(sp[0]["damage"]), 3.0 * 1.15, 0.2, "spit damage (JUICE x1.15)")
	check(hits(st, 0, "l1", 1).is_empty(), "the Head Butt itself should whiff at 3.2 m")
	sim.queue_free()
	var sim2 := duel(c, "dev_biped", 4.0, [])
	var f2 := sim2.fighters[0]
	await run(sim2, 0.3)
	f2.apply_juice_state(js)
	sim2.effects.spawn_zone(f2, {"kind": "sludge_puddle", "radius": 1.5, "duration": 6.0, "owner_immune": true}, f2.pos())
	f2.health = 60.0
	await run(sim2, 2.05)
	check_near(f2.health, 64.0, 0.6, "Overflow heal in sludge (2 HP/s)")
	sim2.queue_free()


## Taunt: 1.5 s, +8 Hype, no armor (a jab interrupts it).
func test_taunt() -> void:
	var sim := duel(ID, "dev_biped", 3.0, [press(T, "taunt")])
	var f := sim.fighters[0]
	await run(sim, T + 1.2)
	check_eq(f.state_name(), "taunt", "state 1.1 s into the taunt")
	check_near(f.hype, 8.0, 0.01, "taunt Hype")
	await run(sim, 0.6)
	check(f.state_name() != "taunt", "taunt longer than 1.5 s")
	sim.queue_free()
	var sim2 := duel(ID, "dev_biped", 1.3, [press(T, "taunt")], [{"t0": T + 0.3, "t1": T + 1.0, "press": ["light"], "every": 0.25}])
	var st2 := await run(sim2, T + 1.2)
	check(not hits(st2, 1, "", 0).is_empty(), "dummy never reached the taunting Slurry (setup)")
	check(st2["states"].has("hitstun"), "taunt was not interrupted (it has no armor)")
	sim2.queue_free()


## Bot plays the trapper per the ROSTER AI notes: keeps its distance band and lobs from range.
func test_bot_trapper_uses_kit() -> void:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var arena := ArenaDef.from_dict({"id": "kit_test", "base": "octagon", "radius": 7.0, "spawns": [[0, -3, 0], [0, 3, 180]]})
	var bot := BotBrain.new("pro", 4242)
	var c := Content.creature(ID)
	bot.set_personality(c.ai)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": INTRO}, "seed": 5,
		"fighters": [{"creature": c, "team": 0, "source": bot}, {"creature": Content.creature("dev_biped"), "team": 1, "source": InputSource.Scripted.new([])}]})
	var st := await run(sim, 12.0)
	check(not events(st, "ability", "slot", "ability1").is_empty(), "the Slurry bot never lobbed")
	check(not hits(st, 0, "sludge_lob", 1).is_empty() or not hits(st, 0, "", 1).is_empty(), "the Slurry bot never landed anything")
	sim.queue_free()


## Campaign techniques (content/core/techniques/slurry.json, ROSTER §5) are patches and hooks on
## this kit: every patch lands on a real field and each technique delivers its effect.
func test_campaign_techniques_deliver() -> void:
	var base := creature(ID)
	var tk := {}
	for tid in ["tech_slurry_septic_bloom", "tech_slurry_lockjaw", "tech_slurry_blood_thinner", "tech_slurry_grease_trap",
			"tech_slurry_double_dip", "tech_slurry_hardened_arteries"]:
		var r := technique_kit(ID, tid)
		tk[tid] = r
		var tc: CreatureDef = r["creature"]
		check(tc.errors.is_empty(), "%s: patched kit does not parse: %s" % [tid, str(tc.errors)])
		check(not (r["hits"] as Array).has(0), "%s: a patch missed the kit (targets per patch %s)" % [tid, str(r["hits"])])
	# Septic Bloom: every puddle 50% wider and +2 s (Rear & Crash puddle 1.3 m / 4 s -> 1.95 m / 6 s)
	var sim := duel(ID, "dev_biped", 3.0, [])
	with_mods(sim.fighters[0], tk["tech_slurry_septic_bloom"]["mods"])
	await run(sim, 0.3)
	for e in base.moves["heavy_charged"].effects:
		if str(e.get("type", "")) == "zone":
			sim.effects.fire(sim.fighters[0], e, null)
	var zs := sim.effects.entities.filter(func(z): return z["kind"] == "zone" and int(z["owner"]) == 0)
	if check(zs.size() == 1, "Septic Bloom: %d puddles" % zs.size()):
		check_near(float(zs[0]["radius"]), 1.3 * 1.5, 0.01, "Septic Bloom puddle radius")
		check_near(float(zs[0]["life"]), 4.0 + 2.0, 0.01, "Septic Bloom puddle duration")
	sim.queue_free()
	# Lockjaw: Fang Snap drags far harder (bite pull and delayed yank both x2.4) ...
	var lj: CreatureDef = tk["tech_slurry_lockjaw"]["creature"]
	var pulls := {}
	for which in ["base", "lockjaw"]:
		var c3: CreatureDef = creature(ID, ["l3"]) if which == "base" else technique_kit(ID, "tech_slurry_lockjaw")["creature"]
		c3.light_string = ["l3"]
		var sim3 := duel(c3, "dev_biped", 1.3, [press(T, "light")])
		var st3 := await run(sim3, 1.6, "l3")
		check(not hits(st3, 0, "l3", 1).is_empty(), "%s Fang Snap missed" % which)
		pulls[which] = -kb_along(st3)
		check_sane(st3, sim3.fighters[0], "%s Fang Snap" % which)
		sim3.queue_free()
	check(float(pulls["lockjaw"]) >= 0.6 and float(pulls["lockjaw"]) >= float(pulls["base"]) + 0.45,
		"Lockjaw pull %.2f m (base %.2f m)" % [float(pulls["lockjaw"]), float(pulls["base"])])
	# ... and Coil reaches ~0.2 m further (lunge x1.4): grabs where the base Coil whiffs
	for gc in [["dev_biped", 1.55], ["f_jitters", 1.95]]:
		for which in ["base", "lockjaw"]:
			var sim4 := duel(base if which == "base" else lj, str(gc[0]), float(gc[1]), [press(T, "grab")])
			var st4 := await run(sim4, 1.4)
			var grabbed := not events(st4, "grab").is_empty()
			check(grabbed == (which == "lockjaw"), "%s Coil vs %s at %.2f m: grabbed=%s" % [which, gc[0], float(gc[1]), str(grabbed)])
			check_sane(st4, sim4.fighters[0], "%s Coil" % which)
			sim4.queue_free()
	# Blood Thinner: Gunking adds the extra bleed; blocked hits on Gunked targets let 35% through, not 25%
	var blocked_dmg := {}
	for which in ["base", "thinner"]:
		var c5: CreatureDef = creature(ID, ["l1"]) if which == "base" else technique_kit(ID, "tech_slurry_blood_thinner")["creature"]
		c5.light_string = ["l1"]
		var sim5 := duel(c5, "dev_biped", 1.1, [press(T + 0.3, "light")], [hold(T - 0.3, T + 2.0, "guard")])
		await run(sim5, 0.3)
		sim5.fighters[1].statuses.add_buildup("sludge", 100.0, sim5.fighters[0])
		check(sim5.fighters[1].statuses.has("gunked"), "pre-Gunk failed")
		check(sim5.fighters[1].statuses.has("blood_thinner") == (which == "thinner"), "%s: Blood Thinner bleed present=%s" % [which, str(sim5.fighters[1].statuses.has("blood_thinner"))])
		var st5 := await run(sim5, 1.4, "l1")
		var bl: Array = hits(st5, 0, "l1", 1).filter(func(h): return bool(h["blocked"]))
		if check(not bl.is_empty(), "%s: Head Butt was not blocked (%s)" % [which, _hit_summary(st5)]):
			blocked_dmg[which] = float(bl[0]["damage"])
		sim5.queue_free()
	if blocked_dmg.size() == 2:
		check_near(float(blocked_dmg["thinner"]) / maxf(0.01, float(blocked_dmg["base"])), 1.4, 0.03, "Blood Thinner chip through guard")
	# Grease Trap: all three puddle sources Grease enemies (dodge -40%); Slurry glides in any Sludge zone
	var gt: CreatureDef = tk["tech_slurry_grease_trap"]["creature"]
	var greased := 0
	var zone_specs: Array = [gt.abilities["ability1"].effects[0].get("on_expire", {})]
	for e in gt.moves["heavy_charged"].effects + gt.abilities["juice"].effects:
		if str(e.get("type", "")) == "zone":
			zone_specs.append(e)
	for z in zone_specs:
		var zst: Dictionary = (z as Dictionary).get("status", {})
		if str(zst.get("id", "")) == "grease_trap" and is_equal_approx(float(zst.get("dash", 1.0)), 0.6) and bool(z.get("owner_immune", false)):
			greased += 1
	check_eq(greased, 5, "Greased puddle sources (lob, Rear & Crash, 3x Overflow)")
	var sim6 := duel(gt, "dev_biped", 1.6, [])
	await run(sim6, 0.3)
	for e in gt.moves["heavy_charged"].effects:
		if str(e.get("type", "")) == "zone":
			sim6.effects.fire(sim6.fighters[0], e, null)
	sim6.effects.spawn_zone(null, {"kind": "sludge_puddle", "radius": 0.8, "duration": 3.0}, sim6.fighters[0].pos())
	await run(sim6, 0.6)
	check(sim6.fighters[1].statuses.has("grease_trap"), "the enemy in Slurry's puddle is not Greased")
	check(not sim6.fighters[0].statuses.has("grease_trap"), "Slurry Greased by its own puddle")
	check(sim6.fighters[0].statuses.has("grease_glide"), "Slurry does not glide in a Sludge zone")
	sim6.queue_free()
	# Double Dip: 3 lob charges; Drain Dive emerge 9 dmg in 1.6 m
	var dd: CreatureDef = tk["tech_slurry_double_dip"]["creature"]
	check_eq(int(dd.ability_charges.get("ability1", 0)), 3, "Double Dip lob charges")
	var emerge: Dictionary = (dd.abilities["ability2"].effects[0]["on_emerge"] as Array)[0]
	check_near(float(emerge["damage"]), 9.0, 0.01, "Double Dip emerge damage")
	check_near(float(emerge["radius"]), 1.6, 0.01, "Double Dip emerge radius")
	# Hardened Arteries: poise 80; the dive refund and the Overflow self-heal are gone
	var ha: CreatureDef = tk["tech_slurry_hardened_arteries"]["creature"]
	check_near(ha.stat("poise"), 80.0, 0.01, "Hardened Arteries poise")
	check(ha.passives.filter(func(h): return str(h.get("id", "")) == "slurry_dive_refund").is_empty(), "dive refund still there")
	var heal_hooks := 0
	for e in ha.abilities["juice"].effects:
		for h in e.get("hooks", []):
			if str(h.get("id", "")) == "slurry_overflow_heal":
				heal_hooks += 1
	check_eq(heal_hooks, 0, "Overflow self-heal hooks left")
	check(not base.passives.filter(func(h): return str(h.get("id", "")) == "slurry_dive_refund").is_empty(), "base kit lost its tagged dive refund")
