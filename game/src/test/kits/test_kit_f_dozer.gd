extends "res://src/test/kits/dd_kit_base.gd"
## DOZER (f_dozer) kit verification — docs/kits/f_dozer.md, ROSTER.md §4.
## Requirements: CNT-01 (finished fighter kits), CMB-06 (grab/throw/pummel layer).
## Every move: connects at its intended range against a standing dummy and misses outside it;
## damage / knockback / launch / build-up / properties; guard-crush; cooldowns; JUICE; grab,
## pummel, throws; physical sanity (upright, no spin-out, no self-clip, cage, 1.6 m cap).
## Also the generic engine extensions added with this kit (charge "recovery" + kept wall-bonk
## stagger, the "cooldown" hook action).
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_f_dozer
## Balance bouts: set KIT_BOUTS=<n> (default 2) for the Dozer mirror in test_zz_balance
## (the Dredge-vs-Dozer pairing runs in test_kit_f_dredge.gd).

const ID := "f_dozer"

## slot, gaps that must connect (any), gap that must miss
const RANGE_TABLE := [
	["l1", [1.4, 1.6], 2.05],
	["l3", [1.3, 1.5], 1.95],
	["heavy", [1.5, 1.7], 2.15],
	["finisher", [1.3, 1.5], 1.95],
]


func test_kit_is_complete_and_clean() -> void:
	var c := Content.creature(ID)
	check(c.is_valid(), "creature parses without errors: %s" % ", ".join(c.errors))
	for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "pummel", "taunt"]:
		check(c.moves.has(slot), "move slot %s present" % slot)
	for slot in ["ability1", "ability2", "juice"]:
		check(c.abilities.has(slot), "ability %s present" % slot)
	check_near(float(c.cooldowns["ability1"]), 8.0, 0.001, "Bulldoze cooldown")
	check_near(float(c.cooldowns["ability2"]), 11.0, 0.001, "Dust Bowl cooldown")
	for k in ["throw_fwd", "throw_side", "throw_back"]:
		check(c.throws.has(k), "throw %s present" % k)
	var raw := FileAccess.get_file_as_string("res://content/core/creatures/f_dozer.json")
	check(not raw.contains("_stub"), "no stub moves left")
	check_near(c.stat("health"), 130.0, 0.01, "HP")
	check_near(c.stat("walk_speed"), 3.0, 0.01, "walk")
	check_near(c.stat("stamina"), 95.0, 0.01, "stamina")
	check_near(c.stat("poise"), 85.0, 0.01, "poise")
	check_near(c.stat("dodge_distance"), 3.2, 0.01, "dash")
	check(c.ai.has("abilities") and c.ai.has("range"), "bot hints present")
	for slot in ["heavy", "heavy_charged"]:
		var m: MoveDef = c.moves[slot]
		check(not m.armor.is_empty(), "%s carries armor" % slot)
	var t: MoveDef = c.moves["taunt"]
	check_near(t.duration, 1.5, 0.001, "taunt lasts 1.5 s")
	check(t.armor.is_empty(), "taunt has no armor")


func test_moves_connect_in_range_and_miss_outside() -> void:
	for row in RANGE_TABLE:
		var slot: String = row[0]
		var landed := false
		var best := {}
		for g in row[1]:
			var r := await measure_move(ID, slot, float(g))
			check_sane(r, "%s @%.2f" % [slot, g])
			if not r["melee"].is_empty():
				landed = true
				best = r
		check(landed, "%s connects at %s m" % [slot, str(row[1])])
		if landed:
			check(float(best["melee"][0]["damage"]) > 0.0, "%s deals damage" % slot)
			check(best["b_states"].has("hitstun") or best["b_states"].has("knockdown"), "%s staggers the dummy" % slot)
			check(float(best["b_buildup"].get("grit", 0.0)) > 0.0 or best["b_states"].has("knockdown"), "%s adds Grit build-up" % slot)
		var miss := await measure_move(ID, slot, float(row[2]))
		check(miss["melee"].is_empty(), "%s misses at %.2f m (got %d melee hits)" % [slot, row[2], miss["melee"].size()])


