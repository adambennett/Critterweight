extends "res://src/test/kits/kit_harness_stoke_gusto.gd"
## STOKE (f_stoke) kit verification — docs/kits/f_stoke.md, docs/design/ROSTER.md §1.
## Every move is driven against a standing dummy (mirror and the cross-matchup body) and checked
## for: contact inside its range and no contact beyond it, damage / stun / poise / Scorch build-up,
## weapon reach ≤ 1.6 m from the root, attacker stability (no fall, no spin-out, no self-clipping,
## stays in the cage), plus every special property (strings, finisher, charge, armor, guard-crush,
## launches, side-shove, statuses, abilities with cooldowns, JUICE, grabs/pummel/throws, taunt).
## Run: godot --headless --path game --fixed-fps 120 -- --test test_kit_f_stoke

const CID := "f_stoke"
const FOE := "f_gusto"

## slot -> gaps (root to root, m) that must connect vs the mirror / vs Gusto, and a gap that must not.
const STRIKES := {
	"l1": {"hit": [1.1, 1.3], "hit_foe": [1.1, 1.3], "miss": 1.7},
	"l2": {"hit": [1.1, 1.2], "hit_foe": [1.1, 1.3], "miss": 1.8},
	"l3": {"hit": [1.05, 1.2], "hit_foe": [1.0, 1.1], "miss": 1.6},
	"heavy": {"hit": [1.1, 1.2], "hit_foe": [1.2, 1.4], "miss": 1.95},
	"heavy_charged": {"hit": [1.1, 1.4], "hit_foe": [1.2, 1.4], "miss": 2.0},
	"finisher": {"hit": [1.4, 1.8], "hit_foe": [1.3, 1.6], "miss": 2.35},
	"dash_attack": {"hit": [1.5], "hit_foe": [1.5], "miss": 2.3},
}


func test_stats_slots_and_data() -> void:
	var c := Content.creature(CID)
	check(c != null and c.is_valid(), "creature loads without errors: %s" % (str(c.errors) if c else "missing"))
	check_near(c.stat("health"), 110.0, 0.01, "health")
	check_near(c.stat("walk_speed"), 3.4, 0.01, "walk speed")
	check_near(c.stat("stamina"), 100.0, 0.01, "stamina")
	check_near(c.stat("poise"), 60.0, 0.01, "poise")
	check_near(c.stat("dodge_distance"), 2.8, 0.01, "dash distance")
	check_near(c.stat("dodge_time"), 0.3, 0.01, "dash time")
	check_near(c.body.total_mass, 85.0, 0.5, "mass")
	for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "grab", "pummel", "taunt"]:
		check(c.moves.has(slot), "move slot %s" % slot)
	for slot in ["ability1", "ability2", "juice"]:
		check(c.abilities.has(slot), "ability slot %s" % slot)
	check_eq(c.light_string, ["l1", "l2", "l3"], "light string")
	check_near(float(c.cooldowns["ability1"]), 7.0, 0.01, "Steam Vent cooldown")
	check_near(float(c.cooldowns["ability2"]), 12.0, 0.01, "Stoke the Fire cooldown")
	check_near(float(c.juice.get("duration", 0.0)), 6.0, 0.01, "Meltdown lasts 6 s")
	for k in ["throw_fwd", "throw_back", "throw_side"]:
		check(c.throws.has(k), "throw %s" % k)
	var raw := FileAccess.get_file_as_string("res://content/core/creatures/%s.json" % CID)
	check(not raw.contains("_stub"), "no stub moves left")
	check_near(c.moves["taunt"].duration, 1.5, 0.001, "taunt lasts 1.5 s")
	check(c.moves["taunt"].armor.is_empty(), "taunt has no armor")
	# ROSTER startup / active / recovery (s), stamina and damage, within engine tuning tolerance
	_check_timing(c.moves["l1"], [0.12, 0.08, 0.18], 4.0, 4.0)
	_check_timing(c.moves["l2"], [0.14, 0.08, 0.22], 5.0, 5.0)
	_check_timing(c.moves["l3"], [0.18, 0.10, 0.30], 7.0, 7.0)
	_check_timing(c.moves["heavy"], [0.28, 0.10, 0.40], 12.0, 13.0)
	_check_timing(c.moves["heavy_charged"], [0.50, 0.12, 0.50], 16.0, 18.0)
	_check_timing(c.moves["finisher"], [0.16, 0.10, 0.45], 10.0, 10.0)
	_check_timing(c.moves["dash_attack"], [0.14, 0.10, 0.35], 8.0, 8.0)
	for slot in ["l1", "l2", "l3", "heavy", "heavy_charged", "finisher", "dash_attack", "pummel"]:
		check_eq(c.moves[slot].element, "scorch", "%s is Scorch" % slot)


