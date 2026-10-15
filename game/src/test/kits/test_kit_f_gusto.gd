extends "res://src/test/kits/kit_harness_stoke_gusto.gd"
## GUSTO (f_gusto) kit verification — docs/kits/f_gusto.md, docs/design/ROSTER.md §3.
## Same contract as test_kit_f_stoke.gd: every move is driven against a standing dummy (mirror and
## Stoke) and checked for contact inside its range, no contact beyond it, damage / stun / poise /
## Gale build-up, reach ≤ 1.6 m from the root and attacker stability; then every special property
## (multi-hits, Winded follow-ups, wind push, leap + landing area, spin, trip, hover with the aerial
## variants, projectile with burst, cheap dodges, grab/pecks/throws incl. Carry-and-Drop, JUICE).
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_f_gusto

const CID := "f_gusto"
const FOE := "f_stoke"

const STRIKES := {
	"l1": {"hit": [1.3, 1.4], "hit_foe": [1.1, 1.3], "miss": 1.95},
	"l2": {"hit": [1.2, 1.25], "hit_foe": [1.1, 1.25], "miss": 1.65},
	"l3": {"hit": [1.3, 1.4], "hit_foe": [1.2, 1.3], "miss": 1.85},
	"heavy": {"hit": [1.2, 1.5], "hit_foe": [1.4, 1.6], "miss": 2.45},
	"heavy_charged": {"hit": [1.8, 2.2], "hit_foe": [1.8, 2.2], "miss": 4.4},
	"finisher": {"hit": [1.4, 1.6], "hit_foe": [1.2, 1.4], "miss": 3.4},
	"dash_attack": {"hit": [1.4, 1.6], "hit_foe": [1.4, 1.6], "miss": 2.4},
}


func test_stats_slots_and_data() -> void:
	var c := Content.creature(CID)
	check(c != null and c.is_valid(), "creature loads without errors: %s" % (str(c.errors) if c else "missing"))
	check_near(c.stat("health"), 85.0, 0.01, "health")
	check_near(c.stat("walk_speed"), 4.3, 0.01, "walk speed")
	check_near(c.stat("stamina"), 110.0, 0.01, "stamina")
	check_near(c.stat("poise"), 40.0, 0.01, "poise")
	check_near(c.stat("dodge_distance"), 3.6, 0.01, "dash distance (longest)")
	check_near(c.body.total_mass, 55.0, 0.5, "mass")
	for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "pummel", "taunt", "l1@hovering", "heavy@hovering"]:
		check(c.moves.has(slot), "move slot %s" % slot)
	for slot in ["ability1", "ability2", "juice"]:
		check(c.abilities.has(slot), "ability slot %s" % slot)
	check_near(float(c.cooldowns["ability1"]), 5.0, 0.01, "Gust Bomb cooldown")
	check_near(float(c.cooldowns["ability2"]), 6.0, 0.01, "Hang Time cooldown")
	check_near(float(c.juice.get("duration", 0.0)), 7.0, 0.01, "Hurricane Strut lasts 7 s")
	var raw := FileAccess.get_file_as_string("res://content/core/creatures/%s.json" % CID)
	check(not raw.contains("_stub"), "no stub moves left")
	check_near(c.moves["taunt"].duration, 1.5, 0.001, "taunt lasts 1.5 s")
	_check_timing(c.moves["l1"], [0.10, 0.08, 0.18], 4.0, 4.0)
	_check_timing(c.moves["l2"], [0.12, 0.12, 0.20], 4.0, 2.0)
	_check_timing(c.moves["l3"], [0.16, 0.10, 0.30], 7.0, 7.0)
	_check_timing(c.moves["heavy"], [0.24, 0.12, 0.40], 11.0, 6.0)
	_check_timing(c.moves["finisher"], [0.15, 0.40, 0.45], 10.0, 3.0)
	_check_timing(c.moves["dash_attack"], [0.10, 0.12, 0.30], 7.0, 6.0)
	for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "pummel", "l1@hovering"]:
		check_eq(c.moves[slot].element, "gale", "%s is Gale" % slot)


