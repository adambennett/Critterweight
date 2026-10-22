extends MovesKitCase
## Jitters' v0.9.18 move pool (docs/kits/f_jitters.md "Movesets", docs/design/MOVESET_COMBAT.md §4):
## every move does what its description says, in Movesets, against standing dev_biped dummies (whose
## pool, built from their Classic kit, never changes); the styles are clean patches that change
## behaviour; and the effects kit draws and cleans up every event and entity it names.

const LIVE_WIRE := ["slap", "thunder_jolt", "arc_lash", "spring_pad"]
const OVERLOAD := ["slap", "discharge", "chain_lightning", "static_field"]
const POOL := ["slap", "squash", "arc_lash", "spring_pad", "thunder_jolt", "discharge", "chain_lightning", "static_field"]
const FOE := "dev_biped"
const POWER := 1.25            ## Jitters' power stat: effect damage scales with it
const VFX := ["jitters_thunder_jolt", "jitters_chain_bolt", "jitters_chain_arc", "jitters_chain_beam", "jitters_static_field",
	"jitters_chain_field", "jitters_discharge_core", "jitters_discharge_ring"]

var _state := {}               ## fighter -> Fighter.State the effects test's info callable reports


func test_pool_and_loadouts() -> void:
	var c := Content.creature("f_jitters")
	for id in POOL:
		check_pool_move("f_jitters", id)
	check_eq(c.resolve_loadout([]), LIVE_WIRE, "the default loadout is Live Wire")
	check_eq((c.loadouts["overload"] as Dictionary)["moves"], OVERLOAD, "Overload is the second build")
	var shared := LIVE_WIRE.filter(func(x) -> bool: return OVERLOAD.has(x))
	check_eq(shared, ["slap"], "the two builds share only the basic strike")
	var want := {"slap": ["strike", "basic", ""], "squash": ["strike", "heavy", "charge"], "arc_lash": ["projectile", "special", ""],
		"spring_pad": ["utility", "special", ""], "thunder_jolt": ["projectile", "special", ""], "discharge": ["blast", "special", ""],
		"chain_lightning": ["projectile", "special", ""], "static_field": ["control", "special", ""]}
	for id in want:
		var pm: PoolMove = c.pool[id]
		check_eq([pm.category, pm.role, pm.hold], want[id], "%s: category, role, hold" % id)
	# the v0.9.17 moves are the Classic moves themselves (so upgrades written for them keep working)
	var slap: PoolMove = c.pool["slap"]
	var squash: PoolMove = c.pool["squash"]
	check_eq(slap.string, ["l1", "l2", "l3", "finisher"], "the basic string ends in the Static Cling")
	check_eq(slap.dash, "dash_attack", "out of a dodge: Pinball")
	check(squash.move == c.moves["heavy"] and squash.charged == c.moves["heavy_charged"], "Squash charges into the Super Squash")
	check((c.pool["arc_lash"] as PoolMove).move == c.abilities["ability1"] and (c.pool["spring_pad"] as PoolMove).move == c.abilities["ability2"],
		"Arc Lash and Spring Pad are the v0.9.17 abilities")
	check(is_equal_approx((c.pool["arc_lash"] as PoolMove).cooldown, 6.0) and is_equal_approx((c.pool["spring_pad"] as PoolMove).cooldown, 7.0),
		"with their own cooldowns")
	# the four new moves: static specials with real cooldowns and stamina costs
	for id in ["thunder_jolt", "discharge", "chain_lightning", "static_field"]:
		var pm2: PoolMove = c.pool[id]
		check(pm2.cooldown >= 4.0 and pm2.cooldown <= 12.0 and pm2.stamina_cost() > 0.0, "%s: cooldown %.1f s, cost %.0f" % [id, pm2.cooldown, pm2.stamina_cost()])
		check(pm2.move.kind == "ability" and pm2.element == "static" and not pm2.move.keys.is_empty(), "%s: an animated static move" % id)