## Startup = first hit window start, active = window span, recovery = the rest of the move.
func _check_timing(m: MoveDef, sar: Array, stamina: float, damage: float) -> void:
	var t0 := m.first_active()
	var t1 := float(m.windows[m.windows.size() - 1]["t1"])
	check_near(t0, float(sar[0]), 0.045, "%s startup" % m.id)
	check_near(t1 - t0, float(sar[1]), 0.045, "%s active" % m.id)
	check_near(m.duration - t1, float(sar[2]), 0.05, "%s recovery" % m.id)
	check_near(m.stamina, stamina, 0.01, "%s stamina" % m.id)
	check_near(m.damage, damage, 0.01, "%s damage" % m.id)


func test_strikes_connect_in_range_and_miss_beyond() -> void:
	var c := Content.creature(CID)
	for slot in STRIKES:
		var spec: Dictionary = STRIKES[slot]
		var m: MoveDef = c.moves[slot]
		for pair in [[CID, "hit"], [FOE, "hit_foe"]]:
			for gap in spec[pair[1]]:
				var r := await run_move(CID, {"slot": slot, "gap": gap, "def_id": pair[0]})
				check_strike(r, m, "%s vs %s @%.2f" % [slot, pair[0], gap], "scorch")
				dispose(r["sim"])
		var rm := await run_move(CID, {"slot": slot, "gap": float(spec["miss"])})
		check(hits_with_damage(rm).is_empty(), "%s must not connect at %.2f m: %s" % [slot, spec["miss"], describe(rm)])
		check_stable(rm, "%s whiff" % slot)
		dispose(rm["sim"])


func test_knockback_scale_side_shove_and_turn() -> void:
	# ROSTER knockback is metres on a ~100 kg target: measured on the mirror (85 kg) within ±50%
	var roster := {"l1": 0.3, "l2": 0.5, "heavy": 1.5, "heavy_charged": 3.0, "finisher": 2.0}
	var disp := {}
	for slot in roster:
		var r := await run_move(CID, {"slot": slot, "gap": {"finisher": 1.5, "heavy_charged": 1.1}.get(slot, 1.2)})
		disp[slot] = (r["tgt_disp"] as Vector3).length()
		check(float(disp[slot]) > float(roster[slot]) * 0.5 and float(disp[slot]) < float(roster[slot]) * 1.5,
			"%s knockback %.2f m vs ROSTER %.1f m" % [slot, disp[slot], roster[slot]])
		dispose(r["sim"])
	check(float(disp["l1"]) < float(disp["l2"]) and float(disp["l2"]) < float(disp["heavy"]) and float(disp["heavy"]) < float(disp["heavy_charged"]),
		"knockback grows jab < cross < overhand < haymaker %s" % str(disp))
	# Lead Hook: sideways shove toward Stoke's right and a ~30° turn of the target
	var h := await run_move(CID, {"slot": "l3", "gap": 1.1})
	check(not hits_with_damage(h).is_empty(), "hook connects")
	var hd: Vector3 = h["tgt_disp"]
	check(hd.x < -0.5 and absf(hd.x) > absf(hd.z), "hook shoves the target sideways (x %.2f z %.2f)" % [hd.x, hd.z])
	check(absf(float(h["tgt_turn_deg"]) - 30.0) < 8.0, "hook turns the target ~30° (%.1f)" % float(h["tgt_turn_deg"]))
	dispose(h["sim"])


