extends "res://src/test/kits/dd_kit_base.gd"
## DREDGE (f_dredge) kit verification — docs/kits/f_dredge.md, ROSTER.md §2.
## Every move: connects at its intended range against a standing dummy and misses outside it;
## damage / knockback / stun / build-up / properties; guard and parry rules; cooldowns; JUICE;
## grab, pummel, throws; physical sanity (upright, no spin-out, no self-clip, cage, 1.6 m cap).
## Also the generic engine extensions added with this kit (directional dodge, heavy variants that
## can still charge, the throw_distance status).
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_f_dredge
## Balance bouts: set KIT_BOUTS=<n> (default 2) to run n bot bouts per pairing in test_zz_balance.

const ID := "f_dredge"

## slot, gaps that must connect (any), gap that must miss, melee weapon slot for the hit filter
const RANGE_TABLE := [
	["l1", [1.3, 1.45], 1.8],
	["l2", [1.3, 1.45], 1.75],
	["l3", [1.3, 1.5], 1.95],
	["heavy", [1.25, 1.35], 1.8],
	["finisher", [1.25, 1.4], 1.85],
]


func _soak(sim: MatchSim) -> void:
	var b: Fighter = sim.fighters[1]
	b.statuses.add_buildup("brine", 120.0, null)


func test_kit_is_complete_and_clean() -> void:
	var c := Content.creature(ID)
	check(c.is_valid(), "creature parses without errors: %s" % ", ".join(c.errors))
	for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "pummel", "taunt"]:
		check(c.moves.has(slot), "move slot %s present" % slot)
	for slot in ["ability1", "ability2", "juice"]:
		check(c.abilities.has(slot), "ability %s present" % slot)
	check_near(float(c.cooldowns["ability1"]), 6.0, 0.001, "Tide Spit cooldown")
	check_near(float(c.cooldowns["ability2"]), 10.0, 0.001, "Anchor Drop cooldown")
	for k in ["throw_fwd", "throw_side", "throw_back"]:
		check(c.throws.has(k), "throw %s present" % k)
	var raw := FileAccess.get_file_as_string("res://content/core/creatures/f_dredge.json")
	check(not raw.contains("_stub"), "no stub moves left")
	check_near(c.stat("health"), 140.0, 0.01, "HP")
	check_near(c.stat("walk_speed"), 2.6, 0.01, "forward walk")
	check_near(c.stat("side_speed"), 3.2, 0.01, "side walk")
	check_near(c.stat("dodge_distance"), 2.2, 0.01, "forward dash")
	check_near(c.stat("dodge_side_distance"), 3.0, 0.01, "side dash")
	check_near(c.stat("poise"), 90.0, 0.01, "poise")
	check_near(c.stat("stamina"), 90.0, 0.01, "stamina")
	check(not c.passives.is_empty(), "kit passives present")
	check(c.ai.has("abilities") and c.ai.has("range"), "bot hints present")
	var t: MoveDef = c.moves["taunt"]
	check_near(t.duration, 1.5, 0.001, "taunt lasts 1.5 s")
	check(t.armor.is_empty(), "taunt has no armor")
	check_near(c.abilities["juice"].duration, 0.6, 0.11, "JUICE activation ~0.5 s")


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
			var h: Dictionary = best["melee"][0]
			check(float(h["damage"]) > 0.0, "%s deals damage" % slot)
			check(best["b_states"].has("hitstun") or best["b_states"].has("knockdown"), "%s staggers the dummy" % slot)
			check(float(best["b_buildup"].get("brine", 0.0)) > 0.0 or best["b_states"].has("knockdown"), "%s adds Brine build-up" % slot)
		var miss := await measure_move(ID, slot, float(row[2]))
		check(miss["melee"].is_empty(), "%s misses at %.2f m (got %d melee hits)" % [slot, row[2], miss["melee"].size()])


