extends MovesKitCase
## Dredge's v0.9.18 move pool (docs/kits/f_dredge.md "Movesets", docs/design/MOVESET_COMBAT.md §4):
## every move does what its description says, in Movesets, against a standing Stoke (a Scorch
## fighter: brine soaks him, where another crab would shrug off Dredge's zones); the drilled styles
## patch their moves and change what they do; the effects kit draws and cleans up its moves headless.

const TIDECALLER := ["claw_snap", "bubble_stream", "hydro_cannon", "anchor_drop"]
const BREAKWATER := ["claw_snap", "crusher_slam", "whirlpool", "shell_brace"]
const POOL := ["claw_snap", "crusher_slam", "tide_spit", "anchor_drop", "bubble_stream", "hydro_cannon", "whirlpool", "shell_brace"]
const FOE := "f_stoke"
const VFX := ["dredge_bubble", "dredge_bubble_pop", "dredge_hydro_beam", "dredge_riptide_beam", "dredge_hydro_kick", "dredge_whirl_open",
	"dredge_whirlpool", "dredge_geyser", "dredge_shell_brace", "dredge_barnacle_burst", "dredge_cavitation", "dredge_spit_splash"]

var _state := {}         ## (effects tests) fighter -> Fighter.State the info callable reports
var _charge := {}        ## (effects tests) fighter -> the charge level it reports (-1: not charging)


func test_pool_and_loadouts() -> void:
	var c := Content.creature("f_dredge")
	for id in POOL:
		check_pool_move("f_dredge", id)
	check_eq(c.resolve_loadout([]), TIDECALLER, "the default loadout is Tidecaller")
	check_eq((c.loadouts["breakwater"] as Dictionary)["moves"], BREAKWATER, "Breakwater is the second build")
	var shared := TIDECALLER.filter(func(x) -> bool: return BREAKWATER.has(x))
	check_eq(shared, ["claw_snap"], "the two builds share only the basic strike")
	var stream: PoolMove = c.pool["bubble_stream"]
	check(stream.hold == "sustain" and stream.aim_turn > 0.0 and stream.drain > 0.0 and stream.category == "stream", "Bubble Stream is held, aimed and drains stamina")
	var cannon: PoolMove = c.pool["hydro_cannon"]
	check(cannon.hold == "charge" and cannon.move.charge_time >= 1.0 and cannon.category == "blast", "Hydro Cannon is a long charge")
	var slam: PoolMove = c.pool["crusher_slam"]
	check(slam.role == "heavy" and slam.hold == "charge" and slam.charged != null, "Crusher Slam charges into the Hull Breaker")
	var spit: PoolMove = c.pool["tide_spit"]
	var anchor: PoolMove = c.pool["anchor_drop"]
	check(is_equal_approx(spit.cooldown, 6.0) and is_equal_approx(anchor.cooldown, 10.0), "the abilities keep their v0.9.17 cooldowns")
	check_eq(c.light_string, ["l1", "l2", "l3"], "Classic keeps its light string")


func test_styles_patch_their_moves() -> void:
	var entry := Content.creature_entry("f_dredge")
	var c := Content.creature("f_dredge")
	for id in POOL:
		var pm: PoolMove = c.pool[id]
		for sid in pm.styles:
			var st: Dictionary = pm.styles[sid]
			check(str(st.get("name", "")) != "" and str(st.get("desc", "")).length() > 30, "%s/%s is named and described" % [id, sid])
			var d: Dictionary = entry.duplicate(true)
			var res := ContentPatch.apply_all(d, st.get("patch", []))
			check((res["unmatched"] as Array).is_empty() and int(res["hits"]) > 0, "%s/%s: every op reaches its move (%s)" % [id, sid, str(res)])
			var pc := CreatureDef.from_dict(d, Callable(), "test")
			check(pc.is_valid(), "%s/%s: the drilled fighter still parses (%s)" % [id, sid, str(pc.errors)])