func test_light_string_and_finisher() -> void:
	# mash Light: jab -> cross -> hook; Light, Light, Heavy in the cancel window: Gut Furnace
	var s1 := InputSource.Scripted.new([{"t0": INTRO + 0.2, "t1": INTRO + 1.6, "press": ["light"], "every": 0.16}])
	var sim := duel(CID, FOE, 1.2, s1)
	await step_sim(sim, INTRO + 1.4)
	var slots := events_of(sim, "move_start").filter(func(e): return int(e["fighter"]) == 0).map(func(e): return str(e["slot"]))
	check(slots.size() >= 3 and slots.slice(0, 3) == ["l1", "l2", "l3"], "light string l1 -> l2 -> l3 (%s)" % str(slots))
	dispose(sim)
	var s2 := InputSource.Scripted.new([{"t0": INTRO + 0.2, "t1": INTRO + 0.25, "press": ["light"]}, {"t0": INTRO + 0.36, "t1": INTRO + 0.41, "press": ["light"]},
		{"t0": INTRO + 0.55, "t1": INTRO + 0.6, "press": ["heavy"]}])
	var sim2 := duel(CID, FOE, 1.2, s2)
	await step_sim(sim2, INTRO + 1.8)
	var slots2 := events_of(sim2, "move_start").filter(func(e): return int(e["fighter"]) == 0).map(func(e): return str(e["slot"]))
	check(slots2.has("finisher"), "Heavy in the cancel window is the Finisher (%s)" % str(slots2))
	var fin := hits_by(sim2, 0).filter(func(e): return str(e["slot"]) == "finisher" and float(e["damage"]) > 0.0)
	check(not fin.is_empty(), "Gut Furnace lands after the string")
	dispose(sim2)


func test_charged_heavy_hold_armor_and_overhand_armor() -> void:
	var c := Content.creature(CID)
	# hold Heavy: the Overhand turns into the Furnace Haymaker
	var d := Driver.new()
	d.holds = [{"t0": 0.2, "t1": 1.0, "button": FighterInput.HEAVY}]
	d.presses = [{"t": 0.2, "button": FighterInput.HEAVY}]
	var sim := duel(CID, FOE, 1.3, d)
	await step_sim(sim, INTRO + 0.1)
	var a := sim.fighters[0]
	var saw_charge_armor := false
	var saw_charged := false
	var p_hold := Vector3.INF
	var hold_drift := 0.0
	for i in 200:
		sim.step(DT)
		await get_tree().physics_frame
		if a.move_slot == "heavy":
			if p_hold == Vector3.INF:
				p_hold = a.pos()
			hold_drift = maxf(hold_drift, Vector2(a.pos().x - p_hold.x, a.pos().z - p_hold.z).length())
		if a.move_slot == "heavy" and a._charging and a._armor_covers("light") and not a._armor_covers("heavy"):
			saw_charge_armor = true
		if a.move_slot == "heavy_charged":
			saw_charged = true
			if a.state_time < 0.45:
				check(a._armor_covers("light"), "Haymaker startup is armored against Lights")
	check(saw_charge_armor, "holding the charge carries Light armor")
	check(saw_charged, "hold >= 0.35 s releases the Furnace Haymaker")
	# the Overhand lunge starts after the charge hold point (0.7 x startup), so Stoke winds up in place
	check(hold_drift < 0.3, "Stoke holds his ground while charging (drift %.2f m)" % hold_drift)
	check(not hits_by(sim, 0).filter(func(e): return str(e["slot"]) == "heavy_charged").is_empty(), "Haymaker connects")
	dispose(sim)
	# the Overhand is armored (vs Lights) during its active window only: a jab that lands in the
	# window does not stagger Stoke, the same jab during the windup does
	var m: MoveDef = c.moves["heavy"]
	check(m.in_ranges(m.armor, 0.30) and not m.in_ranges(m.armor, 0.1), "Overhand armor covers its active window")
	check_eq(m.armor_level, "lights", "Overhand armor level")
	for spec in [[0.30, false], [0.08, true]]:
		var od := Driver.new()
		od.starts = [{"t": 0.2, "slot": "heavy"}]
		var osim := duel(CID, CID, 3.0, od)
		await step_sim(osim, INTRO + 0.2 + float(spec[0]))
		var st := osim.fighters[0]
		var foe := osim.fighters[1]
		osim.combat.deliver(foe, st, {"attacker": foe, "damage": 4.0, "point": st.pos(), "normal": Vector3.UP, "seg": 0, "part": "core",
			"blocked": false, "parried": false, "counter": false, "knockback": Vector3.ZERO, "local_impulse": Vector3.ZERO, "stun": 0.25,
			"poise": 5.0, "knockdown": false, "hype_mult": 1.0, "element": "", "buildup": 0.0, "move": "jab", "slot": "l1",
			"move_class": "light", "from": foe.pos(), "melee": false, "status": {}, "splat": {}, "unblockable": true})
		check_eq(st.state == Fighter.State.HITSTUN, bool(spec[1]), "jab at Overhand t=%.2f staggers: %s" % [spec[0], str(spec[1])])
		dispose(osim)


