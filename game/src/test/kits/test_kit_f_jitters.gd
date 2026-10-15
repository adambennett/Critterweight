extends "res://src/test/kits/kit_sj_helpers.gd"
## JITTERS (f_jitters) kit verification (docs/kits/f_jitters.md, ROSTER §6). Every move connects at
## its intended range against standing dummies and whiffs outside it, applies its damage /
## knockback / stun / Static build-up and properties, obeys guard/parry rules and cooldowns, and
## never tips Jitters over, spins it out, sinks it, pushes it out of the cage or carries an active
## weapon past the 1.6 m reach cap. Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_f_jitters

const ID := "f_jitters"
const POWER := 1.25          ## Jitters' power stat (effect damage scales with it)


func _rows() -> Array:
	return [
		{"label": "L1 Slap", "string": ["l1"], "steps": [press(T, "light")], "vs": [["dev_biped", 0.8], ["f_slurry", 0.8]],
			"miss": 1.6, "key": "l1", "dmg": [1.5, 7.0], "el": "static", "kb": "away"},
		{"label": "L2 Double Slap", "string": ["l2"], "steps": [press(T, "light")], "vs": [["dev_biped", 0.8], ["f_slurry", 0.8]],
			"miss": 1.6, "key": "l2", "dmg": [1.5, 7.0], "el": "static", "kb": "away"},
		{"label": "L3 Headbonk", "string": ["l3"], "steps": [press(T, "light")], "vs": [["f_slurry", 1.1], ["dev_biped", 0.9]],
			"miss": 2.2, "key": "l3", "dmg": [2.5, 12.0], "el": "static", "kb": "away"},
		{"label": "Heavy Squash", "steps": [press(T, "heavy")], "vs": [["dev_biped", 1.5], ["f_slurry", 2.0]], "miss": 3.2,
			"key": "heavy", "dmg": [4.0, 25.0], "el": "static", "secs": 2.2},
		{"label": "Charged Heavy Super Squash", "steps": [hold(T, T + 0.85, "heavy")], "vs": [["f_slurry", 2.5], ["dev_biped", 2.0]],
			"miss": 4.4, "key": "heavy_charged", "dmg": [4.0, 34.0], "el": "static", "secs": 3.2},
		{"label": "Finisher Static Cling", "string": ["l1"], "steps": [press(T, "light"), press(T + 0.13, "heavy")],
			"vs": [["dev_biped", 1.1], ["f_slurry", 1.1]], "miss": 2.3, "key": "static_cling", "dmg": [9.0 * POWER - 0.1, 9.0 * POWER + 0.1], "el": "static"},
		{"label": "Dash Attack Pinball", "steps": [stick(T - 0.05, T + 0.3, "toward"), press(T, "dodge"), press(T + 0.1, "light")],
			"vs": [["f_slurry", 3.0], ["dev_biped", 2.5]], "miss": 4.6, "key": "dash_attack", "dmg": [3.0, 12.0], "el": "static", "kb": "away"},
		{"label": "Ability 1 Arc Lash", "steps": [press(T, "ability1")], "vs": [["dev_biped", 5.0], ["f_slurry", 5.0]], "miss": 10.6,
			"radius": 8.0, "key": "arc_lash", "dmg": [6.0 * POWER - 0.1, 6.0 * POWER + 0.1], "el": "static", "kb": "away", "secs": 2.8},
		{"label": "JUICE Overcharge burst", "steps": [press(T, "juice")], "hype": 100.0, "vs": [["dev_biped", 2.6], ["f_slurry", 2.6]],
			"miss": 3.8, "key": "overcharge_burst", "dmg": [10.0 * POWER * 1.15 - 0.1, 10.0 * POWER * 1.15 + 0.1], "el": "static", "kb": "away", "secs": 1.6},
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


## Headbonk bounces Jitters back off the target (safe spacing).
func test_headbonk_bounces_back() -> void:
	var sim := duel(creature(ID, ["l3"]), "f_slurry", 1.1, [press(T, "light")])
	var st := await run(sim, 1.6, "l3")
	if check(not hits(st, 0, "l3", 1).is_empty(), "Headbonk missed"):
		check(attacker_back(st) > 0.25, "Headbonk did not bounce Jitters back (%.2f m)" % attacker_back(st))
	sim.queue_free()


## Squash: the slam hits, then the landing circle (r 1.0, 4 dmg, Static 10) catches anyone near the
## landing point even when the slam itself whiffs.
func test_squash_landing_circle() -> void:
	var sim := duel(ID, "dev_biped", 1.5, [press(T, "heavy")])
	var st := await run(sim, 2.2, "heavy")
	check(not hits(st, 0, "heavy", 1).is_empty(), "Squash slam missed at 1.5 m")
	var land := hits(st, 0, "squash_landing", 1)
	if check(not land.is_empty(), "Squash landing circle missed (%s)" % _hit_summary(st)):
		check_near(float(land[0]["damage"]), 4.0 * POWER, 0.05, "landing damage")
	check(not events(st, "land").is_empty(), "Squash never landed")
	check_sane(st, sim.fighters[0], "Squash")
	sim.queue_free()
	var sim2 := duel(ID, "dev_biped", 2.8, [press(T, "heavy")])
	var st2 := await run(sim2, 2.2)
	check(hits(st2, 0, "heavy", 1).is_empty(), "Squash slam should whiff at 2.8 m")
	check(not hits(st2, 0, "squash_landing", 1).is_empty(), "the landing circle should still catch a target 2.8 m away")
	sim2.queue_free()


## Super Squash: knock-up (launch), guard-crush, bigger landing circle; no armor (airborne).
func test_super_squash_launch_crush_landing() -> void:
	var c := creature(ID)
	check(c.moves["heavy_charged"].armor.is_empty(), "Super Squash must not carry armor (airborne)")
	var sim := duel(ID, "f_slurry", 2.5, [hold(T, T + 0.85, "heavy")])
	var st := await run(sim, 3.2, "heavy_charged")
	check(not hits(st, 0, "heavy_charged", 1).is_empty(), "Super Squash missed")
	check(float(st["d_max_y"]) > float(st["d_start"].y) + 0.25, "no knock-up (dummy rose %.2f m)" % (float(st["d_max_y"]) - float(st["d_start"].y)))
	check(not hits(st, 0, "super_squash_landing", 1).is_empty(), "Super Squash landing circle missed")
	sim.queue_free()
	var drains := {}
	for slot in ["heavy", "heavy_charged"]:
		var steps := [press(T, "heavy")] if slot == "heavy" else [hold(T, T + 0.85, "heavy")]
		var sim2 := duel(ID, "dev_biped", 1.5 if slot == "heavy" else 2.0, steps, [hold(T - 0.2, T + 2.6, "guard")])
		var st2 := await run(sim2, 3.2, slot)
		var blocked: Array = hits(st2, 0, slot, 1).filter(func(h): return bool(h["blocked"]))
		if check(not blocked.is_empty(), "%s was not blocked by a held guard (%s)" % [slot, _hit_summary(st2)]):
			drains[slot] = sim2.fighters[1].max_stamina - float(st2["d_min_stamina"])
		sim2.queue_free()
	if drains.size() == 2:
		check(float(drains["heavy_charged"]) >= 30.0 and float(drains["heavy_charged"]) > 3.0 * float(drains["heavy"]),
			"guard-crush drain %.1f vs Squash %.1f" % [float(drains["heavy_charged"]), float(drains["heavy"])])


## Static Cling: if the discharge triggers Jolted, Jitters gains +10 Hype on top of the hit's Hype.
func test_static_cling_jolt_hype() -> void:
	var gains := {}
	for primed in [false, true]:
		var sim := duel(creature(ID, ["l1"]), "dev_biped", 1.1, [press(T, "light"), press(T + 0.13, "heavy")])
		if primed:
			sim.fighters[1].statuses.add_buildup("static", 70.0, null)
		var st := await run(sim, 1.4, "static_cling")
		check(not hits(st, 0, "static_cling", 1).is_empty(), "Static Cling missed (primed=%s)" % str(primed))
		if primed:
			check(st["d_statuses"].has("jolted"), "Static Cling did not trigger Jolted")
		gains[primed] = sim.fighters[0].hype
		sim.queue_free()
	check_near(float(gains[true]) - float(gains[false]), 10.0, 0.6, "Jolted bonus Hype")


## Pinball: bounces once off the fence toward the lock-on target (second leg ~1.5 m); ×2 damage when
## Jitters was launched by its own Spring Pad.
func test_pinball_wall_bounce_and_pad_bonus() -> void:
	# a far target (out of soft-lock range) lets Jitters face the fence; the bounce turns it back
	var sim := duel(ID, "dev_biped", 0.0, [stick(T - 0.05, T + 0.3, "away"), press(T, "dodge"), press(T + 0.1, "light")], [],
		[[0, 6.0, 0], [0, -6.5, 0]], [], 8.0)
	var f := sim.fighters[0]
	var st := await run(sim, 1.55)
	check(events(st, "bounce").size() == 1, "expected exactly one fence bounce, got %d" % events(st, "bounce").size())
	var back := float(st["a_max_z"]) - f.pos().z
	check(back > 1.1, "second leg after the bounce only %.2f m" % back)
	var to_t := (sim.fighters[1].pos() - f.pos())
	to_t.y = 0.0
	check(f.forward().dot(to_t.normalized()) > 0.9, "the bounce did not turn Jitters toward its target")
	check_sane(st, f, "Pinball bounce")
	sim.queue_free()
	# pad bonus: identical runs, one with the pad_launched flag set
	var dmg := {}
	for launched in [false, true]:
		var sim2 := duel(ID, "f_slurry", 3.0, [stick(T - 0.05, T + 0.3, "toward"), press(T, "dodge"), press(T + 0.1, "light")])
		await run(sim2, T - 0.05)
		if launched:
			sim2.fighters[0].set_flag("pad_launched", 1.5)
		var st3 := await run(sim2, 1.0, "dash_attack")
		var hs := hits(st3, 0, "dash_attack", 1)
		if check(not hs.is_empty(), "Pinball missed (launched=%s)" % str(launched)):
			dmg[launched] = float(hs[0]["damage"])
		sim2.queue_free()
	if dmg.size() == 2:
		check_near(float(dmg[true]) / float(dmg[false]), 2.0, 0.02, "pad Pinball damage ratio")


## Grab: Suction Hug latches at ~0.8 m; Zap pummels (2 dmg, Static 15) every 0.25 s (fastest); throws.
func test_suction_hug_zaps_and_throws() -> void:
	var simw := duel(ID, "dev_biped", 1.6, [press(T, "grab")])
	var stw := await run(simw, 1.4)
	check(events(stw, "grab").is_empty(), "Suction Hug grabbed at 1.6 m (should whiff)")
	check_sane(stw, simw.fighters[0], "Suction Hug whiff")
	simw.queue_free()
	var sim := duel(ID, "dev_biped", 0.8, [press(T, "grab"), {"t0": T + 0.4, "t1": T + 1.3, "press": ["light"], "every": 0.05}])
	var st := await run(sim, 2.0)
	check(not events(st, "grab").is_empty(), "Suction Hug did not grab at 0.8 m")
	var pm := hits(st, 0, "pummel", 1)
	check(pm.size() == 3, "expected 3 zaps, got %d" % pm.size())
	for i in pm.size():
		check_near(float(pm[i]["damage"]), 2.0 * POWER, 0.05, "zap damage")
		if i > 0:
			var gap_s := (int(pm[i]["tick"]) - int(pm[i - 1]["tick"])) / float(Engine.physics_ticks_per_second)
			check(gap_s >= 0.24 and gap_s <= 0.34, "zaps %.2f s apart (0.25 s cadence)" % gap_s)
	check(float(st["d_buildup"].get("static", 0.0)) >= 40.0 or st["d_statuses"].has("jolted"), "zaps built no Static")
	sim.queue_free()
	for th in [["throw_fwd", "toward", 8.0, 1.5], ["throw_side", Vector3(1, 0, 0), 8.0, 1.5], ["throw_back", "away", 7.0, 0.5]]:
		var steps := [press(T, "grab"), stick(T + 0.6, T + 0.72, th[1]), press(T + 0.7, "grab")]
		var sim2 := duel(ID, "dev_biped", 0.8, steps)
		var st2 := await run(sim2, 2.4)
		var tev := events(st2, "throw")
		if check(tev.size() == 1, "%s: no throw" % th[0]):
			check_eq(str(tev[0]["kind"]), str(th[0]), "throw kind")
		var thits := hits(st2, 0, "throw", 1)
		if check(thits.size() == 1, "%s: no throw damage" % th[0]):
			check_near(float(thits[0]["damage"]), float(th[2]) * POWER, 0.05, "%s damage" % th[0])
		var moved := Vector2(sim2.fighters[1].pos().x - float(st2["d_start"].x), sim2.fighters[1].pos().z - float(st2["d_start"].z)).length()
		check(moved >= float(th[3]), "%s: dummy only travelled %.2f m" % [th[0], moved])
		check_sane(st2, sim2.fighters[0], str(th[0]))
		sim2.queue_free()


## Slippery: grabs on Jitters hold 30% shorter (1.4 s); knockdown recovery is 30% faster (kit trait
## stats held_time 0.7 / getup_speed 1.3).
func test_slippery_hold_and_quick_getup() -> void:
	var plain_entry: Dictionary = Content.creature_entry(ID).duplicate(true)
	var pst: Dictionary = plain_entry["stats"]
	pst["getup_speed"] = 1.0
	pst["held_time"] = 1.0
	var plain := CreatureDef.from_dict(plain_entry)
	check(plain.is_valid(), "plain Jitters copy invalid")
	var holds := {}
	for slippery in [true, false]:
		var victim: CreatureDef = creature(ID) if slippery else plain
		var sim := duel("f_slurry", victim, 1.3, [press(T, "grab")])
		var st := await run(sim, 3.4)
		var g := events(st, "grab")
		var th := events(st, "throw")
		if check(g.size() == 1 and th.size() == 1, "auto-throw setup failed (slippery=%s: %d grabs, %d throws)" % [str(slippery), g.size(), th.size()]):
			holds[slippery] = (int(th[0]["tick"]) - int(g[0]["tick"])) / float(Engine.physics_ticks_per_second)
		sim.queue_free()
	if holds.size() == 2:
		check_near(float(holds[true]), 1.4, 0.05, "hold time on Jitters")
		check_near(float(holds[false]), 2.0, 0.05, "hold time on plain Jitters")
	var downs := {}
	for quick in [true, false]:
		var sim2 := duel(creature(ID) if quick else plain, "dev_biped", 4.0, [])
		await run(sim2, T)
		var f := sim2.fighters[0]
		f.knock_down("test")
		var t0 := f.time
		var dt := 1.0 / Engine.physics_ticks_per_second
		while f.is_down() and f.time - t0 < 6.0:
			sim2.step(dt)
			await get_tree().physics_frame
		downs[quick] = f.time - t0
		sim2.queue_free()
	check(float(downs[true]) < float(downs[false]) * 0.85, "get-up %.2f s vs %.2f s without the trait" % [float(downs[true]), float(downs[false])])


## Arc Lash: slow homing orb (6 dmg, Static 45) that curves onto a strafing target; on timeout it
## pulses (r 1.2, 3 dmg, Static 20) but never after a direct hit; reflectable; 6 s cooldown.
func test_arc_lash_homing_pulse_cooldown() -> void:
	var strafe := {"t0": T, "t1": T + 2.0, "move": Vector3(1, 0, 0)}
	var sim := duel(ID, "dev_biped", 5.0, [press(T, "ability1"), press(T + 1.0, "ability1")], [strafe], [], [], 8.0)
	var f := sim.fighters[0]
	var st := await run(sim, 2.6)
	check(not hits(st, 0, "arc_lash", 1).is_empty(), "Arc Lash missed a strafing target (homing)")
	check(hits(st, 0, "arc_lash_pulse", 1).is_empty(), "Arc Lash pulsed after a direct hit")
	check(events(st, "ability", "slot", "ability1").size() == 1, "Arc Lash fired twice inside its cooldown")
	check(float(f.cooldown_left.get("ability1", 0.0)) > 3.5 and float(f.cooldown_left.get("ability1", 0.0)) <= 6.0,
		"Arc Lash cooldown %.2f" % float(f.cooldown_left.get("ability1", 0.0)))
	sim.queue_free()
	# out of reach: the orb times out ~9 m out and the pulse catches a target standing there
	var sim2 := duel(ID, "dev_biped", 10.2, [press(T, "ability1")], [], [], [], 8.0)
	var st2 := await run(sim2, 2.6)
	check(hits(st2, 0, "arc_lash", 1).is_empty(), "the orb should time out short of 10.2 m")
	var pl := hits(st2, 0, "arc_lash_pulse", 1)
	if check(not pl.is_empty(), "no expiry pulse hit (%s)" % _hit_summary(st2)):
		check_near(float(pl[0]["damage"]), 3.0 * POWER, 0.05, "pulse damage")
	sim2.queue_free()
	# reflectable
	var sim3 := duel(ID, "dev_biped", 4.0, [press(T, "ability1")])
	sim3.fighters[1].set_flag("reflect", 5.0)
	var st3 := await run(sim3, 2.0)
	check(not events(st3, "reflect").is_empty(), "Arc Lash was not reflected")
	sim3.queue_free()


## Spring Pad: placed ~2.2 m ahead (max 2, 10 s), launches enemies 2.5 m up with a 0.4 s landing
## stun; launches Jitters too, whose Heavy is then a free (no stamina) Squash.
func test_spring_pad_launches() -> void:
	# enemy launch: the pad lands right under the dummy
	var sim := duel(ID, "dev_biped", 2.2, [press(T, "ability2")])
	var st := await run(sim, 2.6)
	var pads := events(st, "prop_spawn", "prop", "spring_pad")
	if check(pads.size() == 1, "no spring pad"):
		var pp: Vector3 = pads[0]["pos"]
		check(Vector2(pp.x - float(st["a_start"].x), pp.z - float(st["a_start"].z)).length() > 1.8, "pad placed too close")
	check(not events(st, "spring", "fighter", 1).is_empty(), "the pad did not launch the enemy")
	check(float(st["d_max_y"]) > float(st["d_start"].y) + 1.2, "enemy launch height %.2f" % (float(st["d_max_y"]) - float(st["d_start"].y)))
	check(st["d_states"].has("hitstun"), "the enemy did not land stunned")
	check(float(sim.fighters[0].cooldown_left.get("ability2", 0.0)) > 4.5, "Spring Pad cooldown not running")
	# max 2 active pads
	var pad_e: Dictionary = {}
	for e in sim.fighters[0].creature.abilities["ability2"].effects:
		if str(e.get("type", "")) == "prop":
			pad_e = e
	for i in 3:
		sim.effects.fire(sim.fighters[0], pad_e, null)
	var mine := sim.effects.entities.filter(func(x): return x["kind"] == "prop" and str(x["prop"]) == "spring_pad" and int(x["owner"]) == 0)
	check(mine.size() == 2, "spring pads active: %d (max 2)" % mine.size())
	sim.queue_free()
	# own launch + free Squash
	var steps := [press(T, "ability2"), stick(T + 0.5, T + 1.4, "toward")]
	var sim2 := duel(ID, "dev_biped", 7.0, steps, [], [], [], 8.0)
	var f := sim2.fighters[0]
	var launched_at := -1.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var cursor := 0
	for i in int(2.4 / dt):
		sim2.step(dt)
		await get_tree().physics_frame
		for ev in sim2.events_since(cursor):
			cursor = int(ev["seq"])
			if str(ev["type"]) == "spring" and int(ev["fighter"]) == 0 and launched_at < 0.0:
				launched_at = sim2.time
		if launched_at > 0.0 and sim2.time >= launched_at + 0.2:
			break
	if check(launched_at > 0.0, "Jitters never stepped onto its own pad"):
		check(f.has_flag("pad_launched"), "no pad_launched flag after the launch")
		var st_before := f.stamina
		f.input.press(FighterInput.HEAVY)
		var st2 := await run(sim2, 0.3)
		var starts := events(st2, "move_start", "slot", "heavy@pad_launched")
		check(not starts.is_empty(), "pad Heavy variant not used (%s)" % str(events(st2, "move_start")))
		check(f.stamina >= st_before - 0.01, "the pad Squash cost stamina (%.1f -> %.1f)" % [st_before, f.stamina])
	sim2.queue_free()


## Jitters springs off its own pad toward a dummy `gap` m away and presses Heavy `delay` s into the
## flight (the free pad Squash); returns the run summary from the press on ({} if it never launched).
func _pad_squash(c: CreatureDef, gap: float, delay: float) -> Dictionary:
	var steps := [press(T, "ability2"), stick(T + 0.5, T + 1.4, "toward")]
	var sim := duel(c, "dev_biped", gap, steps, [], [], [], 8.0)
	var f := sim.fighters[0]
	var launched_at := -1.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var cursor := 0
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	for i in int(2.4 / dt):
		sim.step(dt)
		await get_tree().physics_frame
		for ev in sim.events_since(cursor):
			cursor = int(ev["seq"])
			if str(ev["type"]) == "spring" and int(ev["fighter"]) == 0 and launched_at < 0.0:
				launched_at = sim.time
		if launched_at > 0.0 and sim.time >= launched_at + delay:
			break
	var st := {}
	if check(launched_at > 0.0, "Jitters never stepped onto its own pad"):
		f.input.press(FighterInput.HEAVY)
		st = await run(sim, 2.4)
		check(not events(st, "move_start", "slot", "heavy@pad_launched").is_empty(), "pad Squash variant not used")
		check_sane(st, f, "pad Squash")
	sim.queue_free()
	return st


## The pad Squash keeps its slam live until the (late, high) landing, so it crushes a target at the
## bottom of the arc instead of only catching it with the landing circle.
func test_pad_squash_slam_connects() -> void:
	var st := await _pad_squash(creature(ID), 5.0, 0.45)
	if not st.is_empty():
		check(not hits(st, 0, "heavy@pad_launched", 1).is_empty(), "pad Squash slam never connected (%s)" % _hit_summary(st))


## Overcharge: armored activation, burst, 8 s of: Light-stagger immunity, landing pulses, chain arcs
## from Light hits to the nearest other enemy; then the JUICE crash.
func test_overcharge_activation_and_end() -> void:
	var sim := duel(ID, "dev_biped", 2.6, [press(T, "juice")], [], [], [], 8.0)
	var f := sim.fighters[0]
	f.hype = 100.0
	var st := await run(sim, T + 0.25)
	check(not events(st, "juice").is_empty(), "JUICE did not start at 100 Hype")
	check(f.time < f.armor_until and f.armor_level == "all", "activation not fully armored")
	check(f.time < f.invuln_until, "activation not invulnerable for its first 0.3 s")
	var st2 := await run(sim, 1.0)
	check(not hits(st2, 0, "overcharge_burst", 1).is_empty(), "the burst missed at 2.6 m")
	check(f.has_flag("juiced") and f.juice_armor == "lights", "no Light-stagger immunity during Overcharge")
	var st3 := await run(sim, 8.0)
	var ends := events(st3, "juice_end")
	if check(ends.size() == 1, "JUICE did not end"):
		var t_end := int(ends[0]["tick"]) / float(Engine.physics_ticks_per_second)
		check_near(t_end, T + 0.45 + 8.0, 0.1, "JUICE end time")
	check(f.speed_mult() < 0.8, "no JUICE crash slowdown (%.2f)" % f.speed_mult())
	sim.queue_free()


func _juice_state(c: CreatureDef) -> Dictionary:
	for e in c.abilities["juice"].effects:
		if str(e.get("type", "")) == "juice_state":
			return e
	return {}


## The Overcharge state: Lights do not stagger Jitters, landings pulse (r 2), Light hits arc to the
## nearest other enemy within 2 m.
func test_overcharge_state_effects() -> void:
	var c := creature(ID, ["l1"])
	var js := _juice_state(c)
	check(not js.is_empty(), "juice_state effect missing")
	# armor vs Lights: the dummy jabs a juiced Jitters
	var jabs := {"t0": T, "t1": T + 1.2, "press": ["light"], "every": 0.45}
	var sim := duel(c, creature("f_slurry", ["l1"]), 1.3, [], [jabs])
	await run(sim, 0.3)
	sim.fighters[0].apply_juice_state(js)
	var st := await run(sim, 1.4)
	check(not hits(st, 1, "", 0).is_empty(), "the dummy never reached Jitters (setup)")
	check(not st["states"].has("hitstun"), "a Light staggered the juiced Jitters")
	sim.queue_free()
	# landing pulse after a Squash
	var sim2 := duel(c, "dev_biped", 1.5, [press(T, "heavy")])
	await run(sim2, 0.3)
	sim2.fighters[0].apply_juice_state(js)
	var st2 := await run(sim2, 2.0)
	check(not hits(st2, 0, "overcharge_pulse", 1).is_empty(), "no landing pulse during Overcharge (%s)" % _hit_summary(st2))
	sim2.queue_free()
	# chain arc: a Slap on dummy 1 arcs to dummy 2 standing 1.2 m behind it
	var sim3 := duel(c, "dev_biped", 0.0, [press(T, "light")], [], [[0, -0.4, 0], [0, 0.4, 180], [1.0, 1.0, 180]], ["dev_biped"])
	await run(sim3, 0.3)
	sim3.fighters[0].apply_juice_state(js)
	var st3 := await run(sim3, 1.2)
	check(not hits(st3, 0, "l1", 1).is_empty(), "the Slap missed (setup)")
	check(not hits(st3, 0, "overcharge_arc", 2).is_empty(), "no chain arc to the second enemy (%s)" % _hit_summary(st3))
	sim3.queue_free()


## Lights obey guard (blocked, 25% damage) and parry; Arc Lash (projectile) can be blocked, not parried.
func test_guard_and_parry() -> void:
	var c := creature(ID, ["l1"])
	var sim0 := duel(c, "f_slurry", 0.8, [press(T, "light")])
	var st0 := await run(sim0, 1.0, "l1")
	var t_hit := float(st0["hit_t"])
	var raw := hits(st0, 0, "l1", 1)
	check(t_hit > 0.0 and not raw.is_empty(), "reference Slap missed")
	sim0.queue_free()
	var sim := duel(c, "f_slurry", 0.8, [press(T, "light")], [hold(T - 0.2, T + 1.0, "guard")])
	var st := await run(sim, 1.0)
	var hs: Array = st["hits"].filter(func(h): return int(h.get("fighter", -1)) == 0 and str(h.get("slot", "")) == "l1")
	if check(not hs.is_empty() and bool(hs[0]["blocked"]), "Slap into guard was not blocked (%s)" % _hit_summary(st)) and not raw.is_empty():
		check(float(hs[0]["damage"]) <= float(raw[0]["damage"]) * 0.35, "guarded damage %.2f vs %.2f" % [float(hs[0]["damage"]), float(raw[0]["damage"])])
	sim.queue_free()
	var sim2 := duel(c, "f_slurry", 0.8, [press(T, "light")], [hold(t_hit - 0.06, t_hit + 0.6, "guard")])
	var st2 := await run(sim2, 1.0)
	var ps: Array = st2["hits"].filter(func(h): return int(h.get("fighter", -1)) == 0 and bool(h["parried"]))
	check(not ps.is_empty(), "Slap was not parried (%s)" % _hit_summary(st2))
	check(st2["states"].has("hitstun"), "parried Jitters was not staggered")
	sim2.queue_free()
	var sim3 := duel(ID, "dev_biped", 4.0, [press(T, "ability1")])
	var st3a := await run(sim3, 2.2, "arc_lash")
	var t_orb := float(st3a["hit_t"])
	sim3.queue_free()
	if check(t_orb > 0.0, "reference Arc Lash missed"):
		var sim4 := duel(ID, "dev_biped", 4.0, [press(T, "ability1")], [hold(t_orb - 0.06, t_orb + 1.0, "guard")])
		var st4 := await run(sim4, 2.2)
		var orb: Array = st4["hits"].filter(func(h): return str(h.get("move", "")) == "arc_lash")
		check(not orb.is_empty() and bool(orb[0]["blocked"]) and not bool(orb[0]["parried"]), "Arc Lash should be blocked, never parried (%s)" % _hit_summary(st4))
		sim4.queue_free()


## Taunt: 1.5 s, +8 Hype.
func test_taunt() -> void:
	var sim := duel(ID, "dev_biped", 3.0, [press(T, "taunt")])
	var f := sim.fighters[0]
	await run(sim, T + 1.2)
	check_eq(f.state_name(), "taunt", "state 1.2 s into the taunt")
	check_near(f.hype, 8.0, 0.01, "taunt Hype")
	await run(sim, 0.6)
	check(f.state_name() != "taunt", "taunt longer than 1.5 s")
	sim.queue_free()


## Bot plays the pest per the ROSTER AI notes: stays close, uses its abilities, lands hits.
func test_bot_pest_uses_kit() -> void:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var arena := ArenaDef.from_dict({"id": "kit_test", "base": "octagon", "radius": 7.0, "spawns": [[0, -2.5, 0], [0, 2.5, 180]]})
	var bot := BotBrain.new("pro", 4243)
	var c := Content.creature(ID)
	bot.set_personality(c.ai)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": INTRO}, "seed": 6,
		"fighters": [{"creature": c, "team": 0, "source": bot}, {"creature": Content.creature("dev_biped"), "team": 1, "source": InputSource.Scripted.new([])}]})
	var st := await run(sim, 12.0)
	var abilities := events(st, "ability", "fighter", 0)
	check(not abilities.is_empty(), "the Jitters bot never used an ability")
	check(hits(st, 0, "", 1).size() >= 3, "the Jitters bot landed fewer than 3 hits in 12 s")
	sim.queue_free()