func test_light_string_and_finisher_via_input() -> void:
	var r := await measure_move(ID, "l1", 1.3, {"via": [{"t0": 0.0, "press": ["light"]}, {"t0": 0.24, "press": ["light"]},
		{"t0": 0.58, "press": ["light"]}, {"t0": 0.93, "press": ["heavy"]}], "dur": 2.4})
	var slots: Array = r["slots"]
	check(slots.size() >= 4 and slots.slice(0, 4) == ["l1", "l2", "l3", "finisher"], "L1 > L2 > L3 > Finisher chain (got %s)" % str(slots))
	check(r["melee"].size() >= 3, "the string lands several hits (%d)" % r["melee"].size())
	check_sane(r, "string")


func test_crusher_slam_armor_and_wave_line() -> void:
	# armored startup: a jab during the windup does not interrupt the slam
	var sb := InputSource.Scripted.new([{"t0": 0.42, "t1": 0.45, "press": ["light"]}])
	var r := await measure_move(ID, "heavy", 1.85, {"sb": sb, "dummy": Content.creature("f_dozer"), "keep": true})
	var a: Fighter = r["a"]
	check(a.stats_record["damage_taken"] > 0.0, "Dozer's snout jab tags Dredge during the slam's windup")
	check(not r["hits"].is_empty(), "the armored slam lands through the jab (not interrupted)")
	release(r)
	# the wave line reaches past the claw (2.6 m) and trips a Soaked target
	var far := await measure_move(ID, "heavy", 2.6, {"before": _soak})
	check(far["melee"].is_empty() and not far["effect_hits"].is_empty(), "wave line hits at 2.6 m where the claw cannot")
	check(far["b_states"].has("knockdown"), "wave trips (knocks down) a Soaked target")
	var dry := await measure_move(ID, "heavy", 2.6)
	check(not dry["effect_hits"].is_empty() and not dry["b_states"].has("knockdown"), "wave does not trip a dry target")
	var juiced := await measure_move(ID, "heavy@juiced", 4.2)
	check(not juiced["effect_hits"].is_empty(), "High Tide wave line reaches 4 m+ (hit at 4.2 m)")
	var plain := await measure_move(ID, "heavy", 4.2)
	check(plain["effect_hits"].is_empty(), "normal wave line stops short of 4.2 m")


func test_charged_heavy_hull_breaker() -> void:
	# hold Heavy: the slam freezes in its windup (armored vs lights) and switches to Hull Breaker
	var r := await measure_move(ID, "heavy", 1.35, {"via": [{"t0": 0.0, "press": ["heavy"]}, {"t0": 0.0, "t1": 0.85, "hold": ["heavy"]}],
		"dur": 2.4, "dummy": Content.creature("f_dozer")})
	check("heavy_charged" in r["slots"], "a long hold becomes Hull Breaker (%s)" % str(r["slots"]))
	check(not r["melee"].is_empty(), "Hull Breaker connects")
	var puddles := 0
	for ev in r["events"]:
		if ev["type"] == "effect" and str(ev.get("effect", "")) == "zone" and str(ev.get("move", "")).ends_with("heavy_charged"):
			puddles += 1
	check(puddles == 1, "Hull Breaker leaves a Brine puddle at impact")
	check_sane(r, "hull_breaker")
	# guard-crush: drains far more guard stamina than the tap slam
	var g := InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])
	var crush := await measure_move(ID, "heavy_charged", 1.3, {"sb": g, "dummy": Content.creature("f_dozer"), "keep": true})
	var blocked_crush := count_events(crush["events"], "hit", "blocked", true)
	var st_crush: float = crush["b"].max_stamina - crush["b"].stamina
	release(crush)
	var g2 := InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])
	var tap := await measure_move(ID, "heavy", 1.3, {"sb": g2, "dummy": Content.creature("f_dozer"), "keep": true})
	var st_tap: float = tap["b"].max_stamina - tap["b"].stamina
	release(tap)
	check(blocked_crush >= 1, "Hull Breaker into guard is blocked (not unblockable)")
	check(st_crush > st_tap * 2.0, "guard-crush drains much more stamina (%.1f vs %.1f)" % [st_crush, st_tap])