func test_haymaker_guard_crush_and_sizzle_knock_up() -> void:
	var guard := InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])
	var oh := await run_move(CID, {"slot": "heavy", "gap": 1.2, "def_id": FOE, "def_src": guard})
	var hm := await run_move(CID, {"slot": "heavy_charged", "gap": 1.3, "def_id": FOE, "def_src": InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])})
	var oh_b := (oh["hits"] as Array).filter(func(h): return bool(h["blocked"]))
	var hm_b := (hm["hits"] as Array).filter(func(h): return bool(h["blocked"]))
	check(not oh_b.is_empty() and not hm_b.is_empty(), "both heavies are blocked by a guarding target")
	var drain_oh := (oh["sim"] as MatchSim).fighters[1].max_stamina - float(oh["tgt_stamina_min"])
	var drain_hm := (hm["sim"] as MatchSim).fighters[1].max_stamina - float(hm["tgt_stamina_min"])
	check(drain_hm >= drain_oh * 1.8, "Haymaker crushes the guard: stamina drain %.1f vs Overhand %.1f" % [drain_hm, drain_oh])
	dispose(oh["sim"])
	dispose(hm["sim"])
	# on a Sizzling target the Haymaker knocks up (~1.2 m)
	var plain := await run_move(CID, {"slot": "heavy_charged", "gap": 1.3, "def_id": FOE})
	var sizz := await run_move(CID, {"slot": "heavy_charged", "gap": 1.3, "def_id": FOE, "setup": func(s: MatchSim): _sizzle(s.fighters[1], s.fighters[0])})
	check(not hits_with_damage(sizz).is_empty(), "Haymaker connects on the Sizzling target")
	check(float(sizz["tgt_rise"]) > float(plain["tgt_rise"]) + 0.3, "Sizzling target is knocked up (rise %.2f vs %.2f)" % [sizz["tgt_rise"], plain["tgt_rise"]])
	dispose(plain["sim"])
	dispose(sizz["sim"])


## Puts Sizzle on `f` as if `by` had applied it.
func _sizzle(f: Fighter, by: Fighter) -> void:
	f.statuses.add_buildup("scorch", 100.0, by)


func test_gut_furnace_feeds_on_sizzle() -> void:
	var plain := await run_move(CID, {"slot": "finisher", "gap": 1.4, "def_id": FOE})
	var sizz := await run_move(CID, {"slot": "finisher", "gap": 1.4, "def_id": FOE, "setup": func(s: MatchSim):
		_sizzle(s.fighters[1], s.fighters[0])
		var st: Dictionary = s.fighters[1].statuses.element_status("scorch")
		st["left"] = 1.0})
	var dp := float((hits_with_damage(plain)[0] as Dictionary)["dmg"]) if not hits_with_damage(plain).is_empty() else 0.0
	var ds := float((hits_with_damage(sizz)[0] as Dictionary)["dmg"]) if not hits_with_damage(sizz).is_empty() else 0.0
	check(dp > 0.0 and ds > dp + 2.5, "+4 damage on a Sizzling target (%.1f vs %.1f)" % [ds, dp])
	var st: Dictionary = (sizz["sim"] as MatchSim).fighters[1].statuses.element_status("scorch")
	check(not st.is_empty() and float(st["left"]) > 1.0, "Sizzle refreshed by the Gut Furnace")
	dispose(plain["sim"])
	dispose(sizz["sim"])