func _check_timing(m: MoveDef, sar: Array, stamina: float, damage: float) -> void:
	var t0 := m.first_active()
	var t1 := float(m.windows[m.windows.size() - 1]["t1"])
	check_near(t0, float(sar[0]), 0.045, "%s startup" % m.id)
	check_near(t1 - t0, float(sar[1]), 0.06, "%s active" % m.id)
	check_near(m.duration - t1, float(sar[2]), 0.06, "%s recovery" % m.id)
	check_near(m.stamina, stamina, 0.01, "%s stamina" % m.id)
	check_near(m.damage, damage, 0.01, "%s damage per hit" % m.id)


func test_strikes_connect_in_range_and_miss_beyond() -> void:
	var c := Content.creature(CID)
	for slot in STRIKES:
		var spec: Dictionary = STRIKES[slot]
		var m: MoveDef = c.moves[slot]
		for pair in [[CID, "hit"], [FOE, "hit_foe"]]:
			for gap in spec[pair[1]]:
				var r := await run_move(CID, {"slot": slot, "gap": gap, "def_id": pair[0]})
				check_strike(r, m, "%s vs %s @%.2f" % [slot, pair[0], gap], "gale")
				dispose(r["sim"])
		var rm := await run_move(CID, {"slot": slot, "gap": float(spec["miss"])})
		check(hits_with_damage(rm).is_empty(), "%s must not connect at %.2f m: %s" % [slot, spec["miss"], describe(rm)])
		check_stable(rm, "%s whiff" % slot)
		dispose(rm["sim"])


func test_multi_hits_and_wind_push() -> void:
	# Beak Peck: two pecks; Tailspin: three hits; Crosswind Slash: wings + a wind push even on a miss
	var pk := await run_move(CID, {"slot": "l2", "gap": 1.25, "def_id": FOE})
	check(hits_with_damage(pk).size() >= 2, "Beak Peck hits twice: %s" % describe(pk))
	dispose(pk["sim"])
	var ts := await run_move(CID, {"slot": "finisher", "gap": 1.3, "def_id": FOE})
	check(hits_with_damage(ts).size() >= 3, "Tailspin hits three times: %s" % describe(ts))
	check(float((ts["tgt_disp"] as Vector3).length()) > 1.2, "Tailspin pushes the target away (%.2f)" % (ts["tgt_disp"] as Vector3).length())
	check(float(ts["att_disp"]) > 0.6, "Tailspin drifts forward (%.2f)" % float(ts["att_disp"]))
	check_stable(ts, "Tailspin")
	dispose(ts["sim"])
	var cw := await run_move(CID, {"slot": "heavy", "gap": 1.5, "def_id": FOE})
	check(hits_with_damage(cw).size() >= 1, "Crosswind Slash connects: %s" % describe(cw))
	dispose(cw["sim"])
	var wind := await run_move(CID, {"slot": "heavy", "gap": 2.3, "def_id": FOE})
	check(hits_with_damage(wind).is_empty(), "wings miss at 2.3 m")
	check(float((wind["tgt_disp"] as Vector3).z) > 0.4, "the wind still pushes the target (%.2f m)" % float((wind["tgt_disp"] as Vector3).z))
	dispose(wind["sim"])


func _wind(f: Fighter, by: Fighter) -> void:
	f.statuses.add_buildup("gale", 100.0, by)


func _soak(f: Fighter, by: Fighter) -> void:
	f.statuses.add_buildup("brine", 100.0, by)


func test_winded_follow_ups_launch_and_trip() -> void:
	# Scissor Kick: knock-up only if the target is Winded
	var plain := await run_move(CID, {"slot": "l3", "gap": 1.4})
	var wnd := await run_move(CID, {"slot": "l3", "gap": 1.4, "setup": func(s: MatchSim): _wind(s.fighters[1], s.fighters[0])})
	check(not hits_with_damage(wnd).is_empty(), "kick connects on the Winded target")
	check(float(wnd["tgt_rise"]) > float(plain["tgt_rise"]) + 0.2, "Winded target is knocked up (%.2f vs %.2f)" % [wnd["tgt_rise"], plain["tgt_rise"]])
	dispose(plain["sim"])
	dispose(wnd["sim"])
	# Skid Kick: trip (knockdown) only on Winded or Soaked targets
	var sk := await run_move(CID, {"slot": "dash_attack", "gap": 1.5, "def_id": FOE})
	check(not hits_with_damage(sk).is_empty(), "Skid Kick connects")
	check(not bool(sk["knockdown"]), "no trip on a fresh target")
	dispose(sk["sim"])
	for setup in [func(s: MatchSim): _wind(s.fighters[1], s.fighters[0]), func(s: MatchSim): _soak(s.fighters[1], s.fighters[0])]:
		var tr := await run_move(CID, {"slot": "dash_attack", "gap": 1.5, "def_id": FOE, "setup": setup})
		check(bool(tr["knockdown"]), "Skid Kick trips a Winded/Soaked target: %s" % describe(tr))
		dispose(tr["sim"])


