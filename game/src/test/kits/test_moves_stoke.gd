extends MovesKitCase
## Stoke's v0.9.18 move pool (docs/kits/f_stoke.md, docs/design/MOVESET_COMBAT.md §4): every move
## does what its description says, in Movesets, against a standing Dredge.

const FURNACE := ["ember_jab", "flamethrower", "steam_vent", "stoke_the_fire"]
const BRAWLER := ["ember_jab", "furnace_haymaker", "flare_rush", "cinder_shot"]


func test_pool_and_loadouts() -> void:
	var c := Content.creature("f_stoke")
	for id in ["ember_jab", "furnace_haymaker", "steam_vent", "stoke_the_fire", "flamethrower", "cinder_shot", "flare_rush", "fire_spin"]:
		check_pool_move("f_stoke", id)
	check_eq(c.resolve_loadout([]), FURNACE, "the default loadout is Furnace")
	check_eq((c.loadouts["brawler"] as Dictionary)["moves"], BRAWLER, "Brawler is the second build")
	var shared := FURNACE.filter(func(x) -> bool: return BRAWLER.has(x))
	check_eq(shared, ["ember_jab"], "the two builds share only the basic strike")


func test_flamethrower_pours_aims_and_burns() -> void:
	var sim := duel("f_stoke", FURNACE, "f_dredge", 2.2)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	var d := sim.fighters[1]
	var hp := d.health
	await use_slot(sim, 0, 1, 1.6, 0.8)          # Move 2 = Flamethrower, held 1.6 s
	var fx := pool_events(sim, "effect", "flamethrower").filter(func(e: Dictionary) -> bool: return str(e["effect"]) == "area")
	check(fx.size() >= 9, "the cone fires every 0.12 s while held (%d)" % fx.size())
	check(pool_damage(sim, "flamethrower") > 6.0 and d.health < hp, "it burns the fighter in front (%.1f)" % pool_damage(sim, "flamethrower"))
	check(d.statuses.has_element("scorch") or float(d.statuses.buildup.get("scorch", 0.0)) > 0.0, "and builds Sizzle")
	var patches := sim.effects.entities.filter(func(ent: Dictionary) -> bool: return str(ent.get("kind", "")) == "zone")
	check(not patches.is_empty(), "the floor it lingers on catches fire")
	# aiming: with the stick pushed to the side the flame sweeps (slowly) toward it
	var sim2 := duel("f_stoke", FURNACE, "f_dredge", 2.2)
	await step_sim(sim2, 0.4)
	var s2 := sim2.fighters[0]
	var yaw0 := s2.facing_yaw
	s2.input.press(FighterInput.HEAVY)
	s2.input.move = Vector3(1, 0, 0)
	await step_sim(sim2, 1.0)
	var swept := absf(MathX.wrap_angle(s2.facing_yaw - yaw0))
	check(swept > 0.6 and swept < 2.6, "the stick sweeps the flame at its turn rate (%.2f rad in ~0.7 s)" % swept)
	s2.input.set_held(FighterInput.HEAVY, false)
	s2.input.move = Vector3.ZERO
	await step_sim(sim2, 0.5)


func test_steam_vent_and_stoke_the_fire_carry_over() -> void:
	var sim := duel("f_stoke", FURNACE, "f_dredge", 1.6)
	await step_sim(sim, 0.4)
	await use_slot(sim, 0, 2, 0.0, 0.8)          # Move 3 = Steam Vent (ability1)
	var vent := sim.events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == "effect" and int(e["fighter"]) == 0 and str(e.get("vfx", "")) == "steam_vent")
	check(not vent.is_empty(), "Steam Vent fires its v0.9.17 cone")
	await use_slot(sim, 0, 3, 0.0, 0.5)          # Move 4 = Stoke the Fire
	check(sim.fighters[0].statuses.has("stoked"), "Stoke the Fire stokes")


func test_cinder_shot_lobs_bursts_and_leaves_fire() -> void:
	var sim := duel("f_stoke", BRAWLER, "f_dredge", 5.0)
	await step_sim(sim, 0.4)
	await use_slot(sim, 0, 3, 0.0, 0.32)         # Move 4 = Cinder Shot (thrown 0.22 s in)
	check(not pool_entities(sim, "cinder_shot", "projectile").is_empty(), "a coal is in the air")
	await step_sim(sim, 1.5)
	var burst := pool_events(sim, "effect", "cinder_shot").filter(func(e: Dictionary) -> bool: return str(e.get("vfx", "")) == "cinder_burst")
	check(not burst.is_empty(), "it bursts where it lands")
	var zones := sim.effects.entities.filter(func(ent: Dictionary) -> bool: return str(ent.get("kind", "")) == "zone")
	check(not zones.is_empty(), "and leaves burning ground")
	check(pool_damage(sim, "cinder_shot") > 0.0, "a fighter standing there is scorched (%.1f)" % pool_damage(sim, "cinder_shot"))


func test_flare_rush_lunges_explodes_and_recoils() -> void:
	var sim := duel("f_stoke", BRAWLER, "f_dredge", 3.0)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	var z0 := s.pos().z
	s.input.press(FighterInput.AB1)              # Move 3 = Flare Rush
	await step_sim(sim, 0.3)
	check(s.pos().z > z0 + 1.0, "a long lunge (%.2f m)" % (s.pos().z - z0))
	await step_sim(sim, 0.6)
	check(pool_damage(sim, "flare_rush") >= 6.0, "the punch lands and explodes (%.1f)" % pool_damage(sim, "flare_rush"))
	var hits := pool_events(sim, "hit", "flare_rush")
	check(not hits.is_empty() and str(hits[0].get("cat", "")) == "rush", "attributed to the rush")


func test_fire_spin_rings_and_follows() -> void:
	var sim := duel("f_stoke", ["ember_jab", "fire_spin"], "f_dredge", 1.3)
	await step_sim(sim, 0.4)
	var hp := sim.fighters[1].health
	await use_slot(sim, 0, 1, 0.0, 0.6)          # Move 2 = Fire Spin
	check(sim.fighters[1].health < hp, "the ring burns the fighter beside Stoke")
	var ring := sim.effects.entities.filter(func(ent: Dictionary) -> bool: return str(ent.get("kind", "")) == "zone" and bool((ent.get("e", {}) as Dictionary).get("follow_owner", false)))
	check(not ring.is_empty(), "a ring of fire follows Stoke")


func test_heavy_charges_into_the_haymaker() -> void:
	var sim := duel("f_stoke", BRAWLER, "f_dredge", 1.4)
	await step_sim(sim, 0.4)
	var s := sim.fighters[0]
	s.input.press(FighterInput.HEAVY)            # Move 2 = Furnace Haymaker
	await step_sim(sim, 1.3)
	check(s.move_charge > 0.5, "holding charges it (%.2f)" % s.move_charge)
	s.input.set_held(FighterInput.HEAVY, false)
	await step_sim(sim, 0.1)
	check_eq(s.move_slot, "heavy_charged", "release: the Furnace Haymaker")
	await step_sim(sim, 1.0)