func test_bubble_stream_soaks_while_held_and_stops_on_release() -> void:
	var sim := duel("f_dredge", TIDECALLER, FOE, 2.2)
	await step_sim(sim, 0.4)
	var d := sim.fighters[0]
	var foe := sim.fighters[1]
	var hp := foe.health
	var st0 := d.stamina
	d.input.press(FighterInput.HEAVY)            # Move 2 = Bubble Stream, held
	await step_sim(sim, 1.0)
	check(d.move_pool_id == "bubble_stream" and d.sustaining, "held: he keeps blowing past the move's own length")
	check(not pool_entities(sim, "bubble_stream", "projectile").is_empty(), "bubbles drift between them")
	await step_sim(sim, 0.6)
	var puffs := _puffs(sim)
	check(puffs >= 8, "a bubble every 0.15 s while held (%d)" % puffs)
	check(d.stamina < st0 - 6.0 - 9.0 * 0.9, "the stream drains stamina while held (%.1f -> %.1f)" % [st0, d.stamina])
	d.input.set_held(FighterInput.HEAVY, false)
	await step_sim(sim, 0.4)                     # the last bubbles reach him
	var n := _puffs(sim)
	var hits := pool_events(sim, "hit", "bubble_stream")
	check(hits.size() >= 4, "the bubbles pop on the fighter in front (%d)" % hits.size())
	check(hits.all(func(e: Dictionary) -> bool: return bool(e.get("tick", false)) and str(e.get("cat", "")) == "stream"), "as throttled stream ticks")
	check(foe.health < hp, "they sting (%.1f)" % (hp - foe.health))
	check(foe.statuses.has_element("brine") or float(foe.statuses.buildup.get("brine", 0.0)) > 30.0, "and soak him")
	check(d.hype < 15.0, "a stream builds little hype (%.1f)" % d.hype)
	print("DREDGE bubble stream: %d puffs in 1.6 s held, %d pops on Stoke for %.1f damage, brine %.0f%s, stamina %.0f -> %.0f, hype %.1f" % [puffs,
		hits.size(), hp - foe.health, float(foe.statuses.buildup.get("brine", 0.0)), " (Soaked)" if foe.statuses.has_element("brine") else "", st0, d.stamina, d.hype])
	await step_sim(sim, 1.2)
	check(_puffs(sim) == n and n <= puffs + 2, "release stops the stream (%d -> %d)" % [puffs, _puffs(sim)])
	check(d.move == null, "and he plays out its recovery")


func test_bubbles_stop_shots() -> void:
	var sim := duel("f_dredge", TIDECALLER, FOE, 3.0)
	await step_sim(sim, 0.4)
	var d := sim.fighters[0]
	var foe := sim.fighters[1]
	d.input.press(FighterInput.HEAVY)
	await step_sim(sim, 0.9)                     # a screen of bubbles between them
	var hp := d.health
	sim.effects.fire(foe, {"type": "projectile", "speed": 8.0, "radius": 0.2, "life": 1.0, "damage": 6.0, "stun": 0.3, "poise": 8.0,
		"offset": [0, 0.75, 0.5]})
	await step_sim(sim, 0.6)
	var stopped := sim.events.filter(func(e: Dictionary) -> bool:
		return str(e["type"]) == "projectile_destroyed" and str(e.get("by", "")) == "intercept" and int(e.get("fighter", -1)) == 0)
	check(not stopped.is_empty(), "a bubble stops the shot")
	check(is_equal_approx(d.health, hp), "and it never reaches Dredge (%.1f -> %.1f)" % [hp, d.health])
	d.input.set_held(FighterInput.HEAVY, false)
	await step_sim(sim, 0.6)