func test_hoof_stomp_pulse() -> void:
	# the stomp's ground pulse (r 0.8 m around the landing hoof) carries the hit
	var near := await measure_move(ID, "l2", 1.45)
	check(near["effect_hits"].size() == 1, "Hoof Stomp's pulse hits a target in front (%d)" % near["effect_hits"].size())
	check(near["b_states"].has("hitstun"), "stomp staggers")
	check(float(near["b_buildup"].get("grit", 0.0)) >= 12.0, "12 + 5 Grit build-up (%.1f)" % float(near["b_buildup"].get("grit", 0.0)))
	check_sane(near, "l2")
	var far := await measure_move(ID, "l2", 2.1)
	check(far["hits"].is_empty(), "the pulse is small: nothing at 2.1 m")


func test_light_string_and_finisher_via_input() -> void:
	var r := await measure_move(ID, "l1", 1.45, {"via": [{"t0": 0.0, "press": ["light"]}, {"t0": 0.24, "press": ["light"]},
		{"t0": 0.5, "press": ["light"]}, {"t0": 0.85, "press": ["heavy"]}], "dur": 2.4})
	var slots: Array = r["slots"]
	check(slots.size() >= 4 and slots.slice(0, 4) == ["l1", "l2", "l3", "finisher"], "L1 > L2 > L3 > Finisher chain (got %s)" % str(slots))
	check(r["hits"].size() >= 3, "the string lands several hits (%d)" % r["hits"].size())
	check_sane(r, "string")


func test_scoop_launches() -> void:
	var r := await measure_move(ID, "l3", 1.4, {"dummy": dummy(100.0)})
	check(not r["melee"].is_empty(), "Scoop connects")
	check(float(r["b_rise"]) > 0.6 and float(r["b_rise"]) < 1.6, "launcher: knock-up ~1.0 m (%.2f)" % r["b_rise"])


func test_horn_lunge_armor_and_reach() -> void:
	# the crab jabs Dozer during the windup: armor carries the lunge through to the hit
	var landed := 0
	var tagged := 0
	for g in [1.9, 2.0, 2.2]:
		var sb := InputSource.Scripted.new([{"t0": 0.45, "t1": 0.48, "press": ["light"]}])
		var r := await measure_move(ID, "heavy", g, {"sb": sb, "dummy": Content.creature("f_dredge"), "keep": true})
		var a: Fighter = r["a"]
		if not r["melee"].is_empty():
			landed += 1
		if a.stats_record["damage_taken"] > 0.0:
			tagged += 1
		check(a.state != Fighter.State.HITSTUN or not r["melee"].is_empty(), "lunge not interrupted at %.1f m" % g)
		release(r)
	check(landed >= 1, "Horn Lunge lands on a crab that jabs it during the windup (%d of 3 gaps)" % landed)
	check(tagged >= 1, "the jab does connect (armor, not a whiff)")
	var lunge := await measure_move(ID, "heavy", 5.0)
	var d := Vector3(lunge["a_disp"])
	check(d.z > 0.45 and d.z < 1.1, "root lunges ~0.6 m (%.2f)" % d.z)