func _effect_of(m: MoveDef, type: String) -> Dictionary:
	for e in m.effects:
		if str(e.get("type", "")) == type:
			return e
	return {}


## Campaign techniques (content/core/techniques/jitters.json, ROSTER §6) are patches and hooks on
## this kit: every patch lands on a real field and each technique delivers its effect.
func test_campaign_techniques_deliver() -> void:
	var tk := {}
	for tid in ["tech_jitters_capacitor", "tech_jitters_bouncy_castle", "tech_jitters_chain_reaction", "tech_jitters_rubber_core",
			"tech_jitters_head_hunter", "tech_jitters_short_fuse"]:
		var r := technique_kit(ID, tid)
		tk[tid] = r
		var tc: CreatureDef = r["creature"]
		check(tc.errors.is_empty(), "%s: patched kit does not parse: %s" % [tid, str(tc.errors)])
		check(not (r["hits"] as Array).has(0), "%s: a patch missed the kit (targets per patch %s)" % [tid, str(r["hits"])])
	# Capacitor: Overcharge 8 -> 10 s, Hype gain +20%
	var cap: CreatureDef = tk["tech_jitters_capacitor"]["creature"]
	check_near(float(cap.juice.get("duration", 0.0)), 10.0, 0.01, "Capacitor JUICE duration")
	check_near(float(_effect_of(cap.abilities["juice"], "juice_state").get("duration", 0.0)), 10.0, 0.01, "Capacitor Overcharge state")
	check_near(float(tk["tech_jitters_capacitor"]["mods"].get("hype_gain", 1.0)), 1.2, 0.001, "Capacitor Hype gain")
	# Bouncy Castle: 3 pads, 5 s cooldown
	var bc: CreatureDef = tk["tech_jitters_bouncy_castle"]["creature"]
	check_near(float(bc.cooldowns.get("ability2", 0.0)), 5.0, 0.01, "Bouncy Castle cooldown")
	var sim := duel(bc, "dev_biped", 6.0, [], [], [], [], 8.0)
	await run(sim, 0.3)
	for i in 4:
		sim.effects.fire(sim.fighters[0], _effect_of(bc.abilities["ability2"], "prop"), null)
	var pads := sim.effects.entities.filter(func(x): return x["kind"] == "prop" and str(x["prop"]) == "spring_pad" and int(x["owner"]) == 0)
	check_eq(pads.size(), 3, "Bouncy Castle pads active")
	sim.queue_free()
	# Chain Reaction: Slapping a Jolted enemy leaks Static to another enemy within 1.5 m (none without it)
	var leaked := {}
	for which in ["base", "chain"]:
		var cc: CreatureDef = creature(ID) if which == "base" else technique_kit(ID, "tech_jitters_chain_reaction")["creature"]
		var sim2 := duel(cc, "dev_biped", 0.8, [press(T + 0.3, "light")], [], [[0, -0.4, 0], [0, 0.4, 180], [1.0, -0.5, 0]], ["dev_biped"])
		await run(sim2, 0.3)
		sim2.fighters[1].statuses.add_buildup("static", 100.0, sim2.fighters[0])
		check(sim2.fighters[1].statuses.has("jolted"), "pre-Jolt failed")
		var st2 := await run(sim2, 1.0)
		check(not hits(st2, 0, "l1", 1).is_empty(), "%s: Slap missed the Jolted enemy" % which)
		check(hits(st2, 0, "l1", 2).is_empty(), "%s: the Slap itself reached the bystander (test setup)" % which)
		leaked[which] = float(sim2.fighters[2].statuses.buildup.get("static", 0.0)) + (100.0 if sim2.fighters[2].statuses.has("jolted") else 0.0)
		sim2.queue_free()
	check(float(leaked["base"]) < 0.01 and float(leaked["chain"]) > 4.0, "Chain Reaction leak: base %.1f, technique %.1f" % [float(leaked["base"]), float(leaked["chain"])])
	# Rubber Core: poise 60, and the run's get-up x1.5 stacks with the kit's own x1.3
	var rc: Dictionary = tk["tech_jitters_rubber_core"]
	check_near((rc["creature"] as CreatureDef).stat("poise"), 60.0, 0.01, "Rubber Core poise")
	var sim3 := duel(rc["creature"], "dev_biped", 3.0, [])
	with_mods(sim3.fighters[0], rc["mods"])
	check_near(sim3.fighters[0].getup_speed_mult(), 1.3 * 1.5, 0.001, "Rubber Core get-up speed")
	sim3.queue_free()
	# Head Hunter: both Squash variants leap 0.5 m higher to a 2.5 m target point, the slam window and
	# recovery run on to the later landing, and head hits Bonk for +7 instead of +3
	var hh: CreatureDef = tk["tech_jitters_head_hunter"]["creature"]
	var plain := creature(ID)
	for slot in ["heavy", "heavy@pad_launched"]:
		var lp := _effect_of(hh.moves[slot], "leap")
		var lp0 := _effect_of(plain.moves[slot], "leap")
		check_near(float(lp["height"]), float(lp0["height"]) + 0.5, 0.001, "%s leap height" % slot)
		check_near(float(lp["distance"]), 2.5, 0.001, "%s leap target point" % slot)
		check_near(hh.moves[slot].duration, plain.moves[slot].duration + 0.24, 0.001, "%s duration" % slot)
	var bonk := {}
	for which in ["base", "hunter"]:
		var sim4 := duel(plain if which == "base" else hh, "f_slurry", 2.0, [press(T, "heavy")])
		var st4 := await run(sim4, 2.6, "heavy")
		var hs := hits(st4, 0, "heavy", 1)
		if check(not hs.is_empty() and str(hs[0]["part"]) == "head", "%s Squash vs Slurry: no head hit (%s)" % [which, _hit_summary(st4)]):
			bonk[which] = float(hs[0]["damage"])
		check_sane(st4, sim4.fighters[0], "%s Squash" % which)
		sim4.queue_free()
	if bonk.size() == 2:
		check(float(bonk["hunter"]) >= float(bonk["base"]) + 4.0, "Head Hunter Bonk %.1f vs %.1f" % [float(bonk["hunter"]), float(bonk["base"])])
	var sim5 := duel(hh, "f_jitters", 2.2, [press(T, "heavy")])
	var st5 := await run(sim5, 2.6, "heavy")
	check(not hits(st5, 0, "heavy", 1).is_empty(), "Head Hunter Squash whiffed a target 2.2 m away (%s)" % _hit_summary(st5))
	check_sane(st5, sim5.fighters[0], "Head Hunter Squash")
	sim5.queue_free()
	var st6 := await _pad_squash(hh, 5.0, 0.45)
	if not st6.is_empty():
		check(not hits(st6, 0, "heavy@pad_launched", 1).is_empty(), "Head Hunter pad Squash slam never connected (%s)" % _hit_summary(st6))
	# Short Fuse: Arc Lash homing 90 -> 180 deg/s and 2 charges; stamina regen -20%
	var sf: CreatureDef = tk["tech_jitters_short_fuse"]["creature"]
	check_near(float(_effect_of(sf.abilities["ability1"], "projectile")["homing_deg"]), 180.0, 0.01, "Short Fuse homing")
	check_eq(int(sf.ability_charges.get("ability1", 0)), 2, "Short Fuse charges")
	check_near(float(tk["tech_jitters_short_fuse"]["mods"].get("stamina_regen", 1.0)), 0.8, 0.001, "Short Fuse stamina regen")