func test_hydro_cannon_charges_into_a_long_beam_and_recoils() -> void:
	# a tap squirts a short jet
	var tap := duel("f_dredge", TIDECALLER, FOE, 3.0)
	await step_sim(tap, 0.4)
	var tz := tap.fighters[1].pos().z
	await use_slot(tap, 0, 2, 0.0, 1.5)          # Move 3 = Hydro Cannon, tapped
	var jet := _areas(tap, "hydro_cannon")
	check(jet.size() == 1 and float(jet[0].get("length", 0.0)) < 4.0, "a tap fires one short jet (%s)" % str(jet))
	var tap_dmg := pool_damage(tap, "hydro_cannon")
	var tap_push := tap.fighters[1].pos().z - tz
	check(tap_dmg > 0.0, "it reaches a fighter three metres away (%.1f)" % tap_dmg)
	# held, it pumps up into the six-metre beam
	var sim := duel("f_dredge", TIDECALLER, FOE, 3.0)
	await step_sim(sim, 0.4)
	var d := sim.fighters[0]
	var foe := sim.fighters[1]
	var z0 := d.pos().z
	var fz := foe.pos().z
	d.input.press(FighterInput.AB1)
	await step_sim(sim, 1.0)
	check(d.move_pool_id == "hydro_cannon" and d.move_charge > 0.4, "holding pumps the cannon (%.2f)" % d.move_charge)
	check(_areas(sim, "hydro_cannon").is_empty(), "and holds the shot")
	await step_sim(sim, 0.7)                     # full charge: it fires on its own
	d.input.set_held(FighterInput.AB1, false)
	await step_sim(sim, 1.2)
	var beam := _areas(sim, "hydro_cannon")
	check(beam.size() == 1 and float(beam[0].get("length", 0.0)) > 5.8, "a full charge fires the six-metre beam (%s)" % str(beam))
	var dmg := pool_damage(sim, "hydro_cannon")
	check(dmg > tap_dmg * 2.0, "that hits far harder (%.1f vs %.1f)" % [dmg, tap_dmg])
	check(foe.pos().z - fz > tap_push + 1.0, "and blasts him down the cage (%.2f m vs %.2f)" % [foe.pos().z - fz, tap_push])
	check(d.pos().z < z0 - 0.4, "the recoil slides Dredge back (%.2f m)" % (z0 - d.pos().z))
	var hits := pool_events(sim, "hit", "hydro_cannon")
	check(hits.size() == 1 and str(hits[0].get("cat", "")) == "blast" and not bool(hits[0].get("tick", false)), "one blast hit, attributed (%s)" % str(hits))
	check(float(d.cooldown_left.get("m3", 0.0)) > 0.0, "and the cannon cools down")
	print("DREDGE hydro cannon: tap %.1f m jet, %.1f damage, %.2f m push; full charge %.1f m beam, %.1f damage, %.2f m push, recoil slide %.2f m" % [
		float(jet[0].get("length", 0.0)) if not jet.is_empty() else 0.0, tap_dmg, tap_push,
		float(beam[0].get("length", 0.0)) if not beam.is_empty() else 0.0, dmg, foe.pos().z - fz, z0 - d.pos().z])


func test_whirlpool_drags_in_and_soaks() -> void:
	var sim := duel("f_dredge", BREAKWATER, FOE, 3.6)
	await step_sim(sim, 0.4)
	var d := sim.fighters[0]
	var foe := sim.fighters[1]
	var hp := foe.health
	var gap0 := _gap(d, foe)
	var dp := d.pos()
	await use_slot(sim, 0, 2, 0.0, 0.6)          # Move 3 = Whirlpool (the claws strike the floor 0.46 s in)
	var pools := pool_entities(sim, "whirlpool", "zone")
	check(pools.size() == 1, "a whirlpool opens")
	if pools.is_empty():
		return
	var centre: Vector3 = pools[0]["pos"]
	check(absf(centre.z - (dp.z + 1.6)) < 0.3 and absf(centre.x - dp.x) < 0.3, "just in front of him (%s)" % str(centre))
	var yank := pool_events(sim, "hit", "whirlpool")
	check(not yank.is_empty() and str(yank[0].get("cat", "")) == "control", "its rim yanks the fighter inside (attributed)")
	await step_sim(sim, 1.5)
	var gap1 := _gap(d, foe)
	check(gap1 < gap0 - 0.8, "it drags him toward its centre (%.2f -> %.2f m)" % [gap0, gap1])
	check(foe.statuses.has("dredge_undertow"), "slowed while he is caught")
	check(foe.health < hp, "the churning water hurts (%.1f)" % (hp - foe.health))
	check(foe.statuses.has_element("brine") or float(foe.statuses.buildup.get("brine", 0.0)) > 30.0, "and soaks him")
	check(d.pos().distance_to(dp) < 0.3, "Dredge himself is not pulled (%.2f m)" % d.pos().distance_to(dp))
	print("DREDGE whirlpool: gap %.2f -> %.2f m two seconds after the press, %.1f damage, brine %.0f%s" % [gap0, gap1, hp - foe.health,
		float(foe.statuses.buildup.get("brine", 0.0)), " (Soaked)" if foe.statuses.has_element("brine") else ""])