func test_double_clamp_hold_on_soaked() -> void:
	var wet := await measure_move(ID, "l3", 1.2, {"before": _soak, "keep": true, "dummy": Content.creature("f_dozer")})
	var dry := await measure_move(ID, "l3", 1.2, {"keep": true, "dummy": Content.creature("f_dozer")})
	check(not wet["melee"].is_empty() and not dry["melee"].is_empty(), "Double Clamp lands on both")
	var t_wet := float(wet.get("b_stun_time", 0.0))
	var t_dry := float(dry.get("b_stun_time", 0.0))
	check(t_wet > t_dry + 0.25, "Clamp Hold: a Soaked target is held ~0.4 s longer (%.2f vs %.2f s)" % [t_wet, t_dry])
	release(wet)
	release(dry)


func test_bilge_pump_shoves_into_wall_for_splat() -> void:
	var r := await measure_move(ID, "finisher", 1.3, {"radius": 2.6})
	check(not r["melee"].is_empty(), "Bilge Pump clamps the target")
	check(count_events(r["events"], "splat") >= 1, "the shove into the cage wall splats (+dmg, +stun)")
	var open := await measure_move(ID, "finisher", 1.3, {"dummy": dummy(100.0)})
	check(float(open["kb"]) > 1.2, "shoves a 100 kg target well back (%.2f m)" % open["kb"])


func test_scuttle_check_forward_and_sideways() -> void:
	var fwd := await measure_move(ID, "dash_attack", 2.2, {"via": [{"t0": 0.0, "t1": 0.7, "move": Vector3(0, 0, 1)},
		{"t0": 0.0, "press": ["dodge"]}, {"t0": 0.12, "press": ["light"]}], "dur": 1.6})
	check("dash_attack" in fwd["slots"], "Light during a dodge becomes Scuttle Check")
	check(not fwd["melee"].is_empty(), "forward Scuttle Check connects after a dash from 2.2 m")
	check_sane(fwd, "scuttle fwd")
	# sideways: the dummy stands to Dredge's left; dash left into it (shell side leads)
	var side := await measure_move(ID, "dash_attack", 0.0, {"b_offset": Vector3(2.4, 0, 0), "b_yaw": -90.0,
		"via": [{"t0": 0.0, "t1": 0.7, "move": Vector3(1, 0, 0)}, {"t0": 0.0, "press": ["dodge"]}, {"t0": 0.12, "press": ["light"]}], "dur": 1.6, "keep": true})
	var a: Fighter = side["a"]
	check(not side["melee"].is_empty(), "sideways Scuttle Check connects")
	check(a.has_flag("dodge_side") or count_events(side["events"], "dodge") == 1, "the dash was a side dash")
	if not side["melee"].is_empty():
		var nominal := (7.0 + 1.0) * 1.15 * 1.5
		check(float(side["melee"][0]["damage"]) <= nominal, "side bonus is +1 dmg, not more")
	check(a.creature.moves["dash_attack"].on_hit.size() == 1, "side bonus hook present")
	release(side)