func test_skid_kick_from_dodge_and_cheap_dodges() -> void:
	var d := Driver.new()
	d.dirs = [{"t0": 0.18, "t1": 0.45, "dir": Vector3(0, 0, 1)}]
	d.presses = [{"t": 0.2, "button": FighterInput.DODGE}, {"t": 0.33, "button": FighterInput.LIGHT}]
	var r := await run_move(CID, {"att_src": d, "slot": "dash_attack", "gap": 2.8, "def_id": FOE, "watch": 1.4})
	var dh := (r["hits"] as Array).filter(func(h): return str(h["slot"]) == "dash_attack" and float(h["dmg"]) > 0.0)
	check(not dh.is_empty(), "Light during the dash is the Skid Kick and it connects from 2.8 m: %s" % describe(r))
	check_stable(r, "Skid Kick")
	dispose(r["sim"])
	# a dodge costs Gusto 8 stamina (12 for everyone else)
	var dd := Driver.new()
	dd.presses = [{"t": 0.2, "button": FighterInput.DODGE}]
	var sim := duel(CID, FOE, 4.0, dd)
	await step_sim(sim, INTRO + 0.3)
	check_near(sim.fighters[0].max_stamina - sim.fighters[0].stamina, 8.0, 0.6, "Gusto's dodge costs 8")
	check(sim.fighters[0].state == Fighter.State.DODGE or not events_of(sim, "dodge").is_empty(), "dodged")
	dispose(sim)


func test_downdraft_leap_direct_hit_and_landing_area() -> void:
	var r := await run_move(CID, {"slot": "heavy_charged", "gap": 2.0, "def_id": FOE, "watch": 1.8})
	var direct := (r["hits"] as Array).filter(func(h): return str(h["slot"]) == "heavy_charged" and float(h["dmg"]) > 0.0)
	var area := (r["hits"] as Array).filter(func(h): return str(h["slot"]) == "effect" and float(h["dmg"]) > 0.0)
	check(not direct.is_empty(), "both feet connect: %s" % describe(r))
	check(not area.is_empty(), "landing area hits")
	check(int(r.get("ev_land", 0)) >= 1, "Downdraft is a real leap (landing event)")
	check(float(r["att_rise"]) > 0.3, "Gusto leaves the floor (%.2f)" % float(r["att_rise"]))
	check(float(r["att_disp"]) > 1.2, "leaps toward the target (%.2f)" % float(r["att_disp"]))
	check(float(r["tgt_rise"]) > 0.3, "direct hit knocks up (%.2f)" % float(r["tgt_rise"]))
	check_stable(r, "Downdraft")
	dispose(r["sim"])
	# only the landing area reaches a target that the feet miss
	var near := await run_move(CID, {"slot": "heavy_charged", "gap": 3.4, "def_id": FOE, "watch": 1.8})
	var a2 := (near["hits"] as Array).filter(func(h): return str(h["slot"]) == "effect" and float(h["dmg"]) > 0.0)
	check(not a2.is_empty() or not hits_with_damage(near).is_empty(), "landing area reaches 1.5 m around the landing point")
	dispose(near["sim"])
	# a charged Heavy hold turns into the Downdraft
	var d := Driver.new()
	d.holds = [{"t0": 0.2, "t1": 0.95, "button": FighterInput.HEAVY}]
	d.presses = [{"t": 0.2, "button": FighterInput.HEAVY}]
	var sim := duel(CID, FOE, 2.0, d)
	await step_sim(sim, INTRO + 1.6)
	var slots := events_of(sim, "move_start").filter(func(e): return int(e["fighter"]) == 0).map(func(e): return str(e["slot"]))
	check(slots.has("heavy_charged"), "hold Heavy -> Downdraft (%s)" % str(slots))
	dispose(sim)