## Every style is a well-formed patch that hits this fighter's data, the drilled fighter still parses,
## and the style changes how the move behaves (spot checks on the parsed result).
func test_styles_patch_cleanly() -> void:
	var c := Content.creature("f_jitters")
	for id in POOL:
		var pm: PoolMove = c.pool[id]
		for sid in pm.styles:
			var patch: Array = (pm.styles[sid] as Dictionary)["patch"]
			for p in patch:
				check_eq(ContentPatch.validate(p), "", "%s.%s: patch is well formed" % [id, sid])
			var d: Dictionary = Content.creature_entry("f_jitters").duplicate(true)
			var res := ContentPatch.apply_all(d, patch)
			check((res["unmatched"] as Array).is_empty(), "%s.%s: every patch hits a field (%s)" % [id, sid, str(res["unmatched"])])
			var dc := CreatureDef.from_dict(d, Callable(), "test")
			check(dc.is_valid(), "%s.%s: the drilled Jitters parses (%s)" % [id, sid, str(dc.errors)])
	var cap := _drilled("discharge", "capacitor").pool["discharge"] as PoolMove
	check(cap.hold == "charge" and cap.move.charge_time > 0.0 and cap.move.charge_at >= 0.0, "Capacitor: hold to charge")
	var ls := _drilled("chain_lightning", "lightning_strike").pool["chain_lightning"] as PoolMove
	var line := AbilityVfx.effect_of(ls.move, "area")
	check(str(line.get("shape", "")) == "line" and AbilityVfx.effect_of(ls.move, "projectile").is_empty(), "Lightning Strike: an instant line, no ball")
	check(not (line.get("status", {}) as Dictionary).is_empty(), "which still marks what it hits to jump from")
	var ta := _drilled("static_field", "tesla_aura").pool["static_field"] as PoolMove
	check(bool(AbilityVfx.effect_of(ta.move, "zone").get("follow_owner", false)), "Tesla Aura: the field rides on Jitters")
	var sb := _drilled("spring_pad", "springboard")
	check_eq(str(AbilityVfx.effect_of(sb.abilities["ability2"], "prop").get("at", "")), "self", "Springboard: the pad lands under Jitters")
	var af := _drilled("squash", "aftershock")
	check_eq((AbilityVfx.effect_of(af.moves["heavy_charged"], "leap").get("on_land", []) as Array).size(), 2, "Aftershock: the landing also leaves a field")


func test_thunder_jolt_crosses_the_cage_and_jolts() -> void:
	var sim := duel("f_jitters", LIVE_WIRE, FOE, 5.0)
	await step_sim(sim, 0.4)
	var d := sim.fighters[1]
	var z0 := sim.fighters[0].pos().z
	await use_slot(sim, 0, 1, 0.0, 0.15)          # Move 2 = Thunder Jolt (it leaves the cap 0.14 s in)
	check(not pool_entities(sim, "thunder_jolt", "projectile").is_empty(), "a bolt is in the air")
	await step_sim(sim, 0.5)
	check(sim.fighters[0].pos().z < z0 - 0.05, "the pop bounces Jitters back (%.2f m)" % (z0 - sim.fighters[0].pos().z))
	var launch := _launches(sim, "thunder_jolt")
	var hits := pool_events(sim, "hit", "thunder_jolt")
	if check(not launch.is_empty() and not hits.is_empty(), "it hits the target 5 m away (%d launches, %d hits)" % [launch.size(), hits.size()]):
		var flight := float(int(hits[0]["tick"]) - int(launch[0]["tick"])) / Engine.physics_ticks_per_second
		check(flight < 0.3, "very fast: %.2f s across the gap" % flight)
		check_eq(str(hits[0].get("cat", "")), "projectile", "attributed to a projectile move")
		check_near(float(hits[0]["damage"]), 4.0 * POWER, 0.2, "a light poke")
	check(float(d.statuses.buildup.get("static", 0.0)) >= 20.0 or d.statuses.has_element("static"), "that builds Jolted (%s)" % str(d.statuses.buildup))


## Thunder Jolt is a bolt: a guard tapped as it arrives parries it, and the parried bolt does nothing.
func test_thunder_jolt_parried_by_a_timed_guard() -> void:
	var sim := duel("f_jitters", LIVE_WIRE, FOE, 5.0)
	await step_sim(sim, 0.4)
	var t0 := sim.tick_count
	await use_slot(sim, 0, 1, 0.0, 0.6)
	var hits := pool_events(sim, "hit", "thunder_jolt")
	if not check(not hits.is_empty(), "setup: the bolt lands on an open target"):
		return
	var lead := int(hits[0]["tick"]) - t0               # ticks from the press to the hit
	var sim2 := duel("f_jitters", LIVE_WIRE, FOE, 5.0)
	await step_sim(sim2, 0.4)
	var d := sim2.fighters[1]
	var hp := d.health
	sim2.fighters[0].input.press(FighterInput.HEAVY)    # Move 2
	await _ticks(sim2, 2)
	sim2.fighters[0].input.set_held(FighterInput.HEAVY, false)
	await _ticks(sim2, lead - 2 - roundi(0.08 * Engine.physics_ticks_per_second))
	d.input.press(FighterInput.GUARD)                   # 0.08 s before it arrives (parry window 0.12 s)
	await step_sim(sim2, 0.4)
	var hits2 := pool_events(sim2, "hit", "thunder_jolt")
	check(not hits2.is_empty() and bool(hits2[0]["parried"]), "the guard tap parries it (%s)" % str(hits2))
	check_near(d.health, hp, 0.01, "and it does no damage")