func test_side_dash_is_longer_and_flags() -> void:
	# engine extension: dodge_side_distance + "dodge_side" flag
	var sim := kit_sim(ID, dummy(), 4.0, InputSource.Scripted.new([{"t0": 0.4, "t1": 0.9, "move": Vector3(1, 0, 0)}, {"t0": 0.4, "t1": 0.43, "press": ["dodge"]}]))
	var a := sim.fighters[0]
	await run(sim, 0.39)
	var p0 := a.pos()
	await run(sim, 0.05)
	check(a.has_flag("dodge_side"), "a sideways dodge sets the dodge_side flag")
	await run(sim, 0.5)
	var side_d := Vector2(a.pos().x - p0.x, a.pos().z - p0.z).length()
	release(sim)
	var sim2 := kit_sim(ID, dummy(), 6.0, InputSource.Scripted.new([{"t0": 0.4, "t1": 0.9, "move": Vector3(0, 0, 1)}, {"t0": 0.4, "t1": 0.43, "press": ["dodge"]}]))
	var a2 := sim2.fighters[0]
	await run(sim2, 0.39)
	var q0 := a2.pos()
	await run(sim2, 0.05)
	check(not a2.has_flag("dodge_side"), "a forward dodge does not")
	await run(sim2, 0.5)
	var fwd_d := Vector2(a2.pos().x - q0.x, a2.pos().z - q0.z).length()
	release(sim2)
	check(side_d > fwd_d + 0.4, "side dash travels farther than the forward dash (%.2f vs %.2f m)" % [side_d, fwd_d])
	check(fwd_d > 1.4 and fwd_d < 3.0, "forward dash ~2.2 m (%.2f)" % fwd_d)
	check(side_d > 2.2 and side_d < 3.8, "side dash ~3.0 m (%.2f)" % side_d)


func test_side_walk_is_faster() -> void:
	var sim := kit_sim(ID, dummy(), 4.0, InputSource.Scripted.new([{"t0": 0.3, "t1": 1.5, "move": Vector3(1, 0, 0)}]))
	var a := sim.fighters[0]
	await run(sim, 0.8)
	var v_side := Vector2(a.rig.com_velocity().x, a.rig.com_velocity().z).length()
	release(sim)
	var sim2 := kit_sim(ID, dummy(), 6.0, InputSource.Scripted.new([{"t0": 0.3, "t1": 1.5, "move": Vector3(0, 0, -1)}]))
	var a2 := sim2.fighters[0]
	await run(sim2, 0.8)
	var v_back := Vector2(a2.rig.com_velocity().x, a2.rig.com_velocity().z).length()
	release(sim2)
	check(v_side > 2.8, "scuttles sideways at ~3.2 m/s (%.2f)" % v_side)
	check(v_side > v_back + 0.5, "sideways is his fast direction (%.2f vs back %.2f)" % [v_side, v_back])


func test_grab_reach_pummel_and_throws() -> void:
	var grab := await measure_move(ID, "grab", 1.45, {"via": [{"t0": 0.0, "press": ["grab"]}], "dur": 0.9, "keep": true})
	check(count_events(grab["events"], "grab") == 1, "Clamp grabs at 1.45 m root gap (~1.3 m reach)")
	release(grab)
	var miss := await measure_move(ID, "grab", 1.8, {"via": [{"t0": 0.0, "press": ["grab"]}], "dur": 0.9})
	check(count_events(miss["events"], "grab") == 0, "Clamp misses at 1.8 m")
	# Dredge turns toward the victim held in his right claw, so "side" is aimed left-forward of spawn facing
	for kind in [["throw_fwd", Vector3(0, 0, 1)], ["throw_side", Vector3(1, 0, 0.5).normalized()], ["throw_back", Vector3(0, 0, -1)]]:
		var r := await measure_move(ID, "grab", 1.4, {"dummy": dummy(100.0), "keep": true, "dur": 2.5, "via": [{"t0": 0.0, "press": ["grab"]},
			{"t0": 0.5, "press": ["light"]}, {"t0": 0.95, "press": ["light"]}, {"t0": 1.3, "t1": 1.5, "move": kind[1]}, {"t0": 1.35, "press": ["heavy"]}]})
		var b: Fighter = r["b"]
		var pummels := 0
		var throw_dmg := 0.0
		for ev in r["events"]:
			if ev["type"] == "hit" and str(ev.get("slot", "")) == "pummel":
				pummels += 1
				check_near(float(ev["damage"]), 4.0 * Content.creature(ID).stat("power"), 0.01, "pummel squeeze 4 dmg (x power)")
			if ev["type"] == "hit" and str(ev.get("slot", "")) == "throw":
				throw_dmg = float(ev["damage"])
		var throws := []
		for ev2 in r["events"]:
			if ev2["type"] == "throw":
				throws.append(str(ev2["kind"]))
		check(pummels == 2, "%s: two pummels landed (%d)" % [kind[0], pummels])
		check(throws == [kind[0]], "%s thrown (%s)" % [kind[0], str(throws)])
		var expected: float = {"throw_fwd": 12.0, "throw_side": 9.0, "throw_back": 8.0}[kind[0]]
		check_near(throw_dmg, expected * Content.creature(ID).stat("power"), 0.01, "%s damage (x power)" % kind[0])
		check(float(b.statuses.buildup.get("brine", 0.0)) > 0.0 or b.statuses.has_element("brine"), "%s: pummels add Brine build-up" % kind[0])
		var land := b.pos() - Vector3(r["b_start"])
		var a_fwd := Vector3(0, 0, 1)
		if kind[0] == "throw_back":
			var a: Fighter = r["a"]
			check(land.dot(a_fwd) < -0.6, "Over-the-Shell lands behind Dredge (%.2f m)" % land.dot(a_fwd))
			var to_a := a.pos() - b.pos()
			to_a.y = 0.0
			check(b.is_down() and MathX.forward_of_yaw(b.facing_yaw).dot(to_a.normalized()) < 0.0, "target lands facing away from Dredge")
		elif kind[0] == "throw_fwd":
			check(land.dot(a_fwd) > 1.5, "Overhead Hurl carries the target forward (%.2f m)" % land.dot(a_fwd))
		release(r)