func test_quarry_ram() -> void:
	var r := await measure_move(ID, "heavy", 3.2, {"via": [{"t0": 0.0, "press": ["heavy"]}, {"t0": 0.0, "t1": 0.85, "hold": ["heavy"]}],
		"dur": 2.6, "dummy": dummy(100.0)})
	check("heavy_charged" in r["slots"], "a long hold becomes Quarry Ram (%s)" % str(r["slots"]))
	check(not r["melee"].is_empty(), "the ram connects after its 3 m dash")
	check(float(r["b_rise"]) > 0.7, "horn uppercut knock-up (%.2f m)" % r["b_rise"])
	check_sane(r, "quarry_ram")
	var dash := await measure_move(ID, "heavy_charged", 6.0, {"radius": 7.0})
	check(Vector3(dash["a_disp"]).z > 2.4 and Vector3(dash["a_disp"]).z < 4.0, "3 m dash at 6 m/s (%.2f)" % Vector3(dash["a_disp"]).z)
	# guard-crush and armor throughout
	var g := InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])
	var crush := await measure_move(ID, "heavy_charged", 2.6, {"sb": g, "keep": true, "dur": 2.0})
	var st_crush: float = crush["b"].max_stamina - crush["b"].stamina
	release(crush)
	var g2 := InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])
	var tap := await measure_move(ID, "heavy", 1.6, {"sb": g2, "keep": true})
	var st_tap: float = tap["b"].max_stamina - tap["b"].stamina
	release(tap)
	check(st_crush > st_tap * 2.0, "guard-crush drains much more stamina (%.1f vs %.1f)" % [st_crush, st_tap])


func test_gravel_toss_cone() -> void:
	var r := await measure_move(ID, "finisher", 1.4)
	check(not r["melee"].is_empty() and not r["effect_hits"].is_empty(), "snout flick + gravel cone both hit")
	var far := await measure_move(ID, "finisher", 2.0)
	check(far["melee"].is_empty() and far["effect_hits"].size() == 1, "the 2 m gravel cone reaches past the snout")
	check(float(far["b_buildup"].get("grit", 0.0)) >= 15.0, "cone adds Grit 20 (%.1f)" % float(far["b_buildup"].get("grit", 0.0)))
	var gt: Dictionary = Content.creature(ID).moves["finisher"].effects[0]
	check(str(gt["shape"]) == "cone" and float(gt["cone_deg"]) == 60.0 and float(gt["radius"]) == 2.0, "2 m, 60-degree cone")


func test_shoulder_barge() -> void:
	var r := await measure_move(ID, "dash_attack", 2.8, {"via": [{"t0": 0.0, "t1": 0.7, "move": Vector3(0, 0, 1)},
		{"t0": 0.0, "press": ["dodge"]}, {"t0": 0.12, "press": ["light"]}], "dur": 1.6})
	check("dash_attack" in r["slots"], "Light during a dodge becomes Shoulder Barge")
	check(not r["melee"].is_empty(), "Shoulder Barge connects after a dash from 2.8 m")
	check_sane(r, "barge")


func test_grab_reach_pummel_and_throws() -> void:
	var grab := await measure_move(ID, "grab", 1.3, {"via": [{"t0": 0.0, "press": ["grab"]}], "dur": 0.9})
	check(count_events(grab["events"], "grab") == 1, "Snout Hook grabs at 1.3 m root gap (~1.0 m reach)")
	var miss := await measure_move(ID, "grab", 1.6, {"via": [{"t0": 0.0, "press": ["grab"]}], "dur": 0.9})
	check(count_events(miss["events"], "grab") == 0, "Snout Hook misses at 1.6 m")
	for kind in [["throw_fwd", Vector3(0, 0, 1)], ["throw_side", Vector3(1, 0, 0)], ["throw_back", Vector3(0, 0, -1)]]:
		var r := await measure_move(ID, "grab", 1.3, {"dummy": dummy(100.0), "keep": true, "dur": 2.6, "via": [{"t0": 0.0, "press": ["grab"]},
			{"t0": 0.5, "press": ["light"]}, {"t0": 1.3, "t1": 1.5, "move": kind[1]}, {"t0": 1.35, "press": ["heavy"]}]})
		var b: Fighter = r["b"]
		var pummel_dmg := 0.0
		var throw_dmg := 0.0
		var kinds := []
		for ev in r["events"]:
			if ev["type"] == "hit" and str(ev.get("slot", "")) == "pummel":
				pummel_dmg = float(ev["damage"])
			if ev["type"] == "hit" and str(ev.get("slot", "")) == "throw":
				throw_dmg = float(ev["damage"])
			if ev["type"] == "throw":
				kinds.append(str(ev["kind"]))
		var pw := Content.creature(ID).stat("power")
		check_near(pummel_dmg, 3.0 * pw, 0.01, "%s: headbutt-shake pummel 3 dmg (x power)" % kind[0])
		check(kinds == [kind[0]], "%s thrown (%s)" % [kind[0], str(kinds)])
		var expected: float = {"throw_fwd": 10.0, "throw_side": 9.0, "throw_back": 9.0}[kind[0]]
		check_near(throw_dmg, expected * pw, 0.01, "%s damage (x power)" % kind[0])
		var land := b.pos() - Vector3(r["b_start"])
		if kind[0] == "throw_fwd":
			check(float(r["b_rise"]) > 0.8, "Launch: knock-up (%.2f m)" % r["b_rise"])
			check(land.z > 1.5, "Launch: thrown forward (%.2f m)" % land.z)
		elif kind[0] == "throw_back":
			check(land.z < -1.0, "Buck: tossed over his own back (%.2f m)" % land.z)
			check(b.is_down(), "Buck knocks down")
		release(r)