## Chain Lightning: the ball strikes the locked target and the charge jumps to the nearest other foe
## within 3 m (4.5 m from a Soaked target); a guarded ball does not jump.
func test_chain_lightning_jumps_to_a_second_foe() -> void:
	var sim := _trio(3.5, Vector2(2.0, 2.75))           # the second dummy 2.2 m from the first
	await step_sim(sim, 0.4)
	await use_slot(sim, 0, 2, 0.0, 1.0)                 # Move 3 = Chain Lightning
	var on_first := pool_events(sim, "hit", "chain_lightning").filter(func(e: Dictionary) -> bool: return int(e["target"]) == 1)
	var on_second := pool_events(sim, "hit", "chain_lightning").filter(func(e: Dictionary) -> bool: return int(e["target"]) == 2)
	check(not on_first.is_empty() and str(on_first[0]["move"]) == "chain_lightning" and str(on_first[0]["cat"]) == "projectile",
		"the ball strikes the locked target (%s)" % str(on_first))
	check(not on_second.is_empty() and str(on_second[0]["move"]) == "chain_lightning_arc" and str(on_second[0]["cat"]) == "projectile",
		"and jumps to the second (%s)" % str(on_second))
	if not on_first.is_empty() and not on_second.is_empty():
		check_eq(int(on_second[0]["tick"]), int(on_first[0]["tick"]), "at once")
	check(sim.events.any(func(e: Dictionary) -> bool: return str(e["type"]) == "arc" and int(e["fighter"]) == 0), "an arc event for the views and commentary")
	# 3.8 m apart: out of reach, unless the struck fighter is Soaked
	for soaked in [false, true]:
		var sim2 := _trio(3.5, Vector2(3.8, 1.75))
		await step_sim(sim2, 0.4)
		if soaked:
			sim2.fighters[1].statuses.add_buildup("brine", 100.0, null)
			check(sim2.fighters[1].statuses.has_element("brine"), "setup: the target is Soaked")
		await use_slot(sim2, 0, 2, 0.0, 1.0)
		check(not pool_events(sim2, "hit", "chain_lightning").filter(func(e: Dictionary) -> bool: return int(e["target"]) == 1).is_empty(), "the ball lands (soaked %s)" % str(soaked))
		var jumped := not pool_events(sim2, "hit", "chain_lightning").filter(func(e: Dictionary) -> bool: return int(e["target"]) == 2).is_empty()
		check(jumped == soaked, "3.8 m: %s" % ("a Soaked target conducts it that far" if soaked else "too far to jump"))
	# a guard earths it
	var sim3 := _trio(3.5, Vector2(2.0, 2.75))
	await step_sim(sim3, 0.4)
	sim3.fighters[1].input.press(FighterInput.GUARD)
	await step_sim(sim3, 0.2)
	await use_slot(sim3, 0, 2, 0.0, 1.0)
	var blocked := pool_events(sim3, "hit", "chain_lightning").filter(func(e: Dictionary) -> bool: return int(e["target"]) == 1)
	check(not blocked.is_empty() and bool(blocked[0]["blocked"]), "the ball is guarded (%s)" % str(blocked))
	check(pool_events(sim3, "hit", "chain_lightning").filter(func(e: Dictionary) -> bool: return int(e["target"]) == 2).is_empty(), "a guarded ball does not jump")