func test_tide_spit_projectile_puddle_cooldown() -> void:
	var r := await measure_move(ID, "ability1", 4.0, {"via": [{"t0": 0.0, "press": ["ability1"]}, {"t0": 1.5, "press": ["ability1"]}, {"t0": 6.3, "press": ["ability1"]}],
		"dur": 7.6, "keep": true})
	var spits := 0
	var puddles := 0
	for ev in r["events"]:
		if ev["type"] == "ability" and int(ev["fighter"]) == 0:
			spits += 1
		if ev["type"] == "effect" and str(ev.get("effect", "")) == "zone":
			puddles += 1
	check(spits == 2, "Tide Spit obeys its 6 s cooldown (used %d times of 3 presses)" % spits)
	check(not r["effect_hits"].is_empty(), "the lob hits a target 4 m away")
	check(puddles >= 1, "a Brine puddle is left where it lands")
	check(float(r["b_buildup"].get("brine", 0.0)) > 0.0 or (r["b"] as Fighter).statuses.has_element("brine"), "40 Brine build-up per glob")
	release(r)
	# reflectable
	var refl := await measure_move(ID, "ability1", 4.0, {"before": func(sim: MatchSim) -> void: sim.fighters[1].set_flag("reflect", 3.0), "dur": 2.2, "keep": true})
	check(count_events(refl["events"], "reflect") >= 1, "the glob can be reflected")
	release(refl)