func test_pummel_interval() -> void:
	# engine extension: the pummel's "interval" (0.4 s) rate-limits mashing
	var r := await measure_move(ID, "grab", 1.3, {"via": [{"t0": 0.0, "press": ["grab"]}, {"t0": 0.5, "press": ["light"]},
		{"t0": 0.55, "press": ["light"]}, {"t0": 0.6, "press": ["light"]}, {"t0": 0.95, "press": ["light"]}], "dur": 1.2})
	var times := []
	for ev in r["events"]:
		if ev["type"] == "hit" and str(ev.get("slot", "")) == "pummel":
			times.append(int(ev["tick"]))
	check(times.size() == 2, "mashing 3 presses in 0.1 s gives one pummel, the next comes 0.4 s later (%d pummels)" % times.size())
	if times.size() == 2:
		check(float(times[1] - times[0]) * DT >= 0.39, "pummels at least 0.4 s apart")


func test_bulldoze_carry_splat_bonk_recovery() -> void:
	# target 3.4 m ahead near a wall: hit, carried, splatted into the cage
	var r := await measure_move(ID, "ability1", 3.4, {"radius": 3.2, "dur": 2.4, "dummy": dummy(100.0)})
	check(not r["melee"].is_empty(), "Bulldoze hits the target in its path")
	check(count_events(r["events"], "carry") == 1, "the target is carried")
	check(count_events(r["events"], "splat") == 1, "carried into the wall: wall splat")
	check(r["b_states"].has("knockdown") or r["b_states"].has("down"), "wall splat knocks down")
	check_sane(r, "bulldoze")
	# no target, straight into the wall: Dozer staggers 0.6 s (the stagger is kept, not cancelled)
	var stagger := 0.0
	var sim := kit_sim(ID, dummy(), 4.0, null, null, {}, 3.0, Vector3(-2.0, 0, -3.4))
	sim.fighters[1].team = 0
	var d := sim.fighters[0]
	await run(sim, 0.4)
	d.target = null
	start(d, "ability1")
	for i in 240:
		await run(sim, DT)
		if d.state == Fighter.State.HITSTUN:
			stagger += DT
	check(count_events(sim.events, "wall_bonk") == 1, "charging into a wall with no target bonks")
	check(stagger > 0.45 and stagger < 0.8, "wall-bonk stagger ~0.6 s (%.2f)" % stagger)
	release(sim)
	# open floor: ends after 6 m and plays its recovery (not instantly actionable)
	var sim2 := kit_sim(ID, dummy(), 5.0, null, null, {}, 9.0, Vector3(6.0, 0, -6.0))
	sim2.fighters[1].team = 0
	var e := sim2.fighters[0]
	await run(sim2, 0.4)
	e.target = null
	var p0 := e.pos()
	start(e, "ability1")
	var t_end := -1.0
	var t := 0.0
	while t < 3.0:
		await run(sim2, DT)
		t += DT
		if e.state != Fighter.State.ABILITY and t_end < 0.0:
			t_end = t
	var dist := Vector2(e.pos().x - p0.x, e.pos().z - p0.z).length()
	check(dist > 5.0 and dist < 7.4, "drives ~6 m (%.2f)" % dist)
	check(t_end > 0.3 + 6.0 / 7.0 + 0.3, "recovery after the charge (ability ends at %.2f s)" % t_end)
	release(sim2)


