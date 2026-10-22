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
	for style in ["classic", "moves"]:
		for el in ["spectral", "grit"]:
			# An unobstructed control proves that a missing hit is cover, not a mis-aimed fixture.
			await _cover_shot(style, el, "none")
			await _cover_shot(style, el, "boulder")


func test_spectral_projectiles_pass_through_authored_arena_cover() -> void:
	for style in ["classic", "moves"]:
		for el in ["spectral", "grit"]:
			# Arena cover has two collision paths: splat proxies and ordinary solid props.
			await _cover_shot(style, el, "prop_crate")
			await _cover_shot(style, el, "prop_tire_stack")


func _cover_shot(style: String, element: String, cover: String) -> void:
	var sim := MatchSim.new()
	sim.running = false
	fresh_world().add_child(sim)
	var props := []
	if cover not in ["none", "boulder"]:
		props.append({"type": cover, "pos": [0, 0, -0.5]})
	var arena := ArenaDef.from_dict({"id": "trait_cover", "format": 2, "base": "gullet", "props": props})
	sim.setup({"arena": arena, "rules": {"combat": style, "rounds": 1, "round_time": 0, "intro_time": 0.2},
		"seed": 1, "fighters": [{"creature": Content.creature("f_varga"), "team": 0}, {"creature": Content.creature("f_knell"), "team": 1}]})
	if cover.begins_with("prop_"):
		var hazard := sim.hazards as ArenaHazards
		check(hazard != null and hazard.props.any(func(p: Dictionary) -> bool: return str(p["type"]) == cover and p["body"] != null), "the %s cover actually exists" % cover)
	await step_sim(sim, 0.4)
	var a := sim.fighters[0]
	var b := sim.fighters[1]
	a.rig.place(Vector3(0, 0, -3.0), 0.0)
	b.rig.place(Vector3(0, 0, 3.0), PI)
	# Rig.place sets the body pose; projectile emission uses the fighter's logical facing.
	a.facing_yaw = 0.0
	b.facing_yaw = PI
	if cover == "boulder":
		sim.effects.fire(a, {"type": "prop", "prop": "boulder", "at": "forward:2.5", "hp": 999})
	var hp := b.health
	sim.effects.fire(a, {"type": "projectile", "speed": 10.0, "radius": 0.25, "life": 1.5, "damage": 5.0,
		"element": element, "offset": [0, 0.6, 0.6]})
	await step_sim(sim, 0.9)
	var through := sim.events.any(func(e: Dictionary) -> bool: return str(e["type"]) == "hit" and int(e["fighter"]) == 0 and int(e["target"]) == 1)
	var should_hit := cover == "none" or element == "spectral"
	check_eq(through, should_hit, "%s %s projectile through %s: contact" % [style, element, cover])
	check_eq(b.health < hp, should_hit, "%s %s projectile through %s: damage" % [style, element, cover])
	# Each case owns its physics world; retire it before the next case instead of leaving all
	# sixteen worlds' idle ragdolls scheduled on Jolt's worker pool at once.
	sim.get_parent().queue_free()
	await get_tree().process_frame