func test_anchor_drop_counter_armor_and_grab() -> void:
	# the attacker (Stoke stub kit or Dozer) hits Dredge during Anchor Drop: counter snap fires, no stagger
	var sim := kit_sim(ID, ID, 1.3, InputSource.Scripted.new([{"t0": 0.3, "t1": 0.33, "press": ["ability2"]}]))
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	await run(sim, 0.6)
	check(a.counter_active(), "counter stance active")
	check(a.statuses.has("anchored"), "anchored status (knockback taken -50%)")
	# a heavy melee hit lands on the anchored crab (delivered through the combat funnel)
	var h := {"attacker": b, "damage": 12.0, "point": a.pos(), "normal": Vector3.BACK, "seg": 0, "part": "shell", "blocked": false,
		"parried": false, "counter": false, "knockback": Vector3(0, 0, -4.0), "local_impulse": Vector3.ZERO, "stun": 0.6, "poise": 30.0,
		"knockdown": false, "hype_mult": 1.0, "element": "", "buildup": 0.0, "move": "test", "slot": "heavy", "move_class": "heavy",
		"from": b.pos(), "melee": true, "status": {}, "splat": {}}
	sim.combat.deliver(b, a, h)
	await run(sim, 0.1)
	check(count_events(sim.events, "counter") == 1, "a melee hit on Dredge triggers the claw-snap counter")
	check_near(b.max_health - b.health, 6.0, 0.6, "the counter snap deals 6 to the attacker")
	check(b.statuses.buildup.get("brine", 0.0) > 0.0 or b.statuses.has_element("brine"), "counter adds Brine build-up")
	check(a.state == Fighter.State.ABILITY, "armor: the heavy hit does not stagger him (state %s)" % a.state_name())
	# area effects (not melee) do not trigger it
	sim.effects.effect_hit(b, a, {"damage": 3.0, "knockback": 1.0}, b.pos())
	await run(sim, 0.05)
	check(count_events(sim.events, "counter") == 1, "non-melee hits do not trigger the counter")
	release(sim)
	# cannot walk, turns slowly
	var sim2 := kit_sim(ID, dummy(), 3.0, InputSource.Scripted.new([{"t0": 0.3, "t1": 0.33, "press": ["ability2"]}, {"t0": 0.5, "t1": 2.6, "move": Vector3(1, 0, 0)}]))
	var a2 := sim2.fighters[0]
	await run(sim2, 0.5)
	var q0 := a2.pos()
	await run(sim2, 2.0)
	check(Vector2(a2.pos().x - q0.x, a2.pos().z - q0.z).length() < 0.3, "cannot walk while anchored")
	release(sim2)
	# grabs still work on him
	var sim3 := kit_sim(ID, "f_dozer", 1.35, InputSource.Scripted.new([{"t0": 0.3, "t1": 0.33, "press": ["ability2"]}]),
		InputSource.Scripted.new([{"t0": 0.7, "t1": 0.73, "press": ["grab"]}]))
	await run(sim3, 1.6)
	check(count_events(sim3.events, "grab") >= 1, "grabs beat the anchor's armor")
	release(sim3)
	# cooldown 10 s
	var sim4 := kit_sim(ID, dummy(), 3.0, InputSource.Scripted.new([{"t0": 0.3, "t1": 0.33, "press": ["ability2"]}, {"t0": 4.0, "t1": 4.03, "press": ["ability2"]}, {"t0": 10.5, "t1": 10.53, "press": ["ability2"]}]))
	await run(sim4, 11.0)
	check(count_events(sim4.events, "ability", "fighter", 0) == 2, "Anchor Drop cooldown 10 s")
	release(sim4)


func test_juice_high_tide() -> void:
	var r := await measure_move(ID, "juice", 3.5, {"rules": {"start_hype": 100}, "via": [{"t0": 0.0, "press": ["juice"]}], "dur": 10.0, "keep": true})
	var a: Fighter = r["a"]
	var b: Fighter = r["b"]
	check(count_events(r["events"], "juice") == 1, "JUICE activates at 100 Hype")
	check(r["b_states"].has("knockdown"), "the ground-wave ring knocks down a target 3.5 m away")
	check(count_events(r["events"], "juice_end") == 1, "JUICE ends")
	check(a.time >= a.crash_until - 2.01 and a.crash_until > 0.0, "ends with the crash downside")
	check(b.statuses.has_element("brine") or float(b.statuses.buildup.get("brine", 0.0)) > 30.0, "the flooded floor soaks the opponent")
	check(not a.statuses.has_element("brine"), "Dredge is immune to his own flood")
	release(r)
	# during High Tide: faster walk, longer throws, longer wave line
	var sim := kit_sim(ID, dummy(), 4.0, InputSource.Scripted.new([{"t0": 0.2, "t1": 0.23, "press": ["juice"]}, {"t0": 1.2, "t1": 2.4, "move": Vector3(0, 0, -1)}]), null, {"start_hype": 100})
	var a2 := sim.fighters[0]
	await run(sim, 1.0)
	check(a2.has_flag("juiced") and a2.statuses.mult("throw_distance") > 1.25, "throws +30% while juiced")
	await run(sim, 1.0)
	var v := Vector2(a2.rig.com_velocity().x, a2.rig.com_velocity().z).length()
	check(v > 2.7, "walks faster during High Tide (%.2f m/s backing up)" % v)
	release(sim)