func test_stoke_step_from_dodge_launches() -> void:
	var d := Driver.new()
	d.dirs = [{"t0": 0.18, "t1": 0.45, "dir": Vector3(0, 0, 1)}]
	d.presses = [{"t": 0.2, "button": FighterInput.DODGE}, {"t": 0.32, "button": FighterInput.LIGHT}]
	var r := await run_move(CID, {"att_src": d, "slot": "dash_attack", "gap": 2.6, "def_id": FOE, "watch": 1.4})
	var dh := (r["hits"] as Array).filter(func(h): return str(h["slot"]) == "dash_attack" and float(h["dmg"]) > 0.0)
	check(not dh.is_empty(), "Light during the dash is the Stoke Step and it connects after a dash: %s" % describe(r))
	check(float(r["tgt_rise"]) > 0.25, "Stoke Step launches (rise %.2f)" % float(r["tgt_rise"]))
	check_stable(r, "Stoke Step")
	dispose(r["sim"])


func test_clinch_pummel_and_throws() -> void:
	# grab beats guard; pummel = knee (3 dmg, Scorch 8)
	var d := Driver.new()
	d.presses = [{"t": 0.2, "button": FighterInput.GRAB}, {"t": 0.75, "button": FighterInput.LIGHT}]
	var r := await run_move(CID, {"att_src": d, "slot": "grab", "gap": 1.2, "def_id": FOE, "watch": 1.0,
		"def_src": InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])})
	check(int(r.get("ev_grab", 0)) == 1, "Clinch grabs a guarding target")
	var pm := (r["hits"] as Array).filter(func(h): return str(h["slot"]) == "pummel")
	check(not pm.is_empty() and absf(float(pm[0]["dmg"]) - 3.0 * Elements.damage_mult("scorch", "gale")) < 0.6, "knee pummel ~3 dmg: %s" % str(pm))
	check(float((r["sim"] as MatchSim).fighters[1].statuses.buildup.get("scorch", 0.0)) > 4.0, "pummel adds Scorch build-up")
	dispose(r["sim"])
	var miss := await run_move(CID, {"slot": "grab", "gap": 1.8})
	check(int(miss.get("ev_grab", 0)) == 0, "Clinch misses at 1.8 m")
	dispose(miss["sim"])
	# throws: forward Belly Toss (9, knockdown), back Dump (knockdown), side Shove-off (4, no knockdown)
	for spec in [["throw_fwd", Vector3(0, 0, 1), 9.0, true, 1.4], ["throw_back", Vector3(0, 0, -1), 8.0, true, 1.4], ["throw_side", Vector3(1, 0, 0), 4.0, false, 1.8]]:
		var td := Driver.new()
		td.presses = [{"t": 0.2, "button": FighterInput.GRAB}, {"t": 0.8, "button": FighterInput.GRAB}]
		td.dirs = [{"t0": 0.75, "t1": 0.85, "dir": spec[1]}]
		var tr := await run_move(CID, {"att_src": td, "slot": "grab", "gap": 1.2, "def_id": FOE, "watch": 1.8})
		var sim: MatchSim = tr["sim"]
		var thr := events_of(sim, "throw")
		check(not thr.is_empty() and str(thr[0]["kind"]) == str(spec[0]), "%s performed (%s)" % [spec[0], str(thr)])
		var th := (tr["hits"] as Array).filter(func(h): return str(h["slot"]) == "throw")
		check(not th.is_empty() and absf(float(th[0]["dmg"]) - float(spec[2]) * Elements.damage_mult("", "gale")) < 1.0, "%s damage ~%.0f (%s)" % [spec[0], spec[2], str(th)])
		check_eq(bool(tr["knockdown"]), bool(spec[3]), "%s knockdown" % spec[0])
		check(float((tr["tgt_disp"] as Vector3).length()) > float(spec[4]), "%s sends the target %.2f m %s" % [spec[0], (tr["tgt_disp"] as Vector3).length(), str(tr["tgt_disp"])])
		dispose(sim)