func test_shell_brace_hardens_and_slows() -> void:
	var sim := duel("f_dredge", BREAKWATER, FOE, 2.4)
	await step_sim(sim, 0.4)
	var d := sim.fighters[0]
	var foe := sim.fighters[1]
	var blow := {"damage": 10.0, "knockback": 3.0, "stun": 0.2, "poise": 5.0}
	var walk := d.speed_mult()
	sim.effects.effect_hit(foe, d, blow, foe.pos())
	var plain := _last_hit_on(sim, 0)
	await step_sim(sim, 2.0)                     # the combo protection from that blow resets
	await use_slot(sim, 0, 3, 0.0, 0.5)          # Move 4 = Shell Brace (he braces 0.2 s in)
	check(d.statuses.has("shell_braced"), "Dredge braces under his shell")
	check(d.speed_mult() < walk * 0.75, "and walks slower (%.2f -> %.2f)" % [walk, d.speed_mult()])
	check(is_equal_approx(d.statuses.knockback_taken_mult(), 0.5), "he takes half the knockback (%.2f)" % d.statuses.knockback_taken_mult())
	sim.effects.effect_hit(foe, d, blow, foe.pos())
	var braced := _last_hit_on(sim, 0)
	check(braced > plain * 0.55 and braced < plain * 0.65, "and 40%% less damage (%.1f vs %.1f)" % [braced, plain])
	print("DREDGE shell brace: a 10-damage blow deals %.1f plain, %.1f braced; walk x%.2f" % [plain, braced, d.speed_mult() / maxf(walk, 0.01)])
	await step_sim(sim, 3.0)
	check(not d.statuses.has("shell_braced"), "for three seconds")


func test_classic_moves_carry_over() -> void:
	# Claw Snap: press after press walks the Classic string into the Bilge Pump
	var sim := duel("f_dredge", BREAKWATER, FOE, 1.5)
	await step_sim(sim, 0.4)
	var d := sim.fighters[0]
	var slots: Array = []
	for k in 4:
		d.input.press(FighterInput.LIGHT)
		await step_sim(sim, 0.03)
		slots.append(d.move_slot)
		d.input.set_held(FighterInput.LIGHT, false)
		var guard := 0
		while d.move != null and d.state_time < d.move.cancel_t0 + 0.02 and guard < 200:
			await step_sim(sim, DT)
			guard += 1
		if d.move != null and d.move.windows.size() > 0:
			while d.move != null and d.state_time < d.move.last_active() + 0.01 and guard < 300:
				await step_sim(sim, DT)
				guard += 1
	check_eq(slots, ["l1", "l2", "l3", "finisher"], "Claw Snap walks its string into the Bilge Pump")
	await step_sim(sim, 1.2)
	# Crusher Slam: held, the claw stays up and winds into the Hull Breaker
	d.input.press(FighterInput.HEAVY)
	await step_sim(sim, 1.2)
	check(d.move_pool_id == "crusher_slam" and d.move_charge > 0.4, "holding Crusher Slam charges it (%.2f)" % d.move_charge)
	d.input.set_held(FighterInput.HEAVY, false)
	await step_sim(sim, 0.1)
	check_eq(d.move_slot, "heavy_charged", "release: the Hull Breaker")
	await step_sim(sim, 1.6)
	# Anchor Drop (Tidecaller) plants the counter stance
	var tc := duel("f_dredge", TIDECALLER, FOE, 2.0)
	await step_sim(tc, 0.4)
	await use_slot(tc, 0, 3, 0.0, 0.4)           # Move 4 = Anchor Drop
	check(tc.fighters[0].counter_active(), "Anchor Drop plants the counter stance")
	# Tide Spit (off both builds) lobs its glob and leaves a puddle
	var sp := duel("f_dredge", ["claw_snap", "tide_spit"], FOE, 4.0)
	await step_sim(sp, 0.4)
	await use_slot(sp, 0, 1, 0.0, 0.4)           # Move 2 = Tide Spit (spat 0.3 s in)
	check(not pool_entities(sp, "tide_spit", "projectile").is_empty(), "Tide Spit lobs its glob")
	await step_sim(sp, 1.4)
	check(not pool_entities(sp, "tide_spit", "zone").is_empty(), "and leaves a brine puddle")