func test_hang_time_hover_zone_immunity_and_aerials() -> void:
	var d := Driver.new()
	d.presses = [{"t": 0.2, "button": FighterInput.AB2}]
	var sim := duel(CID, FOE, 3.0, d)
	await step_sim(sim, INTRO + 0.1)
	var g := sim.fighters[0]
	var y0 := g.pos().y
	# an enemy zone under Gusto
	sim.effects.spawn_zone(sim.fighters[1], {"kind": "scorch_patch", "radius": 1.5, "duration": 3.0, "skip_zone_reaction": true}, g.ground_pos())
	await step_sim(sim, 0.8)
	check(g.has_flag("hovering"), "Hang Time hovers")
	check(g.pos().y > y0 + 1.3, "hops ~2 m up (%.2f -> %.2f)" % [y0, g.pos().y])
	var hp := g.health
	await step_sim(sim, 0.4)
	check_near(g.health, hp, 0.01, "ground zones do not burn a hovering Gusto")
	check(float(g.statuses.buildup.get("scorch", 0.0)) <= 0.0, "nor build up Scorch")
	# steerable at 3 m/s
	(sim.input_sources[0] as Driver).move_dir = Vector3(1, 0, 0)
	var x0 := g.pos().x
	await step_sim(sim, 0.3)
	check(g.pos().x - x0 > 0.4, "steerable while hovering (%.2f m in 0.3 s)" % (g.pos().x - x0))
	(sim.input_sources[0] as Driver).move_dir = Vector3.ZERO
	await step_sim(sim, 1.6)
	check(not g.has_flag("hovering"), "hover ends after 1.2 s")
	check(absf(g.pos().y - y0) < 0.2 and not g.motor.tuck, "lands and walks again")
	dispose(sim)
	await _check_cooldown("ability2", FighterInput.AB2, 6.0)
	# Light while hovering = Dive Peck; Heavy while hovering = Downdraft without the hold
	for spec in [["light", "l1@hovering"], ["heavy", "heavy@hovering"]]:
		var ad := Driver.new()
		ad.presses = [{"t": 0.2, "button": FighterInput.AB2}, {"t": 0.85, "button": FighterInput.BUTTON_NAMES.find(spec[0])}]
		var r := await run_move(CID, {"att_src": ad, "slot": spec[1], "gap": 2.4, "def_id": FOE, "watch": 2.4})
		var hs := (r["hits"] as Array).filter(func(h): return str(h["slot"]) == str(spec[1]) and float(h["dmg"]) > 0.0)
		check(not hs.is_empty(), "%s from the hover connects: %s" % [spec[1], describe(r)])
		check(float((r["sim"] as MatchSim).fighters[0].pos().y) < 1.3, "%s brings Gusto back down" % spec[1])
		dispose(r["sim"])


func test_gust_bomb_projectile_burst_and_reflect() -> void:
	var r := await run_move(CID, {"slot": "ability1", "ability": true, "gap": 3.5, "def_id": FOE})
	var hs := hits_with_damage(r)
	check(not hs.is_empty(), "Gust Bomb hits at 3.5 m")
	check(float((r["tgt_disp"] as Vector3).z) > 1.2, "pushes the target (%.2f)" % float((r["tgt_disp"] as Vector3).z))
	var bu := float((r.get("buildup_at_hit", {}) as Dictionary).get("gale", 0.0))
	check(bu >= 30.0 or (r["statuses"] as Array).has("winded"), "direct hit + burst ~Gale 40 (%.1f)" % bu)
	dispose(r["sim"])
	var far := await run_move(CID, {"slot": "ability1", "ability": true, "gap": 10.6, "def_id": FOE, "arena_r": 7.0})
	check((far["hits"] as Array).is_empty(), "range 8 m (+1.5 m burst): nothing reaches 10.6 m: %s" % describe(far))
	dispose(far["sim"])
	# burst on expiry: a target standing near the end of the flight path is pushed without a direct hit
	var bd := await run_move(CID, {"slot": "ability1", "ability": true, "gap": 3.5, "def_id": FOE, "setup": func(s: MatchSim):
		s.fighters[1].rig.place(Vector3(1.0, 0.0, s.fighters[0].pos().z + 8.6), PI)})
	var burst := (bd["hits"] as Array).filter(func(h): return str(h["slot"]) == "effect")
	check(not burst.is_empty(), "expiry burst catches a target 1.5 m from its end point: %s" % describe(bd))
	dispose(bd["sim"])
	# reflectable
	var rf := await run_move(CID, {"slot": "ability1", "ability": true, "gap": 3.0, "def_id": FOE, "setup": func(s: MatchSim): s.fighters[1].set_flag("reflect", 3.0)})
	check(int(rf.get("ev_reflect", 0)) >= 1, "a reflecting target sends the Gust Bomb back")
	check((rf["sim"] as MatchSim).fighters[0].health < (rf["sim"] as MatchSim).fighters[0].max_health, "and it hits Gusto")
	dispose(rf["sim"])
	await _check_cooldown("ability1", FighterInput.AB1, 5.0)