func test_steam_vent_cone_push_projectiles_and_cooldown() -> void:
	var r := await run_move(CID, {"slot": "ability1", "ability": true, "gap": 1.6, "def_id": FOE})
	var hs := hits_with_damage(r)
	check(not hs.is_empty(), "Steam Vent cone hits at 1.6 m")
	check(float((r["buildup_at_hit"] as Dictionary).get("scorch", 0.0)) >= 30.0 or (r["statuses"] as Array).has("sizzle"), "Scorch 35 build-up")
	check(float((r["tgt_disp"] as Vector3).z) > 1.5, "pushes ~2.5 m (%.2f)" % float((r["tgt_disp"] as Vector3).z))
	dispose(r["sim"])
	var far := await run_move(CID, {"slot": "ability1", "ability": true, "gap": 2.8, "def_id": FOE})
	check(hits_with_damage(far).is_empty(), "cone is 2 m long")
	dispose(far["sim"])
	# an enemy projectile entering the cone is destroyed
	var pr := await run_move(CID, {"slot": "ability1", "ability": true, "gap": 4.0, "def_id": FOE, "watch": 0.8, "setup": func(s: MatchSim):
		var foe: Fighter = s.fighters[1]
		s.effects.fire(foe, {"type": "projectile", "speed": 6.0, "radius": 0.3, "life": 2.0, "damage": 5, "offset": [0, 1.1, 0.6]}, null)})
	check(int(pr.get("ev_projectile_destroyed", 0)) >= 1, "Steam Vent destroys the incoming projectile")
	check_near((pr["sim"] as MatchSim).fighters[0].health, (pr["sim"] as MatchSim).fighters[0].max_health, 0.01, "Stoke is not hit by it")
	dispose(pr["sim"])
	await _check_cooldown("ability1", FighterInput.AB1, 7.0)


## Presses an ability, presses again after 1 s (refused: cooldown) and again after `cd` (accepted).
func _check_cooldown(slot: String, button: int, cd: float) -> void:
	var d := Driver.new()
	d.presses = [{"t": 0.2, "button": button}, {"t": 1.2, "button": button}, {"t": 0.3 + cd, "button": button}]
	var sim := duel(CID, FOE, 4.0, d)
	await step_sim(sim, INTRO + cd + 0.6)
	var uses := events_of(sim, "ability").filter(func(e): return int(e["fighter"]) == 0 and str(e["slot"]) == slot)
	check_eq(uses.size(), 2, "%s used twice in %.1f s with a %.0f s cooldown" % [slot, cd + 0.4, cd])
	dispose(sim)


func test_stoke_the_fire_buff() -> void:
	var c := Content.creature(CID)
	var r := await run_move(CID, {"slot": "ability2", "ability": true, "gap": 4.0, "watch": 0.5})
	var sim: MatchSim = r["sim"]
	var a := sim.fighters[0]
	check(a.statuses.has("stoked"), "Stoke the Fire applies its buff")
	check_near(a.statuses.mult("move_speed"), 1.25, 0.001, "startup/recovery -20% (moves run 1.25x)")
	check_near(a.statuses.stamina_regen_mult(), 0.0, 0.001, "stamina regen 0 while stoked")
	var hp := a.health
	await step_sim(sim, 2.0)
	check(a.health < hp - 1.5 and a.health > hp - 2.5, "self-burn ~1 HP/s (%.2f -> %.2f)" % [hp, a.health])
	a.health = 1.4
	await step_sim(sim, 1.4)
	check(a.health >= 1.0 and not a.is_out(), "self-burn cannot kill (%.2f)" % a.health)
	dispose(sim)
	# every hit adds +5 Scorch on top of the move's own build-up
	var plain := await run_move(CID, {"slot": "l2", "gap": 1.2, "def_id": FOE})
	var buffed := await run_move(CID, {"slot": "l2", "gap": 1.2, "def_id": FOE, "setup": func(s: MatchSim):
		s.effects.fire(s.fighters[0], c.abilities["ability2"].effects[0], null)})
	var bp := float((plain.get("buildup_at_hit", {}) as Dictionary).get("scorch", 0.0))
	var bb := float((buffed.get("buildup_at_hit", {}) as Dictionary).get("scorch", 0.0))
	check(bp > 0.0 and bb >= bp + 3.0, "stoked hit adds +5 Scorch (%.1f vs %.1f)" % [bb, bp])
	check(float(buffed["first_hit_t"]) > 0.0, "buffed cross connects")
	dispose(plain["sim"])
	dispose(buffed["sim"])
	await _check_cooldown("ability2", FighterInput.AB2, 12.0)