func test_discharge_bursts_then_rings() -> void:
	var sim := duel("f_jitters", OVERLOAD, FOE, 1.2)
	await step_sim(sim, 0.4)
	var d := sim.fighters[1]
	await use_slot(sim, 0, 1, 0.0, 1.0)                 # Move 2 = Discharge
	var hits := pool_events(sim, "hit", "discharge")
	var core := hits.filter(func(e: Dictionary) -> bool: return str(e["move"]) == "discharge")
	check(not core.is_empty() and str(core[0]["cat"]) == "blast", "the burst hits the fighter beside Jitters (%s)" % str(hits))
	var rings := pool_events(sim, "effect", "discharge").filter(func(e: Dictionary) -> bool: return str(e.get("vfx", "")) == "jitters_discharge_ring")
	check_eq(rings.size(), 3, "the ring crackles three times")
	var gap := Vector2(d.pos().x - sim.fighters[0].pos().x, d.pos().z - sim.fighters[0].pos().z).length()
	check(gap > 1.7, "and it hurls the fighter back (%.2f m from 1.2 m)" % gap)
	# 2.2 m out: past the burst, inside the ring
	var sim2 := duel("f_jitters", OVERLOAD, FOE, 2.2)
	await step_sim(sim2, 0.4)
	await use_slot(sim2, 0, 1, 0.0, 1.0)
	var hits2 := pool_events(sim2, "hit", "discharge")
	check(not hits2.is_empty() and hits2.all(func(e: Dictionary) -> bool: return str(e["move"]) == "discharge_ring"),
		"only the ring reaches 2.2 m (%s)" % str(hits2.map(func(e: Dictionary) -> String: return str(e["move"]))))


## The squash shrugs off a light hit (the burst still comes) but not a heavy one.
func test_discharge_squash_armours_against_lights() -> void:
	for cls in ["light", "heavy"]:
		var sim := duel("f_jitters", OVERLOAD, FOE, 1.2)
		await step_sim(sim, 0.4)
		var j := sim.fighters[0]
		j.input.press(FighterInput.HEAVY)               # Move 2 = Discharge
		await _ticks(sim, 2)
		j.input.set_held(FighterInput.HEAVY, false)
		await step_sim(sim, 0.18)
		check_eq(j.move_pool_id, "discharge", "setup: squashing (%s)" % cls)
		sim.effects.effect_hit(sim.fighters[1], j, {"damage": 3.0, "stun": 0.4, "poise": 4.0, "class": cls}, sim.fighters[1].pos())
		await step_sim(sim, 0.5)
		var burst := pool_events(sim, "effect", "discharge").filter(func(e: Dictionary) -> bool: return str(e.get("vfx", "")) == "jitters_discharge_core")
		if cls == "light":
			check(not burst.is_empty(), "a light hit does not stop the Discharge")
		else:
			check(burst.is_empty(), "a heavy hit knocks it out of the squash")


## Static Field: it lands on whoever is in front (flinching a charging attack out of its charge), keeps
## them twitching and builds Jolted; anyone walking in later flinches too; Jitters is immune.
func test_static_field_flinches_whoever_enters() -> void:
	var sim := duel("f_jitters", OVERLOAD, FOE, 2.5)
	await step_sim(sim, 0.4)
	var d := sim.fighters[1]
	d.input.press(FighterInput.HEAVY)                   # the dummy's Move 2: its Haymaker, held to charge
	await step_sim(sim, 0.3)
	check(d.move != null and d.move_charge > 0.0, "setup: the dummy is charging (%.2f)" % d.move_charge)
	var n0 := sim.events.size()
	await use_slot(sim, 0, 3, 0.0, 0.3)                 # Move 4 = Static Field
	var zone := pool_entities(sim, "static_field", "zone")
	if check(not zone.is_empty(), "a static field lies on the floor"):
		check_near(float(zone[0]["radius"]), 2.0, 0.01, "2 m across each way")
	var flinches := sim.events.slice(n0).filter(func(e: Dictionary) -> bool: return str(e["type"]) == "flinch" and int(e["fighter"]) == 1)
	check(not flinches.is_empty() and bool(flinches[0]["interrupted"]), "the dummy flinches out of its charge (%s)" % str(flinches))
	check(d.move == null or d.move_slot != "heavy", "its charge is gone (%s)" % d.move_slot)
	await step_sim(sim, 1.6)
	var twitches := sim.events.slice(n0).filter(func(e: Dictionary) -> bool: return str(e["type"]) == "flinch" and int(e["fighter"]) == 1)
	check(twitches.size() >= 3, "and keeps twitching inside (%d flinches)" % twitches.size())
	check(float(d.statuses.buildup.get("static", 0.0)) > 0.0 or d.statuses.has_element("static"), "while Jolted builds (%s)" % str(d.statuses.buildup))
	check(sim.events.slice(n0).filter(func(e: Dictionary) -> bool: return str(e["type"]) == "flinch" and int(e["fighter"]) == 0).is_empty(), "Jitters is immune to its own field")
	# a fighter outside is untouched until it walks in
	var sim2 := duel("f_jitters", OVERLOAD, FOE, 4.6)
	await step_sim(sim2, 0.4)
	var d2 := sim2.fighters[1]
	var m0 := sim2.events.size()
	await use_slot(sim2, 0, 3, 0.0, 0.5)
	var early := sim2.events.slice(m0).filter(func(e: Dictionary) -> bool: return str(e["type"]) == "flinch" and int(e["fighter"]) == 1)
	check(early.is_empty(), "nobody outside the field flinches")
	d2.input.move = Vector3(0, 0, -1)                   # it walks in toward Jitters
	await step_sim(sim2, 1.0)
	d2.input.move = Vector3.ZERO
	var late := sim2.events.slice(m0).filter(func(e: Dictionary) -> bool: return str(e["type"]) == "flinch" and int(e["fighter"]) == 1)
	check(not late.is_empty(), "walking in flinches it")