func test_drilled_styles_change_behaviour() -> void:
	# Riptide: the cannon hauls its target in instead of blasting it away
	var rip := _duel_with(_drilled({"hydro_cannon": "riptide"}), TIDECALLER, 4.0)
	await step_sim(rip, 0.4)
	var foe := rip.fighters[1]
	var fz := foe.pos().z
	await use_slot(rip, 0, 2, 1.7, 1.0)          # a full charge
	check(not pool_events(rip, "hit", "hydro_cannon").is_empty(), "the riptide beam lands")
	check(foe.pos().z < fz - 0.6, "and drags the target toward Dredge (%.2f m)" % (fz - foe.pos().z))
	# Eye of the Storm: the whirlpool opens around Dredge and travels with him
	var eye := _duel_with(_drilled({"whirlpool": "eye_of_the_storm"}), BREAKWATER, 3.0)
	await step_sim(eye, 0.4)
	var d := eye.fighters[0]
	await use_slot(eye, 0, 2, 0.0, 0.7)
	var pools := pool_entities(eye, "whirlpool", "zone")
	check(pools.size() == 1 and _flat(pools[0]["pos"], d.pos()) < 0.3, "Eye of the Storm opens around him")
	var x0 := d.pos().x
	d.input.move = Vector3(1, 0, 0)              # he scuttles sideways
	await step_sim(eye, 0.8)
	d.input.move = Vector3.ZERO
	pools = pool_entities(eye, "whirlpool", "zone")
	check(absf(d.pos().x - x0) > 0.5, "Dredge scuttles away (%.2f m)" % absf(d.pos().x - x0))
	check(pools.size() == 1 and _flat(pools[0]["pos"], d.pos()) < 0.3, "and the whirlpool travels with him")


func test_effects_kit_is_registered_and_draws_its_vfx() -> void:
	var views := _views(["f_dredge"])
	var fx := _fx(views)
	check(fx.moves != null and fx.moves.kits.has("f_dredge"), "Dredge's kit is loaded")
	var kit = fx.moves.kits.get("f_dredge")
	if kit == null:
		_free(fx, views)
		return
	for v in VFX:
		check(fx.moves.by_vfx.get(v) == kit, "the kit draws '%s'" % v)
	for v in ["brine_glob", "brine_wave", "tide_ring", "brine_puddle", "brine_flood"]:
		check(not fx.moves.by_vfx.has(v), "the v0.9.17 '%s' recipe is not taken over" % v)
	# every effect it names is drawn (a script error would leave it undrawn)
	for v in VFX:
		var ev := {"type": "effect", "fighter": 0, "effect": "area", "vfx": v, "pos": Vector3(0, 0.5, 1.0), "origin": Vector3.ZERO, "radius": 1.5,
			"length": 5.0, "width": 1.0, "shape": "line", "yaw": 0.0, "speed": 5.0, "duration": 0.4, "element": "brine", "pool": "x"}
		check(kit.on_effect(0, ev), "'%s' draws" % v)
	await wait_frames(80)
	check((kit._braces as Dictionary).is_empty(), "the brace drawn above (0.4 s) has ended")
	_free(fx, views)