func test_meltdown_juice() -> void:
	var d := Driver.new()
	d.presses = [{"t": 0.2, "button": FighterInput.JUICE}]
	var sim := duel(CID, FOE, 2.0, d)
	await step_sim(sim, INTRO)
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	a.hype = 100.0
	await step_sim(sim, 0.3)
	check(a.state == Fighter.State.ABILITY and a.move_slot == "juice", "JUICE starts with 100 Hype")
	check(a.is_evading(), "0.3 s of invulnerability on activation")
	check(a._armor_covers("heavy"), "full armor during the 0.5 s activation")
	check_near(a.hype, 0.0, 0.01, "Hype spent")
	await step_sim(sim, 0.5)
	var pulse := hits_by(sim, 0).filter(func(e): return str(e["slot"]) == "effect" and float(e["damage"]) > 0.0)
	check(not pulse.is_empty(), "Meltdown pulse hits within 3 m")
	check(b.statuses.has_element("scorch") or float(b.statuses.buildup.get("scorch", 0.0)) >= 40.0, "pulse adds Scorch 50")
	check(a.has_flag("juiced"), "JUICE state active")
	check(a._armor_covers("light") and not a._armor_covers("heavy"), "armor vs everything but Heavies")
	# a hit during the state adds +25 Scorch and leaves a Scorch patch at the impact point
	b.statuses.clear()
	var zones_before := sim.effects.entities.filter(func(e): return e["kind"] == "zone").size()
	sim.combat.deliver(a, b, {"attacker": a, "damage": 4.0, "point": b.pos(), "normal": Vector3.UP, "seg": 0, "part": "core",
		"blocked": false, "parried": false, "counter": false, "knockback": Vector3.ZERO, "local_impulse": Vector3.ZERO, "stun": 0.1,
		"poise": 1.0, "knockdown": false, "hype_mult": 1.0, "element": "scorch", "buildup": 0.0, "move": "test", "slot": "l1",
		"move_class": "light", "from": a.pos(), "melee": false, "status": {}, "splat": {}, "unblockable": true})
	check(float(b.statuses.buildup.get("scorch", 0.0)) >= 20.0, "+25 Scorch per hit while juiced (%s)" % str(b.statuses.buildup))
	check(sim.effects.entities.filter(func(e): return e["kind"] == "zone").size() > zones_before, "hit leaves a Scorch patch")
	await step_sim(sim, 5.3)
	check(a.has_flag("juiced"), "JUICE still active after 5.8 s")
	a.stamina = a.max_stamina
	await step_sim(sim, 1.0)
	check(not a.has_flag("juiced"), "JUICE ends after 6 s")
	check(not events_of(sim, "juice_end").is_empty(), "juice_end event")
	check(a.time < a.crash_until, "burnt-out crash follows")
	check(a.stamina <= a.max_stamina - 25.0, "burnt out: -30 stamina (%.1f)" % a.stamina)
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
	# a guarding target blocks the jab and takes chip only
	var open := await run_move(CID, {"slot": "l2", "gap": 1.2, "def_id": FOE})
	var guarded := await run_move(CID, {"slot": "l2", "gap": 1.2, "def_id": FOE, "def_src": InputSource.Scripted.new([{"t0": 0.0, "t1": 9.0, "hold": ["guard"]}])})
	var gh := guarded["hits"] as Array
	check(not gh.is_empty() and bool(gh[0]["blocked"]), "guard blocks the cross")
	check(float(guarded["hp_lost"]) < float(open["hp_lost"]) * 0.4, "guard absorbs most damage (%.1f vs %.1f)" % [guarded["hp_lost"], open["hp_lost"]])
	dispose(open["sim"])
	dispose(guarded["sim"])
	# a well-timed guard tap parries and staggers Stoke
	var m: MoveDef = Content.creature(CID).moves["l2"]
	var tap := InputSource.Scripted.new([{"t0": INTRO + 0.2 + m.first_active() - 0.04, "t1": INTRO + 1.5, "hold": ["guard"], "press": ["guard"]}])
	var p := await run_move(CID, {"slot": "l2", "gap": 1.2, "def_id": FOE, "def_src": tap})
	check(int(p.get("ev_parry", 0)) >= 1, "parry registered: %s" % describe(p))
	check((p.get("att_states", []) as Array).has("hitstun"), "attacker staggered by the parry (%s)" % str(p.get("att_states", [])))
	dispose(p["sim"])