## The two v0.9.17 abilities and the heavy work as moves: Arc Lash throws its orb, Spring Pad plants
## its pad, Squash charges into the Super Squash when held.
func test_v0917_moves_carry_over() -> void:
	var sim := duel("f_jitters", LIVE_WIRE, FOE, 4.0)
	await step_sim(sim, 0.4)
	await use_slot(sim, 0, 2, 0.0, 0.3)                 # Move 3 = Arc Lash
	check(not pool_entities(sim, "arc_lash", "projectile").is_empty(), "Arc Lash throws its homing orb")
	await step_sim(sim, 1.0)
	await use_slot(sim, 0, 3, 0.0, 0.4)                 # Move 4 = Spring Pad
	check(not pool_entities(sim, "spring_pad", "prop").is_empty(), "Spring Pad plants its pad")
	var sim2 := duel("f_jitters", ["slap", "squash"], FOE, 2.0)
	await step_sim(sim2, 0.4)
	var s := sim2.fighters[0]
	s.input.press(FighterInput.HEAVY)                   # Move 2 = Squash
	await step_sim(sim2, 0.9)
	check(s.move_charge > 0.4, "holding charges it (%.2f)" % s.move_charge)
	s.input.set_held(FighterInput.HEAVY, false)
	await step_sim(sim2, 0.1)
	check_eq(s.move_slot, "heavy_charged", "release: the Super Squash")
	await step_sim(sim2, 1.8)


## Classic is untouched: with the pool in its file, a Classic match still plays the v0.9.17 kit on
## the v0.9.17 inputs (Light the Slap string, Heavy the Squash, the abilities on their own buttons).
func test_classic_jitters_is_unchanged() -> void:
	var sim := duel("f_jitters", [], FOE, 2.0, {"combat": "classic"})
	await step_sim(sim, 0.4)
	var j := sim.fighters[0]
	check(j.combat_style == "classic" and j.loadout.is_empty(), "a Classic match, no loadout")
	for step in [[FighterInput.LIGHT, "l1"], [FighterInput.HEAVY, "heavy"], [FighterInput.AB1, "ability1"], [FighterInput.AB2, "ability2"]]:
		var b := int(step[0])
		j.input.press(b)
		await _ticks(sim, 2)
		j.input.set_held(b, false)
		check(j.move_slot.split("@")[0] == str(step[1]) and j.move_pool_id == "", "Classic input %d plays %s (%s)" % [b, str(step[1]), j.move_slot])
		await step_sim(sim, 2.0)