func test_bulldoze_splat_ko_ends_round_cleanly() -> void:
	# engine fix: a wall splat that KOs the carried victim ends the round, and the winner's celebrate()
	# drops the carry in the middle of Fighter._finish_charge (it then called pos() on null)
	var sim := kit_sim(ID, dummy(100.0), 3.4, null, null, {}, 3.2)
	var d := sim.fighters[0]
	var v := sim.fighters[1]
	await run(sim, 0.4)
	start(d, "ability1")
	for i in 288:
		await run(sim, DT)
		if v.health > 2.0 and count_events(sim.events, "carry") > 0:
			v.health = 2.0   # carried: the wall splat will be the KO
	check(count_events(sim.events, "carry") == 1, "the target is carried")
	check(count_events(sim.events, "round_end") == 1, "the splat KO ends the round")
	check(count_events(sim.events, "splat") == 1, "the KO splat is still reported")
	check(d._carried == null, "nothing left carried")
	release(sim)


func test_bulldoze_cooldown_and_armor() -> void:
	var sim := kit_sim(ID, dummy(), 4.0, InputSource.Scripted.new([{"t0": 0.3, "t1": 0.33, "press": ["ability1"]},
		{"t0": 3.0, "t1": 3.03, "press": ["ability1"]}, {"t0": 8.6, "t1": 8.63, "press": ["ability1"]}]), null, {}, 9.0, Vector3(6.0, 0, -6.0))
	await run(sim, 9.2)
	check(count_events(sim.events, "ability", "fighter", 0) == 2, "Bulldoze cooldown 8 s")
	release(sim)
	var m: MoveDef = Content.creature(ID).abilities["ability1"]
	check(m.in_ranges(m.armor, 0.1) and m.in_ranges(m.armor, 1.0), "armor throughout the charge")


func test_dust_bowl() -> void:
	var sim := kit_sim(ID, "f_dredge", 2.2, InputSource.Scripted.new([{"t0": 0.3, "t1": 0.33, "press": ["ability2"]},
		{"t0": 1.8, "t1": 2.6, "move": Vector3(1, 0, 0)}, {"t0": 3.0, "t1": 3.03, "press": ["ability2"]}]))
	var dz := sim.fighters[0]
	var dr := sim.fighters[1]
	await run(sim, 0.7)
	check(dz.statuses.has("dust_bowl") and dz._armor_covers("light") and not dz._armor_covers("heavy"), "armor vs Lights while in the bowl")
	await run(sim, 0.3)   # first zone tick applies the choke status
	dr.poise = 30.0
	await run(sim, 0.7)
	check(float(dr.statuses.buildup.get("grit", 0.0)) > 8.0 or dr.statuses.has_element("grit"), "Grit build-up to enemies inside")
	check(dr.statuses.has("dust_choked") and dr.poise < 31.0, "enemy poise regen stops inside")
	var cloud := {}
	for ent in sim.effects.entities:
		if ent["kind"] == "zone" and bool(ent["follow"]):
			cloud = ent
	check(not cloud.is_empty(), "the dust cloud exists")
	var start_pos := dz.pos()
	await run(sim, 0.8)
	if not cloud.is_empty():
		check(Vector2(cloud["pos"].x - dz.pos().x, cloud["pos"].z - dz.pos().z).length() < 0.2 and dz.pos().distance_to(start_pos) > 0.8, "the cloud follows Dozer")
	await run(sim, 1.0)
	check(count_events(sim.events, "ability", "fighter", 0) == 1, "Dust Bowl cooldown 11 s")
	release(sim)
	# enemy projectiles entering the cloud are destroyed
	var sim2 := kit_sim(ID, "f_dredge", 5.0, InputSource.Scripted.new([{"t0": 0.3, "t1": 0.33, "press": ["ability2"]}]),
		InputSource.Scripted.new([{"t0": 0.8, "t1": 0.83, "press": ["ability1"]}]))
	await run(sim2, 2.4)
	check(count_events(sim2.events, "projectile_destroyed") >= 1, "Tide Spit is destroyed by the dust cloud")
	check(sim2.fighters[0].health >= sim2.fighters[0].max_health, "and never lands")
	release(sim2)