func test_taunt_hype_and_no_armor() -> void:
	var r := await measure_move(ID, "taunt", 1.6, {"via": [{"t0": 0.0, "press": ["taunt"]}], "dur": 1.0, "keep": true,
		"sb": InputSource.Scripted.new([{"t0": 0.0, "t1": 2.0, "move": "to_target"}, {"t0": 0.65, "t1": 0.68, "press": ["light"]}])})
	var a: Fighter = r["a"]
	check_near(a.hype, 8.0, 3.0, "taunt +8 Hype (+ hit hype)")
	check(count_events(r["events"], "taunt") == 1, "taunt plays")
	release(r)


func test_every_move_is_physically_sane() -> void:
	for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "taunt", "ability1", "ability2", "juice"]:
		var r := await measure_move(ID, slot, 3.2, {"rules": {"start_hype": 100} if slot == "juice" else {}})
		check_sane(r, "%s (whiff)" % slot)


func test_heavy_variant_still_charges() -> void:
	# engine fix: a "heavy@juiced" variant switches to heavy_charged on a long hold
	var sim := kit_sim(ID, dummy(), 3.0, InputSource.Scripted.new([{"t0": 0.2, "t1": 0.23, "press": ["juice"]},
		{"t0": 1.4, "t1": 1.43, "press": ["heavy"]}, {"t0": 1.4, "t1": 2.3, "hold": ["heavy"]}]), null, {"start_hype": 100})
	await run(sim, 3.2)
	var slots := []
	for ev in sim.events:
		if ev["type"] == "move_start" and int(ev["fighter"]) == 0:
			slots.append(str(ev["slot"]))
	check(slots.has("heavy@juiced") and slots.has("heavy_charged"), "juiced slam charges into Hull Breaker (%s)" % str(slots))
	release(sim)


func test_charge_hold_is_stationary() -> void:
	await check_charge_hold_stationary(ID)


func test_zy_measure_table() -> void:
	# ROSTER knockback metres on a 100 kg target (sideways for L2, radial shove for the finisher)
	await measure_table(ID, [["l1", 1.35, 0.5], ["l2", 1.35, 1.2], ["l3", 1.35, 0.8], ["heavy", 1.3, 1.0],
		["heavy_charged", 1.3, -1.0], ["finisher", 1.3, 2.5],
		["dash_attack", 2.2, 2.0, [{"t0": 0.0, "t1": 0.7, "move": Vector3(0, 0, 1)}, {"t0": 0.0, "press": ["dodge"]}, {"t0": 0.12, "press": ["light"]}]],
		["ability1", 4.0, 1.0]])


func test_zz_balance() -> void:
	var n := int(OS.get_environment("KIT_BOUTS")) if OS.get_environment("KIT_BOUTS") != "" else 2
	if n <= 0:
		print("BALANCE skipped (KIT_BOUTS=0)")
		return
	var cross := await spar("f_dredge", "f_dozer", n)
	print("BALANCE dredge vs dozer: ", spar_summary(cross))
	var mirror := await spar("f_dredge", "f_dredge", n)
	print("BALANCE dredge mirror: ", spar_summary(mirror))
	check(int(cross["wins"]["f_dredge"]) + int(cross["wins"]["f_dozer"]) + int(cross["draws"]) == n, "bouts completed")
	check(float(cross["dmg"]["f_dredge"]) > 0.0 and float(cross["dmg"]["f_dozer"]) > 0.0, "both fighters land damage")
	if n >= 20:
		var share := float(cross["wins"]["f_dredge"]) / maxf(1.0, float(n - int(cross["draws"])))
		check(share >= 0.35 and share <= 0.65, "Dredge vs Dozer within 35-65%% (%.0f%%)" % (share * 100.0))