func test_zz_lab() -> void:
	await lab(CID)


## Evidence frames (gated, needs a window): see kit_harness_stoke_gusto.gd showcase().
func test_zz_showcase() -> void:
	var hyped := func(s: MatchSim): s.fighters[0].hype = 100.0
	await showcase(CID, [
		{"name": "jab", "def": FOE, "gap": 1.25, "starts": [{"t": 1.2, "slot": "l1"}], "at": [1.2 + 0.17]},
		{"name": "lead_hook", "def": CID, "gap": 1.15, "starts": [{"t": 1.2, "slot": "l3"}], "at": [1.2 + 0.10, 1.2 + 0.22]},
		{"name": "overhand", "def": FOE, "gap": 1.3, "starts": [{"t": 1.2, "slot": "heavy"}], "at": [1.2 + 0.23, 1.2 + 0.34]},
		{"name": "haymaker", "def": FOE, "gap": 1.3, "starts": [{"t": 1.2, "slot": "heavy_charged"}], "at": [1.2 + 0.36, 1.2 + 0.55]},
		{"name": "gut_furnace", "def": FOE, "gap": 1.5, "starts": [{"t": 1.2, "slot": "finisher"}], "at": [1.2 + 0.21]},
		{"name": "stoke_step", "def": FOE, "gap": 2.6, "dirs": [{"t0": 1.18, "t1": 1.45, "dir": Vector3(0, 0, 1)}],
			"presses": [{"t": 1.2, "button": FighterInput.DODGE}, {"t": 1.32, "button": FighterInput.LIGHT}], "at": [1.32 + 0.2]},
		{"name": "steam_vent", "def": FOE, "gap": 1.7, "starts": [{"t": 1.2, "slot": "ability1", "ability": true}], "at": [1.2 + 0.26]},
		{"name": "meltdown", "def": FOE, "gap": 2.0, "setup": hyped, "presses": [{"t": 1.2, "button": FighterInput.JUICE}], "at": [1.2 + 0.47, 1.2 + 1.6]},
	])


## Balance spars (gated, slow): `-- --test test_kit_f_stoke.gd::test_zz_balance --kit-balance [n] [difficulty]`
## prints win rates and damage per landed hit for Stoke vs Gusto and both mirrors.
func test_zz_balance() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--kit-balance")
	if i < 0:
		return
	var n := int(args[i + 1]) if i + 1 < args.size() and args[i + 1].is_valid_int() else 20
	var diff := args[i + 2] if i + 2 < args.size() and not args[i + 2].begins_with("--") else "regular"
	var only := args[args.find("--kit-pair") + 1] if args.has("--kit-pair") else ""
	for pair in [[CID, FOE], [CID, CID], [FOE, FOE]]:
		if only != "" and "%s-%s" % [pair[0], pair[1]] != only:
			continue
		await balance(pair[0], pair[1], n, diff)