func test_juice_landslide() -> void:
	var r := await measure_move(ID, "juice", 3.5, {"rules": {"start_hype": 100}, "via": [{"t0": 0.0, "press": ["juice"]},
		{"t0": 2.0, "press": ["ability1"]}, {"t0": 4.2, "press": ["ability1"]}], "dur": 7.4, "radius": 7.0, "keep": true})
	var a: Fighter = r["a"]
	check(count_events(r["events"], "juice") == 1, "JUICE activates at 100 Hype")
	check(r["b_states"].has("knockdown"), "the 6 m ground-wave line knocks down a target 3.5 m ahead")
	var bulldozes := 0
	for ev in r["events"]:
		if ev["type"] == "move_start" and int(ev["fighter"]) == 0 and str(ev["slot"]) == "ability1@juiced":
			bulldozes += 1
	check(bulldozes == 2, "Bulldoze has no cooldown during Landslide (%d uses 2.2 s apart)" % bulldozes)
	check(count_events(r["events"], "juice_end") == 1, "JUICE ends after 6 s")
	release(r)
	# a juiced Bulldoze hit drops a boulder (target 7 m away: beyond the 6 m wave, inside the 10 m charge)
	var rb := await measure_move(ID, "juice", 7.0, {"rules": {"start_hype": 100}, "via": [{"t0": 0.0, "press": ["juice"]},
		{"t0": 0.9, "press": ["ability1"]}], "dur": 3.0, "radius": 9.0, "dummy": dummy(100.0)})
	var hit_t := -1.0
	var boulder_t := -1.0
	for ev in rb["events"]:
		if ev["type"] == "hit" and int(ev["fighter"]) == 0 and str(ev.get("move", "")).ends_with("ability1@juiced") and hit_t < 0.0:
			hit_t = float(ev["tick"]) * DT
		if ev["type"] == "prop_spawn" and str(ev.get("prop", "")) == "boulder" and boulder_t < 0.0:
			boulder_t = float(ev["tick"]) * DT
	check(hit_t > 0.0, "the juiced Bulldoze reaches a target 7 m away")
	check(boulder_t > 0.0 and absf(boulder_t - hit_t) < 0.05, "its hit drops a boulder prop (hit %.2f s, boulder %.2f s)" % [hit_t, boulder_t])
	# permanent armor: a heavy hit during the JUICE does not stagger him
	var sim := kit_sim(ID, "f_dredge", 1.4, InputSource.Scripted.new([{"t0": 0.2, "t1": 0.23, "press": ["juice"]}]), null, {"start_hype": 100})
	var dz := sim.fighters[0]
	var dr := sim.fighters[1]
	await run(sim, 1.2)
	var h := {"attacker": dr, "damage": 14.0, "point": dz.pos(), "normal": Vector3.BACK, "seg": 0, "part": "core", "blocked": false,
		"parried": false, "counter": false, "knockback": Vector3(0, 0, -3.0), "local_impulse": Vector3.ZERO, "stun": 0.6, "poise": 30.0,
		"knockdown": false, "hype_mult": 1.0, "element": "", "buildup": 0.0, "move": "test", "slot": "heavy", "move_class": "heavy",
		"from": dr.pos(), "melee": true, "status": {}, "splat": {}}
	sim.combat.deliver(dr, dz, h)
	await run(sim, 0.05)
	check(dz.state != Fighter.State.HITSTUN, "permanent armor during Landslide (state %s)" % dz.state_name())
	check(Content.creature(ID).abilities["ability1@juiced"].effects[0]["distance"] >= 10.0, "10 m Bulldoze range during Landslide")
	release(sim)