func test_effects_follow_their_moves_and_clean_up() -> void:
	var views := _views(["f_dredge"])
	var fx := _fx(views)
	var kit = fx.moves.kits.get("f_dredge")
	if kit == null:
		fail("Dredge's kit is not loaded")
		_free(fx, views)
		return
	# Bubble Stream: froth wells at the mouth while sustained, stops on release or when cut off
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "mv.bubble_stream", "id": "f_dredge.mv.bubble_stream", "pool": "bubble_stream", "cat": "stream"})
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "start", "pool": "bubble_stream", "slot": "m2"})
	check((kit._froth as Dictionary).has(0), "blowing: froth at the mouth")
	await wait_frames(4)
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "end", "pool": "bubble_stream", "slot": "m2"})
	check(not (kit._froth as Dictionary).has(0), "release ends it")
	fx.on_event({"type": "sustain", "fighter": 0, "phase": "start", "pool": "bubble_stream", "slot": "m2"})
	_state[0] = Fighter.State.HITSTUN
	await wait_frames(4)
	check(not (kit._froth as Dictionary).has(0), "a stream cut off stops frothing")
	_state.erase(0)
	# Hydro Cannon: the water gathers with the charge, the beam ends it; cut off, it spills
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "mv.hydro_cannon", "id": "f_dredge.mv.hydro_cannon", "pool": "hydro_cannon", "cat": "blast"})
	_charge[0] = 0.8
	await wait_frames(6)
	var c: Dictionary = (kit._cannons as Dictionary).get(0, {})
	check(not c.is_empty() and float(c.get("level", 0.0)) > 0.7, "the charge swells the barrel (%s)" % str(c.get("level", "-")))
	var orb = c.get("orb")
	_charge[0] = -1.0
	fx.on_event({"type": "effect", "fighter": 0, "effect": "area", "vfx": "dredge_hydro_beam", "pool": "hydro_cannon", "pos": Vector3.ZERO,
		"origin": Vector3.ZERO, "length": 5.6, "width": 1.1, "radius": 0.0, "shape": "line", "yaw": 0.0, "element": "brine"})
	check(not (kit._cannons as Dictionary).has(0), "firing ends the charge")
	await wait_frames(2)
	check(orb == null or not is_instance_valid(orb), "and its barrel of water")
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "mv.hydro_cannon", "id": "f_dredge.mv.hydro_cannon", "pool": "hydro_cannon", "cat": "blast"})
	_state[0] = Fighter.State.HITSTUN
	await wait_frames(4)
	check(not (kit._cannons as Dictionary).has(0), "a cannon cut off spills its water")
	_state.erase(0)
	# Whirlpool: the pool shows under the stir until the claws strike the floor
	fx.on_event({"type": "move_start", "fighter": 0, "slot": "mv.whirlpool", "id": "f_dredge.mv.whirlpool", "pool": "whirlpool", "cat": "control"})
	check((kit._whirls as Dictionary).has(0), "the stir shows the pool to come")
	fx.on_event({"type": "effect", "fighter": 0, "effect": "area", "vfx": "dredge_whirl_open", "pool": "whirlpool", "pos": Vector3(0, 0, 1.6),
		"radius": 2.4, "shape": "circle", "yaw": 0.0, "element": "brine"})
	check(not (kit._whirls as Dictionary).has(0), "and gives way to the real one")
	# a bubble and a whirlpool follow their simulation entities, then clean up
	fx.sync_entities([{"id": 1, "kind": "projectile", "vfx": "dredge_bubble", "pos": Vector3(0, 0.7, 1.0), "radius": 0.22, "element": "brine", "team": 0},
		{"id": 2, "kind": "zone", "vfx": "dredge_whirlpool", "zone_kind": "brine_puddle", "pos": Vector3(0, 0, 2.0), "radius": 2.4, "element": "brine", "team": 0}])
	check(fx._ents.has(1) and fx._ents.has(2), "a bubble and a whirlpool are drawn")
	var bubble: Node3D = (fx._ents[1] as Dictionary)["node"]
	var pool_node: Node3D = (fx._ents[2] as Dictionary)["node"]
	await wait_frames(3)
	fx.sync_entities([{"id": 1, "kind": "projectile", "vfx": "dredge_bubble", "pos": Vector3(0, 0.75, 1.4), "radius": 0.22, "element": "brine", "team": 0},
		{"id": 2, "kind": "zone", "vfx": "dredge_whirlpool", "zone_kind": "brine_puddle", "pos": Vector3(1, 0, 2.0), "radius": 2.4, "element": "brine", "team": 0}])
	check(bubble.global_position.is_equal_approx(Vector3(0, 0.75, 1.4)), "the bubble drifts with its projectile")
	check(is_equal_approx(pool_node.global_position.x, 1.0), "the whirlpool follows its zone")
	fx.sync_entities([])
	await wait_frames(60)
	check(not is_instance_valid(bubble), "the bubble pops and is cleaned up")
	check(not is_instance_valid(pool_node), "the whirlpool drains away and is cleaned up")
	_free(fx, views)