func _check_cooldown(slot: String, button: int, cd: float) -> void:
	var d := Driver.new()
	d.presses = [{"t": 0.2, "button": button}, {"t": 1.2, "button": button}, {"t": 0.3 + cd, "button": button}]
	var sim := duel(CID, FOE, 9.0, d)
	await step_sim(sim, INTRO + cd + 0.6)
	var uses := events_of(sim, "ability").filter(func(e): return int(e["fighter"]) == 0 and str(e["slot"]) == slot)
	check_eq(uses.size(), 2, "%s used twice in %.1f s with a %.0f s cooldown" % [slot, cd + 0.4, cd])
	dispose(sim)


func test_talon_snatch_pecks_and_throws() -> void:
	var d := Driver.new()
	d.presses = [{"t": 0.2, "button": FighterInput.GRAB}, {"t": 0.8, "button": FighterInput.LIGHT}]
	var r := await run_move(CID, {"att_src": d, "slot": "grab", "gap": 1.3, "def_id": FOE, "watch": 1.0,
		"def_src": InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])})
	check(int(r.get("ev_grab", 0)) == 1, "Talon Snatch grabs a guarding target")
	var pm := (r["hits"] as Array).filter(func(h): return str(h["slot"]) == "pummel")
	check(not pm.is_empty() and absf(float(pm[0]["dmg"]) - 2.0 * Elements.damage_mult("gale", "scorch")) < 0.5, "peck pummel ~2 dmg: %s" % str(pm))
	check_stable(r, "Talon Snatch hold")
	dispose(r["sim"])
	var miss := await run_move(CID, {"slot": "grab", "gap": 1.9})
	check(int(miss.get("ev_grab", 0)) == 0, "Talon Snatch misses a Gusto at 1.9 m")
	dispose(miss["sim"])
	miss = await run_move(CID, {"slot": "grab", "gap": 2.2, "def_id": FOE})
	check(int(miss.get("ev_grab", 0)) == 0, "Talon Snatch misses a Stoke at 2.2 m")
	dispose(miss["sim"])
	for spec in [["throw_fwd", Vector3(0, 0, 1), 8.0, 1.8], ["throw_side", Vector3(1, 0, 0), 7.0, 2.0], ["throw_back", Vector3(0, 0, -1), 7.0, 1.2]]:
		var td := Driver.new()
		td.presses = [{"t": 0.2, "button": FighterInput.GRAB}, {"t": 0.8, "button": FighterInput.GRAB}]
		td.dirs = [{"t0": 0.75, "t1": 0.85, "dir": spec[1]}]
		var tr := await run_move(CID, {"att_src": td, "slot": "grab", "gap": 1.3, "def_id": FOE, "watch": 1.9})
		var sim: MatchSim = tr["sim"]
		var thr := events_of(sim, "throw")
		check(not thr.is_empty() and str(thr[0]["kind"]) == str(spec[0]), "%s performed (%s)" % [spec[0], str(thr)])
		var th := (tr["hits"] as Array).filter(func(h): return str(h["slot"]) == "throw")
		check(not th.is_empty() and absf(float(th[0]["dmg"]) - float(spec[2])) < 1.0, "%s damage ~%.0f (%s)" % [spec[0], spec[2], str(th)])
		check(bool(tr["knockdown"]), "%s knocks down" % spec[0])
		check(float((tr["tgt_disp"] as Vector3).length()) > float(spec[3]), "%s sends the target %.2f m %s" % [spec[0], (tr["tgt_disp"] as Vector3).length(), str(tr["tgt_disp"])])
		if spec[0] == "throw_fwd":
			check(float(tr["att_disp"]) > 1.5, "Carry-and-Drop: Gusto leaps after the target (%.2f m)" % float(tr["att_disp"]))
			check(int(tr.get("ev_land", 0)) >= 1, "Carry-and-Drop lands")
		dispose(sim)