## A few styles in a duel: Capacitor's charge grows the burst, Double Jolt fires twice, Tesla Aura's
## field rides along, Ground Current leaves a field where the ball bursts, Lightning Strike is instant.
func test_styles_in_a_duel() -> void:
	# Capacitor: a full charge reaches a third further than a tap
	var radii := []
	for held in [0.0, 1.1]:
		var sim := _duel_drilled(_drilled("discharge", "capacitor"), ["slap", "discharge"], 2.4)
		await step_sim(sim, 0.4)
		await use_slot(sim, 0, 1, held, 0.6)
		var core := pool_events(sim, "effect", "discharge").filter(func(e: Dictionary) -> bool: return str(e.get("vfx", "")) == "jitters_discharge_core")
		radii.append(float(core[0]["radius"]) if not core.is_empty() else 0.0)
	check(is_equal_approx(float(radii[0]), 1.3) and float(radii[1]) > 1.7, "Capacitor: charge scales the burst (%s)" % str(radii))
	# Double Jolt: two bolts, each lighter
	var sim2 := _duel_drilled(_drilled("thunder_jolt", "double_jolt"), ["slap", "thunder_jolt"], 4.0)
	await step_sim(sim2, 0.4)
	await use_slot(sim2, 0, 1, 0.0, 0.8)
	var launches := _launches(sim2, "thunder_jolt")
	var hits := pool_events(sim2, "hit", "thunder_jolt")
	check(launches.size() == 2 and hits.size() == 2, "Double Jolt: two bolts, two hits (%d, %d)" % [launches.size(), hits.size()])
	if not hits.is_empty():
		check_near(float(hits[0]["damage"]), 0.6 * 4.0 * POWER, 0.2, "each a lighter bolt")
	# Tesla Aura: the field moves with Jitters
	var sim3 := _duel_drilled(_drilled("static_field", "tesla_aura"), ["slap", "static_field"], 4.0)
	await step_sim(sim3, 0.4)
	await use_slot(sim3, 0, 1, 0.0, 0.4)
	var j := sim3.fighters[0]
	j.input.move = Vector3(1, 0, 0)                     # it walks off sideways once the slam is over
	await step_sim(sim3, 1.0)
	j.input.move = Vector3.ZERO
	var aura := pool_entities(sim3, "static_field", "zone")
	if check(not aura.is_empty(), "Tesla Aura: a field around Jitters"):
		var zp: Vector3 = aura[0]["pos"]
		check(Vector2(zp.x - j.pos().x, zp.z - j.pos().z).length() < 0.2 and absf(j.pos().x) > 0.5, "that follows it (zone %s, Jitters %s)" % [zp, j.pos()])
	# Ground Current: a small field where the ball bursts
	var sim4 := _duel_drilled(_drilled("chain_lightning", "ground_current"), ["slap", "chain_lightning"], 3.5)
	await step_sim(sim4, 0.4)
	await use_slot(sim4, 0, 1, 0.0, 0.9)
	check(not pool_entities(sim4, "chain_lightning", "zone").is_empty(), "Ground Current: the burst leaves a static field")
	# Lightning Strike: no ball in flight, the line lands the moment it fires
	var sim5 := _duel_drilled(_drilled("chain_lightning", "lightning_strike"), ["slap", "chain_lightning"], 5.0)
	await step_sim(sim5, 0.4)
	await use_slot(sim5, 0, 1, 0.0, 0.8)
	var strike := pool_events(sim5, "effect", "chain_lightning")
	var struck := pool_events(sim5, "hit", "chain_lightning")
	check(not strike.is_empty() and not struck.is_empty() and int(struck[0]["tick"]) == int(strike[0]["tick"]),
		"Lightning Strike: the bolt lands the instant it fires (%d, %d)" % [strike.size(), struck.size()])