# ---- helpers ---------------------------------------------------------------------------------

## Projectile events of the Bubble Stream (one per puff).
func _puffs(sim: MatchSim) -> int:
	return pool_events(sim, "effect", "bubble_stream").filter(func(e: Dictionary) -> bool: return str(e["effect"]) == "projectile").size()


## Area effect events of a pool move of fighter 0.
func _areas(sim: MatchSim, pool: String) -> Array:
	return pool_events(sim, "effect", pool).filter(func(e: Dictionary) -> bool: return str(e["effect"]) == "area")


func _gap(a: Fighter, b: Fighter) -> float:
	return _flat(a.pos(), b.pos())


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Damage of the last hit fighter `target` took.
func _last_hit_on(sim: MatchSim, target: int) -> float:
	var hits := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "hit" and int(e.get("target", -1)) == target)
	return float((hits[-1] as Dictionary).get("damage", 0.0)) if not hits.is_empty() else 0.0


## Dredge drilled in styles ({pool move: style}): his content with those patches applied.
func _drilled(styles: Dictionary) -> CreatureDef:
	var d: Dictionary = Content.creature_entry("f_dredge").duplicate(true)
	var c := Content.creature("f_dredge")
	for id in styles:
		var pm: PoolMove = c.pool[id]
		var st: Dictionary = pm.styles[styles[id]]
		ContentPatch.apply_all(d, st["patch"])
	var dc := CreatureDef.from_dict(d, Callable(), "test")
	check(dc.is_valid(), "the drilled Dredge parses (%s)" % str(dc.errors))
	return dc


## A Movesets duel like duel(), with a creature definition (a drilled Dredge) instead of an id.
func _duel_with(c: CreatureDef, loadout: Array, gap: float) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 7.0, "spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": "moves"}, "seed": 7, "fighters": [
		{"creature": c, "team": 0, "source": null, "loadout": loadout},
		{"creature": Content.creature(FOE), "team": 1, "source": null}]})
	return sim


func _fx(views: Array) -> AbilityVfx:
	var fx := AbilityVfx.new()
	fx.view_of = func(i: int): return views[i] if i >= 0 and i < views.size() else null
	fx.info_of = func(i: int) -> Dictionary:
		if i < 0 or i >= views.size():
			return {}
		return {"ground": Vector3(i * 2.0, 0, 0), "yaw": 0.0, "state": int(_state.get(i, Fighter.State.ABILITY)), "juiced": false,
			"hidden": false, "charge": float(_charge.get(i, -1.0)), "out": false}
	fx.fighter_count = func() -> int: return views.size()
	add_child(fx)
	return fx


func _views(ids: Array) -> Array:
	var out := []
	for id in ids:
		var v := CreatureView.new()
		add_child(v)
		v.setup(Content.creature(str(id)))
		out.append(v)
	return out


func _free(fx: AbilityVfx, views: Array) -> void:
	fx.queue_free()
	for v in views:
		(v as Node).queue_free()
	_state.clear()
	_charge.clear()