func test_hurricane_strut_juice() -> void:
	var d := Driver.new()
	d.presses = [{"t": 0.2, "button": FighterInput.JUICE}]
	var sim := duel(CID, FOE, 2.0, d)
	await step_sim(sim, INTRO)
	var g := sim.fighters[0]
	var b := sim.fighters[1]
	g.hype = 100.0
	var bz := b.pos().z
	await step_sim(sim, 0.3)
	check(g.move_slot == "juice" and g.is_evading() and g._armor_covers("heavy"), "activation: invulnerable then armored")
	await step_sim(sim, 0.6)
	check(b.pos().z - bz > 1.5, "activation cone pushes ~3 m (%.2f)" % (b.pos().z - bz))
	check(b.statuses.has_element("gale") or float(b.statuses.buildup.get("gale", 0.0)) >= 25.0, "Gale 30 on activation")
	check(g.has_flag("juiced") and g.statuses.has("juiced"), "Hurricane Strut active")
	check_near(g.statuses.speed_mult(), 1.35, 0.001, "move speed +35%")
	# free dodges that leave a Gale vortex where they started
	var st := g.stamina
	var zones := sim.effects.entities.filter(func(e): return str(e.get("zone_kind", "")) == "gale_vortex").size()
	(sim.input_sources[0] as Driver).presses.append({"t": (sim.input_sources[0] as Driver).time + 0.05, "button": FighterInput.DODGE})
	await step_sim(sim, 0.4)
	check(g.stamina >= st - 0.01, "dodges cost no stamina (%.1f -> %.1f)" % [st, g.stamina])
	check(sim.effects.entities.filter(func(e): return str(e.get("zone_kind", "")) == "gale_vortex").size() > zones, "the dodge leaves a Gale vortex")
	# a taunt during the strut heals 5
	g.health = 50.0
	(sim.input_sources[0] as Driver).presses.append({"t": (sim.input_sources[0] as Driver).time + 0.05, "button": FighterInput.TAUNT})
	await step_sim(sim, 0.3)
	check_near(g.health, 55.0, 0.6, "taunt heals 5 during the strut")
	await step_sim(sim, 6.6)
	check(not g.has_flag("juiced"), "Hurricane Strut ends after 7 s")
	check(not events_of(sim, "juice_end").is_empty(), "juice_end event")
	dispose(sim)


func test_taunt_guard_and_parry() -> void:
	var d := Driver.new()
	d.presses = [{"t": 0.2, "button": FighterInput.TAUNT}]
	var sim := duel(CID, FOE, 3.0, d)
	await step_sim(sim, INTRO + 0.3)
	var a := sim.fighters[0]
	check(a.state == Fighter.State.TAUNT, "taunt plays")
	check_near(a.hype, 8.0, 0.01, "+8 Hype")
	check(not a._armor_covers("light"), "taunt has no armor")
	await step_sim(sim, 1.0)
	check(a.state == Fighter.State.TAUNT, "taunt still playing after 1.2 s")
	await step_sim(sim, 0.5)
	check(a.state != Fighter.State.TAUNT, "taunt lasts 1.5 s")
	dispose(sim)
	var open := await run_move(CID, {"slot": "l1", "gap": 1.4})
	var guarded := await run_move(CID, {"slot": "l1", "gap": 1.4, "def_src": InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])})
	var gh := guarded["hits"] as Array
	check(not gh.is_empty() and bool(gh[0]["blocked"]), "guard blocks the Wing Snap: %s" % describe(guarded))
	check(float(guarded["hp_lost"]) < float(open["hp_lost"]) * 0.4, "guard absorbs most damage (%.1f vs %.1f)" % [guarded["hp_lost"], open["hp_lost"]])
	dispose(open["sim"])
	dispose(guarded["sim"])
	var m: MoveDef = Content.creature(CID).moves["l1"]
	var tap := InputSource.Scripted.new([{"t0": INTRO + 0.2 + m.first_active() - 0.03, "t1": INTRO + 1.5, "hold": ["guard"], "press": ["guard"]}])
	var p := await run_move(CID, {"slot": "l1", "gap": 1.4, "def_src": tap})
	check(int(p.get("ev_parry", 0)) >= 1, "parry registered: %s" % describe(p))
	check((p.get("att_states", []) as Array).has("hitstun"), "Gusto staggered by the parry (%s)" % str(p.get("att_states", [])))
	dispose(p["sim"])


func test_zz_lab() -> void:
	await lab(CID)