## The effects kit (src/view/fx/moves/f_jitters.gd): registered under its own names, a build-up for
## each new move that ends at its first effect (or when the move is cut off), every event drawn, a
## chain jump drawn from whichever of its halves comes first, projectile and field entities that
## follow their entity (and its size) and clean up after themselves, at any quality.
func test_effects_kit_draws_and_cleans_up() -> void:
	var views := _views(["f_jitters", "f_dredge"])
	var fx := _fx(views)
	await wait_vfx_seconds(30.0 / 120.0)
	var kit = fx.moves.kits.get("f_jitters")
	if not check(kit != null, "Jitters' effects kit is loaded"):
		_free(fx, views)
		return
	for v in VFX:
		check(fx.moves.by_vfx.get(v) == kit, "the kit draws '%s'" % v)
	for v in ["orb", "pulse", "discharge", "squash", "overcharge", "spring_pad", "static_field"]:
		check(not fx.moves.by_vfx.has(v), "the v0.9.17 recipe '%s' is left alone" % v)
	var before := fx.get_child_count()
	# each new move's build-up runs from its start to its first effect
	var firsts := {"thunder_jolt": _effect("jitters_thunder_jolt", "projectile"), "chain_lightning": _effect("jitters_chain_bolt", "projectile"),
		"discharge": _effect("jitters_discharge_core", "area", {"radius": 1.3}), "static_field": _effect("jitters_static_field", "zone", {"radius": 2.0})}
	for pool in firsts:
		fx.on_event(_move_start(pool))
		check((kit._preps as Dictionary).has(0), "%s: its build-up starts with the move" % pool)
		await wait_vfx_seconds(8.0 / 120.0)
		fx.on_event(firsts[pool])
		check(not (kit._preps as Dictionary).has(0), "%s: and ends at its first effect" % pool)
	check(fx.get_child_count() > before + 10, "effects were built (%d nodes)" % (fx.get_child_count() - before))
	# a move cut off mid build-up takes its build-up with it
	fx.on_event(_move_start("discharge"))
	await wait_frames(3)
	_state[0] = Fighter.State.HITSTUN
	await wait_frames(3)
	check(not (kit._preps as Dictionary).has(0), "an interrupted build-up ends with the move")
	_state.erase(0)
	# every other event it names, and the hits of its moves
	fx.on_event(_effect("jitters_discharge_ring", "area", {"shape": "ring", "inner": 1.1, "radius": 2.5}))
	fx.on_event(_effect("jitters_chain_beam", "area", {"shape": "line", "length": 6.5, "width": 0.7, "origin": Vector3.ZERO}))
	fx.on_event(_effect("jitters_chain_field", "zone", {"radius": 1.1}))
	for h in [["thunder_jolt", "thunder_jolt", false], ["thunder_jolt", "thunder_jolt", true], ["chain_lightning", "chain_lightning", false],
			["chain_lightning", "chain_lightning", true], ["discharge", "discharge", false], ["discharge", "discharge_ring", false]]:
		fx.on_event(_hit(str(h[0]), str(h[1]), bool(h[2])))
	# a chain jump's two halves meet in either order, and a lone half lapses
	fx.on_event(_hit("chain_lightning", "chain_lightning_arc", false))
	check((kit._jumps as Dictionary).has(0), "the jump's hit waits for its effect")
	fx.on_event(_effect("jitters_chain_arc", "chain_arc", {"radius": 3.0}))
	check(not (kit._jumps as Dictionary).has(0), "and the two meet in the leap")
	fx.on_event(_effect("jitters_chain_arc", "chain_arc", {"radius": 4.5}))
	fx.on_event(_hit("chain_lightning", "chain_lightning_arc", false))
	check(not (kit._jumps as Dictionary).has(0), "in either order")
	fx.on_event(_effect("jitters_chain_arc", "chain_arc", {"radius": 3.0}))
	await wait_vfx_seconds(40.0 / 120.0)
	check(not (kit._jumps as Dictionary).has(0), "a jump that found no second foe lapses")
	# entities: the bolt and the ball fly with their projectiles, the fields follow their zones
	var ents := [
		{"id": 1, "kind": "projectile", "vfx": "jitters_thunder_jolt", "pos": Vector3(0, 1, 1), "radius": 0.16, "element": "static", "team": 0},
		{"id": 2, "kind": "projectile", "vfx": "jitters_chain_bolt", "pos": Vector3(0, 1, 2), "radius": 0.24, "element": "static", "team": 0},
		{"id": 3, "kind": "zone", "zone_kind": "static_field", "vfx": "jitters_static_field", "pos": Vector3.ZERO, "radius": 2.0, "element": "static", "team": 0, "owner": 0},
		{"id": 4, "kind": "zone", "zone_kind": "static_field", "vfx": "jitters_chain_field", "pos": Vector3(3, 0, 3), "radius": 1.1, "element": "static", "team": 0}]
	fx.sync_entities(ents)
	for id in [1, 2, 3, 4]:
		check(fx._ents.has(id) and str((fx._ents[id] as Dictionary).get("kind", "")) != "", "entity %d is drawn" % id)
	var bolt_node: Node3D = (fx._ents[1] as Dictionary)["node"]
	var ball_node: Node3D = (fx._ents[2] as Dictionary)["node"]
	var field_node: Node3D = (fx._ents[3] as Dictionary)["node"]
	for k in 10:
		ents[0]["pos"] = Vector3(0, 1, 1 + 0.4 * (k + 1))
		ents[1]["pos"] = Vector3(0, 1, 2 + 0.25 * (k + 1))
		ents[2]["pos"] = Vector3(0.1 * (k + 1), 0, 0)
		ents[2]["radius"] = 2.4
		fx.sync_entities(ents)
		await wait_frames(1)
	check(bolt_node.global_position.is_equal_approx(Vector3(0, 1, 5)), "the bolt flies with its projectile")
	check(ball_node.global_position.is_equal_approx(Vector3(0, 1, 4.5)), "the ball flies with its projectile")
	check(is_equal_approx(field_node.global_position.x, 1.0), "the field follows its zone")
	check(_footprint_radius(field_node) > 2.39, "and its size (%.2f)" % _footprint_radius(field_node))
	fx.sync_entities([])
	# the same at Low quality with Reduce flashing
	fx.configure(0, true)
	fx.on_event(_move_start("chain_lightning"))
	await wait_frames(4)
	fx.on_event(_effect("jitters_chain_bolt", "projectile"))
	fx.on_event(_effect("jitters_discharge_core", "area", {"radius": 1.3}))
	fx.on_event(_effect("jitters_discharge_ring", "area", {"shape": "ring", "inner": 1.1, "radius": 2.5}))
	fx.on_event(_hit("thunder_jolt", "thunder_jolt", false))
	fx.sync_entities(ents)
	await wait_frames(3)
	fx.sync_entities([])
	# everything transient dissipates and frees itself
	await wait_vfx_seconds(4.0)
	check(not is_instance_valid(bolt_node) and not is_instance_valid(ball_node) and not is_instance_valid(field_node), "entity looks are freed")
	var left := []
	for n in fx.get_children():
		if n is GPUParticles3D and (n as GPUParticles3D).one_shot:
			continue        # the shared pool
		left.append("%s:%s" % [n.get_class(), n.name])
	check(left.is_empty(), "nothing left behind: %s" % str(left.slice(0, 12)))
	check(fx._follows.is_empty() and fx._anims.is_empty(), "no followers (%d) or animations (%d) left" % [fx._follows.size(), fx._anims.size()])
	check((kit._preps as Dictionary).is_empty() and (kit._jumps as Dictionary).is_empty(), "the kit holds nothing")
	_free(fx, views)