func test_taunt_hype() -> void:
	var r := await measure_move(ID, "taunt", 3.0, {"via": [{"t0": 0.0, "press": ["taunt"]}], "dur": 1.7, "keep": true})
	var a: Fighter = r["a"]
	check_near(a.hype, 8.0, 0.01, "taunt +8 Hype")
	check(count_events(r["events"], "taunt") == 1, "taunt plays")
	check_sane(r, "taunt")
	release(r)


func test_every_move_is_physically_sane() -> void:
	for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "taunt", "ability1", "ability2", "juice"]:
		var r := await measure_move(ID, slot, 3.4, {"rules": {"start_hype": 100} if slot == "juice" else {}, "radius": 8.0})
		check_sane(r, "%s (whiff)" % slot)


func test_cooldown_hook_action() -> void:
	# engine extension: {"type": "cooldown", "slot", "set" | "add"} resets/adjusts ability cooldowns
	var sim := kit_sim(ID, dummy(), 5.0)
	var f := sim.fighters[0]
	await run(sim, 0.2)
	f.cooldown_left["ability2"] = 9.0
	f.charges_left["ability2"] = 0
	f.hooks.run_inline({"do": [{"type": "cooldown", "slot": "ability2", "add": -3.0}]}, {})
	check_near(float(f.cooldown_left["ability2"]), 6.0, 0.001, "add -3 s")
	f.hooks.run_inline({"do": [{"type": "cooldown", "slot": "ability2", "set": 0.0}]}, {})
	check_near(float(f.cooldown_left["ability2"]), 0.0, 0.001, "set 0")
	check_eq(int(f.charges_left["ability2"]), 1, "charges refilled at 0")
	check(Hooks.validate({"on": "ability_used", "do": [{"type": "cooldown", "slot": "ability1", "set": 0}]}).is_empty(), "the action validates")
	release(sim)


func test_charge_hold_is_stationary() -> void:
	await check_charge_hold_stationary(ID)


func test_zy_measure_table() -> void:
	# ROSTER knockback metres on a 100 kg target (L3 / Quarry Ram are launchers: rise is printed)
	await measure_table(ID, [["l1", 1.5, 0.6], ["l2", 1.45, 0.4], ["l3", 1.4, -1.0], ["heavy", 1.5, 2.0],
		["heavy_charged", 2.6, -1.0], ["finisher", 1.4, 2.5],
		["dash_attack", 2.8, 2.0, [{"t0": 0.0, "t1": 0.7, "move": Vector3(0, 0, 1)}, {"t0": 0.0, "press": ["dodge"]}, {"t0": 0.12, "press": ["light"]}]],
		["ability1", 3.4, -1.0]])


func test_zz_balance() -> void:
	var n := int(OS.get_environment("KIT_BOUTS")) if OS.get_environment("KIT_BOUTS") != "" else 2
	if n <= 0:
		print("BALANCE skipped (KIT_BOUTS=0)")
		return
	var mirror := await spar("f_dozer", "f_dozer", n, "pro", 300)
	print("BALANCE dozer mirror: ", spar_summary(mirror))
	check(int(mirror["wins"]["side0"]) + int(mirror["wins"]["side1"]) + int(mirror["draws"]) == n, "bouts completed")
	check(float(mirror["dmg"]["side0"]) + float(mirror["dmg"]["side1"]) > 0.0, "damage dealt")
