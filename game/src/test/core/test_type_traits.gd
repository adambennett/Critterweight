extends TestCase
## v0.9.18 type traits (docs/design/MOVESET_COMBAT.md §3.7): the three reactions that used to apply
## nothing (Bell Ringer, Grave Chill, Crack Guard) do what elements.json and the Compendium say, and
## spectral projectiles pass through cover props while others are stopped.


func _sim() -> MatchSim:
	return make_sim("", {"rounds": 1, "round_time": 0, "intro_time": 0.2}, [{"creature": "f_varga", "team": 0}, {"creature": "f_knell", "team": 1}])


func _reaction(id: String) -> Dictionary:
	for k in Elements.reactions:
		var r: Dictionary = Elements.reactions[k]
		if str(r.get("id", "")) == id:
			return r
	return {}


func test_bell_ringer_grave_chill_and_crack_guard_apply() -> void:
	var sim := _sim()
	await step_sim(sim, 0.4)
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	var hp := b.health
	sim.effects.trigger_reaction(_reaction("bell_ringer"), b, a, "scrap", "spectral")
	check(b.health < hp, "Bell Ringer deals its damage (%.1f -> %.1f)" % [hp, b.health])
	await step_sim(sim, 1.0)
	sim.effects.trigger_reaction(_reaction("grave_chill"), b, a, "spectral", "brine")
	check(b.statuses.has("grave_chill"), "Grave Chill slows (status applied)")
	var hp2 := b.health
	sim.effects.trigger_reaction(_reaction("crack_guard"), b, a, "scrap", "grit")
	check(b.health < hp2, "Crack Guard deals its damage")
	check(b.statuses.flag("no_guard"), "and opens the guard")


func test_spectral_projectiles_pass_through_cover() -> void:
	for el in ["spectral", "grit"]:
		var sim := _sim()
		await step_sim(sim, 0.4)
		var a := sim.fighters[0]
		a.rig.place(Vector3(0, a.rig.ground_y, -3.0), 0.0)
		sim.fighters[1].rig.place(Vector3(0, sim.fighters[1].rig.ground_y, 3.0), PI)
		# a rock between them, then a shot through it
		sim.effects.fire(a, {"type": "prop", "prop": "boulder", "at": "forward:2.5", "hp": 999})
		sim.effects.fire(a, {"type": "projectile", "speed": 10.0, "radius": 0.25, "life": 1.5, "damage": 5.0, "element": el, "offset": [0, 0.6, 0.6]})
		await step_sim(sim, 0.9)
		var through := sim.events.any(func(e: Dictionary) -> bool: return str(e["type"]) == "hit" and int(e["fighter"]) == 0 and int(e["target"]) == 1)
		if el == "spectral":
			check(through, "a spectral shot drifts through the rock")
		else:
			check(not through, "a %s shot is stopped by the rock" % el)