## ---- helpers --------------------------------------------------------------------------------------

## The projectile launches of fighter 0's pool move (its other effects, such as a recoil, aside).
func _launches(sim: MatchSim, pool: String) -> Array:
	return pool_events(sim, "effect", pool).filter(func(e: Dictionary) -> bool: return str(e["effect"]) == "projectile")


## Steps exactly `n` simulation ticks.
func _ticks(sim: MatchSim, n: int) -> void:
	await step_sim(sim, (float(maxi(n, 0)) + 0.5) / Engine.physics_ticks_per_second)


## Jitters (Overload) facing a standing dev_biped `gap` metres ahead and a second one at `second`
## (x, z), each on its own team (a three-way brawl).
func _trio(gap: float, second: Vector2) -> MatchSim:
	var arena := ArenaDef.from_dict({"id": "t", "base": "octagon", "radius": 7.0,
		"spawns": [[0, -gap * 0.5, 0], [0, gap * 0.5, 180], [second.x, second.y, 180]]})
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	sim.setup({"arena": arena, "rules": {"rounds": 1, "round_time": 0, "intro_time": 0.2, "combat": "moves"}, "seed": 7, "fighters": [
		{"creature": Content.creature("f_jitters"), "team": 0, "source": null, "loadout": OVERLOAD},
		{"creature": Content.creature(FOE), "team": 1, "source": null},
		{"creature": Content.creature(FOE), "team": 2, "source": null}]})
	return sim


## Jitters with one move drilled to a style (its patch applied to the creature data, as a run does).
func _drilled(id: String, style: String) -> CreatureDef:
	var d: Dictionary = Content.creature_entry("f_jitters").duplicate(true)
	var pm: PoolMove = Content.creature("f_jitters").pool[id]
	ContentPatch.apply_all(d, (pm.styles[style] as Dictionary)["patch"])
	return CreatureDef.from_dict(d, Callable(), "test")


## MovesKitCase.duel for a drilled Jitters.
func _duel_drilled(c: CreatureDef, loadout: Array, gap: float) -> MatchSim:
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
			"hidden": false, "charge": -1.0, "out": false}
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


func _move_start(pool: String) -> Dictionary:
	return {"type": "move_start", "fighter": 0, "slot": "mv." + pool, "id": "f_jitters.mv." + pool, "pool": pool, "cat": ""}


## An effect event of fighter 0 as EffectsSystem.fire builds it.
func _effect(vfx: String, effect: String, extra := {}) -> Dictionary:
	var ev := {"type": "effect", "fighter": 0, "effect": effect, "pos": Vector3(0, 0, 1.3), "element": "static", "vfx": vfx,
		"radius": 0.0, "shape": "circle", "yaw": 0.0, "move": "", "pool": "x"}
	ev.merge(extra, true)
	return ev


## A hit of fighter 0 on fighter 1 by one of its pool moves.
func _hit(pool: String, move: String, blocked: bool) -> Dictionary:
	return {"type": "hit", "fighter": 0, "target": 1, "damage": 5.0, "point": Vector3(2, 1, 0), "normal": Vector3(0, 0, -1), "blocked": blocked,
		"parried": false, "element": "static", "move": move, "pool": pool, "cat": "projectile", "counter": false}


## The radius a field look currently draws (its floor footprint's).
func _footprint_radius(root: Node3D) -> float:
	for n in root.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).material_override is ShaderMaterial:
			var m := (n as MeshInstance3D).material_override as ShaderMaterial
			if m.shader == FxKit.shader("fx_area"):
				return float(m.get_shader_parameter("radius"))
	return 0.0
